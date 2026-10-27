import Foundation

/// An exact fraction `numerator / denominator` with overflow-checked arithmetic.
///
/// All operations return `nil` instead of trapping when a result does not fit in `Int`;
/// callers then fall back to floating point. The value is always normalised:
/// the denominator is positive and `gcd(numerator, denominator) == 1`.
public struct Rational: Hashable, Sendable, Comparable, Codable {
    public let numerator: Int
    public let denominator: Int

    public static let zero = Rational(unchecked: 0, 1)
    public static let one = Rational(unchecked: 1, 1)
    public static let minusOne = Rational(unchecked: -1, 1)
    public static let half = Rational(unchecked: 1, 2)

    /// Creates a normalised fraction. Returns `nil` for a zero denominator or when
    /// normalisation would overflow (only possible with `Int.min`).
    public init?(_ numerator: Int, _ denominator: Int = 1) {
        guard denominator != 0 else { return nil }
        guard numerator != .min, denominator != .min else { return nil }
        let g = Rational.gcd(numerator, denominator)
        var n = numerator / g
        var d = denominator / g
        if d < 0 { n = -n; d = -d }
        self.numerator = n
        self.denominator = d
    }

    init(unchecked numerator: Int, _ denominator: Int) {
        self.numerator = numerator
        self.denominator = denominator
    }

    public init(_ integer: Int) {
        // `Int.min` has no positive counterpart; nudging it keeps every operation trap-free.
        self.init(unchecked: integer == .min ? .min + 1 : integer, 1)
    }

