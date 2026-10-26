import Foundation

/// Indefinite integrals by the methods of a first calculus course: the table of basic integrals
/// for linear inner functions, linearity, substitution, integration by parts, partial fractions,
/// powers and products of sine and cosine, the universal substitution t = tan(x/2), rational
/// functions of eˣ and the radical forms √(ax² + bx + c). Every result is checked by
/// differentiating it, so a wrong form is never shown; nil when no method applies.
public enum Antiderivative {
    /// F with F′ = f (without the constant C), simplified. In degrees or gradians the
    /// trigonometric functions are integrated as sin(kx) with k = π/180 (or π/200).
    public static func integrate(_ f: Expr, variable x: String = "x", angleUnit: AngleUnit = .radians) -> Expr? {
        let k: Expr? = switch angleUnit {
        case .radians: nil
        case .degrees: .product([.frac(1, 180), .constant(.pi)])
        case .gradians: .product([.frac(1, 200), .constant(.pi)])
        }
        let integrand = Simplifier.simplify(k.map { toRadians(f, $0) } ?? f)
        var search = Search()
        guard let raw = search.integrate(integrand, x, depth: 0) else { return nil }
        let candidates = [tidy(Simplifier.simplify(raw)), raw]
        guard let F = candidates.first(where: { verify($0, against: integrand, x) }) else { return nil }
        return k.map { Simplifier.simplify(fromRadians(F, $0)) } ?? F
    }

    // MARK: Verification

    /// F′ = f at sample points (other free variables get fixed sample values).
    static func verify(_ F: Expr, against f: Expr, _ x: String) -> Bool {
        guard let dF = try? Differentiator.derivative(of: F, withRespectTo: x) else { return false }
        var context = EvaluationContext()
        for (index, name) in f.freeVariables.union(F.freeVariables).subtracting([x]).sorted().enumerated() {
            context.variables[name] = 1.3 + 0.37 * Double(index)
        }
        var checked = 0
        for p in [0.37, 1.13, 2.71, -0.83, -1.91, 3.37, 0.61, 4.4, -3.3, 0.05, 6.2, -5.7, 0.93, -0.47] {
            context.variables[x] = p
            guard let a = try? RealEvaluator.evaluate(dF, context: context),
                  let b = try? RealEvaluator.evaluate(f, context: context), a.isFinite, b.isFinite else { continue }
            guard Swift.abs(a - b) <= 1e-7 * Swift.max(1, Swift.abs(b)) else { return false }
            checked += 1
        }
        return checked >= 3
    }

    /// ln|eʷ| → w, |eʷ| → eʷ (after substitutions such as u = eˣ).
    static func tidy(_ e: Expr) -> Expr {
        let inner = e.mapChildren(tidy)
        switch inner {
        case .function(.abs, let args) where args.count == 1:
            if case .power(.constant(.e), _) = args[0] { return args[0] }
        case .function(.ln, let args) where args.count == 1:
            if case .power(.constant(.e), let w) = args[0] { return w }
        default:
            break
        }
        return inner
    }

    // MARK: Degrees

    /// sin u → sin(k·u) and arcsin u → (arcsin u)/k: the integrand in radians.
    static func toRadians(_ e: Expr, _ k: Expr) -> Expr {
        let inner = e.mapChildren { toRadians($0, k) }
        guard case .function(let fn, let args) = inner, args.count == 1 else { return inner }
        if fn.isTrigonometric { return .function(fn, [.product([k, args[0]])]) }
        if fn.isInverseTrigonometric { return .quotient(inner, k) }
        return inner
    }

    /// Back to the calculator's angle unit: sin w → sin(w/k), arcsin v → k·arcsin v.
    static func fromRadians(_ e: Expr, _ k: Expr) -> Expr {
        let inner = e.mapChildren { fromRadians($0, k) }
        guard case .function(let fn, let args) = inner, args.count == 1 else { return inner }
        if fn.isTrigonometric { return .function(fn, [Simplifier.simplify(.quotient(args[0], k))]) }
        if fn.isInverseTrigonometric { return .product([k, inner]) }
        return inner
    }

    // MARK: Table for a linear inner function u = ax + b

    /// a when u = ax + b (a ≠ 0 and constant).
    static func linearCoefficient(_ u: Expr, _ x: String) -> Expr? {
        guard u.dependsOn(x), let du = try? Differentiator.derivative(of: u, withRespectTo: x) else { return nil }
        guard !du.dependsOn(x), !isZero(du) else { return nil }
        return du
    }

