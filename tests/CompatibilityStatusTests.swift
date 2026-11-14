// SPDX-License-Identifier: GPL-3.0-only
// Tests for the Phase F unified compatibility status model: the
// mapping from real inputs (evaluator eligibility, profile, snapshot
// / working documents, staged and restart-pending sets) to the eight
// display statuses, the China-offer rule, and the #178 warning.
//
// Fixtures come from `CoreModuleFixtures` (LilaIntelligenceTests):
// nothing here fabricates a detection value. The #178 decision is
// still open, so these tests assert only that the warning is SHOWN
// for the staged-vs-native conflict — never that a skip happens.
import Foundation
import XCTest
@testable import GestaltX

final class CompatibilityStatusTests: XCTestCase {
    private func profile(productType: String = "iPhone14,7", isNativeAI: Bool = false,
                        cacheReadState: CacheReadState? = nil) -> DeviceProfile {
        var base = CoreModuleFixtures.profile(productType: productType, isNativeAI: isNativeAI)
        if let cacheReadState {
            base = DeviceProfile(
                productType: base.productType, modelNumber: base.modelNumber,
                osVersion: base.osVersion, osBuild: base.osBuild,
                regionCode: base.regionCode, salesRegionSuffix: base.salesRegionSuffix,
                isNativeAppleIntelligence: base.isNativeAppleIntelligence,
                modelDecision: base.modelDecision, cacheLayout: base.cacheLayout,
                cacheReadState: cacheReadState, liveAIEnabled: base.liveAIEnabled,
                liveRegionCode: base.liveRegionCode,
                appGroupAvailable: base.appGroupAvailable,
                shareExtensionPresent: base.shareExtensionPresent,
                backupCount: base.backupCount, hasTrustedBackup: base.hasTrustedBackup,
                changeRecordCount: base.changeRecordCount)
        }
        return base
    }

    private func snapshot() throws -> DocumentSnapshot {
        CoreModuleFixtures.snapshot(document: try CoreModuleFixtures.document())
    }

    private func detail(
        featureID: String = "ai", eligibility: FeatureEligibility,
        reason: String = "test reason", profile: DeviceProfile,
        snapshot: DocumentSnapshot?, working: GestaltDocument? = nil,
        staged: Set<String> = [], pendingRestart: Set<String> = []
    ) -> CompatibilityStatusDetail {
        CompatibilityStatusResolver.resolve(
            featureID: featureID, eligibility: eligibility, reason: reason,
            profile: profile, documentRead: snapshot != nil, working: working,
            stagedFeatureIDs: staged, pendingRestartFeatureIDs: pendingRestart)
    }

    // MARK: - The eight statuses, one real input each

    func testNativeSupportedNeverRecommendsModification() throws {
        let result = detail(featureID: "ai", eligibility: .nativeSupported,
                            profile: profile(), snapshot: try snapshot())
        XCTAssertEqual(result.status, .nativeSupported)
        XCTAssertFalse(result.recommendsModification)
        XCTAssertFalse(result.restartRequired)
        XCTAssertTrue(result.evidence.contains(
            "Already supported on this device — no change needed."))
    }

    func testEligibleMapsToModifiableAndIsOffered() throws {
        let result = detail(featureID: "esim", eligibility: .eligibleToEnable,
                            profile: profile(), snapshot: try snapshot())
        XCTAssertEqual(result.status, .modifiable)
        XCTAssertTrue(result.recommendsModification)
        XCTAssertTrue(CompatibilityStatusResolver.isOffered(result))
    }

    func testAlreadyConfiguredMapsToEnabled() throws {
        let result = detail(featureID: "esim", eligibility: .alreadyConfigured,
                            profile: profile(), snapshot: try snapshot())
        XCTAssertEqual(result.status, .enabled)
        XCTAssertFalse(result.recommendsModification)
        XCTAssertFalse(CompatibilityStatusResolver.isOffered(result))
    }

    func testStagedBeatsEligible() throws {
        let result = detail(featureID: "esim", eligibility: .eligibleToEnable,
                            profile: profile(), snapshot: try snapshot(),
                            staged: ["esim"])
        XCTAssertEqual(result.status, .staged)
        XCTAssertTrue(result.restartRequired)
        XCTAssertFalse(result.recommendsModification)
    }

    func testPendingRestartBeatsEnabled() throws {
        let result = detail(featureID: "esim", eligibility: .alreadyConfigured,
                            profile: profile(), snapshot: try snapshot(),
                            pendingRestart: ["esim"])
        XCTAssertEqual(result.status, .needsRestart)
        XCTAssertTrue(result.restartRequired)
    }

    func testUnknownMapsToUnverifiedWithEvidence() throws {
        let result = detail(featureID: "siriOnDevice", eligibility: .unknown,
                            reason: "Keep-only: never auto-staged.",
                            profile: profile(), snapshot: try snapshot())
        XCTAssertEqual(result.status, .unverified)
        XCTAssertEqual(result.reason, "Keep-only: never auto-staged.")
        XCTAssertTrue(result.evidence.contains("Keep-only: never auto-staged."))
        XCTAssertFalse(result.recommendsModification)
        XCTAssertFalse(CompatibilityStatusResolver.isOffered(result))
    }

    func testConflictMapsToUnsupportedWithGuardReason() throws {
        let result = detail(featureID: "audioIntelligence", eligibility: .conflict,
                            reason: "Guard blocks this combination.",
                            profile: profile(productType: "iPhone16,2", isNativeAI: true),
                            snapshot: try snapshot())
        // A guard conflict is never presented as "can enable".
        XCTAssertEqual(result.status, .unsupported)
        XCTAssertEqual(result.reason, "Guard blocks this combination.")
        XCTAssertFalse(result.recommendsModification)
        XCTAssertFalse(CompatibilityStatusResolver.isOffered(result))
    }

