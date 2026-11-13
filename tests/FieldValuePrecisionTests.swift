import Foundation
import XCTest
@testable import GestaltX

final class FieldValuePrecisionTests: XCTestCase {
    struct Failure: Error { let message: String }
    func expect(_ condition: Bool, _ message: String) {
        XCTAssert(condition, message)
    }

    func testFieldValuePrecision() throws {
        // Include precision below a millisecond and a value very close to the
        // reference epoch: preserving only milliseconds or nanoseconds loses it.
        let dates = [Date(timeIntervalSinceReferenceDate: 816_000_000.1234567),
                     Date(timeIntervalSinceReferenceDate: 0.000000000123456789)]
        for date in dates {
            var draft = FieldDraft(originalKey: "date", key: "date", kind: .date,
                                   text: PlistValueKind.date.text(for: date), originalValue: date)
            expect((try draft.parsedValue() as? Date) == date, "Staging unchanged date text retains exact binary precision")
            draft.key = "renamed-date"
            expect((try draft.parsedValue() as? Date) == date, "Renaming a date key preserves its exact value")
            draft.text = "2026-11-09T12:00:00.125Z"
            let changed = try draft.parsedValue()
            expect(GestaltDocument.valuesEqual(changed, try PlistValueKind.date.parse(draft.text)), "Changed date text is parsed")
            expect((changed as? Date) != date, "Changed text does not return the captured original")
            draft.kind = .string
            draft.text = PlistValueKind.date.text(for: date)
            expect(try draft.parsedValue() as? String == draft.text, "Explicit type changes are respected")
        }
        let preciseDate = dates[0]
        let values: [Any] = [
            [preciseDate, Data([0, 255]), NSNumber(value: true)],
            ["date": preciseDate, "nested": [preciseDate]]
        ]
        for value in values {
            let kind = PlistValueKind.detect(value)
            let draft = FieldDraft(originalKey: "collection", key: "renamed", kind: kind,
                                   text: kind.text(for: value), originalValue: value)
            expect(GestaltDocument.valuesEqual(try draft.parsedValue(), value), "Unchanged collections preserve nested dates and value types")
            let encoded = try PropertyListSerialization.data(fromPropertyList: ["CacheExtra": ["renamed": draft.parsedValue()]], format: .binary, options: 0)
            let document = try GestaltDocument(data: encoded)
            expect(GestaltDocument.valuesEqual(document.extra["renamed"]!, value), "Exact values survive a binary plist save")
        }
        let newDate = FieldDraft(key: "added", kind: .date, text: "2026-11-09T12:00:00Z")
        expect(try newDate.parsedValue() is Date, "New fields without an original value are parsed normally")
        var changedInteger = FieldDraft(originalKey: "number", key: "number", kind: .integer, text: "7", originalValue: NSNumber(value: 7))
        changedInteger.text = "8"
        expect((try changedInteger.parsedValue() as? NSNumber)?.intValue == 8, "Changed ordinary fields still use normal parsing")
        expect(PlistValueKind.date.text(for: preciseDate).contains("."), "Date editing text includes fractional seconds")
    }
}
