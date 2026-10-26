import Foundation

/// The solution set of an inequality in one unknown, as intervals.
public struct InequalitySolution: Sendable, Hashable {
    public struct Interval: Sendable, Hashable {
        public var lower: Double
        public var upper: Double
        public var lowerIncluded: Bool
        public var upperIncluded: Bool
        public var exactLower: ExactReal?
        public var exactUpper: ExactReal?

        public var isPoint: Bool { lower == upper }
    }

    public var variable: String
    public var intervals: [Interval]
    /// Trigonometric inequalities repeat: every interval + k·period.
    public var period: Double?

    public var isEmpty: Bool { intervals.isEmpty }

    /// Values that satisfy both (systems and chains of inequalities in one unknown).
    public func intersection(_ other: InequalitySolution) -> InequalitySolution? {
        guard period == nil, other.period == nil, variable == other.variable else { return nil }
        var result: [Interval] = []
        for a in intervals {
            for b in other.intervals {
                let lower: (Double, Bool, ExactReal?) = a.lower > b.lower ? (a.lower, a.lowerIncluded, a.exactLower)
                    : b.lower > a.lower ? (b.lower, b.lowerIncluded, b.exactLower)
                    : (a.lower, a.lowerIncluded && b.lowerIncluded, a.exactLower ?? b.exactLower)
                let upper: (Double, Bool, ExactReal?) = a.upper < b.upper ? (a.upper, a.upperIncluded, a.exactUpper)
                    : b.upper < a.upper ? (b.upper, b.upperIncluded, b.exactUpper)
                    : (a.upper, a.upperIncluded && b.upperIncluded, a.exactUpper ?? b.exactUpper)
                guard lower.0 < upper.0 || (lower.0 == upper.0 && lower.1 && upper.1) else { continue }
                result.append(Interval(lower: lower.0, upper: upper.0, lowerIncluded: lower.1, upperIncluded: upper.1,
                                       exactLower: lower.2, exactUpper: upper.2))
            }
        }
        return InequalitySolution(variable: variable, intervals: result.sorted { $0.lower < $1.lower }, period: nil)
    }
    public var isAllReals: Bool {
        intervals.count == 1 && intervals[0].lower == -.infinity && intervals[0].upper == .infinity && period == nil
    }
}

/// Solves f(x) < g(x) (≤, >, ≥) from the zeros, poles and domain edges of f − g: the sign is
/// tested between them, zeros belong to the solution of ≤ and ≥, poles never do.
public enum InequalitySolver {
    /// Several inequalities at once (a system, or the links of a chain a < f(x) ≤ b):
    /// the intersection of their solutions.
    public static func solve(_ links: [(Expr, RelationOperator, Expr)], variable: String = "x", context: EvaluationContext) -> InequalitySolution? {
        var combined: InequalitySolution?
        for (lhs, op, rhs) in links {
            guard let solution = solve(lhs, op, rhs, variable: variable, context: context) else { return nil }
            if let current = combined {
                guard let both = current.intersection(solution) else { return nil }
                combined = both
            } else {
                combined = solution
            }
        }
        return combined
    }

