import Foundation
import XCTest
@testable import GestaltX

struct TestFailure: Error { let message: String }
final class AccessTrace: @unchecked Sendable {
    var acquired = 0
    var released: [Int64] = []
    var writes = 0
}
final class DocumentTests: XCTestCase {
    func verifyPresetRestoration(data: Data, directory: URL, removeJournal: Bool = false) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let original = try GestaltDocument(data: data)
        for capability in Capability.all {
            let device = directory.appendingPathComponent(capability.id + ".plist")
            let backups = directory.appendingPathComponent(capability.id + "-backups", isDirectory: true)
            try data.write(to: device)
            let store = GestaltFileStore(deviceURL: device, backupDirectory: backups, deviceID: "preset-fixture", acquire: { 1 }, release: { _ in })
            let initial = try await store.loadDevice()
            var enabled = initial.document
            capability.apply(.enable, to: &enabled, restoringFrom: initial)
            _ = try await store.commit(enabled, expected: initial)
            if removeJournal {
                // An earlier app version has backups but no original-value record.
                try fm.removeItem(at: backups.appendingPathComponent("OriginalValues.plist"))
            } else {
                // Deleting visible backups must not erase the independent record.
                for record in try await store.backups() { try await store.deleteBackup(record) }
            }
            let reopened = GestaltFileStore(deviceURL: device, backupDirectory: backups, deviceID: "preset-fixture", acquire: { 1 }, release: { _ in })
            let loaded = try await reopened.loadDevice()
            var restored = loaded.document
            capability.apply(.disable, to: &restored, restoringFrom: loaded)
            XCTAssert(restored.matches(original), "Every preset restores exact original presence, values, types and unrelated data: " + capability.id)
            _ = try await reopened.commit(restored, expected: loaded)
            let readback = try await reopened.loadDevice()
            XCTAssert(readback.document.matches(original), "Restored fields survive disk write and reload: " + capability.id)
            capability.apply(.disable, to: &restored, restoringFrom: readback)
            XCTAssert(restored.matches(original), "Repeated disable does not create absent keys: " + capability.id)
        }
    }

    func verifyDynamicCacheLayout() throws {
        let uuid = "A4A4A4A4-1111-2222-3333-123456789ABC"
        let address: UInt64 = 0x180100000
        let keys = ["AAAAAAAAAAAAAAAAAAAAAA", DeviceCacheOptions.greenTeaKey,
                    DeviceCacheOptions.wapiKey, "CCCCCCCCCCCCCCCCCCCCCC",
                    DeviceCacheOptions.notGreenTeaKey, "DDDDDDDDDDDDDDDDDDDDDD"]
        var strings = Data((uuid + "\0").utf8)
        var pointers: [UInt64] = []
        for key in keys { pointers.append(address + UInt64(strings.count)); strings.append(contentsOf: (key + "\0").utf8) }
        var descriptors = Data(repeating: 0, count: keys.count * 64)
        func put<T: FixedWidthInteger>(_ value: T, into bytes: inout Data, at offset: Int) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { bytes.replaceSubrange(offset..<(offset + $0.count), with: $0) }
        }
        for i in keys.indices {
            // PAC-tagged data pointers must resolve without dereferencing them.
            put(pointers[i] | 0xABCD_0000_0000_0000, into: &descriptors, at: i * 64)
            put(Int16(i), into: &descriptors, at: i * 64 + 0x3A)
            put(UInt32(11), into: &descriptors, at: i * 64 + 0x3C)
        }
        let layout = try MobileGestaltCacheLayout.scan(strings: strings, stringAddress: address, constants: [descriptors])
        XCTAssert(layout.uuid == uuid && layout.slotCount == 6, "Resolve UUID and slot count from the library query table")
        XCTAssert(layout.greenTeaOffset == 8 && layout.notGreenTeaOffset == 32,
                   "Each query gets an independently resolved offset")
        XCTAssert(layout.validityOffset(for: layout.notGreenTeaIndex) == 52, "Compute validity offsets from this layout's slot count")
        var cache = Data(repeating: 0, count: layout.byteCount)
        cache[layout.greenTeaOffset] = 1
        cache[layout.validityOffset(for: layout.greenTeaIndex)] = 1
        cache[layout.validityOffset(for: layout.notGreenTeaIndex)] = 1
        cache[0] = 99
        let original = try GestaltDocument(data: PropertyListSerialization.data(fromPropertyList: [
            "CacheUUID": uuid, "CacheData": cache, "CacheExtra": [GestaltKeys.regionCode: "CH"]
        ], format: .binary, options: 0))
        var edited = original
        try edited.setCacheOptions(.enabled, using: layout)
        try DeviceCacheOptions.validateEdit(from: original, to: edited, using: layout)
        XCTAssert(try DeviceCacheOptions.flags(in: edited, using: layout) == .enabled, "Write the dynamically located target bytes")
        try edited.setCacheOptions(.restricted, using: layout)
        XCTAssert(edited.matches(original), "Restore dynamic flags without changing other cache bytes or region fields")
        XCTAssert(layout.wapiIndex == 2, "Resolve WAPI independently from its descriptor")
        var wapiCache = cache
        wapiCache[16] = 1; wapiCache[50] = 1
        var wapiRoot = original.root; wapiRoot["CacheData"] = wapiCache
        let wapiDocument = try GestaltDocument(data: PropertyListSerialization.data(fromPropertyList: wapiRoot, format: .binary, options: 0))
        var wapiEdited = wapiDocument
        try wapiEdited.setWAPI(false, using: layout)
        try DeviceCacheOptions.validateEdit(from: wapiDocument, to: wapiEdited, using: layout)
        XCTAssert(try !DeviceCacheOptions.wapi(in: wapiEdited, using: layout), "Use relocated WAPI offsets")
        var absentWAPI = descriptors
        put(UInt64(0), into: &absentWAPI, at: 128)
        let withoutWAPI = try MobileGestaltCacheLayout.scan(strings: strings, stringAddress: address, constants: [absentWAPI])
        XCTAssert(withoutWAPI.wapiIndex == nil, "Missing WAPI keeps green-tea available")
        XCTAssertThrowsError(try wapiEdited.setWAPI(false, using: withoutWAPI), "Missing WAPI cannot be written")
        var invalidWAPI = descriptors
        put(UInt32(5), into: &invalidWAPI, at: 128 + 0x3C)
        XCTAssertThrowsError(try MobileGestaltCacheLayout.scan(strings: strings, stringAddress: address, constants: [invalidWAPI]), "A non-Boolean WAPI descriptor fails the whole scan")
        var ambiguous = descriptors
        ambiguous.append(descriptors.subdata(in: 64..<128))
        put(Int16(3), into: &ambiguous, at: descriptors.count + 0x3A)
        XCTAssertThrowsError(try MobileGestaltCacheLayout.scan(strings: strings, stringAddress: address, constants: [ambiguous]), "Reject duplicate descriptors with conflicting indices")
        var wrongType = descriptors
        put(UInt32(5), into: &wrongType, at: 64 + 0x3C)
        XCTAssertThrowsError(try MobileGestaltCacheLayout.scan(strings: strings, stringAddress: address, constants: [wrongType]), "Reject non-Boolean target descriptors")
        var missing = descriptors
        put(UInt64(0), into: &missing, at: 64)
        XCTAssertThrowsError(try MobileGestaltCacheLayout.scan(strings: strings, stringAddress: address, constants: [missing]), "Reject missing query references")
        XCTAssertThrowsError(try MobileGestaltCacheLayout.scan(strings: strings + Data("BBBBBBBB-1111-2222-3333-123456789ABC\0".utf8), stringAddress: address, constants: [descriptors]), "Reject ambiguous cache UUIDs")
        let invalid = MobileGestaltCacheLayout(uuid: uuid, slotCount: 6, greenTeaIndex: 99, notGreenTeaIndex: 4)
        XCTAssertThrowsError(try DeviceCacheOptions.validatedData(in: original, using: invalid), "Reject invalid resolved offsets before indexing data")
        // Optional local-only image/export fixtures are never copied into the repo.
        if let imagePath = ProcessInfo.processInfo.environment["GX_TEST_MG_IMAGE"] {
            let image = try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: imagePath)), options: [], format: nil) as! [String: Any]
            let actual = try MobileGestaltCacheLayout.scan(image: image)
            XCTAssert(actual.slotCount == 719 && actual.greenTeaIndex == 382 && actual.notGreenTeaIndex == 505,
                       "Real 24A446 system-library descriptors resolve independently of the old profile")
            if let exportPath = ProcessInfo.processInfo.environment["GX_TEST_MG_EXPORT"] {
                let url = URL(fileURLWithPath: exportPath), bytes = try Data(contentsOf: url)
                let original = try GestaltDocument(data: bytes)
                let flags = try DeviceCacheOptions.flags(in: original, using: actual)
                var edited = original
                try edited.setCacheOptions(.enabled, using: actual)
                try DeviceCacheOptions.validateEdit(from: original, to: edited, using: actual)
                try edited.setCacheOptions(flags, using: actual)
                XCTAssert(edited.matches(original), "Actual exported cache round-trips exact original flags with dynamic offsets")
                XCTAssert(try Data(contentsOf: url) == bytes, "The owner's exported file remains untouched")
            }
        }
    }

    func verifyCachedOptions(in root: URL) async throws {
        var cache = Data(repeating: 0, count: 6480)
        cache[0xBF8] = 1
        cache[0x17FF] = 1
        cache[0x187A] = 1
        cache[17] = 93 // An unrelated byte must survive every operation.
        let fixture: [String: Any] = [
            "CacheVersion": "24C5037i", "CacheUUID": "7F1DF278-18B7-4E5A-8425-09E8830DE9AF",
            "CacheData": cache, "UnchangedTopLevel": ["nested": true],
            "CacheExtra": [GestaltKeys.productType: "iPhone18,1", GestaltKeys.regionCode: "CH",
                           GestaltKeys.legacyRegionInfo: "CH/A", "unrelated": Data([1, 2, 3])]
        ]
        func document(_ input: [String: Any]) throws -> GestaltDocument {
            try GestaltDocument(data: PropertyListSerialization.data(fromPropertyList: input, format: .binary, options: 0))
        }
        func verifyOnlyTargetBytes(_ original: GestaltDocument) throws -> GestaltDocument {
            var enabled = original
            try enabled.setCacheOptions(.enabled)
            try DeviceCacheOptions.validateEdit(from: original, to: enabled)
            let before = original.root["CacheData"] as! Data
            let after = enabled.root["CacheData"] as! Data
            let changed = before.indices.filter { before[$0] != after[$0] }
            XCTAssert(changed == [0xBF8, 0xFD0], "Only the two independently verified bytes change")
            var expected = original.root
            var expectedCache = before
            expectedCache[0xBF8] = 0; expectedCache[0xFD0] = 1
            expected["CacheData"] = expectedCache
            XCTAssert(GestaltDocument.valuesEqual(enabled.root, expected), "All other root values, CacheExtra, regions and validity bytes remain intact")
            XCTAssert(DeviceCacheOptions.changes(from: original, to: enabled).count == 2, "CacheData-only changes are counted")
            XCTAssert(try DeviceCacheOptions.flags(in: enabled) == .enabled, "Enabled flags are readable")
            XCTAssert(try document(expected).matches(GestaltDocument(data: enabled.encoded())), "Cache edit preserves types through binary plist encoding")
            var repeated = enabled
            try repeated.setCacheOptions(.enabled)
            XCTAssert(DeviceCacheOptions.changes(from: enabled, to: repeated).isEmpty, "Enable is idempotent")
            try repeated.setCacheOptions(.restricted)
            XCTAssert(repeated.matches(original), "Restore restriction returns the complete original document")
            return enabled
        }
        let original = try document(fixture)
        let enabled = try verifyOnlyTargetBytes(original)
        var invalidLayout = fixture; invalidLayout["CacheUUID"] = "different-layout"
        XCTAssertThrowsError(try { var doc = try document(invalidLayout); try doc.setCacheOptions(.enabled) }(), "Reject a different cache layout")
        for version in ["24C9999", "another-build", ""] {
            var alternate = fixture; alternate["CacheVersion"] = version
            alternate["CacheExtra"] = [GestaltKeys.productType: "another-model"]
            let alternateDocument = try document(alternate)
            var edited = alternateDocument
            try edited.setCacheOptions(.enabled)
            try DeviceCacheOptions.validateEdit(from: alternateDocument, to: edited)
            XCTAssert(try DeviceCacheOptions.flags(in: edited) == .enabled, "Matching layouts are accepted regardless of model and build")
            let saved = try CachedOptionsOriginal(document: alternateDocument)
            XCTAssert(try saved.flags(in: original) == .restricted, "Restoration uses layout identity, not model or OS version")
        }
        var noVersion = fixture; noVersion.removeValue(forKey: "CacheVersion")
        noVersion["CacheExtra"] = [String: Any]()
        var noMetadata = try document(noVersion)
        let noMetadataOriginal = try CachedOptionsOriginal(document: noMetadata)
        try noMetadata.setCacheOptions(.enabled)
        XCTAssert(try noMetadataOriginal.flags(in: noMetadata) == .restricted, "Missing model/build metadata does not block edit or restore")
        for (offset, value) in [(0x17FF, UInt8(0)), (0x187A, 0), (0xBF8, 2), (0xFD1, 1)] {
            var invalid = fixture; var bytes = cache; bytes[offset] = value; invalid["CacheData"] = bytes
            XCTAssertThrowsError(try { var doc = try document(invalid); try doc.setCacheOptions(.enabled) }(), "Reject invalid flags, validity or slot padding")
        }
        var truncated = fixture; truncated["CacheData"] = Data(cache.dropLast())
        XCTAssertThrowsError(try { var doc = try document(truncated); try doc.setCacheOptions(.enabled) }(), "Reject a truncated cache")
        for key in [DeviceCacheOptions.greenTeaKey, DeviceCacheOptions.notGreenTeaKey, "green-tea", "not-green-tea"] {
            var conflicting = original; conflicting.set(false, for: key)
            XCTAssertThrowsError(try conflicting.setCacheOptions(.enabled), "Reject conflicting CacheExtra fields")
        }
        var tampered = fixture; var unrelated = cache; unrelated[17] = 94; tampered["CacheData"] = unrelated
        XCTAssertThrowsError(try DeviceCacheOptions.validateEdit(from: original, to: document(tampered)), "Reject changes to unrelated cache bytes at commit validation")
        var changedModel = enabled; changedModel.set("iPhone18,2", for: GestaltKeys.productType)
        try DeviceCacheOptions.validateEdit(from: original, to: changedModel)
        XCTAssert(changedModel.extra[GestaltKeys.productType] as? String == "iPhone18,2", "A staged model change no longer blocks cache edits")
        var pending = enabled
        pending.set("pending", for: "unrelated-pending")
        let baseline = DocumentSnapshot(data: try original.encoded(), document: original, source: .local, name: "fixture")
        var restoredOtherField = original
        restoredOtherField.set("restored", for: "other-preset")
        let rebased = baseline.rebasingPendingEdits(pending, onto: restoredOtherField, excluding: ["other-preset"])
        XCTAssert(try DeviceCacheOptions.flags(in: rebased) == .enabled, "Restoring an unrelated preset retains staged cache flags")
        XCTAssert(rebased.extra["unrelated-pending"] as? String == "pending", "Rebase retains other staged fields")
        XCTAssert(rebased.extra["other-preset"] as? String == "restored", "Rebase retains the just-restored preset")
        let device = root.appendingPathComponent("cache-option-device.plist")
        let originalBytes = try original.encoded()
        try originalBytes.write(to: device)
        let store = GestaltFileStore(deviceURL: device, backupDirectory: root.appendingPathComponent("cache-option-backups"),
                                    deviceID: "cache-option-fixture", acquire: { 1 }, release: { _ in })
        let snapshot = try await store.loadDevice()
        let committed = try await store.commit(enabled, expected: snapshot)
        XCTAssert(committed.document.matches(enabled), "CacheData-only write passes full readback verification")
        let backups = try await store.backups()
        let writeBackup = backups.first { $0.reason == "Before applying" }!
        XCTAssert(backups.count == 2, "Initial and pre-write backups are retained")
        let writeBackupData = try await store.backupData(writeBackup)
        XCTAssert(writeBackupData == originalBytes, "Backup retains exact pre-patch bytes")
        _ = try await store.commit(original, expected: committed, restoring: writeBackup)
        XCTAssert(try GestaltDocument(data: Data(contentsOf: device)).matches(original), "Owned backup restores the original cache flags")
        let rejected = try await store.loadDevice()
        do {
            _ = try await store.commit(document(tampered), expected: rejected)
            throw TestFailure(message: "Commit must reject unrelated cache edits")
        } catch is GestaltFailure {}
        XCTAssert(try Data(contentsOf: device) == originalBytes, "Rejected cache edits never reach the system writer")
        // All valid Boolean pairs are possible baselines. Restoring must not
        // manufacture the mainland restriction pair on an already-modified file.
        let pairs = [CachedOptionFlags.restricted, .enabled,
                     CachedOptionFlags(greenTea: false, notGreenTea: false),
                     CachedOptionFlags(greenTea: true, notGreenTea: true)]
        for (index, flags) in pairs.enumerated() {
            for mode in ["journal", "deleted-backups", "missing-journal", "legacy-journal"] {
                let directory = root.appendingPathComponent("cache-option-original-\(index)-" + mode)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let device = directory.appendingPathComponent("device.plist")
                let backups = directory.appendingPathComponent("backups")
                var baseline = original
                try baseline.setCacheOptions(flags)
                try baseline.encoded().write(to: device)
                func makeStore() -> GestaltFileStore {
                    GestaltFileStore(deviceURL: device, backupDirectory: backups, deviceID: "audio-original-fixture",
                                     acquire: { 1 }, release: { _ in })
                }
                let store = makeStore()
                let initial = try await store.loadDevice()
                XCTAssert(initial.cachedOptionsOriginal == nil, "Unknown history is not guessed")
                XCTAssert(try initial.originalCachedOptionFlags() == flags, "Unknown original uses the loaded baseline")
                var changed = initial.document
                // Ensure a real edit even when the input already has enabled flags.
                try changed.setCacheOptions(flags == .enabled ? .restricted : .enabled)
                changed.set("committed", for: "other-field")
                let applied = try await store.commit(changed, expected: initial)
                XCTAssert(try applied.originalCachedOptionFlags() == flags, "Commit records the actual original pair")
                // Repeated changes must never replace the earliest recorded state.
                var secondEdit = applied.document
                try secondEdit.setCacheOptions(CachedOptionFlags(greenTea: !flags.greenTea, notGreenTea: !flags.notGreenTea))
                let second = try await store.commit(secondEdit, expected: applied)
                XCTAssert(try second.originalCachedOptionFlags() == flags, "Repeated writes retain the first original")
                let journal = backups.appendingPathComponent("OriginalValues.plist")
                if mode == "deleted-backups" {
                    for record in try await store.backups() { try await store.deleteBackup(record) }
                } else if mode == "missing-journal" {
                    try FileManager.default.removeItem(at: journal)
                } else if mode == "legacy-journal" {
                    var plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: journal), options: [], format: nil) as! [String: Any]
                    plist.removeValue(forKey: "faceTimeAudio")
                    plist.removeValue(forKey: "cacheHistoryRecovered")
                    try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0).write(to: journal)
                }
                let reopened = makeStore()
                let loaded = try await reopened.loadDevice()
                XCTAssert(try loaded.originalCachedOptionFlags() == flags, "Reload and migration retain originals: " + mode)
                if mode == "deleted-backups" {
                    let recreated = try await reopened.backups().first!
                    let saved = try GestaltDocument(data: await reopened.backupData(recreated))
                    XCTAssert(try DeviceCacheOptions.flags(in: saved) == flags, "Recreated initial backup contains saved original cache flags")
                }
                if mode == "missing-journal" || mode == "legacy-journal" {
                    for record in try await reopened.backups() { try await reopened.deleteBackup(record) }
                    let migrated = try await makeStore().loadDevice()
                    XCTAssert(try migrated.originalCachedOptionFlags() == flags, "Migrated originals remain after backups are deleted")
                }
                var pending = loaded.document
                try pending.setCacheOptions(.enabled)
                pending.set("pending", for: "pending-field")
                var restored = loaded.document
                try restored.setCacheOptions(loaded.originalCachedOptionFlags())
                let result = try await reopened.commit(restored, expected: loaded)
                XCTAssert(result.document.extra["other-field"] as? String == "committed", "One-cell restore leaves other applied fields intact")
                let rebased = loaded.rebasingPendingEdits(pending, onto: result.document, excluding: [], preservingCacheData: false)
                XCTAssert(try DeviceCacheOptions.flags(in: rebased) == flags, "Reverting the preset discards only its staged cache edits")
                XCTAssert(rebased.extra["pending-field"] as? String == "pending", "Reverting the preset preserves unrelated pending edits")
                let final = try await makeStore().loadDevice()
                XCTAssert(try DeviceCacheOptions.flags(in: final.document) == flags, "Exact original flags survive write and reopen")
                var expected = baseline
                expected.set("committed", for: "other-field")
                XCTAssert(final.document.matches(expected), "Restore touches only the two flag bytes")
            }
        }
        let journal = root.appendingPathComponent("cache-option-backups/OriginalValues.plist")
        let intactJournal = try Data(contentsOf: journal)
        var corruptJournal = try PropertyListSerialization.propertyList(from: intactJournal, options: [], format: nil) as! [String: Any]
        corruptJournal["faceTimeAudio"] = Data([0, 1, 2])
        try PropertyListSerialization.data(fromPropertyList: corruptJournal, format: .binary, options: 0).write(to: journal)
        let beforeCorruptRead = try Data(contentsOf: device)
        do {
            _ = try await store.loadDevice()
            throw TestFailure(message: "Malformed saved cache originals must block reading instead of being ignored")
        } catch is GestaltFailure {}
        XCTAssert(try Data(contentsOf: device) == beforeCorruptRead, "A corrupt original record cannot modify the device")
        try intactJournal.write(to: journal)
        let local = try await store.loadLocal(data: originalBytes, name: "local-fixture")
        let localEdit = try await store.commit(enabled, expected: local)
        XCTAssert(try localEdit.originalCachedOptionFlags() == .restricted, "Local sessions retain their own original flags")
        let otherLocal = try await store.loadLocal(data: enabled.encoded(), name: "unrelated-local")
        XCTAssert(try otherLocal.cachedOptionsOriginal == nil && otherLocal.originalCachedOptionFlags() == .enabled,
                   "Newly opened files do not inherit another document's original flags")
        var foreignLayout = fixture
        foreignLayout["CacheUUID"] = "different-layout"
        let savedOriginal = try CachedOptionsOriginal(document: original)
        XCTAssertThrowsError(try savedOriginal.flags(in: document(foreignLayout)), "Saved originals cannot be reused with another layout")
    }

    func testDocument() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("GestaltX-tests-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try verifyDynamicCacheLayout()
        try await verifyCachedOptions(in: root)
        try await verifyWAPI(in: root)
        let device = root.appendingPathComponent("device.plist")
        let backups = root.appendingPathComponent("backups", isDirectory: true)
        let original: [String: Any] = [
            "CacheExtra": ["VasUgeSzVyHdB27g2XpN0g": "fixture-device", GestaltKeys.productType: "iPhone17,1",
                           "integer": NSNumber(value: 1), "boolean": NSNumber(value: true),
                           "payload": Data([0, 1, 255]), "nested": ["array": [1, true, "text"]]],
            "CacheData": Data([5, 10, 15]), "CacheUUID": "fixture-layout", "CacheVersion": "fixture-version", "UnchangedTopLevel": "keep"
        ]
        let originalData = try PropertyListSerialization.data(fromPropertyList: original, format: .binary, options: 0)
        try await verifyPresetRestoration(data: originalData, directory: root.appendingPathComponent("absent-presets"))
        var existingRoot = original
        var existingExtra = existingRoot["CacheExtra"] as! [String: Any]
        for capability in Capability.all {
            for (index, key) in capability.keys.enumerated() {
                existingExtra[key] = capability.id == "ipadApps" ? [1, 3] : capability.id == "pencil" ? NSNumber(value: 0) : index.isMultiple(of: 2) ? NSNumber(value: false) : NSNumber(value: 0)
            }
        }
        existingRoot["CacheExtra"] = existingExtra
        let existingData = try PropertyListSerialization.data(fromPropertyList: existingRoot, format: .binary, options: 0)
        try await verifyPresetRestoration(data: existingData, directory: root.appendingPathComponent("existing-presets"))
        try await verifyPresetRestoration(data: originalData, directory: root.appendingPathComponent("legacy-presets"), removeJournal: true)
        let pencil = Capability.all.first { $0.id == "pencil" }!
        let pencilKey = pencil.keys[0]
        var residual = try GestaltDocument(data: originalData)
        residual.set(NSNumber(value: 0), for: pencilKey)
        let legacyDevice = root.appendingPathComponent("untracked-pencil.plist")
        let legacyBackups = root.appendingPathComponent("untracked-pencil-backups")
        try residual.encoded().write(to: legacyDevice)
        let legacyStore = GestaltFileStore(deviceURL: legacyDevice, backupDirectory: legacyBackups, deviceID: "legacy-pencil", acquire: { 1 }, release: { _ in })
        let legacyLoaded = try await legacyStore.loadDevice()
        var removed = legacyLoaded.document
        pencil.apply(.removeAdded, to: &removed, restoringFrom: legacyLoaded)
        _ = try await legacyStore.commit(removed, expected: legacyLoaded, originallyAbsentKeys: [pencilKey])
        let freshStore = GestaltFileStore(deviceURL: legacyDevice, backupDirectory: legacyBackups, deviceID: "legacy-pencil", acquire: { 1 }, release: { _ in })
        let fresh = try await freshStore.loadDevice()
        XCTAssert(fresh.originals[pencilKey] != nil && fresh.originalValue(for: pencilKey) == nil, "Explicit removal records absence instead of retaining an old zero residue")
        var pencilEnabled = fresh.document
        pencil.apply(.enable, to: &pencilEnabled, restoringFrom: fresh)
        let enabledAgain = try await freshStore.commit(pencilEnabled, expected: fresh)
        var pencilDisabled = enabledAgain.document
        pencil.apply(.disable, to: &pencilDisabled, restoringFrom: enabledAgain)
        XCTAssert(pencilDisabled.extra[pencilKey] == nil, "Enable then disable after legacy cleanup does not recreate Pencil zero")
        let wrongDeviceStore = GestaltFileStore(deviceURL: legacyDevice, backupDirectory: legacyBackups, deviceID: "another-installation", acquire: { 1 }, release: { _ in })
        do { _ = try await wrongDeviceStore.loadDevice(); throw TestFailure(message: "Must reject foreign original-value records") }
        catch is GestaltFailure {}
        let unreadableRecordDevice = root.appendingPathComponent("bad-origin-device.plist")
        let unreadableRecordBackups = root.appendingPathComponent("bad-origin-backups")
        try originalData.write(to: unreadableRecordDevice)
        let originalTrace = AccessTrace()
        let badOriginStore = GestaltFileStore(deviceURL: unreadableRecordDevice, backupDirectory: unreadableRecordBackups, deviceID: "bad-origin", acquire: { 1 }, release: { _ in }, writeData: { _, _ in originalTrace.writes += 1 })
        let beforeBadOrigin = try await badOriginStore.loadDevice()
        try fm.createDirectory(at: unreadableRecordBackups.appendingPathComponent("OriginalValues.plist"), withIntermediateDirectories: true)
        var badOriginEdit = beforeBadOrigin.document
        pencil.apply(.enable, to: &badOriginEdit, restoringFrom: beforeBadOrigin)
        do { _ = try await badOriginStore.commit(badOriginEdit, expected: beforeBadOrigin); throw TestFailure(message: "Broken originals must stop a system write") }
        catch is GestaltFailure {}
        XCTAssert(try originalTrace.writes == 0 && Data(contentsOf: unreadableRecordDevice) == originalData, "No system write when original values cannot be preserved")
        let unknownSnapshot = DocumentSnapshot(data: try residual.encoded(), document: residual, source: .local, name: "unknown")
        var unknown = residual
        pencil.apply(.disable, to: &unknown, restoringFrom: unknownSnapshot)
        XCTAssert(unknown.matches(residual), "Without prior records, do not guess an existing zero field was originally absent")
        let srd = Capability.all.first { $0.id == "srd" }!
        let srdKey = srd.keys[0]
        let srdDevice = root.appendingPathComponent("srd-device.plist")
        try originalData.write(to: srdDevice)
        let srdStore = GestaltFileStore(deviceURL: srdDevice, backupDirectory: root.appendingPathComponent("srd-backups"), deviceID: "fixture-srd", acquire: { 1 }, release: { _ in })
        let srdInitial = try await srdStore.loadDevice()
        var srdDocument = srdInitial.document
        srd.apply(.keep, to: &srdDocument, restoringFrom: srdInitial)
        XCTAssert(srdDocument.matches(srdInitial.document), "Keep Current must not alter SRD")
        srd.apply(.enable, to: &srdDocument, restoringFrom: srdInitial)
        _ = try await srdStore.commit(srdDocument, expected: srdInitial)
        let srdReloaded = try await srdStore.loadDevice()
        XCTAssert((srdReloaded.document.extra[srdKey] as? NSNumber)?.intValue == 1, "SRD enable persists across reload")
        srdDocument = srdReloaded.document
        srd.apply(.disable, to: &srdDocument, restoringFrom: srdReloaded)
        XCTAssert(srdDocument.extra[srdKey] == nil, "SRD disable removes the override instead of storing zero")
        let srdDisabled = try await srdStore.commit(srdDocument, expected: srdReloaded)
        XCTAssert(srdDisabled.document.matches(srdInitial.document), "Disabling an added SRD override restores the original document")
        let srdAfterDisable = try await srdStore.loadDevice()
        XCTAssert(srdAfterDisable.document.extra[srdKey] == nil, "Removed SRD override stays absent after readback")
        srdDocument = srdAfterDisable.document
        srd.apply(.disable, to: &srdDocument, restoringFrom: srdAfterDisable)
        XCTAssert(srdDocument.matches(srdInitial.document), "Disabling an absent SRD key does not create a zero override")
        let srdBackups = try await srdStore.backups()
        XCTAssert(srdBackups.count == 3, "Initial read, SRD enable and disable retain backups")
        // A region-code edit must not rewrite or synthesize either sales suffix,
        // alter the separate AI flag, or touch CacheData and other device fields.
        for suffixKeys in [[], [GestaltKeys.regionInfo], [GestaltKeys.legacyRegionInfo], [GestaltKeys.regionInfo, GestaltKeys.legacyRegionInfo]] {
            var fixture = original
            var extra = fixture["CacheExtra"] as! [String: Any]
            extra[GestaltKeys.regionCode] = "CH"
            extra["A62OafQ85EJAiiqKn4agtg"] = NSNumber(value: 1)
            for key in suffixKeys { extra[key] = "CH/A" }
            fixture["CacheExtra"] = extra
            let data = try PropertyListSerialization.data(fromPropertyList: fixture, format: .binary, options: 0)
            var regionDocument = try GestaltDocument(data: data)
            regionDocument.applyRegion(code: "LL")
            extra[GestaltKeys.regionCode] = "LL"
            var expected = fixture
            expected["CacheExtra"] = extra
            XCTAssert(GestaltDocument.valuesEqual(regionDocument.root, expected), "Code-only edit preserves all other fields for each suffix layout")
            let encoded = try regionDocument.encoded()
            XCTAssert(try GestaltDocument(data: encoded).matches(regionDocument), "Code-only edit survives plist roundtrip")
            regionDocument.applyRegion(code: "CH", salesSuffix: "CH/A")
            XCTAssert(regionDocument.extra[GestaltKeys.regionCode] as? String == "CH", "Sales-region restore resets the region code")
            let restoredSuffixKeys = suffixKeys.isEmpty ? [GestaltKeys.regionInfo] : suffixKeys
            for key in restoredSuffixKeys {
                XCTAssert(regionDocument.extra[key] as? String == "CH/A", "Sales-region restore retains the original suffix")
            }

            let keep = RegionPreset.all.first { $0.id == "keep" }!
            let china = RegionPreset.all.first { $0.id == "CN" }!
            let us = RegionPreset.all.first { $0.id == "US" }!
            XCTAssert(us.code == "LL", "US uses Apple's LL region code")
            for option in RegionPreset.all where option.id != "keep" {
                var codeOnly = try GestaltDocument(data: data)
                codeOnly.applyRegion(salesRegion: keep, regionCode: option)
                var expectedExtra = fixture["CacheExtra"] as! [String: Any]
                expectedExtra[GestaltKeys.regionCode] = option.code
                var expectedRoot = fixture
                expectedRoot["CacheExtra"] = expectedExtra
                XCTAssert(GestaltDocument.valuesEqual(codeOnly.root, expectedRoot), "Each region-code option preserves the sales suffix and unrelated fields")
            }
            var combined = try GestaltDocument(data: data)
            for key in suffixKeys { combined.set("ZA/A", for: key) }
            combined.applyRegion(salesRegion: china, regionCode: us)
            XCTAssert(combined.extra[GestaltKeys.regionCode] as? String == "LL", "Combined choices retain the independently selected region code")
            for key in restoredSuffixKeys {
                XCTAssert(combined.extra[key] as? String == "CH/A", "Combined choices restore the sales suffix instead of retaining ZA/A")
            }
            var unchanged = try GestaltDocument(data: data)
            unchanged.applyRegion(salesRegion: keep, regionCode: keep)
            XCTAssert(GestaltDocument.valuesEqual(unchanged.root, fixture), "Keeping both selections leaves all fields untouched")
        }
        try originalData.write(to: device)
        let trace = AccessTrace()
        let store = GestaltFileStore(deviceURL: device, backupDirectory: backups, deviceID: "fixture-installation", acquire: {
            trace.acquired += 1; return 0
        }, release: { trace.released.append($0) }, writeData: { data, url in
            trace.writes += 1
            let files = try FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)
            XCTAssert(files.contains { $0.pathExtension == "plist" }, "A backup must exist before the system write")
            try data.write(to: url)
        })
        var document = try GestaltDocument(data: originalData)
        XCTAssert(PlistValueKind.detect(document.extra["integer"]!) == .integer, "Integer type detection")
        XCTAssert(PlistValueKind.detect(document.extra["boolean"]!) == .boolean, "Boolean type detection")
        XCTAssert(!GestaltDocument.valuesEqual(NSNumber(value: true), NSNumber(value: 1)), "Do not conflate Boolean and integer")
        XCTAssert(!GestaltDocument.valuesEqual(NSNumber(value: 1.0), NSNumber(value: 1)), "Do not conflate real and integer")
        XCTAssertThrowsError(try PlistValueKind.integer.parse("bad"), "Reject an invalid integer")
        XCTAssertThrowsError(try PlistValueKind.real.parse("NaN"), "Reject non-finite real")
        XCTAssertThrowsError(try PlistValueKind.boolean.parse("yes"), "Reject ambiguous Boolean")
        XCTAssertThrowsError(try PlistValueKind.data.parse("***"), "Reject invalid Base64")
        XCTAssertThrowsError(try PlistValueKind.array.parse("<dict/>"), "Reject wrong collection type")
        XCTAssertThrowsError(try GestaltDocument(data: Data("<plist><dict/></plist>".utf8)), "Reject missing CacheExtra")
        let nested = try PlistValueKind.dictionary.parse("<dict><key>blob</key><data>AAH/</data><key>list</key><array><true/><integer>7</integer><date>2026-11-09T12:00:00Z</date></array></dict>")
        let roundtrip = try PlistValueKind.dictionary.parse(PlistValueKind.dictionary.text(for: nested))
        XCTAssert(GestaltDocument.valuesEqual(nested, roundtrip), "Nested XML roundtrip preserves types")
        _ = try PlistValueKind.date.parse("2026-11-09T12:00:00.125Z")
        let initial = try await store.loadDevice()
        let firstReadBackups = try await store.backups()
        XCTAssert(firstReadBackups.count == 1 && firstReadBackups[0].reason == "Initial backup", "First device read saves a backup before editing")
        _ = try await store.loadDevice()
        let rereadBackups = try await store.backups()
        XCTAssert(rereadBackups.count == 1, "Repeated reads do not duplicate the initial backup")
        trace.released.removeAll()
        var pending = initial.document
        pending.set("pending", for: "unrelated-pending")
        pending.set(nil, for: "payload")
        pending.set(NSNumber(value: 1), for: srdKey)
        var latest = initial.document
        latest.set(nil, for: srdKey)
        let rebased = initial.rebasingPendingEdits(pending, onto: latest, excluding: [srdKey])
        XCTAssert(rebased.extra[srdKey] == nil, "Single-row restore removes the target's pending override")
        XCTAssert(rebased.extra["unrelated-pending"] as? String == "pending" && rebased.extra["payload"] == nil, "Single-row restore preserves unrelated pending additions and deletions")
        document.set("edited", for: "new")
        let committed = try await store.commit(document, expected: initial)
        XCTAssert(committed.document.matches(document), "Successful transaction must match readback")
        XCTAssert((committed.document.root["CacheData"] as? Data) == Data([5, 10, 15]), "Preserve CacheData")
        XCTAssert((committed.document.root["UnchangedTopLevel"] as? String) == "keep", "Preserve unrelated root values")
        let records = try await store.backups()
        XCTAssert(records.count == 2 && records.allSatisfy { $0.source == .device }, "Initial and transaction backups are persistent and source-bound")
        let firstBackupData = try await store.backupData(records[0])
        XCTAssert(firstBackupData == originalData, "Backup stores the original bytes")
        XCTAssert(trace.released == [0], "Zero is a valid extension handle and must be released")
        do { _ = try await store.commit(document, expected: initial); throw TestFailure(message: "Reject stale snapshot") }
        catch is GestaltFailure {}
        XCTAssert(trace.writes == 1, "Stale write must not reach writer")
        let restored = try await store.commit(GestaltDocument(data: originalData), expected: committed, restoring: records[0])
        XCTAssert(restored.document.matches(try GestaltDocument(data: originalData)), "Restore original from owned backup")
        let foreign = BackupRecord(id: UUID(), date: .now, reason: "Manual backup", source: .local, deviceID: "other", byteCount: originalData.count)
        do { _ = try await store.commit(document, expected: restored, restoring: foreign); throw TestFailure(message: "Reject foreign backup") }
        catch is GestaltFailure {}

        for mode in ["partial-failure", "wrong-readback"] {
            try originalData.write(to: device)
            let broken = GestaltFileStore(deviceURL: device, backupDirectory: root.appendingPathComponent(mode), deviceID: "fixture-installation", acquire: { 1 }, release: { _ in }, writeData: { data, url in
                if mode == "partial-failure" { try Data("partial".utf8).write(to: url); throw GestaltFailure("injected failure") }
                var wrong = try GestaltDocument(data: data); wrong.set("unexpected", for: "tamper")
                try wrong.encoded().write(to: url)
            })
            let snapshot = try await broken.loadDevice()
            do { _ = try await broken.commit(document, expected: snapshot); throw TestFailure(message: "Must reject " + mode) }
            catch is GestaltFailure {}
            XCTAssert(try Data(contentsOf: device) == originalData, "Recovery restores exact previous bytes: " + mode)
        }
        let occupied = root.appendingPathComponent("not-a-directory")
        try Data("occupied".utf8).write(to: occupied)
        let blockedTrace = AccessTrace()
        let blocked = GestaltFileStore(deviceURL: device, backupDirectory: occupied, deviceID: "fixture", acquire: { 1 }, release: { _ in }, writeData: { _, _ in blockedTrace.writes += 1 })
        do { _ = try await blocked.loadDevice(); throw TestFailure(message: "Initial backup failure must stop device editing") }
        catch is TestFailure { throw TestFailure(message: "Backup failure must stop write") } catch {}
        XCTAssert(blockedTrace.writes == 0, "No system writer after backup failure")
        let local = GestaltFileStore(deviceURL: device, backupDirectory: root.appendingPathComponent("local"), deviceID: "local", acquire: { throw TestFailure(message: "Local mode must not acquire device access") }, release: { _ in })
        let localSnapshot = try await local.loadLocal(data: originalData, name: "test.plist")
        let savedLocal = try await local.commit(document, expected: localSnapshot)
        XCTAssert(savedLocal.source == .local && savedLocal.document.matches(document), "Local document mode")
        XCTAssert(try Data(contentsOf: device) == originalData, "Local mode leaves device bytes untouched")
        let localBackups = try await local.backups()
        XCTAssert(localBackups.first?.source == .local, "Local backups stay local")
        try await store.deleteBackup(records[0])
        let remaining = try await store.backups()
        XCTAssert(!remaining.contains { $0.id == records[0].id }, "Backup deletion updates library")
    }
}
