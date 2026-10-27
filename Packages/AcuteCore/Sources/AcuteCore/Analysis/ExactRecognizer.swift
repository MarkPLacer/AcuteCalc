import Foundation

/// Recognises numerically found values as nice closed forms (½, −3, π/6, √2/2, 2π/3).
/// Only accepts matches within a tight tolerance and small denominators, and the
/// caller may verify the candidate (e.g. `f(candidate) ≈ 0`).
public enum ExactRecognizer {
    public static func recognize(_ x: Double, tolerance: Double = 1e-10) -> ExactReal? {
        guard x.isFinite, abs(x) < 1e9 else { return nil }
        if abs(x) < tolerance { return .zero }
        func close(_ candidate: Double) -> Bool { abs(candidate - x) <= tolerance * max(1, abs(x)) }

        if let r = Rational.approximating(x, maxDenominator: 64, tolerance: tolerance), close(r.doubleValue) {
            return ExactReal(r)
        }
        // Multiples of π: p/q · π
        if let r = Rational.approximating(x / .pi, maxDenominator: 24, tolerance: tolerance),
           let value = ExactReal.pi.multiplied(by: ExactReal(r)), close(value.doubleValue) {
            return value
        }
        // (p/q)·√n
        for n in [2, 3, 5, 6, 7, 10, 11, 13, 14, 15, 17, 19, 21, 22, 23] {
            let root = Double(n).squareRoot()
            if let r = Rational.approximating(x / root, maxDenominator: 12, tolerance: tolerance),
               let value = ExactReal.squareRoot(of: Rational(n))?.multiplied(by: ExactReal(r)), close(value.doubleValue) {
                return value
            }
        }
        // (a + b√n)/c for small a, b, c (golden ratio, roots of quadratics)
        for n in [2, 3, 5, 6, 7] {
            let root = Double(n).squareRoot()
            for c in 1...6 {
                for b in [-2, -1, 1, 2] {
                    let a = Double(c) * x - Double(b) * root
                    let ai = a.rounded()
                    if abs(a - ai) < tolerance * Double(c) * 10, abs(ai) <= 30,
                       let rc = Rational(1, c),
                       let surd = ExactReal.squareRoot(of: Rational(n))?.multiplied(by: ExactReal(b)),
                       let value = ExactReal(Int(ai)).adding(surd)?.multiplied(by: ExactReal(rc)),
                       close(value.doubleValue) {
                        return value
                    }
                }
            }
        }
        return nil
    }

    /// Closed forms with e, ln and √π, which `ExactReal` cannot hold, for a value `recognize` did not match:
    /// e^(p/q) (e, 1/e, e², √e, ∛e), (a + b·E)/c for E = e, e², 1/e (e − 1, (e² − 1)/2, 1 − 2/e, e/2),
    /// (p/q)·ln a (ln 2, ln(2)/2, 2 ln 3), ln(m/n) (ln(3/2)) and (p/q)·√π (√π, √π/2). Every parameter is
    /// bounded (about 2 000 candidates in all), so within 10⁻⁹ a random decimal matches one of them with a
    /// probability below 10⁻⁶. The result is in display form (`DisplayForm`).
    public static func closedForm(_ x: Double, tolerance: Double = 1e-10) -> Expr? {
        guard x.isFinite, abs(x) < 1e9, abs(x) > tolerance else { return nil }
        func close(_ candidate: Double) -> Bool { abs(candidate - x) <= tolerance * max(1, abs(x)) }
        let e = Expr.constant(.e)
        // e^(p/q) with q ≤ 3 and |p| ≤ 6: e, e⁶, 1/e², √e, ∛e (lim (1 + 1/(3x))^x for x → ∞)
        for q in 1...3 {
            for p in -6...6 where p != 0 {
                guard let r = Rational(p, q), r.denominator == q, close(Foundation.exp(r.doubleValue)) else { continue }
                return r == .one ? e : DisplayForm.prettify(.power(e, .number(r)))
            }
        }
        // (a + b·E)/c with |a| ≤ 10, |b| ≤ 3, c ≤ 4: e − 1 (∫₀¹ eˣ dx), (e² − 1)/2, 1 − 2/e, e/2, 3e/4
        let bases: [(value: Double, expr: Expr)] = [(M_E, e), (Foundation.exp(2.0), .power(e, .int(2))), (1 / M_E, .quotient(.one, e))]
        for base in bases {
            for c in 1...4 {
                for b in [1, -1, 2, -2, 3, -3] {
                    let a = (Double(c) * x - Double(b) * base.value).rounded()
                    if abs(a) <= 10, close((a + Double(b) * base.value) / Double(c)) {
                        return linearForm(Int(a), b, base.expr, c)
                    }
                }
            }
        }
        // (p/q)·ln a with q ≤ 4 and |p| ≤ 12 (ln 4 is 2 ln 2): ln 2 (lim (2ˣ − 1)/x), ln(2)/2 (∫₀^(π/4) tan x dx)
        for a in [2, 3, 5, 6, 7, 10] {
            let ln = Foundation.log(Double(a))
            if let r = Rational.approximating(x / ln, maxDenominator: 4, tolerance: tolerance), abs(r.numerator) <= 12,
               close(r.doubleValue * ln) {
                return DisplayForm.prettify(.product([.number(r), .function(.ln, [.int(a)])]))
            }
        }
        // ln(m/n) for 2 ≤ m, n ≤ 10: ln(3/2) (∫₂³ dx/x), ln(2/3)
        for m in 2...10 {
            for n in 2...10 where m != n && Rational.gcd(m, n) == 1 {
                guard let ratio = Rational(m, n), close(Foundation.log(Double(m) / Double(n))) else { continue }
                return .function(.ln, [.number(ratio)])
            }
        }
        // (p/q)·√π with q ≤ 8 and |p| ≤ 16: √π (∫ e^(−x²) dx over ℝ), √π/2 (over [0, ∞))
        let rootPi = Double.pi.squareRoot()
        if let r = Rational.approximating(x / rootPi, maxDenominator: 8, tolerance: tolerance), abs(r.numerator) <= 16,
           close(r.doubleValue * rootPi) {
            return DisplayForm.prettify(.product([.number(r), .function(.sqrt, [.constant(.pi)])]))
        }
        return nil
    }

    /// (a + b·base)/c as it is written: e − 1, 1 − 2/e, (e² − 1)/2, 3e/4, 1/(2e).
    static func linearForm(_ a: Int, _ b: Int, _ base: Expr, _ c: Int) -> Expr {
        if a == 0 { return DisplayForm.prettify(.product([.frac(b, c), base])) }
        let term: Expr = abs(b) == 1 ? base : .product([.int(abs(b)), base])
        let numerator: Expr = b > 0 ? .sum([term, .int(a)]) : .sum([.int(a), .negation(term)])
        return DisplayForm.prettify(c == 1 ? numerator : .quotient(numerator, .int(c)))
    }
}
