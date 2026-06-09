import XCTest
@testable import MediaOrganizerCore

final class ProjectStoreTests: XCTestCase {

    private let fm = FileManager.default
    private let store = ProjectStore()
    private let engine = SymlinkEngine()
    private let validator = LinkValidator()

    private func makeEmptyWorkspace() throws -> Workspace {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "mxfproj-\(UUID().uuidString)")
        try fm.createDirectory(at: root.appending(path: "Avid MediaFiles"),
                               withIntermediateDirectories: true)
        addTeardownBlock { try? self.fm.removeItem(at: root) }
        return Workspace(root: root)
    }

    func testCreateAndListSorted() throws {
        let ws = try makeEmptyWorkspace()
        XCTAssertTrue(store.projects(in: ws).isEmpty)
        try store.createProject(named: "HBO_Media", in: ws)
        try store.createProject(named: "Disney_Media", in: ws)
        XCTAssertEqual(store.projects(in: ws).map(\.name), ["Disney_Media", "HBO_Media"])
    }

    func testDuplicateAndInvalidNamesRejected() throws {
        let ws = try makeEmptyWorkspace()
        try store.createProject(named: "Show", in: ws)
        XCTAssertThrowsError(try store.createProject(named: "Show", in: ws)) { err in
            guard let pe = err as? ProjectError, case .alreadyExists = pe else {
                return XCTFail("expected alreadyExists, got \(err)")
            }
        }
        for bad in ["", "   ", "a/b", ".", ".."] {
            XCTAssertThrowsError(try store.createProject(named: bad, in: ws),
                                 "name \"\(bad)\" should be rejected")
        }
    }

    // Health derives the active project and flags a dangling link (unplugged).
    func testHealthActiveProjectAndDangling() throws {
        let ws = try makeEmptyWorkspace()
        try store.createProject(named: "A", in: ws)
        try store.createProject(named: "B", in: ws)
        try engine.apply(engine.planSwitch(to: "A", in: ws))

        var h = validator.health(of: ws)
        XCTAssertEqual(h.activeProject, "A")
        XCTAssertTrue(h.targetResolves)

        // Simulate the project's media disappearing (e.g. drive unplugged).
        try fm.removeItem(at: ws.projectMXF("A"))
        h = validator.health(of: ws)
        XCTAssertEqual(h.activeProject, "A", "still derivable from the link path")
        XCTAssertFalse(h.targetResolves, "now dangling")
    }
}
