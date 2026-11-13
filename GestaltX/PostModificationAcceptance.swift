// SPDX-License-Identifier: GPL-3.0-only
// Post-Modification Auto-Acceptance (修改后自动验收) — after the
// user restarts the device, re-reads the device and compares each
// modification target against what was staged, and generates a real
// acceptance report. Pure Foundation — no SwiftUI, no UIKit, no
// singletons, no global mutable state.
//
// The report distinguishes three things that must never be
// confused:
//   • the FILE still holding the value (the post-restart document
//     read from the device), and
//   • the SYSTEM actually using the value (the live probe, when
//     the caller supplies one), and
//   • a field that was NOT re-read: it is reported as not re-read,
//     never claimed accepted.
//
// It builds on Restore Intelligence's `HistoryJournal` records and
// the Modified Values read-only report: it does NOT duplicate
// them — it adds the restart-aware before/after comparison and the
// acceptance report. It never writes to the MobileGestalt cache.
// The "mark restart-verified" action only sets a flag on history
// records, and only for records whose items all accepted.
import Foundation

// MARK: - Outcomes

/// What the post-restart re-read says about one modification.
enum AcceptanceOutcome: String, Equatable, Sendable {
    /// The file holds the staged target value.
    case accepted
    /// The file holds the original value again — the system
    /// reverted it (the known region case: CH → LL → CH).
    case reverted
    /// The file holds a third value, neither the target nor the
    /// original.
    case changed
    /// The field could not be read from the post-restart document
    /// (layout unresolvable, slot unreadable, key absent).
    case unreadable
    /// No post-restart document was supplied, so this field was
    /// not re-read at all.
    case notReRead

    var title: String {
        switch self {
        case .accepted: return L("Accepted")
        case .reverted: return L("Reverted")
        case .changed: return L("Changed")
        case .unreadable: return L("Unreadable")
        case .notReRead: return L("Not re-read")
        }
    }
}

/// One modification's acceptance result. `liveValue` is the live
/// probe's answer for this key when the caller supplied one
/// (CacheExtra keys only — CacheData slots have no live probe);
/// `liveAgrees` is true when the live probe agrees with the staged
/// target, false when it disagrees, `nil` when there is no live
/// probe for this key. A file value and a live value disagreeing is
/// reported, never hidden: the file holding a value does not mean
/// the system uses it.
struct AcceptanceItem: Equatable, Identifiable, Sendable {
    /// The record this item reports on. The identity of the item:
    /// two records may stage the same key at different times, so
    /// the key alone is not a unique identity.
    var id: String { recordID.uuidString }
    let recordID: UUID
    let key: String
    let title: String
    let layer: ChangeLayer
    let original: ChangeValue
    let target: ChangeValue
    /// The value in the post-restart document, or `nil` when the
    /// field was not re-read or could not be read.
    let current: ChangeValue?
    let outcome: AcceptanceOutcome
    let liveValue: ChangeValue?
    let liveAgrees: Bool?
}

/// The acceptance report for one re-read. `restartVerifiedCandidateIDs`
/// are the record IDs whose items all accepted: the caller may mark
/// those records restart-verified in history (a history-only flag,
/// never a device write).
struct AcceptanceReport: Equatable, Sendable {
    let items: [AcceptanceItem]
    let acceptedCount: Int
    let revertedCount: Int
    let changedCount: Int
    let unreadableCount: Int
    let notReReadCount: Int
    let generatedAt: Date
    /// True only when the caller confirmed the device was actually
    /// restarted after the changes were applied. Without a restart
    /// the file values say nothing about whether the system took
    /// the change, and the summary says so.
    let restartConfirmed: Bool
    let revertedKeys: [String]
    let restartVerifiedCandidateIDs: [UUID]
    let summary: String

    /// The disclaimer every display of this report must carry.
    static let disclaimer = L("Only fields that were re-read after a restart are claimed accepted. A value in the file does not prove the system uses it.")
}

// MARK: - Acceptance

