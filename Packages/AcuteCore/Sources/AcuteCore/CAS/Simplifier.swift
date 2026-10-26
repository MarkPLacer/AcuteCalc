import Foundation

/// A small, predictable algebraic simplifier.
///
/// It canonicalises (`a − b → a + (−1)·b`, `a/b → a·b⁻¹`, `√x → x^½`), folds exact
/// constants, collects like terms and equal bases, and applies a handful of
/// identities. It intentionally never expands products of sums (use `expand`).
public enum Simplifier {
    public static func simplify(_ expr: Expr) -> Expr {
        var current = canonical(expr)
        // A few passes reach a fixed point for everything we generate.
        for _ in 0..<4 {
            let next = pass(current)
            if next == current { break }
            current = next
        }
        return current
    }

    // MARK: Canonical form

    static func canonical(_ expr: Expr) -> Expr {
        let e = expr.mapChildren(canonical)
        switch e {
        case .negation(let inner):
            return .product([.number(.minusOne), inner])
        case .quotient(let a, let b):
            return .product([a, .power(b, .number(.minusOne))])
        case .function(.sqrt, let args) where args.count == 1:
            return .power(args[0], .number(.half))
        case .function(.cbrt, let args) where args.count == 1:
            return .power(args[0], .number(Rational(1, 3)!))
        case .function(.root, let args) where args.count == 2:
            if let n = args[0].rationalValue, let inv = n.reciprocal() {
                return .power(args[1], .number(inv))
            }
            return .power(args[1], .power(args[0], .number(.minusOne)))
        case .function(.exp, let args) where args.count == 1:
            return .power(.constant(.e), args[0])
        case .percent(let inner):
            return .product([inner, .number(Rational(1, 100)!)])
        default:
            return e
        }
    }

    static func pass(_ expr: Expr) -> Expr {
        let e = expr.mapChildren(pass)
        switch e {
        case .sum(let terms): return simplifySum(terms)
        case .product(let factors): return simplifyProduct(factors)
        case .power(let b, let x): return simplifyPower(b, x)
        case .function(let f, let args): return simplifyFunction(f, args)
        case .negation(let inner): return simplifyProduct([.number(.minusOne), inner])
        case .quotient(let a, let b): return simplifyProduct([a, simplifyPower(b, .number(.minusOne))])
        default: return e
        }
    }

    // MARK: Numbers

    enum Num {
        case exact(Rational)
        case approx(Double)

        var double: Double {
            switch self {
            case .exact(let r): r.doubleValue
            case .approx(let d): d
            }
        }

        var expr: Expr {
            switch self {
            case .exact(let r): .number(r)
            case .approx(let d): .decimal(d)
            }
        }

        var isZero: Bool { double == 0 }
        var isOne: Bool { if case .exact(let r) = self { return r == .one }; return double == 1 }

        static func + (a: Num, b: Num) -> Num {
            if case .exact(let x) = a, case .exact(let y) = b, let s = x.adding(y) { return .exact(s) }
            return .approx(a.double + b.double)
        }

        static func * (a: Num, b: Num) -> Num {
            if case .exact(let x) = a, case .exact(let y) = b, let p = x.multiplied(by: y) { return .exact(p) }
            return .approx(a.double * b.double)
        }
    }

    static func numeric(_ e: Expr) -> Num? {
        switch e {
        case .number(let r): .exact(r)
        case .decimal(let d): .approx(d)
        default: nil
        }
    }

    // MARK: Sums

    /// Splits `3·x²` into (3, x²); terms without a numeric factor get coefficient 1.
    static func splitCoefficient(_ term: Expr) -> (Num, Expr?) {
        if let n = numeric(term) { return (n, nil) }
        if case .product(let factors) = term, let first = factors.first, let n = numeric(first) {
            let rest = Array(factors.dropFirst())
            return (n, rest.count == 1 ? rest[0] : .product(rest))
        }
        return (.exact(.one), term)
    }

