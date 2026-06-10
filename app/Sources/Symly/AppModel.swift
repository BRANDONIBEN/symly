import SwiftUI
import AppKit
import LocalAuthentication
import SymlyCore

/// Where the app is in its flow, derived from the chosen volume + its setup state.
enum Phase: Equatable {
    case chooseVolume
    case setupFresh
    case setupAdopt(hasMedia: Bool)
    case blocked(String)
    case ready
}

/// A full in-app page shown over the panel (its own "screen").
enum AppPage: Equatable {
    case none
    case howItWorks
    case help
    case settings
}

@MainActor
final class AppModel: ObservableObject {
    @Published var volumes: [VolumeInfo] = []
    @Published var selectedVolume: VolumeInfo?
    /// The app-owned folder name on the drive (configurable in setup + settings).
    @Published var projectsFolderName = "Symly Media"
    @Published var setup: VolumeSetupState?

    @Published var projects: [Project] = []
    @Published var health: LinkHealth?
    @Published var chosenProject: String?
    @Published var showingNewProject = false
    @Published var justCompletedSetup = false
    @Published var page: AppPage = .none
    /// True until the user finishes the first-run How It Works screen. Persisted,
    /// so it only ever appears on the very first launch.
    @Published var showOnboarding: Bool = !UserDefaults.standard.bool(forKey: "hasOnboarded")

    @Published var errorMessage: String?

    /// Whether Symly protects the projects folder with a deny-delete ACL so it
    /// can't be renamed or deleted by accident in Finder. Default on; persisted.
    @Published var protectProjectsFolder: Bool =
        (UserDefaults.standard.object(forKey: "protectProjectsFolder") as? Bool) ?? true

    private let defaultProjectsFolder = "Symly Media"
    private let store = ProjectStore()
    private let engine = SymlinkEngine()
    private let validator = LinkValidator()
    private let folderWatcher = FolderWatcher()
    private let volumeWatcher = VolumeWatcher()
    private let folderLock = FolderLock()

    /// Cached volume-support probe results, keyed by volume path, so each drive is
    /// probed once per mount rather than on every focus or external change.
    private var supportByVolume: [String: VolumeSupport] = [:]

    // MARK: Derived

    /// Rebuilt from the selected volume + chosen folder name (cheap, value type).
    var workspace: Workspace? {
        guard let url = selectedVolume?.url else { return nil }
        return Workspace(root: url, projectsFolderName: projectsFolderName)
    }

    var phase: Phase {
        guard workspace != nil else { return .chooseVolume }
        switch setup {
        case .configured: return .ready
        case .fresh: return .setupFresh
        case .needsAdoption(let hasMedia): return .setupAdopt(hasMedia: hasMedia)
        case .blocked(let reason): return .blocked(reason)
        case .none: return .chooseVolume
        }
    }

