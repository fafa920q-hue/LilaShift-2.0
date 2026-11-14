// SPDX-License-Identifier: GPL-3.0-only
// Stable, testable sorting rules for the lists the home and the
// detail pages show (P1.6). These are pure functions over the
// existing model types: they change the ORDER of rows only, never
// the data, the feature behavior, or which rows exist.
//
// Rules:
// - Presets: the user's chosen sort, with a stable tiebreak by
//   feature id. Apply `PresetCatalog.favoritesFirst` first when
//   the view shows favorites first; this function only orders
//   within the chosen sort.
// - Restore history: newest first (date descending). Swift's
//   `sorted(by:)` is stable, so entries with equal dates keep
//   their input order.
// - Modified fields: the fixed one-tap order (eSIM green-tea,
//   eSIM not-green-tea, then the six AI capabilities in staging
//   order); fields that are not one-tap fields sort after all of
//   them, alphabetically by key.
import Foundation

enum HomeSorting {
    /// The fixed one-tap order, as feature ids, from the one-tap
    /// proposal: eSIM, region code, then the six AI capabilities in
    /// staging order. The region code is a CacheData slot and never
    /// appears in a Modified Values row; it is kept here so this
    /// order is the same single source of truth as the proposal
    /// (`SafePatchProposal.oneTap`).
    static let oneTapFeatureOrder: [String] =
        [FeatureEligibilityEvaluator.esimFeatureID,
         FeatureEligibilityEvaluator.regionCodeFeatureID]
        + ChinaUnlock.aiCapabilityIDs

    /// Rank of each Modified Values row key in the one-tap order.
    /// eSIM rows use the synthetic keys "esim-green-tea" /
    /// "esim-not-green-tea"; AI rows use the capability's CacheExtra
    /// key, looked up from `Capability.all`, so a key added to the
    /// catalog is ranked without editing this file. Keys absent
    /// from this map are not one-tap fields: they sort after all
    /// of them, alphabetically by key.
    static func oneTapRankByKey() -> [String: Int] {
        var ranks: [String: Int] = [:]
        var next = 0
        ranks["esim-green-tea"] = next
        next += 1
        ranks["esim-not-green-tea"] = next
        next += 1
        for featureID in ChinaUnlock.aiCapabilityIDs {
            guard let capability = Capability.all.first(where: { $0.id == featureID }) else {
                continue
            }
            for key in capability.keys where ranks[key] == nil {
                ranks[key] = next
                next += 1
            }
        }
        return ranks
    }

    /// Modified fields, by the fixed one-tap order; fields that
    /// are not one-tap fields sort after all of them,
    /// alphabetically by key. Rows are keyed by `key`, so equal
    /// keys cannot occur and the result is fully deterministic.
    static func sortModifiedValues(_ rows: [ModifiedValueRow]) -> [ModifiedValueRow] {
        let ranks = oneTapRankByKey()
        return rows.sorted { first, second in
            let firstRank = ranks[first.key]
            let secondRank = ranks[second.key]
            switch (firstRank, secondRank) {
            case let (a?, b?):
                return a < b
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return first.key < second.key
            }
        }
    }

    /// Restore history, newest first. Swift's `sorted(by:)` is
    /// stable, so entries with equal dates keep their input order.
    static func sortHistory(_ entries: [RestoreTimelineEntry]) -> [RestoreTimelineEntry] {
        entries.sorted { $0.date > $1.date }
    }

    /// The user's chosen preset sort. `.catalog` keeps the
    /// catalog's fixed order (the input order); `.name` sorts by
    /// Chinese name (A–Z); `.risk` sorts by risk, highest first.
    /// Every sort breaks ties by feature id, so the result is
    /// deterministic even when two entries share a name or a risk
    /// level.
    enum PresetSortOrder: String, CaseIterable, Sendable {
        case catalog
        case name
        case risk
    }

    /// Presets in the user's chosen sort, with a stable tiebreak
    /// by feature id. `.catalog` returns the input unchanged: the
    /// catalog order is the input order.
    ///
    /// NOTE (Phase E decision, 2026-11-14): this function is NOT
    /// wired into any view, deliberately. The catalog card orders
    /// through `PersonalizationCenter.sortedEntries`, which uses
    /// `HomeSorting.compare` — a stable sort (equal entries keep
    /// catalog order) with `localizedStandardCompare` names. This
    /// function instead breaks ties by feature id and compares
    /// names with `<`, so wiring it in would change the catalog
    /// card's visible order and fail the stable-order tests in
    /// PersonalizationCenterTests. It stays here as a tested pure
    /// helper; aligning the two tiebreak rules is a separate,
    /// deliberate follow-up, not a silent swap in this phase.
    static func sortPresets(_ entries: [PresetEntry], by order: PresetSortOrder) -> [PresetEntry] {
        switch order {
        case .catalog:
            return entries
        case .name:
            return entries.sorted { first, second in
                if first.chineseName != second.chineseName {
                    return first.chineseName < second.chineseName
                }
                return first.featureID < second.featureID
            }
        case .risk:
            return entries.sorted { first, second in
                let firstRisk = riskRank(first.riskLevel)
                let secondRisk = riskRank(second.riskLevel)
                if firstRisk != secondRisk {
                    return firstRisk < secondRisk
                }
                return first.featureID < second.featureID
            }
        }
    }

