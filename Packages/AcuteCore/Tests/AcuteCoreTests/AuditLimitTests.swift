import Foundation
import Testing
@testable import AcuteCore

// MAT-07: limits that are ±∞ where LimitEvaluator said "limita ne obstaja" (its samples reach only
// |f| ≈ 4·10⁴ at 1/(x − 2) near 2, its rule for ±∞ wants 10⁶), and x → ±∞ typed on its own, which the
// calculator always answered with "Prevelika vrednost" (it evaluated the point ∞ with
// RealEvaluator.evaluate). The limits are built as the keypad builds them and go through
// CalculationEngine.calculate, the call CalculatorModel makes.

@Suite struct AuditLimitTests {
    /// lim, lim⁻ or lim⁺ from the keypad with the point and the body typed as text ("inf" is ∞).
    func limitNode(_ point: String, _ body: String, _ direction: LimitDirection) throws -> MathNode {
        .limit(point: try MathRowConverter.row(fromText: point), body: try MathRowConverter.row(fromText: body), direction: direction)
    }

    func outcome(_ point: String, _ body: String, _ direction: LimitDirection = .both) throws -> CalculationOutcome {
        let row = MathRow([try limitNode(point, body, direction)])
        return CalculationEngine.calculate(row, variables: [:], exactVariables: [:], settings: CalculationSettings()).outcome
    }

    /// The decimal the calculator shows by default (NORM1, 10 significant digits, decimal comma).
    func shown(_ value: Double) -> String {
        NumberFormatting.format(value, options: NumberFormatOptions()).plainText
    }

    /// References from the leading term at the point: K/(x − a)ᵐ, ln of a simple zero, tan at its poles
    /// (tan(πx + π/2) = −cot πx), 1/√(x − 2); ln x at 0 two-sided takes its only side, as √x at 0 does.
    @Test func infiniteLimitsAtFinitePoints() throws {
        let cases: [(point: String, body: String, direction: LimitDirection, positive: Bool)] = [
            ("2", "1/(x-2)", .right, true), ("2", "1/(x-2)", .left, false), ("2", "(x+1)/(x-2)", .right, true),
            ("0", "1/x", .right, true), ("0", "1/x", .left, false), ("0", "x^(-1)", .right, true),
            ("0", "ln(x)", .right, false), ("0", "ln(x)", .both, false), ("0", "ln(x)/ln(2)", .right, false),
            ("0", "ln(x)/ln(1/2)", .right, true), ("1", "1/ln(x)", .right, true), ("0", "1/(e^x-1)", .left, false),
            ("0", "tan(pi*x+pi/2)", .right, false), ("0", "tan(pi*x+pi/2)", .left, true),
            ("1", "tan(pi*x+pi/2)", .right, false), ("1", "tan(pi*x+pi/2)", .left, true),
            ("pi/2", "tan(x)", .left, true), ("pi/2", "tan(x)", .right, false),
            ("2", "1/sqrt(x-2)", .right, true), ("2", "1/(x^2-4)", .right, true),
        ]
        for c in cases {
            let result = try outcome(c.point, c.body, c.direction)
            guard case .infinite(let positive) = result else {
                Issue.record("lim x→\(c.point) (\(c.direction)) \(c.body) gave \(result)")
                continue
            }
            #expect(positive == c.positive, "lim x→\(c.point) (\(c.direction)) \(c.body)")
        }
    }

    /// References from the leading term: c·xᵖ (p > 0), c·ln x, aˣ with a > 1, e^(−x) at −∞.
    @Test func infiniteLimitsAtInfinityTypedAlone() throws {
        let cases: [(point: String, body: String, positive: Bool)] = [
            ("inf", "x", true), ("-inf", "x", false), ("inf", "sqrt(x)", true), ("inf", "x^(1/3)", true),
            ("inf", "ln(x)", true), ("inf", "ln(x)/ln(1/2)", false), ("inf", "e^x", true), ("inf", "2^x", true),
            ("inf", "x^2", true), ("inf", "x/2", true), ("inf", "x/(-2)", false), ("inf", "(x^2+1)/x", true),
            ("inf", "(2*x^2+1)/(x-1)", true), ("-inf", "x^3", false), ("-inf", "e^(-x)", true),
        ]
        for c in cases {
            let result = try outcome(c.point, c.body)
            guard case .infinite(let positive) = result else {
                Issue.record("lim x→\(c.point) \(c.body) gave \(result)")
                continue
            }
            #expect(positive == c.positive, "lim x→\(c.point) \(c.body)")
        }
    }

    /// References: e, e^(1/3), e⁻², e⁻¹, π/2, leading coefficients 2 and 3/7, x·sin(1/x) → 1,
    /// √(x² + x) − x → 1/2, and 0 for 2/x, (1/2)ˣ, x·e⁻ˣ, eˣ at −∞ — as shown.
    @Test func finiteLimitsAtInfinityTypedAlone() throws {
        let cases: [(point: String, body: String, shown: String)] = [
            ("inf", "(1+1/x)^x", "2,718281828"), ("-inf", "(1+1/x)^x", "2,718281828"),
            ("inf", "(1+1/(3*x))^x", "1,395612425"), ("inf", "(x/(x+2))^x", "0,135335283"),
            ("inf", "(1-1/x)^x", "0,367879441"), ("inf", "arctan(x)", "1,570796327"),
            ("inf", "(2*x+1)/(x-3)", "2"), ("inf", "(3*x^2+1)/(7*x^2-x)", "0,428571429"),
            ("inf", "x*sin(1/x)", "1"), ("inf", "sqrt(x^2+x)-x", "0,5"),
            ("inf", "2/x", "0"), ("inf", "(1/2)^x", "0"), ("inf", "x*e^(-x)", "0"), ("-inf", "e^x", "0"),
        ]
        for c in cases {
            let result = try outcome(c.point, c.body)
            guard case .number(let number) = result else {
                Issue.record("lim x→\(c.point) \(c.body) gave \(result)")
                continue
            }
            #expect(shown(number.value) == c.shown, "lim x→\(c.point) \(c.body) = \(number.value)")
        }
    }

