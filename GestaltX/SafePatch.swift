// SPDX-License-Identifier: GPL-3.0-only
// SafePatch (修改模拟器) — pre-write simulation + conflict analysis.
// Pure Foundation — no SwiftUI, no UIKit, no singletons, no global
// mutable state.
//
// Before the user taps enable, the simulator shows each field's
// current value, target value, risk and expected impact. It tests, on
// an offline in-memory copy, whether presets conflict, whether they
// touch hardware-identity fields, and whether there are unrecoverable
// modifications.
//
// THE SIMULATOR NEVER WRITES. It reads the snapshot and the backup
// inventory, builds the would-be document as an in-memory struct copy
// (using the same typed document setters, on the copy only), computes
// the diff, verifies the serialization round-trip, and discards the
// copy. No file I/O happens here; no GestaltFileStore call, no commit,
// no DevicePlistWriter call.
//
// SIMULATION PASSING DOES NOT MEAN the system will take effect. A
// passing simulation only means the proposed change is internally
// consistent and restorable on paper; real-device verification after
// applying and restarting is still required, and the UI must say so.
import Foundation

// MARK: - Proposal

/// What the user wants to stage, as data. The simulator never stages
/// anything; it only simulates this proposal.
struct SafePatchProposal: Hashable, Sendable {
    let featureIDs: [String]
    let regionMode: ChinaUnlockRegionMode

    init(featureIDs: [String], regionMode: ChinaUnlockRegionMode = .regionCodeOnly) {
        self.featureIDs = featureIDs
        self.regionMode = regionMode
    }

    /// The 9-item China Unlock: eSIM + region code + six AI keys.
    static func oneTap(regionMode: ChinaUnlockRegionMode = .regionCodeOnly) -> SafePatchProposal {
        SafePatchProposal(featureIDs: [FeatureEligibilityEvaluator.esimFeatureID,
                                       FeatureEligibilityEvaluator.regionCodeFeatureID]
                            + ChinaUnlock.aiCapabilityIDs, regionMode: regionMode)
    }

    /// The six AI capabilities only (the standalone AI preset).
    static func aiOnly(regionMode: ChinaUnlockRegionMode = .regionCodeOnly) -> SafePatchProposal {
        SafePatchProposal(featureIDs: ChinaUnlock.aiCapabilityIDs, regionMode: regionMode)
    }

    /// eSIM + region only (the standalone eSIM & Region preset).
    static func esimRegion(regionMode: ChinaUnlockRegionMode = .regionCodeOnly) -> SafePatchProposal {
        SafePatchProposal(featureIDs: [FeatureEligibilityEvaluator.esimFeatureID,
                                       FeatureEligibilityEvaluator.regionCodeFeatureID],
                          regionMode: regionMode)
    }
}

// MARK: - Simulation result types

/// One pre-check in the simulation sequence.
struct SafePatchCheck: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case trustedOriginal
        case unchangedSinceSnapshot
        case dependencies
        case nativeAndConflicts
        case diff
        case hardwareIdentity
        case backupPrerequisites
        case serialization
    }
    let kind: Kind
    /// True when the check passed. A failed check is a blocker when
    /// `isBlocker` is true, a warning otherwise.
    let passed: Bool
    let isBlocker: Bool
    let reason: String

    /// The user-facing title for this check kind.
    var title: String {
        switch kind {
        case .trustedOriginal: return L("Trusted original snapshot")
        case .unchangedSinceSnapshot: return L("Unchanged since snapshot")
        case .dependencies: return L("Preset dependencies")
        case .nativeAndConflicts: return L("Native support and conflicts")
        case .diff: return L("Original → target diff")
        case .hardwareIdentity: return L("Hardware-identity check")
        case .backupPrerequisites: return L("Backup and restore prerequisites")
        case .serialization: return L("Offline serialization")
        }
    }
}

/// Where the "original" value in a diff row comes from. A recorded
/// original is trusted; a first-recorded value is the value the
/// snapshot document held when this app first read it — it may
/// already have been modified before that read, so it is never
/// presented as a factory value; `.absent` means the key did not
/// exist.
enum SafePatchOriginalSource: Equatable, Sendable {
    case recordedOriginal
    case firstRecordedValue
    case absent
}

/// One field the proposal would change: original → target.
struct SafePatchDiff: Equatable, Sendable {
    let key: String
    let title: String
    let layer: ChangeLayer
    let original: ChangeValue
    let target: ChangeValue
    let originalSource: SafePatchOriginalSource
    let risk: CapabilityRiskLevel
    var wasAbsent: Bool { original == .absent }

