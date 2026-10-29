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
        #expect(try surface("x^2-y^2=z") == (try surface("z=x^2-y^2")))
    }

    @Test func zOnBothSidesIsNotAnExplicitSurface() throws {
        #expect(try surface("x+z=z^2") == nil)
    }
}
