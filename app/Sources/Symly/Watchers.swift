import AppKit
import Foundation

/// Watches one directory for entries being added / removed / renamed and calls
/// `onChange` on the main queue. Used to keep the project list live.
final class FolderWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var watchedPath: String?

    func watch(_ url: URL, onChange: @escaping () -> Void) {
        if watchedPath == url.path, source != nil { return }
        stop()
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        src.setEventHandler { onChange() }
        src.setCancelHandler { close(descriptor) }
        source = src
        watchedPath = url.path
        src.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        watchedPath = nil
    }

    deinit { stop() }
}

/// Watches for drives mounting / unmounting / renaming.
final class VolumeWatcher {
    private var tokens: [NSObjectProtocol] = []

    func start(onChange: @escaping () -> Void) {
        let nc = NSWorkspace.shared.notificationCenter
        let names: [NSNotification.Name] = [
            NSWorkspace.didMountNotification,
            NSWorkspace.didUnmountNotification,
            NSWorkspace.didRenameVolumeNotification,
        ]
        for name in names {
            tokens.append(nc.addObserver(forName: name, object: nil, queue: .main) { _ in onChange() })
        }
    }

    func stop() {
        let nc = NSWorkspace.shared.notificationCenter
        tokens.forEach { nc.removeObserver($0) }
        tokens = []
    }

    deinit { stop() }
}
