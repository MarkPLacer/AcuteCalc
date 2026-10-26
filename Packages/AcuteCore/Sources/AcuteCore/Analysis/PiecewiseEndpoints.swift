import Foundation

/// The ends of the pieces of a piecewise function: a filled point where the bound belongs to
/// the piece (≤, ≥) and a hollow one where it does not (<, >), as drawn in exercises.
public enum PiecewiseEndpoints {
    public static func points(_ expr: Expr, variable: String = "x", context: EvaluationContext) -> [SpecialPoint] {
        guard case .piecewise(let parts) = expr else { return [] }
        var ends: [SpecialPoint] = []
        var index = 0
        while index + 1 < parts.count {
            let value = parts[index], condition = parts[index + 1]
            index += 2
            for (bound, included) in bounds(condition, variable: variable, context: context) {
                var at = context
                at.variables[variable] = bound
                guard let y = try? RealEvaluator.evaluate(value, context: at), y.isFinite else { continue }
                ends.append(SpecialPoint(kind: included ? .closedEnd : .openEnd, x: bound, y: NumericCalculus.clean(y)))
            }
        }
        // Where two pieces meet continuously the filled end covers the hollow one.
        return ends.filter { end in
            end.kind == .closedEnd || !ends.contains { other in
                other.kind == .closedEnd && Swift.abs(other.x - end.x) < 1e-9 && Swift.abs(other.y - end.y) < 1e-9 * max(1, Swift.abs(end.y))
            }
        }
    }

    /// Constant bounds of `variable` in conditions such as x < 1, 2 ≤ x or −1 ≤ x < 3.
    static func bounds(_ condition: Expr, variable: String, context: EvaluationContext) -> [(Double, Bool)] {
        guard case .relation(let lhs, let op, let rhs) = condition else { return [] }
        let included = op == .lessOrEqual || op == .greaterOrEqual
        if case .relation(_, _, let middle) = lhs {
            var result = bounds(lhs, variable: variable, context: context)
            if case .variable(variable) = middle, let b = constant(rhs, variable: variable, context: context) {
                result.append((b, included))
            }
            return result
        }
        if case .variable(variable) = lhs, let b = constant(rhs, variable: variable, context: context) { return [(b, included)] }
        if case .variable(variable) = rhs, let a = constant(lhs, variable: variable, context: context) { return [(a, included)] }
        return []
    }

    private static func constant(_ e: Expr, variable: String, context: EvaluationContext) -> Double? {
        guard !e.dependsOn(variable), let value = try? RealEvaluator.evaluate(e, context: context), value.isFinite else { return nil }
        return value
    }
}
