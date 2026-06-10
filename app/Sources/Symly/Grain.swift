import SwiftUI
import CoreImage
import AppKit

/// A faint monochrome noise tile that gives the dark panel a subtle paper-like
/// "tooth." Built once, tiled, low opacity.
enum Grain {
    static let tile: Image? = build()

    private static func build() -> Image? {
        let side = 140
        let context = CIContext(options: nil)
        guard let noise = CIFilter(name: "CIRandomGenerator")?.outputImage else { return nil }
        let mono = noise.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0.0,
            kCIInputContrastKey: 1.1,
        ])
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        guard let cg = context.createCGImage(mono, from: rect) else { return nil }
        return Image(decorative: cg, scale: 1)
    }
}

struct GrainOverlay: View {
    var opacity: Double = 0.06

    var body: some View {
        if let tile = Grain.tile {
            tile
                .resizable(resizingMode: .tile)
                .opacity(opacity)
                .blendMode(.overlay)
                .allowsHitTesting(false)
                .ignoresSafeArea()
        }
    }
}

/// A faint connector mesh: a lattice of nodes (dots) linked by thin lines, the
/// node positions slightly jittered so it reads as a network of connections
/// rather than graph paper. Fits a symlink tool: everything is a link. Static
/// and deterministic (jitter is a fixed function of the node index).
struct ConnectorMesh: View {
    var spacing: CGFloat = 58
    var line: Color = Palette.gridLine
    var node: Color = Palette.accentLight.opacity(0.13)

    private func point(_ c: Int, _ r: Int, _ s: CGFloat) -> CGPoint {
        let jx = CGFloat(sin(Double(c) * 12.99 + Double(r) * 4.13)) * s * 0.22
        let jy = CGFloat(cos(Double(c) * 7.23 + Double(r) * 9.71)) * s * 0.22
        return CGPoint(x: CGFloat(c) * s + jx, y: CGFloat(r) * s + jy)
    }

    var body: some View {
        Canvas { ctx, size in
            let s = spacing
            let cols = Int(size.width / s) + 2
            let rows = Int(size.height / s) + 2
            // Links: each node joins its right and down neighbour.
            var links = Path()
            for c in 0...cols {
                for r in 0...rows {
                    let p = point(c, r, s)
                    links.move(to: p); links.addLine(to: point(c + 1, r, s))
                    links.move(to: p); links.addLine(to: point(c, r + 1, s))
                }
            }
            ctx.stroke(links, with: .color(line), lineWidth: 0.6)
            // Nodes.
            var dots = Path()
            for c in 0...cols {
                for r in 0...rows {
                    let p = point(c, r, s)
                    dots.addEllipse(in: CGRect(x: p.x - 1.3, y: p.y - 1.3, width: 2.6, height: 2.6))
                }
            }
            ctx.fill(dots, with: .color(node))
        }
        .allowsHitTesting(false)
        .drawingGroup()
        .ignoresSafeArea()
    }
}
