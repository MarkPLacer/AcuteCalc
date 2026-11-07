import Testing
@testable import AcuteCalc

/// apis:1: the 3D canvas is black in both appearances, but its axis numbers had the secondary label colour, which in
/// the light appearance is dark: 1.36:1 in surface-light.png. They are now white, each on a dark plate, so they also
/// stay readable where they lie over a bright part of the surface.
@MainActor
@Suite struct SurfaceTickContrastTests {
    @Test func numbersOnThePlateReachTheTextMinimumOverAWhiteSurface() {
        // The plate over a white surface, blended in sRGB (a Canvas works in non-linear sRGB by default): 5.7:1.
        let grey = Float(1 - SurfaceAxisTicks.plateOpacity)
        #expect(Contrast.ratio(RGBA(1, 1, 1, 1), RGBA(grey, grey, grey, 1)) >= 4.5)
    }
}
