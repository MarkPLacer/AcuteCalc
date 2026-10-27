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
    /// exponents stay ("1,5e-3"); the minus sign U+2212 of shown Slovenian negatives is "-".
    static func number(from text: String) -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\u{2212}", with: "-")
            .replacingOccurrences(of: ",", with: ".")
        guard let number = Double(normalized), number.isFinite else { return nil }
        return number
    }
}