    func testUnsupportedKeepsItsReason() throws {
        let result = detail(featureID: "esim", eligibility: .unsupported,
                            reason: "Not a China-market device.",
                            profile: profile(), snapshot: try snapshot())
        XCTAssertEqual(result.status, .unsupported)
        XCTAssertEqual(result.reason, "Not a China-market device.")
        XCTAssertFalse(CompatibilityStatusResolver.isOffered(result))
    }

    func testNoSnapshotIsReadFailedNotUnverified() {
        let result = detail(featureID: "ai", eligibility: .unknown,
                            profile: profile(), snapshot: nil)
        XCTAssertEqual(result.status, .readFailed)
        XCTAssertTrue(result.evidence.contains("No document has been read."))
    }

    func testFailedCacheReadIsReadFailed() throws {
        let failed = profile(cacheReadState: .failed(reason: "Cache read failed in test."))
        let result = detail(featureID: "ai", eligibility: .unknown,
                            profile: failed, snapshot: try snapshot())
        XCTAssertEqual(result.status, .readFailed)
        XCTAssertEqual(result.reason, "Cache read failed in test.")
    }

    func testNativeStaysNativeEvenWhenStaged() throws {
        let result = detail(featureID: "ai", eligibility: .nativeSupported,
                            profile: profile(), snapshot: try snapshot(),
                            staged: ["ai"])
        XCTAssertEqual(result.status, .nativeSupported)
        XCTAssertFalse(result.recommendsModification)
    }

    // MARK: - #178 warning (display only; no skip is implemented)

    func testNativeAIWarningShownForStagedAudioIntelligence() throws {
        let working = try CoreModuleFixtures.document(
            extra: [DeviceCacheOptions.audioIntelligenceKey: true])
        let warning = CompatibilityStatusResolver.nativeAIWarning(
            featureID: "audioIntelligence",
            profile: profile(productType: "iPhone16,2", isNativeAI: true),
            working: working)
        XCTAssertNotNil(warning, "Staged audioIntelligence on native-AI hardware must warn")
    }

    func testNativeAIWarningAbsentWhenNotStaged() throws {
        let working = try CoreModuleFixtures.document()
        let warning = CompatibilityStatusResolver.nativeAIWarning(
            featureID: "audioIntelligence",
            profile: profile(productType: "iPhone16,2", isNativeAI: true),
            working: working)
        XCTAssertNil(warning)
    }

    func testNativeAIWarningAbsentOnNonNativeHardware() throws {
        let working = try CoreModuleFixtures.document(
            extra: [DeviceCacheOptions.audioIntelligenceKey: true])
        let warning = CompatibilityStatusResolver.nativeAIWarning(
            featureID: "audioIntelligence",
            profile: profile(productType: "iPhone14,7", isNativeAI: false),
            working: working)
        XCTAssertNil(warning)
    }

    // MARK: - Staged / pending-restart derivation from real documents

    func testStagedFeatureIDsFromRegionChange() throws {
        let first = try CoreModuleFixtures.document()
        let staged = try CoreModuleFixtures.document(extra: [GestaltKeys.regionCode: "LL"])
        let ids = CompatibilityStatusResolver.stagedFeatureIDs(
            snapshot: CoreModuleFixtures.snapshot(document: first), working: staged)
        XCTAssertEqual(ids, [FeatureEligibilityEvaluator.regionCodeFeatureID])
    }

    func testStagedFeatureIDsEmptyWhenDocumentsMatch() throws {
        let doc = try CoreModuleFixtures.document()
        let ids = CompatibilityStatusResolver.stagedFeatureIDs(
            snapshot: CoreModuleFixtures.snapshot(document: doc), working: doc)
        XCTAssertTrue(ids.isEmpty)
    }

    func testStagedFeatureIDsFromESIMFlagChange() throws {
        let first = try CoreModuleFixtures.document(greenTea: true, notGreenTea: false)
        let staged = try CoreModuleFixtures.document(greenTea: false, notGreenTea: true)
        let ids = CompatibilityStatusResolver.stagedFeatureIDs(
            snapshot: CoreModuleFixtures.snapshot(document: first), working: staged)
        XCTAssertEqual(ids, [FeatureEligibilityEvaluator.esimFeatureID])
    }

    func testPendingRestartFeatureIDsOnlyUnverifiedRecords() {
        func record(featureID: String, restartVerified: Bool) -> RecordedChange {
            RecordedChange(id: UUID(), date: Date(), deviceID: "test-device",
                           osBuild: "23A344", featureID: featureID,
                           key: GestaltKeys.regionCode, layer: .cacheExtra,
                           original: .string("CH"), new: .string("LL"),
                           backupProvenance: .preModification, verified: true,
                           restartVerified: restartVerified)
        }
        let ids = CompatibilityStatusResolver.pendingRestartFeatureIDs(records: [
            record(featureID: "regionCode", restartVerified: false),
            record(featureID: "esim", restartVerified: true),
        ])
        XCTAssertEqual(ids, ["regionCode"])
    }

    // MARK: - Offer rule: only modifiable is offered

    func testOnlyModifiableIsOffered() throws {
        let snap = try snapshot()
        for eligibility in [FeatureEligibility.nativeSupported, .alreadyConfigured,
                            .unsupported, .unknown, .conflict] {
            let result = detail(featureID: "ai", eligibility: eligibility,
                                profile: profile(), snapshot: snap)
            XCTAssertFalse(CompatibilityStatusResolver.isOffered(result),
                           "\(eligibility) must never be offered as a modification")
        }
    }
}
