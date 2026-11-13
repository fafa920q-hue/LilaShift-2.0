// SPDX-License-Identifier: GPL-3.0-only
// Device Capability Fingerprint (设备能力指纹) — a persistent,
// versioned record of this device's REAL capabilities and system
// build characteristics, stored locally with a SHA-256 digest.
// Pure Foundation — no SwiftUI, no UIKit, no singletons, no global
// mutable state.
//
// A fingerprint is captured only from a real read: `capture`
// returns `nil` when there is no snapshot, and a device that has
// never been read has NO fingerprint (unknown), never a default
// one. On each read, `compare` lists what changed against the
// stored fingerprint. A change to the product type, OS build, cache
// layout UUID or slot count invalidates the previously recorded
// support scope: the UI must flag that re-verification is needed,
// because a support statement made for one build does not carry
// over to another.
import Foundation

// MARK: - Fingerprint

/// A versioned snapshot of the device's real capabilities. Every
/// field is optional: a field that could not be read is `nil`
/// (unknown), never a guessed value. `digest` is a SHA-256 over the
/// canonical encoding of the fields — it is computed, never stored,
/// so a stored fingerprint can always be re-verified.
struct DeviceFingerprint: Equatable, Codable, Sendable {
    static let currentVersion = 1

    let version: Int
    let deviceID: String
    let productType: String?
    let modelNumber: String?
    let osVersion: String?
    let osBuild: String?
    let regionCode: String?
    let salesRegionSuffix: String?
    let cacheLayoutUUID: String?
    let cacheSlotCount: Int?
    let cacheByteCount: Int?
    let esimGreenTea: Bool?
    let esimNotGreenTea: Bool?
    let wapiEnabled: Bool?
    let audioIntelligenceSlot: Bool?
    let personalTranslatorSlot: Bool?
    let isNativeAppleIntelligence: Bool?
    let appGroupAvailable: Bool?
    let backupCount: Int?
    let hasTrustedBackup: Bool?
    let recordedAt: Date

    /// SHA-256 hex over the canonical encoding of every field
    /// except `recordedAt` (the capture time is metadata, not
    /// device state: two captures of the same device must hash
    /// the same).
    var digest: String {
        let parts: [String] = [
            "v\(version)", deviceID,
            productType ?? "-", modelNumber ?? "-",
            osVersion ?? "-", osBuild ?? "-",
            regionCode ?? "-", salesRegionSuffix ?? "-",
            cacheLayoutUUID ?? "-",
            cacheSlotCount.map(String.init) ?? "-",
            cacheByteCount.map(String.init) ?? "-",
            esimGreenTea.map { $0 ? "1" : "0" } ?? "-",
            esimNotGreenTea.map { $0 ? "1" : "0" } ?? "-",
            wapiEnabled.map { $0 ? "1" : "0" } ?? "-",
            audioIntelligenceSlot.map { $0 ? "1" : "0" } ?? "-",
            personalTranslatorSlot.map { $0 ? "1" : "0" } ?? "-",
            isNativeAppleIntelligence.map { $0 ? "1" : "0" } ?? "-",
            appGroupAvailable.map { $0 ? "1" : "0" } ?? "-",
            backupCount.map(String.init) ?? "-",
            hasTrustedBackup.map { $0 ? "1" : "0" } ?? "-",
        ]
        return HistoryJournal.sha256Hex(of: Data(parts.joined(separator: "|").utf8))
    }
}

/// One field that changed between two fingerprints. `field` is a
/// stable machine-readable key; `displayName` is the user-facing
/// label; `old` / `new` are display strings ("Unknown" when the
/// value was not readable). `invalidatesSupportScope` is true for
/// the fields whose change means the previously recorded support
/// scope may no longer apply.
struct FingerprintChange: Equatable, Identifiable, Sendable {
    var id: String { field }
    let field: String
    let displayName: String
    let old: String
    let new: String
    let invalidatesSupportScope: Bool
}

/// The result of comparing a current fingerprint against the stored
/// one. `changes` is empty when nothing changed. When the stored
/// fingerprint is from a different device, `compare` reports that
/// instead of listing field changes.
struct FingerprintComparison: Equatable, Sendable {
    let changes: [FingerprintChange]
    let differentDevice: Bool
    let invalidatesSupportScope: Bool

    var hasChanges: Bool { differentDevice || !changes.isEmpty }
}

// MARK: - Capture and compare

