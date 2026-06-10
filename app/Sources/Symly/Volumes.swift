import Foundation

/// A mounted volume the user can pick from (no Finder dialog).
struct VolumeInfo: Identifiable, Equatable {
    let url: URL
    let name: String
    let isRemovable: Bool
    let isInternal: Bool
    /// Lowercased filesystem type from statfs (e.g. "apfs", "hfs", "exfat",
    /// "msdos", "smbfs"). Read-only, cheap: used only for an inline hint in the
    /// picker. The authoritative check is engine.checkVolumeSupport on select.
    let fsType: String
    let isWritable: Bool
    /// Space the OS reports as available for "important usage" (matches what Finder
    /// shows as Available). nil if the volume didn't report it.
    let freeBytes: Int64?
    var id: String { url.path }

    /// A cheap, read-only guess at whether Symly can use this drive, shown inline
    /// in the picker. A read-only mount cannot be written; network shares vary by
    /// server (selectable, but flagged). Everything else, including exFAT/FAT
    /// (which DO support symlinks on macOS, verified on real hardware), is treated
    /// as usable and confirmed by the real probe when selected.
    enum Eligibility: Equatable {
        case eligible
        case network
        case readOnly
        case unsupported(String)
    }

    var eligibility: Eligibility {
        if !isWritable { return .readOnly }
        switch fsType {
        case "smbfs", "nfs", "afpfs", "webdav", "ftp":
            return .network
        default:
            // APFS, Mac OS Extended, and exFAT/FAT all support symlinks on macOS,
            // so we never pre-block by filesystem name. The on-select probe is the
            // real gate and catches anything that genuinely can't hold a link.
            return .eligible
        }
    }

    /// Display order: usable drives first, dead ends last.
    var eligibilityRank: Int {
        switch eligibility {
        case .eligible: return 0
        case .network: return 1
        case .readOnly: return 2
        case .unsupported: return 3
        }
    }

    /// Whether the row can be chosen. Read-only drives can't be (nor any drive the
    /// real probe later rejects), so the picker shows those disabled.
    var isSelectable: Bool {
        switch eligibility {
        case .unsupported, .readOnly: return false
        case .eligible, .network: return true
        }
    }

    /// exFAT and FAT have no ACLs, so the projects-folder lock can't apply there.
    /// Symlinks work fine; only the optional deny-delete lock is unavailable.
    var supportsFolderLock: Bool {
        !["exfat", "msdos", "vfat", "fat", "fat32", "ms-dos"].contains(fsType)
    }

    /// Human-readable free space, e.g. "467 GB free". nil when the volume didn't
    /// report a usable figure, so the UI can simply omit it.
    var freeSpaceLabel: String? {
        guard let freeBytes, freeBytes > 0 else { return nil }
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useGB, .useTB]
        return f.string(fromByteCount: freeBytes) + " free"
    }
}

enum Volumes {
    static func mounted() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeIsBrowsableKey, .volumeIsRemovableKey,
            .volumeIsInternalKey, .volumeIsEjectableKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []

        return urls.compactMap { url -> VolumeInfo? in
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  v.volumeIsBrowsable == true else { return nil }
            // Exclude the startup volume mounted at "/". On modern macOS the boot
            // disk is a sealed, read-only System volume; you cannot create
            // "/Avid MediaFiles/MXF" at its root (it is not a firmlinked path), so
            // Avid managed media can't live there the way it does on other volumes.
            // Pro Avid media lives on a dedicated external/secondary drive anyway.
            guard url.standardizedFileURL.path != "/" else { return nil }
            let fs = filesystem(of: url)
            // forImportantUsage is APFS-aware (counts purgeable space) but returns
            // nil/0 on exFAT, HFS+, and shares; fall back to the plain available
            // capacity, then to statfs, so every drive reports a figure.
            let positive: (Int64) -> Int64? = { $0 > 0 ? $0 : nil }
            let free: Int64? = v.volumeAvailableCapacityForImportantUsage.flatMap(positive)
                ?? v.volumeAvailableCapacity.map(Int64.init).flatMap(positive)
                ?? fs.freeBytes
            return VolumeInfo(
                url: url,
                name: v.volumeName ?? url.lastPathComponent,
                isRemovable: (v.volumeIsRemovable ?? false) || (v.volumeIsEjectable ?? false),
                isInternal: v.volumeIsInternal ?? false,
                fsType: fs.type,
                isWritable: fs.writable,
                freeBytes: free
            )
        }
    }

    /// The filesystem type name and writability of a volume, via statfs. This only
    /// reads mount metadata; it never writes to the drive.
    private static func filesystem(of url: URL) -> (type: String, writable: Bool, freeBytes: Int64?) {
        var s = statfs()
        guard statfs(url.path, &s) == 0 else { return ("", true, nil) }
        let type = withUnsafePointer(to: &s.f_fstypename) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) {
                String(cString: $0)
            }
        }
        let writable = (s.f_flags & UInt32(MNT_RDONLY)) == 0
        // f_bavail (blocks free to a non-root user) * f_bsize. Works on every
        // mounted filesystem, including exFAT, where the URL keys come back empty.
        let free = Int64(s.f_bavail) * Int64(s.f_bsize)
        return (type.lowercased(), writable, free > 0 ? free : nil)
    }
}
