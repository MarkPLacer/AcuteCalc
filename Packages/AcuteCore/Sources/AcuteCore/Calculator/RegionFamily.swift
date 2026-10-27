import Foundation

/// A system with a condition on its index, `…, n ∈ ℕ`: the other parts, the index and its first value.
public struct IndexedSystem: Sendable, Hashable {
    /// The parts besides the condition (the inequalities of a region, or a sequence term).
    public var parts: [Expr]
    /// The index, usually n.
    public var index: String
    /// The first value of the index: 1 for n ∈ ℕ, 0 for n ∈ ℕ₀, a for n = a, a + 1, …
    public var start: Int

    public init(parts: [Expr], index: String, start: Int) {
        self.parts = parts
        self.index = index
        self.start = start
    }
}

extension Parser {
    /// The parts of a system with one condition that lets its index run over the integers from a
    /// first value: `n ∈ ℕ` (1, 2, …), `n ∈ ℕ₀` (0, 1, …), `n = 1, 2, …` or `n ∈ {1, 2, 3, …}`,
    /// anywhere among the parts (text may write `n in N`, `N_0` and `...`). Nil without such a
    /// condition; an error when there is one but the rest does not parse or never uses the index.
    public static func parseIndexedSystem(tokens: [Token], options: ParserOptions = ParserOptions()) throws(MathError) -> IndexedSystem? {
        let parts = systemParts(tokens)
        var condition: (index: String, start: Int, parts: Range<Int>)?
        var i = 0
        while i < parts.count {
            // `n ∈` while typing the set.
            if parts[i].count == 2, indexName(parts[i][0]) != nil, isElementSign(parts[i][1]) { throw .incomplete }
            guard let found = indexCondition(parts, at: i) else {
                i += 1
                continue
            }
            guard condition == nil else { throw .syntax("indeks je lahko podan le enkrat") }
            condition = found
            i = found.parts.upperBound
        }
        guard let condition else { return nil }
        var rest = parts
        rest.removeSubrange(condition.parts)
        guard !rest.isEmpty, rest.allSatisfy({ !$0.isEmpty }) else { throw .incomplete }
        var exprs: [Expr] = []
        for part in rest { exprs.append(try parse(tokens: part, options: options)) }
        guard exprs.contains(where: { $0.dependsOn(condition.index) }) else {
            throw .syntax("izraz ne vsebuje indeksa \(condition.index)")
        }
        return IndexedSystem(parts: exprs, index: condition.index, start: condition.start)
    }

    /// `n ∈ ℕ`, `n ∈ ℕ₀` or `n ∈ {a, a + 1, …}` in part `i`, or `n = a, a + 1, …` from part `i` on.
    private static func indexCondition(_ parts: [[Token]], at i: Int) -> (index: String, start: Int, parts: Range<Int>)? {
        let part = parts[i]
        guard part.count >= 3, let index = indexName(part[0]) else { return nil }
        let rest = Array(part.dropFirst(2))
        if isElementSign(part[1]) {
            if let start = naturalsStart(rest) { return (index, start, i..<(i + 1)) }
            // {1, 2, 3, …}: the lexer reads braces as parentheses.
            guard rest.count >= 3, rest.first?.opValue == "(", rest.last?.opValue == ")",
                  let start = runStart(systemParts(Array(rest.dropFirst().dropLast()))) else { return nil }
            return (index, start, i..<(i + 1))
        }
        guard part[1].opValue == "=" else { return nil }
        // n = 1, 2, …: the values go on in the following parts, up to the ellipsis.
        var values = [rest]
        var end = i + 1
        while values.last?.last?.opValue != "…", end < parts.count {
            values.append(parts[end])
            end += 1
        }
        guard let start = runStart(values) else { return nil }
        return (index, start, i..<end)
    }

    /// The first of consecutive integers `a, a + 1, …` that end with an ellipsis.
    private static func runStart(_ items: [[Token]]) -> Int? {
        guard var last = items.last, last.last?.opValue == "…" else { return nil }
        last.removeLast()
        var values: [Int] = []
        for item in items.dropLast() + (last.isEmpty ? [] : [last]) {
            guard let value = integer(item) else { return nil }
            values.append(value)
        }
        guard let first = values.first, zip(values, values.dropFirst()).allSatisfy({ $1 == $0 + 1 }) else { return nil }
        return first
    }

