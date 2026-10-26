import SwiftUI
import Testing
@testable import AcuteCalc

/// UI-11 / A11Y-08: math follows larger Dynamic Type sizes with an upper bound, and the default
/// and smaller sizes keep the designed font sizes (the default appearance does not change).
/// The factor's input is a @ScaledMetric of 100 (100 at the default text size).
@MainActor
@Suite struct MathTextDynamicTypeTests {
    @Test func defaultAndSmallerTextSizesKeepTheDesignedSize() {
        #expect(MathText.dynamicTypeFactor(100) == 1)
        #expect(MathText.dynamicTypeFactor(82) == 1)
    }

    @Test func largerTextSizesEnlargeMath() {
        // Body text is 17 pt at the default size and 23 pt at the largest non-accessibility size.
        let factor = MathText.dynamicTypeFactor(100 * 23 / 17)
        #expect(abs(factor - 23.0 / 17.0) < 1e-9)
    }

    @Test func accessibilitySizesAreCapped() {
        // AX5 body text is 53 pt (3.1×); lists stop at 200 %, the calculator result at 150 %.
        #expect(MathText.dynamicTypeFactor(100 * 53 / 17) == 2)
        #expect(MathText.dynamicTypeFactor(176, maximum: 1.5) == 1.5)
    }
}
