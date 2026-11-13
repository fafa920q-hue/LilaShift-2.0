import Foundation
import XCTest
@testable import GestaltX

final class SharedInboxContainmentTests: XCTestCase {
    struct Failure: Error { let message: String }

    func testSharedInboxContainment() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("GestaltX-inbox-boundaries-" + UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let bytes = try PropertyListSerialization.data(fromPropertyList: ["CacheExtra": ["fixture": true]], format: .binary, options: 0)
        let components = ["GestaltX", "ShareInbox", "test"]
        for level in components.indices {
            let fixture = root.appendingPathComponent(String(level))
            let container = fixture.appendingPathComponent("container")
            let outside = fixture.appendingPathComponent("outside")
            let protected = try SharedPlistInbox(container: outside, namespace: "test")
            let entry = try protected.enqueue(bytes, name: "keep.plist")
            let inbox = try SharedPlistInbox(container: container, namespace: "test")
            var link = container, destination = outside
            for component in components.prefix(level + 1) {
                link.appendPathComponent(component)
                destination.appendPathComponent(component)
            }
            try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createSymbolicLink(at: link, withDestinationURL: destination)
            XCTAssertThrowsError(try inbox.entries(), "Reject a linked ancestor during enumeration")
            XCTAssertThrowsError(try inbox.enqueue(bytes, name: "must-not-publish.plist"), "Reject a linked ancestor before writing")
            XCTAssertThrowsError(try inbox.read(entry), "Reject a linked ancestor before reading")
            XCTAssertThrowsError(try inbox.acknowledge(entry), "Reject a linked ancestor before acknowledgement")
            inbox.reject(entry)
            XCTAssert(try protected.entries().map(\.id) == [entry.id], "Another namespace's entry must remain published")
            XCTAssert(try protected.read(entry) == bytes, "Another namespace's bytes must remain unchanged")
            XCTAssert(try fm.contentsOfDirectory(atPath: protected.directory.path) == [entry.id.uuidString],
                       "No staging or quarantine files may be created outside the inbox")
        }

        let control = try SharedPlistInbox(container: root.appendingPathComponent("healthy"), namespace: "test")
        let first = try control.enqueue(bytes, name: "first.plist")
        let second = try control.enqueue(bytes, name: "second.plist")
        let external = root.appendingPathComponent("external-sentinel")
        try Data("keep".utf8).write(to: external)
        let batch = control.directory.appendingPathComponent(first.id.uuidString)
        try fm.createDirectory(at: batch.appendingPathComponent("extra"), withIntermediateDirectories: false)
        try fm.createSymbolicLink(at: batch.appendingPathComponent("extra/link"), withDestinationURL: external)
        try control.acknowledge(first)
        XCTAssert(try Data(contentsOf: external) == Data("keep".utf8), "Cleanup unlinks nested links without following them")
        XCTAssert(try control.entries().map(\.id) == [second.id], "Acknowledgement removes only its own batch")
        XCTAssert(try control.read(second) == bytes, "Normal queued documents remain readable")
        control.reject(second)
        XCTAssert(try control.entries().isEmpty, "Quarantine still removes the selected entry from enumeration")
    }
}