enum DeviceFingerprintCapture {
    /// Captures the current fingerprint from the profile and the
    /// read snapshot. Returns `nil` when there is no snapshot —
    /// a device that has never been read has no fingerprint.
    /// The eSIM flags, WAPI flag and AI slot values come from the
    /// document through `DeviceCacheOptions`, the same readers the
    /// rest of the app uses; a value that cannot be read stays
    /// `nil`.
    static func capture(profile: DeviceProfile, snapshot: DocumentSnapshot?) -> DeviceFingerprint? {
        guard let snapshot else { return nil }
        let document = snapshot.document
        let layout = profile.cacheLayout.value
        let flags = try? DeviceCacheOptions.flags(in: document, using: layout)
        return DeviceFingerprint(
            version: DeviceFingerprint.currentVersion,
            deviceID: document.extra["UniqueDeviceID"] as? String ?? "",
            productType: profile.productType.value,
            modelNumber: profile.modelNumber.value,
            osVersion: profile.osVersion.value,
            osBuild: profile.osBuild.value,
            regionCode: document.extra[GestaltKeys.regionCode] as? String,
            salesRegionSuffix: document.extra[GestaltKeys.regionInfo] as? String,
            cacheLayoutUUID: document.root["CacheUUID"] as? String,
            cacheSlotCount: layout?.slotCount,
            cacheByteCount: layout?.byteCount,
            esimGreenTea: flags?.greenTea,
            esimNotGreenTea: flags?.notGreenTea,
            wapiEnabled: try? DeviceCacheOptions.wapi(in: document, using: layout),
            audioIntelligenceSlot: DeviceCacheOptions.advAISlotValue(
                DeviceCacheOptions.audioIntelligenceKey, in: document, using: layout),
            personalTranslatorSlot: DeviceCacheOptions.advAISlotValue(
                DeviceCacheOptions.personalTranslatorKey, in: document, using: layout),
            isNativeAppleIntelligence: profile.isNativeAppleIntelligence.value,
            appGroupAvailable: profile.appGroupAvailable.value,
            backupCount: profile.backupCount,
            hasTrustedBackup: profile.hasTrustedBackup,
            recordedAt: Date())
    }

    /// Compares `current` against `stored` field by field. Fields
    /// that were unreadable on either side are compared as
    /// "unknown" strings, so a value appearing or disappearing is
    /// still reported as a change. Product type, OS build, cache
    /// layout UUID and slot count invalidate the support scope.
    static func compare(stored: DeviceFingerprint, current: DeviceFingerprint) -> FingerprintComparison {
        guard stored.deviceID == current.deviceID else {
            return FingerprintComparison(changes: [], differentDevice: true,
                                         invalidatesSupportScope: true)
        }
        var changes: [FingerprintChange] = []
        func add(
            field: String, displayName: String, old: String?, new: String?,
            invalidates: Bool = false
        ) {
            guard old != new else { return }
            changes.append(FingerprintChange(
                field: field, displayName: displayName,
                old: old ?? L("Unknown"), new: new ?? L("Unknown"),
                invalidatesSupportScope: invalidates))
        }
        add(field: "productType", displayName: L("Product type"),
            old: stored.productType, new: current.productType, invalidates: true)
        add(field: "modelNumber", displayName: L("Model number"),
            old: stored.modelNumber, new: current.modelNumber)
        add(field: "osVersion", displayName: L("iOS version"),
            old: stored.osVersion, new: current.osVersion)
        add(field: "osBuild", displayName: L("Build"),
            old: stored.osBuild, new: current.osBuild, invalidates: true)
        add(field: "regionCode", displayName: L("Region code"),
            old: stored.regionCode, new: current.regionCode)
        add(field: "salesRegionSuffix", displayName: L("Sales region"),
            old: stored.salesRegionSuffix, new: current.salesRegionSuffix)
        add(field: "cacheLayoutUUID", displayName: L("Cache layout"),
            old: stored.cacheLayoutUUID, new: current.cacheLayoutUUID, invalidates: true)
        add(field: "cacheSlotCount", displayName: L("Cache slots"),
            old: stored.cacheSlotCount.map(String.init), new: current.cacheSlotCount.map(String.init),
            invalidates: true)
        add(field: "cacheByteCount", displayName: L("Cache bytes"),
            old: stored.cacheByteCount.map(String.init), new: current.cacheByteCount.map(String.init))
        add(field: "esimGreenTea", displayName: L("eSIM green-tea"),
            old: boolText(stored.esimGreenTea), new: boolText(current.esimGreenTea))
        add(field: "esimNotGreenTea", displayName: L("eSIM not-green-tea"),
            old: boolText(stored.esimNotGreenTea), new: boolText(current.esimNotGreenTea))
        add(field: "wapiEnabled", displayName: L("WAPI"),
            old: boolText(stored.wapiEnabled), new: boolText(current.wapiEnabled))
        add(field: "audioIntelligenceSlot", displayName: L("Audio Intelligence slot"),
            old: boolText(stored.audioIntelligenceSlot), new: boolText(current.audioIntelligenceSlot))
        add(field: "personalTranslatorSlot", displayName: L("Personal Translator slot"),
            old: boolText(stored.personalTranslatorSlot), new: boolText(current.personalTranslatorSlot))
        add(field: "isNativeAppleIntelligence", displayName: L("Native Apple Intelligence"),
            old: boolText(stored.isNativeAppleIntelligence), new: boolText(current.isNativeAppleIntelligence))
        add(field: "appGroupAvailable", displayName: L("App Group"),
            old: boolText(stored.appGroupAvailable), new: boolText(current.appGroupAvailable))
        add(field: "backupCount", displayName: L("Backups"),
            old: stored.backupCount.map(String.init), new: current.backupCount.map(String.init))
        add(field: "hasTrustedBackup", displayName: L("Trusted backup"),
            old: boolText(stored.hasTrustedBackup), new: boolText(current.hasTrustedBackup))
        return FingerprintComparison(
            changes: changes, differentDevice: false,
            invalidatesSupportScope: changes.contains(where: \.invalidatesSupportScope))
    }

