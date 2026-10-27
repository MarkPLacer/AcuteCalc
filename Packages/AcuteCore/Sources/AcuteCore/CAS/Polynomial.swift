import Foundation

/// A real polynomial c₀ + c₁x + … + cₙxⁿ, with exact coefficients when available.
public struct Polynomial: Sendable, Hashable {
    public var coefficients: [Double]
    public var exactCoefficients: [Rational]?

    public var degree: Int { coefficients.count - 1 }

    public init(coefficients: [Double], exact: [Rational]? = nil) {
        var c = coefficients
        var e = exact
        while c.count > 1, c.last == 0 { c.removeLast(); e?.removeLast() }
        self.coefficients = c
        self.exactCoefficients = e
    }

    /// Recognises `expr` as a polynomial in `variable` (after expansion), degree ≤ 24.
    public static func extract(from expr: Expr, variable: String) -> Polynomial? {
        let expanded = Simplifier.expand(expr)
        let terms: [Expr] = { if case .sum(let t) = expanded { return t } else { return [expanded] } }()
        var exact: [Int: Rational] = [:]
        var approx: [Int: Double] = [:]
        var allExact = true
        for term in terms {
            var coefficient: Simplifier.Num = .exact(.one)
            var power = 0
            let factors: [Expr] = { if case .product(let f) = term { return f } else { return [term] } }()
            for f in factors {
                if let n = Simplifier.numeric(f) {
                    coefficient = coefficient * n
                } else if case .variable(let v) = f, v == variable {
                    power += 1
                } else if case .power(.variable(let v), let e) = f, v == variable, let r = e.rationalValue,
                          r.isInteger, r.numerator >= 0, r.numerator <= 24 {
                    power += r.numerator
                } else if !f.dependsOn(variable), let value = try? RealEvaluator.evaluate(f) {
                    coefficient = coefficient * .approx(value)
                } else {
                    return nil
                }
            }
            guard power <= 24 else { return nil }
            switch coefficient {
            case .exact(let r):
                if let existing = exact[power] {
                    guard let s = existing.adding(r) else { allExact = false; approx[power, default: 0] += r.doubleValue; continue }
                    exact[power] = s
                } else {
                    exact[power] = r
                }
            case .approx(let d):
                allExact = false
                approx[power, default: 0] += d
            }
        }
        let degree = (Array(exact.keys) + Array(approx.keys)).max() ?? 0
        var c = [Double](repeating: 0, count: degree + 1)
        var e = [Rational](repeating: .zero, count: degree + 1)
        for (p, r) in exact { c[p] += r.doubleValue; e[p] = r }
        for (p, d) in approx { c[p] += d }
        return Polynomial(coefficients: c, exact: allExact ? e : nil)
    }

    public func evaluate(_ x: Double) -> Double {
        coefficients.reversed().reduce(0) { $0 * x + $1 }
    }

    /// Horner division by (x − r): returns quotient and remainder.
    public func divided(byRoot r: Double) -> (Polynomial, Double) {
        guard degree >= 1 else { return (self, coefficients.first ?? 0) }
        var q = [Double](repeating: 0, count: degree)
        var carry = 0.0
        for i in stride(from: degree, through: 1, by: -1) {
            carry = coefficients[i] + carry * r
            q[i - 1] = carry
        }
        let remainder = coefficients[0] + carry * r
        return (Polynomial(coefficients: q), remainder)
    }

