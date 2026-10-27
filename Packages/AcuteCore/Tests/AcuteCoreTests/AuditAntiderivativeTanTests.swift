import Foundation
import Testing
@testable import AcuteCore

// ∫√(tan x) dx, approved by the owner: the substitution t = √(tan x) turns it into ∫2t²/(1 + t⁴) dt
// (Antiderivative.tangentRoot). On origin/main (b025358) the calculator answered "Ni podprto: nedoločenega
// integrala ne znam izraziti – vnesi meje za določeni integral" (audit probe, owner-I25), so every test here
// fails there except the last one, which guards that the probe's other indefinite integrals keep their text.

@Suite struct AuditAntiderivativeTanTests {
    /// ∫ body dx typed as integral(body, x) in "Vnos izraza", i.e. the keypad ∫ with both bounds empty, through
    /// the call CalculatorModel makes (the route of the probe).
    static func calculate(_ body: String, settings: CalculationSettings = CalculationSettings()) throws -> Calculation {
        let row = try MathRowConverter.row(fromText: "integral(\(body), x)")
        return CalculationEngine.calculate(row, variables: [:], exactVariables: [:], settings: settings)
    }

    /// F + C, or nil (recorded as an issue) when the calculator gave no antiderivative.
    static func antiderivative(_ body: String, settings: CalculationSettings = CalculationSettings()) throws -> Expr? {
        let calculation = try calculate(body, settings: settings)
        guard case .symbolic(let result) = calculation.outcome else {
            Issue.record("∫ \(body) dx gave \(calculation.outcome)")
            return nil
        }
        return result
    }

    /// F(x) with C = 0.
    static func value(_ F: Expr, at x: Double) throws -> Double {
        try RealEvaluator.evaluate(F, context: EvaluationContext(variables: ["x": x, "C": 0]))
    }

    @Test func squareRootOfTangentIsSymbolic() throws {
        let calculation = try Self.calculate("sqrt(tan(x))")
        guard case .symbolic(let result) = calculation.outcome else {
            Issue.record("∫ √(tan x) dx gave \(calculation.outcome)")
            return
        }
        // Only x and the constant C: no substitution variable is left over.
        #expect(result.freeVariables == ["x", "C"])
        // The graphs of f and F.
        #expect(calculation.graph?.kinds.count == 2)
    }

    @Test func squareRootOfTangentMatchesTheDefiniteIntegral() throws {
        let result = try Self.antiderivative("sqrt(tan(x))")
        let F = try #require(result)
        let exact = try Self.value(F, at: .pi / 4) - Self.value(F, at: .pi / 8)
        let numeric = try Integrator.integrate(try Parser.parse("sqrt(tan(x))"), variable: "x", from: .pi / 8, to: .pi / 4,
                                               context: EvaluationContext())
        // Gauss–Kronrod at tolerance 1e-11 on an integrand that is smooth on [π/8, π/4].
        #expect(abs(exact - numeric) < 1e-10)
        // 0.32157147620550790381…: 60-point Gauss–Legendre on 8 panels (Python, 0.32157147620550774) and the
        // closed form in 50-digit decimal arithmetic.
        #expect(abs(exact - 0.3215714762055079) < 1e-12)
    }

    /// The textbook form (√2/2)·arctan((tan x − 1)/√(2 tan x)) + (√2/4)·ln((tan x − √(2 tan x) + 1)/(tan x + √(2 tan x) + 1))
    /// up to a constant on (0, π/2).
    @Test func squareRootOfTangentIsTheTextbookFormUpToAConstant() throws {
        let result = try Self.antiderivative("sqrt(tan(x))")
        let F = try #require(result)
        func textbook(_ x: Double) -> Double {
            let t = tan(x), s = (2 * t).squareRoot(), r2 = 2.0.squareRoot()
            return r2 / 2 * atan((t - 1) / s) + r2 / 4 * log((t - s + 1) / (t + s + 1))
        }
        let points = [0.1, 0.3, 0.6, 0.9, 1.2, 1.5]
        let offset = try Self.value(F, at: points[0]) - textbook(points[0])
        for p in points {
            // Rounding only (|F| < 2 here); a wrong term would differ by more than 10⁻³.
            let difference = try Self.value(F, at: p) - textbook(p) - offset
            #expect(abs(difference) < 1e-12, "x = \(p)")
        }
    }

