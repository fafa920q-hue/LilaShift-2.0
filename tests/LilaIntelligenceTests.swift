// SPDX-License-Identifier: GPL-3.0-only
// Tests for Lila Intelligence (紫序智能引擎): eligibility decisions
// including unknown-model fail-closed, native-skip, and the #178/#266
// CacheExtra-vs-CacheData conflict handling.
//
// Fixtures use the offline `originalProfile` layout (uuid
// 7F1DF278-..., 720 slots) so `MobileGestaltCacheLayout.resolve`
// succeeds on the test host, and a scanned layout (mirroring the
// DocumentTests scan fixture) for the AdvAI slots, which the offline
// profile does not resolve. No test fabricates a detection value:
// every profile is built from explicit fixture data.
import Foundation
import XCTest
@testable import GestaltX

/// Shared fixtures for the three core-module test files. All helpers
/// build real `GestaltDocument` / `MobileGestaltCacheLayout` /
/// `DeviceProfile` values from explicit data — nothing is faked.
enum CoreModuleFixtures {
    static let uuid = MobileGestaltCacheLayout.originalProfile.uuid
    static let layout = MobileGestaltCacheLayout.originalProfile

    /// CacheData bytes matching `originalProfile` (720 slots, 6480
    /// bytes). The eSIM and WAPI validity bytes are set to 1; slot
    /// values come from the arguments.
    static func cacheData(greenTea: Bool, notGreenTea: Bool, wapi: Bool) -> Data {
        var cache = Data(repeating: 0, count: layout.byteCount)
        func setSlot(_ index: Int, value: Bool) {
            cache[index * 8] = value ? 1 : 0
            cache[layout.validityOffset(for: index)] = 1
        }
        setSlot(layout.greenTeaIndex, value: greenTea)
        setSlot(layout.notGreenTeaIndex, value: notGreenTea)
        if let wapiIndex = layout.wapiIndex { setSlot(wapiIndex, value: wapi) }
        return cache
    }

    /// A document matching `originalProfile`. `extra` is merged over
    /// the base CacheExtra (region CH, product type iPhone14,7, no AI
    /// keys by default).
    static func document(extra: [String: Any] = [:], greenTea: Bool = true,
                         notGreenTea: Bool = false, wapi: Bool = true) throws -> GestaltDocument {
        var base: [String: Any] = [
            GestaltKeys.regionCode: "CH",
            GestaltKeys.productType: "iPhone14,7",
        ]
        for (key, value) in extra { base[key] = value }
        return try GestaltDocument(data: PropertyListSerialization.data(fromPropertyList: [
            "CacheUUID": uuid,
            "CacheData": cacheData(greenTea: greenTea, notGreenTea: notGreenTea, wapi: wapi),
            "CacheExtra": base,
        ], format: .binary, options: 0))
    }

    static func snapshot(document: GestaltDocument,
                         originals: [String: OriginalField] = [:],
                         cachedOptions: CachedOptionsOriginal? = nil,
                         wapi: WAPIOriginal? = nil) -> DocumentSnapshot {
        var snap = DocumentSnapshot(data: Data(), document: document, source: .device, name: "test")
        snap.originals = originals
        snap.cachedOptionsOriginal = cachedOptions
        snap.wapiOriginal = wapi
        return snap
    }

    /// A DeviceProfile for a known model. `layout` defaults to the
    /// `originalProfile` layout; pass a scanned layout for the AdvAI
    /// slot tests. `liveAIEnabled` defaults to unknown (no probe on
    /// the test host); pass `.known(true)` for the native-proof tests
    /// that need a live answer.
    static func profile(productType: String, isNativeAI: Bool, regionCode: String = "CH",
                        layout: MobileGestaltCacheLayout = MobileGestaltCacheLayout.originalProfile,
                        liveAIEnabled: ProfileValue<Bool> = .unknown(reason: "test")) -> DeviceProfile {
        DeviceProfile(
            productType: .known(productType),
            modelNumber: .known("A1234"),
            osVersion: .known("27.0.1"),
            osBuild: .known("23A344"),
            regionCode: .known(regionCode),
            salesRegionSuffix: .known(regionCode + "/A"),
            isNativeAppleIntelligence: .known(isNativeAI),
            modelDecision: DeviceModelSupport.decision(for: productType, originalRegModel: nil),
            cacheLayout: .known(layout),
            cacheReadState: .read(cacheUUID: uuid, byteCount: layout.byteCount),
            liveAIEnabled: liveAIEnabled,
            liveRegionCode: .known(regionCode),
            appGroupAvailable: .known(true),
            shareExtensionPresent: .known(false),
            backupCount: 0,
            hasTrustedBackup: false,
            changeRecordCount: 0)
    }

