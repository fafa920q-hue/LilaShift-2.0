// SPDX-License-Identifier: GPL-3.0-only
// Restore Intelligence (智能恢复引擎) — modification timeline and
// precise restore. Pure Foundation — no SwiftUI, no UIKit, no
// singletons, no global mutable state.
//
// The engine automatically saves a trusted record of each operation
// and compares before/after states. The user can choose per-item
// restore, preset-group restore, history-based restore, or
// verified-backup restore, always with a pre-restore Diff and a
// post-restore acceptance check.
//
// THE ENGINE NEVER WRITES THE DEVICE FILE ITSELF. Restore execution
// goes only through GestaltManager's EXISTING restore paths
// (`restore(_:)` for a full backup, `restoreCapability(_:)` for one
// capability, `restoreCacheOption()` for the eSIM flags, and the
// China Unlock group restores). Where no existing path covers an
// item, the action is preview-only with a clear "restore path not
// yet connected" state — never a fake restore. The stores below keep
// history in the app's own container (Application
// Support/GestaltX/History), never in the system MobileGestalt cache.
//
// The first-read value is called the "first-recorded value", never
// the factory original: if the system was modified before the first
// read, the first-recorded value may already be modified. Fields
// with NO trusted original value never offer a fake precise restore;
// unknown-original fields are marked "undetermined", never guessed.
import Foundation

// MARK: - History journal (shared file mechanism)

/// What went wrong reading or writing a history file. The caller
/// maps these to user-facing strings; the journal itself never
/// invents a localized message.
enum HistoryJournalError: Error, Equatable, Sendable {
    /// No file exists at the path (a fresh install, or the file was
    /// deleted). Callers treat this as an empty store, not an error.
    case fileNotFound
    /// The digest sidecar is missing, or the file bytes do not match
    /// it: the file may have been replaced or truncated.
    case digestMismatch
    /// The verified bytes could not be decoded as the expected type.
    case decodeFailed
    /// The atomic write or its read-back verification failed.
    case writeFailed
}

/// A versioned envelope for one history file. `version` is the
/// format version of this file; readers refuse versions newer than
/// the one they understand. `deviceID` scopes the file to one
/// device: history from another device must never be restored here.
struct HistoryEnvelope<Record: Codable>: Codable {
    let version: Int
    let deviceID: String
    let records: [Record]
}

enum HistoryJournal {
    /// SHA-256 hex of data, reusing the store's digest.
    static func sha256Hex(of data: Data) -> String {
        GestaltFileStore.sha256Hex(of: data)
    }

    /// The digest sidecar for a history file: `<filename>.sha256`.
    static func digestURL(for fileURL: URL) -> URL {
        fileURL.appendingPathExtension("sha256")
    }

    /// Reads and verifies a history file: the digest sidecar must
    /// exist and match the file bytes, and the bytes must decode as
    /// the expected type. Throws `.fileNotFound` when the file does
    /// not exist (callers treat that as an empty store).
    static func readVerifiedJSON<T: Decodable>(_ type: T.Type, from fileURL: URL) throws -> T {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw HistoryJournalError.fileNotFound
        }
        guard let data = try? Data(contentsOf: fileURL),
              let digest = try? String(contentsOf: digestURL(for: fileURL), encoding: .utf8),
              digest.trimmingCharacters(in: .whitespacesAndNewlines) == sha256Hex(of: data) else {
            throw HistoryJournalError.digestMismatch
        }
        guard let value = try? JSONDecoder().decode(type, from: data) else {
            throw HistoryJournalError.decodeFailed
        }
        return value
    }

    /// Writes a history file atomically with its digest sidecar, then
    /// reads both back and verifies them. The digest is written before
    /// the read-back check, so a partial write is never mistaken for
    /// a verified file.
    static func writeVerifiedJSON<T: Encodable>(_ value: T, to fileURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else {
            throw HistoryJournalError.writeFailed
        }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            try sha256Hex(of: data).write(to: digestURL(for: fileURL),
                                          atomically: true, encoding: .utf8)
            guard let reread = try? Data(contentsOf: fileURL), reread == data,
                  let digest = try? String(contentsOf: digestURL(for: fileURL), encoding: .utf8),
                  digest.trimmingCharacters(in: .whitespacesAndNewlines) == sha256Hex(of: data) else {
                throw HistoryJournalError.writeFailed
            }
        } catch let error as HistoryJournalError {
            throw error
        } catch {
            throw HistoryJournalError.writeFailed
        }
    }
}

// MARK: - Change-record store

