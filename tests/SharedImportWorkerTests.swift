import Foundation
import XCTest
@testable import GestaltX

private actor Started {
    private var ready = false
    private var waiting: CheckedContinuation<Void, Never>?
    func wait() async {
        if ready { return }
        await withCheckedContinuation { waiting = $0 }
    }
    func signal() { ready = true; waiting?.resume(); waiting = nil }
}

private final class MainQueueCoordinator: NSFileCoordinator, @unchecked Sendable {
    let replacement: URL
    private(set) var leftMainThread = false
    private(set) var mainQueueProgressed = false
    init(_ replacement: URL) { self.replacement = replacement; super.init(filePresenter: nil) }

    override func coordinate(readingItemAt url: URL, options: NSFileCoordinator.ReadingOptions,
                             error: NSErrorPointer, byAccessor reader: (URL) -> Void) {
        leftMainThread = !Thread.isMainThread
        let callback = DispatchSemaphore(value: 0)
        DispatchQueue.main.async { callback.signal() }
        mainQueueProgressed = callback.wait(timeout: .now() + 5) == .success
        reader(replacement)
        // A coordinated URL can be temporary; reading after the accessor exits
        // would now fail instead of returning the captured document bytes.
        try? FileManager.default.removeItem(at: replacement)
    }
}

private final class WaitingCoordinator: NSFileCoordinator, @unchecked Sendable {
    let started = Started()
    private let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var cancelled = false
    private(set) var entered = false
    private(set) var accessed = false

    override func coordinate(readingItemAt url: URL, options: NSFileCoordinator.ReadingOptions,
                             error: NSErrorPointer, byAccessor reader: (URL) -> Void) {
        entered = true
        Task { await started.signal() }
        _ = release.wait(timeout: .now() + 5)
        lock.lock(); let cancelled = self.cancelled; lock.unlock()
        if cancelled { error?.pointee = NSError(domain: NSCocoaErrorDomain, code: CocoaError.userCancelled.rawValue); return }
        accessed = true
        reader(url)
    }
    override func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
        release.signal()
    }
}

final class SharedImportWorkerTests: XCTestCase {
    struct Failure: Error { let message: String }

    @MainActor func testSharedImportWorker() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("GestaltX-import-worker-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let bytes = try PropertyListSerialization.data(fromPropertyList: ["CacheExtra": ["fixture": true]], format: .binary, options: 0)
        let supplied = root.appendingPathComponent("temporary.plist")
        try bytes.write(to: supplied)
        let coordinator = MainQueueCoordinator(supplied)
        let result = try await SharedPlistInbox.readDocumentAsync(at: root.appendingPathComponent("placeholder.plist"), coordinator: coordinator)
        XCTAssert(coordinator.leftMainThread && coordinator.mainQueueProgressed,
                   "The main queue must keep running while a coordinated read waits")
        XCTAssert(result == bytes, "Consume the accessor URL while it is valid")

        let source = root.appendingPathComponent("cancel.plist")
        try bytes.write(to: source)
        let waiting = WaitingCoordinator()
        let task = Task { try await SharedPlistInbox.readDocumentAsync(at: source, coordinator: waiting) }
        await waiting.started.wait()
        task.cancel()
        do { _ = try await task.value; throw Failure(message: "Expected cancellation") }
        catch is CancellationError {}
        XCTAssert(!waiting.accessed, "Cancel a pending coordinator without consuming its URL")

        let neverStarted = WaitingCoordinator()
        let cancelled = Task { try await SharedPlistInbox.readDocumentAsync(at: source, coordinator: neverStarted) }
        cancelled.cancel()
        do { _ = try await cancelled.value; throw Failure(message: "Expected cancellation before startup") }
        catch is CancellationError {}
        XCTAssert(!neverStarted.entered, "An already-cancelled import must not begin coordination")

        let inbox = try SharedPlistInbox(container: root, namespace: "test")
        let entry = try inbox.enqueue(bytes, name: "queued.plist")
        let queuedData = try await inbox.readAsync(entry)
        XCTAssert(queuedData == bytes, "Queued reads use the same bounded background worker")
        XCTAssert(try inbox.entries().map(\.id) == [entry.id], "Reading never acknowledges the queued document")
    }
}
