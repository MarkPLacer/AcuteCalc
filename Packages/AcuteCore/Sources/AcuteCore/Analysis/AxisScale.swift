import Foundation

/// The scale of a graph axis. On a logarithmic axis (base 10) equal distances are equal factors, a
/// decade per step, so a quantity over many powers of ten fits on one axis: the frequencies of the
/// electromagnetic spectrum from 10⁰ to 10²⁰ Hz. Graphs are laid out in plot coordinates, the value
/// itself or its log₁₀; panning and zooming move those, so on a logarithmic axis they work in decades.
public enum AxisScale: String, CaseIterable, Codable, Sendable {
    case linear
    case logarithmic

    /// The plot coordinate of a value: NaN where it cannot be drawn (0 and the negative values on a
    /// logarithmic axis, which lie at −∞ or nowhere).
    public func plotCoordinate(_ value: Double) -> Double {
        switch self {
        case .linear: value
        case .logarithmic: value > 0 ? log10(value) : .nan
        }
    }

    /// The value at a plot coordinate (0 or ∞ beyond the range of a Double).
    public func value(atPlotCoordinate coordinate: Double) -> Double {
        switch self {
        case .linear: coordinate
        case .logarithmic: pow(10, coordinate)
        }
    }

    /// The values over a range of plot coordinates.
    public func valueRange(_ plot: ClosedRange<Double>) -> ClosedRange<Double> {
        value(atPlotCoordinate: plot.lowerBound)...value(atPlotCoordinate: plot.upperBound)
    }

    /// The plot coordinates of the part of a range of values the axis can draw: the range itself on a
    /// linear axis; on a logarithmic one its positive part, from three decades below the top where it
    /// reaches 0 or below (−5 … 5 shows 0,005 … 5); nil when nothing of it can be drawn.
    public func plotExtent(of values: ClosedRange<Double>) -> ClosedRange<Double>? {
        switch self {
        case .linear:
            return values.lowerBound.isFinite && values.upperBound.isFinite ? values : nil
        case .logarithmic:
            let top = Swift.min(values.upperBound, .greatestFiniteMagnitude)
            let bottom = values.lowerBound > 0 ? values.lowerBound : top / 1000
            guard top > 0, bottom > 0, bottom <= top else { return nil }
            return log10(bottom)...log10(top)
        }
    }

    /// A range of values cut into pieces that an even sampling resolves: the range itself on a linear
    /// axis; on a logarithmic one decades (wider beyond `maximumCount` of them) overlapping by 5 %, since
    /// 2400 samples spread evenly over 1 … 10²⁰ are 4·10¹⁶ apart and miss everything below. A range
    /// that reaches 0 (an interval typed for the analysis) keeps its part up to 10⁻¹² of the top whole.
    public func samplingPieces(of range: ClosedRange<Double>, maximumCount: Int = 48) -> [ClosedRange<Double>] {
        guard self == .logarithmic, range.upperBound > 0 else { return [range] }
        // A view beyond 10³⁰⁸ shows values up to ∞; the pieces end at the largest Double.
        let upper = Swift.min(range.upperBound, .greatestFiniteMagnitude)
        guard range.lowerBound > 0 else {
            let floor = upper * 1e-12
            guard range.lowerBound < floor else { return [range] }
            return [range.lowerBound...floor] + samplingPieces(of: floor...upper, maximumCount: maximumCount)
        }
        let low = log10(range.lowerBound), high = log10(upper)
        // Nothing to cut past the largest Double (a view beyond 10³⁰⁸ starts at ∞ there).
        guard low.isFinite, high > low else { return [range] }
        // (The tolerance keeps log₁₀ 10²⁰ = 20 + 1 ulp at twenty pieces.)
        let count = Int(Swift.min(Double(Swift.max(1, maximumCount)), (high - low - 1e-9).rounded(.up)))
        guard count > 1 else { return [range] }
        let width = (high - low) / Double(count)
        return (0..<count).map { i in
            let a = i == 0 ? range.lowerBound : pow(10, low + (Double(i) - 0.05) * width)
            let b = i == count - 1 ? upper : pow(10, low + (Double(i + 1) + 0.05) * width)
            return a...b
        }
    }
}

