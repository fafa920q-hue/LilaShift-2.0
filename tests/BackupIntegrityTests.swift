import Foundation
import XCTest
@testable import GestaltX

final class BackupIntegrityTests: XCTestCase {
    struct Failure: Error { let message: String }
    static func expectRejected(_ store: GestaltFileStore, record: BackupRecord) async {
        await XCTAssertThrowsError(try await store.backupData(record)) { error in
            XCTAssertTrue(error is GestaltFailure)
        }
    }

    func testBackupIntegrity() async throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }
        let device = directory.appendingPathComponent("device.plist")
        let backups = directory.appendingPathComponent("backups")
        let bytes = try PropertyListSerialization.data(fromPropertyList: ["CacheExtra": ["setting": "alpha"]], format: .binary, options: 0)
        try bytes.write(to: device)
        let store = GestaltFileStore(deviceURL: device, backupDirectory: backups, deviceID: "integrity-fixture", acquire: { 1 }, release: { _ in })
        _ = try await store.loadDevice()
        let record = try await store.backups().first!
        XCTAssert(try await store.backupData(record) == bytes, "Unchanged backup passes verification")
        let backupURL = backups.appendingPathComponent(record.filename)
        var altered = try GestaltDocument(data: bytes)
        altered.set("omega", for: "setting")
        let replacement = try altered.encoded()
        XCTAssert(replacement.count == record.byteCount, "Fixture replacement is a different valid plist of identical size")
        try replacement.write(to: backupURL)
        await expectRejected(store, record: record)
        try Data(bytes.dropLast()).write(to: backupURL)
        await expectRejected(store, record: record)
        try bytes.write(to: backupURL)
        let metadata = try JSONSerialization.jsonObject(with: Data(contentsOf: backups.appendingPathComponent(record.id.uuidString + ".json"))) as! [String: Any]
        XCTAssert((metadata["sha256"] as? String)?.count == 64, "New backup metadata persists a SHA-256 digest")

        // Decode the actual old schema, rather than relying only on the new
        // initializer's default argument, to verify backward compatibility.
        var legacyJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as! [String: Any]
        legacyJSON.removeValue(forKey: "sha256")
        let legacy = try JSONDecoder().decode(BackupRecord.self, from: JSONSerialization.data(withJSONObject: legacyJSON))
        XCTAssert(try await store.backupData(legacy) == bytes, "Legacy backups of the recorded length remain readable")
        try Data(bytes.dropLast()).write(to: backupURL)
        await expectRejected(store, record: legacy)
        try bytes.write(to: backupURL)
        var wrongDigestJSON = metadata
        wrongDigestJSON["sha256"] = String(repeating: "0", count: 64)
        let wrongDigest = try JSONDecoder().decode(BackupRecord.self, from: JSONSerialization.data(withJSONObject: wrongDigestJSON))
        await expectRejected(store, record: wrongDigest)
        XCTAssert(try Data(contentsOf: device) == bytes, "Rejected backup reads never modify the device")
    }
}
