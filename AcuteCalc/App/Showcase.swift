import AcuteCore
import Foundation

/// Screenshot scenes for the README (Debug builds only; a no-op in Release).
///
/// The screenshot UI test (AcuteCalcScreenshots) launches the app once per scene with
/// `ACUTE_SHOWCASE` naming it (`graphs`, `analysis`, `calculator`, `surface`, `complex`, `tools`
/// or `formulas`) and `ACUTE_SHOWCASE_APPEARANCE` set to `dark` or `light`. The scene is built
/// here from input as a student would type it, then the test captures the whole screen.
enum Showcase {
    static func run(calculator: CalculatorModel, store: AppStore, settings: AppSettings, select: (AppTab) -> Void) async {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        guard let scene = environment["ACUTE_SHOWCASE"] else { return }
        settings.appearance = environment["ACUTE_SHOWCASE_APPEARANCE"] == "light" ? .light : .dark
        switch scene {
        case "graphs":
            // The word "Acute" drawn by nine parametric curves, one colour per letter.
            settings.graphLineWidth = 5
            store.graphFunctions = GraphPresets.rows(for: GraphPresets.lettering).map {
                GraphFunctionDefinition(row: $0.row, colorIndex: $0.color)
            }
            await showGraph(x: -1...28, y: 0...6, select: select)
        case "analysis":
            // Zeros, extrema, the inflection point, f′, a shaded integral and the intersections with g.
            settings.graphLineWidth = 3
            var cubic = GraphFunctionDefinition(row: typed("f(x)=x^3→-3x"), colorIndex: 0)
            cubic.showDerivative = true
            cubic.shadeEnabled = true
            cubic.shadeFrom = -3.0.squareRoot()
            cubic.shadeTo = 0
            store.graphFunctions = [cubic, GraphFunctionDefinition(row: typed("g(x)=x"), colorIndex: 1)]
            await showGraph(x: -3...3, y: -3.5...3.5, select: select)
        case "calculator":
            // A matura equation: exact periodic solutions, both sides drawn above.
            calculator.press(.clear)
            calculator.insert(row: typed("{sin}x→=1/2"))
            select(.calculator)
        case "surface":
            if let preset = SurfacePresets.real.first, let row = SurfacePresets.row(for: preset) {
                store.surfaces = [SurfaceDefinition(row: row, kind: preset.kind, extent: preset.extent)]
            }
            UserDefaults.standard.set(GraphSpace.space.rawValue, forKey: "graphSpace")
            select(.graphs)
        case "complex":
            store.complexFunction = typed("{zeta}z")
            UserDefaults.standard.set(ComplexViewMode.coloring.rawValue, forKey: "complexViewMode")
            UserDefaults.standard.set(GraphSpace.complex.rawValue, forKey: "graphSpace")
            select(.graphs)
        case "tools":
            // Slope field, the solution through (0, 1) and its closed form.
            select(.tools)
            try? await Task.sleep(for: .seconds(1))
            SmokeHooks.openTool?(.differentialEquations)
        case "formulas":
            select(.formulas)
        default:
            break
        }
        #endif
    }

    #if DEBUG
    private static func showGraph(x: ClosedRange<Double>, y: ClosedRange<Double>, select: (AppTab) -> Void) async {
        UserDefaults.standard.set(GraphSpace.plane.rawValue, forKey: "graphSpace")
        select(.graphs)
        try? await Task.sleep(for: .seconds(2))
        SmokeHooks.frameGraph?(x, y)
    }

    /// A row as typed on the keypad (see `SmokeTest.keys`), so `f(x) = …` keeps its name.
    private static func typed(_ keys: String) -> MathRow {
        var editor = MathEditor()
        for key in SmokeTest.keys(keys) { _ = editor.apply(key) }
        return editor.root
    }
    #endif
}