    static func table(_ f: Expr, _ x: String) -> Expr? {
        switch f {
        case .variable:
            return .quotient(.power(f, .int(2)), .int(2))
        case .power(let base, let exponent) where !exponent.dependsOn(x):
            // (ax + b)ⁿ
            guard let a = linearCoefficient(base, x) else { return nil }
            if isMinusOne(exponent) { return .quotient(.function(.ln, [.function(.abs, [base])]), a) }
            let n1 = Simplifier.simplify(.sum([exponent, .one]))
            return .quotient(.power(base, n1), .product([a, n1]))
        case .power(let base, let exponent) where !base.dependsOn(x):
            // e^(ax + b), c^(ax + b)
            guard let a = linearCoefficient(exponent, x) else { return nil }
            if base == .constant(.e) { return .quotient(f, a) }
            return .quotient(f, .product([a, .function(.ln, [base])]))
        case .function(let fn, let args) where args.count == 1:
            let u = args[0]
            guard let a = linearCoefficient(u, x) else { return nil }
            let u2 = Expr.power(u, .int(2))
            let F: Expr
            switch fn {
            case .sin: F = .negation(.function(.cos, [u]))
            case .cos: F = .function(.sin, [u])
            case .tan: F = .negation(.function(.ln, [.function(.abs, [.function(.cos, [u])])]))
            case .cot: F = .function(.ln, [.function(.abs, [.function(.sin, [u])])])
            case .sec: F = .function(.ln, [.function(.abs, [.sum([.function(.sec, [u]), .function(.tan, [u])])])])
            case .csc: F = .negation(.function(.ln, [.function(.abs, [.sum([.function(.csc, [u]), .function(.cot, [u])])])]))
            case .sinh: F = .function(.cosh, [u])
            case .cosh: F = .function(.sinh, [u])
            case .tanh: F = .function(.ln, [.function(.cosh, [u])])
            case .coth: F = .function(.ln, [.function(.abs, [.function(.sinh, [u])])])
            case .ln: F = .sum([.product([u, .function(.ln, [u])]), .negation(u)])
            case .log10, .log2:
                F = .quotient(.sum([.product([u, .function(.ln, [u])]), .negation(u)]), .function(.ln, [.int(fn == .log10 ? 10 : 2)]))
            case .abs: F = .quotient(.product([u, .function(.abs, [u])]), .int(2))
            case .asin: F = .sum([.product([u, .function(.asin, [u])]), .power(.sum([.one, .negation(u2)]), .number(.half))])
            case .acos: F = .sum([.product([u, .function(.acos, [u])]), .negation(.power(.sum([.one, .negation(u2)]), .number(.half)))])
            case .atan: F = .sum([.product([u, .function(.atan, [u])]), .negation(.quotient(.function(.ln, [.sum([.one, u2])]), .int(2)))])
            case .acot: F = .sum([.product([u, .function(.acot, [u])]), .quotient(.function(.ln, [.sum([.one, u2])]), .int(2))])
            case .asinh: F = .sum([.product([u, .function(.asinh, [u])]), .negation(.power(.sum([u2, .one]), .number(.half)))])
            case .atanh: F = .sum([.product([u, .function(.atanh, [u])]), .quotient(.function(.ln, [.sum([.one, .negation(u2)])]), .int(2))])
            default: return nil
            }
            return .quotient(F, a)
        default:
            return nil
        }
    }

    // MARK: √(αx² + βx + γ) and 1/√(αx² + βx + γ) by completing the square

    static func radical(_ f: Expr, _ x: String) -> Expr? {
        guard case .power(let radicand, let e) = f, let r = e.rationalValue, r == .half || r == Rational(-1, 2),
              let p = Polynomial.extract(from: radicand, variable: x), p.degree == 2 else { return nil }
        let alpha = p.coefficients[2], beta = p.coefficients[1], gamma = p.coefficients[0]
        // radicand = α((x + s)² + k)
        let k = gamma / alpha - beta * beta / (4 * alpha * alpha)
        guard k != 0 else { return nil }
        let u = Simplifier.simplify(.sum([.variable(x), number(beta / (2 * alpha))]))
        let root = Expr.power(radicand, .number(.half))
        if alpha > 0 {
            // ∫ du/√(u² + k) = ln|u + √(u² + k)| with √(u² + k) = √q/√α
            let ln = Expr.function(.ln, [.function(.abs, [.sum([u, .quotient(root, sqrtExpr(alpha))])])])
            if r.isNegative { return .quotient(ln, sqrtExpr(alpha)) }
            // √α·[u/2·√(u² + k) + k/2·ln|u + √(u² + k)|]
            return .sum([.quotient(.product([u, root]), .int(2)), .product([number(k / 2), sqrtExpr(alpha), ln])])
        }
        // α < 0: radicand = |α|(m² − u²)
        let m2 = -k
        guard m2 > 0 else { return nil }
        let arcsin = Expr.function(.asin, [.quotient(u, sqrtExpr(m2))])
        if r.isNegative { return .quotient(arcsin, sqrtExpr(-alpha)) }
        return .sum([.quotient(.product([u, root]), .int(2)), .product([number(m2 / 2), sqrtExpr(-alpha), arcsin])])
    }

    // MARK: Rational functions

    typealias Fraction = (numerator: [Rational], denominator: [Rational])

    /// f as P/Q with exact rational coefficients (lowest power first), deg Q ≥ 1.
    static func rationalFunction(_ f: Expr, _ x: String) -> Fraction? {
        guard let form = rationalForm(f, x), Poly.degree(form.denominator) >= 1 else { return nil }
        return form
    }

    /// Sums of fractions over a common denominator; nil for anything that is not a rational
    /// function of x with rational coefficients.
    static func rationalForm(_ e: Expr, _ x: String) -> Fraction? {
        switch e {
        case .number(let r):
            return ([r], [.one])
        case .variable(let v) where v == x:
            return ([.zero, .one], [.one])
        case .negation(let inner):
            guard let a = rationalForm(inner, x), let n = Poly.scaled(a.numerator, by: .minusOne) else { return nil }
            return (n, a.denominator)
        case .sum(let terms):
            var result: Fraction = ([.zero], [.one])
            for term in terms {
                guard let t = rationalForm(term, x), let left = Poly.multiply(result.numerator, t.denominator),
                      let right = Poly.multiply(t.numerator, result.denominator), let n = Poly.add(left, right),
                      let d = Poly.multiply(result.denominator, t.denominator) else { return nil }
                result = (n, d)
            }
            return result
        case .product(let factors):
            var result: Fraction = ([.one], [.one])
            for factor in factors {
                guard let t = rationalForm(factor, x), let n = Poly.multiply(result.numerator, t.numerator),
                      let d = Poly.multiply(result.denominator, t.denominator) else { return nil }
                result = (n, d)
            }
            return result
        case .quotient(let a, let b):
            guard let p = rationalForm(a, x), let q = rationalForm(b, x), !Poly.isZero(q.numerator),
                  let n = Poly.multiply(p.numerator, q.denominator), let d = Poly.multiply(p.denominator, q.numerator) else { return nil }
            return (n, d)
        case .power(let base, let exponent):
            guard let k = exponent.rationalValue?.integerValue, Swift.abs(k) <= 12, let b = rationalForm(base, x),
                  let n = Poly.power(b.numerator, Swift.abs(k)), let d = Poly.power(b.denominator, Swift.abs(k)) else { return nil }
            if k >= 0 { return (n, d) }
            return Poly.isZero(n) ? nil : (d, n)
        default:
            return nil
        }
    }

