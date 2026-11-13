// SPDX-License-Identifier: GPL-3.0-only
// Preset Catalog (智能预设数据库) — a structured catalog of every
// preset the app offers, with Chinese names, descriptions, applicable
// scope, minimum system, risk level with a specific reason, restore
// method, and traceable evidence. Pure Foundation — no SwiftUI, no
// UIKit, no singletons, no global mutable state.
//
// The catalog is DATA, not UI: a `PresetEntry` model plus search,
// filter, favorites and custom-combination logic that never touches
// the UI. It builds on what already exists instead of duplicating
// it:
//   • `CapabilityEntry` for the per-capability titles, keys,
//     dependencies, conflicts, risk level, effect method,
//     verification/restore steps and source files;
//   • `CompatibilityEntry` for the verified product-type list;
//   • `FeatureEligibilityEvaluator` (via the caller's evaluations)
//     for per-device native support — the catalog itself never
//     claims a feature is native on a device it has not seen;
//   • `DependencyAnalyzer` and `SafePatch` for checking custom
//     combinations.
//
// Honesty rules that apply to the whole layer:
// - Every claim is traceable: a risk level or an applicability
//   statement without an evidence source is not allowed. Where the
//   evidence is missing, the entry says so explicitly — never a
//   guessed claim, never "all models supported".
// - A hypothesis is labelled a hypothesis (`.hypothesis`), never
//   presented as an observed fact.
// - "First-recorded value" is never called the factory original.
// - No string here claims "100% safe", "fully supported", or
//   "guaranteed".
// - The catalog never stages or writes anything. A custom
//   combination is a PLAN: it is checked, never applied by this
//   layer — applying stays with the existing stage paths, and the
//   UI must say the combination is not connected.
import Foundation

// MARK: - Categories

/// Preset categories for search and filtering. The five
/// `CapabilityCategory` cases are kept; `esim` and `region` cover
/// the virtual entries, and `group` covers the preset groups
/// (one-tap, AI-only, eSIM+region).
enum PresetCategory: String, CaseIterable, Equatable, Sendable, Identifiable {
    case esim
    case region
    case intelligence
    case display
    case device
    case ipad
    case advanced
    case group

    var id: String { rawValue }

    var title: String {
        switch self {
        case .esim: return L("eSIM")
        case .region: return L("Region")
        case .intelligence: return L("Intelligence")
        case .display: return L("Display")
        case .device: return L("Device")
        case .ipad: return L("iPad")
        case .advanced: return L("Advanced")
        case .group: return L("Group")
        }
    }

    /// The `CapabilityCategory` this preset category corresponds to,
    /// or `nil` for the categories `Capability` does not have.
    var capabilityCategory: CapabilityCategory? {
        switch self {
        case .intelligence: return .intelligence
        case .display: return .display
        case .device: return .device
        case .ipad: return .ipad
        case .advanced: return .advanced
        case .esim, .region, .group: return nil
        }
    }
}

/// Whether a catalog entry is a single capability, a virtual feature
/// (eSIM, region code, WAPI, model number — not a `Capability`), or
/// a preset group (one-tap, AI-only, eSIM+region).
enum PresetEntryKind: String, Equatable, Sendable {
    case capability
    case virtual
    case group
}

// MARK: - Scope and minimum system

/// Which devices a preset is known to apply to. An explicit list is
/// the only "verified" scope; everything else is a stated condition
/// or an explicit unknown — never "all models".
enum PresetScope: Equatable, Sendable {
    /// An explicit list of verified product types.
    case verifiedModels([String])
    /// Devices whose hardware natively supports Apple Intelligence
    /// (the exact-match list in `DeviceAIEligibility`).
    case nativeAIHardware
    /// China-market devices (region code CH) with a resolvable cache
    /// layout — a condition, not a model list.
    case chinaMarketDevices
    /// iPad hardware.
    case ipadHardware
    /// No verified scope: `reason` says what is unknown.
    case unknown(reason: String)

    /// Short user-facing label for the scope.
    var label: String {
        switch self {
        case .verifiedModels(let models):
            return String(format: L("%d verified models"), models.count)
        case .nativeAIHardware:
            return L("Native Apple Intelligence hardware")
        case .chinaMarketDevices:
            return L("China-market devices")
        case .ipadHardware:
            return L("iPad hardware")
        case .unknown:
            return L("Not verified")
        }
    }
}

/// The minimum system version a preset is known to need, or an
/// explicit unknown. `.known` is used only where there is evidence
/// (an effect hint stating a version, or the app's supported range
/// for the iOS 27 cache features).
enum PresetMinSystem: Equatable, Sendable {
    case known(String)
    case unknown(reason: String)

    var label: String {
        switch self {
        case .known(let version): return version
        case .unknown: return L("Not verified")
        }
    }
}

// MARK: - Evidence

/// What kind of evidence backs a claim. A hypothesis is labelled as
/// one — it is never presented as an observed fact.
enum PresetEvidenceKind: String, Equatable, Sendable {
    case observed
    case upstream
    case hypothesis
    case code

    var title: String {
        switch self {
        case .observed: return L("Observed")
        case .upstream: return L("Upstream")
        case .hypothesis: return L("Hypothesis")
        case .code: return L("Source code")
        }
    }
}

/// One traceable evidence item. `text` is Chinese; `kind` says what
/// the text is (an observation, an upstream reference, a hypothesis,
/// or a source-code reference).
struct PresetEvidence: Equatable, Sendable {
    let text: String
    let kind: PresetEvidenceKind
}

// MARK: - Catalog entry

