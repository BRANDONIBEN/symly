import SwiftUI
import Combine
import SymlyCore

let panelWidth: CGFloat = 420
let panelHeight: CGFloat = 600

extension AnyTransition {
    /// A sleek, native screen change: a small spring-settled scale + fade (a soft
    /// "push forward"), not a webpage-style slide.
    static var gentle: AnyTransition {
        .scale(scale: 0.97, anchor: .center).combined(with: .opacity)
    }
}

extension Binding where Value == String {
    /// Live-replaces whitespace with underscores so media folder names stay space-free,
    /// the way Avid media naming expects (e.g. "HBO Media" -> "HBO_Media").
    var spaceless: Binding<String> {
        Binding(
            get: { wrappedValue },
            set: { newValue in
                wrappedValue = newValue.replacingOccurrences(
                    of: "\\s", with: "_", options: .regularExpression)
            }
        )
    }
}

// MARK: - Root

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        ZStack(alignment: .top) {
            PanelBackground()
            screen
                .animation(reduce ? nil : .spring(response: 0.32, dampingFraction: 0.85), value: model.phase)
                .animation(reduce ? nil : .spring(response: 0.32, dampingFraction: 0.85), value: model.page)
                .animation(reduce ? nil : .spring(response: 0.32, dampingFraction: 0.85), value: model.showOnboarding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onAppear { model.start() }
        .sheet(isPresented: $model.showingNewProject) {
            NewProjectSheet().environmentObject(model)
        }
        .alert(
            "Heads up",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder private var screen: some View {
        if model.showOnboarding {
            OnboardingPage().transition(.gentle)
        } else {
            switch model.page {
            case .howItWorks: HowItWorksPage().transition(.gentle)
            case .help:       HelpPage().transition(.gentle)
            case .settings:   SettingsPage().transition(.gentle)
            case .none:       homeContent.transition(.gentle)
            }
        }
    }

    @ViewBuilder private var homeContent: some View {
        switch model.phase {
        case .chooseVolume:        ChooseVolumeStep()
        case .setupFresh:          FreshSetupStep()
        case .setupAdopt(let m):   AdoptSetupStep(hasMedia: m)
        case .blocked(let reason): BlockedStep(reason: reason)
        case .ready:               MainPanel()
        }
    }
}

// MARK: - Glassy background

struct PanelBackground: View {
    var body: some View {
        ZStack {
            Palette.canvas
            // Soft navy lift toward the upper center (Suite depth).
            RadialGradient(colors: [Palette.canvasLift.opacity(0.95), .clear],
                           center: UnitPoint(x: 0.5, y: 0.32), startRadius: 6, endRadius: 420)
            ConnectorMesh()
            // Quiet rim light along the top edge.
            VStack { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1); Spacer() }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Shared bits

struct FieldLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 9, weight: .semibold)).tracking(1.3).foregroundStyle(Palette.ink30)
    }
}

struct CareNote: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield").font(.system(size: 11)).foregroundStyle(Palette.accentLight)
            Text("Your media is never copied or deleted. Only symlinks change.")
                .font(.system(size: 10.5)).foregroundStyle(Palette.ink45)
        }
    }
}

struct PrimaryButton: View {
    let title: String
    let enabled: Bool
    let action: () -> Void
    var body: some View {
        Button(action: { if enabled { action() } }) {
            Text(title).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(enabled ? .white : Palette.ink45)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(enabled ? Palette.accent : Palette.fieldFill))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(enabled ? Color.clear : Palette.hairline, lineWidth: 1))
                .shadow(color: enabled ? Palette.accent.opacity(0.4) : .clear, radius: 14, y: 4)
        }
        .buttonStyle(PressableStyle()).disabled(!enabled)
    }
}

struct ChangeDriveButton: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Button("Choose a different drive") { model.changeDrive() }
            .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.ink30)
    }
}

/// The consistent bottom nav, identical on every primary screen: How it works +
/// Help on the left, the Settings gear on the right.
struct ScreenFooter: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: 16) {
            linkButton("How it works") { model.page = .howItWorks }
            linkButton("Help") { model.page = .help }
            Spacer()
            Button(action: { model.page = .settings }) {
                Image(systemName: "gearshape").font(.system(size: 13)).foregroundStyle(Palette.ink30)
            }
            .buttonStyle(.plain)
        }
    }
    private func linkButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11)).foregroundStyle(Palette.ink30)
        }
        .buttonStyle(.plain)
    }
}

/// A quiet, accent-tipped tip callout used in setup.
struct TipNote: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb").font(.system(size: 11)).foregroundStyle(Palette.accentLight)
            Text(text).font(.system(size: 11)).foregroundStyle(Palette.ink55)
                .fixedSize(horizontal: false, vertical: true).lineSpacing(1.5)
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 9).fill(Palette.selection))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Palette.accent.opacity(0.28), lineWidth: 1))
    }
}

struct FolderNameField: View {
    @EnvironmentObject var model: AppModel
    var disabled = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel("MEDIA FOLDER ON DRIVE")
            TextField("Folder name", text: $model.projectsFolderName)
                .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.ink)
                .fieldStyle().disabled(disabled)
            Text("We make this folder on your drive. Each project gets its own media folder inside it.")
                .font(.system(size: 10)).foregroundStyle(Palette.ink30).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Setup scaffold (fixed size, top-aligned)

