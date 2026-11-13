// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 huamidev
import Foundation
import SwiftUI
import Combine

struct PlistImportOffer: Identifiable {
    let id = UUID()
    let data: Data
    let name: String
    let identity: DevicePlistIdentity?
    let sharedSource: (SharedPlistInbox, SharedPlistEntry)?
}

@MainActor
final class GestaltManager: ObservableObject {
    @Published private(set) var snapshot: DocumentSnapshot?
    @Published private(set) var working: GestaltDocument?
    @Published private(set) var isBusy = false
    /// True only while `connect()` is reading the device. Presentation
    /// state for the read-progress card; no read/write behavior depends
    /// on it.
    @Published private(set) var isReading = false
    @Published private(set) var status = "Connect to your device or open a plist."
    @Published private(set) var deviceAccessible = false
    @Published private(set) var backups: [BackupRecord] = []
    @Published private(set) var logs: [String] = []
    @Published var message: String?
    @Published var isRespringing = false
    @Published var needsRespring = false
    @Published var choices: [String: PresetChoice] = [:]
    @Published var regionID = "keep"
    @Published var regionCodeID = "keep"
    @Published var modelID = "keep"
    /// Region mode for China Unlock (default region-code-only).
    /// Persisted across launches; never reset by loading a document.
    /// The one-tap unlock stages the same 9 items in either mode; the
    /// mode only affects manual region presets and restoring an unlock
    /// applied by an older build.
    @Published var chinaUnlockRegionMode: ChinaUnlockRegionMode = .regionCodeOnly
    /// The user explicitly confirmed an unverified (warned) AI staging
    /// combination after reading its reason on the checkup card, by
    /// tapping Fix. In-memory only, never persisted: a fresh launch
    /// re-surfaces the warning. Reset whenever a new document is loaded.
    /// Only ever converts a `.warn` decision into `.allow` (see
    /// `AIStagingGuard`); a `.block` is never overridden by it.
    @Published var userConfirmedUnverifiedAICombination = false
    @Published var changesName = false
    @Published var modelName = ""
    @Published var subtype = 0
    @Published private(set) var wapiChoice: WAPIChoice = .keep
    @Published private(set) var cacheOptionChoice: CacheOptionChoice = .keep
    private let files: GestaltFileStore
    private var exploitLogObserver: NSObjectProtocol?

