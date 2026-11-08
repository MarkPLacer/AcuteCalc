import AcuteCore
import Testing
@testable import AcuteCalc

/// docs:3: Grafi gave every row it can show only in 3D the note »Funkcija dveh spremenljivk« (a function of two
/// variables), even an equation in x, y and z such as x² + y² + z² = 4, which is the implicit surface F(x, y, z) = 0.
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