    private static func integer(_ tokens: [Token]) -> Int? {
        let negative = tokens.first?.opValue == "-"
        let digits = negative ? Array(tokens.dropFirst()) : tokens
        guard digits.count == 1, case .number(let text) = digits[0], let value = Int(text), value <= 1_000_000 else { return nil }
        return negative ? -value : value
    }

    /// ℕ (or N) starts at 1, ℕ₀ (or N₀) at 0.
    private static func naturalsStart(_ tokens: [Token]) -> Int? {
        var name: String?
        if tokens.count == 1 { name = word(tokens[0]) }
        if tokens.count == 2, let base = word(tokens[0]), case .sub(let s) = tokens[1] { name = base + "_" + s }
        switch name {
        case "ℕ", "N": return 1
        case "ℕ_0", "N_0": return 0
        default: return nil
        }
    }

    /// A one-letter index other than x, y, z, e, i and the number sets.
    private static func indexName(_ token: Token) -> String? {
        guard let name = word(token), name.count == 1, name.first?.isLetter == true,
              !["x", "y", "z", "e", "i", "N", "ℕ", "ℤ", "ℚ", "ℝ", "ℂ"].contains(name) else { return nil }
        return name
    }

    private static func isElementSign(_ token: Token) -> Bool {
        token.opValue == "∈" || token == .identifier("in")
    }

    /// Typed text gives identifiers, the math editor variable structures.
    private static func word(_ token: Token) -> String? {
        switch token {
        case .identifier(let name): name
        case .structure(.variable(let name)): name
        default: nil
        }
    }
}

/// D₁ ∪ D₂ ∪ …: a region D_n for every n = start, start + 1, …, typed as the inequalities of D_n
/// with a condition on the index, e.g. (x − n)² + y² ≤ 2^(−n−1), n ∈ ℕ.
public struct RegionFamily: Sendable, Hashable {
    /// The inequalities of D_n, in x, y and the index.
    public var relations: [Expr]
    public var index: String
    public var start: Int
    /// D_n = {gap ≥ 0}, or {gap > 0} when every inequality is strict: the least margin of its inequalities.
    public var gap: Expr
    public var strict: Bool
    /// The same region for measuring it: a disc or an ellipse given by its radius (√Q ≤ R,
    /// |z − c| ≤ R) as the quadratic R·|R| − Q ≥ 0.
    var measuredGap: Expr

    static let notARegion = MathError.unsupported("neskončna unija je mogoča za območja, podana z neenačbami v x in y")

    /// The members of an indexed system; an error unless its parts are inequalities in x and y
    /// (chains and sets of complex numbers included).
    public init(_ system: IndexedSystem) throws(MathError) {
        var gaps: [Expr] = []
        var strict = true
        for relation in system.parts {
            guard case .relation(var lhs, let op, var rhs) = relation else { throw Self.notARegion }
            if case .relation = lhs {
                guard let chain = PlaneSets.chainRegion(relation) else { throw Self.notARegion }
                gaps.append(chain.lhs)
                if chain.relation != .greater { strict = false }
                continue
            }
            if PlaneSets.isComplexSet(relation) {
                guard let real = PlaneSets.complexRelation(lhs, rhs) else { throw Self.notARegion }
                lhs = real.lhs
                rhs = real.rhs
            }
            switch op {
            case .less, .lessOrEqual: gaps.append(rhs - lhs)
            case .greater, .greaterOrEqual: gaps.append(lhs - rhs)
            case .equal, .notEqual: throw Self.notARegion
            }
            if op == .lessOrEqual || op == .greaterOrEqual { strict = false }
        }
        let gap = gaps.count == 1 ? gaps[0] : Expr.function(.min, gaps)
        guard gap.dependsOn("x") || gap.dependsOn("y") else { throw Self.notARegion }
        guard gap.dependsOn(system.index) else { throw .syntax("območje ne vsebuje indeksa \(system.index)") }
        relations = system.parts
        index = system.index
        start = system.start
        self.gap = gap
        self.strict = strict
        measuredGap = gaps.count == 1 && system.parts.count == 1 ? Self.squaredRadius(gap) ?? gap : gap
    }

