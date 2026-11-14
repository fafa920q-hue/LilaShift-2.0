// SPDX-License-Identifier: GPL-3.0-only
// History & restore experience (Phase G) — ONE coherent
// presentation of the history data that already exists.
//
// The storage already exists (HistoryJournal / ChangeRecordStore /
// RestoreIntelligence / DeviceFingerprint /
// PostModificationAcceptance); this file only presents it as one
// unified view. It never writes the device file, never changes a
// record's meaning, and never adds a restore path: restore execution
// stays in GestaltManager's existing paths, reached only through the
// preview + second confirmation in the views.
//
// Honesty rules:
// - The first-read value is the "first-recorded value", never the
//   factory original. A first read cannot prove the device was
//   unmodified before this app first saw it; the label says so.
// - A staged value is shown only when the working document actually
//   differs from the first-recorded value for that key; otherwise
//   there is no staged change to show.
// - A restore preview must show, before execution: device identity,
//   file integrity, backup source, current system compatibility,
//   and the before/after diff. Anything that cannot be verified is
//   shown as unknown, never as verified.
// - High-risk operations (restore, apply) need a second
//   confirmation. `TwoStepConfirmation` is the gate the views use:
//   the first tap arms it (and reveals the preview), only the
//   second tap executes.
import Foundation

// MARK: - Unified history entry

/// One row of the unified history & restore view: the
/// first-recorded value, the current value, the staged value (when
/// there is one), the operation record behind it, the trusted
/// backups, the restore state and the verification results — all
/// from the existing stores, presented together.
struct UnifiedHistoryEntry: Equatable, Sendable, Identifiable {
    let id: UUID
    let date: Date
    let title: String
    let key: String
    let layer: ChangeLayer
    /// The value as first recorded. Labelled by
    /// `firstRecordedLabel` — "First-recorded value" for a first
    /// read, never "factory original" unless the provenance is
    /// `.verifiedFactory`.
    let firstRecordedValue: ChangeValue
    let firstRecordedLabel: String
    let currentValue: ChangeValue?
    /// The value in the working (staged) document, or `nil` when
    /// the working value equals the first-recorded value — i.e.
    /// there is no staged change for this key.
    let stagedValue: ChangeValue?
    let isRecordedOperation: Bool
    let backupProvenance: BackupProvenance
    let backupSourceLabel: String
    let restoreState: RestoreTimelineStatus
    let restartVerified: Bool
    /// Whether an automatic restore is allowed for this entry
    /// (trusted original + locatable slot + matching layout).
    let autoRestorable: Bool
    /// The eligibility reason: why it can, or cannot, be restored.
    let restoreReason: String
    /// Whether any stored backup verified (file exists, byte count
    /// and SHA-256 match, parses as a plist). A global fact about
    /// the backup store, labelled as such — not a per-change claim.
    let verifiedBackupOnFile: Bool
}

enum HistoryRestoreSummary {
    /// Builds the unified entries from the timeline (which already
    /// merges recorded operations with detected differences), the
    /// persisted records, the first-read snapshot, the working
    /// document and the backup verifications. Order follows the
    /// timeline (newest first). Pure: reads only its parameters.
    static func unifiedEntries(
        timeline: [RestoreTimelineEntry],
        records: [RecordedChange],
        snapshot: GestaltDocument?,
        working: GestaltDocument?,
        layout: MobileGestaltCacheLayout?,
        verifications: [BackupVerification]
    ) -> [UnifiedHistoryEntry] {
        let verifiedBackupOnFile = verifications.contains { $0.status == .verified }
        return timeline.map { entry in
            let recorded = records.first { $0.id == entry.id }
            let staged = stagedValue(for: entry, snapshot: snapshot, working: working, layout: layout)
            let (autoRestorable, restoreReason) = restoreEligibility(
                entry: entry, recorded: recorded, current: working, layout: layout)
            return UnifiedHistoryEntry(
                id: entry.id, date: entry.date, title: entry.title,
                key: entry.key, layer: entry.layer,
                firstRecordedValue: entry.original,
                firstRecordedLabel: entry.provenanceLabel,
                currentValue: entry.current,
                stagedValue: staged,
                isRecordedOperation: entry.isRecordedOperation,
                backupProvenance: entry.provenance,
                backupSourceLabel: RestoreIntelligence.provenanceLabel(for: entry.provenance),
                restoreState: entry.status,
                restartVerified: entry.restartVerified,
                autoRestorable: autoRestorable,
                restoreReason: restoreReason,
                verifiedBackupOnFile: verifiedBackupOnFile)
        }
    }

    /// The staged value for one timeline entry: the working
    /// document's value for the key, or `nil` when there is no
    /// working document, the value cannot be read, or it equals the
    /// first-recorded value (no staged change).
    static func stagedValue(
        for entry: RestoreTimelineEntry,
        snapshot: GestaltDocument?,
        working: GestaltDocument?,
        layout: MobileGestaltCacheLayout?
    ) -> ChangeValue? {
        guard let working else { return nil }
        let staged: ChangeValue?
        switch entry.layer {
        case .cacheExtra:
            staged = ChangeValue.fromPlistValue(working.extra[entry.key])
        case .artwork:
            staged = ChangeValue.fromPlistValue(working.artwork[entry.key])
        case .cacheData:
            staged = slotValue(entry.key, in: working, using: layout)
        }
        guard let staged, staged != entry.original else { return nil }
        return staged
    }