/// One catalog entry: a capability, a virtual feature, or a preset
/// group. All display content is stored as data here — the Chinese
/// name, description, scope note, risk reason, restore method and
/// evidence are plain Chinese strings, not localized keys, because
/// they are catalog content written in Chinese (the same way
/// `Capability.detail` is English content stored plainly).
struct PresetEntry: Equatable, Sendable, Identifiable {
    var id: String { featureID }
    let featureID: String
    let kind: PresetEntryKind
    let category: PresetCategory
    /// Chinese name, for example "音频智能".
    let chineseName: String
    /// English title, from the underlying `CapabilityEntry` (or the
    /// virtual/group definition).
    let englishTitle: String
    /// What it does, what it does NOT change, what happens after a
    /// restart, and the known risks — in Chinese, specific to this
    /// entry.
    let chineseDescription: String
    /// Which devices it is known to apply to.
    let scope: PresetScope
    /// Chinese explanation of the scope.
    let scopeNote: String
    /// Minimum system version, or an explicit unknown.
    let minSystem: PresetMinSystem
    /// Risk level, from the underlying `CapabilityEntry` (caution →
    /// high, Intelligence → medium, otherwise low).
    let riskLevel: CapabilityRiskLevel
    /// The specific risk, in Chinese — the mechanism, not a generic
    /// "this may be risky".
    let riskReason: String
    /// How to restore it, in Chinese, and whether a trusted original
    /// is required.
    let restoreMethod: String
    /// Traceable evidence. Never empty: at minimum the source-code
    /// references for the key mapping.
    let evidence: [PresetEvidence]
    /// Member feature ids, for groups only; empty otherwise.
    let memberIDs: [String]
    /// The underlying keys (CacheExtra keys, or CacheData slot keys).
    let keys: [String]
    /// The underlying key or slot, in words (from the underlying
    /// `CapabilityEntry`).
    let underlyingKeyOrSlot: String
    /// Feature ids this entry depends on (from the underlying
    /// `CapabilityEntry`).
    let dependencies: [String]
    /// Feature ids this entry conflicts with (from the underlying
    /// `CapabilityEntry`).
    let conflicts: [String]
}

// MARK: - Shared content constants

/// Chinese content shared by many entries. These are facts that are
/// the same for a whole class of entries (for example, the standard
/// restore wording for capabilities); the per-entry risk reason and
/// description are always entry-specific.
enum PresetSharedContent {
    /// Reason used when no verified per-entry scope exists.
    static let unknownScopeReason =
        "无已验证的逐项适用机型表；此项不依赖特定机型，但各机型与系统构建上的实际生效情况未经逐一验证。"
    /// Reason used when no verified per-entry minimum system exists.
    static let unknownMinSystemReason =
        "无单独验证的最低系统版本；应用本身要求 iOS 26，核心读写需要 iOS 27。"
    /// Standard restore wording for single capabilities.
    static let restoreCapability =
        "在预设列表中选择「恢复原值」；无记录原值时移除新增的键，不填猜测值。"
    /// Standard restore wording for preset groups.
    static let restoreGroup =
        "按成员逐项还原（见各成员的恢复方式）；整组还原走一键解锁的还原路径。"
    /// Standard "does not change hardware" clause, reused from the
    /// existing localized string (capability flags cannot add missing
    /// hardware).
    static let noHardwareChange = "只改功能标记，不增加硬件。"

    /// Evidence: the key mapping is cross-checked against MGKeys,
    /// Nugget and mond (see the `Capabilities.swift` header).
    static let keyMappingEvidence = PresetEvidence(
        text: "键映射对照 MGKeys、Nugget、mond（见 GestaltX/Capabilities.swift）。",
        kind: .code)
    /// Evidence: the region value was rebuilt at boot on 17 Pro Max.
    static let regionRevertedEvidence = PresetEvidence(
        text: "2026-11-13 在 iPhone 17 Pro Max（A3527）上观察到：写入并验证成功，重启后地区恢复为 CH。",
        kind: .observed)
    /// Evidence: the cache-discard hypothesis, labelled as one.
    static let cacheDiscardHypothesis = PresetEvidence(
        text: "监管型号与硬件对不上可能导致系统在启动时丢弃整个缓存——假设，尚未证实；上游 GestaltX #128 的面容 ID 修复方向与此一致。",
        kind: .hypothesis)
    /// Evidence: the #178 CacheExtra/Slot conflict on Air.
    static let audioSlotEvidence = PresetEvidence(
        text: "2026-11-13 在 iPhone Air（A3518）上观察到：CacheExtra 音频智能键已暂存为 1，CacheData 插槽 #178 读数为原生 0。",
        kind: .observed)
    /// Evidence: the #178 slot unresolvable on 17 Pro Max.
    static let audioSlotUnresolvableEvidence = PresetEvidence(
        text: "2026-11-13 在 iPhone 17 Pro Max（A3527）上：#178 插槽无法解析，守卫拒绝自动暂存。",
        kind: .observed)
    /// Evidence: the eSIM slots resolved dynamically on 17 Pro Max.
    static let esimSlotsEvidence = PresetEvidence(
        text: "2026-11-13 在 iPhone 17 Pro Max（A3527）上：eSIM 槽位实际解析为 382/505（动态解析，非兜底 383/506）。",
        kind: .observed)
    /// Evidence: changing hardware-identity fields breaks Face ID.
    static let faceIDUpstreamEvidence = PresetEvidence(
        text: "上游 GestaltX #128：改硬件身份字段会破坏面容 ID。",
        kind: .upstream)
    /// Evidence: siriOnDevice is kept by design (upstream #102).
    static let siriKeepUpstreamEvidence = PresetEvidence(
        text: "上游 GestaltX #102：保留设备专属的 Siri 值。",
        kind: .upstream)
}

// MARK: - Catalog

/// The smart preset database. Entries are built from the existing
/// `CapabilityEntry` catalog (titles, keys, dependencies, conflicts,
/// risk level, effect method, sources) plus the hand-written Chinese
/// content in `chineseContent` — one table row per entry. An entry
/// with no Chinese content row is dropped by the builder, and the
/// catalog tests assert the exact entry count, so a missing row
/// fails loudly instead of shipping an entry without a Chinese
/// description.
enum PresetCatalog {
    static let version = 1
    static let catalogDate = LilaEngine.catalogDate

    static let all: [PresetEntry] = build()

    static func entry(for id: String) -> PresetEntry? {
        all.first { $0.featureID == id }
    }

    /// The three preset groups, in display order.
    static var groups: [PresetEntry] {
        all.filter { $0.kind == .group }
    }

    /// Builds the catalog: the 35 `CapabilityEntry` entries (33
    /// capabilities + eSIM + region code), the WAPI and model-number
    /// virtual entries, and the three preset groups.
    private static func build() -> [PresetEntry] {
        var entries: [PresetEntry] = []
        for capabilityEntry in CapabilityEntry.all {
            guard let content = mergedChineseContent[capabilityEntry.id] else { continue }
            entries.append(entry(from: capabilityEntry, content: content))
        }
        entries.append(wapiEntry)
        entries.append(modelNumberEntry)
        entries.append(contentsOf: groupEntries)
        return entries
    }