    /// All complex roots (Durand–Kerner), polished with Newton steps.
    public func complexRoots() -> [Complex] {
        guard degree >= 1, let lead = coefficients.last, lead != 0 else { return [] }
        let monic = coefficients.map { $0 / lead }
        let n = degree
        func p(_ z: Complex) -> Complex {
            var acc = Complex.zero
            for c in monic.reversed() { acc = acc * z + Complex(c, 0) }
            return acc
        }
        let radius = 1 + (monic.dropLast().map { abs($0) }.max() ?? 1)
        var roots = (0..<n).map { k in Complex.polar(radius * 0.9, 2 * .pi * Double(k) / Double(n) + 0.4) }
        for _ in 0..<500 {
            var maxDelta = 0.0
            for i in 0..<n {
                var denominator = Complex.one
                for j in 0..<n where j != i { denominator *= roots[i] - roots[j] }
                let delta = p(roots[i]) / denominator
                roots[i] -= delta
                maxDelta = max(maxDelta, delta.magnitude)
            }
            if maxDelta < 1e-15 { break }
        }
        return roots.map { z in
            // Snap tiny imaginary parts.
            abs(z.im) < 1e-9 * max(1, abs(z.re)) ? Complex(z.re, 0) : z
        }
    }

    public func realRoots() -> [Double] {
        // Repeated roots: solve the square-free part, whose simple roots Durand–Kerner finds accurately.
        if let distinct = squareFreePart() { return distinct.realRoots() }
        return complexRoots().filter { $0.im == 0 }.map { r in
            // Newton polish on the original polynomial
            var x = r.re
            for _ in 0..<3 {
                let fx = evaluate(x)
                let d = derivativePolynomial().evaluate(x)
                if d == 0 { break }
                x -= fx / d
            }
            return NumericCalculus.clean(x)
        }.sorted()
    }

    public func derivativePolynomial() -> Polynomial {
        guard degree >= 1 else { return Polynomial(coefficients: [0]) }
        let c = (1...degree).map { Double($0) * coefficients[$0] }
        let e = exactCoefficients.map { ex in (1...degree).map { ex[$0].multiplied(by: Rational($0)) ?? .zero } }
        return Polynomial(coefficients: c, exact: e)
    }

    /// p / gcd(p, p′) over ℚ: the same roots, each only once. `nil` when p already is square-free, has
    /// inexact coefficients or the exact arithmetic overflows. Durand–Kerner reaches only ~√ε on a
    /// repeated root, so the double roots ±√5 of (x² − 5)² came out as complex pairs with |Im| ≈ 10⁻⁸.
    func squareFreePart() -> Polynomial? {
        guard degree >= 2, let p = exactCoefficients else { return nil }
        var derivative: [Rational] = []
        for k in 1...degree {
            guard let c = p[k].multiplied(by: Rational(k)) else { return nil }
            derivative.append(c)
        }
        // Euclid's algorithm; monic remainders keep the fractions small.
        var a = p, b = derivative
        while !(b.count == 1 && b[0].isZero) {
            guard let r = Polynomial.divide(a, by: b)?.remainder, let next = Polynomial.monic(r) else { return nil }
            a = b
            b = next
        }
        guard a.count > 1, let gcd = Polynomial.monic(a), let q = Polynomial.divide(p, by: gcd)?.quotient else { return nil }
        return Polynomial(coefficients: q.map(\.doubleValue), exact: q)
    }

    /// Exact coefficients (lowest power first) divided by the leading one; `nil` on overflow.
    private static func monic(_ c: [Rational]) -> [Rational]? {
        guard let lead = c.last, !lead.isZero else { return c }
        var result: [Rational] = []
        for x in c {
            guard let y = x.divided(by: lead) else { return nil }
            result.append(y)
        }
        return result
    }

    /// Long division of exact coefficient lists (lowest power first); `nil` on overflow.
    private static func divide(_ a: [Rational], by b: [Rational]) -> (quotient: [Rational], remainder: [Rational])? {
        guard let lead = b.last, !lead.isZero else { return nil }
        let n = b.count - 1
        var r = a
        guard r.count > n else { return ([Rational.zero], r) }
        var q = [Rational](repeating: .zero, count: r.count - n)
        for k in stride(from: r.count - 1, through: n, by: -1) {
            guard let factor = r[k].divided(by: lead) else { return nil }
            q[k - n] = factor
            for i in 0...n {
                guard let m = b[i].multiplied(by: factor), let s = r[k - n + i].subtracting(m) else { return nil }
                r[k - n + i] = s
            }
        }
        var remainder = Array(r.prefix(n))
        while remainder.count > 1, remainder.last?.isZero == true { remainder.removeLast() }
        return (q, remainder.isEmpty ? [Rational.zero] : remainder)
    }

