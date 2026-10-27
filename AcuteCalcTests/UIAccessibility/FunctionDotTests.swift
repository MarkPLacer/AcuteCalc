import Testing
@testable import AcuteCalc

/// A11Y-09 (2): the colour dot of a function row in the Graphs tab was told apart from the others
/// only by its colour, and VoiceOver called every dot "Skrij graf" / "Pokaži graf". With
/// Differentiate Without Color the dot also shows the function's number (nothing is drawn with
/// the setting off), and the VoiceOver label names the function by that number.
@MainActor
@Suite struct FunctionDotTests {
    @Test func differentiateWithoutColorShowsTheNumber() {
        #expect(FunctionRow.dotNumber(3, differentiateWithoutColor: true) == "3")
        #expect(FunctionRow.dotNumber(12, differentiateWithoutColor: true) == "12")
    }

    @Test func defaultDotHasNoNumber() {
        #expect(FunctionRow.dotNumber(3, differentiateWithoutColor: false) == nil)
    }

    @Test func voiceOverLabelNamesTheFunction() {
        #expect(FunctionRow.dotLabel(2, visible: true) == "Skrij graf 2")
        #expect(FunctionRow.dotLabel(2, visible: false) == "Pokaži graf 2")
    }

    /// Why the number is black on a filled dot: WCAG text minimum 4.5:1; black has 6.19:1
    /// (purple) to 14.90:1 (yellow), white only 1.41:1 (yellow) to 3.39:1 (purple).
    @Test func blackNumbersAreLegibleOnEveryFilledDot() {
        let black = RGBA(0, 0, 0, 1)
        for color in GraphPalette.colors {
            #expect(Contrast.ratio(black, color) >= 4.5, "\(color)")
        }
    }
}
