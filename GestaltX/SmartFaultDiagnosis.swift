// SPDX-License-Identifier: GPL-3.0-only
// Smart Fault Diagnosis (智能故障诊断) — what went wrong, the most
// likely cause, and what to try next, from REAL data only. Pure
// Foundation — no SwiftUI, no UIKit, no singletons, no global mutable
// state.
//
// Inputs (all injected, all real — the engine reuses the other
// modules instead of re-implementing them):
//   • the device profile (model, OS build, cache layout),
//   • the system health score (four dimensions with reasons),
//   • the device fingerprint comparison (what changed since capture),
//   • the post-modification acceptance report (what stuck after restart),
//   • the backup inventory with read-only verification results,
//   • the per-feature eligibility evaluations (`.conflict` carries the
//     AI staging guard's reason),
//   • structured operation events (read/write/restore attempts and
//     guard firings), when the caller supplies them.
//
// Honesty rules, enforced by the types:
//   • A diagnosis is either KNOWN (`.known`) — the cause is
//     documented in this codebase or in a recorded observation — or
//     UNDETERMINED (`.undetermined`) — the cause has not been
//     determined, and the diagnosis states what was OBSERVED instead
//     of a cause. An undetermined diagnosis never invents a cause.
//   • A suggested fix is a suggestion, never a guarantee: no fix
//     string claims the fix will work, and the report carries that
//     disclaimer on every display.
//   • Evidence is always quoted from the inputs (a guard reason, a
//     health dimension reason, an acceptance summary, a changed
//     fingerprint field) — never synthesized.
//   • The engine stages nothing and writes nothing: it only reads its
//     inputs and returns a report.
//
// Known issues this engine recognizes (each with its documented cause):
//   • region reverted after restart (observed on iPhone 17 Pro Max
//     A3527: the region returns to CH after a restart),
//   • eSIM layout unresolvable (one-tap refused by the guard),
//   • AdvAI slot (#178/#266) unresolvable on native-AI hardware
//     (CacheExtra staged 1, CacheData slot natively 0 — separate values),
//   • hardware-identity guard refusal,
//   • backup missing / corrupt / from a different cache generation,
//   • no backup / backups unverified,
//   • fingerprint change invalidating the recorded support scope,
//   • file value vs live probe disagreement.
// Everything else — a failed read, write or restore — is reported as
// undetermined with the observed facts.
import Foundation

// MARK: - Severity

/// How urgent a diagnosis is. `.error` means a failure was observed
/// (a write did not verify, a backup is corrupt); `.warning` means a
/// change did not take effect or needs attention before staging;
/// `.info` means something is missing or unconfirmed, not broken.
enum FaultSeverity: String, Equatable, Sendable {
    case error
    case warning
    case info

    var title: String {
        switch self {
        case .error: return L("Error")
        case .warning: return L("Warning")
        case .info: return L("Note")
        }
    }

    /// Display order: errors first, then warnings, then notes.
    var sortOrder: Int {
        switch self {
        case .error: return 0
        case .warning: return 1
        case .info: return 2
        }
    }
}

// MARK: - Cause (known vs undetermined)

/// The cause of a fault. `.known` carries the documented cause.
/// `.undetermined` carries what was OBSERVED instead of a cause —
/// the cause has not been determined, and nothing here is a guess.
enum FaultCause: Equatable, Sendable {
    /// The cause is documented: the string states it.
    case known(String)
    /// The cause has not been determined: the string states what was
    /// observed instead of a cause — never a guessed cause.
    case undetermined(observed: String)

    var isKnown: Bool {
        if case .known = self { return true }
        return false
    }

    /// The user-facing cause text. For an undetermined cause this is
    /// the honest "not yet determined" line plus what was observed.
    var text: String {
        switch self {
        case .known(let cause):
            return cause
        case .undetermined(let observed):
            return L("Cause not yet determined.") + " " + observed
        }
    }
}

// MARK: - Operation events (structured session log input)