struct SetupScaffold<Content: View, Footer: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 38)
            MXFIconTile(size: 44)
            Spacer().frame(height: 14)
            Text(title).font(.system(size: 20, weight: .bold))
                .foregroundStyle(Palette.ink).multilineTextAlignment(.center)
            Spacer().frame(height: 7)
            Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.ink55)
                .multilineTextAlignment(.center).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 334)
            if let name = model.selectedVolume?.name {
                Spacer().frame(height: 13)
                SelectedDriveChip(name: name)
            }
            Spacer().frame(height: 20)
            content()
            Spacer(minLength: 14)
            footer()
            Spacer().frame(height: 16)
            ScreenFooter()
        }
        .padding(.horizontal, 30).padding(.bottom, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }
}

/// A compact indicator of which drive is being set up, shown on every setup step
/// so the drive you are configuring is never ambiguous.
struct SelectedDriveChip: View {
    let name: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "externaldrive.fill").font(.system(size: 10.5)).foregroundStyle(Palette.accentLight)
            Text(name).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.ink).lineLimit(1)
        }
        .padding(.horizontal, 11).padding(.vertical, 5.5)
        .background(Capsule().fill(Palette.selection))
        .overlay(Capsule().strokeBorder(Palette.accent.opacity(0.3), lineWidth: 1))
    }
}

// MARK: - Step 1: choose volume

struct ChooseVolumeStep: View {
    @EnvironmentObject var model: AppModel

    /// Usable drives first (external before internal), then network, read-only,
    /// and unsupported drives last, so the drive you want is at the top.
    private var sortedVolumes: [VolumeInfo] {
        model.volumes.sorted { a, b in
            if a.eligibilityRank != b.eligibilityRank { return a.eligibilityRank < b.eligibilityRank }
            if a.isRemovable != b.isRemovable { return a.isRemovable && !b.isRemovable }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    var body: some View {
        SetupScaffold(
            title: "Choose your drive",
            subtitle: "Pick the drive your Avid media lives on. We only ever touch this drive, and only ever change symlinks."
        ) {
            VStack(spacing: 14) {
                TipNote(text: "Set up here before you open Avid. It reads from your active media folder the moment it launches.")
                Group {
                    if model.volumes.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "externaldrive.badge.questionmark")
                                .font(.system(size: 20)).foregroundStyle(Palette.ink30)
                            Text("Connect a drive and it shows up here automatically.")
                                .font(.system(size: 12)).foregroundStyle(Palette.ink45)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 22)
                    } else if sortedVolumes.count > 4 {
                        VStack(spacing: 6) {
                            // 4 full rows (54pt each, 8pt gaps) plus a 10pt peek of
                            // the 5th, hard-clipped, so the fold reads as a tuck:
                            // there are more drives just under it.
                            ScrollView { volumeRows }.frame(height: 258).scrollIndicators(.hidden)
                            Text("\(sortedVolumes.count) drives connected. Scroll for the rest.")
                                .font(.system(size: 9.5)).foregroundStyle(Palette.ink30)
                        }
                    } else {
                        volumeRows
                    }
                }
            }
        } footer: {
            EmptyView()
        }
        .onAppear { model.reloadVolumes() }
    }

    private var volumeRows: some View {
        VStack(spacing: 8) {
            ForEach(sortedVolumes) { vol in
                VolumeChoiceRow(vol: vol)
                    .onTapGesture { if vol.isSelectable { model.select(vol) } }
            }
        }
    }
}

struct VolumeChoiceRow: View {
    let vol: VolumeInfo
    @State private var hover = false

    private var selectable: Bool { vol.isSelectable }
    private var active: Bool { hover && selectable }

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 15)).foregroundStyle(iconColor).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(vol.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    .foregroundStyle(selectable ? Palette.ink : Palette.ink45)
                Text(subtitle).font(.system(size: 10)).foregroundStyle(subtitleColor).lineLimit(1)
            }
            Spacer()
            Image(systemName: selectable ? "chevron.right" : "lock.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(active ? Palette.accentLight : Palette.ink30)
        }
        .padding(.horizontal, 13).padding(.vertical, 12)
        .frame(height: 54)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(active ? Palette.selection : Palette.fieldFill))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(active ? Palette.accent.opacity(0.4) : Palette.hairline, lineWidth: 1))
        .opacity(selectable ? 1 : 0.6)
        .contentShape(Rectangle())
        .onHover { if selectable { hover = $0 } }
        .animation(.easeOut(duration: 0.15), value: hover)
        .help(helpText)
    }

    private var icon: String {
        switch vol.eligibility {
        case .unsupported, .readOnly: return "externaldrive.badge.xmark"
        case .network: return "network"
        case .eligible: return vol.isInternal ? "internaldrive.fill" : "externaldrive.fill"
        }
    }
    private var iconColor: Color {
        if !selectable { return Palette.ink30 }
        return active ? Palette.accentLight : Palette.ink55
    }
    private var subtitle: String {
        switch vol.eligibility {
        case .eligible:
            let kind = vol.isInternal ? "Internal" : (vol.isRemovable ? "External" : "Volume")
            return vol.freeSpaceLabel.map { "\(kind) · \($0)" } ?? kind
        case .network: return "Network drive · test on your setup first"
        case .readOnly: return "Read-only · can't create the link"
        case .unsupported(let kind): return "\(kind) · can't hold a symlink"
        }
    }
    private var subtitleColor: Color {
        switch vol.eligibility {
        case .eligible: return Palette.ink30
        case .network, .readOnly, .unsupported: return Palette.warn
        }
    }
    private var helpText: String {
        switch vol.eligibility {
        case .unsupported(let reason): return reason
        case .readOnly: return "This drive is mounted read-only, so Symly can't create the link."
        case .network: return "Network and shared volumes support symlinks inconsistently. Test the import/switch flow on your setup before relying on it."
        case .eligible: return ""
        }
    }
}

