// SPDX-License-Identifier: GPL-3.0-only
// Diagnostics Expansion (诊断扩展) — battery status, the app's own
// container cache, device connection status, and the operation log.
// Pure Foundation plus UIKit for the battery (public API only) — no
// singletons, no global mutable state. Read-only, except for one
// action: clearing the app's OWN Caches directory.
//
// Honesty rules, enforced by the types:
//   • Battery level and state come from `UIDevice` (public API).
//     Battery health, cycle count and capacity are NOT available
//     through any public iOS API: they are shown as "not available",
//     never a guessed value.
//   • Cache sizes are real numbers from FileManager over the app's
//     OWN container (Application Support, Caches, tmp). System
//     caches are never read, and the clear action only removes the
//     contents of the app's own Caches directory — it refuses any
//     other directory, and it never touches a system cache.
//   • Connection status is built from the real device profile
//     (`DeviceProfiler`) and the real cache read state. Unknown stays
//     unknown; the last-read time is `nil` until a read happens.
//   • The operation log shows structured events recorded by
//     `OperationEventRecorder` plus the app's existing free-text
//     session log. Write, restore and guard events are NOT recorded
//     yet: the only hook points for them are inside the write path
//     (`apply()` / `stage*` / `restore*`), which this version must
//     not touch — the viewer says so explicitly instead of
//     pretending the log is complete.
import Foundation
import UIKit

// MARK: - Battery

/// Battery state, mapped from `UIDevice.BatteryState`. `.unknown`
/// is a real state (the device cannot report one), never a guess.
enum BatteryState: String, Equatable, Codable, Sendable {
    case unknown
    case unplugged
    case charging
    case full

    var title: String {
        switch self {
        case .unknown: return L("Unknown")
        case .unplugged: return L("Unplugged")
        case .charging: return L("Charging")
        case .full: return L("Full")
        }
    }
}

/// The battery status from the public `UIDevice` API. `level` is
/// 0.0–1.0, or `nil` when the device reports -1.0 (unknown).
/// Battery health, cycle count and capacity are NOT in this struct:
/// no public iOS API exposes them, so this layer never claims them.
struct BatteryStatus: Equatable, Sendable {
    let level: Double?
    let state: BatteryState

    /// The honest note every battery display must carry: health,
    /// cycle count and capacity are not available through public
    /// iOS APIs.
    static let healthNotAvailable =
        L("Battery health, cycle count and capacity are not available through public iOS APIs.")

    /// The level as a whole percent, or `nil` when unknown.
    var levelPercent: Int? {
        guard let level else { return nil }
        return Int((level * 100).rounded())
    }

    /// Pure mapping from the `UIDevice` readings. A level of -1.0
    /// (what `UIDevice` reports when it cannot determine the level)
    /// becomes `nil`.
    static func from(level: Double, state: UIDevice.BatteryState) -> BatteryStatus {
        let mappedState: BatteryState
        switch state {
        case .unknown: mappedState = .unknown
        case .unplugged: mappedState = .unplugged
        case .charging: mappedState = .charging
        case .full: mappedState = .full
        @unknown default: mappedState = .unknown
        }
        return BatteryStatus(level: level < 0 ? nil : min(max(level, 0), 1), state: mappedState)
    }
}

/// A source of battery status. The production source reads
/// `UIDevice`; tests inject a stub. Reading the battery enables
/// battery monitoring on `UIDevice` (a public, app-wide setting).
protocol BatteryStatusSource: Sendable {
    func read() -> BatteryStatus
}

/// Reads the battery from `UIDevice` (public API). Enabling
/// monitoring is done once, in `init`.
final class UIDeviceBatteryReader: BatteryStatusSource {
    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    func read() -> BatteryStatus {
        BatteryStatus.from(
            level: Double(UIDevice.current.batteryLevel),
            state: UIDevice.current.batteryState)
    }
}

// MARK: - App container cache

/// One of the app's own container directories.
enum AppCacheDirectoryKind: String, Equatable, Hashable, CaseIterable, Sendable {
    case applicationSupport
    case caches
    case temporary

