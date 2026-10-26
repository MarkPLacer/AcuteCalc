import Foundation
import Testing
@testable import AcuteCore

// MARK: Function analysis (audit)

@Suite struct AuditFunctionAnalysisTests {
    /// Orodja → Analiza funkcije: Parser.parse, FunctionAnalysisView(range: −10…10) → FunctionAnalyzer.analyze.
    func analysis(_ text: String, range: ClosedRange<Double> = -10...10) throws -> FunctionAnalysis {
        FunctionAnalyzer.analyze(try Parser.parse(text), range: range, context: EvaluationContext())
    }

    /// Računalo: CalculationEngine.calculate → EquationSolver.solve (no range).
    func solutions(_ text: String) throws -> EquationResult? {
        let calculation = CalculationEngine.calculate(try Parser.parse(text), variables: [:], exactVariables: [:], settings: CalculationSettings())
        guard case .solutions(let result) = calculation.outcome else { return nil }
        return result
    }

    @Test func functionsRepeatingOnlyForPositiveXAreNotPeriodic() throws {
        // sin|x|, frac x = x − trunc x and frac|x| repeat only for x > 0: sin|−π/2| = 1 but
        // sin|−π/2 + 2π| = −1, frac(−0.5) = −0.5 but frac(0.5) = 0.5. All probes were positive, so the
        // analysis said "Periodična, osnovna perioda 2π" and "… 1".
        for text in ["sin(abs(x))", "frac(x)", "frac(abs(x))"] {
            let period = try analysis(text).period
            #expect(period == nil, "\(text): \(String(describing: period))")
        }
        // Periodic on all of ℝ, as before: x − ⌊x⌋ (1), |sin x| and tan x (π), sin x (2π).
        for (text, expected) in [("x-floor(x)", 1.0), ("abs(sin(x))", Double.pi), ("tan(x)", Double.pi), ("sin(x)", 2 * Double.pi)] {
            let period = try analysis(text).period
            #expect(period == expected, "\(text): \(String(describing: period))")
        }
    }

    @Test func equationsWithSinAbsAndFracHaveNoFalsePeriod() throws {
        // sin|x| = 1/2 gave "π/6 + k·2π; 5π/6 + k·2π, k ∈ ℤ": k = −1 gives sin|−11π/6| = −1/2, and
        // −π/6, −5π/6 … were missing.
        let sine = try #require(try solutions("sin(abs(x))=1/2"))
        #expect(sine.period == nil)
        #expect(sine.solutions.contains { abs($0.value + .pi / 6) < 1e-9 })
        let allSolve = sine.solutions.allSatisfy { abs(sin(abs($0.value)) - 0.5) < 1e-9 }
        #expect(allSolve)
        // frac(x) = −1/2 gave "Ni realnih rešitev" (period 1 seen for x > 0), but frac(−1/2) = −1/2.
        let fraction = try #require(try solutions("frac(x)=-1/2"))
        #expect(fraction.period == nil)
        #expect(fraction.solutions.contains { abs($0.value + 0.5) < 1e-9 })
    }

    @Test func simplePolesAreFound() throws {
        // 1/(x − 2) on −10…10: the sample x = 2 lands on the pole (NaN from the VM), and
        // |f(2 ± 2·10⁻⁵)| = 5·10⁴ stayed under the 10⁵ threshold: no "Navpična: x = 2".
        let simple = try analysis("1/(x-2)").poles
        #expect(simple == [2])
        let two = try analysis("x^2/(x^2-4)").poles
        #expect(two == [-2, 2])
        // 1/x² at the sample x = 0: the square of 0.nextUp is 0 again.
        let secondOrder = try analysis("1/x^2").poles
        #expect(secondOrder == [0])
        // tan x on −10…10: ±π/2, ±3π/2, ±5π/2 (|tan(π/2 ± 2·10⁻⁵)| = 5·10⁴).
        let tangent = try analysis("tan(x)").poles
        #expect(tangent.count == 6)
        let onZerosOfCosine = tangent.allSatisfy { abs(cos($0)) < 1e-9 }
        #expect(onZerosOfCosine)
        // The graph on a 402 pt wide canvas (visibleX = ±402/96): the middle sample is x = 0.
        let graph = try analysis("1/x", range: -4.1875...4.1875).poles
        #expect(graph == [0])
    }

