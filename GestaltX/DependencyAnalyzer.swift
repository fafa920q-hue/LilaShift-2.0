// SPDX-License-Identifier: GPL-3.0-only
// Dependency Analyzer (功能依赖分析器) — for a selected set of
// capabilities and presets, identifies dependencies, conflicts and
// duplicate modifications, and gives an overall verdict. Pure
// Foundation — no SwiftUI, no UIKit, no singletons, no global
// mutable state.
//
// The analyzer reuses what already exists instead of re-implementing
// it:
//   • `DependencyResolver` for the ordering and the layout /
//     region / baseline checks on the requested feature set;
//   • `FeatureEligibilityEvaluator` for the guard and model gates
//     on each capability (native-AI conflicts, unknown models);
//   • the written-key expansion the stage paths use (mirroring
//     `Capability.apply` and the eSIM / region / WAPI staging) for
//     the duplicate and value-conflict comparison, so the analysis
//     and staging never disagree about what a feature writes.
//
// It never writes to the MobileGestalt cache. Staging, if the user
// chooses it, goes through the existing stage paths only.
import Foundation

// MARK: - Findings

/// How severe a finding is. A blocker refuses staging (an
/// unsatisfied dependency or a value conflict). A warning is
/// something the user should know before staging (a duplicate, or
/// a conflict that already exists on the device). Information is
/// context (a dependency that is already satisfied).
enum DependencyFindingSeverity: String, Equatable, Sendable {
    case blocker
    case warning
    case info
}

/// One finding about one feature. `featureID` is the capability or
/// preset feature ID the finding belongs to (or "" for a finding
/// about the set as a whole, such as a cross-feature value
/// conflict). `code` is a stable machine-readable key used to
/// de-duplicate findings that two sources report about the same
/// thing.
struct DependencyFinding: Equatable, Identifiable, Sendable {
    var id: String { featureID + ":" + kind.rawValue + ":" + code }
    let featureID: String
    let kind: DependencyFindingKind
    let severity: DependencyFindingSeverity
    let code: String
    let message: String
}

/// What kind of relationship a finding describes.
enum DependencyFindingKind: String, Equatable, Sendable {
    case dependency
    case conflict
    case duplicate
}

/// The overall verdict for the selected set.
enum DependencyVerdict: String, Equatable, Sendable {
    case safeToStage
    case hasConflicts
    case missingPrerequisites
    case unknown

    var title: String {
        switch self {
        case .safeToStage: return L("Safe to stage")
        case .hasConflicts: return L("Has conflicts")
        case .missingPrerequisites: return L("Missing prerequisites")
        case .unknown: return L("Unknown")
        }
    }
}

/// The analysis result for one selection.
struct DependencyAnalysis: Equatable, Sendable {
    let verdict: DependencyVerdict
    let findings: [DependencyFinding]
    /// Findings grouped by feature ID, in the order the features
    /// were requested. The key "" holds findings about the set as
    /// a whole (cross-feature conflicts and duplicates).
    let perFeature: [String: [DependencyFinding]]
    let summary: String
}

// MARK: - Analyzer

