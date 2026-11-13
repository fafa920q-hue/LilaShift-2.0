// SPDX-License-Identifier: GPL-3.0-only
// Tests for Device Capability Fingerprint (设备能力指纹): no
// fingerprint before a read, capture records real fields with a
// stable digest, comparison detects changes, support-scope
// invalidation, and the store round-trip.
import Foundation
import XCTest
@testable import GestaltX

final class DeviceFingerprintTests: XCTestCase {
    /// A device that has never been read has NO fingerprint —
    /// capture returns nil, never a default one.
    func testCaptureReturnsNilWithoutSnapshot() {
        let profile = CoreModuleFixtures.profile(productType: "iPhone14,7", isNativeAI: false)
        XCTAssertNil(DeviceFingerprintCapture.capture(profile: profile, snapshot: nil),
                     "An unread device has no fingerprint")
    }

    /// Capture records the device's real fields from the profile
    /// and the document: product type, OS build, region, cache
    /// layout size, eSIM flags and WAPI. The digest is stable
    /// across captures of the same device state (the capture time
    /// is metadata, not device state).
    func testCaptureRecordsRealFields() throws {
        let document = try CoreModuleFixtures.document()
        let snapshot = CoreModuleFixtures.snapshot(document: document)
        let profile = CoreModuleFixtures.profile(productType: "iPhone14,7", isNativeAI: false)
        let first = try XCTUnwrap(DeviceFingerprintCapture.capture(profile: profile, snapshot: snapshot))
        let second = try XCTUnwrap(DeviceFingerprintCapture.capture(profile: profile, snapshot: snapshot))
        XCTAssertEqual(first.productType, "iPhone14,7")
        XCTAssertEqual(first.osBuild, "23A344")
        XCTAssertEqual(first.regionCode, "CH")
        XCTAssertEqual(first.cacheSlotCount, 720)
        XCTAssertEqual(first.cacheByteCount, 6480)
        XCTAssertEqual(first.esimGreenTea, true)
        XCTAssertEqual(first.esimNotGreenTea, false)
        XCTAssertEqual(first.wapiEnabled, true)
        XCTAssertEqual(first.isNativeAppleIntelligence, false)
        XCTAssertFalse(first.digest.isEmpty)
        XCTAssertEqual(first.digest, second.digest,
                       "Two captures of the same device state must hash the same")
    }

    /// An OS build change is reported, and it invalidates the
    /// previously recorded support scope.
    func testCompareDetectsOSBuildChange() {
        let stored = fingerprint(osBuild: "23A344")
        let current = fingerprint(osBuild: "23A345")
        let comparison = DeviceFingerprintCapture.compare(stored: stored, current: current)
        XCTAssertTrue(comparison.hasChanges)
        XCTAssertTrue(comparison.invalidatesSupportScope)
        XCTAssertEqual(comparison.changes.count, 1)
        XCTAssertEqual(comparison.changes.first?.field, "osBuild")
        XCTAssertEqual(comparison.changes.first?.old, "23A344")
        XCTAssertEqual(comparison.changes.first?.new, "23A345")
    }

    /// A region-code change is reported, but it does not invalidate
    /// the support scope on its own.
    func testCompareDetectsRegionChangeWithoutInvalidating() {
        let stored = fingerprint(regionCode: "CH")
        let current = fingerprint(regionCode: "LL")
        let comparison = DeviceFingerprintCapture.compare(stored: stored, current: current)
        XCTAssertTrue(comparison.hasChanges)
        XCTAssertFalse(comparison.invalidatesSupportScope)
        XCTAssertEqual(comparison.changes.count, 1)
        XCTAssertEqual(comparison.changes.first?.field, "regionCode")
    }

    /// Identical fingerprints compare with no changes.
    func testCompareNoChangesWhenIdentical() {
        let stored = fingerprint()
        let comparison = DeviceFingerprintCapture.compare(stored: stored, current: stored)
        XCTAssertFalse(comparison.hasChanges)
        XCTAssertTrue(comparison.changes.isEmpty)
        XCTAssertFalse(comparison.invalidatesSupportScope)
    }

    /// A fingerprint from a different device is reported as such,
    /// instead of listing field changes.
    func testCompareDifferentDevice() {
        let stored = fingerprint(deviceID: "device-A")
        let current = fingerprint(deviceID: "device-B")
        let comparison = DeviceFingerprintCapture.compare(stored: stored, current: current)
        XCTAssertTrue(comparison.differentDevice)
        XCTAssertTrue(comparison.hasChanges)
        XCTAssertTrue(comparison.changes.isEmpty,
                      "A different device must not be reported as field changes")
    }

    /// A changed field changes the digest.
    func testDigestChangesWhenFieldChanges() {
        XCTAssertNotEqual(fingerprint(regionCode: "CH").digest,
                          fingerprint(regionCode: "LL").digest)
    }

    /// The store round-trips a fingerprint with its digest sidecar:
    /// a missing file loads as nil, a saved fingerprint loads back
    /// equal, and a fingerprint with no device ID is refused.
    func testStoreRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lilashift-fingerprint-test-\(UUID().uuidString)", isDirectory: true)
        let store = DeviceFingerprintStore(directory: directory, deviceID: "test-device")
        XCTAssertNil(try store.load(), "A missing fingerprint file loads as nil")
        let saved = fingerprint(deviceID: "test-device")
        try store.save(saved)
        XCTAssertEqual(try store.load(), saved, "A saved fingerprint must load back equal")
        let unidentified = fingerprint(deviceID: "")
        XCTAssertThrowsError(try store.save(unidentified),
                             "A fingerprint with no device ID must be refused")
        try? FileManager.default.removeItem(at: directory)
    }

    /// A stored fingerprint for another device is refused on load.
    func testStoreRefusesOtherDevice() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lilashift-fingerprint-test-\(UUID().uuidString)", isDirectory: true)
        let storeA = DeviceFingerprintStore(directory: directory, deviceID: "device-A")
        try storeA.save(fingerprint(deviceID: "device-A"))
        let storeB = DeviceFingerprintStore(directory: directory, deviceID: "device-B")
        XCTAssertThrowsError(try storeB.load(),
                             "A fingerprint for another device must be refused")
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Helpers

    /// A fingerprint with test defaults and the given overrides.
    private func fingerprint(
        deviceID: String = "test-device",
        productType: String? = "iPhone14,7",
        osBuild: String? = "23A344",
        regionCode: String? = "CH"
    ) -> DeviceFingerprint {
        DeviceFingerprint(
            version: DeviceFingerprint.currentVersion,
            deviceID: deviceID,
            productType: productType,
            modelNumber: "A1234",
            osVersion: "27.0.1",
            osBuild: osBuild,
            regionCode: regionCode,
            salesRegionSuffix: "CH/A",
            cacheLayoutUUID: CoreModuleFixtures.uuid,
            cacheSlotCount: 720,
            cacheByteCount: 6480,
            esimGreenTea: true,
            esimNotGreenTea: false,
            wapiEnabled: true,
            audioIntelligenceSlot: nil,
            personalTranslatorSlot: nil,
            isNativeAppleIntelligence: false,
            appGroupAvailable: true,
            backupCount: 0,
            hasTrustedBackup: false,
            recordedAt: Date(timeIntervalSince1970: 0))
    }
}