    /// A factor of the denominator: x − r or an irreducible x² + px + q, with its multiplicity.
    struct Factor {
        var polynomial: [Rational]
        var multiplicity: Int
        var isQuadratic: Bool { polynomial.count == 3 }
    }

    /// Monic factors over ℚ: rational roots, then quadratics (a power of one quadratic, two
    /// quadratics x⁴ + sx² + t or a quartic with integer coefficients); nil otherwise.
    static func factor(_ monic: [Rational]) -> [Factor]? {
        guard let split = Poly.rationalRoots(monic), let quadratics = quadraticFactors(split.rest) else { return nil }
        return split.roots.map { Factor(polynomial: [$0.value.negated() ?? .zero, .one], multiplicity: $0.multiplicity) } + quadratics
    }

    static func quadraticFactors(_ p: [Rational]) -> [Factor]? {
        let n = Poly.degree(p)
        if n == 0 { return [] }
        if n == 2 { return [Factor(polynomial: p, multiplicity: 1)] }
        guard n % 2 == 0, n <= 8 else { return nil }
        // Qᵐ with Q = x² + bx + c: x^(2m−1) has m·b, x^(2m−2) has m·c + C(m, 2)·b².
        let m = n / 2
        if let b = p[n - 1].divided(by: Rational(m)), let b2 = b.multiplied(by: b),
           let binomial = b2.multiplied(by: Rational(m * (m - 1) / 2)), let rest = p[n - 2].subtracting(binomial),
           let c = rest.divided(by: Rational(m)), let power = Poly.power([c, b, .one], m), power == Poly.trimmed(p) {
            return [Factor(polynomial: [c, b, .one], multiplicity: m)]
        }
        guard n == 4 else { return nil }
        // x⁴ + sx² + t = (x² − y₁)(x² − y₂)
        if p[1].isZero, p[3].isZero, let s2 = p[2].multiplied(by: p[2]), let t4 = p[0].multiplied(by: Rational(4)),
           let discriminant = s2.subtracting(t4), let root = discriminant.root(2), let minusS = p[2].negated(),
           let y1 = minusS.adding(root)?.multiplied(by: .half), let y2 = minusS.subtracting(root)?.multiplied(by: .half),
           y1 != y2, let a = y1.negated(), let b = y2.negated() {
            return [Factor(polynomial: [a, .zero, .one], multiplicity: 1), Factor(polynomial: [b, .zero, .one], multiplicity: 1)]
        }
        // (x² + ax + b)(x² + cx + d) with integers: bd = a₀, a + c = a₃, ad + bc = a₁, b + d + ac = a₂
        guard p.allSatisfy({ $0.isInteger && Swift.abs($0.numerator) <= 1_000_000 }) else { return nil }
        let a0 = p[0].numerator, a1 = p[1].numerator, a2 = p[2].numerator, a3 = p[3].numerator
        guard a0 != 0, let divisors = Poly.divisors(a0) else { return nil }
        for b in divisors.flatMap({ [$0, -$0] }) {
            let d = a0 / b
            var pairs: [(Rational, Rational)] = []
            if b != d {
                // ad + (a₃ − a)b = a₁
                if let a = Rational(a1 - b * a3, d - b), let c = Rational(a3).subtracting(a) { pairs.append((a, c)) }
            } else if a1 == b * a3, let disc = Rational(a3 * a3 - 4 * (a2 - 2 * b)).root(2),
                      let a = Rational(a3).adding(disc)?.multiplied(by: .half), let c = Rational(a3).subtracting(disc)?.multiplied(by: .half) {
                pairs.append((a, c))
            }
            for (a, c) in pairs {
                let first = [Rational(b), a, .one], second = [Rational(d), c, .one]
                if let product = Poly.multiply(first, second), product == Poly.trimmed(p) {
                    return [Factor(polynomial: first, multiplicity: 1), Factor(polynomial: second, multiplicity: 1)]
                }
            }
        }
        return nil
    }

    /// ∫ dx/Qʲ for Q = x² + px + q = u² + d (u = x + p/2, d = q − p²/4):
    /// I₁ = arctan(u/√d)/√d (d > 0) or ln|(u − √−d)/(u + √−d)|/(2√−d),
    /// Iⱼ = u/(2d(j − 1)Q^(j−1)) + (2j − 3)/(2d(j − 1))·Iⱼ₋₁.
    static func quadraticIntegral(_ j: Int, _ quadratic: [Rational], _ x: String) -> Expr? {
        guard let halfP = quadratic[1].multiplied(by: .half), let p2 = halfP.multiplied(by: halfP),
              let d = quadratic[0].subtracting(p2), !d.isZero else { return nil }
        let u = Poly.expr([halfP, .one], x)
        if j == 1 {
            if d.isPositive {
                let root = sqrtExpr(d.doubleValue, exact: d)
                return .quotient(.function(.atan, [.quotient(u, root)]), root)
            }
            guard let minusD = d.negated() else { return nil }
            let root = sqrtExpr(minusD.doubleValue, exact: minusD)
            let ratio = Expr.quotient(.sum([u, .negation(root)]), .sum([u, root]))
            return .quotient(.function(.ln, [.function(.abs, [ratio])]), .product([.int(2), root]))
        }
        guard let previous = quadraticIntegral(j - 1, quadratic, x),
              let twoD = d.multiplied(by: Rational(2 * (j - 1))), let factor = Rational(2 * j - 3).divided(by: twoD) else { return nil }
        let Q = Poly.expr(quadratic, x)
        return .sum([.quotient(u, .product([.number(twoD), .power(Q, .int(j - 1))])), .product([.number(factor), previous])])
    }

    // MARK: Helpers

    static func isZero(_ e: Expr) -> Bool {
        switch e {
        case .number(let r): r.isZero
        case .decimal(let d): d == 0
        default: false
        }
    }

    static func isMinusOne(_ e: Expr) -> Bool {
        if let r = e.rationalValue { return r == .minusOne }
        if case .decimal(let d) = e { return d == -1 }
        return false
    }

