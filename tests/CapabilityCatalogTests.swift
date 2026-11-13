import Foundation
import XCTest
@testable import GestaltX

final class CapabilityCatalogTests: XCTestCase {
    struct Failure: Error { let message: String }

    func testCapabilityCatalog() throws {
        let ids = Capability.all.map(\.id)
        XCTAssert(Set(ids).count == ids.count, "Capability ids are unique")
        for capability in Capability.all {
            XCTAssert(!capability.keys.isEmpty, "\(capability.id) has at least one key")
            for key in capability.keys {
                XCTAssert(key.count == 22 || key == "UIParallaxCapability",
                           "\(capability.id) uses a MobileGestalt key: \(key)")
                if let values = capability.values {
                    XCTAssert(values[key] != nil, "\(capability.id) has a value for \(key)")
                }
            }
        }

        let original: [String: Any] = [
            "CacheExtra": [
                "YlEtTtHlNesRBMal1CqRaA": NSNumber(value: 0),
                "UIParallaxCapability": NSNumber(value: 1),
                "qqrspu7CpuPdZwSDxNY+Fg": NSNumber(value: 1),
            ],
            "CacheData": Data([0, 1, 2]),
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: original, format: .binary, options: 0)
        let document = try GestaltDocument(data: data)
        let snapshot = DocumentSnapshot(data: data, document: document, source: .local, name: "fixture")

        for capability in Capability.all where capability.availableChoices.contains(.enable) {
            var enabled = document
            capability.apply(.enable, to: &enabled, restoringFrom: snapshot)
            for key in capability.keys {
                let expected = capability.values?[key] ?? capability.enabled
                let actual: Any = enabled.extra[key] ?? NSNull()
                XCTAssert(GestaltDocument.valuesEqual(actual, expected),
                           "\(capability.id) enables \(key) with the catalog value")
            }

            capability.apply(.disable, to: &enabled, restoringFrom: snapshot)
            XCTAssert(enabled.matches(document), "\(capability.id) restores the original document")

            capability.apply(.removeAdded, to: &enabled, restoringFrom: snapshot)
            for key in capability.keys {
                XCTAssert(enabled.extra[key] == nil, "\(capability.id) removes \(key)")
            }
        }

        // P0-4 fail-closed model gate: an unknown device matches no
        // verified entry and resolves to unknown with a reason — never to
        // a borrowed layout, a guessed model number, or an assumed
        // capability. Matching is by exact entry only; no family/prefix
        // inference.
        func expectUnknown(productType: String, originalRegModel: String?, _ message: String) throws {
            XCTAssert(USRegulatoryModelMapping.usRegulatoryModel(originalRegModel: originalRegModel,
                                                                  productType: productType) == nil,
                       "\(message): region mapping is nil")
            XCTAssert(!USRegulatoryModelMapping.isKnownProductType(productType),
                       "\(message): product type is not a verified entry")
            let decision = DeviceModelSupport.decision(for: productType, originalRegModel: originalRegModel)
            XCTAssert(!decision.isKnown, "\(message): model decision is not known")
            guard let reason = decision.reason else {
                throw Failure(message: "\(message): unknown model carries no reason")
            }
            XCTAssert(!reason.isEmpty, "\(message): unknown-model reason is non-empty")
        }

        // Unknown ProductType and unknown prefix.
        try expectUnknown(productType: "iPhone99,9", originalRegModel: nil,
                          "iPhone99,9 is unknown")
        try expectUnknown(productType: "iPhone99,9", originalRegModel: "A9999",
                          "iPhone99,9 with an unmapped A-number is unknown")
        try expectUnknown(productType: "XPhone99,9", originalRegModel: nil,
                          "A made-up prefix is unknown")
        try expectUnknown(productType: "iPhone", originalRegModel: nil,
                          "A bare iPhone prefix with no variant is unknown")
        try expectUnknown(productType: "", originalRegModel: nil,
                          "An empty product type is unknown")

        // Known family, unlisted variant: iPhone19,9 shares the iPhone19
        // family with listed variants but has no verified entry itself.
        try expectUnknown(productType: "iPhone19,9", originalRegModel: nil,
                          "iPhone19,9 is an unlisted variant of a known family")
        try expectUnknown(productType: "iPhone18,9", originalRegModel: nil,
                          "iPhone18,9 is an unlisted variant of a known family")

        // iPad / non-iPhone: nil even when the recorded regulatory model
        // is a known iPhone A-number (the family is checked first).
        try expectUnknown(productType: "iPad16,1", originalRegModel: nil,
                          "iPad16,1 maps to nil")
        XCTAssert(USRegulatoryModelMapping.usRegulatoryModel(originalRegModel: "A3718",
                                                              productType: "iPad16,1") == nil,
                   "A known iPhone A-number never maps an iPad to a US model")
        XCTAssert(DeviceModelSupport.decision(for: "iPad16,1", originalRegModel: "A3718").isKnown == false,
                   "A known iPhone A-number never makes an iPad known")
        try expectUnknown(productType: "iPod9,1", originalRegModel: "A3718",
                          "A non-iPhone with a known A-number is unknown")

        // Listed variants still map (regression guard for the gate).
        XCTAssert(USRegulatoryModelMapping.usRegulatoryModel(originalRegModel: nil,
                                                              productType: "iPhone19,3") == "A3473",
                   "iPhone19,3 maps to US A3473")
        XCTAssert(USRegulatoryModelMapping.usRegulatoryModel(originalRegModel: nil,
                                                              productType: "iPhone18,4") == "A3260",
                   "iPhone18,4 maps to US A3260")
        XCTAssert(USRegulatoryModelMapping.isKnownProductType("iPhone19,3")
                   && DeviceModelSupport.decision(for: "iPhone19,3", originalRegModel: nil).isKnown
                   && USRegulatoryModelMapping.unknownModelReason(originalRegModel: nil,
                                                                  productType: "iPhone19,3") == nil,
                   "A listed variant is known and carries no unknown-model reason")
        // A verified A-number is itself a verified entry, so it still
        // wins over the product-type fallback on an iPhone — family
        // inference is not needed for that.
        XCTAssert(DeviceModelSupport.decision(for: "iPhone19,9", originalRegModel: "A3718").isKnown,
                   "iPhone19,9 with verified A3718 is known via the A-number, not the family")

    }
}