/// The kind of a structured operation event. Failure and guard
/// kinds are the ones the diagnosis engine has a rule for: a
/// success event carries no diagnosis. The four success kinds
/// (`readSucceeded`, `writeVerified`, `restoreSucceeded`,
/// `backupCreated`) exist for the operation log viewer (P4): they
/// record what happened, and the engine ignores them. Only the
/// kinds the manager layer actually records are ever produced —
/// in P4 that is `readSucceeded`, `readFailed` and
/// `backupCreated`; write, restore and guard events are not
/// connected yet (see `OperationEventRecorder`).
enum OperationEventKind: String, Equatable, Codable, Sendable {
    /// A read attempt succeeded.
    case readSucceeded
    /// A read attempt failed.
    case readFailed
    /// A write attempt verified.
    case writeVerified
    /// A write attempt did not verify.
    case writeFailed
    /// A restore attempt succeeded.
    case restoreSucceeded
    /// A restore attempt failed.
    case restoreFailed
    /// The eSIM layout guard refused staging: the layout could not
    /// be resolved.
    case guardLayoutUnresolved
    /// The hardware-identity guard refused staging: the proposal
    /// touched a hardware-identity field.
    case guardHardwareIdentity
    /// The native-AI conflict guard fired (CacheExtra staged vs the
    /// native CacheData slot).
    case guardNativeConflict
    /// An AdvAI CacheData slot (#178/#266) could not be located.
    case slotUnresolvable
    /// A backup was created.
    case backupCreated
    /// A backup failed verification.
    case backupFailed
    /// The region reverted after a restart.
    case regionReverted

    /// The user-facing title for the operation log viewer. Success
    /// kinds state what happened; failure and guard kinds reuse the
    /// diagnosis titles.
    var title: String {
        switch self {
        case .readSucceeded: return L("Read succeeded")
        case .readFailed: return L("Read failed")
        case .writeVerified: return L("File write verified")
        case .writeFailed: return L("Write did not verify")
        case .restoreSucceeded: return L("Restore succeeded")
        case .restoreFailed: return L("Restore failed")
        case .guardLayoutUnresolved: return L("eSIM layout could not be resolved")
        case .guardHardwareIdentity: return L("Hardware-identity change refused")
        case .guardNativeConflict: return L("Apple Intelligence slot could not be resolved")
        case .slotUnresolvable: return L("Apple Intelligence slot could not be resolved")
        case .backupCreated: return L("Backup saved")
        case .backupFailed: return L("Backup could not be verified")
        case .regionReverted: return L("Region reverted after restart")
        }
    }
}

/// One structured operation event: what happened, when, to which
/// key/feature, and the observed fact (a guard reason or error text).
/// `detail` is quoted as evidence, never parsed for a cause.
struct OperationEvent: Equatable, Identifiable, Sendable {
    let id: UUID
    let date: Date
    let kind: OperationEventKind
    /// The affected key or slot, when the event is about one.
    let key: String?
    /// The observed fact: a guard reason, an error description, or
    /// the acceptance outcome that was seen.
    let detail: String
    /// The feature this event belongs to, when known.
    let featureID: String?

    init(id: UUID = UUID(), date: Date = Date(), kind: OperationEventKind,
         key: String? = nil, detail: String, featureID: String? = nil) {
        self.id = id
        self.date = date
        self.kind = kind
        self.key = key
        self.detail = detail
        self.featureID = featureID
    }
}

// MARK: - Diagnosis and report

/// One diagnosed issue: what happened, the most likely cause (or an
/// honest "not yet determined" with what was observed), the evidence
/// it is based on, and a concrete suggested fix. `code` is the stable
/// machine-readable identifier (for example "region-reverted");
/// `relatedKeys` lists the cache keys the issue is about, when any.
struct FaultDiagnosis: Equatable, Identifiable, Sendable {
    var id: String { code }
    let code: String
    let severity: FaultSeverity
    let title: String
    let whatHappened: String
    let cause: FaultCause
    /// Evidence quoted from the inputs: guard reasons, health
    /// dimension reasons, acceptance summaries, changed fingerprint
    /// fields, or operation-event details. Never synthesized.
    let evidence: [String]
    /// A concrete suggested fix. Always a suggestion, never a
    /// guarantee — see `FaultDiagnosisReport.disclaimer`.
    let suggestedFix: String
    let relatedKeys: [String]
}

/// The diagnosis report for one run. `diagnoses` is sorted by
/// severity (errors, warnings, notes) in rule order within a
/// severity. `eventsConnected` is true only when structured operation
/// events were supplied: when false, write/restore/guard events are
/// not in this report, because the app does not record them yet.
struct FaultDiagnosisReport: Equatable, Sendable {
    let diagnoses: [FaultDiagnosis]
    let generatedAt: Date
    let summary: String
    let eventsConnected: Bool