    private static func entry(from capabilityEntry: CapabilityEntry, content: PresetContent) -> PresetEntry {
        let category: PresetCategory
        switch capabilityEntry.id {
        case FeatureEligibilityEvaluator.esimFeatureID:
            category = .device
        case FeatureEligibilityEvaluator.regionCodeFeatureID:
            category = .intelligence
        default:
            switch capabilityEntry.category {
            case .display: category = .display
            case .device: category = .device
            case .ipad: category = .ipad
            case .intelligence: category = .intelligence
            case .advanced: category = .advanced
            }
        }
        return PresetEntry(
            featureID: capabilityEntry.id,
            kind: capabilityEntry.id == FeatureEligibilityEvaluator.esimFeatureID
                || capabilityEntry.id == FeatureEligibilityEvaluator.regionCodeFeatureID
                ? .virtual : .capability,
            category: category,
            chineseName: content.chineseName,
            englishTitle: capabilityEntry.title,
            chineseDescription: content.chineseDescription,
            scope: content.scope,
            scopeNote: content.scopeNote,
            minSystem: content.minSystem,
            riskLevel: capabilityEntry.riskLevel,
            riskReason: content.riskReason,
            restoreMethod: content.restoreMethod,
            evidence: content.evidence + capabilityEntry.sources.map {
                PresetEvidence(text: $0, kind: .code)
            },
            memberIDs: [],
            keys: capabilityEntry.keys,
            underlyingKeyOrSlot: capabilityEntry.underlyingKeyOrSlot,
            dependencies: capabilityEntry.dependencies,
            conflicts: capabilityEntry.conflicts)
    }

    /// The WAPI virtual entry: staging sets the CacheData WAPI slot
    /// to false. Not a `Capability` — it has no CacheExtra keys.
    private static var wapiEntry: PresetEntry {
        PresetEntry(
            featureID: FeatureEligibilityEvaluator.wapiFeatureID,
            kind: .virtual,
            category: .device,
            chineseName: "WAPI",
            englishTitle: "WAPI",
            chineseDescription: "关闭 WAPI（将 CacheData WAPI 插槽暂存为 false）。不改变 Wi-Fi 硬件；关闭后可显示为 Wi-Fi，部分联网选项可能随之变化，重启后生效。",
            scope: .unknown(reason: "WAPI 插槽的存在取决于缓存布局，各机型未经逐一验证。"),
            scopeNote: "WAPI 插槽是否存在取决于本机缓存布局；布局无法解析时适用情况未知。",
            minSystem: .unknown(reason: PresetSharedContent.unknownMinSystemReason),
            riskLevel: .medium,
            riskReason: "只改 WAPI 缓存插槽；不改变 Wi-Fi 硬件，重启后生效情况未经逐一验证。",
            restoreMethod: PresetSharedContent.restoreCapability,
            evidence: [PresetEvidence(text: "GestaltX/DeviceCacheOptions.swift", kind: .code)],
            memberIDs: [],
            keys: [DeviceCacheOptions.wapiKey],
            underlyingKeyOrSlot: "WAPI CacheData slot (resolved from the device layout)",
            dependencies: [],
            conflicts: [])
    }

    /// The model-number virtual entry: the regulatory model (A
    /// number). One-tap never stages it; it is offered only through
    /// the manual model picker and the Revert path, guarded by
    /// `preservesDeviceIdentity` at commit.
    private static var modelNumberEntry: PresetEntry {
        PresetEntry(
            featureID: "modelNumber",
            kind: .virtual,
            category: .intelligence,
            chineseName: "监管型号",
            englishTitle: "Model Number",
            chineseDescription: "更改监管型号（A 编号）。此项只在手动模式中使用，一键解锁不改监管型号。改动监管型号可能导致系统在启动时丢弃整个缓存。",
            scope: .verifiedModels(CompatibilityEntry.productTypes),
            scopeNote: "仅限有已验证对照表的机型（iPhone 14,7–19,8，共 26 个产品类型）；表外机型未知，绝不推测。",
            minSystem: .unknown(reason: PresetSharedContent.unknownMinSystemReason),
            riskLevel: .high,
            riskReason: "监管型号与硬件对不上可能导致系统在启动时丢弃整个缓存；改硬件身份字段会破坏面容 ID（上游 #128）。",
            restoreMethod: "仅通过「恢复原值」还原记录的监管型号；切勿手动填一个未验证的型号。",
            evidence: [PresetSharedContent.faceIDUpstreamEvidence,
                       PresetSharedContent.cacheDiscardHypothesis,
                       PresetEvidence(text: "GestaltX/USRegulatoryModelMapping.swift", kind: .code)],
            memberIDs: [],
            keys: [GestaltKeys.modelNumber],
            underlyingKeyOrSlot: GestaltKeys.modelNumber,
            dependencies: [],
            conflicts: [])
    }

