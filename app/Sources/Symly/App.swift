import SwiftUI
import AppKit

@main
struct SymlyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        // The real window is created in AppDelegate so the content is pinned to
        // fill (WindowGroup centers non-filling content). This dummy scene just
        // satisfies the App protocol; it is never shown.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--export-icon"), i + 1 < args.count {
            IconExporter.export(to: args[i + 1])
            NSApp.terminate(nil)
            return
        }

        let size = NSSize(width: panelWidth, height: panelHeight)

        let hosting = NSHostingView(rootView: RootView().environmentObject(model))
        hosting.sizingOptions = []  // do not let the content drive the window size
        if #available(macOS 13.3, *) {
            hosting.safeAreaRegions = []  // publish no safe area, so content fills from y=0 (under the titlebar)
        }
        hosting.translatesAutoresizingMaskIntoConstraints = false

        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false
        win.backgroundColor = NSColor(srgbRed: 0x08 / 255.0, green: 0x08 / 255.0, blue: 0x0B / 255.0, alpha: 1)

        let container = NSView()
        win.contentView = container
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        win.setContentSize(size)
        win.contentMinSize = size
        win.contentMaxSize = size
        win.styleMask.remove(.resizable)
        win.standardWindowButton(.zoomButton)?.isEnabled = false
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window?.makeKeyAndOrderFront(nil)
        return true
    }
}