    /// A scanned layout with the two AdvAI slots resolved, plus a
    /// matching document. Mirrors the DocumentTests scan fixture.
    /// The AdvAI slots are the #178/#266 slots: their indices are
    /// resolved from the scan, never hardcoded.
    static func scannedLayoutAndDocument(extra: [String: Any] = [:], audioSlot: Bool,
                                         translatorSlot: Bool, greenTea: Bool = true,
                                         notGreenTea: Bool = false, wapi: Bool = true)
    throws -> (layout: MobileGestaltCacheLayout, document: GestaltDocument) {
        let uuid = "A4A4A4A4-1111-2222-3333-123456789ABC"
        let address: UInt64 = 0x180100000
        let keys = ["AAAAAAAAAAAAAAAAAAAAAA",
                    DeviceCacheOptions.greenTeaKey,
                    DeviceCacheOptions.notGreenTeaKey,
                    DeviceCacheOptions.wapiKey,
                    DeviceCacheOptions.audioIntelligenceKey,
                    DeviceCacheOptions.personalTranslatorKey,
                    "CCCCCCCCCCCCCCCCCCCCCC",
                    "DDDDDDDDDDDDDDDDDDDDDD"]
        var strings = Data((uuid + "\0").utf8)
        var pointers: [UInt64] = []
        for key in keys {
            pointers.append(address + UInt64(strings.count))
            strings.append(contentsOf: (key + "\0").utf8)
        }
        var descriptors = Data(repeating: 0, count: keys.count * 64)
        func put<T: FixedWidthInteger>(_ value: T, into bytes: inout Data, at offset: Int) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { bytes.replaceSubrange(offset..<(offset + $0.count), with: $0) }
        }
        for i in keys.indices {
            put(pointers[i] | 0xABCD_0000_0000_0000, into: &descriptors, at: i * 64)
            put(Int16(i), into: &descriptors, at: i * 64 + 0x3A)
            put(UInt32(11), into: &descriptors, at: i * 64 + 0x3C)
        }
        let layout = try MobileGestaltCacheLayout.scan(
            strings: strings, stringAddress: address, constants: [descriptors])
        var cache = Data(repeating: 0, count: layout.byteCount)
        func setSlot(_ index: Int, value: Bool) {
            cache[index * 8] = value ? 1 : 0
            cache[layout.validityOffset(for: index)] = 1
        }
        setSlot(layout.greenTeaIndex, value: greenTea)
        setSlot(layout.notGreenTeaIndex, value: notGreenTea)
        if let wapiIndex = layout.wapiIndex { setSlot(wapiIndex, value: wapi) }
        if let audioIndex = layout.slotIndex(forKey: DeviceCacheOptions.audioIntelligenceKey) {
            setSlot(audioIndex, value: audioSlot)
        }
        if let translatorIndex = layout.slotIndex(forKey: DeviceCacheOptions.personalTranslatorKey) {
            setSlot(translatorIndex, value: translatorSlot)
        }
        var base: [String: Any] = [
            GestaltKeys.regionCode: "CH",
            GestaltKeys.productType: "iPhone19,1",
        ]
        for (key, value) in extra { base[key] = value }
        let document = try GestaltDocument(data: PropertyListSerialization.data(fromPropertyList: [
            "CacheUUID": uuid,
            "CacheData": cache,
            "CacheExtra": base,
        ], format: .binary, options: 0))
        return (layout, document)
    }
}

