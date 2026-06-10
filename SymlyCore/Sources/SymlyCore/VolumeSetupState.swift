import Foundation

/// What the app must do to a chosen volume before projects can be switched.
/// Drives the setup walkthrough.
public enum VolumeSetupState: Equatable, Sendable {
    /// No `Avid MediaFiles/MXF` on the volume yet. Create it fresh.
    case fresh
    /// `Avid MediaFiles/MXF` is already our symlink. The active project (if the
    /// link points into a known project) is provided.
    case configured(active: String?)
    /// A real `Avid MediaFiles/MXF` folder exists (Avid wrote there directly).
    /// It must be adopted: its media moved into a named project, then linked.
    /// `hasMedia` is false when that folder is empty (nothing to move).
    case needsAdoption(hasMedia: Bool)
    /// Something unexpected sits at the path (e.g. a file). Surface, do nothing.
    case blocked(reason: String)
}
