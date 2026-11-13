// SPDX-License-Identifier: GPL-3.0-only
// Apple Intelligence 4-factor readiness checkup + slot-only conflict guards.
//
// Adapted from Erosion-CN's AppleIntelligenceCheckupCard idea; reimplemented
// for GestaltX's staging model (read-only until Fix is tapped, then the
// normal review + backup + readback flow).
//
// UNRESOLVED CONFLICT (#178) — READ BEFORE CHANGING THE UNLOCK:
// Erosion-CN's live probes (iPhone 18 Pro Max iPhone19,7 and iPhone 15 Pro
// Max iPhone16,2, iOS 27) report that the Audio Intelligence CacheData
// slot (rb2tKZxlj0Gm2tBmUQSLqQ, observed slot #178 on those devices) is
// natively FALSE on iPhone/iPad, and forcing the *slot* to 1 breaks Photos
// high-quality Clean Up. Erosion-CN therefore treats any presence of the
// CacheExtra key as a conflict and strips it on native-AI hardware.
// Our 9-item unlock sets CacheExtra `audioIntelligence` = 1 on every
// device, including native-AI iPhones. The CacheData slot and the
// CacheExtra key are two different layers, and neither codebase establishes
// from source alone whether setting the *CacheExtra key* to 1 on a
// native-AI iPhone is harmless, redundant, or harmful. Until that is
// verified on a native-AI device, the guards in this file are SLOT-ONLY:
// they repair a slot that reads 1, and they never flag, strip, or change
// the CacheExtra key the unlock sets. Do NOT "fix" this by changing the
// 9-item default without a device-verified decision from the user.
//
// LAYER MODEL — never conflate the two:
// * CacheExtra key: a named entry in the plist's CacheExtra dictionary
//   (e.g. `audioIntelligence` = 1 staged by the unlock). It advertises a
//   capability; it is what presets stage and what `Capability` writes.
// * CacheData slot: one boolean byte inside the CacheData blob, located by
//   a dynamically resolved slot index (e.g. slot #178 / #266 on the probed
//   devices). It is what `DeviceCacheOptions.advAISlotValue` reads and
//   what `setAdvAISlot` repairs. The two layers share one obfuscated key
//   string (rb2tKZxlj0Gm2tBmUQSLqQ / M1n2sAqf33NAOgZRGxQYBA) as a lookup
//   name only — sharing the name does not make them the same value.
// Slot numbers (#178/#266) are per-device observations, never constants:
// every guard resolves its slot dynamically and reports "unknown" when
// resolution fails.
import Foundation

/// A CacheData slot that disagrees with its native baseline on a
/// native-AI iPhone, or a CacheExtra key that contradicts it. The two
/// layers are separate cases and are reported separately in `detail`: a
/// slot reading is always named "CacheData slot", a key value is always
/// named "CacheExtra key", and the resolved slot number is shown when
/// known.
enum AIConflict: Equatable, Identifiable {
    /// The Personal Translator CacheData slot reads 0 on a native-AI
    /// iPhone, where its native baseline is 1. Slot-only: the CacheExtra
    /// key is never consulted for this case.
    case personalTranslatorSlotDisabled(slot: Int?)
    /// The CacheExtra key `personalTranslator` is explicitly 0 on a
    /// native-AI iPhone, where its native CacheData slot baseline is 1.
    /// Key-only: the CacheData slot reading is never consulted for this
    /// case.
    case personalTranslatorKeyDisabled
    /// Audio Intelligence CacheData slot reads 1 on an iPhone/iPad,
    /// where its native baseline is 0. Slot-only: the CacheExtra key
    /// `audioIntelligence` is never consulted for this case.
    case audioIntelligenceEnabled(slot: Int?)

    var id: String {
        switch self {
        case .personalTranslatorSlotDisabled: return "personalTranslatorSlotDisabled"
        case .personalTranslatorKeyDisabled: return "personalTranslatorKeyDisabled"
        case .audioIntelligenceEnabled: return "audioIntelligenceEnabled"
        }
    }

