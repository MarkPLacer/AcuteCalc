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
}
