// SPDX-License-Identifier: GPL-3.0-only
// Lila Intelligence shared vocabulary (core modules). Pure Swift — no
// SwiftUI, no UIKit, no singletons, no global mutable state. Every type
// here is data; the Lila Intelligence profiler, the eligibility
// evaluator, the recommendation builder, the SafePatch simulator and
// the Restore Intelligence timeline build on it.
//
// Honesty rules that apply to the whole layer:
// - A value that is inaccessible or unverifiable is reported as
//   `.unknown(reason:)`, never fabricated and never defaulted to a
//   plausible value.
// - No string in this layer claims "all models supported", "100% safe",
//   or "fully factory restore".
// - A `reason` string is user-facing and must go through `L()`; keep
//   the number of new reason strings small and reuse existing catalog
//   strings wherever one fits.
// - The first-read value is called the "first-recorded value", never
//   the factory original: a first read cannot prove the device was
//   unmodified before this app first saw it.
import Foundation

enum LilaEngine {
    /// Version of the capability/compatibility catalog data. Bump it
    /// whenever the table changes, so a stale table can be identified.
    static let catalogVersion = 1
    /// Date the catalog data was last reviewed (ISO format).
    static let catalogDate = "2026-11-14"
}

/// A value that is either genuinely known or explicitly unknown.
/// `unknown` carries the specific reason the value could not be
/// obtained — never a fabricated value, never a silent default.
enum ProfileValue<Value: Equatable & Sendable>: Equatable, Sendable {
    case known(Value)
    case unknown(reason: String)

    var value: Value? {
        if case .known(let value) = self { return value }
        return nil
    }

    var isKnown: Bool { value != nil }

    var unknownReason: String? {
        if case .unknown(let reason) = self { return reason }
        return nil
    }
}

/// Whether the device cache has been read, and if not, why.
enum CacheReadState: Equatable, Sendable {
    case notRead
    case read(cacheUUID: String, byteCount: Int)
    case failed(reason: String)
}

/// Eligibility of one feature on this device. Exactly six states; a
/// feature is actionable only in `.eligibleToEnable`. `.unknown` means
/// the device is read-only for that feature until the missing evidence
/// is obtained — it is never treated as eligible.
enum FeatureEligibility: String, Equatable, Sendable {
    /// The device already has this capability natively; staging it
    /// again would overwrite native configuration.
    case nativeSupported
    /// The capability is already configured (staged or applied) on
    /// this device; re-writing it is a no-op, not a native state.
    case alreadyConfigured
    /// Verified compatible and not yet enabled: may be staged.
    case eligibleToEnable
    /// Hardware does not support this feature, or the device is not
    /// in the feature's applicable scope.
    case unsupported
    /// The system or model is unknown, or the evidence needed to
    /// decide is missing: read-only, no auto-apply.
    case unknown
    /// A dependency conflict blocks auto-apply; the specific reason
    /// is carried alongside the state by the caller.
    case conflict

    var isActionable: Bool { self == .eligibleToEnable }
}

/// A specific reason a plan step cannot proceed. Never a generic
/// "failed": `code` is a stable machine-readable identifier (for
/// example "unknown-model", "layout-unresolved", "conflict") and
/// `reason` is the user-facing localized explanation.
struct PlanBlocker: Equatable, Sendable {
    let featureID: String
    let code: String
    let reason: String
}

/// How a detected difference is classified. Only
/// `.recordedByThisApp` and `.differsFromTrustedBackup` carry a known
/// original value; the other cases never claim one, and no case ever
/// asserts that a specific tool made the change.
enum ChangeProvenanceCategory: String, Equatable, Sendable {
    /// This app recorded the change (a `RecordedChange` exists).
    case recordedByThisApp
    /// The current value differs from a backup with trusted
    /// provenance (`.verifiedFactory` or `.preModification`).
    case differsFromTrustedBackup
    /// The value differs from what the device's own evidence implies
    /// but no trusted history proves it — a suspicion, not a fact.
    case suspectedModification
    /// The value differs from a backup whose origin is not trusted
    /// (`.firstRead`, `.importedHistory`, `.unknown`).
    case unknownSource
    /// No evidence of a modification: current state matches every
    /// trusted source, or there is no trusted source to compare.
    case noProvableModification
}

/// One recorded value in a change record. `.absent` means the key did
/// not exist — restoring it means removing the key, never filling in
/// a guessed default.
enum ChangeValue: Equatable, Codable, Sendable {
    case bool(Bool)
    case int(Int)
    case string(String)
    case data(Data)
    case absent
}