    /// Whether the entry may be auto-restored, with the reason.
    /// Recorded changes go through the existing eligibility
    /// checker; detected differences (no recorded operation, first
    /// read only) are never auto-restorable — there is no trusted
    /// original to restore from.
    static func restoreEligibility(
        entry: RestoreTimelineEntry, recorded: RecordedChange?,
        current: GestaltDocument?, layout: MobileGestaltCacheLayout?
    ) -> (autoRestorable: Bool, reason: String) {
        guard let recorded, let current else {
            return (false, L("A precise restore cannot be guaranteed without a trusted backup. Use read-only diagnostics or import a backup instead."))
        }
        switch RestoreEligibilityChecker.eligibility(
            for: recorded, record: nil, current: current, layout: layout) {
        case .restorable(_, let reason):
            return (true, reason)
        case .notRestorable(let reason):
            return (false, reason)
        }
    }

    /// Reads one CacheData slot value, mirroring
    /// `RestorePreviewBuilder`'s slot reading for the five known
    /// keys; any other key or unresolvable slot reads as `nil`,
    /// never guessed.
    static func slotValue(
        _ key: String, in document: GestaltDocument,
        using layout: MobileGestaltCacheLayout?
    ) -> ChangeValue? {
        guard let layout else { return nil }
        switch key {
        case DeviceCacheOptions.greenTeaKey:
            return (try? DeviceCacheOptions.flags(in: document, using: layout)).map { .bool($0.greenTea) }
        case DeviceCacheOptions.notGreenTeaKey:
            return (try? DeviceCacheOptions.flags(in: document, using: layout)).map { .bool($0.notGreenTea) }
        case DeviceCacheOptions.wapiKey:
            return (try? DeviceCacheOptions.wapi(in: document, using: layout)).map(ChangeValue.bool)
        case DeviceCacheOptions.audioIntelligenceKey, DeviceCacheOptions.personalTranslatorKey:
            return DeviceCacheOptions.advAISlotValue(key, in: document, using: layout)
                .map(ChangeValue.bool)
        default:
            return nil
        }
    }
}

// MARK: - Restore preview checklist

/// The five things the restore confirmation must show before a
/// restore executes: device identity, file integrity, backup
/// source, current system compatibility, and the before/after diff.
/// `nil` outcomes mean "could not be verified" — shown as unknown,
/// never as a pass.
struct RestorePreviewChecklist: Equatable, Sendable {
    /// "This device", "Another device", or "Unknown" (no
    /// installation id recorded yet).
    let deviceIdentity: String
    /// Whether the change/backup belongs to this device, or `nil`
    /// when it could not be determined.
    let deviceMatches: Bool?
    /// The device name shown to the user (the connected device's
    /// display name), so the identity can be checked at a glance.
    let deviceDisplayName: String
    let fileIntegrity: String
    /// Whether the backup file verified, or `nil` when there is no
    /// backup file to check for this change.
    let fileIntegrityOK: Bool?
    /// The backup's provenance label ("Verified factory backup",
    /// "First-read device state", ...).
    let backupSource: String
    let systemCompatible: String
    /// Whether the current cache layout matches, or `nil` when the
    /// layout could not be resolved.
    let systemCompatibleOK: Bool?
    /// The value currently in the document, or `nil` when it could
    /// not be read.
    let beforeValue: ChangeValue?
    /// The value a restore would write back, or `nil` for a
    /// whole-backup restore (every field, no single value).
    let afterValue: ChangeValue?

    /// True only when no check failed. Unknown checks do not pass
    /// the gate by themselves — they are shown as unknown and the
    /// caller still asks the user to confirm — but they do not
    /// block the way a failed check does: a failed device match, a
    /// failed file check or a layout mismatch is a hard stop in the
    /// UI (the restore button stays disabled).
    var noCheckFailed: Bool {
        deviceMatches != false && fileIntegrityOK != false && systemCompatibleOK != false
    }
}