/// Persistence for `RecordedChange` timeline records. Records live in
/// one versioned JSON envelope with a SHA-256 sidecar. A missing file
/// is an empty store; a tampered, truncated or undecodable file is
/// refused, never trusted. The store never writes the device file and
/// never changes a record's meaning: persistence only, no restore
/// decisions here.
struct ChangeRecordStore: Sendable {
    /// Format version of the envelope written by `save`. Readers refuse
    /// envelopes newer than this version, never guess at them.
    static let currentVersion = 1
    static let fileName = "change-records.json"

    let directory: URL
    let deviceID: String

    init(directory: URL, deviceID: String) {
        self.directory = directory
        self.deviceID = deviceID
    }

    private var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    /// Loads the stored records. A missing file loads as an empty
    /// store. A digest mismatch, an undecodable file, an envelope
    /// newer than this version, or an envelope for another device
    /// throws.
    ///
    /// Migration: before the v1 envelope, records were written as a
    /// bare JSON array with no digest sidecar. Such a file decodes in
    /// memory only — the next `save` writes the enveloped v1 format
    /// with a digest. A file that decodes neither as an envelope nor
    /// as a bare array is refused, never trusted.
    func load() throws -> [RecordedChange] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let envelope = try HistoryJournal.readVerifiedJSON(
                HistoryEnvelope<RecordedChange>.self, from: fileURL)
            guard envelope.version <= Self.currentVersion else {
                throw GestaltFailure("This history uses a newer format this version cannot read.")
            }
            guard envelope.deviceID == deviceID else {
                throw GestaltFailure("This history belongs to a different device.")
            }
            return envelope.records
        } catch let error as HistoryJournalError {
            switch error {
            case .fileNotFound:
                return []
            case .digestMismatch, .decodeFailed:
                if let migrated = readBareArrayIfPresent() { return migrated }
                throw GestaltFailure("The change history could not be read. No system changes were made.")
            case .writeFailed:
                throw GestaltFailure("The change history could not be read. No system changes were made.")
            }
        } catch let error as GestaltFailure {
            throw error
        } catch {
            throw GestaltFailure("The change history could not be read. No system changes were made.")
        }
    }

    /// Saves the records as a v1 envelope with a SHA-256 sidecar,
    /// verified by a read-back. A failed write throws and leaves the
    /// previous verified file untouched (the journal writes
    /// atomically).
    func save(_ records: [RecordedChange]) throws {
        do {
            try HistoryJournal.writeVerifiedJSON(
                HistoryEnvelope(version: Self.currentVersion, deviceID: deviceID, records: records),
                to: fileURL)
        } catch {
            throw GestaltFailure("The change history could not be saved and verified. No system changes were made.")
        }
    }

    /// Loads the stored records, appends one change, and saves the
    /// result.
    func append(_ change: RecordedChange) throws {
        var records = try load()
        records.append(change)
        try save(records)
    }

    /// Reads a pre-envelope bare JSON array of records, or `nil` when
    /// the file does not decode as one. Used only on the migration
    /// path.
    private func readBareArrayIfPresent() -> [RecordedChange]? {
        guard let data = try? Data(contentsOf: fileURL),
              let records = try? JSONDecoder().decode([RecordedChange].self, from: data) else {
            return nil
        }
        return records
    }
}

// MARK: - Restore log

/// What happened to one restore attempt, as recorded in the log.
enum RestoreOutcome: String, Codable, Equatable, Sendable {
    case restored
    case failed
    case notAttempted
}

/// One restore-log entry: what was attempted, what it targeted, and
/// what happened. `targetValue` is the recorded original the restore
/// aimed at (`.absent` when the key did not originally exist).
struct RestoreLogEntry: Codable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let changeID: UUID?
    let featureID: String
    let key: String
    let layer: ChangeLayer
    let targetValue: ChangeValue
    let outcome: RestoreOutcome
    let reason: String
    /// The batch restore point this attempt belongs to, or `nil` for
    /// a single restore (which creates no batch restore point).
    let restorePointID: UUID?
    let deviceID: String
    let osBuild: String
}

/// The restore log file: a `HistoryEnvelope` of `RestoreLogEntry`
/// records plus a SHA-256 sidecar, read and written through
/// `HistoryJournal`. A log failure never fails a restore — it is
/// reported through `logSaved` instead.
struct RestoreLogStore: Sendable {
    static let currentVersion = 1
    static let fileName = "restore-log.json"
    let directory: URL
    let deviceID: String

    init(directory: URL, deviceID: String) {
        self.directory = directory
        self.deviceID = deviceID
    }