/// Pure analysis over explicit inputs. `featureIDs` is the set the
/// user selected (one-tap's 9 items, the AI-only preset, the
/// eSIM+region preset, or individual capabilities). `snapshot` is
/// `nil` when the device has never been read: then the analysis is
/// `.unknown`, because dependencies cannot be checked without a
/// document.
enum DependencyAnalyzer {
    static func analyze(
        featureIDs: [String],
        profile: DeviceProfile,
        snapshot: DocumentSnapshot?,
        liveAIEnabled: Bool? = nil
    ) -> DependencyAnalysis {
        guard let snapshot else {
            return DependencyAnalysis(
                verdict: .unknown, findings: [],
                perFeature: [:],
                summary: L("No document has been read."))
        }
        var findings: [DependencyFinding] = []

        // 1. Ordering and the layout / region / baseline checks.
        // DependencyResolver.check reports the blockers for the
        // requested set (layout unresolved, region missing, no
        // native baseline); those are the missing-prerequisite
        // findings. Each blocker already carries the feature id it
        // belongs to.
        let blockers = DependencyResolver.check(
            featureIDs: featureIDs, profile: profile,
            document: snapshot.document, layout: profile.cacheLayout.value)
        for blocker in blockers {
            findings.append(DependencyFinding(
                featureID: blocker.featureID, kind: .dependency,
                severity: .blocker, code: blocker.code, message: blocker.reason))
        }

        // 2. The eligibility guard on each capability: the
        // native-AI guard conflict and the unknown-model /
        // unsupported gates. The eSIM and region features are not
        // run through the evaluator — the resolver already covers
        // their layout dependency, and running both would report
        // the same unresolvable layout twice.
        for featureID in featureIDs {
            guard ChinaUnlock.aiCapabilityIDs.contains(featureID)
                || Capability.all.map(\.id).contains(featureID) else { continue }
            let evaluation = FeatureEligibilityEvaluator.evaluate(
                featureID: featureID, profile: profile, document: snapshot,
                layout: profile.cacheLayout.value, liveAIEnabled: liveAIEnabled,
                userConfirmedUnverifiedCombination: false)
            switch evaluation.eligibility {
            case .conflict:
                findings.append(DependencyFinding(
                    featureID: featureID, kind: .conflict, severity: .blocker,
                    code: "native-conflict",
                    message: evaluation.reason))
            case .unknown:
                findings.append(DependencyFinding(
                    featureID: featureID, kind: .dependency, severity: .blocker,
                    code: "unknown",
                    message: evaluation.reason))
            case .unsupported:
                findings.append(DependencyFinding(
                    featureID: featureID, kind: .dependency, severity: .blocker,
                    code: "unsupported",
                    message: evaluation.reason))
            case .eligibleToEnable, .alreadyConfigured, .nativeSupported:
                break
            }
        }

        // 3. Catalog conflicts inside the selected set: siriOnDevice
        // conflicts with every AI capability, and vice versa.
        for featureID in featureIDs {
            guard let entry = CapabilityEntry.entry(for: featureID) else { continue }
            for conflictID in entry.conflicts where featureIDs.contains(conflictID) {
                findings.append(DependencyFinding(
                    featureID: featureID, kind: .conflict, severity: .blocker,
                    code: "catalog-conflict",
                    message: String(format: L("%@ conflicts with %@"), featureID, conflictID)))
            }
        }

        // 4. Written-key comparison: duplicates (same key, same
        // value — harmless but redundant) and value conflicts (same
        // key, different values — staging would overwrite one of
        // them). The written keys come from the same expansion
        // SafePatch uses, so the analysis and the simulation agree.
        let writtenKeys = writtenKeys(for: featureIDs)
        findings.append(contentsOf: keyFindings(writtenKeys))

        findings = deduplicate(findings)

        let verdict: DependencyVerdict
        if findings.contains(where: { $0.kind == .conflict && $0.severity == .blocker }) {
            verdict = .hasConflicts
        } else if findings.contains(where: { $0.kind == .dependency && $0.severity == .blocker }) {
            verdict = .missingPrerequisites
        } else {
            verdict = .safeToStage
        }
        let summary = summarize(verdict: verdict, findings: findings, featureCount: featureIDs.count)
        var perFeature: [String: [DependencyFinding]] = [:]
        for featureID in featureIDs {
            perFeature[featureID] = findings.filter { $0.featureID == featureID }
        }
        perFeature[""] = findings.filter { $0.featureID == "" }
        return DependencyAnalysis(verdict: verdict, findings: findings,
                                  perFeature: perFeature, summary: summary)
    }

    // MARK: - Written keys

    /// The keys each selected feature would write, with the value
    /// each would write — the same expansion the stage paths use,
    /// so the analysis never disagrees with staging. Keys are
    /// namespaced by layer so a CacheData slot and a CacheExtra key
    /// with the same name are never confused.
    private static func writtenKeys(for featureIDs: [String]) -> [(featureID: String, key: String, layer: ChangeLayer, value: ChangeValue)] {
        var keys: [(featureID: String, key: String, layer: ChangeLayer, value: ChangeValue)] = []
        for featureID in featureIDs {
            switch featureID {
            case FeatureEligibilityEvaluator.esimFeatureID:
                keys.append((featureID, DeviceCacheOptions.greenTeaKey, .cacheData, .bool(false)))
                keys.append((featureID, DeviceCacheOptions.notGreenTeaKey, .cacheData, .bool(true)))
            case FeatureEligibilityEvaluator.regionCodeFeatureID:
                keys.append((featureID, GestaltKeys.regionCode, .cacheExtra, .string("LL")))
            case FeatureEligibilityEvaluator.wapiFeatureID:
                keys.append((featureID, DeviceCacheOptions.wapiKey, .cacheData, .bool(false)))
            default:
                keys.append(contentsOf: capabilityKeys(featureID, featureID: featureID))
            }
        }
        return keys
    }