    var slot: Int? {
        switch self {
        case .personalTranslatorSlotDisabled(let slot): return slot
        case .personalTranslatorKeyDisabled: return nil
        case .audioIntelligenceEnabled(let slot): return slot
        }
    }

    /// Which layer this conflict is about.
    var layer: AIFlagLayer {
        switch self {
        case .personalTranslatorSlotDisabled: return .cacheDataSlot
        case .personalTranslatorKeyDisabled: return .cacheExtraKey
        case .audioIntelligenceEnabled: return .cacheDataSlot
        }
    }

    var detail: String {
        switch self {
        case .personalTranslatorSlotDisabled(let slot):
            if let slot {
                String(format: L("Personal Translator CacheData slot #%d reads 0 on a native-AI iPhone — its native baseline is 1. Photos Clean Up and Camera Siri may fail."), slot)
            } else {
                L("Personal Translator is off on a native-AI iPhone — its CacheData slot reads 0. Photos Clean Up and Camera Siri may fail.")
            }
        case .personalTranslatorKeyDisabled:
            L("Personal Translator CacheExtra key is explicitly 0 on a native-AI iPhone — its native CacheData slot baseline is 1. Photos Clean Up and Camera Siri may fail.")
        case .audioIntelligenceEnabled(let slot):
            if let slot {
                String(format: L("Audio Intelligence CacheData slot #%d reads 1 — its native baseline is 0. Photos high-quality Clean Up may fail."), slot)
            } else {
                L("Audio Intelligence CacheData slot reads 1 — its native baseline is 0. Photos high-quality Clean Up may fail.")
            }
        }
    }
}

/// One AI flag, two independent layers. A CacheExtra key and a CacheData
/// slot that share an obfuscated key string are different values in
/// different places; a statement about one is never a statement about
/// the other.
enum AIFlagLayer: Equatable {
    /// A named entry in the plist's CacheExtra dictionary.
    case cacheExtraKey
    /// One boolean byte inside the CacheData blob, at a dynamically
    /// resolved slot index.
    case cacheDataSlot
}

/// A proposed AI staging, with the CacheExtra layer and the CacheData
/// layer kept as separate inputs. `nil` on a slot value means the slot
/// did not resolve on this layout — unknown, never a guessed baseline.
/// `nil` on a CacheExtra value means the key is absent from the staged
/// preview. `nil` on `liveAIEnabled` means the live MGCopyAnswer probe
/// could not answer.
struct AIStagingRequest: Equatable {
    let productType: String
    /// Staged CacheExtra value for `audioIntelligence`; `nil` = key absent.
    var audioIntelligenceExtra: Bool? = nil
    /// Staged CacheExtra value for `personalTranslator`; `nil` = key absent.
    var personalTranslatorExtra: Bool? = nil
    /// Resolved CacheData slot value for Audio Intelligence; `nil` = unknown.
    var audioIntelligenceSlot: Bool? = nil
    /// Resolved CacheData slot value for Personal Translator; `nil` = unknown.
    var personalTranslatorSlot: Bool? = nil
    /// Dynamically resolved CacheData slot index for Audio Intelligence, when known.
    var audioIntelligenceSlotIndex: Int? = nil
    /// Dynamically resolved CacheData slot index for Personal Translator, when known.
    var personalTranslatorSlotIndex: Int? = nil
    /// Live on-device probe of the `ai` CacheExtra key; `nil` = probe could not answer.
    var liveAIEnabled: Bool? = nil
    /// The user explicitly confirmed an unverified (warned) combination
    /// after reading its reason. Never set by the guard itself.
    var userConfirmedUnverifiedCombination: Bool = false
}

