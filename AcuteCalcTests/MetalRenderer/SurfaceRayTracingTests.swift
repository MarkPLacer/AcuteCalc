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
        // What `update` builds for the model.
        let signature = SurfaceRayTracing.signature(for: model, program: program)
        #expect(signature.resolution == n)
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
        // The finest grid Nastavitve offer is traced as it is drawn, too.
        model.resolution = SurfaceRayTracing.maxResolution
        let finest = SurfaceRayTracing.signature(for: model, program: program)
        #expect(finest.resolution == SurfaceRayTracing.maxResolution)
        #expect(SurfaceEncoder.gridResolution(model) == SurfaceRayTracing.maxResolution)
    }

    /// Audit concurrency:5: a failed build was started again on every redraw, without a limit. Now a delayed
    /// retry tries it three times, ever later, and then the surface is drawn without ray tracing.
    @Test func aFailedBuildIsRetriedThreeTimesWithAGrowingDelay() {
        #expect(SurfaceRayTracing.retryDelay(afterFailures: 1) == Duration.milliseconds(250))
        #expect(SurfaceRayTracing.retryDelay(afterFailures: 2) == Duration.milliseconds(500))
        #expect(SurfaceRayTracing.retryDelay(afterFailures: 3) == Duration.seconds(1))
        #expect(SurfaceRayTracing.retryDelay(afterFailures: 4) == nil)
    }
}
