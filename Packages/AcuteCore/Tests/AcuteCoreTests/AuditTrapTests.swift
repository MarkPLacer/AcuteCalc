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
#endif
}