// MARK: - Step 2a: fresh

struct FreshSetupStep: View {
    @EnvironmentObject var model: AppModel
    @State private var name = ""
    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        SetupScaffold(
            title: "Set up this drive",
            subtitle: "No Avid MediaFiles/MXF here yet. Name your first media folder. Avid writes into it as you import, or you copy existing MXF in. Switching later just repoints the link."
        ) {
            VStack(spacing: 14) {
                LinkDiagram(rightLabel: trimmed.isEmpty ? "Your media folder" : trimmed)
                TextField("Media folder name, e.g. HBO_Media", text: $name.spaceless)
                    .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Palette.ink).fieldStyle().onSubmit(go)
                FolderNameField()
                CareNote()
            }
        } footer: {
            VStack(spacing: 10) {
                PrimaryButton(title: "Create & link", enabled: !trimmed.isEmpty && model.folderNameValid, action: go)
                ChangeDriveButton()
            }
        }
    }

    private func go() {
        guard !trimmed.isEmpty else { return }
        model.completeFreshSetup(projectName: trimmed)
    }
}

// MARK: - Step 2b: adopt

struct AdoptSetupStep: View {
    @EnvironmentObject var model: AppModel
    let hasMedia: Bool
    @State private var name = ""
    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var subtitle: String {
        hasMedia
            ? "This drive already has media in Avid MediaFiles/MXF. Name the media folder for it, and we move it into place by a same-drive rename. Never a copy or delete."
            : "There is an empty Avid MediaFiles/MXF here. Name a media folder to adopt it into, and we set up the link."
    }

    var body: some View {
        SetupScaffold(title: "We found existing media", subtitle: subtitle) {
            VStack(spacing: 14) {
                LinkDiagram(rightLabel: trimmed.isEmpty ? "Your media folder" : trimmed)
                TextField("Media folder name", text: $name.spaceless)
                    .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Palette.ink)
                    .fieldStyle().onSubmit(go)
                FolderNameField()
                CareNote()
            }
        } footer: {
            VStack(spacing: 10) {
                PrimaryButton(title: "Set up this media folder", enabled: !trimmed.isEmpty && model.folderNameValid, action: go)
                ChangeDriveButton()
            }
        }
    }

    private func go() {
        guard !trimmed.isEmpty else { return }
        model.adopt(projectName: trimmed)
    }
}

struct BlockedStep: View {
    let reason: String
    var body: some View {
        SetupScaffold(title: "Can't set up this drive", subtitle: reason) {
            CareNote()
        } footer: {
            ChangeDriveButton()
        }
    }
}

// MARK: - Setup single-link diagram (Avid -> the project being named)

struct LinkDiagram: View {
    var rightLabel: String
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var draw: CGFloat = 0

    var body: some View {
        // Left pill and right pill sit at their natural width; the dashed line is
        // the flexible element between them. So the right (project) pill hugs the
        // right edge and grows leftward as the name grows, and the line shrinks to
        // meet it. The label is capped so the pill can't outgrow the panel.
        HStack(spacing: 8) {
            pill("Avid MediaFiles", system: "externaldrive.fill", alignment: .leading)
                .layoutPriority(1)
            GeometryReader { geo in
                SymlinkTrace(startX: 0, startY: geo.size.height / 2,
                             endX: geo.size.width, endY: geo.size.height / 2,
                             draw: reduce ? 1 : draw)
            }
            .frame(minWidth: 16)
            pill(String(rightLabel.prefix(LinkDiagram.maxLabel)), system: "folder.fill", alignment: .trailing)
                .layoutPriority(1)
        }
        .frame(height: 38)
        .onAppear {
            guard !reduce else { draw = 1; return }
            draw = 0
            withAnimation(.easeOut(duration: 0.7)) { draw = 1 }
        }
    }

    /// Cap the project label so the growing pill can never overflow the panel.
    static let maxLabel = 32

    private func pill(_ text: String, system: String, alignment: TextAlignment = .leading) -> some View {
        HStack(spacing: 5) {
            Image(systemName: system).font(.system(size: 10)).foregroundStyle(Palette.accentLight)
            Text(text).font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.ink)
                .lineLimit(1).multilineTextAlignment(alignment)
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(Palette.selection))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.accent.opacity(0.4), lineWidth: 1))
    }
}

