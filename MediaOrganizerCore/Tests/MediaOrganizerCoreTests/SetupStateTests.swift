import XCTest
@testable import MediaOrganizerCore

final class SetupStateTests: XCTestCase {

    private let fm = FileManager.default
    private let engine = SymlinkEngine()
    private let store = ProjectStore()

    private func makeWorkspace() throws -> Workspace {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "mxfsetup-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? self.fm.removeItem(at: root) }
        return Workspace(root: root)
    }

    func testFreshWhenNothingExists() throws {
        let ws = try makeWorkspace()
        XCTAssertEqual(engine.setupState(ws), .fresh)
    }

    func testConfiguredAfterSetup() throws {
        let ws = try makeWorkspace()
        try store.createProject(named: "Show", in: ws)
        try engine.apply(engine.planSwitch(to: "Show", in: ws))
        XCTAssertEqual(engine.setupState(ws), .configured(active: "Show"))
    }

    func testNeedsAdoptionWithMedia() throws {
        let ws = try makeWorkspace()
        let file = ws.mxfLink.appending(path: "1").appending(path: "clip.mxf")
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "media".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(engine.setupState(ws), .needsAdoption(hasMedia: true))
    }

    func testNeedsAdoptionWhenEmpty() throws {
        let ws = try makeWorkspace()
        try fm.createDirectory(at: ws.mxfLink, withIntermediateDirectories: true)
        XCTAssertEqual(engine.setupState(ws), .needsAdoption(hasMedia: false))
    }

    // The link was deleted but projects still exist: the drive is set up, so the
    // user should land on the main panel to reconnect (active: nil), not "fresh".
    func testReconnectWhenLinkRemovedButProjectsExist() throws {
        let ws = try makeWorkspace()
        try store.createProject(named: "Show", in: ws)
        try engine.apply(engine.planSwitch(to: "Show", in: ws))
        try fm.removeItem(at: ws.mxfLink)   // delete just the MXF symlink
        XCTAssertEqual(engine.setupState(ws), .configured(active: nil))
    }

    // An empty projects folder (no project subdirectories) is still fresh.
    func testFreshWhenProjectsFolderEmpty() throws {
        let ws = try makeWorkspace()
        try fm.createDirectory(at: ws.projectsRoot, withIntermediateDirectories: true)
        XCTAssertEqual(engine.setupState(ws), .fresh)
    }

    // A custom projects-folder name round-trips: it is recoverable from the link.
    func testConfiguredProjectsFolderDerivedFromLink() throws {
        let base = try makeWorkspace()
        let custom = Workspace(root: base.root, projectsFolderName: "Iben Media")
        try store.createProject(named: "Show", in: custom)
        try engine.apply(engine.planSwitch(to: "Show", in: custom))
        XCTAssertEqual(engine.configuredProjectsFolder(root: base.root), "Iben Media")
    }
}