/// The scales of the two axes of a graph.
public struct AxisScales: Hashable, Sendable {
    public var x: AxisScale
    public var y: AxisScale

    public init(x: AxisScale = .linear, y: AxisScale = .linear) {
        self.x = x
        self.y = y
    }

    public static let linear = AxisScales()

    public var isLinear: Bool { x == .linear && y == .linear }

    /// The plot coordinates of a point (NaN where it cannot be drawn).
    public func plotPoint(_ point: SIMD2<Double>) -> SIMD2<Double> {
        SIMD2(x.plotCoordinate(point.x), y.plotCoordinate(point.y))
    }

    /// The point at plot coordinates.
    public func point(atPlot plot: SIMD2<Double>) -> SIMD2<Double> {
        SIMD2(x.value(atPlotCoordinate: plot.x), y.value(atPlotCoordinate: plot.y))
    }
}

// MARK: - Grid and labels

/// A line of the grid of a logarithmic axis.
public struct AxisTick: Equatable, Sendable {
    /// The plot coordinate: log₁₀ of the value.
    public var position: Double
    /// The value (0 or ∞ beyond the range of a Double).
    public var value: Double
    /// Major lines are labelled, the minor ones between them are not.
    public var isMajor: Bool
    /// The label of a major line (when asked for).
    public var label: String?
    /// Where labels would overlap the lower rank stays: 0 the decades (or every label of an even
    /// grid), 1 two and five times a decade, 2 the other multiples, 3 the minor lines.
    public var rank: Int
}

/// The grid lines and labels of a logarithmic axis.
public enum LogarithmicAxis {
    /// The lines over a range of plot coordinates (decades) at `pointsPerDecade`, the major ones about
    /// `targetPoints` apart or more, by zoom:
    /// - every decade, or every 2nd, 5th, 10th … one with the decades between as minor lines;
    /// - every decade, with 2 … 9 times it as minor lines;
    /// - 1, 2 and 5 times each decade, minor 3, 4, 6, 7, 8 and 9 times;
    /// - every whole multiple 1 … 9 of each decade, minor the halves;
    /// - within a decade (at 30 targets per decade and more) evenly spaced values, 1, 2 or 5 times a
    ///   power of ten apart, about a target apart at the upper end.
    /// Labels are 10ⁿ, or written out where that is not longer (1, 10, 100, 0,1 and 0,01), and 2·10³
    /// between those decades or 20 and 0,05 between the written ones.
    public static func ticks(in range: ClosedRange<Double>, pointsPerDecade: Double, targetPoints: Double = 90,
                             labels: Bool = true, decimalSeparator: String = ",") -> [AxisTick] {
        let d = pointsPerDecade, t = targetPoints
        // Plot coordinates beyond ±10¹² decades have no fraction left to place lines by.
        guard d > 0, d.isFinite, t > 0, t.isFinite, range.lowerBound > -1e12, range.upperBound < 1e12 else { return [] }
        let step = decadeStep(t / d)
        if step > 1 {
            return decades(in: range, every: step, labels: labels, separator: decimalSeparator)
        }
        if d >= 30 * t, let even = evenlySpaced(in: range, pointsPerDecade: d, targetPoints: t, labels: labels, separator: decimalSeparator) {
            return even
        }
        // (multiple of the decade, rank of a major line or nil for a minor one)
        let pattern: [(multiple: Double, rank: Int?)]
        if d >= 8 * t {
            pattern = (2...19).map { half -> (multiple: Double, rank: Int?) in
                let m = Double(half) / 2
                guard m == m.rounded() else { return (m, nil) }
                return (m, rank(Int(m)))
            }
        } else if d >= 3 * t {
            pattern = (1...9).map { m -> (multiple: Double, rank: Int?) in (Double(m), m == 1 || m == 2 || m == 5 ? rank(m) : nil) }
        } else {
            pattern = (1...9).map { m -> (multiple: Double, rank: Int?) in (Double(m), m == 1 ? 0 : nil) }
        }
        return multiples(in: range, pattern: pattern, labels: labels, separator: decimalSeparator)
    }

