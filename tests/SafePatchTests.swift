// SPDX-License-Identifier: GPL-3.0-only
// Tests for SafePatch (修改模拟器): simulation diffs, the
// hardware-identity guard, unknown-model fail-closed, and the
// changed-snapshot refusal.
//
// The happy-path fixture is a known non-native model (iPhone14,7)
// with a document matching the offline `originalProfile` layout, so
// `resolve(in:)` succeeds on the test host and the profile is
// injected (the test host itself is an unknown model, which is
// exactly what the fail-closed test exercises).
import Foundation
import XCTest
@testable import GestaltX

final class SafePatchTests: XCTestCase {
    /// The 9-item one-tap unlock on a known non-native CH device:
    /// the simulation proceeds, the diff is exactly the 9 fields
    /// (region + 6 AI keys + the eSIM pair), the serialization
    /// round-trips, and the effect states show only "staged" as
    /// projected — the other three are confirmed only by real events.
    func testOneTapSimulationHappyPath() throws {
        let document = try CoreModuleFixtures.document()
        let snapshot = CoreModuleFixtures.snapshot(
            document: document,
            cachedOptions: try CachedOptionsOriginal(document: document),
            wapi: try WAPIOriginal(document: document))
        let profile = CoreModuleFixtures.profile(productType: "iPhone14,7", isNativeAI: false)
        let simulation = SafePatch.simulate(
            proposal: SafePatchProposal.oneTap(), snapshot: snapshot, profile: profile)
        XCTAssertTrue(simulation.canProceed, "One-tap must proceed on a known non-native CH device; blockers: \(simulation.blockers)")
        XCTAssertTrue(simulation.serializationOK, "The simulated document must encode and decode back to itself")
        XCTAssertNotNil(simulation.simulatedByteCount)
        XCTAssertTrue(simulation.hardwareIdentityTouches.isEmpty,
                      "One-tap must not touch any hardware-identity field")
        XCTAssertEqual(simulation.diffs.count, 9,
                       "One-tap changes exactly 9 fields, got: \(simulation.diffs.map(\.key))")
        let regionDiff = simulation.diffs.first { $0.key == GestaltKeys.regionCode }
        XCTAssertEqual(regionDiff?.original, .string("CH"))
        XCTAssertEqual(regionDiff?.target, .string("LL"))
        XCTAssertEqual(regionDiff?.originalSource, .firstRecordedValue)
        for key in ChinaUnlock.aiCapabilityIDs.compactMap({ id in Capability.all.first { $0.id == id }?.keys.first }) {
            let diff = simulation.diffs.first { $0.key == key }
            XCTAssertEqual(diff?.original, .absent, "AI key \(key) was absent before staging")
            XCTAssertEqual(diff?.target, .bool(true))
        }
        let greenTea = simulation.diffs.first { $0.key == DeviceCacheOptions.greenTeaKey }
        XCTAssertEqual(greenTea?.original, .bool(true))
        XCTAssertEqual(greenTea?.target, .bool(false))
        XCTAssertEqual(greenTea?.originalSource, .recordedOriginal)
        let notGreenTea = simulation.diffs.first { $0.key == DeviceCacheOptions.notGreenTeaKey }
        XCTAssertEqual(notGreenTea?.original, .bool(false))
        XCTAssertEqual(notGreenTea?.target, .bool(true))
        let staged = simulation.effectStates.first { $0.effect == .staged }
        XCTAssertEqual(staged?.status, .notReached,
                       "A simulation only projects 'staged'; it never claims the write or the function is verified")
        XCTAssertTrue(simulation.effectStates.filter { $0.effect != .staged }
            .allSatisfy { $0.status == .notReached },
            "File-write, restart and function verification are confirmed only by real events")
    }

    /// Region-only proposal: the diff is exactly the region code,
    /// model-independent, and it proceeds without an injected profile.
    func testRegionOnlyProposalDiff() throws {
        let document = try CoreModuleFixtures.document()
        let snapshot = CoreModuleFixtures.snapshot(
            document: document,
            originals: [GestaltKeys.regionCode: OriginalField(value: "CH")])
        let simulation = SafePatch.simulate(
            proposal: SafePatchProposal(featureIDs: [FeatureEligibilityEvaluator.regionCodeFeatureID]),
            snapshot: snapshot)
        XCTAssertTrue(simulation.canProceed, "Region staging is model-independent; blockers: \(simulation.blockers)")
        XCTAssertEqual(simulation.diffs.count, 1)
        XCTAssertEqual(simulation.diffs.first?.key, GestaltKeys.regionCode)
        XCTAssertEqual(simulation.diffs.first?.original, .string("CH"))
        XCTAssertEqual(simulation.diffs.first?.target, .string("LL"))
        XCTAssertEqual(simulation.diffs.first?.originalSource, .recordedOriginal)
    }

