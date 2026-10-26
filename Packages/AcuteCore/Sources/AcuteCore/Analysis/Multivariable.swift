import Foundation

/// Functions of several variables (Matematika II at FE and FGG): gradient, Hessian, stationary
/// points and their type, extrema under constraints (Lagrange multipliers), the tangent plane
/// and Taylor polynomial, Jacobian matrices, double and triple integrals over regions bounded
/// by functions, and levels for contour lines.
public enum Multivariable {
    public enum Kind: String, Sendable, Hashable {
        case minimum, maximum, saddle, undecided

        public var title: String {
            switch self {
            case .minimum: "lokalni minimum"
            case .maximum: "lokalni maksimum"
            case .saddle: "sedlo"
            case .undecided: "test ne odloči"
            }
        }
    }

    public struct CriticalPoint: Sendable, Hashable {
        public var coordinates: [Double]
        /// Exact coordinates where they are recognised (½, √2, π/4 …).
        public var exact: [ExactReal?]
        public var value: Double
        public var exactValue: ExactReal?
        public var kind: Kind
        /// Lagrange multipliers λ (constrained extrema only).
        public var multipliers: [Double]
        /// D = f_xx·f_yy − f_xy² (two variables without constraints).
        public var discriminant: Double?
    }

    // MARK: Derivatives

    public static func gradient(_ f: Expr, variables: [String]) throws(MathError) -> [Expr] {
        var out: [Expr] = []
        for v in variables { out.append(try Differentiator.derivative(of: f, withRespectTo: v)) }
        return out
    }

    public static func hessian(_ f: Expr, variables: [String]) throws(MathError) -> [[Expr]] {
        var rows: [[Expr]] = []
        for d in try gradient(f, variables: variables) { rows.append(try gradient(d, variables: variables)) }
        return rows
    }

    /// ∂(f₁, …, fₘ)/∂(x₁, …, xₙ)
    public static func jacobian(_ functions: [Expr], variables: [String]) throws(MathError) -> [[Expr]] {
        var rows: [[Expr]] = []
        for f in functions { rows.append(try gradient(f, variables: variables)) }
        return rows
    }

    /// Determinant of a 1×1 … 3×3 matrix of expressions, simplified.
    public static func determinant(_ m: [[Expr]]) -> Expr? {
        guard !m.isEmpty, m.count <= 3, m.allSatisfy({ $0.count == m.count }) else { return nil }
        switch m.count {
        case 1: return m[0][0]
        case 2: return Simplifier.simplify(.sum([.product([m[0][0], m[1][1]]), .negation(.product([m[0][1], m[1][0]]))]))
        case 3:
            func minor(_ i: Int, _ j: Int) -> Expr {
                let r = [0, 1, 2].filter { $0 != i }, c = [0, 1, 2].filter { $0 != j }
                return .sum([.product([m[r[0]][c[0]], m[r[1]][c[1]]]), .negation(.product([m[r[0]][c[1]], m[r[1]][c[0]]]))])
            }
            return Simplifier.simplify(.sum([.product([m[0][0], minor(0, 0)]), .negation(.product([m[0][1], minor(0, 1)])),
                                             .product([m[0][2], minor(0, 2)])]))
        default:
            return nil
        }
    }