enum RestorePreviewChecklistBuilder {
    /// The checklist for restoring one recorded change. `item` is
    /// the `RestorePreviewBuilder` item for the change (it carries
    /// the before/after diff); `verifications` are the stored
    /// backup verifications; `deviceID` is the installation device
    /// id (`nil` when none was recorded); `current` is the working
    /// document and `layout` its resolved layout.
    static func build(
        change: RecordedChange, item: RestoreItemPreview,
        verifications: [BackupVerification], deviceID: String?,
        deviceDisplayName: String, current: GestaltDocument?,
        layout: MobileGestaltCacheLayout?
    ) -> RestorePreviewChecklist {
        let deviceIdentity = deviceIdentityText(changeDeviceID: change.deviceID, deviceID: deviceID)
        let deviceMatches = deviceMatch(changeDeviceID: change.deviceID, deviceID: deviceID)
        let (fileIntegrity, fileIntegrityOK) = fileIntegrityForChange(
            change: change, verifications: verifications)
        return RestorePreviewChecklist(
            deviceIdentity: deviceIdentity, deviceMatches: deviceMatches,
            deviceDisplayName: deviceDisplayName,
            fileIntegrity: fileIntegrity, fileIntegrityOK: fileIntegrityOK,
            backupSource: change.backupProvenance.displayLabel,
            systemCompatible: systemCompatibilityText(current: current, layout: layout),
            systemCompatibleOK: systemCompatibility(current: current, layout: layout),
            beforeValue: item.currentValue, afterValue: item.targetValue)
    }

    /// The checklist for restoring a whole backup file. The backup
    /// record itself is the file being verified, so file integrity
    /// is exact (not the best-effort match used for single changes).
    /// The diff is whole-file: there is no single before/after
    /// value, so both are `nil` and the UI says so.
    static func buildForBackup(
        record: BackupRecord, verifications: [BackupVerification],
        deviceID: String?, deviceDisplayName: String,
        current: GestaltDocument?, layout: MobileGestaltCacheLayout?
    ) -> RestorePreviewChecklist {
        let deviceIdentity = deviceIdentityText(changeDeviceID: record.deviceID, deviceID: deviceID)
        let deviceMatches = deviceMatch(changeDeviceID: record.deviceID, deviceID: deviceID)
        let verification = verifications.first { $0.record.id == record.id }
        let (fileIntegrity, fileIntegrityOK): (String, Bool?) = {
            switch verification?.status {
            case .verified:
                return (L("Verified."), true)
            case .failed(let reason):
                return (reason, false)
            case .notFound, nil:
                return (L("Backup file not found."), false)
            }
        }()
        return RestorePreviewChecklist(
            deviceIdentity: deviceIdentity, deviceMatches: deviceMatches,
            deviceDisplayName: deviceDisplayName,
            fileIntegrity: fileIntegrity, fileIntegrityOK: fileIntegrityOK,
            backupSource: record.provenance.displayLabel,
            systemCompatible: systemCompatibilityText(current: current, layout: layout),
            systemCompatibleOK: systemCompatibility(current: current, layout: layout),
            beforeValue: nil, afterValue: nil)
    }

    // MARK: - Helpers

    private static func deviceIdentityText(changeDeviceID: String, deviceID: String?) -> String {
        guard let deviceID else { return L("Unknown") }
        return changeDeviceID == deviceID ? L("This device") : L("Another device")
    }

    private static func deviceMatch(changeDeviceID: String, deviceID: String?) -> Bool? {
        guard let deviceID else { return nil }
        return changeDeviceID == deviceID
    }

    /// File integrity for one change: there is no per-change backup
    /// file, so this matches verifications by device id. A verified
    /// backup for this device means a verified file exists; no
    /// verification at all means there is nothing to check (unknown,
    /// not failed); a present-but-unverified file reports its
    /// specific failure reason.
    private static func fileIntegrityForChange(
        change: RecordedChange, verifications: [BackupVerification]
    ) -> (String, Bool?) {
        let own = verifications.filter { $0.record.deviceID == change.deviceID }
        if own.contains(where: { $0.status == .verified }) {
            return (L("Verified backup on file."), true)
        }
        if own.isEmpty {
            return (L("No verified backup file for this change."), nil)
        }
        for verification in own {
            if case .failed(let reason) = verification.status {
                return (reason, false)
            }
        }
        return (L("Backup file not found."), false)
    }

    private static func systemCompatibilityText(
        current: GestaltDocument?, layout: MobileGestaltCacheLayout?
    ) -> String {
        switch systemCompatibility(current: current, layout: layout) {
        case true: return L("Verified. Cache layout matches this device.")
        case false: return L("Verified, but the cache layout differs from this device.")
        case nil: return L("Unknown")
        }
    }

    private static func systemCompatibility(
        current: GestaltDocument?, layout: MobileGestaltCacheLayout?
    ) -> Bool? {
        guard let current, let layout else { return nil }
        return layout.matches(current)
    }
}

// MARK: - High-risk second confirmation

/// The gate for high-risk operations (restore, apply): the first
/// tap arms it and reveals the preview, only the second tap
/// executes. The views hold one of these per restore button; the
/// gate itself is pure and unit-tested, so the "second confirmation"
/// is behavior, not just a label.
struct TwoStepConfirmation: Equatable, Sendable {
    private(set) var armed = false

    /// Requests execution. Returns `true` only on the second
    /// consecutive request (the confirmation); the first request
    /// arms the gate and returns `false` (do not execute).
    mutating func request() -> Bool {
        if armed { return true }
        armed = true
        return false
    }

    /// Disarms the gate (for example when the sheet closes).
    mutating func reset() { armed = false }
}
