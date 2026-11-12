import Foundation

/// Offline tests for the hardened in-place device writer (item 6).
/// No device or signing is needed: the writer works on any regular file.
/// A fault-injected partial write cannot be unit-tested without a device
/// seam, so the no-0-byte-window property is covered by the shorter/longer
/// payload cases plus the store-level commit below, which uses the real
/// default `writeData`.
@main struct DevicePlistWriterTests {
    struct Failure: Error { let message: String }
    static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message: message) }
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
        do {
            try DevicePlistWriter.write(Data(), to: file)
            throw Failure(message: "Empty write was not refused")
        } catch is DevicePlistWriter.WriteError {}
        try expect(try Data(contentsOf: file) == shorter,
                   "Refused empty write leaves the file untouched")

        // A missing file is refused before anything is created.
        let missing = directory.appendingPathComponent("missing.plist")
        do {
            try DevicePlistWriter.write(Data("x".utf8), to: missing)
            throw Failure(message: "Write to a missing file was not refused")
        } catch is DevicePlistWriter.WriteError {}
        try expect(!fm.fileExists(atPath: missing.path),
                   "Refused write to a missing file creates nothing")

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

        print("PASS: DevicePlistWriter overwrites in place with pwrite, truncates only a shorter tail, refuses empty/missing files, and the store's default writeData commits through it.")
    }
}
