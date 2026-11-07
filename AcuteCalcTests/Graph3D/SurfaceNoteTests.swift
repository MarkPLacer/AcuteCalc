import AcuteCore
import Testing
@testable import AcuteCalc

/// docs:3: Grafi called every row it can only show in 3D a function of two variables, also an equation in x, y and
/// z such as x² + y² + z² = 4, which is drawn as the implicit surface F(x, y, z) = 0.
@MainActor
@Suite struct SurfaceNoteTests {
    @Test func grafiNamesAnEquationInXYAndZASurface() throws {
        let sphere = try GraphFunctionDefinition(row: MathRowConverter.row(fromText: "x^2+y^2+z^2=4"), colorIndex: 0)
        let saddle = try GraphFunctionDefinition(row: MathRowConverter.row(fromText: "x*y"), colorIndex: 1)
        let model = GraphWorkspaceModel()
        model.sync([sphere, saddle], parameters: [:], lineWidth: 3, showSpecialPoints: true)
        #expect(model.notes[sphere.id] == "Ploskev F(x, y, z) = 0 – prikaži jo v 3D.")
        #expect(model.notes[saddle.id] == "Funkcija dveh spremenljivk – prikaži jo v 3D.")
    }
}
