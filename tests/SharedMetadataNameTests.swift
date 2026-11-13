import Foundation
import XCTest
@testable import GestaltX

final class SharedMetadataNameTests: XCTestCase {
    struct Failure: Error { let message: String }

    func testSharedMetadataName() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("GestaltX-share-names-" + UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let inbox = try SharedPlistInbox(container: root, namespace: "test")
        let bytes = try PropertyListSerialization.data(fromPropertyList: ["CacheExtra": ["fixture": true]], format: .binary, options: 0)
        let family = "👩‍👩‍👦‍👦"
        let names = [String(repeating: family, count: 200),
                     "a" + String(repeating: "\u{0301}", count: 4096),
                     String(repeating: "\\\"", count: 200),
                     "../../usual\n-name.plist", "\n\r\t"]
        for name in names {
            let entry = try inbox.enqueue(bytes, name: name)
            XCTAssert(try inbox.entries().contains { $0.id == entry.id },
                       "Every successfully published name must be visible to the metadata reader")
            XCTAssert(try inbox.read(entry) == bytes, "Name truncation must not affect the document")
            let metadata = inbox.directory.appendingPathComponent(entry.id.uuidString).appendingPathComponent("entry.json")
            XCTAssert(try Data(contentsOf: metadata).count <= 4096, "Metadata must obey its read limit")
            XCTAssert(entry.name.utf8.count <= 1024, "Display names have a UTF-8 budget")
            XCTAssert(!entry.name.isEmpty && entry.name.count <= 200, "Keep a bounded, nonempty display name")
        }
        let ordinary = try inbox.enqueue(bytes, name: "ordinary.plist")
        XCTAssert(ordinary.name == "ordinary.plist", "Ordinary filenames are unchanged")
        let emoji = try inbox.enqueue(bytes, name: String(repeating: family, count: 200))
        XCTAssert(emoji.name.allSatisfy { String($0) == family }, "Never split a composed character")
    }
}
