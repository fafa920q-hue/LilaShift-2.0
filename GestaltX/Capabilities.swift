// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 huamidev
// Public MobileGestalt key mappings cross-checked against MGKeys, Nugget and mond.
// Preset behavior is independently implemented for GestaltX.
import Foundation

enum CapabilityCategory: String, CaseIterable, Equatable, Identifiable {
    case display = "Display", device = "Device", ipad = "iPad", intelligence = "Intelligence", advanced = "Advanced"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .display: "display"
        case .device: "iphone"
        case .ipad: "ipad.landscape"
        case .intelligence: "sparkles"
        case .advanced: "wrench.and.screwdriver"
        }
    }
    var subtitle: String {
        switch self {
        case .display: "Dynamic Island, Always-On and Liquid Glass"
        case .device: "Charging, buttons and device identity"
        case .ipad: "Stage Manager and app compatibility"
        case .intelligence: "Region and generative model capabilities"
        case .advanced: "Internal features and research settings"
        }
    }
}

struct Capability: Identifiable, Equatable {
    let id: String
    let category: CapabilityCategory
    let title: String
    let detail: String
    let keys: [String]
    var caution = false
    /// Per-key values for presets that are not a plain Boolean 1, such as the
    /// parallax switch (0) or the AOD flipbook count.
    var values: [String: Any]? = nil

    /// Capabilities are compared by their Equatable fields. `values` is
    /// excluded: `[String: Any]` cannot be Equatable, and the catalog is
    /// keyed by `id`, so the same id always carries the same values in
    /// practice.
    static func == (lhs: Capability, rhs: Capability) -> Bool {
        lhs.id == rhs.id
            && lhs.category == rhs.category
            && lhs.title == rhs.title
            && lhs.detail == rhs.detail
            && lhs.keys == rhs.keys
            && lhs.caution == rhs.caution
    }
    var availableChoices: [PresetChoice] {
        // Preserve the device-specific Siri capability type and allow recovery from older overrides.
        id == "siriOnDevice" ? [.keep, .disable, .removeAdded] : PresetChoice.allCases
    }
    var requiresEnableConfirmation: Bool { id == "storage" }
    var effectHint: String {
        switch id {
        case "ai", "photosCleanUp", "alwaysListeningSiri":
            "Restart required. Apple Intelligence also depends on device and region."
        case "personalTranslator":
            "Restart required. Apple Intelligence also depends on device and region. This stages the CacheExtra key; the CacheData slot is a separate value."
        case "siriOnDevice":
            "Restart required. Siri uses a device-specific capability type; changing it may affect the Apple Intelligence Siri interface. Keep the current value or restore the recorded original."
        case "audioIntelligence":
            "Restart required. Apple Intelligence also depends on device and region. The exact entry point depends on the device and OS version. This stages the CacheExtra key; the CacheData slot is a separate value."
        case "handwritingSynthesis":
            "Restart required. Apple Intelligence also depends on device and region. Results depend on the app and system support."
        case "pencil": "Restart the device, then reopen Settings. Pencil hardware support is still required."
        case "aod":
            "Respring first. Restart the device if the change does not appear. Display behavior depends on the panel and may increase power use and burn-in risk."
        case "liquidGlass":
            "Respring first. Restart the device if the change does not appear. Requires iOS 26 or later."
        case "aodFlipbookCount":
            "A device restart may be required. Experimental; the accepted range varies by iOS build."
        case "pwm":
            "A device restart may be required. Actual dimming behavior depends on the panel."
        case "displayPort":
            "A device restart may be required. Compatible hardware is still required."
        case "chargeLimit":
            "A device restart may be required. Actual charging control depends on hardware."
        case "tapToWake":
            "A device restart may be required. Only shown on devices where tap-to-wake is hidden."
        case "cameraControl":
            "A device restart may be required. This does not add a physical button."
        case "collisionSOS":
            "A device restart may be required. Hardware support is still required."
        case "stageManager":
            "A device restart may be required. Layout behavior varies by device."
        case "internal", "internalSettings":
            "A device restart may be required. Some system services may behave differently."
        case "storage":
            "A device restart may be required. This changes the system-wide InternalBuild flag, not just storage information. System services may behave differently. Revert restores the recorded original value."
        case "srd":
            "A device restart may be required. This does not turn the device into an Apple SRD."
        case "bootChime", "actionButton", "aodHighLuminance", "aodFlipbook":
            "A device restart may be required."
        default: "Respring first. Restart the device if the change does not appear."
        }
    }
    /// The enable value for a plain boolean capability flag. This must
    /// be a real Boolean (`true`), not the integer 1: the codebase
    /// distinguishes Boolean from integer ("Do not conflate Boolean
    /// and integer"), and `ChangeValue` reports them as different
    /// types. Capabilities whose enable value is not a plain boolean
    /// declare it explicitly in `values`.
    var enabled: Any { id == "ipadApps" ? [1, 2] : true }