    static func number(_ value: Double) -> Expr {
        if let r = Rational.approximating(value, maxDenominator: 10_000, tolerance: 1e-12) { return .number(r) }
        return .decimal(value)
    }

    /// √v exactly where possible (2, √3 …).
    static func sqrtExpr(_ v: Double, exact: Rational? = nil) -> Expr {
        guard let r = exact ?? Rational.approximating(v, maxDenominator: 10_000, tolerance: 1e-12) else { return .decimal(v.squareRoot()) }
        if let root = r.root(2) { return .number(root) }
        return .power(.number(r), .number(.half))
    }

    static func size(_ e: Expr) -> Int { 1 + e.children.reduce(0) { $0 + size($1) } }
}

// MARK: - Search

/// One integration: the methods recurse on simpler integrands within a step budget.
struct Search {
    private var steps = 0
    private var fresh = 0

    mutating func integrate(_ input: Expr, _ x: String, depth: Int) -> Expr? {
        steps += 1
        guard depth < 14, steps < 4000 else { return nil }
        let f = Simplifier.simplify(input)
        if !f.dependsOn(x) { return .product([f, .variable(x)]) }
        switch f {
        case .sum(let terms):
            var parts: [Expr] = []
            for term in terms {
                guard let part = integrate(term, x, depth: depth + 1) else { return nil }
                parts.append(part)
            }
            return .sum(parts)
        case .product(let factors) where factors.contains(where: { !$0.dependsOn(x) }):
            let constants = factors.filter { !$0.dependsOn(x) }
            let rest = factors.filter { $0.dependsOn(x) }
            return integrate(rest.count == 1 ? rest[0] : .product(rest), x, depth: depth + 1).map { .product(constants + [$0]) }
        default:
            break
        }
        if let r = Antiderivative.table(f, x) ?? Antiderivative.radical(f, x) { return r }
        if let rational = Antiderivative.rationalFunction(f, x),
           let r = integrateRational(rational.numerator, rational.denominator, x, depth: depth) { return r }
        if let r = trigonometric(f, x, depth: depth) { return r }
        if let r = byParts(f, x, depth: depth) { return r }
        if let r = substitution(f, x, depth: depth) { return r }
        if let r = exponentialSubstitution(f, x, depth: depth) { return r }
        if let r = universalSubstitution(f, x, depth: depth) { return r }
        // (x + 1)²·x, (x² + 1)³ …: multiplying out gives simple terms.
        let expanded = Simplifier.expand(f)
        if expanded != f, case .sum = expanded { return integrate(expanded, x, depth: depth + 1) }
        return nil
    }

    /// A fresh name for the variable of a substitution.
    private mutating func freshVariable() -> String {
        fresh += 1
        return "τ\(fresh)"
    }

    // MARK: Partial fractions

    mutating func integrateRational(_ numerator: [Rational], _ denominator: [Rational], _ x: String, depth: Int) -> Expr? {
        var numerator = Poly.trimmed(numerator), denominator = Poly.trimmed(denominator)
        // Cancel common factors first (smaller denominators factor more easily).
        if let common = Poly.gcd(numerator, denominator), Poly.degree(common) >= 1,
           let n = Poly.divide(numerator, by: common), let d = Poly.divide(denominator, by: common),
           Poly.isZero(n.remainder), Poly.isZero(d.remainder) {
            numerator = n.quotient
            denominator = d.quotient
        }
        if Poly.degree(denominator) == 0 {
            guard let scale = denominator.first?.reciprocal(), let p = Poly.scaled(numerator, by: scale) else { return nil }
            return integrate(Poly.expr(p, x), x, depth: depth + 1)
        }
        guard let lead = denominator.last, let inverse = lead.reciprocal(),
              let den = Poly.scaled(denominator, by: inverse), let num = Poly.scaled(numerator, by: inverse),
              let division = Poly.divide(num, by: den) else { return nil }
        var pieces: [Expr] = []
        if !Poly.isZero(division.quotient) {
            guard let q = integrate(Poly.expr(division.quotient, x), x, depth: depth + 1) else { return nil }
            pieces.append(q)
        }
        let remainder = division.remainder
        if Poly.isZero(remainder) { return pieces.isEmpty ? .zero : .sum(pieces) }
        guard let factors = Antiderivative.factor(den) else { return nil }
        // Undetermined coefficients: one per A/(x − r)ᵏ, two per (Bx + C)/Qʲ.
        struct Unknown {
            var factor: Int
            var power: Int
            var linearPart: Bool
            var basis: [Rational]
        }
        var unknowns: [Unknown] = []
        for (index, factor) in factors.enumerated() {
            for power in 1...factor.multiplicity {
                var cofactor: [Rational] = [.one]
                for (other, f) in factors.enumerated() {
                    guard let p = Poly.power(f.polynomial, other == index ? f.multiplicity - power : f.multiplicity),
                          let product = Poly.multiply(cofactor, p) else { return nil }
                    cofactor = product
                }
                if factor.isQuadratic {
                    guard let shifted = Poly.multiply(cofactor, [.zero, .one]) else { return nil }
                    unknowns.append(Unknown(factor: index, power: power, linearPart: true, basis: shifted))
                }
                unknowns.append(Unknown(factor: index, power: power, linearPart: false, basis: cofactor))
            }
        }
        let n = Poly.degree(den)
        guard unknowns.count == n else { return nil }
        var matrix: [Rational] = []
        var constants: [Rational] = []
        for power in 0..<n {
            for unknown in unknowns { matrix.append(power < unknown.basis.count ? unknown.basis[power] : .zero) }
            constants.append(power < remainder.count ? remainder[power] : .zero)
        }
        guard case .unique(let solution)? = try? LinearSystemSolver.solve(coefficients: Matrix(rows: n, columns: n, exact: matrix),
                                                                         constants: Matrix(rows: n, columns: 1, exact: constants)),
              let coefficients = solution.exact, coefficients.count == n else { return nil }
        // Coefficients by factor and power: (B of Bx, C).
        var parts: [Int: [Int: (b: Rational, c: Rational)]] = [:]
        for (unknown, value) in zip(unknowns, coefficients) {
            var entry = parts[unknown.factor]?[unknown.power] ?? (b: .zero, c: .zero)
            if unknown.linearPart { entry.b = value } else { entry.c = value }
            parts[unknown.factor, default: [:]][unknown.power] = entry
        }
        for (index, factor) in factors.enumerated() {
            let polynomial = Poly.expr(factor.polynomial, x)
            for power in 1...factor.multiplicity {
                guard let entry = parts[index]?[power], !(entry.b.isZero && entry.c.isZero) else { continue }
                if !factor.isQuadratic {
                    // c/(x − r)ᵏ
                    if power == 1 {
                        pieces.append(.product([.number(entry.c), .function(.ln, [.function(.abs, [polynomial])])]))
                    } else {
                        guard let k = entry.c.divided(by: Rational(1 - power)) else { return nil }
                        pieces.append(.product([.number(k), .power(polynomial, .int(1 - power))]))
                    }
                    continue
                }
                // (bx + c)/Qʲ = (b/2)(2x + p)/Qʲ + (c − bp/2)/Qʲ
                let p = factor.polynomial[1]
                guard let halfB = entry.b.multiplied(by: .half), let bp = halfB.multiplied(by: p),
                      let rest = entry.c.subtracting(bp), let halfP = p.multiplied(by: .half),
                      let p2 = halfP.multiplied(by: halfP), let d = factor.polynomial[0].subtracting(p2) else { return nil }
                if !halfB.isZero {
                    if power == 1 {
                        // Q > 0 everywhere when it has no real roots.
                        let ln: Expr = d.isPositive ? .function(.ln, [polynomial]) : .function(.ln, [.function(.abs, [polynomial])])
                        pieces.append(.product([.number(halfB), ln]))
                    } else {
                        guard let k = halfB.divided(by: Rational(1 - power)) else { return nil }
                        pieces.append(.product([.number(k), .power(polynomial, .int(1 - power))]))
                    }
                }
                if !rest.isZero {
                    guard let integral = Antiderivative.quadraticIntegral(power, factor.polynomial, x) else { return nil }
                    pieces.append(.product([.number(rest), integral]))
                }
            }
        }
        return pieces.isEmpty ? .zero : .sum(pieces)
    }

