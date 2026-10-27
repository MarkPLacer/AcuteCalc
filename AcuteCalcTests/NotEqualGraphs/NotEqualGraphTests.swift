import AcuteCore
import Foundation
import Metal
import Testing
@testable import AcuteCalc

/// SHD-07 in the app: how GraphCanvasModel draws, frames and reads out the ≠ graphs of the engine.
@MainActor
@Suite struct NotEqualGraphCanvasTests {
    private func items(_ request: GraphRequest) -> [PlotItem] {
        request.kinds.enumerated().map { PlotItem(id: "k\($0.offset)", kind: $0.element, color: GraphPalette.color(0)) }
    }

    private func system(_ text: String) throws -> GraphRequest {
        let relations = try #require(Parser.parseSystem(tokens: try Lexer().tokenize(text)))
        return try #require(CalculationEngine.systemGraph(relations))
    }

    private func modes(_ request: GraphRequest) -> [Int32] {
        let canvas = GraphCanvasModel()
        canvas.items = items(request)
        canvas.rebuildScene()
        return canvas.scene.implicits.map { $0.mode }
    }

    /// x ≠ 2 is the region drawn like x > 2 (mode 3: filled, dashed edge), not the line x = 2 (mode 0 on main).
    /// 0 ≤ x ≤ 3, x ≠ 1 is that region (mode 3) with the band's edges solid over it (mode 4); main drew the
    /// line x = 1 alone (mode 0), the single strictness flag the band with x = 1 solid (mode 4 alone).
    @Test func notEqualIsDrawnAsARegion() throws {
        let line = try #require(CalculationEngine.graphRequest(for: try Parser.parse("x != 2")))
        #expect(modes(line) == [3])
        #expect(modes(try system("0<=x<=3, x!=1")) == [3, 4])
    }

    /// "Prilagodi pogled" frames x² + y² ≠ 4 and |z − 1| ≠ 2 by their circles, as main did (a guard: the region
    /// |F − G| > 0 has no sign change for ImplicitBounds, so the view stayed at ±20).
    @Test func fitFramesTheCurveOfANotEqual() throws {
        for (text, low, high) in [("x^2+y^2 != 4", -2.0, 2.0), ("|z-1| != 2", -1.0, 3.0)] {
            let canvas = GraphCanvasModel()
            canvas.viewport.size = CGSize(width: 400, height: 400)
            canvas.viewport.scale = SIMD2(10, 10)
            canvas.viewport.center = .zero
            canvas.items = items(try #require(CalculationEngine.graphRequest(for: try Parser.parse(text))))
            canvas.fitToContent()
            let x = canvas.viewport.visibleX
            #expect(x.lowerBound < low && x.upperBound > high, "\(text): \(x)")
            #expect(x.upperBound - x.lowerBound < 10, "\(text): \(x)")
        }
    }

    /// VoiceOver reads x ≠ 2 as typed (a guard: main read it so; the region read "|x − 2| > 0"), and a system
    /// with ≠ next to ≤ as one region (its solid edges are part of it, not a second relation).
    @Test func notEqualReadsAsTyped() throws {
        let style = MathStyle(decimalSeparator: ",")
        let relation = try Parser.parse("x != 2")
        guard case .relation(let lhs, .notEqual, let rhs) = relation else {
            Issue.record("x != 2 did not parse as a ≠ relation")
            return
        }
        let line = try #require(CalculationEngine.graphRequest(for: relation))
        let typed = MathAccessibility.label(MathRowConverter.row(for: .relation(lhs, .notEqual, rhs)), style: style)
        #expect(GraphAccessibility.summary(items: items(line), pointCount: 0, style: style) == typed)
        let band = items(try system("0<=x<=3, x!=1"))
        let first = try #require(band.first)
        #expect(GraphAccessibility.summary(items: band, pointCount: 0, style: style)
                == GraphAccessibility.summary(items: [first], pointCount: 0, style: style))
    }
}

/// The ≠ graphs rendered by the app's shaders through GraphRenderHarness: 240 × 240 px, 36 px per unit, white
/// items with the canvas's 22 % fill (56 of 255 over black), line half width 4.5 px. A pixel is drawn above 128.
/// The expected counts come from a float32 emulation of implicit_fragment (described in the commit message).
@MainActor
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "needs a Metal device"))
struct NotEqualGraphGPUTests {
    private static let size = 240

