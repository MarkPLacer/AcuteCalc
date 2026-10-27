import Testing
@testable import AcuteCalc

/// UI-07 (d): assigning an unchanged special-points setting (the calculator does it after every
/// graphed result) does not rebuild and redraw the scene; a change does.
@MainActor
@Suite struct GraphSceneRebuildTests {
    @Test func onlyChangedSettingsRebuildTheScene() throws {
        let canvas = GraphCanvasModel()
        var redraws = 0
        canvas.requestRedraw = { redraws += 1 }
        try #require(canvas.showSpecialPoints && canvas.highlightIntersections)
        canvas.showSpecialPoints = true
        canvas.highlightIntersections = true
        // Before the fix assigning the special points rebuilt the scene anyway.
        #expect(redraws == 0)
        canvas.showSpecialPoints = false
        #expect(redraws == 1)
        // Without the special points the intersection markers follow this flag.
        canvas.highlightIntersections = false
        #expect(redraws == 2)
    }
}
