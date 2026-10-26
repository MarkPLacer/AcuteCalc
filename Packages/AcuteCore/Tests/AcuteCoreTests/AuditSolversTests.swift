import Foundation
import Testing
@testable import AcuteCore

// MARK: Audit: equations, inequalities and triangles

@Suite struct AuditSolversTests {
    func inequality(_ s: String) throws -> InequalitySolution {
        guard case .relation(let lhs, let op, let rhs) = try parse(s) else { throw MathError.syntax("ni neenačba") }
        return try #require(InequalitySolver.solve(lhs, op, rhs, context: EvaluationContext()))
    }

    func equation(_ lhs: String, _ rhs: String) throws -> EquationResult {
        try EquationSolver.solve(lhs: try parse(lhs), rhs: try parse(rhs), context: EvaluationContext())
    }

    // MAT-05: exact roots outside the sampled window −1000…1000 were dropped.

    @Test func inequalityKeepsPolynomialRootsBeyondThousand() throws {
        let above = try inequality("x>2000")
        try #require(above.intervals.count == 1)
        #expect(above.intervals[0].lower == 2000 && above.intervals[0].upper == .infinity && !above.intervals[0].lowerIncluded)
        let profit = try inequality("12x-15000>0")
        try #require(profit.intervals.count == 1)
        #expect(profit.intervals[0].lower == 1250 && profit.intervals[0].upper == .infinity)
        let below = try inequality("x<2000")
        try #require(below.intervals.count == 1)
        #expect(below.intervals[0].lower == -.infinity && below.intervals[0].upper == 2000 && !below.intervals[0].upperIncluded)
    }

    @Test func chainBeyondThousandIsBounded() throws {
        let calculation = CalculationEngine.calculate(try parse("0<x<5000"), variables: [:], exactVariables: [:], settings: CalculationSettings())
        guard case .inequality(let s) = calculation.outcome else {
            Issue.record("no solution of the chain 0 < x < 5000")
            return
        }
        try #require(s.intervals.count == 1)
        #expect(s.intervals[0].lower == 0 && s.intervals[0].upper == 5000)
        #expect(!s.intervals[0].lowerIncluded && !s.intervals[0].upperIncluded)
    }

    // MAT-06: numeric solutions beyond ±1000 were never searched ("Ni realnih rešitev").

    @Test func equationSolutionsBeyondThousandAreFound() throws {
        let common = try equation("log(x)", "4")
        try #require(common.solutions.count == 1)
        #expect(abs(common.solutions[0].value - 10_000) < 1e-12 * 10_000)
        let root = try equation("sqrt(x)", "40")
        try #require(root.solutions.count == 1)
        #expect(abs(root.solutions[0].value - 1600) < 1e-12 * 1600)
        let natural = try equation("ln(x)", "7")
        try #require(natural.solutions.count == 1)
        #expect(abs(natural.solutions[0].value - exp(7)) < 1e-12 * exp(7))
    }

    @Test func inequalitySolutionBeyondThousand() throws {
        let common = try inequality("log(x)>4")
        try #require(common.intervals.count == 1)
        #expect(abs(common.intervals[0].lower - 10_000) < 1e-8 && common.intervals[0].upper == .infinity)
        // 1/x < 0,0001 → x < 0 or x > 10⁴
        let reciprocal = try inequality("1/x<0.0001")
        try #require(reciprocal.intervals.count == 2)
        #expect(reciprocal.intervals[0].lower == -.infinity && reciprocal.intervals[0].upper == 0 && !reciprocal.intervals[0].upperIncluded)
        #expect(abs(reciprocal.intervals[1].lower - 10_000) < 1e-8 && reciprocal.intervals[1].upper == .infinity)
    }

    // MAT-08: a pole in the same gap of the sign scan as a zero (or at the end of a period) was missed.

