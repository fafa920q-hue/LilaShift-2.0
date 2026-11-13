// SPDX-License-Identifier: GPL-3.0-only
// Tests for System Health Score (系统健康评分): the unread device
// is unknown, a known device with full evidence scores healthy, an
// unknown model scores low on compatibility, and the overall score
// never reaches 100.
import Foundation
import XCTest
@testable import GestaltX

final class SystemHealthScoreTests: XCTestCase {
    /// A device that has never been read scores nothing: every
    /// dimension is unknown and the overall score is nil — an
    /// unread device is never scored as healthy or unhealthy.
    func testUnreadDeviceScoresUnknown() {
        let profile = CoreModuleFixtures.profile(productType: "iPhone14,7", isNativeAI: false)
        let score = SystemHealthScorer.score(profile: profile, snapshot: nil, backups: [])
        XCTAssertNil(score.overallScore, "An unread device has no overall score")
        XCTAssertEqual(score.overallLevel, .unknown)
        XCTAssertTrue(score.dimensions.allSatisfy { $0.score == nil && $0.level == .unknown },
                      "Every dimension is unknown for an unread device")
    }

    /// A known device with full evidence: layout resolved, CacheUUID
    /// present, originals recorded, document round-trips, model and
    /// build known, support scope recorded, a trusted verified
    /// backup, and a one-tap simulation with 9 diffs. Cache,
    /// compatibility and backup score 100; risk scores 90 (9 staged
    /// fields deduct 10); the overall is the mean, capped at 99.
    func testKnownDeviceWithFullEvidenceScoresHealthy() throws {
        let document = try CoreModuleFixtures.document()
        let snapshot = CoreModuleFixtures.snapshot(
            document: document,
            originals: [GestaltKeys.regionCode: OriginalField(value: "CH")],
            cachedOptions: try CachedOptionsOriginal(document: document),
            wapi: try WAPIOriginal(document: document))
        let profile = CoreModuleFixtures.profile(productType: "iPhone14,7", isNativeAI: false)
        let backup = BackupRecord(
            id: UUID(), date: Date(), reason: "test", source: .device,
            deviceID: "test", byteCount: 6480, sha256: "00",
            provenance: .verifiedFactory)
        let simulation = SafePatch.simulate(
            proposal: SafePatchProposal.oneTap(), snapshot: snapshot, profile: profile)
        let score = SystemHealthScorer.score(
            profile: profile, snapshot: snapshot, backups: [backup],
            backupVerifications: [BackupVerification(record: backup, status: .verified, layoutMatchesCurrent: true)],
            simulation: simulation)
        XCTAssertEqual(score.dimension(.cacheIntegrity)?.score, 100)
        XCTAssertEqual(score.dimension(.compatibility)?.score, 100)
        XCTAssertEqual(score.dimension(.backup)?.score, 100)
        XCTAssertEqual(score.dimension(.modificationRisk)?.score, 90,
                       "9 staged fields deduct 10 from the risk dimension")
        XCTAssertEqual(score.overallScore, 97, "Mean of 100, 100, 100 and 90")
        XCTAssertEqual(score.overallLevel, .healthy)
    }

    /// An unknown model must NOT score high on compatibility: no
    /// model points, no support-scope points, and the total is
    /// capped at 30 even though the OS build and version are known.
    func testUnknownModelScoresLowOnCompatibility() throws {
        let document = try CoreModuleFixtures.document()
        let snapshot = CoreModuleFixtures.snapshot(document: document)
        let profile = CoreModuleFixtures.profile(productType: "iPhone99,9", isNativeAI: false)
        let score = SystemHealthScorer.score(profile: profile, snapshot: snapshot, backups: [])
        XCTAssertEqual(score.dimension(.compatibility)?.score, 30,
                       "Unknown model: 20 for the build + 10 for the version, capped at 30")
        XCTAssertEqual(score.dimension(.compatibility)?.level, .poor)
        XCTAssertLessThan(score.overallScore ?? 100, 80,
                          "An unknown model can never score healthy overall")
    }

    /// The overall score never reaches 100, even with perfect
    /// evidence everywhere: no check this app can run proves the
    /// system will accept a change.
    func testOverallScoreNeverReaches100() throws {
        let document = try CoreModuleFixtures.document()
        let snapshot = CoreModuleFixtures.snapshot(
            document: document,
            originals: [GestaltKeys.regionCode: OriginalField(value: "CH")],
            cachedOptions: try CachedOptionsOriginal(document: document),
            wapi: try WAPIOriginal(document: document))
        let profile = CoreModuleFixtures.profile(productType: "iPhone14,7", isNativeAI: false)
        let backup = BackupRecord(
            id: UUID(), date: Date(), reason: "test", source: .device,
            deviceID: "test", byteCount: 6480, sha256: "00",
            provenance: .verifiedFactory)
        let score = SystemHealthScorer.score(
            profile: profile, snapshot: snapshot, backups: [backup],
            backupVerifications: [BackupVerification(record: backup, status: .verified, layoutMatchesCurrent: true)])
        XCTAssertEqual(score.dimension(.cacheIntegrity)?.score, 100)
        XCTAssertEqual(score.dimension(.compatibility)?.score, 100)
        XCTAssertEqual(score.dimension(.backup)?.score, 100)
        XCTAssertEqual(score.dimension(.modificationRisk)?.score, 100)
        XCTAssertEqual(score.overallScore, 99, "The overall score is capped at 99, never 100")
        XCTAssertEqual(score.overallLevel, .healthy)
    }

    /// No backups at all is a backup score of 0, with the reason
    /// saying so — never a silent default.
    func testNoBackupsScoresZeroOnBackup() throws {
        let document = try CoreModuleFixtures.document()
        let snapshot = CoreModuleFixtures.snapshot(document: document)
        let profile = CoreModuleFixtures.profile(productType: "iPhone14,7", isNativeAI: false)
        let score = SystemHealthScorer.score(profile: profile, snapshot: snapshot, backups: [])
        XCTAssertEqual(score.dimension(.backup)?.score, 0)
        XCTAssertEqual(score.dimension(.backup)?.level, .poor)
    }

    /// A hardware-identity touch in the simulation drops the risk
    /// dimension to 0, whatever else is true.
    func testHardwareIdentityTouchDropsRiskToZero() throws {
        let document = try CoreModuleFixtures.document()
        let snapshot = CoreModuleFixtures.snapshot(document: document)
        let profile = CoreModuleFixtures.profile(productType: "iPhone14,7", isNativeAI: false)
        let simulation = SafePatchSimulation(
            proposal: SafePatchProposal.oneTap(), checks: [], diffs: [],
            blockers: [], warnings: [],
            hardwareIdentityTouches: [GestaltKeys.productType],
            canProceed: false, serializationOK: false, backupReady: false,
            effectStates: [], simulatedByteCount: nil)
        let score = SystemHealthScorer.score(
            profile: profile, snapshot: snapshot, backups: [], simulation: simulation)
        XCTAssertEqual(score.dimension(.modificationRisk)?.score, 0,
                       "A hardware-identity touch is a risk score of 0")
    }
}
