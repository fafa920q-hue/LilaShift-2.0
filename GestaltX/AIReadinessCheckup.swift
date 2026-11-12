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
// Slot numbers (#178/#266) are per-device observations, never constants:
// every guard resolves its slot dynamically and reports "unknown" when
// resolution fails.
import Foundation

/// A CacheData slot that disagrees with its native baseline on a
/// native-AI iPhone. Slot-only: the CacheExtra key is never consulted.
enum AIConflict: Equatable, Identifiable {
    /// Personal Translator slot reads 0 (or its CacheExtra key is
    /// explicitly 0) on a native-AI iPhone, where it is natively 1.
    case personalTranslatorDisabled(slot: Int?)
    /// Audio Intelligence slot reads 1 on an iPhone/iPad, where it is
    /// natively 0.
    case audioIntelligenceEnabled(slot: Int?)

    var id: String {
        switch self {
        case .personalTranslatorDisabled: return "personalTranslatorDisabled"
        case .audioIntelligenceEnabled: return "audioIntelligenceEnabled"
        }
    }

    var slot: Int? {
        switch self {
        case .personalTranslatorDisabled(let slot): return slot
        case .audioIntelligenceEnabled(let slot): return slot
        }
    }

    var detail: String {
        switch self {
        case .personalTranslatorDisabled:
            L("Personal Translator slot is off on a native-AI iPhone — Photos Clean Up and Camera Siri may fail.")
        case .audioIntelligenceEnabled:
            L("Audio Intelligence slot is on — Photos high-quality Clean Up may fail.")
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
    /// regulatory model; `expectedUSModel` is the mapped US model for Full
    /// US mode (`nil` when no mapping is known).
    static func evaluate(
        regionCode: String?,
        sysconfig: String?,
        regModel: String?,
        regionMode: ChinaUnlockRegionMode,
        expectedUSModel: String?,
        esimEnabled: Bool,
        conflicts: [AIConflict],
        aiEnabledCount: Int,
        aiTotal: Int,
        productType: String,
        liveRegionCode: String?,
        liveRegModel: String?,
        liveAIEnabled: Bool?
    ) -> AIReadinessCheckup {
        let native = DeviceAIEligibility.isNativeAppleIntelligence(productType: productType)

        // Region: the staged code must be LL; in Full US mode the staged
        // sales-region suffix must be LL/A as well.
        let regionReady = regionCode == "LL"
            && (regionMode == .regionCodeOnly || sysconfig == "LL/A")
        let regionDetail: String
        if regionMode == .fullUS, let sysconfig {
            regionDetail = "\(regionCode ?? L("Not present")) · \(sysconfig)"
        } else {
            regionDetail = regionCode ?? L("Not present")
        }
        let region = AIReadinessFactor(
            title: L("Region Code"),
            detail: regionDetail,
            isReady: regionReady,
            isLiveActive: liveRegionCode.map { $0 != "CH" && $0 != "ZA" })

        let regModelReady: Bool
        let regModelTitle: String
        if regionMode == .fullUS {
            regModelTitle = L("Regulatory model")
            regModelReady = expectedUSModel.map { $0 == regModel } ?? (regModel?.isEmpty == false)
        } else {
            // LL-only mode keeps the factory model: any kept value passes.
            regModelTitle = L("Regulatory model (factory model kept)")
            regModelReady = regModel?.isEmpty == false
        }
        let regModelLive: Bool?
        if let liveRegModel {
            regModelLive = regionMode == .fullUS
                ? (expectedUSModel.map { $0 == liveRegModel } ?? true)
                : !liveRegModel.isEmpty
        } else {
            regModelLive = nil
        }
        let regModelFactor = AIReadinessFactor(
            title: regModelTitle,
            detail: regModel ?? L("Not present"),
            isReady: regModelReady,
            isLiveActive: regModelLive)

        let esimDetail: String
        if let conflict = conflicts.first {
            esimDetail = conflict.detail
        } else {
            esimDetail = esimEnabled ? L("Configured") : L("Not Configured")
        }
        let esim = AIReadinessFactor(
            title: L("eSIM gate and conflicts"),
            detail: esimDetail,
            isReady: esimEnabled && conflicts.isEmpty,
            isLiveActive: nil)

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