    /// The keys one capability would write: each key in the
    /// capability's key list, with the capability's enabled value
    /// (or its per-key override). Mirrors `Capability.apply`.
    private static func capabilityKeys(
        _ capabilityID: String, featureID: String
    ) -> [(featureID: String, key: String, layer: ChangeLayer, value: ChangeValue)] {
        guard let capability = Capability.all.first(where: { $0.id == capabilityID }),
              !capability.keys.isEmpty else { return [] }
        return capability.keys.map { key in
            let value = ChangeValue.fromPlistValue(capability.values?[key] ?? capability.enabled) ?? .absent
            // Every capability key is written through
            // `document.set(...)`, which writes CacheExtra.
            return (featureID, key, ChangeLayer.cacheExtra, value)
        }
    }

    /// Duplicates and value conflicts among the written keys. A
    /// duplicate is the same key written to the same value by two
    /// features (warning: redundant). A value conflict is the same
    /// key written to different values (blocker: one would
    /// overwrite the other). Both are reported once per key, with
    /// the features involved named in the message.
    private static func keyFindings(
        _ writtenKeys: [(featureID: String, key: String, layer: ChangeLayer, value: ChangeValue)]
    ) -> [DependencyFinding] {
        var findings: [DependencyFinding] = []
        var byKey: [String: [(featureID: String, value: ChangeValue)]] = [:]
        for entry in writtenKeys {
            let namespaced = entry.layer.rawValue + ":" + entry.key
            byKey[namespaced, default: []].append((entry.featureID, entry.value))
        }
        for (namespaced, entries) in byKey where entries.count > 1 {
            let key = namespaced.split(separator: ":", maxSplits: 1).last.map(String.init) ?? namespaced
            let distinctValues = Set(entries.map(\.value))
            let featureNames = Array(Set(entries.map(\.featureID))).sorted().joined(separator: ", ")
            if distinctValues.count > 1 {
                findings.append(DependencyFinding(
                    featureID: "", kind: .conflict, severity: .blocker,
                    code: "value-conflict:" + namespaced,
                    message: String(format: L("%@ is set to different values by %@"), key, featureNames)))
            } else {
                findings.append(DependencyFinding(
                    featureID: "", kind: .duplicate, severity: .warning,
                    code: "duplicate:" + namespaced,
                    message: String(format: L("%@ is changed to the same value by %@"), key, featureNames)))
            }
        }
        return findings
    }

    // MARK: - Helpers

    /// Drops findings that two sources reported about the same
    /// thing (same feature, same kind, same code), keeping the
    /// first.
    private static func deduplicate(_ findings: [DependencyFinding]) -> [DependencyFinding] {
        var seen: Set<String> = []
        return findings.filter { finding in
            let key = finding.featureID + ":" + finding.kind.rawValue + ":" + finding.code
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private static func summarize(
        verdict: DependencyVerdict, findings: [DependencyFinding], featureCount: Int
    ) -> String {
        let blockers = findings.filter { $0.severity == .blocker }.count
        let warnings = findings.filter { $0.severity == .warning }.count
        switch verdict {
        case .safeToStage:
            if warnings > 0 {
                return String(format: L("Safe to stage: %d features, %d warnings."), featureCount, warnings)
            }
            return String(format: L("Safe to stage: %d features, no findings."), featureCount)
        case .hasConflicts:
            return String(format: L("%d conflicts block staging."), blockers)
        case .missingPrerequisites:
            return String(format: L("%d prerequisites are missing."), blockers)
        case .unknown:
            return L("No document has been read.")
        }
    }
}
