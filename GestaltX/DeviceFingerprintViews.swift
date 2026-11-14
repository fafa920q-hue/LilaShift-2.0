// SPDX-License-Identifier: GPL-3.0-only
// Device Capability Fingerprint (设备能力指纹) — read-only SwiftUI
// display.
//
// Shows the stored fingerprint for this device (when one exists),
// the current fingerprint from the latest read, and what changed
// between them. A change to the product type, OS build, cache layout
// or slot count flags that the previously recorded support scope may
// no longer apply and re-verification is needed. "Save fingerprint"
// only writes the app's own history file, never the MobileGestalt
// cache. A device that has never been read has no fingerprint —
// the card says so, instead of showing a default one.
import SwiftUI

struct DeviceFingerprintCard: View {
    @EnvironmentObject private var model: GestaltManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var stored: DeviceFingerprint?
    @State private var fingerprintError: String?
    @State private var saveMessage: String?
    @State private var showingDetails = false

    private var heroTint: Color {
        colorScheme == .dark
            ? Color(red: 0.16, green: 0.13, blue: 0.28).opacity(0.65)
            : Color.lavenderGlass.opacity(0.65)
    }

    /// The current fingerprint from the latest read, or `nil` when
    /// the device has not been read yet.
    private var current: DeviceFingerprint? {
        guard model.snapshot != nil else { return nil }
        let report = LilaIntelligence.report(
            snapshot: model.snapshot, backups: model.backups)
        return DeviceFingerprintCapture.capture(profile: report.profile, snapshot: model.snapshot)
    }

    private var comparison: FingerprintComparison? {
        guard let stored, let current else { return nil }
        return DeviceFingerprintCapture.compare(stored: stored, current: current)
    }

    var body: some View {
        GlassCard(cornerRadius: GlassTokens.cardRadius, tint: heroTint) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    GlassIconPedestal(systemImage: "fingerprint", tint: .gestaltAccent, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Device Capability Fingerprint"))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(L("This device's real capabilities and build, recorded locally with a SHA-256 digest."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if model.snapshot == nil {
                    Text(L("Read the device first to capture its fingerprint."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(L(model.isBusy ? "Reading…" : "Read Device")) {
                        Task { await model.connect() }
                    }
                    .buttonStyle(GlassPrimaryButtonStyle())
                    .disabled(model.isBusy)
                    .opacity(model.isBusy ? 0.5 : 1)
                } else if let current {
                    if stored == nil {
                        Text(L("No fingerprint has been recorded for this device yet."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else if let comparison {
                        if comparison.differentDevice {
                            Text(L("The stored fingerprint belongs to a different device. It was not used."))
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        } else if comparison.changes.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text(L("Fingerprint unchanged since it was recorded."))
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                            }
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text(String(format: L("%d fields changed since the fingerprint was recorded."), comparison.changes.count))
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                            }
                            if comparison.invalidatesSupportScope {
                                Text(L("The recorded support scope may no longer apply. Re-verification is needed before staging."))
                                    .font(.subheadline)
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    Text(String(format: L("Recorded %@ · Digest %@"), current.recordedAt.formatted(date: .abbreviated, time: .shortened), String(current.digest.prefix(16))))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button(showingDetails ? L("Hide Details") : L("Show Details")) {
                        showingDetails.toggle()
                    }
                    .font(.subheadline)

                    if showingDetails, let comparison, !comparison.changes.isEmpty {
                        ForEach(comparison.changes) { change in
                            HStack(spacing: 8) {
                                Text(change.displayName)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(change.old) → \(change.new)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Button(L("Save current fingerprint")) {
                        saveCurrent(current)
                    }
                    .buttonStyle(GlassPrimaryButtonStyle())

                    if let saveMessage {
                        Text(saveMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let fingerprintError {
                        Text(fingerprintError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Text(L("The fingerprint is stored only on this device, in the app's own history. It is never sent anywhere."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { loadStored() }
        .onChange(of: model.working != nil) { _, _ in loadStored() }
    }

    private func loadStored() {
        guard let deviceID = RestoreIntelligence.installationDeviceID else {
            fingerprintError = L("History is unavailable: no installation ID has been recorded yet.")
            stored = nil
            return
        }
        let store = DeviceFingerprintStore(
            directory: RestoreIntelligence.historyDirectory, deviceID: deviceID)
        do {
            stored = try store.load()
            fingerprintError = nil
        } catch {
            stored = nil
            fingerprintError = L("The device fingerprint could not be read. No system changes were made.")
        }
    }

    private func saveCurrent(_ fingerprint: DeviceFingerprint) {
        guard let deviceID = RestoreIntelligence.installationDeviceID else {
            fingerprintError = L("History is unavailable: no installation ID has been recorded yet.")
            return
        }
        let store = DeviceFingerprintStore(
            directory: RestoreIntelligence.historyDirectory, deviceID: deviceID)
        do {
            try store.save(fingerprint)
            stored = fingerprint
            saveMessage = L("Fingerprint saved.")
            fingerprintError = nil
        } catch {
            saveMessage = nil
            fingerprintError = L("The device fingerprint could not be saved. No system changes were made.")
        }
    }
}