/// The outcome of the staging guard. `.allow` is the only outcome that
/// may be auto-staged (e.g. by one-tap Fix). `.warn` needs an explicit
/// user confirmation after the reason is shown — it is not silent.
/// `.block` needs the slot repaired to its native baseline first.
struct AIStagingDecision: Equatable {
    enum Outcome: Equatable { case allow, warn, block }
    let outcome: Outcome
    /// The specific reason for the outcome, in user-facing wording.
    let reason: String
    var allowsAutoStage: Bool { outcome == .allow }
    var requiresExplicitConfirmation: Bool { outcome == .warn }
    var requiresSlotRepair: Bool { outcome == .block }
}

/// Pure staging guard for the #178/#266 AI flags. It stages nothing and
/// changes no document; it only decides whether a proposed combination
/// may be auto-staged, with a specific reason. Fail-closed by default:
/// on native-AI hardware an AI key may be auto-staged only when its
/// CacheData slot resolved and matches its native baseline — an
/// unresolved slot, a slot that disagrees with its baseline, or a live
/// probe that disagrees all refuse silent auto-staging. The one
/// exception is the unresolved #178 question itself: staging CacheExtra
/// `audioIntelligence` = 1 while its CacheData slot reads its native 0
/// is a `.warn`, not a `.block`, because whether the CacheExtra key
/// alone is harmful is unverified — but it still must not be auto-staged
/// silently; it needs explicit confirmation. The guard is wired into
/// `GestaltManager.fixAIReadiness` (which evaluates the China Unlock
/// proposal before staging: repair first, then block refuses with the
/// reason, warn proceeds only as the user's explicit confirmation) and
/// into the checkup (which surfaces the decision for the currently
/// staged combination). It is deliberately NOT wired into
/// `stageChinaUnlock`: the one-tap unlock is an explicit user action
/// that stages CacheExtra keys only and never writes a slot, so a
/// pre-existing slot conflict is not caused or worsened by staging —
/// the checkup surfaces it with a repair path instead of disabling the
/// unlock outright.
enum AIStagingGuard {
    static func decide(_ request: AIStagingRequest) -> AIStagingDecision {
        let native = DeviceAIEligibility.isNativeAppleIntelligence(productType: request.productType)
        let confirmed = request.userConfirmedUnverifiedCombination

        if native {
            // Hard slot conflicts first: a CacheData slot that disagrees
            // with its native baseline must be repaired before staging.
            if request.audioIntelligenceSlot == true {
                return .init(outcome: .block, reason: audioSlotConflictReason(slot: request.audioIntelligenceSlotIndex))
            }
            if request.personalTranslatorSlot == false {
                return .init(outcome: .block, reason: translatorSlotConflictReason(slot: request.personalTranslatorSlotIndex))
            }
            // A CacheExtra key explicitly 0 for Personal Translator
            // contradicts its native CacheData slot baseline of 1.
            if request.personalTranslatorExtra == false {
                return .init(outcome: .block, reason: L("Personal Translator CacheExtra key is explicitly 0 on a native-AI iPhone, but its native CacheData slot baseline is 1. Restore the CacheExtra key before staging."))
            }
            // Unknown baseline: an AI key is staged but its CacheData slot
            // did not resolve, so the native baseline cannot be verified.
            // Fail closed — refuse auto-staging until verified on-device.
            if request.audioIntelligenceExtra == true, request.audioIntelligenceSlot == nil {
                return .init(outcome: .block, reason: L("Audio Intelligence CacheData slot did not resolve, so its native baseline cannot be verified. Auto-staging is refused until the slot is verified on-device."))
            }
            if request.personalTranslatorExtra == true, request.personalTranslatorSlot == nil {
                return .init(outcome: .block, reason: L("Personal Translator CacheData slot did not resolve, so its native baseline cannot be verified. Auto-staging is refused until the slot is verified on-device."))
            }
            // Unresolved #178: CacheExtra `audioIntelligence` = 1 staged
            // while its CacheData slot reads its native 0. The slot is
            // correct; whether the CacheExtra key alone is safe is not
            // established. Warn with the specific reason; never stage
            // silently. Explicit confirmation is the only way through.
            if request.audioIntelligenceExtra == true, request.audioIntelligenceSlot == false {
                if confirmed {
                    return .init(outcome: .allow, reason: L("Unverified combination explicitly confirmed by the user; staging proceeds."))
                }
                return .init(outcome: .warn, reason: audioExtraUnverifiedReason(slot: request.audioIntelligenceSlotIndex))
            }
            // Live probe disagrees: the device itself reports Apple
            // Intelligence off while AI keys are being staged.
            if request.liveAIEnabled == false,
               request.audioIntelligenceExtra == true || request.personalTranslatorExtra == true {
                if confirmed {
                    return .init(outcome: .allow, reason: L("Unverified combination explicitly confirmed by the user; staging proceeds."))
                }
                return .init(outcome: .warn, reason: L("The live probe reports Apple Intelligence off on this native-AI iPhone, which conflicts with staging AI capabilities. Confirm explicitly before staging."))
            }
            return .init(outcome: .allow, reason: L("CacheData slots match their native baselines; staging is verified-safe."))
        }

        // Non-native hardware has no native-AI baseline to verify against;
        // the unlock is what enables AI here. The only signal is a
        // CacheData slot that reads against the recorded iPhone/iPad
        // baseline (Audio Intelligence natively 0), which is unverified
        // on this hardware — warn, do not block.
        if request.audioIntelligenceSlot == true {
            if confirmed {
                return .init(outcome: .allow, reason: L("Unverified combination explicitly confirmed by the user; staging proceeds."))
            }
            return .init(outcome: .warn, reason: nonNativeAudioSlotReason(slot: request.audioIntelligenceSlotIndex))
        }
        return .init(outcome: .allow, reason: L("No native-AI baseline applies to this hardware; the unlock enables AI capabilities."))
    }

