// SPDX-License-Identifier: GPL-3.0-only
// System Health Score (系统健康评分) — a diagnostic summary of this
// device's cache integrity, compatibility, backup state and
// modification risk. Pure Foundation — no SwiftUI, no UIKit, no
// singletons, no global mutable state.
//
// The score is computed from REAL data only: the device profile, the
// read snapshot, the backup inventory (with read-only verification
// results when the caller supplies them), an optional SafePatch
// simulation, the persisted change records, and the count of
// modifications the Modified Values report detected outside this
// app's records. Anything inaccessible lowers the score toward
// "unknown" — never fabricated, never defaulted to a plausible value.
//
// THE SCORE IS A DIAGNOSTIC SUMMARY ONLY. It never claims a device
// is "100% safe", "fully supported" or "guaranteed to work": a high
// score means the checks this app can run passed, not that the
// system will accept a change. The UI must carry that disclaimer,
// and no score here is ever presented as a safety guarantee.
import Foundation

// MARK: - Dimensions

/// One of the four scored dimensions.
enum HealthDimension: String, CaseIterable, Equatable, Sendable {
    case cacheIntegrity
    case compatibility
    case backup
    case modificationRisk

    var title: String {
        switch self {
        case .cacheIntegrity: return L("Cache integrity")
        case .compatibility: return L("Compatibility")
        case .backup: return L("Backup")
        case .modificationRisk: return L("Modification risk")
        }
    }
}

/// The level a score maps to. `.unknown` means the dimension could
/// not be scored at all (no evidence) — it is never shown as a
/// number, and it never raises the overall score.
enum HealthScoreLevel: String, Equatable, Sendable {
    case healthy
    case fair
    case poor
    case unknown

    var title: String {
        switch self {
        case .healthy: return L("Healthy")
        case .fair: return L("Fair")
        case .poor: return L("Needs attention")
        case .unknown: return L("Unknown")
        }
    }

    /// Level for a 0...100 score. 80 and above is healthy, 50 and
    /// above is fair, below 50 needs attention.
    static func level(for score: Int) -> HealthScoreLevel {
        if score >= 80 { return .healthy }
        if score >= 50 { return .fair }
        return .poor
    }
}

/// One dimension's score: 0...100, or `nil` when it could not be
/// scored at all. `reasons` explains every deduction in
/// user-facing words; an unscored dimension carries the reason it
/// could not be scored.
struct HealthDimensionScore: Equatable, Identifiable, Sendable {
    var id: HealthDimension { dimension }
    let dimension: HealthDimension
    let score: Int?
    let level: HealthScoreLevel
    let reasons: [String]
}

// MARK: - Result

/// The full health report: four dimension scores plus an overall
/// score (the mean of the dimensions that could be scored, or `nil`
/// when none could be). `summary` is a short human-readable line.
/// The disclaimer is always present: the score is diagnostic only.
struct SystemHealthScore: Equatable, Sendable {
    let dimensions: [HealthDimensionScore]
    let overallScore: Int?
    let overallLevel: HealthScoreLevel
    let summary: String

    /// The disclaimer every display of this score must carry.
    static let disclaimer = L("This score is a diagnostic summary only. It does not guarantee safety or that any feature will work.")

    func dimension(_ dimension: HealthDimension) -> HealthDimensionScore? {
        dimensions.first { $0.dimension == dimension }
    }
}

// MARK: - Scorer