    @Test func rationalInequalityFindsPoleNextToZero() throws {
        // (4x − 1)/(3x − 1) ≥ 0 → x ≤ 1/4 or x > 1/3
        let s = try inequality("(4x-1)/(3x-1)>=0")
        try #require(s.intervals.count == 2)
        #expect(s.intervals[0].lower == -.infinity && abs(s.intervals[0].upper - 0.25) < 1e-12 && s.intervals[0].upperIncluded)
        #expect(abs(s.intervals[1].lower - 1.0 / 3) < 1e-12 && !s.intervals[1].lowerIncluded && s.intervals[1].upper == .infinity)
        // (5x − 1)/(5x − 2) ≥ 0 → x ≤ 1/5 or x > 2/5
        let t = try inequality("(5x-1)/(5x-2)>=0")
        try #require(t.intervals.count == 2)
        #expect(abs(t.intervals[0].upper - 0.2) < 1e-12 && t.intervals[0].upperIncluded)
        #expect(abs(t.intervals[1].lower - 0.4) < 1e-12 && !t.intervals[1].lowerIncluded)
    }

    @Test func poleAtTheEndOfThePeriodIsExcluded() throws {
        // cot x < 0 → π/2 < x < π (+ kπ). In floating point cot π ≈ −8·10¹⁵ is finite, so π was included.
        let s = try inequality("cot(x)<0")
        #expect(s.period.map { abs($0 - .pi) < 1e-12 } == true)
        try #require(s.intervals.count == 1)
        #expect(abs(s.intervals[0].lower - .pi / 2) < 1e-12 && abs(s.intervals[0].upper - .pi) < 1e-12)
        #expect(!s.intervals[0].lowerIncluded && !s.intervals[0].upperIncluded)
    }

    @Test func rationalInequalityBeyondThousand() throws {
        // (x − 2000)/(x − 3000) > 0 → x < 2000 or x > 3000 (zero and pole both outside the window)
        let s = try inequality("(x-2000)/(x-3000)>0")
        try #require(s.intervals.count == 2)
        #expect(s.intervals[0].lower == -.infinity && abs(s.intervals[0].upper - 2000) < 1e-9 && !s.intervals[0].upperIncluded)
        #expect(s.intervals[1].lower == 3000 && !s.intervals[1].lowerIncluded && s.intervals[1].upper == .infinity)
    }

    // MAT-09: Durand–Kerner reaches only ~10⁻⁸ on a double root; irrational double roots were lost.

    @Test func repeatedIrrationalRootsStayReal() throws {
        let r = try equation("(x^2-5)^2", "0")
        try #require(r.solutions.count == 2)
        #expect(abs(r.solutions[0].value + 5.0.squareRoot()) < 1e-12)
        #expect(abs(r.solutions[1].value - 5.0.squareRoot()) < 1e-12)
        #expect(r.complexSolutions.isEmpty)
        // (x² + x − 1)² = 0 → x = (−1 ± √5)/2
        let golden = try equation("(x^2+x-1)^2", "0")
        try #require(golden.solutions.count == 2)
        #expect(abs(golden.solutions[0].value - (-1 - 5.0.squareRoot()) / 2) < 1e-12)
        #expect(abs(golden.solutions[1].value - (5.0.squareRoot() - 1) / 2) < 1e-12)
    }

    @Test func repeatedComplexRootsAreListedOnce() throws {
        // (x² + 1)² = 0 → x = ±i, each once and accurate (not four values ±i ± 10⁻⁸).
        let r = try equation("(x^2+1)^2", "0")
        #expect(r.solutions.isEmpty)
        try #require(r.complexSolutions.count == 2)
        let plus = r.complexSolutions.contains { ($0 - Complex(0, 1)).magnitude < 1e-12 }
        let minus = r.complexSolutions.contains { ($0 - Complex(0, -1)).magnitude < 1e-12 }
        #expect(plus && minus)
    }