    /// R − √Q (also R − |w|) with R free of x and y as R·|R| − Q: the same points, as a quadratic.
    static func squaredRadius(_ gap: Expr) -> Expr? {
        guard case .sum(let terms) = gap, terms.count == 2, case .negation(let root) = terms[1],
              !terms[0].dependsOn("x"), !terms[0].dependsOn("y") else { return nil }
        let radius = terms[0]
        let square: Expr
        switch root {
        case .function(.sqrt, let args) where args.count == 1: square = args[0]
        case .power(let base, .number(let exponent)) where exponent == .half: square = base
        case .function(.abs, let args) where args.count == 1: square = .power(args[0], .int(2))
        default: return nil
        }
        return .product([radius, .function(.abs, [radius])]) - square
    }

    /// Members examined at most (pairs, areas, the members drawn).
    static let memberLimit = 4096
}

// MARK: Members

extension RegionFamily {
    /// A member D_k that is an ellipse (a disc in particular): the points p with
    /// (p − center)ᵀ S⁻¹ (p − center) ≤ 1 for the shape matrix S = [[sxx, sxy], [sxy, syy]].
    public struct Ellipse: Sendable, Hashable {
        public var center: SIMD2<Double>
        public var sxx: Double
        public var sxy: Double
        public var syy: Double

        public init(center: SIMD2<Double>, sxx: Double, sxy: Double, syy: Double) {
            self.center = center
            self.sxx = sxx
            self.sxy = sxy
            self.syy = syy
        }

        /// A disc.
        public init(center: SIMD2<Double>, radius: Double) {
            self.init(center: center, sxx: radius * radius, sxy: 0, syy: radius * radius)
        }

        public var area: Double { .pi * Swift.max(0, sxx * syy - sxy * sxy).squareRoot() }

        /// Half the width and half the height of the bounding box.
        public var halfSize: SIMD2<Double> { SIMD2(sxx.squareRoot(), syy.squareRoot()) }

        /// Whether the interiors meet (touching is not overlapping), by Perram and Wertheim's
        /// criterion: they do iff the maximum over λ ∈ [0, 1] of λ(1 − λ)·rᵀ((1 − λ)S₁ + λS₂)⁻¹r,
        /// r joining the centres, is below 1. The function is concave, so a golden-section search finds it.
        public func overlaps(_ other: Ellipse) -> Bool {
            let r = other.center - center
            func f(_ l: Double) -> Double {
                let m11 = (1 - l) * sxx + l * other.sxx
                let m12 = (1 - l) * sxy + l * other.sxy
                let m22 = (1 - l) * syy + l * other.syy
                let det = m11 * m22 - m12 * m12
                return l * (1 - l) * (m22 * r.x * r.x - 2 * m12 * r.x * r.y + m11 * r.y * r.y) / det
            }
            let golden = (5.0.squareRoot() - 1) / 2
            var low = 0.0, high = 1.0
            var x1 = high - golden, x2 = golden
            var f1 = f(x1), f2 = f(x2)
            for _ in 0..<80 {
                if f1 < f2 {
                    low = x1
                    x1 = x2
                    f1 = f2
                    x2 = low + golden * (high - low)
                    f2 = f(x2)
                } else {
                    high = x2
                    x2 = x1
                    f2 = f1
                    x1 = high - golden * (high - low)
                    f1 = f(x1)
                }
            }
            return Swift.max(f1, f2) < 1 - 1e-9
        }
    }

    /// One member, as far as its area and extent go.
    public enum Member: Sendable, Hashable {
        case ellipse(Ellipse)
        /// No point, or a single one.
        case empty
        /// Not an ellipse: its area and extent are not known.
        case other
    }

    /// D_k (any real k), see `Probe.member`.
    public func member(_ k: Double, parameters: [String: Double] = [:]) -> Member {
        (try? Probe(self, parameters: parameters))?.member(k) ?? .other
    }

    /// a·u² + b·uv + c·v² + d·u + e·v + f around the point of a fit.
    struct Quadratic {
        var a, b, c, d, e, f: Double

        /// The quadratic part is negative definite: an ellipse where the value is positive.
        var isNegativeDefinite: Bool { a < 0 && c < 0 && 4 * a * c - b * b > 1e-12 * (a * a + c * c) }

