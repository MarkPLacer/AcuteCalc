import Foundation
import Testing
@testable import AcuteCore

// MARK: Logarithmic axes

@Suite struct AxisScaleTests {
    // (Key paths and closures stay out of #expect, whose expansion does not compile them.)
    private func majors(_ ticks: [AxisTick]) -> [AxisTick] { ticks.filter { $0.isMajor } }
    private func minors(_ ticks: [AxisTick]) -> [AxisTick] { ticks.filter { !$0.isMajor } }
    private func labels(_ ticks: [AxisTick]) -> [String] { ticks.compactMap { $0.label } }
    private func positions(_ ticks: [AxisTick]) -> [Double] { ticks.map { $0.position } }
    private func xs(_ points: [SpecialPoint]) -> [Double] { points.map { $0.x } }

    private func isSorted(_ values: [Double]) -> Bool { zip(values, values.dropFirst()).allSatisfy { $0 <= $1 } }

    private func matches(_ values: [Double], _ expected: [Double], _ tolerance: Double = 1e-9) -> Bool {
        values.count == expected.count && zip(values, expected).allSatisfy { approx($0, $1, tolerance) }
    }

    @Test func plotCoordinates() {
        let log = AxisScale.logarithmic
        #expect(log.plotCoordinate(1) == 0)
        #expect(approx(log.plotCoordinate(1000), 3))
        #expect(approx(log.plotCoordinate(0.01), -2))
        // 0 lies at −∞ and negative values nowhere: neither is drawn.
        #expect(log.plotCoordinate(0).isNaN)
        #expect(log.plotCoordinate(-5).isNaN)
        #expect(approx(log.value(atPlotCoordinate: 20), 1e20))
        #expect(approx(log.value(atPlotCoordinate: log.plotCoordinate(3.7)), 3.7, 1e-15))
        let values = log.valueRange(-1...2)
        #expect(approx(values.lowerBound, 0.1) && approx(values.upperBound, 100))
        #expect(AxisScale.linear.plotCoordinate(-5) == -5)
        #expect(AxisScale.linear.value(atPlotCoordinate: -5) == -5)

        let axes = AxisScales(x: .logarithmic, y: .linear)
        let plot = axes.plotPoint(SIMD2(100, -3))
        #expect(approx(plot.x, 2) && plot.y == -3)
        let point = axes.point(atPlot: SIMD2(2, -3))
        #expect(approx(point.x, 100) && point.y == -3)
        let semilogY = AxisScales(x: .linear, y: .logarithmic)
        #expect(semilogY.plotPoint(SIMD2(1, -3)).y.isNaN)
        #expect(AxisScales.linear.isLinear && !axes.isLinear)
    }

    @Test func samplingPieces() throws {
        // A linear axis and a range shorter than a decade are sampled whole.
        #expect(AxisScale.linear.samplingPieces(of: 1...1e20) == [1...1e20])
        #expect(AxisScale.logarithmic.samplingPieces(of: 2...3) == [2...3])
        // 10⁰ … 10²⁰: twenty decades that overlap, from exactly 1 to exactly 10²⁰.
        let pieces = AxisScale.logarithmic.samplingPieces(of: 1...1e20)
        #expect(pieces.count == 20)
        #expect(pieces.first?.lowerBound == 1)
        #expect(pieces.last?.upperBound == 1e20)
        for (a, b) in zip(pieces, pieces.dropFirst()) {
            #expect(b.lowerBound < a.upperBound, "\(a) and \(b) do not overlap")
            #expect(a.upperBound / a.lowerBound < 15)
        }
        let fourth = pieces[3]
        #expect(fourth.lowerBound < 1000 && fourth.upperBound > 10_000)
        // Beyond 48 decades the pieces get wider instead of more.
        #expect(AxisScale.logarithmic.samplingPieces(of: 1e-100...1e100).count == 48)
        // A view past 10³⁰⁸ shows values up to ∞: the pieces end at the largest Double.
        let beyond = AxisScale.logarithmic.samplingPieces(of: 1...Double.infinity)
        #expect(beyond.count == 48)
        #expect(beyond.last?.upperBound == .greatestFiniteMagnitude)
        // Nothing to cut where the range is not positive.
        #expect(AxisScale.logarithmic.samplingPieces(of: -1...1e9) == [-1...1e9])
    }

