import Foundation

/// What a calculator input describes once parsed.
public enum GraphKind: Sendable, Hashable {
    /// y = f(x)
    case explicit(Expr)
    /// x = f(y)
    case explicitInY(Expr)
    /// F(x, y) relation G(x, y), drawn per pixel on the GPU (circles, conics, inequalities)
    case implicit(lhs: Expr, relation: RelationOperator, rhs: Expr)
    /// z = f(x, y)
    case surface(Expr)
    /// A sequence a(n) drawn as points for n = 1, 2, 3 …
    case sequence(Expr)
    /// A point in the plane.
    case point(x: Expr, y: Expr)
    /// A segment: an arrow (a vector or complex number from the origin) or a dashed helper line.
    case segment(x0: Expr, y0: Expr, x1: Expr, y1: Expr, arrow: Bool)
    /// Straight sides through points given as x₁, y₁, x₂, y₂, … (a polygon when closed).
    case polyline([Expr], closed: Bool)
    /// A parametric curve (x(t), y(t)) for t from `from` to `to`; polar curves r(θ) become one.
    case parametric(x: Expr, y: Expr, from: Double, to: Double)
    /// The slope field of y′ = f(x, y).
    case slopeField(Expr)
    /// The solution of y′ = f(x, y) (order 1) or y″ = f(x, y, y′) (order 2) through the initial values.
    case odeSolution(Expr, order: Int, x0: Double, initial: [Double])

    /// Points, segments and polygons (vectors, complex numbers, figures) rather than curves.
    public var isFigure: Bool {
        switch self {
        case .point, .segment, .polyline: true
        default: false
        }
    }
}

public struct NumericResult: Sendable, Hashable {
    public var value: Double
    public var exact: ExactReal?
    /// Exact closed form that isn't an `ExactReal` (e.g. log₇ 2).
    public var closedForm: Expr?

    public init(value: Double, exact: ExactReal? = nil, closedForm: Expr? = nil) {
        self.value = value
        self.exact = exact
        self.closedForm = closedForm
    }

    /// Exact form worth showing next to the decimal value.
    public var displayExact: Expr? {
        if let exact, exact.complexity <= 12, !(exact.isRational && exact.rational!.isInteger) { return exact.expr }
        return closedForm
    }
}

/// Extra structure for results the Sharp EL-W531 shows specially.
public enum SpecialResult: Sendable, Hashable {
    /// a int÷ b → quotient and remainder
    case quotientRemainder(quotient: Int, remainder: Int)
    /// →rθ
    case polar(r: Double, theta: Double)
    /// →xy
    case rectangular(x: Double, y: Double)
    /// Polygon A(…), B(…), C(…) …: area S and perimeter o.
    case polygon(area: Double, perimeter: Double)
    /// Segment A(…), B(…): its length d.
    case segmentLength(Double)
    /// Data points (x₁, y₁), (x₂, y₂) …: the area under the broken line through them.
    case areaUnderPolyline(Double)
    /// A parametric or polar curve: its length L and, when it closes, the area S it encloses.
    case curve(length: Double, area: Double?)
}

/// Graph overlays implied by the input (integral area, derivative curve, equation sides).
public struct GraphRequest: Sendable, Hashable {
    public var kinds: [GraphKind]
    /// Shade ∫ₐᵇ f between the curve and the x-axis.
    public var shadedIntegral: ShadedIntegral?
    /// Free parameters that need sliders (a, k, r, p …).
    public var parameters: [String]
    /// Points to highlight (intersections of equation sides, solutions).
    public var highlightIntersections: Bool

    public init(kinds: [GraphKind], shadedIntegral: ShadedIntegral? = nil, parameters: [String] = [], highlightIntersections: Bool = false) {
        self.kinds = kinds
        self.shadedIntegral = shadedIntegral
        self.parameters = parameters
        self.highlightIntersections = highlightIntersections
    }
}

/// The band to shade, ordered (lower ≤ upper) whatever the direction of the integral.
public struct ShadedIntegral: Sendable, Hashable {
    public var integrand: Expr
    public var lower: Double
    public var upper: Double
}

public enum CalculationOutcome: Sendable {
    case empty
    case incomplete
    case error(MathError)
    case number(NumericResult)
    case complex(Complex)
    /// Symbolic CAS output (e.g. a derivative or Taylor polynomial)
    case symbolic(Expr)
    case solutions(EquationResult)
    case special(SpecialResult, NumericResult)
    /// A matrix or vector result.
    case matrix(Matrix)
    /// Limits that diverge to ±∞
    case infinite(positive: Bool)
    /// The solution set of an inequality: x ∈ (−∞, −2) ∪ (2, ∞).
    case inequality(InequalitySolution)
    /// The solution of a linear system: x = 2, y = 1 (real or complex, e.g. node voltages).
    case linearSystem(LinearEquations.Solution)
    /// Eigenvalues and eigenvectors of a matrix: eig(A).
    case eigen(EigenDecomposition)
}

/// Everything the calculator shows for one input: a value and/or a graph.
public struct Calculation: Sendable {
    public var expr: Expr?
    public var outcome: CalculationOutcome
    public var graph: GraphRequest?

    public init(expr: Expr?, outcome: CalculationOutcome, graph: GraphRequest?) {
        self.expr = expr
        self.outcome = outcome
        self.graph = graph
    }
}

public struct CalculationSettings: Sendable, Hashable {
    public var angleUnit: AngleUnit
    public var complexResults: Bool
    public var randomSeed: UInt64
    /// Electrical engineering: j is the imaginary unit.
    public var imaginaryUnitJ = false

    public init(angleUnit: AngleUnit = .radians, complexResults: Bool = true, randomSeed: UInt64 = 1, imaginaryUnitJ: Bool = false) {
        self.imaginaryUnitJ = imaginaryUnitJ
        self.angleUnit = angleUnit
        self.complexResults = complexResults
        self.randomSeed = randomSeed
    }
}

/// Classifies and evaluates calculator input.
public enum CalculationEngine {
    static let graphVariables: Set<String> = ["x", "y", "z"]

