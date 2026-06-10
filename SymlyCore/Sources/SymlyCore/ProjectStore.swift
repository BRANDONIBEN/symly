import Foundation

/// A named project: a real folder under `Symly Media` that holds its
/// own `MXF` media tree (with its own Avid database pair per numbered subfolder).
public struct Project: Equatable, Sendable, Identifiable {
    public let name: String
    public let mxfURL: URL
    public var id: String { name }

    public init(name: String, mxfURL: URL) {
        self.name = name
        self.mxfURL = mxfURL
    }
}

public enum ProjectError: Error, Equatable, Sendable {
    case invalidName(String)
    case alreadyExists(String)
}

/// Manages the app-owned project folders. The directories on disk are the
/// source of truth; this type just lists and creates them. It never deletes a
/// project (removing real media is out of scope by design).
public struct ProjectStore: Sendable {
    private var fm: FileManager { .default }

    public init() {}

    /// Every immediate subfolder of `Symly Media`, sorted by name.
    public func projects(in ws: Workspace) -> [Project] {
        guard let entries = try? fm.contentsOfDirectory(
            at: ws.projectsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries.compactMap { dir -> Project? in
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
                return nil
            }
            return Project(name: dir.lastPathComponent, mxfURL: dir.appending(path: "MXF"))
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Create a new, empty project (its `MXF` folder). Avid fills it in later.
    @discardableResult
    public func createProject(named name: String, in ws: Workspace) throws -> Project {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("/"),
              trimmed != ".", trimmed != ".."
        else { throw ProjectError.invalidName(name) }

        let projectDir = ws.projectsRoot.appending(path: trimmed)
        guard !fm.fileExists(atPath: projectDir.path) else {
            throw ProjectError.alreadyExists(trimmed)
        }
        let mxf = ws.projectMXF(trimmed)
        try fm.createDirectory(at: mxf, withIntermediateDirectories: true)
        return Project(name: trimmed, mxfURL: mxf)
    }
}