    // MARK: Trigonometric integrands

    mutating func trigonometric(_ f: Expr, _ x: String, depth: Int) -> Expr? {
        if case .power(.function(let fn, let args), let e) = f, args.count == 1, let n = e.rationalValue?.integerValue,
           let a = Antiderivative.linearCoefficient(args[0], x) {
            let u = args[0]
            switch (fn, n) {
            case (.cos, -2): return .quotient(.function(.tan, [u]), a)
            case (.sin, -2): return .negation(.quotient(.function(.cot, [u]), a))
            case (.cosh, -2): return .quotient(.function(.tanh, [u]), a)
            case (.sinh, -2): return .negation(.quotient(.function(.coth, [u]), a))
            case (.cos, -1):
                // ln|1/cos u + tan u|
                return .quotient(.function(.ln, [.function(.abs, [.sum([.power(.function(.cos, [u]), .int(-1)), .function(.tan, [u])])])]), a)
            case (.sin, -1):
                return .quotient(.function(.ln, [.function(.abs, [.function(.tan, [.quotient(u, .int(2))])])]), a)
            case (.tan, let k) where k >= 2:
                // tanᵏ u = tanᵏ⁻² u·(1/cos² u − 1)
                let lower = Expr.power(.function(.tan, [u]), .int(k - 2))
                return integrate(.sum([.product([lower, .power(.function(.cos, [u]), .int(-2))]), .negation(lower)]), x, depth: depth + 1)
            default:
                break
            }
        }
        if let rewritten = productToSum(f, x) { return integrate(rewritten, x, depth: depth + 1) }
        guard let powers = sineCosinePowers(f, x), powers.m + powers.n >= 2 else { return nil }
        let u = powers.argument, m = powers.m, n = powers.n
        let sin = Expr.function(.sin, [u]), cos = Expr.function(.cos, [u])
        func power(_ e: Expr, _ k: Int) -> Expr { .power(e, .int(k)) }
        let rewritten: Expr
        if m % 2 == 1 && m >= 3 {
            // sin u·(1 − cos² u)^((m−1)/2)·cosⁿ u, then u = cos
            rewritten = .product([sin, power(.sum([.one, .negation(power(cos, 2))]), (m - 1) / 2), power(cos, n)])
        } else if n % 2 == 1 && n >= 3 {
            rewritten = .product([cos, power(.sum([.one, .negation(power(sin, 2))]), (n - 1) / 2), power(sin, m)])
        } else if m % 2 == 0 && n % 2 == 0 {
            // sin² u = (1 − cos 2u)/2, cos² u = (1 + cos 2u)/2
            let double = Expr.function(.cos, [Simplifier.simplify(.product([.int(2), u]))])
            rewritten = .product([power(.quotient(.sum([.one, .negation(double)]), .int(2)), m / 2),
                                  power(.quotient(.sum([.one, double]), .int(2)), n / 2)])
        } else {
            return nil  // sin u·cosⁿ u and sinᵐ u·cos u: substitution
        }
        let expanded = Simplifier.expand(rewritten)
        guard expanded != f else { return nil }
        return integrate(expanded, x, depth: depth + 1)
    }

    /// sinᵐ u·cosⁿ u (m, n ≥ 0) for one linear argument u.
    func sineCosinePowers(_ f: Expr, _ x: String) -> (argument: Expr, m: Int, n: Int)? {
        let factors: [Expr] = { if case .product(let list) = f { return list } else { return [f] } }()
        var argument: Expr?
        var m = 0, n = 0
        for factor in factors {
            var base = factor, k = 1
            if case .power(let b, let e) = factor, let integer = e.rationalValue?.integerValue, integer > 0 {
                base = b
                k = integer
            }
            guard case .function(let fn, let args) = base, args.count == 1, fn == .sin || fn == .cos else { return nil }
            if let argument, argument != args[0] { return nil }
            argument = args[0]
            if fn == .sin { m += k } else { n += k }
        }
        guard let argument, Antiderivative.linearCoefficient(argument, x) != nil else { return nil }
        return (argument, m, n)
    }

