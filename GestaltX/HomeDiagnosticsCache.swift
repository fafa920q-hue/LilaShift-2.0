// SPDX-License-Identifier: GPL-3.0-only
// HomeDiagnosticsCache — one shared, cached home-diagnostics
// computation for the Tools home.
//
// Problem: every diagnostics card recomputed the same expensive
// values as a SwiftUI computed property, on EVERY body evaluation.
// The device report, backup verification (disk reads + SHA-256 of
// every backup file), the one-tap SafePatch simulation, the health
// score, the Modified Values report and the fingerprint capture were
// each computed up to three times per body evaluation — and the body
// is re-evaluated whenever ANY GestaltManager @Published property
// changes (including the session log, which appends during a read).
// That is what made the home scroll lag.
//
// Fix: this cache computes each shared value ONCE per input change,
// on a background task, and publishes the result. The cards read the
// cached value (cheap) instead of recomputing. The cache keeps the
// previous values while a refresh is in flight, so the home never
// flashes empty. A value is only published when it actually changed
// (all cached types are Equatable), so a refresh that produces the
// same values does not rebuild the home.
//
// Invalidation (what triggers a refresh, and what it means):
//   - ContentView drives `refresh(snapshot:working:backups:)` on
//     appear and whenever the snapshot data, the backup inventory or
//     the staged-change count changes. A refresh is also triggered
//     after an explicit backup/restore, via `refresh()`.
//   - The inputs are the snapshot, the working document and the
//     backup inventory. Anything derived from them (report, health,
//     simulations, verifications, fingerprint, live values) is
//     recomputed together in one background pass, so the cards can
//     never disagree about the same underlying data.
//   - The cache never writes anything: it only reads the snapshot,
//     the working document, the backup files (read-only verification)
//     and the history stores (read-only loads). All MobileGestalt
//     writes, backups, restores and staging stay in GestaltManager.
//   - Unknown stays unknown: a value that could not be computed
//     (no snapshot, no history id, unreadable file) is published as
//     nil / empty / unknown, never fabricated.
//
// Concurrency: the cache itself is @MainActor (it owns @Published
// state). The heavy work runs in a `Task.detached` (the same pattern
// AppAppearanceViews already uses for image work): the detached task
// captures only Sendable inputs (the snapshot, working document and
// backup records are all Sendable value types) and returns a
// Sendable result; the outer Task (MainActor-isolated) applies it.
// The history stores (ChangeRecordStore, DeviceFingerprintStore) are
// Sendable structs whose `load()` does file I/O, so loading them on
// the detached task moves the disk reads off the main thread. The
// live-probe values are also read on the detached task: the live
// Gestalt query can be slow, and it must never block scrolling.
import SwiftUI

/// The result of one background diagnostics computation. Every field
/// is a Sendable value type, so the whole result can cross from the
/// detached task back to the main actor safely.
private struct HomeDiagnosticsResult: Sendable {
    var deviceReport: LilaDeviceReport?
    var backupVerifications: [BackupVerification]
    var simulations: [SafePatchProposal: SafePatchSimulation]
    var healthScore: SystemHealthScore?
    var externalModificationCount: Int
    var records: [RecordedChange]
    var historyError: String?
    var storedFingerprint: DeviceFingerprint?
    var fingerprintError: String?
    var currentFingerprint: DeviceFingerprint?
    var liveValues: [String: ChangeValue]
    /// Feature ids staged in the working document but not yet
    /// applied (snapshot vs working diff), for the compatibility
    /// status model (Phase F). Computed here once, so every card
    /// shows the same staged set.
    var stagedFeatureIDs: Set<String>
    /// Feature ids applied but not yet verified after a restart,
    /// for the compatibility status model (Phase F).
    var pendingRestartFeatureIDs: Set<String>
}

/// Environment key for the shared diagnostics cache. The default is
/// `nil`: a view that renders without the cache (for example the
/// SwiftUI snapshot tests, which only provide a GestaltManager) falls
/// back to computing directly, so its rendered output is unchanged.
private struct HomeDiagnosticsCacheKey: EnvironmentKey {
    static let defaultValue: HomeDiagnosticsCache? = nil
}

extension EnvironmentValues {
    var homeDiagnosticsCache: HomeDiagnosticsCache? {
        get { self[HomeDiagnosticsCacheKey.self] }
        set { self[HomeDiagnosticsCacheKey.self] = newValue }
    }
}

/// Returns the strings with duplicates removed, keeping the first
/// occurrence of each, in order. Used to merge duplicate blocking
/// reasons and identical status lines in the home cards; the
/// underlying evaluations and evidence are still shown in full in
/// the details, so nothing is lost.
func deduplicated(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { seen.insert($0).inserted }
}

