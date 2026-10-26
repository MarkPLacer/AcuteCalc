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
}
