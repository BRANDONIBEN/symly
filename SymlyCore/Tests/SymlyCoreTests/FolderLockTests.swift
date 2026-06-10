import XCTest
@testable import SymlyCore

final class FolderLockTests: XCTestCase {
    private let fm = FileManager.default
    private let lock = FolderLock()

    func testLockBlocksRenameKeepsContentsWritableAndUnlockRestores() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "locktest-\(UUID().uuidString)")
        let folder = root.appending(path: "Symly Media")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock {
            self.lock.unlock(folder)
            try? self.fm.removeItem(at: root)
        }

        XCTAssertFalse(lock.isLocked(folder), "starts unlocked")

        // Lock it.
        XCTAssertTrue(lock.lock(folder))
        XCTAssertTrue(lock.isLocked(folder), "deny-delete ACL is present")

        // Re-locking is idempotent (still reads as locked, no error).
        XCTAssertTrue(lock.lock(folder))
        XCTAssertTrue(lock.isLocked(folder))

        // Renaming the locked folder fails.
        let renamed = root.appending(path: "My Projects")
        XCTAssertThrowsError(try fm.moveItem(at: folder, to: renamed),
                             "a locked folder must not be renamable")

        // ...but its contents are still fully writable (Avid + Symly keep working).
        XCTAssertNoThrow(try "media".write(to: folder.appending(path: "clip.mxf"),
                                           atomically: true, encoding: .utf8))
        XCTAssertNoThrow(try fm.createDirectory(at: folder.appending(path: "NewProject"),
                                                withIntermediateDirectories: true))

        // Unlocking restores rename.
        XCTAssertTrue(lock.unlock(folder))
        XCTAssertFalse(lock.isLocked(folder))
        XCTAssertNoThrow(try fm.moveItem(at: folder, to: renamed))
    }
}
