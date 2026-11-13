import Foundation
import XCTest
@testable import GestaltX

private final class CatalogFixture: @unchecked Sendable {
    private let lock = NSLock()
    var inventory: LaunchArtworkInventory
    private var probes: [String] = []
    var retry = Set<String>()
    init(_ inventory: LaunchArtworkInventory) { self.inventory = inventory }
    func snapshot(_ discover: Bool) -> LaunchArtworkInventory { lock.lock(); defer { lock.unlock() }; return inventory }
    func verify(_ candidate: LaunchArtworkCandidate) -> LaunchArtworkAvailability {
        lock.lock(); probes.append(candidate.app.id); let retryable = retry.contains(candidate.app.id); lock.unlock()
        if candidate.app.byteCount >= 100 { Thread.sleep(forTimeInterval: 0.04) }
        return .init(available: !retryable, retryable: retryable)
    }
    func update(_ next: LaunchArtworkInventory, retry: Set<String> = []) { lock.lock(); defer { lock.unlock() }; inventory = next; self.retry = retry }
    func reset() { lock.lock(); defer { lock.unlock() }; probes = [] }
    var counts: [String] { lock.lock(); defer { lock.unlock() }; return probes }
    var backend: LaunchArtworkCatalogStore.Backend { .init(inventory: { self.snapshot($0) }, verify: { self.verify($0) }) }
}

final class LaunchArtworkCatalogTests: XCTestCase {
    func expect(_ condition: Bool, _ message: String) {
        XCTAssert(condition, message)
    }
    func candidate(_ id: String, size: Int64, generation: String = "1") -> LaunchArtworkCandidate {
        .init(app: .init(id: "test.\(id)", name: id, byteCount: size), generation: generation, container: "/owned/\(id)")
    }
    func collect(_ store: LaunchArtworkCatalogStore, force: Bool = false) async -> [LaunchArtworkApp] {
        var rows: [LaunchArtworkApp] = []
        for await event in store.events(force: force) {
            switch event {
            case .snapshot(let cached): rows = cached
            case .upsert(let app): LaunchArtworkAppOrder.upsert(app, in: &rows)
            case .remove(let id): rows.removeAll { $0.id == id }
            }
        }
        return rows
    }
    func testLaunchArtworkCatalog() async throws {
        let fm = FileManager.default, root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let small = candidate("small", size: 10), large = candidate("large", size: 100), unknown = candidate("unknown", size: 0)
        let fixture = CatalogFixture(.init(complete: true, candidates: [large, unknown, small], containerGeneration: "root-1"))
        let store = LaunchArtworkCatalogStore(storage: root, device: "device", backend: fixture.backend)
        var streamed: [String] = []
        for await event in store.events() {
            if case .upsert(let app) = event { streamed.append(app.id) }
        }
        expect(streamed == [small.app.id, large.app.id, unknown.app.id], "Rows were not emitted individually in ascending app-size order")
        expect(fixture.counts == streamed, "Verification order differed from stream order")
        fixture.reset()
        let reopened = LaunchArtworkCatalogStore(storage: root, device: "device", backend: fixture.backend)
        let cache = await reopened.cached()
        expect(cache.map(\.id) == streamed && cache.map(\.name) == ["small", "large", "unknown"], "Names/order did not survive reopening")
        let unchanged = await collect(reopened)
        expect(unchanged.map(\.id) == streamed && fixture.counts.isEmpty, "Unchanged apps were scanned again")

        fixture.reset()
        let middle = candidate("middle", size: 20), changedLarge = candidate("large", size: 100, generation: "2")
        fixture.update(.init(complete: true, candidates: [unknown, changedLarge, middle], containerGeneration: "root-2"))
        let delta = await collect(reopened)
        expect(delta.map(\.id) == [middle.app.id, large.app.id, unknown.app.id], "Install/uninstall delta was not merged into cached rows")
        expect(fixture.counts == [middle.app.id, large.app.id], "Incremental refresh scanned unchanged apps")

        fixture.reset()
        let unavailable = candidate("large", size: 100, generation: "3")
        fixture.update(.init(complete: false, candidates: [unavailable], containerGeneration: "root-2"), retry: [large.app.id])
        let partial = await collect(reopened)
        expect(Set(partial.map(\.id)) == Set(delta.map(\.id)), "A temporary/partial inventory erased cached apps")
        let foreign = LaunchArtworkCatalogStore(storage: root, device: "another-device", backend: fixture.backend)
        expect(await foreign.cached().isEmpty, "Catalog cache leaked across device identities")

        var sorted: [LaunchArtworkApp] = []
        LaunchArtworkAppOrder.upsert(large.app, in: &sorted); LaunchArtworkAppOrder.upsert(small.app, in: &sorted)
        LaunchArtworkAppOrder.upsert(.init(id: large.app.id, name: "large", byteCount: 1), in: &sorted)
        expect(sorted.map(\.id) == [large.app.id, small.app.id], "An updated row duplicated instead of moving to its new size position")
    }
    func testAppAppearanceResearchPreviewFailsClosed() {
        let proposal = AppAppearanceProposal(bundleID: "com.tencent.xin", currentName: "微信", proposedName: "WX")
        XCTAssertEqual(proposal.check, .previewOnly)
        XCTAssertFalse(proposal.canApplyNatively, "A preview may never claim native editing succeeded")

        let whitespace = AppAppearanceProposal(bundleID: "com.tencent.xin", currentName: "微信", proposedName: "   ")
        XCTAssertEqual(whitespace.check, .invalidName)

        let tooLong = AppAppearanceProposal(bundleID: "com.tencent.xin", currentName: "微信",
                                            proposedName: String(repeating: "A", count: 33))
        XCTAssertEqual(tooLong.check, .invalidName)

        let invalidID = AppAppearanceProposal(bundleID: "../invalid", currentName: "微信", proposedName: "WX")
        XCTAssertEqual(invalidID.check, .invalidIdentifier)

        let controls = AppAppearanceProposal(bundleID: "com.tencent.xin", currentName: "微信", proposedName: "WX\\nBad")
        XCTAssertEqual(controls.check, .invalidName)
    }

}
