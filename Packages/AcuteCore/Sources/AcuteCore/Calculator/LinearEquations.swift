import Foundation

/// A system of linear equations typed in the calculator — 2x + y = 5, x − y = 1, or the node
/// and mesh equations of a circuit with complex impedances — solved exactly when every
/// coefficient is rational, otherwise in complex floating point.
public enum LinearEquations {
    public struct Solution: Sendable, Hashable {
        public var unknowns: [String]
        public var values: [Complex]
        /// Exact fractions when every coefficient is rational.
        public var exact: [Rational]?

        public var isReal: Bool { values.allSatisfy { $0.im == 0 } }
    }

    /// Nil when the relations are not a square system of linear equations (they are drawn instead).
    public static func solve(_ relations: [Expr], variables: [String: Double], angleUnit: AngleUnit) throws(MathError) -> Solution? {
        guard relations.count >= 2 else { return nil }
        var differences: [Expr] = []
        for relation in relations {
            guard case .relation(let lhs, .equal, let rhs) = relation else { return nil }
            if case .relation = lhs { return nil }
            differences.append(.sum([lhs, .negation(rhs)]))
        }
        let names = unknowns(relations, known: Set(variables.keys))
        guard names.count == relations.count else { return nil }
        let n = names.count
        let context = EvaluationContext(angleUnit: angleUnit, variables: variables)
        var a = [[Complex]](repeating: [Complex](repeating: .zero, count: n), count: n)
        var b = [Complex](repeating: .zero, count: n)
        var exactA: [Rational]? = []
        var exactB: [Rational]? = []
        func exact(_ e: Expr) -> Rational? {
            ExactEvaluator.value(e, angleUnit: angleUnit, variables: [:])?.rational
        }
        for (row, difference) in differences.enumerated() {
            var constantPart = difference
            for name in names { constantPart = constantPart.substituting(name, with: .zero) }
            for (column, name) in names.enumerated() {
                guard let derivative = try? Differentiator.derivative(of: difference, withRespectTo: name, angleUnit: angleUnit) else { return nil }
                let coefficient = Simplifier.simplify(derivative)
                // Linear: no coefficient may contain an unknown.
                guard !names.contains(where: { coefficient.dependsOn($0) }),
                      let value = CalculationEngine.complexValue(coefficient, context: context) else { return nil }
                a[row][column] = value
                if let r = exact(coefficient) { exactA?.append(r) } else { exactA = nil }
            }
            let constant = Simplifier.simplify(.negation(constantPart))
            guard let value = CalculationEngine.complexValue(constant, context: context) else { return nil }
            b[row] = value
            if let r = exact(constant) { exactB?.append(r) } else { exactB = nil }
        }
        if let exactA, let exactB {
            switch try LinearSystemSolver.solve(coefficients: Matrix(rows: n, columns: n, exact: exactA),
                                                constants: Matrix(rows: n, columns: 1, exact: exactB)) {
            case .unique(let m):
                return Solution(unknowns: names, values: (0..<n).map { Complex(m[$0, 0], 0) }, exact: m.exact)
            case .none:
                throw .domain("sistem nima rešitve")
            case .infinite:
                throw .domain("sistem ima neskončno rešitev")
            }
        }
        return Solution(unknowns: names, values: try eliminate(a, b), exact: nil)
    }

    /// Unknowns in order of appearance (x, y, z or I₁, I₂ …): free variables without a stored value.
    static func unknowns(_ relations: [Expr], known: Set<String>) -> [String] {
        let free = relations.reduce(Set<String>()) { $0.union($1.freeVariables) }.subtracting(known)
        var order: [String] = []
        func visit(_ e: Expr) {
            if case .variable(let name) = e, free.contains(name), !order.contains(name) { order.append(name) }
            for child in e.children { visit(child) }
        }
        relations.forEach(visit)
        return order
    }

    /// Gaussian elimination with partial pivoting in complex arithmetic.
    static func eliminate(_ matrix: [[Complex]], _ rhs: [Complex]) throws(MathError) -> [Complex] {
        var a = matrix, b = rhs
        let n = b.count
        let scale = Swift.max(1e-300, a.flatMap { $0 }.map(\.magnitude).max() ?? 1)
        for column in 0..<n {
            var pivot = column
            for row in column..<n where a[row][column].magnitude > a[pivot][column].magnitude { pivot = row }
            guard a[pivot][column].magnitude > 1e-12 * scale else { throw .domain("sistem nima enolične rešitve") }
            a.swapAt(column, pivot)
            b.swapAt(column, pivot)
            for row in (column + 1)..<n {
                let factor = a[row][column] / a[column][column]
                for k in column..<n { a[row][k] -= factor * a[column][k] }
                b[row] -= factor * b[column]
            }
        }
        var x = [Complex](repeating: .zero, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            var sum = b[row]
            for k in (row + 1)..<n { sum -= a[row][k] * x[k] }
            x[row] = sum / a[row][row]
        }
        return x.map { Complex(NumericCalculus.clean($0.re), NumericCalculus.clean($0.im)) }
    }
}