    public static func calculate(_ row: MathRow, variables: [String: Double], exactVariables: [String: ExactReal],
                                 matrixVariables: [String: Matrix] = [:], functions: [String: Expr] = [:],
                                 settings: CalculationSettings) -> Calculation {
        guard !row.isEmpty else { return Calculation(expr: nil, outcome: .empty, graph: nil) }
        let options = ParserOptions(knownVariables: Set(variables.keys).union(matrixVariables.keys), functions: functions,
                                    imaginaryUnitJ: settings.imaginaryUnitJ)
        // x ≥ 0, y ≥ 0, x + y ≤ 4 or y = 2x + 1, y = 4 − x: draw the system.
        if let system = MathRowConverter.system(from: row, options: options) {
            // A square linear system is solved (exactly or with complex coefficients).
            do {
                if let solution = try LinearEquations.solve(system, variables: variables, angleUnit: settings.angleUnit) {
                    var graph: GraphRequest?
                    if !solution.isReal {
                        graph = GraphRequest(kinds: solution.values.map { arrow($0.re, $0.im) })
                    } else if Set(solution.unknowns).isSubset(of: ["x", "y"]) {
                        graph = systemGraph(system, knownVariables: Set(variables.keys))
                    }
                    return Calculation(expr: nil, outcome: .linearSystem(solution), graph: graph)
                }
            } catch {
                return Calculation(expr: nil, outcome: .error(error), graph: systemGraph(system, knownVariables: Set(variables.keys)))
            }
            guard let graph = systemGraph(system, knownVariables: Set(variables.keys)) else {
                return Calculation(expr: nil, outcome: .error(.unsupported("tega sistema ni mogoče narisati")), graph: nil)
            }
            let outcome = figureMeasures(system, variables: variables) ?? inequalitySystem(system, variables: variables)
                ?? curveMeasures(graph, variables: variables, typedRange: system.contains { parameterRange($0) != nil }) ?? .empty
            return Calculation(expr: nil, outcome: outcome, graph: graph)
        }
        let expr: Expr
        do {
            expr = try MathRowConverter.expr(from: row, options: options)
        } catch .incomplete {
            return Calculation(expr: nil, outcome: .incomplete, graph: nil)
        } catch {
            return Calculation(expr: nil, outcome: .error(error), graph: nil)
        }
        return calculate(expr, variables: variables, exactVariables: exactVariables, matrixVariables: matrixVariables, settings: settings)
    }

