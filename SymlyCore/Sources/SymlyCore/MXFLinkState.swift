import Foundation

/// What currently sits at `Avid MediaFiles/MXF`.
public enum MXFLinkState: Equatable, Sendable {
    /// Nothing there yet (fresh drive, or the link was removed).
    case missing
    /// A real folder of media that has not been adopted into a project. The
    /// engine refuses to overwrite this; it must be adopted (relocated) first.
    case realDirectory
    /// An unexpected real file sits at the path.
    case file
    /// A symlink, with the path it points at (as stored on the link).
    case symlink(target: URL)
}