    /// The three preset groups. A group is a named set of members;
    /// it stages nothing by itself — the existing stage paths own
    /// staging, and a group entry only describes the set.
    private static var groupEntries: [PresetEntry] {
        [
            PresetEntry(
                featureID: "preset.oneTap",
                kind: .group,
                category: .group,
                chineseName: "一键解锁（中国）",
                englishTitle: "China Unlock (One-Tap)",
                chineseDescription: "为国行 eSIM 设备一键暂存 9 项：2 个 eSIM 缓存标记、地区码 LL、6 个 Apple 智能键。不改监管型号与销售地区。siriOnDevice 刻意保留原值。重启后须重新读取验收；系统可能在重启时还原地区值。",
                scope: .unknown(reason: "组合包含不同适用范围的项目：eSIM 仅限中国大陆市场设备，AI 功能依赖原生硬件或地区 LL。"),
                scopeNote: "eSIM 仅限中国大陆市场设备（地区码 CH）；AI 功能依赖原生硬件或地区 LL；地区码暂存不依赖机型。",
                minSystem: .known("iOS 27"),
                riskLevel: .high,
                riskReason: "组合内含高风险项：地区值可能在重启后还原（已在 iPhone 17 Pro Max A3527 上观察到），音频智能在原生 AI 硬件上有插槽冲突。",
                restoreMethod: PresetSharedContent.restoreGroup,
                evidence: [PresetSharedContent.regionRevertedEvidence,
                           PresetSharedContent.audioSlotEvidence,
                           PresetSharedContent.esimSlotsEvidence,
                           PresetEvidence(text: "GestaltX/Capabilities.swift（9 项定义）", kind: .code)],
                memberIDs: [FeatureEligibilityEvaluator.esimFeatureID,
                            FeatureEligibilityEvaluator.regionCodeFeatureID]
                    + ChinaUnlock.aiCapabilityIDs,
                keys: [],
                underlyingKeyOrSlot: "eSIM CacheData slots + region code + 6 AI CacheExtra keys",
                dependencies: [],
                conflicts: []),
            PresetEntry(
                featureID: "preset.aiOnly",
                kind: .group,
                category: .group,
                chineseName: "仅开启 AI",
                englishTitle: "AI Only",
                chineseDescription: "只暂存 6 个 Apple 智能键，不动 eSIM 与地区。注意：AI 功能依赖地区为 LL；单独使用此预设而不改地区时，依赖分析会报告缺少地区前置条件。",
                scope: .nativeAIHardware,
                scopeNote: "原生支持 Apple 智能的机型可直接使用；其他机型须暂存开启，且地区须为 LL。",
                minSystem: .known("iOS 27"),
                riskLevel: .medium,
                riskReason: "仅改 6 个 AI 能力标记；实际可用还取决于机型、地区与 Apple 服务器；单独使用时须先把地区改为 LL。",
                restoreMethod: PresetSharedContent.restoreGroup,
                evidence: [PresetSharedContent.audioSlotEvidence,
                           PresetEvidence(text: "GestaltX/Capabilities.swift（AI 预设）", kind: .code)],
                memberIDs: ChinaUnlock.aiCapabilityIDs,
                keys: [],
                underlyingKeyOrSlot: "6 AI CacheExtra keys",
                dependencies: [FeatureEligibilityEvaluator.regionCodeFeatureID],
                conflicts: ["siriOnDevice"]),
            PresetEntry(
                featureID: "preset.esimRegion",
                kind: .group,
                category: .group,
                chineseName: "eSIM 与地区",
                englishTitle: "eSIM & Region",
                chineseDescription: "只暂存 2 个 eSIM 缓存标记与地区码 LL，不动 AI。适用于只想开 eSIM 与改地区的用户。",
                scope: .chinaMarketDevices,
                scopeNote: "仅中国大陆市场设备（地区码 CH）且缓存布局可解析时适用。",
                minSystem: .known("iOS 27"),
                riskLevel: .medium,
                riskReason: "地区值可能在重启后还原（已在 iPhone 17 Pro Max A3527 上观察到）；eSIM 标记不证明 eSIM 硬件存在。",
                restoreMethod: PresetSharedContent.restoreGroup,
                evidence: [PresetSharedContent.regionRevertedEvidence,
                           PresetSharedContent.esimSlotsEvidence,
                           PresetEvidence(text: "GestaltX/Capabilities.swift（eSIM 与地区预设）", kind: .code)],
                memberIDs: [FeatureEligibilityEvaluator.esimFeatureID,
                            FeatureEligibilityEvaluator.regionCodeFeatureID],
                keys: [],
                underlyingKeyOrSlot: "eSIM CacheData slots + region code",
                dependencies: [],
                conflicts: []),
        ]
    }
}

// MARK: - Chinese content

/// Hand-written Chinese content for one catalog entry. `scope`,
/// `minSystem` and `restoreMethod` have honest defaults (unknown
/// scope, unknown minimum, standard capability restore); the name,
/// description and risk reason are always entry-specific.
private struct PresetContent {
    let chineseName: String
    let chineseDescription: String
    var scope: PresetScope = .unknown(reason: PresetSharedContent.unknownScopeReason)
    var scopeNote: String = "各机型与系统构建上的实际生效情况未经逐一验证。"
    var minSystem: PresetMinSystem = .unknown(reason: PresetSharedContent.unknownMinSystemReason)
    let riskReason: String
    var restoreMethod: String = PresetSharedContent.restoreCapability
    var evidence: [PresetEvidence] = []
}