final class LilaIntelligenceTests: XCTestCase {
    /// Unknown model: every model-dependent feature is read-only
    /// (`.unknown`) with the model decision's reason — fail-closed,
    /// never eligible. Region staging is model-independent and is
    /// NOT blocked by the model.
    func testUnknownModelFailsClosed() throws {
        let profile = CoreModuleFixtures.profile(productType: "iPhone99,9", isNativeAI: false)
        XCTAssertFalse(profile.modelDecision.isKnown, "iPhone99,9 has no verified mapping entry")
        let document = try CoreModuleFixtures.document()
        let snapshot = CoreModuleFixtures.snapshot(document: document)
        for featureID in ChinaUnlock.aiCapabilityIDs {
            let result = FeatureEligibilityEvaluator.evaluate(
                featureID: featureID, profile: profile, document: snapshot,
                layout: CoreModuleFixtures.layout, liveAIEnabled: nil,
                userConfirmedUnverifiedCombination: false)
            XCTAssertEqual(result.eligibility, .unknown,
                           "Unknown model must be read-only for \(featureID)")
        }
        let region = FeatureEligibilityEvaluator.evaluate(
            featureID: FeatureEligibilityEvaluator.regionCodeFeatureID, profile: profile,
            document: snapshot, layout: CoreModuleFixtures.layout, liveAIEnabled: nil,
            userConfirmedUnverifiedCombination: false)
        XCTAssertEqual(region.eligibility, .eligibleToEnable,
                       "Region staging is model-independent and stays eligible on an unknown model")
    }

    /// Native-AI hardware with the live probe on and both AdvAI slot
    /// baselines agreeing: the AI capabilities are natively supported
    /// and must NOT be re-staged.
    func testNativeAISkipsStaging() throws {
        let (layout, document) = try CoreModuleFixtures.scannedLayoutAndDocument(
            audioSlot: false, translatorSlot: true)
        let profile = CoreModuleFixtures.profile(
            productType: "iPhone19,1", isNativeAI: true, layout: layout,
            liveAIEnabled: .known(true))
        let snapshot = CoreModuleFixtures.snapshot(document: document)
        for featureID in ChinaUnlock.aiCapabilityIDs {
            let result = FeatureEligibilityEvaluator.evaluate(
                featureID: featureID, profile: profile, document: snapshot,
                layout: layout, liveAIEnabled: true,
                userConfirmedUnverifiedCombination: false)
            XCTAssertEqual(result.eligibility, .nativeSupported,
                           "Native hardware with agreeing slot baselines must be native-supported for \(featureID)")
        }
    }

    /// #178: on native-AI hardware, CacheExtra `audioIntelligence` = 1
    /// staged while its CacheData slot reads its native 0 is a
    /// conflict (`.warn` in the guard) — it must not be auto-staged
    /// silently. An explicit user confirmation is the only way
    /// through, and then the already-staged key reads as configured.
    func testAudioIntelligenceSlotConflict() throws {
        let (layout, document) = try CoreModuleFixtures.scannedLayoutAndDocument(
            extra: [DeviceCacheOptions.audioIntelligenceKey: NSNumber(value: 1)],
            audioSlot: false, translatorSlot: true)
        let profile = CoreModuleFixtures.profile(
            productType: "iPhone19,1", isNativeAI: true, layout: layout)
        let snapshot = CoreModuleFixtures.snapshot(document: document)
        let unconfirmed = FeatureEligibilityEvaluator.evaluate(
            featureID: "audioIntelligence", profile: profile, document: snapshot,
            layout: layout, liveAIEnabled: nil, userConfirmedUnverifiedCombination: false)
        XCTAssertEqual(unconfirmed.eligibility, .conflict,
                       "CacheExtra audioIntelligence=1 with slot 0 must conflict on native hardware")
        XCTAssertTrue(unconfirmed.reason.contains("slot"),
                      "The conflict reason must name the slot, got: \(unconfirmed.reason)")
        let confirmed = FeatureEligibilityEvaluator.evaluate(
            featureID: "audioIntelligence", profile: profile, document: snapshot,
            layout: layout, liveAIEnabled: nil, userConfirmedUnverifiedCombination: true)
        XCTAssertNotEqual(confirmed.eligibility, .conflict,
                          "An explicit confirmation must clear the #178 warn")
    }