    @Test func intervalsDoNotRunAcrossAPole() throws {
        // 1/(x − 2): f′ = −1/(x − 2)² < 0 and f″ = 2/(x − 2)³, so it decreases on (−10, 2) and on
        // (2, 10), not on (−10, 10) (f(1) = −1 < f(3) = 1); concave on (−10, 2), convex on (2, 10).
        let a = try analysis("1/(x-2)")
        #expect(a.increasing.isEmpty)
        #expect(a.decreasing == [-10.0...2.0, 2.0...10.0])
        #expect(a.concave == [-10.0...2.0])
        #expect(a.convex == [2.0...10.0])
        // (x² − 4)/(x − 1) = x + 1 − 3/(x − 1): f′ = 1 + 3/(x − 1)² > 0 and f″ = −6/(x − 1)³.
        let b = try analysis("(x^2-4)/(x-1)")
        #expect(b.increasing == [-10.0...1.0, 1.0...10.0])
        #expect(b.decreasing.isEmpty)
        #expect(b.convex == [-10.0...1.0])
        #expect(b.concave == [1.0...10.0])
    }

    @Test func intervalsStayInTheDomain() throws {
        // ln x with "Od x = −10, Do x = 5": f′ = 1/x and f″ = −1/x² exist for x < 0 too, so the analysis
        // said "Pada na (−10, 5)" and "Konkavna (∩) na (−10, 5)"; ln x increases and is concave on (0, 5).
        let ln = try analysis("ln(x)", range: -10...5)
        #expect(ln.increasing == [0.0...5.0])
        #expect(ln.decreasing.isEmpty)
        #expect(ln.concave == [0.0...5.0])
        #expect(ln.convex.isEmpty)
        // arcsin x is defined on [−1, 1] and increases there (f′ = 1/√(1 − x²)), concave on (−1, 0) and
        // convex on (0, 1) (f″ = x/(1 − x²)^(3/2)); it was "Narašča na (−10, 10)".
        let arcsine = try analysis("arcsin(x)")
        #expect(arcsine.increasing == [-1.0...1.0])
        #expect(arcsine.concave == [-1.0...0.0])
        #expect(arcsine.convex == [0.0...1.0])
        // √x on −10…10: the only midpoint was 0, the end of the domain (f′(0) undefined): no interval.
        let root = try analysis("sqrt(x)")
        #expect(root.increasing == [0.0...10.0])
        #expect(root.concave == [0.0...10.0])
        // √(4 − x²): increasing on (−2, 0), decreasing on (0, 2), concave on (−2, 2).
        let semicircle = try analysis("sqrt(4-x^2)")
        #expect(semicircle.increasing == [-2.0...0.0])
        #expect(semicircle.decreasing == [0.0...2.0])
        #expect(semicircle.concave == [-2.0...2.0])
        #expect(semicircle.convex.isEmpty)
    }

    @Test func intervalsSurviveAHoleAtTheirMidpoint() throws {
        // x²/x = x and x³/x = x² for x ≠ 0 with "Od x = −3,2, Do x = 3,2": no sample lands on 0 (the
        // middle one is 4.4·10⁻¹⁶), but 0 is the midpoint of the whole range, where f = 0/0, so x²/x
        // lost "Narašča na (−3,2; 3,2)" (f′ = 1) and x³/x "Konveksna (∪) na (−3,2; 3,2)" (f″ = 2).
        let line = try analysis("x^2/x", range: -3.2...3.2)
        #expect(line.increasing == [-3.2...3.2])
        #expect(line.decreasing.isEmpty)
        let parabola = try analysis("x^3/x", range: -3.2...3.2)
        #expect(parabola.convex == [-3.2...3.2])
        #expect(parabola.concave.isEmpty)
    }

