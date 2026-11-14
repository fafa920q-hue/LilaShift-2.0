// SPDX-License-Identifier: GPL-3.0-only
// Compatibility status (Phase F) — ONE unified status model used
// everywhere a capability is displayed.
//
// The existing `FeatureEligibility` (six states) is the evaluator's
// vocabulary; this model is the DISPLAY vocabulary (eight states,
// in the task's terms). It is a pure mapping over real inputs only:
// the evaluator's eligibility + reason, the device profile, the
// snapshot / working documents, the staged-change set and the
// restart-verification set. It never re-evaluates eligibility, never
// guesses a system version or a capability state, and never presents
// an unknown as a success.
//
// The eight statuses:
//   .nativeSupported — the device already has the capability
//     natively; the UI must NOT present "modify" as the primary or
//     recommended action for it.
//   .modifiable — verified compatible and not yet enabled: may be
//     staged. This is the ONLY status that recommends modification.
//   .enabled — already configured (staged or applied) on this device.
//   .staged — staged in the working document but not yet applied.
//   .needsRestart — applied, but not yet verified after a restart.
//   .unverified — the evidence needed to decide is missing; the
//     detail carries the risk AND the detection evidence (what was
//     read, what is missing), not just a label.
//   .unsupported — hardware does not support the feature, or the
//     device is outside the feature's scope; the reason says WHY.
//   .readFailed — the read itself failed (no document, or the cache
//     read failed); distinct from unverified, where the read
//     succeeded but the evidence is insufficient.
//
// The #178 decision is still OPEN (whether to skip
// audioIntelligence on native-AI devices). This model implements
// no skip and changes no guard behavior: it only surfaces the
// existing conflict honestly as `nativeAIWarning` on the affected
// capability, so the warning is visible wherever the status is.
import Foundation

/// One of the eight display statuses for a capability.
enum CompatibilityStatus: String, CaseIterable, Equatable, Sendable {
    case nativeSupported
    case modifiable
    case enabled
    case staged
    case needsRestart
    case unverified
    case unsupported
    case readFailed

    var title: String {
        switch self {
        case .nativeSupported: return L("Natively supported")
        case .modifiable: return L("Modifiable")
        case .enabled: return L("Enabled")
        case .staged: return L("Staged")
        case .needsRestart: return L("Needs restart")
        case .unverified: return L("Unverified")
        case .unsupported: return L("Unsupported")
        case .readFailed: return L("Read failed")
        }
    }

    /// Whether the UI may present "modify / enable" as the primary
    /// or recommended action. Only `.modifiable` does: a natively
    /// supported capability must never be offered a duplicate
    /// modification by default, and an already-enabled, staged,
    /// unverified, unsupported or unread capability must never be
    /// presented as "can enable".
    var recommendsModification: Bool { self == .modifiable }

    /// Whether the capability is already present on the device
    /// (natively, or configured), so no modification is needed.
    var isAlreadyPresent: Bool {
        self == .nativeSupported || self == .enabled
    }
}

/// The resolved status of one capability, with the evidence behind
/// it. `reason` is the evaluator's (or the read's) specific reason;
/// `evidence` is what was actually read and what is missing, so an
/// unverified capability is never shown as a bare label.
struct CompatibilityStatusDetail: Equatable, Sendable {
    let featureID: String
    let status: CompatibilityStatus
    let reason: String
    let evidence: [String]
    let riskLevel: CapabilityRiskLevel
    /// Mirrors `status.recommendsModification`: only true for
    /// `.modifiable`.
    let recommendsModification: Bool
    /// True for `.staged` and `.needsRestart`: the change needs a
    /// restart (or an apply + restart) to take effect.
    let restartRequired: Bool
    /// The #178 warning, set only for audioIntelligence on
    /// native-AI hardware where the staged CacheExtra value
    /// disagrees with the native CacheData slot. The skip decision
    /// is still open; this is a display warning only.
    let nativeAIWarning: String?
}