    /// Exact value of a decimal literal such as `"12.375"` or `"1.5E3"`.
    /// Returns `nil` if the value does not fit.
    public init?(decimalString string: String) {
        var text = string.replacingOccurrences(of: ",", with: ".")
        var exponent = 0
        if let eIndex = text.firstIndex(where: { $0 == "E" || $0 == "e" }) {
            guard let e = Int(text[text.index(after: eIndex)...]) else { return nil }
            exponent = e
            text = String(text[..<eIndex])
        }
        var negative = false
        if text.hasPrefix("-") { negative = true; text.removeFirst() }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        let intPart = parts[0].isEmpty ? "0" : String(parts[0])
        let fracPart = parts.count == 2 ? String(parts[1]) : ""
        let digits = (intPart + fracPart).drop(while: { $0 == "0" })
        guard digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber) else { return nil }
        guard digits.count <= 18 else { return nil }
        let mantissa = digits.isEmpty ? 0 : Int(digits) ?? 0
        // 1ᴇ−9223372036854775808 has the exponent Int.min, where `exponent − count` or `abs`
        // would trap; such a literal is left to the parser's Double path (it is 0 there).
        let (scale, overflow) = exponent.subtractingReportingOverflow(fracPart.count)
        guard !overflow, scale.magnitude <= 18 else { return nil }
        var value: Rational?
        if scale >= 0 {
            guard let p = Rational.pow10(scale) else { return nil }
            let (m, o) = mantissa.multipliedReportingOverflow(by: p)
            guard !o else { return nil }
            value = Rational(m)
        } else {
            guard let p = Rational.pow10(-scale) else { return nil }
            value = Rational(mantissa, p)
        }
        guard var result = value else { return nil }
        if negative { result = result.negated() ?? result }
        self = result
    }

    public var isInteger: Bool { denominator == 1 }
    public var isZero: Bool { numerator == 0 }
    public var isNegative: Bool { numerator < 0 }
    public var isPositive: Bool { numerator > 0 }
    public var doubleValue: Double { Double(numerator) / Double(denominator) }
    /// `numerator` is never `Int.min` (the failable initialiser rejects it), so `abs` is safe.
    public var magnitude: Rational { Rational(unchecked: abs(numerator), denominator) }

    public var integerValue: Int? { isInteger ? numerator : nil }

    // MARK: Arithmetic (overflow-checked)

    public func negated() -> Rational? {
        guard numerator != .min else { return nil }
        return Rational(unchecked: -numerator, denominator)
    }

    public func adding(_ other: Rational) -> Rational? {
        if other.isZero { return self }
        if isZero { return other }
        let g = Rational.gcd(denominator, other.denominator)
        let lhsScale = other.denominator / g
        let rhsScale = denominator / g
        let (a, o1) = numerator.multipliedReportingOverflow(by: lhsScale)
        let (b, o2) = other.numerator.multipliedReportingOverflow(by: rhsScale)
        let (n, o3) = a.addingReportingOverflow(b)
        let (d, o4) = denominator.multipliedReportingOverflow(by: lhsScale)
        guard !(o1 || o2 || o3 || o4) else { return nil }
        return Rational(n, d)
    }

    public func subtracting(_ other: Rational) -> Rational? {
        guard let neg = other.negated() else { return nil }
        return adding(neg)
    }

    public func multiplied(by other: Rational) -> Rational? {
        if isZero || other.isZero { return .zero }
        let g1 = Rational.gcd(numerator, other.denominator)
        let g2 = Rational.gcd(other.numerator, denominator)
        let (n, o1) = (numerator / g1).multipliedReportingOverflow(by: other.numerator / g2)
        let (d, o2) = (denominator / g2).multipliedReportingOverflow(by: other.denominator / g1)
        guard !(o1 || o2) else { return nil }
        return Rational(n, d)
    }

    public func reciprocal() -> Rational? {
        guard numerator != 0 else { return nil }
        return Rational(denominator, numerator)
    }

    public func divided(by other: Rational) -> Rational? {
        guard let r = other.reciprocal() else { return nil }
        return multiplied(by: r)
    }

    /// Integer power; negative exponents produce the reciprocal power.
    public func power(_ exponent: Int) -> Rational? {
        if exponent == 0 { return .one }
        if exponent < 0 {
            guard exponent != .min, let r = reciprocal() else { return nil }
            return r.power(-exponent)
        }
        var result = Rational.one
        var base = self
        var e = exponent
        while e > 0 {
            if e & 1 == 1 {
                guard let r = result.multiplied(by: base) else { return nil }
                result = r
            }
            e >>= 1
            if e > 0 {
                guard let b = base.multiplied(by: base) else { return nil }
                base = b
            }
        }
        return result
    }

    /// Exact `q`-th root if both numerator and denominator are perfect powers.
    public func root(_ q: Int) -> Rational? {
        guard q >= 1 else { return nil }
        if q == 1 { return self }
        if numerator < 0 {
            guard q % 2 == 1, let pos = negated()?.root(q) else { return nil }
            return pos.negated()
        }
        guard let n = Rational.exactIntegerRoot(numerator, q),
              let d = Rational.exactIntegerRoot(denominator, q) else { return nil }
        return Rational(n, d)
    }

    public static func < (lhs: Rational, rhs: Rational) -> Bool {
        let (a, o1) = lhs.numerator.multipliedReportingOverflow(by: rhs.denominator)
        let (b, o2) = rhs.numerator.multipliedReportingOverflow(by: lhs.denominator)
        if o1 || o2 { return lhs.doubleValue < rhs.doubleValue }
        return a < b
    }

    // MARK: Helpers

    public static func gcd(_ a: Int, _ b: Int) -> Int {
        var x = a.magnitude
        var y = b.magnitude
        while y != 0 { (x, y) = (y, x % y) }
        return x == 0 ? 1 : Int(clamping: x)
    }

    public static func lcm(_ a: Int, _ b: Int) -> Int? {
        if a == 0 || b == 0 { return 0 }
        let (m, o) = (abs(a) / gcd(a, b)).multipliedReportingOverflow(by: abs(b))
        return o ? nil : m
    }

    static func pow10(_ n: Int) -> Int? {
        guard n >= 0 && n <= 18 else { return nil }
        var r = 1
        for _ in 0..<n { r *= 10 }
        return r
    }

    /// Exact integer `q`-th root of a non-negative integer, if it exists.
    static func exactIntegerRoot(_ value: Int, _ q: Int) -> Int? {
        guard value >= 0 else { return nil }
        if value < 2 { return value }
        let estimate = Int((pow(Double(value), 1.0 / Double(q))).rounded())
        // 0 and 1 cannot be roots of a value ≥ 2, and the powers of a candidate ≥ 2 pass the value within
        // 63 steps, so a huge index (2^(10⁻⁹) asks for root 10⁹) no longer runs q multiplications.
        for candidate in max(2, estimate - 1)...(estimate + 1) {
            var p = 1
            var tooLarge = false
            for _ in 0..<q {
                let (m, o) = p.multipliedReportingOverflow(by: candidate)
                if o || m > value { tooLarge = true; break }
                p = m
            }
            if !tooLarge && p == value { return candidate }
        }
        return nil
    }

    /// Best rational approximation with bounded denominator (continued fractions).
    /// Returns `nil` when the value isn't within `tolerance` of a fraction with
    /// denominator ≤ `maxDenominator`.
    public static func approximating(_ x: Double, maxDenominator: Int = 10_000, tolerance: Double = 1e-12) -> Rational? {
        guard x.isFinite, abs(x) < 1e15 else { return nil }
        let negative = x < 0
        var value = abs(x)
        var (h0, h1) = (0, 1)
        var (k0, k1) = (1, 0)
        for _ in 0..<40 {
            let a = Int(value.rounded(.down))
            let (h2, o1) = a.multipliedReportingOverflow(by: h1)
            let (k2, o2) = a.multipliedReportingOverflow(by: k1)
            if o1 || o2 { return nil }
            let hn = h2 + h0
            let kn = k2 + k0
            if kn > maxDenominator { break }
            (h0, h1) = (h1, hn)
            (k0, k1) = (k1, kn)
            let approx = Double(h1) / Double(k1)
            if abs(approx - abs(x)) <= tolerance * max(1, abs(x)) {
                return Rational(negative ? -h1 : h1, k1)
            }
            let frac = value - Double(a)
            if frac < 1e-15 { break }
            value = 1 / frac
        }
        let approx = k1 == 0 ? .infinity : Double(h1) / Double(k1)
        if k1 != 0 && abs(approx - abs(x)) <= tolerance * max(1, abs(x)) {
            return Rational(negative ? -h1 : h1, k1)
        }
        return nil
    }
}

extension Rational: CustomStringConvertible {
    public var description: String {
        denominator == 1 ? "\(numerator)" : "\(numerator)/\(denominator)"
    }
}