/// Pure scoring over explicit inputs. Reads its inputs, writes
/// nothing, performs no file I/O: the caller supplies the backup
/// verification results (from `RestoreIntelligence.verifyBackups`),
/// the simulation (from `SafePatch.simulate`) and the recorded
/// changes (from `ChangeRecordStore`).
enum SystemHealthScorer {
    /// Scores the device. `snapshot` is `nil` when the device has
    /// never been read: then every dimension is unknown and the
    /// overall score is `nil` — an unread device is never scored
    /// as healthy or unhealthy.
    static func score(
        profile: DeviceProfile,
        snapshot: DocumentSnapshot?,
        backups: [BackupRecord],
        backupVerifications: [BackupVerification] = [],
        simulation: SafePatchSimulation? = nil,
        recordedChanges: [RecordedChange] = [],
        externalModificationCount: Int = 0
    ) -> SystemHealthScore {
        guard let snapshot else {
            let reason = L("No document has been read.")
            let dimensions = HealthDimension.allCases.map {
                HealthDimensionScore(dimension: $0, score: nil, level: .unknown, reasons: [reason])
            }
            return SystemHealthScore(
                dimensions: dimensions, overallScore: nil, overallLevel: .unknown,
                summary: L("No document has been read."))
        }
        let cache = scoreCacheIntegrity(profile: profile, snapshot: snapshot)
        let compatibility = scoreCompatibility(profile: profile)
        let backup = scoreBackup(backups: backups, verifications: backupVerifications)
        let risk = scoreModificationRisk(
            profile: profile, simulation: simulation,
            recordedChanges: recordedChanges,
            externalModificationCount: externalModificationCount)
        let dimensions = [cache, compatibility, backup, risk]
        let scored = dimensions.compactMap(\.score)
        // The overall score is capped at 99: no set of checks this
        // app can run proves the system will accept a change, so no
        // device is ever scored 100. The cap is part of the score,
        // not a display trick — a 100 would read as a guarantee.
        let overall: Int? = scored.isEmpty ? nil : min(scored.reduce(0, +) / scored.count, 99)
        let level: HealthScoreLevel = overall.map(HealthScoreLevel.level(for:)) ?? .unknown
        let summary: String
        if let overall {
            summary = String(format: L("Health score %d of 100. %@"), overall, level.title)
        } else {
            summary = L("Health could not be scored: no evidence was available.")
        }
        return SystemHealthScore(dimensions: dimensions, overallScore: overall,
                                 overallLevel: level, summary: summary)
    }

    // MARK: - Cache integrity (0...100; always scored when a snapshot exists)

    /// Layout resolved (40) + CacheUUID present (20) + recorded
    /// originals present (20) + document round-trips (20). A missing
    /// layout or a missing CacheUUID is a deduction with its reason,
    /// never a silent default.
    private static func scoreCacheIntegrity(
        profile: DeviceProfile, snapshot: DocumentSnapshot
    ) -> HealthDimensionScore {
        var score = 0
        var reasons: [String] = []
        if profile.cacheLayout.isKnown {
            score += 40
        } else {
            reasons.append(profile.cacheLayout.unknownReason
                ?? L("Unable to resolve this device's MobileGestalt cache layout."))
        }
        switch profile.cacheReadState {
        case .read(_, _):
            score += 20
        case .notRead:
            reasons.append(L("No document has been read."))
        case .failed(let reason):
            reasons.append(reason)
        }
        let hasOriginals = !snapshot.originals.isEmpty
            || snapshot.cachedOptionsOriginal != nil
            || snapshot.wapiOriginal != nil
        if hasOriginals {
            score += 20
        } else {
            reasons.append(L("No recorded original exists, so a precise restore cannot be guaranteed."))
        }
        if roundTrips(snapshot.document) {
            score += 20
        } else {
            reasons.append(L("The document could not be serialized and verified."))
        }
        if reasons.isEmpty {
            reasons.append(L("Cache layout resolved, CacheUUID present, originals recorded, document verified."))
        }
        return HealthDimensionScore(
            dimension: .cacheIntegrity, score: score,
            level: HealthScoreLevel.level(for: score), reasons: reasons)
    }

    /// In-memory serialization round-trip: the document must encode
    /// and decode back to itself. Pure, no file I/O.
    private static func roundTrips(_ document: GestaltDocument) -> Bool {
        guard let data = try? document.encoded(),
              let decoded = try? GestaltDocument(data: data) else { return false }
        return decoded.matches(document)
    }

    // MARK: - Compatibility (0...100, nil when the product type is unknown)

    /// Model known (40) + OS build known (20) + OS version known
    /// (10) + support scope recorded (30). An unknown model caps the
    /// score at 30: a device with an unknown model must NOT score
    /// high on compatibility. An unknown product type cannot be
    /// scored at all.
    private static func scoreCompatibility(profile: DeviceProfile) -> HealthDimensionScore {
        guard profile.productType.isKnown else {
            return HealthDimensionScore(
                dimension: .compatibility, score: nil, level: .unknown,
                reasons: [profile.productType.unknownReason ?? L("Device identity is unavailable.")])
        }
        var score = 0
        var reasons: [String] = []
        if profile.modelDecision.isKnown {
            score += 40
        } else {
            reasons.append(profile.modelDecision.reason
                ?? L("No US regulatory model known for this device — region code only."))
        }
        if profile.osBuild.isKnown {
            score += 20
        } else {
            reasons.append(profile.osBuild.unknownReason ?? L("Unknown build"))
        }
        if profile.osVersion.isKnown {
            score += 10
        } else {
            reasons.append(profile.osVersion.unknownReason ?? L("Unknown OS"))
        }
        if CompatibilityEntry.entry(for: profile.productType.value ?? "") != nil {
            score += 30
        } else {
            reasons.append(L("No verified OS-build compatibility table exists for this model, so OS-build compatibility is unknown."))
        }
        // Unknown model: cap at 30, whatever the other checks say.
        if !profile.modelDecision.isKnown {
            score = min(score, 30)
        }
        if reasons.isEmpty {
            reasons.append(L("Model, OS build and support scope are recorded for this device."))
        }
        return HealthDimensionScore(
            dimension: .compatibility, score: score,
            level: HealthScoreLevel.level(for: score), reasons: reasons)
    }