// MARK: - Ready: switching panel

struct MainPanel: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 38)
            Header()
            Spacer().frame(height: 18)
            if model.justCompletedSetup {
                SetupDoneBanner()
                Spacer().frame(height: 14)
            } else if model.linkNeedsReestablishing {
                BrokenLinkBanner()
                Spacer().frame(height: 14)
            } else if model.activeProject == nil && !model.projects.isEmpty {
                ReconnectBanner()
                Spacer().frame(height: 14)
            }
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) { FieldLabel("DRIVE"); ReadyVolumeRow() }
                VStack(alignment: .leading, spacing: 7) { FieldLabel("ACTIVE MEDIA FOLDER"); DestinationDropdown() }
            }
            .zIndex(1)
            Spacer().frame(height: 20)
            ConfirmButton()
            Spacer().frame(height: 14)
            StatusLine()
            if model.projects.count > 1 {
                Spacer().frame(height: 7)
                Text("Switch while Avid is closed, so it reloads the project cleanly.")
                    .font(.system(size: 10)).foregroundStyle(Palette.ink30)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity)
            }
            Spacer(minLength: 16)
            ScreenFooter()
        }
        .padding(.horizontal, 30).padding(.bottom, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }
}

/// Shown when the drive is already set up (projects exist) but nothing is linked
/// right now, e.g. the MXF symlink was deleted. Reassures + points to the action.
struct ReconnectBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "link").font(.system(size: 14)).foregroundStyle(Palette.accentLight)
            VStack(alignment: .leading, spacing: 2) {
                Text("This drive is already set up").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ink)
                Text("No media folder is linked right now. Pick one below to reconnect, or add a new one. Your media is untouched.")
                    .font(.system(size: 10.5)).foregroundStyle(Palette.ink55).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.selection))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.accent.opacity(0.32), lineWidth: 1))
    }
}

/// Shown when the drive is mounted but the active link points at a folder that
/// is no longer there (renamed, moved, or deleted in Finder). It is NOT a
/// disconnect and NOT media loss: the link just needs to be re-established.
struct BrokenLinkBanner: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 14)).foregroundStyle(Palette.warn)
            VStack(alignment: .leading, spacing: 2) {
                Text("This drive's link needs re-establishing").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ink)
                Text("The folder it points to isn't there anymore. It may have been renamed or moved in Finder. Your media is safe. To fix it, rename the folder back to what it was, or pick a media folder below to re-link.")
                    .font(.system(size: 10.5)).foregroundStyle(Palette.ink55).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.warn.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.warn.opacity(0.4), lineWidth: 1))
    }
}

struct SetupDoneBanner: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 14)).foregroundStyle(Palette.accentLight)
            Text("This drive is set up").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ink)
            Spacer(minLength: 0)
            Button(action: { model.dismissSetupDone() }) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.ink45)
            }.buttonStyle(.plain)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.selection))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.accent.opacity(0.3), lineWidth: 1))
    }
}

struct Header: View {
    var body: some View {
        VStack(spacing: 9) {
            MXFIconTile(size: 50)
            Text("Symly")
                .font(.system(size: 18, weight: .bold)).foregroundStyle(Palette.ink).tracking(0.5)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ReadyVolumeRow: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "externaldrive.fill").font(.system(size: 12)).foregroundStyle(Palette.accentLight)
            Text(model.volumeName).font(.system(size: 13)).foregroundStyle(Palette.ink).lineLimit(1)
            Spacer()
            if model.driveConnected, let free = model.selectedVolume?.freeSpaceLabel {
                Text(free).font(.system(size: 11)).foregroundStyle(Palette.ink30)
            }
            if !model.driveConnected {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundStyle(.orange)
            }
            Button("Change") { model.changeDrive() }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.ink45)
        }
        .fieldStyle()
    }
}

struct DestinationDropdown: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var open = false
    @State private var hovered: String?

    private var isPlaceholder: Bool { model.chosenProject == nil }
    private var label: String { model.chosenProject ?? "Select a media folder" }

    var body: some View {
        Button(action: { toggle() }) {
            HStack(spacing: 8) {
                Group { if isPlaceholder { Text(label).italic() } else { Text(label) } }
                    .font(.system(size: 13)).foregroundStyle(isPlaceholder ? Palette.ink45 : Palette.ink)
                Spacer()
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.ink45)
                    .rotationEffect(.degrees(open ? 180 : 0))
            }
            .fieldStyle().contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { if open { menu.offset(y: 44) } }
        .zIndex(open ? 10 : 0)
    }

    private var menu: some View {
        VStack(spacing: 0) {
            if model.projects.isEmpty {
                Text("No media folders yet").font(.system(size: 12)).foregroundStyle(Palette.ink30)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 13).padding(.vertical, 11)
            }
            ForEach(model.projects) { project in
                menuRow(project.name, active: project.name == model.activeProject)
            }
            Rectangle().fill(Palette.hairline).frame(height: 1)
            Button(action: { close(); model.showingNewProject = true }) {
                HStack(spacing: 7) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .bold)); Text("New media folder"); Spacer()
                }
                .font(.system(size: 13)).foregroundStyle(Palette.accentLight)
                .padding(.horizontal, 13).padding(.vertical, 11).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(hovered == "__new" ? Palette.selection : Color.clear)
            .onHover { if $0 { hovered = "__new" } else if hovered == "__new" { hovered = nil } }
        }
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(hex: 0x141833)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 18, y: 9)
        .transition(reduce ? .opacity : .scale(scale: 0.96, anchor: .top).combined(with: .opacity))
    }

    private func menuRow(_ name: String, active: Bool) -> some View {
        Button(action: { select(name) }) {
            HStack(spacing: 8) {
                Text(name).font(.system(size: 13)).foregroundStyle(active ? Palette.ink : Palette.ink55)
                Spacer()
                if active { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.accentLight) }
            }
            .padding(.horizontal, 13).padding(.vertical, 10).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(hovered == name ? Palette.selection : Color.clear)
        .onHover { if $0 { hovered = name } else if hovered == name { hovered = nil } }
    }

    private func toggle() {
        if reduce { open.toggle() } else { withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { open.toggle() } }
    }
    private func close() {
        if reduce { open = false } else { withAnimation(.easeOut(duration: 0.16)) { open = false } }
    }
    private func select(_ name: String) { model.chosenProject = name; close() }
}