    public static func calculate(_ expr: Expr, variables: [String: Double], exactVariables: [String: ExactReal],
                                 matrixVariables: [String: Matrix] = [:], settings: CalculationSettings) -> Calculation {
        var context = EvaluationContext(angleUnit: settings.angleUnit, variables: variables, exactVariables: exactVariables,
                                        matrixVariables: matrixVariables, randomSeed: settings.randomSeed)
        // A named point A(2, 3) (A not a stored value): draw it.
        if let point = PlaneSets.point(expr), let name = point.name, variables[name] == nil, matrixVariables[name] == nil {
            return Calculation(expr: expr, outcome: .empty, graph: GraphRequest(kinds: [.point(x: point.x, y: point.y)]))
        }
        // (x(t), y(t)) and r = f(θ): the curve with its length and the area it encloses.
        if let curve = parametricCurve(expr, knownVariables: Set(variables.keys)) {
            let graph = GraphRequest(kinds: [curve.kind], parameters: curve.parameters)
            return Calculation(expr: expr, outcome: curveMeasures(graph, variables: variables) ?? .empty, graph: graph)
        }
        // eig(A): eigenvalues and eigenvectors; charpoly(A): det(A − λI), drawn so its zeros show.
        if case .function(let f, let args) = expr, f == .eig || f == .charpoly, args.count == 1 {
            do throws(MathError) {
                guard case .matrix(let m) = try MatrixEvaluator(context: context).evaluate(args[0]) else {
                    throw MathError.domain("\(f.internationalName) potrebuje kvadratno matriko")
                }
                let eigen = try EigenDecomposition(m)
                if f == .eig { return Calculation(expr: expr, outcome: .eigen(eigen), graph: nil) }
                let graph = GraphRequest(kinds: [.explicit(eigen.characteristicPolynomial.substituting("λ", with: .x))])
                return Calculation(expr: expr, outcome: .symbolic(eigen.characteristicPolynomial), graph: graph)
            } catch {
                return Calculation(expr: expr, outcome: .error(error), graph: nil)
            }
        }
        // Matrices and vectors
        if MatrixEvaluator.involvesMatrices(expr, matrixVariables: Set(matrixVariables.keys)) {
            do {
                switch try MatrixEvaluator(context: context).evaluate(expr) {
                case .matrix(let m):
                    return Calculation(expr: expr, outcome: .matrix(m), graph: planeVectorGraph(expr, result: m, context: context))
                case .scalar(let value, let exact):
                    return Calculation(expr: expr, outcome: .number(NumericResult(value: NumericCalculus.clean(value), exact: exact)), graph: nil)
                }
            } catch {
                return Calculation(expr: expr, outcome: .error(error), graph: nil)
            }
        }
        let free = expr.freeVariables.subtracting(variables.keys).subtracting(matrixVariables.keys)
        let parameters = free.subtracting(graphVariables).sorted()
        // Graphs use radians regardless of the calculator's angle unit.
        func params() -> [String] { parameters }

        switch expr {
        case .relation(.relation, _, _):
            // −1 ≤ y < 2, 1 < x < 3, 1 ≤ |z| ≤ 2 → the region between the bounds
            if let graph = chainGraph(expr, parameters: params()) {
                // −2 < 2x − 1 ≤ 5 in one unknown: also the solution as intervals.
                return Calculation(expr: expr, outcome: inequalitySystem([expr], variables: variables) ?? .empty, graph: graph)
            }
            return Calculation(expr: expr, outcome: .error(.unsupported("verižne neenačbe brez x, y ali z (uporabi jih kot pogoje v odsekoma definirani funkciji)")), graph: nil)
        case .relation(let lhs, let op, let rhs):
            // Sets of complex numbers: |z − 1| ≤ 2, Re z ≥ −2 … drawn in the plane z = x + iy.
            if PlaneSets.isComplexSet(expr), let plane = PlaneSets.complexRelation(lhs, rhs) {
                return Calculation(expr: expr, outcome: .empty, graph: GraphRequest(kinds: [.implicit(lhs: plane.lhs, relation: op, rhs: plane.rhs)], parameters: params()))
            }
            // a_n = 2n + 1 (also typed a(n) = …): the sequence as points.
            if op == .equal, let sequence = sequenceDefinition(lhs, rhs) {
                let others = params().filter { $0 != "n" && $0 != sequence.name }
                return Calculation(expr: expr, outcome: .empty, graph: GraphRequest(kinds: [.sequence(sequence.term)], parameters: others))
            }
            let lhsFree = lhs.freeVariables.subtracting(variables.keys)
            let rhsFree = rhs.freeVariables.subtracting(variables.keys)
            let all = lhsFree.union(rhsFree)
            // y = f(x)
            if op == .equal, case .variable("y") = lhs, !rhsFree.contains("y") {
                if rhsFree.contains("z") { break }
                return Calculation(expr: expr, outcome: .empty, graph: GraphRequest(kinds: explicitKinds(rhs), parameters: params()))
            }
            if op == .equal, case .variable("y") = rhs, !lhsFree.contains("y") {
                return Calculation(expr: expr, outcome: .empty, graph: GraphRequest(kinds: explicitKinds(lhs), parameters: params()))
            }
            // x = f(y)
            if op == .equal, case .variable("x") = lhs, !rhsFree.contains("x"), rhsFree.contains("y") {
                return Calculation(expr: expr, outcome: .empty, graph: GraphRequest(kinds: [.explicitInY(rhs)], parameters: params()))
            }
            // z = f(x, y)
            if op == .equal, case .variable("z") = lhs, !rhsFree.contains("z") {
                return Calculation(expr: expr, outcome: .empty, graph: GraphRequest(kinds: [.surface(rhs)], parameters: params()))
            }
            // Relation in x and y → implicit curve or region
            if all.contains("y") {
                return Calculation(expr: expr, outcome: .empty, graph: GraphRequest(kinds: [.implicit(lhs: lhs, relation: op, rhs: rhs)], parameters: params()))
            }
            // Equation in one unknown → solve, and graph both sides when the unknown is x.
            let unknown = all.contains("x") ? "x" : (all.sorted().first ?? "x")
            if op == .equal {
                let others = all.subtracting([unknown]).sorted()
                var graph: GraphRequest? = unknown == "x"
                    ? GraphRequest(kinds: [.explicit(lhs), .explicit(rhs)], parameters: others, highlightIntersections: true)
                    : nil
                // x = 3 is also the vertical line.
                if case .variable("x") = lhs, !rhs.dependsOn("x") {
                    graph = GraphRequest(kinds: [.explicitInY(rhs)], parameters: others)
                } else if case .variable("x") = rhs, !lhs.dependsOn("x") {
                    graph = GraphRequest(kinds: [.explicitInY(lhs)], parameters: others)
                }
                if let undefined = others.first {
                    // Parameters without values: show the graph with sliders instead of a number.
                    return Calculation(expr: expr, outcome: graph == nil ? .error(.undefinedVariable(undefined)) : .empty, graph: graph)
                }
                do {
                    let result = try EquationSolver.solve(lhs: lhs, rhs: rhs, variable: unknown, context: context)
                    return Calculation(expr: expr, outcome: .solutions(result), graph: graph)
                } catch {
                    return Calculation(expr: expr, outcome: .error(error), graph: graph)
                }
            }
            // Inequality in one unknown: its solution as intervals, and the region for x.
            let graph = unknown == "x" ? GraphRequest(kinds: [.implicit(lhs: lhs, relation: op, rhs: rhs)], parameters: params()) : nil
            if all.subtracting([unknown]).isEmpty, let solution = InequalitySolver.solve(lhs, op, rhs, variable: unknown, context: context) {
                return Calculation(expr: expr, outcome: .inequality(solution), graph: graph)
            }
            return Calculation(expr: expr, outcome: .empty, graph: graph ?? GraphRequest(kinds: [.implicit(lhs: lhs, relation: op, rhs: rhs)], parameters: params()))
        default:
            break
        }

        // d/dx f(x) without a point → symbolic derivative (and graphs of f and f′)
        if case .derivative(let body, let variable, nil) = expr {
            do {
                let derivative = try Differentiator.derivative(of: body, withRespectTo: variable, angleUnit: settings.angleUnit)
                let graph = variable == "x" && !body.freeVariables.contains("y")
                    ? GraphRequest(kinds: [.explicit(body), .explicit(derivative)], parameters: params().filter { $0 != "x" })
                    : nil
                return Calculation(expr: expr, outcome: .symbolic(derivative), graph: graph)
            } catch {
                return Calculation(expr: expr, outcome: .error(error), graph: nil)
            }
        }

        // ∫ f dx without bounds → F + C (checked by differentiating it), with the graphs of f and F.
        if case .integral(let body, let variable, nil, nil) = expr {
            var graph = variable == "x" && !body.freeVariables.contains("y")
                ? GraphRequest(kinds: explicitKinds(body), parameters: params().filter { $0 != "x" })
                : nil
            guard let antiderivative = Antiderivative.integrate(body, variable: variable, angleUnit: settings.angleUnit) else {
                return Calculation(expr: expr, outcome: .error(.unsupported("nedoločenega integrala ne znam izraziti – vnesi meje za določeni integral")), graph: graph)
            }
            graph?.kinds.append(.explicit(antiderivative))
            return Calculation(expr: expr, outcome: .symbolic(.sum([antiderivative, .variable("C")])), graph: graph)
        }

        // Graphable expression in x (no '=') → y = expr
        if free.contains("x") || free.contains("y") {
            if free.contains("y") {
                return Calculation(expr: expr, outcome: .empty, graph: GraphRequest(kinds: [.surface(expr)], parameters: params()))
            }
            return Calculation(expr: expr, outcome: .empty, graph: GraphRequest(kinds: explicitKinds(expr), parameters: params()))
        }
        // An expression in t (physics: x(t) = 20·cos(πt/3)) is drawn against t.
        if free.contains("t") {
            return Calculation(expr: expr, outcome: .empty,
                               graph: GraphRequest(kinds: explicitKinds(expr.substituting("t", with: .x)), parameters: params().filter { $0 != "t" }))
        }
        // An expression in n alone is a sequence: its terms as points.
        if free.contains("n") {
            return Calculation(expr: expr, outcome: .empty, graph: GraphRequest(kinds: [.sequence(expr)], parameters: params().filter { $0 != "n" }))
        }

        if let undefined = parameters.first {
            return Calculation(expr: expr, outcome: .error(.undefinedVariable(undefined)), graph: nil)
        }

        // Complex arithmetic (the result is also shown in the complex plane)
        if expr.containsImaginaryUnit {
            let outcome = complexOutcome(expr, context: context)
            return Calculation(expr: expr, outcome: outcome, graph: complexPlaneGraph(expr, outcome: outcome, context: context))
        }

        // Limits may diverge.
        if case .limit(let body, let variable, let point, let direction) = expr {
            do {
                let a = try RealEvaluator.evaluate(point, context: context)
                let value = try LimitEvaluator.limit(body, variable: variable, at: a, direction: direction, context: context)
                if value.isInfinite { return Calculation(expr: expr, outcome: .infinite(positive: value > 0), graph: limitGraph(body, variable: variable, params: params())) }
                return Calculation(expr: expr, outcome: .number(numeric(value, expr: nil, context: context)), graph: limitGraph(body, variable: variable, params: params()))
            } catch {
                return Calculation(expr: expr, outcome: .error(error), graph: limitGraph(body, variable: variable, params: params()))
            }
        }

        // Plain numeric evaluation (with exact form when possible)
        do {
            context.randomSeed = settings.randomSeed
            let value = try RealEvaluator.evaluate(expr, context: context)
            let result = numeric(value, expr: expr, context: context)
            var graph: GraphRequest?
            if case .integral(let body, let v, let lo?, let hi?) = expr, v == "x",
               body.freeVariables.subtracting(["x"]).subtracting(variables.keys).isEmpty {
                // The bounds as the value reads them: eval keeps ±∞ (evaluate throws .overflow for it).
                var bounds = RealEvaluator(context: context)
                let a = (try? bounds.eval(lo)) ?? .nan
                let b = (try? bounds.eval(hi)) ?? .nan
                // ∫₅¹ (or ∫₂¹ while 10 is being typed) shades the band [1, 5]: the app forms
                // lower...upper, which traps for reversed bounds. The value keeps its sign.
                // ∞ is drawn at ±10⁶ on its own side: ∫∞⁰ e⁻ˣ shades [0, 10⁶], not [−10⁶, 0].
                let from = a.isFinite ? a : (a == .infinity ? 1e6 : -1e6), to = b.isFinite ? b : (b == -.infinity ? -1e6 : 1e6)
                graph = GraphRequest(kinds: [.explicit(body)], shadedIntegral: ShadedIntegral(integrand: body, lower: Swift.min(from, to), upper: Swift.max(from, to)))
            }
            if case .function(.idiv, let args) = expr, args.count == 2,
               let a = try? RealEvaluator.evaluate(args[0], context: context), let b = try? RealEvaluator.evaluate(args[1], context: context),
               let ia = RealEvaluator.exactInt(a), let ib = RealEvaluator.exactInt(b), ib != 0 {
                return Calculation(expr: expr, outcome: .special(.quotientRemainder(quotient: ia / ib, remainder: ia % ib), result), graph: nil)
            }
            if case .function(.pol, let args) = expr, args.count == 2,
               let x = try? RealEvaluator.evaluate(args[0], context: context), let y = try? RealEvaluator.evaluate(args[1], context: context) {
                let theta = atan2(y, x) / settings.angleUnit.radiansPerUnit
                return Calculation(expr: expr, outcome: .special(.polar(r: hypot(x, y), theta: theta), result), graph: nil)
            }
            if case .function(.rec, let args) = expr, args.count == 2,
               let r = try? RealEvaluator.evaluate(args[0], context: context), let t = try? RealEvaluator.evaluate(args[1], context: context) {
                let angle = t * settings.angleUnit.radiansPerUnit
                return Calculation(expr: expr, outcome: .special(.rectangular(x: r * cos(angle), y: r * sin(angle)), result), graph: nil)
            }
            return Calculation(expr: expr, outcome: .number(result), graph: graph)
        } catch .notReal where settings.complexResults {
            let outcome = complexOutcome(expr, context: context)
            return Calculation(expr: expr, outcome: outcome, graph: complexPlaneGraph(expr, outcome: outcome, context: context))
        } catch {
            return Calculation(expr: expr, outcome: .error(error), graph: nil)
        }
    }