    /// Risk rank for sorting: highest risk first.
    private static func riskRank(_ level: CapabilityRiskLevel) -> Int {
        switch level {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }

    /// The ONE preset comparison used by every list that shows
    /// catalog entries: `PersonalizationCenter.sortedEntries` (the
    /// catalog card) and `sortCatalogItems` (the unified feature
    /// catalog) both call this, so the same sort means the same
    /// order everywhere. Semantics are the ones the catalog card
    /// has always had and the PersonalizationCenter tests assert:
    /// - `.byName`: Chinese name via `localizedStandardCompare`,
    ///   then feature id via `localizedStandardCompare`.
    /// - `.byRisk`: highest risk first; equal risk compares equal
    ///   (the caller keeps catalog order with a stable sort).
    /// - `.byCategory`: `PresetCategory` order; equal category
    ///   compares equal (stable sort keeps catalog order).
    /// This is deliberately NOT `sortPresets` above: that helper
    /// breaks ties by feature id and compares names with `<`,
    /// which would change the catalog card's order and fail the
    /// stable-order tests. `sortPresets` stays as an un-wired
    /// helper (see its note); do not wire it into a view.
    static func compare(_ left: PresetEntry, _ right: PresetEntry, by sort: CatalogSort) -> ComparisonResult {
        switch sort {
        case .byName:
            let nameComparison = left.chineseName.localizedStandardCompare(right.chineseName)
            if nameComparison != .orderedSame { return nameComparison }
            return left.featureID.localizedStandardCompare(right.featureID)
        case .byRisk:
            if left.riskLevel != right.riskLevel {
                return riskRank(left.riskLevel) < riskRank(right.riskLevel)
                    ? .orderedAscending : .orderedDescending
            }
            return .orderedSame
        case .byCategory:
            let leftIndex = PresetCategory.allCases.firstIndex(of: left.category) ?? PresetCategory.allCases.count
            let rightIndex = PresetCategory.allCases.firstIndex(of: right.category) ?? PresetCategory.allCases.count
            if leftIndex != rightIndex {
                return leftIndex < rightIndex ? .orderedAscending : .orderedDescending
            }
            return .orderedSame
        }
    }

    /// The ONE ordering rule for the unified feature catalog
    /// (`FeatureCatalog.apply`, the catalog browser, the home
    /// common-features section). One comparator, applied
    /// everywhere — no per-page ad-hoc ordering. Precedence:
    /// 1. favorites first, when the toggle is on;
    /// 2. the user's custom order (listed ids in listed order;
    ///    unlisted ids come after, in sort order);
    /// 3. recent use (most recent first; recent ids before the
    ///    rest);
    /// 4. the user's sort: by name (`localizedStandardCompare`,
    ///    then id), by risk (highest first; pages have no risk and
    ///    sort as low), by category (`categorySortRank`);
    /// 5. input order (stable: equal items keep catalog order).
    /// With no favorites, no custom order and no recent use, the
    /// result for preset-only input is exactly
    /// `PersonalizationCenter.sortedEntries` — the equivalence test
    /// in FeatureCatalogTests asserts that for all three sorts.
    static func sortCatalogItems(
        _ items: [FeatureCatalogItem],
        by sort: CatalogSort,
        favoritesFirst: Bool,
        favoriteIDs: Set<String>,
        customOrder: [String]?,
        recentIDs: [String]
    ) -> [FeatureCatalogItem] {
        var customRank: [String: Int] = [:]
        for (index, id) in (customOrder ?? []).enumerated() where customRank[id] == nil {
            customRank[id] = index
        }
        var recentRank: [String: Int] = [:]
        for (index, id) in recentIDs.enumerated() where recentRank[id] == nil {
            recentRank[id] = index
        }
        return items.enumerated().sorted { left, right in
            let first = left.element
            let second = right.element
            if favoritesFirst {
                let firstFavorite = favoriteIDs.contains(first.id)
                let secondFavorite = favoriteIDs.contains(second.id)
                if firstFavorite != secondFavorite { return firstFavorite }
            }
            let firstCustom = customRank[first.id]
            let secondCustom = customRank[second.id]
            switch (firstCustom, secondCustom) {
            case let (a?, b?):
                if a != b { return a < b }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                break
            }
            let firstRecent = recentRank[first.id]
            let secondRecent = recentRank[second.id]
            switch (firstRecent, secondRecent) {
            case let (a?, b?):
                if a != b { return a < b }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                break
            }
            switch sort {
            case .byName:
                let nameComparison = first.chineseName.localizedStandardCompare(second.chineseName)
                if nameComparison != .orderedSame { return nameComparison == .orderedAscending }
                let idComparison = first.id.localizedStandardCompare(second.id)
                if idComparison != .orderedSame { return idComparison == .orderedAscending }
            case .byRisk:
                let firstRisk = first.riskLevel.map(riskRank) ?? 2
                let secondRisk = second.riskLevel.map(riskRank) ?? 2
                if firstRisk != secondRisk { return firstRisk < secondRisk }
            case .byCategory:
                if first.categorySortRank != second.categorySortRank {
                    return first.categorySortRank < second.categorySortRank
                }
            }
            return left.offset < right.offset
        }.map(\.element)
    }
}