    init() {
        let defaults = UserDefaults.standard
        chinaUnlockRegionMode = ChinaUnlockRegionMode.stored
        let deviceID = defaults.string(forKey: "GestaltX.installationID") ?? UUID().uuidString
        defaults.set(deviceID, forKey: "GestaltX.installationID")
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GestaltX/Backups", isDirectory: true)
        files = GestaltFileStore(deviceURL: URL(fileURLWithPath: GestaltKeys.devicePath), backupDirectory: directory,
                                deviceID: deviceID, acquire: {
            #if targetEnvironment(simulator)
            throw GestaltFailure("Device access is unavailable in the Simulator. Open a plist to explore LilaShift.")
            #else
            let target = (GestaltKeys.devicePath as NSString).deletingLastPathComponent
            let signedGroups = GXEntitlementsReader.usableAppGroups()
            guard !signedGroups.isEmpty else {
                throw GestaltFailure("The signed app has no usable App Group. Enable its App Group capability and sign it again.")
            }
            // Re-signed certificates often carry several App Groups and only some of
            // them hold a usable container, so try each one instead of trusting one.
            var rejection: Int64 = -1
            for signedGroup in signedGroups {
                var handle = worse_query(target, signedGroup, false, false)
                if handle == -4, let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: signedGroup) {
                    // The exploit swaps Library/Caches for a symlink, so a container
                    // without Library fails until the directory exists.
                    try? FileManager.default.createDirectory(at: root.appendingPathComponent("Library/Caches"),
                                                             withIntermediateDirectories: true)
                    handle = worse_query(target, signedGroup, false, false)
                }
                if handle >= 0 { return handle }
                rejection = handle
            }
            if rejection == -1 {
                throw GestaltFailure("The signed app has no usable App Group. Enable its App Group capability and sign it again.")
            }
            throw GestaltFailure("MobileGestalt access was denied. Check the OS version and App Group signing.")
            #endif
        }, release: { worse_query_release($0) },
        expectedDeviceURL: URL(fileURLWithPath: GestaltKeys.devicePath),
        eventSink: { text in
            NotificationCenter.default.post(name: Notification.Name("GestaltX.worse_query.log"), object: nil,
                                            userInfo: ["message": text])
        })
        exploitLogObserver = NotificationCenter.default.addObserver(forName: Notification.Name("GestaltX.worse_query.log"), object: nil, queue: nil) { [weak self] notification in
            guard let text = notification.userInfo?["message"] as? String else { return }
            DispatchQueue.main.async { [weak self] in self?.log("[worse_query] " + text) }
        }
    }

    deinit { if let exploitLogObserver { NotificationCenter.default.removeObserver(exploitLogObserver) } }

    var changeKeys: [String] {
        guard let before = snapshot?.document.extra, let after = preview?.extra else { return [] }
        return Set(before.keys).union(after.keys).filter { key in
            switch (before[key], after[key]) {
            case (nil, nil): return false
            case (nil, _), (_, nil): return true
            case (let a?, let b?): return !GestaltDocument.valuesEqual(a, b)
            }
        }.sorted()
    }
    var cacheDataChanges: [CachedBooleanChange] {
        guard let original = snapshot?.document, let edited = preview else { return [] }
        return DeviceCacheOptions.changes(from: original, to: edited)
    }
    /// Full CacheData diff for the review sheet, including any changed
    /// byte outside the known slots.
    var cacheDataDiff: CacheDataDiff? {
        guard let original = snapshot?.document, let edited = preview else { return nil }
        return DeviceCacheOptions.diff(from: original, to: edited)
    }
    /// Pre-preview validation gate: the same `validateEdit` that `commit`
    /// enforces, run when the review sheet opens so a staged edit that
    /// fails validation is shown (and Apply disabled) before Apply is
    /// pressed. The commit-time check remains the enforcement point.
    var previewValidationError: String? {
        guard let snapshot, let preview else { return nil }
        do {
            try DeviceCacheOptions.validateEdit(from: snapshot.document, to: preview)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
    var changeCount: Int { changeKeys.count + cacheDataChanges.count }
    var hasDocument: Bool { snapshot != nil }
    var sourceIsDevice: Bool { snapshot?.source == .device }
    var artworkEditingError: GestaltFailure? {
        guard let working, !working.canEditArtwork else { return nil }
        return GestaltFailure("The artwork field is not a dictionary. Edit it in MG Control before using these presets.")
    }
    var displayedName: String {
        working?.artwork["ArtworkDeviceProductDescription"] as? String ?? working?.extra["Z/dqyWS6OZTRy10UcmUAhw"] as? String ?? UIDevice.current.model
    }
    var preview: GestaltDocument? {
        guard var doc = working, let snapshot else { return nil }
        for capability in Capability.all {
            capability.apply(choices[capability.id] ?? .keep, to: &doc, restoringFrom: snapshot)
        }
        if subtype != 0, doc.setArtwork(NSNumber(value: subtype), for: "ArtworkDeviceSubType") {
            doc.set(NSNumber(value: true), for: "YlEtTtHlNesRBMal1CqRaA")
        }
        if changesName, doc.setArtwork(modelName.trimmingCharacters(in: .whitespacesAndNewlines), for: "ArtworkDeviceProductDescription") {
            doc.set(modelName.trimmingCharacters(in: .whitespacesAndNewlines), for: "Z/dqyWS6OZTRy10UcmUAhw")
            doc.set(modelName.trimmingCharacters(in: .whitespacesAndNewlines), for: "bbtR9jQx50Fv5Af/affNtA")
        }
        doc.applyRegion(salesRegion: RegionPreset.all.first { $0.id == regionID },
                        regionCode: RegionPreset.all.first { $0.id == regionCodeID },
                        skipCreatingRegionInfoOnModernOS: chinaUnlockRegionMode == .fullUS)
        doc.applyModel(ModelPreset.all.first { $0.id == modelID })
        return doc
    }

    private func log(_ text: String) {
        let time = Date.now.formatted(date: .omitted, time: .standard)
        logs.append("[\(time)] \(text)")
        if logs.count > 1000 { logs.removeFirst(logs.count - 1000) }
    }
    private func failed(_ error: Error) { message = error.localizedDescription; log(error.localizedDescription) }
    private func accept(_ loaded: DocumentSnapshot) {
        snapshot = loaded; working = loaded.document
        choices = [:]; regionID = "keep"; regionCodeID = "keep"; modelID = "keep"; changesName = false; subtype = 0
        userConfirmedUnverifiedAICombination = false
        cacheOptionChoice = .keep
        wapiChoice = .keep
        modelName = loaded.document.artwork["ArtworkDeviceProductDescription"] as? String ?? ""
    }
    func clearStaged() {
        if let snapshot { accept(snapshot) }
    }

    /// Test-only entry point: loads a fixture snapshot so staging and
    /// preview logic can be verified without a device or signing.
    /// Production code never calls this; it only resets staged state
    /// through the same `accept` path as a real read.
    func loadSnapshotForTests(_ snapshot: DocumentSnapshot) { accept(snapshot) }

    // MARK: - China Unlock

    /// True while the full China Unlock is staged (not yet applied):
    /// eSIM flags enabled, region code US and all six AI presets enabled.
    var isChinaUnlockStaged: Bool {
        guard hasDocument else { return false }
        return cacheOptionChoice == .enable
            && regionCodeID == ChinaUnlock.regionCodeID
            && ChinaUnlock.aiCapabilityIDs.allSatisfy { (choices[$0] ?? .keep) == .enable }
    }

    /// Region code shown by the staged preview (`LL` once unlocked).
    var previewRegionCode: String? { preview?.extra[GestaltKeys.regionCode] as? String }

    var previewESIMFlags: CachedOptionFlags? {
        guard let preview else { return nil }
        return try? DeviceCacheOptions.flags(in: preview)
    }

    var isESIMUnlockedInPreview: Bool { previewESIMFlags == .enabled }

    var chinaUnlockEnabledAICapabilityIDs: Set<String> {
        guard let fields = preview?.extra else { return [] }
        return Set(ChinaUnlock.aiCapabilities.filter { capability in
            capability.keys.allSatisfy { (fields[$0] as? NSNumber)?.intValue == 1 }
        }.map(\.id))
    }

    var chinaUnlockAIEnabledCount: Int { chinaUnlockEnabledAICapabilityIDs.count }

    /// True when the preview already shows the full unlock, whether it was
    /// just staged or applied in an earlier session: eSIM enabled, region
    /// code LL and all six AI presets enabled. The sales-region suffix
    /// and the regulatory model number are never part of the unlock, so
    /// they are not required here.
    var isChinaUnlockedInPreview: Bool {
        isESIMUnlockedInPreview && previewRegionCode == "LL"
            && chinaUnlockAIEnabledCount == ChinaUnlock.aiCapabilityIDs.count
    }

    /// True while the AI-only preset is staged: all six AI presets
    /// enabled. This is the AI part of the one-tap unlock, staged on its
    /// own; eSIM and region are untouched. It is not blocked by the eSIM
    /// cache layout, because the six AI keys are CacheExtra values and do
    /// not need the layout to resolve.
    var isChinaAIOnlyStaged: Bool {
        guard hasDocument else { return false }
        return ChinaUnlock.aiCapabilityIDs.allSatisfy { (choices[$0] ?? .keep) == .enable }
    }

    /// True when the preview already shows all six AI presets enabled,
    /// whether staged now or applied in an earlier session.
    var isChinaAIOnlyApplied: Bool {
        chinaUnlockAIEnabledCount == ChinaUnlock.aiCapabilityIDs.count
    }

    /// True while the eSIM+region preset is staged: eSIM flags enabled
    /// and region code US. This is the eSIM+region part of the one-tap
    /// unlock, staged on its own; the six AI presets are untouched.
    var isChinaESIMRegionStaged: Bool {
        guard hasDocument else { return false }
        return cacheOptionChoice == .enable && regionCodeID == ChinaUnlock.regionCodeID
    }

    /// True when the preview already shows eSIM enabled and region code
    /// LL, whether staged now or applied in an earlier session.
    var isChinaESIMRegionApplied: Bool {
        isESIMUnlockedInPreview && previewRegionCode == "LL"
    }

    // MARK: - AI readiness checkup (item 4)

    /// Live on-device probe answers (MGCopyAnswer). `nil` means the probe
    /// could not answer (simulator, or the key is unreadable) — the
    /// checkup renders "live: unknown", never a faked value.
    @Published var liveRegionCode: String?
    @Published var liveRegModel: String?
    @Published var liveAIEnabled: Bool?

    /// Refreshes the live probe answers. Read-only; safe to call from the
    /// checkup card's `onAppear`.
    func refreshLiveProbe() {
        liveRegionCode = LiveGestaltProbe.queryString(GestaltKeys.regionCode)
        liveRegModel = LiveGestaltProbe.queryString(GestaltKeys.modelNumber)
        liveAIEnabled = Capability.all.first { $0.id == "ai" }.flatMap { capability in
            capability.keys.first.flatMap { LiveGestaltProbe.queryBool($0) }
        }
    }

    /// Slot and key conflicts on native-AI hardware, computed from the staged
    /// preview. The Personal Translator case is split per layer: a CacheData
    /// slot reading 0 against its native baseline of 1, and a CacheExtra key
    /// explicitly 0, are separate conflicts. The Audio Intelligence case
    /// stays slot-only (see the #178 note in AIReadinessCheckup.swift): the
    /// unlock sets CacheExtra `audioIntelligence` = 1 by definition, and
    /// whether that key alone harms native-AI iPhones is unverified. An
    /// unresolvable slot means "unknown", never a conflict.
    var aiConflicts: [AIConflict] {
        guard let preview,
              let productType = preview.extra[GestaltKeys.productType] as? String,
              DeviceAIEligibility.isNativeAppleIntelligence(productType: productType),
              let layout = try? MobileGestaltCacheLayout.resolve(in: preview) else { return [] }
        var conflicts: [AIConflict] = []
        let ptBaseline = DeviceAIEligibility.nativeAdvAISlotValue(
            key: DeviceCacheOptions.personalTranslatorKey, productType: productType)
        if ptBaseline == true {
            let slotValue = DeviceCacheOptions.advAISlotValue(
                DeviceCacheOptions.personalTranslatorKey, in: preview, using: layout)
            if slotValue == false {
                conflicts.append(.personalTranslatorSlotDisabled(
                    slot: layout.slotIndex(forKey: DeviceCacheOptions.personalTranslatorKey)))
            }
            if (preview.extra[DeviceCacheOptions.personalTranslatorKey] as? NSNumber)?.intValue == 0 {
                conflicts.append(.personalTranslatorKeyDisabled)
            }
        }
        let audioBaseline = DeviceAIEligibility.nativeAdvAISlotValue(
            key: DeviceCacheOptions.audioIntelligenceKey, productType: productType)
        if audioBaseline == false,
           DeviceCacheOptions.advAISlotValue(
               DeviceCacheOptions.audioIntelligenceKey, in: preview, using: layout) == true {
            conflicts.append(.audioIntelligenceEnabled(
                slot: layout.slotIndex(forKey: DeviceCacheOptions.audioIntelligenceKey)))
        }
        return conflicts
    }

    /// The staging-guard decision for a document, or `nil` when the guard
    /// has no input. `nil` has two distinct causes, and callers must not
    /// treat them as a block: the layout did not resolve at all (the
    /// eSIM layout gate is the fail-closed enforcement for that case), or
    /// the layout carries no resolved AdvAI slot index at all — the
    /// offline profile and the simulator, where the slots are
    /// unobservable rather than conflicting. The pure guard
    /// (`AIStagingGuard.decide`) still fails closed on an unresolvable
    /// slot when a caller can establish the slot should have resolved;
    /// the manager cannot establish that (a real device scan can
    /// legitimately find no AdvAI descriptors), so it reports no decision
    /// instead of blocking the unlock on unobservable slots. `nil` is
    /// therefore "no guard input", never "safe" and never "blocked".
    /// `proposedUnlock` evaluates the China Unlock proposal (both guarded
    /// CacheExtra keys staged as 1) instead of the document's current
    /// staged values — what Fix is about to stage, rather than what is
    /// already staged.
    static func stagingDecision(for document: GestaltDocument,
                                layout: MobileGestaltCacheLayout,
                                liveAIEnabled: Bool?,
                                userConfirmedUnverifiedCombination: Bool,
                                proposedUnlock: Bool) -> AIStagingDecision? {
        let audioIndex = layout.slotIndex(forKey: DeviceCacheOptions.audioIntelligenceKey)
        let translatorIndex = layout.slotIndex(forKey: DeviceCacheOptions.personalTranslatorKey)
        guard audioIndex != nil || translatorIndex != nil else { return nil }
        let productType = document.extra[GestaltKeys.productType] as? String ?? ""
        var request = AIStagingRequest(productType: productType)
        if proposedUnlock {
            request.audioIntelligenceExtra = true
            request.personalTranslatorExtra = true
        } else {
            request.audioIntelligenceExtra = (document.extra[DeviceCacheOptions.audioIntelligenceKey] as? NSNumber)?.boolValue
            request.personalTranslatorExtra = (document.extra[DeviceCacheOptions.personalTranslatorKey] as? NSNumber)?.boolValue
        }
        request.audioIntelligenceSlot = DeviceCacheOptions.advAISlotValue(
            DeviceCacheOptions.audioIntelligenceKey, in: document, using: layout)
        request.personalTranslatorSlot = DeviceCacheOptions.advAISlotValue(
            DeviceCacheOptions.personalTranslatorKey, in: document, using: layout)
        request.audioIntelligenceSlotIndex = audioIndex
        request.personalTranslatorSlotIndex = translatorIndex
        request.liveAIEnabled = liveAIEnabled
        request.userConfirmedUnverifiedCombination = userConfirmedUnverifiedCombination
        return AIStagingGuard.decide(request)
    }

    /// The guard decision for the combination currently staged in the
    /// preview, or `nil` when the slots are unobservable (see
    /// `stagingDecision(for:layout:...)`). The checkup surfaces a
    /// `.block`/`.warn` decision in its eSIM/conflict factor with the
    /// decision's specific reason.
    var aiStagingDecision: AIStagingDecision? {
        guard let preview,
              let layout = try? MobileGestaltCacheLayout.resolve(in: preview) else { return nil }
        return Self.stagingDecision(for: preview, layout: layout, liveAIEnabled: liveAIEnabled,
                                    userConfirmedUnverifiedCombination: userConfirmedUnverifiedAICombination,
                                    proposedUnlock: false)
    }

    /// The guard decision for the China Unlock proposal (all six AI keys
    /// staged as 1), evaluated on the current preview, or `nil` when the
    /// slots are unobservable. Fix evaluates this before staging: it
    /// answers whether the combination Fix is about to stage is blocked,
    /// warned, or allowed.
    var proposedUnlockStagingDecision: AIStagingDecision? {
        guard let preview,
              let layout = try? MobileGestaltCacheLayout.resolve(in: preview) else { return nil }
        return Self.stagingDecision(for: preview, layout: layout, liveAIEnabled: liveAIEnabled,
                                    userConfirmedUnverifiedCombination: userConfirmedUnverifiedAICombination,
                                    proposedUnlock: true)
    }

    /// The 4-factor readiness checkup for the staged preview, or `nil`
    /// when no document is loaded.
    var aiReadinessCheckup: AIReadinessCheckup? {
        guard let preview, let snapshot else { return nil }
        let productType = preview.extra[GestaltKeys.productType] as? String
            ?? snapshot.document.extra[GestaltKeys.productType] as? String ?? ""
        return AIReadinessCheckup.evaluate(
            regionCode: preview.extra[GestaltKeys.regionCode] as? String,
            regModel: preview.extra[GestaltKeys.modelNumber] as? String,
            esimEnabled: isESIMUnlockedInPreview,
            conflicts: aiConflicts,
            aiEnabledCount: chinaUnlockAIEnabledCount,
            aiTotal: ChinaUnlock.aiCapabilities.count,
            productType: productType,
            liveRegionCode: liveRegionCode,
            liveRegModel: liveRegModel,
            liveAIEnabled: liveAIEnabled,
            stagingDecision: aiStagingDecision)
    }

    /// Stages slot-only repairs for the detected AI conflicts: each slot
    /// is set to its native baseline through the normal staging path, so
    /// the repair still goes through review + backup + readback. A
    /// CacheExtra key that was explicitly disabled is restored to its
    /// recorded original. Returns true when anything was staged.
    @discardableResult
    func repairAIConflicts() -> Bool {
        guard !isBusy, var document = working, let snapshot,
              let productType = document.extra[GestaltKeys.productType] as? String else { return false }
        var staged = false
        for conflict in aiConflicts {
            switch conflict {
            case .personalTranslatorSlotDisabled:
                if let baseline = DeviceAIEligibility.nativeAdvAISlotValue(
                       key: DeviceCacheOptions.personalTranslatorKey, productType: productType),
                   let current = DeviceCacheOptions.advAISlotValue(
                       DeviceCacheOptions.personalTranslatorKey, in: document),
                   current != baseline {
                    do {
                        try document.setAdvAISlot(DeviceCacheOptions.personalTranslatorKey, value: baseline)
                        staged = true
                    } catch { /* Layout changed under us; leave it unstaged. */ }
                }
            case .personalTranslatorKeyDisabled:
                if (document.extra[DeviceCacheOptions.personalTranslatorKey] as? NSNumber)?.intValue == 0 {
                    document.set(snapshot.originalValue(for: DeviceCacheOptions.personalTranslatorKey),
                                 for: DeviceCacheOptions.personalTranslatorKey)
                    staged = true
                }
            case .audioIntelligenceEnabled:
                if let baseline = DeviceAIEligibility.nativeAdvAISlotValue(
                       key: DeviceCacheOptions.audioIntelligenceKey, productType: productType),
                   let current = DeviceCacheOptions.advAISlotValue(
                       DeviceCacheOptions.audioIntelligenceKey, in: document),
                   current != baseline {
                    do {
                        try document.setAdvAISlot(DeviceCacheOptions.audioIntelligenceKey, value: baseline)
                        staged = true
                    } catch { /* Layout changed under us; leave it unstaged. */ }
                }
            }
        }
        if staged { working = document }
        return staged
    }

    /// One-tap fix for the AI readiness checkup: repairs any slot
    /// conflicts first, then evaluates the staging guard on the China
    /// Unlock proposal before staging it. A `.block` decision holds the
    /// staging — the reason is shown, while a repair staged above stays
    /// staged for review. A `.warn` decision proceeds: tapping Fix on
    /// the checkup card, after the reason was shown there, is the
    /// explicit confirmation, and it is recorded so the checkup stops
    /// reporting the warned combination as not ready. Never writes
    /// directly; the caller opens the existing review sheet (same as the
    /// unlock card's path).
    @discardableResult
    func fixAIReadiness() -> Bool {
        var didSomething = false
        if repairAIConflicts() { didSomething = true }
        // Re-evaluate on the (possibly repaired) preview: a slot repaired
        // to its native baseline no longer blocks staging.
        if let decision = proposedUnlockStagingDecision {
            if decision.requiresSlotRepair {
                message = decision.reason
                log(decision.reason)
                return didSomething
            }
            if decision.requiresExplicitConfirmation {
                userConfirmedUnverifiedAICombination = true
                didSomething = true
            }
        }
        if !isChinaUnlockedInPreview, stageChinaUnlock() { didSomething = true }
        return didSomething
    }

    /// The reason the cache layout cannot be resolved on this device, if
    /// any. `nil` means the runtime scan matched this document. This is
    /// the UI lock state for the eSIM/WAPI switches: when it is non-nil
    /// the switches stay locked and the reason is shown. Presentation
    /// only; the stage-time throw remains the enforcement point.
    var cacheLayoutError: String? {
        guard let working else { return L("Read MobileGestalt first.") }
        do {
            _ = try MobileGestaltCacheLayout.resolve(in: working)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// The reason the eSIM cache layout cannot be verified, if any.
    /// `nil` means the layout resolves and the eSIM flags can be read,
    /// so the full group may be staged. Read-only: it never writes.
    var chinaUnlockESIMLayoutError: String? {
        guard let working else { return L("Read MobileGestalt first.") }
        do {
            _ = try DeviceCacheOptions.flags(in: working)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Stages the full China Unlock: eSIM cache flags, region code US and
    /// the six Apple Intelligence presets — exactly the 9 items, in either
    /// region mode. Nothing is written here; the user still reviews the
    /// changes and applies them, and a restart is required before they
    /// take effect. The sales-region suffix, the regulatory model number,
    /// `siriOnDevice` and WAPI are never staged: a regulatory model that
    /// does not match the hardware makes the system discard the whole
    /// MobileGestalt cache at boot and rebuild it from factory data, so
    /// the region change does not stick.
    ///
    /// This is an explicit user action, so it is deliberately not gated
    /// by the AI staging guard (see `AIStagingGuard`): it stages
    /// CacheExtra keys only and never writes a CacheData slot, so a
    /// pre-existing slot conflict is surfaced by the checkup with a
    /// repair path instead of disabling the unlock. The guard is enforced
    /// on the checkup card's Fix path (`fixAIReadiness`).
    ///
    /// If the eSIM cache layout cannot be verified, the whole group is
    /// stopped and the reason is shown (`message`); region code and AI
    /// are NOT staged as a fallback. They remain settable through their
    /// individual preset entries.
    @discardableResult
    func stageChinaUnlock() -> Bool {
        guard !isBusy else { return false }
        if let reason = chinaUnlockESIMLayoutError {
            message = reason
            log(reason)
            return false
        }
        guard stageCacheOption(.enable) else { return false }
        regionCodeID = ChinaUnlock.regionCodeID
        regionID = "keep"
        for id in ChinaUnlock.aiCapabilityIDs { choices[id] = .enable }
        return true
    }

    /// Stages a restore of the full China Unlock: eSIM flags back to the
    /// recorded originals, region code back to its recorded original and
    /// the six AI presets back to their recorded originals (`.disable`
    /// removes keys that were originally absent). `siriOnDevice` and WAPI
    /// are left untouched. The sales-region suffixes and the model number
    /// are also restored when the stored mode is Full US, so an unlock
    /// applied by an older build can still be reverted.
    @discardableResult
    func restoreChinaUnlock() -> Bool {
        guard stageCacheOption(.restoreOriginal) else { return false }
        regionCodeID = "keep"
        regionID = "keep"
        if let snapshot, var document = working {
            // The region overlay is preview-only, so stopping the overlay
            // alone would leave a previously applied `LL` in `working`.
            // Reset the working document itself to the recorded original.
            document.set(snapshot.originalValue(for: GestaltKeys.regionCode), for: GestaltKeys.regionCode)
            if chinaUnlockRegionMode == .fullUS {
                // Full-US staging also writes the sales-region suffixes
                // and the regulatory model number; restore those too.
                document.set(snapshot.originalValue(for: GestaltKeys.regionInfo), for: GestaltKeys.regionInfo)
                document.set(snapshot.originalValue(for: GestaltKeys.legacyRegionInfo), for: GestaltKeys.legacyRegionInfo)
                document.set(snapshot.originalValue(for: GestaltKeys.modelNumber), for: GestaltKeys.modelNumber)
            }
            working = document
        }
        for id in ChinaUnlock.aiCapabilityIDs { choices[id] = .disable }
        return true
    }

    /// Stages only the six Apple Intelligence presets — the AI part of the
    /// one-tap unlock, without eSIM or region. Deliberately not gated by
    /// the eSIM cache layout (see `chinaUnlockESIMLayoutError`): the AI
    /// keys are CacheExtra values and do not need the layout. Like the
    /// one-tap, this is an explicit user action, so it is not gated by
    /// the AI staging guard; the checkup surfaces any slot conflict with
    /// a repair path.
    @discardableResult
    func stageChinaAIOnly() -> Bool {
        guard !isBusy else { return false }
        for id in ChinaUnlock.aiCapabilityIDs { choices[id] = .enable }
        return true
    }

    /// Stages a restore of the AI-only preset: the six AI presets back to
    /// their recorded originals (`.disable` removes keys that were
    /// originally absent). eSIM and region are left untouched.
    @discardableResult
    func restoreChinaAIOnly() -> Bool {
        guard !isBusy else { return false }
        for id in ChinaUnlock.aiCapabilityIDs { choices[id] = .disable }
        return true
    }

    /// Stages only the eSIM cache flags and the region code US (LL) — the
    /// eSIM+region part of the one-tap unlock, without the six AI presets.
    /// Guarded by the eSIM cache layout exactly like `stageChinaUnlock`:
    /// if the layout cannot be verified, the preset is stopped and the
    /// reason is shown (`message`).
    @discardableResult
    func stageChinaESIMRegion() -> Bool {
        guard !isBusy else { return false }
        if let reason = chinaUnlockESIMLayoutError {
            message = reason
            log(reason)
            return false
        }
        guard stageCacheOption(.enable) else { return false }
        regionCodeID = ChinaUnlock.regionCodeID
        regionID = "keep"
        return true
    }

    /// Stages a restore of the eSIM+region preset: eSIM flags back to the
    /// recorded originals and region code back to its recorded original.
    /// The six AI presets are left untouched.
    @discardableResult
    func restoreChinaESIMRegion() -> Bool {
        guard stageCacheOption(.restoreOriginal) else { return false }
        regionCodeID = "keep"
        regionID = "keep"
        if let snapshot, var document = working {
            // The region overlay is preview-only, so stopping the overlay
            // alone would leave a previously applied `LL` in `working`.
            // Reset the working document itself to the recorded original.
            document.set(snapshot.originalValue(for: GestaltKeys.regionCode), for: GestaltKeys.regionCode)
            working = document
        }
        return true
    }

    @discardableResult
    func stageCacheOption(_ choice: CacheOptionChoice) -> Bool {
        guard !isBusy, var document = working, let snapshot else { return false }
        do {
            let flags: CachedOptionFlags
            switch choice {
            case .keep: flags = try DeviceCacheOptions.flags(in: snapshot.document)
            case .enable: flags = .enabled
            case .restoreOriginal: flags = try snapshot.originalCachedOptionFlags()
            }
            try document.setCacheOptions(flags)
            working = document
            cacheOptionChoice = choice
            return true
        } catch {
            failed(error)
            return false
        }
    }

    func stageWAPI(_ choice: WAPIChoice) {
        guard !isBusy, var document = working, let snapshot else { return }
        do {
            let value: Bool
            switch choice {
            case .keep: value = try DeviceCacheOptions.wapi(in: snapshot.document)
            case .disable: value = false
            case .restoreOriginal: value = try snapshot.originalWAPI()
            }
            try document.setWAPI(value)
            working = document
            wapiChoice = choice
        } catch { failed(error) }
    }

    var canRestoreCacheOption: Bool {
        guard !isBusy, let snapshot, let working,
              let original = try? snapshot.originalCachedOptionFlags(),
              let current = try? DeviceCacheOptions.flags(in: working) else { return false }
        return cacheOptionChoice != .keep || current != original
    }

    func restoreCacheOption() async {
        guard !isBusy, let before = snapshot, let pending = working else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            var restored = before.document
            try restored.setCacheOptions(before.originalCachedOptionFlags())
            let result: DocumentSnapshot
            if restored.matches(before.document) {
                result = before
            } else {
                logChanges(from: before.document, to: restored, prefix: "[restore-option] ")
                result = try await files.commit(restored, expected: before)
                needsRespring = result.source == .device
                message = L(result.source == .device
                            ? "Write verified. Some features require a device restart."
                            : "Local changes saved. Export the plist to keep a copy.")
            }
            snapshot = result
            working = before.rebasingPendingEdits(pending, onto: result.document, excluding: [], preservingCacheData: false)
            if let value = try? DeviceCacheOptions.wapi(in: pending),
               (try? DeviceCacheOptions.wapi(in: before.document)) != value { try working?.setWAPI(value) }
            cacheOptionChoice = .keep
            log("[restore-option] " + L("Original values restored."))
            await reloadBackups()
        } catch { failed(error); await reloadBackups() }
    }

    func canRestore(_ capability: Capability) -> Bool {
        guard !isBusy, let snapshot, let working else { return false }
        if (choices[capability.id] ?? .keep) != .keep { return true }
        if capability.id == "dynamicIsland" && subtype != 0 { return true }
        if capability.id == "dynamicIsland" {
            var restored = working
            capability.restoreDynamicIslandLayout(in: &restored, from: snapshot)
            if !restored.matches(working) { return true }
        }
        if capability.id == ModelPreset.restoration.id && modelID != "keep" { return true }
        return capability.keys.contains { key in
            switch (snapshot.originalValue(for: key), working.extra[key]) {
            case (nil, nil): false
            case (let a?, let b?): !GestaltDocument.valuesEqual(a, b)
            default: true
            }
        }
    }

    func restoreCapability(_ capability: Capability) async {
        guard !isBusy, let before = snapshot, let pending = working else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            var restored = before.document
            let removesAdded = choices[capability.id] == .removeAdded
            let absentKeys = removesAdded ? Set(capability.keys) : Set<String>()
            capability.apply(removesAdded ? .removeAdded : .disable, to: &restored, restoringFrom: before)
            let result: DocumentSnapshot
            if restored.matches(before.document) && absentKeys.isEmpty {
                result = before
            } else {
                for line in diffLines(before.document.extra, restored.extra) { log("[restore-field] " + line) }
                result = try await files.commit(restored, expected: before, originallyAbsentKeys: absentKeys)
                needsRespring = result.source == .device
                message = L(result.source == .device ? "Original values restored." : "Local changes saved. Export the plist to keep a copy.")
            }
            snapshot = result
            var rebased = before.rebasingPendingEdits(pending, onto: result.document, excluding: Set(capability.keys))
            capability.restoreDynamicIslandLayout(in: &rebased, from: before)
            working = rebased
            choices[capability.id] = .keep
            if capability.id == "dynamicIsland" { subtype = 0 }
            if capability.id == ModelPreset.restoration.id { modelID = "keep" }
            log("[restore-field] " + L(capability.title) + ": " + L("Original values restored."))
            await reloadBackups()
        } catch { failed(error); await reloadBackups() }
    }
    func clearLog() { logs = [] }

    // MARK: - Exploit-process logging

    private func describe(_ value: Any?) -> String {
        guard let value else { return "∅" }
        if let data = value as? Data { return "\(data.count) bytes" }
        let text = PlistValueKind.detect(value).text(for: value)
        return text.count > 80 ? String(text.prefix(80)) + "…" : text
    }

    private func diffLines(_ before: [String: Any], _ after: [String: Any], prefix: String = "") -> [String] {
        var lines: [String] = []
        for key in Set(before.keys).union(after.keys).sorted() {
            let path = prefix.isEmpty ? key : prefix + "." + key
            switch (before[key], after[key]) {
            case (nil, let value?): lines.append("+ \(path) = \(describe(value))")
            case (let value?, nil): lines.append("- \(path)  (was \(describe(value)))")
            case (let oldValue?, let newValue?):
                guard !GestaltDocument.valuesEqual(oldValue, newValue) else { continue }
                if let oldDict = oldValue as? [String: Any], let newDict = newValue as? [String: Any] {
                    lines.append(contentsOf: diffLines(oldDict, newDict, prefix: path))
                } else {
                    lines.append("~ \(path): \(describe(oldValue)) → \(describe(newValue))")
                }
            default: break
            }
        }
        return lines
    }

    private func summarize(_ document: GestaltDocument) -> [String] {
        var lines = ["CacheExtra: \(document.extra.count) keys"]
        if let cacheData = document.root["CacheData"] as? Data { lines.append("CacheData: \(cacheData.count) bytes") }
        do {
            let layout = try MobileGestaltCacheLayout.resolve(in: document)
            let source = MobileGestaltCacheLayout.runtimeLayout().map { $0 == layout } == true ? "runtime scan" : "offline profile"
            lines.append("Cache layout: \(layout.uuid), \(layout.slotCount) slots (\(source))")
            lines.append(String(format: "green-tea: index %d, offset 0x%X; not-green-tea: index %d, offset 0x%X",
                                layout.greenTeaIndex, layout.greenTeaOffset, layout.notGreenTeaIndex, layout.notGreenTeaOffset))
        } catch { lines.append("Cache offsets: " + error.localizedDescription) }
        if let model = document.artwork["ArtworkDeviceProductDescription"] as? String { lines.append("model name: \(model)") }
        if let subtype = document.artwork["ArtworkDeviceSubType"] { lines.append("subtype: \(describe(subtype))") }
        if let region = document.extra[GestaltKeys.regionCode] as? String { lines.append("region code: \(region)") }
        for key in [GestaltKeys.regionInfo, GestaltKeys.legacyRegionInfo] {
            if let info = document.extra[key] as? String { lines.append("region info: \(info)") }
        }
        if let product = document.extra[GestaltKeys.productType] as? String { lines.append("product type: \(product)") }
        return lines
    }

    private func logChanges(from original: GestaltDocument, to edited: GestaltDocument, prefix: String) {
        for line in diffLines(original.root, edited.root) { log(prefix + line) }
        for change in DeviceCacheOptions.changes(from: original, to: edited) {
            log(prefix + "CacheData.\(change.name) @\(String(format: "0x%X", change.offset)): \(change.before) → \(change.after)")
        }
    }

    func connect(showErrorAlert: Bool = true) async {
        guard !isBusy else { return }
        isBusy = true; isReading = true; status = "Checking device access…"
        log("[read] Starting MobileGestalt access")
        defer { isBusy = false; isReading = false }
        do {
            let result = try await files.loadDevice()
            accept(result); deviceAccessible = true; status = "Device connected"
            log("[read] plist: \(result.data.count) bytes")
            for line in summarize(result.document) { log("[read] " + line) }
            log(L("Device connected"))
        } catch {
            deviceAccessible = false; status = "Device access unavailable"
            if showErrorAlert { failed(error) } else { log(error.localizedDescription) }
        }
        await reloadBackups()
    }

    #if targetEnvironment(simulator)
    func open(_ url: URL) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? 0) <= 16 * 1024 * 1024 else { throw GestaltFailure("Choose a plist smaller than 16 MB.") }
            let result = try await files.loadLocal(data: Data(contentsOf: url), name: url.lastPathComponent)
            accept(result); status = "Local file opened"; needsRespring = false
            log("[open] \(url.lastPathComponent): \(result.data.count) bytes")
            for line in summarize(result.document) { log("[open] " + line) }
            log(L("Local file opened") + ": " + url.lastPathComponent)
        } catch { failed(error) }
    }

    #endif

    private func verifyImport(_ bytes: Data) async throws -> (Data, DevicePlistIdentity?) {
        if let payload = try DeviceBoundPlist.verifiedPayload(bytes) { return (payload, nil) }
        let incoming = try DevicePlistIdentity(plist: bytes)
        guard incoming.values.count >= 2 else { throw DevicePlistIdentity.incomplete }
        let empty = try DevicePlistIdentity(properties: [:])
        var trusted = (try? DevicePlistIdentity(properties: GXCopyCurrentDeviceIdentity())) ?? empty
        if trusted.values.count >= 2 {
            do { try incoming.requireMatch(with: trusted); return (bytes, trusted) }
            catch let error as SharedPlistError where error.key == DevicePlistIdentity.mismatch.key { throw error }
            catch { /* The cache may provide an additional identifier. */ }
        }
        // Only a fresh read from the actual device path is a trusted fallback.
        // Previously imported documents and user-provided backups are never used.
        do {
            let live = try await files.loadDevice()
            trusted = try trusted.mergingTrusted(DevicePlistIdentity(properties: live.document.extra))
        } catch { throw DevicePlistIdentity.unavailable }
        try incoming.requireMatch(with: trusted)
        return (bytes, trusted)
    }

    func prepareSharedPlist(_ entry: SharedPlistEntry, from inbox: SharedPlistInbox) async -> SharedImportPreparation<PlistImportOffer> {
        guard !isBusy, changeCount == 0 else { return .deferred(nil) }
        isBusy = true
        defer { isBusy = false }
        do {
            let bytes = try await inbox.readAsync(entry)
            let (payload, identity) = try await verifyImport(bytes)
            try Task.checkCancellation()
            log("[share] Device ownership verified; waiting for import confirmation")
            return .ready(PlistImportOffer(data: payload, name: entry.name, identity: identity, sharedSource: (inbox, entry)))
        } catch is CancellationError {
            return .deferred(nil)
        } catch {
            // Retry only known access/service failures, not invalid content.
            log("[share] " + error.localizedDescription)
            if !inbox.reject(entry, after: error) {
                return .deferred(error.localizedDescription)
            }
            return .rejected(error.localizedDescription)
        }
    }

    func prepareFileImport(_ url: URL) async -> PlistImportOffer? {
        guard !isBusy, changeCount == 0 else { return nil }
        isBusy = true
        defer { isBusy = false }
        do {
            let bytes = try await SharedPlistInbox.readDocumentAsync(at: url)
            let (payload, identity) = try await verifyImport(bytes)
            try Task.checkCancellation()
            return PlistImportOffer(data: payload, name: url.lastPathComponent, identity: identity, sharedSource: nil)
        } catch is CancellationError { return nil }
        catch { failed(error); return nil }
    }

    func acceptImport(_ offer: PlistImportOffer) async {
        guard !isBusy, changeCount == 0 else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            // Use the immutable bytes that were verified for this confirmation.
            if let identity = offer.identity { try DevicePlistIdentity(plist: offer.data).requireMatch(with: identity) }
            var loaded = try await files.loadLocal(data: offer.data, name: offer.name)
            loaded.ownershipVerified = true
            accept(loaded); status = "Local file opened"; needsRespring = false
            discardImport(offer)
            log("[share] Verified device plist imported: \(offer.data.count) bytes")
        } catch { failed(error) }
    }

    var canRestoreImportedPlist: Bool {
        snapshot?.source == .local && snapshot?.ownershipVerified == true && changeCount == 0 && !isBusy
    }
    func restoreImportedPlist() async {
        guard canRestoreImportedPlist, let imported = snapshot else { return }
        isBusy = true; defer { isBusy = false }
        do {
            let live = try await files.loadDevice()
            let restored = try await files.restoreVerifiedImport(imported, expected: live)
            let changed = !restored.document.matches(live.document)
            accept(restored); needsRespring = needsRespring || changed
            status = "Changes verified on device"
            message = changed ? L("Backup restored and verified.") + " " + L("Some changes require a device restart.")
                : L("This backup already matches the device. No changes were made.")
            log("[restore] Verified imported document restored")
            await reloadBackups()
        } catch { failed(error); await reloadBackups() }
    }

    func discardImport(_ offer: PlistImportOffer) {
        if let (inbox, entry) = offer.sharedSource {
            do { try inbox.acknowledge(entry) }
            catch { log("[share] Inbox cleanup failed") }
        }
    }

    func stage(_ draft: FieldDraft) throws {
        let key = draft.key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw GestaltFailure("Enter a field key.") }
        guard var doc = working else { throw GestaltFailure("Load a document first.") }
        if draft.originalKey != key && doc.extra[key] != nil { throw GestaltFailure("That key already exists. Edit the existing field instead.") }
        let value = try draft.parsedValue()
        if let originalKey = draft.originalKey, originalKey != key { doc.set(nil, for: originalKey) }
        doc.set(value, for: key); working = doc
        // Explicit field edits take precedence: discard presets that would overwrite the key.
        let changedKeys = Set([key, draft.originalKey].compactMap { $0 })
        for capability in Capability.all where !changedKeys.isDisjoint(with: capability.keys) { choices[capability.id] = .keep }
        if !changedKeys.isDisjoint(with: [GestaltKeys.regionCode, GestaltKeys.regionInfo, GestaltKeys.legacyRegionInfo]) { regionID = "keep"; regionCodeID = "keep" }
        if changedKeys.contains(GestaltKeys.artwork) { subtype = 0 }
        if changedKeys.contains(GestaltKeys.modelNumber) { modelID = "keep" }
        if !changedKeys.isDisjoint(with: [GestaltKeys.artwork, "Z/dqyWS6OZTRy10UcmUAhw", "bbtR9jQx50Fv5Af/affNtA"]) { changesName = false }
    }
    func removeField(_ key: String) {
        working?.set(nil, for: key)
        for capability in Capability.all where capability.keys.contains(key) { choices[capability.id] = .keep }
        if [GestaltKeys.regionCode, GestaltKeys.regionInfo, GestaltKeys.legacyRegionInfo].contains(key) { regionID = "keep"; regionCodeID = "keep" }
        if key == GestaltKeys.artwork { subtype = 0 }
        if key == GestaltKeys.modelNumber { modelID = "keep" }
        if [GestaltKeys.artwork, "Z/dqyWS6OZTRy10UcmUAhw", "bbtR9jQx50Fv5Af/affNtA"].contains(key) { changesName = false }
    }

    func apply() async {
        guard !isBusy, let snapshot, let edited = preview else { return }
        if (changesName || subtype != 0), let error = artworkEditingError { failed(error); return }
        guard changeCount > 0 else { return }
        if changesName && modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { failed(GestaltFailure("Enter a model name before applying.")); return }
        isBusy = true
        defer { isBusy = false }
        do {
            log("[apply] source=\(snapshot.source.rawValue) fields=\(changeCount)")
            logChanges(from: snapshot.document, to: edited, prefix: "[diff] ")
            let absentKeys = Set(Capability.all.filter { choices[$0.id] == .removeAdded }.flatMap(\.keys))
            let result = try await files.commit(edited, expected: snapshot, originallyAbsentKeys: absentKeys)
            accept(result); needsRespring = result.source == .device
            status = result.source == .device ? "Changes verified on device" : "Local changes saved"
            let changedCacheOption = !DeviceCacheOptions.changes(from: snapshot.document, to: edited).isEmpty
            message = L(result.source == .device
                        ? (changedCacheOption ? "Write verified. Some features require a device restart." : "Write verified. Some features require a device restart.")
                        : "Local changes saved. Export the plist to keep a copy.")
            log(L(status)); await reloadBackups()
        } catch { failed(error); await reloadBackups() }
    }

    func backup() async {
        guard !isBusy, let snapshot else { return }
        isBusy = true; defer { isBusy = false }
        do { try await files.backup(snapshot); log(L("Backup saved")); message = L("Backup saved"); await reloadBackups() }
        catch { failed(error) }
    }
    func reloadBackups() async {
        do { backups = try await files.backups() } catch { failed(error) }
    }
    func restore(_ record: BackupRecord) async {
        guard !isBusy, let snapshot else { return }
        guard changeCount == 0 else {
            message = L("Save or discard your current changes before opening another plist.")
            return
        }
        isBusy = true; defer { isBusy = false }
        do {
            let data = try await files.backupData(record)
            let restored = try GestaltDocument(data: data)
            log("[restore] \(record.filename) · \(record.byteCount) bytes · reason=\(record.reason)")
            logChanges(from: snapshot.document, to: restored, prefix: "[restore-diff] ")
            let result = try await files.commit(restored, expected: snapshot, restoring: record)
            let changed = !result.document.matches(snapshot.document)
            accept(result); needsRespring = result.source == .device && (needsRespring || changed)
            message = L(result.source == .device
                        ? (changed ? "Backup restored and verified." : "This backup already matches the device. No changes were made.")
                        : "Backup opened as a local document.")
            log(message ?? ""); await reloadBackups()
        } catch { failed(error); await reloadBackups() }
    }
    func openBackup(_ record: BackupRecord) async {
        guard !isBusy else { return }
        guard changeCount == 0 else {
            message = L("Save or discard your current changes before opening another plist.")
            return
        }
        isBusy = true; defer { isBusy = false }
        do {
            let data = try await files.backupData(record)
            accept(try await files.loadLocal(data: data, name: record.filename, provenance: record.provenance)); status = "Local file opened"
        } catch { failed(error) }
    }
    func deleteBackup(_ record: BackupRecord) async {
        guard !isBusy else { return }
        isBusy = true; defer { isBusy = false }
        do { try await files.deleteBackup(record); await reloadBackups() } catch { failed(error) }
    }
    func exportBackup(_ record: BackupRecord) async -> TemporaryExport? {
        do {
            let data = try await files.backupExportData(record, sealingWith: { try DeviceBoundPlist.seal($0) })
            return try exportData(data, name: record.filename)
        }
        catch { failed(error); return nil }
    }
    func exportDocument() -> TemporaryExport? {
        guard let doc = preview, let snapshot else { return nil }
        do {
            let plain = try doc.encoded()
            let bytes = snapshot.source == .device || snapshot.ownershipVerified ? try DeviceBoundPlist.seal(plain) : plain
            return try exportData(bytes, name: "MobileGestalt-LilaShift.plist")
        }
        catch { failed(error); return nil }
    }
    private func exportData(_ data: Data, name: String) throws -> TemporaryExport {
        try TemporaryExport(data: data, name: name)
    }
}
