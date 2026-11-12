import Foundation

@main struct LocalRestoreProvenanceTests {
    struct Failure: Error { let message: String }
    static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message: message) }
    }

    static func main() async throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }
        let device = directory.appendingPathComponent("device.plist")
        func fixture(_ serial: String, _ value: String) throws -> Data {
            try PropertyListSerialization.data(fromPropertyList: [
                "CacheExtra": ["VasUgeSzVyHdB27g2XpN0g": serial, "setting": value],
                "CacheUUID": "same-layout", "CacheVersion": "same-version", "CacheData": Data([0, 1, 2])
            ], format: .binary, options: 0)
        }
        let initialBytes = try fixture("current-device", "original")
        try initialBytes.write(to: device)
        let store = GestaltFileStore(deviceURL: device, backupDirectory: directory.appendingPathComponent("backups"),
                                     deviceID: "provenance-fixture", acquire: { 1 }, release: { _ in })
        let live = try await store.loadDevice()
        var verified = try await store.loadLocal(data: initialBytes, name: "verified-export.plist")
        verified.ownershipVerified = true
        var edit = verified.document
        edit.set("local edit", for: "setting")
        let savedEdit = try await store.commit(edit, expected: verified)
        try expect(savedEdit.ownershipVerified, "Ordinary edits preserve a verified import's ownership")

        let untrustedBytes = try fixture("foreign-device", "unverified backup")
        let untrusted = try await store.loadLocal(data: untrustedBytes, name: "foreign.plist")
        try await store.backup(untrusted)
        let record = try await store.backups().first { $0.source == .local && $0.reason == "Manual backup" }!
        let replacement = try GestaltDocument(data: await store.backupData(record))
        let restored = try await store.commit(replacement, expected: savedEdit, restoring: record)
        try expect(restored.source == .local && restored.document.matches(replacement), "Unverified backups remain available for local editing")
        try expect(!restored.ownershipVerified, "A replacement backup must not inherit the previous import's device ownership")
        do {
            _ = try await store.restoreVerifiedImport(restored, expected: live)
            throw Failure(message: "The replacement backup incorrectly qualified as a verified import")
        } catch let failure as GestaltFailure {
            try expect(failure.key == "This plist's device proof could not be verified on this device.", "Reject replacement at the ownership gate")
        }
        try expect(try Data(contentsOf: device) == initialBytes, "Local replacement never writes the device")

        var anotherEdit = restored.document
        anotherEdit.set("further edit", for: "setting")
        let stillUnverified = try await store.commit(anotherEdit, expected: restored)
        try expect(!stillUnverified.ownershipVerified, "Later edits cannot regain the discarded ownership")
        let identical = try await store.commit(verified.document, expected: verified, restoring: record)
        try expect(!identical.ownershipVerified, "A backup replacement requires fresh verification even when its values happen to match")

        // --- P0-2 backup provenance ---
        let provenanceDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: provenanceDir, withIntermediateDirectories: true)
        let provenanceDevice = provenanceDir.appendingPathComponent("device.plist")
        try initialBytes.write(to: provenanceDevice)
        let writingStore = GestaltFileStore(deviceURL: provenanceDevice,
                                            backupDirectory: provenanceDir.appendingPathComponent("backups"),
                                            deviceID: "provenance-writing", acquire: { 1 }, release: { _ in },
                                            writeData: { data, url in try data.write(to: url) })
        let liveSnapshot = try await writingStore.loadDevice()
        try expect(liveSnapshot.provenance == .firstRead,
                   "A live device snapshot is first-read state, not factory state")
        let importedSnapshot = try await writingStore.loadLocal(data: initialBytes, name: "imported.plist")
        try expect(importedSnapshot.provenance == .importedHistory,
                   "A locally opened file is imported history, not factory state")

        // A pre-write backup records pre-modification provenance, and it
        // survives the JSON round-trip through the backup listing.
        var deviceEdit = liveSnapshot.document
        deviceEdit.set("edited", for: "setting")
        _ = try await writingStore.commit(deviceEdit, expected: liveSnapshot)
        let writtenBackups = try await writingStore.backups()
        try expect(writtenBackups.first { $0.reason == "Before applying" }?.provenance == .preModification,
                   "A backup taken before applying records pre-modification provenance")
        try expect(writtenBackups.first { $0.reason == "Initial backup" }?.provenance == .firstRead,
                   "The initial backup keeps first-read provenance after later writes")

        // Manual backups record what they read: live device reads are
        // first-read state; local snapshots are imported history.
        try await writingStore.backup(liveSnapshot)
        let manualDevice = try await writingStore.backups().first { $0.reason == "Manual backup" && $0.source == .device }
        try expect(manualDevice?.provenance == .firstRead,
                   "A manual backup of the live device is first-read state")
        let localSnapshot = try await writingStore.loadLocal(data: initialBytes, name: "manual-local.plist")
        try await writingStore.backup(localSnapshot)
        let manualLocal = try await writingStore.backups().first { $0.reason == "Manual backup" && $0.source == .local }
        try expect(manualLocal?.provenance == .importedHistory,
                   "A manual backup of a local file is imported history")

        // A verified import is saved as imported history even though it is
        // stored as a device backup for the restore mechanics, and the
        // restored snapshot carries that provenance.
        let changedBytes = try fixture("current-device", "imported-change")
        var imported = try await writingStore.loadLocal(data: changedBytes, name: "verified-import.plist")
        imported.ownershipVerified = true
        let currentLive = try await writingStore.loadDevice()
        let restoredVerified = try await writingStore.restoreVerifiedImport(imported, expected: currentLive)
        try expect(restoredVerified.provenance == .importedHistory,
                   "A restored verified import carries imported-history provenance")
        let verifiedRecord = try await writingStore.backups().first { $0.reason == "Verified import" }
        try expect(verifiedRecord?.provenance == .importedHistory && verifiedRecord?.source == .device,
                   "A verified import is recorded as imported history, not as a device-origin backup")
        try expect(try await writingStore.backups().first { $0.reason == "Before restoring" }?.provenance == .preModification,
                   "Restoring first records the pre-restoration state")

        print("PASS: local edits preserve provenance; backup replacement clears it and cannot restore the device; first-read, pre-modification and imported-history backups are recorded and distinguishable.")
    }
}