    private var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    /// All logged entries, oldest first. A missing file reads as an
    /// empty log; a digest mismatch, undecodable file, newer format
    /// or foreign device is a `GestaltFailure` — never a silent
    /// empty log, and no system changes are made on any of these
    /// paths (the log is read-only here).
    func load() throws -> [RestoreLogEntry] {
        do {
            let envelope = try HistoryJournal.readVerifiedJSON(
                HistoryEnvelope<RestoreLogEntry>.self, from: fileURL)
            guard envelope.version <= Self.currentVersion else {
                throw GestaltFailure("This history uses a newer format this version cannot read.")
            }
            guard envelope.deviceID == deviceID else {
                throw GestaltFailure("This history belongs to a different device.")
            }
            return envelope.records
        } catch let error as HistoryJournalError {
            switch error {
            case .fileNotFound:
                return []
            case .digestMismatch, .decodeFailed, .writeFailed:
                throw GestaltFailure("The restore log could not be read. No system changes were made.")
            }
        } catch let error as GestaltFailure {
            throw error
        } catch {
            throw GestaltFailure("The restore log could not be read. No system changes were made.")
        }
    }

    /// Appends one entry and saves the log. Returns false when the
    /// log could not be saved (the restore itself is unaffected).
    @discardableResult
    func append(_ entry: RestoreLogEntry) -> Bool {
        do {
            var entries = try load()
            entries.append(entry)
            try HistoryJournal.writeVerifiedJSON(
                HistoryEnvelope(version: Self.currentVersion, deviceID: deviceID, records: entries),
                to: fileURL)
            return true
        } catch {
            return false
        }
    }

    /// Exports the log as JSON data (for the user to share or keep).
    /// The export contains only log fields — no device secrets beyond
    /// the deviceID already stored in the log.
    func exportJSON() throws -> Data {
        let entries = try load()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(entries)
    }
}

// MARK: - Restore eligibility (decision only — no execution here)

/// Whether one recorded change may be restored automatically, with
/// the specific reason either way.
enum RestoreEligibility: Sendable {
    /// Auto-restore is allowed. `record` is the backup the restore
    /// will be committed against, or `nil` when the change's own
    /// trusted recorded original is the source and no backup record
    /// was supplied.
    case restorable(record: BackupRecord?, reason: String)
    /// Auto-restore is refused. `reason` is user-facing and specific.
    case notRestorable(reason: String)
}

/// Decides whether a recorded change may be restored automatically.
/// This is a DECISION ONLY: it never writes anything. The actual
/// restore goes through GestaltManager's existing restore paths.
/// Trust rules (fail-closed throughout):
/// - Only a trusted original is auto-restorable: a `RecordedChange`
///   that is verified and whose backup provenance is
///   `.verifiedFactory` or `.preModification`.
/// - A supplied `BackupRecord` must itself have trusted provenance.
///   A record with `.unknown`, `.firstRead` or `.importedHistory`
///   provenance is never silently applied; it may be shown for manual
///   review.
/// - Originally-absent keys restore as absent (the key is removed),
///   never filled with a guessed default.
/// - A change touching a CacheData slot is restorable only when the
///   slot can be located on the current layout; an unlocatable slot
///   refuses rather than guessing an offset.
/// - When no reliable backup exists, the answer is `.notRestorable`
///   with a reason that says precisely that a precise restore cannot
///   be guaranteed and offers read-only diagnostics and backup
///   import — never a fake restore.
enum RestoreEligibilityChecker {
    static func eligibility(for change: RecordedChange, record: BackupRecord?,
                            current: GestaltDocument, layout: MobileGestaltCacheLayout?) -> RestoreEligibility {
        // The change must still match the current cache structure.
        if let layout, !layout.matches(current) {
            return .notRestorable(reason: L("This plist uses a different system cache layout and cannot be restored."))
        }
        // A CacheData slot must be locatable on this layout; an
        // unlocatable slot is refused, never guessed. The slot value
        // itself must be a single byte (a Boolean or integer).
        if change.layer == .cacheData {
            guard let layout, layout.slotIndex(forKey: change.key) != nil else {
                return .notRestorable(reason: L("This change touches a CacheData slot that cannot be located on this device."))
            }
            guard change.original.isCacheDataByte else {
                return .notRestorable(reason: L("Original values could not be read. No system changes were made."))
            }
        }
        // Malformed artwork is never overwritten: restoring into it
        // would silently lose its data.
        if change.layer == .artwork, !current.canEditArtwork {
            return .notRestorable(reason: L("The stored artwork value is malformed, so it cannot be restored."))
        }
        // A supplied backup must have trusted provenance. First-read,
        // imported and unknown-origin records may be shown for manual
        // review, never silently applied.
        if let record, !record.provenance.isTrustedForRestore {
            return .notRestorable(reason: L("This backup's origin is not trusted, so it cannot be restored automatically. It can be reviewed manually instead."))
        }
        // The recorded original itself must be verified and from
        // trusted provenance. Without that there is no reliable
        // backup to restore from.
        guard change.verified, change.backupProvenance.isTrustedForRestore else {
            return .notRestorable(reason: L("A precise restore cannot be guaranteed without a trusted backup. Use read-only diagnostics or import a backup instead."))
        }
        return .restorable(record: record, reason: L("A trusted original is available for this change."))
    }
}

