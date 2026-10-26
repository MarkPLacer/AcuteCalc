import Foundation

/// Ordinary differential equations of first-year courses, y′ = f(x, y) and y″ = f(x, y, y′):
/// numeric solutions of initial value problems (adaptive Dormand–Prince RK5(4)), slope fields,
/// and closed forms for linear first-order, separable, linear second-order equations with
/// constant coefficients and Euler (Cauchy–Euler) equations. A closed form is only returned
/// after substituting it into the equation at sample points.
public enum DifferentialEquation {
    /// The variable that stands for y′ in y″ = f(x, y, y′).
    public static let slopeName = "dy"

    // MARK: Evaluation

    /// f(x, y, y′) as a fast closure (bytecode; the tree walker when the program is too large).
    static func makeField(_ f: Expr, parameters: [String: Double]) -> (Double, Double, Double) -> Double {
        let compiler = BytecodeCompiler(slots: ["x": .x, "y": .y, slopeName: .t], angleUnit: .radians, constants: parameters)
        if let program = try? compiler.compile(f) {
            let vm = RealVM(program: program)
            return { x, y, dy in vm.evaluate(x: x, y: y, t: dy) }
        }
        return { x, y, dy in
            var context = EvaluationContext(variables: parameters)
            context.variables["x"] = x
            context.variables["y"] = y
            context.variables[slopeName] = dy
            return (try? RealEvaluator.evaluate(f, context: context)) ?? .nan
        }
    }

    // MARK: Numeric solution

    /// Points (x, y) of the solution through y(x₀) = y₀ (and y′(x₀) = y′₀ for order 2) on [a, b],
    /// integrated from x₀ in both directions; it stops where the solution leaves the domain of f
    /// or blows up.
    public static func solve(_ f: Expr, order: Int, x0: Double, initial: [Double], over range: ClosedRange<Double>,
                             parameters: [String: Double] = [:]) -> [SIMD2<Double>] {
        guard initial.count >= order, order == 1 || order == 2 else { return [] }
        let field = makeField(f, parameters: parameters)
        let derivative: (Double, [Double]) -> [Double] = order == 1
            ? { x, s in [field(x, s[0], 0)] }
            : { x, s in [s[1], field(x, s[0], s[1])] }
        let state = Array(initial.prefix(order))
        let maxStep = (range.upperBound - range.lowerBound) / 300
        var forward: [SIMD2<Double>] = []
        var backward: [SIMD2<Double>] = []
        if range.upperBound > x0 {
            forward = integrate(derivative, from: x0, to: range.upperBound, state: state, maxStep: maxStep)
        }
        if range.lowerBound < x0 {
            backward = integrate(derivative, from: x0, to: range.lowerBound, state: state, maxStep: maxStep)
        }
        return backward.reversed() + [SIMD2(x0, state[0])] + forward
    }