    @Test func intervalsDoNotRunAcrossAJumpAtTheirMidpoint() throws {
        // On −3.2…3.2 again no sample lands on the midpoint 0, but there arctan(1/x) jumps from −π/2
        // to π/2, x − |x|/x from 1 to −1 and ln|x| → −∞ (missed as a pole), while f′ or f″ has one
        // sign on both sides: the analysis said "Pada na (−3,2; 3,2)" (f(−0.1) = −1.471 < f(0.1) =
        // 1.471), "Narašča na (−3,2; 3,2)" (f(−0.5) = 0.5 > f(0.5) = −0.5) and "Konkavna (∩) na
        // (−3,2; 3,2)" across the asymptote.
        func across(_ intervals: [ClosedRange<Double>]) -> Bool {
            intervals.contains { $0.lowerBound < 0 && 0 < $0.upperBound }
        }
        let arctangent = try analysis("arctan(1/x)", range: -3.2...3.2)
        #expect(!across(arctangent.decreasing), "\(arctangent.decreasing)")
        let step = try analysis("x-abs(x)/x", range: -3.2...3.2)
        #expect(!across(step.increasing), "\(step.increasing)")
        let logarithm = try analysis("ln(abs(x))", range: -3.2...3.2)
        #expect(!across(logarithm.concave), "\(logarithm.concave)")
    }

    @Test func obliqueInterceptHasNoExtrapolationNoise() throws {
        // y = x for x + 1/x and x³/(x² − 4) = x + 4x/(x² − 4): the extrapolated intercept was
        // 1,56·10⁻¹¹ and −1,30·10⁻¹¹, shown as "Poševna: y = 1·x + 1,56472·10⁻¹¹".
        let a = try #require(try analysis("x+1/x").obliqueAsymptote)
        #expect(a.intercept == 0)
        let b = try #require(try analysis("x^3/(x^2-4)").obliqueAsymptote)
        #expect(b.intercept == 0)
        // A real intercept stays: x·arctan x = (π/2)x − 1 + O(1/x²).
        let c = try #require(try analysis("x*arctan(x)").obliqueAsymptote)
        #expect(abs(c.intercept + 1) < 1e-6)
    }

    @Test func noPolesWhereThereAreNone() throws {
        // Holes, jumps, ends of the domain and smooth functions (no poles before the fix either). Not
        // ln x: x = 0 is its vertical asymptote (ln x → −∞), which the search misses (|f| grows only
        // logarithmically, |ln(2·10⁻⁵)|/|ln(2·10⁻³)| = 1.74).
        for text in ["sin(x)/x", "(x^2-1)/(x-1)", "x/x", "floor(x)", "abs(x)/x", "x^3-3x", "sqrt(x)", "e^x", "1/(x^2+1)"] {
            let poles = try analysis(text).poles
            #expect(poles.isEmpty, "\(text): \(poles)")
        }
        // Narrow finite peaks on wide ranges (a zoomed-out graph): |f| grows 10× from 100·d to d
        // (d = 10⁻⁶ of the range) but levels off below the half-width; 1/((x − 1)² + 10⁻⁴) has its
        // maximum 10⁴ at x = 1, 1/(x² + 10⁻³) 10³ at 0, 1/(x² + 10⁻⁶) 10⁶ at 0. They were "Navpična: x = …".
        let peaks: [(String, ClosedRange<Double>)] = [("1/((x-1)^2+0.0001)", -500.0...500.0),
                                                      ("1/(x^2+0.001)", -1000.0...1000.0),
                                                      ("1/(x^2+0.000001)", -5000.0...5000.0)]
        for (text, range) in peaks {
            let poles = try analysis(text, range: range).poles
            #expect(poles.isEmpty, "\(text) on \(range): \(poles)")
        }
    }
}
