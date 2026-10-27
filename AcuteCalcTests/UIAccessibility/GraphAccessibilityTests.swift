import AcuteCore
import Testing
@testable import AcuteCalc

/// A11Y-05: the 2D graph (a Metal view) gets a VoiceOver summary of the visible functions and one
/// element per special point, with coordinates formatted like the on-screen callout.
@MainActor
@Suite struct GraphAccessibilityTests {
    let style = MathStyle(decimalSeparator: ",")

    @Test func summaryListsTheVisibleFunctions() {
        let items = [
            PlotItem(id: "a", kind: .explicit(.function(.sin, [.variable("x")])), color: GraphPalette.color(0)),
            PlotItem(id: "b", kind: .explicit(.variable("x")), color: GraphPalette.color(1), visible: false),
        ]
        #expect(GraphAccessibility.summary(items: items, pointCount: 2, style: style) == "y = sin(x); posebne točke: 2")
        #expect(GraphAccessibility.summary(items: items, pointCount: 0, style: style) == "y = sin(x)")
        #expect(GraphAccessibility.summary(items: [], pointCount: 0, style: style) == "Brez funkcij")
    }

    @Test func specialPointsUseTheDisplayedFormat() throws {
        let zero = GraphPointInfo(point: SpecialPoint(kind: .zero, x: 0, y: 0), color: GraphPalette.color(0))
        #expect(GraphAccessibility.point(zero, style: style) == "Ničla: x = 0, y = 0")
        let half = try #require(Rational(1, 2))
        let maximum = GraphPointInfo(point: SpecialPoint(kind: .maximum, x: 0.5, y: 1.25, exactX: ExactReal(half)),
                                     color: GraphPalette.color(0))
        #expect(GraphAccessibility.point(maximum, style: style) == "Maksimum: x = (1)/(2), y = 1,25")
    }
}