    /// Dormand–Prince RK5(4) with step-size control; returns (x, y) after every accepted step.
    static func integrate(_ g: (Double, [Double]) -> [Double], from x0: Double, to x1: Double, state: [Double], maxStep: Double) -> [SIMD2<Double>] {
        let direction: Double = x1 > x0 ? 1 : -1
        var x = x0
        var y = state
        var h = direction * Swift.min(maxStep, Swift.abs(x1 - x0) / 100)
        var points: [SIMD2<Double>] = []
        let c: [Double] = [0, 1.0 / 5, 3.0 / 10, 4.0 / 5, 8.0 / 9, 1, 1]
        let a: [[Double]] = [
            [],
            [1.0 / 5],
            [3.0 / 40, 9.0 / 40],
            [44.0 / 45, -56.0 / 15, 32.0 / 9],
            [19372.0 / 6561, -25360.0 / 2187, 64448.0 / 6561, -212.0 / 729],
            [9017.0 / 3168, -355.0 / 33, 46732.0 / 5247, 49.0 / 176, -5103.0 / 18656],
            [35.0 / 384, 0, 500.0 / 1113, 125.0 / 192, -2187.0 / 6784, 11.0 / 84],
        ]
        let b5: [Double] = [35.0 / 384, 0, 500.0 / 1113, 125.0 / 192, -2187.0 / 6784, 11.0 / 84, 0]
        let b4: [Double] = [5179.0 / 57600, 0, 7571.0 / 16695, 393.0 / 640, -92097.0 / 339200, 187.0 / 2100, 1.0 / 40]
        var steps = 0
        while (x1 - x) * direction > 1e-12 * Swift.max(1, Swift.abs(x1)), steps < 50_000 {
            steps += 1
            if (x + h - x1) * direction > 0 { h = x1 - x }
            var k: [[Double]] = []
            for stage in 0..<7 {
                var s = y
                for (j, aj) in a[stage].enumerated() {
                    for i in s.indices { s[i] += h * aj * k[j][i] }
                }
                k.append(g(x + c[stage] * h, s))
            }
            var high = y, low = y
            for i in y.indices {
                for stage in 0..<7 {
                    high[i] += h * b5[stage] * k[stage][i]
                    low[i] += h * b4[stage] * k[stage][i]
                }
            }
            guard high.allSatisfy(\.isFinite) else {
                // Leaving the domain or a pole: shrink the step, then stop.
                if Swift.abs(h) < 1e-9 * Swift.max(1, Swift.abs(x)) { break }
                h /= 4
                continue
            }
            var error = 0.0
            for i in y.indices {
                let scale = 1e-9 + 1e-9 * Swift.max(Swift.abs(y[i]), Swift.abs(high[i]))
                error = Swift.max(error, Swift.abs(high[i] - low[i]) / scale)
            }
            if error <= 1 {
                x += h
                y = high
                points.append(SIMD2(x, y[0]))
                if Swift.abs(y[0]) > 1e9 { break }
            }
            let factor = error == 0 ? 4 : Swift.min(4, Swift.max(0.2, 0.9 * Foundation.pow(error, -0.2)))
            h = direction * Swift.min(Swift.abs(h * factor), maxStep)
            if Swift.abs(h) < 1e-12 * Swift.max(1, Swift.abs(x)) { break }
        }
        return points
    }

    // MARK: Slope field

    /// Short segments of slope f(x, y) on a grid of the window, separated by NaN points. `aspect`
    /// is the screen size of one y unit over one x unit, so the segments look equally long.
    public static func slopeField(_ f: Expr, x: ClosedRange<Double>, y: ClosedRange<Double>, columns: Int, rows: Int,
                                  aspect: Double, parameters: [String: Double] = [:]) -> [SIMD2<Double>] {
        let field = makeField(f, parameters: parameters)
        let dx = (x.upperBound - x.lowerBound) / Double(columns)
        let dy = (y.upperBound - y.lowerBound) / Double(rows)
        let length = 0.35 * Swift.min(dx, dy * Swift.max(aspect, 1e-9))
        var points: [SIMD2<Double>] = []
        points.reserveCapacity(columns * rows * 3)
        for i in 0..<columns {
            for j in 0..<rows {
                let cx = x.lowerBound + (Double(i) + 0.5) * dx
                let cy = y.lowerBound + (Double(j) + 0.5) * dy
                let m = field(cx, cy, 0)
                guard m.isFinite else { continue }
                // Direction (1, m) in screen space, scaled back to graph units.
                let screen = SIMD2(1.0, m * aspect)
                let unit = screen / (screen * screen).sum().squareRoot()
                let half = SIMD2(unit.x * length, unit.y * length / Swift.max(aspect, 1e-9)) / 2
                points.append(SIMD2(cx, cy) - half)
                points.append(SIMD2(cx, cy) + half)
                points.append(SampledCurve.breakPoint)
            }
        }
        return points
    }

    // MARK: Closed forms