    var volumeName: String { selectedVolume?.name ?? "" }
    var activeProject: String? { health?.activeProject }
    var driveConnected: Bool { health?.targetResolves ?? true }
    /// Whether the chosen volume is actually mounted (vs. the link target missing).
    var driveMounted: Bool {
        guard let url = selectedVolume?.url else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
    /// The drive is mounted, but the active link points at a folder that is no
    /// longer there (its target was renamed, moved, or deleted in Finder). The
    /// media is safe; the link just needs to be re-established. This is distinct
    /// from the drive being unplugged (driveMounted) and from the link being
    /// removed entirely (activeProject == nil, which the reconnect banner covers).
    var linkNeedsReestablishing: Bool {
        driveMounted && activeProject != nil && !driveConnected
    }
    var canConfirm: Bool {
        guard let chosen = chosenProject else { return false }
        return chosen != activeProject
    }

    var folderNameValid: Bool {
        let t = projectsFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty && !t.contains("/") && t != "." && t != ".."
    }

    // MARK: Lifecycle + live updates

    func start() {
        reloadVolumes()
        if let url = VolumeAccess.rememberedURL(in: volumes),
           let info = volumes.first(where: { $0.url == url }) {
            select(info)
        }
        volumeWatcher.start { [weak self] in
            Task { @MainActor in self?.externalChange() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.externalChange() }
        }
    }

    private func externalChange() {
        reloadVolumes()
        guard workspace != nil else { return }
        recomputeSetup()
    }

    func reloadVolumes() {
        volumes = Volumes.mounted()
        // Keep the active drive's snapshot current (free space, writability) while
        // it stays mounted; leave it untouched if it has gone away, so the
        // disconnect state still shows the last-known name.
        if let sel = selectedVolume,
           let fresh = volumes.first(where: { $0.url.path == sel.url.path }) {
            selectedVolume = fresh
        }
        // Drop cached probe results for drives that are no longer mounted, so a
        // reconnected (or reformatted) drive is re-probed fresh.
        let live = Set(volumes.map { $0.url.path })
        supportByVolume = supportByVolume.filter { live.contains($0.key) }
    }

    func select(_ info: VolumeInfo) {
        selectedVolume = info
        // A configured drive carries its folder name in the existing link.
        projectsFolderName = engine.configuredProjectsFolder(root: info.url) ?? defaultProjectsFolder
        VolumeAccess.remember(info.url)
        justCompletedSetup = false
        recomputeSetup()
    }

    private func recomputeSetup() {
        guard let ws = workspace else { setup = nil; return }
        // Gate on the real symlink probe first: a drive that can't hold a symlink
        // (exFAT/FAT, a share that drops links) or is read-only is routed to the
        // blocked screen instead of a setup flow that would fail.
        switch volumeSupport(ws) {
        case .noSymlinks:
            setup = .blocked(reason: "This drive can't store the symlink Symly needs. That is usually a network or shared volume whose server doesn't support links. A local drive works (APFS, Mac OS Extended, and exFAT all do), or pick a different one. Your media is not touched.")
        case .notWritable:
            setup = .blocked(reason: "This drive is read-only, so Symly can't create the link here. Make sure the drive is unlocked and you have write access, or pick a different drive.")
        case .ok:
            setup = engine.setupState(ws)
            if case .configured = setup { refreshReady() }
        }
    }

    /// Volume-support probe, cached per mount so it runs once per drive.
    private func volumeSupport(_ ws: Workspace) -> VolumeSupport {
        let key = ws.root.standardizedFileURL.path
        if let cached = supportByVolume[key] { return cached }
        let result = engine.checkVolumeSupport(ws)
        supportByVolume[key] = result
        return result
    }

    func changeDrive() {
        folderWatcher.stop()
        selectedVolume = nil
        projectsFolderName = defaultProjectsFolder
        setup = nil
        projects = []
        health = nil
        chosenProject = nil
        justCompletedSetup = false
        reloadVolumes()
    }

    // MARK: Fresh setup

    func completeFreshSetup(projectName: String) {
        guard let ws = workspace, folderNameValid else { return }
        do {
            try store.createProject(named: projectName, in: ws)
            try engine.apply(engine.planSwitch(to: projectName, in: ws))
            setup = engine.setupState(ws)
            justCompletedSetup = true
            refreshReady()
        } catch {
            errorMessage = friendly(error)
        }
    }

    // MARK: Adoption (existing media), applied directly, no dry-run readout

    func adopt(projectName: String) {
        guard let ws = workspace, folderNameValid else { return }
        do {
            try engine.apply(engine.planAdopt(as: projectName, in: ws))
            setup = engine.setupState(ws)
            justCompletedSetup = true
            refreshReady()
        } catch {
            errorMessage = friendly(error)
        }
    }

    // MARK: Ready / switching

    func refreshReady() {
        guard let ws = workspace else { return }
        projects = store.projects(in: ws)
        health = validator.health(of: ws)
        chosenProject = health?.activeProject
        folderWatcher.watch(ws.projectsRoot) { [weak self] in
            Task { @MainActor in self?.projectsChanged() }
        }
        ensureProtection()
    }

    private func projectsChanged() {
        guard let ws = workspace else { return }
        projects = store.projects(in: ws)
        health = validator.health(of: ws)
    }

    func dismissSetupDone() { justCompletedSetup = false }

    /// Finish the first-run How It Works screen. It is never shown again.
    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasOnboarded")
        showOnboarding = false
    }

    @discardableResult
    func createProject(named name: String) -> Bool {
        guard let ws = workspace else { return false }
        do {
            let project = try store.createProject(named: name, in: ws)
            refreshReady()
            chosenProject = project.name
            return true
        } catch {
            errorMessage = friendly(error)
            return false
        }
    }

    /// Repoint the live link to the chosen project. Applied directly: nothing is
    /// copied or deleted, so there is nothing to pre-audit.
    func switchToChosen() {
        guard let ws = workspace, let chosen = chosenProject, chosen != activeProject else { return }
        do {
            try engine.apply(engine.planSwitch(to: chosen, in: ws))
            refreshReady()
        } catch {
            errorMessage = friendly(error)
        }
    }

    /// Open the active project's media folder in Finder (the symlink shortcut).
    func openMediaFolder() {
        guard let ws = workspace else { return }
        let target: URL
        if let active = activeProject,
           FileManager.default.fileExists(atPath: ws.projectMXF(active).path) {
            target = ws.projectMXF(active)
        } else {
            target = ws.projectsRoot
        }
        NSWorkspace.shared.open(target)
    }

