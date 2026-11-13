// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import XCTest
@testable import GestaltX

final class ImportedWallpaperDeletionTests: XCTestCase {
    let fm = FileManager.default
    func importFolder(_ pack: WallpaperPack, storage: URL) -> URL {
        storage.appendingPathComponent("Wallpapers/\(pack.id.uuidString)")
    }
    func recordsURL(_ id: UUID, storage: URL) -> URL {
        storage.appendingPathComponent("WallpaperInstallations/\(id.uuidString).plist")
    }
    func makeImport(_ pack: WallpaperPack, storage: URL) throws -> Data {
        let directory = importFolder(pack, storage: storage)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("imported assets".utf8).write(to: directory.appendingPathComponent("Asset.bin"))
        try CustomizationFiles.saveVerified(pack, to: directory.appendingPathComponent("Pack.plist"))
        // Future manifest fields must survive deletion even if WallpaperPack does not decode them.
        var values = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: directory.appendingPathComponent("Pack.plist")), format: nil) as! [String: Any]
        values["futureInstallationMetadata"] = ["version": 2]
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        try data.write(to: directory.appendingPathComponent("Pack.plist"))
        return data
    }
    func localStore(_ storage: URL, device: String = "original-device") -> CustomizationStore {
        CustomizationStore(storage: storage, device: device, resolver: { _ in
            fatalError("Deleting an imported wallpaper requested system-container access")
        })
    }
    func testImportedWallpaperDeletion() async throws {
        let root = fm.temporaryDirectory.appendingPathComponent("GX-ImportedWallpaperDeletion-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        try await unapplied(root.appendingPathComponent("Unapplied"))
        for device in ["original-device", "changed-device"] {
            for changed in [false, true] {
                try await applied(root.appendingPathComponent("\(device)-\(changed)"), device: device, changed: changed)
            }
        }
        try await failedRecordWrite(root.appendingPathComponent("FailedRecordWrite"))
        try await repeatedImport(root.appendingPathComponent("RepeatedImport"))
        try await links(root.appendingPathComponent("Links"))
    }
    func unapplied(_ storage: URL) async throws {
        let pack = WallpaperPack(id: UUID(), name: "Unapplied", descriptors: [])
        let other = WallpaperPack(id: UUID(), name: "Other", descriptors: [])
        _ = try makeImport(pack, storage: storage)
        let otherData = try makeImport(other, storage: storage)
        let store = localStore(storage)
        try await store.deleteImportedWallpaper(pack.id)
        try await store.deleteImportedWallpaper(pack.id)
        let listed = try await store.listWallpapers()
        XCTAssert(listed.map(\.id) == [other.id], "Deleted import remains listed or another pack was removed")
        XCTAssert(!fm.fileExists(atPath: importFolder(pack, storage: storage).path), "Import directory remains")
        XCTAssert(!fm.fileExists(atPath: recordsURL(pack.id, storage: storage).path), "Unapplied pack created installation records")
        XCTAssert(try Data(contentsOf: importFolder(other, storage: storage).appendingPathComponent("Pack.plist")) == otherData, "Another pack changed")
    }
    func applied(_ storage: URL, device: String, changed: Bool) async throws {
        let poster = storage.appendingPathComponent("FakePosterBoard")
        let relative = "Library/Application Support/PRBPosterExtensionDataStore/61/Extensions/com.apple.WallpaperKit.CollectionsPoster/descriptors/\(UUID().uuidString)"
        let target = poster.appendingPathComponent(relative)
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        let original = Data("installed wallpaper".utf8)
        let file = target.appendingPathComponent("Wallpaper.bin")
        try original.write(to: file)
        let entry = WallpaperInstallation(relative: relative, files: try CustomizationFiles.tree(target), committed: true)
        let pack = WallpaperPack(id: UUID(), name: "Applied", descriptors: [], installations: [entry], installedDevice: "original-device")
        let manifest = try makeImport(pack, storage: storage)
        let other = WallpaperPack(id: UUID(), name: "Other", descriptors: [])
        let otherManifest = try makeImport(other, storage: storage)
        let unrelated = target.deletingLastPathComponent().appendingPathComponent("existing/Keep.bin")
        try fm.createDirectory(at: unrelated.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("unrelated wallpaper".utf8).write(to: unrelated)
        if changed { try Data("changed outside GestaltX".utf8).write(to: file) }
        let before = try CustomizationFiles.tree(poster)
        try await localStore(storage, device: device).deleteImportedWallpaper(pack.id)
        XCTAssert(!fm.fileExists(atPath: importFolder(pack, storage: storage).path), "Applied import was not deleted")
        XCTAssert(try CustomizationFiles.tree(poster) == before, "Local deletion changed system wallpapers")
        let record = recordsURL(pack.id, storage: storage)
        let saved = try PropertyListDecoder().decode([Data].self, from: Data(contentsOf: record))
        XCTAssert(saved == [manifest], "Complete installation manifest was not preserved")
        XCTAssert(try Data(contentsOf: importFolder(other, storage: storage).appendingPathComponent("Pack.plist")) == otherManifest, "Another imported pack changed")
        await XCTAssertThrowsError(try await localStore(storage, device: "changed-device").removeWallpaper(pack.id))
        XCTAssert(fm.fileExists(atPath: record.path), "Device mismatch lost archived ownership")
        let uninstaller = CustomizationStore(storage: storage, device: "original-device", resolver: { _ in poster })
        if changed {
            await XCTAssertThrowsError(try await uninstaller.removeWallpaper(pack.id))
            XCTAssert(try CustomizationFiles.tree(poster) == before, "Uninstall removed an externally changed wallpaper")
            XCTAssert(fm.fileExists(atPath: record.path), "Refused uninstall lost archived ownership")
            try original.write(to: file)
        }
        let remaining = try await uninstaller.removeWallpaper(pack.id)
        XCTAssert(remaining.map(\.id) == [other.id], "Archived uninstall affected another import")
        XCTAssert(!fm.fileExists(atPath: target.path), "Archived uninstall requires the deleted import")
        XCTAssert(fm.fileExists(atPath: unrelated.path), "Uninstall deleted an unowned descriptor")
        XCTAssert(!fm.fileExists(atPath: record.path), "Completed uninstall left obsolete ownership")
    }
    func failedRecordWrite(_ storage: URL) async throws {
        let pack = WallpaperPack(id: UUID(), name: "Applied", descriptors: [],
                                 installations: [.init(relative: "tracked", files: [:])], installedDevice: "old-device")
        let manifest = try makeImport(pack, storage: storage)
        let blocker = storage.appendingPathComponent("WallpaperInstallations")
        try Data("not a directory".utf8).write(to: blocker)
        let store = localStore(storage)
        await XCTAssertThrowsError(try await store.deleteImportedWallpaper(pack.id))
        XCTAssert(try Data(contentsOf: importFolder(pack, storage: storage).appendingPathComponent("Pack.plist")) == manifest, "Failed record write deleted the original pack")
        let listed = try await store.listWallpapers()
        XCTAssert(listed.map(\.id) == [pack.id], "Failed deletion lost the list item")
        try fm.removeItem(at: blocker)
        try await store.deleteImportedWallpaper(pack.id)
        XCTAssert(fm.fileExists(atPath: recordsURL(pack.id, storage: storage).path), "Retry did not preserve installation records")
    }
    func repeatedImport(_ storage: URL) async throws {
        let poster = storage.appendingPathComponent("FakePosterBoard")
        let provider = "Library/Application Support/PRBPosterExtensionDataStore/61/Extensions/com.apple.WallpaperKit.CollectionsPoster/descriptors"
        let id = UUID()
        let store = localStore(storage)
        var manifests: [Data] = []
        var paths: [URL] = []
        for committed in [true, false] {
            let relative = provider + "/" + UUID().uuidString
            let target = poster.appendingPathComponent(relative)
            let actual = committed ? target : target.deletingLastPathComponent().appendingPathComponent(".GestaltX-stage-\(target.lastPathComponent)")
            try fm.createDirectory(at: actual, withIntermediateDirectories: true)
            try Data("installed".utf8).write(to: actual.appendingPathComponent("Wallpaper.bin"))
            let entry = WallpaperInstallation(relative: relative, files: try CustomizationFiles.tree(actual), committed: committed)
            let pack = WallpaperPack(id: id, name: "Reimported", descriptors: [], installations: [entry], installedDevice: "original-device")
            manifests.append(try makeImport(pack, storage: storage))
            paths.append(actual)
            try await store.deleteImportedWallpaper(id)
        }
        let saved = try PropertyListDecoder().decode([Data].self, from: Data(contentsOf: recordsURL(id, storage: storage)))
        XCTAssert(saved == manifests, "A reused pack UUID overwrote older installation records")
        _ = try await CustomizationStore(storage: storage, device: "original-device", resolver: { _ in poster }).removeWallpaper(id)
        for path in paths { XCTAssert(!fm.fileExists(atPath: path.path), "An archived or partial installation was orphaned") }
    }
    func links(_ storage: URL) async throws {
        let outside = storage.appendingPathComponent("Outside")
        let pack = WallpaperPack(id: UUID(), name: "Linked", descriptors: [], installedDevice: "old-device")
        let manifest = try makeImport(pack, storage: outside)
        try fm.createDirectory(at: storage.appendingPathComponent("Wallpapers"), withIntermediateDirectories: true)
        let link = importFolder(pack, storage: storage)
        try fm.createSymbolicLink(at: link, withDestinationURL: importFolder(pack, storage: outside))
        await XCTAssertThrowsError(try await localStore(storage).deleteImportedWallpaper(pack.id))
        XCTAssert(try Data(contentsOf: importFolder(pack, storage: outside).appendingPathComponent("Pack.plist")) == manifest, "Deletion followed a pack symlink")
        try fm.removeItem(at: link)
        _ = try makeImport(pack, storage: storage)
        try fm.createSymbolicLink(at: storage.appendingPathComponent("WallpaperInstallations"), withDestinationURL: outside)
        await XCTAssertThrowsError(try await localStore(storage).deleteImportedWallpaper(pack.id))
        XCTAssert(fm.fileExists(atPath: importFolder(pack, storage: storage).path), "Record-directory symlink deleted the import")
    }
}