    private func render(_ request: GraphRequest) throws -> [UInt8] {
        let canvas = GraphCanvasModel()
        canvas.items = request.kinds.enumerated().map { PlotItem(id: "k\($0.offset)", kind: $0.element, color: .rgba(1, 1, 1)) }
        canvas.rebuildScene()
        return try GraphRenderHarness.render(canvas.scene, pointsPerUnit: 12, contentScale: 3, width: Self.size, height: Self.size)
    }

    private func request(_ text: String) throws -> GraphRequest {
        if let relations = Parser.parseSystem(tokens: try Lexer().tokenize(text)) {
            return try #require(CalculationEngine.systemGraph(relations))
        }
        return try #require(CalculationEngine.graphRequest(for: try Parser.parse(text)))
    }

    /// Pixel column whose centre is the first one right of graph x.
    private static func column(_ x: Double) -> Int { Int((x * 36 + Double(size) / 2).rounded(.down)) }

    private func drawn(_ pixels: [UInt8], column: Int) -> Int {
        (0..<Self.size).filter { pixels[$0 * Self.size + column] > 128 }.count
    }

    /// sin²x + cos²x ≠ 1 holds nowhere: nothing is drawn (emulation 0 px, as main). Compared exactly, the float
    /// rounding of sin²x + cos²x − 1 filled 12480 of the 57600 pixels.
    @Test func identityDrawsNothing() throws {
        let pixels = try render(try request("sin(x)^2+cos(x)^2 != 1"))
        let touched = pixels.filter { $0 > 20 }.count
        #expect(touched == 0, "\(touched) pixels")
    }

    /// Polynomial identities typed with ≠ hold nowhere, so nothing is drawn. Their float rounding grows with the
    /// terms (x², 2xy), not with F or G, beyond the tolerance of bc_compare (emulation: 226, 5920 and 12 pixels);
    /// main drew their curve F = G, which is the rounding noise of F − G (0, 6630 and 5908 pixels).
    @Test func polynomialIdentityDrawsNothing() throws {
        for text in ["(x+y)^2 != x^2+2x*y+y^2", "(x+y)^3 != x^3+3x^2*y+3x*y^2+y^3", "x*(x+y) != x^2+x*y"] {
            let pixels = try render(try request(text))
            let touched = pixels.filter { $0 > 20 }.count
            #expect(touched == 0, "\(text): \(touched) pixels")
        }
    }

    /// 0 ≤ x ≤ 3, x ≠ 1: the line x = 1 inside the filled band is dashed (emulation: 140 of 240 pixels of its
    /// column in 40 runs), the edges x = 0 and x = 3 are solid (240 each). Main and the single strictness flag drew
    /// x = 1 solid (240).
    @Test func excludedLineInAClosedBandIsDashed() throws {
        let pixels = try render(try request("0<=x<=3, x!=1"))
        let excluded = drawn(pixels, column: Self.column(1))
        #expect(excluded >= Self.size * 35 / 100 && excluded <= Self.size * 75 / 100, "\(excluded) of \(Self.size)")
        #expect(drawn(pixels, column: Self.column(0)) == Self.size)
        #expect(drawn(pixels, column: Self.column(3)) == Self.size)
        // Inside the band only the fill (56).
        let inside = pixels[Self.size / 2 * Self.size + Self.column(2)]
        #expect(inside > 30 && inside < 90, "\(inside)")
    }

    /// Pixels drawn at all (above 20) in the columns left of graph x.
    private func touched(_ pixels: [UInt8], leftOf x: Double) -> Int {
        var count = 0
        for row in 0..<Self.size {
            for px in 0..<Self.column(x) where pixels[row * Self.size + px] > 20 { count += 1 }
        }
        return count
    }

    /// The pixel at graph (x, y).
    private func pixel(_ pixels: [UInt8], _ x: Double, _ y: Double) -> UInt8 {
        pixels[Int((Double(Self.size) / 2 - y * 36).rounded(.down)) * Self.size + Self.column(x)]
    }

