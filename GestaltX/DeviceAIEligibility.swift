// SPDX-License-Identifier: GPL-3.0-only
// Native Apple Intelligence hardware eligibility, owned by GestaltX.
//
// Device list transcribed from Erosion-CN's `isAppleIntellHD` (same
// device identifiers, reimplemented as a pure lookup). Review the list on
// every new iPhone/iPad generation; unknown future models default to NOT
// native (fail closed: the unlock still works, the checkup just reports
// the hardware as not natively eligible). List current as of 2026-11-13
// (iPhone 18 series).
import Foundation

enum DeviceAIEligibility {
    /// Exact-match only: an unlisted model (including a future
    /// `iPhone19,9`) is NOT native. No prefix catch-all — a new
    /// generation must be added here explicitly after it is verified.
    static func isNativeAppleIntelligence(productType: String) -> Bool {
        nativeProductTypes.contains(productType)
    }

    private static let nativeProductTypes: Set<String> = [
        "iPhone16,1", "iPhone16,2",
        "iPhone17,1", "iPhone17,2", "iPhone17,3", "iPhone17,4", "iPhone17,5",
        "iPhone18,1", "iPhone18,2", "iPhone18,3", "iPhone18,4", "iPhone18,5",
        "iPhone19,1", "iPhone19,2", "iPhone19,3", "iPhone19,4",
        "iPhone19,5", "iPhone19,6", "iPhone19,7", "iPhone19,8",
        "iPad13,4", "iPad13,5", "iPad13,6", "iPad13,7", "iPad13,8", "iPad13,9",
        "iPad13,10", "iPad13,11", "iPad13,16", "iPad13,17",
        "iPad14,3", "iPad14,4", "iPad14,5", "iPad14,6",
        "iPad14,8", "iPad14,9", "iPad14,10", "iPad14,11",
        "iPad15,3", "iPad15,4", "iPad15,5", "iPad15,6",
        "iPad16,1", "iPad16,2", "iPad16,3", "iPad16,4", "iPad16,5", "iPad16,6",
        "iPad16,8", "iPad16,9", "iPad16,10", "iPad16,11",
        "iPad17,1", "iPad17,2", "iPad17,3", "iPad17,4",
    ]

    /// Native CacheData SLOT baseline for the two guarded AdvAI slots, as
    /// a pure function of product type, so a polluted backup can never
    /// downgrade them. `key` is the obfuscated key string shared as a
    /// lookup name by the CacheExtra capability and the CacheData slot of
    /// the same name — the returned value is the native CacheData SLOT
    /// value only, never the CacheExtra key's value, and the two must
    /// never be compared against each other. Ground truth per
    /// Erosion-CN's live probes (iPhone 18 Pro Max iPhone19,7 and iPhone
    /// 15 Pro Max iPhone16,2, iOS 27): Audio Intelligence is natively
    /// false on iPhone/iPad; Personal Translator is natively true on
    /// native-AI iPhones. Evidence scope: both baselines were probed on
    /// native-AI hardware only. The baseline therefore applies only to
    /// hardware explicitly listed as native (exact match, never a model
    /// prefix): on unlisted hardware this returns `nil` — unknown, and
    /// callers must fail closed on it, never assume a value. (An earlier
    /// version returned the Audio Intelligence false baseline for any
    /// iPhone/iPad prefix; that over-broad match is removed — an
    /// unlisted model must not inherit a baseline probed on other
    /// hardware.) Returns `nil` when there is no known native baseline
    /// for this device/key (for example Personal Translator on iPad,
    /// where the recorded original is the baseline, or any key on
    /// hardware with no known baseline).
    static func nativeAdvAISlotValue(key: String, productType: String) -> Bool? {
        if key == DeviceCacheOptions.audioIntelligenceKey,
           nativeProductTypes.contains(productType) {
            return false
        }
        if key == DeviceCacheOptions.personalTranslatorKey,
           productType.hasPrefix("iPhone"), nativeProductTypes.contains(productType) {
            return true
        }
        return nil
    }
}