        /// Where the gradient vanishes, relative to the point of the fit.
        var vertex: SIMD2<Double> {
            let det = 4 * a * c - b * b
            return SIMD2((b * e - 2 * c * d) / det, (b * d - 2 * a * e) / det)
        }
    }

    /// Evaluates the measured gap of D_t for any real t.
    struct Probe {
        private var vm: RealVM

        init(_ family: RegionFamily, parameters: [String: Double]) throws(MathError) {
            var slots: [String: VariableSlot] = ["x": .x, "y": .y, family.index: .parameter(0)]
            var values = [0.0]
            for name in family.measuredGap.freeVariables.subtracting(["x", "y", family.index]).sorted() {
                guard let value = parameters[name] else { throw .undefinedVariable(name) }
                slots[name] = .parameter(values.count)
                values.append(value)
            }
            vm = RealVM(program: try BytecodeCompiler(slots: slots).compile(family.measuredGap), parameters: values)
        }

        /// D_t from second differences of its gap g with steps of 1 (exact for a quadratic): an ellipse
        /// when the quadratic part is negative definite and g is that quadratic at other points too.
        /// Newton steps move the centre to where it carries all its digits, so g there (the
        /// greatest value) is exact even for a tiny member far from the origin.
        func member(_ t: Double) -> Member {
            var vm = self.vm
            vm.parameters[0] = t
            func g(_ p: SIMD2<Double>) -> Double { vm.evaluate(x: p.x, y: p.y) }
            func fit(_ p: SIMD2<Double>) -> Quadratic? {
                let f0 = g(p), xp = g(p + SIMD2(1, 0)), xm = g(p - SIMD2(1, 0))
                let yp = g(p + SIMD2(0, 1)), ym = g(p - SIMD2(0, 1)), xy = g(p + SIMD2(1, 1))
                guard [f0, xp, xm, yp, ym, xy].allSatisfy(\.isFinite) else { return nil }
                return Quadratic(a: (xp - 2 * f0 + xm) / 2, b: xy - xp - yp + f0, c: (yp - 2 * f0 + ym) / 2,
                                 d: (xp - xm) / 2, e: (yp - ym) / 2, f: f0)
            }
            guard let first = fit(.zero), first.isNegativeDefinite else { return .other }
            var center = first.vertex
            for _ in 0..<8 {
                guard let local = fit(center), local.isNegativeDefinite else { return .other }
                let step = local.vertex
                guard step.x.isFinite, step.y.isFinite else { return .other }
                center += step
                if Swift.abs(step.x) + Swift.abs(step.y) <= 1e-15 * (1 + Swift.abs(center.x) + Swift.abs(center.y)) { break }
            }
            guard let q = fit(center), q.isNegativeDefinite else { return .other }
            let g0 = q.f
            // The quadratic must hold away from the points of the fit as well (a polynomial of degree 2).
            for (u, v) in [(0.6, 0.3), (-1.3, 0.8), (2.2, -1.7), (-0.4, -2.9), (6.5, 4.1), (-9.1, 1.6)] {
                let p = center + SIMD2(u, v)
                let du = p.x - center.x, dv = p.y - center.y
                let terms = [g0, q.a * du * du, q.b * du * dv, q.c * dv * dv, q.d * du, q.e * dv]
                let model = terms.reduce(0, +)
                let magnitude = terms.reduce(0) { $0 + Swift.abs($1) }
                let value = g(p)
                guard value.isFinite, Swift.abs(value - model) <= 1e-8 * magnitude else { return .other }
            }
            guard g0 > 0 else { return .empty }
            let scale = g0 / (q.a * q.c - q.b * q.b / 4)
            return .ellipse(Ellipse(center: center, sxx: -q.c * scale, sxy: q.b / 2 * scale, syy: -q.a * scale))
        }
    }