    public static func solve(_ lhs: Expr, _ op: RelationOperator, _ rhs: Expr, variable: String = "x",
                             context: EvaluationContext) -> InequalitySolution? {
        let strict: Bool
        let positive: Bool
        switch op {
        case .less: (strict, positive) = (true, false)
        case .lessOrEqual: (strict, positive) = (false, false)
        case .greater: (strict, positive) = (true, true)
        case .greaterOrEqual: (strict, positive) = (false, true)
        case .equal, .notEqual: return nil
        }
        let difference = Simplifier.simplify(.sum([lhs, .negation(rhs)]))
        guard difference.dependsOn(variable),
              let equation = try? EquationSolver.solve(lhs: difference, rhs: .zero, variable: variable, context: context) else { return nil }
        let f = FunctionAnalyzer.makeFunction(difference, variable: variable, context: context)
        let period = equation.period
        let range: ClosedRange<Double> = period.map { 0...$0 } ?? (equation.searchedRange ?? -1000...1000)
        func holds(_ v: Double) -> Bool { v.isFinite && (positive ? v > 0 : v < 0) }

        // Critical points: zeros (exact where possible), poles and edges of the domain. Only one period
        // limits the zeros; roots beyond the sampled range (x > 2000) bound the pieces as well.
        struct Critical { var x: Double; var exact: ExactReal?; var included: Bool }
        var critical: [Critical] = equation.solutions.filter { period == nil || range.contains($0.value) }.map {
            Critical(x: $0.value, exact: $0.exact, included: !strict)
        }
        // A zero of a denominator never belongs to the solution, even where f − g seemed to vanish.
        for pole in denominatorZeros(difference, variable: variable, in: range, periodic: period != nil, context: context) {
            if let i = critical.firstIndex(where: { Swift.abs($0.x - pole.x) < 1e-9 }) {
                critical[i].included = false
            } else {
                critical.append(Critical(x: pole.x, exact: pole.exact ?? ExactRecognizer.recognize(pole.x, tolerance: 1e-9), included: false))
            }
        }
        for pole in signBreaks(f, in: range, zeros: critical.map(\.x)) where !critical.contains(where: { Swift.abs($0.x - pole) < 1e-9 }) {
            critical.append(Critical(x: pole, exact: ExactRecognizer.recognize(pole, tolerance: 1e-9), included: false))
        }
        for edge in domainEdges(f, in: range) where !critical.contains(where: { Swift.abs($0.x - edge) < 1e-7 }) {
            let value = f(edge)
            critical.append(Critical(x: edge, exact: ExactRecognizer.recognize(edge, tolerance: 1e-9),
                                     included: value.isFinite && (holds(value) || (!strict && Swift.abs(value) < 1e-12))))
        }
        critical.sort { $0.x < $1.x }

        // Pieces between the critical points (to ±∞ unless periodic).
        let low = period == nil ? -Double.infinity : range.lowerBound
        let high = period == nil ? Double.infinity : range.upperBound
        let bounds = [low] + critical.map(\.x) + [high]
        func sample(_ a: Double, _ b: Double) -> Double {
            if a == -.infinity { return b == .infinity ? 0 : b - Swift.max(1, Swift.abs(b)) }
            if b == .infinity { return a + Swift.max(1, Swift.abs(a)) }
            return (a + b) / 2
        }
        var intervals: [InequalitySolution.Interval] = []
        for i in 0..<(bounds.count - 1) {
            let a = bounds[i], b = bounds[i + 1]
            guard b > a else { continue }
            // An overflowed value (eˣ beyond x ≈ 709.8) still has its sign; NaN fails both comparisons.
            let value = f(sample(a, b))
            guard positive ? value > 0 : value < 0 else { continue }
            let left = i > 0 ? critical[i - 1] : nil
            let right = i < critical.count ? critical[i] : nil
            var piece = InequalitySolution.Interval(lower: a, upper: b,
                                                    lowerIncluded: left?.included ?? (period != nil && holds(f(a))),
                                                    upperIncluded: right?.included ?? false,
                                                    exactLower: left?.exact, exactUpper: right?.exact)
            // Join with the previous piece when they share an included end.
            if var last = intervals.last, last.upper == a, last.upperIncluded || piece.lowerIncluded {
                last.upper = b
                last.upperIncluded = piece.upperIncluded
                last.exactUpper = piece.exactUpper
                intervals[intervals.count - 1] = last
                continue
            }
            if period != nil, i == bounds.count - 2 { piece.upperIncluded = piece.upperIncluded || holds(f(b)) }
            intervals.append(piece)
        }
        // Isolated points (x² ≤ 0 → x = 0): included zeros not inside any interval.
        if !strict {
            for c in critical where c.included && !intervals.contains(where: { $0.lower <= c.x && c.x <= $0.upper }) {
                intervals.append(InequalitySolution.Interval(lower: c.x, upper: c.x, lowerIncluded: true, upperIncluded: true,
                                                            exactLower: c.exact, exactUpper: c.exact))
            }
            intervals.sort { $0.lower < $1.lower }
        }
        return InequalitySolution(variable: variable, intervals: intervals, period: period)
    }

