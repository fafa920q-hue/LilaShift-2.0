// SPDX-License-Identifier: GPL-3.0-only
// Tests for Dependency Analyzer (功能依赖分析器): region as the
// master switch, the siriOnDevice/AI catalog conflict, the #178
// native-AI slot conflict, duplicate detection, and the unread
// device.
import Foundation
import XCTest
@testable import GestaltX

final class DependencyAnalyzerTests: XCTestCase {
    /// The 9-item one-tap on a known non-native CH device: every
    /// dependency is satisfied, no conflicts, no duplicates.
    func testOneTapSafeToStage() throws {
        let document = try CoreModuleFixtures.document()
        let snapshot = CoreModuleFixtures.snapshot(document: document)
        let profile = CoreModuleFixtures.profile(productType: "iPhone14,7", isNativeAI: false)
        let analysis = DependencyAnalyzer.analyze(
            featureIDs: SafePatchProposal.oneTap().featureIDs,
            profile: profile, snapshot: snapshot)
        XCTAssertEqual(analysis.verdict, .safeToStage)
        XCTAssertTrue(analysis.findings.isEmpty, "One-tap on the fixture must have no findings, got: \(analysis.findings)")
    }

    /// Region is the master switch: the AI-only preset without
    /// regionCode staged is missing its prerequisite, and the
    /// analysis says so with the resolver's missing-region code.
    func testAIOnlyWithoutRegionMissingPrerequisite() throws {
        let document = try CoreModuleFixtures.document()
        let snapshot = CoreModuleFixtures.snapshot(document: document)
        let profile = CoreModuleFixtures.profile(productType: "iPhone14,7", isNativeAI: false)
        let analysis = DependencyAnalyzer.analyze(
            featureIDs: SafePatchProposal.aiOnly().featureIDs,
            profile: profile, snapshot: snapshot)
        XCTAssertEqual(analysis.verdict, .missingPrerequisites)
        XCTAssertTrue(analysis.findings.contains {
            $0.kind == .dependency && $0.code == "missing-region" && $0.severity == .blocker
        }, "AI without region must report the missing-region prerequisite")
    }

    /// siriOnDevice conflicts with every AI capability in the
    /// catalog: selecting both is a conflict verdict, with a
    /// catalog-conflict finding on each side.
    func testSiriOnDeviceConflictsWithAI() throws {
        let document = try CoreModuleFixtures.document()
        let snapshot = CoreModuleFixtures.snapshot(document: document)
        let profile = CoreModuleFixtures.profile(productType: "iPhone14,7", isNativeAI: false)
        let analysis = DependencyAnalyzer.analyze(
            featureIDs: ["siriOnDevice", "ai"], profile: profile, snapshot: snapshot)
        XCTAssertEqual(analysis.verdict, .hasConflicts)
        XCTAssertTrue(analysis.findings.contains {
            $0.kind == .conflict && $0.code == "catalog-conflict" && $0.featureID == "ai"
        }, "AI must report its catalog conflict with siriOnDevice")
        XCTAssertTrue(analysis.findings.contains {
            $0.kind == .conflict && $0.code == "catalog-conflict" && $0.featureID == "siriOnDevice"
        }, "siriOnDevice must report its catalog conflict with AI")
    }

    /// #178: on native-AI hardware, CacheExtra `audioIntelligence`
    /// = 1 staged while its CacheData slot reads its native 0 is a
    /// conflict the analyzer surfaces with the native-conflict code
    /// — the AI-only preset on this device is not safe to stage.
    func testNativeAudioIntelligenceSlotConflict() throws {
        let (layout, document) = try CoreModuleFixtures.scannedLayoutAndDocument(
            extra: [DeviceCacheOptions.audioIntelligenceKey: NSNumber(value: 1)],
            audioSlot: false, translatorSlot: true)
        let profile = CoreModuleFixtures.profile(
            productType: "iPhone19,1", isNativeAI: true, layout: layout)
        let snapshot = CoreModuleFixtures.snapshot(document: document)
        let analysis = DependencyAnalyzer.analyze(
            featureIDs: SafePatchProposal.aiOnly().featureIDs,
            profile: profile, snapshot: snapshot)
        XCTAssertEqual(analysis.verdict, .hasConflicts)
        XCTAssertTrue(analysis.findings.contains {
            $0.kind == .conflict && $0.code == "native-conflict" && $0.featureID == "audioIntelligence"
        }, "The #178 conflict must be reported for audioIntelligence")
    }