    /// The Taylor polynomial of order 1 (tangent plane) or 2 around a point.
    public static func taylor(_ f: Expr, variables: [String], at point: [Double], order: Int,
                              parameters: [String: Double] = [:]) throws(MathError) -> Expr {
        guard point.count == variables.count, order == 1 || order == 2 else {
            throw .domain("Taylorjev polinom reda 1 ali 2 v točki z eno koordinato za vsako spremenljivko")
        }
        var context = EvaluationContext(variables: parameters)
        for (v, a) in zip(variables, point) { context.variables[v] = a }
        func value(_ e: Expr) throws(MathError) -> Expr { number(try RealEvaluator.evaluate(e, context: context)) }
        let shifts: [Expr] = zip(variables, point).map { v, a in a == 0 ? .variable(v) : .sum([.variable(v), number(-a)]) }
        var terms: [Expr] = [try value(f)]
        let g = try gradient(f, variables: variables)
        for (d, s) in zip(g, shifts) { terms.append(.product([try value(d), s])) }
        if order >= 2 {
            let h = try hessian(f, variables: variables)
            for i in variables.indices {
                for j in i..<variables.count {
                    // ½·Σᵢⱼ f_ij·dᵢ·dⱼ = Σᵢ ½f_ii·dᵢ² + Σᵢ<ⱼ f_ij·dᵢ·dⱼ
                    let hij = try value(h[i][j])
                    let coefficient = i == j ? Expr.product([.number(.half), hij]) : hij
                    terms.append(.product([coefficient, shifts[i], shifts[j]]))
                }
            }
        }
        return Simplifier.simplify(.sum(terms))
    }

    // MARK: Fast evaluation

    /// f(u₀, u₁, u₂) for up to three variables (bytecode slots x, y, t).
    static func compile(_ e: Expr, variables: [String], parameters: [String: Double]) -> ([Double]) -> Double {
        let slots: [VariableSlot] = [.x, .y, .t]
        var map: [String: VariableSlot] = [:]
        for (i, v) in variables.prefix(3).enumerated() { map[v] = slots[i] }
        if let program = try? BytecodeCompiler(slots: map, constants: parameters).compile(e) {
            let vm = RealVM(program: program)
            return { u in vm.evaluate(x: u.count > 0 ? u[0] : 0, y: u.count > 1 ? u[1] : 0, t: u.count > 2 ? u[2] : 0) }
        }
        return { u in
            var context = EvaluationContext(variables: parameters)
            for (v, value) in zip(variables, u) { context.variables[v] = value }
            return (try? RealEvaluator.evaluate(e, context: context)) ?? .nan
        }
    }

    // MARK: Stationary points

    /// Points with ∇f = 0 in the box, found by Newton's method from a grid of starting points,
    /// with their type from the signs of the Hessian's eigenvalues.
    public static func stationaryPoints(_ f: Expr, variables: [String], box: [ClosedRange<Double>],
                                        parameters: [String: Double] = [:]) -> [CriticalPoint] {
        let n = variables.count
        guard n >= 1, n <= 3, box.count == n, let g = try? gradient(f, variables: variables),
              let h = try? hessian(f, variables: variables) else { return [] }
        let grad = g.map { compile($0, variables: variables, parameters: parameters) }
        let hess = h.map { row in row.map { compile($0, variables: variables, parameters: parameters) } }
        let value = compile(f, variables: variables, parameters: parameters)
        var found: [[Double]] = []
        for start in grid(box, perAxis: n == 3 ? 6 : 9) {
            guard let u = newton({ p in grad.map { $0(p) } }, { p in hess.map { row in row.map { $0(p) } } }, start: start),
                  inside(u, box) else { continue }
            if !found.contains(where: { close($0, u, box) }) { found.append(u) }
        }
        return found.map { u in
            let exact = recognize(u) { candidate in grad.allSatisfy { Swift.abs($0(candidate)) < 1e-10 } }
            let matrix = hess.map { row in row.map { $0(u) } }
            let kind = classify(matrix)
            let discriminant = n == 2 ? NumericCalculus.clean(matrix[0][0] * matrix[1][1] - matrix[0][1] * matrix[1][0]) : nil
            return point(f, variables: variables, u: u, exact: exact, value: value, kind: kind, multipliers: [], discriminant: discriminant)
        }
    }

    // MARK: Constrained extrema

