import Foundation
import XCTest
@testable import GestaltX

final class BackupDeletionTests: XCTestCase {
    struct Failure: Error { let message: String }
    final class RemovalTrace: @unchecked Sendable {
        var failPayload = true
        var failMetadataOnce = false
        var paths: [String] = []
    }

    func testBackupDeletion() async throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }
        let device = directory.appendingPathComponent("device.plist")
        let backups = directory.appendingPathComponent("backups")
        let bytes = try PropertyListSerialization.data(fromPropertyList: ["CacheExtra": ["setting": "original"]], format: .binary, options: 0)
        try bytes.write(to: device)
        let trace = RemovalTrace()
        let store = GestaltFileStore(deviceURL: device, backupDirectory: backups, deviceID: "deletion-fixture",
                                     acquire: { 1 }, release: { _ in }, removeBackupItem: { url in
            trace.paths.append(url.lastPathComponent)
            if trace.failPayload && url.pathExtension == "plist" { throw CocoaError(.fileWriteNoPermission) }
            if trace.failMetadataOnce && url.pathExtension == "json" {
                trace.failMetadataOnce = false
                throw CocoaError(.fileWriteNoPermission)
            }
            try FileManager.default.removeItem(at: url)
        })
        let initial = try await store.loadDevice()
        let record = try await store.backups().first!
        let metadata = backups.appendingPathComponent(record.id.uuidString + ".json")
        let originalMetadata = try Data(contentsOf: metadata)
        await XCTAssertThrowsError(try await store.deleteBackup(record)) { error in
            XCTAssertTrue((error as? CocoaError)?.code == .fileWriteNoPermission, "Report the real deletion error")
        }
        XCTAssert(try await store.backups().contains { $0.id == record.id }, "A failed payload removal must leave the backup visible")
        XCTAssert(try await store.backupData(record) == bytes, "The visible backup remains recoverable")
        XCTAssert(try Data(contentsOf: metadata) == originalMetadata, "A failed payload removal preserves its original metadata")
        XCTAssert(trace.paths == [record.filename], "Metadata removal is not attempted before a successful payload removal")

        trace.failPayload = false
        trace.paths = []
        try await store.deleteBackup(record)
        XCTAssert(try await store.backups().isEmpty, "A successful retry removes the backup from the listing")
        XCTAssert(!fm.fileExists(atPath: metadata.path), "A successful delete removes metadata")
        XCTAssert(!fm.fileExists(atPath: backups.appendingPathComponent(record.filename).path), "A successful delete removes payload")
        XCTAssert(try fm.contentsOfDirectory(atPath: backups.path).isEmpty, "A successful delete leaves no staging or orphan files")

        try await store.backup(initial)
        let interrupted = try await store.backups().first!
        let interruptedMetadata = backups.appendingPathComponent(interrupted.id.uuidString + ".json")
        trace.failMetadataOnce = true
        await XCTAssertThrowsError(try await store.deleteBackup(interrupted)) { error in
            XCTAssertTrue((error as? CocoaError)?.code == .fileWriteNoPermission, "Metadata errors remain visible to the caller")
        }
        XCTAssert(!fm.fileExists(atPath: backups.appendingPathComponent(interrupted.filename).path), "The interrupted delete already removed the payload")
        XCTAssert(fm.fileExists(atPath: interruptedMetadata.path), "The interrupted delete still has metadata to clean up")
        try await store.deleteBackup(interrupted)
        XCTAssert(try fm.contentsOfDirectory(atPath: backups.path).isEmpty, "Retry after metadata failure tolerates only the missing payload and completes cleanup")
        XCTAssert(try Data(contentsOf: device) == bytes, "Deleting backups never modifies the device file")
    }
}
