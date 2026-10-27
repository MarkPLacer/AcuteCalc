import AcuteCore
import Testing
@testable import AcuteCalc

/// UI-12: formula rows are parsed once and cached; the cached row is exactly what parsing the
/// LaTeX gives (so the Formulas tab shows the same math), also for formulas that do not parse.
@MainActor
@Suite struct FormulaRowCacheTests {
    @Test func cachedRowsMatchParsing() {
        let formulas = (FormulaLibrary.mathematics + FormulaLibrary.physics).flatMap(\.formulas)
        #expect(!formulas.isEmpty)
        for formula in formulas {
            let parsed = try? LaTeXConverter.row(fromLaTeX: formula.latex)
            let first = FormulaRowCache.row(for: formula)
            let second = FormulaRowCache.row(for: formula)
            #expect(first == parsed, "\(formula.title)")
            #expect(second == parsed, "\(formula.title)")
        }
    }
}
