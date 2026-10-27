import AcuteCore
import Foundation
import Testing
@testable import AcuteCalc

/// A calculator model with its own data file and settings (the model keeps both weakly).
@MainActor
final class PreviewStoredValuesFixture {
    let directory: URL
    let suite: String
    let store: AppStore
    let settings: AppSettings
    let model = CalculatorModel()

    init() throws {
        let directory = try AppDataInputTestSupport.makeDirectory()
        let suite = "AppDataInput-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        self.directory = directory
        self.suite = suite
        store = AppStore(fileURL: directory.appendingPathComponent("AcuteCalcData.json"))
        settings = AppSettings(defaults: defaults)
        model.store = store
        model.settings = settings
    }

    /// Types `text` (letters are variable symbols, * is ×) and presses =, as on the keypad.
    func enter(_ text: String) {
        model.editor = MathEditor(root: MathRow.text(text))
        model.press(.enter)
    }

    func tearDown() {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}

/// GAP-gap-preview-vars-1: CalculationEngine leaves stored values (A–F, X, Y, M, Ans) out of the graph's
/// parameters so they get no slider, but the preview canvas and the 3D model got only the sliders, so
/// y = A·x, x² + y² = A and z = A·x·y could not be compiled and silently drew nothing. Reference values
/// by hand: A = 2 gives 2·3 = 6, 0·3 + 1 = 1, 2² + 0² − 2 = 2 and 2·1·1 = 2 (exact in Double).
@MainActor
@Suite struct PreviewStoredValuesTests {
    @Test func explicitCurveUsesStoredValues() throws {
        let fixture = try PreviewStoredValuesFixture()
        defer { fixture.tearDown() }
        fixture.store.store(2, rational: Rational(2, 1), in: "A")

        for (text, expected) in [("y=A*x", 6.0), ("y=M*x+1", 1.0)] {   // M is the memory, 0
            fixture.enter(text)
            let sliders = fixture.model.calculation?.graph?.parameters
            #expect(sliders == [], "\(text) gets no slider")
            guard case .explicit(let f)? = fixture.model.graph.items.first?.kind else {
                Issue.record("\(text) is not an explicit graph")
                continue
            }
            let y = fixture.model.graph.makeFunction(f)(3)
            #expect(y == expected, "\(text) at x = 3")   // before the fix: NaN, nothing is drawn
        }
    }

    @Test func implicitRelationUsesStoredValues() throws {
        let fixture = try PreviewStoredValuesFixture()
        defer { fixture.tearDown() }
        fixture.store.store(2, rational: Rational(2, 1), in: "A")

        fixture.enter("x*x+y*y=A")
        guard case .implicit(let lhs, _, let rhs)? = fixture.model.graph.items.first?.kind else {
            Issue.record("x² + y² = A is not an implicit graph")
            return
        }
        // As GraphCanvasModel.implicitProgram compiles it: slots x, y and one per canvas parameter.
        let parameters = fixture.model.graph.parameters
        let names = parameters.keys.sorted()
        var slots: [String: VariableSlot] = ["x": .x, "y": .y]
        for (i, name) in names.enumerated() { slots[name] = .parameter(i) }
        // Before the fix the canvas has no parameter A: undefinedVariable("A"), the circle is skipped.
        let program = try BytecodeCompiler(slots: slots).compile(.sum([lhs, .negation(rhs)]))
        let vm = RealVM(program: program, parameters: names.map { parameters[$0] ?? 0 })
        #expect(vm.evaluate(x: 2, y: 0) == 2)
    }

    @Test func surfaceUsesStoredValues() throws {
        let fixture = try PreviewStoredValuesFixture()
        defer { fixture.tearDown() }
        fixture.store.store(2, rational: Rational(2, 1), in: "A")

        fixture.enter("z=A*x*y")
        #expect(fixture.model.isSurface)
        // Before the fix SurfaceModel cannot compile A (program nil) and the 3D preview shows only the box.
        let program = try #require(fixture.model.surface.program)
        let surface = fixture.model.surface
        let vm = RealVM(program: program, parameters: surface.parameterNames.map { surface.parameters[$0] ?? 0 })
        #expect(vm.evaluate(x: 1, y: 1) == 2)
    }

    /// Not a regression test: sliders behave as before, also for a memory that was deleted.
    @Test func slidersStayAsBefore() throws {
        let fixture = try PreviewStoredValuesFixture()
        defer { fixture.tearDown() }
        fixture.store.store(2, rational: Rational(2, 1), in: "A")
        fixture.enter("y=A*x")

        fixture.store.variables["A"] = nil
        fixture.enter("y=A*x")
        let sliders = fixture.model.calculation?.graph?.parameters
        #expect(sliders == ["A"])
        #expect(fixture.model.graph.parameters["A"] == 1)   // a new slider starts at 1, not at the old A = 2

        fixture.enter("y=k*x")
        let next = fixture.model.calculation?.graph?.parameters
        #expect(next == ["k"])
        #expect(fixture.model.graph.parameters["k"] == 1)
    }
}
