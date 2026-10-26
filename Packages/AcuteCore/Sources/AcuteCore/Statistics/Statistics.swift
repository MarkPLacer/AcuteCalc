import Foundation

/// One observation: x (and y for two-variable data) with a frequency (Sharp: x, y, f).
public struct DataPoint: Hashable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var x: Double
    public var y: Double
    public var frequency: Double

    public init(id: UUID = UUID(), x: Double, y: Double = 0, frequency: Double = 1) {
        self.id = id
        self.x = x
        self.y = y
        self.frequency = frequency
    }
}

/// Single-variable statistics (Sharp STAT SD mode plus median and quartiles).
public struct OneVariableStatistics: Hashable, Sendable {
    /// n — the sum of the frequencies.
    public var count: Double
    /// Σx
    public var sum: Double
    /// Σx²
    public var sumOfSquares: Double
    /// x̄
    public var mean: Double
    /// σx² (divide by n)
    public var populationVariance: Double
    /// sx² (divide by n − 1); `nil` for a single value.
    public var sampleVariance: Double?
    public var minimum: Double
    public var maximum: Double
    public var median: Double
    /// Q₁ and Q₃ as the medians of the lower and upper half (the median excluded for odd n).
    public var lowerQuartile: Double
    public var upperQuartile: Double
    /// Most frequent values (empty when every value occurs equally often).
    public var modes: [Double]

    public var populationStandardDeviation: Double { populationVariance.squareRoot() }
    public var sampleStandardDeviation: Double? { sampleVariance.map { $0.squareRoot() } }
    public var range: Double { maximum - minimum }
    public var interquartileRange: Double { upperQuartile - lowerQuartile }
    /// Coefficient of variation σ/x̄.
    public var coefficientOfVariation: Double? { mean == 0 ? nil : populationStandardDeviation / Swift.abs(mean) }

    public init?(values: [Double], frequencies: [Double]? = nil) {
        let weights = frequencies ?? Array(repeating: 1, count: values.count)
        let pairs = zip(values, weights).filter { $0.0.isFinite && $0.1 > 0 && $0.1.isFinite }
        guard !pairs.isEmpty else { return nil }
        let n = pairs.reduce(0) { $0 + $1.1 }
        let sum = pairs.reduce(0) { $0 + $1.0 * $1.1 }
        let mean = sum / n
        // Two-pass variance (numerically stable).
        let squaredDeviations = pairs.reduce(0) { $0 + (($1.0 - mean) * ($1.0 - mean)) * $1.1 }
        count = n
        self.sum = sum
        sumOfSquares = pairs.reduce(0) { $0 + $1.0 * $1.0 * $1.1 }
        self.mean = mean
        populationVariance = squaredDeviations / n
        sampleVariance = n > 1 ? squaredDeviations / (n - 1) : nil
        let sorted = pairs.sorted { $0.0 < $1.0 }
        minimum = sorted.first!.0
        maximum = sorted.last!.0
        if pairs.allSatisfy({ $0.1 == $0.1.rounded() }) {
            // Positions in the frequency-expanded sample; Q₁/Q₃ exclude the median for odd n.
            let half = (n / 2).rounded(.down)
            median = OneVariableStatistics.median(of: sorted, from: 0, to: n)
            lowerQuartile = OneVariableStatistics.median(of: sorted, from: 0, to: half)
            upperQuartile = OneVariableStatistics.median(of: sorted, from: n - half, to: n)
        } else {
            median = OneVariableStatistics.weightedQuantile(sorted, 0.5, total: n)
            lowerQuartile = OneVariableStatistics.weightedQuantile(sorted, 0.25, total: n)
            upperQuartile = OneVariableStatistics.weightedQuantile(sorted, 0.75, total: n)
        }
        // Modes
        var tally: [Double: Double] = [:]
        for (v, f) in pairs { tally[v, default: 0] += f }
        let best = tally.values.max() ?? 0
        let candidates = tally.filter { $0.value == best }.keys.sorted()
        modes = candidates.count == tally.count && tally.count > 1 ? [] : candidates
    }

    /// Median of the observations at (1-based, frequency-expanded) positions start+1 … end.
    static func median(of sorted: [(Double, Double)], from start: Double, to end: Double) -> Double {
        let m = end - start
        guard m > 0 else { return sorted.first?.0 ?? .nan }
        func value(at position: Double) -> Double {
            var cumulative = 0.0
            for (v, f) in sorted {
                cumulative += f
                if position <= cumulative + 1e-9 { return v }
            }
            return sorted.last?.0 ?? .nan
        }
        if m.truncatingRemainder(dividingBy: 2) == 1 {
            return value(at: start + (m + 1) / 2)
        }
        return (value(at: start + m / 2) + value(at: start + m / 2 + 1)) / 2
    }

