import Foundation

/// An exact real number of the form `Σ cᵢ · √rᵢ · πᵏⁱ` with rational `cᵢ`,
/// square-free radicands `rᵢ ≥ 1` and small integer powers of π.
///
/// This is what lets the calculator answer `sin(60°)` with `√3/2` and
/// `√8 + √2` with `3√2`, like a CAS would. Every operation returns `nil`
/// when the result leaves the representable set (or would grow too large);
/// the caller then shows only the decimal approximation.
public struct ExactReal: Hashable, Sendable {
    public struct Basis: Hashable, Sendable, Comparable {
        public let radicand: Int
        public let piPower: Int

        public static let unit = Basis(radicand: 1, piPower: 0)

        public static func < (lhs: Basis, rhs: Basis) -> Bool {
            if lhs.piPower != rhs.piPower { return lhs.piPower < rhs.piPower }
            return lhs.radicand < rhs.radicand
        }
    }

    /// Non-zero coefficients only.
    public let terms: [Basis: Rational]

    static let maxTerms = 4
    static let maxRadicand = 1_000_000
    static let maxPiPower = 4

    init?(validating terms: [Basis: Rational]) {
        var cleaned: [Basis: Rational] = [:]
        for (basis, coefficient) in terms where !coefficient.isZero {
            guard basis.radicand >= 1, basis.radicand <= ExactReal.maxRadicand,
                  abs(basis.piPower) <= ExactReal.maxPiPower else { return nil }
            cleaned[basis] = coefficient
        }
        guard cleaned.count <= ExactReal.maxTerms else { return nil }
        self.terms = cleaned
    }

    public init(_ rational: Rational) {
        self.terms = rational.isZero ? [:] : [.unit: rational]
    }

    public init(_ integer: Int) { self.init(Rational(integer)) }

    public static let zero = ExactReal(Rational.zero)
    public static let one = ExactReal(Rational.one)
    public static let pi = ExactReal(validating: [Basis(radicand: 1, piPower: 1): .one])!

    // MARK: Inspection

    public var isZero: Bool { terms.isEmpty }

    /// The value as a plain fraction when it has no surd or π part.
    public var rational: Rational? {
        if terms.isEmpty { return .zero }
        if terms.count == 1, let c = terms[.unit] { return c }
        return nil
    }

    public var isRational: Bool { rational != nil }

    /// True when the value contains π (e.g. an angle like 5π/6).
    public var involvesPi: Bool { terms.keys.contains { $0.piPower != 0 } }

