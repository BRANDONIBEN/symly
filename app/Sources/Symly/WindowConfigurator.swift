import SwiftUI
import AppKit

/// Tunes the host NSWindow: transparent + glassy, no title bar, and pinned to an
/// exact fixed size (so the content never centers inside a too-tall window).
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.remove(.resizable)
            window.isMovableByWindowBackground = true
            window.isOpaque = true
            window.backgroundColor = NSColor(srgbRed: 0x08 / 255.0, green: 0x08 / 255.0, blue: 0x0B / 255.0, alpha: 1)
            window.hasShadow = true
            window.standardWindowButton(.zoomButton)?.isEnabled = false

            // Pin to an exact fixed size, killing the centering gap.
            let size = NSSize(width: panelWidth, height: panelHeight)
            window.setContentSize(size)
            window.contentMinSize = size
            window.contentMaxSize = size
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        // Re-assert the fixed, non-resizable size in case SwiftUI re-enables it.
        let size = NSSize(width: panelWidth, height: panelHeight)
        if window.contentMinSize != size {
            window.contentMinSize = size
            window.contentMaxSize = size
        }
        window.styleMask.remove(.resizable)
    }
}

/// A behind-window vibrancy layer that lets the blurred desktop read as glass.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        v.isEmphasized = true
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
    }
}