    /// What to draw for a definition in the graph workspace (no numeric evaluation).
    /// `y = f(x)`, `f(x)`, `x = g(y)`, `x = 3` (vertical line), implicit relations and
    /// regions in x and y, `z = f(x, y)`, and equations in x (both sides, with intersections).
    public static func graphRequest(for expr: Expr, knownVariables: Set<String> = []) -> GraphRequest? {
        let free = expr.freeVariables.subtracting(knownVariables)
        let parameters = free.subtracting(graphVariables).sorted()
        if let curve = parametricCurve(expr, knownVariables: knownVariables) {
            return GraphRequest(kinds: [curve.kind], parameters: curve.parameters)
        }
        if let point = PlaneSets.point(expr) {
            return GraphRequest(kinds: [.point(x: point.x, y: point.y)], parameters: parameters.filter { $0 != point.name })
        }
        switch expr {
        case .relation(.relation, _, _):
            return chainGraph(expr, parameters: parameters)
        case .relation(let lhs, let op, let rhs):
            if PlaneSets.isComplexSet(expr), let plane = PlaneSets.complexRelation(lhs, rhs) {
                return GraphRequest(kinds: [.implicit(lhs: plane.lhs, relation: op, rhs: plane.rhs)], parameters: parameters)
            }
            if op == .equal, let sequence = sequenceDefinition(lhs, rhs) {
                return GraphRequest(kinds: [.sequence(sequence.term)], parameters: parameters.filter { $0 != "n" && $0 != sequence.name })
            }
            let lhsFree = lhs.freeVariables.subtracting(knownVariables)
            let rhsFree = rhs.freeVariables.subtracting(knownVariables)
            if op == .equal, case .variable("y") = lhs, !rhsFree.contains("y"), !rhsFree.contains("z") {
                return GraphRequest(kinds: explicitKinds(rhs), parameters: parameters)
            }
            if op == .equal, case .variable("y") = rhs, !lhsFree.contains("y"), !lhsFree.contains("z") {
                return GraphRequest(kinds: explicitKinds(lhs), parameters: parameters)
            }
            if op == .equal, case .variable("x") = lhs, !rhsFree.contains("x"), !rhsFree.contains("z") {
                return GraphRequest(kinds: [.explicitInY(rhs)], parameters: parameters)
            }
            if op == .equal, case .variable("z") = lhs, !rhsFree.contains("z") {
                return GraphRequest(kinds: [.surface(rhs)], parameters: parameters)
            }
            if lhsFree.union(rhsFree).contains("y") {
                return GraphRequest(kinds: [.implicit(lhs: lhs, relation: op, rhs: rhs)], parameters: parameters)
            }
            if op == .equal {
                return GraphRequest(kinds: [.explicit(lhs), .explicit(rhs)], parameters: parameters, highlightIntersections: true)
            }
            return GraphRequest(kinds: [.implicit(lhs: lhs, relation: op, rhs: rhs)], parameters: parameters)
        case .derivative(let body, let variable, nil) where variable == "x":
            guard let derivative = try? Differentiator.derivative(of: body, withRespectTo: "x") else { return nil }
            return GraphRequest(kinds: [.explicit(derivative)], parameters: parameters)
        default:
            if free.contains("y") { return GraphRequest(kinds: [.surface(expr)], parameters: parameters) }
            if free.contains("t"), !free.contains("x") {
                return GraphRequest(kinds: explicitKinds(expr.substituting("t", with: .x)), parameters: parameters.filter { $0 != "t" })
            }
            if free.contains("n"), !free.contains("x") {
                return GraphRequest(kinds: [.sequence(expr)], parameters: parameters.filter { $0 != "n" })
            }
            return GraphRequest(kinds: explicitKinds(expr), parameters: parameters)
        }
    }

    /// `a_n = …`: a sequence given by its general term (n = 1, 2, 3 …).
    static func sequenceDefinition(_ lhs: Expr, _ rhs: Expr) -> (name: String, term: Expr)? {
        guard case .variable(let name) = lhs, name.hasSuffix("_n"), rhs.dependsOn("n"),
              !rhs.dependsOn("x"), !rhs.dependsOn("y") else { return nil }
        return (name, rhs)
    }

    /// What to draw for a row of the graph workspace: a system or a single definition.
    public static func graphRequest(for row: MathRow, knownVariables: Set<String> = [], functions: [String: Expr] = [:]) throws(MathError) -> GraphRequest? {
        let options = ParserOptions(knownVariables: knownVariables, functions: functions)
        if let system = MathRowConverter.system(from: row, options: options) {
            return systemGraph(system, knownVariables: knownVariables)
        }
        return graphRequest(for: try MathRowConverter.expr(from: row, options: options), knownVariables: knownVariables)
    }