    public var sortedTerms: [(basis: Basis, coefficient: Rational)] {
        terms.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    public var doubleValue: Double {
        terms.reduce(0.0) { acc, term in
            acc + term.value.doubleValue * Double(term.key.radicand).squareRoot() * pow(Double.pi, Double(term.key.piPower))
        }
    }

    /// Rough complexity used to decide whether showing the exact form is helpful.
    public var complexity: Int {
        terms.reduce(0) { acc, term in
            acc + 1 + (term.key.radicand > 1 ? 1 : 0) + (term.key.piPower != 0 ? 1 : 0)
                + String(term.value.numerator).count / 4 + String(term.value.denominator).count / 4
        }
    }

    // MARK: Construction helpers

    /// `√r` for a non-negative rational, simplified (√8 → 2√2, √(1/2) → √2/2).
    public static func squareRoot(of value: Rational) -> ExactReal? {
        guard !value.isNegative else { return nil }
        if value.isZero { return .zero }
        // √(p/q) = √(p·q) / q
        let (pq, overflow) = value.numerator.multipliedReportingOverflow(by: value.denominator)
        guard !overflow, let (square, free) = squarefreeDecomposition(pq),
              let coefficient = Rational(square, value.denominator) else { return nil }
        return ExactReal(validating: [Basis(radicand: free, piPower: 0): coefficient])
    }

    /// Splits `n = square² · free` with `free` square-free.
    static func squarefreeDecomposition(_ n: Int) -> (square: Int, free: Int)? {
        guard n > 0, n <= 1_000_000_000_000 else { return nil }
        var m = n
        var square = 1
        var free = 1
        var p = 2
        while p * p <= m {
            var count = 0
            while m % p == 0 { m /= p; count += 1 }
            if count > 0 {
                for _ in 0..<(count / 2) { square *= p }
                if count % 2 == 1 { free *= p }
            }
            p += (p == 2) ? 1 : 2
        }
        if m > 1 { free *= m }
        return (square, free)
    }

    // MARK: Arithmetic

    public func negated() -> ExactReal? {
        var out: [Basis: Rational] = [:]
        for (b, c) in terms {
            guard let n = c.negated() else { return nil }
            out[b] = n
        }
        return ExactReal(validating: out)
    }

    public func adding(_ other: ExactReal) -> ExactReal? {
        var out = terms
        for (b, c) in other.terms {
            if let existing = out[b] {
                guard let sum = existing.adding(c) else { return nil }
                out[b] = sum
            } else {
                out[b] = c
            }
        }
        return ExactReal(validating: out)
    }

    public func subtracting(_ other: ExactReal) -> ExactReal? {
        guard let n = other.negated() else { return nil }
        return adding(n)
    }

    public func multiplied(by other: ExactReal) -> ExactReal? {
        var out: [Basis: Rational] = [:]
        for (b1, c1) in terms {
            for (b2, c2) in other.terms {
                let (product, overflow) = b1.radicand.multipliedReportingOverflow(by: b2.radicand)
                guard !overflow, let (square, free) = ExactReal.squarefreeDecomposition(product),
                      var coefficient = c1.multiplied(by: c2),
                      let scaled = coefficient.multiplied(by: Rational(square)) else { return nil }
                coefficient = scaled
                let basis = Basis(radicand: free, piPower: b1.piPower + b2.piPower)
                if let existing = out[basis] {
                    guard let sum = existing.adding(coefficient) else { return nil }
                    out[basis] = sum
                } else {
                    out[basis] = coefficient
                }
            }
        }
        return ExactReal(validating: out)
    }

    public func reciprocal() -> ExactReal? {
        let sorted = sortedTerms
        switch sorted.count {
        case 0:
            return nil
        case 1:
            // 1 / (c·√r·πᵏ) = √r / (c·r) · π⁻ᵏ
            let (b, c) = sorted[0]
            guard let denominator = c.multiplied(by: Rational(b.radicand)),
                  let coefficient = denominator.reciprocal() else { return nil }
            return ExactReal(validating: [Basis(radicand: b.radicand, piPower: -b.piPower): coefficient])
        case 2:
            // (c₀√r₀ + c₁√r₁)·πᵏ: multiplying by the conjugate gives (c₀²r₀ − c₁²r₁)·π²ᵏ,
            // a single term whose reciprocal is handled by the case above.
            let (b0, c0) = sorted[0]
            let (b1, c1) = sorted[1]
            guard b0.piPower == b1.piPower, let negated = c1.negated(),
                  let conjugate = ExactReal(validating: [b0: c0, b1: negated]),
                  let normSquared = multiplied(by: conjugate),
                  normSquared.terms.count == 1,
                  let inverseNorm = normSquared.reciprocal() else { return nil }
            return conjugate.multiplied(by: inverseNorm)
        default:
            return nil
        }
    }

    public func divided(by other: ExactReal) -> ExactReal? {
        guard let r = other.reciprocal() else { return nil }
        return multiplied(by: r)
    }

    public func power(_ exponent: Int) -> ExactReal? {
        guard abs(exponent) <= 64 else { return nil }
        if exponent == 0 { return .one }
        if exponent < 0 {
            guard let r = reciprocal() else { return nil }
            return r.power(-exponent)
        }
        var result = ExactReal.one
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

    /// Square root when the result stays representable: rationals and
    /// single terms like `4π²` → `2π`.
    public func squareRoot() -> ExactReal? {
        if isZero { return .zero }
        if let r = rational { return ExactReal.squareRoot(of: r) }
        guard terms.count == 1, let (b, c) = terms.first.map({ ($0.key, $0.value) }),
              b.radicand == 1, b.piPower % 2 == 0, !c.isNegative,
              let root = ExactReal.squareRoot(of: c),
              let piPart = ExactReal(validating: [Basis(radicand: 1, piPower: b.piPower / 2): .one]) else { return nil }
        return root.multiplied(by: piPart)
    }

    /// `self ^ (p/q)` for rational exponents where the result is representable.
    public func power(_ exponent: Rational) -> ExactReal? {
        if exponent.isInteger { return power(exponent.numerator) }
        guard let base = rational else {
            if exponent.denominator == 2, let s = squareRoot() { return s.power(exponent.numerator) }
            return nil
        }
        if let root = base.root(exponent.denominator) {
            return ExactReal(root).power(exponent.numerator)
        }
        if exponent.denominator == 2, let s = ExactReal.squareRoot(of: base) {
            return s.power(exponent.numerator)
        }
        return nil
    }

    /// Sign of the value: -1, 0 or +1 (decided numerically; exact zero is detected exactly).
    public var signum: Int {
        if isZero { return 0 }
        return doubleValue < 0 ? -1 : 1
    }
}

extension ExactReal: CustomStringConvertible {
    public var description: String {
        if terms.isEmpty { return "0" }
        return sortedTerms.map { term in
            var parts: [String] = []
            parts.append(term.coefficient.description)
            if term.basis.radicand > 1 { parts.append("√\(term.basis.radicand)") }
            if term.basis.piPower == 1 { parts.append("π") } else if term.basis.piPower != 0 { parts.append("π^\(term.basis.piPower)") }
            return parts.joined(separator: "·")
        }.joined(separator: " + ")
    }
}
