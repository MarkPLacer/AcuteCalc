import Testing
@testable import AcuteCore

// Runtime traps reachable from user input (audit gap-int-traps). Inputs that trap in AcuteCore
// on the unfixed code run as exit tests, so a trap fails only its own test.

@Suite struct AuditTrapTests {
    // MARK: Reversed integral bounds (GAP-int-traps-1)

    /// ∫ₐᵇ body dx as typed on the keypad.
    func integralRow(_ lower: String, _ upper: String, body: [MathNode] = [.symbol(.variable("x"))]) -> MathRow {
        MathRow([.integral(lower: MathRow(MathRowConverter.digits(lower)), upper: MathRow(MathRowConverter.digits(upper)), body: MathRow(body))])
    }

    @Test func reversedIntegralBoundsShadeAnOrderedBand() throws {
        // (lower, upper, ∫ x dx = (upper² − lower²)/2, band): ∫₂¹ is ∫₂¹⁰ halfway through typing.
        let cases: [(lower: String, upper: String, value: Double, from: Double, to: Double)] = [
            ("5", "1", -12, 1, 5), ("2", "1", -1.5, 1, 2), ("15", "2", -110.5, 2, 15), ("1", "5", 12, 1, 5),
        ]
        for c in cases {
            let calculation = CalculationEngine.calculate(integralRow(c.lower, c.upper), variables: [:], exactVariables: [:], settings: CalculationSettings())
            guard case .number(let result) = calculation.outcome else {
                Issue.record("∫ from \(c.lower) to \(c.upper) gave \(calculation.outcome)")
                continue
            }
            // The value keeps the orientation (∫ₐᵇ = −∫ᵇₐ); quadrature of x is exact to rounding.
            #expect(abs(result.value - c.value) < 1e-9)
            // The app shades lower...upper, which traps unless lower ≤ upper.
            let shade = try #require(calculation.graph?.shadedIntegral)
            #expect(shade.lower == c.from && shade.upper == c.to)
        }
    }

    /// ∞ is drawn at ±10⁶; reversed improper integrals used to put +∞ at −10⁶ (and −∞ at +10⁶).
    @Test func reversedImproperIntegralShadesItsOwnSide() throws {
        // ∫∞⁰ e⁻ˣ dx = −∫₀^∞ e⁻ˣ dx = −1 over [0, ∞); ∫₀^(−∞) eˣ dx = −∫₋∞⁰ eˣ dx = −1 over (−∞, 0].
        let cases: [(text: String, from: Double, to: Double)] = [
            ("integral(e^(-x), x, inf, 0)", 0, 1e6), ("integral(e^x, x, 0, -inf)", -1e6, 0),
        ]
        for c in cases {
            let calculation = CalculationEngine.calculate(try Parser.parse(c.text), variables: [:], exactVariables: [:], settings: CalculationSettings())
            guard case .number(let result) = calculation.outcome else {
                Issue.record("\(c.text) gave \(calculation.outcome)")
                continue
            }
            // Quadrature tolerance 1e-11; the band is what this test is about.
            #expect(abs(result.value + 1) < 1e-9)
            let shade = try #require(calculation.graph?.shadedIntegral)
            #expect(shade.lower == c.from && shade.upper == c.to)
        }
    }

    // MARK: Non-finite angles in geodesy (GAP-int-traps-4)

    /// The app shows these angles in ° ′ ″ with Int(…), which traps for NaN.
    @Test func geodesyRejectsNonFiniteAngles() {
        // 1e308° in radians, computed as GeodeticUnit.radians does: (1e308·π)/180 = ∞.
        let infinite = 1e308 * Double.pi / 180
        #expect(infinite.isInfinite)
        let phi1 = 46.0569 * Double.pi / 180, phi2 = 40.7128 * Double.pi / 180, lambda2 = -74.006 * Double.pi / 180
        #expect(Geodesy.rhumbLine(latitude1: phi1, longitude1: infinite, latitude2: phi2, longitude2: lambda2, radius: 6371) == nil)
        #expect(Geodesy.rhumbLine(latitude1: phi1, longitude1: 0, latitude2: phi2, longitude2: .nan, radius: 6371) == nil)
        // A traverse with one side: an infinite angle, a NaN angle, and finite angles whose sum overflows.
        let a = Geodesy.Point(y: 1000, x: 1000), oa = Geodesy.Point(y: 1000, x: 2000)
        let b = Geodesy.Point(y: 1900, x: 1200), ob = Geodesy.Point(y: 2900, x: 1200)
        for angles in [[infinite, 3.6], [Double.nan, 3.6], [1e308, 1e308]] {
            #expect(throws: MathError.self) {
                try Geodesy.traverse(start: a, startOrientation: oa, end: b, endOrientation: ob, angles: angles, distances: [922])
            }
        }
        // Identical points "0 0 0 0" and "1e200 0 1e200 0": u² = ∞, so a = ∞/∞ = NaN.
        #expect(throws: MathError.self) {
            try Geodesy.helmert([(source: Geodesy.Point(y: 0, x: 0), target: Geodesy.Point(y: 0, x: 0)),
                                 (source: Geodesy.Point(y: 1e200, x: 0), target: Geodesy.Point(y: 1e200, x: 0))])
        }
    }

    /// Σu² overflows while Σu·u′ stays finite: a = finite/∞ = 0 passes a finite check on a and b.
    @Test func helmertRejectsOverflowedSquares() {
        // "0 0 0 0" and "1e200 0 1 0": Σu² = 2·(5·10¹⁹⁹)² = ∞ and Σu·u′ = 5·10¹⁹⁹, so a = b = 0 and the
        // fit has residuals ±0,5, while the exact fit is a = 10⁻²⁰⁰, t = 0 with zero residuals.
        #expect(throws: MathError.self) {
            try Geodesy.helmert([(source: Geodesy.Point(y: 0, x: 0), target: Geodesy.Point(y: 0, x: 0)),
                                 (source: Geodesy.Point(y: 1e200, x: 0), target: Geodesy.Point(y: 1, x: 0))])
        }
    }

