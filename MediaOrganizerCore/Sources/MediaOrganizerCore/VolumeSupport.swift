import Foundation

/// Whether a chosen volume can host the symlink Symly depends on. Checked once
/// when the user picks a drive, before any setup, so an unsupported drive is
/// turned away with a clear reason instead of failing with a raw syscall error
/// partway through setup.
public enum VolumeSupport: Equatable, Sendable {
    /// Symlinks create and read back correctly here (APFS, Mac OS Extended).
    case ok
    /// The filesystem cannot store symlinks (exFAT, FAT32/MS-DOS) or silently
    /// fails to honor them (some SMB/NAS shares). Symly cannot run here.
    case noSymlinks
    /// The volume is mounted read-only, or the app lacks write permission.
    case notWritable
}