struct ConfirmButton: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduce
    private var armed: Bool { model.canConfirm }
    var body: some View {
        Button(action: { if armed { model.switchToChosen() } }) {
            Text("Switch").font(.system(size: 13, weight: .semibold)).foregroundStyle(armed ? .white : Palette.ink45)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(armed ? Palette.accent : Palette.fieldFill))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(armed ? Color.clear : Palette.hairline, lineWidth: 1))
                .shadow(color: armed ? Palette.accent.opacity(0.4) : .clear, radius: armed ? 14 : 0, y: armed ? 4 : 0)
        }
        .buttonStyle(PressableStyle()).disabled(!armed).animation(reduce ? nil : .easeOut(duration: 0.22), value: armed)
    }
}

/// "Linked to <project>": a shortcut that opens that project's media folder in Finder.
struct LinkedToButton: View {
    @EnvironmentObject var model: AppModel
    let project: String
    @State private var hover = false
    var body: some View {
        Button(action: { model.openMediaFolder() }) {
            HStack(spacing: 4) {
                Text("Linked to").foregroundStyle(Palette.ink45)
                Text(project).foregroundStyle(Palette.accentLight)
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 9)).foregroundStyle(Palette.accentLight.opacity(hover ? 1 : 0.55))
            }
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(hover ? Palette.selection.opacity(0.7) : Color.clear))
        }
        .buttonStyle(PressableStyle())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
        .help("Open \(project)'s media folder in Finder")
    }
}

struct StatusLine: View {
    @EnvironmentObject var model: AppModel
    var body: some View { content.font(.system(size: 11)).frame(maxWidth: .infinity) }
    @ViewBuilder private var content: some View {
        if !model.driveMounted {
            warn("Drive not connected. Reconnect to relink.")
        } else if let active = model.activeProject {
            if model.driveConnected {
                LinkedToButton(project: active)
            } else {
                warn("Link points to a missing folder. Re-link to fix it.")
            }
        } else {
            Text("No media folder linked yet.").foregroundStyle(Palette.ink45)
        }
    }
    private func warn(_ message: String) -> some View {
        HStack(spacing: 5) { Image(systemName: "exclamationmark.triangle.fill"); Text(message) }.foregroundStyle(.orange)
    }
}

// MARK: - Pages

/// A real, contained back control: a circular chevron button. Reads as a button,
/// not floating text, and sits clear of the window's traffic lights.
struct BackButton: View {
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(hover ? Palette.accentLight : Palette.ink55)
                .frame(width: 33, height: 33)
                .background(Circle().fill(hover ? Palette.selection : Palette.card))
                .overlay(Circle().strokeBorder(hover ? Palette.accent.opacity(0.55) : Palette.hairline, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
        .accessibilityLabel("Back")
    }
}

struct PageChrome<Content: View>: View {
    @EnvironmentObject var model: AppModel
    let title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 0) {
            // Nav bar: back chevron on the left, title centered, clear of the lights.
            ZStack {
                Text(title)
                    .font(.system(size: 20, weight: .bold)).foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .center)
                HStack {
                    BackButton { model.page = .none }
                    Spacer()
                }
            }
            .padding(.top, 50).padding(.horizontal, 22)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 24)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }
}

struct HowItWorksPage: View {
    var body: some View {
        PageChrome(title: "How it works") {
            VStack(spacing: 20) {
                SymlinkTreeAnimation().frame(height: 238).padding(.horizontal, 26)
                VStack(alignment: .leading, spacing: 15) {
                    StepRow(n: 1, title: "Pick your drive", detail: "Choose the drive your Avid media lives on.")
                    StepRow(n: 2, title: "Name your media folders", detail: "Each project gets its own media folder. Avid fills it as you import, or you copy existing MXF into the numbered 1, 2, 3 folders.")
                    StepRow(n: 3, title: "Switch in one click", detail: "Avid always reads one link. Switching repoints it. Nothing is copied, moved, or deleted.")
                }
                .padding(.horizontal, 32)
            }
        }
    }
}