// MARK: - Restore preview

/// How risky an automatic restore of one change is. `low` means the
/// change may be auto-restored as previewed; `review` means it may
/// be restored but only after the user has seen the conflict; `blocked`
/// means automatic restore is refused.
enum RestoreRisk: String, Equatable, Sendable {
    case low
    case review
    case blocked

    var displayLabel: String {
        switch self {
        case .low: return L("Low risk")
        case .review: return L("Review required")
        case .blocked: return L("Cannot restore automatically")
        }
    }
}

/// One change as it would be restored.
struct RestoreItemPreview: Equatable, Sendable {
    let change: RecordedChange
    /// The value currently in the document, or `nil` when it could
    /// not be read (unresolvable layout, or a value with no
    /// `ChangeValue` representation). A missing key reads as `.absent`.
    let currentValue: ChangeValue?
    /// The value a restore would write back: the recorded original.
    let targetValue: ChangeValue
    let backupSource: BackupProvenance
    let backupSourceLabel: String
    /// Whether the supplied backup record (when one was supplied)
    /// belongs to the same device as the change. True when no record
    /// was supplied; a record for another device never matches.
    let deviceMatches: Bool
    let risk: RestoreRisk
    let autoRestorable: Bool
    /// User-facing reason: the eligibility reason, or the first
    /// conflict string when conflicts demote a restorable item to
    /// review.
    let reason: String
    let conflicts: [String]
    /// Which existing GestaltManager path would perform this restore,
    /// or `.previewOnly` when no existing path covers it.
    let action: RestoreAction
}

/// The preview over a whole selected set, in the caller's order.
struct RestorePreview: Equatable, Sendable {
    let items: [RestoreItemPreview]
    let canAutoRestoreAll: Bool
    let blockedCount: Int
    let reviewCount: Int
    let hasReliableBackup: Bool
    /// Set when no change in the set has a reliable backup: a precise
    /// restore cannot be guaranteed, so the user is pointed at
    /// read-only diagnostics or backup import instead.
    let notice: String?
}

