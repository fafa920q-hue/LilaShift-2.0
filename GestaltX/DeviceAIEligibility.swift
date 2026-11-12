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
    static func isNativeAppleIntelligence(productType: String) -> Bool {
        nativeProductTypes.contains(productType) || productType.hasPrefix("iPhone19,")
    }

    private static let nativeProductTypes: Set<String> = [
        "iPhone16,1", "iPhone16,2",
        "iPhone17,1", "iPhone17,2", "iPhone17,3", "iPhone17,4", "iPhone17,5",
        "iPhone18,1", "iPhone18,2", "iPhone18,3", "iPhone18,4", "iPhone18,5",
        "iPad13,4", "iPad13,5", "iPad13,6", "iPad13,7", "iPad13,8", "iPad13,9",
        "iPad13,10", "iPad13,11", "iPad13,16", "iPad13,17",
        "iPad14,3", "iPad14,4", "iPad14,5", "iPad14,6",
        "iPad14,8", "iPad14,9", "iPad14,10", "iPad14,11",
        "iPad15,3", "iPad15,4", "iPad15,5", "iPad15,6",
        "iPad16,1", "iPad16,2", "iPad16,3", "iPad16,4", "iPad16,5", "iPad16,6",
        "iPad16,8", "iPad16,9", "iPad16,10", "iPad16,11",
        "iPad17,1", "iPad17,2", "iPad17,3", "iPad17,4",
    ]

    /// Native CacheData baseline for the two guarded AdvAI slots, as a pure
    /// function of product type, so a polluted backup can never downgrade
    /// them. Ground truth per Erosion-CN's live probes (iPhone 18 Pro Max
    /// iPhone19,7 and iPhone 15 Pro Max iPhone16,2, iOS 27): Audio
    /// Intelligence is natively false on iPhone/iPad; Personal Translator
    /// is natively true on native-AI iPhones. Returns `nil` when there is
    /// no known native baseline for this device/key (for example Personal
    /// Translator on iPad, where the recorded original is the baseline).
    static func nativeAdvAISlotValue(key: String, productType: String) -> Bool? {
        if key == DeviceCacheOptions.audioIntelligenceKey,
           productType.hasPrefix("iPhone") || productType.hasPrefix("iPad") {
            return false
        }
        if key == DeviceCacheOptions.personalTranslatorKey,
           productType.hasPrefix("iPhone"), isNativeAppleIntelligence(productType: productType) {
            return true
        }
        return nil
    }
}
