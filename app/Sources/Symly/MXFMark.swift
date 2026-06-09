import SwiftUI

/// The Symly mark: an S formed by a symlink connector (two nodes joined by an
/// S-curve) over a faint connector mesh, on a deep-navy squircle. This single
/// view is the source of truth for both the in-app icon tile and the exported
/// app icon (`IconExporter` renders it at every size).
struct MXFIconTile: View {
    var size: CGFloat = 44

    var body: some View {
        let corner = size * 0.225
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x1C2746), Color(hex: 0x0B0E1C)],
                                     startPoint: .top, endPoint: .bottom))
            Canvas { ctx, sz in mark(ctx, sz) }
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Palette.accent.opacity(0.5), lineWidth: max(1, size * 0.012))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }

    private func mark(_ ctx: GraphicsContext, _ sz: CGSize) {
        let w = sz.width
        let inset = w * 0.185
        let r = CGRect(x: inset, y: inset, width: w - 2 * inset, height: w - 2 * inset)
        // Canvas is top-left origin; flip y so the verified (y-up) coords map over.
        func P(_ nx: CGFloat, _ ny: CGFloat) -> CGPoint {
            CGPoint(x: r.minX + r.width * nx, y: r.minY + r.height * (1 - ny))
        }

        // 1. Faint connector webbing (spacing relative to size, so it scales).
        let sp = w * 0.135
        func wp(_ i: Int, _ j: Int) -> CGPoint {
            CGPoint(x: CGFloat(i) * sp + CGFloat(sin(Double(i) * 12.99 + Double(j) * 4.13)) * sp * 0.22,
                    y: CGFloat(j) * sp + CGFloat(cos(Double(i) * 7.23 + Double(j) * 9.71)) * sp * 0.22)
        }
        let cols = Int(w / sp) + 2, rows = Int(w / sp) + 2
        var lines = Path()
        for i in 0...cols {
            for j in 0...rows {
                let p = wp(i, j)
                lines.move(to: p); lines.addLine(to: wp(i + 1, j))
                lines.move(to: p); lines.addLine(to: wp(i, j + 1))
            }
        }
        ctx.stroke(lines, with: .color(Palette.accentLight.opacity(0.05)), lineWidth: max(0.4, w * 0.004))
        var dots = Path()
        for i in 0...cols {
            for j in 0...rows {
                let p = wp(i, j)
                dots.addEllipse(in: CGRect(x: p.x - w * 0.006, y: p.y - w * 0.006, width: w * 0.012, height: w * 0.012))
            }
        }
        ctx.fill(dots, with: .color(Palette.accentLight.opacity(0.07)))

        // 2. The S connector: a soft glow underlay, then the solid line.
        var s = Path()
        s.move(to: P(0.72, 0.85))
        s.addCurve(to: P(0.50, 0.50), control1: P(0.34, 1.07), control2: P(0.09, 0.60))
        s.addCurve(to: P(0.28, 0.15), control1: P(0.91, 0.40), control2: P(0.66, -0.07))
        ctx.stroke(s, with: .color(Palette.accentLight.opacity(0.30)),
                   style: StrokeStyle(lineWidth: r.width * 0.205, lineCap: .round, lineJoin: .round))
        ctx.stroke(s, with: .color(Palette.accent),
                   style: StrokeStyle(lineWidth: r.width * 0.11, lineCap: .round, lineJoin: .round))

        // 3. The two nodes (gradient body, cool-white center).
        func node(_ c: CGPoint) {
            let rad = r.width * 0.14
            let rect = CGRect(x: c.x - rad, y: c.y - rad, width: rad * 2, height: rad * 2)
            ctx.fill(Path(ellipseIn: rect),
                     with: .linearGradient(Gradient(colors: [Palette.accentLight, Palette.accent]),
                                           startPoint: CGPoint(x: rect.midX, y: rect.minY),
                                           endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
            let cr = rad * 0.34
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - cr, y: c.y - cr, width: cr * 2, height: cr * 2)),
                     with: .color(Palette.cream))
        }
        node(P(0.72, 0.85))
        node(P(0.28, 0.15))
    }
}