    /// Unknown model (the test host itself): the simulation blocks —
    /// fail-closed — because the model-dependent AI features cannot
    /// be judged. Nothing is staged, and the blockers name the model.
    func testUnknownModelBlocksSimulation() throws {
        let document = try CoreModuleFixtures.document()
        let snapshot = CoreModuleFixtures.snapshot(document: document)
        let simulation = SafePatch.simulate(proposal: SafePatchProposal.oneTap(), snapshot: snapshot)
        XCTAssertFalse(simulation.canProceed,
                       "An unknown model must block the one-tap simulation")
        XCTAssertFalse(simulation.blockers.isEmpty, "The blockers must name why the simulation refused")
    }

    /// A current document that differs from the snapshot: the
    /// unchanged-since-snapshot check fails as a blocker and the
    /// simulation refuses, even though the proposal itself is fine.
    func testSimulationRefusesChangedSnapshot() throws {
        let document = try CoreModuleFixtures.document()
        let snapshot = CoreModuleFixtures.snapshot(document: document)
        var changed = document
        changed.set("LL", for: GestaltKeys.regionCode)
        let profile = CoreModuleFixtures.profile(productType: "iPhone14,7", isNativeAI: false)
        let simulation = SafePatch.simulate(
            proposal: SafePatchProposal(featureIDs: [FeatureEligibilityEvaluator.regionCodeFeatureID]),
            snapshot: snapshot, currentDocument: changed, profile: profile)
        XCTAssertFalse(simulation.canProceed,
                       "A changed snapshot must block the simulation")
        let check = simulation.check(.unchangedSinceSnapshot)
        XCTAssertEqual(check?.passed, false)
        XCTAssertEqual(check?.isBlocker, true)
    }

    /// No snapshot at all: the trusted-original check fails as a
    /// blocker and the simulation refuses.
    func testSimulationWithoutSnapshotBlocks() {
        let simulation = SafePatch.simulate(
            proposal: SafePatchProposal.oneTap(), snapshot: nil)
        XCTAssertFalse(simulation.canProceed, "No snapshot must block the simulation")
        XCTAssertEqual(simulation.check(.trustedOriginal)?.passed, false)
        XCTAssertEqual(simulation.check(.trustedOriginal)?.isBlocker, true)
    }

    /// Hardware-identity guard (defense-in-depth): the one-tap
    /// proposal touches no identity field, and the guard's key set
    /// contains the product type, the model number, and the three
    /// obfuscated device-identity keys. The underlying invariant is
    /// that changing an identity key fails `preservesDeviceIdentity`.
    func testHardwareIdentityGuard() throws {
        let document = try CoreModuleFixtures.document()
        let snapshot = CoreModuleFixtures.snapshot(document: document)
        let profile = CoreModuleFixtures.profile(productType: "iPhone14,7", isNativeAI: false)
        let simulation = SafePatch.simulate(
            proposal: SafePatchProposal.oneTap(), snapshot: snapshot, profile: profile)
        XCTAssertEqual(simulation.check(.hardwareIdentity)?.passed, true)
        XCTAssertTrue(simulation.hardwareIdentityTouches.isEmpty)
        XCTAssertTrue(SafePatch.hardwareIdentityKeys.contains(GestaltKeys.productType))
        XCTAssertTrue(SafePatch.hardwareIdentityKeys.contains(GestaltKeys.modelNumber))
        XCTAssertTrue(SafePatch.hardwareIdentityKeys.contains("re6Zb+zwFKJNlkQTUeT+/w"))
        XCTAssertTrue(SafePatch.hardwareIdentityKeys.contains("VasUgeSzVyHdB27g2XpN0g"))
        XCTAssertTrue(SafePatch.hardwareIdentityKeys.contains("TF31PAB6aO8KAbPyNKSxKA"))
        var changed = document
        changed.set("iPhone99,9", for: GestaltKeys.productType)
        XCTAssertFalse(changed.preservesDeviceIdentity(of: document),
                       "Changing the product type must fail the device-identity check")
    }

    /// A proposal that would change nothing (region already LL):
    /// the diff check warns, the diff is empty, and the simulation
    /// still proceeds (nothing to do is not a blocker).
    func testNoOpProposalWarns() throws {
        let document = try CoreModuleFixtures.document(extra: [GestaltKeys.regionCode: "LL"])
        let snapshot = CoreModuleFixtures.snapshot(document: document)
        let simulation = SafePatch.simulate(
            proposal: SafePatchProposal(featureIDs: [FeatureEligibilityEvaluator.regionCodeFeatureID]),
            snapshot: snapshot)
        XCTAssertTrue(simulation.diffs.isEmpty, "Region already LL means nothing would change")
        XCTAssertEqual(simulation.check(.diff)?.passed, false)
        XCTAssertEqual(simulation.check(.diff)?.isBlocker, false,
                       "Changing nothing is a warning, not a blocker")
    }
}
