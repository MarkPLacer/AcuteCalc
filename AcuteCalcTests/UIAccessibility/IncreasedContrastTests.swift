import Testing
@testable import AcuteCalc

/// UI-10 / A11Y-12: under Increase Contrast white text on the accent colour reaches the WCAG text
/// minimum (4.5:1) and graph curves on the light theme the graphics minimum (3:1); the default
/// colours are unchanged. Ratios use the WCAG 2 relative luminance (see the commit message for
/// the values, computed independently in Python).
@MainActor
@Suite struct IncreasedContrastTests {
    let white = RGBA(1, 1, 1, 1)

    @Test func defaultAccentsAreBelowTheTextMinimum() {
        // The finding: white on acuteBlue 2.60:1, mint 2.15:1, orange 2.21:1, green 2.12:1.
        #expect(abs(Contrast.ratio(white, AccentTheme.acuteBlue.rgba) - 2.60) < 0.01)
        #expect(abs(Contrast.ratio(white, AccentTheme.green.rgba) - 2.12) < 0.01)
    }

    @Test func increasedContrastAccentsCarryWhiteText() {
        for accent in AccentTheme.allCases {
            let darker = accent.rgba.darkened(toContrastOnWhite: 4.6)
            #expect(Contrast.ratio(white, darker) >= 4.5, "\(accent)")
        }
    }

    @Test func lightThemeCurvesReachThreeToOneUnderIncreasedContrast() {
        for color in GraphPalette.colors {
            #expect(Contrast.ratio(white, GraphTheme.lightIncreasedContrast.curveColor(color)) >= 3, "\(color)")
        }
        // Yellow had 1.41:1.
        #expect(Contrast.ratio(white, GraphPalette.colors[5]) < 1.5)
    }

    @Test func defaultThemesKeepThePaletteColours() {
        for color in GraphPalette.colors {
            #expect(GraphTheme.light.curveColor(color) == color)
            #expect(GraphTheme.dark.curveColor(color) == color)
        }
    }

    @Test func coloursWithEnoughContrastStayTheSame() {
        // Red (3.36:1) and purple (3.39:1) already pass 3.2:1.
        #expect(GraphTheme.lightIncreasedContrast.curveColor(GraphPalette.colors[1]) == GraphPalette.colors[1])
        #expect(GraphTheme.lightIncreasedContrast.curveColor(GraphPalette.colors[4]) == GraphPalette.colors[4])
    }

    @Test func darkeningKeepsAlpha() {
        let translucent = RGBA(1, 0.84, 0.04, 0.5)
        #expect(translucent.darkened(toContrastOnWhite: 3.2).w == 0.5)
    }
}
