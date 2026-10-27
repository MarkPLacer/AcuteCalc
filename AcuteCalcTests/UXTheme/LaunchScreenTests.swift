import Foundation
import Testing
import UIKit
@testable import AcuteCalc

/// UI-14: the generated launch screen named no colour, so nothing tied it to the first screen (HIG
/// Launching: "Design a launch screen that's nearly identical to the first screen of your app").
/// It now names LaunchBackground, which must be the calculator's background (CalculatorScreen:
/// `Color(.systemBackground)`) in light and in dark.
@MainActor
@Suite struct LaunchScreenTests {
    @Test func launchScreenHasTheCalculatorBackgroundInBothAppearances() throws {
        let launchScreen = Bundle.main.object(forInfoDictionaryKey: "UILaunchScreen") as? [String: Any]
        // Before the fix the generated UILaunchScreen was an empty dictionary.
        let name = try #require(launchScreen?["UIColorName"] as? String)
        let colour = try #require(UIColor(named: name, in: .main, compatibleWith: nil))
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let launch = try #require(Self.components(colour.resolvedColor(with: traits)))
            let calculator = try #require(Self.components(UIColor.systemBackground.resolvedColor(with: traits)))
            let look = style == .dark ? "dark" : "light"
            for (launchComponent, calculatorComponent) in zip(launch, calculator) {
                // Half a step of an 8-bit channel: the colours are the same on screen.
                #expect(abs(launchComponent - calculatorComponent) < 0.5 / 255, "\(look): \(launch) vs \(calculator)")
            }
        }
    }

    /// Red, green, blue and alpha in extended sRGB, or nil when the colour has no RGB form.
    private static func components(_ colour: UIColor) -> [CGFloat]? {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard colour.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return [red, green, blue, alpha]
    }
}
