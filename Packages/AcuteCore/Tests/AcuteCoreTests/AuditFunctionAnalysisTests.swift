import Foundation
import Testing
@testable import AcuteCore

// MARK: Function analysis (audit)

@Suite struct AuditFunctionAnalysisTests {
    /// Orodja → Analiza funkcije: Parser.parse, FunctionAnalysisView(range: −10…10) → FunctionAnalyzer.analyze.
    func analysis(_ text: String, range: ClosedRange<Double> = -10...10) throws -> FunctionAnalysis {
        FunctionAnalyzer.analyze(try Parser.parse(text), range: range, context: EvaluationContext())
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
        #expect(a.decreasing == [-10...2, 2...10])
        #expect(a.concave == [-10...2])
        #expect(a.convex == [2...10])
        // (x² − 4)/(x − 1) = x + 1 − 3/(x − 1): f′ = 1 + 3/(x − 1)² > 0 and f″ = −6/(x − 1)³.
        let b = try analysis("(x^2-4)/(x-1)")
        #expect(b.increasing == [-10...1, 1...10])
        #expect(b.decreasing.isEmpty)
        #expect(b.convex == [-10...1])
        #expect(b.concave == [1...10])
    }

    @Test func intervalsStayInTheDomain() throws {
        // ln x with "Od x = −10, Do x = 5": f′ = 1/x and f″ = −1/x² exist for x < 0 too, so the analysis
        // said "Pada na (−10, 5)" and "Konkavna (∩) na (−10, 5)"; ln x increases and is concave on (0, 5).
        let ln = try analysis("ln(x)", range: -10...5)
        #expect(ln.increasing == [0...5])
        #expect(ln.decreasing.isEmpty)
        #expect(ln.concave == [0...5])
        #expect(ln.convex.isEmpty)
        // arcsin x is defined on [−1, 1] and increases there (f′ = 1/√(1 − x²)), concave on (−1, 0) and
        // convex on (0, 1) (f″ = x/(1 − x²)^(3/2)); it was "Narašča na (−10, 10)".
        let arcsine = try analysis("arcsin(x)")
        #expect(arcsine.increasing == [-1...1])
        #expect(arcsine.concave == [-1...0])
        #expect(arcsine.convex == [0...1])
        // √x on −10…10: the only midpoint was 0, the end of the domain (f′(0) undefined): no interval.
        let root = try analysis("sqrt(x)")
        #expect(root.increasing == [0...10])
        #expect(root.concave == [0...10])
        // √(4 − x²): increasing on (−2, 0), decreasing on (0, 2), concave on (−2, 2).
        let semicircle = try analysis("sqrt(4-x^2)")
        #expect(semicircle.increasing == [-2...0])
        #expect(semicircle.decreasing == [0...2])
        #expect(semicircle.concave == [-2...2])
        #expect(semicircle.convex.isEmpty)
    }

    @Test func noPolesWhereThereAreNone() throws {
        // Holes, jumps, ends of the domain and smooth functions (no poles before the fix either).
        for text in ["sin(x)/x", "(x^2-1)/(x-1)", "x/x", "floor(x)", "abs(x)/x", "x^3-3x", "ln(x)", "sqrt(x)", "e^x", "1/(x^2+1)"] {
            let poles = try analysis(text).poles
            #expect(poles.isEmpty, "\(text): \(poles)")
        }
    }
}