    // MARK: Exact solving

    /// Exact real roots for polynomials with rational coefficients: rational roots
    /// (rational root theorem) and quadratic factors with surds. `nil` when some roots
    /// can only be given numerically.
    public func exactRealRoots() -> [ExactReal]? {
        guard var coeffs = exactCoefficients, degree >= 1 else { return nil }
        // Scale to integers.
        var lcm = 1
        for c in coeffs { guard let l = Rational.lcm(lcm, c.denominator) else { return nil }; lcm = l }
        var ints: [Int] = []
        for c in coeffs {
            guard let v = c.multiplied(by: Rational(lcm))?.integerValue else { return nil }
            ints.append(v)
        }
        var roots: [ExactReal] = []
        // Factor out x^k
        while ints.count > 1, ints[0] == 0 {
            ints.removeFirst()
            if !roots.contains(.zero) { roots.append(.zero) }
        }
        coeffs = ints.map { Rational($0) }
        var current = coeffs
        // Rational roots p/q: p | a₀, q | aₙ
        func divisors(_ n: Int) -> [Int] {
            let m = abs(n)
            guard m > 0, m <= 10_000_000 else { return [] }
            var d: [Int] = []
            var i = 1
            while i * i <= m {
                if m % i == 0 { d.append(i); if i != m / i { d.append(m / i) } }
                i += 1
            }
            return d
        }
        func evaluateExact(_ c: [Rational], _ x: Rational) -> Rational? {
            var acc = Rational.zero
            for coefficient in c.reversed() {
                guard let m = acc.multiplied(by: x), let s = m.adding(coefficient) else { return nil }
                acc = s
            }
            return acc
        }
        func deflate(_ c: [Rational], _ r: Rational) -> [Rational]? {
            let n = c.count - 1
            var q = [Rational](repeating: .zero, count: n)
            var carry = Rational.zero
            for i in stride(from: n, through: 1, by: -1) {
                guard let m = carry.multiplied(by: r), let s = c[i].adding(m) else { return nil }
                carry = s
                q[i - 1] = carry
            }
            return q
        }
        var searching = true
        // Deflate rational roots until a quadratic (or lower) remains.
        while searching, current.count > 3 {
            searching = false
            guard let a0 = current.first?.integerValue, let an = current.last?.integerValue, a0 != 0 else { break }
            outer: for p in divisors(a0) {
                for q in divisors(an) {
                    for sign in [1, -1] {
                        guard let r = Rational(sign * p, q), let v = evaluateExact(current, r), v.isZero,
                              let next = deflate(current, r) else { continue }
                        roots.append(ExactReal(r))
                        current = next
                        searching = true
                        break outer
                    }
                }
            }
        }
        switch current.count - 1 {
        case 0:
            break
        case 1:
            guard let r = current[0].divided(by: current[1])?.negated() else { return nil }
            roots.append(ExactReal(r))
        case 2:
            let a = current[2], b = current[1], c = current[0]
            guard let b2 = b.multiplied(by: b), let ac4 = a.multiplied(by: c)?.multiplied(by: Rational(4)),
                  let discriminant = b2.subtracting(ac4) else { return nil }
            if discriminant.isNegative { break }
            guard let sqrtD = ExactReal.squareRoot(of: discriminant), let twoA = a.multiplied(by: Rational(2)),
                  let minusB = b.negated() else { return nil }
            let base = ExactReal(minusB)
            guard let r1 = base.subtracting(sqrtD)?.divided(by: ExactReal(twoA)),
                  let r2 = base.adding(sqrtD)?.divided(by: ExactReal(twoA)) else { return nil }
            roots.append(r1)
            if discriminant != .zero { roots.append(r2) }
        default:
            return nil
        }
        var unique: [ExactReal] = []
        for r in roots where !unique.contains(r) { unique.append(r) }
        return unique.sorted { $0.doubleValue < $1.doubleValue }
    }
}