    static func simplifySum(_ input: [Expr]) -> Expr {
        var terms: [Expr] = []
        for t in input {
            if case .sum(let inner) = t { terms.append(contentsOf: inner) } else { terms.append(t) }
        }
        var constant = Num.exact(.zero)
        var order: [Expr] = []
        var coefficients: [Expr: Num] = [:]
        for t in terms {
            let (c, rest) = splitCoefficient(t)
            guard let rest else { constant = constant + c; continue }
            if let existing = coefficients[rest] {
                coefficients[rest] = existing + c
            } else {
                coefficients[rest] = c
                order.append(rest)
            }
        }
        var result: [Expr] = []
        for rest in order {
            guard let c = coefficients[rest], !c.isZero else { continue }
            result.append(makeTerm(c, rest))
        }
        result.sort(by: termOrder)
        if !constant.isZero { result.append(constant.expr) }
        if result.isEmpty { return constant.expr }
        return result.count == 1 ? result[0] : .sum(result)
    }

    static func makeTerm(_ c: Num, _ rest: Expr) -> Expr {
        if c.isOne { return rest }
        if case .product(let factors) = rest { return .product([c.expr] + factors) }
        return .product([c.expr, rest])
    }

    /// Orders sum terms by descending polynomial degree, then structurally.
    static func termOrder(_ a: Expr, _ b: Expr) -> Bool {
        let da = degree(a)
        let db = degree(b)
        if da != db { return da > db }
        return sortKey(a) < sortKey(b)
    }

    static func degree(_ e: Expr) -> Double {
        switch e {
        case .variable: return 1
        case .power(let b, let x):
            if case .variable = b, let n = numeric(x) { return n.double }
            return degree(b) * (numeric(x)?.double ?? 1)
        case .product(let factors): return factors.reduce(0) { $0 + degree($1) }
        case .function: return 0.5
        default: return 0
        }
    }

    // MARK: Products

    static func simplifyProduct(_ input: [Expr]) -> Expr {
        var factors: [Expr] = []
        for f in input {
            if case .product(let inner) = f { factors.append(contentsOf: inner) } else { factors.append(f) }
        }
        var coefficient = Num.exact(.one)
        var order: [Expr] = []
        var exponents: [Expr: [Expr]] = [:]
        for f in factors {
            if let n = numeric(f) {
                if n.isZero { return .number(.zero) }
                coefficient = coefficient * n
                continue
            }
            let (base, exponent): (Expr, Expr) = {
                if case .power(let b, let x) = f { return (b, x) }
                return (f, .number(.one))
            }()
            if exponents[base] == nil { order.append(base) }
            exponents[base, default: []].append(exponent)
        }
        var result: [Expr] = []
        for base in order {
            guard let list = exponents[base] else { continue }
            let exponent = list.count == 1 ? list[0] : simplifySum(list)
            let p = simplifyPower(base, exponent)
            if let n = numeric(p) {
                coefficient = coefficient * n
            } else if case .product(let inner) = p {
                // e.g. (2x)² → 4x²
                for f in inner {
                    if let n = numeric(f) { coefficient = coefficient * n } else { result.append(f) }
                }
            } else {
                result.append(p)
            }
        }
        if coefficient.isZero { return .number(.zero) }
        result.sort { sortKey($0) < sortKey($1) }
        if result.isEmpty { return coefficient.expr }
        if !coefficient.isOne { result.insert(coefficient.expr, at: 0) }
        return result.count == 1 ? result[0] : .product(result)
    }

    // MARK: Powers

    static func simplifyPower(_ base: Expr, _ exponent: Expr) -> Expr {
        if let x = numeric(exponent) {
            if x.isZero { return .number(.one) }
            if x.isOne { return base }
        }
        if let b = numeric(base) {
            if b.isOne { return .number(.one) }
            if b.isZero, let x = numeric(exponent), x.double > 0 { return .number(.zero) }
            if let x = numeric(exponent) {
                switch (b, x) {
                case (.exact(let rb), .exact(let rx)):
                    if rx.isInteger, let p = rb.power(rx.numerator) { return .number(p) }
                    if !rx.isInteger, let root = rb.root(rx.denominator), let p = root.power(rx.numerator) {
                        return .number(p)
                    }
                    // Keep irrational powers like 2^(1/2) symbolic, but pull out perfect squares:
                    // √12 → 2·√3, √(1/2) → ½·√2
                    if rx == .half, rb.isPositive, let exact = ExactReal.squareRoot(of: rb), exact.terms.count == 1,
                       let term = exact.sortedTerms.first, term.basis.radicand > 1, term.coefficient != .one {
                        return .product([.number(term.coefficient), .power(.number(Rational(term.basis.radicand)), .number(.half))])
                    }
                    return .power(base, exponent)
                default:
                    return .decimal(Foundation.pow(b.double, x.double))
                }
            }
        }
        // (a^b)^c → a^(b·c) for integer c
        if case .power(let innerBase, let innerExp) = base, let c = numeric(exponent),
           case .exact(let rc) = c, rc.isInteger {
            return simplifyPower(innerBase, simplifyProduct([innerExp, exponent]))
        }
        // (a·b)^n → aⁿ·bⁿ for integer n
        if case .product(let factors) = base, let c = numeric(exponent), case .exact(let rc) = c, rc.isInteger {
            return simplifyProduct(factors.map { simplifyPower($0, exponent) })
        }
        // e^(ln u) → u
        if case .constant(.e) = base, case .function(.ln, let args) = exponent, args.count == 1 {
            return args[0]
        }
        return .power(base, exponent)
    }

