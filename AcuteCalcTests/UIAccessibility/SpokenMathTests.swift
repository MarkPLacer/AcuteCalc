import AcuteCore
import Testing
@testable import AcuteCalc

/// A11Y-06 (first step) and A11Y-10: VoiceOver gets the decimal separator, multiplication sign and
/// function notation the screen shows instead of the clipboard text (decimal point, English
/// names), and keys get descriptive Slovenian names instead of glyphs (C for nCr, · for times).
@MainActor
@Suite struct SpokenMathTests {
    /// 2,5·tan(x) as the editor builds it.
    let row = MathRow([
        .symbol(.digit(2)), .symbol(.decimalPoint), .symbol(.digit(5)), .symbol(.times),
        .function(.tan, argument: MathRow([.symbol(.variable("x"))])),
    ])

    @Test func labelsUseTheDisplayedNotation() {
        let slovenian = MathStyle(multiplication: "·", decimalSeparator: ",", slovenianNames: true)
        let international = MathStyle(multiplication: "×", decimalSeparator: ".", slovenianNames: false)
        #expect(MathAccessibility.label(row, style: slovenian) == "2,5·tg(x)")
        #expect(MathAccessibility.label(row, style: international) == "2.5×tan(x)")
        // The clipboard text stays the machine format.
        #expect(MathRowConverter.plainText(row) == "2.5·tan(x)")
    }

    @Test func argumentsAreSeparatedLikeOnScreen() {
        // With a decimal comma "mod(2,5, 3)" would be ambiguous; the screen shows mod(2,5; 3).
        let mod = MathRow([.function2(.mod, MathRow.text("2.5"), MathRow.text("3"))])
        let style = MathStyle(decimalSeparator: ",")
        #expect(MathAccessibility.label(mod, style: style) == "mod(2,5; 3)")
    }

    @Test func imaginaryUnitFollowsTheSetting() {
        let z = MathRow([.symbol(.digit(3)), .symbol(.plus), .symbol(.digit(4)), .symbol(.constant(.i))])
        #expect(MathAccessibility.label(z, style: MathStyle(imaginaryUnit: "j")) == "3+4j")
    }

    @Test func scientificNumbersAreSpokenAsAWhole() {
        let formatted = NumberFormatting.format(1.5e-12, options: NumberFormatOptions(decimalSeparator: ","))
        #expect(MathAccessibility.number(formatted) == "1,5 krat 10 na −12")
        #expect(MathAccessibility.number(NumberFormatting.format(0.25, options: NumberFormatOptions(decimalSeparator: ","))) == "0,25")
    }

    @Test func keysHaveDescriptiveSlovenianNames() {
        #expect(KeypadKey.function2(.nCr).accessibilityName == "kombinacije, n nad r")
        #expect(KeypadKey.function2(.nPr).accessibilityName == "variacije")
        #expect(KeypadKey.symbol(.times).accessibilityName == "krat")
        #expect(KeypadKey.symbol(.exponent10).accessibilityName == "krat deset na")
        #expect(KeypadKey.function(.sin).accessibilityName == "sinus")
        #expect(KeypadKey.function(.tan).accessibilityName == "tangens")
        #expect(KeypadKey.symbol(.factorial).accessibilityName == "fakulteta")
        #expect(KeypadKey.symbol(.ans).accessibilityName == "prejšnji rezultat")
        #expect(KeypadKey.function(.normcdf).accessibilityName == "porazdelitvena funkcija Fi")
    }

    @Test func decimalSeparatorKeyFollowsTheSetting() {
        #expect(KeypadKey.point.accessibilityName(decimalSeparator: ",") == "decimalna vejica")
        #expect(KeypadKey.point.accessibilityName(decimalSeparator: ".") == "decimalna pika")
    }

    @Test func noPaletteKeyIsNamedByAGlyph() {
        let glyphs: Set<String> = ["·", "ᴇ", "!", "ᵀ", "C", "V", "Φ", "Ans", "Dice", "Coin", "Rand"]
        for page in SymbolPage.all {
            for key in page.keys {
                #expect(!glyphs.contains(key.accessibilityName), "\(page.title): \(key.accessibilityName)")
            }
        }
    }
}