    /// Zeros of the denominators of f (quotients, negative powers, tan/sec → cos, cot/csc → sin,
    /// coth/csch → sinh), where f is undefined. Solved from the denominators themselves (exactly for
    /// polynomials): a pole in the same gap of the sign scan as a zero of f shows no sign change, so
    /// (4x − 1)/(3x − 1) ≥ 0 lost its pole 1/3. Decimal exponents such as x^(−2,0) are exact after parsing.
    static func denominatorZeros(_ expr: Expr, variable: String, in range: ClosedRange<Double>, periodic: Bool,
                                 context: EvaluationContext) -> [(x: Double, exact: ExactReal?)] {
        var denominators: [Expr] = []
        func collect(_ e: Expr) {
            switch e {
            case .quotient(_, let d): denominators.append(d)
            case .power(let b, let x):
                if let r = x.rationalValue, r.isNegative { denominators.append(b) }
            case .function(.cot, let args), .function(.csc, let args): denominators.append(.function(.sin, args))
            case .function(.tan, let args), .function(.sec, let args): denominators.append(.function(.cos, args))
            case .function(.coth, let args), .function(.csch, let args): denominators.append(.function(.sinh, args))
            default: break
            }
            for c in e.children { collect(c) }
        }
        collect(expr)
        var zeros: [(x: Double, exact: ExactReal?)] = []
        for d in denominators where d.dependsOn(variable) {
            guard let solved = try? EquationSolver.solve(lhs: d, rhs: .zero, variable: variable, context: context) else { continue }
            for solution in solved.solutions {
                if let p = solved.period {
                    // Every repetition inside the sampled range; one at the end of f's period may round
                    // just outside it (cot x < 0 must still exclude x = π).
                    let slack = periodic ? 1e-9 : 0.0
                    let first = ((range.lowerBound - solution.value) / p - slack).rounded(.up)
                    let last = ((range.upperBound - solution.value) / p + slack).rounded(.down)
                    guard first <= last, last - first < 10_000, Swift.abs(first) < 1e9 else { continue }
                    for k in Int(first)...Int(last) {
                        let x = Swift.min(Swift.max(solution.value + Double(k) * p, range.lowerBound), range.upperBound)
                        zeros.append((x, k == 0 ? solution.exact : nil))
                    }
                } else if !periodic || range.contains(solution.value) {
                    zeros.append((solution.value, solution.exact))
                }
            }
        }
        return zeros
    }

    /// Poles and jumps: f changes sign without passing through a zero, or is undefined at a
    /// single grid point between defined neighbours. Located by bisection on the sign.
    static func signBreaks(_ f: (Double) -> Double, in range: ClosedRange<Double>, zeros: [Double], samples: Int = 4000) -> [Double] {
        let step = (range.upperBound - range.lowerBound) / Double(samples)
        func isZero(_ c: Double) -> Bool { zeros.contains { Swift.abs($0 - c) < 1e-6 * Swift.max(1, Swift.abs(c)) } }
        var breaks: [Double] = []
        var previousX = range.lowerBound
        var previous = f(previousX)
        for i in 1...samples {
            let x = range.lowerBound + Double(i) * step
            let value = f(x)
            if previous.isFinite, value.isFinite, previous != 0, value != 0, (previous < 0) != (value < 0) {
                var a = previousX, b = x
                let signA = previous < 0
                for _ in 0..<80 {
                    let m = (a + b) / 2
                    let fm = f(m)
                    if !fm.isFinite { a = m; b = m; break }
                    if (fm < 0) == signA { a = m } else { b = m }
                }
                let c = (a + b) / 2
                if !isZero(c) { breaks.append(c) }
            } else if !value.isFinite, previous.isFinite, f(x + step).isFinite, !isZero(x) {
                breaks.append(x)
            }
            previousX = x
            previous = value
        }
        return breaks
    }

    /// Where f switches between defined and undefined (√x at 0, ln x at 0 …), found by bisection.
    /// Only NaN is undefined: eˣ overflowing to ∞ beyond x ≈ 709.8 is no edge of its domain.
    static func domainEdges(_ f: (Double) -> Double, in range: ClosedRange<Double>, samples: Int = 4000) -> [Double] {
        let step = (range.upperBound - range.lowerBound) / Double(samples)
        var edges: [Double] = []
        var previousX = range.lowerBound
        var previousDefined = !f(previousX).isNaN
        for i in 1...samples {
            let x = range.lowerBound + Double(i) * step
            let defined = !f(x).isNaN
            if defined != previousDefined {
                // Bisect towards the defined side.
                var inside = defined ? x : previousX
                var outside = defined ? previousX : x
                for _ in 0..<80 {
                    let mid = (inside + outside) / 2
                    if !f(mid).isNaN { inside = mid } else { outside = mid }
                }
                // A single undefined point (a pole) is not an edge of the domain.
                let probe = inside + (outside - inside) * 4
                if f(probe).isNaN || f(outside + (outside - inside) * 4).isNaN { edges.append(inside) }
            }
            previousX = x
            previousDefined = defined
        }
        // Snap to exact values (the edge of √x is 0, not 1e-20).
        return edges.map { edge in
            if let exact = ExactRecognizer.recognize(edge, tolerance: 1e-9), Swift.abs(exact.doubleValue - edge) < 1e-7 {
                return exact.doubleValue
            }
            return edge
        }
    }
}