    // MARK: Functions

    static func simplifyFunction(_ f: MathFunction, _ args: [Expr]) -> Expr {
        let call = Expr.function(f, args)
        // Fold constant arguments when an exact value exists (sin(π/6) → 1/2, ln 1 → 0).
        if !args.isEmpty, !f.isRandom, args.allSatisfy({ $0.freeVariables.isEmpty }),
           let exact = try? ExactEvaluator.evaluate(call, angleUnit: .radians), exact.complexity <= 6 {
            return Simplifier.canonical(exact.expr)
        }
        switch f {
        case .ln:
            if case .constant(.e) = args[0] { return .number(.one) }
            if case .power(.constant(.e), let x) = args[0] { return x }
        case .abs:
            if case .function(.abs, _) = args[0] { return args[0] }
            if let n = numeric(args[0]) { return Num.approx(Swift.abs(n.double)).expr }
        default:
            break
        }
        // Fold decimal-only arguments numerically.
        if args.allSatisfy({ if case .decimal = $0 { true } else { false } }),
           let v = try? RealEvaluator.evaluate(call) {
            return .decimal(v)
        }
        return call
    }

    // MARK: Ordering

    static func sortKey(_ e: Expr) -> String {
        switch e {
        case .number(let r): return "0\(r)"
        case .decimal(let d): return "0\(d)"
        case .constant(let c): return "1\(c.rawValue)"
        case .variable(let v): return "2\(v)"
        case .power(let b, let x): return "3\(sortKey(b))^\(sortKey(x))"
        case .function(let f, let args): return "4\(f.rawValue)(\(args.map(sortKey).joined(separator: ",")))"
        case .sum(let t): return "5(" + t.map(sortKey).joined(separator: "+") + ")"
        case .product(let t): return "6(" + t.map(sortKey).joined(separator: "*") + ")"
        default: return "9\(e.nodeCount)"
        }
    }

    // MARK: Expansion

    /// Multiplies out products of sums and small integer powers of sums.
    public static func expand(_ expr: Expr) -> Expr {
        let e = simplify(expr).mapChildren(expand)
        switch e {
        case .product(let factors):
            return distribute(factors) ?? simplify(e)
        case .power(let b, let x):
            // (a + b)ⁿ is multiplied out directly: simplifying the product (a + b)·(a + b)·…
            // would fold it back into the power.
            if case .sum = b, let n = x.rationalValue, n.isInteger, n.numerator >= 2, n.numerator <= 12 {
                return distribute(Array(repeating: b, count: n.numerator)) ?? e
            }
            return e
        default:
            return simplify(e)
        }
    }

    /// Multiplies the factors out, collecting like terms after every step; nil when the
    /// expansion would grow beyond 512 terms.
    static func distribute(_ factors: [Expr]) -> Expr? {
        var acc: [Expr] = [.number(.one)]
        for f in factors {
            let summands: [Expr] = { if case .sum(let t) = f { return t } else { return [f] } }()
            guard acc.count * summands.count <= 512 else { return nil }
            var next: [Expr] = []
            for a in acc { for s in summands { next.append(simplifyProduct([a, s])) } }
            let collected = simplifySum(next)
            acc = { if case .sum(let t) = collected { return t } else { return [collected] } }()
        }
        return simplify(.sum(acc))
    }
}
