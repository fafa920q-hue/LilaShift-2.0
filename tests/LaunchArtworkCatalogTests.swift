import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
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

        // A real newline is a control character; a literal backslash is not.
        let controls = AppAppearanceProposal(bundleID: "com.tencent.xin", currentName: "微信", proposedName: "WX\nBad")
        XCTAssertEqual(controls.check, .invalidName)
    }

    // MARK: - App Appearance preview: image validation

    private func makePNG(width: Int, height: Int, red: CGFloat = 1, green: CGFloat = 0, blue: CGFloat = 0) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let writer = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(writer, context.makeImage()!, nil)
        XCTAssert(CGImageDestinationFinalize(writer))
        return data as Data
    }

    private func makeJPEG(width: Int, height: Int) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let writer = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(writer, context.makeImage()!, nil)
        XCTAssert(CGImageDestinationFinalize(writer))
        return data as Data
    }

    private func fakeHEICData() -> Data {
        var bytes = Data([0, 0, 0, 24])
        bytes.append(contentsOf: "ftypheic".utf8)
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 64))
        return bytes
    }

    private func decodedSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (width, height)
    }

    func testAppAppearanceImageFormatDetection() {
        XCTAssertEqual(AppAppearanceImageFormat.detect(from: makePNG(width: 8, height: 8)), .png)
        XCTAssertEqual(AppAppearanceImageFormat.detect(from: makeJPEG(width: 8, height: 8)), .jpeg)
        XCTAssertEqual(AppAppearanceImageFormat.detect(from: fakeHEICData()), .heic)
        XCTAssertEqual(AppAppearanceImageFormat.detect(from: Data()), .unsupported)
        XCTAssertEqual(AppAppearanceImageFormat.detect(from: Data("GIF89a".utf8) + Data(repeating: 0, count: 32)), .unsupported)
        XCTAssertEqual(AppAppearanceImageFormat.detect(from: Data("hello".utf8)), .unsupported)
    }

    private func validationError(for data: Data) -> AppAppearanceValidatedImage.ValidationError? {
        switch AppAppearanceValidatedImage.validate(data) {
        case .success: return nil
        case .failure(let error): return error
        }
    }

    func testAppAppearanceImageValidation() {
        XCTAssertEqual(validationError(for: Data()), .empty)
        XCTAssertEqual(validationError(for: Data(count: AppAppearanceValidatedImage.maximumBytes + 1)), .tooLarge)
        XCTAssertEqual(validationError(for: Data("GIF89a".utf8) + Data(repeating: 0, count: 32)), .unsupportedFormat)
        // A HEIC brand is recognised as a supported format, but these
        // bytes are not a real HEIC image, so validation must say
        // undecodable — never "unsupported format".
        XCTAssertEqual(validationError(for: fakeHEICData()), .undecodable)

        let png = makePNG(width: 200, height: 100)
        switch AppAppearanceValidatedImage.validate(png) {
        case .success(let validated):
            XCTAssertEqual(validated.format, .png)
            XCTAssertEqual(validated.width, 200)
            XCTAssertEqual(validated.height, 100)
            XCTAssertEqual(validated.byteCount, png.count)
        case .failure(let error):
            XCTFail("valid PNG rejected: \(error)")
        }

        let jpeg = makeJPEG(width: 100, height: 80)
        switch AppAppearanceValidatedImage.validate(jpeg) {
        case .success(let validated):
            XCTAssertEqual(validated.format, .jpeg)
            XCTAssertEqual(validated.width, 100)
            XCTAssertEqual(validated.height, 80)
        case .failure(let error):
            XCTFail("valid JPEG rejected: \(error)")
        }

        let huge = makePNG(width: 5000, height: 100)
        XCTAssertEqual(validationError(for: huge), .dimensionsTooLarge)
    }

    func testAppAppearanceCropRect() {
        let full = AppAppearanceCrop()
        XCTAssertEqual(full.rect(for: CGSize(width: 200, height: 100)), CGRect(x: 0, y: 0, width: 200, height: 100))

        var square = AppAppearanceCrop()
        square.mode = .square
        XCTAssertEqual(square.rect(for: CGSize(width: 200, height: 100)), CGRect(x: 50, y: 0, width: 100, height: 100))
        XCTAssertEqual(square.rect(for: CGSize(width: 100, height: 200)), CGRect(x: 0, y: 50, width: 100, height: 100))

        var custom = AppAppearanceCrop()
        custom.mode = .custom
        custom.top = 0.1; custom.leading = 0.2; custom.bottom = 0.1; custom.trailing = 0.2
        let rect = custom.rect(for: CGSize(width: 200, height: 100))
        XCTAssertEqual(rect.origin.x, 40, accuracy: 0.001)
        XCTAssertEqual(rect.origin.y, 10, accuracy: 0.001)
        XCTAssertEqual(rect.width, 120, accuracy: 0.001)
        XCTAssertEqual(rect.height, 80, accuracy: 0.001)

        // Insets beyond 0.4 are clamped, and the rect never inverts.
        var clamped = AppAppearanceCrop()
        clamped.mode = .custom
        clamped.leading = 0.9; clamped.trailing = 0.9
        let clampedRect = clamped.rect(for: CGSize(width: 200, height: 100))
        XCTAssertEqual(clampedRect.origin.x, 80, accuracy: 0.001)
        XCTAssertEqual(clampedRect.width, 40, accuracy: 0.001)
        XCTAssertGreaterThan(clampedRect.width, 0)
        XCTAssertGreaterThan(clampedRect.height, 0)
    }

    func testAppAppearanceCroppedThumbnail() throws {
        let png = makePNG(width: 200, height: 100)
        var square = AppAppearanceCrop()
        square.mode = .square
        let squareThumb = try XCTUnwrap(AppAppearanceValidatedImage.croppedThumbnailPNG(from: png, crop: square))
        let squareSize = try XCTUnwrap(decodedSize(of: squareThumb))
        XCTAssertEqual(squareSize.width, 100)
        XCTAssertEqual(squareSize.height, 100)

        let fullThumb = try XCTUnwrap(AppAppearanceValidatedImage.croppedThumbnailPNG(from: png, crop: AppAppearanceCrop()))
        let fullSize = try XCTUnwrap(decodedSize(of: fullThumb))
        XCTAssertEqual(fullSize.width, 200)
        XCTAssertEqual(fullSize.height, 100)

        var custom = AppAppearanceCrop()
        custom.mode = .custom
        custom.top = 0.1; custom.leading = 0.1; custom.bottom = 0.1; custom.trailing = 0.1
        let customThumb = try XCTUnwrap(AppAppearanceValidatedImage.croppedThumbnailPNG(from: png, crop: custom))
        let customSize = try XCTUnwrap(decodedSize(of: customThumb))
        XCTAssertEqual(customSize.width, 160)
        XCTAssertEqual(customSize.height, 80)
    }

    func testAppAppearancePreviewHistoryUndo() {
        var history = AppAppearancePreviewHistory()
        XCTAssertEqual(history.current, .empty)
        XCTAssertFalse(history.canUndo)
        XCTAssertNil(history.undo())

        let first = AppAppearancePreviewState(name: "A")
        history.push(first)
        XCTAssertTrue(history.canUndo)
        XCTAssertEqual(history.current.name, "A")
        let second = AppAppearancePreviewState(name: "B")
        history.push(second)
        XCTAssertEqual(history.current.name, "B")
        XCTAssertEqual(history.undo()?.name, "A")
        XCTAssertEqual(history.current.name, "A")
        XCTAssertEqual(history.undo()?.name, "")
        XCTAssertFalse(history.canUndo)
        XCTAssertNil(history.undo())

        // Pushing an identical state does not grow the stack.
        history.push(.empty)
        XCTAssertFalse(history.canUndo)

        // An in-place update (typing a name) does not add a history entry.
        history.push(first)
        history.updateCurrent { $0.name = "A2" }
        XCTAssertEqual(history.current.name, "A2")
        XCTAssertEqual(history.undo()?.name, "")
        XCTAssertFalse(history.canUndo)

        history.push(first)
        history.reset()
        XCTAssertEqual(history.current, .empty)
        XCTAssertFalse(history.canUndo)
    }

    func testAppAppearanceDraftSaveLoad() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: dir) }

        XCTAssertNil(try AppAppearanceDraft.load(bundleID: "com.tencent.xin", from: dir))

        let state = AppAppearancePreviewState(imageData: makePNG(width: 64, height: 64), name: "WX",
                                             crop: AppAppearanceCrop(), cornerRadius: 12)
        let draft = AppAppearanceDraft(bundleID: "com.tencent.xin", state: state)
        try draft.save(to: dir)
        let loaded = try XCTUnwrap(AppAppearanceDraft.load(bundleID: "com.tencent.xin", from: dir))
        XCTAssertEqual(loaded.version, 1)
        XCTAssertEqual(loaded.bundleID, "com.tencent.xin")
        XCTAssertEqual(loaded.state, draft.state)
        XCTAssertEqual(loaded.imageDigest, draft.imageDigest)
        XCTAssertEqual(loaded.state.imageData, state.imageData)

        // A draft saved under another bundle ID is not returned here.
        XCTAssertNil(try AppAppearanceDraft.load(bundleID: "com.other.app", from: dir))

        // Renaming the file to another bundle ID is refused: the draft
        // records its own owner and the owner must match the file name.
        let url = dir.appendingPathComponent("com.tencent.xin.plist")
        let renamed = dir.appendingPathComponent("com.other.app.plist")
        try fm.copyItem(at: url, to: renamed)
        XCTAssertThrowsError(try AppAppearanceDraft.load(bundleID: "com.other.app", from: dir))

        // Garbage bytes are refused instead of shown.
        try Data("not a plist".utf8).write(to: url)
        XCTAssertThrowsError(try AppAppearanceDraft.load(bundleID: "com.tencent.xin", from: dir))

        // A valid plist whose image bytes were swapped is refused by the
        // digest check, even though the plist itself still decodes.
        try draft.save(to: dir)
        var tampered = try XCTUnwrap(AppAppearanceDraft.load(bundleID: "com.tencent.xin", from: dir))
        tampered.state.imageData = makePNG(width: 32, height: 32)
        try PropertyListEncoder().encode(tampered).write(to: url)
        XCTAssertThrowsError(try AppAppearanceDraft.load(bundleID: "com.tencent.xin", from: dir))
    }

    func testAppAppearanceProposalNameEdgeCases() {
        func check(_ name: String) -> AppAppearanceProposal.Check {
            AppAppearanceProposal(bundleID: "com.tencent.xin", currentName: "微信", proposedName: name).check
        }
        XCTAssertEqual(check(String(repeating: "A", count: 32)), .previewOnly)
        XCTAssertEqual(check(String(repeating: "A", count: 33)), .invalidName)
        XCTAssertEqual(check("微信💬"), .previewOnly)
        XCTAssertEqual(check("WX\nBad"), .invalidName)
        XCTAssertEqual(check("WX\tBad"), .invalidName)
        XCTAssertEqual(check(""), .invalidName)
        XCTAssertEqual(check("  WX  "), .previewOnly)
        XCTAssertEqual(check("WX Bad"), .previewOnly)
    }

    func testAppAppearanceCapabilityDefaultsUnknown() {
        let proposal = AppAppearanceProposal(bundleID: "com.tencent.xin", currentName: "微信", proposedName: "WX")
        XCTAssertEqual(proposal.capability, .unknown)
        XCTAssertNotEqual(proposal.capability, .verifiedWritable)
        XCTAssertEqual(AppAppearanceCapability.defaultCapability, .unknown)
        XCTAssertFalse(proposal.canApplyNatively, "A preview may never claim native editing succeeded")
        // The corner radius is clamped, never negative or oversized.
        XCTAssertEqual(AppAppearancePreviewState(cornerRadius: -5).cornerRadius, 0)
        XCTAssertEqual(AppAppearancePreviewState(cornerRadius: 99).cornerRadius, AppAppearancePreviewState.maximumCornerRadius)
    }

}
