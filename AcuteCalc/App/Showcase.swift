import AcuteCore
import Foundation
import OSLog

/// Screenshot scenes for the README (Debug builds only; a no-op in Release).
///
/// The screenshot UI test (AcuteCalcScreenshots) launches the app once per scene with
/// `ACUTE_SHOWCASE` naming it (`graphs`, `analysis`, `calculator`, `surface`, `landscape`,
/// `complex`, `tools` or `formulas`) and `ACUTE_SHOWCASE_APPEARANCE` set to `dark` or `light`.
/// The scene is built here from input as a student would type it, then the test captures the
/// whole screen. A scene that cannot be built is logged (the Screenshots workflow prints the
/// app's log).
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
            UserDefaults.standard.set(GraphSpace.plane.rawValue, forKey: "graphSpace")
            select(.graphs)
            await frame({ SmokeHooks.frameGraph }, x: -1...28, y: 0...6)
        case "analysis":
            // Zeros, extrema, the inflection point, f′, a shaded integral and the intersections with g.
            settings.graphLineWidth = 3
            var cubic = GraphFunctionDefinition(row: typed("f(x)=x^3→-3x"), colorIndex: 0)
            cubic.showDerivative = true
            cubic.shadeEnabled = true
            cubic.shadeFrom = -3.0.squareRoot()
            cubic.shadeTo = 0
            store.graphFunctions = [cubic, GraphFunctionDefinition(row: typed("g(x)=x"), colorIndex: 1)]
            UserDefaults.standard.set(GraphSpace.plane.rawValue, forKey: "graphSpace")
            select(.graphs)
            await frame({ SmokeHooks.frameGraph }, x: -3...3, y: -3.5...3.5)
        case "calculator":
            // A matura equation: exact periodic solutions, both sides drawn above.
            calculator.press(.clear)
            calculator.insert(row: typed("{sin}x→=1/2"))
            select(.calculator)
        case "surface":
            // Two hills and two valleys: the extrema of a function of two variables.
            if let preset = SurfacePresets.real.first(where: { $0.text == "z=x*y*e^(-(x^2+y^2)/2)" }),
               let row = SurfacePresets.row(for: preset) {
                store.surfaces = [SurfaceDefinition(row: row, kind: preset.kind, extent: preset.extent)]
            } else {
                log.error("Showcase surface: the 3D example z = x·y·e^(−(x² + y²)/2) is missing")
            }
            UserDefaults.standard.set(GraphSpace.space.rawValue, forKey: "graphSpace")
            select(.graphs)
        case "landscape":
            // |Γ(z)| over the complex plane, coloured by arg Γ(z): the poles rise as spikes.
            if let preset = SurfacePresets.complex.first(where: { $0.text == "gamma(z)" }),
               let row = SurfacePresets.row(for: preset) {
                var surface = SurfaceDefinition(row: row, kind: preset.kind, extent: preset.extent)
                surface.colorMode = preset.colorMode
                store.surfaces = [surface]
            } else {
                log.error("Showcase landscape: the 3D example |Γ(z)| is missing")
            }
            UserDefaults.standard.set(GraphSpace.space.rawValue, forKey: "graphSpace")
            select(.graphs)
        case "complex":
            // Domain colouring of Γ(z): the poles at 0, −1, −2, … are bright points.
            do {
                store.complexFunction = try MathRowConverter.row(fromText: "gamma(z)")
            } catch {
                log.error("Showcase complex: gamma(z) did not parse: \(error.localizedDescription, privacy: .public)")
            }
            UserDefaults.standard.set(ComplexViewMode.coloring.rawValue, forKey: "complexViewMode")
            UserDefaults.standard.set(GraphSpace.complex.rawValue, forKey: "graphSpace")
            select(.graphs)
        case "tools":
            // Slope field, the solution through (0, 1) and its closed form.
            select(.tools)
            if let open = await hook({ SmokeHooks.openTool }) { open(.differentialEquations) }
        case "formulas":
            select(.formulas)
        default:
            log.error("Showcase: no scene \(scene, privacy: .public)")
        }
        #endif
    }

    #if DEBUG
    private static let log = Logger(subsystem: "com.markplacer.acutecalc", category: "Showcase")

    /// A hook once its view has appeared and registered it (nil after 30 s, logged).
    private static func hook<Value>(_ read: () -> Value?) async -> Value? {
        for _ in 0..<120 {
            if let value = read() { return value }
            try? await Task.sleep(for: .milliseconds(250))
        }
        log.error("Showcase: a view did not register its hook within 30 s")
        return nil
    }

    /// Frames a graph twice, the second time after the canvas has its final size.
    private static func frame(_ read: () -> ((ClosedRange<Double>, ClosedRange<Double>) -> Void)?,
                              x: ClosedRange<Double>, y: ClosedRange<Double>) async {
        guard let show = await hook(read) else { return }
        for _ in 0..<2 {
            try? await Task.sleep(for: .seconds(1))
            show(x, y)
        }
    }

    /// A row as typed on the keypad (see `SmokeTest.keys`), so `f(x) = …` keeps its name.
    private static func typed(_ keys: String) -> MathRow {
        var editor = MathEditor()
        for key in SmokeTest.keys(keys) { _ = editor.apply(key) }
        return editor.root
    }
    #endif
}
