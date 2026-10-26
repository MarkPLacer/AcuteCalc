import Foundation

/// Sets for the matura: subsets of the real line built from intervals, single numbers or an
/// inequality, set expressions in A, B and C with ∪, ∩, \ and the complement, and the regions
/// of a Venn diagram of two or three sets with the number of elements in each.
public enum SetAlgebra {
    public typealias Interval = InequalitySolution.Interval

    // MARK: Sets of real numbers

    /// A subset of ℝ: disjoint intervals and single numbers in increasing order.
    public struct RealSet: Sendable, Hashable {
        public private(set) var intervals: [Interval]

        public init(_ intervals: [Interval]) {
            self.intervals = RealSet.normalized(intervals)
        }

        public static let empty = RealSet([])
        public static let reals = RealSet([Interval(lower: -.infinity, upper: .infinity, lowerIncluded: false, upperIncluded: false)])

        public var isEmpty: Bool { intervals.isEmpty }

        /// The set written as the solution of an inequality in x, to show it the same way.
        public var solution: InequalitySolution { InequalitySolution(variable: "x", intervals: intervals) }

        public var isAllReals: Bool {
            intervals.count == 1 && intervals[0].lower == -.infinity && intervals[0].upper == .infinity
        }

        public func contains(_ x: Double) -> Bool {
            intervals.contains { i in
                (x > i.lower || (x == i.lower && i.lowerIncluded)) && (x < i.upper || (x == i.upper && i.upperIncluded))
            }
        }

        public func union(_ other: RealSet) -> RealSet { RealSet(intervals + other.intervals) }

        public func intersection(_ other: RealSet) -> RealSet {
            var pieces: [Interval] = []
            for a in intervals {
                for b in other.intervals {
                    var piece = a
                    if b.lower > a.lower || (b.lower == a.lower && !b.lowerIncluded) {
                        piece.lower = b.lower
                        piece.lowerIncluded = b.lowerIncluded
                        piece.exactLower = b.exactLower ?? (b.lower == a.lower ? a.exactLower : nil)
                    }
                    if b.upper < a.upper || (b.upper == a.upper && !b.upperIncluded) {
                        piece.upper = b.upper
                        piece.upperIncluded = b.upperIncluded
                        piece.exactUpper = b.exactUpper ?? (b.upper == a.upper ? a.exactUpper : nil)
                    }
                    pieces.append(piece)
                }
            }
            return RealSet(pieces)
        }

        /// ℝ without the set.
        public var complement: RealSet {
            var pieces: [Interval] = []
            var start = Interval(lower: -.infinity, upper: .infinity, lowerIncluded: false, upperIncluded: false)
            for i in intervals {
                var gap = start
                gap.upper = i.lower
                gap.upperIncluded = !i.lowerIncluded
                gap.exactUpper = i.exactLower
                pieces.append(gap)
                start.lower = i.upper
                start.lowerIncluded = !i.upperIncluded
                start.exactLower = i.exactUpper
            }
            pieces.append(start)
            return RealSet(pieces)
        }

        public func subtracting(_ other: RealSet) -> RealSet { intersection(other.complement) }

        /// Sorted, without empty pieces, with overlapping or touching pieces merged and infinite
        /// ends open.
        static func normalized(_ pieces: [Interval]) -> [Interval] {
            let valid = pieces.compactMap { piece -> Interval? in
                var i = piece
                guard !i.lower.isNaN, !i.upper.isNaN else { return nil }
                if i.lower == -.infinity { i.lowerIncluded = false }
                if i.upper == .infinity { i.upperIncluded = false }
                guard i.lower < i.upper || (i.lower == i.upper && i.lowerIncluded && i.upperIncluded) else { return nil }
                return i
            }
            let sorted = valid.sorted { $0.lower < $1.lower || ($0.lower == $1.lower && $0.lowerIncluded && !$1.lowerIncluded) }
            var merged: [Interval] = []
            for i in sorted {
                guard var last = merged.last,
                      i.lower < last.upper || (i.lower == last.upper && (last.upperIncluded || i.lowerIncluded)) else {
                    merged.append(i)
                    continue
                }
                if i.upper > last.upper {
                    last.upper = i.upper
                    last.upperIncluded = i.upperIncluded
                    last.exactUpper = i.exactUpper
                } else if i.upper == last.upper {
                    last.upperIncluded = last.upperIncluded || i.upperIncluded
                    last.exactUpper = last.exactUpper ?? i.exactUpper
                }
                merged[merged.count - 1] = last
            }
            return merged
        }