    /// The bodies of the definitions `f(x) = …` among `rows`, so other rows can use f(…):
    /// g(x) = f(x − 2) + 1 in the graph list, f(2) in the calculator. Definitions may use
    /// each other (a few passes resolve the chain).
    public static func definedFunctions(_ rows: [MathRow]) -> [String: Expr] {
        var functions: [String: Expr] = [:]
        for _ in 0..<3 {
            var next: [String: Expr] = [:]
            for row in rows {
                let options = ParserOptions(functions: functions)
                guard let tokens = try? MathRowConverter.tokens(from: row, options: options),
                      let head = Parser.definitionHead(tokens, options: options),
                      case .relation(.variable("y"), .equal, let body)? = try? Parser.parse(tokens: tokens, options: options)
                else { continue }
                next[head.name] = body
            }
            if next == functions { break }
            functions = next
        }
        return functions
    }

    /// A system: equations alone are curves with their intersections marked; inequalities alone
    /// are one region where all of them hold; equations with inequalities are drawn only where
    /// the inequalities hold (x² + y² = 4, y ≥ 0 is a semicircle; y = 1, −1 ≤ x < 2 a segment).
    public static func systemGraph(_ relations: [Expr], knownVariables: Set<String> = []) -> GraphRequest? {
        if let curves = parametricSystem(relations, knownVariables: knownVariables) { return curves }
        var kinds: [GraphKind] = []
        var equations: [(Expr, RelationOperator, Expr)] = []
        var gaps: [Expr] = []
        var strict = true
        var parameters = Set<String>()
        var points: [(x: Expr, y: Expr)] = []
        var allNamed = true
        for relation in relations {
            if let point = PlaneSets.point(relation) {
                // A(1, 2), B(4, 5), C(6, 1): the points and the triangle; unnamed (1, 9), (2, 15), …
                // are data joined in order (a frequency polygon).
                points.append((point.x, point.y))
                if point.name == nil { allNamed = false }
                kinds.append(.point(x: point.x, y: point.y))
                parameters.formUnion(relation.freeVariables.subtracting(knownVariables).subtracting(graphVariables).subtracting([point.name ?? ""]))
                continue
            }
            parameters.formUnion(relation.freeVariables.subtracting(knownVariables).subtracting(graphVariables))
            guard case .relation(var lhs, let op, var rhs) = relation else { return nil }
            if case .relation = lhs {
                guard let region = PlaneSets.chainRegion(relation) else { return nil }
                gaps.append(region.lhs)
                if region.relation != .greater { strict = false }
                continue
            }
            if PlaneSets.isComplexSet(relation) {
                guard let plane = PlaneSets.complexRelation(lhs, rhs) else { return nil }
                lhs = plane.lhs
                rhs = plane.rhs
            }
            switch op {
            case .less: gaps.append(rhs - lhs)
            case .lessOrEqual: gaps.append(rhs - lhs); strict = false
            case .greater: gaps.append(lhs - rhs)
            case .greaterOrEqual: gaps.append(lhs - rhs); strict = false
            case .equal, .notEqual:
                equations.append((lhs, op, rhs))
            }
        }
        if points.count == relations.count, points.count >= 2 {
            kinds.insert(.polyline(points.flatMap { [$0.x, $0.y] }, closed: allNamed && points.count >= 3), at: 0)
        }
        let region = gaps.isEmpty ? nil : gaps.count == 1 ? gaps[0] : Expr.function(.min, gaps)
        if let region, !equations.isEmpty {
            // Curves restricted to the region: undefined (not drawn) where an inequality fails.
            let condition = Expr.relation(region, strict ? .greater : .greaterOrEqual, .zero)
            for (lhs, op, rhs) in equations {
                kinds.append(.implicit(lhs: .piecewise([lhs - rhs, condition]), relation: op, rhs: .zero))
            }
        } else if let region {
            kinds.append(.implicit(lhs: region, relation: strict ? .greater : .greaterOrEqual, rhs: .zero))
        } else {
            for (lhs, op, rhs) in equations {
                guard let request = graphRequest(for: .relation(lhs, op, rhs), knownVariables: knownVariables) else { return nil }
                kinds.append(contentsOf: request.kinds)
            }
        }
        guard !kinds.isEmpty else { return nil }
        return GraphRequest(kinds: kinds, parameters: parameters.sorted(), highlightIntersections: true)
    }

    // MARK: Parametric and polar curves

    /// (x(t), y(t)) or r = f(θ) (also φ or t) as a parametric curve over `range` (default: one turn
    /// [0, 2π] for polar and trigonometric curves, otherwise [−10, 10]).
    static func parametricCurve(_ expr: Expr, range: ClosedRange<Double>? = nil, knownVariables: Set<String> = []) -> (kind: GraphKind, parameters: [String])? {
        let x: Expr, y: Expr
        var polar = false
        if let point = PlaneSets.point(expr), point.name == nil {
            let free = point.x.freeVariables.union(point.y.freeVariables)
            guard free.contains("t"), !free.contains("x"), !free.contains("y") else { return nil }
            x = point.x
            y = point.y
        } else if case .relation(.variable("r"), .equal, let rhs) = expr, !rhs.dependsOn("x"), !rhs.dependsOn("y"),
                  let angle = ["θ", "φ", "t"].first(where: { rhs.dependsOn($0) }) {
            let r = rhs.substituting(angle, with: .variable("t"))
            x = .product([r, .function(.cos, [.variable("t")])])
            y = .product([r, .function(.sin, [.variable("t")])])
            polar = true
        } else {
            return nil
        }
        let trigonometric = polar || [x, y].contains { e in
            e.contains { node in
                if case .function(let f, _) = node { return f.isTrigonometric }
                return false
            }
        }
        let interval = range ?? (trigonometric ? 0...(2 * Double.pi) : -10...10)
        let parameters = x.freeVariables.union(y.freeVariables).subtracting(["t"]).subtracting(knownVariables).sorted()
        return (.parametric(x: x, y: y, from: interval.lowerBound, to: interval.upperBound), parameters)
    }

    /// a ≤ t ≤ b (also θ, φ) with constant bounds.
    static func parameterRange(_ relation: Expr) -> ClosedRange<Double>? {
        guard case .relation(.relation(let a, let first, .variable(let v)), let second, let b) = relation,
              ["t", "θ", "φ"].contains(v), first.isInequality, second.isInequality,
              let lower = try? RealEvaluator.evaluate(a), let upper = try? RealEvaluator.evaluate(b),
              lower.isFinite, upper.isFinite, lower != upper else { return nil }
        return Swift.min(lower, upper)...Swift.max(lower, upper)
    }