    /// Extrema of f under gᵢ = 0 (Lagrange: ∇f = Σλᵢ∇gᵢ). The type comes from d²L on the tangent
    /// space dg = 0, which agrees with the bordered Hessian test but does not depend on the order
    /// of the variables.
    public static func constrainedExtrema(_ f: Expr, constraints: [Expr], variables: [String], box: [ClosedRange<Double>],
                                          parameters: [String: Double] = [:]) -> [CriticalPoint] {
        let n = variables.count, m = constraints.count
        guard n >= 2, n <= 3, m >= 1, m < n, box.count == n else { return [] }
        let multipliers = (1...m).map { "λ_\($0)" }
        let unknowns = variables + multipliers
        // Lagrangian L = f − Σλᵢgᵢ; residuals ∂L/∂xⱼ and gᵢ.
        let lagrangian = Expr.sum([f] + zip(multipliers, constraints).map { name, g -> Expr in .negation(.product([.variable(name), g])) })
        guard let dL = try? gradient(lagrangian, variables: variables) else { return [] }
        let residualExprs = dL + constraints
        guard let jacobianExprs = try? jacobian(residualExprs, variables: unknowns) else { return [] }
        func evaluate(_ e: Expr, _ u: [Double]) -> Double {
            var context = EvaluationContext(variables: parameters)
            for (name, value) in zip(unknowns, u) { context.variables[name] = value }
            return (try? RealEvaluator.evaluate(e, context: context)) ?? .nan
        }
        let constraintGradients = constraints.compactMap { try? gradient($0, variables: variables) }
        guard constraintGradients.count == m, let fGradient = try? gradient(f, variables: variables) else { return [] }
        var found: [[Double]] = []
        for start in grid(box, perAxis: n == 3 ? 5 : 9) {
            // Onto the constraints, then λ by least squares, then Newton on the whole system.
            guard var x = project(start, constraints: constraints, gradients: constraintGradients, evaluate: evaluate) else { continue }
            let b = constraintGradients.map { row in row.map { evaluate($0, x) } }
            let gf = fGradient.map { evaluate($0, x) }
            let normal = (0..<m).map { i in (0..<m).map { j in zip(b[i], b[j]).map(*).reduce(0, +) } }
            let rhs = (0..<m).map { i in zip(b[i], gf).map(*).reduce(0, +) }
            guard let lambda = solveLinear(normal, rhs) else { continue }
            x += lambda
            guard let u = newton({ p in residualExprs.map { evaluate($0, p) } },
                                 { p in jacobianExprs.map { row in row.map { evaluate($0, p) } } }, start: x),
                  inside(Array(u.prefix(n)), box) else { continue }
            if !found.contains(where: { close(Array($0.prefix(n)), Array(u.prefix(n)), box) }) { found.append(u) }
        }
        let value = compile(f, variables: variables, parameters: parameters)
        let hessianOfL = (try? hessian(lagrangian, variables: variables)) ?? []
        return found.map { u in
            let x = Array(u.prefix(n)), lambda = Array(u.suffix(m))
            let exact = recognize(x) { candidate in
                constraints.allSatisfy { Swift.abs(evaluate($0, candidate + lambda)) < 1e-10 }
                    && dL.allSatisfy { Swift.abs(evaluate($0, candidate + lambda)) < 1e-8 }
            }
            let normals = constraintGradients.map { row in row.map { evaluate($0, u) } }
            let h = hessianOfL.map { row in row.map { evaluate($0, u) } }
            let kind: Kind
            if h.count == n, let z = tangentBasis(normals, dimension: n) {
                // d²L(dx) for dx = Σ cₖzₖ in the tangent space: the matrix zₐᵀ·H_L·z_b.
                let hz = z.map { b in h.map { row in zip(row, b).reduce(0) { $0 + $1.0 * $1.1 } } }
                let reduced = z.map { a in hz.map { column in zip(a, column).reduce(0) { $0 + $1.0 * $1.1 } } }
                kind = classify(reduced, scale: h.flatMap { $0 }.map(Swift.abs).max())
            } else {
                // Linearly dependent constraint gradients: the Lagrange conditions do not decide.
                kind = .undecided
            }
            return point(f, variables: variables, u: x, exact: exact, value: value, kind: kind, multipliers: lambda, discriminant: nil)
        }
    }

