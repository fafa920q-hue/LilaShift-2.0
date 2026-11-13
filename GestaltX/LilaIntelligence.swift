// SPDX-License-Identifier: GPL-3.0-only
// Lila Intelligence (紫序智能引擎) — device capability identification
// and per-device recommendations. Pure Foundation — no SwiftUI, no
// UIKit, no singletons, no global mutable state.
//
// The engine reads REAL device data only: product type, OS version and
// build, system region and sales region, MobileGestalt read status,
// CacheUUID and cache layout, eSIM capabilities, native Apple
// Intelligence status, actual App Group permissions, backup
// availability, and whether the device can perform supported
// operations. Anything inaccessible is `.unknown(reason:)`, never
// fabricated. The engine stages nothing and writes nothing: it only
// evaluates and recommends. A recommendation is data for review; the
// existing GestaltManager paths own staging, backup, apply and
// readback.
//
// Initially a LOCAL RULE ENGINE — no paid AI API. Support scope is
// recorded per model and system build, never as "all iOS 27
// compatible": there is no verified OS-build compatibility table in
// the tree, so OS-build compatibility is always `.unknown` with a
// reason.
import Foundation

// MARK: - Profiler sources (injectable; tests supply fakes)

/// Live MobileGestalt answers (MGCopyAnswer). `nil` means the probe
/// could not answer for that key — the caller reports unknown, never a
/// guessed value.
protocol LiveAnswersSource: Sendable {
    func boolAnswer(for key: String) -> Bool?
    func stringAnswer(for key: String) -> String?
}

/// The production live source: a thin wrapper over `LiveGestaltProbe`.
struct LiveGestaltProbeSource: LiveAnswersSource {
    func boolAnswer(for key: String) -> Bool? { LiveGestaltProbe.queryBool(key) }
    func stringAnswer(for key: String) -> String? { LiveGestaltProbe.queryString(key) }
}

/// Stored backups, as the profiler needs them: how many exist, and
/// whether any has trusted provenance. The production wiring reads
/// `GestaltManager.backups` and passes the records in; a throwing or
/// unavailable store yields no records here, and the caller must not
/// present that as "no backups exist" — it presents the count it was
/// actually given.
protocol BackupInventorySource: Sendable {
    var records: [BackupRecord] { get }
}

/// No backup inventory is available (for example before any store is
/// wired up). Reports zero backups and no trusted backup.
struct EmptyBackupInventorySource: BackupInventorySource {
    var records: [BackupRecord] { [] }
}

/// App Group / share-extension state. `nil` means the state could not
/// be determined — the profiler then reports unknown, never a guessed
/// boolean.
protocol SigningStateSource: Sendable {
    var appGroupAvailable: Bool? { get }
    var shareExtensionPresent: Bool? { get }
}

/// The production signing source: the usable App Groups come from the
/// signed entitlements, and the share extension is found by its bundle
/// identifier in the main bundle's PlugIns directory. A missing appex
/// is definitively absent; an appex whose Info.plist cannot be read
/// is unknown, not absent.
struct SystemSigningStateSource: SigningStateSource {
    var appGroupAvailable: Bool? {
        GXEntitlementsReader.usableAppGroups().contains(GestaltKeys.group)
    }

    var shareExtensionPresent: Bool? {
        let appexURL = Bundle.main.bundleURL
            .appendingPathComponent("PlugIns/GestaltXShare.appex")
        guard FileManager.default.fileExists(atPath: appexURL.path) else { return false }
        guard let plist = NSDictionary(contentsOf: appexURL.appendingPathComponent("Info.plist")),
              let identifier = plist["CFBundleIdentifier"] as? String else { return nil }
        return identifier == "com.huami.gestultx.ShareExtension"
    }
}

// MARK: - DeviceProfiler

/// Assembles a `DeviceProfile` from injectable inputs. A struct, not a
/// singleton: callers construct it with the sources they can provide
/// and pass a document (or `nil` when none has been read).
struct DeviceProfiler {
    private let identity: any DeviceIdentitySource
    private let live: any LiveAnswersSource
    private let backups: any BackupInventorySource
    private let signing: any SigningStateSource
    /// Number of persisted change records. 0 until a record store
    /// exists; the profiler never invents a count.
    private let changeRecordCount: Int

    init(identity: any DeviceIdentitySource = SystemDeviceIdentitySource(),
         live: any LiveAnswersSource = LiveGestaltProbeSource(),
         backups: any BackupInventorySource = EmptyBackupInventorySource(),
         signing: any SigningStateSource = SystemSigningStateSource(),
         changeRecordCount: Int = 0) {
        self.identity = identity
        self.live = live
        self.backups = backups
        self.signing = signing
        self.changeRecordCount = changeRecordCount
    }

    /// Builds the profile for `document`, or for "no document" when
    /// `document` is `nil`. `documentByteCount` is the byte count of the
    /// data the document was read from (for example
    /// `snapshot.data.count`); it is reported in `cacheReadState`.
    func profile(document: GestaltDocument?, documentByteCount: Int) -> DeviceProfile {
        let noDocument = L("No document has been read.")
        let noIdentity = L("Device identity is unavailable.")
        let notPresent = L("Not present")
        let liveUnknown = L("Live status unknown")
        let signingUnknown = L("Signing state could not be read.")

        let productType = identity.productType
        let profileProductType: ProfileValue<String> = productType.map { .known($0) }
            ?? .unknown(reason: noIdentity)
        let osVersion: ProfileValue<String> = identity.osVersion.map { .known($0) }
            ?? .unknown(reason: noIdentity)
        let osBuild: ProfileValue<String> = identity.osBuild.map { .known($0) }
            ?? .unknown(reason: noIdentity)

        func stringField(_ key: String) -> ProfileValue<String> {
            guard let document else { return .unknown(reason: noDocument) }
            guard let value = document.extra[key] as? String else {
                return .unknown(reason: notPresent)
            }
            return .known(value)
        }

        let modelNumber = stringField(GestaltKeys.modelNumber)
        let regionCode = stringField(GestaltKeys.regionCode)
        // Sales-region suffix: modern `regionInfo` first, legacy
        // `legacyRegionInfo` as fallback — GestaltManager reads both
        // the same way, and the iOS-27 guard never creates regionInfo
        // when it is absent, so the legacy key is still the source on
        // older layouts.
        let salesRegionSuffix: ProfileValue<String> = {
            guard let document else { return .unknown(reason: noDocument) }
            for key in [GestaltKeys.regionInfo, GestaltKeys.legacyRegionInfo] {
                if let value = document.extra[key] as? String { return .known(value) }
            }
            return .unknown(reason: notPresent)
        }()

        // Exact-match native-AI list; an unknown product type is
        // unknown, never assumed native or non-native.
        let isNativeAppleIntelligence: ProfileValue<Bool>
        if let productType {
            isNativeAppleIntelligence = .known(
                DeviceAIEligibility.isNativeAppleIntelligence(productType: productType))
        } else {
            isNativeAppleIntelligence = .unknown(reason: noIdentity)
        }

        // Fail-closed model gate: the recorded model number is the
        // original regulatory model, the identity product type is the
        // fallback. An unknown product type (for example the simulator)
        // yields an unknown decision with a reason.
        let modelDecision = DeviceModelSupport.decision(
            for: productType ?? "",
            originalRegModel: modelNumber.value)

        let cacheLayout: ProfileValue<MobileGestaltCacheLayout>
        let cacheReadState: CacheReadState
        if let document {
            do {
                cacheLayout = .known(try MobileGestaltCacheLayout.resolve(in: document))
            } catch {
                // The lock reason: why the layout cannot be resolved,
                // shown instead of any borrowed layout.
                cacheLayout = .unknown(reason: error.localizedDescription)
            }
            if let uuid = document.root["CacheUUID"] as? String {
                cacheReadState = .read(cacheUUID: uuid, byteCount: documentByteCount)
            } else {
                cacheReadState = .failed(reason: notPresent)
            }
        } else {
            cacheLayout = .unknown(reason: noDocument)
            cacheReadState = .notRead
        }

        // Live answers, following the GestaltManager pattern: the region
        // code as a string, Apple Intelligence from the "ai"
        // capability's first key. `nil` from the probe is unknown.
        let liveAIEnabled: ProfileValue<Bool>
        if let aiKey = Capability.all.first(where: { $0.id == "ai" })?.keys.first,
           let answer = live.boolAnswer(for: aiKey) {
            liveAIEnabled = .known(answer)
        } else {
            liveAIEnabled = .unknown(reason: liveUnknown)
        }
        let liveRegionCode: ProfileValue<String>
        if let answer = live.stringAnswer(for: GestaltKeys.regionCode) {
            liveRegionCode = .known(answer)
        } else {
            liveRegionCode = .unknown(reason: liveUnknown)
        }

        let appGroupAvailable: ProfileValue<Bool> = signing.appGroupAvailable.map { .known($0) }
            ?? .unknown(reason: signingUnknown)
        let shareExtensionPresent: ProfileValue<Bool> = signing.shareExtensionPresent.map { .known($0) }
            ?? .unknown(reason: signingUnknown)

        let records = backups.records
        let hasTrustedBackup = records.contains {
            $0.provenance == .verifiedFactory || $0.provenance == .preModification
        }

        return DeviceProfile(
            productType: profileProductType,
            modelNumber: modelNumber,
            osVersion: osVersion,
            osBuild: osBuild,
            regionCode: regionCode,
            salesRegionSuffix: salesRegionSuffix,
            isNativeAppleIntelligence: isNativeAppleIntelligence,
            modelDecision: modelDecision,
            cacheLayout: cacheLayout,
            cacheReadState: cacheReadState,
            liveAIEnabled: liveAIEnabled,
            liveRegionCode: liveRegionCode,
            appGroupAvailable: appGroupAvailable,
            shareExtensionPresent: shareExtensionPresent,
            backupCount: records.count,
            hasTrustedBackup: hasTrustedBackup,
            changeRecordCount: changeRecordCount)
    }
}