    @Test func inequalityWithDoubleIrrationalRoots() throws {
        // x⁴ − 10x² + 25 = (x² − 5)² > 0 → every x except ±√5
        let s = try inequality("x^4-10x^2+25>0")
        try #require(s.intervals.count == 3)
        #expect(abs(s.intervals[0].upper + 5.0.squareRoot()) < 1e-12 && !s.intervals[0].upperIncluded)
        #expect(abs(s.intervals[1].lower + 5.0.squareRoot()) < 1e-12 && abs(s.intervals[1].upper - 5.0.squareRoot()) < 1e-12)
        #expect(abs(s.intervals[2].lower - 5.0.squareRoot()) < 1e-12 && s.intervals[2].upper == .infinity)
    }

    // MAT-14: a local minimum of |f| was accepted against the largest |f| of the whole range.

    @Test func nearTangencyIsNotReportedAsRoot() throws {
        // eˣ − x − 0,9995 ≥ 0,0005 (minimum at x = 0) and cosh x − 0,9996 ≥ 0,0004: no real solution.
        #expect(try equation("e^x", "x+0.9995").solutions.isEmpty)
        #expect(try equation("cosh(x)", "0.9996").solutions.isEmpty)
        #expect(try inequality("e^x<=x+0.9995").isEmpty)
    }

    @Test func trueTangencyIsStillARoot() throws {
        // Guard for MAT-14 (passes before and after): eˣ = x + 1 touches at 0, sin x = 1 at π/2.
        // A touching root is located only to about √ε, hence 1e-7.
        let touching = try equation("e^x", "x+1")
        try #require(touching.solutions.count == 1)
        #expect(abs(touching.solutions[0].value) < 1e-7)
        let sine = try equation("sin(x)", "1")
        try #require(sine.solutions.count == 1)
        #expect(abs(sine.solutions[0].value - .pi / 2) < 1e-7)
    }

    // MAT-11: sin β = 0,9999999999999998 instead of 1 gave two nearly equal triangles.

    @Test func ssaBoundaryCaseHasOneRightTriangle() throws {
        // a = 5, b = 10, α = 30°: a = b·sin α, so β = 90° and c = 5√3.
        let t = try TriangleSolver.solve(TriangleInput(a: 5, b: 10, alpha: 30 * Double.pi / 180))
        try #require(t.count == 1)
        #expect(t[0].isRight)
        #expect(abs(t[0].beta - .pi / 2) < 1e-12)
        #expect(abs(t[0].c - 5 * 3.0.squareRoot()) < 1e-12)
        // Unchanged: a = 6, b = 8, α = 30° still has two triangles.
        #expect(try TriangleSolver.solve(TriangleInput(a: 6, b: 8, alpha: .pi / 6)).count == 2)
    }

    // Underflow: x²·eˣ is exactly 0 in floating point below x ≈ −745, which listed ~2500 "solutions".

    @Test func underflowIsNoRoot() throws {
        let product = try equation("x^2*e^x", "0")
        try #require(product.solutions.count == 1)
        #expect(abs(product.solutions[0].value) < 1e-12)
        #expect(try equation("e^x", "0").solutions.isEmpty)
        #expect(try equation("e^(-x)", "0").solutions.isEmpty)
        // (1 − x)·e⁻ˣ underflows to −0 beyond x ≈ 745: x = 1 only.
        let decaying = try equation("(1-x)*e^(-x)", "0")
        try #require(decaying.solutions.count == 1)
        #expect(abs(decaying.solutions[0].value - 1) < 1e-12)
    }

    @Test func inequalityAcrossAnUnderflowedTail() throws {
        // x²·eˣ > 0 for every x ≠ 0
        let s = try inequality("x^2*e^x>0")
        try #require(s.intervals.count == 2)
        #expect(s.intervals[0].lower == -.infinity && abs(s.intervals[0].upper) < 1e-12 && !s.intervals[0].upperIncluded)
        #expect(abs(s.intervals[1].lower) < 1e-12 && !s.intervals[1].lowerIncluded && s.intervals[1].upper == .infinity)
    }

    // Overflow: eˣ = ∞ beyond x ≈ 709.8 is a value too large to represent, not an end of the domain.

