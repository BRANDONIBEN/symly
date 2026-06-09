import Foundation

/// A working location on a volume: the rigid Avid path plus the app-owned
/// project folders that live beside it. All paths are derived; this type holds
/// no state and never touches the filesystem.
public struct Workspace: Equatable, Sendable {
    /// The volume root (or a working subfolder of it) the user granted.
    public let root: URL

    /// The app-owned folder on the drive that holds each project's media.
    /// Configurable so editors can name it to taste; the default is descriptive.
    public let projectsFolderName: String

    public init(root: URL, projectsFolderName: String = "Symly Media") {
        self.root = root
        self.projectsFolderName = projectsFolderName
    }

    /// `<root>/Avid MediaFiles`: Avid's own folder.
    public var avidMediaFiles: URL {
        root.appending(path: "Avid MediaFiles")
    }

    /// `<root>/Avid MediaFiles/MXF`: the rigid location Avid reads/writes.
    /// In this system it is a symlink the app repoints per project.
    public var mxfLink: URL {
        avidMediaFiles.appending(path: "MXF")
    }

    /// `<root>/Symly Media`: the app-owned root holding each
    /// project's real media tree.
    public var projectsRoot: URL {
        root.appending(path: projectsFolderName)
    }

    /// The real `MXF` directory for a named project.
    public func projectMXF(_ name: String) -> URL {
        projectsRoot.appending(path: name).appending(path: "MXF")
    }

    /// If `target` resolves to `<projectsRoot>/<name>/MXF`, return `<name>`.
    /// Matches by path component, ignoring case and Unicode normal form, so a
    /// case-insensitive drive or an accented volume name (precomposed vs
    /// decomposed) still resolves the active project's name correctly.
    public func projectName(forResolvedTarget target: URL) -> String? {
        let root = projectsRoot.standardizedFileURL.pathComponents
        let comps = target.standardizedFileURL.pathComponents
        guard comps.count > root.count else { return nil }
        for i in root.indices where !Workspace.sameComponent(root[i], comps[i]) {
            return nil
        }
        return comps[root.count]
    }

    /// Two path components are "the same" if they match ignoring case and Unicode
    /// normal form (precomposed vs decomposed), matching how macOS volumes
    /// (APFS/HFS+, case-insensitive by default) actually compare names.
    static func sameComponent(_ a: String, _ b: String) -> Bool {
        a.precomposedStringWithCanonicalMapping
            .caseInsensitiveCompare(b.precomposedStringWithCanonicalMapping) == .orderedSame
    }
}