extension PresetCatalog {
    /// Hand-written Chinese content, one row per catalog entry. The
    /// description translates the entry's own detail and effect hint
    /// and adds what it does NOT change; the risk reason names the
    /// specific mechanism. Entries not listed here are dropped by
    /// the builder (and the count test fails), so the table must
    /// cover every `CapabilityEntry` id.
    static let chineseContent: [String: PresetContent] = [
        // MARK: Virtual entries
        "esim": PresetContent(
            chineseName: "eSIM",
            chineseDescription: "启用或关闭 eSIM 相关系统选项：green-tea 改为 false、not-green-tea 改为 true。暂存只改 eSIM 缓存标记，不证明 eSIM 硬件存在。布局无法解析时整组拒绝暂存。",
            scope: .chinaMarketDevices,
            scopeNote: "仅中国大陆市场设备（地区码 CH）且缓存布局可解析时适用；与具体机型无关。",
            minSystem: .known("iOS 27"),
            riskReason: "只改 eSIM 缓存标记，不证明 eSIM 硬件存在；布局无法解析时整组拒绝暂存。",
            evidence: [PresetSharedContent.esimSlotsEvidence]),
        "regionCode": PresetContent(
            chineseName: "地区码",
            chineseDescription: "为受地区限制的功能设置设备地区码（一键解锁暂存为 LL）。更改地区后需要重新启动设备。系统可能在重启时重建缓存的地区值，而不是保留暂存值。",
            scope: .unknown(reason: "各机型与系统构建上的实际生效情况未经逐一验证。"),
            scopeNote: "地区码暂存不依赖机型；已在 iPhone Air（A3518）上观察到暂存生效，在 iPhone 17 Pro Max（A3527）上观察到重启后还原。其他机型未经验证。",
            minSystem: .known("iOS 27"),
            riskReason: "系统可能在重启时重建缓存的地区值，而不是保留暂存值（已在 iPhone 17 Pro Max A3527 上观察到）。",
            evidence: [PresetSharedContent.regionRevertedEvidence,
                       PresetSharedContent.cacheDiscardHypothesis]),
        // MARK: Apple Intelligence
        "ai": PresetContent(
            chineseName: "Apple 智能",
            chineseDescription: "启用 Apple 智能生成式模型。需要重新启动设备。Apple 智能还取决于机型与地区（须为 LL）。只改能力标记，不增加生成式模型硬件。",
            scope: .nativeAIHardware,
            scopeNote: "原生支持 Apple 智能的机型可直接使用；其他机型须暂存开启，且地区须为 LL。",
            minSystem: .known("iOS 27"),
            riskReason: "仅改 Apple 智能能力标记；实际可用还取决于机型、地区（须为 LL）与 Apple 服务器，标记本身不保证功能可用。",
            evidence: [PresetSharedContent.keyMappingEvidence]),
        "siriOnDevice": PresetContent(
            chineseName: "设备端 Siri",
            chineseDescription: "在设备上运行 Siri 处理。此项使用设备专属的能力类型；改动可能影响 Apple 智能 Siri 界面，请保留当前值或恢复记录的原始值。一键解锁刻意保留此项，不参与暂存。",
            scope: .unknown(reason: "此项仅保留，不参与暂存；适用范围无意义。"),
            scopeNote: "此项仅保留原值，不参与任何暂存。",
            riskReason: "此项使用设备专属的 Siri 能力类型；强制改值可能使 Apple 智能 Siri 界面还原（上游 #102），因此一键解锁刻意保留原值。",
            evidence: [PresetSharedContent.siriKeepUpstreamEvidence]),
        "audioIntelligence": PresetContent(
            chineseName: "音频智能",
            chineseDescription: "声明 iOS 27 音频智能能力。需要重新启动设备。Apple 智能还取决于机型与地区。具体入口取决于机型与系统版本。此项暂存 CacheExtra 键；CacheData 插槽是另一个独立的值。",
            scope: .nativeAIHardware,
            scopeNote: "原生支持 Apple 智能的机型可直接使用；其他机型须暂存开启，且地区须为 LL。",
            minSystem: .known("iOS 27"),
            riskReason: "CacheExtra 键与 CacheData 插槽是两个独立的值：在原生 AI 硬件上插槽原生为 0，单独暂存 CacheExtra 键的安全性未经验证。",
            evidence: [PresetSharedContent.audioSlotEvidence,
                       PresetSharedContent.audioSlotUnresolvableEvidence]),
        "personalTranslator": PresetContent(
            chineseName: "个人翻译",
            chineseDescription: "声明个人翻译能力。需要重新启动设备。Apple 智能还取决于机型与地区。此项暂存 CacheExtra 键；CacheData 插槽是另一个独立的值。",
            scope: .nativeAIHardware,
            scopeNote: "原生支持 Apple 智能的机型可直接使用；其他机型须暂存开启，且地区须为 LL。",
            minSystem: .known("iOS 27"),
            riskReason: "与音频智能相同：CacheExtra 键与 CacheData 插槽是两个独立的值；插槽无法解析时守卫会拒绝暂存。",
            evidence: [PresetEvidence(text: "GestaltX/DeviceAIEligibility.swift（原生 AdvAI 插槽基线）", kind: .code)]),
        "photosCleanUp": PresetContent(
            chineseName: "照片清理",
            chineseDescription: "声明照片清理（Clean Up）能力。需要重新启动设备。Apple 智能还取决于机型与地区。实际效果取决于应用与系统支持。",
            scope: .nativeAIHardware,
            scopeNote: "原生支持 Apple 智能的机型可直接使用；其他机型须暂存开启，且地区须为 LL。",
            minSystem: .known("iOS 27"),
            riskReason: "仅改照片清理能力标记；实际可用取决于机型、地区与应用支持。",
            evidence: [PresetSharedContent.keyMappingEvidence]),
        "handwritingSynthesis": PresetContent(
            chineseName: "手写合成",
            chineseDescription: "声明手写合成模型能力。需要重新启动设备。Apple 智能还取决于机型与地区。实际效果取决于应用与系统支持。",
            scope: .nativeAIHardware,
            scopeNote: "原生支持 Apple 智能的机型可直接使用；其他机型须暂存开启，且地区须为 LL。",
            minSystem: .known("iOS 27"),
            riskReason: "仅改手写合成模型能力标记；实际可用取决于机型、地区与应用支持。",
            evidence: [PresetSharedContent.keyMappingEvidence]),
        "alwaysListeningSiri": PresetContent(
            chineseName: "随时聆听 Siri",
            chineseDescription: "声明随时聆听「嘿 Siri」支持。需要重新启动设备。Apple 智能还取决于机型与地区。",
            scope: .nativeAIHardware,
            scopeNote: "原生支持 Apple 智能的机型可直接使用；其他机型须暂存开启，且地区须为 LL。",
            minSystem: .known("iOS 27"),
            riskReason: "仅改随时聆听 Siri 能力标记；实际可用取决于机型、地区与 Apple 服务器。",
            evidence: [PresetSharedContent.keyMappingEvidence]),
        // MARK: Display
        "dynamicIsland": PresetContent(
            chineseName: "灵动岛",
            chineseDescription: "开启备用灵动岛能力。先执行注销，若未生效则重新启动设备。只改能力标记，不增加灵动岛硬件；设备本身须具备灵动岛布局。",
            riskReason: "只改灵动岛能力标记；设备本身须具备灵动岛布局（ArtworkDeviceSubType 为灵动岛布局值），否则无效果。",
            evidence: [PresetEvidence(text: "GestaltX/ContentView.swift（灵动岛布局选择器）", kind: .code)]),
        "aod": PresetContent(
            chineseName: "常亮显示",
            chineseDescription: "让锁屏在屏幕关闭时保持可见。先执行注销，若未生效则重新启动设备。显示效果取决于屏幕面板，可能增加耗电与烧屏风险。",
            riskReason: "常亮显示可能增加耗电与烧屏风险；显示效果取决于屏幕面板。"),
        "aodVibrancy": PresetContent(
            chineseName: "常亮鲜明度",
            chineseDescription: "调整常亮显示的渲染能力。先执行注销，若未生效则重新启动设备。",
            riskReason: "只改常亮渲染能力标记；实际渲染效果取决于屏幕面板。"),
        "aodHighLuminance": PresetContent(
            chineseName: "常亮高亮",
            chineseDescription: "允许常亮显示达到更高亮度。可能需要重新启动设备才能生效。",
            riskReason: "只改常亮亮度上限标记；实际亮度取决于屏幕面板。"),
        "aodFlipbook": PresetContent(
            chineseName: "常亮翻页小组件",
            chineseDescription: "在锁屏上启用常亮翻页小组件。先执行注销，若未生效则重新启动设备。",
            riskReason: "只改常亮翻页小组件标记；须锁屏支持该小组件。"),
        "aodFlipbookCount": PresetContent(
            chineseName: "常亮翻页数量",
            chineseDescription: "设置允许的常亮翻页条目数量（改为 3）。可能需要重新启动设备才能生效。实验性功能；可接受的范围因 iOS 构建而异。",
            riskReason: "实验性功能；可接受的数量范围因 iOS 构建而异，超出范围可能不生效。"),
        "parallax": PresetContent(
            chineseName: "壁纸视差",
            chineseDescription: "让壁纸不再随设备移动而移动（改为 0，即关闭视差）。先执行注销，若未生效则重新启动设备。",
            riskReason: "只改壁纸视差标记；不改变壁纸本身。"),
        "hdrPhotoDisplay": PresetContent(
            chineseName: "HDR 照片显示",
            chineseDescription: "为照片启用真正的 HDR 渲染。先执行注销，若未生效则重新启动设备。",
            riskReason: "只改 HDR 渲染能力标记；实际渲染取决于屏幕面板是否支持 HDR。"),
        "pwm": PresetContent(
            chineseName: "脉宽调制",
            chineseDescription: "声明支持 PWM 调光。可能需要重新启动设备才能生效。实际调光行为取决于屏幕面板。",
            riskReason: "只声明支持 PWM；实际调光行为取决于屏幕面板，标记本身不改变调光硬件。"),
        "displayPort": PresetContent(
            chineseName: "DisplayPort 输出",
            chineseDescription: "声明支持 DisplayPort 输出。可能需要重新启动设备才能生效。仍需要兼容的硬件。",
            riskReason: "只声明支持 DisplayPort 输出；仍需要兼容的硬件，标记本身不增加输出能力。"),
        "liquidGlass": PresetContent(
            chineseName: "液态玻璃低功耗渲染",
            chineseDescription: "使用低功耗液态玻璃渲染。先执行注销，若未生效则重新启动设备。要求 iOS 26 或更高版本。",
            minSystem: .known("iOS 26"),
            riskReason: "只改液态玻璃渲染模式标记；要求 iOS 26 或更高版本。"),
    ]
}