    /// The disclaimer every display of this report must carry.
    static let disclaimer = L("A suggested fix is a suggestion, not a guarantee. It may not work on this device.")

    var errorCount: Int { diagnoses.filter { $0.severity == .error }.count }
    var warningCount: Int { diagnoses.filter { $0.severity == .warning }.count }
    var infoCount: Int { diagnoses.filter { $0.severity == .info }.count }
    var hasIssues: Bool { !diagnoses.isEmpty }

    func diagnosis(code: String) -> FaultDiagnosis? {
        diagnoses.first { diagnosis in diagnosis.code == code }
    }
}

// MARK: - Input

/// Everything the diagnosis engine reads. Every field is optional or
/// empty by default: the engine diagnoses from whatever evidence the
/// caller could supply, and reports "no issues found" when the
/// supplied evidence shows none — it never invents evidence.
struct FaultDiagnosisInput: Sendable {
    /// The device profile, or `nil` when the device has never been read.
    let profile: DeviceProfile?
    /// The system health score, when the caller computed one.
    let health: SystemHealthScore?
    /// The stored-vs-current fingerprint comparison, when a stored
    /// fingerprint exists.
    let fingerprintComparison: FingerprintComparison?
    /// The post-modification acceptance report, when recorded changes
    /// were re-read.
    let acceptance: AcceptanceReport?
    /// The backup inventory (the records themselves).
    let backupRecords: [BackupRecord]
    /// Read-only verification results for the backup inventory.
    let backupVerifications: [BackupVerification]
    /// Per-feature eligibility evaluations; the engine uses the
    /// `.conflict` ones (they carry the AI staging guard's reason).
    let evaluations: [LilaFeatureEvaluation]
    /// Structured operation events, when the caller records them.
    let events: [OperationEvent]

    init(profile: DeviceProfile? = nil,
         health: SystemHealthScore? = nil,
         fingerprintComparison: FingerprintComparison? = nil,
         acceptance: AcceptanceReport? = nil,
         backupRecords: [BackupRecord] = [],
         backupVerifications: [BackupVerification] = [],
         evaluations: [LilaFeatureEvaluation] = [],
         events: [OperationEvent] = []) {
        self.profile = profile
        self.health = health
        self.fingerprintComparison = fingerprintComparison
        self.acceptance = acceptance
        self.backupRecords = backupRecords
        self.backupVerifications = backupVerifications
        self.evaluations = evaluations
        self.events = events
    }
}

// MARK: - Engine

/// Pure diagnosis over explicit inputs. Reads its inputs, writes
/// nothing, performs no file I/O. One diagnosis per issue code at
/// most: the same issue seen through two inputs (for example a layout
/// failure in both the profile and an operation event) is reported
/// once, with the evidence from both.
enum SmartFaultDiagnosis {
    /// The two AdvAI CacheData slots (#178 audio intelligence, #266
    /// personal translator): the only slots the diagnosis attributes
    /// to the native-AI conflict.
    private static let advAIKeys: Set<String> = [
        DeviceCacheOptions.audioIntelligenceKey,
        DeviceCacheOptions.personalTranslatorKey,
    ]

    private static let advAIFeatureIDs: Set<String> = [
        "audioIntelligence", "personalTranslator",
    ]

    static func diagnose(_ input: FaultDiagnosisInput) -> FaultDiagnosisReport {
        var ordered: [(order: Int, diagnosis: FaultDiagnosis)] = []
        var seen = Set<String>()
        func add(_ diagnosis: FaultDiagnosis) {
            guard seen.insert(diagnosis.code).inserted else { return }
            ordered.append((order: ordered.count, diagnosis: diagnosis))
        }

        diagnoseNeverRead(input, add: add)
        diagnoseRegionReverted(input, add: add)
        diagnoseLayoutUnresolved(input, add: add)
        diagnoseAdvAISlot(input, add: add)
        diagnoseHardwareIdentityGuard(input, add: add)
        diagnoseBackups(input, add: add)
        diagnoseFingerprint(input, add: add)
        diagnoseAcceptance(input, add: add)
        diagnoseHealth(input, add: add)
        diagnoseFailedOperations(input, add: add)

        let diagnoses = ordered
            .sorted { left, right in
                if left.diagnosis.severity.sortOrder != right.diagnosis.severity.sortOrder {
                    return left.diagnosis.severity.sortOrder < right.diagnosis.severity.sortOrder
                }
                return left.order < right.order
            }
            .map { entry in entry.diagnosis }
        let summary: String
        if diagnoses.isEmpty {
            summary = L("No issues were found in the available data.")
        } else {
            let errors = diagnoses.filter { diagnosis in diagnosis.severity == .error }.count
            let warnings = diagnoses.filter { diagnosis in diagnosis.severity == .warning }.count
            let notes = diagnoses.filter { diagnosis in diagnosis.severity == .info }.count
            summary = String(format: L("%d errors, %d warnings, %d notes"), errors, warnings, notes)
        }
        return FaultDiagnosisReport(
            diagnoses: diagnoses, generatedAt: Date(), summary: summary,
            eventsConnected: !input.events.isEmpty)
    }