    /// The exact area of D_k (rational, surd and π arithmetic), when its gap evaluates exactly.
    /// Only for a member already found to be an ellipse: the same differences as `Probe.member`.
    func exactArea(_ k: Int) -> ExactReal? {
        guard measuredGap.freeVariables.isSubset(of: ["x", "y", index]) else { return nil }
        func g(_ x: Int, _ y: Int) -> ExactReal? {
            ExactEvaluator.value(measuredGap, angleUnit: .radians, variables: ["x": ExactReal(x), "y": ExactReal(y), index: ExactReal(k)])
        }
        let half = ExactReal(Rational.half)
        let two = ExactReal(2)
        guard let f0 = g(0, 0), let xp = g(1, 0), let xm = g(-1, 0), let yp = g(0, 1), let ym = g(0, -1), let xy = g(1, 1),
              let twice = f0.multiplied(by: two),
              let a = xp.adding(xm)?.subtracting(twice)?.multiplied(by: half),
              let c = yp.adding(ym)?.subtracting(twice)?.multiplied(by: half),
              let b = xy.subtracting(xp)?.subtracting(yp)?.adding(f0),
              let d = xp.subtracting(xm)?.multiplied(by: half),
              let e = yp.subtracting(ym)?.multiplied(by: half),
              let ac = a.multiplied(by: c), let bb = b.multiplied(by: b), let be = b.multiplied(by: e), let bd = b.multiplied(by: d),
              let cd2 = c.multiplied(by: d)?.multiplied(by: two), let ae2 = a.multiplied(by: e)?.multiplied(by: two),
              let det4 = ac.multiplied(by: ExactReal(4))?.subtracting(bb), det4.signum > 0,
              // The vertex (x₀, y₀) and the value there, f + (d·x₀ + e·y₀)/2.
              let x0 = be.subtracting(cd2)?.divided(by: det4), let y0 = bd.subtracting(ae2)?.divided(by: det4),
              let dx = d.multiplied(by: x0), let ey = e.multiplied(by: y0),
              let g0 = dx.adding(ey)?.multiplied(by: half)?.adding(f0) else { return nil }
        guard g0.signum > 0 else { return .zero }
        // π·g₀/√(ac − b²/4)
        guard let quarter = Rational(1, 4), let det = det4.multiplied(by: ExactReal(quarter)), let root = det.squareRoot(),
              let area = ExactReal.pi.multiplied(by: g0)?.divided(by: root) else { return nil }
        return area
    }
}

// MARK: Drawing

extension RegionFamily {
    /// The members to draw in a window, in index order: those that reach into it and are at least
    /// `minimumSize` across, up to `limit`; the scan stops after eight smaller (or empty) ones in a
    /// row. Members that are not ellipses have unknown extents: then simply the first `limit`.
    public func drawnMembers(x: ClosedRange<Double>, y: ClosedRange<Double>, minimumSize: Double,
                             parameters: [String: Double] = [:], limit: Int) -> [Int] {
        let first = Array(start..<(start + limit))
        guard let probe = try? Probe(self, parameters: parameters) else { return first }
        var members: [Int] = []
        var small = 0
        var k = start
        while members.count < limit, small < 8, k < start + Self.memberLimit {
            switch probe.member(Double(k)) {
            case .other:
                return first
            case .empty:
                small += 1
            case .ellipse(let e):
                let half = e.halfSize
                if 2 * Swift.max(half.x, half.y) < minimumSize {
                    small += 1
                } else {
                    small = 0
                    if e.center.x + half.x >= x.lowerBound, e.center.x - half.x <= x.upperBound,
                       e.center.y + half.y >= y.lowerBound, e.center.y - half.y <= y.upperBound {
                        members.append(k)
                    }
                }
            }
            k += 1
        }
        return members
    }

    /// A window that shows the members down to a fiftieth of the largest of the first 64
    /// (nil when they are not ellipses or all empty).
    public func frame(parameters: [String: Double] = [:]) -> (x: ClosedRange<Double>, y: ClosedRange<Double>)? {
        guard let probe = try? Probe(self, parameters: parameters) else { return nil }
        var shapes: [Ellipse] = []
        for k in start..<(start + 64) {
            switch probe.member(Double(k)) {
            case .ellipse(let e): shapes.append(e)
            case .empty: continue
            case .other: return nil
            }
        }
        guard let largest = shapes.map({ Swift.max($0.halfSize.x, $0.halfSize.y) }).max(), largest > 0 else { return nil }
        let shown = shapes.filter { Swift.max($0.halfSize.x, $0.halfSize.y) >= largest / 50 }
        let low = shown.map { $0.center - $0.halfSize }
        let high = shown.map { $0.center + $0.halfSize }
        guard let x0 = low.map(\.x).min(), let x1 = high.map(\.x).max(), let y0 = low.map(\.y).min(), let y1 = high.map(\.y).max() else { return nil }
        return (x0...x1, y0...y1)
    }
}

