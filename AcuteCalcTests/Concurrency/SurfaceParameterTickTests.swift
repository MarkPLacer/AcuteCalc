import AcuteCore
import Testing
@testable import AcuteCalc

/// UI-04 (a): a parameter tick samples the z range of a 3D surface or a complex landscape once (49 × 49
/// evaluations on the main actor; ≈ 4.8 ms for |ζ(z)| on ±16 in the audit's desktop port), not three times or
/// twice, and gives the same z range as a new model.
@MainActor
@Suite struct SurfaceParameterTickTests {
    /// What SurfaceWorkspaceView.apply() does with the model for z = f(x, y) on ±4, also on every parameter tick.
    private func apply(_ body: Expr, a: Double, to surface: SurfaceModel) {
        surface.colorMode = .height
        surface.zScale = 0.75
        surface.domain = SIMD4(-4, 4, -4, 4)
        surface.setFunction(body, parameters: ["a": a])
    }

    @Test func aParameterTickOfASurfaceSamplesTheZRangeOnce() throws {
        let body = try Parser.parse("a*sin(x^2+y^2)")
        let surface = SurfaceModel()
        apply(body, a: 1, to: surface)
        let before = surface.zRangeSamplings
        apply(body, a: 2.5, to: surface)
        // Before the fix the unchanged domain, the new parameters and setFunction each sampled it.
        #expect(surface.zRangeSamplings == before + 1)
        let fresh = SurfaceModel()
        fresh.setFunction(body, parameters: ["a": 2.5])
        #expect(surface.zRange == fresh.zRange)
        #expect(surface.errorMessage == nil)
    }

    @Test func aParameterTickOfAComplexLandscapeSamplesTheZRangeOnce() throws {
        let body = try Parser.parse("z^2+a")
        let landscape = SurfaceModel()
        landscape.kind = .complexModulus
        // What ComplexWorkspaceView.apply() hands the landscape, also on every parameter tick.
        landscape.setFunction(body, parameters: ["a": 1])
        let before = landscape.zRangeSamplings
        landscape.setFunction(body, parameters: ["a": 2])
        // Before the fix the new parameters and setFunction each sampled it.
        #expect(landscape.zRangeSamplings == before + 1)
        let fresh = SurfaceModel()
        fresh.kind = .complexModulus
        fresh.setFunction(body, parameters: ["a": 2])
        #expect(landscape.zRange == fresh.zRange)
    }

    @Test func aNewDomainSamplesTheZRangeAgain() throws {
        let body = try Parser.parse("x^2+y^2")
        let surface = SurfaceModel()
        surface.setFunction(body, parameters: [:])
        let before = surface.zRangeSamplings
        surface.domain = SIMD4(-2, 2, -2, 2)
        #expect(surface.zRangeSamplings == before + 1)
        let fresh = SurfaceModel()
        fresh.domain = SIMD4(-2, 2, -2, 2)
        fresh.setFunction(body, parameters: [:])
        #expect(surface.zRange == fresh.zRange)
    }

    @Test func aFunctionWithNewParametersCompilesWithThem() throws {
        let first = try Parser.parse("a*x")
        let second = try Parser.parse("b*y")
        let surface = SurfaceModel()
        surface.setFunction(first, parameters: ["a": 1])
        // A new function with another parameter: compiled with its slot, its z range sampled once
        // (before the fix twice: for the new parameters and again by setFunction).
        let before = surface.zRangeSamplings
        surface.setFunction(second, parameters: ["b": 3])
        #expect(surface.errorMessage == nil)
        #expect(surface.program != nil)
        #expect(surface.parameterNames == ["b"])
        #expect(surface.zRangeSamplings == before + 1)
        let fresh = SurfaceModel()
        fresh.setFunction(second, parameters: ["b": 3])
        #expect(surface.zRange == fresh.zRange)
    }
}
