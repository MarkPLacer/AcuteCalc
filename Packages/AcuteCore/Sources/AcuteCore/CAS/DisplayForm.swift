import Foundation

/// Turns canonical CAS output back into the notation a student expects:
/// `x·(−1)` → `−x`, `x·y⁻¹` → `x/y`, `x^½` → `√x`, `(3/2)·x` → `3x/2`.
public enum DisplayForm {
    public static func prettify(_ expr: Expr) -> Expr {
        let e = expr.mapChildren(prettify)
        switch e {
        case .number(let r) where r.isNegative:
            return .negation(.number(r.magnitude))
        case .decimal(let d) where d < 0:
            return .negation(.decimal(-d))
        case .product(let factors):
            return prettifyProduct(factors)
        case .power(let base, let exponent):
            return prettifyPower(base, exponent)
        case .sum(let terms):
            // Flatten sums produced by prettifying children.
            var out: [Expr] = []
            for t in terms {
                if case .sum(let inner) = t { out.append(contentsOf: inner) } else { out.append(t) }
            }
            return .sum(out)
        default:
            return e
        }
    }

    /// Reads a (possibly negated) rational exponent.
    private static func exponentValue(_ e: Expr) -> Rational? {
        switch e {
        case .number(let r): r
        case .negation(.number(let r)): r.negated()
        case .quotient(.number(let a), .number(let b)): a.divided(by: b)
        case .negation(.quotient(.number(let a), .number(let b))): a.divided(by: b)?.negated()
        default: nil
        }
    }

    private static func prettifyPower(_ base: Expr, _ exponent: Expr) -> Expr {
        guard let r = exponentValue(exponent) else { return .power(base, exponent) }
        if r.isNegative {
            let positive = r.magnitude
            let denominator: Expr = positive == .one ? base : prettifyPower(base, .number(positive))
            return .quotient(.number(.one), denominator)
        }
        if r == .half { return .function(.sqrt, [base]) }
        if r.numerator == 1, r.denominator > 1 { return .function(.root, [.int(r.denominator), base]) }
        return .power(base, rationalExpr(r))
    }

    private static func rationalExpr(_ r: Rational) -> Expr {
        let n: Expr = .number(r.magnitude.denominator == 1 ? r.magnitude : Rational(r.magnitude.numerator))
        let v: Expr = r.denominator == 1 ? n : .quotient(n, .number(Rational(r.denominator)))
        return r.isNegative ? .negation(v) : v
    }

    private static func prettifyProduct(_ factors: [Expr]) -> Expr {
        var negative = false
        var numerator: [Expr] = []
        var denominator: [Expr] = []
        for f in factors {
            switch f {
            case .negation(let inner):
                negative.toggle()
                append(inner, &numerator, &denominator)
            default:
                append(f, &numerator, &denominator)
            }
        }
        // Merge numeric factors in the numerator into a leading coefficient.
        let top: Expr = numerator.isEmpty ? .number(.one) : (numerator.count == 1 ? numerator[0] : .product(numerator))
        var result: Expr = top
        if !denominator.isEmpty {
            let bottom: Expr = denominator.count == 1 ? denominator[0] : .product(denominator)
            result = .quotient(top, bottom)
        }
        return negative ? .negation(result) : result
    }

    private static func append(_ f: Expr, _ numerator: inout [Expr], _ denominator: inout [Expr]) {
        switch f {
        case .number(let r):
            if r.numerator != 1 { numerator.insert(.number(Rational(r.numerator)), at: 0) }
            if r.denominator != 1 { denominator.insert(.number(Rational(r.denominator)), at: 0) }
        case .quotient(let a, let b):
            if a != .number(.one) { numerator.append(a) }
            denominator.append(b)
        default:
            numerator.append(f)
        }
    }
}