    // MARK: - Never read

    private static func diagnoseNeverRead(
        _ input: FaultDiagnosisInput, add: (FaultDiagnosis) -> Void
    ) {
        guard input.profile == nil else { return }
        add(FaultDiagnosis(
            code: "never-read", severity: .info,
            title: L("Device not read yet"),
            whatHappened: L("No document has been read."),
            cause: .known(L("No read has happened yet, so there is nothing to diagnose.")),
            evidence: [],
            suggestedFix: L("Read the device to see its current state."),
            relatedKeys: []))
    }

    // MARK: - Region reverted after restart (known)

    private static func diagnoseRegionReverted(
        _ input: FaultDiagnosisInput, add: (FaultDiagnosis) -> Void
    ) {
        let acceptanceReverted: Bool = {
            guard let acceptance = input.acceptance else { return false }
            return acceptance.restartConfirmed
                && acceptance.revertedKeys.contains(GestaltKeys.regionCode)
        }()
        let revertedEvents = input.events.filter { event in event.kind == .regionReverted }
        guard acceptanceReverted || !revertedEvents.isEmpty else { return }
        var evidence: [String] = []
        if let acceptance = input.acceptance, acceptanceReverted {
            evidence.append(acceptance.summary)
        }
        evidence.append(contentsOf: revertedEvents.map { event in event.detail })
        add(FaultDiagnosis(
            code: "region-reverted", severity: .warning,
            title: L("Region reverted after restart"),
            whatHappened: L("The region code is back to its original value in the re-read document."),
            cause: .known(L("The system rebuilt the cached region value on restart instead of keeping the staged value. This has been observed on iPhone 17 Pro Max (A3527): the region returned to CH after a restart.")),
            evidence: evidence,
            suggestedFix: L("Confirm the device was restarted after applying, then re-read and check the acceptance report. If the region keeps reverting, restore from a verified backup."),
            relatedKeys: [GestaltKeys.regionCode]))
    }

    // MARK: - eSIM layout unresolvable (known)

    private static func diagnoseLayoutUnresolved(
        _ input: FaultDiagnosisInput, add: (FaultDiagnosis) -> Void
    ) {
        let layoutReason = input.profile?.cacheLayout.unknownReason
        let layoutEvents = input.events.filter { event in event.kind == .guardLayoutUnresolved }
        guard layoutReason != nil || !layoutEvents.isEmpty else { return }
        var evidence: [String] = []
        if let layoutReason { evidence.append(layoutReason) }
        evidence.append(contentsOf: layoutEvents.map { event in event.detail })
        add(FaultDiagnosis(
            code: "layout-unresolved", severity: .warning,
            title: L("eSIM layout could not be resolved"),
            whatHappened: L("The eSIM cache layout could not be resolved on this device."),
            cause: .known(L("The cache layout could not be resolved on this model and OS build, so eSIM staging was refused by the guard.")),
            evidence: evidence,
            suggestedFix: L("Re-read the device. If it keeps failing, note the model and iOS minor version — the layout may not be resolvable on this build."),
            relatedKeys: [DeviceCacheOptions.greenTeaKey, DeviceCacheOptions.notGreenTeaKey]))
    }

    // MARK: - AdvAI slot unresolvable / native conflict (known)