#if os(macOS) || os(Linux) || os(Windows)
    // MARK: ᴇ exponent at Int.min (GAP-int-traps-2)

    @Test func exponentAtIntMinFallsBackToDouble() async {
        await #expect(processExitsWith: .success) {
            // Exponent Int.min (abs traps), Int.min + 1 with one decimal (abs of Int.min) and
            // Int.min with one decimal (Int.min − 1 traps).
            precondition(Rational(decimalString: "1E-9223372036854775808") == nil)
            precondition(Rational(decimalString: "1.5E-9223372036854775807") == nil)
            precondition(Rational(decimalString: "1.5E-9223372036854775808") == nil)
            // Keypad 1 ᴇ − 9223372036854775808: 10^(−9.2·10¹⁸) underflows to 0 as a Double.
            let keys: [MathNode] = [.symbol(.digit(1)), .symbol(.exponent10), .symbol(.minus)] + MathRowConverter.digits("9223372036854775808")
            let calculation = CalculationEngine.calculate(MathRow(keys), variables: [:], exactVariables: [:], settings: CalculationSettings())
            guard case .number(let result) = calculation.outcome, result.value == 0 else {
                fatalError("1ᴇ−9223372036854775808 gave \(calculation.outcome)")
            }
            // Pasted text reaches the same literal through the lexer.
            let pasted = try Parser.parse("2*1E-9223372036854775808")
            let value = try RealEvaluator.evaluate(pasted, context: EvaluationContext())
            precondition(value == 0, "2·1ᴇ−9223372036854775808 gave \(value)")
        }
    }

    // MARK: ker/eig scaled through Int.min (GAP-int-traps-6)

    @Test func kernelScaledThroughIntMinDoesNotTrap() async {
        await #expect(processExitsWith: .success) {
            // ker [[1, 0, 2⁶²], [0, 1, ½]] = span (−2⁶², −½, 1); the integer scaling by 2 gives Int.min.
            let big: Rational = Rational(1 << 62)
            let a = Matrix(rows: 2, columns: 3, exact: [.one, .zero, big, .zero, .one, .half])
            let k = a.kernel()
            guard k.rows == 3, k.columns == 1, let v = k.exact else { fatalError("ker A is not one exact vector") }
            // A·v = 0 exactly, with v ≠ 0.
            let first = big.multiplied(by: v[2]).flatMap { v[0].adding($0) }
            let second = Rational.half.multiplied(by: v[2]).flatMap { v[1].adding($0) }
            precondition(!v[2].isZero && first == Rational.zero && second == Rational.zero, "A·v ≠ 0 for v = \(v)")
            // eig scales its exact null spaces the same way; the vector stays as it is.
            let unscaled: [Rational] = [Rational(-(1 << 62)), Rational(unchecked: -1, 2), .one]
            precondition(EigenDecomposition.integerScaled(unscaled) == unscaled)
        }
    }

    // MARK: sinᵐ·cosⁿ with huge exponents (GAP-int-traps-7)

    @Test func hugeSineCosinePowersDoNotTrap() async {
        await #expect(processExitsWith: .success) {
            // m + n = 10¹⁹ > Int.max. No antiderivative is needed, only no trap.
            _ = Antiderivative.integrate(try Parser.parse("sin(x)^(5*10^18)*cos(x)^(5*10^18)"))
        }
    }
#endif
}