    public struct ClosedForm: Sendable, Hashable {
        /// The general solution y = … with C (or C₁, C₂), or an implicit relation H(y) = G(x) + C.
        public var general: Expr
        /// The solution through the initial values, when they fix the constants.
        public var particular: Expr?
        /// How it was found (linearna 1. reda, ločljive spremenljivke …).
        public var method: String
    }

    /// A closed form of y′ = f(x, y) (order 1) or y″ = f(x, y, y′) (order 2), or nil.
    public static func closedForm(_ f: Expr, order: Int, x0: Double? = nil, initial: [Double]? = nil) -> ClosedForm? {
        let f = Simplifier.simplify(f)
        if order == 1 {
            return firstOrderLinear(f, x0: x0, y0: initial?.first) ?? separable(f, x0: x0, y0: initial?.first)
        }
        guard order == 2 else { return nil }
        return constantCoefficients(f, x0: x0, initial: initial) ?? euler(f, x0: x0, initial: initial)
    }

    /// ∂f/∂v when it does not depend on any of `free`.
    static func coefficient(_ f: Expr, _ v: String, independentOf free: [String]) -> Expr? {
        guard let d = try? Differentiator.derivative(of: f, withRespectTo: v) else { return nil }
        return free.contains(where: { d.dependsOn($0) }) ? nil : d
    }

    // y′ = a(x)·y + b(x): y = e^A·(∫b·e^(−A) dx + C), A = ∫a dx
    static func firstOrderLinear(_ f: Expr, x0: Double?, y0: Double?) -> ClosedForm? {
        guard f.dependsOn("y"), let a = coefficient(f, "y", independentOf: ["y"]) else { return nil }
        let b = Simplifier.simplify(.sum([f, .negation(.product([a, .variable("y")]))]))
        guard !b.dependsOn("y"), let A = Antiderivative.integrate(a) else { return nil }
        let growth = Expr.power(.constant(.e), A)
        let constant = Expr.variable("C")
        let general: Expr
        var integral: Expr = .zero
        if Antiderivative.isZero(b) {
            general = Simplifier.simplify(.product([constant, growth]))
        } else {
            guard let I = Antiderivative.integrate(.product([b, .power(.constant(.e), .negation(A))])) else { return nil }
            integral = I
            general = Simplifier.simplify(.product([growth, .sum([I, constant])]))
        }
        guard verify(general, f, order: 1, constants: ["C": 1.7]) else { return nil }
        var particular: Expr?
        if let x0, let y0, let g0 = value(growth, at: x0), g0 != 0, let i0 = value(integral, at: x0) {
            let c = y0 / g0 - i0
            particular = Simplifier.simplify(general.substituting("C", with: number(c)))
        }
        return ClosedForm(general: general, particular: particular, method: "linearna enačba 1. reda")
    }

    // y′ = g(x)·h(y): ∫dy/h(y) = ∫g(x) dx + C
    static func separable(_ f: Expr, x0: Double?, y0: Double?) -> ClosedForm? {
        let factors: [Expr] = { if case .product(let list) = f { return list } else { return [f] } }()
        var g: [Expr] = [], h: [Expr] = []
        for factor in factors {
            if factor.dependsOn("x") && factor.dependsOn("y") { return nil }
            if factor.dependsOn("y") { h.append(factor) } else { g.append(factor) }
        }
        guard !h.isEmpty else { return nil }
        let gx = g.isEmpty ? Expr.one : Simplifier.simplify(.product(g))
        let hy = Simplifier.simplify(.product(h))
        guard let H = Antiderivative.integrate(.power(hy, .int(-1)), variable: "y"),
              let G = Antiderivative.integrate(gx, variable: "x") else { return nil }
        let constant = Expr.variable("C")
        var particular: Expr?
        var c0: Double?
        if let x0, let y0, let h0 = value(H, variable: "y", at: y0), let g0 = value(G, at: x0) { c0 = h0 - g0 }
        // Explicit y when H can be inverted: ln|y| = G + C → y = C·e^G, …
        if let explicit = invert(H, G) {
            if verify(explicit.general, f, order: 1, constants: ["C": 1.7]) {
                if let x0, let y0, let c = explicit.constant(x0, y0) {
                    particular = Simplifier.simplify(explicit.general.substituting("C", with: number(c)))
                }
                return ClosedForm(general: explicit.general, particular: particular, method: "ločljive spremenljivke")
            }
        }
        let general = Expr.relation(H, .equal, .sum([G, constant]))
        if let c0 { particular = .relation(H, .equal, Simplifier.simplify(.sum([G, number(c0)]))) }
        return ClosedForm(general: general, particular: particular, method: "ločljive spremenljivke (implicitno)")
    }