    @Test func decadeLabels() {
        // 10ⁿ, written out where that is not longer: 1, 10, 100 and 0,1, 0,01.
        var written: [String] = []
        for exponent in -4...4 { written.append(LogarithmicAxis.decadeLabel(exponent)) }
        #expect(written == ["10⁻⁴", "10⁻³", "0,01", "0,1", "1", "10", "100", "10³", "10⁴"])
        #expect(LogarithmicAxis.decadeLabel(20) == "10²⁰")
        #expect(LogarithmicAxis.decadeLabel(-12) == "10⁻¹²")
        #expect(LogarithmicAxis.decadeLabel(-2, separator: ".") == "0.01")
        #expect(LogarithmicAxis.multipleLabel(5, 2, separator: ",") == "500")
        #expect(LogarithmicAxis.multipleLabel(5, -2, separator: ",") == "0,05")
        #expect(LogarithmicAxis.multipleLabel(2, 3, separator: ",") == "2·10³")
        #expect(LogarithmicAxis.multipleLabel(3, -7, separator: ",") == "3·10⁻⁷")
    }

    @Test func zoomedOutDecades() {
        // The spectrum 10⁰ … 10²⁰ on a phone (about 20 points per decade): every 5th decade is labelled.
        let phone = LogarithmicAxis.ticks(in: 0...20, pointsPerDecade: 19.5)
        #expect(positions(majors(phone)) == [0, 5, 10, 15, 20])
        #expect(labels(phone) == ["1", "10⁵", "10¹⁰", "10¹⁵", "10²⁰"])
        #expect(minors(phone).count == 16)
        // On an iPad (about 48 points per decade) every second one, minor lines at the others.
        let pad = LogarithmicAxis.ticks(in: 0...20, pointsPerDecade: 48)
        #expect(positions(majors(pad)) == [0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20])
        #expect(positions(minors(pad)) == [1, 3, 5, 7, 9, 11, 13, 15, 17, 19])
        #expect(labels(pad).last == "10²⁰")
        // Far out: every 100th decade; the values beyond the Doubles are 0 and ∞.
        let far = LogarithmicAxis.ticks(in: -1000...1000, pointsPerDecade: 1)
        #expect(far.count == 101)
        #expect(majors(far).count == 21)
        #expect(labels(far).first == "10⁻¹⁰⁰⁰")
        #expect(far.first?.value == 0)
        #expect(far.last?.value == .infinity)
    }

    @Test func decadesWithMinorLines() throws {
        // 100 points per decade: 1, 10, 100 labelled, 2 … 9 times each decade as minor lines.
        let ticks = LogarithmicAxis.ticks(in: 0...2, pointsPerDecade: 100)
        #expect(labels(ticks) == ["1", "10", "100"])
        let minor = minors(ticks)
        try #require(minor.count == 16)
        #expect(matches([minor[0].value, minor[7].value, minor[8].value, minor[15].value], [2, 9, 20, 90]))
        #expect(isSorted(positions(ticks)))
        #expect(approx(ticks[1].position, log10(2.0)))
    }

