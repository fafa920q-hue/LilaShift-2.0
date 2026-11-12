import Foundation
import Darwin

/// Offline tests for the hardened in-place device writer (item 6).
/// No device or signing is needed: the writer works on any regular file.
/// Failure paths are exercised through `DevicePlistWriter.FaultInjection`
/// (short write, failed write/sync/truncate, readback mismatch, failed
/// open); filesystem-level refusals (symlink, directory, FIFO, wrong
/// target path) are exercised with real fixtures. Faults are never applied
/// to the rollback, so every failure test also proves the original bytes
/// come back.
@main struct DevicePlistWriterTests {
    struct Failure: Error { let message: String }
    static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message: message) }
    }
    static func expectError(_ expected: DevicePlistWriter.WriteError,
                            _ operation: () throws -> Void, _ message: String) throws {
        do {
            try operation()
            throw Failure(message: message + " (no error was thrown)")
        } catch let error as DevicePlistWriter.WriteError {
            try expect(error == expected, message + " (got \(error))")
        }
    }

    static func main() async throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }

        // Longer payload overwrites in place.
        let file = directory.appendingPathComponent("device.plist")
        let original = Data("original-content-0123456789".utf8)
        try original.write(to: file)
        let longer = Data("replacement-content-that-is-longer-0123456789".utf8)
        try DevicePlistWriter.write(longer, to: file)
        try expect(try Data(contentsOf: file) == longer,
                   "Longer payload replaces the file byte-for-byte")

        // Shorter payload truncates the tail: no trailing garbage.
        let shorter = Data("short".utf8)
        try DevicePlistWriter.write(shorter, to: file)
        try expect(try Data(contentsOf: file) == shorter,
                   "Shorter payload truncates the tail instead of leaving garbage")

        // Empty data is refused and the file is untouched.
        try expectError(.emptyData,
                        { try DevicePlistWriter.write(Data(), to: file) },
                        "Empty write was not refused with emptyData")
        try expect(try Data(contentsOf: file) == shorter,
                   "Refused empty write leaves the file untouched")

        // A missing file is refused before anything is created.
        let missing = directory.appendingPathComponent("missing.plist")
        try expectError(.openFailed(ENOENT),
                        { try DevicePlistWriter.write(Data("x".utf8), to: missing) },
                        "Write to a missing file was not refused with openFailed(ENOENT)")
        try expect(!fm.fileExists(atPath: missing.path),
                   "Refused write to a missing file creates nothing")

        // An empty original is refused: there are no bytes a rollback could restore.
        let empty = directory.appendingPathComponent("empty.plist")
        try Data().write(to: empty)
        try expectError(.unreadableOriginal,
                        { try DevicePlistWriter.write(Data("x".utf8), to: empty) },
                        "Write over an empty original was not refused with unreadableOriginal")
        try expect(try Data(contentsOf: empty).isEmpty,
                   "Refused write over an empty file leaves it empty")

        // A symlink is refused even though it points at a valid file, and
        // the target is untouched. (O_NOFOLLOW is the second line of
        // defence; the lstat regular-file check fires first.)
        let link = directory.appendingPathComponent("link.plist")
        try fm.createSymbolicLink(at: link, withDestinationURL: file)
        try expectError(.notRegularFile,
                        { try DevicePlistWriter.write(Data("x".utf8), to: link) },
                        "Symlink target was not refused with notRegularFile")
        try expect(try Data(contentsOf: file) == shorter,
                   "Refused symlink write leaves the target untouched")

        // A directory and a FIFO are not regular files and are refused
        // without ever being opened for writing.
        try expectError(.notRegularFile,
                        { try DevicePlistWriter.write(Data("x".utf8), to: directory) },
                        "Directory target was not refused with notRegularFile")
        let fifo = directory.appendingPathComponent("fifo.plist")
        try expect(fifo.withUnsafeFileSystemRepresentation { mkfifo($0!, 0o600) } == 0,
                   "Could not create FIFO fixture")
        try expectError(.notRegularFile,
                        { try DevicePlistWriter.write(Data("x".utf8), to: fifo) },
                        "FIFO target was not refused with notRegularFile")

        // Expected-path pinning: a different file is refused, while the
        // same file reached through a symlinked parent directory is the
        // same canonical path and still writes.
        let realDir = directory.appendingPathComponent("real")
        try fm.createDirectory(at: realDir, withIntermediateDirectories: true)
        let realFile = realDir.appendingPathComponent("device.plist")
        try original.write(to: realFile)
        let linkDir = directory.appendingPathComponent("linked")
        try fm.createSymbolicLink(at: linkDir, withDestinationURL: realDir)
        let viaLink = linkDir.appendingPathComponent("device.plist")
        try expectError(.unexpectedTarget,
                        { try DevicePlistWriter.write(Data("x".utf8), to: file, expectedURL: realFile) },
                        "Write to a different file passed the expected-path check")
        try expect(try Data(contentsOf: file) == shorter,
                   "Refused wrong-target write leaves the file untouched")
        try DevicePlistWriter.write(Data("pinned".utf8), to: viaLink, expectedURL: realFile)
        try expect(try Data(contentsOf: realFile) == Data("pinned".utf8),
                   "Same canonical file through a symlinked directory still writes")

        // Fault injection. Each failure reports its own error and restores
        // the original bytes; the open failure leaves the file untouched.
        let faultFile = directory.appendingPathComponent("fault.plist")
        try original.write(to: faultFile)
        // A short first pwrite is absorbed by the loop: the write still lands whole.
        try DevicePlistWriter.write(longer, to: faultFile,
                                    faults: DevicePlistWriter.FaultInjection(shortWriteOnce: true))
        try expect(try Data(contentsOf: faultFile) == longer,
                   "Short first pwrite must still land the whole payload")
        try expectError(.writeFailed(EIO),
                        { try DevicePlistWriter.write(Data("boom".utf8), to: faultFile,
                                                     faults: DevicePlistWriter.FaultInjection(failWrite: true)) },
                        "Injected write failure was not reported with writeFailed")
        try expect(try Data(contentsOf: faultFile) == longer,
                   "Injected write failure must restore the original bytes")
        try expectError(.syncFailed(EIO),
                        { try DevicePlistWriter.write(Data("boom".utf8), to: faultFile,
                                                     faults: DevicePlistWriter.FaultInjection(failSync: true)) },
                        "Injected sync failure was not reported with syncFailed")
        try expect(try Data(contentsOf: faultFile) == longer,
                   "Injected sync failure must restore the original bytes")
        try expectError(.verificationFailed,
                        { try DevicePlistWriter.write(Data("boom".utf8), to: faultFile,
                                                     faults: DevicePlistWriter.FaultInjection(corruptReadback: true)) },
                        "Injected readback mismatch was not reported with verificationFailed")
        try expect(try Data(contentsOf: faultFile) == longer,
                   "Injected readback mismatch must restore the original bytes")
        try expectError(.truncateFailed(EIO),
                        { try DevicePlistWriter.write(Data("tiny".utf8), to: faultFile,
                                                     faults: DevicePlistWriter.FaultInjection(failTruncate: true)) },
                        "Injected truncate failure was not reported with truncateFailed")
        try expect(try Data(contentsOf: faultFile) == longer,
                   "Injected truncate failure must restore the original bytes")
        try expectError(.openFailed(EACCES),
                        { try DevicePlistWriter.write(Data("boom".utf8), to: faultFile,
                                                     faults: DevicePlistWriter.FaultInjection(failOpen: true)) },
                        "Injected open failure was not reported with openFailed")
        try expect(try Data(contentsOf: faultFile) == longer,
                   "Injected open failure must leave the file untouched")

        // Store level: the default `writeData` seam is the hardened writer,
        // and a device commit through it still verifies on readback.
        let device = directory.appendingPathComponent("store-device.plist")
        let backups = directory.appendingPathComponent("backups")
        let bytes = try PropertyListSerialization.data(
            fromPropertyList: ["CacheExtra": ["setting": "alpha"]], format: .binary, options: 0)
        try bytes.write(to: device)
        let store = GestaltFileStore(deviceURL: device, backupDirectory: backups,
                                     deviceID: "writer-fixture",
                                     acquire: { 1 }, release: { _ in })
        let snapshot = try await store.loadDevice()
        var edited = snapshot.document
        edited.set("omega", for: "setting")
        let result = try await store.commit(edited, expected: snapshot)
        try expect(result.document.extra["setting"] as? String == "omega",
                   "Device commit through the hardened writer applies")
        try expect(try Data(contentsOf: device) == result.data,
                   "Device file matches the committed document after the hardened write")

        print("PASS: DevicePlistWriter overwrites in place with pwrite, truncates only a shorter tail, refuses empty/missing/empty-original files, symlinks, directories and FIFOs, pins the expected target path, survives injected short-write/sync/readback/truncate/open failures with rollback, and the store's default writeData commits through it.")
    }
}