    /// The rank of the label of m·10ⁿ (see `AxisTick.rank`).
    private static func rank(_ multiple: Int) -> Int {
        switch multiple {
        case 1: 0
        case 2, 5: 1
        default: 2
        }
    }

    /// The decade step of the major lines: 1, 2 or 5 times a power of ten near `raw` decades, rounded
    /// like `GridSpacing.choose` in the app, and at least one decade.
    static func decadeStep(_ raw: Double) -> Double {
        guard raw > 1 else { return 1 }
        let base = pow(10, floor(log10(raw)))
        let fraction = raw / base
        return (fraction < 1.5 ? 1 : fraction < 3.5 ? 2 : fraction < 7.5 ? 5 : 10) * base
    }

    /// Every `step`-th decade as a major line, the decades between them in subdivisions like those
    /// of a linear grid (2 → 1, 5 → 1, 10 → 2, 20 → 5 …) as minor ones.
    private static func decades(in range: ClosedRange<Double>, every step: Double, labels: Bool, separator: String) -> [AxisTick] {
        guard step.isFinite, step < 1e12 else { return [] }
        let leading = (step / pow(10, floor(log10(step)))).rounded()
        let minor = Swift.max(1, step / (leading == 2 ? 4 : 5))
        guard (range.upperBound - range.lowerBound) / minor < 10_000 else { return [] }
        var ticks: [AxisTick] = []
        var k = (range.lowerBound / minor).rounded(.up)
        while k * minor <= range.upperBound {
            let position = k * minor
            let isMajor = position.truncatingRemainder(dividingBy: step) == 0
            ticks.append(AxisTick(position: position, value: pow(10, position), isMajor: isMajor,
                                  label: labels && isMajor ? decadeLabel(Int(position), separator: separator) : nil,
                                  rank: isMajor ? 0 : 3))
            k += 1
        }
        return ticks
    }

    /// The multiples m·10ⁿ of the pattern in every decade n of the range.
    private static func multiples(in range: ClosedRange<Double>, pattern: [(multiple: Double, rank: Int?)],
                                  labels: Bool, separator: String) -> [AxisTick] {
        let first = Int(range.lowerBound.rounded(.down)), last = Int(range.upperBound.rounded(.down))
        guard last - first < 1000 else { return [] }
        var ticks: [AxisTick] = []
        for exponent in first...last {
            for (multiple, rank) in pattern {
                let position = Double(exponent) + log10(multiple)
                guard range.contains(position) else { continue }
                let power = pow(10, Double(Swift.abs(exponent)))
                ticks.append(AxisTick(position: position, value: exponent >= 0 ? multiple * power : multiple / power,
                                      isMajor: rank != nil,
                                      label: labels && rank != nil ? multipleLabel(Int(multiple), exponent, separator: separator) : nil,
                                      rank: rank ?? 3))
            }
        }
        return ticks
    }

    /// Values 1, 2 or 5 times a power of ten apart within less than a decade, where the axis is nearly
    /// linear, spaced for `targetPoints` at the upper end (the closest); nil for a longer range or one
    /// that needs too many lines.
    private static func evenlySpaced(in range: ClosedRange<Double>, pointsPerDecade d: Double, targetPoints t: Double,
                                     labels: Bool, separator: String) -> [AxisTick]? {
        let low = pow(10, range.lowerBound), high = pow(10, range.upperBound)
        guard range.upperBound - range.lowerBound <= 1, low > 0, high.isFinite else { return nil }
        // A step δ at the value v is d·log₁₀(1 + δ/v) ≈ d·δ/(v·ln 10) points long.
        let raw = t * high * log(10) / d
        let base = pow(10, floor(log10(raw)))
        let fraction = raw / base
        let (leading, subdivisions): (Double, Double) = fraction < 1.5 ? (1, 5) : fraction < 3.5 ? (2, 4) : fraction < 7.5 ? (5, 5) : (10, 5)
        let major = leading * base, minor = major / subdivisions
        guard minor > 0, high / minor < 1e15, (high - low) / minor < 2000 else { return nil }
        var ticks: [AxisTick] = []
        var k = (low / minor).rounded(.up)
        while k * minor <= high {
            let value = k * minor
            let isMajor = k.truncatingRemainder(dividingBy: subdivisions) == 0
            ticks.append(AxisTick(position: log10(value), value: value, isMajor: isMajor,
                                  label: labels && isMajor ? evenLabel(value, step: major, separator: separator) : nil,
                                  rank: isMajor ? 0 : 3))
            k += 1
        }
        return ticks
    }

