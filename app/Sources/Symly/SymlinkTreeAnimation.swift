import SwiftUI
import Combine

/// The "how it works" piece, in two panels: a mini MXF MEDIA app on the left
/// where a cursor clicks a project, and a (narrower) Finder window on the right
/// that reacts: Avid MediaFiles / MXF is the symlink, and the accent tunnel
/// re-points up the left gutter to the clicked project's own MXF folder.

struct TreeRowAnchorKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Orthogonal tunnel routed out to a left spine and back in to the target.
struct TunnelShape: Shape {
    var sourceX: CGFloat
    var sourceY: CGFloat
    var spineX: CGFloat
    var targetX: CGFloat
    var targetY: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: sourceX, y: sourceY))
        p.addLine(to: CGPoint(x: spineX, y: sourceY))
        p.addLine(to: CGPoint(x: spineX, y: targetY))
        p.addLine(to: CGPoint(x: targetX, y: targetY))
        return p
    }
}

private enum RowTone { case normal, dim, accent, linked }

struct SymlinkTreeAnimation: View {
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var sel = 0          // active project: drives both panels + the tunnel target
    @State private var cursorRow = 0    // the row the cursor points at (leads `sel`)
    @State private var draw: CGFloat = 0
    @State private var rows: [String: CGRect] = [:]
    @State private var clickScale: CGFloat = 1
    private let timer = Timer.publish(every: 3.6, on: .main, in: .common).autoconnect()

    private let projects = ["Project A", "Project B", "Project C"]
    private let media: [[String]] = [
        ["A_0607.mxf", "A_0608.mxf"],
        ["B_ep01.mxf", "B_ep02.mxf"],
        ["C_recut.mxf"],
    ]

    // Finder tree geometry. The tunnel attaches just LEFT of each row's
    // expand/collapse chevron (chevron sits at basePad + depth*indent), so the
    // line never covers the arrows, and routes up a spine in the far-left gutter.
    private let indent: CGFloat = 11
    private let basePad: CGFloat = 8
    private let spineX: CGFloat = 11
    private func attachX(depth: Int) -> CGFloat { basePad + CGFloat(depth) * indent - 4 }