// MARK: - FeatureEligibilityEvaluator

/// Pure evaluation of one feature on this device. Stages nothing and
/// changes no document; it only decides whether one feature may be
/// staged on this device, with the specific reason.
///
/// The `document` parameter is a `DocumentSnapshot`, not a bare
/// `GestaltDocument`: the snapshot carries the current document plus
/// the recorded originals and the provenance the trusted-original
/// rules need (Dynamic Island). A caller with only a document wraps
/// it in a snapshot; a snapshot with `.firstRead` provenance is never
/// treated as factory state.
///
/// Evaluation order (first matching rule wins):
/// 1. `siriOnDevice` is keep-only: always `.unknown`, never auto-staged.
/// 2. Unknown feature id: `.unknown`.
/// 3. `regionCode` is model-independent: never gated by the model.
/// 4. `esim` and `wapi` are model-independent too: their safety depends
///    on the resolved cache layout, not on a known model entry.
/// 5. Unknown model: `.unknown` with the model decision's reason for
///    every model-dependent feature.
/// 6. AI features: native proof, then the `AIStagingGuard`, then
///    already-configured, then eligible.
/// 7. Dynamic Island: trusted-original native proof, then
///    already-configured, then eligible.
/// 8. Every other capability: already-configured, then eligible.
///
/// Honesty rules: `.unknown` is read-only, never treated as eligible;
/// a device without eSIM hardware is never reported as "eSIM
/// successfully enabled" — eligibility means "flags can be staged",
/// and the eSIM reason says so. No string here makes a
/// universal-support, absolute-safety, or factory-restore claim.
enum FeatureEligibilityEvaluator {
    /// Virtual feature id for the eSIM green-tea / not-green-tea group.
    static let esimFeatureID = "esim"
    /// Virtual feature id for region staging (China Unlock stages LL).
    static let regionCodeFeatureID = "regionCode"
    /// Virtual feature id for WAPI disable (the only WAPI action the
    /// app supports): staging sets the CacheData WAPI slot to false.
    static let wapiFeatureID = "wapi"

    /// Every feature id this evaluator understands.
    static let knownFeatureIDs: [String] =
        Capability.all.map(\.id) + [esimFeatureID, regionCodeFeatureID, wapiFeatureID]

    /// `ArtworkDeviceSubType` values for Dynamic Island layouts, as
    /// offered by the app's own Dynamic Island picker. A factory
    /// artwork subtype in this set means the device shipped with
    /// Dynamic Island. Any other value proves nothing — never assume.
    static let dynamicIslandLayoutSubtypes: Set<Int> = [2556, 2796, 2736, 2622, 2868]

    /// Pure evaluation of one feature on this device. `liveAIEnabled`
    /// is the live probe answer when the caller has one; it falls back
    /// to `profile.liveAIEnabled`. `userConfirmedUnverifiedCombination`
    /// is set only after the user has read a warn reason and confirmed
    /// it explicitly; it never defaults to true.
    static func evaluate(
        featureID: String,
        profile: DeviceProfile,
        document: DocumentSnapshot?,
        layout: MobileGestaltCacheLayout?,
        liveAIEnabled: Bool?,
        userConfirmedUnverifiedCombination: Bool
    ) -> (eligibility: FeatureEligibility, reason: String) {
        // 1. siriOnDevice is keep-only: the unlock deliberately preserves
        // its device-specific value, so the evaluator never auto-stages
        // it — not even with an explicit confirmation.
        if featureID == "siriOnDevice" {
            let hint = Capability.all.first(where: { $0.id == featureID })?.effectHint
            return (.unknown, L(hint ?? "Restart required. Siri uses a device-specific capability type; changing it may affect the Apple Intelligence Siri interface. Keep the current value or restore the recorded original."))
        }

        // 2. Unknown feature id: unknown, never eligible.
        guard knownFeatureIDs.contains(featureID) else {
            return (.unknown, L("Unknown feature — eligibility cannot be determined."))
        }

        // 3. Region staging is model-independent (see
        // `DeviceModelSupport`): it is never gated by the model.
        if featureID == regionCodeFeatureID {
            return evaluateRegionCode(profile: profile, document: document)
        }

        // 4. eSIM is model-independent too: its safety depends on the
        // resolved layout and the CH region, not on a known model.
        if featureID == esimFeatureID {
            return evaluateESIM(profile: profile, document: document, layout: layout)
        }

        // 5. WAPI disable is model-independent for the same reason:
        // only the resolved layout's WAPI slot matters.
        if featureID == wapiFeatureID {
            return evaluateWAPI(profile: profile, document: document, layout: layout)
        }

        // 6. Unknown model: read-only for every model-dependent feature,
        // with the model decision's specific reason.
        if case .unknown(let modelReason) = profile.modelDecision {
            return (.unknown, modelReason)
        }

        // 7. AI features: native proof, then the staging guard.
        if ChinaUnlock.aiCapabilityIDs.contains(featureID) {
            return evaluateAI(featureID: featureID, profile: profile, document: document,
                              layout: layout, liveAIEnabled: liveAIEnabled,
                              userConfirmedUnverifiedCombination: userConfirmedUnverifiedCombination)
        }

        // 8-9. Dynamic Island and every other capability need the
        // current document to judge their state.
        guard let snapshot = document else {
            return (.unknown, L("No device document is available, so this feature cannot be judged."))
        }
        if featureID == "dynamicIsland" {
            return evaluateDynamicIsland(snapshot: snapshot)
        }
        guard let capability = Capability.all.first(where: { $0.id == featureID }) else {
            return (.unknown, L("Unknown feature — eligibility cannot be determined."))
        }
        if capability.isEnabled(in: snapshot.document) {
            return (.alreadyConfigured, L("Configured"))
        }
        return (.eligibleToEnable, L(capability.effectHint))
    }

    // MARK: - Region code (model-independent)