    @Test func overflowIsNoDomainEdge() throws {
        // Was (−∞; 709,78].
        #expect(try inequality("e^x>x+0.9995").isAllReals)
        // 10ˣ > 5 → x > log 5 (was (log 5; 308,25])
        let power = try inequality("10^x>5")
        try #require(power.intervals.count == 1)
        #expect(abs(power.intervals[0].lower - log10(5)) < 1e-12 && power.intervals[0].upper == .infinity)
        // eˣ > 10³⁰⁰ → x > 300·ln 10; the sample point of that piece overflows itself.
        let huge = try inequality("e^x>10^300")
        try #require(huge.intervals.count == 1)
        #expect(abs(huge.intervals[0].lower - 300 * log(10)) < 1e-9 && huge.intervals[0].upper == .infinity)
    }

    // Steep roots: ∛(x² − 2) is about 6·10⁻⁶ at the doubles next to √2, above every tolerance.

    @Test func steepOddRootsAreFound() throws {
        let r = try equation("cbrt(x^2-2)", "0")
        try #require(r.solutions.count == 2)
        #expect(abs(r.solutions[0].value + 2.0.squareRoot()) < 1e-12)
        #expect(abs(r.solutions[1].value - 2.0.squareRoot()) < 1e-12)
        // Graph analysis on the usual window.
        let graph = FunctionAnalyzer.analyze(try parse("cbrt(x^2-2)"), range: -10...10, context: EvaluationContext())
        try #require(graph.zeros.count == 2)
        #expect(abs(graph.zeros[1].x - 2.0.squareRoot()) < 1e-12)
        let shifted = FunctionAnalyzer.analyze(try parse("cbrt(x-0.3)"), range: -10...10, context: EvaluationContext())
        try #require(shifted.zeros.count == 1)
        #expect(abs(shifted.zeros[0].x - 0.3) < 1e-12)
        // A pole still is no root: 1/∛(x − 0,3) = 0 has no solution.
        #expect(try equation("1/cbrt(x-0.3)", "0").solutions.isEmpty)
    }

    @Test func steepRootsCloseTheInterval() throws {
        // ∛(x² − 2) ≥ 0 → x ≤ −√2 or x ≥ √2; the ends were taken for poles and excluded.
        let s = try inequality("cbrt(x^2-2)>=0")
        try #require(s.intervals.count == 2)
        #expect(abs(s.intervals[0].upper + 2.0.squareRoot()) < 1e-12 && s.intervals[0].upperIncluded)
        #expect(abs(s.intervals[1].lower - 2.0.squareRoot()) < 1e-12 && s.intervals[1].lowerIncluded)
    }

    // GAP-period-1: the family x = 0 + k·T was lost when the root came out a few ulps below 0.

    func calculatorSolutions(_ input: String, unit: AngleUnit = .radians) throws -> EquationResult? {
        let calculation = CalculationEngine.calculate(try parse(input), variables: [:], exactVariables: [:],
                                                      settings: CalculationSettings(angleUnit: unit))
        guard case .solutions(let result) = calculation.outcome else { return nil }
        return result
    }

    @Test func solutionFamilyAtZeroIsKept() throws {
        let cases: [(input: String, unit: AngleUnit, period: Double, roots: [Double])] = [
            ("2cos(x-pi/3)=1", .radians, 2 * .pi, [0, 2 * .pi / 3]),     // was 2π/3 only
            ("2sin(x-pi/6)+1=0", .radians, 2 * .pi, [0, 4 * .pi / 3]),   // was 4π/3 only
            ("sin(x-pi)=0", .radians, 2 * .pi, [0, .pi]),                // was π only
            ("tan(x-3*pi/4)=1", .radians, .pi, [0]),                     // was "Ni realnih rešitev"
            ("2cos(x-60)=1", .degrees, 360, [0, 120]),                   // was 120° only
            ("sin(x-pi)^2=0", .radians, .pi, [0]),                       // touching at 0, was none
        ]
        for c in cases {
            let result = try #require(try calculatorSolutions(c.input, unit: c.unit), "\(c.input)")
            #expect(result.period.map { abs($0 - c.period) < 1e-9 * c.period } == true, "\(c.input)")
            let values = result.solutions.map(\.value)
            #expect(values.count == c.roots.count, "\(c.input): \(values)")
            for x in c.roots {
                #expect(values.contains { abs($0 - x) < 1e-9 * max(1, c.period) }, "\(c.input): x = \(x) + k·T missing")
            }
        }
    }

