import Foundation

/// Every way the engine can refuse to act. The guard fails closed: when in
/// doubt, it throws rather than touching the filesystem.
public enum SafetyError: Error, Equatable, Sendable {
    /// Asked to remove something that is not a symlink. The core invariant:
    /// the app only ever removes symlinks, never real media.
    case refusedNonSymlinkRemoval(URL)
    /// A real media folder sits at the rigid path; repointing would clobber it.
    /// It must be adopted (relocated) first.
    case wouldOverwriteRealDirectory(URL)
    /// The project's MXF target does not exist.
    case targetDoesNotExist(URL)
    /// A move would cross volumes (i.e. copy bytes); blocked so media is only
    /// ever relocated by an instant same-volume rename.
    case crossVolumeMove(from: URL, to: URL)
    /// A protected system path (/, /Volumes, /System, …) was targeted.
    case protectedPath(URL)
    /// Expected a directory, found something else.
    case notADirectory(URL)
    /// A relocation destination already exists; refusing to merge/overwrite.
    case destinationExists(URL)
    /// An atomic link replacement failed at the syscall level (e.g. the drive
    /// went away mid-rename). The existing link is left untouched.
    case linkReplaceFailed(URL)
}