    var title: String {
        switch self {
        case .applicationSupport: return L("Application Support")
        case .caches: return L("Caches")
        case .temporary: return L("Temporary")
        }
    }
}

/// The measured size of one of the app's own container directories.
/// Real numbers from FileManager; a missing directory measures as
/// zero, never an error.
struct AppContainerCacheEntry: Equatable, Sendable {
    let kind: AppCacheDirectoryKind
    let byteCount: Int64
    let fileCount: Int
}

/// The measured sizes of the app's own container directories.
struct AppContainerCacheReport: Equatable, Sendable {
    let entries: [AppContainerCacheEntry]
    let measuredAt: Date

    var totalBytes: Int64 { entries.reduce(0) { $0 + $1.byteCount } }
    var totalFiles: Int { entries.reduce(0) { $0 + $1.fileCount } }

    func entry(for kind: AppCacheDirectoryKind) -> AppContainerCacheEntry? {
        entries.first { $0.kind == kind }
    }
}

/// Measures the app's OWN container directories, and clears the
/// app's OWN Caches directory. The URLs are injected so tests can
/// measure a temporary directory; the production caller passes the
/// real container URLs from FileManager.
enum AppContainerCacheMeasurer {
    /// Measures the three container directories. Read-only: nothing
    /// is created, moved or deleted.
    static func measure(
        applicationSupport: URL, caches: URL, temporary: URL
    ) -> AppContainerCacheReport {
        AppContainerCacheReport(
            entries: [
                measureOne(.applicationSupport, url: applicationSupport),
                measureOne(.caches, url: caches),
                measureOne(.temporary, url: temporary),
            ],
            measuredAt: Date())
    }

    private static func measureOne(_ kind: AppCacheDirectoryKind, url: URL) -> AppContainerCacheEntry {
        var bytes: Int64 = 0
        var files = 0
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles], errorHandler: nil) else {
            return AppContainerCacheEntry(kind: kind, byteCount: 0, fileCount: 0)
        }
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            files += 1
            bytes += Int64(values.fileSize ?? 0)
        }
        return AppContainerCacheEntry(kind: kind, byteCount: bytes, fileCount: files)
    }

    /// Clears the app's OWN Caches directory: removes its contents,
    /// never the directory itself, and returns the bytes freed.
    /// Refuses any URL whose last component is not "Caches", so a
    /// wrong URL can never delete another directory. System caches
    /// are never touched.
    static func clearCaches(at cachesURL: URL) throws -> Int64 {
        guard cachesURL.lastPathComponent == "Caches" else {
            throw GestaltFailure("Refusing to clear a directory that is not the app's Caches directory.")
        }
        let before = measureOne(.caches, url: cachesURL)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: cachesURL, includingPropertiesForKeys: nil)) ?? []
        for item in contents {
            try FileManager.default.removeItem(at: item)
        }
        let after = measureOne(.caches, url: cachesURL)
        guard after.fileCount == 0 else {
            throw GestaltFailure("The app cache could not be cleared.")
        }
        return before.byteCount - after.byteCount
    }
}

// MARK: - Device connection status

/// The device connection status, from real data only: the device
/// profile (model, OS, region, App Group) and the cache read state
/// (whether the last read succeeded, how many bytes). `lastReadAt`
/// is the time of the last successful read, or `nil` when no read
/// has happened — unknown stays unknown.
struct DeviceConnectionStatus: Equatable, Sendable {
    let productType: ProfileValue<String>
    let osVersion: ProfileValue<String>
    let osBuild: ProfileValue<String>
    let regionCode: ProfileValue<String>
    let appGroupAvailable: ProfileValue<Bool>
    let cacheReadState: CacheReadState
    let lastReadAt: Date?

