import Foundation

/// Offline tests for the item-4 AI checkup and slot-only guards: the
/// eligibility table, the native-baseline override, the 4-factor
/// evaluation, and the AdvAI slot read/write machinery on a synthetic
/// scanned layout. The live MGCopyAnswer probe is device-tested only.
@main struct AIReadinessTests {
    struct Failure: Error { let message: String }
    static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message: message) }
    }
    static func put<T: FixedWidthInteger>(_ value: T, into data: inout Data, at offset: Int) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.replaceSubrange(offset..<(offset + $0.count), with: $0) }
    }

    static func evaluate(regionCode: String? = "LL", sysconfig: String? = nil,
                         regModel: String? = "A3518",
                         regionMode: ChinaUnlockRegionMode = .regionCodeOnly,
                         expectedUSModel: String? = nil,
                         esimEnabled: Bool = true, conflicts: [AIConflict] = [],
                         aiEnabledCount: Int = 6, aiTotal: Int = 6,
                         productType: String = "iPhone16,2",
                         liveRegionCode: String? = nil, liveRegModel: String? = nil,
                         liveAIEnabled: Bool? = nil) -> AIReadinessCheckup {
        AIReadinessCheckup.evaluate(
            regionCode: regionCode, sysconfig: sysconfig, regModel: regModel,
            regionMode: regionMode, expectedUSModel: expectedUSModel,
            esimEnabled: esimEnabled, conflicts: conflicts,
            aiEnabledCount: aiEnabledCount, aiTotal: aiTotal, productType: productType,
            liveRegionCode: liveRegionCode, liveRegModel: liveRegModel, liveAIEnabled: liveAIEnabled)
    }

    @MainActor
    static func main() throws {
        ChinaUnlockRegionMode.stored = .regionCodeOnly

        // Eligibility table (fail closed: unknown models are not native).
        try expect(DeviceAIEligibility.isNativeAppleIntelligence(productType: "iPhone16,2"),
                   "iPhone16,2 (15 Pro Max) is native-AI hardware")
        try expect(!DeviceAIEligibility.isNativeAppleIntelligence(productType: "iPhone15,4"),
                   "iPhone15,4 (15) is not native-AI hardware")
        try expect(DeviceAIEligibility.isNativeAppleIntelligence(productType: "iPhone19,7"),
                   "iPhone19,7 is native via the iPhone19, prefix catch-all")
        try expect(!DeviceAIEligibility.isNativeAppleIntelligence(productType: "iPhone99,9"),
                   "Unknown future models default to not native")

        // Native baselines: a polluted backup cannot downgrade them.
        try expect(DeviceAIEligibility.nativeAdvAISlotValue(key: DeviceCacheOptions.audioIntelligenceKey, productType: "iPhone16,2") == false,
                   "Audio Intelligence baseline is false on iPhone")
        try expect(DeviceAIEligibility.nativeAdvAISlotValue(key: DeviceCacheOptions.personalTranslatorKey, productType: "iPhone16,2") == true,
                   "Personal Translator baseline is true on a native-AI iPhone")
        try expect(DeviceAIEligibility.nativeAdvAISlotValue(key: DeviceCacheOptions.personalTranslatorKey, productType: "iPhone15,4") == nil,
                   "Personal Translator has no forced baseline on non-native hardware")
        try expect(DeviceAIEligibility.nativeAdvAISlotValue(key: DeviceCacheOptions.personalTranslatorKey, productType: "iPad16,1") == nil,
                   "Personal Translator has no forced baseline on iPad")

        // All-ready evaluation (LL-only, native hardware, staged unlock).
        let ready = evaluate(liveRegionCode: "LL", liveAIEnabled: true)
        try expect(ready.readyCount == 4 && ready.isReady, "Staged unlock on native hardware is 4/4 ready")
        try expect(ready.factors[0].isLiveActive == true && ready.factors[3].isLiveActive == true,
                   "Live probe answers flow into the region and AI factors")
        let unknownLive = evaluate()
        try expect(unknownLive.factors[0].isLiveActive == nil,
                   "No probe answer renders live: unknown, never faked")

        // LL-only mode passes on any kept factory model; Full US mode
        // requires the mapped US model.
        let kept = evaluate(regModel: "A3518")
        try expect(kept.factors[1].isReady, "LL-only passes on the kept factory model")
        let fullUS = evaluate(regionMode: .fullUS, sysconfig: "LL/A", regModel: "A3260",
                              expectedUSModel: "A3260")
        try expect(fullUS.factors[0].isReady && fullUS.factors[1].isReady,
                   "Full US passes with LL/A and the mapped model")
        let fullUSWrong = evaluate(regionMode: .fullUS, sysconfig: "LL/A", regModel: "A3518",
                                   expectedUSModel: "A3260")
        try expect(!fullUSWrong.factors[1].isReady, "Full US fails when the model is not the mapped US model")

        // A slot conflict fails the eSIM/conflict factor and names itself.
        let conflict = AIConflict.personalTranslatorDisabled(slot: 266)
        let conflicted = evaluate(conflicts: [conflict])
        try expect(!conflicted.factors[2].isReady && conflicted.factors[2].detail == conflict.detail,
                   "A conflict fails factor 3 and its detail names the conflict")
        let locked = evaluate(regionCode: "CH", esimEnabled: false, aiEnabledCount: 0,
                              productType: "iPhone15,4")
        try expect(locked.readyCount == 1, "Locked non-native device is 1/4 ready (regulatory model only)")

        // AdvAI slot machinery on a synthetic scanned layout.
        let uuid = "A4A4A4A4-1111-2222-3333-123456789ABC"
        let address: UInt64 = 0x180100000
        let keys = ["AAAAAAAAAAAAAAAAAAAAAA", DeviceCacheOptions.greenTeaKey,
                    DeviceCacheOptions.notGreenTeaKey, DeviceCacheOptions.wapiKey,
                    DeviceCacheOptions.audioIntelligenceKey, DeviceCacheOptions.personalTranslatorKey]
        var strings = Data((uuid + "\0").utf8)
        var pointers: [UInt64] = []
        for key in keys {
            pointers.append(address + UInt64(strings.count))
            strings.append(contentsOf: (key + "\0").utf8)
        }
        var descriptors = Data(repeating: 0, count: keys.count * 64)
        for i in keys.indices {
            put(pointers[i], into: &descriptors, at: i * 64)
            put(Int16(i), into: &descriptors, at: i * 64 + 0x3A)
            put(UInt32(11), into: &descriptors, at: i * 64 + 0x3C)
        }
        let layout = try MobileGestaltCacheLayout.scan(strings: strings, stringAddress: address, constants: [descriptors])
        try expect(layout.audioIntellIndex == 4 && layout.personalTranslatorIndex == 5,
                   "Synthetic layout resolves both AdvAI slots")
        var cache = Data(count: layout.byteCount)
        cache[layout.audioIntellOffset!] = 1
        cache[layout.personalTranslatorOffset!] = 0
        cache[layout.validityOffset(for: 4)] = 1
        cache[layout.validityOffset(for: 5)] = 1
        cache[layout.greenTeaOffset] = 1
        cache[layout.validityOffset(for: layout.greenTeaIndex)] = 1
        cache[layout.validityOffset(for: layout.notGreenTeaIndex)] = 1
        let original = try GestaltDocument(data: PropertyListSerialization.data(fromPropertyList: [
            "CacheVersion": "24C5037i", "CacheUUID": uuid,
            "CacheData": cache,
            "CacheExtra": [GestaltKeys.productType: "iPhone16,2", GestaltKeys.regionCode: "CH"],
        ], format: .binary, options: 0))
        try expect(DeviceCacheOptions.advAISlotValue(DeviceCacheOptions.audioIntelligenceKey, in: original, using: layout) == true,
                   "Audio Intelligence slot reads 1 from the fixture")
        try expect(DeviceCacheOptions.advAISlotValue(DeviceCacheOptions.personalTranslatorKey, in: original, using: layout) == false,
                   "Personal Translator slot reads 0 from the fixture")
        var repaired = original
        try repaired.setAdvAISlot(DeviceCacheOptions.personalTranslatorKey, value: true, using: layout)
        try expect(DeviceCacheOptions.advAISlotValue(DeviceCacheOptions.personalTranslatorKey, in: repaired, using: layout) == true,
                   "setAdvAISlot repairs the Personal Translator slot to its native baseline")
        try DeviceCacheOptions.validateEdit(from: original, to: repaired, using: layout)
        var untouched = original
        try untouched.setAdvAISlot(DeviceCacheOptions.greenTeaKey, value: false, using: layout)
        try expect(untouched.matches(original), "setAdvAISlot ignores non-AdvAI keys")

        // Manager level on the offline profile: slots do not resolve, so
        // there are no conflicts to repair, and Fix stages the unlock.
        let profile = MobileGestaltCacheLayout.originalProfile
        var profileCache = Data(count: profile.byteCount)
        profileCache[profile.greenTeaOffset] = 1
        profileCache[profile.validityOffset(for: profile.greenTeaIndex)] = 1
        profileCache[profile.validityOffset(for: profile.notGreenTeaIndex)] = 1
        let profileDoc = try GestaltDocument(data: PropertyListSerialization.data(fromPropertyList: [
            "CacheVersion": "24C5037i", "CacheUUID": profile.uuid,
            "CacheData": profileCache,
            "CacheExtra": [GestaltKeys.productType: "iPhone18,1", GestaltKeys.regionCode: "CH",
                           GestaltKeys.regionInfo: "CH/A", GestaltKeys.legacyRegionInfo: "CH/A",
                           GestaltKeys.modelNumber: "A3518"],
        ], format: .binary, options: 0))
        let snapshot = DocumentSnapshot(data: try profileDoc.encoded(), document: profileDoc,
                                        source: .local, name: "fixture")
        let manager = GestaltManager()
        manager.loadSnapshotForTests(snapshot)
        try expect(manager.aiConflicts.isEmpty, "Offline profile has no resolvable slots, so no conflicts")
        try expect(!manager.repairAIConflicts(), "Nothing to repair without conflicts")
        guard let before = manager.aiReadinessCheckup else { throw Failure(message: "Checkup exists for a loaded document") }
        try expect(before.readyCount == 2, "Unstaged fixture is 2/4 ready (regulatory model + AI eligibility via native hardware)")
        try expect(manager.fixAIReadiness() && manager.isChinaUnlockStaged,
                   "Fix stages the unlock when it is not staged")
        try expect(manager.aiReadinessCheckup?.isReady == true,
                   "Staged fixture is 4/4 ready")

        print("PASS: eligibility table, native baselines, 4-factor evaluation, AdvAI slot read/repair, and manager-level Fix staging.")
    }
}
