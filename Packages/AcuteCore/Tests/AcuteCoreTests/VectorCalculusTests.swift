import Foundation
import Testing
@testable import AcuteCore

// MARK: Vector analysis and spherical triangles

@Suite struct VectorCalculusTests {
    private func evaluate(_ e: Expr, _ variables: [String: Double] = [:]) throws -> Double {
        try RealEvaluator.evaluate(e, context: EvaluationContext(variables: variables))
    }

    @Test func differentialOperators() throws {
        // div (x²y, xy, z) = 2xy + x + 1
        let div = try VectorCalculus.divergence([try parse("x^2*y"), try parse("x*y"), try parse("z")])
        #expect(approx(try evaluate(div, ["x": 1, "y": 2, "z": 3]), 6))
        // rot (−y, x, 0) = (0, 0, 2); in the plane ∂Q/∂x − ∂P/∂y = 2
        let rot = try VectorCalculus.curl([try parse("-y"), try parse("x"), .zero])
        #expect(rot.count == 3)
        #expect(approx(try evaluate(rot[0]), 0))
        #expect(approx(try evaluate(rot[1]), 0))
        #expect(approx(try evaluate(rot[2]), 2))
        let planar = try VectorCalculus.curl([try parse("-y"), try parse("x")])
        #expect(planar.count == 1)
        #expect(approx(try evaluate(planar[0]), 2))
        let laplace = try VectorCalculus.laplacian(try parse("x^2 + y^2 + z^2"), variables: ["x", "y", "z"])
        #expect(approx(try evaluate(laplace, ["x": 0.3, "y": -1, "z": 2]), 6))
        let harmonic = try VectorCalculus.laplacian(try parse("e^x*sin(y)"), variables: ["x", "y"])
        #expect(approx(try evaluate(harmonic, ["x": 0.7, "y": 1.9]), 0))
    }

    @Test func potentials() throws {
        // (2xy + z, x², x) = ∇(x²y + xz)
        let field = [try parse("2x*y + z"), try parse("x^2"), try parse("x")]
        #expect(VectorCalculus.isConservative(field))
        let phi = try #require(VectorCalculus.potential(field))
        #expect(approx(try evaluate(phi, ["x": 1, "y": 2, "z": 3]) - (try evaluate(phi, ["x": 0, "y": 0, "z": 0])), 5))
        let swirl = [try parse("-y"), try parse("x")]
        #expect(!VectorCalculus.isConservative(swirl))
        #expect(VectorCalculus.potential(swirl) == nil)
    }

    @Test func lineIntegrals() throws {
        // ∮ −y dx + x dy around the unit circle = 2π
        let circle = [try parse("cos(t)"), try parse("sin(t)")]
        let work = try VectorCalculus.workIntegrand([try parse("-y"), try parse("x")], curve: circle, parameter: "t")
        let circulation = try VectorCalculus.integrate(work, parameter: "t", from: .zero, to: try parse("2pi"))
        #expect(approx(circulation.value, 2 * .pi))
        let exact = try #require(circulation.exact)
        #expect(approx(try evaluate(exact), 2 * .pi))
        // One turn of the helix (cos t, sin t, t) is 2π√2 long.
        let helix = [try parse("cos(t)"), try parse("sin(t)"), try parse("t")]
        let ds = try VectorCalculus.arcIntegrand(.one, curve: helix, parameter: "t")
        let length = try VectorCalculus.integrate(ds, parameter: "t", from: .zero, to: try parse("2pi"))
        #expect(approx(length.value, 2 * .pi * 2.0.squareRoot()))
    }

    @Test func sphereAreaAndFlux() throws {
        // Unit sphere: area 4π; the flux of (x, y, z) outwards is 4π = ∭ div F dV (Gauss).
        let sphere = [try parse("sin(u)*cos(v)"), try parse("sin(u)*sin(v)"), try parse("cos(u)")]
        let bounds = (lower: [Expr.zero, .zero], upper: [try parse("pi"), try parse("2pi")])
        let dS = try VectorCalculus.areaIntegrand(.one, surface: sphere, parameters: "u", "v")
        let area = try Multivariable.iteratedIntegral(dS, variables: ["u", "v"], lower: bounds.lower, upper: bounds.upper)
        #expect(approx(area, 4 * .pi, 1e-7))
        let flux = try VectorCalculus.fluxIntegrand([try parse("x"), try parse("y"), try parse("z")], surface: sphere, parameters: "u", "v")
        let outward = try Multivariable.iteratedIntegral(flux, variables: ["u", "v"], lower: bounds.lower, upper: bounds.upper)
        #expect(approx(outward, 4 * .pi, 1e-7))
    }
}

@Suite struct SphericalTriangleTests {
    @Test func octantAndEquilateral() throws {
        let octant = try #require(SphericalTriangle.sides(.pi / 2, .pi / 2, .pi / 2))
        #expect(approx(octant.alpha, .pi / 2) && approx(octant.beta, .pi / 2) && approx(octant.gamma, .pi / 2))
        #expect(approx(octant.excess, .pi / 2))
        let equilateral = try #require(SphericalTriangle.sides(.pi / 3, .pi / 3, .pi / 3))
        #expect(approx(equilateral.alpha, acos(1.0 / 3)))
        let fromAngles = try #require(SphericalTriangle.angles(.pi / 2, .pi / 2, .pi / 2))
        #expect(approx(fromAngles.a, .pi / 2) && approx(fromAngles.c, .pi / 2))
    }

    @Test func mixedCases() throws {
        let sas = try #require(SphericalTriangle.sides(.pi / 2, .pi / 2, included: .pi / 2))
        #expect(approx(sas.a, .pi / 2) && approx(sas.beta, .pi / 2))
        let asa = try #require(SphericalTriangle.angles(.pi / 2, .pi / 2, included: .pi / 2))
        #expect(approx(asa.alpha, .pi / 2) && approx(asa.b, .pi / 2))
        // Round trip: sides → angles → sides
        let t = try #require(SphericalTriangle.sides(0.9, 1.2, 1.4))
        let back = try #require(SphericalTriangle.angles(t.alpha, t.beta, t.gamma))
        #expect(approx(back.a, 0.9) && approx(back.b, 1.2) && approx(back.c, 1.4))
        #expect(SphericalTriangle.sides(1, 1, 3) == nil)
        #expect(SphericalTriangle.angles(0.5, 0.5, 0.5) == nil)
    }
}