    /// Parametric curves given as (x(t), y(t)), r = f(θ) or x = f(t), y = g(t), with an
    /// optional range a ≤ t ≤ b; nil when the system contains anything else.
    static func parametricSystem(_ relations: [Expr], knownVariables: Set<String>) -> GraphRequest? {
        var range: ClosedRange<Double>?
        var curves: [Expr] = []
        var xOfT: Expr?, yOfT: Expr?
        for relation in relations {
            if let interval = parameterRange(relation) {
                range = interval
                continue
            }
            if case .relation(.variable(let side), .equal, let rhs) = relation, side == "x" || side == "y",
               rhs.dependsOn("t"), !rhs.dependsOn("x"), !rhs.dependsOn("y") {
                if side == "x" { xOfT = rhs } else { yOfT = rhs }
                continue
            }
            curves.append(relation)
        }
        if let x = xOfT, let y = yOfT {
            curves.append(.matrix(rows: 2, columns: 1, entries: [x, y]))
        } else if xOfT != nil || yOfT != nil {
            return nil
        }
        guard !curves.isEmpty else { return nil }
        var kinds: [GraphKind] = []
        var parameters = Set<String>()
        for expr in curves {
            guard let curve = parametricCurve(expr, range: range, knownVariables: knownVariables) else { return nil }
            kinds.append(curve.kind)
            parameters.formUnion(curve.parameters)
        }
        return GraphRequest(kinds: kinds, parameters: parameters.sorted())
    }

    /// The length L = ∫√(x′² + y′²) dt of a single parametric curve and, when it closes, the
    /// area S = ½|∮(x·y′ − y·x′) dt| it encloses (Green's formula). On the default interval a closed
    /// curve that runs over itself n times (r = sin θ, (cos 2t, sin 2t)) is measured once; a typed
    /// interval a ≤ t ≤ b is the path that was asked for.
    static func curveMeasures(_ graph: GraphRequest, variables: [String: Double], typedRange: Bool = false) -> CalculationOutcome? {
        guard graph.parameters.isEmpty, graph.kinds.count == 1, case .parametric(let x, let y, let a, let b) = graph.kinds[0],
              let dx = try? Differentiator.derivative(of: x, withRespectTo: "t"),
              let dy = try? Differentiator.derivative(of: y, withRespectTo: "t") else { return nil }
        let context = EvaluationContext(variables: variables)
        let speed = Expr.power(.sum([.power(dx, .int(2)), .power(dy, .int(2))]), .number(.half))
        guard let length = try? Integrator.integrate(speed, variable: "t", from: a, to: b, context: context), length.isFinite else { return nil }
        let fx = FunctionAnalyzer.makeFunction(x, variable: "t", context: context)
        let fy = FunctionAnalyzer.makeFunction(y, variable: "t", context: context)
        let tolerance = 1e-9 * Swift.max(1, length)
        var area: Double?
        var turns = 1.0
        if hypot(fx(a) - fx(b), fy(a) - fy(b)) <= tolerance {
            // Relative to the length: (10⁻⁷cos t, 10⁻⁷sin t) moves only 6·10⁻¹⁰ in a thousandth of a turn,
            // which the absolute 10⁻⁹ above took for 1000 turns.
            if !typedRange { turns = Double(repetitions(fx, fy, from: a, to: b, tolerance: 1e-9 * length)) }
            let integrand = Expr.product([.number(.half), .sum([.product([x, dy]), .negation(.product([y, dx]))])])
            if let s = try? Integrator.integrate(integrand, variable: "t", from: a, to: b, context: context), s.isFinite {
                area = NumericCalculus.clean(Swift.abs(s) / turns)
            }
        }
        let l = NumericCalculus.clean(length / turns)
        return .special(.curve(length: l, area: area), NumericResult(value: l))
    }

    /// How many times a closed curve runs over itself on [a, b]: the largest n ≤ 1000 with
    /// γ(t + (b − a)/n) = γ(t) at 16 points (2 for r = sin θ on [0, 2π], 40 for (cos 40t, sin 40t)).
    /// A wrong n fails at its first point almost always, so this costs about 1000 pairs of points,
    /// small next to the two adaptive integrals; at most 999·16.
    static func repetitions(_ fx: (Double) -> Double, _ fy: (Double) -> Double, from a: Double, to b: Double, tolerance: Double) -> Int {
        for n in stride(from: 1000, through: 2, by: -1) {
            let period = (b - a) / Double(n)
            let repeats = (0..<16).allSatisfy { k in
                let t = a + (Double(k) + 0.318) / 16 * (b - a - period)
                return hypot(fx(t + period) - fx(t), fy(t + period) - fy(t)) <= tolerance
            }
            if repeats { return n }
        }
        return 1
    }

    /// A system or chain of inequalities in one unknown (not y): the intersection of the solutions.
    static func inequalitySystem(_ relations: [Expr], variables: [String: Double]) -> CalculationOutcome? {
        var unknowns = Set<String>()
        var links: [(Expr, RelationOperator, Expr)] = []
        for relation in relations {
            unknowns.formUnion(relation.freeVariables.subtracting(variables.keys))
            guard let parts = PlaneSets.links(relation) else { return nil }
            links += parts
        }
        guard unknowns.count == 1, let unknown = unknowns.first, unknown != "y", unknown != "z",
              links.allSatisfy({ $0.1 != .equal && $0.1 != .notEqual }),
              let solution = InequalitySolver.solve(links, variable: unknown, context: EvaluationContext(variables: variables)) else { return nil }
        return .inequality(solution)
    }