    // App-mock geometry (fixed, so the cursor math is exact)
    private let appW: CGFloat = 150
    private let headerH: CGFloat = 36
    private let labelH: CGFloat = 20
    private let rowH: CGFloat = 25
    private let rowGap: CGFloat = 6
    private var listTop: CGFloat { headerH + labelH }
    private func rowCenterY(_ i: Int) -> CGFloat { listTop + CGFloat(i) * (rowH + rowGap) + rowH / 2 }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            appMock
            finderWindow
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .onAppear {
            if reduce { draw = 1; return }
            draw = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeInOut(duration: 0.6)) { draw = 1 }
            }
        }
        .onReceive(timer) { _ in advance() }
    }

    private func advance() {
        guard !reduce else { return }
        let next = (sel + 1) % projects.count
        // 1. The cursor travels to the next project.
        withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { cursorRow = next }
        // 2. On arrival, click: a press pulse + an expanding ring.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeOut(duration: 0.11)) { clickScale = 0.82 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { clickScale = 1 }
            }
            // 3. The Finder reacts: drop the old link, switch, re-grow the tunnel.
            var instant = Transaction(); instant.disablesAnimations = true
            withTransaction(instant) { draw = 0 }
            withAnimation(.easeInOut(duration: 0.4)) { sel = next }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeInOut(duration: 0.55)) { draw = 1 }
            }
        }
    }

    // MARK: App mock (left)

    private var appMock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                MXFIconTile(size: 17)
                Text("Symly").font(.system(size: 10.5, weight: .bold)).foregroundStyle(Palette.ink).tracking(0.3)
            }
            .frame(height: headerH, alignment: .center).padding(.horizontal, 11)

            Text("ACTIVE PROJECT")
                .font(.system(size: 7.5, weight: .semibold)).tracking(1.2).foregroundStyle(Palette.ink30)
                .frame(height: labelH, alignment: .leading).padding(.horizontal, 11)

            VStack(spacing: rowGap) {
                ForEach(Array(projects.enumerated()), id: \.offset) { i, p in
                    appRow(i, p)
                }
            }
            .padding(.horizontal, 9)
            .padding(.bottom, 11)
        }
        .frame(width: appW)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color(hex: 0x141833)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
        .overlay(alignment: .topLeading) { cursor }
    }

    private func appRow(_ i: Int, _ name: String) -> some View {
        let active = i == sel
        return HStack(spacing: 7) {
            Image(systemName: "folder.fill").font(.system(size: 10))
                .foregroundStyle(active ? Palette.accent : Palette.ink45)
            Text(name).font(.system(size: 9.5, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? Palette.ink : Palette.ink55)
            Spacer(minLength: 0)
            if active {
                Image(systemName: "checkmark").font(.system(size: 7, weight: .bold)).foregroundStyle(Palette.accentLight)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: rowH)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(active ? Palette.selection : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(active ? Palette.accent.opacity(0.45) : Color.clear, lineWidth: 1))
    }

    private var cursor: some View {
        // Sits in the open space between the project name and the checkmark.
        let x: CGFloat = 100
        let y = rowCenterY(cursorRow)
        return Image(systemName: "cursorarrow")
            .font(.system(size: 14, weight: .regular)).foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
            .scaleEffect(clickScale)
            .position(x: x, y: y)
            .allowsHitTesting(false)
    }

    // MARK: Finder window (right, narrower)

    private var finderWindow: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                titleBar
                tree
                Spacer(minLength: 0)
            }
            tunnel
        }
        .frame(width: 196)
        .coordinateSpace(name: "tree")
        .onPreferenceChange(TreeRowAnchorKey.self) { rows = $0 }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(hex: 0x141833)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var titleBar: some View {
        HStack(spacing: 5) {
            Circle().fill(Color(hex: 0xFF5F57)).frame(width: 6, height: 6)
            Circle().fill(Color(hex: 0xFEBC2E)).frame(width: 6, height: 6)
            Circle().fill(Color(hex: 0x3D3A36)).frame(width: 6, height: 6)
            Text("Hard Drive").font(.system(size: 9)).foregroundStyle(Palette.ink45).padding(.leading, 6)
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }

    private var tree: some View {
        VStack(alignment: .leading, spacing: 0) {
            row("hd", "Hard Drive", depth: 0, folder: true, open: true, tone: .normal)
            row("amf", "Avid MediaFiles", depth: 1, folder: true, open: true, tone: .accent)
            row("amf-mxf", "MXF", depth: 2, folder: true, open: true, tone: .linked, badge: true)
            ForEach(media[sel], id: \.self) { f in
                row("amflink-\(f)", f, depth: 3, folder: false, open: false, tone: .linked, badge: true)
            }
            row("mop", "Symly Media", depth: 1, folder: true, open: true, tone: .normal)
            ForEach(Array(projects.enumerated()), id: \.offset) { i, p in
                row("proj-\(i)", p, depth: 2, folder: true, open: i == sel,
                    tone: i == sel ? .accent : .dim)
                if i == sel {
                    row("proj-\(i)-mxf", "MXF", depth: 3, folder: true, open: true, tone: .accent)
                    ForEach(media[i], id: \.self) { f in
                        row("file-\(f)", f, depth: 4, folder: false, open: false, tone: .normal)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ id: String, _ label: String, depth: Int, folder: Bool, open: Bool,
                     tone: RowTone, badge: Bool = false) -> some View {
        HStack(spacing: 4) {
            if folder {
                Image(systemName: "chevron.right")
                    .font(.system(size: 6, weight: .semibold)).foregroundStyle(Palette.ink30)
                    .rotationEffect(.degrees(open ? 90 : 0)).frame(width: 7)
            } else {
                Color.clear.frame(width: 7)
            }
            ZStack(alignment: .bottomLeading) {
                Image(systemName: folder ? "folder.fill" : "doc.fill")
                    .font(.system(size: folder ? 9 : 8)).foregroundStyle(iconColor(tone))
                if badge {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 5, weight: .bold)).foregroundStyle(Palette.accentLight)
                        .padding(0.5).background(Circle().fill(Color(hex: 0x141833))).offset(x: -2, y: 2)
                }
            }
            Text(label).font(.system(size: 9, weight: tone == .accent ? .semibold : .regular))
                .foregroundStyle(textColor(tone)).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, basePad + CGFloat(depth) * indent)
        .frame(height: 16)
        .background(GeometryReader { g in
            Color.clear.preference(key: TreeRowAnchorKey.self, value: [id: g.frame(in: .named("tree"))])
        })
    }

    @ViewBuilder private var tunnel: some View {
        GeometryReader { _ in
            if let symlink = rows["amf-mxf"], let proj = rows["proj-\(sel)-mxf"] {
                // Draw from the project's own MXF (origin) up to the Avid MediaFiles/MXF symlink.
                let projX = attachX(depth: 3)
                let projY = proj.midY
                let symX = attachX(depth: 2)
                let symY = symlink.midY
                let shape = TunnelShape(sourceX: projX, sourceY: projY, spineX: spineX, targetX: symX, targetY: symY)
                ZStack {
                    shape.trim(from: 0, to: draw)
                        .stroke(Color(hex: 0x6A5CF6).opacity(0.26),
                                style: StrokeStyle(lineWidth: 4, lineCap: .square, lineJoin: .miter)).blur(radius: 2.4)
                    shape.trim(from: 0, to: draw)
                        .stroke(LinearGradient(colors: [Color(hex: 0x9D93FF), Color(hex: 0x6A5CF6)],
                                               startPoint: .bottom, endPoint: .top),
                                style: StrokeStyle(lineWidth: 1.6, lineCap: .square, lineJoin: .miter))
                    TimelineView(.animation) { context in
                        let t = context.date.timeIntervalSinceReferenceDate
                        let phase = CGFloat(t.truncatingRemainder(dividingBy: 1.0)) * -12
                        shape.trim(from: 0, to: draw)
                            .stroke(Color.white.opacity(0.85),
                                    style: StrokeStyle(lineWidth: 1.3, lineCap: .round, dash: [2, 10], dashPhase: phase))
                    }
                    // Origin dot at the project MXF; terminator square at the symlink.
                    Circle().fill(Color(hex: 0x9D93FF)).frame(width: 4, height: 4)
                        .position(x: projX, y: projY).opacity(draw > 0.02 ? 1 : 0)
                    Rectangle().fill(Color(hex: 0x9D93FF)).frame(width: 4, height: 4)
                        .position(x: symX, y: symY).opacity(draw > 0.96 ? 1 : 0)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func iconColor(_ tone: RowTone) -> Color {
        switch tone {
        case .accent: return Palette.accent
        case .linked: return Palette.accentLight.opacity(0.85)
        case .dim: return Palette.ink30
        case .normal: return Palette.ink45
        }
    }
    private func textColor(_ tone: RowTone) -> Color {
        switch tone {
        case .accent: return Palette.ink
        case .linked: return Palette.accentLight
        case .dim: return Palette.ink30
        case .normal: return Palette.ink55
        }
    }
}