    private static func evaluateRegionCode(
        profile: DeviceProfile, document: DocumentSnapshot?
    ) -> (eligibility: FeatureEligibility, reason: String) {
        switch currentRegionCode(profile: profile, document: document) {
        case "LL":
            return (.alreadyConfigured, L("Configured"))
        case .some:
            return (.eligibleToEnable, L("Set the device region code for region-locked features."))
        case nil:
            return (.unknown, L("Region code is unknown."))
        }
    }

    // MARK: - eSIM

    private static func evaluateESIM(
        profile: DeviceProfile, document: DocumentSnapshot?,
        layout: MobileGestaltCacheLayout?
    ) -> (eligibility: FeatureEligibility, reason: String) {
        // Layout first: without resolved slots there is nothing to stage.
        let resolvedLayout = resolvedLayout(profile: profile, document: document, layout: layout)
        guard let resolvedLayout else {
            let lockReason = document.flatMap { MobileGestaltCacheLayout.lockReason(in: $0.document) }
                ?? L("Unable to resolve this device's MobileGestalt cache layout.")
            return (.unknown, lockReason)
        }
        // Region second: eSIM staging applies to China-market devices.
        let region = currentRegionCode(profile: profile, document: document)
        guard let region else {
            return (.unsupported, L("Region code is unknown, so this device cannot be confirmed as a China-market device."))
        }
        guard region == "CH" else {
            return (.unsupported, L("Not a China-market device."))
        }
        // Flags last: the document is needed to read them.
        guard let snapshot = document else {
            return (.unknown, L("No device document is available, so this feature cannot be judged."))
        }
        do {
            let flags = try DeviceCacheOptions.flags(in: snapshot.document, using: resolvedLayout)
            if flags == .enabled {
                return (.alreadyConfigured, L("Configured"))
            }
            // Eligibility means "flags can be staged" — never a claim
            // that eSIM hardware is present.
            return (.eligibleToEnable, L("Staging flips the eSIM cache flags only. It does not prove eSIM hardware is present."))
        } catch {
            return (.unknown, error.localizedDescription)
        }
    }

    // MARK: - WAPI

    /// WAPI disable: the only WAPI action is staging the CacheData
    /// slot to false. No WAPI slot in the resolved layout, or an
    /// unresolvable layout, is unknown — the device's WAPI state
    /// cannot be judged. Already disabled is already configured.
    private static func evaluateWAPI(
        profile: DeviceProfile, document: DocumentSnapshot?,
        layout: MobileGestaltCacheLayout?
    ) -> (eligibility: FeatureEligibility, reason: String) {
        let resolvedLayout = resolvedLayout(profile: profile, document: document, layout: layout)
        guard let resolvedLayout, resolvedLayout.wapiIndex != nil else {
            return (.unknown, L("The cache layout or values do not match this preset."))
        }
        guard let snapshot = document else {
            return (.unknown, L("No device document is available, so this feature cannot be judged."))
        }
        do {
            let enabled = try DeviceCacheOptions.wapi(in: snapshot.document, using: resolvedLayout)
            if !enabled {
                return (.alreadyConfigured, L("Configured"))
            }
            // Eligibility means "the flag can be staged" — never a
            // claim about network hardware.
            return (.eligibleToEnable, L("WAPI flag reads back as disabled — this verifies the staged flag, not network hardware."))
        } catch {
            return (.unknown, error.localizedDescription)
        }
    }

    // MARK: - AI features

    private static func evaluateAI(
        featureID: String, profile: DeviceProfile, document: DocumentSnapshot?,
        layout: MobileGestaltCacheLayout?, liveAIEnabled: Bool?,
        userConfirmedUnverifiedCombination: Bool
    ) -> (eligibility: FeatureEligibility, reason: String) {
        let productType = profile.productType.value ?? ""
        let isNativeHardware = profile.isNativeAppleIntelligence.value
            ?? (productType.isEmpty ? false : DeviceAIEligibility.isNativeAppleIntelligence(productType: productType))
        let liveOn = (liveAIEnabled ?? profile.liveAIEnabled.value) == true
        let resolvedLayout = resolvedLayout(profile: profile, document: document, layout: layout)

        // Native proof: native hardware, the live probe reports Apple
        // Intelligence on, and every resolvable native AdvAI slot
        // baseline agrees with the current slot value. All three must
        // hold — a live probe alone, or a slot baseline alone, never
        // proves the capability is natively present. A slot that does
        // not resolve is not agreement: it fails closed below, through
        // the guard.
        if isNativeHardware, liveOn,
           nativeSlotBaselinesAgree(productType: productType, document: document, layout: resolvedLayout) {
            return (.nativeSupported, L("Native Apple Intelligence hardware"))
        }

        guard let snapshot = document else {
            return (.unknown, L("No device document is available, so this feature cannot be judged."))
        }

        // The guard judges the combination that staging this feature
        // would produce, reusing `AIStagingGuard` — never a local copy
        // of its rules. A `.block` or `.warn` outcome is a `.conflict`
        // with the guard's specific reason; the caller-supplied
        // confirmation is already inside the request, so a confirmed
        // warn arrives here as `.allow`.
        let decision = AIStagingGuard.decide(guardRequest(
            for: featureID, productType: productType, document: snapshot.document,
            layout: resolvedLayout, liveAIEnabled: liveAIEnabled ?? profile.liveAIEnabled.value,
            userConfirmed: userConfirmedUnverifiedCombination))
        switch decision.outcome {
        case .block, .warn:
            return (.conflict, decision.reason)
        case .allow:
            break
        }

        guard let capability = Capability.all.first(where: { $0.id == featureID }) else {
            return (.unknown, L("Unknown feature — eligibility cannot be determined."))
        }
        if capability.isEnabled(in: snapshot.document) {
            return (.alreadyConfigured, L("Configured"))
        }
        return (.eligibleToEnable, L(capability.effectHint))
    }

    /// Whether every native AdvAI slot baseline that exists for this
    /// product type agrees with the current slot value. A baseline with
    /// no resolvable slot is disagreement, never agreement.
    private static func nativeSlotBaselinesAgree(
        productType: String, document: DocumentSnapshot?,
        layout: MobileGestaltCacheLayout?
    ) -> Bool {
        for key in [DeviceCacheOptions.audioIntelligenceKey,
                    DeviceCacheOptions.personalTranslatorKey] {
            guard let baseline = DeviceAIEligibility.nativeAdvAISlotValue(key: key, productType: productType) else {
                continue
            }
            let current = document.flatMap { DeviceCacheOptions.advAISlotValue(key, in: $0.document, using: layout) }
            guard current == baseline else { return false }
        }
        return true
    }

    /// The guard request for staging `featureID`: the proposed value for
    /// the feature itself, the current staged values for the other
    /// guarded key, and the current slot values (staging never writes a
    /// slot, so the current slot values are the proposed ones).
    private static func guardRequest(
        for featureID: String, productType: String, document: GestaltDocument,
        layout: MobileGestaltCacheLayout?, liveAIEnabled: Bool?, userConfirmed: Bool
    ) -> AIStagingRequest {
        func extraBool(_ key: String) -> Bool? {
            (document.extra[key] as? NSNumber)?.boolValue
        }
        func slotValue(_ key: String) -> Bool? {
            DeviceCacheOptions.advAISlotValue(key, in: document, using: layout)
        }
        return AIStagingRequest(
            productType: productType,
            audioIntelligenceExtra: featureID == "audioIntelligence"
                ? true : extraBool(DeviceCacheOptions.audioIntelligenceKey),
            personalTranslatorExtra: featureID == "personalTranslator"
                ? true : extraBool(DeviceCacheOptions.personalTranslatorKey),
            audioIntelligenceSlot: slotValue(DeviceCacheOptions.audioIntelligenceKey),
            personalTranslatorSlot: slotValue(DeviceCacheOptions.personalTranslatorKey),
            audioIntelligenceSlotIndex: layout?.slotIndex(forKey: DeviceCacheOptions.audioIntelligenceKey),
            personalTranslatorSlotIndex: layout?.slotIndex(forKey: DeviceCacheOptions.personalTranslatorKey),
            liveAIEnabled: liveAIEnabled,
            userConfirmedUnverifiedCombination: userConfirmed)
    }

