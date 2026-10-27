import Foundation
import Testing
@testable import AcuteCalc

/// GAP-stats-decimal-1: the x, y and f cells of the statistics table are TextField(value:format:), and
/// SwiftUI stores what format.parseStrategy.parse(text) returns. Before the fix the format was
/// FloatingPointFormatStyle<Double>.number, which parses leniently in the device's locale; in sl_SI "."
/// groups thousands, so "1.25" was stored as 125, "9.81" as 981, "1.5" as 1, "0.5" as 0 and "1.2.3" as 1
/// (ICU 72 unum_parseDouble with Foundation's lenient settings). Expected values: the typed number read
/// with "," or "." as the decimal separator, as ExpressionNumberField.parse reads it.
/// Red run on main: `let cell = FloatingPointFormatStyle<Double>.number.locale(Locale(identifier: "sl_SI"))`.
@MainActor
@Suite struct StatisticsCellInputTests {
    /// The cells' format on a Slovenian device (decimal ",", thousands ".").
    let cell = DecimalEntryFormat().locale(Locale(identifier: "sl_SI"))

    @Test func readsDecimalPointAndComma() {
        let typed: [(String, Double)] = [
            ("1.25", 1.25), ("1,25", 1.25), ("-0.5", -0.5), ("-0,5", -0.5), ("\u{2212}0,5", -0.5),
            ("9.81", 9.81), ("1.5", 1.5), ("0.5", 0.5), ("12.5", 12.5), ("0.001", 0.001), (" 2,54 ", 2.54),
        ]
        for (text, expected) in typed {
            let stored = try? cell.parseStrategy.parse(text)
            #expect(stored == expected, "\(text)")
        }
    }

    /// Integers and exponents keep their values.
    @Test func integersAndExponentsAreUnchanged() {
        let typed: [(String, Double)] = [
            ("158", 158), ("-3", -3), ("0", 0), ("1e3", 1000), ("2.5E2", 250), ("1,5e-3", 0.0015),
        ]
        for (text, expected) in typed {
            let stored = try? cell.parseStrategy.parse(text)
            #expect(stored == expected, "\(text)")
        }
    }

    /// Text that is not one finite number does not parse, so the cell keeps its previous value
    /// (before: "1.2.3" → 1, "1.234,5" → 1234.5, "1/3" → 1, "12 345" → 12345, "1e400" → ∞).
    @Test func otherTextIsNotANumber() {
        for text in ["", "abc", ".", "-", "1.2.3", "1.234,5", "1/3", "12 345", "nan", "inf", "1e400"] {
            let stored = try? cell.parseStrategy.parse(text)
            #expect(stored == nil, "\(text)")
        }
    }

    /// Below 1000 the cells show what `.number` showed ("1,25"), and every shown value reads back
    /// unchanged; that is why there is no thousands separator: "12.345" (12345) would read back as 12.345.
    @Test func shownValuesReadBackUnchanged() {
        let before = FloatingPointFormatStyle<Double>.number.locale(Locale(identifier: "sl_SI"))
        for x in [1.25, 9.81, 158, 0.001, -0.5, 1.0 / 3] {
            #expect(cell.format(x) == before.format(x))
        }
        #expect(cell.format(1.25) == "1,25")
        for x in [1.25, -0.5, 158, 0.001, 1234.5, 12345, -98765.25] {
            let shown = cell.format(x)
            let stored = try? cell.parseStrategy.parse(shown)
            #expect(stored == x, "\(x) is shown as \(shown)")
        }
    }
}
