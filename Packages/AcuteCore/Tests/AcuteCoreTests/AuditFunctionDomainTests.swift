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
        // asymptote x = 2 stays.
        let ln = try analysis("ln(x)/(x-2)")
        #expect(ln.excludedPoints == nil)
        #expect(ln.poles == [2])
        // √x/(x − 3)²: x ≥ 0, x ≠ 3; arcsin x: −1 ≤ x ≤ 1.
        let root = try analysis("sqrt(x)/(x-3)^2")
        #expect(root.excludedPoints == nil)
        let arcsine = try analysis("arcsin(x)")
        #expect(arcsine.excludedPoints == nil)
    }
}