    /// The type from the signs of a symmetric matrix's eigenvalues; values within 10⁻⁸·scale count as 0.
    static func classify(_ matrix: [[Double]], scale: Double? = nil) -> Kind {
        let eigenvalues = EigenDecomposition.jacobi(matrix.flatMap { $0 }, n: matrix.count)
        let tolerance = 1e-8 * Swift.max(1e-300, scale ?? matrix.flatMap { $0 }.map(Swift.abs).max() ?? 0)
        if eigenvalues.allSatisfy({ $0 > tolerance }) { return .minimum }
        if eigenvalues.allSatisfy({ $0 < -tolerance }) { return .maximum }
        if eigenvalues.contains(where: { $0 > tolerance }) && eigenvalues.contains(where: { $0 < -tolerance }) { return .saddle }
        return .undecided
    }

    /// An orthonormal basis of the vectors orthogonal to every row (the tangent space of the
    /// constraints, Gram–Schmidt); nil when the rows are linearly dependent.
    static func tangentBasis(_ rows: [[Double]], dimension n: Int) -> [[Double]]? {
        var basis: [[Double]] = []
        func length(_ v: [Double]) -> Double { v.reduce(0) { $0 + $1 * $1 }.squareRoot() }
        func orthogonalized(_ v: [Double]) -> [Double] {
            basis.reduce(v) { w, q in
                let d = zip(w, q).reduce(0) { $0 + $1.0 * $1.1 }
                return zip(w, q).map { $0 - d * $1 }
            }
        }
        for row in rows {
            let w = orthogonalized(row)
            guard w.count == n, length(w) > 1e-9 * length(row) else { return nil }
            basis.append(w.map { $0 / length(w) })
        }
        let normals = basis.count
        while basis.count < n {
            let candidates = (0..<n).map { j in orthogonalized((0..<n).map { $0 == j ? 1.0 : 0 }) }
            guard let best = candidates.max(by: { length($0) < length($1) }), length(best) > 1e-9 else { return nil }
            basis.append(best.map { $0 / length(best) })
        }
        return Array(basis.dropFirst(normals))
    }

    /// Gauss–Newton steps onto g = 0: x ← x − Bᵀ(BBᵀ)⁻¹g.
    static func project(_ start: [Double], constraints: [Expr], gradients: [[Expr]], evaluate: (Expr, [Double]) -> Double) -> [Double]? {
        var x = start
        for _ in 0..<30 {
            let g = constraints.map { evaluate($0, x) }
            guard g.allSatisfy(\.isFinite) else { return nil }
            if g.map(Swift.abs).max() ?? 0 < 1e-12 { return x }
            let b = gradients.map { row in row.map { evaluate($0, x) } }
            let normal = b.indices.map { i in b.indices.map { j in zip(b[i], b[j]).map(*).reduce(0, +) } }
            guard let y = solveLinear(normal, g) else { return nil }
            for j in x.indices { x[j] -= b.indices.reduce(0) { $0 + b[$1][j] * y[$1] } }
        }
        let g = constraints.map { evaluate($0, x) }
        return g.map(Swift.abs).max() ?? 1 < 1e-8 ? x : nil
    }

    // MARK: Integrals