    /// The user-facing label for where the "original" value comes
    /// from. A first-recorded value is never presented as a factory
    /// value.
    var sourceLabel: String {
        switch originalSource {
        case .recordedOriginal: return L("Original: recorded original")
        case .firstRecordedValue: return L("Original: first-recorded value")
        case .absent: return L("Original: key was absent")
        }
    }
}

/// The four effect states, strictly distinguished. Only the first
/// ("staged") is ever projected by a simulation; the other three are
/// confirmed only by real events after applying (file write verified,
/// re-read consistent after restart, system function actually
/// verified). File write success is NEVER presented as "feature
/// definitely effective".
enum SafePatchEffect: String, Equatable, Sendable {
    case staged
    case fileWriteVerified
    case restartConsistent
    case functionVerified

    var title: String {
        switch self {
        case .staged: return L("Staged")
        case .fileWriteVerified: return L("File write verified")
        case .restartConsistent: return L("Re-read consistent after restart")
        case .functionVerified: return L("System function actually verified")
        }
    }
}

/// Status of one effect state for a simulated or past change.
enum SafePatchEffectStatus: Equatable, Sendable {
    case notReached
    case verified
    case failed(reason: String)
    case unknown(reason: String)
}

struct SafePatchEffectState: Equatable, Sendable {
    let effect: SafePatchEffect
    let status: SafePatchEffectStatus
    let note: String
}

/// The full simulation result. `canProceed` is true only when no
/// check failed as a blocker. Warnings do not block, but they are
/// shown alongside the diff so the user reviews them before applying.
struct SafePatchSimulation: Equatable, Sendable {
    let proposal: SafePatchProposal
    let checks: [SafePatchCheck]
    let diffs: [SafePatchDiff]
    let blockers: [String]
    let warnings: [String]
    /// Keys in the diff that touch hardware-identity fields.
    let hardwareIdentityTouches: [String]
    let canProceed: Bool
    let serializationOK: Bool
    let backupReady: Bool
    let effectStates: [SafePatchEffectState]
    /// Byte count of the simulated document, or `nil` when the
    /// simulation could not build one.
    let simulatedByteCount: Int?

    func check(_ kind: SafePatchCheck.Kind) -> SafePatchCheck? {
        checks.first { $0.kind == kind }
    }
}

// MARK: - Simulator

enum SafePatch {
    /// Hardware-identity fields. Changing any of these can break Face
    /// ID, make verification tools report a mismatch, or make the
    /// system discard the whole cache at boot. The set is the
    /// regulatory model + product type (the two the one-tap / Full US
    /// paths could touch) plus the device-identity keys
    /// `GestaltDocument.preservesDeviceIdentity` guards.
    static let hardwareIdentityKeys: Set<String> = [
        GestaltKeys.productType,
        GestaltKeys.modelNumber,
        "UniqueDeviceID",
        "SerialNumber",
        "UniqueChipID",
        "re6Zb+zwFKJNlkQTUeT+/w",
        "VasUgeSzVyHdB27g2XpN0g",
        "TF31PAB6aO8KAbPyNKSxKA",
        "hardwareModel",
        "cpu",
    ]

