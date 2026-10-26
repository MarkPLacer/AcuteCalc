import Foundation

/// Display formats of scientific calculators (Sharp EL-W531: NORM1/NORM2/FIX/SCI/ENG).
public enum DisplayMode: String, Hashable, Sendable, Codable, CaseIterable {
    case norm1, norm2, fix, sci, eng

    public var label: String {
        switch self {
        case .norm1: "NORM1"
        case .norm2: "NORM2"
        case .fix: "FIX"
        case .sci: "SCI"
        case .eng: "ENG"
        }
    }
}

public struct NumberFormatOptions: Hashable, Sendable, Codable {
    public var mode: DisplayMode
    /// Decimal places for FIX / SCI / ENG.
    public var places: Int
    /// Significant digits in NORM modes.
    public var significantDigits: Int
    public var decimalSeparator: String
    /// e.g. a thin space; `nil` disables grouping.
    public var groupingSeparator: String?

    public init(mode: DisplayMode = .norm1, places: Int = 4, significantDigits: Int = 10, decimalSeparator: String = ",", groupingSeparator: String? = nil) {
        self.mode = mode
        self.places = places
        self.significantDigits = significantDigits
        self.decimalSeparator = decimalSeparator
        self.groupingSeparator = groupingSeparator
    }
}

/// A formatted number: mantissa text and an optional power of ten (shown as ×10ⁿ).
public struct FormattedNumber: Hashable, Sendable {
    public var mantissa: String
    public var exponent: Int?

    public var plainText: String {
        guard let exponent else { return mantissa }
        return "\(mantissa)×10^\(exponent)"
    }
}

public enum NumberFormatting {
    /// Compact machine-style text (15 significant digits, `E` exponent) used internally.
    public static func plain(_ x: Double) -> String {
        guard x.isFinite else { return x.isNaN ? "NaN" : (x > 0 ? "∞" : "-∞") }
        if x == 0 { return "0" }
        let magnitude = abs(x)
        if magnitude >= 1e15 || magnitude < 1e-9 {
            let exponent = Int(Foundation.floor(Foundation.log10(magnitude)))
            let mantissa = x / pow(10, Double(exponent))
            return "\(trimmed(String(format: "%.14f", mantissa)))E\(exponent)"
        }
        return trimmed(String(format: "%.\(max(0, 14 - Int(Foundation.floor(Foundation.log10(magnitude)))))f", x))
    }

    static func trimmed(_ s: String) -> String {
        guard s.contains(".") else { return s }
        var t = s
        while t.hasSuffix("0") { t.removeLast() }
        if t.hasSuffix(".") { t.removeLast() }
        return t == "-0" ? "0" : t
    }

    /// Formats with calculator display rules.
    public static func format(_ value: Double, options: NumberFormatOptions = NumberFormatOptions()) -> FormattedNumber {
        guard value.isFinite else { return FormattedNumber(mantissa: value.isNaN ? "—" : (value > 0 ? "∞" : "−∞"), exponent: nil) }
        let x = value == 0 ? 0 : value // normalise −0
        let magnitude = abs(x)
        switch options.mode {
        case .norm1, .norm2:
            let lower = options.mode == .norm1 ? 1e-9 : 1e-2
            let digits = max(1, min(15, options.significantDigits))
            if x != 0 && (magnitude < lower || magnitude >= pow(10, Double(digits))) {
                return scientific(x, significant: digits, options: options, trim: true)
            }
            // Round to significant digits, then print without exponent.
            let rounded = roundSignificant(x, digits)
            let integerDigits = rounded == 0 ? 1 : max(1, Int(Foundation.floor(Foundation.log10(abs(rounded)))) + 1)
            let decimals = max(0, digits - integerDigits)
            let text = trimmed(String(format: "%.\(decimals)f", rounded))
            return FormattedNumber(mantissa: localize(text, options), exponent: nil)
        case .fix:
            if magnitude >= 1e10 { return scientific(x, significant: options.places + 1, options: options, trim: false) }
            return FormattedNumber(mantissa: localize(String(format: "%.\(options.places)f", x), options), exponent: nil)
        case .sci:
            return scientific(x, significant: options.places + 1, options: options, trim: false)
        case .eng:
            if x == 0 { return FormattedNumber(mantissa: localize(String(format: "%.\(options.places)f", 0.0), options), exponent: 0) }
            var exponent = Int(Foundation.floor(Foundation.log10(magnitude)))
            exponent -= ((exponent % 3) + 3) % 3
            let mantissa = x / pow(10, Double(exponent))
            return FormattedNumber(mantissa: localize(String(format: "%.\(options.places)f", mantissa), options), exponent: exponent)
        }
    }