@MainActor
final class HomeDiagnosticsCache: ObservableObject {
    /// The per-device report (profile + eligibility evaluations), or
    /// `nil` when the device has not been read yet.
    @Published private(set) var deviceReport: LilaDeviceReport?
    /// Read-only verification of every stored backup (disk reads +
    /// SHA-256, computed on the background task).
    @Published private(set) var backupVerifications: [BackupVerification] = []
    /// SafePatch simulations for the three proposals the home shows,
    /// keyed by proposal. The health and diagnosis cards use the
    /// one-tap simulation; the simulator card uses the selected one.
    @Published private(set) var simulations: [SafePatchProposal: SafePatchSimulation] = [:]
    /// The health score, or `nil` when the device has not been read.
    @Published private(set) var healthScore: SystemHealthScore?
    /// Fields the Modified Values report found changed, minus the
    /// keys this app recorded.
    @Published private(set) var externalModificationCount: Int = 0
    /// Recorded changes from the history store (loaded on the
    /// background task, never on the main thread).
    @Published private(set) var records: [RecordedChange] = []
    /// Why the change history could not be read, if it could not.
    @Published private(set) var historyError: String?
    /// The stored device fingerprint, or `nil` when never recorded.
    @Published private(set) var storedFingerprint: DeviceFingerprint?
    /// Why the stored fingerprint could not be read, if it could not.
    @Published private(set) var fingerprintError: String?
    /// The fingerprint of the current snapshot, or `nil` when the
    /// device has not been read yet.
    @Published private(set) var currentFingerprint: DeviceFingerprint?
    /// Live-probe values for the recorded CacheExtra changes, read
    /// on the background task (the live Gestalt query can be slow).
    @Published private(set) var liveValues: [String: ChangeValue] = [:]
    /// Feature ids staged in the working document but not yet
    /// applied. See `HomeDiagnosticsResult.stagedFeatureIDs`.
    @Published private(set) var stagedFeatureIDs: Set<String> = []
    /// Feature ids applied but not yet verified after a restart.
    /// See `HomeDiagnosticsResult.pendingRestartFeatureIDs`.
    @Published private(set) var pendingRestartFeatureIDs: Set<String> = []
    /// True while a background refresh is in flight. The previous
    /// cached values stay visible until the new ones arrive.
    @Published private(set) var isComputing = false

    private var refreshTask: Task<Void, Never>?

    /// The one-tap simulation, or `nil` when it has not been
    /// computed yet. Convenience for the health and diagnosis cards,
    /// which always use the one-tap proposal.
    var oneTapSimulation: SafePatchSimulation? {
        simulations[SafePatchProposal.oneTap()]
    }