    @Test func squareRootOfCotangentMatchesTheDefiniteIntegral() throws {
        let result = try Self.antiderivative("sqrt(cot(x))")
        let F = try #require(result)
        let exact = try Self.value(F, at: .pi / 4) - Self.value(F, at: .pi / 8)
        // 0.48715909379639900921…: Gauss–Legendre as above (0.4871590937963988) and the closed form
        // −[(√2/2)·arctan((cot x − 1)/√(2 cot x)) + (√2/4)·ln(…)] in 50-digit decimals.
        #expect(abs(exact - 0.487159093796399) < 1e-12)
    }

    @Test func constantTimesSquareRootOfTangentOfALinearArgument() throws {
        let result = try Self.antiderivative("3*sqrt(tan(2*x))")
        let F = try #require(result)
        let exact = try Self.value(F, at: .pi / 8) - Self.value(F, at: .pi / 16)
        // u = 2x: (3/2)·∫ from π/8 to π/4 of √(tan u) du = 1.5 · 0.32157147620550790… (Gauss–Legendre: 0.4823572143082616).
        #expect(abs(exact - 0.48235721430826186) < 1e-12)
    }

    @Test func degreesUseTheCalculatorsUnit() throws {
        let result = try Self.antiderivative("sqrt(tan(x))", settings: CalculationSettings(angleUnit: .degrees))
        let F = try #require(result)
        let derivative = try Differentiator.derivative(of: F, withRespectTo: "x", angleUnit: .degrees)
        let slope = try RealEvaluator.evaluate(derivative, context: EvaluationContext(angleUnit: .degrees, variables: ["x": 40, "C": 0]))
        // √(tan 40°) = 0.9160…; the derivative is evaluated to rounding.
        #expect(abs(slope - tan(40 * Double.pi / 180).squareRoot()) < 1e-10)
    }

    /// Guard (passes on origin/main too): the indefinite integrals of the audit probe show exactly the text
    /// they showed on origin/main b025358 (PROBE| lines of the CI run, the text after "= "; the log writes "|" as "¦").
    @Test func probeIndefiniteIntegralsShowTheSameText() throws {
        let cases: [(body: String, shown: String)] = [
            ("1", "x+C"),  // owner-I01
            ("x^3", "(x^(4))/(4)+C"),  // owner-I02
            ("x^(1/2)", "(2x^((3)/(2)))/(3)+C"),  // owner-I03
            ("1/x", "ln(|x|)+C"),  // owner-I04
            ("sin(x)", "−cos(x)+C"),  // owner-I05
            ("cos(x)", "sin(x)+C"),  // owner-I06
            ("1/cos(x)^2", "tan(x)+C"),  // owner-I07
            ("1/sin(x)^2", "−cot(x)+C"),  // owner-I08
            ("1/sqrt(1-x^2)", "arcsin(x)+C"),  // owner-I09
            ("-1/sqrt(1-x^2)", "−arcsin(x)+C"),  // owner-I10
            ("1/(1+x^2)", "arctan(x)+C"),  // owner-I11
            ("e^x", "e^(x)+C"),  // owner-I12
            ("2^x", "(2^(x))/(ln(2))+C"),  // owner-I13
            ("3^x", "(3^(x))/(ln(3))+C"),  // owner-I14
            ("3*x^2-4*x+5", "x^(3)−2x^(2)+5x+C"),  // owner-I15
            ("2*sin(x)+3*e^x", "−2cos(x)+3e^(x)+C"),  // owner-I16
            ("2*x*cos(x^2)", "sin(x^(2))+C"),  // owner-I17
            ("sin(x)*cos(x)", "−((cos(x))^(2))/(2)+C"),  // owner-I18
            ("x*e^(x^2)", "(e^(x^(2)))/(2)+C"),  // owner-I19
            ("x*e^x", "xe^(x)−e^(x)+C"),  // owner-I20
            ("x*sin(x)", "−xcos(x)+sin(x)+C"),  // owner-I21
            ("ln(x)", "xln(x)−x+C"),  // owner-I22
            ("x*ln(x)", "(x^(2)ln(x))/(2)−(x^(2))/(4)+C"),  // owner-I23
            ("abs(x)", "(x|x|)/(2)+C"),  // owner-I24
            ("x^n", "(x^(n+1))/(n+1)+C"),  // extra-P01
            ("a^x", "(a^(x))/(ln(a))+C"),  // extra-P02
        ]
        for c in cases {
            guard let result = try Self.antiderivative(c.body) else { continue }
            #expect(MathRowConverter.plainText(MathRowConverter.row(for: result)) == c.shown, "∫ \(c.body) dx")
        }
    }
}