        /// "[−2, 3) ∪ {5}", "(1; ∞)", "{1, 2, 4}", "ℝ", "∅", or an inequality in one unknown such as
        /// "x² < 4" or "−1 ≤ x < 2"; nil when the text is not a set. With semicolons between
        /// the ends the decimal comma may be used.
        public static func parse(_ text: String) -> RealSet? {
            let t = text.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { return nil }
            if t == "∅" || t == "{}" || t == "{ }" { return .empty }
            if t == "ℝ" || t == "R" { return .reals }
            if t.contains(where: { "<>≤≥".contains($0) }) { return inequality(t) }
            var pieces: [Interval] = []
            for part in t.split(whereSeparator: { $0 == "∪" || $0 == "U" }) {
                guard let piece = parsePiece(part.trimmingCharacters(in: .whitespaces)) else { return nil }
                pieces += piece
            }
            return pieces.isEmpty ? nil : RealSet(pieces)
        }

        private static func inequality(_ text: String) -> RealSet? {
            guard let expr = try? Parser.parse(text), let links = PlaneSets.links(expr) else { return nil }
            let unknowns = expr.freeVariables
            guard unknowns.count == 1, let unknown = unknowns.first, links.allSatisfy({ $0.1 != .equal && $0.1 != .notEqual }),
                  let solution = InequalitySolver.solve(links, variable: unknown, context: EvaluationContext()),
                  solution.period == nil else { return nil }
            return RealSet(solution.intervals)
        }

        /// One interval "[a, b)" or a list of numbers "{a; b}".
        private static func parsePiece(_ text: String) -> [Interval]? {
            guard let open = text.first, let close = text.last, text.count >= 2 else { return nil }
            let inner = String(text.dropFirst().dropLast())
            let semicolons = inner.contains(";")
            let parts = inner.split(separator: semicolons ? ";" : ",", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
            if open == "{" && close == "}" {
                var points: [Interval] = []
                for part in parts {
                    guard let point = number(part, decimalComma: semicolons), point.value.isFinite else { return nil }
                    points.append(Interval(lower: point.value, upper: point.value, lowerIncluded: true, upperIncluded: true,
                                           exactLower: point.exact, exactUpper: point.exact))
                }
                return points
            }
            guard "[(".contains(open), "])".contains(close), parts.count == 2,
                  let a = number(parts[0], decimalComma: semicolons), let b = number(parts[1], decimalComma: semicolons),
                  a.value <= b.value, a.value != .infinity, b.value != -.infinity else { return nil }
            return [Interval(lower: a.value, upper: b.value, lowerIncluded: open == "[", upperIncluded: close == "]",
                             exactLower: a.exact, exactUpper: b.exact)]
        }

        /// A number or an expression (√2, π/2, −∞) and its exact value when it is a simple one.
        private static func number(_ text: String, decimalComma: Bool) -> (value: Double, exact: ExactReal?)? {
            let t = text.replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: " ", with: "")
            switch t {
            case "∞", "+∞", "inf", "+inf": return (.infinity, nil)
            case "-∞", "-inf": return (-.infinity, nil)
            default: break
            }
            let normalized = decimalComma ? t.replacingOccurrences(of: ",", with: ".") : t
            guard !normalized.isEmpty, let expr = try? Parser.parse(normalized),
                  let value = try? RealEvaluator.evaluate(expr, context: EvaluationContext()), value.isFinite else { return nil }
            let exact = ExactRecognizer.recognize(value).flatMap { $0.complexity <= 10 ? $0 : nil }
            return (value, exact)
        }
    }

    // MARK: Set expressions

    /// A set expression in A, B and C: ∪ and \ (difference) bind weakest, then ∩, then the
    /// complement written after a set (A′, A', Aᶜ, A^c).
    public indirect enum Expression: Sendable, Hashable {
        case set(Int)
        case union(Expression, Expression)
        case intersection(Expression, Expression)
        case difference(Expression, Expression)
        case complement(Expression)

        public static let names = ["A", "B", "C"]

        /// The indices of the sets that appear.
        public var sets: Set<Int> {
            switch self {
            case .set(let i): [i]
            case .union(let a, let b), .intersection(let a, let b), .difference(let a, let b): a.sets.union(b.sets)
            case .complement(let a): a.sets
            }
        }

        /// The value for sets of real numbers (complements within ℝ); nil when a set is missing.
        public func evaluate(_ values: [RealSet?]) -> RealSet? {
            switch self {
            case .set(let i):
                return values.indices.contains(i) ? values[i] : nil
            case .union(let a, let b):
                guard let x = a.evaluate(values), let y = b.evaluate(values) else { return nil }
                return x.union(y)
            case .intersection(let a, let b):
                guard let x = a.evaluate(values), let y = b.evaluate(values) else { return nil }
                return x.intersection(y)
            case .difference(let a, let b):
                guard let x = a.evaluate(values), let y = b.evaluate(values) else { return nil }
                return x.subtracting(y)
            case .complement(let a):
                return a.evaluate(values)?.complement
            }
        }

        /// The regions of a Venn diagram of `count` sets that belong to the expression; region
        /// r contains the elements in set i exactly when bit i of r is set (0 is outside all).
        public func regions(of count: Int) -> Set<Int> {
            // A Venn diagram of one to six sets; a set outside them has no region.
            guard (1...6).contains(count) else { return [] }
            let all = Set(0..<(1 << count))
            switch self {
            case .set(let i): return (0..<count).contains(i) ? all.filter { $0 & (1 << i) != 0 } : []
            case .union(let a, let b): return a.regions(of: count).union(b.regions(of: count))
            case .intersection(let a, let b): return a.regions(of: count).intersection(b.regions(of: count))
            case .difference(let a, let b): return a.regions(of: count).subtracting(b.regions(of: count))
            case .complement(let a): return all.subtracting(a.regions(of: count))
            }
        }

        /// Parses "(A ∪ B) ∩ C′", "A \\ B" or "(A ∩ B)ᶜ"; also | or + for ∪, & for ∩ and − for \.
        public static func parse(_ text: String) -> Expression? {
            var parser = ExpressionParser(Array(text.filter { !$0.isWhitespace }))
            guard let expression = parser.union(), parser.atEnd else { return nil }
            return expression
        }
    }

