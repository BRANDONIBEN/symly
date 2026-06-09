import Foundation

/// A read-only snapshot of the MXF link's health, for the UI to render.
public struct LinkHealth: Equatable, Sendable {
    public let state: MXFLinkState
    /// The active project's name, derived when the link points under the
    /// app-owned projects root.
    public let activeProject: String?
    /// False when the link is dangling, typically the drive is unplugged.
    public let targetResolves: Bool

    public init(state: MXFLinkState, activeProject: String?, targetResolves: Bool) {
        self.state = state
        self.activeProject = activeProject
        self.targetResolves = targetResolves
    }
}

/// Reports on the current link without changing anything. Drives the
/// "active project" indicator and the "drive not connected" warning.
public struct LinkValidator: Sendable {
    private var fm: FileManager { .default }
    private let engine = SymlinkEngine()

    public init() {}

    public func health(of ws: Workspace) -> LinkHealth {
        let state = engine.currentState(ws)
        guard case let .symlink(target) = state else {
            return LinkHealth(state: state, activeProject: nil, targetResolves: false)
        }
        return LinkHealth(
            state: state,
            activeProject: ws.projectName(forResolvedTarget: target),
            targetResolves: fm.fileExists(atPath: target.path)
        )
    }
}
