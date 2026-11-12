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

        // Reinstall (new installation ID, empty backup directory, same
        // device directory): the factory backup is recovered from the vault.
        let second = GestaltFileStore(deviceURL: deviceURL,
                                      backupDirectory: directory.appendingPathComponent("backups2"),
                                      deviceID: "install-2", acquire: { 1 }, release: { _ in })
        _ = try await second.loadDevice()
        let recovered = try await second.backups()
        try expect(recovered.count == 1 && recovered[0].reason == "Initial backup",
                   "Reinstall restores one initial backup from the vault")
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

        // Stale vault (different CacheUUID, correct digest for its own
        // bytes): recovery fails and the vault is replaced by the live baseline.
        let stale = try fixtureData(uuid: "BBBBBBBB-1111-2222-3333-123456789ABC")
        try stale.write(to: vaultURL)
        try GestaltFileStore.sha256Hex(of: stale).write(to: digestURL, atomically: true, encoding: .utf8)
        let fourth = GestaltFileStore(deviceURL: deviceURL,
                                      backupDirectory: directory.appendingPathComponent("backups4"),
                                      deviceID: "install-4", acquire: { 1 }, release: { _ in })
        _ = try await fourth.loadDevice()
        try expect(try Data(contentsOf: vaultURL) == liveBytes,
                   "A stale vault is replaced by the live baseline, never restored")

        print("PASS: vault 4-check gate refuses each single mismatch, first load mirrors the factory backup with a SHA-256 sidecar, reinstall recovers it, and corrupt/stale vaults fall back to a fresh backup.")
    }
}
