import Testing
@testable import AcuteCore

// MARK: Asymptotes

@Suite struct AsymptoteTests {
    func analysis(_ text: String) throws -> FunctionAnalysis {
        FunctionAnalyzer.analyze(try Parser.parse(text), range: -10...10, context: EvaluationContext())
    }

    @Test func sineHasNone() throws {
        // The extrapolated limits of sin x gave a tiny slope and drew a stray line at y ≈ −2.6.
        let a = try analysis("sin(x)")
        #expect(a.obliqueAsymptote == nil)
        #expect(a.horizontalAsymptoteLeft == nil)
        #expect(a.horizontalAsymptoteRight == nil)
    }

    @Test func obliqueOfRationalFunctions() throws {
        // (x² + 1)/(x − 1) = x + 1 + 2/(x − 1); (3x³ + 1)/(x² + 7) = 3x − 21x/(x² + 7) + …
        let first = try #require(try analysis("(x^2+1)/(x-1)").obliqueAsymptote)
        #expect(abs(first.slope - 1) < 1e-6 && abs(first.intercept - 1) < 1e-6)
        let second = try #require(try analysis("(3x^3+1)/(x^2+7)").obliqueAsymptote)
        #expect(abs(second.slope - 3) < 1e-6 && abs(second.intercept) < 1e-6)
    }

    @Test func slowlyApproachedOblique() throws {
        // The gap c/x is still 10⁻³ … 8·10⁻³ at x = 10⁵; a fixed threshold there dropped these.
        for (text, slope) in [("(x^2+100)/x", 1.0), ("x + 400/x", 1.0), ("2x + 800/x", 2.0)] {
            let line = try #require(try analysis(text).obliqueAsymptote, "\(text) has no oblique asymptote")
            #expect(abs(line.slope - slope) < 1e-6 && abs(line.intercept) < 1e-6, "\(text)")
        }
    }

    @Test func horizontalStays() throws {
        let a = try analysis("2 + 1/x")
        #expect(abs((a.horizontalAsymptoteRight ?? .nan) - 2) < 1e-9)
        #expect(a.obliqueAsymptote == nil)
    }
}