    // MARK: - Dynamic Island

    private static func evaluateDynamicIsland(
        snapshot: DocumentSnapshot
    ) -> (eligibility: FeatureEligibility, reason: String) {
        // Native only on a trusted original: a verified-factory or
        // pre-modification snapshot whose factory artwork subtype is a
        // Dynamic Island layout. Anything else is judged from the
        // current state — never assumed.
        if let subtype = trustedOriginalArtworkSubtype(snapshot: snapshot),
           dynamicIslandLayoutSubtypes.contains(subtype) {
            return (.nativeSupported, L("This device already has Dynamic Island natively."))
        }
        guard let capability = Capability.all.first(where: { $0.id == "dynamicIsland" }) else {
            return (.unknown, L("Unknown feature — eligibility cannot be determined."))
        }
        if capability.isEnabled(in: snapshot.document) {
            return (.alreadyConfigured, L("Configured"))
        }
        return (.eligibleToEnable, L(capability.effectHint))
    }

    /// The factory artwork subtype, or `nil` when the snapshot is not a
    /// trusted original. `originalValue` falls back to the current
    /// document when no recorded original exists; for a
    /// trusted-provenance snapshot the current document IS the trusted
    /// original state, so the fallback is safe here — and only here.
    private static func trustedOriginalArtworkSubtype(snapshot: DocumentSnapshot) -> Int? {
        guard snapshot.provenance == .verifiedFactory || snapshot.provenance == .preModification else {
            return nil
        }
        let artwork = snapshot.originalValue(for: GestaltKeys.artwork) as? [String: Any]
        return (artwork?["ArtworkDeviceSubType"] as? NSNumber)?.intValue
    }

    // MARK: - Shared helpers

    /// Current region code: the document first, then the profile's
    /// recorded code, then the live probe.
    private static func currentRegionCode(
        profile: DeviceProfile, document: DocumentSnapshot?
    ) -> String? {
        if let code = document?.document.extra[GestaltKeys.regionCode] as? String {
            return code
        }
        return profile.regionCode.value ?? profile.liveRegionCode.value
    }

    /// Resolved layout: the caller's layout first, then the profile's
    /// cached layout, then a resolve from the document itself.
    private static func resolvedLayout(
        profile: DeviceProfile, document: DocumentSnapshot?,
        layout: MobileGestaltCacheLayout?
    ) -> MobileGestaltCacheLayout? {
        if let layout { return layout }
        if let cached = profile.cacheLayout.value { return cached }
        guard let document else { return nil }
        return try? MobileGestaltCacheLayout.resolve(in: document.document)
    }
}

// MARK: - Capability + compatibility catalog

/// Risk of staging a capability, grounded in the existing `caution`
/// flag and effect hints: a caution capability is high; a non-caution
/// Intelligence capability (region- and device-dependent) is medium;
/// everything else is low. Risk never blocks eligibility by itself.
enum CapabilityRiskLevel: String, Codable, Sendable {
    case low, medium, high
}

/// One catalog entry per capability. Titles, details and keys come
/// straight from `Capability.all` (already localized at display time
/// by the UI, exactly like `Capability` itself); the step texts are
/// catalog keys looked up with `L()` at construction.
struct CapabilityEntry: Sendable {
    let id: String
    let category: CapabilityCategory
    let title: String
    let detail: String
    let keys: [String]
    /// Feature ids this entry depends on. Only dependencies grounded in
    /// existing code: AI features depend on "regionCode" (the effect
    /// hint: "Apple Intelligence also depends on device and region").
    /// "esim" depends on a resolved cache layout, which is not a feature
    /// id, so its layout dependency is stated in its effect method and
    /// verification steps instead of here.
    let dependencies: [String]
    /// Feature ids this entry conflicts with. Only conflicts grounded in
    /// existing code: `siriOnDevice` is excluded from the 9-item unlock
    /// because forcing it could revert the Apple Intelligence Siri
    /// interface, so it conflicts with the AI set and vice versa.
    let conflicts: [String]
    let riskLevel: CapabilityRiskLevel
    /// How staging takes effect (the capability's existing effect hint).
    let effectMethod: String
    let verificationSteps: [String]
    let restoreSteps: [String]
    /// The underlying key or slot, in words. AdvAI entries name both
    /// layers: the CacheExtra key and the dynamically resolved CacheData
    /// slot — the two are never conflated.
    let underlyingKeyOrSlot: String
    let sources: [String]
    let lastVerified: String

    static func entry(for id: String) -> CapabilityEntry? {
        all.first { $0.id == id }
    }

    static let all: [CapabilityEntry] =
        Capability.all.map { CapabilityEntry(capability: $0) } + [esimEntry, regionCodeEntry]

    init(id: String, category: CapabilityCategory, title: String, detail: String,
         keys: [String], dependencies: [String], conflicts: [String],
         riskLevel: CapabilityRiskLevel, effectMethod: String,
         verificationSteps: [String], restoreSteps: [String],
         underlyingKeyOrSlot: String, sources: [String], lastVerified: String) {
        self.id = id; self.category = category; self.title = title; self.detail = detail
        self.keys = keys; self.dependencies = dependencies; self.conflicts = conflicts
        self.riskLevel = riskLevel; self.effectMethod = effectMethod
        self.verificationSteps = verificationSteps; self.restoreSteps = restoreSteps
        self.underlyingKeyOrSlot = underlyingKeyOrSlot; self.sources = sources
        self.lastVerified = lastVerified
    }

    private init(capability: Capability) {
        let isAI = ChinaUnlock.aiCapabilityIDs.contains(capability.id)
        self.init(
            id: capability.id,
            category: capability.category,
            title: capability.title,
            detail: capability.detail,
            keys: capability.keys,
            dependencies: isAI ? [FeatureEligibilityEvaluator.regionCodeFeatureID] : [],
            conflicts: capability.id == "siriOnDevice"
                ? ChinaUnlock.aiCapabilityIDs
                : (isAI ? ["siriOnDevice"] : []),
            riskLevel: Self.riskLevel(for: capability),
            effectMethod: capability.effectHint,
            verificationSteps: Self.genericVerificationSteps,
            restoreSteps: Self.genericRestoreSteps,
            underlyingKeyOrSlot: Self.underlyingKeyOrSlot(for: capability),
            sources: Self.sources(for: capability),
            lastVerified: LilaEngine.catalogDate)
    }

    private static func riskLevel(for capability: Capability) -> CapabilityRiskLevel {
        if capability.caution { return .high }
        if capability.category == .intelligence { return .medium }
        return .low
    }

    private static func underlyingKeyOrSlot(for capability: Capability) -> String {
        switch capability.id {
        case "audioIntelligence", "personalTranslator":
            return (capability.keys.first ?? "")
                + " (CacheExtra key; CacheData slot resolved dynamically)"
        default:
            return capability.keys.joined(separator: ", ")
        }
    }

    private static func sources(for capability: Capability) -> [String] {
        var sources = ["GestaltX/Capabilities.swift"]
        if ChinaUnlock.aiCapabilityIDs.contains(capability.id) || capability.id == "siriOnDevice" {
            sources += ["GestaltX/AIReadinessCheckup.swift (AIStagingGuard)",
                        "GestaltX/DeviceAIEligibility.swift"]
        }
        if capability.id == "dynamicIsland" {
            sources += ["GestaltX/ContentView.swift (Dynamic Island layout picker)"]
        }
        return sources
    }

    private static let genericVerificationSteps = [
        L("After applying, restart, then check the related entries in system Settings."),
        L("Capability flags cannot add missing hardware. Some changes require a device restart."),
    ]

    private static let genericRestoreSteps = [
        L("Original values are saved before writing. Revert removes keys that were originally absent."),
        L("The current document is backed up first. Device restores are verified after writing."),
    ]

