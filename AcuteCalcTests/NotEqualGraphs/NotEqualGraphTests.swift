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

    /// "Prilagodi pogled" frames a system with ≠ by its curves, restricted to its inequalities, as main did (a guard:
    /// the region min(…) > 0 changes sign only along y = 0, which is unbounded, or at grid points on a circle, so
    /// the view stayed at ±20, or zoomed onto the origin for (x − 1)² + y² ≠ 1, x² + y² ≠ 4). In a port of
    /// ImplicitBounds and fitToContent the view is x ∈ [−3.10, 3.10] (r = 2) and [−4.65, 4.65] (r = 3), and for
    /// y ≥ 0 or y > 0 the upper semicircle, y ∈ [−1.85, 4.35] (main: the same, [−1.23, 4.97] for y > 0).
    @Test func fitFramesTheCurvesOfANotEqualSystem() throws {
        let systems = [("x^2+y^2 != 4, y >= 0", 2.0), ("x^2+y^2 != 4, y > 0", 2.0), ("x^2+y^2 != 4, x^2+y^2 != 1", 2.0),
                       ("x^2+y^2 != 9, x != 0", 3.0), ("(x-1)^2+y^2 != 1, x^2+y^2 != 4", 2.0)]
        for (text, radius) in systems {
            let canvas = GraphCanvasModel()
            canvas.viewport.size = CGSize(width: 400, height: 400)
            canvas.viewport.scale = SIMD2(10, 10)
            canvas.viewport.center = .zero
            canvas.items = items(try system(text))
            canvas.fitToContent()
            let x = canvas.viewport.visibleX, y = canvas.viewport.visibleY
            #expect(x.lowerBound < -radius && x.upperBound > radius, "\(text): \(x)")
            #expect(x.upperBound - x.lowerBound < 10, "\(text): \(x)")
            if text.contains("y >") {
                #expect(y.lowerBound > -2.5 && y.upperBound > radius, "\(text): \(y)")
            }
        }
    }

    /// "Prilagodi pogled" frames a function restricted only by x ≠ c as the function alone, by its y range (as main
    /// did). Drawn as a curve restricted by the gap of x ≠ c it framed nothing: its curves y − f(x) = 0 and x − c = 0
    /// are unbounded for ImplicitBounds, so the view stayed at y ∈ [−20; 20] (from ±20 main and now frame y = x², x ≠ 1
    /// by y ∈ [0.36; 376.36], the range of the samples without their extreme 3 %).
    @Test func fitFramesAFunctionRestrictedByNotEqualAsTheFunction() throws {
        for (text, function) in [("y=x^2, x!=1", "y=x^2"), ("y=sin(x), x!=0", "y=sin(x)"), ("y=1/x, x!=1", "y=1/x")] {
            let restricted = try system(text)
            let alone = try #require(CalculationEngine.graphRequest(for: try Parser.parse(function)))
            var frames: [ClosedRange<Double>] = []
            for request in [restricted, alone] {
                let canvas = GraphCanvasModel()
                canvas.viewport.size = CGSize(width: 400, height: 400)
                canvas.viewport.scale = SIMD2(10, 10)
                canvas.viewport.center = .zero
                canvas.items = items(request)
                canvas.fitToContent()
                frames.append(canvas.viewport.visibleY)
            }
            #expect(frames[0] == frames[1], "\(text): \(frames)")
            #expect(frames[0] != (-20.0)...20.0, "\(text): \(frames[0])")
        }
    }

    /// VoiceOver reads x ≠ 2 as typed (a guard: main read it so; the region read "|x − 2| > 0"), and the band
    /// 0 ≤ x ≤ 3, x ≠ 1 as its closed part and x ≠ 1: its solid edges are part of the region, not a second
    /// relation, and the region drawn strict does not read "> 0" with the tolerance (a guard: main read the
    /// condition "piecewise(x − 1; min(x − 0; 3 − x) ≥ 0) ≠ 0", the branch "min(min(x − 0; 3 − x); max(…) −
    /// 0,000001·…) > 0").
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
        let band = GraphAccessibility.summary(items: items(try system("0<=x<=3, x!=1")), pointCount: 0, style: style)
        #expect(band.contains("≥") && band.contains("≠") && !band.contains(">") && !band.contains("0,000001"), "\(band)")
    }

    /// In the calculator, 0 ≤ x ≤ 3, x ≠ 1 is drawn in one colour, as in the graph list: kind i got palette colour
    /// i, so the band's solid edges (the second kind) were red over its blue fill and dashes (a guard: main drew
    /// one kind, the line x = 1).
    @Test func calculatorDrawsARegionInOneColour() throws {
        let model = CalculatorModel()
        let symbols: [MathSymbol] = [.digit(0), .lessOrEqual, .variable("x"), .lessOrEqual, .digit(3), .comma,
                                     .variable("x"), .notEqual, .digit(1)]
        model.editor = MathEditor(root: MathRow(symbols.map { MathNode.symbol($0) }))
        model.enter()
        let plotted = model.graph.items
        #expect(!plotted.isEmpty)
        let colours = plotted.map { $0.color }
        let oneColour = colours.allSatisfy { $0 == GraphPalette.color(0) }
        #expect(oneColour, "\(colours)")
    }

    /// A system with ≠ reads its relations, without the tolerance of the gaps (a guard: main read them one by one,
    /// x ≠ 0, y ≠ 0 as "x≠0; y≠0", y = x², y ≠ 1 as "y = x^(2); y≠1"; the region and the restricted curve read
    /// "min(max(x − 0; 0 − x) − 0,000001·max(1; |x|; |0|); …) > 0" and "piecewise(y − x^(2); max(…) − …) = 0").
    @Test func notEqualSystemReadsAsTyped() throws {
        let style = MathStyle(decimalSeparator: ",")
        for text in ["x!=0, y!=0", "y=x^2, y!=1", "x^2+y^2=4, y!=0", "x^2+y^2=4, y>=0, x!=0"] {
            let summary = GraphAccessibility.summary(items: items(try system(text)), pointCount: 0, style: style)
            #expect(summary.contains("≠") && !summary.contains("max") && !summary.contains("0,000001"), "\(text): \(summary)")
            if !text.contains(">") {
                #expect(!summary.contains("piecewise"), "\(text): \(summary)")
            }
        }
        let relations = try #require(Parser.parseSystem(tokens: try Lexer().tokenize("x!=0, y!=0")))
        let typed = relations.map { MathAccessibility.label(MathRowConverter.row(for: $0), style: style) }.joined(separator: "; ")
        let axes = GraphAccessibility.summary(items: items(try system("x!=0, y!=0")), pointCount: 0, style: style)
        #expect(axes == typed)
    }

    /// x > 0, y ≥ 0, x ≠ 1 reads each part of the region with its typed relation, x − 0 > 0 (its edge x = 0 is
    /// dashed), y − 0 ≥ 0 and x ≠ 1. Every part read ≥ 0 when the region had solid edges: "min(x − 0; y − 0) ≥ 0;
    /// x ≠ 1" (main: "piecewise(x − 1; min(x − 0; y − 0) ≥ 0) ≠ 0").
    @Test func mixedRegionReadsItsPartsAsTyped() throws {
        let style = MathStyle(decimalSeparator: ",")
        let relations = try #require(Parser.parseSystem(tokens: try Lexer().tokenize("x>0, y>=0, x!=1")))
        let typed: [Expr] = relations.compactMap { (relation: Expr) -> Expr? in
            guard case .relation(let lhs, let op, let rhs) = relation else { return nil }
            return op == .notEqual ? relation : .relation(lhs - rhs, op, .zero)
        }
        let expected = typed.map { MathAccessibility.label(MathRowConverter.row(for: $0), style: style) }.joined(separator: "; ")
        let summary = GraphAccessibility.summary(items: items(try system("x>0, y>=0, x!=1")), pointCount: 0, style: style)
        #expect(summary == expected)
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

    /// min of an undefined value is undefined in the three GPU interpreters, in either order (ln x at x = −1 and
    /// −2, 1/z at z = 0), as on the CPU. bc_eval_dual kept the second operand when the first was NaN, Metal's min
    /// (bc_eval_real, bc_eval_complex) the defined one, so min(ln x; y) was y where ln x is undefined. Where both
    /// are defined the value is unchanged (at (1, 0.5): 0, exact in float).
    @Test func minOfAnUndefinedOperandIsUndefined() throws {
        let gpu = try ShaderPrecisionGPU()
        let ln = Expr.function(.ln, [.x])
        let points: [SIMD2<Float>] = [SIMD2(-1, 1), SIMD2(-2, 0.5), SIMD2(1, 0.5)]
        let z = Expr.variable("z")
        for arguments in [[ln, Expr.y], [Expr.y, ln]] {
            let program = try BytecodeCompiler(slots: ["x": .x, "y": .y]).compile(.function(.min, arguments))
            for interpreter in [ShaderPrecisionGPU.Interpreter.real, .dual] {
                let values = try gpu.evaluate(program, interpreter, at: points).values
                #expect(values[0].x.isNaN, "\(interpreter) min at (−1, 1): \(values[0].x)")
                #expect(values[1].x.isNaN, "\(interpreter) min at (−2, 0.5): \(values[1].x)")
                #expect(values[2].x == 0, "\(interpreter) min at (1, 0.5): \(values[2].x)")
            }
        }
        for arguments in [[Expr.quotient(.one, z), Expr.int(2)], [Expr.int(2), Expr.quotient(.one, z)]] {
            let program = try BytecodeCompiler(slots: ["z": .z], complexMode: true).compile(.function(.min, arguments))
            let value = try gpu.evaluate(program, .complex, at: [SIMD2(0, 0)]).values[0]
            #expect(value.x.isNaN, "complex min at z = 0: \(value.x)")
        }
    }

    /// max stays main's in the three GPU interpreters (a guard: an undefined max made a union of regions, the max
    /// of their gaps, undefined wherever one region is). bc_eval_dual keeps the second operand when the first is
    /// NaN: max(ln x; y) is y at x = −1 and −2, max(y; ln x) NaN there. Metal's max (bc_eval_real,
    /// bc_eval_complex) returns the defined operand in either order: y, and 2 for max(1/z; 2) at z = 0. Where both
    /// are defined: 0.5 at (1, 0.5), exact in float.
    @Test func maxOfAnUndefinedOperandIsAsOnMain() throws {
        let gpu = try ShaderPrecisionGPU()
        let ln = Expr.function(.ln, [.x])
        let points: [SIMD2<Float>] = [SIMD2(-1, 1), SIMD2(-2, 0.5), SIMD2(1, 0.5)]
        let z = Expr.variable("z")
        for (index, arguments) in [[ln, Expr.y], [Expr.y, ln]].enumerated() {
            let program = try BytecodeCompiler(slots: ["x": .x, "y": .y]).compile(.function(.max, arguments))
            let real = try gpu.evaluate(program, .real, at: points).values.map { $0.x }
            #expect(real[0] == 1 && real[1] == 0.5 && real[2] == 0.5, "real max(\(arguments)): \(real)")
            let dual = try gpu.evaluate(program, .dual, at: points).values.map { $0.x }
            if index == 0 {
                #expect(dual[0] == 1 && dual[1] == 0.5, "dual max(ln x; y): \(dual)")
            } else {
                #expect(dual[0].isNaN && dual[1].isNaN, "dual max(y; ln x): \(dual)")
            }
            #expect(dual[2] == 0.5, "dual max(\(arguments)) at (1, 0.5): \(dual[2])")
        }
        for arguments in [[Expr.quotient(.one, z), Expr.int(2)], [Expr.int(2), Expr.quotient(.one, z)]] {
            let program = try BytecodeCompiler(slots: ["z": .z], complexMode: true).compile(.function(.max, arguments))
            let value = try gpu.evaluate(program, .complex, at: [SIMD2(0, 0)]).values[0]
            #expect(value.x == 2, "complex max(\(arguments)) at z = 0: \(value.x)")
        }
    }

    /// The union of |y| ≤ √(x − 1) and |y| ≤ √(x − 1/2), drawn as the max of their gaps ≥ 0 (as a union of
    /// regions D₁ ∪ D₂ ∪ … is), is filled at (0.75, 0), which lies in the second region only; the first is
    /// undefined there. A guard: with an undefined max nothing left of x = 1 was drawn (emulation: 892 pixels
    /// on main and now, 0 with it).
    @Test func unionOfRegionsIsFilledWhereOneIsUndefined() throws {
        let gaps = [Expr.int(1), Expr.quotient(.one, .int(2))].map { shift in
            Expr.sum([.function(.sqrt, [.sum([.x, .negation(shift)])]), .negation(.function(.abs, [.y]))])
        }
        let pixels = try render(GraphRequest(kinds: [.implicit(lhs: .function(.max, gaps), relation: .greaterOrEqual, rhs: .zero)]))
        let inside = pixel(pixels, 0.75, 0)
        #expect(inside > 30 && inside < 90, "\(inside)")
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

    /// 0 ≤ x ≤ 2, x ≠ 2.1: the included edge x = 2 is solid on both sides, although the excluded line runs 3.6 pixels
    /// beside it. Its solid kind divided by |x − 2.1|, whose derivative skewed the distance estimate and the Newton
    /// step, so the inner half of the stroke was only the region's dashes (emulation: 140 of 240 pixels in the
    /// columns at x = 1.90, 1.93 and 1.96, all 240 now); main drew nothing (the line x = 2.1 restricted to the band).
    @Test func includedEdgeBesideAnExcludedLineIsSolid() throws {
        let pixels = try render(try request("0<=x<=2, x!=2.1"))
        for x in [1.9, 1.93, 1.96] {
            #expect(drawn(pixels, column: Self.column(x)) == Self.size, "x = \(x)")
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
