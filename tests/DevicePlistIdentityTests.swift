import Foundation
import XCTest
@testable import GestaltX

final class DevicePlistIdentityTests: XCTestCase {
    func testDevicePlistIdentity() throws {
        let udid = "0123456789ABCDEF0123456789ABCDEF01234567"
        let serial = "TESTSERIAL12"
        let reference = try DevicePlistIdentity(properties: ["UniqueDeviceID": udid, "SerialNumber": serial, "UniqueChipID": UInt64(123456789)])
        func data(_ extra: [String: Any]) throws -> Data {
            try PropertyListSerialization.data(fromPropertyList: ["CacheExtra": extra], format: .binary, options: 0)
        }
        let owned = try DevicePlistIdentity(plist: data([
            "re6Zb+zwFKJNlkQTUeT+/w": udid.lowercased(), "VasUgeSzVyHdB27g2XpN0g": serial,
            "h9jDsbgj7xIVeIQ8S3/X3Q": "iPhone19,1", "h63QSdBCiT/z0WU6rdQv6Q": "CH"
        ]))
        try owned.requireMatch(with: reference)
        try DevicePlistIdentity(properties: ["SerialNumber": serial, "UniqueChipID": "0x75BCD15"]).requireMatch(with: reference)
        XCTAssertThrowsError(try DevicePlistIdentity(plist: data(["h9jDsbgj7xIVeIQ8S3/X3Q": "iPhone19,1", "h63QSdBCiT/z0WU6rdQv6Q": "CH"])).requireMatch(with: reference), "Same model and region do not prove ownership")
        XCTAssertThrowsError(try DevicePlistIdentity(properties: ["SerialNumber": serial]).requireMatch(with: reference), "One matching identifier is insufficient")
        XCTAssertThrowsError(try DevicePlistIdentity(properties: ["UniqueDeviceID": udid, "SerialNumber": serial, "UniqueChipID": 99]).requireMatch(with: reference), "Any conflicting known identifier rejects the file, even with two matches")
        XCTAssertThrowsError(try DevicePlistIdentity(properties: ["UniqueDeviceID": String(repeating: "A", count: 40), "SerialNumber": "OTHERPHONE12"]).requireMatch(with: reference), "Reject another device's identifiers")
        XCTAssertThrowsError(try owned.requireMatch(with: DevicePlistIdentity(properties: [:])), "Cannot use a missing device identity as a wildcard")
        XCTAssertThrowsError(try DevicePlistIdentity(properties: ["SerialNumber": serial, "VasUgeSzVyHdB27g2XpN0g": "OTHERPHONE12"]), "Reject conflicting clear and hashed aliases")
        XCTAssertThrowsError(try DevicePlistIdentity(properties: ["UniqueChipID": true]), "Boolean ECID is invalid")
        XCTAssertThrowsError(try DevicePlistIdentity(properties: ["UniqueChipID": 123.5]), "Fractional ECID is invalid")
        XCTAssertThrowsError(try reference.mergingTrusted(DevicePlistIdentity(properties: ["SerialNumber": "OTHERPHONE12"])), "Conflicting trusted sources cannot be silently merged")
        if let path = ProcessInfo.processInfo.environment["GX_TEST_MG_EXPORT"] {
            let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
            let parsed = try DevicePlistIdentity(plist: bytes)
            if parsed.values.count < 2 {
                XCTAssertThrowsError(try parsed.requireMatch(with: parsed), "Unidentifiable exports are refused, even if supplied by the owner")
            } else { try parsed.requireMatch(with: parsed) }
        }
    }
}
