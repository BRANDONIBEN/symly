import Foundation

/// Remembers the chosen drive by its volume UUID (stable across remounts and
/// immune to the security-scoped-bookmark "/" resolution bug). The app is
/// non-sandboxed, so it reaches the volume directly; macOS shows its own
/// removable-volume access prompt on first touch.
enum VolumeAccess {
    private static let key = "rememberedVolumeUUID"

    static func remember(_ url: URL) {
        if let uuid = uuid(of: url) {
            UserDefaults.standard.set(uuid, forKey: key)
        }
    }

    static func rememberedURL(in volumes: [VolumeInfo]) -> URL? {
        guard let saved = UserDefaults.standard.string(forKey: key) else { return nil }
        return volumes.first(where: { uuid(of: $0.url) == saved })?.url
    }

    static func uuid(of url: URL) -> String? {
        (try? url.resourceValues(forKeys: [.volumeUUIDStringKey]))?.volumeUUIDString
    }

    /// Forget the remembered drive (used by uninstall).
    static func forget() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
