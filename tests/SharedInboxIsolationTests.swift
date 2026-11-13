import Foundation
import XCTest
@testable import GestaltX

final class SharedInboxIsolationTests: XCTestCase {
    struct Failure: Error { let message: String }

    func testSharedInboxIsolation() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("GestaltX-inbox-isolation-" + UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let bad = try SharedPlistInbox(container: root.appendingPathComponent("bad-group"), namespace: "test")
        let good = try SharedPlistInbox(container: root.appendingPathComponent("good-group"), namespace: "test")
        let missing = try SharedPlistInbox(container: root.appendingPathComponent("missing-group"), namespace: "test")
        try fm.createDirectory(at: bad.directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        let sentinel = Data("The inbox path is a file, not a directory.".utf8)
        try sentinel.write(to: bad.directory)
        let bytes = try PropertyListSerialization.data(fromPropertyList: ["CacheExtra": ["fixture": true]], format: .binary, options: 0)
        let entry = try good.enqueue(bytes, name: "healthy.plist")

        for inboxes in [[bad, good], [good, bad], [missing, bad, good]] {
            let found = try SharedImportQueue.snapshot(in: inboxes)
            XCTAssert(found.count == 1 && found[0].entry.id == entry.id,
                         "An unreadable inbox must not suppress another App Group's valid document")
            XCTAssert(try found[0].inbox.read(found[0].entry) == bytes)
        }
        XCTAssert(try Data(contentsOf: bad.directory) == sentinel,
                     "Fault isolation must not remove or replace the damaged path")
        try good.acknowledge(entry)
        for inboxes in [[bad], [bad, good], [missing, bad]] {
            // The original asserted that snapshot throws a real enumeration
            // error (not the test's own Failure): a successful snapshot, or a
            // Failure-typed throw, must both fail the test.
            XCTAssertThrowsError(try SharedImportQueue.snapshot(in: inboxes)) { error in
                XCTAssertFalse(error is Failure, "An inaccessible remaining inbox must still report its error")
            }
        }
        XCTAssert(try SharedImportQueue.snapshot(in: [good, missing]).isEmpty)
        XCTAssert(try SharedImportQueue.snapshot(in: []).isEmpty)
    }
}
