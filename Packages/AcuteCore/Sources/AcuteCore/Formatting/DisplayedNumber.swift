import Foundation

/// Numbers exactly as the app shows and copies them (`FormattedNumber.plainText` and the
/// superscript `·10ⁿ` form): `12 345` with thin-space digit groups, `−2,5`, `1,5×10^-8`, `2,5·10⁻³`.
public enum DisplayedNumber {
    /// Digit group separators: the thin space of the grouping setting and the no-break spaces.
    static let groupSeparators: Set<Character> = ["\u{2009}", "\u{202F}", "\u{00A0}"]
    static let superscriptDigits: Set<Character> = ["⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹"]

    /// The same number as text the parser reads as that number: digit groups joined and the
    /// decimal comma written as a point (`12 345` → `12345`, `1,5×10^-8` → `1.5×10^-8`), which is
    /// what the app copies with a decimal point and no grouping. Nil for any other text.
    public static func machineText(_ text: String) -> String? {
        var rest = Substring(text)
        func digits() -> String {
            let run = rest.prefix(while: { $0.isASCII && $0.isNumber })
            rest = rest.dropFirst(run.count)
            return String(run)
        }
        var out = ""
        if let sign = rest.first, sign == "−" || sign == "-" {
            out = "-"
            rest = rest.dropFirst()
        }
        // Integer part: plain digits, or a group of one to three followed by groups of three.
        var groups = [digits()]
        while let c = rest.first, groupSeparators.contains(c) {
            rest = rest.dropFirst()
            groups.append(digits())
        }
        guard !groups[0].isEmpty else { return nil }
        if groups.count > 1 {
            guard groups[0].count <= 3, groups.dropFirst().allSatisfy({ $0.count == 3 }) else { return nil }
        }
        out += groups.joined()
        if let c = rest.first, c == "," || c == "." {
            rest = rest.dropFirst()
            let fraction = digits()
            guard !fraction.isEmpty else { return nil }
            out += "." + fraction
        }
        // Power of ten: ×10^-8 (FormattedNumber.plainText) or ·10⁻⁸ (superscripts).
        if rest.hasPrefix("×10^") {
            rest = rest.dropFirst(4)
            var exponent = ""
            if rest.first == "-" {
                exponent = "-"
                rest = rest.dropFirst()
            }
            let magnitude = digits()
            guard !magnitude.isEmpty else { return nil }
            out += "×10^" + exponent + magnitude
        } else if rest.hasPrefix("·10") {
            rest = rest.dropFirst(3)
            var exponent = ""
            if rest.first == "⁻" {
                exponent = "⁻"
                rest = rest.dropFirst()
            }
            let magnitude = rest.prefix(while: { superscriptDigits.contains($0) })
            guard !magnitude.isEmpty else { return nil }
            rest = rest.dropFirst(magnitude.count)
            out += "·10" + exponent + String(magnitude)
        }
        return rest.isEmpty ? out : nil
    }
}
