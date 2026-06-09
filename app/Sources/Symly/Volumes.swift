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
    var id: String { url.path }

    /// A cheap, read-only guess at whether Symly can use this drive, shown inline
    /// in the picker so the user does not pick a dead end. exFAT/FAT cannot store
    /// a symlink at all; a read-only mount cannot be written; network shares vary
    /// by server (selectable, but flagged). Everything else is treated as usable
    /// and confirmed by the real probe when selected.
    enum Eligibility: Equatable {
        case eligible
        case network
        case readOnly
        case unsupported(String)
    }

    var eligibility: Eligibility {
        if !isWritable { return .readOnly }
        switch fsType {
        case "exfat", "msdos", "vfat", "fat", "fat32", "ms-dos":
            return .unsupported("exFAT/FAT")
        case "smbfs", "nfs", "afpfs", "webdav", "ftp":
            return .network
        default:
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

    /// Whether the row can be chosen. exFAT/FAT and read-only drives can't be,
    /// so the picker shows them disabled rather than letting setup fail.
    var isSelectable: Bool {
        switch eligibility {
        case .unsupported, .readOnly: return false
        case .eligible, .network: return true
        }
    }
}

enum Volumes {
    static func mounted() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeIsBrowsableKey, .volumeIsRemovableKey,
            .volumeIsInternalKey, .volumeIsEjectableKey,
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
            return VolumeInfo(
                url: url,
                name: v.volumeName ?? url.lastPathComponent,
                isRemovable: (v.volumeIsRemovable ?? false) || (v.volumeIsEjectable ?? false),
                isInternal: v.volumeIsInternal ?? false,
                fsType: fs.type,
                isWritable: fs.writable
            )
        }
    }

    /// The filesystem type name and writability of a volume, via statfs. This only
    /// reads mount metadata; it never writes to the drive.
    private static func filesystem(of url: URL) -> (type: String, writable: Bool) {
        var s = statfs()
        guard statfs(url.path, &s) == 0 else { return ("", true) }
        let type = withUnsafePointer(to: &s.f_fstypename) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) {
                String(cString: $0)
            }
        }
        let writable = (s.f_flags & UInt32(MNT_RDONLY)) == 0
        return (type.lowercased(), writable)
    }
}
