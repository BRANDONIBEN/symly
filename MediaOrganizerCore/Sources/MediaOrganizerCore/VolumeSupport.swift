import Foundation

/// Whether a chosen volume can host the symlink Symly depends on. Checked once
/// when the user picks a drive, before any setup, so an unsupported drive is
/// turned away with a clear reason instead of failing with a raw syscall error
/// partway through setup.
public enum VolumeSupport: Equatable, Sendable {
    /// Symlinks create and read back correctly here. APFS, Mac OS Extended, and
    /// exFAT all qualify on macOS.
    case ok
    /// The filesystem cannot store a symlink, or silently fails to honor it (some
    /// SMB/NAS shares). exFAT/FAT are NOT in this bucket: they support symlinks on
    /// macOS (verified on real hardware); the probe confirms per drive.
    case noSymlinks
    /// The volume is mounted read-only, or the app lacks write permission.
    case notWritable
}