    /// sin A·cos B = (sin(A + B) + sin(A − B))/2 and the like, for different linear A and B.
    func productToSum(_ f: Expr, _ x: String) -> Expr? {
        guard case .product(let factors) = f, factors.count == 2,
              case .function(let f1, let a1) = factors[0], case .function(let f2, let a2) = factors[1],
              a1.count == 1, a2.count == 1, a1[0] != a2[0], f1 == .sin || f1 == .cos, f2 == .sin || f2 == .cos,
              Antiderivative.linearCoefficient(a1[0], x) != nil, Antiderivative.linearCoefficient(a2[0], x) != nil else { return nil }
        let plus = Simplifier.simplify(.sum([a1[0], a2[0]]))
        let minus = Simplifier.simplify(.sum([a1[0], .negation(a2[0])]))
        func half(_ e: Expr) -> Expr { .quotient(e, .int(2)) }
        switch (f1, f2) {
        case (.sin, .cos): return half(.sum([.function(.sin, [plus]), .function(.sin, [minus])]))
        case (.cos, .sin): return half(.sum([.function(.sin, [plus]), .negation(.function(.sin, [minus]))]))
        case (.sin, .sin): return half(.sum([.function(.cos, [minus]), .negation(.function(.cos, [plus]))]))
        default: return half(.sum([.function(.cos, [minus]), .function(.cos, [plus])]))
        }
    }

    // MARK: Integration by parts

    mutating func byParts(_ f: Expr, _ x: String, depth: Int) -> Expr? {
        let factors: [Expr] = { if case .product(let list) = f { return list } else { return [f] } }()
        if factors.count == 2, let closed = exponentialTimesTrig(factors[0], factors[1], x) ?? exponentialTimesTrig(factors[1], factors[0], x) {
            return closed
        }
        for (index, g) in factors.enumerated() {
            var rest = factors
            rest.remove(at: index)
            let p: Expr = rest.isEmpty ? .one : rest.count == 1 ? rest[0] : .product(rest)
            guard let polynomial = Polynomial.extract(from: p, variable: x), polynomial.degree <= 8 else { continue }
            if polynomial.degree >= 1, isRepeatable(g, x) {
                // Tabular: P·G₁ − P′·G₂ + P″·G₃ − …
                var terms: [Expr] = []
                var derivative = Simplifier.simplify(p)
                var antiderivative = g
                var positive = true
                for _ in 0...polynomial.degree {
                    guard let G = integrate(antiderivative, x, depth: depth + 1) else { return nil }
                    let term = Expr.product([derivative, G])
                    terms.append(positive ? term : .negation(term))
                    guard let d = try? Differentiator.derivative(of: derivative, withRespectTo: x) else { return nil }
                    derivative = d
                    antiderivative = G
                    positive.toggle()
                    if Antiderivative.isZero(derivative) { break }
                }
                return .sum(terms)
            }
            if isLogarithmic(g, x) {
                // ∫P·g = Q·g − ∫Q·g′ (ln, arctan, arcsin … and powers of ln)
                guard let Q = integrate(p, x, depth: depth + 1),
                      let dg = try? Differentiator.derivative(of: g, withRespectTo: x),
                      let remaining = integrate(.product([Q, dg]), x, depth: depth + 1) else { continue }
                return .sum([.product([Q, g]), .negation(remaining)])
            }
        }
        return nil
    }

    /// Functions whose repeated integrals stay simple: sin, cos, sinh, cosh and exponentials of
    /// a linear argument, and powers (ax + b)ʳ with r not a negative integer.
    func isRepeatable(_ g: Expr, _ x: String) -> Bool {
        switch g {
        case .function(let fn, let args) where args.count == 1:
            return [.sin, .cos, .sinh, .cosh].contains(fn) && Antiderivative.linearCoefficient(args[0], x) != nil
        case .power(let base, let exponent):
            if !base.dependsOn(x) { return Antiderivative.linearCoefficient(exponent, x) != nil }
            guard !exponent.dependsOn(x), Antiderivative.linearCoefficient(base, x) != nil else { return false }
            if let r = exponent.rationalValue, r.isInteger, !r.isPositive { return false }
            return true
        default:
            return false
        }
    }

    func isLogarithmic(_ g: Expr, _ x: String) -> Bool {
        switch g {
        case .function(let fn, let args) where args.count == 1:
            return [.ln, .log10, .log2, .atan, .asin, .acos, .acot, .asinh, .atanh].contains(fn) && args[0].dependsOn(x)
        case .power(.function(.ln, let args), let e) where args.count == 1:
            return (e.rationalValue?.integerValue ?? 0) >= 2
        default:
            return false
        }
    }

    /// ∫ e^(ax+c)·sin(bx+d) and ·cos(bx+d) in closed form.
    func exponentialTimesTrig(_ e: Expr, _ t: Expr, _ x: String) -> Expr? {
        guard case .power(.constant(.e), let exponent) = e,
              case .function(let fn, let args) = t, args.count == 1, fn == .sin || fn == .cos,
              let a = Antiderivative.linearCoefficient(exponent, x), let b = Antiderivative.linearCoefficient(args[0], x) else { return nil }
        let v = args[0]
        let norm = Expr.sum([.power(a, .int(2)), .power(b, .int(2))])
        let inner: Expr = fn == .sin
            ? .sum([.product([a, .function(.sin, [v])]), .negation(.product([b, .function(.cos, [v])]))])
            : .sum([.product([a, .function(.cos, [v])]), .product([b, .function(.sin, [v])])])
        return .quotient(.product([e, inner]), norm)
    }

    // MARK: Substitution

