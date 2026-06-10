import Foundation

/// The only type in the system allowed to mutate the filesystem. It reads the
/// current state, builds a `LinkPlan`, and applies it, but every destructive
/// step is routed through `SafetyGuard` first, so it can only ever add or
/// remove symlinks and relocate (never copy or delete) real folders.
public struct SymlinkEngine: Sendable {
    private var fm: FileManager { .default }
    private let safety = SafetyGuard()

    public init() {}

    // MARK: Read

    /// What currently sits at `Avid MediaFiles/MXF`.
    public func currentState(_ ws: Workspace) -> MXFLinkState {
        let mxf = ws.mxfLink
        if safety.isSymlink(mxf) {
            return .symlink(target: resolvedTarget(ofLinkAt: mxf) ?? mxf)
        }
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: mxf.path, isDirectory: &isDir) {
            return isDir.boolValue ? .realDirectory : .file
        }
        return .missing
    }

    /// Which setup case a chosen volume is in. Drives the walkthrough.
    public func setupState(_ ws: Workspace) -> VolumeSetupState {
        switch currentState(ws) {
        case .missing:
            // No active link. But if this drive already holds projects (e.g. the
            // symlink was deleted), it is set up, not fresh: send the user to the
            // main panel to reconnect to one (active: nil) or add a new one.
            return hasExistingProjects(ws) ? .configured(active: nil) : .fresh
        case .symlink(let target):
            return .configured(active: ws.projectName(forResolvedTarget: target))
        case .realDirectory:
            return .needsAdoption(hasMedia: directoryHasEntries(ws.mxfLink))
        case .file:
            return .blocked(reason: "Avid MediaFiles/MXF is a file, not a folder.")
        }
    }

    private func directoryHasEntries(_ url: URL) -> Bool {
        // Skip hidden files (.DS_Store, .Spotlight, …) so a folder that holds
        // only macOS cruft reads as empty, consistent with hasExistingProjects.
        let items = (try? fm.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])) ?? []
        return !items.isEmpty
    }

    /// Whether the drive's projects folder already contains at least one project
    /// (a subdirectory). Used to tell "fresh drive" from "set up, link removed".
    private func hasExistingProjects(_ ws: Workspace) -> Bool {
        let entries = (try? fm.contentsOfDirectory(
            at: ws.projectsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])) ?? []
        return entries.contains { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    /// When the drive is already configured, the projects-folder name encoded in
    /// the existing MXF symlink target, so a configured drive re-derives its own
    /// folder name on relaunch (and across machines) with no extra storage.
    public func configuredProjectsFolder(root: URL) -> String? {
        let mxf = root.appending(path: "Avid MediaFiles").appending(path: "MXF")
        guard safety.isSymlink(mxf), let dest = resolvedTarget(ofLinkAt: mxf) else { return nil }
        let rootComps = root.standardizedFileURL.pathComponents
        let comps = dest.pathComponents
        guard comps.count > rootComps.count else { return nil }
        for i in rootComps.indices where !Workspace.sameComponent(rootComps[i], comps[i]) {
            return nil
        }
        return comps[rootComps.count]
    }

    // MARK: Plan

    /// Plan to make `project` the active one by repointing the MXF symlink.
    /// Throws rather than clobbering real media or pointing at a missing target.
    public func planSwitch(to project: String, in ws: Workspace) throws -> LinkPlan {
        let project = try validName(project)
        let mxf = ws.mxfLink
        let target = ws.projectMXF(project)
        let projectDir = ws.projectsRoot.appending(path: project)
        // The project folder itself must exist on the drive. If it is gone, the
        // drive is likely disconnected (or the project was removed elsewhere).
        guard fm.fileExists(atPath: projectDir.path) else {
            throw SafetyError.targetDoesNotExist(projectDir)
        }
        try safety.assertNotProtected(mxf)

        var ops: [LinkOperation] = []
        // A new or hand-made project may not have its MXF folder yet. Create it
        // (empty) so Avid has somewhere to write. This never deletes anything.
        if !fm.fileExists(atPath: target.path) {
            ops.append(.ensureDirectory(target))
        }
        switch currentState(ws) {
        case .symlink, .missing:
            // Atomic repoint: the rigid path is always either the old link or
            // the new one, never momentarily absent, even if the drive is
            // pulled mid-switch.
            ops.append(.repointSymlink(at: mxf, target: target))
        case .realDirectory:
            throw SafetyError.wouldOverwriteRealDirectory(mxf)
        case .file:
            throw SafetyError.notADirectory(mxf)
        }
        return LinkPlan(operations: ops, summary: "Point MXF → \(project)")
    }

    /// Plan to adopt a pre-existing real `Avid MediaFiles/MXF` into a project:
    /// relocate it (same-volume rename) then symlink the rigid path to it.
    public func planAdopt(as project: String, in ws: Workspace) throws -> LinkPlan {
        let project = try validName(project)
        let mxf = ws.mxfLink
        let dest = ws.projectMXF(project)
        guard case .realDirectory = currentState(ws) else {
            throw SafetyError.notADirectory(mxf)
        }
        guard !fm.fileExists(atPath: dest.path) else {
            throw SafetyError.destinationExists(dest)
        }
        try safety.assertNotProtected(mxf)
        try safety.assertSameVolume(mxf, ws.projectsRoot)
        return LinkPlan(
            operations: [
                .relocateRealDirectory(from: mxf, to: dest),
                .createSymlink(at: mxf, target: dest),
            ],
            summary: "Adopt existing MXF → \(project)"
        )
    }

    /// Rename the app-owned projects folder on the drive and repoint the active
    /// link to follow it. The folder is moved by a same-volume rename (metadata
    /// only: no media copied or deleted), then the link is re-pointed.
    public func planRenameProjectsFolder(in ws: Workspace, to newName: String) throws -> LinkPlan {
        let trimmed = try validName(newName)
        let oldRoot = ws.projectsRoot
        let newRoot = ws.root.appending(path: trimmed)
        guard oldRoot.standardizedFileURL.path != newRoot.standardizedFileURL.path else {
            return LinkPlan(operations: [], summary: "No change")
        }
        guard fm.fileExists(atPath: oldRoot.path) else {
            throw SafetyError.targetDoesNotExist(oldRoot)
        }
        guard !fm.fileExists(atPath: newRoot.path) else {
            throw SafetyError.destinationExists(newRoot)
        }
        try safety.assertNotProtected(oldRoot)
        try safety.assertSameVolume(oldRoot, ws.root)

        var ops: [LinkOperation] = []
        var relink: URL?
        let mxf = ws.mxfLink
        if case let .symlink(target) = currentState(ws),
           let active = ws.projectName(forResolvedTarget: target) {
            ops.append(.removeSymlink(mxf))
            relink = newRoot.appending(path: active).appending(path: "MXF")
        }
        ops.append(.relocateRealDirectory(from: oldRoot, to: newRoot))
        if let relink { ops.append(.createSymlink(at: mxf, target: relink)) }
        return LinkPlan(operations: ops, summary: "Rename projects folder to \(trimmed)")
    }

    /// Plan to remove Symly's link from a drive (used by uninstall). Returns nil
    /// when there is no symlink to remove, so real media is never touched.
    public func planRemoveLink(in ws: Workspace) -> LinkPlan? {
        guard case .symlink = currentState(ws) else { return nil }
        return LinkPlan(operations: [.removeSymlink(ws.mxfLink)], summary: "Remove Symly link")
    }

    // MARK: Apply

    /// Execute a plan. Each step re-validates through the guard (defense in
    /// depth), so even a hand-built plan cannot delete real media.
    public func apply(_ plan: LinkPlan) throws {
        for op in plan.operations {
            switch op {
            case let .ensureDirectory(url):
                try fm.createDirectory(at: url, withIntermediateDirectories: true)

            case let .removeSymlink(url):
                try safety.assertRemovableSymlink(url)   // I1: symlinks only
                try fm.removeItem(at: url)

            case let .relocateRealDirectory(from, to):
                guard !fm.fileExists(atPath: to.path) else {
                    throw SafetyError.destinationExists(to)   // I3: never overwrite
                }
                try safety.assertSameVolume(from, to)         // I7: rename, not copy
                try fm.createDirectory(at: to.deletingLastPathComponent(),
                                       withIntermediateDirectories: true)
                try fm.moveItem(at: from, to: to)

            case let .createSymlink(at, target):
                try fm.createDirectory(at: at.deletingLastPathComponent(),
                                       withIntermediateDirectories: true)
                try fm.createSymbolicLink(atPath: at.path,
                                          withDestinationPath: relativeTarget(for: at, to: target))

            case let .repointSymlink(at, target):
                try repoint(at: at, to: target)
            }
        }
    }

    // MARK: Volume support

    /// Whether the chosen volume can host the symlink Symly depends on. Run once
    /// when a drive is picked: some volumes (a few SMB/NAS shares) silently fail to
    /// store a symlink, and a read-only mount can't be written, so we turn the
    /// drive away with a clear reason instead of failing partway through setup.
    /// exFAT and FAT pass here: they support symlinks on macOS. The probe creates
    /// and removes a single hidden link; it never touches the user's media.
    public func checkVolumeSupport(_ ws: Workspace) -> VolumeSupport {
        let dir = fm.fileExists(atPath: ws.avidMediaFiles.path) ? ws.avidMediaFiles : ws.root
        guard fm.isWritableFile(atPath: dir.path) else { return .notWritable }
        let probe = dir.appending(path: ".symly-support-probe-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: probe) }
        do {
            try fm.createSymbolicLink(atPath: probe.path, withDestinationPath: "symly-probe")
            return (try? fm.destinationOfSymbolicLink(atPath: probe.path)) == "symly-probe"
                ? .ok : .noSymlinks
        } catch {
            return .noSymlinks
        }
    }

    // MARK: Link helpers

    /// Atomically replace whatever symlink is at `at` with one pointing at
    /// `target`: write a temp link beside it, then `rename` it over the old one.
    /// Renaming a symlink is atomic and, on macOS, refuses to clobber a real
    /// directory, so media is structurally safe. If a real file or folder somehow
    /// sits at the path, it refuses outright (defense in depth, mirroring I1).
    private func repoint(at: URL, to target: URL) throws {
        if safety.exists(at) && !safety.isSymlink(at) {
            var isDir: ObjCBool = false
            fm.fileExists(atPath: at.path, isDirectory: &isDir)
            throw isDir.boolValue
                ? SafetyError.wouldOverwriteRealDirectory(at)
                : SafetyError.notADirectory(at)
        }
        try fm.createDirectory(at: at.deletingLastPathComponent(),
                               withIntermediateDirectories: true)
        let tmp = at.deletingLastPathComponent()
            .appending(path: ".symly-link-\(UUID().uuidString)")
        try fm.createSymbolicLink(atPath: tmp.path,
                                  withDestinationPath: relativeTarget(for: at, to: target))
        if rename(tmp.path, at.path) != 0 {
            try? fm.removeItem(at: tmp)
            throw SafetyError.linkReplaceFailed(at)
        }
    }

    /// The destination of the symlink at `linkURL`, resolved to an absolute URL.
    /// Symly stores link targets as drive-relative paths so they survive the
    /// drive remounting at a different location; this turns that back into an
    /// absolute path for state checks. Absolute legacy targets pass through.
    private func resolvedTarget(ofLinkAt linkURL: URL) -> URL? {
        guard let raw = try? fm.destinationOfSymbolicLink(atPath: linkURL.path) else { return nil }
        if raw.hasPrefix("/") { return URL(fileURLWithPath: raw).standardizedFileURL }
        return URL(fileURLWithPath: raw, relativeTo: linkURL.deletingLastPathComponent())
            .standardizedFileURL
    }

    /// `target` expressed relative to the directory that holds `linkURL`, so the
    /// stored link contains no volume mount point and keeps resolving after the
    /// drive remounts at a different path. Both paths live on the same drive by
    /// construction, so this is always a short `../…` hop.
    private func relativeTarget(for linkURL: URL, to target: URL) -> String {
        let base = linkURL.deletingLastPathComponent().standardizedFileURL.pathComponents
        let dest = target.standardizedFileURL.pathComponents
        var i = 0
        while i < base.count && i < dest.count && base[i] == dest[i] { i += 1 }
        let comps = Array(repeating: "..", count: base.count - i) + dest[i...]
        return comps.isEmpty ? "." : comps.joined(separator: "/")
    }

    /// Trim and validate a name that will become a single path component on the
    /// drive. Rejects empty, path separators, and the `.`/`..` traversal names,
    /// so a project or folder name can never escape its parent.
    private func validName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/"), trimmed != ".", trimmed != ".." else {
            throw ProjectError.invalidName(name)
        }
        return trimmed
    }
}