    /// y from H(y) = G(x) + C for the forms that appear in exercises, with the constant for (x₀, y₀).
    static func invert(_ H: Expr, _ G: Expr) -> (general: Expr, constant: (Double, Double) -> Double?)? {
        let C = Expr.variable("C")
        // k·ln|y − c| = G + C → y = c + C·e^(G/k)
        if case .product(let parts) = H, parts.count == 2, let k = parts[0].rationalValue,
           case .function(.ln, let args) = parts[1], case .function(.abs, let inner) = args[0], inner.count == 1,
           let shift = linearShift(inner[0]) {
            let exponent = Expr.quotient(G, .number(k))
            let general = Simplifier.simplify(.sum([.number(shift), .product([C, .power(.constant(.e), exponent)])]))
            return (general, { x0, y0 in value(.power(.constant(.e), exponent), at: x0).map { (y0 - shift.doubleValue) / $0 } })
        }
        if case .function(.ln, let args) = H, case .function(.abs, let inner) = args[0], inner.count == 1, let shift = linearShift(inner[0]) {
            let general = Simplifier.simplify(.sum([.number(shift), .product([C, .power(.constant(.e), G)])]))
            return (general, { x0, y0 in value(.power(.constant(.e), G), at: x0).map { (y0 - shift.doubleValue) / $0 } })
        }
        // arctan y = G + C → y = tan(G + C)
        if case .function(.atan, let args) = H, args == [.variable("y")] {
            let general = Expr.function(.tan, [.sum([G, C])])
            return (general, { x0, y0 in value(G, at: x0).map { Foundation.atan(y0) - $0 } })
        }
        // −1/y = G + C → y = −1/(G + C)
        if let p = Polynomial.extract(from: Simplifier.simplify(.power(H, .int(-1))), variable: "y"), p.degree == 1,
           p.coefficients[0] == 0, p.coefficients[1] != 0 {
            let k = p.coefficients[1]
            let general = Simplifier.simplify(.quotient(.one, .product([number(k), .sum([G, C])])))
            return (general, { x0, y0 in value(G, at: x0).map { 1 / (k * y0) - $0 } })
        }
        return nil
    }

    /// c when u = y − c.
    static func linearShift(_ u: Expr) -> Rational? {
        guard let p = Polynomial.extract(from: u, variable: "y"), p.degree == 1, p.exactCoefficients?[1] == .one,
              let c = p.exactCoefficients?[0] else { return nil }
        return c.negated()
    }