extension PresetCatalog {
    /// The rest of the Chinese content table: device, iPad and
    /// advanced capabilities. (One dictionary literal per category
    /// keeps each extension readable; the two are merged in
    /// `mergedChineseContent` below.)
    static let chineseContentDeviceAndAdvanced: [String: PresetContent] = [
        // MARK: Device
        "bootChime": PresetContent(
            chineseName: "开关机提示音",
            chineseDescription: "显示开关机提示音能力。可能需要重新启动设备才能生效。",
            riskReason: "只改开关机提示音能力标记；实际发声取决于设备扬声器。"),
        "chargeLimit": PresetContent(
            chineseName: "充电上限",
            chineseDescription: "显示充电上限设置。可能需要重新启动设备才能生效。实际充电控制取决于硬件。",
            riskReason: "只改充电上限设置显示；实际充电控制取决于硬件。"),
        "tapToWake": PresetContent(
            chineseName: "轻点唤醒",
            chineseDescription: "显示轻点唤醒功能。可能需要重新启动设备才能生效。仅在轻点唤醒被隐藏的设备上显示。",
            riskReason: "只改轻点唤醒显示；仅在该功能被隐藏的设备上有意义。"),
        "cameraControl": PresetContent(
            chineseName: "相机控制",
            chineseDescription: "显示相机控制设置。可能需要重新启动设备才能生效。这不会增加实体按钮。",
            riskReason: "只改相机控制设置显示；不会增加实体按钮。"),
        "actionButton": PresetContent(
            chineseName: "操作按钮",
            chineseDescription: "显示操作按钮设置页面。可能需要重新启动设备才能生效。",
            riskReason: "只改操作按钮设置页显示；设备本身须有操作按钮硬件。"),
        "collisionSOS": PresetContent(
            chineseName: "碰撞检测 SOS",
            chineseDescription: "在 SOS 紧急联络设置中显示碰撞检测。可能需要重新启动设备才能生效。仍需要硬件支持。",
            riskReason: "只改碰撞检测设置显示；仍需要硬件支持，标记本身不增加检测能力。"),
        "audioMix": PresetContent(
            chineseName: "音频混合",
            chineseDescription: "为支持的媒体启用音频混合能力。可能需要重新启动设备才能生效。",
            riskReason: "只改音频混合能力标记；仅对支持的媒体生效。"),
        "spatialFaceTimeAudio": PresetContent(
            chineseName: "空间化 FaceTime 音频",
            chineseDescription: "为 FaceTime 启用空间音频播放。可能需要重新启动设备才能生效。",
            riskReason: "只改空间音频能力标记；实际播放取决于音频硬件与系统支持。"),
        // MARK: iPad
        "pencil": PresetContent(
            chineseName: "Apple Pencil",
            chineseDescription: "显示 Apple Pencil 设置。重新启动设备后再打开「设置」。仍需要 Apple Pencil 硬件支持。",
            scope: .ipadHardware,
            scopeNote: "仅 iPad 硬件；仍需要 Apple Pencil 硬件支持。",
            riskReason: "只改 Apple Pencil 设置显示；仍需要 Apple Pencil 硬件支持。"),
        "stageManager": PresetContent(
            chineseName: "台前调度",
            chineseDescription: "显示台前调度支持。可能需要重新启动设备才能生效。布局行为因设备而异。",
            scope: .ipadHardware,
            scopeNote: "仅 iPad 硬件；布局行为因设备而异。",
            riskReason: "只改台前调度支持标记；布局行为因设备而异，iPhone 上的实际表现未经逐一验证。"),
        "ipadApps": PresetContent(
            chineseName: "iPad 应用兼容",
            chineseDescription: "允许 iPhone 使用 iPad 应用兼容类型。先执行注销，若未生效则重新启动设备。",
            scope: .unknown(reason: "在 iPhone 上启用 iPad 应用兼容类型；各机型上的实际表现未经逐一验证。"),
            scopeNote: "在 iPhone 上启用 iPad 应用兼容类型；各机型上的实际表现未经逐一验证。",
            riskReason: "只改 iPad 应用兼容类型标记；不改变应用本身的兼容性。"),
        // MARK: Advanced
        "internal": PresetContent(
            chineseName: "Apple 内部功能",
            chineseDescription: "显示内部菜单。可能需要重新启动设备才能生效。部分系统服务的行为可能不同。",
            riskReason: "显示 Apple 内部菜单；部分系统服务的行为可能不同，误改内部设置可能影响系统。"),
        "storage": PresetContent(
            chineseName: "内部版本",
            chineseDescription: "将设备标记为内部版本。可能需要重新启动设备才能生效。这会改动全系统的 InternalBuild 标记，不只是存储信息。系统服务的行为可能不同。还原时会恢复记录的原始值。",
            riskReason: "改动的是全系统 InternalBuild 标记，不只是存储信息；系统服务的行为可能不同。"),
        "srd": PresetContent(
            chineseName: "安全研究设备",
            chineseDescription: "更改安全研究设备能力标记。可能需要重新启动设备才能生效。这不会把设备变成 Apple 安全研究设备。",
            riskReason: "只改安全研究设备能力标记；这不会把设备变成真正的 Apple 安全研究设备。"),
        "internalSettings": PresetContent(
            chineseName: "内部设置",
            chineseDescription: "显示 Apple 内部设置包。可能需要重新启动设备才能生效。部分系统服务的行为可能不同。",
            riskReason: "显示 Apple 内部设置包；部分系统服务的行为可能不同，误改内部设置可能影响系统。"),
    ]