    func isEnabled(in document: GestaltDocument?) -> Bool {
        guard let fields = document?.extra else { return false }
        return keys.allSatisfy { key in
            guard let value = fields[key] else { return false }
            return GestaltDocument.valuesEqual(value, values?[key] ?? enabled)
        }
    }

    func apply(_ choice: PresetChoice, to document: inout GestaltDocument, restoringFrom snapshot: DocumentSnapshot) {
        guard choice != .keep, availableChoices.contains(choice) else { return }
        for key in keys {
            switch choice {
            case .keep: break
            case .enable: document.set(values?[key] ?? enabled, for: key)
            case .disable: document.set(snapshot.originalValue(for: key), for: key)
            case .removeAdded: document.set(nil, for: key)
            }
        }
        if id == "dynamicIsland", choice == .disable || choice == .removeAdded {
            restoreDynamicIslandLayout(in: &document, from: snapshot)
        }
    }

    func restoreDynamicIslandLayout(in document: inout GestaltDocument, from snapshot: DocumentSnapshot) {
        guard id == "dynamicIsland", var artwork = document.extra[GestaltKeys.artwork] as? [String: Any] else { return }
        let original = snapshot.originalValue(for: GestaltKeys.artwork)
        let originalArtwork = original as? [String: Any]
        // Layout and model-name presets share this dictionary. Restore only the
        // layout member so unrelated artwork edits keep their current values.
        artwork["ArtworkDeviceSubType"] = originalArtwork?["ArtworkDeviceSubType"]
        document.set(artwork.isEmpty && original == nil ? nil : artwork, for: GestaltKeys.artwork)
    }
    static let all: [Self] = [
        .init(id: "dynamicIsland", category: .display, title: "Dynamic Island", detail: "Enable the alternate Dynamic Island capability.", keys: ["YlEtTtHlNesRBMal1CqRaA"]),
        .init(id: "aod", category: .display, title: "Always-On Display", detail: "Keep the Lock Screen visible while the display is off.", keys: ["2OOJf1VhaM7NxfRok3HbWQ", "j8/Omm6s1lsmTDFsXjsBfA"], caution: true),
        .init(id: "aodVibrancy", category: .display, title: "AOD Vibrancy", detail: "Adjust Always-On rendering capabilities.", keys: ["ykpu7qyhqFweVMKtxNylWA"]),
        .init(id: "aodHighLuminance", category: .display, title: "High-Luminance Always-On Display", detail: "Allow Always-On Display to reach a higher brightness level.", keys: ["7brdL5xrEUWnlF9C0kdg5A"]),
        .init(id: "aodFlipbook", category: .display, title: "Always-On Display Flipbook", detail: "Enable AOD flipbook widgets on the Lock Screen.", keys: ["aoJSd/MXk7M40NgXTM6x+g"]),
        .init(id: "aodFlipbookCount", category: .display, title: "AOD Flipbook Count", detail: "Set how many AOD flipbook entries are allowed.", keys: ["qqrspu7CpuPdZwSDxNY+Fg"], caution: true, values: ["qqrspu7CpuPdZwSDxNY+Fg": NSNumber(value: 3)]),
        .init(id: "parallax", category: .display, title: "Disable Wallpaper Parallax", detail: "Stop the wallpaper from moving with device motion.", keys: ["UIParallaxCapability"], values: ["UIParallaxCapability": NSNumber(value: 0)]),
        .init(id: "hdrPhotoDisplay", category: .display, title: "HDR Photo Display", detail: "Enable true HDR rendering for photos.", keys: ["a1r7npIrhXsZ7SmKRKC1eA"]),
        .init(id: "pwm", category: .display, title: "Pulse Width Modulation", detail: "Advertise PWM display support.", keys: ["6IejgN+1Fmu5/QrZFOIeNw"], caution: true),
        .init(id: "displayPort", category: .display, title: "DisplayPort Output", detail: "Advertise DisplayPort output support.", keys: ["CoWnN4xo783YGn4wLrUatA"], caution: true),
        .init(id: "liquidGlass", category: .display, title: "Liquid Glass Low-Power Rendering", detail: "Use low-power Liquid Glass rendering.", keys: ["SAGvsp6O6kAQ4fEfDJpC4Q"]),
        .init(id: "bootChime", category: .device, title: "Boot & Shutdown Chime", detail: "Expose the startup and shutdown sound capability.", keys: ["QHxt+hGLaBPbQJbXiUJX3w"]),
        .init(id: "chargeLimit", category: .device, title: "Charge Limit", detail: "Show charging limit settings.", keys: ["37NVydb//GP/GrhuTN+exg"]),
        .init(id: "tapToWake", category: .device, title: "Tap to Wake", detail: "Expose tap-to-wake.", keys: ["yZf3GTRMGTuwSV/lD7Cagw"]),
        .init(id: "cameraControl", category: .device, title: "Camera Control", detail: "Show Camera Control settings.", keys: ["CwvKxM2cEogD3p+HYgaW0Q", "oOV1jhJbdV3AddkcCg0AEA"]),
        .init(id: "actionButton", category: .device, title: "Action Button", detail: "Show the Action Button settings page.", keys: ["cT44WE1EohiwRzhsZ8xEsw"]),
        .init(id: "collisionSOS", category: .device, title: "Collision SOS", detail: "Show collision detection in Emergency SOS settings.", keys: ["HCzWusHQwZDea6nNhaKndw"]),
        .init(id: "audioMix", category: .device, title: "Audio Mix", detail: "Enable the audio mix capability for supported media.", keys: ["aVL5GE3tx0LSCI/ErfrJGA"]),
        .init(id: "spatialFaceTimeAudio", category: .device, title: "Spatial FaceTime Audio", detail: "Enable spatial audio playback for FaceTime.", keys: ["/EVOCjM/Nmb2roP5ebtEFA"]),
        .init(id: "pencil", category: .ipad, title: "Apple Pencil", detail: "Expose Apple Pencil settings.", keys: ["yhHcB0iH0d1XzPO/CFd3ow"]),
        .init(id: "stageManager", category: .ipad, title: "Stage Manager", detail: "Expose Stage Manager support.", keys: ["qeaj75wk3HF4DwQ8qbIi7g"], caution: true),
        .init(id: "ipadApps", category: .ipad, title: "iPad App Compatibility", detail: "Allow iPad app compatibility types on iPhone.", keys: ["9MZ5AdH43csAUajl/dU+IQ"]),
        .init(id: "ai", category: .intelligence, title: "Apple Intelligence Capability", detail: "Enable Apple Intelligence generative models.", keys: ["A62OafQ85EJAiiqKn4agtg"]),
        .init(id: "siriOnDevice", category: .intelligence, title: "On-Device Siri", detail: "Run Siri processing on the device.", keys: ["K/R1GfGfCkXvEhaPS2Vrng"], caution: true),
        .init(id: "audioIntelligence", category: .intelligence, title: "Audio Intelligence", detail: "Advertise the iOS 27 audio intelligence capability.", keys: ["rb2tKZxlj0Gm2tBmUQSLqQ"], caution: true),
        .init(id: "personalTranslator", category: .intelligence, title: "Personal Translator", detail: "Advertise the personal translator capability.", keys: ["M1n2sAqf33NAOgZRGxQYBA"], caution: true),
        .init(id: "photosCleanUp", category: .intelligence, title: "Photos Clean Up", detail: "Advertise the photos inpainting (Clean Up) capability.", keys: ["XNCjqOupLM/S8fNyxRNQTA"], caution: true),
        .init(id: "handwritingSynthesis", category: .intelligence, title: "Handwriting Synthesis", detail: "Advertise the handwriting synthesis model capability.", keys: ["YgYIIViDt1kgzyIsIV61vA"], caution: true),
        .init(id: "alwaysListeningSiri", category: .intelligence, title: "Always-Listening Hey Siri", detail: "Advertise always-listening Hey Siri support.", keys: ["TusANsf9Lfe3P/9fIXXSrQ"], caution: true),
        .init(id: "internal", category: .advanced, title: "Apple Internal Features", detail: "Expose internal menus.", keys: ["EqrsVvjcYDdxHBiQmGhAWw"], caution: true),
        .init(id: "storage", category: .advanced, title: "Internal Build", detail: "Mark the device as an internal build.", keys: ["LBJfwOEzExRxzlAnSuI7eg"], caution: true),
        .init(id: "srd", category: .advanced, title: "Security Research Device", detail: "Change the Security Research Device capability flag.", keys: ["XYlJKKkj2hztRP1NWWnhlw"], caution: true),
        .init(id: "internalSettings", category: .advanced, title: "Internal Settings Bundle", detail: "Expose Apple's internal settings bundle.", keys: ["Oji6HRoPi7rH7HPdWVakuw"], caution: true),
    ]
}