    /// #266: on native-AI hardware, the Personal Translator CacheData
    /// slot reading 0 against its native baseline of 1 is a hard
    /// block — the slot must be repaired before staging.
    func testTranslatorSlotConflictBlocks() throws {
        let (layout, document) = try CoreModuleFixtures.scannedLayoutAndDocument(
            audioSlot: false, translatorSlot: false)
        let profile = CoreModuleFixtures.profile(
            productType: "iPhone19,1", isNativeAI: true, layout: layout)
        let snapshot = CoreModuleFixtures.snapshot(document: document)
        let result = FeatureEligibilityEvaluator.evaluate(
            featureID: "personalTranslator", profile: profile, document: snapshot,
            layout: layout, liveAIEnabled: nil, userConfirmedUnverifiedCombination: false)
        XCTAssertEqual(result.eligibility, .conflict,
                       "Personal Translator slot 0 against a native baseline of 1 must conflict")
    }

    /// eSIM needs a resolved layout and a CH region: no layout is
    /// unknown, a non-CH region is unsupported.
    func testESIMNeedsLayoutAndCHRegion() throws {
        let document = try CoreModuleFixtures.document()
        let snapshot = CoreModuleFixtures.snapshot(document: document)
        let profile = CoreModuleFixtures.profile(productType: "iPhone14,7", isNativeAI: false)
        let noLayout = FeatureEligibilityEvaluator.evaluate(
            featureID: FeatureEligibilityEvaluator.esimFeatureID, profile: profile,
            document: snapshot, layout: nil, liveAIEnabled: nil,
            userConfirmedUnverifiedCombination: false)
        XCTAssertEqual(noLayout.eligibility, .unknown,
                       "eSIM without a resolved layout must be unknown")
        let llProfile = CoreModuleFixtures.profile(
            productType: "iPhone14,7", isNativeAI: false, regionCode: "LL")
        let llDocument = try CoreModuleFixtures.document(extra: [GestaltKeys.regionCode: "LL"])
        let llSnapshot = CoreModuleFixtures.snapshot(document: llDocument)
        let nonChina = FeatureEligibilityEvaluator.evaluate(
            featureID: FeatureEligibilityEvaluator.esimFeatureID, profile: llProfile,
            document: llSnapshot, layout: CoreModuleFixtures.layout, liveAIEnabled: nil,
            userConfirmedUnverifiedCombination: false)
        XCTAssertEqual(nonChina.eligibility, .unsupported,
                       "eSIM on a non-CH device must be unsupported")
        let eligible = FeatureEligibilityEvaluator.evaluate(
            featureID: FeatureEligibilityEvaluator.esimFeatureID, profile: profile,
            document: snapshot, layout: CoreModuleFixtures.layout, liveAIEnabled: nil,
            userConfirmedUnverifiedCombination: false)
        XCTAssertEqual(eligible.eligibility, .eligibleToEnable,
                       "eSIM on a CH device with a resolved layout and restricted flags must be eligible")
    }

    /// The report is per-device: a native-AI device reports its AI
    /// capabilities as native, and the China Unlock recommendation
    /// carries blockers for them instead of staging steps.
    func testReportIsPerDevice() throws {
        let (layout, document) = try CoreModuleFixtures.scannedLayoutAndDocument(
            audioSlot: false, translatorSlot: true)
        let profile = CoreModuleFixtures.profile(
            productType: "iPhone19,1", isNativeAI: true, layout: layout,
            liveAIEnabled: .known(true))
        let snapshot = CoreModuleFixtures.snapshot(document: document)
        let report = LilaIntelligence.report(snapshot: snapshot, profile: profile)
        let aiEvaluations = report.evaluations.filter { ChinaUnlock.aiCapabilityIDs.contains($0.featureID) }
        XCTAssertEqual(aiEvaluations.count, ChinaUnlock.aiCapabilityIDs.count)
        XCTAssertTrue(aiEvaluations.allSatisfy { $0.eligibility == .nativeSupported },
                      "All six AI capabilities must be native-supported on this device")
        let aiSteps = report.chinaUnlockRecommendation.steps.filter {
            ChinaUnlock.aiCapabilityIDs.contains($0.featureID)
        }
        XCTAssertTrue(aiSteps.isEmpty, "No AI staging step may be built for native-supported features")
        XCTAssertFalse(report.chinaUnlockRecommendation.blockers.isEmpty,
                       "Native features must appear as blockers, not silently dropped")
    }
}
