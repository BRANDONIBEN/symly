import Foundation

/// Protects the app-owned projects folder from being renamed or deleted, using a
/// macOS "deny delete" ACL. The lock blocks rename and delete of the folder
/// itself while leaving its contents fully writable, so Avid keeps importing and
/// Symly keeps creating projects inside it. It is a strong deterrent against
/// accidental Finder rename/delete, not an absolute lock: a user with Terminal
/// can remove it (`chmod -a`). APFS and Mac OS Extended only (the formats Symly
/// allows); the calls simply no-op on filesystems without ACL support.
public struct FolderLock: Sendable {
    /// The single access-control entry we add. macOS dedupes it, so applying it
    /// repeatedly is safe and leaves exactly one entry.
    private static let ace = "everyone deny delete"

    public init() {}

    /// Apply the deny-delete ACL. Idempotent. Returns true if chmod succeeded.
    @discardableResult
    public func lock(_ url: URL) -> Bool {
        run("/bin/chmod", ["+a", Self.ace, url.path])
    }

    /// Remove the deny-delete ACL, so the folder can be renamed or deleted again.
    @discardableResult
    public func unlock(_ url: URL) -> Bool {
        run("/bin/chmod", ["-a", Self.ace, url.path])
    }

    /// Whether the deny-delete ACL is currently present on the folder.
    public func isLocked(_ url: URL) -> Bool {
        guard let out = capture("/bin/ls", ["-lde", url.path]) else { return false }
        return out.contains("deny delete")
    }

    @discardableResult
    private func run(_ path: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 }
        catch { return false }
    }

    private func capture(_ path: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