    /// ∫ g(u(x))·u′(x) dx = G(u(x)) for an inner function u of the integrand.
    mutating func substitution(_ f: Expr, _ x: String, depth: Int) -> Expr? {
        let t = freshVariable()
        for u in candidates(f, x) {
            guard let derivative = try? Differentiator.derivative(of: u, withRespectTo: x), !Antiderivative.isZero(derivative) else { continue }
            let ratio = Simplifier.simplify(.quotient(f, derivative))
            let replaced = Simplifier.simplify(replacing(ratio, u, with: .variable(t)))
            guard !replaced.dependsOn(x), replaced.dependsOn(t), let G = integrate(replaced, t, depth: depth + 1) else { continue }
            return G.substituting(t, with: u)
        }
        return nil
    }

    /// Inner functions worth substituting: non-linear arguments, bases and exponents, and the
    /// function calls themselves (ln x in ln x/x), largest first.
    func candidates(_ f: Expr, _ x: String) -> [Expr] {
        var found: [Expr] = []
        func visit(_ e: Expr) {
            switch e {
            case .function(_, let args):
                for arg in args where arg.dependsOn(x) && Antiderivative.linearCoefficient(arg, x) == nil { found.append(arg) }
                if e.dependsOn(x) { found.append(e) }
            case .power(let base, let exponent):
                if base.dependsOn(x), Antiderivative.linearCoefficient(base, x) == nil { found.append(base) }
                if exponent.dependsOn(x), Antiderivative.linearCoefficient(exponent, x) == nil { found.append(exponent) }
            default:
                break
            }
            e.children.forEach(visit)
        }
        visit(f)
        var unique: [Expr] = []
        for c in found where !unique.contains(c) && c != .variable(x) { unique.append(c) }
        return unique.sorted { Antiderivative.size($0) > Antiderivative.size($1) }
    }

    /// Replaces u by τ, also inside powers: x⁴ = (x²)² for u = x².
    func replacing(_ e: Expr, _ target: Expr, with replacement: Expr) -> Expr {
        if e == target { return replacement }
        if case .power(let base, let exponent) = e, let k = exponent.rationalValue {
            if base == target { return .power(replacement, exponent) }
            if case .power(let targetBase, let targetExponent) = target, base == targetBase,
               let m = targetExponent.rationalValue, let ratio = k.divided(by: m), ratio.isInteger {
                return .power(replacement, .number(ratio))
            }
        }
        return e.mapChildren { replacing($0, target, with: replacement) }
    }

    /// R(e^(gx)) dx with τ = e^(gx), dx = dτ/(g·τ) (eˣ/(1 + e²ˣ) → arctan eˣ).
    mutating func exponentialSubstitution(_ f: Expr, _ x: String, depth: Int) -> Expr? {
        var rates: [Rational] = []
        var valid = true
        func visit(_ e: Expr) {
            if case .power(.constant(.e), let w) = e, w.dependsOn(x) {
                if let p = Polynomial.extract(from: w, variable: x), p.degree == 1, let c = p.exactCoefficients, c[0].isZero {
                    rates.append(c[1])
                } else {
                    valid = false
                }
                return
            }
            if case .variable(let v) = e, v == x { valid = false }
            e.children.forEach(visit)
        }
        visit(f)
        guard valid, let g = rates.map(\.magnitude).min(), !g.isZero else { return nil }
        let t = freshVariable()
        func replace(_ e: Expr) -> Expr {
            if case .power(.constant(.e), let w) = e, let p = Polynomial.extract(from: w, variable: x),
               let c = p.exactCoefficients, c.count == 2, let k = c[1].divided(by: g) {
                return .power(.variable(t), .number(k))
            }
            return e.mapChildren(replace)
        }
        let replaced = replace(f)
        guard !replaced.dependsOn(x),
              let G = integrate(.quotient(replaced, .product([.number(g), .variable(t)])), t, depth: depth + 1) else { return nil }
        return G.substituting(t, with: .power(.constant(.e), Simplifier.simplify(.product([.number(g), .variable(x)]))))
    }

    /// R(sin u, cos u, tan u) with t = tan(u/2): sin u = 2t/(1 + t²), cos u = (1 − t²)/(1 + t²),
    /// du = 2 dt/(1 + t²).
    mutating func universalSubstitution(_ f: Expr, _ x: String, depth: Int) -> Expr? {
        var argument: Expr?
        var valid = true
        func visit(_ e: Expr) {
            switch e {
            case .function(let fn, let args) where fn == .sin || fn == .cos || fn == .tan:
                guard args.count == 1, argument == nil || argument == args[0] else { valid = false; return }
                argument = args[0]
            case .variable(let v) where v == x:
                valid = false
            case .function:
                if e.dependsOn(x) { valid = false }
            default:
                e.children.forEach(visit)
            }
        }
        visit(f)
        guard valid, let u = argument, let a = Antiderivative.linearCoefficient(u, x) else { return nil }
        let t = freshVariable()
        let T = Expr.variable(t)
        let onePlus = Expr.sum([.one, .power(T, .int(2))])
        let oneMinus = Expr.sum([.one, .negation(.power(T, .int(2)))])
        func replace(_ e: Expr) -> Expr {
            if case .function(let fn, _) = e {
                switch fn {
                case .sin: return .quotient(.product([.int(2), T]), onePlus)
                case .cos: return .quotient(oneMinus, onePlus)
                case .tan: return .quotient(.product([.int(2), T]), oneMinus)
                default: break
                }
            }
            return e.mapChildren(replace)
        }
        let integrand = Simplifier.simplify(.quotient(.product([.int(2), replace(f)]), .product([a, onePlus])))
        guard let rational = Antiderivative.rationalFunction(integrand, t),
              let G = integrateRational(rational.numerator, rational.denominator, t, depth: depth + 1) else { return nil }
        return G.substituting(t, with: .function(.tan, [.quotient(u, .int(2))]))
    }
}

// MARK: - Exact polynomials

/// Exact polynomial arithmetic on coefficient lists (lowest power first); nil on overflow.
enum Poly {
    static func trimmed(_ c: [Rational]) -> [Rational] {
        var c = c
        while c.count > 1, c.last?.isZero == true { c.removeLast() }
        return c.isEmpty ? [.zero] : c
    }