/// One-tap "China Unlock" (full unlock) for China-mainland devices with
/// eSIM hardware: the eSIM cache flags, region code US (`LL`, sales region
/// untouched) and the six Apple Intelligence presets below.
/// `siriOnDevice` is deliberately excluded: `Capability.availableChoices`
/// for it is only `[.keep, .disable, .removeAdded]`, and 1.0.6 (#102)
/// preserves its device-specific value, so forcing a generic value could
/// revert the Apple Intelligence Siri interface. WAPI and the model number
/// are excluded as well; WAPI can still be disabled on its own.
enum ChinaUnlock {
    static let regionCodeID = "US"
    static let aiCapabilityIDs = ["ai", "audioIntelligence", "personalTranslator",
                                  "photosCleanUp", "handwritingSynthesis", "alwaysListeningSiri"]
    static let aiCapabilities = aiCapabilityIDs.compactMap { id in
        Capability.all.first { $0.id == id }
    }
}

/// Fail-closed model gate for model-dependent presets (P0-4).
///
/// A device is "known" only when it has a verified entry in
/// `USRegulatoryModelMapping` — an exact product-type entry, or a recorded
/// original regulatory model that is itself a verified entry. There is no
/// family or prefix inference: an unlisted variant of a known family
/// (for example iPhone19,9), an unknown ProductType (iPhone99,9), a
/// made-up prefix, an iPad, or an empty product type are all unknown.
///
/// An unknown device must resolve to `.unknown(reason:)` — never to a
/// borrowed layout, a guessed model number, or an assumed capability.
/// The reason is the string the UI shows when the model-dependent part
/// of a preset is withheld.
///
/// Scope: this gates MODEL-DEPENDENT writes only (the Full US model
/// number, and any preset that assumes a known model). It does not gate
/// model-independent writes such as the region code, and it does not
/// gate an explicit per-capability choice the user makes tap by tap in
/// `Capability.apply` — that path has no model judgement to fail closed.
/// Auto-staging paths (one-tap unlock, Fix) must consult this decision
/// before staging anything model-dependent; see the cross-file note in
/// the P0-4 report for the `GestaltManager` wiring.
enum DeviceModelSupport {
    static func decision(for productType: String, originalRegModel: String?) -> DeviceModelDecision {
        if USRegulatoryModelMapping.usRegulatoryModel(originalRegModel: originalRegModel,
                                                      productType: productType) != nil {
            return .known
        }
        return .unknown(reason: USRegulatoryModelMapping.unknownModelReason(
            originalRegModel: originalRegModel, productType: productType)
            ?? L("No US regulatory model known for this device — region code only."))
    }
}