    /// The full Chinese content table: the main table plus the
    /// device/advanced table. The builder reads this merged table.
    static var mergedChineseContent: [String: PresetContent] {
        chineseContent.merging(chineseContentDeviceAndAdvanced) { _, new in new }
    }
}

// MARK: - Search and filter

extension PresetCatalog {
    /// Case-insensitive substring search over the Chinese name,
    /// English title, feature id, underlying keys and Chinese
    /// description. An empty or blank query returns all entries.
    /// No fuzzy guessing: only real substring matches are returned.
    static func search(_ query: String, in entries: [PresetEntry] = all) -> [PresetEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }
        return entries.filter { entry in
            entry.chineseName.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || entry.englishTitle.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || entry.featureID.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || entry.keys.contains { key in
                    key.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                }
                || entry.chineseDescription.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// Filters by category, risk level and per-device eligibility.
    /// `evaluations` maps feature id to eligibility (from
    /// `LilaIntelligence.report`); an entry with no evaluation in
    /// the map counts as `.unknown` — unknown is never assumed
    /// eligible. A group matches an eligibility filter when any of
    /// its members has that eligibility.
    static func filtered(
        _ entries: [PresetEntry],
        category: PresetCategory? = nil,
        riskLevel: CapabilityRiskLevel? = nil,
        eligibility: FeatureEligibility? = nil,
        evaluations: [String: FeatureEligibility] = [:]
    ) -> [PresetEntry] {
        entries.filter { entry in
            if let category, entry.category != category { return false }
            if let riskLevel, entry.riskLevel != riskLevel { return false }
            if let eligibility {
                return eligibilityMatches(entry, eligibility: eligibility, evaluations: evaluations)
            }
            return true
        }
    }

    private static func eligibilityMatches(
        _ entry: PresetEntry, eligibility: FeatureEligibility,
        evaluations: [String: FeatureEligibility]
    ) -> Bool {
        if entry.kind == .group {
            return entry.memberIDs.contains { memberID in
                evaluations[memberID] ?? .unknown == eligibility
            }
        }
        return evaluations[entry.featureID] ?? .unknown == eligibility
    }

    /// Favorites first, keeping the catalog order otherwise (a
    /// stable sort: the relative order inside each group is the
    /// catalog order).
    static func favoritesFirst(_ entries: [PresetEntry], favoriteIDs: Set<String>) -> [PresetEntry] {
        entries.sorted { first, second in
            favoriteIDs.contains(first.featureID) && !favoriteIDs.contains(second.featureID)
        }
    }

    /// The eligibility of one entry on this device, from the
    /// caller's evaluations. Groups have no single eligibility:
    /// this returns the eligibility of the group's first member
    /// that is not `.unknown`, or `.unknown` when every member is
    /// unknown or unevaluated.
    static func eligibility(
        of entry: PresetEntry, evaluations: [String: FeatureEligibility]
    ) -> FeatureEligibility {
        if entry.kind == .group {
            for memberID in entry.memberIDs {
                if let value = evaluations[memberID], value != .unknown {
                    return value
                }
            }
            return .unknown
        }
        return evaluations[entry.featureID] ?? .unknown
    }
}

// MARK: - Favorites

/// What loading the favorites produced. A corrupt, tampered or
/// newer-format file loads as empty favorites with an error — the
/// store never crashes and never trusts a bad file.
struct PresetFavoritesLoad: Equatable, Sendable {
    let ids: [String]
    let error: String?
}

/// Local-only favorites, persisted in the app's own history
/// directory as a versioned JSON envelope with a SHA-256 sidecar
/// (the same pattern as `ChangeRecordStore`). Favorites never
/// touch the MobileGestalt cache and never affect staging.
struct PresetFavoritesStore: Sendable {
    static let fileName = "preset-favorites.json"
    static let currentVersion = 1

    let directory: URL
    let deviceID: String

    private var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    /// Loads the favorite ids. A missing file loads as empty
    /// favorites; a digest mismatch, an undecodable file, an
    /// envelope newer than this version, or an envelope for another
    /// device loads as empty favorites with an error. Unknown ids
    /// (entries no longer in the catalog) are dropped silently —
    /// favorites are low-stakes display state.
    func load() -> PresetFavoritesLoad {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return PresetFavoritesLoad(ids: [], error: nil)
        }
        do {
            let envelope = try HistoryJournal.readVerifiedJSON(
                HistoryEnvelope<String>.self, from: fileURL)
            guard envelope.version <= Self.currentVersion else {
                return PresetFavoritesLoad(ids: [], error: L("These favorites use a newer format this version cannot read."))
            }
            guard envelope.deviceID == deviceID else {
                return PresetFavoritesLoad(ids: [], error: L("These favorites belong to a different device."))
            }
            let known = Set(PresetCatalog.all.map(\.featureID))
            return PresetFavoritesLoad(ids: envelope.records.filter { known.contains($0) }, error: nil)
        } catch {
            return PresetFavoritesLoad(ids: [], error: L("The favorites could not be read. No system changes were made."))
        }
    }