    @Test func periodicInequalityEndsAtZero() throws {
        // 2cos(x − π/3) > 1 ⇔ x ∈ (0; 2π/3) + 2kπ (was [0; 2π/3), although 0 does not solve it)
        let s = try inequality("2cos(x-pi/3)>1")
        try #require(s.intervals.count == 1)
        #expect(abs(s.intervals[0].lower) < 1e-12 && !s.intervals[0].lowerIncluded)
        #expect(abs(s.intervals[0].upper - 2 * .pi / 3) < 1e-9 && !s.intervals[0].upperIncluded)
        // 2cos(x − π/3) ≤ 1 ⇔ x = 0 or 2π/3 ≤ x < 2π (+ 2kπ); x = 0 was missing
        let t = try inequality("2cos(x-pi/3)<=1")
        #expect(t.intervals.contains { $0.isPoint && abs($0.lower) < 1e-12 })
    }

    // GAP-curve-length-area-1: on the default interval a closed curve traced n times had n·L and n·S.

    func curve(_ text: String) throws -> (length: Double, area: Double?) {
        let calculation = CalculationEngine.calculate(try parse(text), variables: [:], exactVariables: [:], settings: CalculationSettings())
        guard case .special(.curve(let length, let area), _) = calculation.outcome else {
            Issue.record("\(text) has no length")
            return (0, nil)
        }
        return (length, area)
    }

    @Test func curveTracedTwiceIsMeasuredOnce() throws {
        // r = sin θ is the circle x² + (y − ½)² = ¼, traced twice on [0, 2π]: L = π, S = π/4 (was 2π, π/2)
        let circle = try curve("r = sin(theta)")
        #expect(abs(circle.length - Double.pi) < 1e-9)
        #expect(circle.area.map { abs($0 - Double.pi / 4) < 1e-9 } == true)
        // r = sin 3θ, traced twice: S = π/4, L = 6·E(8/9) = 6,682446610277629
        let rose = try curve("r = sin(3theta)")
        #expect(abs(rose.length - 6.682446610277629) < 1e-8)
        #expect(rose.area.map { abs($0 - Double.pi / 4) < 1e-9 } == true)
        // (cos 2t, sin 2t): the unit circle twice, L = 2π, S = π (was 4π, 2π)
        let unit = try curve("(cos(2t), sin(2t))")
        #expect(abs(unit.length - 2 * Double.pi) < 1e-9)
        #expect(unit.area.map { abs($0 - Double.pi) < 1e-9 } == true)
    }

    @Test func typedIntervalKeepsThePathLength() throws {
        // Guard (passes before and after): with 0 ≤ θ ≤ 2π typed, L is the path ∫₀^{2π} √(r² + r′²) dθ = 2π.
        let row = MathRow([.symbol(.variable("r")), .symbol(.equals), .function(.sin, argument: MathRow([.symbol(.variable("θ"))])),
                           .symbol(.comma), .symbol(.digit(0)), .symbol(.lessOrEqual), .symbol(.variable("θ")),
                           .symbol(.lessOrEqual), .symbol(.digit(2)), .symbol(.constant(.pi))])
        let calculation = CalculationEngine.calculate(row, variables: [:], exactVariables: [:], settings: CalculationSettings())
        guard case .special(.curve(let length, _), _) = calculation.outcome else {
            Issue.record("r = sin θ, 0 ≤ θ ≤ 2π has no length")
            return
        }
        #expect(abs(length - 2 * Double.pi) < 1e-9)
    }
}