    @Test func zoomedInMultiples() {
        // 300 points per decade: 1, 2 and 5 times each decade.
        let fives = LogarithmicAxis.ticks(in: 0...1, pointsPerDecade: 300)
        #expect(labels(fives) == ["1", "2", "5", "10"])
        let ranks = majors(fives).map { $0.rank }
        #expect(ranks == [0, 1, 1, 0])
        let between = minors(fives).map { $0.value }
        #expect(matches(between, [3, 4, 6, 7, 8, 9]))
        // 800 points per decade: every whole multiple, the halves as minor lines.
        let wholes = LogarithmicAxis.ticks(in: 3...4, pointsPerDecade: 800)
        #expect(labels(wholes) == ["10³", "2·10³", "3·10³", "4·10³", "5·10³", "6·10³", "7·10³", "8·10³", "9·10³", "10⁴"])
        #expect(minors(wholes).count == 9)
        let small = LogarithmicAxis.ticks(in: -2...(-1), pointsPerDecade: 800, decimalSeparator: ".")
        #expect(Array(labels(small).prefix(3)) == ["0.01", "0.02", "0.03"])
    }

    @Test func evenlySpacedWithinADecade() throws {
        // 3000 points per decade over 1,93 … 3,07: steps of 0,2 (0,05 minor), about 90 points at 3.
        let ticks = LogarithmicAxis.ticks(in: log10(1.93)...log10(3.07), pointsPerDecade: 3000)
        #expect(labels(ticks) == ["2", "2,2", "2,4", "2,6", "2,8", "3"])
        #expect(minors(ticks).count == 17)
        let major = positions(majors(ticks))
        try #require(major.count == 6)
        let gap = (major[5] - major[4]) * 3000
        #expect(gap > 60 && gap < 130)
        // Large values: m·10ⁿ with the decimals of the step.
        let giga = LogarithmicAxis.ticks(in: log10(1.99e9)...log10(2.07e9), pointsPerDecade: 20_000)
        #expect(labels(giga) == ["2·10⁹", "2,02·10⁹", "2,04·10⁹", "2,06·10⁹"])
        // 9,99…·10⁹ rounded to the step is 1·10¹⁰.
        #expect(LogarithmicAxis.evenLabel(1e10 - 1, step: 1e8, separator: ",") == "1·10¹⁰")
    }

    @Test func linesStayFewAndApart() {
        // Across the zoom range the major lines are well apart and never too many to draw.
        for exponent in stride(from: -3.0, through: 6, by: 0.25) {
            let perDecade = pow(10, exponent)
            let ticks = LogarithmicAxis.ticks(in: 7.3...(7.3 + 1400 / perDecade), pointsPerDecade: perDecade)
            #expect(ticks.count < 400, "\(perDecade) points per decade: \(ticks.count) lines")
            #expect(!ticks.isEmpty, "\(perDecade) points per decade: no lines")
            #expect(isSorted(positions(ticks)))
            let major = positions(majors(ticks))
            let gaps = zip(major, major.dropFirst()).map { ($1 - $0) * perDecade }
            let closest = gaps.min() ?? .infinity
            #expect(closest > 25, "\(perDecade) points per decade: majors \(closest) points apart")
        }
        // Out of range or without a scale: no lines (and no trap).
        #expect(LogarithmicAxis.ticks(in: 1e13...(1e13 + 5), pointsPerDecade: 50).isEmpty)
        #expect(LogarithmicAxis.ticks(in: 0...5, pointsPerDecade: 0).isEmpty)
        #expect(LogarithmicAxis.ticks(in: 0...5, pointsPerDecade: .infinity).isEmpty)
    }

    // MARK: Analysis

    @Test func zerosOverManyDecades() throws {
        // (x − 2)(x − 300)(x − 5·10⁷) on 1 … 10⁹: 2400 even samples are 4·10⁵ apart and miss 2 and 300.
        let f = try parse("(x-2)(x-300)(x-50000000)")
        let context = EvaluationContext()
        let even = FunctionAnalyzer.analyze(f, range: 1...1e9, context: context)
        let evenZeros = xs(even.zeros)
        #expect(!evenZeros.contains(2))
        let analysis = FunctionAnalyzer.analyze(f, range: 1...1e9, scale: .logarithmic, context: context)
        #expect(matches(xs(analysis.zeros), [2, 300, 5e7]))
        // A maximum between 2 and 300, a minimum between 300 and 5·10⁷.
        #expect(analysis.extrema.count == 2)
        let first = try #require(analysis.extrema.first)
        let second = try #require(analysis.extrema.last)
        #expect(first.kind == .maximum && first.x > 2 && first.x < 300)
        #expect(second.kind == .minimum && second.x > 300 && second.x < 5e7)
        #expect(analysis.range == 1...1e9)
    }