    private static func diagnoseAdvAISlot(
        _ input: FaultDiagnosisInput, add: (FaultDiagnosis) -> Void
    ) {
        let slotEvents = input.events.filter { event in
            event.kind == .slotUnresolvable && event.key.map { key in advAIKeys.contains(key) } == true
        }
        let guardEvents = input.events.filter { event in event.kind == .guardNativeConflict }
        let conflictEvaluations = input.evaluations.filter { evaluation in
            evaluation.eligibility == .conflict && advAIFeatureIDs.contains(evaluation.featureID)
        }
        let unreadableItems: [AcceptanceItem] = {
            guard let acceptance = input.acceptance else { return [] }
            return acceptance.items.filter { item in
                item.outcome == .unreadable && advAIKeys.contains(item.key)
            }
        }()
        guard !slotEvents.isEmpty || !guardEvents.isEmpty
                || !conflictEvaluations.isEmpty || !unreadableItems.isEmpty else { return }
        var evidence: [String] = []
        evidence.append(contentsOf: slotEvents.map { event in event.detail })
        evidence.append(contentsOf: guardEvents.map { event in event.detail })
        evidence.append(contentsOf: conflictEvaluations.map { evaluation in evaluation.reason })
        evidence.append(contentsOf: unreadableItems.map { item in item.title })
        let relatedKeys = Set(
            slotEvents.compactMap { event in event.key }
            + conflictEvaluations.compactMap { evaluation in
                Capability.all.first { capability in capability.id == evaluation.featureID }?.keys.first
            }
            + unreadableItems.map { item in item.key })
        add(FaultDiagnosis(
            code: "adv-ai-slot", severity: .warning,
            title: L("Apple Intelligence slot could not be resolved"),
            whatHappened: L("The CacheData slot for this key could not be located."),
            cause: .known(L("The CacheData slot for this key cannot be located on this device's layout. On native Apple Intelligence hardware the slot is natively off, while the CacheExtra key can be staged on — the two are separate values.")),
            evidence: evidence,
            suggestedFix: L("On native Apple Intelligence hardware, skip this item: the native slot stays off. Otherwise use the repair path, then re-read after a restart."),
            relatedKeys: Array(relatedKeys).sorted()))
    }

    // MARK: - Hardware-identity guard (known)

    private static func diagnoseHardwareIdentityGuard(
        _ input: FaultDiagnosisInput, add: (FaultDiagnosis) -> Void
    ) {
        let events = input.events.filter { event in event.kind == .guardHardwareIdentity }
        guard let first = events.first else { return }
        add(FaultDiagnosis(
            code: "hardware-identity-guard", severity: .warning,
            title: L("Hardware-identity change refused"),
            whatHappened: first.detail,
            cause: .known(L("The proposal touched a hardware-identity field. Staging it is refused by design: changing such a field can break Face ID or make the system discard the whole cache at boot.")),
            evidence: events.map { event in event.detail },
            suggestedFix: L("Remove hardware-identity fields from the proposal."),
            relatedKeys: []))
    }

    // MARK: - Backups (known)

    private static func diagnoseBackups(
        _ input: FaultDiagnosisInput, add: (FaultDiagnosis) -> Void
    ) {
        let verifications = input.backupVerifications
        let missing = verifications.filter { verification in
            verification.status == .notFound
        }
        if !missing.isEmpty {
            add(FaultDiagnosis(
                code: "backup-missing", severity: .error,
                title: L("Backup file is missing"),
                whatHappened: L("A backup file is missing from disk."),
                cause: .known(L("The backup file is no longer on disk.")),
                evidence: missing.map { verification in
                    String(format: L("Backup “%@” — file not found."), verification.record.reason)
                },
                suggestedFix: L("Create a fresh backup before changing anything. This record cannot be used to restore."),
                relatedKeys: []))
        }

        let failedEvents = input.events.filter { event in event.kind == .backupFailed }
        let corrupt = verifications.filter { verification in
            if case .failed = verification.status { return true }
            return false
        }
        if !corrupt.isEmpty || !failedEvents.isEmpty {
            var evidence: [String] = corrupt.map { verification in
                String(format: L("Backup “%@” — verification failed."), verification.record.reason)
            }
            evidence.append(contentsOf: failedEvents.map { event in event.detail })
            add(FaultDiagnosis(
                code: "backup-corrupt", severity: .error,
                title: L("Backup could not be verified"),
                whatHappened: L("The backup could not be verified. No system changes were made."),
                cause: .known(L("The file failed its byte-count, digest or plist check.")),
                evidence: evidence,
                suggestedFix: L("Do not restore from this backup. Create a fresh backup, and keep the failed file for inspection."),
                relatedKeys: []))
        }

        let mismatched = verifications.filter { verification in
            if case .verified = verification.status {
                return verification.layoutMatchesCurrent == false
            }
            return false
        }
        if !mismatched.isEmpty {
            add(FaultDiagnosis(
                code: "backup-layout-mismatch", severity: .warning,
                title: L("Backup is from a different cache generation"),
                whatHappened: L("A verified backup is from a different cache generation than the current document."),
                cause: .known(L("The backup was written from a different cache generation.")),
                evidence: mismatched.map { verification in
                    String(format: L("Backup “%@” — cache layout does not match the current document."),
                           verification.record.reason)
                },
                suggestedFix: L("Create a fresh backup on this build. Treat a restore from this backup as review-required."),
                relatedKeys: []))
        }

        if input.backupRecords.isEmpty {
            add(FaultDiagnosis(
                code: "backup-none", severity: .info,
                title: L("No backups yet"),
                whatHappened: L("No backups exist yet."),
                cause: .known(L("No backup has been created yet.")),
                evidence: [],
                suggestedFix: L("Create a backup before changing anything."),
                relatedKeys: []))
        } else if verifications.isEmpty {
            add(FaultDiagnosis(
                code: "backup-unverified", severity: .info,
                title: L("Backups have not been verified"),
                whatHappened: L("Backups have not been verified yet."),
                cause: .known(L("Backups exist, but none has been verified in this session.")),
                evidence: [],
                suggestedFix: L("Run backup verification before relying on a backup."),
                relatedKeys: []))
        }
    }