    /// Area and perimeter of a polygon A(…), B(…), C(…) … (shoelace formula), or the length of
    /// a segment A(…), B(…).
    static func figureMeasures(_ parts: [Expr], variables: [String: Double]) -> CalculationOutcome? {
        let points = parts.compactMap(PlaneSets.point)
        guard points.count == parts.count, points.count >= 2 else { return nil }
        let context = EvaluationContext(variables: variables)
        if points.allSatisfy({ $0.name == nil }) {
            // (0, 0), (4, 12), (10, 12), (12, 0): the area under v(t) is the distance, under F(s) the work.
            let data = points.compactMap { p -> DataPoint? in
                guard let x = try? RealEvaluator.evaluate(p.x, context: context), let y = try? RealEvaluator.evaluate(p.y, context: context) else { return nil }
                return DataPoint(x: x, y: y)
            }
            guard data.count == points.count, let area = TwoVariableStatistics.areaUnderPolyline(data) else { return nil }
            return .special(.areaUnderPolyline(area), numeric(area, expr: nil, context: context))
        }
        guard points.allSatisfy({ $0.name != nil }) else { return nil }
        var corners: [(x: Double, y: Double)] = []
        for p in points {
            guard let x = try? RealEvaluator.evaluate(p.x, context: context),
                  let y = try? RealEvaluator.evaluate(p.y, context: context), x.isFinite, y.isFinite else { return nil }
            corners.append((x, y))
        }
        func distance(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double)) -> Double { hypot(b.x - a.x, b.y - a.y) }
        if corners.count == 2 {
            let d = distance(corners[0], corners[1])
            return .special(.segmentLength(d), numeric(d, expr: nil, context: context))
        }
        var twiceArea = 0.0, perimeter = 0.0
        for i in corners.indices {
            let a = corners[i], b = corners[(i + 1) % corners.count]
            twiceArea += a.x * b.y - b.x * a.y
            perimeter += distance(a, b)
        }
        let area = Swift.abs(twiceArea) / 2
        return .special(.polygon(area: area, perimeter: perimeter), numeric(area, expr: nil, context: context))
    }

    /// A chain of inequalities in x, y (or z as a complex number) as one shaded region.
    static func chainGraph(_ expr: Expr, parameters: [String]) -> GraphRequest? {
        guard let region = PlaneSets.chainRegion(expr) else { return nil }
        let free = region.lhs.freeVariables
        guard free.contains("x") || free.contains("y") else { return nil }
        return GraphRequest(kinds: [.implicit(lhs: region.lhs, relation: region.relation, rhs: region.rhs)], parameters: parameters)
    }

    /// `y = ±√(r² − x²)` draws both branches.
    static func explicitKinds(_ e: Expr) -> [GraphKind] {
        if let (plus, minus) = splitPlusMinus(e) { return [.explicit(plus), .explicit(minus)] }
        return [.explicit(e)]
    }

    /// Replaces the first `a ± b` anywhere in the tree by `a + b` and `a − b`.
    static func splitPlusMinus(_ e: Expr) -> (Expr, Expr)? {
        if case .plusMinus(let a, let b) = e {
            return (Simplifier.simplify(.sum([a, b])), Simplifier.simplify(.sum([a, .negation(b)])))
        }
        for (index, child) in e.children.enumerated() {
            guard let (plus, minus) = splitPlusMinus(child) else { continue }
            func rebuild(_ replacement: Expr) -> Expr {
                var position = 0
                return e.mapChildren { original in
                    defer { position += 1 }
                    return position == index ? replacement : original
                }
            }
            return (rebuild(plus), rebuild(minus))
        }
        return nil
    }

    static func limitGraph(_ body: Expr, variable: String, params: [String]) -> GraphRequest? {
        guard variable == "x", !body.freeVariables.contains("y") else { return nil }
        return GraphRequest(kinds: [.explicit(body)], parameters: params.filter { $0 != "x" })
    }

    static func numeric(_ value: Double, expr: Expr?, context: EvaluationContext) -> NumericResult {
        if let expr {
            // An exact value is also the decimal one: 10^(−15) is 10⁻¹⁵, not 0.
            if let exact = ExactEvaluator.value(expr, angleUnit: context.angleUnit, variables: context.exactVariables) {
                return NumericResult(value: exact.doubleValue, exact: exact)
            }
            if !involvesTranscendentalResult(expr) {
                // Only cancellation noise becomes 0 (e^(ln 5) − 5, ln(e³) − 3); a small value computed without
                // cancellation stays (h·f = 3,313035075·10⁻¹⁹ J, Φ(−8) = 6,2·10⁻¹⁶), which clean() made 0.
                let scale = noiseScale(expr) { e in (try? RealEvaluator.evaluate(e, context: context)).map { Complex($0, 0) } }
                return NumericResult(value: withoutNoise(value, scale: scale.re))
            }
        }
        // Integrals, sums and limits: recognise π, surds and fractions (∫ sin x/x = π, Σ 1/n² = π²/6). Their
        // numeric error has no scale known here, so tiny values still become 0.
        let exact = ExactRecognizer.recognize(value, tolerance: 1e-9) ?? recognizePiSquared(value)
        return NumericResult(value: NumericCalculus.clean(value), exact: exact)
    }

    /// `x` with its rounding noise removed: 0 when it is below 10⁻¹⁴ of the `scale` of the terms it was
    /// computed from (`noiseScale`), otherwise rounded to 13 significant digits.
    static func withoutNoise(_ x: Double, scale: Double) -> Double {
        scale.isFinite && Swift.abs(x) < 1e-14 * scale ? 0 : NumericCalculus.roundNoise(x)
    }

    /// For each part of a value, the size of the terms it was computed from, which bounds its rounding and
    /// cancellation noise (about 10⁻¹⁶ of it): the largest term of a sum, scaled by products (with the parts
    /// mixed as in the product), quotients and powers, passed on by functions that are about linear in their
    /// argument (|x|, Re, sinh, arctan …; ln turns relative noise into absolute), an ulp or so of the argument
    /// for frac and mod, whose remainder is exact, and otherwise the value itself (h·f or Φ(−8) carry no
    /// cancellation), in both parts unless it is real. `value` evaluates a subexpression (nil when it fails,
    /// which gives no scale).
    static func noiseScale(_ e: Expr, value: (Expr) -> Complex?) -> (re: Double, im: Double) {
        guard let v = value(e) else { return (0, 0) }
        let fresh = (re: v.magnitude, im: v.im == 0 ? 0 : v.magnitude)
        switch e {
        case .number, .decimal, .constant, .variable:
            return (Swift.abs(v.re), Swift.abs(v.im))
        case .sum(let terms):
            var scale = (re: Swift.abs(v.re), im: Swift.abs(v.im))
            for term in terms {
                let s = noiseScale(term, value: value)
                scale = (Swift.max(scale.re, s.re), Swift.max(scale.im, s.im))
            }
            return scale
        case .product(let factors):
            // (a + bi)(c + di) = (ac − bd) + (ad + bc)i
            var scale = (re: 1.0, im: 0.0)
            for factor in factors {
                let s = noiseScale(factor, value: value)
                scale = (scale.re * s.re + scale.im * s.im, scale.re * s.im + scale.im * s.re)
            }
            return scale
        case .negation(let inner):
            return noiseScale(inner, value: value)
        case .percent(let inner):
            let s = noiseScale(inner, value: value)
            return (s.re / 100, s.im / 100)
        case .quotient(let a, let b):
            guard let divisor = value(b), divisor.magnitude > 0 else { return fresh }
            let s = noiseScale(a, value: value)
            if divisor.im == 0 { return (s.re / Swift.abs(divisor.re), s.im / Swift.abs(divisor.re)) }
            let mixed = (s.re + s.im) / divisor.magnitude
            return (mixed, mixed)
        case .power(let base, let exponent):
            guard let p = value(exponent), p.im == 0, p.re > 0, let b = value(base) else { return fresh }
            let s = noiseScale(base, value: value)
            if b.im == 0 && v.im == 0 { return (Swift.max(Swift.abs(v.re), Foundation.pow(s.re, p.re)), 0) }
            let mixed = Swift.max(v.magnitude, Foundation.pow(s.re + s.im, p.re))
            return (mixed, mixed)
        case .function(let f, let args):
            guard let first = args.first else { return fresh }
            switch f {
            case .abs, .re, .im, .conj, .rec:
                // The noise of the part that is kept passes on (r·cos φ keeps that of r).
                let s = noiseScale(first, value: value)
                switch f {
                case .abs: return (Swift.max(Swift.abs(v.re), Swift.max(s.re, s.im)), 0)
                case .im: return (Swift.max(Swift.abs(v.re), s.im), 0)
                case .conj: return (Swift.max(Swift.abs(v.re), s.re), Swift.max(Swift.abs(v.im), s.im))
                default: return (Swift.max(Swift.abs(v.re), s.re), 0)
                }
            case .frac, .mod:
                // The remainder itself is exact: its noise is an ulp or so of the argument, or what cancellation
                // left in it, not the argument's size (frac(10¹⁵ + 0,25) = 0,25).
                guard let x = value(first) else { return fresh }
                let s = noiseScale(first, value: value)
                var scale = Swift.max(1.5e14 * x.re.magnitude.ulp, s.re - Swift.abs(x.re))
                if f == .mod, args.count == 2, let b = value(args[1]) {
                    scale = Swift.max(scale, 1.5e14 * b.re.magnitude.ulp)
                }
                return (scale, 0)
            case .sinh, .tanh, .asin, .atan, .asinh, .atanh, .erf, .degrees:
                // About c·x for small x: the relative noise passes on.
                guard let x = value(first), x.magnitude > 0 else { return fresh }
                let s = noiseScale(first, value: value)
                let scale = Swift.max(v.magnitude, Swift.max(s.re, s.im) * v.magnitude / x.magnitude)
                return (scale, v.im == 0 ? 0 : scale)
            case .ln, .log10, .log2, .log:
                // The relative noise of the argument becomes the absolute noise of the logarithm.
                guard let last = args.last, let x = value(last), x.magnitude > 0 else { return fresh }
                var unit = 1.0
                if f == .log10 { unit = Foundation.log(10.0) }
                if f == .log2 { unit = Foundation.log(2.0) }
                if f == .log, args.count == 2, let base = value(first)?.magnitude, base > 0, base != 1 {
                    unit = Swift.abs(Foundation.log(base))
                }
                let s = noiseScale(last, value: value)
                let scale = Swift.max(v.magnitude, Swift.max(s.re, s.im) / x.magnitude / unit)
                return (scale, v.im == 0 ? 0 : scale)
            case .min, .max:
                // The noise of the argument that was chosen, not of the others: min(−1; 1 + (10²⁰ − 10²⁰)) = −1.
                var scale = (re: 0.0, im: 0.0)
                for arg in args where value(arg) == v {
                    let s = noiseScale(arg, value: value)
                    scale = (Swift.max(scale.re, s.re), Swift.max(scale.im, s.im))
                }
                return scale
            default:
                return fresh
            }
        default:
            return fresh
        }
    }

    static func involvesTranscendentalResult(_ e: Expr) -> Bool {
        e.contains { node in
            switch node {
            case .integral, .summation, .productSeries, .limit, .derivative: true
            default: false
            }
        }
    }

    static func recognizePiSquared(_ x: Double) -> ExactReal? {
        guard let r = Rational.approximating(x / (.pi * .pi), maxDenominator: 360, tolerance: 1e-11),
              let value = ExactReal(validating: [ExactReal.Basis(radicand: 1, piPower: 2): r]),
              abs(value.doubleValue - x) < 1e-10 * max(1, abs(x)) else { return nil }
        return value
    }

    /// An arrow from the origin to (x, y).
    static func arrow(_ x: Double, _ y: Double) -> GraphKind {
        .segment(x0: .zero, y0: .zero, x1: .decimal(x), y1: .decimal(y), arrow: true)
    }

    /// `a ± b` drawn as arrows: the result, both operands and the dashed parallelogram.
    static func parallelogram(result: (Double, Double), _ a: (Double, Double), _ b: (Double, Double)) -> [GraphKind] {
        [arrow(result.0, result.1), arrow(a.0, a.1), arrow(b.0, b.1),
         .segment(x0: .decimal(a.0), y0: .decimal(a.1), x1: .decimal(result.0), y1: .decimal(result.1), arrow: false),
         .segment(x0: .decimal(b.0), y0: .decimal(b.1), x1: .decimal(result.0), y1: .decimal(result.1), arrow: false)]
    }

    /// A complex result as an arrow in the complex plane; a sum or difference of two numbers
    /// also shows the operands (adding complex numbers graphically).
    static func complexPlaneGraph(_ expr: Expr, outcome: CalculationOutcome, context: EvaluationContext) -> GraphRequest? {
        guard case .complex(let c) = outcome else { return nil }
        if case .sum(let terms) = expr, terms.count == 2,
           let a = complexValue(terms[0], context: context), let b = complexValue(terms[1], context: context) {
            return GraphRequest(kinds: parallelogram(result: (c.re, c.im), (a.re, a.im), (b.re, b.im)))
        }
        return GraphRequest(kinds: [arrow(c.re, c.im)])
    }

    /// A vector in the plane as an arrow; a sum or difference of two vectors with its parallelogram.
    static func planeVectorGraph(_ expr: Expr, result: Matrix, context: EvaluationContext) -> GraphRequest? {
        func plane(_ m: Matrix) -> (Double, Double)? {
            guard m.count == 2, let v = m.vectorEntries, v.allSatisfy(\.isFinite) else { return nil }
            return (v[0], v[1])
        }
        guard let r = plane(result) else { return nil }
        if case .sum(let terms) = expr, terms.count == 2,
           case .matrix(let ma)? = try? MatrixEvaluator(context: context).evaluate(terms[0]),
           case .matrix(let mb)? = try? MatrixEvaluator(context: context).evaluate(terms[1]),
           let a = plane(ma), let b = plane(mb) {
            return GraphRequest(kinds: parallelogram(result: r, a, b))
        }
        return GraphRequest(kinds: [arrow(r.0, r.1)])
    }

    static func complexValue(_ expr: Expr, context: EvaluationContext) -> Complex? {
        let compiler = BytecodeCompiler(slots: [:], angleUnit: context.angleUnit, constants: context.variables, complexMode: true)
        guard let program = try? compiler.compile(expr) else { return nil }
        let value = ComplexVM(program: program, requiresRealArguments: true).evaluate(z: .zero)
        return value.isFinite ? value : nil
    }

    static func complexOutcome(_ expr: Expr, context: EvaluationContext) -> CalculationOutcome {
        let compiler = BytecodeCompiler(slots: [:], angleUnit: context.angleUnit, constants: context.variables, complexMode: true)
        do {
            let program = try compiler.compile(expr)
            let value = ComplexVM(program: program, requiresRealArguments: true).evaluate(z: .zero)
            guard value.isFinite else { return .error(.domain("rezultat ni definiran")) }
            // As for real results: e^(iπ) + 1 = 1,2·10⁻¹⁶i is 0, but (1 + i)·6,6·10⁻³⁴ keeps both parts.
            let scale = noiseScale(expr) { complexValue($0, context: context) }
            let cleaned = Complex(withoutNoise(value.re, scale: scale.re), withoutNoise(value.im, scale: scale.im))
            if cleaned.im == 0 { return .number(NumericResult(value: cleaned.re, exact: ExactRecognizer.recognize(cleaned.re))) }
            return .complex(cleaned)
        } catch {
            return .error(error)
        }
    }
}