enum DeviceModelDecision: Equatable {
    /// The device has a verified mapping entry; model-dependent presets
    /// may proceed for that entry only.
    case known
    /// The device matches no verified entry: read-only for anything
    /// model-dependent. `reason` explains why it is blocked.
    case unknown(reason: String)

    var isKnown: Bool { self == .known }
    var reason: String? {
        if case .unknown(let reason) = self { return reason }
        return nil
    }
}

/// Region mode for China Unlock. The one-tap unlock always stages exactly
/// the 9-item definition (eSIM + region code LL + six AI keys) in either
/// mode — the sales-region suffix and the regulatory model number are
/// never staged by the one-tap, because a regulatory model that does not
/// match the hardware makes the system discard the whole MobileGestalt
/// cache at boot and rebuild it from factory data, so the region change
/// does not stick. The mode only affects manual region presets (which
/// sales-region key is created on iOS 27) and restoring an unlock applied
/// by an older build.
enum ChinaUnlockRegionMode: String, CaseIterable, Identifiable {
    case regionCodeOnly, fullUS
    var id: String { rawValue }
    static let userDefaultsKey = "GestaltX.chinaUnlockRegionMode"
    static var stored: Self {
        get {
            guard let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
                  let mode = Self(rawValue: raw) else { return .regionCodeOnly }
            return mode
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: userDefaultsKey) }
    }
}

