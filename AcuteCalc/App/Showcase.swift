import AcuteCore
import Foundation
import OSLog

/// Screenshot scenes, for the README and for agents that need to see the UI (Debug builds only;
/// a no-op in Release).
///
/// `ACUTE_SHOWCASE` lists the scenes, comma-separated (`graphs`, `analysis`, `calculator`,
/// `surface`, `landscape`, `complex`, `tools`, `formulas`, or `all`), `ACUTE_SHOWCASE_APPEARANCE`
/// their appearance (`dark`, `light` or `both`, dark first; `scene@light` gives one scene its
/// own). The app shows them one after another in a single launch, each built here from input as
/// a student would type it; once a scene has settled, the screenshot UI test
/// (AcuteCalcScreenshots) captures the whole screen and lets the app go on (see ShowcaseSync).
/// A scene that cannot be built as asked is logged and listed with its picture. The scenes
/// replace the graphs, surfaces and settings they use: run them on a simulator, not on a device
/// with your own work.
enum Showcase {
    /// Every scene, in the order of `all`.
    static let scenes = ["graphs", "analysis", "calculator", "surface", "landscape", "complex", "tools", "formulas"]

    static func run(calculator: CalculatorModel, store: AppStore, settings: AppSettings, select: (AppTab) -> Void) async {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        guard let request = environment["ACUTE_SHOWCASE"] else { return }
        let shots: [ShowcaseSync.Shot]
        do {
            shots = try plan(request, appearance: environment["ACUTE_SHOWCASE_APPEARANCE"] ?? "dark")
        } catch {
            ShowcaseSync.write("plan.json", ShowcaseSync.Plan(shots: [], error: String(describing: error)))
            return
        }
        ShowcaseSync.write("plan.json", ShowcaseSync.Plan(shots: shots))
        for (index, shot) in shots.enumerated() {
            let start = ContinuousClock.now
            problems = []
            settings.appearance = shot.appearance == "light" ? .light : .dark
            settings.graphLineWidth = 3  // the default; a scene may change it
            await show(shot.scene, calculator: calculator, store: store, settings: settings, select: select)
            let settled = await ShowcaseSync.settle()
            ShowcaseSync.write("ready-\(index).json",
                               ShowcaseSync.Ready(seconds: (ContinuousClock.now - start) / .seconds(1), settled: settled,
                                                  problems: problems))
            // The test captures the screen, then lets the next scene in.
            guard await ShowcaseSync.wait(for: "ack-\(index)") else { return }
        }
        #endif
    }

    #if DEBUG
    private static let log = Logger(subsystem: "com.markplacer.acutecalc", category: "Showcase")

    /// What went wrong while building the current scene.
    private static var problems: [String] = []

    /// Logs a scene that cannot be built as asked; the test lists it with the picture.
    private static func report(_ problem: String) {
        log.error("Showcase: \(problem, privacy: .public)")
        problems.append(problem)
    }

    nonisolated struct RequestError: Error, CustomStringConvertible {
        var description: String
    }

    /// The shots of a request such as `graphs,calculator@light` or `all`, the dark ones first.
    static func plan(_ request: String, appearance: String) throws(RequestError) -> [ShowcaseSync.Shot] {
        guard ["dark", "light", "both"].contains(appearance) else {
            throw RequestError(description: "Unknown appearance \(appearance); use dark, light or both")
        }
        let items = request.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var shots: [ShowcaseSync.Shot] = []
        for look in ["dark", "light"] {
            for item in items {
                // A trailing `@` keeps an empty look, so `graphs@` is an error rather than `graphs`.
                let parts = item.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
                let names = parts.first == "all" ? scenes : [parts.first ?? item]
                guard names.allSatisfy({ scenes.contains($0) }) else {
                    throw RequestError(description: "Unknown scene \(item); the scenes are \(scenes.joined(separator: ", ")) and all")
                }
                let looks = parts.count > 1 ? [parts[1]] : (appearance == "both" ? ["dark", "light"] : [appearance])
                guard looks.allSatisfy({ $0 == "dark" || $0 == "light" }) else {
                    throw RequestError(description: "Unknown appearance in \(item); use @dark or @light")
                }
                for name in names where looks.contains(look) {
                    let shot = ShowcaseSync.Shot(scene: name, appearance: look)
                    if !shots.contains(shot) { shots.append(shot) }
                }
            }
        }
        guard !shots.isEmpty else { throw RequestError(description: "No scene requested") }
        return shots
    }

    /// Builds one scene.
    private static func show(_ scene: String, calculator: CalculatorModel, store: AppStore, settings: AppSettings,
                             select: (AppTab) -> Void) async {
        switch scene {
        case "graphs":
            // The word "Acute" drawn by nine parametric curves, one colour per letter.
            settings.graphLineWidth = 5
            store.graphFunctions = GraphPresets.rows(for: GraphPresets.lettering).map {
                GraphFunctionDefinition(row: $0.row, colorIndex: $0.color)
            }
            use(.plane)
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
            use(.plane)
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
                report("the 3D example z = x·y·e^(−(x² + y²)/2) is missing")
            }
            use(.space)
            select(.graphs)
        case "landscape":
            // |Γ(z)| over the complex plane, coloured by arg Γ(z): the poles rise as spikes.
            if let preset = SurfacePresets.complex.first(where: { $0.text == "gamma(z)" }),
               let row = SurfacePresets.row(for: preset) {
                var surface = SurfaceDefinition(row: row, kind: preset.kind, extent: preset.extent)
                surface.colorMode = preset.colorMode
                store.surfaces = [surface]
            } else {
                report("the 3D example |Γ(z)| is missing")
            }
            use(.space)
            select(.graphs)
        case "complex":
            // Domain colouring of Γ(z): the poles at 0, −1, −2, … are bright points.
            do {
                store.complexFunction = try MathRowConverter.row(fromText: "gamma(z)")
            } catch {
                report("gamma(z) did not parse: \(error.localizedDescription)")
            }
            UserDefaults.standard.set(ComplexViewMode.coloring.rawValue, forKey: "complexViewMode")
            use(.complex)
            select(.graphs)
        case "tools":
            // Slope field, the solution through (0, 1) and its closed form.
            select(.tools)
            if let open = await hook({ SmokeHooks.openTool }) { open(.differentialEquations) }
        case "formulas":
            select(.formulas)
        default:
            report("no scene \(scene)")
        }
    }

    /// Shows `space` in the Graphs tab. A 2D workspace that comes up anew registers its hook
    /// again; until then the old one would frame a graph that is gone.
    private static func use(_ space: GraphSpace) {
        if (UserDefaults.standard.string(forKey: "graphSpace") ?? GraphSpace.plane.rawValue) != space.rawValue {
            SmokeHooks.frameGraph = nil
        }
        UserDefaults.standard.set(space.rawValue, forKey: "graphSpace")
    }

    /// A hook once its view has appeared and registered it (nil after 30 s, reported).
    private static func hook<Value>(_ read: () -> Value?) async -> Value? {
        for _ in 0..<120 {
            if let value = read() { return value }
            try? await Task.sleep(for: .milliseconds(250))
        }
        report("a view did not register its hook within 30 s")
        return nil
    }

    /// Frames a graph once the app has settled, and again once the canvas has its final size.
    private static func frame(_ read: () -> ((ClosedRange<Double>, ClosedRange<Double>) -> Void)?,
                              x: ClosedRange<Double>, y: ClosedRange<Double>) async {
        guard let show = await hook(read) else { return }
        for _ in 0..<2 {
            await ShowcaseSync.settle()
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