    /// Virtual entry for the eSIM green-tea / not-green-tea group. Not a
    /// `Capability`: it stages CacheData slot flags, not CacheExtra keys.
    /// Its effect method states the honesty limit up front: staging flips
    /// flags and does not prove eSIM hardware is present.
    private static let esimEntry = CapabilityEntry(
        id: FeatureEligibilityEvaluator.esimFeatureID,
        category: .device,
        title: "eSIM",
        detail: "Enable or disable the eSIM-related system options.",
        keys: [DeviceCacheOptions.greenTeaKey, DeviceCacheOptions.notGreenTeaKey],
        dependencies: [],
        conflicts: [],
        riskLevel: .medium,
        effectMethod: L("Enable or disable the eSIM-related system options.") + " "
            + L("Staging flips the eSIM cache flags only. It does not prove eSIM hardware is present."),
        verificationSteps: [
            L("Add a digital SIM in Settings."),
            L("Staging flips the eSIM cache flags only. It does not prove eSIM hardware is present."),
        ],
        restoreSteps: genericRestoreSteps,
        underlyingKeyOrSlot: "green-tea / not-green-tea CacheData slots (resolved from the device layout)",
        sources: ["GestaltX/DeviceCacheOptions.swift", "GestaltX/MobileGestaltCacheLayout.swift"],
        lastVerified: LilaEngine.catalogDate)

    /// Virtual entry for region staging (China Unlock stages LL).
    /// Model-independent: it is the one staging the model gate does not
    /// cover.
    private static let regionCodeEntry = CapabilityEntry(
        id: FeatureEligibilityEvaluator.regionCodeFeatureID,
        category: .intelligence,
        title: "Region Code",
        detail: "Set the device region code for region-locked features.",
        keys: [GestaltKeys.regionCode],
        dependencies: [],
        conflicts: [],
        riskLevel: .medium,
        effectMethod: L("Restart the device after changing the region."),
        verificationSteps: [
            L("Restart the device after changing the region."),
            L("Changing a region flag does not guarantee Apple Intelligence or region-restricted services."),
        ],
        restoreSteps: genericRestoreSteps,
        underlyingKeyOrSlot: GestaltKeys.regionCode,
        sources: ["GestaltX/Capabilities.swift (ChinaUnlockRegionMode)",
                  "GestaltX/GestaltDocument.swift"],
        lastVerified: LilaEngine.catalogDate)
}

/// A compatibility value that is either verified or explicitly unknown.
/// There is no `.known` case with a guessed value: anything without a
/// verified table is `.unknown` with the reason.
enum CompatibilityValue: Equatable, Sendable {
    case known(String)
    case unknown(reason: String)
}

/// One compatibility entry per product type in
/// `USRegulatoryModelMapping`'s table. Anything outside the table is
/// unknown — there is no lookup that guesses for an unlisted model.
struct CompatibilityEntry: Sendable {
    let productType: String
    /// Mapped US regulatory model, or `nil` when the table has no entry
    /// (never happens for entries in `.all`; the lookup still returns
    /// `nil` rather than guessing).
    let usModel: String?
    /// Whether this hardware natively supports Apple Intelligence
    /// (exact-match list in `DeviceAIEligibility`).
    let nativeAI: Bool
    /// No verified OS-build compatibility table exists in the tree:
    /// always `.unknown` with a reason, never guessed.
    let osBuildRange: CompatibilityValue
    /// No verified per-model eSIM-hardware table exists in the tree:
    /// always `.unknown` with a reason, never guessed.
    let esimHardware: CompatibilityValue
    /// How the cache layout for this model is evidenced: resolved from
    /// the device's own library, never selected by model or OS.
    let layoutEvidence: String
    /// All cache writes need a restart (grounded in the effect hints).
    let coldRestartRequired: Bool
    let verificationMethod: String
    let restoreMethod: String

    static func entry(for productType: String) -> CompatibilityEntry? {
        all.first { $0.productType == productType }
    }

    /// Product types with a verified entry in
    /// `USRegulatoryModelMapping.productTypeMap` (iPhone 14,7–19,8).
    /// Only the keys are transcribed here; the US model and the
    /// native-AI flag are computed from the source tables, so they
    /// cannot drift. Review this list whenever the mapping table
    /// changes; the catalog tests assert exact set equality.
    static let productTypes: [String] = [
        "iPhone14,7", "iPhone14,8",
        "iPhone15,2", "iPhone15,3",
        "iPhone15,4", "iPhone15,5",
        "iPhone16,1", "iPhone16,2",
        "iPhone17,1", "iPhone17,2", "iPhone17,3", "iPhone17,4", "iPhone17,5",
        "iPhone18,1", "iPhone18,2", "iPhone18,3", "iPhone18,4", "iPhone18,5",
        "iPhone19,1", "iPhone19,2", "iPhone19,3", "iPhone19,4",
        "iPhone19,5", "iPhone19,6", "iPhone19,7", "iPhone19,8",
    ]

    static let all: [CompatibilityEntry] = productTypes.map { productType in
        CompatibilityEntry(
            productType: productType,
            usModel: USRegulatoryModelMapping.usRegulatoryModel(originalRegModel: nil, productType: productType),
            nativeAI: DeviceAIEligibility.isNativeAppleIntelligence(productType: productType),
            osBuildRange: .unknown(reason: L("No verified OS-build compatibility table exists for this model, so OS-build compatibility is unknown.")),
            esimHardware: .unknown(reason: L("No verified per-model eSIM-hardware table exists, so eSIM hardware presence is unknown.")),
            layoutEvidence: L("Cache layout is resolved from the device's own library, never selected by model or OS."),
            coldRestartRequired: true,
            verificationMethod: L("After applying, restart, then check the related entries in system Settings."),
            restoreMethod: L("Original values are saved before writing. Revert removes keys that were originally absent."))
    }
}

/// Catalog identity. Bump `LilaEngine.catalogVersion` whenever the
/// table changes, so a stale table can be identified.
enum CapabilityCatalog {
    static let version = LilaEngine.catalogVersion
    static let catalogDate = LilaEngine.catalogDate
}

// MARK: - Recommendation (data only — never applied by this struct)

/// The kind of write a recommendation step performs.
enum PlanStepKind: String, Equatable, Sendable {
    /// One named entry in the CacheExtra dictionary.
    case cacheExtraKey
    /// One boolean byte inside the CacheData blob, at a resolved slot.
    case cacheDataSlot
    /// The region code (and, in Full US mode, the sales-region suffix).
    case region
    /// One entry inside the artwork dictionary.
    case artwork
}

/// One recommended change, stored as data — never as a closure — so a
/// recommendation is inspectable, reviewable and serialisable before
/// anything is applied. `key` is the primary key for the step; for a
/// multi-key capability the step writes every key of that capability
/// with its catalog value (exactly what `Capability.apply(.enable)`
/// does). `slotIndex` is the resolved CacheData slot for
/// `.cacheDataSlot` steps, or `nil` when the step does not touch
/// CacheData. `salesSuffix` is set only on a Full US region step
/// ("LL/A"); it is `nil` for every other step.
///
/// This struct has NO apply method on purpose: applying a step is the
/// integration's job (GestaltManager's existing staging paths), and
/// the SafePatch simulator applies steps to an in-memory copy only.
struct PlanStep: Equatable, Sendable {
    let featureID: String
    let title: String
    let kind: PlanStepKind
    let key: String?
    let layer: ChangeLayer
    let newValue: ChangeValue
    let slotIndex: Int?
    let salesSuffix: String?
    /// Exactly what will be verified after applying (readback wording).
    /// Never claims hardware verification.
    let verification: String

    init(featureID: String, title: String, kind: PlanStepKind, key: String?,
         layer: ChangeLayer, newValue: ChangeValue, slotIndex: Int?,
         salesSuffix: String? = nil, verification: String) {
        self.featureID = featureID
        self.title = title
        self.kind = kind
        self.key = key
        self.layer = layer
        self.newValue = newValue
        self.slotIndex = slotIndex
        self.salesSuffix = salesSuffix
        self.verification = verification
    }