/// First-launch welcome: the How It Works steps with no back button and a
/// "Let's go" CTA that drops you into setup. Shown only on the very first run.
struct OnboardingPage: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 48)
            MXFIconTile(size: 50)
            Spacer().frame(height: 18)
            Text("How it works").font(.system(size: 22, weight: .bold)).foregroundStyle(Palette.ink)
            Spacer().frame(height: 30)
            LinkDiagram(rightLabel: "Symly Media").padding(.horizontal, 30)
            Spacer().frame(height: 36)
            VStack(alignment: .leading, spacing: 18) {
                StepRow(n: 1, title: "Pick your drive", detail: "Choose the drive your Avid media lives on.")
                StepRow(n: 2, title: "Name your media folders", detail: "Each project gets its own media folder. Avid fills it as you import, or you copy existing MXF into the numbered 1, 2, 3 folders.")
                StepRow(n: 3, title: "Switch in one click", detail: "Avid always reads one link. Switching repoints it. Nothing is copied, moved, or deleted.")
            }
            .padding(.horizontal, 30)
            Spacer(minLength: 24)
            PrimaryButton(title: "Set up my drive", enabled: true) { model.completeOnboarding() }
                .padding(.horizontal, 30)
            Spacer().frame(height: 26)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }
}

struct StepRow: View {
    let n: Int
    let title: String
    let detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                .frame(width: 23, height: 23).background(Circle().fill(Palette.accent))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                Text(detail).font(.system(size: 11)).foregroundStyle(Palette.ink55)
                    .fixedSize(horizontal: false, vertical: true).lineSpacing(1.5)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Orthogonal symlink trace: a right-angle routed path with a soft glow, a
/// crisp accent line, and a white pulse.
struct OrthogonalTrace: Shape {
    var startX: CGFloat
    var startY: CGFloat
    var endX: CGFloat
    var endY: CGFloat
    var animatableData: CGFloat {
        get { endY }
        set { endY = newValue }
    }
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let gutter = startX + (endX - startX) * 0.55
        p.move(to: CGPoint(x: startX, y: startY))
        p.addLine(to: CGPoint(x: gutter, y: startY))
        p.addLine(to: CGPoint(x: gutter, y: endY))
        p.addLine(to: CGPoint(x: endX, y: endY))
        return p
    }
}

/// The symlink trace: a blurred accent glow underlay, a thin gradient line with
/// square caps + miter joins, a white 2/10 flowing dash, a circle at the source
/// and a square at the target.
struct SymlinkTrace: View {
    let startX: CGFloat
    let startY: CGFloat
    let endX: CGFloat
    var endY: CGFloat
    var draw: CGFloat = 1

    private var trace: OrthogonalTrace {
        OrthogonalTrace(startX: startX, startY: startY, endX: endX, endY: endY)
    }

    var body: some View {
        ZStack {
            trace.trim(from: 0, to: draw)
                .stroke(Color(hex: 0x6A5CF6).opacity(0.26),
                        style: StrokeStyle(lineWidth: 4.5, lineCap: .square, lineJoin: .miter))
                .blur(radius: 2.5)
            trace.trim(from: 0, to: draw)
                .stroke(LinearGradient(colors: [Color(hex: 0x9D93FF), Color(hex: 0x6A5CF6)],
                                       startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 1.8, lineCap: .square, lineJoin: .miter))
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let phase = CGFloat(t.truncatingRemainder(dividingBy: 1.0)) * -12
                trace.stroke(Color.white.opacity(0.85),
                             style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [2, 10], dashPhase: phase))
                    .opacity(draw >= 1 ? 0.9 : 0)
            }
            Circle().fill(Color(hex: 0x9D93FF)).frame(width: 4, height: 4)
                .position(x: startX, y: startY).opacity(draw > 0 ? 1 : 0)
            Rectangle().fill(Color(hex: 0x9D93FF)).frame(width: 4.5, height: 4.5)
                .position(x: endX, y: endY).opacity(draw >= 1 ? 1 : 0)
        }
    }
}

struct RepointAnimation: View {
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var toB = false
    private let timer = Timer.publish(every: 2.8, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let leftW: CGFloat = 150
            let rightW: CGFloat = 96
            let startX = leftW
            let endX = w - rightW
            let midY = h / 2
            let aY = h * 0.28
            let bY = h * 0.72
            let endY = toB ? bY : aY

            ZStack(alignment: .topLeading) {
                SymlinkTrace(startX: startX, startY: midY, endX: endX, endY: endY, draw: 1)
                    .frame(width: w, height: h)
                pill("Avid MediaFiles", system: "externaldrive.fill", accent: true).position(x: leftW / 2, y: midY)
                pill("Show A", system: "folder.fill", accent: !toB).position(x: w - rightW / 2, y: aY)
                pill("Show B", system: "folder.fill", accent: toB).position(x: w - rightW / 2, y: bY)
            }
        }
        .onReceive(timer) { _ in
            guard !reduce else { return }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.78)) { toB.toggle() }
        }
    }

    private func pill(_ text: String, system: String, accent: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: system).font(.system(size: 10)).foregroundStyle(accent ? Palette.accentLight : Palette.ink45)
            Text(text).font(.system(size: 10, weight: .medium)).foregroundStyle(accent ? Palette.ink : Palette.ink45).lineLimit(1)
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 7).fill(accent ? Palette.selection : Palette.fieldFill))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(accent ? Palette.accent.opacity(0.5) : Palette.hairline, lineWidth: 1))
        .animation(.easeOut(duration: 0.4), value: accent)
    }
}

