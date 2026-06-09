import SwiftUI
import AppKit

/// The app-icon artwork: the mark on its tile, with a little transparent margin
/// so macOS renders it with the usual icon breathing room.
struct AppIconArtwork: View {
    var px: CGFloat
    var body: some View {
        ZStack {
            Color.clear
            MXFIconTile(size: px * 0.86)
        }
        .frame(width: px, height: px)
    }
}

/// Renders the icon at all required sizes into an .iconset directory. Invoked
/// by `make-icon.sh` via the hidden `--export-icon <dir>` launch argument.
enum IconExporter {
    @MainActor static func export(to dir: String) {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let specs: [(Int, Int)] = [
            (16, 1), (16, 2), (32, 1), (32, 2), (128, 1),
            (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
        ]
        for (pt, scale) in specs {
            let px = CGFloat(pt * scale)
            let renderer = ImageRenderer(content: AppIconArtwork(px: px))
            renderer.scale = 1
            guard let cg = renderer.cgImage else { continue }
            let rep = NSBitmapImageRep(cgImage: cg)
            let name = scale == 1 ? "icon_\(pt)x\(pt).png" : "icon_\(pt)x\(pt)@2x.png"
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
            }
        }
        FileHandle.standardError.write(Data("icon exported to \(dir)\n".utf8))
    }
}