    /// Smallest value whose cumulative weight reaches `p` of the total (non-integer frequencies).
    static func weightedQuantile(_ sorted: [(Double, Double)], _ p: Double, total: Double) -> Double {
        var cumulative = 0.0
        for (v, f) in sorted {
            cumulative += f
            if cumulative >= p * total - 1e-12 { return v }
        }
        return sorted.last?.0 ?? .nan
    }
}

/// Two-variable sums and correlation (Sharp STAT a+bx mode readouts).
public struct TwoVariableStatistics: Hashable, Sendable {
    public var count: Double
    public var sumX: Double, sumY: Double
    public var sumX2: Double, sumY2: Double, sumXY: Double
    public var meanX: Double, meanY: Double
    public var populationSDX: Double, populationSDY: Double
    public var sampleSDX: Double?, sampleSDY: Double?
    /// Pearson correlation coefficient r (nil when x or y is constant).
    public var correlation: Double?
    /// Population covariance.
    public var covariance: Double

    public init?(points: [DataPoint]) {
        let usable = points.filter { $0.x.isFinite && $0.y.isFinite && $0.frequency > 0 }
        guard !usable.isEmpty else { return nil }
        let n = usable.reduce(0) { $0 + $1.frequency }
        func sum(_ f: (DataPoint) -> Double) -> Double { usable.reduce(0) { $0 + f($1) * $1.frequency } }
        count = n
        sumX = sum(\.x)
        sumY = sum(\.y)
        sumX2 = sum { $0.x * $0.x }
        sumY2 = sum { $0.y * $0.y }
        sumXY = sum { $0.x * $0.y }
        meanX = sumX / n
        meanY = sumY / n
        let mx = meanX, my = meanY
        let sxx = sum { ($0.x - mx) * ($0.x - mx) }
        let syy = sum { ($0.y - my) * ($0.y - my) }
        let sxy = sum { ($0.x - mx) * ($0.y - my) }
        populationSDX = (sxx / n).squareRoot()
        populationSDY = (syy / n).squareRoot()
        sampleSDX = n > 1 ? (sxx / (n - 1)).squareRoot() : nil
        sampleSDY = n > 1 ? (syy / (n - 1)).squareRoot() : nil
        covariance = sxy / n
        correlation = (sxx > 0 && syy > 0) ? sxy / (sxx * syy).squareRoot() : nil
    }
}

/// The seven regression models of the Sharp EL-W531.
/// A transformed axis for linearising measurements (t² against l, p against 1/V, ln N against d).
public enum AxisTransform: String, CaseIterable, Identifiable, Sendable, Codable {
    case none, reciprocal, square, squareRoot, naturalLog, commonLog

    public var id: String { rawValue }

    public func apply(_ v: Double) -> Double {
        switch self {
        case .none: v
        case .reciprocal: v == 0 ? .nan : 1 / v
        case .square: v * v
        case .squareRoot: v >= 0 ? v.squareRoot() : .nan
        case .naturalLog: v > 0 ? Foundation.log(v) : .nan
        case .commonLog: v > 0 ? Foundation.log10(v) : .nan
        }
    }

    /// The axis label for a quantity called `name` (x, y …).
    public func label(_ name: String) -> String {
        switch self {
        case .none: name
        case .reciprocal: "1/\(name)"
        case .square: "\(name)²"
        case .squareRoot: "√\(name)"
        case .naturalLog: "ln \(name)"
        case .commonLog: "log \(name)"
        }
    }

    /// The points with both transforms applied (points that become undefined are dropped).
    public static func transform(_ points: [DataPoint], x: AxisTransform, y: AxisTransform) -> [DataPoint] {
        points.compactMap { p in
            let tx = x.apply(p.x), ty = y.apply(p.y)
            guard tx.isFinite, ty.isFinite else { return nil }
            return DataPoint(id: p.id, x: tx, y: ty, frequency: p.frequency)
        }
    }
}

extension TwoVariableStatistics {
    /// Area under the broken line through the points in order of x (trapezoidal rule):
    /// the distance under v(t), the work under F(s) … Negative where y < 0.
    public static func areaUnderPolyline(_ points: [DataPoint]) -> Double? {
        let sorted = points.filter { $0.x.isFinite && $0.y.isFinite }.sorted { $0.x < $1.x }
        guard sorted.count >= 2 else { return nil }
        return zip(sorted, sorted.dropFirst()).reduce(0) { $0 + ($1.1.x - $1.0.x) * ($1.0.y + $1.1.y) / 2 }
    }
}