    // MARK: Labels

    /// 10ⁿ, or written out where that is not longer: 1, 10, 100, 0,1 and 0,01.
    public static func decadeLabel(_ exponent: Int, separator: String = ",") -> String {
        multipleLabel(1, exponent, separator: separator)
    }

    /// m·10ⁿ for a whole m from 1 to 9: written out in a decade whose 10ⁿ is (20, 500, 0,05), else
    /// 2·10³ (and 10³ for m = 1).
    static func multipleLabel(_ multiple: Int, _ exponent: Int, separator: String) -> String {
        guard isWrittenOut(exponent, separator: separator) else {
            return (multiple == 1 ? "" : "\(multiple)·") + "10" + superscript(exponent)
        }
        return exponent >= 0 ? "\(multiple)" + String(repeating: "0", count: exponent)
            : "0" + separator + String(repeating: "0", count: -exponent - 1) + "\(multiple)"
    }

    /// Whether 10ⁿ written out (1000, 0,001) is not longer than "10ⁿ".
    static func isWrittenOut(_ exponent: Int, separator: String) -> Bool {
        let written = exponent >= 0 ? exponent + 1 : -exponent + 1 + separator.count
        return written <= 2 + String(exponent).count
    }

    /// A value of an even grid with the decimals of its step: written out in a decade whose 10ⁿ is
    /// (1,25), else as m·10ⁿ (2,05·10⁹).
    static func evenLabel(_ value: Double, step: Double, separator: String) -> String {
        let stepExponent = Int(floor(log10(step)))
        var exponent = Int(floor(log10(value)))
        if isWrittenOut(exponent, separator: separator) {
            return decimal(value, places: -stepExponent, separator: separator)
        }
        var mantissa = decimal(value / pow(10, Double(exponent)), places: exponent - stepExponent, separator: ".")
        // 9,99…·10⁸ rounded to the step reads 10·10⁸: that is 1·10⁹.
        if let m = Double(mantissa), m >= 10 {
            exponent += 1
            mantissa = decimal(value / pow(10, Double(exponent)), places: exponent - stepExponent, separator: ".")
        }
        return mantissa.replacingOccurrences(of: ".", with: separator) + "·10" + superscript(exponent)
    }

    /// `value` with up to `places` decimals, trailing zeros dropped.
    private static func decimal(_ value: Double, places: Int, separator: String) -> String {
        var text = String(format: "%.\(Swift.min(Swift.max(0, places), 15))f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text.replacingOccurrences(of: ".", with: separator)
    }

    static func superscript(_ n: Int) -> String {
        let digits: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵",
                                              "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻"]
        return String(String(n).map { digits[$0] ?? $0 })
    }
}

// MARK: - Analysis on a logarithmic axis