    // MARK: - Fingerprint (known when the scope is invalidated)

    private static func diagnoseFingerprint(
        _ input: FaultDiagnosisInput, add: (FaultDiagnosis) -> Void
    ) {
        guard let comparison = input.fingerprintComparison,
              !comparison.changes.isEmpty else { return }
        let fieldLines = comparison.changes.map { change in
            "\(change.displayName): \(change.old) → \(change.new)"
        }
        if comparison.invalidatesSupportScope {
            add(FaultDiagnosis(
                code: "fingerprint-invalidated", severity: .warning,
                title: L("Device changed — support scope needs re-verification"),
                whatHappened: L("Device identity or build changed since the last fingerprint."),
                cause: .known(L("The product type, OS build, cache layout or slot count changed since the fingerprint was captured, so the previously recorded support scope may no longer apply.")),
                evidence: fieldLines,
                suggestedFix: L("Re-verify support on this build before staging anything."),
                relatedKeys: []))
        } else {
            add(FaultDiagnosis(
                code: "device-state-changed", severity: .info,
                title: L("Device state changed since the last fingerprint"),
                whatHappened: L("Some device values changed since the fingerprint was captured."),
                cause: .undetermined(observed: L("Device values changed between the stored fingerprint and the current read.")),
                evidence: fieldLines,
                suggestedFix: L("No action is needed unless the change was unexpected — then review the change history."),
                relatedKeys: []))
        }
    }

    // MARK: - Acceptance: live disagreement (known) and unreadable (undetermined)

    private static func diagnoseAcceptance(
        _ input: FaultDiagnosisInput, add: (FaultDiagnosis) -> Void
    ) {
        guard let acceptance = input.acceptance else { return }
        let disagreeing = acceptance.items.filter { item in item.liveAgrees == false }
        if !disagreeing.isEmpty {
            add(FaultDiagnosis(
                code: "live-disagreement", severity: .warning,
                title: L("Live system disagrees with the file"),
                whatHappened: L("The live system answer disagrees with the file value."),
                cause: .known(L("The file holds the staged value, but the live system returns a different answer. A value in the file does not prove the system uses it.")),
                evidence: disagreeing.map { item in
                    "\(item.title) — \(L("Live probe disagrees with the staged value."))"
                },
                suggestedFix: L("Re-read after a restart and check the live probe again."),
                relatedKeys: disagreeing.map { item in item.key }))
        }
        let unreadable = acceptance.items.filter { item in
            item.outcome == .unreadable && !advAIKeys.contains(item.key)
        }
        if !unreadable.isEmpty {
            let titles = unreadable.map { item in item.title }
            add(FaultDiagnosis(
                code: "acceptance-unreadable", severity: .warning,
                title: L("Some fields could not be re-read"),
                whatHappened: String(format: L("%d fields could not be re-read."), unreadable.count),
                cause: .undetermined(observed: titles.joined(separator: "; ")),
                evidence: titles,
                suggestedFix: L("Re-read the device and check whether the fields can be read then."),
                relatedKeys: unreadable.map { item in item.key }))
        }
    }

