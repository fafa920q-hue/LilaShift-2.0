// SPDX-License-Identifier: GPL-3.0-only
@testable import GestaltX
import XCTest

/// Tests for the read-only "Modified Values" report (`ModifiedValues`).
/// The report compares the live-read document against its recorded
/// originals and lists only fields whose current value differs and
/// whose original is known. It stages nothing and writes nothing.
@MainActor
final class ModifiedValuesTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ChinaUnlockRegionMode.stored = .regionCodeOnly
    }

    // MARK: - Fixture

    private static func document(
        regionCode: String,
        regionInfo: String = "CH/A",
        aiEnabled: Bool = false,
        esimEnabled: Bool = false,
        wapiEnabled: Bool = false
    ) throws -> GestaltDocument {
        let layout = MobileGestaltCacheLayout.originalProfile
        var cache = Data(count: layout.byteCount)
        cache[layout.validityOffset(for: layout.greenTeaIndex)] = 1
        cache[layout.validityOffset(for: layout.notGreenTeaIndex)] = 1
        cache[layout.greenTeaIndex * 8] = esimEnabled ? 0 : 1
        cache[layout.notGreenTeaIndex * 8] = esimEnabled ? 1 : 0
        if let wapiIndex = layout.wapiIndex, let wapiOffset = layout.wapiOffset {
            cache[layout.validityOffset(for: wapiIndex)] = 1
            cache[wapiOffset] = wapiEnabled ? 1 : 0
        }
        var extra: [String: Any] = [
            GestaltKeys.productType: "iPhone18,1",
            GestaltKeys.regionCode: regionCode,
            GestaltKeys.regionInfo: regionInfo,
            GestaltKeys.legacyRegionInfo: regionInfo,
            GestaltKeys.modelNumber: "A3518",
            GestaltKeys.siriKey: 2,
        ]
        if aiEnabled {
            for key in ChinaUnlock.aiCapabilityIDs {
                extra[key] = 1
            }
        }
        let data = try PropertyListSerialization.data(fromPropertyList: [
            "CacheUUID": layout.uuid,
            "CacheData": cache,
            "CacheExtra": extra,
        ], format: .binary, options: 0)
        return try GestaltDocument(data: data)
    }

    /// Recorded originals for the "before" state: region CH, sales
    /// region CH/A, regulatory model A3518, and the six AI keys absent
    /// (never set before).
    private static func originals() -> [String: OriginalField] {
        var dict: [String: OriginalField] = [
            GestaltKeys.regionCode: OriginalField(value: "CH"),
            GestaltKeys.regionInfo: OriginalField(value: "CH/A"),
            GestaltKeys.legacyRegionInfo: OriginalField(value: "CH/A"),
            GestaltKeys.modelNumber: OriginalField(value: "A3518"),
        ]
        for key in ChinaUnlock.aiCapabilityIDs {
            dict[key] = OriginalField(value: nil)
        }
        return dict
    }

    private static func snapshot(
        current: GestaltDocument,
        originals: [String: OriginalField] = [:],
        originalOptions: CachedOptionsOriginal? = nil,
        originalWAPI: WAPIOriginal? = nil
    ) throws -> DocumentSnapshot {
        var snapshot = DocumentSnapshot(
            data: try current.encoded(),
            document: current,
            source: .local,
            name: "fixture")
        snapshot.originals = originals
        snapshot.cachedOptionsOriginal = originalOptions
        snapshot.wapiOriginal = originalWAPI
        return snapshot
    }

    // MARK: - Tests

    func testOneTapUnlockIsListedWithOriginalAndCurrent() throws {
        let before = try Self.document(regionCode: "CH")
        let after = try Self.document(regionCode: "LL", aiEnabled: true, esimEnabled: true)
        let snapshot = try Self.snapshot(
            current: after,
            originals: Self.originals(),
            originalOptions: try CachedOptionsOriginal(document: before))
        let report = ModifiedValues.report(for: snapshot)

        guard case .compared(let rows) = report else {
            return XCTFail("expected .compared, got \(report)")
        }
        // Region code, the 6 AI keys, and the 2 eSIM slots = 9 rows.
        XCTAssertEqual(rows.count, 9)
        let byKey = Dictionary(uniqueKeysWithValues: rows.map { ($0.key, $0) })
        let regionRow = try XCTUnwrap(byKey[GestaltKeys.regionCode])
        XCTAssertEqual(regionRow.originalText, "CH")
        XCTAssertEqual(regionRow.currentText, "LL")
        XCTAssertFalse(regionRow.wasAbsent)
        for key in ChinaUnlock.aiCapabilityIDs {
            let row = try XCTUnwrap(byKey[key], "missing row for \(key)")
            XCTAssertEqual(row.originalText, L("Not set"))
            XCTAssertEqual(row.currentText, "1")
            XCTAssertTrue(row.wasAbsent)
        }
        let greenTea = try XCTUnwrap(byKey["esim-green-tea"])
        XCTAssertEqual(greenTea.originalText, "true")
        XCTAssertEqual(greenTea.currentText, "false")
        let notGreenTea = try XCTUnwrap(byKey["esim-not-green-tea"])
        XCTAssertEqual(notGreenTea.originalText, "false")
        XCTAssertEqual(notGreenTea.currentText, "true")
    }

    func testUnchangedFieldIsNotListed() throws {
        // Region info, legacy region info, and the model number are
        // recorded but identical — they must not appear.
        let after = try Self.document(regionCode: "LL", aiEnabled: true, esimEnabled: true)
        let snapshot = try Self.snapshot(current: after, originals: Self.originals())
        let report = ModifiedValues.report(for: snapshot)

        guard case .compared(let rows) = report else {
            return XCTFail("expected .compared, got \(report)")
        }
        XCTAssertEqual(rows.count, 7) // region code + 6 AI keys
        let keys = Set(rows.map(\.key))
        XCTAssertFalse(keys.contains(GestaltKeys.regionInfo))
        XCTAssertFalse(keys.contains(GestaltKeys.legacyRegionInfo))
        XCTAssertFalse(keys.contains(GestaltKeys.modelNumber))
    }

    func testUnknownOriginalIsNotListedAsModified() throws {
        // The current document has the AI keys set, but no originals
        // were ever recorded: the report must say it cannot determine
        // whether anything was modified — never invent originals.
        let after = try Self.document(regionCode: "LL", aiEnabled: true, esimEnabled: true)
        let snapshot = try Self.snapshot(current: after)
        XCTAssertEqual(ModifiedValues.report(for: snapshot), .noRecordedOriginals)
    }

    func testNoDocument() {
        XCTAssertEqual(ModifiedValues.report(for: nil), .noDocument)
    }

    func testNothingDiffersIsAnHonestEmptyComparison() throws {
        let current = try Self.document(regionCode: "CH")
        let snapshot = try Self.snapshot(
            current: current,
            originals: Self.originals(),
            originalOptions: try CachedOptionsOriginal(document: current))
        let report = ModifiedValues.report(for: snapshot)

        guard case .compared(let rows) = report else {
            return XCTFail("expected .compared, got \(report)")
        }
        XCTAssertTrue(rows.isEmpty)
    }

    func testWAPIModificationIsListed() throws {
        let before = try Self.document(regionCode: "CH", wapiEnabled: false)
        let after = try Self.document(regionCode: "CH", wapiEnabled: true)
        let snapshot = try Self.snapshot(
            current: after,
            originals: [GestaltKeys.regionCode: OriginalField(value: "CH")],
            originalWAPI: try WAPIOriginal(document: before))
        let report = ModifiedValues.report(for: snapshot)

        guard case .compared(let rows) = report else {
            return XCTFail("expected .compared, got \(report)")
        }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.key, "wapi")
        XCTAssertEqual(rows.first?.originalText, "false")
        XCTAssertEqual(rows.first?.currentText, "true")
    }

    func testManagerExposesTheSameReport() throws {
        let manager = GestaltManager()
        let after = try Self.document(regionCode: "LL", aiEnabled: true, esimEnabled: true)
        let snapshot = try Self.snapshot(current: after, originals: Self.originals())
        manager.loadSnapshotForTests(snapshot)
        XCTAssertEqual(manager.modifiedValuesReport, ModifiedValues.report(for: snapshot))
    }
}
