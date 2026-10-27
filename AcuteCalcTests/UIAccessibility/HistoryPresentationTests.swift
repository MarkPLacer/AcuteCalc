import SwiftUI
import Testing
@testable import AcuteCalc

/// UI-03 / PLT-05: the History button needs a presentation in every window size. Before the fix
/// the overlay needed regular width over 820 pt and the sheet compact width, so regular windows
/// up to 820 pt (iPad mini and iPad Air 11" portrait, narrow iPad windows) showed nothing.
@Suite struct HistoryPresentationTests {
    @Test func narrowRegularWindowsUseTheSheet() {
        #expect(CalculatorLayout.historyPresentation(sizeClass: .regular, width: 700) == .sheet)
        #expect(CalculatorLayout.historyPresentation(sizeClass: .regular, width: 744) == .sheet)
        #expect(CalculatorLayout.historyPresentation(sizeClass: .regular, width: 820) == .sheet)
    }

    @Test func wideRegularWindowsKeepTheOverlay() {
        #expect(CalculatorLayout.historyPresentation(sizeClass: .regular, width: 821) == .overlay)
        #expect(CalculatorLayout.historyPresentation(sizeClass: .regular, width: 1032) == .overlay)
    }

    @Test func compactWidthKeepsTheSheet() {
        #expect(CalculatorLayout.historyPresentation(sizeClass: .compact, width: 430) == .sheet)
        #expect(CalculatorLayout.historyPresentation(sizeClass: .compact, width: 1000) == .sheet)
        #expect(CalculatorLayout.historyPresentation(sizeClass: nil, width: 1000) == .sheet)
    }

    @Test func overlayOnlyInTheWideLayout() {
        for width in [700.0, 820, 821, 1032] {
            let wide = CalculatorLayout.isWide(sizeClass: .regular, width: width)
            #expect((CalculatorLayout.historyPresentation(sizeClass: .regular, width: width) == .overlay) == wide)
        }
    }
}