enum PresetChoice: Int, CaseIterable, Identifiable {
    case keep, enable, disable, removeAdded
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .keep: "Keep Current"
        case .enable: "Enable"
        case .disable: "Disable (Restore Original)"
        case .removeAdded: "Remove Added Fields"
        }
    }
}

struct RegionPreset: Identifiable {
    let id: String
    let title: String
    let code: String
    let info: String
    static let all: [Self] = [
        .init(id: "keep", title: "Keep Current", code: "", info: ""),
        .init(id: "US", title: "United States", code: "LL", info: "LL/A"),
        .init(id: "HK", title: "Hong Kong", code: "ZA", info: "ZA/A"),
        .init(id: "JP", title: "Japan", code: "J", info: "J/A"),
        .init(id: "CN", title: "China (Mainland)", code: "CH", info: "CH/A"),
        .init(id: "TW", title: "Taiwan", code: "TA", info: "TA/A"),
        .init(id: "UK", title: "United Kingdom", code: "B", info: "B/A"),
        .init(id: "CA", title: "Canada", code: "C", info: "C/A")
    ]
}

struct ModelPreset: Identifiable {
    static let restoration = Capability(id: "modelNumber", category: .intelligence, title: "Model Number",
                                        detail: "", keys: [GestaltKeys.modelNumber])
    let id: String
    let title: String
    let value: String
    static let all: [Self] = [
        .init(id: "keep", title: "Keep Current", value: ""),
        .init(id: "A3472", title: "A3472 — 18 Pro · United States", value: "A3472"),
        .init(id: "A3713", title: "A3713 — 18 Pro · Canada / Japan", value: "A3713"),
        .init(id: "A3714", title: "A3714 — 18 Pro · Other regions", value: "A3714"),
        .init(id: "A3715", title: "A3715 — 18 Pro · China mainland", value: "A3715"),
        .init(id: "A3473", title: "A3473 — 18 Pro Max · United States", value: "A3473"),
        .init(id: "A3716", title: "A3716 — 18 Pro Max · Canada / Japan", value: "A3716"),
        .init(id: "A3717", title: "A3717 — 18 Pro Max · Other regions", value: "A3717"),
        .init(id: "A3718", title: "A3718 — 18 Pro Max · China mainland", value: "A3718"),
        .init(id: "A3260", title: "A3260 — Air · United States / Canada", value: "A3260"),
        .init(id: "A3516", title: "A3516 — Air · Japan", value: "A3516"),
        .init(id: "A3517", title: "A3517 — Air · Other regions", value: "A3517"),
        .init(id: "A3518", title: "A3518 — Air · China mainland", value: "A3518")
    ]
}

struct FieldDraft: Identifiable {
    let id = UUID()
    var originalKey: String?
    var key = ""
    var kind = PlistValueKind.string
    var text = ""
    private let originalValue: Any?
    private let originalText: String?

    init(originalKey: String? = nil, key: String = "", kind: PlistValueKind = .string,
         text: String = "", originalValue: Any? = nil) {
        self.originalKey = originalKey; self.key = key; self.kind = kind; self.text = text
        self.originalValue = originalValue
        self.originalText = originalValue == nil ? nil : text
    }

    func parsedValue() throws -> Any {
        // Text formats can be less precise than a binary plist, including Date
        // values nested inside an XML array or dictionary. A no-op edit or a
        // key rename must preserve the exact value that populated the editor.
        if let originalValue, kind == PlistValueKind.detect(originalValue),
           text == originalText {
            return originalValue
        }
        return try kind.parse(text)
    }
}
