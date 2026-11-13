import Foundation
import Darwin
import XCTest
@testable import GestaltX

final class SharedPlistInboxTests: XCTestCase {
    func testSharedPlistInbox() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("GestaltX-share-tests-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let group = root.appendingPathComponent("resigned-group")
        let inbox = try SharedPlistInbox(container: group, namespace: "com.example.resigned")
        let other = try SharedPlistInbox(container: group, namespace: "com.example.other")
        let document: [String: Any] = ["CacheExtra": ["string": "hello", "boolean": true, "integer": 1], "CacheData": Data([1, 2, 3])]
        let binary = try PropertyListSerialization.data(fromPropertyList: document, format: .binary, options: 0)
        let xml = try PropertyListSerialization.data(fromPropertyList: document, format: .xml, options: 0)
        let source = root.appendingPathComponent("original.plist")
        try binary.write(to: source)
        let read = try SharedPlistInbox.readDocument(at: source)
        let first = try inbox.enqueue(read, name: "../../original\n.plist")
        XCTAssert(first.name == "original.plist", "Filenames are display metadata and cannot escape the inbox")
        XCTAssert(try inbox.read(first) == binary, "Publish and read exact binary plist bytes")
        XCTAssert(try Data(contentsOf: source) == binary, "Sharing never changes the user's original file")
        XCTAssert(try other.entries().isEmpty, "Different app instances do not consume each other's files")
        // Simulate a cold start after the extension process has already exited.
        let restarted = try SharedPlistInbox(container: group, namespace: "com.example.resigned")
        XCTAssert(try restarted.entries().map(\.id) == [first.id], "Completed handoff survives process restart")
        let second = try restarted.enqueue(xml, name: "same-name.plist")
        let third = try restarted.enqueue(binary, name: "same-name.plist")
        XCTAssert(second.id != third.id && (try restarted.entries().count) == 3, "Duplicate filenames never overwrite queued files")
        XCTAssert(try restarted.read(second) == xml, "XML plist is accepted without converting its values")
        try restarted.acknowledge(first)
        XCTAssert(try restarted.entries().map(\.id) == [second.id, third.id], "Acknowledge removes only the imported entry")
        let staged = restarted.directory.appendingPathComponent(".interrupted.pending")
        try fm.createDirectory(at: staged, withIntermediateDirectories: true)
        try binary.write(to: staged.appendingPathComponent("document.plist"))
        XCTAssert(try restarted.entries().count == 2, "Partial publications are never imported")
        XCTAssertThrowsError(try SharedPlistInbox(container: group, namespace: "../escape"), "Reject a path-traversal namespace")
        XCTAssertThrowsError(try SharedPlistInbox.readDocument(at: URL(string: "https://example.com/test.plist")!), "Reject a non-file URL")
        XCTAssertThrowsError(try inbox.enqueue(Data("hello".utf8), name: "wrong.plist"), "Reject a non-plist")
        let invalid = try PropertyListSerialization.data(fromPropertyList: ["NotMobileGestalt": true], format: .binary, options: 0)
        XCTAssertThrowsError(try inbox.enqueue(invalid, name: "wrong.plist"), "Reject plist without CacheExtra")
        let oversized = root.appendingPathComponent("oversized.plist")
        try Data(repeating: 0, count: SharedPlistInbox.maximumByteCount + 1).write(to: oversized)
        XCTAssertThrowsError(try SharedPlistInbox.readDocument(at: oversized), "Bound the file read before parsing")
        // A damaged published file is rejected, retained, and removed from the
        // automatic queue so it cannot repeatedly replace a current document.
        let secondPayload = restarted.directory.appendingPathComponent(second.id.uuidString).appendingPathComponent("document.plist")
        try Data("corrupt".utf8).write(to: secondPayload)
        XCTAssertThrowsError(try restarted.read(second), "Revalidate a modified queue payload")
        restarted.reject(second)
        XCTAssert(try restarted.entries().map(\.id) == [third.id], "Quarantine a broken entry without blocking the queue")
        let thirdPayload = restarted.directory.appendingPathComponent(third.id.uuidString).appendingPathComponent("document.plist")
        try fm.removeItem(at: thirdPayload)
        try fm.createSymbolicLink(at: thirdPayload, withDestinationURL: source)
        XCTAssertThrowsError(try restarted.read(third), "Reject symlinked queue documents")
        XCTAssert(try Data(contentsOf: source) == binary, "Rejected queue links cannot change the source")
        let special = try SharedPlistInbox(container: group, namespace: "special-files")
        let metadataEntry = try special.enqueue(binary, name: "metadata.plist")
        let metadata = special.directory.appendingPathComponent(metadataEntry.id.uuidString).appendingPathComponent("entry.json")
        let savedMetadata = root.appendingPathComponent("saved-entry.json")
        try fm.moveItem(at: metadata, to: savedMetadata)
        try fm.createSymbolicLink(at: metadata, withDestinationURL: savedMetadata)
        XCTAssert(try special.entries().isEmpty, "Ignore symlinked metadata instead of following it")
        try fm.removeItem(at: metadata)
        let madeFIFO = metadata.withUnsafeFileSystemRepresentation { mkfifo($0!, 0o600) }
        XCTAssert(madeFIFO == 0, "Create a named-pipe metadata fixture")
        XCTAssert(try special.entries().isEmpty, "A metadata FIFO with no writer must not block the inbox scan")
        XCTAssertThrowsError(try SharedPlistInbox.readDocument(at: metadata), "Reject a document FIFO without waiting for a writer")
        XCTAssertThrowsError(try SharedPlistInbox.readDocument(at: root), "Reject directories as documents")
        try fm.removeItem(at: metadata)
        try fm.moveItem(at: savedMetadata, to: metadata)
        XCTAssert(try special.read(metadataEntry) == binary, "Normal documents remain readable after malformed queue entries")
    }
}