    private static func audioSlotConflictReason(slot: Int?) -> String {
        if let slot {
            String(format: L("Audio Intelligence CacheData slot #%d reads 1, but its native baseline is 0. Repair the slot to 0 before staging Audio Intelligence."), slot)
        } else {
            L("Audio Intelligence CacheData slot reads 1, but its native baseline is 0. Repair the slot to 0 before staging Audio Intelligence.")
        }
    }

    private static func translatorSlotConflictReason(slot: Int?) -> String {
        if let slot {
            String(format: L("Personal Translator CacheData slot #%d reads 0, but its native baseline on a native-AI iPhone is 1. Repair the slot to 1 before staging."), slot)
        } else {
            L("Personal Translator CacheData slot reads 0, but its native baseline on a native-AI iPhone is 1. Repair the slot to 1 before staging.")
        }
    }

    private static func audioExtraUnverifiedReason(slot: Int?) -> String {
        if let slot {
            String(format: L("CacheExtra audioIntelligence is staged as 1 while CacheData slot #%d reads its native 0. Whether the CacheExtra key alone is safe on native-AI hardware is unverified — confirm explicitly before staging."), slot)
        } else {
            L("CacheExtra audioIntelligence is staged as 1 while its CacheData slot reads its native 0. Whether the CacheExtra key alone is safe on native-AI hardware is unverified — confirm explicitly before staging.")
        }
    }

    private static func nonNativeAudioSlotReason(slot: Int?) -> String {
        if let slot {
            String(format: L("Audio Intelligence CacheData slot #%d reads 1, but the recorded iPhone/iPad baseline is 0. This hardware has no native-AI baseline — confirm explicitly before staging."), slot)
        } else {
            L("Audio Intelligence CacheData slot reads 1, but the recorded iPhone/iPad baseline is 0. This hardware has no native-AI baseline — confirm explicitly before staging.")
        }
    }
}