    static func from(profile: DeviceProfile, lastReadAt: Date?) -> DeviceConnectionStatus {
        DeviceConnectionStatus(
            productType: profile.productType,
            osVersion: profile.osVersion,
            osBuild: profile.osBuild,
            regionCode: profile.regionCode,
            appGroupAvailable: profile.appGroupAvailable,
            cacheReadState: profile.cacheReadState,
            lastReadAt: lastReadAt)
    }

    /// The status when the device has never been read: every field
    /// unknown, no read state, no last-read time.
    static var notRead: DeviceConnectionStatus {
        DeviceConnectionStatus(
            productType: .unknown(reason: L("Device not read yet")),
            osVersion: .unknown(reason: L("Device not read yet")),
            osBuild: .unknown(reason: L("Device not read yet")),
            regionCode: .unknown(reason: L("Device not read yet")),
            appGroupAvailable: .unknown(reason: L("Device not read yet")),
            cacheReadState: .notRead,
            lastReadAt: nil)
    }

    var appGroupSummary: String {
        switch appGroupAvailable {
        case .known(true): return L("Available")
        case .known(false): return L("Unavailable")
        case .unknown: return L("Unknown")
        }
    }

    var cacheReadSummary: String {
        switch cacheReadState {
        case .notRead:
            return L("Not read yet")
        case .read(_, let byteCount):
            return String(format: L("Read: %lld bytes"), byteCount)
        case .failed(let reason):
            return reason
        }
    }

    /// The CacheUUID of the last read, or `nil` when nothing was read.
    var cacheUUID: String? {
        if case .read(let uuid, _) = cacheReadState { return uuid }
        return nil
    }

    var lastReadSummary: String {
        guard let lastReadAt else { return L("Unknown") }
        return lastReadAt.formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - Operation event recorder

/// An append-only, in-memory recorder for structured operation
/// events. It only OBSERVES: the manager layer calls `record` after
/// an operation it already performed (a read, a backup) has
/// finished, and recording never changes the operation's outcome.
/// `record` cannot throw and cannot block the caller: it is an actor
/// method, safe to call from any thread, and the manager calls it
/// fire-and-forget. Events are kept for this session only (newest
/// 500); nothing is written to disk.
///
/// What is recorded in P4: read outcomes (`readSucceeded` /
/// `readFailed`) and backup creation (`backupCreated`). Write,
/// restore and guard events are NOT recorded yet — the only hook
/// points for them are inside the write path (`apply()` /
/// `stage*` / `restore*`), which this version must not touch. The
/// viewer states that gap explicitly (see
/// `OperationLogSnapshot.writeAndRestoreEventsConnected`).
actor OperationEventRecorder {
    static let maxEvents = 500

    private var stored: [OperationEvent] = []

    /// Records one event. Never throws; never affects the operation
    /// that produced the event.
    func record(_ event: OperationEvent) {
        stored.append(event)
        if stored.count > Self.maxEvents {
            stored.removeFirst(stored.count - Self.maxEvents)
        }
    }

    /// All recorded events, newest first.
    func recordedEvents() -> [OperationEvent] {
        stored.reversed()
    }

    var count: Int { stored.count }

    func clear() {
        stored = []
    }
}

// MARK: - Operation log snapshot (what the viewer shows)

/// Everything the operation log viewer shows: the recorded
/// structured events, the app's free-text session log lines, and
/// the explicit statement that write/restore/guard events are not
/// connected yet. The viewer never presents the log as complete.
struct OperationLogSnapshot: Equatable, Sendable {
    let events: [OperationEvent]
    let freeTextLines: [String]

    /// False in P4, by design: write, restore and guard events are
    /// not recorded yet (see `OperationEventRecorder`). The viewer
    /// shows this as an explicit "not connected yet" line.
    static let writeAndRestoreEventsConnected = false

    /// The note the viewer shows about the gap: why write/restore
    /// events are missing, in plain language.
    static let writeAndRestoreNote =
        L("Write, restore and guard events are not recorded yet: the only hook points are inside the write path, which this version must not touch.")

    var hasEvents: Bool { !events.isEmpty }
    var hasFreeTextLines: Bool { !freeTextLines.isEmpty }
}