    /// Whether this step has everything an application needs. A step
    /// is built actionable; this is the executable-recommendation
    /// check, not a repair path.
    var isActionable: Bool {
        switch kind {
        case .cacheExtraKey: return key != nil
        case .cacheDataSlot: return slotIndex != nil
        case .region:
            if case .string = newValue { return true }
            return false
        case .artwork: return key != nil
        }
    }
}

/// A per-device recommendation: data only, never applied by this
/// struct. The caller owns review, staging, backup, apply and
/// readback; this struct only says what would be staged and why a
/// feature could not be staged.
struct LilaRecommendation: Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    let deviceID: String
    let productType: String
    let steps: [PlanStep]
    let blockers: [PlanBlocker]
    let requiresRestart: Bool

    /// True only when there is something to execute, nothing blocks it,
    /// and every step is actionable. An empty recommendation is not
    /// executable: there is nothing to apply.
    var isExecutable: Bool {
        blockers.isEmpty && !steps.isEmpty && steps.allSatisfy(\.isActionable)
    }
}

/// Pure dependency checks over a requested feature set. Every
/// dependency here is grounded in existing code; no dependency is
/// invented. A failed dependency is a `PlanBlocker` with the specific
/// reason.
enum DependencyResolver {
    /// Staging order: eSIM first, then region, then the AI capabilities
    /// (in `ChinaUnlock.aiCapabilityIDs` order), then everything else in
    /// requested order. Mirrors `GestaltManager.stageChinaUnlock`.
    /// Duplicates are removed, keeping the first occurrence.
    static func ordered(featureIDs: [String]) -> [String] {
        var seen = Set<String>()
        var rest: [String] = []
        for id in featureIDs where seen.insert(id).inserted {
            rest.append(id)
        }
        let head = [FeatureEligibilityEvaluator.esimFeatureID, FeatureEligibilityEvaluator.regionCodeFeatureID]
        let ai = ChinaUnlock.aiCapabilityIDs
        return head.filter { rest.contains($0) }
            + ai.filter { rest.contains($0) }
            + rest.filter { !head.contains($0) && !ai.contains($0) }
    }

    /// Checks the three dependencies this engine knows, and only those:
    /// - AI features depend on "regionCode" being staged to LL
    ///   (`Capability.effectHint`: "Apple Intelligence also depends on
    ///   device and region"). No blocker when "regionCode" is requested
    ///   in the same plan, or when the document already reads LL.
    /// - "esim" and "wapi" steps depend on a resolved cache layout
    ///   (`DeviceCacheOptions` / `MobileGestaltCacheLayout`): the slot
    ///   offsets come from the layout, never from a guessed number.
    /// - A slot repair depends on a known native baseline
    ///   (`DeviceAIEligibility.nativeAdvAISlotValue`): on native-AI
    ///   hardware, when a guarded slot disagrees with its baseline but
    ///   no baseline is known for this device/key (for example Personal
    ///   Translator on a native-AI iPad, where the recorded original is
    ///   the baseline), the repair cannot be staged from a constant.
    static func check(featureIDs: [String], profile: DeviceProfile,
                      document: GestaltDocument,
                      layout: MobileGestaltCacheLayout?) -> [PlanBlocker] {
        var blockers: [PlanBlocker] = []
        let requested = Set(featureIDs)

        if requested.contains(FeatureEligibilityEvaluator.esimFeatureID)
            || requested.contains(FeatureEligibilityEvaluator.wapiFeatureID) {
            if layout == nil {
                let reason = MobileGestaltCacheLayout.lockReason(in: document)
                    ?? L("Unable to resolve this device's MobileGestalt cache layout.")
                for id in [FeatureEligibilityEvaluator.esimFeatureID, FeatureEligibilityEvaluator.wapiFeatureID]
                where requested.contains(id) {
                    blockers.append(PlanBlocker(featureID: id, code: "layout-unresolved", reason: reason))
                }
            }
        }

        let aiRequested = ChinaUnlock.aiCapabilityIDs.filter { requested.contains($0) }
        if !aiRequested.isEmpty, !requested.contains(FeatureEligibilityEvaluator.regionCodeFeatureID),
           // The stored region code is "LL" (`ChinaUnlock.regionCodeID`
           // is "US", the preset id — not the stored code).
           document.extra[GestaltKeys.regionCode] as? String != "LL" {
            for id in aiRequested {
                blockers.append(PlanBlocker(
                    featureID: id, code: "missing-region",
                    reason: L("Restart required. Apple Intelligence also depends on device and region.")))
            }
        }

        let productType = profile.productType.value
            ?? document.extra[GestaltKeys.productType] as? String ?? ""
        if let layout, profile.isNativeAppleIntelligence.value == true {
            for key in [DeviceCacheOptions.audioIntelligenceKey,
                        DeviceCacheOptions.personalTranslatorKey] {
                let id = key == DeviceCacheOptions.audioIntelligenceKey
                    ? "audioIntelligence" : "personalTranslator"
                guard requested.contains(id),
                      DeviceAIEligibility.nativeAdvAISlotValue(key: key, productType: productType) == nil,
                      let current = DeviceCacheOptions.advAISlotValue(key, in: document, using: layout) else { continue }
                // The guard blocks exactly when the slot disagrees with
                // the native baseline (audio 1, translator 0); without a
                // known baseline that disagreement cannot be repaired
                // from a constant — the recorded original is the baseline.
                let disagrees = key == DeviceCacheOptions.audioIntelligenceKey ? current : !current
                guard disagrees else { continue }
                blockers.append(PlanBlocker(
                    featureID: id, code: "no-native-baseline",
                    reason: L("The CacheData slot cannot be repaired to a known baseline on this device, so staging is refused until the recorded original value is available.")))
            }
        }
        return blockers
    }
}