    // MARK: - Backup (0...100)

    /// Any backup exists (20) + a trusted-provenance backup (50) +
    /// a verified backup (30). No backups at all is 0. A trusted
    /// backup that has not been verified scores 70, with the reason
    /// saying verification is still pending — unverified is not
    /// verified.
    private static func scoreBackup(
        backups: [BackupRecord], verifications: [BackupVerification]
    ) -> HealthDimensionScore {
        guard !backups.isEmpty else {
            return HealthDimensionScore(
                dimension: .backup, score: 0, level: .poor,
                reasons: [L("No backups exist yet.")])
        }
        var score = 20
        var reasons: [String] = []
        if backups.contains(where: { $0.provenance.isTrustedForRestore }) {
            score += 50
        } else {
            reasons.append(L("No trusted backup exists yet."))
        }
        let verifiedCount = verifications.filter {
            if case .verified = $0.status { return true }
            return false
        }.count
        if verifiedCount > 0 {
            score += 30
        } else if verifications.isEmpty {
            reasons.append(L("Backups have not been verified yet."))
        } else {
            reasons.append(L("The backup could not be verified. No system changes were made."))
        }
        if reasons.isEmpty {
            reasons.append(L("A trusted, verified backup exists for restore."))
        }
        return HealthDimensionScore(
            dimension: .backup, score: score,
            level: HealthScoreLevel.level(for: score), reasons: reasons)
    }

    // MARK: - Modification risk (0...100, higher is safer)

    /// Starts at 100 and deducts: staged diffs (1–9: −10, 10+:
    /// −20), hardware-identity touches (score 0), a failed
    /// native/conflict check (−20), an unresolvable eSIM layout
    /// (−20), modifications detected outside this app's records
    /// (−10), recorded changes not verified as restored (−5 each,
    /// at most −15). The floor is 0.
    private static func scoreModificationRisk(
        profile: DeviceProfile,
        simulation: SafePatchSimulation?,
        recordedChanges: [RecordedChange],
        externalModificationCount: Int
    ) -> HealthDimensionScore {
        var score = 100
        var reasons: [String] = []
        if let simulation {
            switch simulation.diffs.count {
            case 0:
                break
            case 1...9:
                score -= 10
                reasons.append(String(format: L("Would change %d fields"), simulation.diffs.count))
            default:
                score -= 20
                reasons.append(String(format: L("Would change %d fields"), simulation.diffs.count))
            }
            if !simulation.hardwareIdentityTouches.isEmpty {
                score = 0
                reasons.append(L("This proposal touches a hardware-identity field. Staging it is refused."))
            }
            if let nativeCheck = simulation.check(.nativeAndConflicts), !nativeCheck.passed {
                score -= 20
                reasons.append(nativeCheck.reason)
            }
        }
        if !profile.cacheLayout.isKnown {
            score -= 20
            reasons.append(L("Unable to resolve this device's MobileGestalt cache layout."))
        }
        if externalModificationCount > 0 {
            score -= 10
            reasons.append(String(format: L("%d fields were modified outside this app's records."), externalModificationCount))
        }
        if !recordedChanges.isEmpty {
            let deduction = min(recordedChanges.count * 5, 15)
            score -= deduction
            reasons.append(String(format: L("%d recorded modifications have not been verified as restored."), recordedChanges.count))
        }
        score = max(score, 0)
        if reasons.isEmpty {
            reasons.append(L("No modifications recorded."))
        }
        return HealthDimensionScore(
            dimension: .modificationRisk, score: score,
            level: HealthScoreLevel.level(for: score), reasons: reasons)
    }
}
