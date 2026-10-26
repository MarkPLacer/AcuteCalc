import Foundation

/// Fourier series of a function given piecewise on one period (Matematika II at FE and FGG):
/// the coefficients aₙ and bₙ numerically and, when the integrals have closed forms, as
/// formulas in n; partial sums and the periodic extension for graphs.
public enum FourierSeries {
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        /// Period T = b − a: a₀/2 + Σ (aₙ cos nωx + bₙ sin nωx), ω = 2π/T.
        case full
        /// The odd extension of f on [a, b], period 2L with L = b − a: Σ bₙ sin(nπ(x − a)/L).
        case sine
        /// The even extension, period 2L: a₀/2 + Σ aₙ cos(nπ(x − a)/L).
        case cosine
    }

    /// f on one interval: from the end of the previous piece (or the start) to `end`.
    public struct Piece: Sendable, Hashable {
        public var expr: Expr
        public var end: Expr

        public init(expr: Expr, end: Expr) {
            self.expr = expr
            self.end = end
        }
    }

    public struct Series: Sendable, Hashable {
        public var kind: Kind
        public var start: Double
        /// L = b − a: the period of the full series, half the period of sine and cosine series.
        public var length: Double
        /// ω = 2π/L (full series) or π/L (sine and cosine series).
        public var omega: Double
        /// aₙ and bₙ for n = 0 … N (b₀ = 0).
        public var a: [Double]
        public var b: [Double]
        /// a₀, aₙ and bₙ as formulas in n, kept only when they reproduce the numerical values.
        public var a0Formula: Expr?
        public var anFormula: Expr?
        public var bnFormula: Expr?
        /// n where the general formulas divide by zero; the values are still in `a` and `b`.
        public var exceptions: [Int]

        /// The variable of the trigonometric terms: x, or x − a for sine and cosine series.
        var phase: Expr {
            kind == .full || start == 0 ? .variable("x") : .sum([.variable("x"), .decimal(-start)])
        }

        /// S_N(x) with the numerical coefficients.
        public func partialSum(_ terms: Int) -> Expr {
            var parts: [Expr] = []
            if a[0] != 0 { parts.append(.decimal(a[0] / 2)) }
            for n in stride(from: 1, through: Swift.min(terms, a.count - 1), by: 1) {
                let argument = Expr.product([.decimal(Double(n) * omega), phase])
                if a[n] != 0 { parts.append(.product([.decimal(a[n]), .function(.cos, [argument])])) }
                if b[n] != 0 { parts.append(.product([.decimal(b[n]), .function(.sin, [argument])])) }
            }
            return parts.isEmpty ? .zero : .sum(parts)
        }

        public func value(at x: Double, terms: Int) -> Double {
            let u = kind == .full ? x : x - start
            var s = a[0] / 2
            for n in stride(from: 1, through: Swift.min(terms, a.count - 1), by: 1) {
                s += a[n] * cos(Double(n) * omega * u) + b[n] * sin(Double(n) * omega * u)
            }
            return s
        }
    }

    /// The series of f given by `pieces` on [start, end of the last piece], with the
    /// coefficients up to n = max(terms, 8).
    public static func series(_ pieces: [Piece], start: Expr, kind: Kind, terms: Int,
                              parameters: [String: Double] = [:]) throws(MathError) -> Series {
        guard !pieces.isEmpty else { throw .domain("vnesi funkcijo") }
        let context = EvaluationContext(variables: parameters)
        let first = try RealEvaluator.evaluate(start, context: context)
        var bounds = [first]
        for piece in pieces { bounds.append(try RealEvaluator.evaluate(piece.end, context: context)) }
        guard bounds.allSatisfy(\.isFinite), zip(bounds, bounds.dropFirst()).allSatisfy({ $0 < $1 }) else {
            throw .domain("meje odsekov morajo naraščati")
        }
        let a = bounds[0], length = bounds[bounds.count - 1] - bounds[0]
        let omega = (kind == .full ? 2 : 1) * Double.pi / length
        let count = Swift.max(8, Swift.min(terms, 100))
        let functions = pieces.map { FunctionAnalyzer.makeFunction($0.expr, variable: "x", context: context) }

        func coefficient(_ n: Int, cosine: Bool, offset: Double) throws(MathError) -> Double {
            let k = Double(n) * omega
            var sum = 0.0
            for (i, f) in functions.enumerated() {
                sum += try Integrator.integrate({ x in
                    let u = kind == .full ? x : x - a
                    return (f(x) - offset) * (cosine ? cos(k * u) : sin(k * u))
                }, from: bounds[i], to: bounds[i + 1], tolerance: 1e-12)
            }
            return 2 / length * sum
        }

        var cosines = [Double](repeating: 0, count: count + 1)
        var sines = cosines
        if kind != .sine { cosines[0] = try coefficient(0, cosine: true, offset: 0) }
        // The harmonics of f − a₀/2: the constant integrates to zero over the period, so a large
        // mean adds no quadrature noise to them (the sine series has no a₀).
        let offset = cosines[0] / 2
        for n in 1...count {
            if kind != .sine { cosines[n] = try coefficient(n, cosine: true, offset: offset) }
            if kind != .cosine { sines[n] = try coefficient(n, cosine: false, offset: offset) }
        }
        guard (cosines + sines).allSatisfy(\.isFinite) else { throw .domain("funkcija ni integrabilna na intervalu") }
        let scale = (cosines + sines).map(Swift.abs).max() ?? 0
        // Noise is zero: quadrature noise next to the largest harmonic, and the rounding of the
        // values of f, which grows with its mean.
        let harmonics = (cosines.dropFirst() + sines).map(Swift.abs).max() ?? 0
        let noise = Swift.max(1e-11 * harmonics, 1e-13 * Swift.abs(cosines[0]))
        func tidy(_ v: Double) -> Double { Swift.abs(v) <= noise ? 0 : NumericCalculus.clean(v) }
        var series = Series(kind: kind, start: a, length: length, omega: omega,
                            a: [NumericCalculus.clean(cosines[0])] + cosines.dropFirst().map(tidy), b: sines.map(tidy),
                            a0Formula: nil, anFormula: nil, bnFormula: nil, exceptions: [])

        var exceptions = Set<Int>()
        if kind != .sine {
            if let f = meanFormula(pieces, start: start),
               let v = try? RealEvaluator.evaluate(f, context: context), Swift.abs(v - series.a[0]) <= 1e-8 * Swift.max(1, scale) {
                series.a0Formula = f
            }
            if let f = formula(pieces, start: start, kind: kind, cosine: true),
               let check = verify(f, against: series.a, scale: scale, parameters: parameters) {
                series.anFormula = f
                exceptions.formUnion(check)
            }
        }
        if kind != .cosine, let f = formula(pieces, start: start, kind: kind, cosine: false),
           let check = verify(f, against: series.b, scale: scale, parameters: parameters) {
            series.bnFormula = f
            exceptions.formUnion(check)
        }
        series.exceptions = exceptions.sorted()
        return series
    }

    // MARK: Closed forms

    /// (2/L)·∫ f(x)·cos(nωu) dx (or sin) piece by piece with n left as a symbol, simplified with
    /// sin(kπn) = 0 and cos(kπn) = (−1)^(kn).
    static func formula(_ pieces: [Piece], start: Expr, kind: Kind, cosine: Bool) -> Expr? {
        guard let end = pieces.last?.end else { return nil }
        let length = Simplifier.simplify(.sum([end, .negation(start)]))
        let omega = Simplifier.simplify(.product([kind == .full ? .int(2) : .one, .constant(.pi), .power(length, .int(-1))]))
        let phase: Expr = kind == .full ? .variable("x") : .sum([.variable("x"), .negation(start)])
        let argument = Expr.product([.variable("n"), omega, phase])
        var terms: [Expr] = []
        var lower = start
        for piece in pieces {
            let integrand = Simplifier.simplify(.product([piece.expr, .function(cosine ? .cos : .sin, [argument])]))
            guard let F = Antiderivative.integrate(integrand, variable: "x") else { return nil }
            terms.append(F.substituting("x", with: piece.end))
            terms.append(.negation(F.substituting("x", with: lower)))
            lower = piece.end
        }
        let raw = Simplifier.simplify(.product([.int(2), .power(length, .int(-1)), .sum(terms)]))
        return Simplifier.simplify(integerRules(raw))
    }

    /// a₀ = (2/L)·∫ f dx.
    static func meanFormula(_ pieces: [Piece], start: Expr) -> Expr? {
        guard let end = pieces.last?.end else { return nil }
        var terms: [Expr] = []
        var lower = start
        for piece in pieces {
            guard let F = Antiderivative.integrate(piece.expr, variable: "x") else { return nil }
            terms.append(F.substituting("x", with: piece.end))
            terms.append(.negation(F.substituting("x", with: lower)))
            lower = piece.end
        }
        let result = Simplifier.simplify(.product([.int(2), .power(.sum([end, .negation(start)]), .int(-1)), .sum(terms)]))
        return result.freeVariables.isEmpty ? result : nil
    }

    /// sin(kπn) = 0 and cos(kπn) = (−1)^(kn) for whole numbers k and n.
    static func integerRules(_ e: Expr) -> Expr {
        let inner = e.mapChildren(integerRules)
        guard case .function(let f, let args) = inner, f == .sin || f == .cos, args.count == 1, args[0].dependsOn("n") else { return inner }
        let ratio = Simplifier.simplify(.product([args[0], .power(.product([.constant(.pi), .variable("n")]), .int(-1))]))
        guard let k = ratio.rationalValue, k.isInteger else { return inner }
        if f == .sin { return .zero }
        return k.numerator % 2 == 0 ? .one : .power(.int(-1), .variable("n"))
    }

    /// The n (of 1 … 8) where the formula is undefined, when it matches the numerical
    /// coefficients everywhere else; nil when it does not.
    static func verify(_ formula: Expr, against values: [Double], scale: Double, parameters: [String: Double]) -> [Int]? {
        guard formula.freeVariables.subtracting(parameters.keys).isSubset(of: Set(["n"])) else { return nil }
        var exceptions: [Int] = []
        for n in 1...8 {
            var context = EvaluationContext(variables: parameters)
            context.variables["n"] = Double(n)
            guard let v = try? RealEvaluator.evaluate(formula, context: context), v.isFinite else {
                exceptions.append(n)
                continue
            }
            guard Swift.abs(v - values[n]) <= 1e-8 * Swift.max(1, scale) else { return nil }
        }
        return exceptions.count <= 2 ? exceptions : nil
    }

    /// A coefficient as a short closed form: p/q, p/(qπ), p/(qπ²) or (p/q)·π.
    public static func recognize(_ value: Double) -> Expr? {
        guard value.isFinite else { return nil }
        if value == 0 { return .zero }
        let units: [(factor: Double, unit: Expr)] = [
            (1, .one), (Double.pi, .power(.constant(.pi), .int(-1))),
            (Double.pi * Double.pi, .power(.constant(.pi), .int(-2))), (1 / Double.pi, .constant(.pi)),
        ]
        for (factor, unit) in units {
            if let r = Rational.approximating(value * factor, maxDenominator: 360, tolerance: 1e-11),
               Swift.abs(r.doubleValue / factor - value) <= 1e-10 * Swift.max(1, Swift.abs(value)) {
                return Simplifier.simplify(.product([.number(r), unit]))
            }
        }
        return nil
    }

    // MARK: Graph

    /// f repeated with the period (full series), or extended oddly (sine) or evenly (cosine)
    /// to [a − L, a + L] and repeated: the function the series converges to between jumps.
    public static func periodicExtension(_ pieces: [Piece], start: Expr, kind: Kind) -> Expr {
        let x = Expr.variable("x")
        let length = Simplifier.simplify(.sum([pieces.last?.end ?? .one, .negation(start)]))
        func reduced(_ s: Expr, period: Expr, from offset: Expr) -> Expr {
            // s − T·floor((s − offset)/T) lies in [offset, offset + T).
            .sum([s, .negation(.product([period, .function(.floor, [.product([.sum([s, .negation(offset)]), .power(period, .int(-1))])])]))])
        }
        func f(at u: Expr) -> Expr {
            var parts: [Expr] = []
            for (i, piece) in pieces.enumerated() {
                parts.append(piece.expr.substituting("x", with: u))
                if i < pieces.count - 1 { parts.append(.relation(u, .less, piece.end)) }
            }
            return parts.count == 1 ? parts[0] : .piecewise(parts)
        }
        switch kind {
        case .full:
            return f(at: reduced(x, period: length, from: start))
        case .sine, .cosine:
            // w ∈ [−L, L) is x − a reduced with the period 2L; f is read at a + |w|.
            let w = reduced(.sum([x, .negation(start)]), period: .product([.int(2), length]), from: .negation(length))
            let value = f(at: .sum([start, .function(.abs, [w])]))
            return kind == .sine ? .product([.function(.sign, [w]), value]) : value
        }
    }
}