/// Builds a `LilaRecommendation` from plain eligibility results. Pure:
/// reads the profile, document and layout, writes nothing.
enum LilaRecommendationBuilder {
    /// Builds the recommendation for `featureIDs`. `evaluations` is
    /// keyed by feature id and carries the evaluator's eligibility and
    /// its specific reason; a feature with no evaluation, or any
    /// eligibility other than `.eligibleToEnable`, becomes a blocker
    /// and gets no step. `layout` is the resolved cache layout, or
    /// `nil` when it did not resolve — the profile's cached layout is
    /// used as a fallback. `regionMode` selects region-code-only (LL,
    /// sales suffix kept) or Full US (LL + LL/A). The model number is
    /// never staged by this builder: it is outside the 9-item scope
    /// and needs the `DeviceModelSupport` gate, which belongs to the
    /// integration that owns Full US model staging.
    static func build(featureIDs: [String],
                      evaluations: [String: (eligibility: FeatureEligibility, reason: String)],
                      profile: DeviceProfile,
                      document: GestaltDocument,
                      layout: MobileGestaltCacheLayout?,
                      regionMode: ChinaUnlockRegionMode) -> LilaRecommendation {
        let effectiveLayout = layout ?? profile.cacheLayout.value
        let productType = profile.productType.value
            ?? document.extra[GestaltKeys.productType] as? String ?? ""
        let deviceID = document.extra["UniqueDeviceID"] as? String ?? ""
        let ordered = DependencyResolver.ordered(featureIDs: featureIDs)
        var blockers = DependencyResolver.check(featureIDs: ordered, profile: profile,
                                                document: document, layout: effectiveLayout)
        let dependencyBlocked = Set(blockers.map(\.featureID))
        var steps: [PlanStep] = []
        var advAIRequested: [String] = []

        func blockerCode(for eligibility: FeatureEligibility) -> String {
            switch eligibility {
            case .nativeSupported: return "native-supported"
            case .alreadyConfigured: return "already-configured"
            case .unsupported: return "unsupported"
            case .unknown: return "unknown"
            case .conflict: return "conflict"
            case .eligibleToEnable: return "eligible"
            }
        }

        for id in ordered {
            if dependencyBlocked.contains(id) { continue }
            guard let evaluation = evaluations[id] else {
                blockers.append(PlanBlocker(
                    featureID: id, code: "not-evaluated",
                    reason: L("No eligibility result was provided for this feature, so it cannot be staged.")))
                continue
            }
            guard evaluation.eligibility == .eligibleToEnable else {
                blockers.append(PlanBlocker(featureID: id,
                                            code: blockerCode(for: evaluation.eligibility),
                                            reason: evaluation.reason))
                continue
            }
            switch id {
            case FeatureEligibilityEvaluator.esimFeatureID:
                guard let layout = effectiveLayout,
                      (try? DeviceCacheOptions.flags(in: document, using: layout)) != nil else {
                    blockers.append(PlanBlocker(
                        featureID: id, code: "layout-unresolved",
                        reason: MobileGestaltCacheLayout.lockReason(in: document)
                            ?? L("Unable to resolve this device's MobileGestalt cache layout.")))
                    continue
                }
                steps.append(PlanStep(
                    featureID: id, title: L("Network & eSIM"), kind: .cacheDataSlot,
                    key: DeviceCacheOptions.greenTeaKey, layer: .cacheData,
                    newValue: .bool(true), slotIndex: layout.greenTeaIndex,
                    verification: String(format: L("CacheData slots #%d/#%d read back as staged — this verifies the flags, not eSIM hardware."),
                                         layout.greenTeaIndex, layout.notGreenTeaIndex)))
            case FeatureEligibilityEvaluator.regionCodeFeatureID:
                let salesSuffix = regionMode == .fullUS ? "LL/A" : nil
                let staged = salesSuffix.map { "LL, with sales-region suffix \($0)" } ?? "LL"
                steps.append(PlanStep(
                    featureID: id, title: L("Region Code"), kind: .region,
                    key: GestaltKeys.regionCode, layer: .cacheExtra,
                    // The stored region code is "LL" (the US preset's
                    // code); `ChinaUnlock.regionCodeID` is "US", the
                    // preset id, and must never be written as the code.
                    newValue: .string("LL"), slotIndex: nil,
                    salesSuffix: salesSuffix,
                    verification: String(format: L("Region code reads back as %@ — this verifies the staged code, not region-restricted services."),
                                         staged)))
            case FeatureEligibilityEvaluator.wapiFeatureID:
                guard let layout = effectiveLayout, layout.wapiIndex != nil,
                      (try? DeviceCacheOptions.wapi(in: document, using: layout)) != nil else {
                    blockers.append(PlanBlocker(
                        featureID: id, code: "wapi-unavailable",
                        reason: L("The cache layout or values do not match this preset.")))
                    continue
                }
                steps.append(PlanStep(
                    featureID: id, title: L("WAPI"), kind: .cacheDataSlot,
                    key: DeviceCacheOptions.wapiKey, layer: .cacheData,
                    newValue: .bool(false), slotIndex: layout.wapiIndex,
                    verification: L("WAPI flag reads back as disabled — this verifies the staged flag, not network hardware.")))
            case "siriOnDevice":
                // Deliberately excluded from every auto-plan: Siri uses a
                // device-specific capability type, and the 9-item unlock
                // preserves its recorded value. Even an "eligible"
                // evaluation must not stage it.
                let reason = Capability.all.first { $0.id == id }?.effectHint
                    ?? L("Restart required. Siri uses a device-specific capability type; changing it may affect the Apple Intelligence Siri interface. Keep the current value or restore the recorded original.")
                blockers.append(PlanBlocker(featureID: id, code: "excluded-feature", reason: reason))
            case "audioIntelligence", "personalTranslator":
                // Guarded as one combination below, not one by one: the
                // AI staging guard decides on the proposed combination.
                advAIRequested.append(id)
            default:
                guard let capability = Capability.all.first(where: { $0.id == id }) else {
                    blockers.append(PlanBlocker(
                        featureID: id, code: "unknown-feature",
                        reason: L("This feature is not in the capability catalog, so it cannot be staged.")))
                    continue
                }
                let key = capability.keys.first
                let value = key.flatMap { capability.values?[$0] } ?? capability.enabled
                steps.append(PlanStep(
                    featureID: id, title: capability.title, kind: .cacheExtraKey,
                    key: key, layer: .cacheExtra,
                    newValue: ChangeValue.fromPlistValue(value) ?? .absent,
                    slotIndex: nil,
                    verification: String(format: L("CacheExtra key %@ reads back as staged — this verifies the staged flag, not the underlying hardware or service."),
                                         key ?? id)))
            }
        }

        if !advAIRequested.isEmpty {
            addAdvAISteps(for: advAIRequested, profile: profile, document: document,
                          layout: effectiveLayout, productType: productType,
                          steps: &steps, blockers: &blockers)
        }

        return LilaRecommendation(id: UUID(), createdAt: Date(), deviceID: deviceID,
                                  productType: productType, steps: steps, blockers: blockers,
                                  requiresRestart: !steps.isEmpty)
    }