// MARK: Area

/// The area of D₁ ∪ D₂ ∪ … from the areas of its members.
public struct UnionArea: Sendable, Hashable {
    public enum Overlap: Sendable, Hashable {
        /// No two members overlap (touching is allowed).
        case disjoint
        /// D_i and D_j overlap: the sum of the areas is only an upper bound for the area of the union.
        case members(Int, Int)
        /// Too many pairs to check: the sum is only known to be an upper bound.
        case unknown
    }

    public var overlap: Overlap
    /// Σ area(D_n), +∞ when the series diverges.
    public var sum: Double
    /// The sum exactly (a geometric series with exact terms: π/2).
    public var exact: ExactReal?
    /// The sum lies within ± errorBound of `sum` (0 when exact, nil when no bound is known).
    public var errorBound: Double?
    /// The quotient of the areas, when they form a geometric series.
    public var ratio: Double?
    /// Members were checked pair by pair up to this index; the others together cover `remainder`.
    public var checkedThrough: Int
    public var remainder: Double

    /// The area of the union: the sum, when no two members overlap.
    public var area: Double? { overlap == .disjoint ? sum : nil }
}

extension RegionFamily {
    /// Most pairs of members tested for overlap.
    static let pairLimit = 200_000

    /// Σ area(D_n) and whether the members overlap: for members that do not, it is the area of
    /// the union. The members must be ellipses (discs); an error otherwise.
    public func area(parameters: [String: Double] = [:]) throws(MathError) -> UnionArea {
        let probe = try Probe(self, parameters: parameters)
        var ellipses: [Ellipse?] = []
        var areas: [Double] = []
        var total = 0.0
        var negligible = 0
        var complete = false
        while areas.count < Self.memberLimit {
            let ellipse: Ellipse?
            switch probe.member(Double(start + areas.count)) {
            case .ellipse(let e): ellipse = e
            case .empty: ellipse = nil
            case .other: throw .unsupported("ploščino unije znam izračunati, ko so D_n krogi ali elipse")
            }
            let a = ellipse?.area ?? 0
            guard a.isFinite else { throw .domain("ploščina D_\(start + areas.count) ni končna") }
            ellipses.append(ellipse)
            areas.append(a)
            total += a
            // A run of terms below the last digit of the sum: the rest no longer counts.
            negligible = a <= 1e-17 * total ? negligible + 1 : 0
            if negligible >= 8, areas.count >= 16 {
                complete = true
                break
            }
        }
        let series = Self.sum(areas, from: start, complete: complete) { exactArea(start + $0) }

        // Pairs in index order (D₁ and D₂ first); only those whose boxes overlap are tested.
        var overlap = UnionArea.Overlap.disjoint
        var tests = 0
        let halves = ellipses.map { $0?.halfSize ?? .zero }
        search: for i in ellipses.indices {
            guard let e1 = ellipses[i] else { continue }
            for j in (i + 1)..<ellipses.count {
                guard let e2 = ellipses[j] else { continue }
                let reach = halves[i] + halves[j]
                guard Swift.abs(e1.center.x - e2.center.x) < reach.x, Swift.abs(e1.center.y - e2.center.y) < reach.y else { continue }
                tests += 1
                if tests > Self.pairLimit {
                    overlap = .unknown
                    break search
                }
                if e1.overlaps(e2) {
                    overlap = .members(start + i, start + j)
                    break search
                }
            }
        }
        return UnionArea(overlap: overlap, sum: series.sum, exact: series.exact, errorBound: series.errorBound, ratio: series.ratio,
                         checkedThrough: start + ellipses.count - 1, remainder: Swift.max(0, series.sum - total))
    }