    @Test func pointsOnDecadeBordersOnce() throws {
        // A minimum at x = 10 lies where two pieces overlap: found once, the intervals joined.
        let context = EvaluationContext()
        let analysis = FunctionAnalyzer.analyze(try parse("(x-10)^2+1"), range: 1...1000, scale: .logarithmic, context: context)
        #expect(analysis.extrema.count == 1)
        let minimum = try #require(analysis.extrema.first)
        #expect(minimum.kind == .minimum && approx(minimum.x, 10) && approx(minimum.y, 1))
        #expect(analysis.decreasing.count == 1 && analysis.increasing.count == 1)
        let rising = try #require(analysis.increasing.first)
        #expect(approx(rising.lowerBound, 10) && rising.upperBound == 1000)
        let zero = FunctionAnalyzer.analyze(try parse("x-10"), range: 1...1000, scale: .logarithmic, context: context)
        #expect(matches(xs(zero.zeros), [10]))
        // The pole of 1/(x − 50)² and its asymptote y = 0, as on a linear axis.
        let pole = FunctionAnalyzer.analyze(try parse("1/(x-50)^2"), range: 0.01...1e6, scale: .logarithmic, context: context)
        #expect(matches(pole.poles, [50], 1e-6))
        #expect(abs(pole.horizontalAsymptoteRight ?? .nan) < 1e-9)
    }

    @Test func linearScaleIsUnchanged() throws {
        let f = try parse("x^3-3x")
        let context = EvaluationContext()
        let plain = FunctionAnalyzer.analyze(f, range: -3...3, context: context)
        let linear = FunctionAnalyzer.analyze(f, range: -3...3, scale: .linear, context: context)
        #expect(linear.allPoints == plain.allPoints)
        #expect(linear.increasing == plain.increasing)
        #expect(linear.convex == plain.convex)
    }

    @Test func intersectionsAndHolesOverManyDecades() throws {
        let context = EvaluationContext()
        // x² = 3x − 2 at x = 1 and 2, between two even samples 4·10⁵ apart, on 10⁻³ … 10⁹.
        let parabola = FunctionAnalyzer.intersections(try parse("x^2"), try parse("3x-2"), range: 1e-3...1e9,
                                                      scale: .logarithmic, context: context)
        #expect(matches(xs(parabola), [1, 2]))
        let even = FunctionAnalyzer.intersections(try parse("x^2"), try parse("3x-2"), range: 1e-3...1e9, context: context)
        #expect(even.isEmpty)
        // 1/x = x/10⁶ at x = 1000, a decade where two pieces overlap: once.
        let hyperbola = FunctionAnalyzer.intersections(try parse("1/x"), try parse("x/1000000"), range: 1e-3...1e9,
                                                       scale: .logarithmic, context: context)
        #expect(matches(xs(hyperbola), [1000]))
        // The hole of (x² − 4)/(x − 2) at (2, 4), and x ≠ 2 for the domain.
        let analysis = FunctionAnalyzer.analyze(try parse("(x^2-4)/(x-2)"), range: 1e-3...1e9, scale: .logarithmic, context: context)
        let holes = analysis.holes
        #expect(holes.count == 1)
        #expect(matches(analysis.excludedPoints ?? [], [2]))
        let hole = try #require(holes.first)
        #expect(approx(hole.x, 2) && approx(hole.y, 4))
    }
}
