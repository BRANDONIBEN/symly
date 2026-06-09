import Foundation

/// Pure validators that enforce the "never delete media" invariants. No
/// mutation happens here; the guard only reads the filesystem to decide whether
/// an operation is allowed. `SymlinkEngine` cannot act without passing these.
public struct SafetyGuard: Sendable {

    public init() {}

    /// True only if the path is itself a symlink. Uses `lstat`, which never
    /// follows the link, so a symlink pointing at a directory still reports as
    /// a symlink (not a directory).
    public func isSymlink(_ url: URL) -> Bool {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return false }
        return (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFLNK)
    }

    /// True if anything (file, directory, or symlink) exists at the path,
    /// without following symlinks (`lstat`). A dangling symlink still counts as
    /// existing, which is what we want when deciding whether a slot is occupied.
    public func exists(_ url: URL) -> Bool {
        var st = stat()
        return lstat(url.path, &st) == 0
    }

    /// I1: refuse to remove anything that is not a symlink.
    public func assertRemovableSymlink(_ url: URL) throws {
        guard isSymlink(url) else {
            throw SafetyError.refusedNonSymlinkRemoval(url)
        }
    }

    /// Refuse to touch obviously protected system locations.
    public func assertNotProtected(_ url: URL) throws {
        let p = url.standardizedFileURL.path
        let protected: Set<String> = ["", "/", "/Volumes", "/System", "/Users", "/Library"]
        if protected.contains(p) {
            throw SafetyError.protectedPath(url)
        }
    }

    /// I7: a move must stay on one volume so it is a metadata rename, never an
    /// interruptible byte copy. Compares the device id of each path (walking up
    /// to the nearest existing ancestor for paths that don't exist yet).
    public func assertSameVolume(_ a: URL, _ b: URL) throws {
        guard let da = deviceID(a), let db = deviceID(b), da == db else {
            throw SafetyError.crossVolumeMove(from: a, to: b)
        }
    }

    /// The device id of the volume a path lives on. For a path that doesn't
    /// exist yet, resolves against its nearest existing ancestor.
    public func deviceID(_ url: URL) -> dev_t? {
        let fm = FileManager.default
        var u = url.standardizedFileURL
        while !fm.fileExists(atPath: u.path) && u.path != "/" {
            u = u.deletingLastPathComponent()
        }
        var st = stat()
        guard stat(u.path, &st) == 0 else { return nil }
        return st.st_dev
    }
}