    /// Selecting eSIM twice writes the same keys to the same values:
    /// a duplicate warning, not a blocker — the set stays safe to
    /// stage.
    func testDuplicateModificationIsWarningNotBlocker() throws {
        let document = try CoreModuleFixtures.document()
        let snapshot = CoreModuleFixtures.snapshot(document: document)
        let profile = CoreModuleFixtures.profile(productType: "iPhone14,7", isNativeAI: false)
        let featureIDs = SafePatchProposal.oneTap().featureIDs
            + [FeatureEligibilityEvaluator.esimFeatureID]
        let analysis = DependencyAnalyzer.analyze(
            featureIDs: featureIDs, profile: profile, snapshot: snapshot)
        XCTAssertEqual(analysis.verdict, .safeToStage,
                       "Duplicates are redundant, not blocking")
        XCTAssertTrue(analysis.findings.contains {
            $0.kind == .duplicate && $0.severity == .warning
                && $0.code.contains(DeviceCacheOptions.greenTeaKey)
        }, "The green-tea key written twice must be reported as a duplicate")
    }

    /// A device that has never been read cannot be analyzed: the
    /// verdict is unknown, with no findings invented.
    func testUnreadDeviceIsUnknown() {
        let profile = CoreModuleFixtures.profile(productType: "iPhone14,7", isNativeAI: false)
        let analysis = DependencyAnalyzer.analyze(
            featureIDs: SafePatchProposal.oneTap().featureIDs,
            profile: profile, snapshot: nil)
        XCTAssertEqual(analysis.verdict, .unknown)
        XCTAssertTrue(analysis.findings.isEmpty)
    }

    /// The eSIM preset on a device whose layout cannot resolve is
    /// missing its prerequisite: the layout-unresolved blocker.
    func testESIMWithoutLayoutMissingPrerequisite() throws {
        let document = try CoreModuleFixtures.document()
        let snapshot = CoreModuleFixtures.snapshot(document: document)
        var profile = CoreModuleFixtures.profile(productType: "iPhone14,7", isNativeAI: false)
        profile = DeviceProfile(
            productType: profile.productType, modelNumber: profile.modelNumber,
            osVersion: profile.osVersion, osBuild: profile.osBuild,
            regionCode: profile.regionCode, salesRegionSuffix: profile.salesRegionSuffix,
            isNativeAppleIntelligence: profile.isNativeAppleIntelligence,
            modelDecision: profile.modelDecision,
            cacheLayout: .unknown(reason: "test: no layout"),
            cacheReadState: profile.cacheReadState,
            liveAIEnabled: profile.liveAIEnabled, liveRegionCode: profile.liveRegionCode,
            appGroupAvailable: profile.appGroupAvailable,
            shareExtensionPresent: profile.shareExtensionPresent,
            backupCount: profile.backupCount, hasTrustedBackup: profile.hasTrustedBackup,
            changeRecordCount: profile.changeRecordCount)
        let analysis = DependencyAnalyzer.analyze(
            featureIDs: SafePatchProposal.esimRegion().featureIDs,
            profile: profile, snapshot: snapshot)
        XCTAssertEqual(analysis.verdict, .missingPrerequisites)
        XCTAssertTrue(analysis.findings.contains {
            $0.kind == .dependency && $0.code == "layout-unresolved"
        }, "eSIM without a resolved layout must report layout-unresolved")
    }
}