public enum RegressionModel: String, CaseIterable, Identifiable, Sendable, Codable {
    case linear, quadratic, exponential, logarithmic, power, inverse, generalExponential
    /// y = bx: the line through the origin fitted to measurements (direct proportion in physics).
    case proportional

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .linear: "Linearna"
        case .quadratic: "Kvadratna"
        case .exponential: "Eksponentna (e)"
        case .logarithmic: "Logaritemska"
        case .power: "Potenčna"
        case .inverse: "Obratna"
        case .generalExponential: "Eksponentna (b)"
        case .proportional: "Premica skozi izhodišče"
        }
    }

    /// The model equation as shown on the calculator.
    public var formula: String {
        switch self {
        case .linear: "y = a + bx"
        case .quadratic: "y = a + bx + cx²"
        case .exponential: "y = a·eᵇˣ"
        case .logarithmic: "y = a + b·ln x"
        case .power: "y = a·xᵇ"
        case .inverse: "y = a + b/x"
        case .generalExponential: "y = a·bˣ"
        case .proportional: "y = bx"
        }
    }
}

/// A fitted regression curve with Sharp's estimates x′ and y′.
public struct RegressionResult: Hashable, Sendable {
    public var model: RegressionModel
    public var a: Double
    public var b: Double
    /// Coefficient of x² (quadratic model only).
    public var c: Double?
    /// Correlation coefficient of the linearised data (not defined for the quadratic model).
    public var r: Double?
    /// Coefficient of determination R² of the fit on the original data.
    public var rSquared: Double

    /// y′: estimated y for a given x.
    public func predict(_ x: Double) -> Double {
        switch model {
        case .linear: a + b * x
        case .quadratic: a + b * x + (c ?? 0) * x * x
        case .exponential: a * exp(b * x)
        case .logarithmic: x > 0 ? a + b * log(x) : .nan
        case .power: x > 0 || b == b.rounded() ? a * Foundation.pow(x, b) : .nan
        case .inverse: x != 0 ? a + b / x : .nan
        case .generalExponential: a * Foundation.pow(b, x)
        case .proportional: b * x
        }
    }

    /// x′: values of x that give `y` (two for the quadratic model).
    public func estimateX(_ y: Double) -> [Double] {
        switch model {
        case .linear:
            return b == 0 ? [] : [(y - a) / b]
        case .quadratic:
            let cc = c ?? 0
            if cc == 0 { return b == 0 ? [] : [(y - a) / b] }
            let discriminant = b * b - 4 * cc * (a - y)
            if discriminant < 0 { return [] }
            let root = discriminant.squareRoot()
            let x1 = (-b - root) / (2 * cc), x2 = (-b + root) / (2 * cc)
            return discriminant == 0 ? [x1] : [min(x1, x2), max(x1, x2)]
        case .exponential:
            return (y / a > 0 && b != 0) ? [log(y / a) / b] : []
        case .logarithmic:
            return b == 0 ? [] : [exp((y - a) / b)]
        case .power:
            return (y / a > 0 && b != 0) ? [Foundation.pow(y / a, 1 / b)] : []
        case .inverse:
            return y == a ? [] : [b / (y - a)]
        case .generalExponential:
            return (y / a > 0 && b > 0 && b != 1) ? [log(y / a) / log(b)] : []
        case .proportional:
            return b == 0 ? [] : [y / b]
        }
    }

    /// The fitted curve as an expression in x (for graphing and display).
    public var expr: Expr {
        func n(_ v: Double) -> Expr { .decimal(NumberFormatting.roundSignificant(v, 10)) }
        let x = Expr.variable("x")
        switch model {
        case .linear: return .sum([n(a), .product([n(b), x])])
        case .quadratic: return .sum([n(a), .product([n(b), x]), .product([n(c ?? 0), .power(x, .int(2))])])
        case .exponential: return .product([n(a), .power(.constant(.e), .product([n(b), x]))])
        case .logarithmic: return .sum([n(a), .product([n(b), .function(.ln, [x])])])
        case .power: return .product([n(a), .power(x, n(b))])
        case .inverse: return .sum([n(a), .quotient(n(b), x)])
        case .generalExponential: return .product([n(a), .power(n(b), x)])
        case .proportional: return .product([n(b), x])
        }
    }
}