enum RestorePreviewBuilder {
    static func build(changes: [RecordedChange], records: [UUID: BackupRecord],
                      current: GestaltDocument, layout: MobileGestaltCacheLayout?) -> RestorePreview {
        // Pair conflicts are computed over the whole selected set.
        // eSIM: restoring exactly one of the green-tea / not-green-tea
        // flags leaves the pair inconsistent.
        let hasGreenTea = changes.contains {
            $0.layer == .cacheData && $0.key == DeviceCacheOptions.greenTeaKey
        }
        let hasNotGreenTea = changes.contains {
            $0.layer == .cacheData && $0.key == DeviceCacheOptions.notGreenTeaKey
        }
        let esimPairSplit = hasGreenTea != hasNotGreenTea
        // Region: restoring only the region code leaves the
        // sales-region suffix inconsistent.
        let hasRegionCode = changes.contains {
            $0.layer == .cacheExtra && $0.key == GestaltKeys.regionCode
        }
        let hasRegionSuffix = changes.contains {
            $0.layer == .cacheExtra
                && ($0.key == GestaltKeys.regionInfo || $0.key == GestaltKeys.legacyRegionInfo)
        }
        let regionSplit = hasRegionCode && !hasRegionSuffix

        var items: [RestoreItemPreview] = []
        for change in changes {
            var conflicts: [String] = []
            if change.layer == .cacheData
                && (change.key == DeviceCacheOptions.greenTeaKey
                    || change.key == DeviceCacheOptions.notGreenTeaKey)
                && esimPairSplit {
                conflicts.append(L("Restoring only one of the eSIM pair leaves the flags inconsistent. Restore both together."))
            }
            if change.layer == .cacheExtra && change.key == GestaltKeys.regionCode && regionSplit {
                conflicts.append(L("Restoring only the region code leaves the sales-region suffix inconsistent. Restore both together."))
            }

            let record = records[change.id]
            let deviceMatches = record.map { $0.deviceID == change.deviceID } ?? true
            let eligibility = RestoreEligibilityChecker.eligibility(
                for: change, record: record, current: current, layout: layout)
            let currentValue = currentValue(change, in: current, using: layout)
            let action = RestoreAction.forChange(change)
            switch eligibility {
            case .notRestorable(let reason):
                items.append(RestoreItemPreview(
                    change: change, currentValue: currentValue, targetValue: change.original,
                    backupSource: change.backupProvenance,
                    backupSourceLabel: change.backupProvenance.displayLabel,
                    deviceMatches: deviceMatches, risk: .blocked, autoRestorable: false,
                    reason: reason, conflicts: conflicts, action: action))
            case .restorable(_, let reason):
                if conflicts.isEmpty {
                    items.append(RestoreItemPreview(
                        change: change, currentValue: currentValue, targetValue: change.original,
                        backupSource: change.backupProvenance,
                        backupSourceLabel: change.backupProvenance.displayLabel,
                        deviceMatches: deviceMatches, risk: .low, autoRestorable: true,
                        reason: reason, conflicts: conflicts, action: action))
                } else {
                    items.append(RestoreItemPreview(
                        change: change, currentValue: currentValue, targetValue: change.original,
                        backupSource: change.backupProvenance,
                        backupSourceLabel: change.backupProvenance.displayLabel,
                        deviceMatches: deviceMatches, risk: .review, autoRestorable: false,
                        reason: conflicts[0], conflicts: conflicts, action: action))
                }
            }
        }

        let hasReliableBackup = changes.contains {
            $0.verified && ($0.backupProvenance == .verifiedFactory
                            || $0.backupProvenance == .preModification)
        }
        return RestorePreview(
            items: items,
            canAutoRestoreAll: !items.isEmpty && items.allSatisfy { $0.autoRestorable },
            blockedCount: items.filter { $0.risk == .blocked }.count,
            reviewCount: items.filter { $0.risk == .review }.count,
            hasReliableBackup: hasReliableBackup,
            notice: hasReliableBackup ? nil : L("A precise restore cannot be guaranteed without a trusted backup. Use read-only diagnostics or import a backup instead."))
    }

    /// Reads the current value of a change's key in its layer, or
    /// `nil` when it cannot be read. Mirrors the detector's slot
    /// reading for the five known CacheData keys; any other key or
    /// unresolvable slot reads as `nil`, never guessed.
    private static func currentValue(_ change: RecordedChange, in document: GestaltDocument,
                                     using layout: MobileGestaltCacheLayout?) -> ChangeValue? {
        switch change.layer {
        case .cacheExtra:
            return ChangeValue.fromPlistValue(document.extra[change.key])
        case .artwork:
            return ChangeValue.fromPlistValue(document.artwork[change.key])
        case .cacheData:
            guard let layout else { return nil }
            switch change.key {
            case DeviceCacheOptions.greenTeaKey:
                return (try? DeviceCacheOptions.flags(in: document, using: layout)).map { .bool($0.greenTea) }
            case DeviceCacheOptions.notGreenTeaKey:
                return (try? DeviceCacheOptions.flags(in: document, using: layout)).map { .bool($0.notGreenTea) }
            case DeviceCacheOptions.wapiKey:
                return (try? DeviceCacheOptions.wapi(in: document, using: layout)).map(ChangeValue.bool)
            case DeviceCacheOptions.audioIntelligenceKey, DeviceCacheOptions.personalTranslatorKey:
                return DeviceCacheOptions.advAISlotValue(change.key, in: document, using: layout)
                    .map(ChangeValue.bool)
            default:
                return nil
            }
        }
    }
}

// MARK: - Restore actions (existing GestaltManager paths only)

/// Which existing GestaltManager restore path would perform a
/// restore, or `.previewOnly` when no existing path covers the item.
/// Restore Intelligence never adds a new write path: where the
/// action is `.previewOnly`, the UI shows the preview and says
/// plainly that the restore path is not yet connected.
enum RestoreAction: Equatable, Sendable {
    /// Restore a whole backup file (`GestaltManager.restore(_:)`).
    case fullBackup(record: BackupRecord)
    /// Restore one capability's keys (`GestaltManager.restoreCapability(_:)`).
    case capability(Capability)
    /// Restore the eSIM flags (`GestaltManager.restoreCacheOption()`).
    case cacheOption
    /// Restore the 9-item China Unlock group (`GestaltManager.restoreChinaUnlock()`).
    case chinaUnlock
    /// Restore the AI-only group (`GestaltManager.restoreChinaAIOnly()`).
    case aiOnly
    /// Restore the eSIM & Region group (`GestaltManager.restoreChinaESIMRegion()`).
    case esimRegion
    /// No existing restore path covers this item: preview only.
    case previewOnly(reason: String)