    /// "On" / "Off" for a Bool?, `nil` when the value was unreadable.
    private static func boolText(_ value: Bool?) -> String? {
        value.map { $0 ? L("On") : L("Off") }
    }
}

// MARK: - Store

/// Persists one fingerprint per device, as a v1 envelope with a
/// SHA-256 sidecar, verified by a read-back — the same pattern as
/// `ChangeRecordStore`. The store writes to the app's own history
/// directory, never to the MobileGestalt cache. A fingerprint for
/// another device is refused, never trusted.
struct DeviceFingerprintStore: Sendable {
    static let currentVersion = 1
    static let fileName = "device-fingerprint.json"

    let directory: URL
    let deviceID: String

    init(directory: URL, deviceID: String) {
        self.directory = directory
        self.deviceID = deviceID
    }

    private var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    /// Loads the stored fingerprint. A missing file loads as
    /// `nil` (no fingerprint yet — the device has never been
    /// recorded). A digest mismatch, an undecodable file, an
    /// envelope newer than this version, or an envelope for
    /// another device throws.
    func load() throws -> DeviceFingerprint? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let envelope = try HistoryJournal.readVerifiedJSON(
                HistoryEnvelope<DeviceFingerprint>.self, from: fileURL)
            guard envelope.version <= Self.currentVersion else {
                throw GestaltFailure("This history uses a newer format this version cannot read.")
            }
            guard envelope.deviceID == deviceID else {
                throw GestaltFailure("This history belongs to a different device.")
            }
            return envelope.records.first
        } catch let error as HistoryJournalError {
            switch error {
            case .fileNotFound:
                return nil
            case .digestMismatch, .decodeFailed, .writeFailed:
                throw GestaltFailure("The device fingerprint could not be read. No system changes were made.")
            }
        } catch let error as GestaltFailure {
            throw error
        } catch {
            throw GestaltFailure("The device fingerprint could not be read. No system changes were made.")
        }
    }

    /// Saves the fingerprint as a v1 envelope with a SHA-256
    /// sidecar, verified by a read-back. A fingerprint with an
    /// empty device ID (the device was never identified) is
    /// refused: an unidentified fingerprint must never be stored
    /// as if it belonged to this device.
    func save(_ fingerprint: DeviceFingerprint) throws {
        guard !fingerprint.deviceID.isEmpty else {
            throw GestaltFailure("The device could not be identified, so its fingerprint was not saved.")
        }
        do {
            try HistoryJournal.writeVerifiedJSON(
                HistoryEnvelope(version: Self.currentVersion, deviceID: deviceID,
                                records: [fingerprint]),
                to: fileURL)
        } catch {
            throw GestaltFailure("The device fingerprint could not be saved. No system changes were made.")
        }
    }
}