enum PostModificationAcceptance {
    /// Compares each recorded change against the post-restart
    /// document. `records` are the changes this app recorded
    /// (from `ChangeRecordStore`). `current` is the document read
    /// after the restart, or `nil` when no post-restart read has
    /// happened — then every item is `.notReRead` and nothing is
    /// claimed accepted. The CacheData layout is resolved from the
    /// post-restart document itself: a layout that cannot be
    /// resolved there leaves CacheData items `.unreadable`, never
    /// read through a stale layout. `liveValues` maps CacheExtra
    /// keys to the live probe's answer, when the caller has one.
    static func accept(
        records: [RecordedChange],
        current: GestaltDocument?,
        liveValues: [String: ChangeValue] = [:],
        restartConfirmed: Bool = false
    ) -> AcceptanceReport {
        let layout = current.flatMap { try? MobileGestaltCacheLayout.resolve(in: $0) }
        var items: [AcceptanceItem] = []
        for record in records {
            let currentValue = current.flatMap { readCurrent(record, in: $0, using: layout) }
            let outcome: AcceptanceOutcome
            if current == nil {
                outcome = .notReRead
            } else if let currentValue {
                if currentValue == record.new {
                    outcome = .accepted
                } else if currentValue == record.original {
                    outcome = .reverted
                } else {
                    outcome = .changed
                }
            } else {
                outcome = .unreadable
            }
            let liveValue = liveValues[record.key]
            let liveAgrees = liveValue.map { $0 == record.new }
            items.append(AcceptanceItem(
                recordID: record.id,
                key: record.key,
                title: title(for: record),
                layer: record.layer,
                original: record.original, target: record.new,
                current: currentValue, outcome: outcome,
                liveValue: liveValue, liveAgrees: liveAgrees))
        }
        let accepted = items.filter { $0.outcome == .accepted }.count
        let reverted = items.filter { $0.outcome == .reverted }.count
        let changed = items.filter { $0.outcome == .changed }.count
        let unreadable = items.filter { $0.outcome == .unreadable }.count
        let notReRead = items.filter { $0.outcome == .notReRead }.count
        let revertedKeys = items.filter { $0.outcome == .reverted }.map(\.key)
        let candidateIDs = records.filter { record in
            items.contains { $0.recordID == record.id && $0.outcome == .accepted }
        }.map(\.id)
        let summary: String
        if current == nil {
            summary = L("No post-restart document has been read. Nothing is claimed accepted.")
        } else if !restartConfirmed {
            summary = String(format: L("%d of %d fields hold the staged value, but the device was not confirmed restarted."), accepted, items.count)
        } else if reverted > 0 {
            summary = String(format: L("%d of %d fields accepted after restart; %d reverted."), accepted, items.count, reverted)
        } else {
            summary = String(format: L("%d of %d fields accepted after restart."), accepted, items.count)
        }
        return AcceptanceReport(
            items: items, acceptedCount: accepted, revertedCount: reverted,
            changedCount: changed, unreadableCount: unreadable, notReReadCount: notReRead,
            generatedAt: Date(), restartConfirmed: restartConfirmed,
            revertedKeys: revertedKeys, restartVerifiedCandidateIDs: candidateIDs,
            summary: summary)
    }

    /// Builds live-probe values for the recorded changes' CacheExtra
    /// keys, from a live-answers source (the production source is
    /// `LiveGestaltProbeSource`, a thin wrapper over `LiveGestaltProbe`).
    /// The probe is asked in the shape of the staged target value: a
    /// `.bool` target asks for a bool answer, a `.string` target asks
    /// for a string answer. A key the probe cannot answer gets no
    /// entry — never a guessed value — and an `.int` / `.data` /
    /// `.absent` target is not probed at all (the probe API has no
    /// integer answer, and asking a bool question about an integer
    /// key would misread it). CacheData keys get no live value:
    /// CacheData slots have no live probe, so the file value is the
    /// only evidence for them. The caller passes the result as
    /// `liveValues` to `accept(_:)`.
    static func liveValues(
        for records: [RecordedChange],
        using live: any LiveAnswersSource = LiveGestaltProbeSource()
    ) -> [String: ChangeValue] {
        var values: [String: ChangeValue] = [:]
        for record in records where record.layer == .cacheExtra {
            switch record.new {
            case .bool:
                if let answer = live.boolAnswer(for: record.key) {
                    values[record.key] = .bool(answer)
                }
            case .string:
                if let answer = live.stringAnswer(for: record.key) {
                    values[record.key] = .string(answer)
                }
            case .int, .data, .absent:
                break
            }
        }
        return values
    }

    /// Reads the current value of one recorded change from the
    /// post-restart document. Mirrors
    /// `RestorePreviewBuilder.currentValue`: CacheExtra and artwork
    /// keys read straight from the document; CacheData keys read
    /// through `DeviceCacheOptions` with the resolved layout, and
    /// return `nil` when the layout is unresolvable or the key is
    /// not one of the five readable CacheData keys.
    private static func readCurrent(
        _ change: RecordedChange, in document: GestaltDocument,
        using layout: MobileGestaltCacheLayout?
    ) -> ChangeValue? {
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

    /// The user-facing title for a recorded change: the
    /// capability's title when the key belongs to one, the eSIM /
    /// region / WAPI label for the virtual features, otherwise the
    /// key itself.
    private static func title(for record: RecordedChange) -> String {
        if record.layer == .cacheData && record.key == DeviceCacheOptions.greenTeaKey {
            return L("eSIM green-tea")
        }
        if record.layer == .cacheData && record.key == DeviceCacheOptions.notGreenTeaKey {
            return L("eSIM not-green-tea")
        }
        if record.layer == .cacheData && record.key == DeviceCacheOptions.wapiKey {
            return L("WAPI")
        }
        if record.layer == .cacheExtra && record.key == GestaltKeys.regionCode {
            return L("Region code")
        }
        if let capability = Capability.all.first(where: { $0.keys.contains(record.key) }) {
            return capability.title
        }
        return record.key
    }
}