    static func isZero(_ c: [Rational]) -> Bool { c.allSatisfy(\.isZero) }

    static func degree(_ c: [Rational]) -> Int { trimmed(c).count - 1 }

    static func scaled(_ c: [Rational], by k: Rational) -> [Rational]? {
        var out: [Rational] = []
        for value in c {
            guard let product = value.multiplied(by: k) else { return nil }
            out.append(product)
        }
        return out
    }

    static func add(_ a: [Rational], _ b: [Rational]) -> [Rational]? {
        var out = [Rational](repeating: .zero, count: max(a.count, b.count))
        for i in out.indices {
            guard let s = (i < a.count ? a[i] : .zero).adding(i < b.count ? b[i] : .zero) else { return nil }
            out[i] = s
        }
        return trimmed(out)
    }

    /// Monic greatest common divisor (Euclid); nil on overflow.
    static func gcd(_ a: [Rational], _ b: [Rational]) -> [Rational]? {
        var x = trimmed(a), y = trimmed(b)
        while !isZero(y) {
            guard let r = divide(x, by: y)?.remainder else { return nil }
            (x, y) = (y, r)
        }
        guard let lead = x.last, let inverse = lead.reciprocal() else { return nil }
        return scaled(x, by: inverse)
    }

    static func multiply(_ a: [Rational], _ b: [Rational]) -> [Rational]? {
        var out = [Rational](repeating: .zero, count: a.count + b.count - 1)
        for (i, x) in a.enumerated() where !x.isZero {
            for (j, y) in b.enumerated() where !y.isZero {
                guard let product = x.multiplied(by: y), let s = out[i + j].adding(product) else { return nil }
                out[i + j] = s
            }
        }
        return trimmed(out)
    }

    static func power(_ p: [Rational], _ n: Int) -> [Rational]? {
        var result: [Rational] = [.one]
        for _ in 0..<max(0, n) {
            guard let next = multiply(result, p) else { return nil }
            result = next
        }
        return result
    }

    /// a = q·b + r with deg r < deg b.
    static func divide(_ a: [Rational], by b: [Rational]) -> (quotient: [Rational], remainder: [Rational])? {
        let divisor = trimmed(b)
        guard let lead = divisor.last, !lead.isZero else { return nil }
        var remainder = trimmed(a)
        var quotient = [Rational](repeating: .zero, count: max(1, remainder.count - divisor.count + 1))
        while remainder.count >= divisor.count, !isZero(remainder) {
            let shift = remainder.count - divisor.count
            guard let factor = remainder.last?.divided(by: lead) else { return nil }
            quotient[shift] = factor
            for (i, d) in divisor.enumerated() {
                guard let product = d.multiplied(by: factor), let s = remainder[i + shift].subtracting(product) else { return nil }
                remainder[i + shift] = s
            }
            remainder.removeLast()
            remainder = trimmed(remainder)
        }
        return (trimmed(quotient), trimmed(remainder))
    }

    /// Rational roots with multiplicity (rational root theorem) and the factor that is left.
    static func rationalRoots(_ c: [Rational]) -> (roots: [(value: Rational, multiplicity: Int)], rest: [Rational])? {
        var rest = trimmed(c)
        var roots: [(value: Rational, multiplicity: Int)] = []
        while degree(rest) >= 1 {
            guard let candidates = rootCandidates(rest) else { return nil }
            var found = false
            for r in candidates {
                guard let negated = r.negated(), let division = divide(rest, by: [negated, .one]), isZero(division.remainder) else { continue }
                if let i = roots.firstIndex(where: { $0.value == r }) {
                    roots[i].multiplicity += 1
                } else {
                    roots.append((value: r, multiplicity: 1))
                }
                rest = division.quotient
                found = true
                break
            }
            if !found { break }
        }
        return (roots, rest)
    }

    /// ±p/q with p | a₀ and q | aₙ of the polynomial scaled to integers.
    static func rootCandidates(_ c: [Rational]) -> [Rational]? {
        var lcm = 1
        for value in c {
            guard let l = Rational.lcm(lcm, value.denominator) else { return nil }
            lcm = l
        }
        var integers: [Int] = []
        for value in c {
            let (scaled, overflow) = value.numerator.multipliedReportingOverflow(by: lcm / value.denominator)
            guard !overflow else { return nil }
            integers.append(scaled)
        }
        guard let lowest = integers.first, let leading = integers.last, leading != 0 else { return nil }
        if lowest == 0 { return [.zero] }
        guard let ps = divisors(lowest), let qs = divisors(leading) else { return nil }
        var out: [Rational] = []
        for p in ps {
            for q in qs {
                guard let r = Rational(p, q) else { continue }
                out.append(r)
                if let negative = r.negated() { out.append(negative) }
            }
        }
        return out
    }

    /// Positive divisors of n (|n| ≤ 10⁷).
    static func divisors(_ n: Int) -> [Int]? {
        guard n != Int.min else { return nil }
        let m = Swift.abs(n)
        guard m > 0, m <= 10_000_000 else { return nil }
        var small: [Int] = [], large: [Int] = []
        var d = 1
        while d * d <= m {
            if m % d == 0 {
                small.append(d)
                if d != m / d { large.append(m / d) }
            }
            d += 1
        }
        return small + large.reversed()
    }

    static func expr(_ c: [Rational], _ x: String) -> Expr {
        var terms: [Expr] = []
        for (power, coefficient) in c.enumerated().reversed() where !coefficient.isZero {
            let monomial: Expr = power == 1 ? .variable(x) : .power(.variable(x), .int(power))
            if power == 0 {
                terms.append(.number(coefficient))
            } else if coefficient == .one {
                terms.append(monomial)
            } else {
                terms.append(.product([.number(coefficient), monomial]))
            }
        }
        return terms.isEmpty ? .zero : terms.count == 1 ? terms[0] : .sum(terms)
    }
}