    /// Simulates `proposal` against `snapshot`. `currentDocument` is a
    /// fresh re-read of the device file when the caller has one; when
    /// it is supplied and differs from the snapshot, the simulation
    /// refuses (the data changed since the snapshot). `backups` is the
    /// backup inventory used for the restore-prerequisite check.
    /// `profile` is an optional pre-built device profile (for example
    /// from a test fixture); when `nil` the report builds one from the
    /// system sources. Pure: reads its inputs, writes nothing,
    /// performs no file I/O.
    static func simulate(
        proposal: SafePatchProposal,
        snapshot: DocumentSnapshot?,
        currentDocument: GestaltDocument? = nil,
        backups: [BackupRecord] = [],
        userConfirmedUnverifiedCombination: Bool = false,
        profile: DeviceProfile? = nil
    ) -> SafePatchSimulation {
        var checks: [SafePatchCheck] = []
        var blockers: [String] = []
        var warnings: [String] = []

        func record(_ check: SafePatchCheck) {
            checks.append(check)
            if !check.passed {
                if check.isBlocker { blockers.append(check.reason) }
                else { warnings.append(check.reason) }
            }
        }

        // (a) Trusted original snapshot present.
        guard let snapshot else {
            record(SafePatchCheck(kind: .trustedOriginal, passed: false, isBlocker: true,
                                  reason: L("No document has been read.")))
            return finish(proposal: proposal, checks: checks, diffs: [], blockers: blockers,
                          warnings: warnings, hardwareIdentityTouches: [], serializationOK: false,
                          backupReady: false, simulatedByteCount: nil)
        }
        let hasAnyOriginal = !snapshot.originals.isEmpty
            || snapshot.cachedOptionsOriginal != nil
            || snapshot.wapiOriginal != nil
        record(SafePatchCheck(
            kind: .trustedOriginal, passed: hasAnyOriginal, isBlocker: true,
            reason: hasAnyOriginal
                ? L("A trusted original is available for this change.")
                : L("No recorded original exists, so a precise restore cannot be guaranteed.")))

        // (b) Current data unchanged since the snapshot.
        if let currentDocument {
            let unchanged = snapshot.document.matches(currentDocument)
            record(SafePatchCheck(
                kind: .unchangedSinceSnapshot, passed: unchanged, isBlocker: true,
                reason: unchanged
                    ? L("The device data matches the snapshot.")
                    : L("The device data changed since the snapshot. Read again before simulating.")))
        } else {
            record(SafePatchCheck(
                kind: .unchangedSinceSnapshot, passed: false, isBlocker: false,
                reason: L("No fresh re-read was supplied, so the snapshot could not be re-verified.")))
        }

        // Evaluations for the proposed features (single source of
        // truth: the Lila Intelligence report).
        let report = LilaIntelligence.report(snapshot: snapshot, backups: backups,
                                             userConfirmedUnverifiedCombination: userConfirmedUnverifiedCombination,
                                             profile: profile)
        let evaluationMap: [String: (eligibility: FeatureEligibility, reason: String)] =
            Dictionary(uniqueKeysWithValues: report.evaluations.map {
                ($0.featureID, ($0.eligibility, $0.reason))
            })
        let profile = report.profile
        let layout = profile.cacheLayout.value

        // (c) Dependency check.
        let dependencyBlockers = DependencyResolver.check(
            featureIDs: proposal.featureIDs, profile: profile,
            document: snapshot.document, layout: layout)
        record(SafePatchCheck(
            kind: .dependencies,
            passed: dependencyBlockers.isEmpty, isBlocker: true,
            reason: dependencyBlockers.first?.reason
                ?? L("All preset dependencies are satisfied.")))

        // (d) Native support and conflicts. Native-supported and
        // already-configured features need no change (not a blocker);
        // unknown, unsupported and conflicted features block.
        var nativeSkipped: [String] = []
        var conflictReasons: [String] = []
        for id in proposal.featureIDs {
            guard let evaluation = evaluationMap[id] else {
                conflictReasons.append(L("No eligibility result was provided for this feature, so it cannot be staged."))
                continue
            }
            switch evaluation.eligibility {
            case .nativeSupported, .alreadyConfigured:
                nativeSkipped.append(id)
            case .eligibleToEnable:
                break
            case .unknown, .unsupported, .conflict:
                conflictReasons.append(evaluation.reason)
            }
        }
        record(SafePatchCheck(
            kind: .nativeAndConflicts,
            passed: conflictReasons.isEmpty, isBlocker: true,
            reason: conflictReasons.first
                ?? (nativeSkipped.isEmpty
                    ? L("No native support or conflict blocks this proposal.")
                    : L("Some features are already natively supported or configured and need no change."))))

        // Build the recommendation for the proposal (data only), then
        // apply its steps to an in-memory copy of the snapshot
        // document. The copy is discarded after the simulation.
        let recommendation = LilaRecommendationBuilder.build(
            featureIDs: proposal.featureIDs, evaluations: evaluationMap,
            profile: profile, document: snapshot.document,
            layout: layout, regionMode: proposal.regionMode)
        var simulated = snapshot.document
        applySteps(recommendation.steps, to: &simulated, using: layout)

        // (e) Original → target diff, computed from the simulated
        // document against the snapshot (not from the steps, so the
        // diff shows what would actually change, including multi-key
        // capabilities and the eSIM pair).
        let diffs = diffs(between: snapshot, simulated: simulated, using: layout)

        // (f) Hardware-identity check.
        let hardwareTouches = diffs.filter { hardwareIdentityKeys.contains($0.key) }.map(\.key)
        let identityPreserved = simulated.preservesDeviceIdentity(of: snapshot.document)
        record(SafePatchCheck(
            kind: .hardwareIdentity,
            passed: hardwareTouches.isEmpty && identityPreserved, isBlocker: true,
            reason: !hardwareTouches.isEmpty
                ? L("This proposal touches a hardware-identity field. Staging it is refused.")
                : !identityPreserved
                ? L("This proposal changes a device-identity field. Staging it is refused.")
                : L("No hardware-identity field is touched.")))

        // (g) Backup and restore prerequisites.
        let hasTrustedBackup = backups.contains { $0.provenance.isTrustedForRestore }
        record(SafePatchCheck(
            kind: .backupPrerequisites,
            passed: hasTrustedBackup, isBlocker: false,
            reason: hasTrustedBackup
                ? L("A trusted backup exists for restore.")
                : L("No trusted backup exists yet. A pre-change restore point will be created before applying; a precise restore is only guaranteed for changes with a trusted original.")))

        // (h) Offline serialization: the simulated document must encode
        // and decode back to itself, and keep the device identity.
        var serializationOK = false
        var simulatedByteCount: Int?
        do {
            let data = try simulated.encoded()
            let decoded = try GestaltDocument(data: data)
            serializationOK = decoded.matches(simulated) && decoded.preservesDeviceIdentity(of: snapshot.document)
            simulatedByteCount = data.count
        } catch {
            serializationOK = false
        }
        record(SafePatchCheck(
            kind: .serialization, passed: serializationOK, isBlocker: true,
            reason: serializationOK
                ? L("The simulated document serializes and reads back correctly.")
                : L("The simulated document could not be serialized and verified.")))

        // (e) is reported as a check too: an empty diff means the
        // proposal would change nothing.
        record(SafePatchCheck(
            kind: .diff, passed: !diffs.isEmpty, isBlocker: false,
            reason: diffs.isEmpty
                ? L("This proposal would change nothing on this device.")
                : String(format: L("Would change %d fields"), diffs.count)))

        return finish(proposal: proposal, checks: checks, diffs: diffs, blockers: blockers,
                      warnings: warnings, hardwareIdentityTouches: hardwareTouches,
                      serializationOK: serializationOK, backupReady: hasTrustedBackup,
                      simulatedByteCount: simulatedByteCount)
    }

