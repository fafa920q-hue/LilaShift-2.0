// SPDX-License-Identifier: GPL-3.0-only
// Diagnostics Expansion (诊断扩展) — read-only SwiftUI display.
//
// Shows the battery status (public `UIDevice` API only — health,
// cycle count and capacity are shown as not available, never
// guessed), the app's own container cache sizes with a clear action
// limited to the app's own Caches directory, the device connection
// status from the real device profile and cache read state, and the
// operation log (structured events recorded this session plus the
// app's free-text session log). The card never writes to the
// MobileGestalt cache. The only write in this card is clearing the
// app's own Caches directory, which never touches a system cache.
import SwiftUI

struct DiagnosticsExpansionCard: View {
    @EnvironmentObject private var model: GestaltManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var batteryReader = UIDeviceBatteryReader()
    @State private var battery = BatteryStatus(level: nil, state: .unknown)
    @State private var cacheReport: AppContainerCacheReport?
    @State private var cacheMessage: String?
    @State private var cacheError: String?
    @State private var showingClearCacheConfirmation = false
    @State private var recordedEvents: [OperationEvent] = []
    @State private var records: [RecordedChange] = []

    private var heroTint: Color {
        colorScheme == .dark
            ? Color(red: 0.16, green: 0.13, blue: 0.28).opacity(0.65)
            : Color.lavenderGlass.opacity(0.65)
    }

    /// The per-device report (profile + eligibility evaluations), or
    /// `nil` when the device has not been read yet.
    private var deviceReport: LilaDeviceReport? {
        guard model.snapshot != nil else { return nil }
        return LilaIntelligence.report(
            snapshot: model.snapshot, backups: model.backups,
            changeRecordCount: records.count)
    }

    /// The connection status from the real profile, or the not-read
    /// status when the device has not been read yet.
    private var connectionStatus: DeviceConnectionStatus {
        guard let report = deviceReport else { return .notRead }
        return DeviceConnectionStatus.from(
            profile: report.profile, lastReadAt: model.lastReadAt)
    }

    private var byteFormatter: ByteCountFormatter {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }

    private func formatBytes(_ bytes: Int64) -> String {
        byteFormatter.string(fromByteCount: bytes)
    }

    var body: some View {
        GlassCard(cornerRadius: 22, tint: heroTint) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    GlassIconPedestal(systemImage: "heart.text.square", tint: .gestaltAccent, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Diagnostics Expansion"))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(L("Battery, app cache, connection status and the operation log — read-only."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                batterySection
                Divider()
                appCacheSection
                Divider()
                connectionSection
                Divider()
                operationLogSection

                Button(L("Refresh")) {
                    refresh()
                }
                .font(.subheadline)
            }
        }
        .onAppear { refresh() }
        .confirmationDialog(
            L("Clear App Cache"),
            isPresented: $showingClearCacheConfirmation,
            titleVisibility: .visible
        ) {
            Button(L("Clear App Cache"), role: .destructive) {
                clearAppCache()
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("This clears only this app's own Caches directory. It never touches system caches."))
        }
    }

    private func refresh() {
        battery = batteryReader.read()
        reloadHistory()
        measureCache()
        Task {
            recordedEvents = await model.operationEvents.recordedEvents()
        }
    }

    // MARK: - Battery

    private var batterySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Battery"))
                .font(.headline)
                .foregroundStyle(.primary)
            HStack(spacing: 8) {
                Text(L("Battery level") + ":")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let percent = battery.levelPercent {
                    Text("\(percent)%")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                } else {
                    Text(L("Unknown"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("·")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(L("Battery state") + ": " + battery.state.title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
            Text(BatteryStatus.healthNotAvailable)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - App cache

    private var appCacheSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(L("App Cache"))
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Button(L("Clear App Cache")) {
                    showingClearCacheConfirmation = true
                }
                .font(.subheadline)
                .disabled(cacheReport?.entry(for: .caches)?.byteCount == 0)
            }
            if let report = cacheReport {
                ForEach(AppCacheDirectoryKind.allCases, id: \.self) { kind in
                    if let entry = report.entry(for: kind) {
                        HStack(spacing: 8) {
                            Text(kind.title)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(formatBytes(entry.byteCount))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(String(format: L("%lld files"), entry.fileCount))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                HStack(spacing: 8) {
                    Text(L("Total"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(formatBytes(report.totalBytes))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            } else {
                Text(L("Unknown"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let cacheMessage {
                Text(cacheMessage)
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if let cacheError {
                Text(cacheError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func measureCache() {
        let fileManager = FileManager.default
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheReport = AppContainerCacheMeasurer.measure(
            applicationSupport: applicationSupport, caches: caches,
            temporary: fileManager.temporaryDirectory)
    }

    private func clearAppCache() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        do {
            let freed = try AppContainerCacheMeasurer.clearCaches(at: caches)
            cacheMessage = L("App cache cleared.") + " " + formatBytes(freed)
            cacheError = nil
            measureCache()
        } catch {
            cacheMessage = nil
            cacheError = L("The app cache could not be cleared.")
        }
    }

    // MARK: - Connection status

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Connection Status"))
                .font(.headline)
                .foregroundStyle(.primary)
            if model.snapshot == nil {
                Text(L("Device not read yet"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            connectionRow(label: L("Model"), value: connectionStatus.productType)
            connectionRow(label: "iOS", value: connectionStatus.osVersion)
            connectionRow(label: L("OS Build"), value: connectionStatus.osBuild)
            connectionRow(label: L("Region Code"), value: connectionStatus.regionCode)
            HStack(spacing: 8) {
                Text(L("App Group") + ":")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(connectionStatus.appGroupSummary)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
            HStack(spacing: 8) {
                Text(L("Cache Read") + ":")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(connectionStatus.cacheReadSummary)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
            if let uuid = connectionStatus.cacheUUID {
                HStack(spacing: 8) {
                    Text("CacheUUID:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(uuid)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            HStack(spacing: 8) {
                Text(L("Last Read") + ":")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(connectionStatus.lastReadSummary)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
        }
    }

    private func connectionRow(label: String, value: ProfileValue<String>) -> some View {
        HStack(spacing: 8) {
            Text(label + ":")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value.value ?? L("Unknown"))
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Operation log

    private var operationLogSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Operation Log"))
                .font(.headline)
                .foregroundStyle(.primary)
            Text(OperationLogSnapshot.writeAndRestoreNote)
                .font(.caption)
                .foregroundStyle(.secondary)
            if recordedEvents.isEmpty {
                Text(L("No operation events recorded yet."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recordedEvents) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(event.date.formatted(date: .omitted, time: .standard))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            Text(event.kind.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                        Text(event.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            Text(L("Session Log"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            if model.logs.isEmpty {
                Text(L("No activity yet."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(model.logs.suffix(50).reversed()), id: \.self) { line in
                    Text(line)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func reloadHistory() {
        guard let deviceID = RestoreIntelligence.installationDeviceID else {
            records = []
            return
        }
        let store = ChangeRecordStore(
            directory: RestoreIntelligence.historyDirectory, deviceID: deviceID)
        records = (try? store.load()) ?? []
    }
}