extension FunctionAnalyzer {
    /// `analyze` for an axis of the given scale: on a logarithmic one piece by piece
    /// (`AxisScale.samplingPieces`), so 1 … 10 is sampled as finely as 10¹⁹ … 10²⁰, with the points,
    /// poles, holes and intervals of the pieces merged; the asymptotes do not depend on the range and
    /// come from the first piece.
    public static func analyze(_ expr: Expr, variable: String = "x", range: ClosedRange<Double>, scale: AxisScale,
                               context: EvaluationContext, includeAsymptotes: Bool = true) -> FunctionAnalysis {
        let pieces = scale.samplingPieces(of: range)
        var merged = analyze(expr, variable: variable, range: pieces[0], context: context, includeAsymptotes: includeAsymptotes)
        guard pieces.count > 1 else { return merged }
        merged.range = range
        for piece in pieces.dropFirst() {
            let part = analyze(expr, variable: variable, range: piece, context: context, includeAsymptotes: false)
            merged.zeros = merging(merged.zeros, part.zeros)
            merged.extrema = merging(merged.extrema, part.extrema)
            merged.inflections = merging(merged.inflections, part.inflections)
            merged.poles = merging(merged.poles, part.poles)
            merged.holes = merging(merged.holes, part.holes)
            // "x ≠ …" describes the domain only if it does so on every piece.
            if let excluded = merged.excludedPoints, let more = part.excludedPoints {
                merged.excludedPoints = merging(excluded, more)
            } else {
                merged.excludedPoints = nil
            }
            merged.increasing = merging(merged.increasing, part.increasing)
            merged.decreasing = merging(merged.decreasing, part.decreasing)
            merged.convex = merging(merged.convex, part.convex)
            merged.concave = merging(merged.concave, part.concave)
        }
        return merged
    }

    /// `intersections` for an axis of the given scale (piece by piece on a logarithmic one).
    public static func intersections(_ f: Expr, _ g: Expr, variable: String = "x", range: ClosedRange<Double>, scale: AxisScale,
                                     context: EvaluationContext, otherCurve: Int? = nil) -> [SpecialPoint] {
        let pieces = scale.samplingPieces(of: range)
        guard pieces.count > 1 else {
            return intersections(f, g, variable: variable, range: range, context: context, otherCurve: otherCurve)
        }
        return pieces.reduce([]) { found, piece in
            merging(found, intersections(f, g, variable: variable, range: piece, context: context, otherCurve: otherCurve))
        }
    }

    /// The points of `b` that `a` does not have yet (the pieces overlap), in the order of x.
    private static func merging(_ a: [SpecialPoint], _ b: [SpecialPoint]) -> [SpecialPoint] {
        let new = b.filter { p in !a.contains { $0.kind == p.kind && isSame($0.x, p.x) } }
        return (a + new).sorted { $0.x < $1.x }
    }

    private static func merging(_ a: [Double], _ b: [Double]) -> [Double] {
        (a + b.filter { x in !a.contains { isSame($0, x) } }).sorted()
    }

    /// The union of two lists of intervals: the parts of one interval found in two overlapping pieces
    /// are joined, while intervals that only touch stay apart, since they meet at a pole, an extremum
    /// or an end of the domain (tan x increases on both sides of π/2).
    private static func merging(_ a: [ClosedRange<Double>], _ b: [ClosedRange<Double>]) -> [ClosedRange<Double>] {
        var result: [ClosedRange<Double>] = []
        for interval in (a + b).sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = result.last, interval.lowerBound < last.upperBound, !isSame(interval.lowerBound, last.upperBound) {
                result[result.count - 1] = last.lowerBound...Swift.max(last.upperBound, interval.upperBound)
            } else {
                result.append(interval)
            }
        }
        return result
    }

    private static func isSame(_ a: Double, _ b: Double) -> Bool {
        Swift.abs(a - b) <= 1e-9 * Swift.max(Swift.abs(a), Swift.abs(b))
    }
}

extension ImplicitBounds {
    /// `find` over a window of plot coordinates: on a logarithmic axis the grid is even in decades (an
    /// even grid of values over 10⁻¹⁹ … 10²¹ has cells of 10¹⁹ and misses a circle of radius 10), and
    /// the bounds come back in plot coordinates. A relation that reaches 0 on a logarithmic axis runs to
    /// −∞ there, so like a line on a linear axis it reaches the edge of the window and is not bounded.
    public static func find(program: Program, parameters: [Double] = [], plotX: ClosedRange<Double>, plotY: ClosedRange<Double>,
                            axes: AxisScales, resolution: Int = 160) -> Result? {
        let vm = RealVM(program: program, parameters: parameters)
        return find(x: plotX, y: plotY, resolution: resolution) { us, v in
            vm.evaluate(xs: us.map { axes.x.value(atPlotCoordinate: $0) }, y: axes.y.value(atPlotCoordinate: v))
        }
    }
}