    /// The two guarded AI capabilities (`audioIntelligence`,
    /// `personalTranslator`) share one CacheData slot baseline question,
    /// so they are decided together through `AIStagingGuard` on the
    /// proposed combination (both CacheExtra keys staged as 1), mirroring
    /// `GestaltManager.fixAIReadiness`. Their steps therefore land after
    /// the other AI steps in the recommendation; repair steps, when
    /// staged, come immediately before their CacheExtra steps.
    /// - `.allow` — stage the CacheExtra steps.
    /// - `.block` — stage a slot-repair step for each slot that disagrees
    ///   with its known native baseline, then re-evaluate with the
    ///   repaired slots: `.allow` stages repairs + CacheExtra steps;
    ///   `.warn` keeps the repairs but blocks the CacheExtra steps with
    ///   the warn reason (explicit confirmation belongs to the caller,
    ///   not to this builder); still `.block` stages nothing and blocks
    ///   with the new reason.
    /// - `.warn` — block the CacheExtra steps with the warn reason; the
    ///   slots already match their baselines, so there is nothing to
    ///   repair. This is the unresolved #178 case on native hardware:
    ///   staging the CacheExtra key alone is unverified, so it must not
    ///   be auto-staged silently.
    private static func addAdvAISteps(for ids: [String], profile: DeviceProfile,
                                      document: GestaltDocument,
                                      layout: MobileGestaltCacheLayout?,
                                      productType: String,
                                      steps: inout [PlanStep], blockers: inout [PlanBlocker]) {
        func request(slotOverrides: [String: Bool] = [:]) -> AIStagingRequest {
            var request = AIStagingRequest(productType: productType)
            if ids.contains("audioIntelligence") { request.audioIntelligenceExtra = true }
            if ids.contains("personalTranslator") { request.personalTranslatorExtra = true }
            if let layout {
                request.audioIntelligenceSlotIndex = layout.slotIndex(forKey: DeviceCacheOptions.audioIntelligenceKey)
                request.personalTranslatorSlotIndex = layout.slotIndex(forKey: DeviceCacheOptions.personalTranslatorKey)
                request.audioIntelligenceSlot = slotOverrides[DeviceCacheOptions.audioIntelligenceKey]
                    ?? DeviceCacheOptions.advAISlotValue(DeviceCacheOptions.audioIntelligenceKey, in: document, using: layout)
                request.personalTranslatorSlot = slotOverrides[DeviceCacheOptions.personalTranslatorKey]
                    ?? DeviceCacheOptions.advAISlotValue(DeviceCacheOptions.personalTranslatorKey, in: document, using: layout)
            }
            request.liveAIEnabled = profile.liveAIEnabled.value
            return request
        }

        func cacheExtraStep(for id: String) -> PlanStep? {
            guard let capability = Capability.all.first(where: { $0.id == id }),
                  let key = capability.keys.first else { return nil }
            let value = capability.values?[key] ?? capability.enabled
            return PlanStep(
                featureID: id, title: capability.title, kind: .cacheExtraKey,
                key: key, layer: .cacheExtra,
                newValue: ChangeValue.fromPlistValue(value) ?? .absent, slotIndex: nil,
                verification: String(format: L("CacheExtra key %@ reads back as staged — this verifies the staged flag, not the underlying hardware or service."),
                                     key))
        }

        func repairStep(forKey key: String, baseline: Bool, slot: Int) -> PlanStep {
            let id = key == DeviceCacheOptions.audioIntelligenceKey ? "audioIntelligence" : "personalTranslator"
            let title = Capability.all.first { $0.id == id }?.title ?? id
            return PlanStep(
                featureID: id, title: title, kind: .cacheDataSlot,
                key: key, layer: .cacheData, newValue: .bool(baseline), slotIndex: slot,
                verification: String(format: L("CacheData slot #%d reads back at its native baseline — this verifies the slot value, not the feature itself."),
                                     slot))
        }

        let decision = AIStagingGuard.decide(request())
        switch decision.outcome {
        case .allow:
            for id in ids { if let step = cacheExtraStep(for: id) { steps.append(step) } }
        case .warn:
            for id in ids {
                blockers.append(PlanBlocker(featureID: id, code: "guard-warn", reason: decision.reason))
            }
        case .block:
            // Which slots disagree with a known native baseline, and can
            // therefore be repaired to it?
            var repairs: [(key: String, baseline: Bool, slot: Int)] = []
            var overrides: [String: Bool] = [:]
            if let layout {
                for key in [DeviceCacheOptions.audioIntelligenceKey,
                            DeviceCacheOptions.personalTranslatorKey] {
                    let id = key == DeviceCacheOptions.audioIntelligenceKey
                        ? "audioIntelligence" : "personalTranslator"
                    guard ids.contains(id),
                          let baseline = DeviceAIEligibility.nativeAdvAISlotValue(key: key, productType: productType),
                          let slot = layout.slotIndex(forKey: key),
                          let current = DeviceCacheOptions.advAISlotValue(key, in: document, using: layout),
                          current != baseline else { continue }
                    repairs.append((key: key, baseline: baseline, slot: slot))
                    overrides[key] = baseline
                }
            }
            guard !repairs.isEmpty else {
                for id in ids {
                    blockers.append(PlanBlocker(featureID: id, code: "guard-block", reason: decision.reason))
                }
                return
            }
            let redecision = AIStagingGuard.decide(request(slotOverrides: overrides))
            switch redecision.outcome {
            case .allow:
                for repair in repairs {
                    steps.append(repairStep(forKey: repair.key, baseline: repair.baseline, slot: repair.slot))
                }
                for id in ids { if let step = cacheExtraStep(for: id) { steps.append(step) } }
            case .warn:
                // The repairs restore the native baselines and stay
                // staged; the CacheExtra staging itself still needs an
                // explicit confirmation, so it is blocked with the
                // warn reason.
                for repair in repairs {
                    steps.append(repairStep(forKey: repair.key, baseline: repair.baseline, slot: repair.slot))
                }
                for id in ids {
                    blockers.append(PlanBlocker(featureID: id, code: "guard-warn", reason: redecision.reason))
                }
            case .block:
                // The repairs would not clear the block; stage nothing.
                for id in ids {
                    blockers.append(PlanBlocker(featureID: id, code: "guard-block", reason: redecision.reason))
                }
            }
        }
    }
}

// MARK: - LilaIntelligence report

/// One feature's evaluation, for display: the catalog entry, the
/// eligibility state and the specific reason.
struct LilaFeatureEvaluation: Equatable, Sendable {
    let featureID: String
    let title: String
    let eligibility: FeatureEligibility
    let reason: String
    let riskLevel: CapabilityRiskLevel
}

/// The full per-device report: the device profile, every known
/// feature's eligibility, and the recommendation for the features
/// that may be staged. Read-only data — the report never stages or
/// writes anything.
struct LilaDeviceReport: Equatable, Sendable {
    let profile: DeviceProfile
    let evaluations: [LilaFeatureEvaluation]
    /// The recommendation for the China Unlock set (eSIM + region +
    /// the six AI capabilities), built from the evaluations. Other
    /// features are evaluated but not recommended here: the caller
    /// builds a recommendation for them with
    /// `LilaRecommendationBuilder.build` when the user asks for one.
    let chinaUnlockRecommendation: LilaRecommendation

    var nativeCount: Int { evaluations.filter { $0.eligibility == .nativeSupported }.count }
    var eligibleCount: Int { evaluations.filter { $0.eligibility == .eligibleToEnable }.count }
    var blockedCount: Int { evaluations.filter { $0.eligibility == .conflict || $0.eligibility == .unsupported }.count }
    var unknownCount: Int { evaluations.filter { $0.eligibility == .unknown }.count }
}

/// Builds the per-device report from a snapshot. `backups` is the
/// backup inventory the profiler may count (the caller's
/// `GestaltManager.backups`); `changeRecordCount` is the number of
/// persisted change records (0 until Restore Intelligence persists
/// them). Pure: reads the snapshot and the injected sources, writes
/// nothing.
enum LilaIntelligence {
    /// Builds the per-device report for `snapshot`. `profile` is an
    /// optional pre-built profile (for example from a test fixture or
    /// a caller that already profiled the device); when `nil` the
    /// profile is built from the system sources, as before. The
    /// profile is injectable so the evaluation can be unit-tested
    /// against a known device without a real phone.
    static func report(
        snapshot: DocumentSnapshot?,
        backups: [BackupRecord] = [],
        changeRecordCount: Int = 0,
        regionMode: ChinaUnlockRegionMode = .regionCodeOnly,
        userConfirmedUnverifiedCombination: Bool = false,
        profile: DeviceProfile? = nil
    ) -> LilaDeviceReport {
        struct StaticBackups: BackupInventorySource {
            let records: [BackupRecord]
        }
        let profiler = DeviceProfiler(
            backups: StaticBackups(records: backups),
            changeRecordCount: changeRecordCount)
        let document = snapshot?.document
        let profile = profile ?? profiler.profile(
            document: document, documentByteCount: snapshot?.data.count ?? 0)
        let layout = profile.cacheLayout.value
        var evaluations: [LilaFeatureEvaluation] = []
        var evaluationMap: [String: (eligibility: FeatureEligibility, reason: String)] = [:]
        for id in FeatureEligibilityEvaluator.knownFeatureIDs {
            let result = FeatureEligibilityEvaluator.evaluate(
                featureID: id, profile: profile, document: snapshot, layout: layout,
                liveAIEnabled: nil,
                userConfirmedUnverifiedCombination: userConfirmedUnverifiedCombination)
            evaluationMap[id] = result
            let entry = CapabilityEntry.entry(for: id)
            evaluations.append(LilaFeatureEvaluation(
                featureID: id,
                title: entry?.title ?? id,
                eligibility: result.eligibility,
                reason: result.reason,
                riskLevel: entry?.riskLevel ?? .low))
        }
        let chinaUnlockIDs = [FeatureEligibilityEvaluator.esimFeatureID,
                              FeatureEligibilityEvaluator.regionCodeFeatureID]
            + ChinaUnlock.aiCapabilityIDs
        let recommendation: LilaRecommendation
        if let document = snapshot?.document {
            recommendation = LilaRecommendationBuilder.build(
                featureIDs: chinaUnlockIDs, evaluations: evaluationMap,
                profile: profile, document: document,
                layout: layout, regionMode: regionMode)
        } else {
            // No document: no step can be built. Every requested
            // feature is a blocker with its evaluation reason — never
            // an executable step from no evidence.
            recommendation = LilaRecommendation(
                id: UUID(), createdAt: Date(), deviceID: "",
                productType: profile.productType.value ?? "",
                steps: [],
                blockers: chinaUnlockIDs.compactMap { id in
                    evaluationMap[id].map { PlanBlocker(featureID: id, code: "unknown", reason: $0.reason) }
                },
                requiresRestart: false)
        }
        return LilaDeviceReport(profile: profile, evaluations: evaluations,
                                chinaUnlockRecommendation: recommendation)
    }
}
