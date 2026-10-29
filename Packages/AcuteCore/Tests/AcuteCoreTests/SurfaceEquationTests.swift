import Testing
@testable import AcuteCore

/// A surface may be written with z on either side: z = f(x, y) and f(x, y) = z.
@Suite struct SurfaceEquationTests {
    private func request(_ text: String) throws -> GraphRequest {
        let expr = try Parser.parse(text)
        return try #require(CalculationEngine.graphRequest(for: expr))
    }

    private func surface(_ text: String) throws -> Expr? {
        let expr = try Parser.parse(text)
        guard case .surface(let body)? = CalculationEngine.graphRequest(for: expr)?.kinds.first else { return nil }
        return body
    }

    @Test func zOnTheRight() throws {
        let body = try #require(try surface("xy=z"))
        let program = try BytecodeCompiler(slots: ["x": .x, "y": .y]).compile(body)
        #expect(RealVM(program: program).evaluate(x: 2, y: 3) == 6)
        #expect(try request("xy=z").parameters.isEmpty)
    }

    @Test func bothSidesAgree() throws {
        let lhs = try #require(try surface("x^2-y^2=z"))
        let rhs = try #require(try surface("z=x^2-y^2"))
        #expect(lhs == rhs)
    }

    /// F(x, y, z) = G(x, y, z) is the implicit surface F − G = 0 (raymarched by implicit_fragment).
    @Test func implicitSurfaces() throws {
        for text in ["x+z=z^2", "xyz=1", "x^2+y^2+z^2=4"] {
            let body = try #require(try surface(text), "\(text)")
            #expect(body.freeVariables.contains("z"))
        }
        let sphere = try #require(try surface("x^2+y^2+z^2=4"))
        let program = try BytecodeCompiler(slots: ["x": .x, "y": .y, "z": .t]).compile(sphere)
        let vm = RealVM(program: program)
        #expect(vm.evaluate(x: 2, y: 0, t: 0) == 0)
        #expect(vm.evaluate(x: 0, y: 0, t: 2) == 0)
        #expect(vm.evaluate(x: 0, y: 0, t: 0) == -4)
        #expect(try request("xyz=1").parameters.isEmpty)
    }

    /// The calculator agrees with the graphs: an equation in x, y and z is a surface even when x or y
    /// stands alone on one side.
    @Test func calculatorDrawsEquationsInThreeVariablesIn3D() throws {
        for text in ["y=x*z", "x*z=y", "x=y*z", "xyz=1", "y=z", "z=x+z^2"] {
            let calculation = CalculationEngine.calculate(try Parser.parse(text), variables: [:], exactVariables: [:], settings: CalculationSettings())
            guard case .surface(let body)? = calculation.graph?.kinds.first else {
                Issue.record("\(text): \(String(describing: calculation.graph?.kinds))")
                continue
            }
            #expect(!body.freeVariables.isEmpty, "\(text)")
        }
    }

    /// An equation in z alone stays an equation to solve, not a surface.
    @Test func zAloneIsNotASurface() throws {
        #expect(try surface("z^2=4") == nil)
    }
}