    /// Saves the favorite ids as a v1 envelope with a SHA-256
    /// sidecar, verified by a read-back. Unknown ids are dropped
    /// before saving.
    func save(_ ids: [String]) throws {
        let known = Set(PresetCatalog.all.map(\.featureID))
        let filtered = ids.filter { known.contains($0) }
        do {
            try HistoryJournal.writeVerifiedJSON(
                HistoryEnvelope(version: Self.currentVersion, deviceID: deviceID, records: filtered),
                to: fileURL)
        } catch {
            throw GestaltFailure("The favorites could not be saved and verified. No system changes were made.")
        }
    }

    /// Toggles one favorite: loads, flips it, saves, and returns the
    /// new ids.
    func toggle(_ id: String) throws -> [String] {
        var ids = load().ids
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
        } else {
            ids.append(id)
        }
        try save(ids)
        return ids
    }
}

// MARK: - Custom combinations

/// One custom combination: a named set of preset feature ids, saved
/// locally as a PLAN. It is never staged or applied by this layer.
struct PresetCombination: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    var name: String
    var featureIDs: [String]
    let createdAt: Date
}

/// What loading the combinations produced. Member ids that are no
/// longer in the catalog are dropped and reported in
/// `droppedMemberIDs`, so the UI can say so instead of silently
/// shrinking a combination.
struct PresetCombinationLoad: Equatable, Sendable {
    let combinations: [PresetCombination]
    let droppedMemberIDs: [String]
    let error: String?
}

/// Local-only storage for custom combinations, same envelope pattern
/// as the favorites store.
struct PresetCombinationStore: Sendable {
    static let fileName = "preset-combinations.json"
    static let currentVersion = 1

    let directory: URL
    let deviceID: String

    private var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    /// Validates a combination before it is saved: a non-empty name,
    /// at least one member, every member a known catalog id, no
    /// duplicates. Returns the first problem, or `nil` when the
    /// combination is valid.
    static func validationError(name: String, featureIDs: [String]) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return L("Give the combination a name.")
        }
        if featureIDs.isEmpty {
            return L("Choose at least one preset.")
        }
        let known = Set(PresetCatalog.all.map(\.featureID))
        if let unknownID = featureIDs.first(where: { !known.contains($0) }) {
            return String(format: L("Unknown preset: %@"), unknownID)
        }
        if Set(featureIDs).count != featureIDs.count {
            return L("A combination cannot contain the same preset twice.")
        }
        return nil
    }

    /// Loads the saved combinations. A missing file loads as empty;
    /// a bad file loads as empty with an error. Member ids no longer
    /// in the catalog are dropped and reported.
    func load() -> PresetCombinationLoad {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return PresetCombinationLoad(combinations: [], droppedMemberIDs: [], error: nil)
        }
        do {
            let envelope = try HistoryJournal.readVerifiedJSON(
                HistoryEnvelope<PresetCombination>.self, from: fileURL)
            guard envelope.version <= Self.currentVersion else {
                return PresetCombinationLoad(
                    combinations: [], droppedMemberIDs: [],
                    error: L("These combinations use a newer format this version cannot read."))
            }
            guard envelope.deviceID == deviceID else {
                return PresetCombinationLoad(
                    combinations: [], droppedMemberIDs: [],
                    error: L("These combinations belong to a different device."))
            }
            let known = Set(PresetCatalog.all.map(\.featureID))
            var dropped: [String] = []
            let cleaned = envelope.records.map { combination -> PresetCombination in
                let kept = combination.featureIDs.filter { id in
                    if known.contains(id) { return true }
                    dropped.append(id)
                    return false
                }
                var cleanedCombination = combination
                cleanedCombination.featureIDs = kept
                return cleanedCombination
            }
            return PresetCombinationLoad(
                combinations: cleaned, droppedMemberIDs: dropped, error: nil)
        } catch {
            return PresetCombinationLoad(
                combinations: [], droppedMemberIDs: [],
                error: L("The combinations could not be read. No system changes were made."))
        }
    }

    /// Saves the combinations as a v1 envelope with a SHA-256
    /// sidecar, verified by a read-back.
    func save(_ combinations: [PresetCombination]) throws {
        do {
            try HistoryJournal.writeVerifiedJSON(
                HistoryEnvelope(version: Self.currentVersion, deviceID: deviceID, records: combinations),
                to: fileURL)
        } catch {
            throw GestaltFailure("The combinations could not be saved and verified. No system changes were made.")
        }
    }
}

// MARK: - Combination check

/// The check result for one custom combination: the dependency
/// analysis plus the SafePatch simulation. `canProceed` is true
/// only when the analysis is safe AND the simulation can proceed.
/// A combination is checked, never applied — the check result is
/// display data, and the UI must say applying is not connected.
struct PresetCombinationCheck: Equatable, Sendable {
    let analysis: DependencyAnalysis
    let simulation: SafePatchSimulation

    var canProceed: Bool {
        analysis.verdict == .safeToStage && simulation.canProceed
    }

    /// The simulation note: what the simulation says, or its first
    /// blocker when it cannot proceed.
    var simulationNote: String {
        if simulation.canProceed { return L("Simulation can proceed") }
        return simulation.blockers.first ?? L("Simulation blocked")
    }
}

/// Checks a custom combination with the same tools staging uses:
/// `DependencyAnalyzer` for prerequisites, conflicts and
/// duplicates, and `SafePatch` for the pre-write simulation. Pure:
/// reads its inputs, writes nothing.
enum PresetCombinationChecker {
    static func check(
        combination: PresetCombination,
        profile: DeviceProfile,
        snapshot: DocumentSnapshot?,
        backups: [BackupRecord] = [],
        liveAIEnabled: Bool? = nil
    ) -> PresetCombinationCheck {
        let analysis = DependencyAnalyzer.analyze(
            featureIDs: combination.featureIDs, profile: profile,
            snapshot: snapshot, liveAIEnabled: liveAIEnabled)
        let simulation = SafePatch.simulate(
            proposal: SafePatchProposal(featureIDs: combination.featureIDs),
            snapshot: snapshot, backups: backups, profile: profile)
        return PresetCombinationCheck(analysis: analysis, simulation: simulation)
    }
}
