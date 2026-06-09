import XCTest
@testable import MediaOrganizerCore

/// These tests are the executable form of the "never delete media, ever"
/// promise. They run against throwaway temp directories.
final class SymlinkEngineTests: XCTestCase {

    private let fm = FileManager.default
    private let engine = SymlinkEngine()

    /// A workspace with two projects (ProjectA, ProjectB), each holding a real
    /// `MXF/1/<name>_clip.mxf`, and an empty `Avid MediaFiles`.
    private func makeWorkspace() throws -> Workspace {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "mxfcore-\(UUID().uuidString)")
        for p in ["ProjectA", "ProjectB"] {
            let mxf1 = root.appending(path: "Symly Media")
                .appending(path: p).appending(path: "MXF").appending(path: "1")
            try fm.createDirectory(at: mxf1, withIntermediateDirectories: true)
            try "media-\(p)".write(to: mxf1.appending(path: "\(p)_clip.mxf"),
                                   atomically: true, encoding: .utf8)
        }
        try fm.createDirectory(at: root.appending(path: "Avid MediaFiles"),
                               withIntermediateDirectories: true)
        addTeardownBlock { try? self.fm.removeItem(at: root) }
        return Workspace(root: root)
    }

    private func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    // I1 + happy path: create, then repoint; media reads through the link.
    func testSwitchCreatesAndRepointsSymlink() throws {
        let ws = try makeWorkspace()

        try engine.apply(engine.planSwitch(to: "ProjectA", in: ws))
        guard case let .symlink(t1) = engine.currentState(ws) else {
            return XCTFail("expected a symlink after switching to A")
        }
        XCTAssertTrue(t1.path.hasSuffix("ProjectA/MXF"))
        let viaLinkA = ws.mxfLink.appending(path: "1").appending(path: "ProjectA_clip.mxf")
        XCTAssertEqual(try read(viaLinkA), "media-ProjectA")

        try engine.apply(engine.planSwitch(to: "ProjectB", in: ws))
        guard case let .symlink(t2) = engine.currentState(ws) else {
            return XCTFail("expected a symlink after switching to B")
        }
        XCTAssertTrue(t2.path.hasSuffix("ProjectB/MXF"))
        let viaLinkB = ws.mxfLink.appending(path: "1").appending(path: "ProjectB_clip.mxf")
        XCTAssertEqual(try read(viaLinkB), "media-ProjectB")
    }

    // I3: a real folder at the rigid path is never overwritten, and survives.
    func testRefusesToOverwriteRealDirectory() throws {
        let ws = try makeWorkspace()
        let realFile = ws.mxfLink.appending(path: "1").appending(path: "real.mxf")
        try fm.createDirectory(at: realFile.deletingLastPathComponent(),
                               withIntermediateDirectories: true)
        try "PRECIOUS".write(to: realFile, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try engine.planSwitch(to: "ProjectA", in: ws)) { err in
            guard let se = err as? SafetyError, case .wouldOverwriteRealDirectory = se else {
                return XCTFail("expected wouldOverwriteRealDirectory, got \(err)")
            }
        }
        XCTAssertEqual(try read(realFile), "PRECIOUS", "real media must be untouched")
    }

    // I1 at the executor: removeSymlink refuses a real directory.
    func testRemoveSymlinkGuardRefusesRealDirectory() throws {
        let ws = try makeWorkspace()
        let realFile = ws.mxfLink.appending(path: "real.mxf")
        try fm.createDirectory(at: ws.mxfLink, withIntermediateDirectories: true)
        try "x".write(to: realFile, atomically: true, encoding: .utf8)

        let badPlan = LinkPlan(operations: [.removeSymlink(ws.mxfLink)], summary: "hand-built")
        XCTAssertThrowsError(try engine.apply(badPlan)) { err in
            guard let se = err as? SafetyError, case .refusedNonSymlinkRemoval = se else {
                return XCTFail("expected refusedNonSymlinkRemoval, got \(err)")
            }
        }
        XCTAssertTrue(fm.fileExists(atPath: realFile.path), "the folder must survive")
    }

    // I3 + I6 + I7: adopt relocates real media (rename) and links to it; the
    // exact bytes survive and are reachable through the new symlink.
    func testAdoptMovesNotCopiesAndLinks() throws {
        let ws = try makeWorkspace()
        let origFile = ws.mxfLink.appending(path: "1").appending(path: "real.mxf")
        try fm.createDirectory(at: origFile.deletingLastPathComponent(),
                               withIntermediateDirectories: true)
        try "ORIGINAL".write(to: origFile, atomically: true, encoding: .utf8)

        try engine.apply(engine.planAdopt(as: "Show1", in: ws))

        guard case .symlink = engine.currentState(ws) else {
            return XCTFail("MXF should be a symlink after adoption")
        }
        let viaLink = ws.mxfLink.appending(path: "1").appending(path: "real.mxf")
        XCTAssertEqual(try read(viaLink), "ORIGINAL", "media reachable through the link")
        let physical = ws.projectMXF("Show1").appending(path: "1").appending(path: "real.mxf")
        XCTAssertTrue(fm.fileExists(atPath: physical.path), "media physically under the project")
    }

    // A project folder that has no MXF subfolder yet (e.g. made by hand): switch
    // creates the empty MXF and links it, rather than erroring.
    func testSwitchToEmptyProjectCreatesMXFAndLinks() throws {
        let ws = try makeWorkspace()
        let empty = ws.projectsRoot.appending(path: "Netflix_Media")
        try fm.createDirectory(at: empty, withIntermediateDirectories: true)
        XCTAssertFalse(fm.fileExists(atPath: ws.projectMXF("Netflix_Media").path))

        try engine.apply(engine.planSwitch(to: "Netflix_Media", in: ws))

        guard case let .symlink(target) = engine.currentState(ws) else {
            return XCTFail("expected a symlink")
        }
        XCTAssertTrue(target.path.hasSuffix("Netflix_Media/MXF"))
        XCTAssertTrue(fm.fileExists(atPath: ws.projectMXF("Netflix_Media").path),
                      "the empty MXF folder should have been created")
    }

    // The project folder itself missing (drive gone) still errors clearly.
    func testSwitchToMissingTargetThrows() throws {
        let ws = try makeWorkspace()
        XCTAssertThrowsError(try engine.planSwitch(to: "Nope", in: ws)) { err in
            guard let se = err as? SafetyError, case .targetDoesNotExist = se else {
                return XCTFail("expected targetDoesNotExist, got \(err)")
            }
        }
    }

    // Renaming the projects folder moves it (rename) and follows the link.
    func testRenameProjectsFolderMovesAndRelinks() throws {
        let ws = try makeWorkspace()
        try engine.apply(engine.planSwitch(to: "ProjectA", in: ws))

        try engine.apply(engine.planRenameProjectsFolder(in: ws, to: "Studio Media"))

        let renamed = Workspace(root: ws.root, projectsFolderName: "Studio Media")
        XCTAssertFalse(fm.fileExists(atPath: ws.projectsRoot.path), "old folder gone")
        let movedClip = renamed.projectMXF("ProjectA").appending(path: "1").appending(path: "ProjectA_clip.mxf")
        XCTAssertEqual(try read(movedClip), "media-ProjectA", "media moved intact")
        XCTAssertEqual(engine.configuredProjectsFolder(root: ws.root), "Studio Media")
        let viaLink = ws.mxfLink.appending(path: "1").appending(path: "ProjectA_clip.mxf")
        XCTAssertEqual(try read(viaLink), "media-ProjectA", "link follows the renamed folder")
    }

    // Relative targets: the link keeps resolving after the whole drive is
    // remounted at a different path (simulated by moving the root). An absolute
    // target would dangle here.
    func testLinkIsRelativeAndSurvivesRemount() throws {
        let ws = try makeWorkspace()
        try engine.apply(engine.planSwitch(to: "ProjectA", in: ws))

        // The stored link must not bake in the original mount path.
        let raw = try fm.destinationOfSymbolicLink(atPath: ws.mxfLink.path)
        XCTAssertFalse(raw.hasPrefix("/"), "link target should be drive-relative, got \(raw)")

        // Simulate a remount: move the entire root to a new location.
        let newRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "mxfcore-remounted-\(UUID().uuidString)")
        try fm.moveItem(at: ws.root, to: newRoot)
        addTeardownBlock { try? self.fm.removeItem(at: newRoot) }
        let moved = Workspace(root: newRoot)

        let health = LinkValidator().health(of: moved)
        XCTAssertTrue(health.targetResolves, "relative link should resolve after remount")
        XCTAssertEqual(health.activeProject, "ProjectA")
        let viaLink = moved.mxfLink.appending(path: "1").appending(path: "ProjectA_clip.mxf")
        XCTAssertEqual(try read(viaLink), "media-ProjectA",
                       "media still reachable through the relative link after remount")
    }

    // The atomic repoint refuses to replace a real directory (defense in depth),
    // even when handed a hand-built plan.
    func testRepointRefusesRealDirectory() throws {
        let ws = try makeWorkspace()
        let real = ws.mxfLink.appending(path: "keep.mxf")
        try fm.createDirectory(at: ws.mxfLink, withIntermediateDirectories: true)
        try "KEEP".write(to: real, atomically: true, encoding: .utf8)

        let plan = LinkPlan(
            operations: [.repointSymlink(at: ws.mxfLink, target: ws.projectMXF("ProjectA"))],
            summary: "hand-built")
        XCTAssertThrowsError(try engine.apply(plan)) { err in
            guard let se = err as? SafetyError, case .wouldOverwriteRealDirectory = se else {
                return XCTFail("expected wouldOverwriteRealDirectory, got \(err)")
            }
        }
        XCTAssertEqual(try read(real), "KEEP", "real media must be untouched")
    }

    // The volume-support probe passes on a normal (APFS/HFS+) temp volume.
    func testVolumeSupportOKOnTempVolume() throws {
        let ws = try makeWorkspace()
        XCTAssertEqual(engine.checkVolumeSupport(ws), .ok)
    }

    // Active-project detection is case- and normalization-insensitive, so a
    // case-insensitive drive does not read a healthy link as "no project".
    func testActiveProjectMatchesCaseInsensitively() throws {
        let ws = try makeWorkspace()
        let lowercased = ws.root.appending(path: "symly media")
            .appending(path: "ProjectA").appending(path: "MXF")
        XCTAssertEqual(ws.projectName(forResolvedTarget: lowercased), "ProjectA")
    }

    // Every name that becomes a folder is validated; traversal and separators
    // are rejected before any filesystem work happens.
    func testInvalidProjectNameThrows() throws {
        let ws = try makeWorkspace()
        for bad in ["../evil", "a/b", "", "   ", ".", ".."] {
            XCTAssertThrowsError(try engine.planSwitch(to: bad, in: ws),
                                 "should reject \(bad.debugDescription)") { err in
                guard let pe = err as? ProjectError, case .invalidName = pe else {
                    return XCTFail("expected ProjectError.invalidName for \(bad.debugDescription), got \(err)")
                }
            }
        }
    }

    // A real MXF folder holding only macOS cruft (.DS_Store) reports no media.
    func testAdoptionFolderWithOnlyHiddenFilesReadsAsEmpty() throws {
        let ws = try makeWorkspace()
        try fm.createDirectory(at: ws.mxfLink, withIntermediateDirectories: true)
        try "x".write(to: ws.mxfLink.appending(path: ".DS_Store"),
                      atomically: true, encoding: .utf8)
        guard case let .needsAdoption(hasMedia) = engine.setupState(ws) else {
            return XCTFail("expected needsAdoption")
        }
        XCTAssertFalse(hasMedia, ".DS_Store-only folder should not count as holding media")
    }

    // Deleting the MXF symlink (in Finder) never touches media and the link can
    // be re-established. The drive reads as configured (reconnect), not fresh.
    func testDeletingLinkLeavesMediaAndAllowsRelink() throws {
        let ws = try makeWorkspace()
        try engine.apply(engine.planSwitch(to: "ProjectA", in: ws))

        try fm.removeItem(at: ws.mxfLink)
        XCTAssertEqual(engine.currentState(ws), .missing)
        XCTAssertEqual(engine.setupState(ws), .configured(active: nil))

        let clip = ws.projectMXF("ProjectA").appending(path: "1").appending(path: "ProjectA_clip.mxf")
        XCTAssertEqual(try read(clip), "media-ProjectA", "media untouched after deleting the link")

        try engine.apply(engine.planSwitch(to: "ProjectA", in: ws))
        XCTAssertEqual(LinkValidator().health(of: ws).activeProject, "ProjectA")
    }

    // Deleting the whole Avid MediaFiles folder is recoverable: re-linking
    // recreates the parent and restores access; media is intact.
    func testDeletingAvidMediaFilesFolderAllowsRelink() throws {
        let ws = try makeWorkspace()
        try engine.apply(engine.planSwitch(to: "ProjectB", in: ws))

        try fm.removeItem(at: ws.avidMediaFiles)
        XCTAssertEqual(engine.currentState(ws), .missing)

        try engine.apply(engine.planSwitch(to: "ProjectB", in: ws))
        guard case .symlink = engine.currentState(ws) else { return XCTFail("expected a symlink") }
        let viaLink = ws.mxfLink.appending(path: "1").appending(path: "ProjectB_clip.mxf")
        XCTAssertEqual(try read(viaLink), "media-ProjectB")
    }

    // Launch -> switch -> quit -> relaunch: a fresh engine over the same drive
    // re-derives the active project entirely from the on-disk link.
    func testRelaunchRederivesActiveProjectFromDisk() throws {
        let ws = try makeWorkspace()
        try engine.apply(engine.planSwitch(to: "ProjectA", in: ws))

        let fresh = SymlinkEngine()
        let reopened = Workspace(root: ws.root)
        XCTAssertEqual(fresh.setupState(reopened), .configured(active: "ProjectA"))
        XCTAssertEqual(fresh.configuredProjectsFolder(root: ws.root), "Symly Media")
    }

    // Multiple drives, each configured independently with its own link and its
    // own (even differently-named) projects folder, never interfere. Each link
    // resolves to ITS OWN media; switching one leaves the other untouched.
    func testMultipleDrivesStayIndependent() throws {
        let driveA = try makeWorkspace()   // default "Symly Media"

        // A second, separate drive with a different projects-folder name.
        let rootB = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "mxfcore-B-\(UUID().uuidString)")
        for p in ["ProjectA", "ProjectB"] {
            let mxf1 = rootB.appending(path: "Studio Media")
                .appending(path: p).appending(path: "MXF").appending(path: "1")
            try fm.createDirectory(at: mxf1, withIntermediateDirectories: true)
            try "B-\(p)".write(to: mxf1.appending(path: "\(p)_clip.mxf"),
                               atomically: true, encoding: .utf8)
        }
        try fm.createDirectory(at: rootB.appending(path: "Avid MediaFiles"),
                               withIntermediateDirectories: true)
        addTeardownBlock { try? self.fm.removeItem(at: rootB) }
        let driveB = Workspace(root: rootB, projectsFolderName: "Studio Media")

        // Configure each drive independently, to different projects.
        try engine.apply(engine.planSwitch(to: "ProjectA", in: driveA))
        try engine.apply(engine.planSwitch(to: "ProjectB", in: driveB))

        // Each drive reports its own active project and its own folder name.
        XCTAssertEqual(LinkValidator().health(of: driveA).activeProject, "ProjectA")
        XCTAssertEqual(LinkValidator().health(of: driveB).activeProject, "ProjectB")
        XCTAssertEqual(engine.configuredProjectsFolder(root: driveA.root), "Symly Media")
        XCTAssertEqual(engine.configuredProjectsFolder(root: driveB.root), "Studio Media")

        // Each link resolves to media on ITS OWN drive (distinct content).
        XCTAssertEqual(try read(driveA.mxfLink.appending(path: "1").appending(path: "ProjectA_clip.mxf")),
                       "media-ProjectA")
        XCTAssertEqual(try read(driveB.mxfLink.appending(path: "1").appending(path: "ProjectB_clip.mxf")),
                       "B-ProjectB")

        // Switching drive B does not disturb drive A.
        try engine.apply(engine.planSwitch(to: "ProjectA", in: driveB))
        XCTAssertEqual(LinkValidator().health(of: driveA).activeProject, "ProjectA", "drive A untouched")
        XCTAssertEqual(LinkValidator().health(of: driveB).activeProject, "ProjectA")
    }

    // Renaming the projects folder in Finder (bypassing the app) dangles the
    // link: it still names the project, but its target no longer resolves. This
    // is the exact condition the app's "link needs re-establishing" state keys
    // off of (symlink present + activeProject != nil + targetResolves == false).
    // The media itself is untouched under the new folder name.
    func testRenamingProjectsFolderInFinderDanglesLink() throws {
        let ws = try makeWorkspace()
        try engine.apply(engine.planSwitch(to: "ProjectA", in: ws))

        // Simulate a Finder rename of the whole projects folder.
        let renamed = ws.root.appending(path: "My Projects")
        try fm.moveItem(at: ws.projectsRoot, to: renamed)

        let health = LinkValidator().health(of: ws)
        guard case .symlink = health.state else { return XCTFail("link should still be a symlink") }
        XCTAssertEqual(health.activeProject, "ProjectA", "the link still names the project")
        XCTAssertFalse(health.targetResolves, "but its target no longer resolves after the rename")

        // The media is safe under the new folder name.
        let movedClip = renamed.appending(path: "ProjectA").appending(path: "MXF")
            .appending(path: "1").appending(path: "ProjectA_clip.mxf")
        XCTAssertEqual(try read(movedClip), "media-ProjectA", "media untouched, just under a new folder name")
    }

    // Protected-path and same-volume guards.
    func testGuards() throws {
        let ws = try makeWorkspace()
        let g = SafetyGuard()
        XCTAssertThrowsError(try g.assertNotProtected(URL(fileURLWithPath: "/")))
        XCTAssertThrowsError(try g.assertNotProtected(URL(fileURLWithPath: "/Volumes")))
        XCTAssertNoThrow(try g.assertNotProtected(ws.mxfLink))
        XCTAssertNoThrow(try g.assertSameVolume(ws.mxfLink, ws.projectsRoot))
    }
}