struct AIReadinessFactor: Equatable {
    let title: String
    let detail: String
    let isReady: Bool
    /// Live on-device state, or `nil` when the probe could not answer
    /// (simulator, or the key is unreadable). `nil` renders "unknown".
    let isLiveActive: Bool?
}

struct AIReadinessCheckup: Equatable {
    let factors: [AIReadinessFactor]
    var readyCount: Int { factors.filter(\.isReady).count }
    var isReady: Bool { readyCount == factors.count }

    /// Pure evaluation of the four factors from staged values, the live
    /// probe answers and the slot-only conflicts. `regModel` is the staged
    /// regulatory model; the one-tap unlock always keeps the factory
    /// model, so any present value passes — a US model is never required.
    /// `stagingDecision` is the `AIStagingGuard` outcome for the proposed
    /// combination, when one was computed: a `.block` or `.warn` decision
    /// fails the eSIM / conflict factor with the decision's specific
    /// reason, so a conflicting or unverified combination is never
    /// reported 4/4 ready and never auto-staged silently. `nil` (no guard
    /// computed) keeps the previous behaviour.
    static func evaluate(
        regionCode: String?,
        regModel: String?,
        esimEnabled: Bool,
        conflicts: [AIConflict],
        aiEnabledCount: Int,
        aiTotal: Int,
        productType: String,
        liveRegionCode: String?,
        liveRegModel: String?,
        liveAIEnabled: Bool?,
        stagingDecision: AIStagingDecision? = nil
    ) -> AIReadinessCheckup {
        let native = DeviceAIEligibility.isNativeAppleIntelligence(productType: productType)

        // Region: the staged code must be LL. The sales-region suffix is
        // never staged by the one-tap, so it is not required here.
        let regionReady = regionCode == "LL"
        let region = AIReadinessFactor(
            title: L("Region Code"),
            detail: regionCode ?? L("Not present"),
            isReady: regionReady,
            isLiveActive: liveRegionCode.map { $0 != "CH" && $0 != "ZA" })

        // The one-tap unlock keeps the factory model: any kept value
        // passes. A US model is never required.
        let regModelFactor = AIReadinessFactor(
            title: L("Regulatory model (factory model kept)"),
            detail: regModel ?? L("Not present"),
            isReady: regModel?.isEmpty == false,
            isLiveActive: liveRegModel.map { !$0.isEmpty })

        let esimDetail: String
        let esimReady: Bool
        if let decision = stagingDecision, decision.outcome != .allow {
            // A blocked or warned staging decision is surfaced here with
            // its specific reason, ahead of the generic conflict text, and
            // the factor is not ready: the combination must be repaired
            // (.block) or explicitly confirmed (.warn) first.
            esimDetail = decision.reason
            esimReady = false
        } else if let conflict = conflicts.first {
            esimDetail = conflict.detail
            esimReady = false
        } else {
            esimDetail = esimEnabled ? L("Configured") : L("Not Configured")
            esimReady = esimEnabled
        }
        let esim = AIReadinessFactor(
            title: L("eSIM gate and conflicts"),
            detail: esimDetail,
            isReady: esimReady,
            isLiveActive: nil)

        // `aiEnabledCount` counts staged CacheExtra keys (how many of the
        // six AI presets are staged as 1), not CacheData slot values and
        // not live AI state. Live state is `isLiveActive` only; a staged
        // CacheExtra key saying "enabled" is never presented as proof the
        // device's AI is actually on.
        let aiDetail = native ? L("Native Apple Intelligence hardware")
            : "\(aiEnabledCount)/\(aiTotal)"
        let ai = AIReadinessFactor(
            title: L("On-device AI eligibility"),
            detail: aiDetail,
            isReady: native || aiEnabledCount == aiTotal,
            isLiveActive: liveAIEnabled)

        return AIReadinessCheckup(factors: [region, regModelFactor, esim, ai])
    }
}