    /// Recomputes all cached diagnostics for the given inputs on a
    /// background task. Safe to call often: an in-flight refresh is
    /// cancelled, and a refresh that produces unchanged values does
    /// not publish anything. Call this when the snapshot, the working
    /// document or the backup inventory changes, and after an explicit
    /// backup or restore.
    func refresh(snapshot: DocumentSnapshot?, working: GestaltDocument?, backups: [BackupRecord]) {
        refreshTask?.cancel()
        isComputing = true
        // These are cheap reads (URL construction / UserDefaults);
        // the heavy file I/O happens inside the detached task.
        let deviceID = RestoreIntelligence.installationDeviceID
        let historyDirectory = RestoreIntelligence.historyDirectory
        refreshTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Self.compute(
                    snapshot: snapshot, working: working, backups: backups,
                    deviceID: deviceID, historyDirectory: historyDirectory)
            }.value
            guard let self, !Task.isCancelled else { return }
            self.apply(result)
            self.isComputing = false
        }
    }

    /// Applies one computed result, publishing only the values that
    /// actually changed, so a refresh that produces the same values
    /// does not rebuild the home.
    private func apply(_ result: HomeDiagnosticsResult) {
        if deviceReport != result.deviceReport { deviceReport = result.deviceReport }
        if backupVerifications != result.backupVerifications { backupVerifications = result.backupVerifications }
        if simulations != result.simulations { simulations = result.simulations }
        if healthScore != result.healthScore { healthScore = result.healthScore }
        if externalModificationCount != result.externalModificationCount { externalModificationCount = result.externalModificationCount }
        if records != result.records { records = result.records }
        if historyError != result.historyError { historyError = result.historyError }
        if storedFingerprint != result.storedFingerprint { storedFingerprint = result.storedFingerprint }
        if fingerprintError != result.fingerprintError { fingerprintError = result.fingerprintError }
        if currentFingerprint != result.currentFingerprint { currentFingerprint = result.currentFingerprint }
        if liveValues != result.liveValues { liveValues = result.liveValues }
        if stagedFeatureIDs != result.stagedFeatureIDs { stagedFeatureIDs = result.stagedFeatureIDs }
        if pendingRestartFeatureIDs != result.pendingRestartFeatureIDs { pendingRestartFeatureIDs = result.pendingRestartFeatureIDs }
    }

    /// One background pass over the shared inputs. Pure: reads only
    /// its parameters (and the history/backup files, read-only),
    /// writes nothing, performs no UI work. Runs off the main thread
    /// (`nonisolated`), so disk reads, SHA-256 verification and the
    /// live probe never block scrolling.
    nonisolated private static func compute(
        snapshot: DocumentSnapshot?,
        working: GestaltDocument?,
        backups: [BackupRecord],
        deviceID: String?,
        historyDirectory: URL
    ) -> HomeDiagnosticsResult {
        // 1. History (disk I/O, background). A missing installation
        // id means the history stores are unavailable — never scoped
        // to a guessed id.
        var records: [RecordedChange] = []
        var historyError: String?
        var storedFingerprint: DeviceFingerprint?
        var fingerprintError: String?
        if let deviceID {
            let recordStore = ChangeRecordStore(directory: historyDirectory, deviceID: deviceID)
            do {
                records = try recordStore.load()
            } catch {
                records = []
                historyError = L("The change history could not be read. No system changes were made.")
            }
            let fingerprintStore = DeviceFingerprintStore(directory: historyDirectory, deviceID: deviceID)
            do {
                storedFingerprint = try fingerprintStore.load()
            } catch {
                storedFingerprint = nil
                fingerprintError = L("The device fingerprint could not be read. No system changes were made.")
            }
        } else {
            historyError = L("History is unavailable: no installation ID has been recorded yet.")
            fingerprintError = L("History is unavailable: no installation ID has been recorded yet.")
        }

        // 2. Device report (pure computation). Mirrors the cards:
        // no snapshot means no report, never a fabricated one.
        let deviceReport: LilaDeviceReport? = {
            guard let snapshot else { return nil }
            return LilaIntelligence.report(
                snapshot: snapshot, backups: backups,
                changeRecordCount: records.count)
        }()

        // 3. Backup verifications (disk reads + SHA-256, background).
        // This is the same call the health, diagnosis and restore
        // cards used to make separately on every body evaluation.
        let verifications = RestoreIntelligence.verifyBackups(backups, against: working)

        // 4. SafePatch simulations for the three proposals the home
        // shows (pure computation, no file I/O).
        let proposals = [
            SafePatchProposal.oneTap(),
            SafePatchProposal.aiOnly(),
            SafePatchProposal.esimRegion(),
        ]
        var simulations: [SafePatchProposal: SafePatchSimulation] = [:]
        for proposal in proposals {
            simulations[proposal] = SafePatch.simulate(
                proposal: proposal, snapshot: snapshot,
                currentDocument: working, backups: backups)
        }

        // 5. External modifications (Modified Values report, pure).
        let externalModificationCount: Int = {
            let recordedKeys = Set(records.map(\.key))
            return ModifiedValues.report(for: snapshot).rows
                .filter { !recordedKeys.contains($0.key) }.count
        }()

        // 6. Health score (pure computation, uses the values above).
        // Mirrors the health card: no snapshot means no score.
        let healthScore: SystemHealthScore? = {
            guard let report = deviceReport else { return nil }
            return SystemHealthScorer.score(
                profile: report.profile, snapshot: snapshot,
                backups: backups, backupVerifications: verifications,
                simulation: simulations[SafePatchProposal.oneTap()],
                recordedChanges: records,
                externalModificationCount: externalModificationCount)
        }()

        // 7. Current fingerprint (pure computation).
        let currentFingerprint: DeviceFingerprint? = {
            guard let report = deviceReport else { return nil }
            return DeviceFingerprintCapture.capture(profile: report.profile, snapshot: snapshot)
        }()

        // 8. Live-probe values for the recorded CacheExtra changes.
        // The live Gestalt query can be slow, so it runs here on the
        // background task, never on the main thread or in a body.
        let liveValues = PostModificationAcceptance.liveValues(for: records)

        // 9. Compatibility-status inputs (Phase F): the staged set
        // (snapshot vs working diff) and the restart-pending set
        // (applied records not yet restart-verified). Pure reads of
        // the values above; no eligibility is recomputed here.
        let stagedFeatureIDs = CompatibilityStatusResolver.stagedFeatureIDs(
            snapshot: snapshot, working: working)
        let pendingRestartFeatureIDs = CompatibilityStatusResolver.pendingRestartFeatureIDs(
            records: records)

        return HomeDiagnosticsResult(
            deviceReport: deviceReport,
            backupVerifications: verifications,
            simulations: simulations,
            healthScore: healthScore,
            externalModificationCount: externalModificationCount,
            records: records,
            historyError: historyError,
            storedFingerprint: storedFingerprint,
            fingerprintError: fingerprintError,
            currentFingerprint: currentFingerprint,
            liveValues: liveValues,
            stagedFeatureIDs: stagedFeatureIDs,
            pendingRestartFeatureIDs: pendingRestartFeatureIDs)
    }
}