enum CompatibilityStatusResolver {
    /// Resolves the display status for one feature from real inputs.
    /// `eligibility` + `reason` come from
    /// `FeatureEligibilityEvaluator` (via `LilaDeviceReport`); the
    /// caller never recomputes eligibility here. `documentRead` is
    /// whether a device document was read at all (a report exists);
    /// `working` is the staged working document, used only for the
    /// #178 warning. `stagedFeatureIDs` is the set of feature ids
    /// whose values differ between the snapshot and the working
    /// document (see `stagedFeatureIDs(snapshot:working:)`); `pendingRestartFeatureIDs`
    /// is the set of feature ids with an applied but not
    /// restart-verified record (see
    /// `pendingRestartFeatureIDs(records:)`).
    ///
    /// Precedence (first match wins): read failure, then
    /// needs-restart, then native, then enabled, then staged, then
    /// the eligibility mapping. A staged native capability stays
    /// native (no duplicate modification); a staged, guard-blocked
    /// capability stays visible as staged with its conflict reason
    /// carried in `reason` by the caller.
    static func resolve(
        featureID: String,
        eligibility: FeatureEligibility,
        reason: String,
        profile: DeviceProfile,
        documentRead: Bool,
        working: GestaltDocument? = nil,
        stagedFeatureIDs: Set<String> = [],
        pendingRestartFeatureIDs: Set<String> = [],
        riskLevel: CapabilityRiskLevel = .low
    ) -> CompatibilityStatusDetail {
        let warning = nativeAIWarning(
            featureID: featureID, profile: profile, working: working)
        func detail(status: CompatibilityStatus, reason: String,
                    evidence: [String]) -> CompatibilityStatusDetail {
            CompatibilityStatusDetail(
                featureID: featureID, status: status, reason: reason,
                evidence: evidence, riskLevel: riskLevel,
                recommendsModification: status.recommendsModification,
                restartRequired: status == .staged || status == .needsRestart,
                nativeAIWarning: warning)
        }

        // 1. Read failure: no document at all, or the cache read
        // itself failed. This is not "unverified": nothing was read
        // to judge from.
        guard documentRead else {
            let noDocument = L("No device document is available, so this feature cannot be judged.")
            return detail(status: .readFailed, reason: noDocument,
                          evidence: [noDocument, L("No document has been read.")])
        }
        if case .failed(let readReason) = profile.cacheReadState {
            return detail(status: .readFailed, reason: readReason,
                          evidence: [readReason])
        }

        // 2. Applied but not yet verified after a restart.
        if pendingRestartFeatureIDs.contains(featureID) {
            return detail(status: .needsRestart,
                          reason: L("Requires a device restart to take effect."),
                          evidence: [reason])
        }

        // 3. Native: already supported — never recommend a duplicate
        // modification, even when the value is also staged.
        if eligibility == .nativeSupported {
            return detail(status: .nativeSupported, reason: reason,
                          evidence: [reason, L("Already supported on this device — no change needed.")])
        }

        // 4. Already configured on the device.
        if eligibility == .alreadyConfigured {
            return detail(status: .enabled, reason: reason, evidence: [reason])
        }

        // 5. Staged in the working document, not yet applied.
        if stagedFeatureIDs.contains(featureID) {
            return detail(status: .staged, reason: reason, evidence: [reason])
        }

        // 6. The eligibility mapping. A guard conflict is
        // unsupported with the guard's specific reason — never a
        // false "can enable". An unknown eligibility is unverified
        // with the detection evidence, never a bare label.
        switch eligibility {
        case .eligibleToEnable:
            return detail(status: .modifiable, reason: reason, evidence: [reason])
        case .unsupported:
            return detail(status: .unsupported, reason: reason, evidence: [reason])
        case .conflict:
            return detail(status: .unsupported, reason: reason, evidence: [reason])
        case .unknown:
            var evidence = [reason]
            if profile.cacheLayout.value == nil {
                evidence.append(L("The system cache layout could not be resolved, so CacheData checks are unavailable."))
            }
            return detail(status: .unverified, reason: reason, evidence: evidence)
        case .nativeSupported, .alreadyConfigured:
            // Handled above; unreachable here.
            return detail(status: .enabled, reason: reason, evidence: [reason])
        }
    }

    /// Whether a preset for this feature may be offered on this
    /// device. China-model presets are offered only when the
    /// feature's rules are explicit AND its device conditions are
    /// met — which is exactly what `.modifiable` means: the
    /// evaluator already checked the explicit rules against this
    /// device. Native, enabled, staged, unverified, unsupported
    /// and unread features are never offered as a modification.
    static func isOffered(_ detail: CompatibilityStatusDetail) -> Bool {
        detail.status == .modifiable
    }

