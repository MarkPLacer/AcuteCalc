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

    /// Digit groups as the app shows and copies them (»Združevanje števk« groups with thin spaces) or as typed
    /// with spaces keep their value, as `.number` read them ("12 345" → 12345, "12 345,6" → 12345.6).
    @Test func readsDigitGroupSpaces() {
        let typed: [(String, Double)] = [
            ("12 345", 12345), ("12\u{2009}345,6", 12345.6), ("\u{2212}1\u{202F}234\u{00A0}567,25", -1234567.25),
            ("123\u{2009}456.25", 123456.25), ("1 234,5", 1234.5), ("12\u{00A0}345", 12345),
        ]
        for (text, expected) in typed {
            let stored = try? cell.parseStrategy.parse(text)
            #expect(stored == expected, "\(text)")
        }
    }

    /// Text that is not one finite number does not parse, so the cell keeps its previous value
    /// (before: "1.2.3" → 1, "1.234,5" → 1234.5, "1/3" → 1, "1 2" → 1, "12 34" → 1234, "1e400" → ∞).
    @Test func otherTextIsNotANumber() {
        for text in ["", "abc", ".", "-", "1.2.3", "1.234,5", "1/3", "nan", "inf", "1e400",
                     "1 2", "12 34", "1234 567", "12 345 6"] {
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

    /// Locales that show other digits or direction marks: a shown value reads back unchanged, so editing it
    /// is not dropped (`.number` read these leniently). ICU 72: ar_SA shows −0.5 as U+061C "-٠٫٥", fa_IR as
    /// U+200E "−۰٫۵", he_IL as U+200E "-0.5", bn_BD 1.25 as "১.২৫", mr_IN as "१.२५".
    @Test func shownValuesReadBackInOtherScripts() {
        let typed: [(String, Double)] = [
            ("\u{0661}\u{066B}\u{0662}\u{0665}", 1.25),            // Arabic-Indic digits, Arabic decimal separator
            ("\u{06F1}\u{066B}\u{06F2}\u{06F5}", 1.25),            // Persian digits
            ("\u{09E7}.\u{09E8}\u{09EB}", 1.25),                   // Bengali digits
            ("\u{0967}.\u{0968}\u{096B}", 1.25),                   // Devanagari digits
            ("\u{200E}-0.5", -0.5),                                // left-to-right mark (he_IL)
            ("\u{061C}-\u{0661}\u{066B}\u{0662}\u{0665}", -1.25),  // Arabic letter mark (ar)
            ("\u{200E}\u{2212}\u{06F1}\u{066B}\u{06F2}\u{06F5}", -1.25),
        ]
        for (text, expected) in typed {
            let stored = try? cell.parseStrategy.parse(text)
            #expect(stored == expected, "\(text)")
        }
        // Other numerals are still not digits: 2², ½, ①.
        for text in ["2\u{00B2}", "\u{00BD}", "\u{2460}"] {
            let stored = try? cell.parseStrategy.parse(text)
            #expect(stored == nil, "\(text)")
        }
        for id in ["he_IL", "ar_SA", "ar_EG", "fa_IR", "bn_BD", "mr_IN"] {
            let format = DecimalEntryFormat().locale(Locale(identifier: id))
            for x in [1.25, -0.5, 158, 0.001, 12345, -98765.25] {
                let shown = format.format(x)
                let stored = try? format.parseStrategy.parse(shown)
                #expect(stored == x, "\(id): \(x) is shown as \(shown)")
            }
        }
    }
}