extension ChangeValue {
    /// Converts a plist value to a `ChangeValue`, or `nil` when the value
    /// has no `ChangeValue` representation (array, dictionary, date,
    /// real). A missing key converts to `.absent` — restoring it means
    /// removing the key, never filling in a guessed default. Integer
    /// conversion uses `intValue`, matching the flag values (0/1) this
    /// layer classifies; it is not a general 64-bit integer transport.
    static func fromPlistValue(_ value: Any?) -> ChangeValue? {
        guard let value else { return .absent }
        switch PlistValueKind.detect(value) {
        case .boolean: return .bool((value as? NSNumber)?.boolValue ?? false)
        case .integer: return .int((value as? NSNumber)?.intValue ?? 0)
        case .string: return .string(value as? String ?? String(describing: value))
        case .data: return (value as? Data).map(ChangeValue.data)
        case .real, .array, .dictionary, .date: return nil
        }
    }

    /// The plist value this `ChangeValue` represents, or `nil` for
    /// `.absent` (removing the key). Used by the simulator to build the
    /// would-be document in memory only — never a file write.
    var plistValue: Any? {
        switch self {
        case .bool(let value): return NSNumber(value: value)
        case .int(let value): return NSNumber(value: value)
        case .string(let value): return value
        case .data(let value): return value
        case .absent: return nil
        }
    }

    /// Whether this value is a single CacheData byte (a Boolean or an
    /// integer in byte range). Anything else cannot be a slot value.
    var isCacheDataByte: Bool { cacheDataByte != nil }

    var cacheDataByte: UInt8? {
        switch self {
        case .bool(let value): return value ? 1 : 0
        case .int(let value):
            guard (0...255).contains(value) else { return nil }
            return UInt8(value)
        case .string, .data, .absent:
            return nil
        }
    }

    /// Display text for a recorded value. A missing value reads as the
    /// localized "Not set"; anything else uses the app's standard plist
    /// formatter.
    var displayText: String {
        switch self {
        case .absent: return L("Not set")
        case .bool(let value): return value ? "true" : "false"
        case .int(let value): return String(value)
        case .string(let value): return value
        case .data(let value): return value.base64EncodedString()
        }
    }
}

/// Which layer of the cache a change touches. CacheExtra keys and
/// CacheData slots are independent values and must never be compared
/// against each other.
enum ChangeLayer: String, Equatable, Codable, Sendable {
    case cacheExtra
    case cacheData
    case artwork
}

/// One structured change record. `restorable` is true only for a
/// verified change whose backup provenance is trusted
/// (`.verifiedFactory` or `.preModification`): a `.firstRead` or
/// `.importedHistory` record can be shown for manual review, never
/// auto-restored, and an unverified or unknown-provenance record can
/// be shown, never auto-restored.
struct RecordedChange: Equatable, Codable, Sendable {
    let id: UUID
    let date: Date
    let deviceID: String
    let osBuild: String
    let featureID: String
    let key: String
    let layer: ChangeLayer
    let original: ChangeValue
    let new: ChangeValue
    let backupProvenance: BackupProvenance
    let verified: Bool
    /// Whether the change was confirmed after a device restart (the
    /// user restarted and the new value was still in effect). False
    /// means "not confirmed after restart", never "confirmed absent".
    /// Defaults to false so records written before this field decode
    /// and construct unchanged.
    let restartVerified: Bool

    init(id: UUID, date: Date, deviceID: String, osBuild: String,
         featureID: String, key: String, layer: ChangeLayer,
         original: ChangeValue, new: ChangeValue,
         backupProvenance: BackupProvenance, verified: Bool,
         restartVerified: Bool = false) {
        self.id = id
        self.date = date
        self.deviceID = deviceID
        self.osBuild = osBuild
        self.featureID = featureID
        self.key = key
        self.layer = layer
        self.original = original
        self.new = new
        self.backupProvenance = backupProvenance
        self.verified = verified
        self.restartVerified = restartVerified
    }

