import Testing
@testable import AcuteCore

// MARK: Domain in the function analysis (audit)

@Suite struct AuditFunctionDomainTests {
    /// Orodja → Analiza funkcije: Parser.parse, FunctionAnalysisView(range: −10…10) → FunctionAnalyzer.analyze.
    func analysis(_ text: String, range: ClosedRange<Double> = -10...10) throws -> FunctionAnalysis {
        FunctionAnalyzer.analyze(try Parser.parse(text), range: range, context: EvaluationContext())
    }

    @Test func excludedPointsArePolesAndHoles() throws {
        // (x − 1)/((x − 1)(x + 2)²) = 1/(x + 2)² for x ≠ 1: the pole −2 and the hole at 1 (limit 1/9).
        // "Definicijsko območje" listed the poles only, so it said "x ≠ −2".
        let hole = try #require(try analysis("(x-1)/((x-1)(x+2)^2)").excludedPoints)
        #expect(hole == [-2.0, 1.0])
        let rational = try #require(try analysis("x^2/(x^2-4)").excludedPoints)
        #expect(rational == [-2.0, 2.0])
        let reciprocal = try #require(try analysis("1/x").excludedPoints)
        #expect(reciprocal == [0.0])
        let polynomial = try #require(try analysis("x^3-3x").excludedPoints)
        #expect(polynomial.isEmpty)
    }

    @Test func noPointListWhenTheDomainIsCutOff() throws {
        // ln x/(x − 2) is defined only for x > 0, so "x ≠ 2" would be a wrong domain; the vertical
        // asymptote x = 2 stays (x = 0 is one as well, ln x/(x − 2) → +∞, but the search misses it).
        let ln = try analysis("ln(x)/(x-2)")
        #expect(ln.excludedPoints == nil)
        #expect(ln.poles.contains(2))
        // √x/(x − 3)²: x ≥ 0, x ≠ 3; arcsin x: −1 ≤ x ≤ 1.
        let root = try analysis("sqrt(x)/(x-3)^2")
        #expect(root.excludedPoints == nil)
        let arcsine = try analysis("arcsin(x)")
        #expect(arcsine.excludedPoints == nil)
    }

    @Test func noPointListWhenAPointIsNeitherPoleNorHole() throws {
        // |x|/(x(x − 2)) jumps at 0 (limits 1/2 and −1/2), ln|x|/(x − 2) is undefined at 0 (ln|x| → −∞,
        // missed as a pole), ln x/(x − 2) on 0…5 at the end 0: all three are undefined at 0 and 2, but
        // the analysis said "x ≠ 2". −10…9 has no sample on 0.
        let cases: [(String, ClosedRange<Double>)] = [("abs(x)/(x*(x-2))", -10.0...10.0), ("abs(x)/(x*(x-2))", -10.0...9.0),
                                                      ("ln(abs(x))/(x-2)", -10.0...10.0), ("ln(abs(x))/(x-2)", -10.0...9.0),
                                                      ("ln(x)/(x-2)", 0.0...5.0)]
        for (text, range) in cases {
            let a = try analysis(text, range: range)
            #expect(a.poles.contains(2), "\(text) on \(range): \(a.poles)")
            #expect(a.excludedPoints == nil, "\(text) on \(range): \(String(describing: a.excludedPoints))")
        }
        // Zeros of a denominator where rounding leaves f finite: sin x/tan x and 1/tan x are undefined
        // at every multiple of π/2 and (x − π)/sin x at every multiple of π, but sin x/tan x = −1 at
        // x = π, 1/tan(π/2) = 6·10⁻¹⁷ and (π − π)/sin π = 0. The analysis said "x ≠ 0" for the first,
        // left out ±π/2, ±3π/2, ±5π/2 for the second and π for the third (holes the search skips).
        for text in ["sin(x)/tan(x)", "1/tan(x)", "(x-pi)/sin(x)"] {
            let excluded = try analysis(text).excludedPoints
            #expect(excluded == nil, "\(text): \(String(describing: excluded))")
        }
        // Off the grid as well, a hole stays listed: (x² − 1)/(x − 1) on −10…9 is x + 1 for x ≠ 1.
        let hole = try #require(try analysis("(x^2-1)/(x-1)", range: -10...9).excludedPoints)
        #expect(hole == [1.0])
    }
}