    // MARK: - Helpers

    private static func finish(
        proposal: SafePatchProposal, checks: [SafePatchCheck], diffs: [SafePatchDiff],
        blockers: [String], warnings: [String], hardwareIdentityTouches: [String],
        serializationOK: Bool, backupReady: Bool, simulatedByteCount: Int?
    ) -> SafePatchSimulation {
        // Effect states: a simulation only ever projects "staged". The
        // other three are confirmed only by real events after applying.
        // File write success is never presented as "feature definitely
        // effective".
        let effectStates: [SafePatchEffectState] = [
            SafePatchEffectState(
                effect: .staged,
                status: blockers.isEmpty ? .notReached : .unknown(reason: L("Blocked by a pre-check.")),
                note: L("Staged: the change is prepared for review, not yet written.")),
            SafePatchEffectState(
                effect: .fileWriteVerified,
                status: .notReached,
                note: L("File write verified: the written file read back as staged.")),
            SafePatchEffectState(
                effect: .restartConsistent,
                status: .notReached,
                note: L("Re-read consistent after restart: the value survived a device restart.")),
            SafePatchEffectState(
                effect: .functionVerified,
                status: .notReached,
                note: L("System function actually verified: the feature works on the device.")),
        ]
        return SafePatchSimulation(
            proposal: proposal, checks: checks, diffs: diffs,
            blockers: blockers, warnings: warnings,
            hardwareIdentityTouches: hardwareIdentityTouches,
            canProceed: blockers.isEmpty,
            serializationOK: serializationOK, backupReady: backupReady,
            effectStates: effectStates, simulatedByteCount: simulatedByteCount)
    }

    /// Applies recommendation steps to an in-memory document copy.
    /// SIMULATION ONLY: the copy is discarded after the simulation;
    /// this never touches the device file, the store, or
    /// DevicePlistWriter. Uses the same typed document setters as the
    /// real staging paths, so the simulated outcome matches what
    /// staging would produce.
    static func applySteps(_ steps: [PlanStep], to document: inout GestaltDocument,
                           using layout: MobileGestaltCacheLayout?) {
        for step in steps {
            switch step.kind {
            case .cacheExtraKey:
                if let capability = Capability.all.first(where: { $0.id == step.featureID }) {
                    for key in capability.keys {
                        document.set(capability.values?[key] ?? capability.enabled, for: key)
                    }
                } else if let key = step.key {
                    document.set(step.newValue.plistValue, for: key)
                }
            case .cacheDataSlot:
                switch step.featureID {
                case FeatureEligibilityEvaluator.esimFeatureID:
                    try? document.setCacheOptions(.enabled, using: layout)
                case FeatureEligibilityEvaluator.wapiFeatureID:
                    try? document.setWAPI(false, using: layout)
                default:
                    guard let key = step.key, case .bool(let value) = step.newValue else { continue }
                    try? document.setAdvAISlot(key, value: value, using: layout)
                }
            case .region:
                guard case .string(let code) = step.newValue else { continue }
                document.applyRegion(code: code, salesSuffix: step.salesSuffix)
            case .artwork:
                guard let key = step.key, let value = step.newValue.plistValue else { continue }
                _ = document.setArtwork(value, for: key)
            }
        }
    }