    // y″ = p·y′ + q·y + r(x) with constant p, q: λ² − pλ − q = 0, then variation of constants.
    static func constantCoefficients(_ f: Expr, x0: Double?, initial: [Double]?) -> ClosedForm? {
        let free = ["x", "y", slopeName]
        guard let p = coefficient(f, slopeName, independentOf: free), let q = coefficient(f, "y", independentOf: free),
              let pv = p.freeVariables.isEmpty ? (try? RealEvaluator.evaluate(p)) : nil,
              let qv = q.freeVariables.isEmpty ? (try? RealEvaluator.evaluate(q)) : nil else { return nil }
        let r = Simplifier.simplify(.sum([f, .negation(.product([p, .variable(slopeName)])), .negation(.product([q, .variable("y")]))]))
        guard !r.dependsOn("y"), !r.dependsOn(slopeName) else { return nil }
        let x = Expr.variable("x")
        let discriminant = pv * pv + 4 * qv
        let y1: Expr, y2: Expr
        let half = number(pv / 2)
        if Swift.abs(discriminant) < 1e-12 {
            y1 = .power(.constant(.e), .product([half, x]))
            y2 = .product([x, y1])
        } else if discriminant > 0 {
            let root = sqrtExpr(discriminant / 4)
            y1 = .power(.constant(.e), .product([.sum([half, root]), x]))
            y2 = .power(.constant(.e), .product([.sum([half, .negation(root)]), x]))
        } else {
            let beta = sqrtExpr(-discriminant / 4)
            let envelope: Expr = pv == 0 ? .one : .power(.constant(.e), .product([half, x]))
            y1 = Simplifier.simplify(.product([envelope, .function(.cos, [.product([beta, x])])]))
            y2 = Simplifier.simplify(.product([envelope, .function(.sin, [.product([beta, x])])]))
        }
        return linearSecondOrder(f, y1: Simplifier.simplify(y1), y2: Simplifier.simplify(y2), r: r, x0: x0, initial: initial,
                                 method: "linearna enačba 2. reda s konstantnimi koeficienti")
    }

    // x²y″ + bxy′ + cy = 0 (y″ = −(b/x)y′ − (c/x²)y): y = x^m with m² + (b − 1)m + c = 0.
    static func euler(_ f: Expr, x0: Double?, initial: [Double]?) -> ClosedForm? {
        let free = ["y", slopeName]
        guard let p = coefficient(f, slopeName, independentOf: free), let q = coefficient(f, "y", independentOf: free) else { return nil }
        let x = Expr.variable("x")
        let bx = Simplifier.simplify(.product([.number(.minusOne), p, x]))
        let cx = Simplifier.simplify(.product([.number(.minusOne), q, .power(x, .int(2))]))
        guard bx.freeVariables.isEmpty, cx.freeVariables.isEmpty, p.dependsOn("x") || q.dependsOn("x"),
              let b = try? RealEvaluator.evaluate(bx), let c = try? RealEvaluator.evaluate(cx) else { return nil }
        let r = Simplifier.simplify(.sum([f, .negation(.product([p, .variable(slopeName)])), .negation(.product([q, .variable("y")]))]))
        guard Antiderivative.isZero(r) else { return nil }
        let discriminant = (b - 1) * (b - 1) - 4 * c
        let center = (1 - b) / 2
        let y1: Expr, y2: Expr
        let ln = Expr.function(.ln, [x])
        if Swift.abs(discriminant) < 1e-12 {
            y1 = .power(x, number(center))
            y2 = .product([y1, ln])
        } else if discriminant > 0 {
            let root = sqrtExpr(discriminant / 4)
            y1 = .power(x, .sum([number(center), root]))
            y2 = .power(x, .sum([number(center), .negation(root)]))
        } else {
            let beta = sqrtExpr(-discriminant / 4)
            let envelope = Expr.power(x, number(center))
            y1 = .product([envelope, .function(.cos, [.product([beta, ln])])])
            y2 = .product([envelope, .function(.sin, [.product([beta, ln])])])
        }
        return linearSecondOrder(f, y1: Simplifier.simplify(y1), y2: Simplifier.simplify(y2), r: .zero, x0: x0, initial: initial,
                                 method: "Eulerjeva enačba")
    }

