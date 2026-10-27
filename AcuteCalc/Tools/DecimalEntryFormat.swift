import Foundation

/// The format of the statistics table cells (TextField(value:format:)): a typed number is read with
/// "," or "." as the decimal separator, like ExpressionNumberField, and a stored value is shown like
/// `.number` in the device's locale ("1,25" in Slovenian), only without thousands separators.
///
/// `.number` parses leniently in the locale, and where "." groups thousands (sl_SI) it stored "1.25"
/// as 125 and "1.5" as 1. A shown "12.345" (12345) would now be read back as 12.345, hence no grouping.
nonisolated struct DecimalEntryFormat: ParseableFormatStyle {
    var locale: Locale

    init(locale: Locale = .autoupdatingCurrent) {
        self.locale = locale
    }

    func format(_ value: Double) -> String {
        FloatingPointFormatStyle<Double>(locale: locale).grouping(.never).format(value)
    }

    func locale(_ locale: Locale) -> DecimalEntryFormat {
        DecimalEntryFormat(locale: locale)
    }

    var parseStrategy: Strategy { Strategy() }

    /// Text that is not one finite number throws, so the cell keeps its previous value.
    nonisolated struct Strategy: ParseStrategy {
        func parse(_ value: String) throws -> Double {
            guard let number = DecimalEntryFormat.number(from: value) else { throw CocoaError(.formatting) }
            return number
        }
    }

    /// The number rule of ExpressionNumberField.parse without its expressions: "2,5" and "2.5" are 2.5,
    /// exponents stay ("1,5e-3") and digit groups join ("12 345"); the minus sign U+2212 of shown Slovenian
    /// negatives is "-".
    static func number(from text: String) -> Double? {
        let normalized = latinDigits(text).trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\u{2212}", with: "-")
            .replacingOccurrences(of: ",", with: ".")
        guard let joined = joiningDigitGroups(normalized), let number = Double(joined), number.isFinite else { return nil }
        return number
    }

    /// A value shown in a locale with other digits or with direction marks, in the digits Double() reads
    /// (1,25 as "١٫٢٥" in ar_SA, −0,5 as "-0.5" after a left-to-right mark in he_IL): decimal digits of every
    /// script become 0–9, the Arabic decimal separator U+066B becomes ".", and the marks U+200E, U+200F, U+061C
    /// are left out.
    static func latinDigits(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\u{200E}", "\u{200F}", "\u{061C}":
                continue
            case "\u{066B}":
                scalars.append(".")
            default:
                if !scalar.isASCII, scalar.properties.numericType == .decimal, let value = scalar.properties.numericValue {
                    scalars.append(contentsOf: String(Int(value)).unicodeScalars)
                } else {
                    scalars.append(scalar)
                }
            }
        }
        return String(scalars)
    }

    /// "12 345" and "12 345,6" as the app shows and copies them with »Združevanje števk« (thin spaces), or typed
    /// with spaces, which `.number` read as well: a group of one to three digits, then groups of exactly three,
    /// joined (the rule of DisplayedNumber.machineText). Nil when spaces split anything else ("1 2", "12 34").
    static func joiningDigitGroups(_ text: String) -> String? {
        let spaces: Set<Character> = [" ", "\u{00A0}", "\u{202F}", "\u{2009}"]
        let groups = text.split(omittingEmptySubsequences: false, whereSeparator: { spaces.contains($0) })
        guard groups.count > 1 else { return text }
        func isDigits(_ s: Substring) -> Bool { !s.isEmpty && s.allSatisfy { $0.isASCII && $0.isNumber } }
        var first = groups[0]
        if first.first == "-" || first.first == "+" { first = first.dropFirst() }
        guard first.count <= 3, isDigits(first) else { return nil }
        for group in groups.dropFirst().dropLast() {
            guard group.count == 3, isDigits(group) else { return nil }
        }
        // The last group carries the fraction and the exponent ("345.6", "345e3").
        let last = groups[groups.count - 1]
        let lastDigits = last.prefix(3)
        guard lastDigits.count == 3, isDigits(lastDigits), !(last.dropFirst(3).first?.isNumber ?? false) else { return nil }
        return groups.joined()
    }
}
