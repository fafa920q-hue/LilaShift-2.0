import Foundation
import XCTest
@testable import GestaltX

/// Offline tests for the item-4 AI checkup and slot-only guards: the
/// eligibility table, the native-baseline override, the 4-factor
/// evaluation, the AdvAI slot read/write machinery on a synthetic
/// scanned layout, the CacheExtra-key vs CacheData-slot distinction, and
/// the `AIStagingGuard` decisions (conflicting combinations blocked with
/// a reason, unverified combinations warned, unknown baselines failed
/// closed) on native vs non-native hardware. The live MGCopyAnswer probe
/// is device-tested only.
final class AIReadinessTests: XCTestCase {
    struct Failure: Error { let message: String }
    static func put<T: FixedWidthInteger>(_ value: T, into data: inout Data, at offset: Int) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.replaceSubrange(offset..<(offset + $0.count), with: $0) }
    }

    static func evaluate(regionCode: String? = "LL",
                         regModel: String? = "A3518",
                         esimEnabled: Bool = true, conflicts: [AIConflict] = [],
                         aiEnabledCount: Int = 6, aiTotal: Int = 6,
                         productType: String = "iPhone16,2",
                         liveRegionCode: String? = nil, liveRegModel: String? = nil,
                         liveAIEnabled: Bool? = nil,
                         stagingDecision: AIStagingDecision? = nil) -> AIReadinessCheckup {
        AIReadinessCheckup.evaluate(
            regionCode: regionCode, regModel: regModel,
            esimEnabled: esimEnabled, conflicts: conflicts,
            aiEnabledCount: aiEnabledCount, aiTotal: aiTotal, productType: productType,
            liveRegionCode: liveRegionCode, liveRegModel: liveRegModel, liveAIEnabled: liveAIEnabled,
            stagingDecision: stagingDecision)
    }

    @MainActor
    func testAIReadiness() throws {
        ChinaUnlockRegionMode.stored = .regionCodeOnly

        // Eligibility table (fail closed: unknown models are not native).
        XCTAssert(DeviceAIEligibility.isNativeAppleIntelligence(productType: "iPhone16,2"),
                   "iPhone16,2 (15 Pro Max) is native-AI hardware")
        XCTAssert(!DeviceAIEligibility.isNativeAppleIntelligence(productType: "iPhone15,4"),
                   "iPhone15,4 (15) is not native-AI hardware")
        XCTAssert(DeviceAIEligibility.isNativeAppleIntelligence(productType: "iPhone19,7"),
                   "iPhone19,7 is native (explicitly listed, no prefix catch-all)")
        XCTAssert(!DeviceAIEligibility.isNativeAppleIntelligence(productType: "iPhone19,9"),
                   "iPhone19,9 is unlisted, so it defaults to not native")
        XCTAssert(!DeviceAIEligibility.isNativeAppleIntelligence(productType: "iPhone99,9"),
                   "Unknown future models default to not native")

        // Native baselines: a polluted backup cannot downgrade them.
        XCTAssert(DeviceAIEligibility.nativeAdvAISlotValue(key: DeviceCacheOptions.audioIntelligenceKey, productType: "iPhone16,2") == false,
                   "Audio Intelligence baseline is false on iPhone")
        XCTAssert(DeviceAIEligibility.nativeAdvAISlotValue(key: DeviceCacheOptions.audioIntelligenceKey, productType: "iPhone15,4") == nil,
                   "Audio Intelligence has no baseline on non-native hardware (exact membership only, no iPhone prefix)")
        XCTAssert(DeviceAIEligibility.nativeAdvAISlotValue(key: DeviceCacheOptions.audioIntelligenceKey, productType: "iPhone99,9") == nil,
                   "Audio Intelligence has no baseline on unlisted hardware")
        XCTAssert(DeviceAIEligibility.nativeAdvAISlotValue(key: DeviceCacheOptions.personalTranslatorKey, productType: "iPhone16,2") == true,
                   "Personal Translator baseline is true on a native-AI iPhone")
        XCTAssert(DeviceAIEligibility.nativeAdvAISlotValue(key: DeviceCacheOptions.personalTranslatorKey, productType: "iPhone15,4") == nil,
                   "Personal Translator has no forced baseline on non-native hardware")
        XCTAssert(DeviceAIEligibility.nativeAdvAISlotValue(key: DeviceCacheOptions.personalTranslatorKey, productType: "iPad16,1") == nil,
                   "Personal Translator has no forced baseline on iPad")

        // All-ready evaluation (LL-only, native hardware, staged unlock).
        let ready = Self.evaluate(liveRegionCode: "LL", liveAIEnabled: true)
        XCTAssert(ready.readyCount == 4 && ready.isReady, "Staged unlock on native hardware is 4/4 ready")
        XCTAssert(ready.factors[0].isLiveActive == true && ready.factors[3].isLiveActive == true,
                   "Live probe answers flow into the region and AI factors")
        let unknownLive = Self.evaluate()
        XCTAssert(unknownLive.factors[0].isLiveActive == nil,
                   "No probe answer renders live: unknown, never faked")

        // The one-tap unlock keeps the factory model and never stages a
        // sales-region suffix, so the checkup requires only the LL region
        // code and a present model number — never an LL/A suffix or a
        // mapped US model.
        let kept = Self.evaluate(regModel: "A3518")
        XCTAssert(kept.factors[1].isReady, "The kept factory model passes")
        XCTAssert(kept.factors[0].isReady, "The LL region code alone passes, with no sales-region suffix")
        let noModel = Self.evaluate(regModel: nil)
        XCTAssert(!noModel.factors[1].isReady, "A missing model number fails the regulatory-model factor")
        let wrongRegion = Self.evaluate(regionCode: "CH")
        XCTAssert(!wrongRegion.factors[0].isReady, "A CH region code fails the region factor")

        // A slot conflict fails the eSIM/conflict factor and names itself.
        let conflict = AIConflict.personalTranslatorSlotDisabled(slot: 266)
        let conflicted = Self.evaluate(conflicts: [conflict])
        XCTAssert(!conflicted.factors[2].isReady && conflicted.factors[2].detail == conflict.detail,
                   "A conflict fails factor 3 and its detail names the conflict")
        let locked = Self.evaluate(regionCode: "CH", esimEnabled: false, aiEnabledCount: 0,
                              productType: "iPhone15,4")
        XCTAssert(locked.readyCount == 1, "Locked non-native device is 1/4 ready (regulatory model only)")

        // Conflict details name the layer: a CacheData slot reading is
        // never presented as a CacheExtra key value, and an unresolved
        // slot number is never guessed. The Personal Translator triggers
        // are separate cases, one per layer.
        XCTAssert(AIConflict.personalTranslatorSlotDisabled(slot: 266).detail.contains("CacheData slot #266"),
                   "Personal Translator slot conflict names its CacheData slot number")
        XCTAssert(AIConflict.personalTranslatorKeyDisabled.detail.contains("CacheExtra key")
                   && !AIConflict.personalTranslatorKeyDisabled.detail.contains("CacheData slot #"),
                   "Personal Translator key conflict names the CacheExtra-key trigger, never a slot number")
        XCTAssert(AIConflict.audioIntelligenceEnabled(slot: 178).detail.contains("CacheData slot #178"),
                   "Audio Intelligence conflict names its CacheData slot number")
        XCTAssert(AIConflict.audioIntelligenceEnabled(slot: nil).detail.contains("CacheData slot")
                   && !AIConflict.audioIntelligenceEnabled(slot: nil).detail.contains("#"),
                   "Unresolved slot number is reported without a guessed number")
        XCTAssert(AIConflict.personalTranslatorSlotDisabled(slot: nil).detail.contains("CacheData slot reads 0")
                   && !AIConflict.personalTranslatorSlotDisabled(slot: nil).detail.contains("CacheExtra key"),
                   "Personal Translator slot conflict without a number names the slot layer only")
        XCTAssert(AIConflict.audioIntelligenceEnabled(slot: 178).layer == .cacheDataSlot
                   && AIConflict.personalTranslatorSlotDisabled(slot: 266).layer == .cacheDataSlot
                   && AIConflict.personalTranslatorKeyDisabled.layer == .cacheExtraKey,
                   "Conflict cases report which layer they fire on")

        // A guard decision flows into the checkup: block/warn fail factor
        // 3 with the decision's specific reason; allow leaves it ready.
        let blocked = AIStagingGuard.decide(AIStagingRequest(
            productType: "iPhone16,2", audioIntelligenceExtra: true,
            audioIntelligenceSlot: true, audioIntelligenceSlotIndex: 178))
        let blockedCheckup = Self.evaluate(stagingDecision: blocked)
        XCTAssert(!blockedCheckup.factors[2].isReady && blockedCheckup.factors[2].detail == blocked.reason,
                   "A blocked staging decision fails factor 3 with its specific reason")
        let warned = AIStagingGuard.decide(AIStagingRequest(
            productType: "iPhone16,2", audioIntelligenceExtra: true,
            personalTranslatorExtra: true, audioIntelligenceSlot: false,
            personalTranslatorSlot: true, audioIntelligenceSlotIndex: 178,
            personalTranslatorSlotIndex: 266))
        let warnedCheckup = Self.evaluate(stagingDecision: warned)
        XCTAssert(!warnedCheckup.factors[2].isReady && warnedCheckup.factors[2].detail == warned.reason,
                   "A warned (#178 unverified) decision fails factor 3 with its reason instead of silently staging")
        let allowed = AIStagingGuard.decide(AIStagingRequest(
            productType: "iPhone16,2", personalTranslatorExtra: true, personalTranslatorSlot: true))
        let allowedCheckup = Self.evaluate(stagingDecision: allowed)
        XCTAssert(allowedCheckup.factors[2].isReady, "An allowed staging decision leaves factor 3 ready")

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
            Self.put(pointers[i], into: &descriptors, at: i * 64)
            Self.put(Int16(i), into: &descriptors, at: i * 64 + 0x3A)
            Self.put(UInt32(11), into: &descriptors, at: i * 64 + 0x3C)
        }
        let layout = try MobileGestaltCacheLayout.scan(strings: strings, stringAddress: address, constants: [descriptors])
        XCTAssert(layout.audioIntellIndex == 4 && layout.personalTranslatorIndex == 5,
                   "Synthetic layout resolves both AdvAI slots")
        // Builds a document on the synthetic layout with chosen CacheData
        // slot values and chosen CacheExtra key values, so the two layers
        // can be varied independently. Slot indices 4/5 are the resolved
        // layout positions, not the per-device #178/#266 observations.
        func docWithSlots(audioSlot: Bool, translatorSlot: Bool, extraAudio: Int?, extraTranslator: Int?) throws -> GestaltDocument {
            var slotCache = Data(count: layout.byteCount)
            slotCache[layout.audioIntellOffset!] = audioSlot ? 1 : 0
            slotCache[layout.personalTranslatorOffset!] = translatorSlot ? 1 : 0
            slotCache[layout.validityOffset(for: 4)] = 1
            slotCache[layout.validityOffset(for: 5)] = 1
            slotCache[layout.greenTeaOffset] = 1
            slotCache[layout.validityOffset(for: layout.greenTeaIndex)] = 1
            slotCache[layout.validityOffset(for: layout.notGreenTeaIndex)] = 1
            var extra: [String: Any] = [GestaltKeys.productType: "iPhone16,2", GestaltKeys.regionCode: "CH"]
            if let extraAudio { extra[DeviceCacheOptions.audioIntelligenceKey] = NSNumber(value: extraAudio) }
            if let extraTranslator { extra[DeviceCacheOptions.personalTranslatorKey] = NSNumber(value: extraTranslator) }
            return try GestaltDocument(data: PropertyListSerialization.data(fromPropertyList: [
                "CacheVersion": "24C5037i", "CacheUUID": uuid,
                "CacheData": slotCache, "CacheExtra": extra,
            ], format: .binary, options: 0))
        }
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
        XCTAssert(DeviceCacheOptions.advAISlotValue(DeviceCacheOptions.audioIntelligenceKey, in: original, using: layout) == true,
                   "Audio Intelligence slot reads 1 from the fixture")
        XCTAssert(DeviceCacheOptions.advAISlotValue(DeviceCacheOptions.personalTranslatorKey, in: original, using: layout) == false,
                   "Personal Translator slot reads 0 from the fixture")
        var repaired = original
        try repaired.setAdvAISlot(DeviceCacheOptions.personalTranslatorKey, value: true, using: layout)
        XCTAssert(DeviceCacheOptions.advAISlotValue(DeviceCacheOptions.personalTranslatorKey, in: repaired, using: layout) == true,
                   "setAdvAISlot repairs the Personal Translator slot to its native baseline")
        try DeviceCacheOptions.validateEdit(from: original, to: repaired, using: layout)
        var untouched = original
        try untouched.setAdvAISlot(DeviceCacheOptions.greenTeaKey, value: false, using: layout)
        XCTAssert(untouched.matches(original), "setAdvAISlot ignores non-AdvAI keys")

        // CacheExtra key vs CacheData slot: the two layers share one
        // obfuscated key string as a lookup name only, and each layer's
        // value is independent of the other's.
        XCTAssert(Capability.all.first { $0.id == "audioIntelligence" }?.keys == [DeviceCacheOptions.audioIntelligenceKey]
                   && Capability.all.first { $0.id == "personalTranslator" }?.keys == [DeviceCacheOptions.personalTranslatorKey],
                   "The AI Capabilities and the CacheData slots share one obfuscated key string as a lookup name only")
        let slotOneKeyAbsent = try docWithSlots(audioSlot: true, translatorSlot: false, extraAudio: nil, extraTranslator: nil)
        XCTAssert(DeviceCacheOptions.advAISlotValue(DeviceCacheOptions.audioIntelligenceKey, in: slotOneKeyAbsent, using: layout) == true,
                   "CacheData slot reads 1 even when the CacheExtra key is absent")
        let slotZeroKeyOne = try docWithSlots(audioSlot: false, translatorSlot: true, extraAudio: 1, extraTranslator: 1)
        XCTAssert(DeviceCacheOptions.advAISlotValue(DeviceCacheOptions.audioIntelligenceKey, in: slotZeroKeyOne, using: layout) == false,
                   "CacheExtra audioIntelligence = 1 does not move the CacheData slot, which still reads 0")
        XCTAssert(DeviceCacheOptions.advAISlotValue(DeviceCacheOptions.personalTranslatorKey, in: slotZeroKeyOne, using: layout) == true,
                   "CacheExtra personalTranslator = 1 and a slot reading 1 agree, but the slot reading is independent of the key")
        XCTAssert(DeviceCacheOptions.advAISlotValue(DeviceCacheOptions.personalTranslatorKey, in: slotOneKeyAbsent, using: layout) == false,
                   "CacheData slot reads 0 even when the CacheExtra key is absent")

        // Staging guard on native-AI hardware (iPhone16,2): conflicting
        // combinations block with a reason, the unverified #178
        // combination warns, unknown baselines fail closed.
        let verifiedSafe = AIStagingGuard.decide(AIStagingRequest(
            productType: "iPhone16,2", personalTranslatorExtra: true,
            audioIntelligenceSlot: false, personalTranslatorSlot: true))
        XCTAssert(verifiedSafe.outcome == .allow && verifiedSafe.allowsAutoStage,
                   "Native hardware with slots at their baselines and no staged audio key allows auto-staging")
        let unverified178 = AIStagingGuard.decide(AIStagingRequest(
            productType: "iPhone16,2", audioIntelligenceExtra: true,
            personalTranslatorExtra: true, audioIntelligenceSlot: false,
            personalTranslatorSlot: true, audioIntelligenceSlotIndex: 178,
            personalTranslatorSlotIndex: 266))
        XCTAssert(unverified178.outcome == .warn && !unverified178.allowsAutoStage
                   && unverified178.requiresExplicitConfirmation
                   && unverified178.reason.contains("CacheExtra audioIntelligence")
                   && unverified178.reason.contains("CacheData slot #178"),
                   "Staging CacheExtra audioIntelligence = 1 on native hardware while CacheData slot #178 reads its native 0 warns with a specific reason, not silently")
        var confirmed178 = AIStagingRequest(
            productType: "iPhone16,2", audioIntelligenceExtra: true,
            personalTranslatorExtra: true, audioIntelligenceSlot: false,
            personalTranslatorSlot: true, audioIntelligenceSlotIndex: 178,
            personalTranslatorSlotIndex: 266)
        confirmed178.userConfirmedUnverifiedCombination = true
        XCTAssert(AIStagingGuard.decide(confirmed178).outcome == .allow,
                   "Explicit user confirmation is the only way through the #178 warning")
        let audioSlotConflict = AIStagingGuard.decide(AIStagingRequest(
            productType: "iPhone16,2", audioIntelligenceSlot: true,
            audioIntelligenceSlotIndex: 178))
        XCTAssert(audioSlotConflict.outcome == .block && audioSlotConflict.requiresSlotRepair
                   && audioSlotConflict.reason.contains("native baseline is 0"),
                   "Audio Intelligence CacheData slot reading 1 on native hardware blocks with a reason")
        let translatorSlotConflict = AIStagingGuard.decide(AIStagingRequest(
            productType: "iPhone16,2", personalTranslatorSlot: false,
            personalTranslatorSlotIndex: 266))
        XCTAssert(translatorSlotConflict.outcome == .block
                   && translatorSlotConflict.reason.contains("native baseline on a native-AI iPhone is 1"),
                   "Personal Translator CacheData slot reading 0 on native hardware blocks with a reason")
        let translatorKeyDisabled = AIStagingGuard.decide(AIStagingRequest(
            productType: "iPhone16,2", personalTranslatorExtra: false,
            personalTranslatorSlot: true))
        XCTAssert(translatorKeyDisabled.outcome == .block
                   && translatorKeyDisabled.reason.contains("CacheExtra key is explicitly 0"),
                   "Personal Translator CacheExtra key explicitly 0 on native hardware blocks with a reason naming the key layer")
        let unknownAudioBaseline = AIStagingGuard.decide(AIStagingRequest(
            productType: "iPhone16,2", audioIntelligenceExtra: true))
        XCTAssert(unknownAudioBaseline.outcome == .block && !unknownAudioBaseline.allowsAutoStage
                   && unknownAudioBaseline.reason.contains("did not resolve"),
                   "Staging audioIntelligence with an unresolvable CacheData slot fails closed: no live probe data, no auto-stage")
        let unknownTranslatorBaseline = AIStagingGuard.decide(AIStagingRequest(
            productType: "iPhone16,2", personalTranslatorExtra: true))
        XCTAssert(unknownTranslatorBaseline.outcome == .block
                   && unknownTranslatorBaseline.reason.contains("did not resolve"),
                   "Staging personalTranslator with an unresolvable CacheData slot fails closed")
        let liveProbeConflict = AIStagingGuard.decide(AIStagingRequest(
            productType: "iPhone16,2", personalTranslatorExtra: true,
            personalTranslatorSlot: true, liveAIEnabled: false))
        XCTAssert(liveProbeConflict.outcome == .warn
                   && liveProbeConflict.reason.contains("live probe"),
                   "A live probe reporting AI off on native hardware while AI keys are staged warns with a reason")

        // Staging guard on non-native hardware: no native baseline
        // applies, so staging is allowed — except a slot reading against
        // the recorded iPhone/iPad baseline, which warns.
        let nonNativeStaging = AIStagingGuard.decide(AIStagingRequest(
            productType: "iPhone15,4", audioIntelligenceExtra: true))
        XCTAssert(nonNativeStaging.outcome == .allow,
                   "Non-native hardware allows staging without a native baseline to verify")
        let nonNativeSlotOne = AIStagingGuard.decide(AIStagingRequest(
            productType: "iPhone15,4", audioIntelligenceSlot: true,
            audioIntelligenceSlotIndex: 178))
        XCTAssert(nonNativeSlotOne.outcome == .warn && !nonNativeSlotOne.requiresSlotRepair,
                   "Non-native hardware with an Audio Intelligence slot reading 1 warns instead of blocking")
        let nonNativeTranslatorZero = AIStagingGuard.decide(AIStagingRequest(
            productType: "iPhone15,4", personalTranslatorSlot: false))
        XCTAssert(nonNativeTranslatorZero.outcome == .allow,
                   "Non-native hardware has no Personal Translator baseline, so a slot reading 0 does not block")
        let unknownModel = AIStagingGuard.decide(AIStagingRequest(
            productType: "iPhone99,9", audioIntelligenceExtra: true))
        XCTAssert(unknownModel.outcome == .allow,
                   "Unknown future models default to not native, so the guard does not block staging on them")

        // Manager-level request building on the synthetic scanned layout:
        // the manager builds the guard request from a real document +
        // layout (current staged keys, resolved slot values), so the
        // wiring itself — not just the pure guard — is covered.
        let stagedBaseline = try docWithSlots(audioSlot: false, translatorSlot: true, extraAudio: 1, extraTranslator: 1)
        let stagedDecision = GestaltManager.stagingDecision(for: stagedBaseline, layout: layout, liveAIEnabled: nil, userConfirmedUnverifiedCombination: false, proposedUnlock: false)
        XCTAssert(stagedDecision?.outcome == .warn && stagedDecision?.requiresExplicitConfirmation == true,
                   "Manager decision warns for the staged #178 combination (CacheExtra audioIntelligence = 1, slot at its native 0)")
        let stagedConfirmed = GestaltManager.stagingDecision(for: stagedBaseline, layout: layout, liveAIEnabled: nil, userConfirmedUnverifiedCombination: true, proposedUnlock: false)
        XCTAssert(stagedConfirmed?.outcome == .allow,
                   "Manager decision allows the warned combination once the user confirmed it")
        let unstagedBaseline = try docWithSlots(audioSlot: false, translatorSlot: true, extraAudio: nil, extraTranslator: nil)
        let proposalDecision = GestaltManager.stagingDecision(for: unstagedBaseline, layout: layout, liveAIEnabled: nil, userConfirmedUnverifiedCombination: false, proposedUnlock: true)
        XCTAssert(proposalDecision?.outcome == .warn,
                   "Manager proposal decision warns for the unlock before it is staged (both guarded keys proposed as 1)")
        let unproposedDecision = GestaltManager.stagingDecision(for: unstagedBaseline, layout: layout, liveAIEnabled: nil, userConfirmedUnverifiedCombination: false, proposedUnlock: false)
        XCTAssert(unproposedDecision?.outcome == .allow,
                   "Manager decision allows when nothing is staged and the slots read their baselines")
        let slotConflictDoc = try docWithSlots(audioSlot: true, translatorSlot: true, extraAudio: nil, extraTranslator: nil)
        let slotConflictDecision = GestaltManager.stagingDecision(for: slotConflictDoc, layout: layout, liveAIEnabled: nil, userConfirmedUnverifiedCombination: false, proposedUnlock: false)
        XCTAssert(slotConflictDecision?.outcome == .block && slotConflictDecision?.requiresSlotRepair == true,
                   "Manager decision blocks when the Audio Intelligence slot reads 1, even with no key staged")
        let translatorConflictDoc = try docWithSlots(audioSlot: false, translatorSlot: false, extraAudio: nil, extraTranslator: nil)
        let translatorConflictDecision = GestaltManager.stagingDecision(for: translatorConflictDoc, layout: layout, liveAIEnabled: nil, userConfirmedUnverifiedCombination: false, proposedUnlock: false)
        XCTAssert(translatorConflictDecision?.outcome == .block,
                   "Manager decision blocks when the Personal Translator slot reads 0 on native hardware")

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
        XCTAssert(manager.aiConflicts.isEmpty, "Offline profile has no resolvable slots, so no conflicts")
        XCTAssert(manager.aiStagingDecision == nil,
                   "Offline profile carries no resolved AdvAI slot index, so the manager reports no staging decision (unobservable slots, not a block)")
        XCTAssert(!manager.repairAIConflicts(), "Nothing to repair without conflicts")
        guard let before = manager.aiReadinessCheckup else { throw Failure(message: "Checkup exists for a loaded document") }
        XCTAssert(before.readyCount == 2, "Unstaged fixture is 2/4 ready (regulatory model + AI eligibility via native hardware)")
        XCTAssert(manager.fixAIReadiness() && manager.isChinaUnlockStaged,
                   "Fix stages the unlock when it is not staged")
        XCTAssert(manager.aiReadinessCheckup?.isReady == true,
                   "Staged fixture is 4/4 ready")

    }
}
