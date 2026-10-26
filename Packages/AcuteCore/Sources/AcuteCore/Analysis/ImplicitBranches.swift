import Foundation

/// y as one or two functions of x for equations linear or quadratic in y (lines, circles,
/// ellipses, hyperbolas, parabolas). The curve itself is drawn per pixel; the branches let the
/// graph find its intercepts, vertices and intersections with other curves.
public enum ImplicitBranches {
    /// `lhs = rhs` written as a·y² + b·y + c = 0 (a, b, c in x) and solved for y.
    public static func branches(_ lhs: Expr, _ rhs: Expr) -> [Expr]? {
        let difference = Expr.sum([lhs, .negation(rhs)])
        guard difference.dependsOn("y"),
              let first = try? Differentiator.derivative(of: difference, withRespectTo: "y"),
              let second = try? Differentiator.derivative(of: first, withRespectTo: "y") else { return nil }
        let twiceA = Simplifier.simplify(second)
        guard !twiceA.dependsOn("y") else { return nil }
        let b = Simplifier.simplify(first.substituting("y", with: .zero))
        let c = Simplifier.simplify(difference.substituting("y", with: .zero))
        if isZero(twiceA) {
            // b·y + c = 0
            guard !isZero(b) else { return nil }
            return [Simplifier.simplify(.negation(.quotient(c, b)))]
        }
        // y = (−b ± √(b² − 4ac)) / 2a with 2a = twiceA
        let root = Expr.function(.sqrt, [.sum([.power(b, .int(2)), .negation(.product([.int(2), twiceA, c]))])])
        return [Simplifier.simplify(.quotient(.sum([.negation(b), root]), twiceA)),
                Simplifier.simplify(.quotient(.sum([.negation(b), .negation(root)]), twiceA))]
    }

    private static func isZero(_ e: Expr) -> Bool {
        switch e {
        case .number(let r): r == .zero
        case .decimal(let d): d == 0
        default: false
        }
    }
}