struct HelpPage: View {
    @EnvironmentObject var model: AppModel

    private let privacy = "Symly runs entirely on your Mac and never opens a network connection, so nothing you do in it leaves your computer. There is no account, no sign-in, no analytics, no telemetry, and no update check. The only thing it remembers between launches is which drive you last set up, kept in your local app preferences. It reads only the drive you choose, and the only thing it ever writes is a single symlink."
    private let terms = "Symly is free, open source, and provided as-is and as-available, with no warranty of any kind, express or implied, including any warranty of merchantability, fitness for a particular purpose, or non-infringement, and no guarantee that it will be uninterrupted, error-free, or safe for your particular setup. You use it entirely at your own risk. To the fullest extent permitted by law, you agree that Brandon Iben is not liable for any loss or damage of any kind, including lost, moved, or corrupted media, lost work, or downtime, arising from your use of the app or any of its tools. You are responsible for testing it on your own workflow before relying on it, for keeping your own backups, and for how you use it. Always confirm it is appropriate, safe, and secure for your setup before trusting it in production."
    private let disclaimer = "Symly was designed and built by Brandon Iben with AI assistance, including Anthropic's Claude through Claude Code. The judgment and the final calls are his, and the engine is open source so you can read exactly what it does. Its media operations are built to be safe: Symly only ever creates and repoints a symlink, and never copies, moves, or deletes your media. Even so, this is software that touches your media. Test it on your own setup and confirm it behaves the way you expect before you rely on it in production."

    var body: some View {
        PageChrome(title: "Help") {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Button(action: { model.page = .howItWorks }) {
                        HStack(spacing: 9) {
                            Image(systemName: "play.circle").font(.system(size: 14)).foregroundStyle(Palette.accentLight)
                            Text("How it works").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.ink)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.ink30)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 13)
                        .cardStyle(radius: 11)
                    }
                    .buttonStyle(PressableStyle())

                    VStack(alignment: .leading, spacing: 0) {
                        section("PRIVACY POLICY", privacy)
                        divider
                        section("TERMS OF USE", terms)
                        divider
                        section("DISCLAIMER", disclaimer)
                    }
                    .padding(.horizontal, 16)
                    .cardStyle()

                    HStack(spacing: 16) {
                        if let url = URL(string: "https://getsymly.app") {
                            Link(destination: url) {
                                HStack(spacing: 5) {
                                    Image(systemName: "globe").font(.system(size: 11))
                                    Text("getsymly.app").font(.system(size: 11, weight: .medium))
                                }
                                .foregroundStyle(Palette.accentLight)
                            }
                        }
                        if let url = URL(string: "https://github.com/brandoniben/symly") {
                            Link(destination: url) {
                                HStack(spacing: 5) {
                                    Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 11))
                                    Text("GitHub").font(.system(size: 11, weight: .medium))
                                }
                                .foregroundStyle(Palette.accentLight)
                            }
                        }
                    }
                    Text("Questions or feedback? Email symly@brandoniben.com")
                        .font(.system(size: 10.5)).foregroundStyle(Palette.ink45)
                    Text("Not affiliated with, endorsed by, or sponsored by Avid Technology, Inc. Avid and Media Composer are trademarks of Avid Technology, Inc. MXF is an open SMPTE standard.")
                        .font(.system(size: 9.5)).foregroundStyle(Palette.ink30).fixedSize(horizontal: false, vertical: true).lineSpacing(1.3)
                }
                .padding(.horizontal, 24).padding(.bottom, 26)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var divider: some View {
        Rectangle().fill(Palette.hairline).frame(height: 1)
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11, weight: .semibold)).tracking(1.4)
                .foregroundStyle(Palette.accentLight)
            Text(body).font(.system(size: 11)).foregroundStyle(Palette.ink55)
                .fixedSize(horizontal: false, vertical: true).lineSpacing(2.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 15)
    }
}

struct SettingsPage: View {
    @EnvironmentObject var model: AppModel
    @State private var name = ""
    @State private var showUninstall = false
    @State private var hoverUninstall = false
    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isReady: Bool { if case .ready = model.phase { return true } else { return false } }
    private var changed: Bool {
        !trimmed.isEmpty && !trimmed.contains("/") && trimmed != "." && trimmed != ".." && trimmed != model.projectsFolderName
    }

    var body: some View {
        PageChrome(title: "Settings") {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 18) {
                    if isReady {
                        renameSection
                        protectionSection
                    } else {
                        emptyState
                    }
                }
                Spacer(minLength: 24)
                uninstallSection
                Spacer().frame(height: 12)
                versionLabel
            }
            .padding(.horizontal, 26).padding(.bottom, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear { name = model.projectsFolderName }
        .onChange(of: model.projectsFolderName) { new in name = new }
    }