    /// The #178 warning: audioIntelligence staged (CacheExtra true)
    /// on native Apple Intelligence hardware whose native CacheData
    /// slot baseline is off (false). The staged key and the native
    /// slot disagree; whether to skip the key on native hardware is
    /// still undecided, so this only warns — it changes nothing.
    /// Returns `nil` for every other feature, for non-native
    /// hardware, for an unstaged key, and when no native baseline is
    /// known (unknown stays unknown).
    static func nativeAIWarning(
        featureID: String, profile: DeviceProfile, working: GestaltDocument?
    ) -> String? {
        guard featureID == "audioIntelligence",
              profile.isNativeAppleIntelligence.value == true,
              let productType = profile.productType.value,
              let working,
              (working.extra[DeviceCacheOptions.audioIntelligenceKey] as? NSNumber)?.boolValue == true,
              DeviceAIEligibility.nativeAdvAISlotValue(
                key: DeviceCacheOptions.audioIntelligenceKey,
                productType: productType) == false else {
            return nil
        }
        return L("Audio Intelligence is staged on native Apple Intelligence hardware, but the native slot reads off. Whether to skip it is still undecided — nothing was changed.")
    }

    /// Feature ids whose values differ between the first-read
    /// snapshot and the working (staged) document — i.e. the
    /// staged, not-yet-applied changes. CacheExtra and artwork keys
    /// are compared directly; CacheData slots are compared through
    /// the resolved layout only (an unresolvable layout skips the
    /// slot comparison, never guesses an offset). Keys with no
    /// capability or virtual feature id contribute nothing.
    static func stagedFeatureIDs(
        snapshot: DocumentSnapshot?, working: GestaltDocument?
    ) -> Set<String> {
        guard let snapshot, let working else { return [] }
        let first = snapshot.document
        var ids = Set<String>()

        let extraKeys = Set(first.extra.keys).union(working.extra.keys)
        for key in extraKeys where !plistValuesEqual(first.extra[key], working.extra[key]) {
            ids.formUnion(featureIDs(forCacheExtraKey: key))
        }

        let artworkKeys = Set(first.artwork.keys).union(working.artwork.keys)
        for key in artworkKeys where !plistValuesEqual(first.artwork[key], working.artwork[key]) {
            ids.insert("dynamicIsland")
        }

        if let layout = try? MobileGestaltCacheLayout.resolve(in: working) {
            for key in [DeviceCacheOptions.greenTeaKey,
                        DeviceCacheOptions.notGreenTeaKey,
                        DeviceCacheOptions.wapiKey,
                        DeviceCacheOptions.audioIntelligenceKey,
                        DeviceCacheOptions.personalTranslatorKey] {
                if slotBool(key, in: first, using: layout) != slotBool(key, in: working, using: layout) {
                    ids.formUnion(featureIDs(forCacheDataKey: key))
                }
            }
        }
        return ids
    }

    /// Feature ids with an applied but not restart-verified record:
    /// the change is in effect on the device file but its survival
    /// of a restart has not been confirmed yet.
    static func pendingRestartFeatureIDs(records: [RecordedChange]) -> Set<String> {
        Set(records.filter { !$0.restartVerified }.map(\.featureID))
    }

    // MARK: - Helpers

    private static func featureIDs(forCacheExtraKey key: String) -> [String] {
        if key == GestaltKeys.regionCode || key == GestaltKeys.regionInfo
            || key == GestaltKeys.legacyRegionInfo {
            return [FeatureEligibilityEvaluator.regionCodeFeatureID]
        }
        if let capability = Capability.all.first(where: { $0.keys.contains(key) }) {
            return [capability.id]
        }
        return []
    }

    private static func featureIDs(forCacheDataKey key: String) -> [String] {
        switch key {
        case DeviceCacheOptions.greenTeaKey, DeviceCacheOptions.notGreenTeaKey:
            return [FeatureEligibilityEvaluator.esimFeatureID]
        case DeviceCacheOptions.wapiKey:
            return [FeatureEligibilityEvaluator.wapiFeatureID]
        default:
            if let capability = Capability.all.first(where: { $0.keys.contains(key) }) {
                return [capability.id]
            }
            return []
        }
    }

    private static func slotBool(
        _ key: String, in document: GestaltDocument,
        using layout: MobileGestaltCacheLayout
    ) -> Bool? {
        switch key {
        case DeviceCacheOptions.greenTeaKey:
            return (try? DeviceCacheOptions.flags(in: document, using: layout))?.greenTea
        case DeviceCacheOptions.notGreenTeaKey:
            return (try? DeviceCacheOptions.flags(in: document, using: layout))?.notGreenTea
        case DeviceCacheOptions.wapiKey:
            return try? DeviceCacheOptions.wapi(in: document, using: layout)
        case DeviceCacheOptions.audioIntelligenceKey,
             DeviceCacheOptions.personalTranslatorKey:
            return DeviceCacheOptions.advAISlotValue(key, in: document, using: layout)
        default:
            return nil
        }
    }

    private static func plistValuesEqual(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (nil, _), (_, nil): return false
        case let (a as NSObject, b as NSObject): return a.isEqual(b)
        default: return false
        }
    }
}