    /// ∫…∫ f over aᵢ(outer variables) ≤ uᵢ ≤ bᵢ(outer variables), outermost variable first
    /// (iterated adaptive Gauss–Kronrod). Up to three variables.
    public static func iteratedIntegral(_ f: Expr, variables: [String], lower: [Expr], upper: [Expr],
                                        parameters: [String: Double] = [:]) throws(MathError) -> Double {
        let n = variables.count
        guard n >= 1, n <= 3, lower.count == n, upper.count == n else { throw .domain("največ tri spremenljivke z mejami") }
        for (k, bounds) in zip(lower, upper).enumerated() {
            let later = Set(variables[k...])
            guard bounds.0.freeVariables.isDisjoint(with: later), bounds.1.freeVariables.isDisjoint(with: later) else {
                throw .domain("meje za \(variables[k]) smejo vsebovati le zunanje spremenljivke")
            }
        }
        let integrand = compile(f, variables: variables, parameters: parameters)
        let lows = lower.map { compile($0, variables: variables, parameters: parameters) }
        let highs = upper.map { compile($0, variables: variables, parameters: parameters) }
        func level(_ k: Int, _ outer: [Double]) -> Double {
            let a = lows[k](outer + [Double](repeating: 0, count: n - k))
            let b = highs[k](outer + [Double](repeating: 0, count: n - k))
            guard a.isFinite, b.isFinite else { return .nan }
            let tolerance = k == n - 1 ? 1e-11 : 1e-10
            if k == n - 1 {
                return (try? Integrator.integrate({ v in integrand(outer + [v]) }, from: a, to: b, tolerance: tolerance)) ?? .nan
            }
            return (try? Integrator.integrate({ v in level(k + 1, outer + [v]) }, from: a, to: b, tolerance: tolerance)) ?? .nan
        }
        let result = level(0, [])
        guard result.isFinite else { throw .domain("integral ne konvergira ali funkcija ni definirana na območju") }
        return NumericCalculus.clean(result)
    }

    // MARK: Contour lines

    /// About `count` round levels between the 5th and 95th percentile of f on the window.
    public static func contourLevels(_ f: Expr, x: ClosedRange<Double>, y: ClosedRange<Double>, count: Int = 9,
                                     parameters: [String: Double] = [:]) -> [Double] {
        let value = compile(f, variables: ["x", "y"], parameters: parameters)
        var samples: [Double] = []
        for i in 0...40 {
            for j in 0...40 {
                let v = value([x.lowerBound + (x.upperBound - x.lowerBound) * Double(i) / 40,
                               y.lowerBound + (y.upperBound - y.lowerBound) * Double(j) / 40])
                if v.isFinite { samples.append(v) }
            }
        }
        guard samples.count > 10 else { return [] }
        samples.sort()
        let lo = samples[samples.count / 20], hi = samples[samples.count * 19 / 20]
        guard hi > lo else { return [lo] }
        let raw = (hi - lo) / Double(Swift.max(1, count))
        let base = Foundation.pow(10, Foundation.floor(Foundation.log10(raw)))
        let step = [1.0, 2, 2.5, 5, 10].map { $0 * base }.first { $0 >= raw } ?? 10 * base
        var levels: [Double] = []
        var level = Foundation.ceil(lo / step) * step
        while level <= hi && levels.count < 40 {
            levels.append(NumericCalculus.clean(level))
            level += step
        }
        return levels
    }

    // MARK: Helpers

    static func point(_ f: Expr, variables: [String], u: [Double], exact: [ExactReal?], value: ([Double]) -> Double,
                      kind: Kind, multipliers: [Double], discriminant: Double?) -> CriticalPoint {
        let coordinates = zip(u, exact).map { v, e in e?.doubleValue ?? NumericCalculus.clean(v) }
        var exactValue: ExactReal?
        if exact.allSatisfy({ $0 != nil }) {
            var assignment: [String: ExactReal] = [:]
            for (v, e) in zip(variables, exact) { assignment[v] = e }
            exactValue = ExactEvaluator.value(f, angleUnit: .radians, variables: assignment)
        }
        return CriticalPoint(coordinates: coordinates, exact: exact, value: NumericCalculus.clean(value(coordinates)),
                             exactValue: exactValue, kind: kind, multipliers: multipliers.map(NumericCalculus.clean),
                             discriminant: discriminant)
    }

    /// Exact coordinates when every candidate together still satisfies `check`.
    static func recognize(_ u: [Double], check: ([Double]) -> Bool) -> [ExactReal?] {
        let candidates = u.map { ExactRecognizer.recognize($0, tolerance: 1e-9) }
        guard candidates.allSatisfy({ $0 != nil }) else { return u.map { _ in nil } }
        let values = candidates.map { $0!.doubleValue }
        return check(values) ? candidates : u.map { _ in nil }
    }