    /// The action for one recorded change. CacheExtra keys that
    /// belong to a capability restore through that capability; the
    /// eSIM flags restore through the cache-option path; the region
    /// code has no per-item path (it restores with the eSIM & Region
    /// group), so it is preview-only here.
    static func forChange(_ change: RecordedChange) -> RestoreAction {
        switch change.layer {
        case .cacheData:
            if change.key == DeviceCacheOptions.greenTeaKey
                || change.key == DeviceCacheOptions.notGreenTeaKey {
                return .cacheOption
            }
            if let capability = Capability.all.first(where: { $0.keys.contains(change.key) }) {
                return .capability(capability)
            }
            return .previewOnly(reason: L("No restore path is connected for this CacheData slot yet."))
        case .cacheExtra:
            if change.key == GestaltKeys.regionCode
                || change.key == GestaltKeys.regionInfo
                || change.key == GestaltKeys.legacyRegionInfo {
                return .previewOnly(reason: L("The region code restores with the eSIM & Region group, not per item."))
            }
            if let capability = Capability.all.first(where: { $0.keys.contains(change.key) }) {
                return .capability(capability)
            }
            return .previewOnly(reason: L("No restore path is connected for this key yet."))
        case .artwork:
            if let capability = Capability.all.first(where: { $0.id == "dynamicIsland" }) {
                return .capability(capability)
            }
            return .previewOnly(reason: L("No restore path is connected for this artwork key yet."))
        }
    }
}

// MARK: - Timeline

/// Whether a recorded change is still in effect, restored, or
/// changed to something else since it was recorded.
enum RestoreTimelineStatus: Equatable, Sendable {
    /// The current value matches the recorded original: restored.
    case restored
    /// The current value matches the recorded new value: still applied.
    case pending
    /// The current value is neither the original nor the recorded
    /// new value: something else changed it since.
    case changed
    /// The current value could not be read.
    case unknown
}

/// One timeline entry: a recorded operation, or a difference the
/// Modified Values report detected without a recorded operation.
/// `provenanceLabel` always says what the original is — "first
/// recorded value" for a first read, never "factory original" unless
/// the provenance is `.verifiedFactory`.
struct RestoreTimelineEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let featureID: String
    let key: String
    let title: String
    let layer: ChangeLayer
    let original: ChangeValue
    let current: ChangeValue?
    let target: ChangeValue
    let provenance: BackupProvenance
    let provenanceLabel: String
    let status: RestoreTimelineStatus
    let restartVerified: Bool
    /// True when this entry comes from a persisted `RecordedChange`;
    /// false when it is a difference detected by the Modified Values
    /// report with no recorded operation behind it.
    let isRecordedOperation: Bool
}

// MARK: - Backup verification

/// The verification state of one stored backup, checked read-only
/// from the backup directory: the file must exist, match its
/// recorded byte count and SHA-256 digest, parse as a MobileGestalt
/// plist, and (when a current document is supplied) match its cache
/// layout generation.
enum BackupVerificationStatus: Equatable, Sendable {
    case verified
    case failed(reason: String)
    case notFound
}

struct BackupVerification: Equatable, Sendable {
    let record: BackupRecord
    let status: BackupVerificationStatus
    /// Whether the backup's cache layout generation matches the
    /// current document (`nil` when no current document was supplied
    /// or the backup could not be parsed).
    let layoutMatchesCurrent: Bool?
}

// MARK: - RestoreIntelligence namespace

