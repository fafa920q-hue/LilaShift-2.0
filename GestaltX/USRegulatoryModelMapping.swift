// SPDX-License-Identifier: GPL-3.0-only
// US regulatory-model mapping for the opt-in Full US region mode.
//
// Value pairs transcribed from Erosion-CN's `usRegulatoryModelNumber`
// (same A-number pairs, reimplemented as a pure lookup in GestaltX's
// style). The table must be reviewed on every new iPhone generation:
// unknown models are refused (nil), never guessed, and the mode then
// stages region + sales region only.
import Foundation

enum USRegulatoryModelMapping {
    /// US regulatory model for a device, or `nil` when unknown. Tries the
    /// recorded original regulatory model first, then the product type.
    /// iPads return `nil`: the unlock is iPhone-focused and an iPad has
    /// no eSIM group.
    static func usRegulatoryModel(originalRegModel: String?, productType: String) -> String? {
        if let originalRegModel, let mapped = regModelMap[originalRegModel] { return mapped }
        guard !productType.hasPrefix("iPad") else { return nil }
        return productTypeMap[productType]
    }

    // Original regulatory model -> US model.
    private static let regModelMap: [String: String] = [
        // iPhone 18 Pro Max -> US A3473
        "A3718": "A3473", "A3717": "A3473", "A3716": "A3473",
        // iPhone 18 Pro -> US A3472
        "A3715": "A3472", "A3714": "A3472", "A3713": "A3472",
        // iPhone Duo -> US A3447
        "A3721": "A3447", "A3720": "A3447", "A3719": "A3447",
        // iPhone 17 -> US A3258
        "A3520": "A3258", "A3519": "A3258",
        // iPhone 17 Pro -> US A3256
        "A3523": "A3256", "A3522": "A3256",
        // iPhone 17 Pro Max -> US A3257
        "A3526": "A3257", "A3525": "A3257",
        // iPhone Air -> US A3260
        "A3518": "A3260", "A3517": "A3260",
        // iPhone 17e -> US A3575
        "A3635": "A3575", "A3634": "A3575",
        // iPhone 16 -> US A3081
        "A3288": "A3081", "A3287": "A3081",
        // iPhone 16 Plus -> US A3082
        "A3291": "A3082", "A3290": "A3082",
        // iPhone 16 Pro -> US A3083
        "A3294": "A3083", "A3293": "A3083",
        // iPhone 16 Pro Max -> US A3084
        "A3297": "A3084", "A3296": "A3084",
        // iPhone 16e -> US A3212
        "A3410": "A3212", "A3409": "A3212",
        // iPhone 15 -> US A2846
        "A3092": "A2846", "A3090": "A2846",
        // iPhone 15 Plus -> US A2847
        "A3096": "A2847", "A3094": "A2847",
        // iPhone 15 Pro -> US A2848
        "A3104": "A2848", "A3102": "A2848",
        // iPhone 15 Pro Max -> US A2849
        "A3108": "A2849", "A3106": "A2849",
    ]

    // Product type -> US model (fallback when the original regulatory
    // model is unknown or absent).
    private static let productTypeMap: [String: String] = [
        // iPhone 14 series
        "iPhone14,7": "A2649", "iPhone14,8": "A2632",
        "iPhone15,2": "A2650", "iPhone15,3": "A2651",
        // iPhone 15 series
        "iPhone15,4": "A2846", "iPhone15,5": "A2847",
        "iPhone16,1": "A2848", "iPhone16,2": "A2849",
        // iPhone 16 series
        "iPhone17,1": "A3083", "iPhone17,2": "A3084",
        "iPhone17,3": "A3081", "iPhone17,4": "A3082", "iPhone17,5": "A3212",
        // iPhone 17 / Air / 17e series
        "iPhone18,1": "A3256", "iPhone18,2": "A3257",
        "iPhone18,3": "A3258", "iPhone18,4": "A3260", "iPhone18,5": "A3575",
        // iPhone 18 / Duo series (including regional board product types)
        "iPhone19,1": "A3471", "iPhone19,2": "A3472",
        "iPhone19,3": "A3473", "iPhone19,4": "A3447",
        "iPhone19,5": "A3471", "iPhone19,6": "A3472",
        "iPhone19,7": "A3473", "iPhone19,8": "A3447",
    ]
}