    /// y = C₁y₁ + C₂y₂ + y_p with y_p = −y₁∫y₂r/W dx + y₂∫y₁r/W dx (variation of constants).
    static func linearSecondOrder(_ f: Expr, y1: Expr, y2: Expr, r: Expr, x0: Double?, initial: [Double]?, method: String) -> ClosedForm? {
        guard let d1 = try? Differentiator.derivative(of: y1, withRespectTo: "x"),
              let d2 = try? Differentiator.derivative(of: y2, withRespectTo: "x") else { return nil }
        var particularSolution: Expr = .zero
        if !Antiderivative.isZero(r) {
            let wronskian = Simplifier.simplify(.sum([.product([y1, d2]), .negation(.product([d1, y2]))]))
            guard let u1 = Antiderivative.integrate(.quotient(.product([y2, r]), wronskian)),
                  let u2 = Antiderivative.integrate(.quotient(.product([y1, r]), wronskian)) else { return nil }
            particularSolution = Simplifier.simplify(.sum([.negation(.product([y1, u1])), .product([y2, u2])]))
        }
        let general = Simplifier.simplify(.sum([.product([.variable("C_1"), y1]), .product([.variable("C_2"), y2]), particularSolution]))
        guard verify(general, f, order: 2, constants: ["C_1": 1.3, "C_2": -0.7]) else { return nil }
        var particular: Expr?
        if let x0, let initial, initial.count >= 2,
           let a = value(y1, at: x0), let b = value(y2, at: x0), let c = value(d1, at: x0), let d = value(d2, at: x0),
           let yp = value(particularSolution, at: x0),
           let dp = (try? Differentiator.derivative(of: particularSolution, withRespectTo: "x")).flatMap({ value($0, at: x0) }) {
            // C₁y₁ + C₂y₂ = y₀ − y_p, C₁y₁′ + C₂y₂′ = y′₀ − y_p′
            let det = a * d - b * c
            if Swift.abs(det) > 1e-12 {
                let e = initial[0] - yp, g = initial[1] - dp
                let c1 = (e * d - b * g) / det, c2 = (a * g - e * c) / det
                particular = Simplifier.simplify(general.substituting("C_1", with: number(c1)).substituting("C_2", with: number(c2)))
            }
        }
        return ClosedForm(general: general, particular: particular, method: method)
    }

    // MARK: Helpers

    /// The residual y′ − f (or y″ − f) vanishes at sample points for the given constants.
    static func verify(_ solution: Expr, _ f: Expr, order: Int, constants: [String: Double]) -> Bool {
        guard let d1 = try? Differentiator.derivative(of: solution, withRespectTo: "x") else { return false }
        let d2 = order == 2 ? (try? Differentiator.derivative(of: d1, withRespectTo: "x")) : nil
        if order == 2 && d2 == nil { return false }
        var checked = 0
        for x in [0.37, 1.13, 2.21, -0.83, 0.61, 1.71, -1.37, 2.9] {
            var context = EvaluationContext(variables: constants)
            context.variables["x"] = x
            guard let y = try? RealEvaluator.evaluate(solution, context: context), let dy = try? RealEvaluator.evaluate(d1, context: context),
                  y.isFinite, dy.isFinite else { continue }
            context.variables["y"] = y
            context.variables[slopeName] = dy
            guard let rhs = try? RealEvaluator.evaluate(f, context: context), rhs.isFinite else { continue }
            let lhs: Double
            if let d2 {
                guard let value = try? RealEvaluator.evaluate(d2, context: context), value.isFinite else { continue }
                lhs = value
            } else {
                lhs = dy
            }
            guard Swift.abs(lhs - rhs) <= 1e-6 * Swift.max(1, Swift.abs(rhs)) else { return false }
            checked += 1
        }
        return checked >= 3
    }

    static func value(_ e: Expr, variable: String = "x", at x: Double) -> Double? {
        guard let v = try? RealEvaluator.evaluate(e, context: EvaluationContext(variables: [variable: x])), v.isFinite else { return nil }
        return v
    }

    static func number(_ value: Double) -> Expr {
        if let exact = ExactRecognizer.recognize(value, tolerance: 1e-10), exact.complexity <= 6 { return exact.expr }
        return .decimal(NumericCalculus.clean(value))
    }

    static func sqrtExpr(_ value: Double) -> Expr {
        if let r = Rational.approximating(value, maxDenominator: 10_000, tolerance: 1e-12) {
            if let root = r.root(2) { return .number(root) }
            return .power(.number(r), .number(.half))
        }
        return .decimal(value.squareRoot())
    }
}