enum RestoreIntelligence {
    /// The app's own history directory (Application
    /// Support/GestaltX/History). Change records and the restore log
    /// live here, never in the system MobileGestalt cache.
    static var historyDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GestaltX/History", isDirectory: true)
    }

    /// The backup directory GestaltManager uses (Application
    /// Support/GestaltX/Backups). Read-only from here: verification
    /// reads the files, never writes them.
    static var backupDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GestaltX/Backups", isDirectory: true)
    }

    /// The installation device ID GestaltManager records
    /// (`GestaltX.installationID`). `nil` when it was never set — the
    /// history stores are unavailable then, never scoped to a guessed
    /// id.
    static var installationDeviceID: String? {
        UserDefaults.standard.string(forKey: "GestaltX.installationID")
    }

    /// Records one applied or staged change in the history store.
    /// Best-effort helper for the UI, called after an apply/restore
    /// completes through an existing GestaltManager path. Returns
    /// false when the store is unavailable or the write could not be
    /// verified — the device is unaffected either way.
    @discardableResult
    static func recordChange(_ change: RecordedChange) -> Bool {
        guard let deviceID = installationDeviceID else { return false }
        let store = ChangeRecordStore(directory: historyDirectory, deviceID: deviceID)
        do { try store.append(change); return true } catch { return false }
    }

    /// Appends one restore-log entry. Best-effort: returns false when
    /// the log could not be saved — the restore itself is unaffected.
    @discardableResult
    static func logRestore(_ entry: RestoreLogEntry) -> Bool {
        guard let deviceID = installationDeviceID else { return false }
        return RestoreLogStore(directory: historyDirectory, deviceID: deviceID).append(entry)
    }

    /// Builds the modification timeline from persisted records plus a
    /// direct snapshot-vs-current comparison. A recorded change and a
    /// detected difference for the same key merge into one entry,
    /// preferring the recorded operation. Entries are newest first.
    ///
    /// The snapshot is the source of recorded originals for detected
    /// differences. When there is no snapshot, no differences are
    /// claimed — without a recorded original there is nothing honest
    /// to compare against.
    static func timeline(
        records: [RecordedChange],
        snapshot: GestaltDocument?,
        current: GestaltDocument,
        layout: MobileGestaltCacheLayout?
    ) -> [RestoreTimelineEntry] {
        var entries: [RestoreTimelineEntry] = []
        var coveredKeys = Set<String>()

        func slotValue(_ key: String, in document: GestaltDocument,
                       using layout: MobileGestaltCacheLayout?) -> ChangeValue? {
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

        func currentValue(for change: RecordedChange) -> ChangeValue? {
            switch change.layer {
            case .cacheExtra:
                return ChangeValue.fromPlistValue(current.extra[change.key])
            case .artwork:
                return ChangeValue.fromPlistValue(current.artwork[change.key])
            case .cacheData:
                return slotValue(change.key, in: current, using: layout)
            }
        }

        func status(for change: RecordedChange, currentValue: ChangeValue?) -> RestoreTimelineStatus {
            guard let currentValue else { return .unknown }
            if currentValue == change.original { return .restored }
            if currentValue == change.new { return .pending }
            return .changed
        }

        for change in records {
            let current = currentValue(for: change)
            let capability = Capability.all.first { $0.keys.contains(change.key) }
            entries.append(RestoreTimelineEntry(
                id: change.id, date: change.date, featureID: change.featureID,
                key: change.key,
                title: capability?.title ?? ModifiedValues.title(forKey: change.key),
                layer: change.layer, original: change.original,
                current: current, target: change.new,
                provenance: change.backupProvenance,
                provenanceLabel: provenanceLabel(for: change.backupProvenance),
                status: status(for: change, currentValue: current),
                restartVerified: change.restartVerified,
                isRecordedOperation: true))
            coveredKeys.insert(change.key)
        }

        // Detected differences with no recorded operation behind them.
        // Their original is the snapshot's first-recorded value, never
        // a factory claim. Without a snapshot nothing is claimed.
        if let snapshot {
            // CacheExtra differences.
            let extraKeys = Set(snapshot.extra.keys).union(current.extra.keys)
            for key in extraKeys where !coveredKeys.contains(key) {
                let original = ChangeValue.fromPlistValue(snapshot.extra[key])
                let currentValue = ChangeValue.fromPlistValue(current.extra[key])
                guard let original, let currentValue, original != currentValue else { continue }
                let capability = Capability.all.first { $0.keys.contains(key) }
                entries.append(RestoreTimelineEntry(
                    id: stableUUID(forLayer: .cacheExtra, key: key), date: Date(), featureID: capability?.id ?? key,
                    key: key, title: capability?.title ?? ModifiedValues.title(forKey: key),
                    layer: .cacheExtra, original: original,
                    current: currentValue, target: currentValue,
                    provenance: .firstRead,
                    provenanceLabel: provenanceLabel(for: .firstRead),
                    status: .pending, restartVerified: false,
                    isRecordedOperation: false))
            }
            // Known CacheData slot differences.
            for key in [DeviceCacheOptions.greenTeaKey, DeviceCacheOptions.notGreenTeaKey,
                        DeviceCacheOptions.wapiKey, DeviceCacheOptions.audioIntelligenceKey,
                        DeviceCacheOptions.personalTranslatorKey]
            where !coveredKeys.contains(key) {
                guard let original = slotValue(key, in: snapshot, using: layout),
                      let currentValue = slotValue(key, in: current, using: layout),
                      original != currentValue else { continue }
                let capability = Capability.all.first { $0.keys.contains(key) }
                entries.append(RestoreTimelineEntry(
                    id: stableUUID(forLayer: .cacheData, key: key), date: Date(), featureID: capability?.id ?? key,
                    key: key, title: capability?.title ?? ModifiedValues.title(forKey: key),
                    layer: .cacheData, original: original,
                    current: currentValue, target: currentValue,
                    provenance: .firstRead,
                    provenanceLabel: provenanceLabel(for: .firstRead),
                    status: .pending, restartVerified: false,
                    isRecordedOperation: false))
            }
            // Artwork differences.
            let artworkKeys = Set(snapshot.artwork.keys).union(current.artwork.keys)
            for key in artworkKeys where !coveredKeys.contains(key) {
                let original = ChangeValue.fromPlistValue(snapshot.artwork[key])
                let currentValue = ChangeValue.fromPlistValue(current.artwork[key])
                guard let original, let currentValue, original != currentValue else { continue }
                entries.append(RestoreTimelineEntry(
                    id: stableUUID(forLayer: .artwork, key: key), date: Date(), featureID: "dynamicIsland",
                    key: key, title: ModifiedValues.title(forKey: key),
                    layer: .artwork, original: original,
                    current: currentValue, target: currentValue,
                    provenance: .firstRead,
                    provenanceLabel: provenanceLabel(for: .firstRead),
                    status: .pending, restartVerified: false,
                    isRecordedOperation: false))
            }
        }

        return HomeSorting.sortHistory(entries)
    }

    /// A stable UUID for a detected (unrecorded) timeline entry,
    /// derived from its layer + key so the row keeps its identity
    /// across recomputes (the timeline is rebuilt from the live
    /// document on every render). A recorded operation keeps its own
    /// persisted id.
    private static func stableUUID(forLayer layer: ChangeLayer, key: String) -> UUID {
        let hex = GestaltFileStore.sha256Hex(of: Data("\(layer.rawValue):\(key)".utf8))
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<16 {
            let start = hex.index(hex.startIndex, offsetBy: i * 2)
            let end = hex.index(start, offsetBy: 2)
            bytes[i] = UInt8(hex[start..<end], radix: 16) ?? 0
        }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5],
                           bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// The honest label for a backup provenance. A first read is the
    /// "first-recorded value", never the factory original.
    static func provenanceLabel(for provenance: BackupProvenance) -> String {
        switch provenance {
        case .verifiedFactory: return L("Verified factory backup")
        case .firstRead: return L("First-recorded value")
        case .preModification: return L("State before change")
        case .importedHistory: return L("Imported backup")
        case .unknown: return L("Unknown source")
        }
    }

    /// Verifies stored backups read-only: each file must exist, match
    /// its recorded byte count and SHA-256 digest, and parse as a
    /// MobileGestalt plist. When `current` is supplied, the backup's
    /// cache layout generation must also match it. A failure is
    /// reported with the specific reason, never hidden. `directory`
    /// overrides the backup directory (the production directory by
    /// default); tests pass a temporary directory so verification of
    /// an existing file can be exercised without touching the real
    /// backup store. A record with no recorded digest (`sha256 == nil`,
    /// legacy records) is checked by byte count and parse only — there
    /// is no digest to compare against, and the result says so by
    /// still reporting `.verified` when those checks pass.
    static func verifyBackups(_ records: [BackupRecord],
                              against current: GestaltDocument?,
                              directory: URL? = nil) -> [BackupVerification] {
        let directory = directory ?? backupDirectory
        return records.map { record in
            let url = directory.appendingPathComponent(record.filename)
            guard FileManager.default.fileExists(atPath: url.path) else {
                return BackupVerification(record: record, status: .notFound, layoutMatchesCurrent: nil)
            }
            guard let data = try? Data(contentsOf: url),
                  data.count == record.byteCount,
                  record.sha256.map({ $0 == GestaltFileStore.sha256Hex(of: data) }) ?? true,
                  let backupDocument = try? GestaltDocument(data: data) else {
                return BackupVerification(
                    record: record,
                    status: .failed(reason: L("The backup could not be verified. No system changes were made.")),
                    layoutMatchesCurrent: nil)
            }
            var layoutMatches: Bool?
            if let current {
                let uuidMatches = (backupDocument.root["CacheUUID"] as? String)
                    == (current.root["CacheUUID"] as? String)
                let cacheMatches: Bool = {
                    guard let a = backupDocument.root["CacheData"] as? Data,
                          let b = current.root["CacheData"] as? Data else { return false }
                    return a.count == b.count
                }()
                layoutMatches = uuidMatches && cacheMatches
            }
            return BackupVerification(record: record, status: .verified, layoutMatchesCurrent: layoutMatches)
        }
    }
}