    /// Diffs the simulated document against the snapshot. For each
    /// field that differs, the original is the recorded original when
    /// one exists, the snapshot document's value (first-recorded
    /// value) when it does not, or `.absent` when the key did not
    /// exist. CacheData slots are compared through the typed
    /// accessors, never by raw offsets.
    private static func diffs(between snapshot: DocumentSnapshot,
                              simulated: GestaltDocument,
                              using layout: MobileGestaltCacheLayout?) -> [SafePatchDiff] {
        var rows: [SafePatchDiff] = []
        let before = snapshot.document.extra
        let after = simulated.extra
        for key in Set(before.keys).union(after.keys) {
            let oldValue = before[key]
            let newValue = after[key]
            switch (oldValue, newValue) {
            case (nil, nil): continue
            case (let a?, let b?) where GestaltDocument.valuesEqual(a, b): continue
            default: break
            }
            let (original, source): (ChangeValue, SafePatchOriginalSource)
            if let recorded = snapshot.originals[key] {
                original = ChangeValue.fromPlistValue(recorded.value) ?? .absent
                source = .recordedOriginal
            } else if let current = oldValue {
                original = ChangeValue.fromPlistValue(current) ?? .absent
                source = .firstRecordedValue
            } else {
                original = .absent
                source = .absent
            }
            guard let target = ChangeValue.fromPlistValue(newValue) else { continue }
            let capability = Capability.all.first { $0.keys.contains(key) }
            let risk = capability.flatMap { CapabilityEntry.entry(for: $0.id)?.riskLevel } ?? .low
            rows.append(SafePatchDiff(
                key: key,
                title: capability?.title ?? ModifiedValues.title(forKey: key),
                layer: .cacheExtra,
                original: original,
                target: target,
                originalSource: source,
                risk: risk))
        }

        // eSIM CacheData slots. The resolved layout is used explicitly
        // (never re-resolved from the document), so the diff reads the
        // same slots the simulation staged.
        if let originalFlags = snapshot.cachedOptionsOriginal,
           let simulatedFlags = try? DeviceCacheOptions.flags(in: simulated, using: layout) {
            if originalFlags.flags.greenTea != simulatedFlags.greenTea {
                rows.append(SafePatchDiff(
                    key: DeviceCacheOptions.greenTeaKey, title: "eSIM (green-tea)",
                    layer: .cacheData,
                    original: .bool(originalFlags.flags.greenTea),
                    target: .bool(simulatedFlags.greenTea),
                    originalSource: .recordedOriginal, risk: .medium))
            }
            if originalFlags.flags.notGreenTea != simulatedFlags.notGreenTea {
                rows.append(SafePatchDiff(
                    key: DeviceCacheOptions.notGreenTeaKey, title: "eSIM (not-green-tea)",
                    layer: .cacheData,
                    original: .bool(originalFlags.flags.notGreenTea),
                    target: .bool(simulatedFlags.notGreenTea),
                    originalSource: .recordedOriginal, risk: .medium))
            }
        }

        // WAPI CacheData slot. The recorded original's layout UUID must
        // match this snapshot's layout; otherwise the stored value
        // belongs to a different cache generation and is not compared.
        if let wapiOriginal = snapshot.wapiOriginal,
           wapiOriginal.layoutUUID == (snapshot.document.root["CacheUUID"] as? String ?? ""),
           let simulatedWAPI = try? DeviceCacheOptions.wapi(in: simulated, using: layout),
           wapiOriginal.enabled != simulatedWAPI {
            rows.append(SafePatchDiff(
                key: DeviceCacheOptions.wapiKey, title: "WAPI",
                layer: .cacheData,
                original: .bool(wapiOriginal.enabled), target: .bool(simulatedWAPI),
                originalSource: .recordedOriginal, risk: .low))
        }

        rows.sort { $0.key < $1.key }
        return rows
    }
}
