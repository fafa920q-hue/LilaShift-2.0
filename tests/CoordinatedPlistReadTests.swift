import Foundation
import Darwin
import XCTest
@testable import GestaltX

private final class RedirectingCoordinator: NSFileCoordinator {
    let readableURL: URL
    private(set) var requestedURL: URL?

    init(readableURL: URL) {
        self.readableURL = readableURL
        super.init(filePresenter: nil)
    }

    override func coordinate(readingItemAt url: URL, options: NSFileCoordinator.ReadingOptions,
                             error outError: NSErrorPointer, byAccessor reader: (URL) -> Void) {
        requestedURL = url
        reader(readableURL)
    }
}

private final class FailingCoordinator: NSFileCoordinator {
    let failure = NSError(domain: "CoordinatedPlistReadTests", code: 42)

    override func coordinate(readingItemAt url: URL, options: NSFileCoordinator.ReadingOptions,
                             error outError: NSErrorPointer, byAccessor reader: (URL) -> Void) {
        outError?.pointee = failure
    }
}

final class CoordinatedPlistReadTests: XCTestCase {
    func testCoordinatedPlistRead() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("GestaltX-coordinated-read-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let placeholder = root.appendingPathComponent("not-downloaded.plist")
        let readable = root.appendingPathComponent("materialized.plist")
        let bytes = try PropertyListSerialization.data(fromPropertyList: ["CacheExtra": ["field": "value"]],
                                                        format: .binary, options: 0)
        try bytes.write(to: readable)
        let redirect = RedirectingCoordinator(readableURL: readable)
        let imported = try SharedPlistInbox.readDocument(at: placeholder, coordinator: redirect)
        XCTAssert(redirect.requestedURL == placeholder)
        XCTAssert(imported == bytes, "Read the URL supplied by the coordinator, not the placeholder")
        let local = try SharedPlistInbox.readDocument(at: readable)
        XCTAssert(local == bytes)

        let fifo = root.appendingPathComponent("pipe.plist")
        let madeFIFO = fifo.withUnsafeFileSystemRepresentation { mkfifo($0!, 0o600) }
        XCTAssert(madeFIFO == 0)
        let link = root.appendingPathComponent("link.plist")
        try fm.createSymbolicLink(at: link, withDestinationURL: readable)
        for special in [fifo, root, link] {
            let coordinator = RedirectingCoordinator(readableURL: readable)
            XCTAssertThrowsError(try SharedPlistInbox.readDocument(at: special, coordinator: coordinator)) { error in
                XCTAssertTrue((error as? SharedPlistError)?.key == "The shared plist could not be read. Share it again.")
            }
            XCTAssert(coordinator.requestedURL == nil, "A special file must not reach coordination")
        }
        // Exercise the default coordinator as well: it must never wait for a
        // writer on this real named pipe. The test runner bounds each process.
        XCTAssertThrowsError(try SharedPlistInbox.readDocument(at: fifo)) { error in
            XCTAssertTrue(error is SharedPlistError)
        }

        let failing = FailingCoordinator(filePresenter: nil)
        XCTAssertThrowsError(try SharedPlistInbox.readDocument(at: readable, coordinator: failing)) { error in
            XCTAssertTrue((error as NSError) == failing.failure)
        }
        try Data("invalid".utf8).write(to: readable)
        XCTAssertThrowsError(try SharedPlistInbox.readDocument(at: placeholder, coordinator: redirect)) { error in
            XCTAssertTrue((error as? SharedPlistError)?.key == "Choose a MobileGestalt plist with a CacheExtra dictionary.")
        }
        try Data(repeating: 0, count: SharedPlistInbox.maximumByteCount + 1).write(to: readable)
        XCTAssertThrowsError(try SharedPlistInbox.readDocument(at: placeholder, coordinator: redirect)) { error in
            XCTAssertTrue((error as? SharedPlistError)?.key == "Choose a plist smaller than 16 MB.")
        }
    }
}