    /// Σ terms[i] (the areas of D_first, D_first+1, …) with the rest of the series:
    /// - a geometric series exactly (`exactTerm` gives the exact terms) or from its quotient;
    /// - `complete`: the terms left out are below the last digit of the sum;
    /// - otherwise a power law fitted to the last terms, with the rest between the integral bounds
    ///   ∫_{N+1}^∞ a + a(N+1)/2 ≤ Σ_{n>N} a(n) ≤ ∫_{N+½}^∞ a of a decreasing convex a(t) = C·t^(−p).
    static func sum(_ terms: [Double], from first: Int, complete: Bool, exactTerm: (Int) -> ExactReal?)
        -> (sum: Double, exact: ExactReal?, errorBound: Double?, ratio: Double?) {
        let partial = terms.reduce(0, +)
        let rounding = partial * 1e-16 * Double(terms.count)
        // A geometric series: one quotient between the first terms, which carry all their digits,
        // confirmed by all the others.
        let head = Array(terms.prefix(20))
        if head.count >= 6, head.allSatisfy({ $0 > 0 }) {
            let q = head[1] / head[0]
            let geometric = zip(head, head.dropFirst()).allSatisfy { Swift.abs($1 / $0 - q) <= 1e-9 * q }
                && terms.indices.allSatisfy { Swift.abs(terms[$0] - head[0] * pow(q, Double($0))) <= 1e-6 * terms[$0] + 1e-15 * partial }
            if geometric {
                guard q < 1 - 1e-9 else { return (.infinity, nil, nil, q) }
                let value = head[0] / (1 - q)
                if let exact = exactGeometricSum(exactTerm), Swift.abs(exact.doubleValue - value) <= 1e-12 * value {
                    return (exact.doubleValue, exact, 0, q)
                }
                if let r = Rational.approximating(q, maxDenominator: 1000, tolerance: 1e-13), let factor = Rational.one.subtracting(r)?.reciprocal(),
                   let a0 = ExactRecognizer.recognize(head[0], tolerance: 1e-13), let exact = a0.multiplied(by: ExactReal(factor)),
                   Swift.abs(exact.doubleValue - value) <= 1e-12 * value {
                    return (exact.doubleValue, exact, 0, q)
                }
                return (value, nil, value * 1e-12, q)
            }
        }
        if complete { return (partial, nil, rounding + partial * 1e-16, nil) }
        // Slowly decreasing areas (π/(4n²) …): the exponent of a power law from the last two octaves.
        let n = terms.count
        let indices = [n / 4, n / 2, n - 1]
        let m = indices.map { Double(first + $0) }
        let a = indices.map { terms[$0] }
        guard m[0] > 0, a.allSatisfy({ $0 > 0 }) else { return (partial, nil, nil, nil) }
        let p1 = log(a[1] / a[2]) / log(m[2] / m[1])
        let p2 = log(a[0] / a[1]) / log(m[1] / m[0])
        guard p1.isFinite, p2.isFinite else { return (partial, nil, nil, nil) }
        if p1 <= 1 + 1e-6 { return (.infinity, nil, nil, nil) }
        let last = m[2]
        func rest(_ p: Double) -> (low: Double, high: Double) {
            let c = a[2] * pow(last, p)
            let low = c * pow(last + 1, 1 - p) / (p - 1) + c * pow(last + 1, -p) / 2
            let high = c * pow(last + 0.5, 1 - p) / (p - 1)
            return (low, high)
        }
        let fitted = rest(p1)
        let other = p2 > 1 ? rest(p2) : (low: Double.infinity, high: Double.infinity)
        let middle = (fitted.low + fitted.high) / 2
        let bound = (fitted.high - fitted.low) / 2 + Swift.abs((other.low + other.high) / 2 - middle) + rounding
        return (partial + middle, nil, bound.isFinite ? bound : nil, nil)
    }

    /// a₀/(1 − q) from exact first terms with an exact rational quotient.
    private static func exactGeometricSum(_ exactTerm: (Int) -> ExactReal?) -> ExactReal? {
        guard let a0 = exactTerm(0), let a1 = exactTerm(1), let a2 = exactTerm(2), !a0.isZero, !a1.isZero,
              let q0 = a1.divided(by: a0), let q1 = a2.divided(by: a1), q0 == q1, let q = q0.rational,
              q < Rational.one, let factor = Rational.one.subtracting(q)?.reciprocal() else { return nil }
        return a0.multiplied(by: ExactReal(factor))
    }
}