    static func grid(_ box: [ClosedRange<Double>], perAxis: Int) -> [[Double]] {
        var points: [[Double]] = [[]]
        for range in box {
            let values = (0..<perAxis).map { i in range.lowerBound + (range.upperBound - range.lowerBound) * (Double(i) + 0.5) / Double(perAxis) }
            points = points.flatMap { p in values.map { p + [$0] } }
        }
        return points
    }

    static func inside(_ u: [Double], _ box: [ClosedRange<Double>]) -> Bool {
        zip(u, box).allSatisfy { v, range in
            let margin = 1e-9 * Swift.max(1, range.upperBound - range.lowerBound)
            return v >= range.lowerBound - margin && v <= range.upperBound + margin
        }
    }

    static func close(_ a: [Double], _ b: [Double], _ box: [ClosedRange<Double>]) -> Bool {
        let size = box.map { $0.upperBound - $0.lowerBound }.max() ?? 1
        return zip(a, b).allSatisfy { Swift.abs($0 - $1) <= 1e-6 * Swift.max(1, size) }
    }

    /// Newton's method for R(u) = 0 with Jacobian J; steps are limited so it does not jump far.
    static func newton(_ residual: ([Double]) -> [Double], _ jacobian: ([Double]) -> [[Double]], start: [Double],
                       iterations: Int = 60) -> [Double]? {
        var u = start
        for _ in 0..<iterations {
            let r = residual(u)
            guard r.allSatisfy(\.isFinite) else { return nil }
            if r.map(Swift.abs).max() ?? 0 < 1e-13 { break }
            guard let step = solveLinear(jacobian(u), r.map { -$0 }) else { return nil }
            let size = Swift.max(1, u.map(Swift.abs).max() ?? 1)
            let length = step.map(Swift.abs).max() ?? 0
            let scale = length > 10 * size ? 10 * size / length : 1
            u = zip(u, step).map { $0 + scale * $1 }
            if length < 1e-15 * size { break }
        }
        let r = residual(u)
        guard r.allSatisfy(\.isFinite), r.map(Swift.abs).max() ?? 1 < 1e-9 else { return nil }
        return u
    }

    /// A·x = b by Gaussian elimination with partial pivoting; nil when A is (nearly) singular.
    static func solveLinear(_ a: [[Double]], _ b: [Double]) -> [Double]? {
        let n = b.count
        guard a.count == n, a.allSatisfy({ $0.count == n }) else { return nil }
        var m = a, y = b
        let scale = Swift.max(1e-300, a.flatMap { $0 }.map(Swift.abs).max() ?? 0)
        for col in 0..<n {
            guard let pivot = (col..<n).max(by: { Swift.abs(m[$0][col]) < Swift.abs(m[$1][col]) }),
                  Swift.abs(m[pivot][col]) > 1e-13 * scale else { return nil }
            m.swapAt(col, pivot)
            y.swapAt(col, pivot)
            for r in (col + 1)..<Swift.max(col + 1, n) {
                let factor = m[r][col] / m[col][col]
                if factor == 0 { continue }
                for c in col..<n { m[r][c] -= factor * m[col][c] }
                y[r] -= factor * y[col]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for r in stride(from: n - 1, through: 0, by: -1) {
            let s = ((r + 1)..<Swift.max(r + 1, n)).reduce(y[r]) { $0 - m[r][$1] * x[$1] }
            x[r] = s / m[r][r]
        }
        return x.allSatisfy(\.isFinite) ? x : nil
    }

    static func number(_ value: Double) -> Expr {
        if let exact = ExactRecognizer.recognize(value, tolerance: 1e-10), exact.complexity <= 6 { return exact.expr }
        return .decimal(NumericCalculus.clean(value))
    }
}
