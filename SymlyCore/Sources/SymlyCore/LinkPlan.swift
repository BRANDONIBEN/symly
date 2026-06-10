import Foundation

/// A single filesystem operation the engine may perform. The set is
/// deliberately tiny: there is no "delete folder" or "copy" operation, so the
/// engine structurally cannot destroy media.
public enum LinkOperation: Equatable, Sendable {
    /// Move a real directory to a new home (used only for adoption). Implemented
    /// as a same-volume rename: atomic, no bytes copied, nothing deleted.
    case relocateRealDirectory(from: URL, to: URL)
    /// Create an app-owned directory if it does not exist (e.g. a new project's
    /// empty MXF folder). Never deletes; createDirectory is a no-op if present.
    case ensureDirectory(URL)
    /// Remove a symlink (guarded: the target must be a symlink).
    case removeSymlink(URL)
    /// Create a symlink at a path pointing to a target.
    case createSymlink(at: URL, target: URL)
    /// Atomically repoint the link at `at` to `target`: a temp link is written
    /// beside it and renamed over the old one, so the rigid path is never
    /// momentarily without a link. Refuses to replace a real directory.
    case repointSymlink(at: URL, target: URL)
}

/// An ordered, inspectable description of exactly what will happen. The dry-run
/// preview in the UI renders this same value the executor consumes, so the
/// preview can never disagree with the action.
public struct LinkPlan: Equatable, Sendable {
    public let operations: [LinkOperation]
    public let summary: String

    public init(operations: [LinkOperation], summary: String) {
        self.operations = operations
        self.summary = summary
    }

    /// Human-readable lines for the preview sheet.
    public var previewLines: [String] {
        operations.map { op in
            switch op {
            case let .relocateRealDirectory(from, to):
                return "Move (rename, no copy): \(from.path) → \(to.path)"
            case let .ensureDirectory(url):
                return "Create empty media folder: \(url.path)"
            case let .removeSymlink(url):
                return "Remove symlink: \(url.path)"
            case let .createSymlink(at, target):
                return "Link: \(at.path) → \(target.path)"
            case let .repointSymlink(at, target):
                return "Repoint link (atomic): \(at.path) → \(target.path)"
            }
        }
    }
}