    static func scientific(_ x: Double, significant: Int, options: NumberFormatOptions, trim: Bool) -> FormattedNumber {
        if x == 0 { return FormattedNumber(mantissa: "0", exponent: 0) }
        var exponent = Int(Foundation.floor(Foundation.log10(abs(x))))
        var mantissa = x / pow(10, Double(exponent))
        let decimals = max(0, significant - 1)
        // Rounding may push the mantissa to 10.0
        let scale = pow(10, Double(decimals))
        mantissa = (mantissa * scale).rounded() / scale
        if abs(mantissa) >= 10 { mantissa /= 10; exponent += 1 }
        var text = String(format: "%.\(decimals)f", mantissa)
        if trim { text = trimmed(text) }
        return FormattedNumber(mantissa: localize(text, options), exponent: exponent)
    }

    public static func roundSignificant(_ x: Double, _ digits: Int) -> Double {
        guard x != 0, x.isFinite else { return x }
        let exponent = Int(Foundation.floor(Foundation.log10(abs(x))))
        let scale = pow(10, Double(digits - 1 - exponent))
        guard scale.isFinite, scale > 0 else { return x }
        return (x * scale).rounded() / scale
    }

    /// Applies decimal separator, digit grouping and a typographic minus.
    static func localize(_ text: String, _ options: NumberFormatOptions) -> String {
        var negative = false
        var body = text
        if body.hasPrefix("-") { negative = true; body.removeFirst() }
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        var integer = String(parts[0])
        if let group = options.groupingSeparator, integer.count > 4 {
            var grouped = ""
            for (i, c) in integer.reversed().enumerated() {
                if i > 0 && i % 3 == 0 { grouped.append(contentsOf: group.reversed()) }
                grouped.append(c)
            }
            integer = String(grouped.reversed())
        }
        var result = integer
        if parts.count > 1 { result += options.decimalSeparator + parts[1] }
        return negative ? "−" + result : result
    }

    // MARK: Alternative representations (CHANGE key)

    /// a b/c for an improper fraction.
    public static func mixedFraction(_ r: Rational) -> (whole: Int, numerator: Int, denominator: Int)? {
        guard !r.isInteger, abs(r.numerator) > r.denominator else { return nil }
        let whole = r.numerator / r.denominator
        let remainder = abs(r.numerator % r.denominator)
        return (whole, remainder, r.denominator)
    }

    /// Splits 1/7 into ("0", "", "142857"), 1/6 into ("0", "1", "6").
    public static func recurringDecimal(_ r: Rational, maxPeriod: Int = 60) -> (integerPart: String, prefix: String, period: String)? {
        guard !r.isInteger else { return nil }
        var d = r.denominator
        while d % 2 == 0 { d /= 2 }
        while d % 5 == 0 { d /= 5 }
        guard d != 1 else { return nil } // terminating decimal
        let negative = r.isNegative
        let n = abs(r.numerator)
        let integerPart = n / r.denominator
        var remainder = n % r.denominator
        var seen: [Int: Int] = [:]
        var digits: [Character] = []
        while remainder != 0 && seen[remainder] == nil && digits.count < maxPeriod + 30 {
            seen[remainder] = digits.count
            remainder *= 10
            digits.append(Character(String(remainder / r.denominator)))
            remainder %= r.denominator
        }
        guard remainder != 0, let start = seen[remainder] else { return nil }
        let period = String(digits[start...])
        guard period.count <= maxPeriod else { return nil }
        return ((negative ? "−" : "") + String(integerPart), String(digits[..<start]), period)
    }

    /// Degrees → (°, ′, ″).
    public static func sexagesimal(_ degrees: Double) -> (degrees: Int, minutes: Int, seconds: Double, negative: Bool) {
        let negative = degrees < 0
        var total = abs(degrees)
        var d = Int(total)
        total = (total - Double(d)) * 60
        var m = Int(total)
        var s = (total - Double(m)) * 60
        s = (s * 1e6).rounded() / 1e6
        if s >= 60 { s -= 60; m += 1 }
        if m >= 60 { m -= 60; d += 1 }
        return (d, m, s, negative)
    }

    public static func primeFactorization(_ n: Int) -> [(prime: Int, exponent: Int)]? {
        guard n >= 2, n <= 9_999_999_999 else { return nil }
        var m = n
        var factors: [(Int, Int)] = []
        var p = 2
        while p * p <= m {
            var e = 0
            while m % p == 0 { m /= p; e += 1 }
            if e > 0 { factors.append((p, e)) }
            p += p == 2 ? 1 : 2
        }
        if m > 1 { factors.append((m, 1)) }
        return factors
    }

    /// Integer in another base; negative numbers use 10-digit two's complement like Sharp's N-base mode.
    public static func toBase(_ n: Int, base: Int) -> String {
        guard base >= 2, base <= 16 else { return String(n) }
        if n < 0 {
            let width = base == 2 ? 10 : 10
            var modulus = 1
            for _ in 0..<width { modulus *= base }
            return String(modulus + n, radix: base).uppercased()
        }
        return String(n, radix: base).uppercased()
    }
}
