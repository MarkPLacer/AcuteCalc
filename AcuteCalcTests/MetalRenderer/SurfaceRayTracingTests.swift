import AcuteCore
import Testing
@testable import AcuteCalc

/// Sence in odsevi (ray tracing) on z = f(x, y). The simulator has no ray tracing GPU, so these check the
/// parts that run on the CPU.
@MainActor
@Suite struct SurfaceRayTracingTests {
    /// Audit metal:1: the traced mesh had a fixed 96 × 96 grid while the surface is drawn at 160 × 160 by
    /// default, so shadow and mirror rays could start under the traced triangles.
    @Test func theTracedMeshIsTheDrawnGrid() throws {
        let body = try Parser.parse("sin(x^2+y^2)")
        let model = SurfaceModel()
        model.setFunction(body)
        let program = try #require(model.program)
        let n = SurfaceEncoder.gridResolution(model)
        #expect(n == 160)
        let signature = SurfaceRayTracing.Signature(instructions: program.instructions, parameters: [], domain: model.domain,
                                                    zRange: model.zRange, zScale: model.zScale, resolution: n)
        let (positions, indices) = SurfaceRayTracing.mesh(signature, program: program)
        #expect(positions.count == n * n * 3)
        // surface_vertex puts vertex (i, j) at X = i / (n − 1) · 2 − 1 and Z = −(j / (n − 1) · 2 − 1).
        let last = 3 * (n * n - 1)
        #expect(positions[3] == Float(1 / Double(n - 1) * 2 - 1))
        #expect(positions[last] == 1)
        #expect(positions[last + 2] == -1)
        let inGrid = indices.allSatisfy { Int($0) < n * n }
        #expect(inGrid)
        #expect(indices.count <= (n - 1) * (n - 1) * 6)
    }
}