    // MARK: - Health dimensions (undetermined — the dimension reasons are the evidence)

    private static func diagnoseHealth(
        _ input: FaultDiagnosisInput, add: (FaultDiagnosis) -> Void
    ) {
        if let health = input.health,
           let cache = health.dimension(.cacheIntegrity),
           cache.level == .poor,
           let profile = input.profile, profile.cacheLayout.isKnown {
            add(FaultDiagnosis(
                code: "cache-integrity", severity: .warning,
                title: L("Cache integrity needs attention"),
                whatHappened: L("The cache integrity checks did not all pass."),
                cause: .undetermined(observed: cache.reasons.joined(separator: " ")),
                evidence: cache.reasons,
                suggestedFix: L("Re-read the device and check whether the integrity checks pass then."),
                relatedKeys: []))
        }

        let compatibility = input.health?.dimension(.compatibility)
        if compatibility?.level == .unknown {
            add(FaultDiagnosis(
                code: "compatibility-unknown", severity: .info,
                title: L("Compatibility is unknown"),
                whatHappened: L("Compatibility could not be determined for this device."),
                cause: .undetermined(observed: compatibility?.reasons.joined(separator: " ") ?? ""),
                evidence: compatibility?.reasons ?? [],
                suggestedFix: L("Check whether this model is in the supported list, and re-read the device."),
                relatedKeys: []))
        } else if let profile = input.profile, !profile.productType.isKnown,
                  let reason = profile.productType.unknownReason {
            add(FaultDiagnosis(
                code: "compatibility-unknown", severity: .info,
                title: L("Compatibility is unknown"),
                whatHappened: L("Compatibility could not be determined for this device."),
                cause: .undetermined(observed: reason),
                evidence: [reason],
                suggestedFix: L("Check whether this model is in the supported list, and re-read the device."),
                relatedKeys: []))
        }

        if let health = input.health,
           let risk = health.dimension(.modificationRisk),
           risk.level == .poor {
            add(FaultDiagnosis(
                code: "modification-risk", severity: .warning,
                title: L("Modification risk needs attention"),
                whatHappened: L("The modification-risk checks did not all pass."),
                cause: .undetermined(observed: risk.reasons.joined(separator: " ")),
                evidence: risk.reasons,
                suggestedFix: L("Review the change history and the Modified Values report. If a change was unwanted, restore from a trusted backup."),
                relatedKeys: []))
        }
    }

    // MARK: - Failed operations (undetermined — never a guessed cause)

    private static func diagnoseFailedOperations(
        _ input: FaultDiagnosisInput, add: (FaultDiagnosis) -> Void
    ) {
        diagnoseFailedOperation(
            kind: .readFailed, code: "read-failed",
            title: L("Read failed"),
            whatHappened: L("A read attempt failed."),
            suggestedFix: L("Try reading again. If it keeps failing, check the App Group and signing state."),
            input: input, add: add)
        diagnoseFailedOperation(
            kind: .writeFailed, code: "write-failed",
            title: L("Write did not verify"),
            whatHappened: L("A write attempt did not verify."),
            suggestedFix: L("Do not retry the write blindly. Re-read the device to see its current state first."),
            input: input, add: add)
        diagnoseFailedOperation(
            kind: .restoreFailed, code: "restore-failed",
            title: L("Restore failed"),
            whatHappened: L("A restore attempt failed."),
            suggestedFix: L("Re-read the device and check the restore log. If the device is in an unwanted state, restore from a verified backup."),
            input: input, add: add)
    }

    /// One failed-operation diagnosis: the cause is undetermined by
    /// construction — the observed event details are the evidence,
    /// never a guessed cause.
    private static func diagnoseFailedOperation(
        kind: OperationEventKind, code: String, title: String,
        whatHappened: String, suggestedFix: String,
        input: FaultDiagnosisInput, add: (FaultDiagnosis) -> Void
    ) {
        let events = input.events.filter { event in event.kind == kind }
        guard let first = events.first else { return }
        add(FaultDiagnosis(
            code: code, severity: .error,
            title: title,
            whatHappened: whatHappened,
            cause: .undetermined(observed: first.detail),
            evidence: events.map { event in event.detail },
            suggestedFix: suggestedFix,
            relatedKeys: events.compactMap { event in event.key }))
    }
}