    private struct ExpressionParser {
        let characters: [Character]
        var position = 0

        init(_ characters: [Character]) { self.characters = characters }

        var atEnd: Bool { position == characters.count }

        private var current: Character? { position < characters.count ? characters[position] : nil }

        mutating func union() -> Expression? {
            guard var left = intersection() else { return nil }
            while let c = current {
                if "∪|+".contains(c) {
                    position += 1
                    guard let right = intersection() else { return nil }
                    left = .union(left, right)
                } else if "\\−-∖".contains(c) {
                    position += 1
                    guard let right = intersection() else { return nil }
                    left = .difference(left, right)
                } else {
                    break
                }
            }
            return left
        }

        mutating func intersection() -> Expression? {
            guard var left = complement() else { return nil }
            while let c = current, "∩&".contains(c) {
                position += 1
                guard let right = complement() else { return nil }
                left = .intersection(left, right)
            }
            return left
        }

        mutating func complement() -> Expression? {
            guard var value = primary() else { return nil }
            while let c = current {
                if "′'ᶜ".contains(c) {
                    position += 1
                } else if c == "^", position + 1 < characters.count, characters[position + 1] == "c" {
                    position += 2
                } else {
                    break
                }
                value = .complement(value)
            }
            return value
        }

        mutating func primary() -> Expression? {
            guard let c = current else { return nil }
            if c == "(" {
                position += 1
                guard let inner = union(), current == ")" else { return nil }
                position += 1
                return inner
            }
            guard let index = Expression.names.firstIndex(of: String(c)) else { return nil }
            position += 1
            return .set(index)
        }
    }

    // MARK: Venn diagrams

    /// The number of elements in each region of a Venn diagram of two sets, from the sizes of
    /// the sets, of their intersection and of the universal set (nil when unknown).
    public static func regionCounts(universe: Double?, a: Double, b: Double, ab: Double) throws(MathError) -> [Int: Double] {
        try checkGiven([universe, a, b, ab])
        var counts: [Int: Double] = [0b11: ab, 0b01: a - ab, 0b10: b - ab]
        if let universe { counts[0] = universe - (a + b - ab) }
        try check(counts)
        return counts
    }

    /// The same for three sets by inclusion and exclusion.
    public static func regionCounts(universe: Double?, a: Double, b: Double, c: Double,
                                    ab: Double, ac: Double, bc: Double, abc: Double) throws(MathError) -> [Int: Double] {
        try checkGiven([universe, a, b, c, ab, ac, bc, abc])
        var counts: [Int: Double] = [
            0b111: abc,
            0b011: ab - abc, 0b101: ac - abc, 0b110: bc - abc,
            0b001: a - ab - ac + abc, 0b010: b - ab - bc + abc, 0b100: c - ac - bc + abc,
        ]
        if let universe { counts[0] = universe - (a + b + c - ab - ac - bc + abc) }
        try check(counts)
        return counts
    }

    /// The number of elements in the regions of an expression; nil when one of them is unknown.
    public static func count(_ regions: Set<Int>, in counts: [Int: Double]) -> Double? {
        var total = 0.0
        for region in regions {
            guard let n = counts[region] else { return nil }
            total += n
        }
        return total
    }

    /// The numbers of elements given must be whole and not negative.
    private static func checkGiven(_ values: [Double?]) throws(MathError) {
        guard values.compactMap({ $0 }).allSatisfy({ $0.isFinite && $0 >= 0 && $0 == $0.rounded() }) else {
            throw .domain("števila elementov morajo biti cela in nenegativna")
        }
    }

    private static func check(_ counts: [Int: Double]) throws(MathError) {
        guard counts.values.allSatisfy({ $0.isFinite }) else { throw .domain("števila elementov morajo biti končna") }
        guard counts.values.allSatisfy({ $0 >= 0 }) else {
            throw .domain("podatki si nasprotujejo: neko področje bi imelo negativno število elementov")
        }
    }
}