    /// min and max of an undefined value are undefined in the three GPU interpreters, in either order (ln x at
    /// x = −1 and −2, 1/z at z = 0), as on the CPU. bc_eval_dual kept the second operand when the first was NaN,
    /// Metal's min and max (bc_eval_real, bc_eval_complex) the defined one, so min(ln x; y) was y where ln x is
    /// undefined. Where both are defined the values are unchanged (at (1, 0.5): min 0, max 0.5, exact in float).
    @Test func minAndMaxOfAnUndefinedOperandAreUndefined() throws {
        let gpu = try ShaderPrecisionGPU()
        let ln = Expr.function(.ln, [.x])
        let points: [SIMD2<Float>] = [SIMD2(-1, 1), SIMD2(-2, 0.5), SIMD2(1, 0.5)]
        let z = Expr.variable("z")
        for function in [MathFunction.min, .max] {
            for arguments in [[ln, Expr.y], [Expr.y, ln]] {
                let program = try BytecodeCompiler(slots: ["x": .x, "y": .y]).compile(.function(function, arguments))
                for interpreter in [ShaderPrecisionGPU.Interpreter.real, .dual] {
                    let values = try gpu.evaluate(program, interpreter, at: points).values
                    #expect(values[0].x.isNaN, "\(interpreter) \(function) at (−1, 1): \(values[0].x)")
                    #expect(values[1].x.isNaN, "\(interpreter) \(function) at (−2, 0.5): \(values[1].x)")
                    #expect(values[2].x == (function == .min ? 0 : 0.5), "\(interpreter) \(function) at (1, 0.5): \(values[2].x)")
                }
            }
            for arguments in [[Expr.quotient(.one, z), Expr.int(2)], [Expr.int(2), Expr.quotient(.one, z)]] {
                let program = try BytecodeCompiler(slots: ["z": .z], complexMode: true).compile(.function(function, arguments))
                let value = try gpu.evaluate(program, .complex, at: [SIMD2(0, 0)]).values[0]
                #expect(value.x.isNaN, "complex \(function) at z = 0: \(value.x)")
            }
        }
    }

    /// y ≥ ln x, y ≤ 2 is drawn only where ln x is defined: nothing left of x = −0.1, the fill at (2, 1).
    /// The region min(y − ln x; 2 − y) was 2 − y there, so y ≤ 2 was filled and y = 2 drawn across x < 0
    /// (emulation: 22852 pixels left of x = −0.1 on main, 0 now).
    @Test func regionIsNotFilledWhereAnInequalityIsUndefined() throws {
        let pixels = try render(try request("y>=ln(x), y<=2"))
        #expect(touched(pixels, leftOf: -0.1) == 0)
        let inside = pixel(pixels, 2, 1)
        #expect(inside > 30 && inside < 90, "\(inside)")
    }

    /// y ≥ ln x, x ≠ 1 in both orders: the gaps of ≠ come last, min(y − ln x; gap of x ≠ 1), which was the gap
    /// where ln x is undefined, so all of x < 0 was filled (emulation: 27840 pixels left of x = −0.1, 0 now).
    /// Main drew only the line x = 1 (no fill at (2, 2)).
    @Test func notEqualRegionIsNotFilledWhereAnInequalityIsUndefined() throws {
        for text in ["y>=ln(x), x!=1", "x!=1, y>=ln(x)"] {
            let pixels = try render(try request(text))
            #expect(touched(pixels, leftOf: -0.1) == 0, "\(text)")
            let inside = pixel(pixels, 2, 2)
            #expect(inside > 30 && inside < 90, "\(text): \(inside)")
        }
    }

    /// x ≠ y: the diagonal through the pixel centres (column + row = 239) is dashed, about half of them drawn
    /// (emulation: 133 of 240). As |x − y| its derivative was 0 there, so none were (a gap along the dashes);
    /// main drew all 240 (the solid line x = y).
    @Test func excludedDiagonalIsDashedThroughThePixelCentres() throws {
        let pixels = try render(try request("x != y"))
        let onDiagonal = (0..<Self.size).filter { row in pixels[row * Self.size + (Self.size - 1 - row)] > 128 }.count
        #expect(onDiagonal >= Self.size * 35 / 100 && onDiagonal <= Self.size * 75 / 100, "\(onDiagonal) of \(Self.size)")
    }
}