    // MARK: Rename projects folder, applied directly

    func renameProjectsFolder(to newName: String) {
        guard let ws = workspace else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/"), trimmed != "." , trimmed != "..",
              trimmed != projectsFolderName else { return }
        do {
            // Build (and validate) the plan first, then lift the lock so the
            // rename can proceed; refreshReady re-applies it on the new folder.
            let plan = try engine.planRenameProjectsFolder(in: ws, to: trimmed)
            folderLock.unlock(ws.projectsRoot)
            try engine.apply(plan)
            projectsFolderName = trimmed
            refreshReady()
        } catch {
            ensureProtection()   // restore the lock if the rename did not happen
            errorMessage = friendly(error)
        }
    }

    // MARK: Folder protection (deny-delete ACL)

    /// Turn the projects-folder lock on or off, persist the choice, and apply it
    /// immediately. On = the folder can't be renamed or deleted in Finder.
    func setProtection(_ on: Bool) {
        protectProjectsFolder = on
        UserDefaults.standard.set(on, forKey: "protectProjectsFolder")
        ensureProtection()
    }

    /// Whether the active drive's filesystem supports the folder lock. exFAT and
    /// FAT have no ACLs, so the lock can't apply there; symlinks still work fine.
    var folderLockAvailable: Bool { selectedVolume?.supportsFolderLock ?? true }

    /// Make the on-disk lock match the current preference, where the drive
    /// supports it. Locking is idempotent; contents stay fully writable either way.
    private func ensureProtection() {
        guard let ws = workspace, folderLockAvailable,
              FileManager.default.fileExists(atPath: ws.projectsRoot.path) else { return }
        if protectProjectsFolder { folderLock.lock(ws.projectsRoot) }
        else { folderLock.unlock(ws.projectsRoot) }
    }

    // MARK: Uninstall

    /// Ask the user to authenticate, then remove Symly cleanly: lift the lock and
    /// remove the link on the active drive (media untouched), clear preferences,
    /// and move the app to the Trash. Only the active drive is cleaned; offline
    /// drives keep their (harmless) link until reconnected.
    func uninstall() {
        let ctx = LAContext()
        ctx.localizedCancelTitle = "Cancel"
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            errorMessage = "Couldn't verify it's you, so nothing was removed."
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication,
                           localizedReason: "uninstall Symly and remove its link from this drive") { ok, _ in
            guard ok else { return }
            Task { @MainActor in self.performUninstall() }
        }
    }

    private func performUninstall() {
        // 1. Clean the active drive: lift the lock, remove the symlink. Media is
        //    never touched (removeSymlink is guarded to symlinks only).
        if let ws = workspace {
            folderLock.unlock(ws.projectsRoot)
            if let plan = engine.planRemoveLink(in: ws) { try? engine.apply(plan) }
        }
        // 2. Clear ALL of Symly's preferences (the onboarding flag, the protection
        //    setting, anything else) plus the remembered-drive bookmark, so a later
        //    reinstall starts truly fresh and the first-run screen shows again.
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        VolumeAccess.forget()
        // 3. Move the app to the Trash, then quit.
        NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    // MARK: Messages

    private func friendly(_ error: Error) -> String {
        if let pe = error as? ProjectError {
            switch pe {
            case .invalidName(let n): return "\"\(n)\" is not a valid media folder name."
            case .alreadyExists(let n): return "A media folder named \"\(n)\" already exists. Pick another name."
            }
        }
        if let se = error as? SafetyError {
            switch se {
            case .wouldOverwriteRealDirectory:
                return "There is real media at Avid MediaFiles/MXF. It needs to be adopted into a media folder first. Nothing will be deleted."
            case .refusedNonSymlinkRemoval:
                return "Refused: that is not a symlink, so it was left alone. Your media is safe."
            case .targetDoesNotExist:
                return "Couldn't find that media folder on the drive. If the drive was disconnected, reconnect it and try again."
            case .crossVolumeMove:
                return "That would cross drives. The media folder has to live on the same drive as the media."
            case .protectedPath:
                return "Refused: that is a protected system location."
            case .notADirectory:
                return "There is an unexpected file where the media folder should be."
            case .destinationExists:
                return "A folder already exists at the destination. Pick another media folder name."
            case .linkReplaceFailed:
                return "Couldn't update the link, the drive may have been disconnected. The previous link was left in place; reconnect the drive and try again."
            }
        }
        return error.localizedDescription
    }
}