    private var renameSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("MEDIA FOLDER").font(.system(size: 10, weight: .semibold)).tracking(1.3).foregroundStyle(Palette.ink30)

            // The field + its explanation, grouped as one card.
            VStack(alignment: .leading, spacing: 11) {
                TextField("Folder name", text: $name)
                    .textFieldStyle(.plain).font(.system(size: 14)).foregroundStyle(Palette.ink)
                    .fieldStyle()
                    .onSubmit { if changed { model.renameProjectsFolder(to: trimmed) } }
                Text("The folder on \(model.volumeName.isEmpty ? "your drive" : model.volumeName) that holds every project's media. Avid never sees this name; it reads through the link.")
                    .font(.system(size: 11)).foregroundStyle(Palette.ink45)
                    .fixedSize(horizontal: false, vertical: true).lineSpacing(1.5)
            }
            .padding(15)
            .cardStyle()

            PrimaryButton(title: "Rename folder", enabled: changed) {
                model.renameProjectsFolder(to: trimmed)
            }

            if changed {
                Button(action: { name = model.projectsFolderName }) {
                    Text("Reset").font(.system(size: 11)).foregroundStyle(Palette.ink45)
                }
                .buttonStyle(PressableStyle()).frame(maxWidth: .infinity)
            }
        }
    }

    private var protectionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PROTECTION").font(.system(size: 10, weight: .semibold)).tracking(1.3).foregroundStyle(Palette.ink30)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Lock the media folder").font(.system(size: 13, weight: .medium))
                        .foregroundStyle(model.folderLockAvailable ? Palette.ink : Palette.ink45)
                    Text(model.folderLockAvailable
                         ? "Stops \(model.projectsFolderName) from being renamed or deleted by accident in Finder."
                         : "Not available on this drive's format. exFAT and FAT have no folder-level locking; Symly works normally otherwise.")
                        .font(.system(size: 11)).foregroundStyle(Palette.ink45)
                        .fixedSize(horizontal: false, vertical: true).lineSpacing(1.5)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: Binding(get: { model.protectProjectsFolder && model.folderLockAvailable },
                                         set: { model.setProtection($0) }))
                    .labelsHidden().toggleStyle(.switch).tint(Palette.accent)
                    .disabled(!model.folderLockAvailable)
            }
            .padding(15)
            .cardStyle()
        }
    }

    // A quiet, low-emphasis destructive trigger: small muted text, tucked at the
    // bottom and separated from the settings. The weight (red button, full
    // explanation) lives in the confirmation dialog, not here.
    private var uninstallSection: some View {
        Button(action: { showUninstall = true }) {
            Text("Uninstall Symly…")
                .font(.system(size: 11.5))
                .foregroundStyle(hoverUninstall ? Color(hex: 0xE5736A) : Palette.ink30)
        }
        .buttonStyle(PressableStyle())
        .frame(maxWidth: .infinity)
        .onHover { hoverUninstall = $0 }
        .animation(.easeOut(duration: 0.15), value: hoverUninstall)
        .confirmationDialog("Uninstall Symly?", isPresented: $showUninstall, titleVisibility: .visible) {
            Button("Uninstall Symly", role: .destructive) { model.uninstall() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Symly's link and lock are removed from this drive and the app moves to the Trash. Your media and Symly Media folders stay exactly as they are. Drives that aren't connected keep their link until you reconnect them.")
        }
    }

    // App version, read from the bundle so it tracks make-app.sh's
    // CFBundleShortVersionString (falls back when run outside the .app bundle).
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    private var versionLabel: some View {
        Text("Symly \(appVersion)")
            .font(.system(size: 10)).foregroundStyle(Palette.ink30)
            .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Image(systemName: "externaldrive.badge.questionmark").font(.system(size: 26)).foregroundStyle(Palette.ink30)
            Text("Nothing to set yet")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink55)
            Text("Choose and set up a drive first. Then you can rename its media folder here.")
                .font(.system(size: 11.5)).foregroundStyle(Palette.ink45)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity).padding(.top, 40).padding(.horizontal, 10)
    }
}

// MARK: - Sheets

struct NewProjectSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New media folder").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
            Text("A named folder for this project's media. Once it is the active media folder, Avid writes here as you import. You can also copy existing MXF media in, kept in the numbered 1, 2, 3 folders Avid scans.")
                .font(.system(size: 11)).foregroundStyle(Palette.ink55).fixedSize(horizontal: false, vertical: true)
            TextField("e.g. HBO_Media", text: $name.spaceless)
                .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Palette.ink).fieldStyle().onSubmit(create)
            Text("Spaces become underscores.")
                .font(.system(size: 10)).foregroundStyle(Palette.ink30)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.plain).foregroundStyle(Palette.ink55)
                Button(action: create) {
                    Text("Create").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 9).background(RoundedRectangle(cornerRadius: 9).fill(trimmed.isEmpty ? Palette.fieldFill : Palette.accent))
                }.buttonStyle(PressableStyle()).disabled(trimmed.isEmpty)
            }
        }
        .padding(20).frame(width: 360).background(SheetBackground())
    }
    private func create() {
        guard !trimmed.isEmpty else { return }
        if model.createProject(named: trimmed) { dismiss() }
    }
}