    /// Decodes records written before `restartVerified` existed as
    /// not restart-verified, never as verified.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        deviceID = try container.decode(String.self, forKey: .deviceID)
        osBuild = try container.decode(String.self, forKey: .osBuild)
        featureID = try container.decode(String.self, forKey: .featureID)
        key = try container.decode(String.self, forKey: .key)
        layer = try container.decode(ChangeLayer.self, forKey: .layer)
        original = try container.decode(ChangeValue.self, forKey: .original)
        new = try container.decode(ChangeValue.self, forKey: .new)
        backupProvenance = try container.decode(BackupProvenance.self, forKey: .backupProvenance)
        verified = try container.decode(Bool.self, forKey: .verified)
        restartVerified = try container.decodeIfPresent(Bool.self, forKey: .restartVerified) ?? false
    }

    var wasAbsent: Bool { original == .absent }
    var restorable: Bool {
        verified && (backupProvenance == .verifiedFactory || backupProvenance == .preModification)
    }
}

/// What the profiler can legally obtain about this device. Every field
/// is either a real value or an explicit `.unknown` — the profiler
/// never fabricates a field, and the evaluator treats `.unknown` as
/// read-only for the features that need it.
struct DeviceProfile: Equatable, Sendable {
    /// Product type, for example "iPhone18,4". Unknown on the
    /// simulator or when the device cannot be identified.
    let productType: ProfileValue<String>
    /// Regulatory model number (A-number) as recorded in the cache.
    let modelNumber: ProfileValue<String>
    /// OS version, for example "27.0.1".
    let osVersion: ProfileValue<String>
    /// OS build, for example "23A344".
    let osBuild: ProfileValue<String>
    /// Region code as recorded in the cache, for example "CH" or "LL".
    let regionCode: ProfileValue<String>
    /// Sales-region suffix, for example "CH/A" or "LL/A".
    let salesRegionSuffix: ProfileValue<String>
    /// Whether this hardware natively supports Apple Intelligence
    /// (exact-match list in `DeviceAIEligibility`).
    let isNativeAppleIntelligence: ProfileValue<Bool>
    /// Fail-closed model gate (`DeviceModelSupport`).
    let modelDecision: DeviceModelDecision
    /// The resolved cache layout, or unknown with the lock reason.
    let cacheLayout: ProfileValue<MobileGestaltCacheLayout>
    let cacheReadState: CacheReadState
    /// Live probe answers (MGCopyAnswer), or unknown when the probe
    /// could not answer (simulator, unreadable key).
    let liveAIEnabled: ProfileValue<Bool>
    let liveRegionCode: ProfileValue<String>
    /// App Group + share-extension state for the signing/install path.
    let appGroupAvailable: ProfileValue<Bool>
    let shareExtensionPresent: ProfileValue<Bool>
    /// Backup inventory: how many backups exist, and whether any of
    /// them has trusted provenance.
    let backupCount: Int
    let hasTrustedBackup: Bool
    let changeRecordCount: Int
}

/// A source of device identity facts. Implementations read what is
/// legally obtainable and return `nil` for what is not; the profiler
/// turns `nil` into `.unknown` with a reason.
protocol DeviceIdentitySource: Sendable {
    var productType: String? { get }
    var osVersion: String? { get }
    var osBuild: String? { get }
}

/// The system identity source: product type from the machine
/// identifier, OS version and build from `ProcessInfo`. Returns `nil`
/// where the platform does not expose a value (for example the
/// product type on the simulator, where the machine is "arm64").
struct SystemDeviceIdentitySource: DeviceIdentitySource {
    var productType: String? {
        var name = utsname()
        guard uname(&name) == 0 else { return nil }
        let machine = withUnsafeBytes(of: name.machine) { raw in
            raw.withMemoryRebound(to: CChar.self) { String(cString: $0.baseAddress!) }
        }
        // A simulator reports its host CPU ("arm64"/"x86_64"), which is
        // not a product type. Only iPhone/iPad identifiers count.
        guard machine.hasPrefix("iPhone") || machine.hasPrefix("iPad") else { return nil }
        return machine
    }

    var osVersion: String? {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    var osBuild: String? {
        // "Version 27.0.1 (Build 23A344)" — the build is the parenthesised part.
        let text = ProcessInfo.processInfo.operatingSystemVersionString
        guard let open = text.firstIndex(of: "("), let close = text.firstIndex(of: ")"),
              open < close else { return nil }
        let build = text[text.index(after: open)..<close]
            .replacingOccurrences(of: "Build ", with: "")
            .trimmingCharacters(in: .whitespaces)
        return build.isEmpty ? nil : build
    }
}

extension BackupProvenance {
    /// Provenance trusted enough for an automatic restore: factory
    /// state verified against the system vault, or state recorded
    /// immediately before this app wrote. First-read, imported and
    /// unknown-origin state is not trusted for auto-restore.
    var isTrustedForRestore: Bool {
        self == .verifiedFactory || self == .preModification
    }
}
