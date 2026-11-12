import Foundation

/// Offline tests for the item-2 dual vault backup: the 4-check gate and the
/// install / reinstall / corrupt-digest flow. The "system" directory is a
/// temp directory here; on device it is the shared mobilegestaltcache
/// Caches directory next to the live plist.
@main struct SystemVaultTests {
    struct Failure: Error { let message: String }
    static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message: message) }
    }

    static func fixtureData(uuid: String = "7F1DF278-18B7-4E5A-8425-09E8830DE9AF",
                            version: String = "24C5037i",
                            productType: String = "iPhone18,1",
                            cacheBytes: Int = 6480) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: [
            "CacheVersion": version, "CacheUUID": uuid,
            "CacheData": Data(count: cacheBytes),
            "CacheExtra": [GestaltKeys.productType: productType, GestaltKeys.regionCode: "CH"],
        ], format: .binary, options: 0)
    }

    static func main() async throws {
        // Known-answer digest.
        try expect(GestaltFileStore.sha256Hex(of: Data("abc".utf8))
                   == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                   "SHA-256 hex matches the known digest of 'abc'")

        // The 4-check gate: matching passes; each single mismatch fails.
        let live = try GestaltDocument(data: fixtureData())
        try expect(GestaltFileStore.vaultMatchesLive(vaultData: fixtureData(), live: live),
                   "Matching vault passes all four checks")
        try expect(!GestaltFileStore.vaultMatchesLive(
                       vaultData: fixtureData(uuid: "BBBBBBBB-1111-2222-3333-123456789ABC"), live: live),
                   "UUID mismatch fails the gate")
        try expect(!GestaltFileStore.vaultMatchesLive(vaultData: fixtureData(version: "24C5037j"), live: live),
                   "CacheVersion mismatch fails the gate")
        try expect(!GestaltFileStore.vaultMatchesLive(vaultData: fixtureData(productType: "iPhone18,2"), live: live),
                   "ProductType mismatch fails the gate")
        try expect(!GestaltFileStore.vaultMatchesLive(vaultData: fixtureData(cacheBytes: 6471), live: live),
                   "CacheData length mismatch fails the gate")
        try expect(!GestaltFileStore.vaultMatchesLive(vaultData: Data("not a plist".utf8), live: live),
                   "Unparseable vault fails the gate")

        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }
        let deviceURL = directory.appendingPathComponent("com.apple.MobileGestalt.plist")
        let liveBytes = try fixtureData()
        try liveBytes.write(to: deviceURL)
        let vaultURL = directory.appendingPathComponent(".gestaltx_factory_vault.plist")
        let digestURL = vaultURL.appendingPathExtension("sha256")
        let provenanceURL = vaultURL.appendingPathExtension("provenance")

        // First install: loadDevice creates the initial backup and mirrors
        // it into the vault with a SHA-256 sidecar.
        let first = GestaltFileStore(deviceURL: deviceURL,
                                     backupDirectory: directory.appendingPathComponent("backups1"),
                                     deviceID: "install-1", acquire: { 1 }, release: { _ in })
        _ = try await first.loadDevice()
        try expect(fm.fileExists(atPath: vaultURL.path) && fm.fileExists(atPath: digestURL.path),
                   "First load mirrors the factory backup into the vault")
        try expect(try Data(contentsOf: vaultURL) == liveBytes,
                   "Vault content equals the live bytes")
        try expect(try String(contentsOf: digestURL, encoding: .utf8)
                   == GestaltFileStore.sha256Hex(of: liveBytes),
                   "Vault sidecar holds the SHA-256 of the vault bytes")
        try expect(try await first.backups().count == 1, "First load saves one initial backup")
        let firstBackups = try await first.backups()
        try expect(firstBackups[0].provenance == .firstRead,
                   "The first backup is recorded as first-read state, never factory state")
        try expect(try String(contentsOf: provenanceURL, encoding: .utf8) == BackupProvenance.firstRead.rawValue,
                   "The vault sidecar records first-read provenance on first load")

        // Reinstall (new installation ID, empty backup directory, same
        // device directory): the factory backup is recovered from the vault.
        // The recovered bytes are the first read mirrored on first install,
        // so they are first-read state, not verified factory state.
        let second = GestaltFileStore(deviceURL: deviceURL,
                                      backupDirectory: directory.appendingPathComponent("backups2"),
                                      deviceID: "install-2", acquire: { 1 }, release: { _ in })
        _ = try await second.loadDevice()
        let recovered = try await second.backups()
        try expect(recovered.count == 1 && recovered[0].reason == "Initial backup",
                   "Reinstall restores one initial backup from the vault")
        try expect(recovered[0].provenance == .firstRead,
                   "A vault recovery of a first-read mirror stays first-read state, never factory state")
        try expect(try await second.backupData(recovered[0]) == liveBytes,
                   "Recovered backup bytes match the live bytes")

        // Corrupt digest: recovery fails, a fresh initial backup is made
        // instead, and the vault is re-synced to the live bytes.
        try String(repeating: "0", count: 64).write(to: digestURL, atomically: true, encoding: .utf8)
        let third = GestaltFileStore(deviceURL: deviceURL,
                                     backupDirectory: directory.appendingPathComponent("backups3"),
                                     deviceID: "install-3", acquire: { 1 }, release: { _ in })
        _ = try await third.loadDevice()
        try expect(try await third.backups().count == 1, "Corrupt digest still yields a fresh initial backup")
        try expect(try String(contentsOf: digestURL, encoding: .utf8)
                   == GestaltFileStore.sha256Hex(of: liveBytes),
                   "A corrupt digest is replaced by a re-synced vault sidecar")
        try expect(try String(contentsOf: provenanceURL, encoding: .utf8) == BackupProvenance.firstRead.rawValue,
                   "A re-synced vault records first-read provenance")

        // Stale vault (different CacheUUID, correct digest for its own
        // bytes): a digest-valid vault is an earlier valid backup, so it is
        // kept, never silently replaced — stale is not invalid, and the
        // factory copy for an older cache generation must survive. A fresh
        // first-read local backup is still created.
        let stale = try fixtureData(uuid: "BBBBBBBB-1111-2222-3333-123456789ABC")
        try stale.write(to: vaultURL)
        try GestaltFileStore.sha256Hex(of: stale).write(to: digestURL, atomically: true, encoding: .utf8)
        let fourth = GestaltFileStore(deviceURL: deviceURL,
                                      backupDirectory: directory.appendingPathComponent("backups4"),
                                      deviceID: "install-4", acquire: { 1 }, release: { _ in })
        _ = try await fourth.loadDevice()
        try expect(try Data(contentsOf: vaultURL) == stale,
                   "A digest-valid stale vault is kept, never replaced by the live baseline")
        let fourthBackups = try await fourth.backups()
        try expect(fourthBackups.count == 1 && fourthBackups[0].provenance == .firstRead,
                   "A stale vault still yields a fresh first-read local backup")

        // --- P0-2 provenance ---
        // The five cases are distinct, round-trip through JSON, and the
        // first-read label never claims factory state.
        try expect(BackupProvenance.allCases.count == 5, "Five provenance cases exist")
        try expect(Set(BackupProvenance.allCases.map(\.rawValue)).count == 5,
                   "Each provenance case has a distinct raw value")
        try expect(Set(BackupProvenance.allCases.map(\.displayLabel)).count == 5,
                   "Each provenance case has a distinct user-facing label")
        try expect(BackupProvenance.firstRead.displayLabel != BackupProvenance.verifiedFactory.displayLabel,
                   "First-read state is labelled differently from a verified factory backup")
        try expect(BackupProvenance.allCases.filter(\.isFactory) == [.verifiedFactory],
                   "Only a verified factory backup claims factory state")
        for provenance in BackupProvenance.allCases {
            let record = BackupRecord(id: UUID(), date: Date(), reason: "Manual backup", source: .device,
                                      deviceID: "roundtrip", byteCount: 3, sha256: nil, provenance: provenance)
            let decoded = try JSONDecoder().decode(BackupRecord.self, from: JSONEncoder().encode(record))
            try expect(decoded.provenance == provenance,
                       "Provenance survives a JSON round-trip: \(provenance.rawValue)")
            try expect(decoded.provenanceLabel == provenance.displayLabel,
                       "Record label matches its provenance: \(provenance.rawValue)")
        }
        // Legacy JSON without a provenance key infers honestly from the
        // reason: pre-write reasons are pre-modification history; an initial
        // backup is unknown, never assumed to be factory state.
        func legacyProvenance(reason: String, source: DocumentSource) throws -> BackupProvenance {
            var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
                BackupRecord(id: UUID(), date: Date(), reason: reason, source: source,
                             deviceID: "legacy", byteCount: 3))) as! [String: Any]
            json.removeValue(forKey: "provenance")
            return try JSONDecoder().decode(BackupRecord.self, from: JSONSerialization.data(withJSONObject: json)).provenance
        }
        try expect(try legacyProvenance(reason: "Before applying", source: .device) == .preModification,
                   "Legacy pre-write backup infers pre-modification provenance")
        try expect(try legacyProvenance(reason: "Before restoring", source: .device) == .preModification,
                   "Legacy pre-restore backup infers pre-modification provenance")
        try expect(try legacyProvenance(reason: "Initial backup", source: .device) == .unknown,
                   "Legacy initial backup does not infer factory provenance")
        try expect(try legacyProvenance(reason: "Original values snapshot", source: .device) == .unknown,
                   "Legacy original-values snapshot does not infer factory provenance")
        try expect(try legacyProvenance(reason: "Verified import", source: .device) == .importedHistory,
                   "Legacy verified import infers imported-history provenance")
        try expect(try legacyProvenance(reason: "Manual backup", source: .local) == .importedHistory,
                   "Legacy local manual backup infers imported-history provenance")
        try expect(try legacyProvenance(reason: "Manual backup", source: .device) == .firstRead,
                   "Legacy device manual backup infers first-read provenance")

        // A digest-valid verified factory vault is never overwritten: not by
        // a later first read, and not when the live device has since been
        // modified. Recovery keeps the vault and its provenance.
        let factoryDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: factoryDir, withIntermediateDirectories: true)
        let factoryDevice = factoryDir.appendingPathComponent("com.apple.MobileGestalt.plist")
        try liveBytes.write(to: factoryDevice)
        let factoryVault = factoryDir.appendingPathComponent(".gestaltx_factory_vault.plist")
        let factoryDigest = factoryVault.appendingPathExtension("sha256")
        let factorySidecar = factoryVault.appendingPathExtension("provenance")
        try liveBytes.write(to: factoryVault)
        try GestaltFileStore.sha256Hex(of: liveBytes).write(to: factoryDigest, atomically: true, encoding: .utf8)
        try BackupProvenance.verifiedFactory.rawValue.write(to: factorySidecar, atomically: true, encoding: .utf8)
        var modifiedDoc = try GestaltDocument(data: liveBytes)
        modifiedDoc.set("US", for: GestaltKeys.regionCode)
        try modifiedDoc.encoded().write(to: factoryDevice)
        let factoryStore = GestaltFileStore(deviceURL: factoryDevice,
                                            backupDirectory: factoryDir.appendingPathComponent("backups"),
                                            deviceID: "factory-1", acquire: { 1 }, release: { _ in })
        _ = try await factoryStore.loadDevice()
        let factoryBackups = try await factoryStore.backups()
        try expect(factoryBackups.count == 1 && factoryBackups[0].provenance == .verifiedFactory,
                   "Reinstall recovery restores the verified factory backup")
        try expect(try Data(contentsOf: factoryVault) == liveBytes,
                   "A verified factory vault is never overwritten by a later first read")
        try expect(try String(contentsOf: factorySidecar, encoding: .utf8) == BackupProvenance.verifiedFactory.rawValue,
                   "The verified factory provenance sidecar survives recovery")
        var modifiedAgain = try GestaltDocument(data: liveBytes)
        modifiedAgain.set("LL", for: GestaltKeys.regionCode)
        try modifiedAgain.encoded().write(to: factoryDevice)
        let factoryStore2 = GestaltFileStore(deviceURL: factoryDevice,
                                             backupDirectory: factoryDir.appendingPathComponent("backups2"),
                                             deviceID: "factory-2", acquire: { 1 }, release: { _ in })
        _ = try await factoryStore2.loadDevice()
        try expect(try Data(contentsOf: factoryVault) == liveBytes,
                   "First-read state never overwrites a verified factory vault")
        let factoryBackups2 = try await factoryStore2.backups()
        try expect(factoryBackups2.count == 1 && factoryBackups2[0].provenance == .verifiedFactory,
                   "Later reinstalls still recover the factory backup")

        // Reinstall recovery requires the digest: vault bytes without a
        // digest file are not recovered, and a legacy vault without a
        // provenance sidecar recovers as unknown provenance, never factory.
        let digestDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: digestDir, withIntermediateDirectories: true)
        let digestDevice = digestDir.appendingPathComponent("com.apple.MobileGestalt.plist")
        try liveBytes.write(to: digestDevice)
        let digestVault = digestDir.appendingPathComponent(".gestaltx_factory_vault.plist")
        try liveBytes.write(to: digestVault)
        let noDigestStore = GestaltFileStore(deviceURL: digestDevice,
                                             backupDirectory: digestDir.appendingPathComponent("backups-nodigest"),
                                             deviceID: "digest-1", acquire: { 1 }, release: { _ in })
        _ = try await noDigestStore.loadDevice()
        let noDigestBackups = try await noDigestStore.backups()
        try expect(noDigestBackups.count == 1 && noDigestBackups[0].provenance == .firstRead,
                   "Without a digest the vault is not recovered; a fresh first-read backup is made")
        try expect(try Data(contentsOf: digestVault) == liveBytes
                   && String(contentsOf: digestVault.appendingPathExtension("provenance"), encoding: .utf8) == BackupProvenance.firstRead.rawValue,
                   "A digest-less vault is re-synced as first-read state once its digest is written")
        let legacyDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        let legacyDevice = legacyDir.appendingPathComponent("com.apple.MobileGestalt.plist")
        try liveBytes.write(to: legacyDevice)
        let legacyVault = legacyDir.appendingPathComponent(".gestaltx_factory_vault.plist")
        try liveBytes.write(to: legacyVault)
        try GestaltFileStore.sha256Hex(of: liveBytes).write(to: legacyVault.appendingPathExtension("sha256"), atomically: true, encoding: .utf8)
        let legacyStore = GestaltFileStore(deviceURL: legacyDevice,
                                           backupDirectory: legacyDir.appendingPathComponent("backups"),
                                           deviceID: "legacy-1", acquire: { 1 }, release: { _ in })
        _ = try await legacyStore.loadDevice()
        let legacyBackups = try await legacyStore.backups()
        try expect(legacyBackups.count == 1 && legacyBackups[0].provenance == .unknown,
                   "A legacy vault without a provenance sidecar recovers as unknown provenance, never as factory")

        print("PASS: vault 4-check gate refuses each single mismatch; first load records a first-read backup and mirrors it with SHA-256 and provenance sidecars; reinstall recovers the recorded provenance; a digest-valid vault (factory or stale) is never overwritten; recovery requires the digest; legacy vaults recover as unknown provenance, never as factory.")
    }
}