public enum Regression {
    /// Least-squares fit of `model` to the points (frequencies act as weights).
    public static func fit(_ model: RegressionModel, points: [DataPoint]) throws(MathError) -> RegressionResult {
        let usable = points.filter { $0.x.isFinite && $0.y.isFinite && $0.frequency > 0 }
        // Linearising transforms
        var transformed: [(x: Double, y: Double, w: Double)] = []
        for p in usable {
            var X = p.x, Y = p.y
            switch model {
            case .linear, .quadratic, .proportional: break
            case .exponential, .generalExponential:
                guard p.y > 0 else { throw .domain("ta model zahteva y > 0") }
                Y = log(p.y)
            case .logarithmic:
                guard p.x > 0 else { throw .domain("ta model zahteva x > 0") }
                X = log(p.x)
            case .power:
                guard p.x > 0, p.y > 0 else { throw .domain("ta model zahteva x > 0 in y > 0") }
                X = log(p.x); Y = log(p.y)
            case .inverse:
                guard p.x != 0 else { throw .domain("ta model zahteva x ≠ 0") }
                X = 1 / p.x
            }
            transformed.append((X, Y, p.frequency))
        }
        let needed = model == .quadratic ? 3 : model == .proportional ? 1 : 2
        guard Set(transformed.map(\.x)).count >= needed else { throw .domain("premalo različnih točk") }

        var result: RegressionResult
        if model == .proportional {
            // Least squares through the origin: b = Σw·x·y / Σw·x².
            let sxx = transformed.reduce(0) { $0 + $1.x * $1.x * $1.w }
            guard sxx > 0 else { throw .domain("vse vrednosti x so 0") }
            let sxy = transformed.reduce(0) { $0 + $1.x * $1.y * $1.w }
            let r = (try? linearFit(transformed)).flatMap { $0.2 }
            result = RegressionResult(model: model, a: 0, b: sxy / sxx, c: nil, r: r, rSquared: 0)
        } else if model == .quadratic {
            let (a, b, c) = try quadraticFit(transformed)
            result = RegressionResult(model: model, a: a, b: b, c: c, r: nil, rSquared: 0)
        } else {
            let (intercept, slope, r) = try linearFit(transformed)
            switch model {
            case .exponential, .power:
                result = RegressionResult(model: model, a: exp(intercept), b: slope, c: nil, r: r, rSquared: 0)
            case .generalExponential:
                result = RegressionResult(model: model, a: exp(intercept), b: exp(slope), c: nil, r: r, rSquared: 0)
            default:
                result = RegressionResult(model: model, a: intercept, b: slope, c: nil, r: r, rSquared: 0)
            }
        }
        // R² on the original data.
        let W = usable.reduce(0) { $0 + $1.frequency }
        let meanY = usable.reduce(0) { $0 + $1.y * $1.frequency } / W
        let total = usable.reduce(0) { $0 + ($1.y - meanY) * ($1.y - meanY) * $1.frequency }
        let residual = usable.reduce(0) { acc, p in
            let e = p.y - result.predict(p.x)
            return acc + e * e * p.frequency
        }
        result.rSquared = total > 0 ? max(0, 1 - residual / total) : 1
        return result
    }

    /// Weighted least-squares line Y = intercept + slope·X and the correlation r.
    static func linearFit(_ data: [(x: Double, y: Double, w: Double)]) throws(MathError) -> (Double, Double, Double?) {
        let W = data.reduce(0) { $0 + $1.w }
        let mx = data.reduce(0) { $0 + $1.x * $1.w } / W
        let my = data.reduce(0) { $0 + $1.y * $1.w } / W
        let sxx = data.reduce(0) { $0 + ($1.x - mx) * ($1.x - mx) * $1.w }
        let syy = data.reduce(0) { $0 + ($1.y - my) * ($1.y - my) * $1.w }
        let sxy = data.reduce(0) { $0 + ($1.x - mx) * ($1.y - my) * $1.w }
        guard sxx > 0 else { throw .domain("vse vrednosti x so enake") }
        let slope = sxy / sxx
        return (my - slope * mx, slope, syy > 0 ? sxy / (sxx * syy).squareRoot() : nil)
    }

    /// y = a + bx + cx² by weighted least squares on centred x (better conditioned).
    static func quadraticFit(_ data: [(x: Double, y: Double, w: Double)]) throws(MathError) -> (Double, Double, Double) {
        let W = data.reduce(0) { $0 + $1.w }
        let m = data.reduce(0) { $0 + $1.x * $1.w } / W
        var s = [Double](repeating: 0, count: 5)   // Σw·u^k, k = 0…4
        var t = [Double](repeating: 0, count: 3)   // Σw·y·u^k, k = 0…2
        for p in data {
            let u = p.x - m
            var power = 1.0
            for k in 0..<5 {
                s[k] += p.w * power
                if k < 3 { t[k] += p.w * p.y * power }
                power *= u
            }
        }
        let system = Matrix(rows: 3, columns: 3, values: [s[0], s[1], s[2], s[1], s[2], s[3], s[2], s[3], s[4]])
        guard let solution = try? system.solve(Matrix(rows: 3, columns: 1, values: t)) else {
            throw .domain("kvadratne regresije ni mogoče izračunati")
        }
        let a0 = solution[0, 0], b0 = solution[1, 0], c0 = solution[2, 0]
        // Back from u = x − m: a0 + b0(x − m) + c0(x − m)²
        let c = c0
        let b = b0 - 2 * c0 * m
        let a = a0 - b0 * m + c0 * m * m
        return (a, b, c)
    }
}