    /// The finding's examples on LimitEvaluator itself: |1/(x − 2)| and (x² + 1)/x stay below 10⁶ on its samples.
    @Test func limitEvaluatorGivesInfinityWhereItsSamplesStopShort() throws {
        #expect(try LimitEvaluator.limit({ 1 / ($0 - 2) }, at: 2, direction: .right) == .infinity)
        #expect(try LimitEvaluator.limit({ 1 / ($0 - 2) }, at: 2, direction: .left) == -.infinity)
        #expect(try LimitEvaluator.limit({ ($0 * $0 + 1) / $0 }, at: .infinity, direction: .both) == .infinity)
        #expect(try LimitEvaluator.limit({ log($0) }, at: 0, direction: .right) == -.infinity)
    }

    /// No limit (oscillation, different or missing sides, a jump), or one the samples cannot settle (slow
    /// convergence or divergence, a slow oscillation, x ≥ 2⁵³ being even integers, total cancellation in a
    /// Taylor remainder, an overflow inside f, a pole 10⁻⁹ beside the point): still an error, not a value.
    @Test func limitsWithoutASettledValueStayErrors() throws {
        let cases: [(point: String, body: String, direction: LimitDirection)] = [
            ("0", "1/x", .both), ("pi/2", "tan(x)", .both), ("0", "e^(1/x)", .both), ("0", "sin(1/x)", .both),
            ("0", "sin(1/x)", .right), ("inf", "x*sin(x)", .both), ("2", "floor(x)", .both), ("2", "1/sqrt(x-2)", .left),
            ("inf", "x^(1/x)", .both), ("inf", "ln(x)/x", .both), ("inf", "sin(x)/x", .both), ("0", "1-x^0.01", .right),
            ("inf", "ln(ln(x))", .both), ("0", "2+x^0.000000001*ln(x)", .right), ("inf", "x^0.5*sin(0.05*ln(x))", .both),
            ("0", "x^(-0.5)*sin(0.05*ln(x))", .right), ("inf", "e^x*cos(0.1*ln(x)+1)", .both), ("inf", "x*sin(2*pi*x)", .both),
            ("inf", "(-1)^floor(x)*x", .both), ("inf", "x^4*(cos(0.00000001/x)-1+(0.00000001/x)^2/2)", .both),
            ("0", "((1+10^(-16)*x)-1-10^(-16)*x)/x^4", .right), ("inf", "x^150*e^(-x)", .both),
            ("inf", "x/gamma(x+1)^(1/x)", .both), ("2", "1/(x-2.000000001)", .left),
        ]
        for c in cases {
            let result = try outcome(c.point, c.body, c.direction)
            guard case .error = result else {
                Issue.record("lim x→\(c.point) (\(c.direction)) \(c.body) gave \(result)")
                continue
            }
        }
    }

    /// Where LimitEvaluator's own samples give a value, it is kept bit for bit, also inside an expression
    /// (0 + lim …); its inaccurate ones too (xˣ at 0⁺ = 0,99999140327113, ln x/x at ∞ = 8,6·10⁻⁶).
    @Test func valuesOfTheSamplesAreKept() throws {
        let cases: [(body: String, point: Double, direction: LimitDirection)] = [
            ("x^x", 0, .right), ("x*ln(x)", 0, .right), ("sin(x)/x", 0, .right), ("1/x^2", 0, .left),
            ("ln(x)/x", .infinity, .both), ("x^(1/x)", .infinity, .both), ("(1+1/x)^x", .infinity, .both),
            ("e^x*cos(0.1*ln(x)+1)", .infinity, .both), ("x^2", .infinity, .both),
        ]
        for c in cases {
            let f = FunctionAnalyzer.makeFunction(try parse(c.body), variable: "x", context: EvaluationContext())
            let sampled = c.point.isInfinite ? NumericCalculus.limit(of: f, at: c.point) : LimitEvaluator.oneSided(f, c.point, c.direction == .left ? -1 : 1)
            let expected = try #require(sampled)
            let limit = try LimitEvaluator.limit(try parse(c.body), variable: "x", at: c.point, direction: c.direction, context: EvaluationContext())
            #expect(limit == expected, "\(c.body) at \(c.point)")
        }
        // Typed alone, (1+1/x)^x at ∞ comes from the shallower grids; inside 0 + lim it is the sampled value.
        let nested = MathRow([.symbol(.digit(0)), .symbol(.plus), try limitNode("inf", "(1+1/x)^x", .both)])
        let result = CalculationEngine.calculate(nested, variables: [:], exactVariables: [:], settings: CalculationSettings()).outcome
        let f = FunctionAnalyzer.makeFunction(try parse("(1+1/x)^x"), variable: "x", context: EvaluationContext())
        let sampled = try #require(NumericCalculus.limit(of: f, at: .infinity))
        guard case .number(let number) = result else {
            Issue.record("0 + lim x→∞ (1+1/x)^x gave \(result)")
            return
        }
        #expect(number.value == sampled)
    }
}
