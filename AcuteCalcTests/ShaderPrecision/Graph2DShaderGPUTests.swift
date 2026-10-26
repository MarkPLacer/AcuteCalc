import AcuteCore
import Foundation
import Metal
import Testing
@testable import AcuteCalc

/// The 2D graph shaders (implicit_fragment, line_vertex/line_fragment in Graph2D.metal) rendered by the
/// app's own Graph2DEncoder: 240 × 240 px, 12 pt per unit at 3 px per point (36 px per unit), lines 3 pt
/// wide (half width 4.5 px), white on black, view centred at the origin. A pixel counts as drawn when its
/// coverage is above one half (> 128 of 255). The expected counts come from a float32 emulation of
/// the shaders (described in the commit messages).
@MainActor
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "needs a Metal device"))
struct Graph2DShaderGPUTests {
    private static let size = 240
    private static let pixelsPerUnit = 36.0

    /// Pixel column whose centre is the first one right of graph x.
    private static func column(_ x: Double) -> Int { Int((x * pixelsPerUnit + Double(size) / 2).rounded(.down)) }

    private func render(_ scene: GraphScene) throws -> [UInt8] {
        try GraphRenderHarness.render(scene, pointsPerUnit: 12, contentScale: 3, width: Self.size, height: Self.size)
    }

    /// F(x, y) relation 0 as GraphCanvasModel builds it (program of lhs − rhs), boundary line only: the
    /// fill is transparent, so the pixels show the line coverage.
    private func implicit(_ f: Expr, mode: Int32) throws -> [UInt8] {
        let program = try BytecodeCompiler(slots: ["x": .x, "y": .y]).compile(.sum([f, .negation(.zero)]))
        var scene = GraphScene()
        scene.implicits = [GraphScene.Implicit(id: "f", program: program, parameters: [],
                                               color: .rgba(1, 1, 1), fillColor: .rgba(0, 0, 0, 0), mode: mode)]
        return try render(scene)
    }

    private func drawn(_ pixels: [UInt8], columns: ClosedRange<Int>) -> Int {
        var count = 0
        for row in 0..<Self.size {
            for px in columns where pixels[row * Self.size + px] > 128 { count += 1 }
        }
        return count
    }

    /// Samples on the circle of radius 2 around the origin (720 pixels).
    private func onCircle(_ pixels: [UInt8]) -> [Bool] {
        (0..<720).map { k in
            let t = Double(k) / 720 * 2 * Double.pi
            let px = Int(Double(Self.size) / 2 + 2 * Self.pixelsPerUnit * cos(t))
            let py = Int(Double(Self.size) / 2 - 2 * Self.pixelsPerUnit * sin(t))
            return pixels[py * Self.size + px] > 128
        }
    }

    // MARK: SHD-01 Newton check

    /// (x − 1)/(x + 2) ≥ 0 holds for x < −2 or x ≥ 1; x = −2 is a pole, not part of the boundary. One
    /// Newton step from a pixel near a simple pole leaves |F(q)|/|F| ≈ 0.5 (0.4988 just right of x = −2),
    /// which the old check (≤ 0.5) accepted: a solid line along x = −2 (emulation: 1200 px in the 7
    /// columns right of it; 0 after the fix). The boundary x = 1 stays (emulation: 2160 px).
    @Test func simplePoleIsNotDrawnAsABoundary() throws {
        let pixels = try implicit(Expr.quotient(Expr.x - .int(1), Expr.x + .int(2)), mode: 4)
        let pole = Self.column(-2)
        #expect(drawn(pixels, columns: pole...(pole + 6)) == 0)
        let zero = Self.column(1)
        #expect(drawn(pixels, columns: (zero - 5)...(zero + 5)) >= Self.size * 8)
    }

    /// 1/x² − 1 ≥ 0: x = 0 is a double pole (ratio (1 + 1/2)⁻² = 0.444, accepted before: emulation 3360 px
    /// in the 14 columns around x = 0; 0 after); the zero x = 1 stays drawn (emulation: 2160 px).
    @Test func doublePoleIsNotDrawnAsABoundary() throws {
        let pixels = try implicit(Expr.quotient(.one, .power(.x, .int(2))) - .one, mode: 4)
        let pole = Self.column(0)
        #expect(drawn(pixels, columns: (pole - 7)...(pole + 6)) == 0)
        let zero = Self.column(1)
        #expect(drawn(pixels, columns: (zero - 5)...(zero + 5)) >= Self.size * 8)
    }

    /// Zeros are still accepted: x² + y² = 4 is drawn all the way round.
    @Test func circleIsDrawnAllRound() throws {
        let pixels = try implicit(Expr.power(.x, .int(2)) + .power(.y, .int(2)) - .int(4), mode: 0)
        let visible = onCircle(pixels)
        #expect(!visible.contains(false))
    }

    // MARK: SHD-05 dashed boundary of strict inequalities

    /// x² + y² < 4 must have a dashed boundary. The old dash coordinate dot(centered, tangent) is 0 all
    /// along a circle around the view centre, so rounding noise decided each pixel (emulation: 185 runs
    /// along the circle, 97 of them 1–2 samples long). Measured along the dominant tangent axis it gives
    /// dashes (emulation: 95 runs, 1 short; 57 % visible).
    @Test func strictCircleBoundaryIsDashed() throws {
        let pixels = try implicit(Expr.power(.x, .int(2)) + .power(.y, .int(2)) - .int(4), mode: 1)
        let visible = onCircle(pixels)
        var runs: [Int] = []
        var run = 1
        for k in 1..<visible.count {
            if visible[k] == visible[k - 1] { run += 1 } else { runs.append(run); run = 1 }
        }
        runs.append(run)
        let short = runs.filter { $0 <= 2 }.count
        #expect(runs.count >= 10)
        #expect(short * 5 < runs.count, "\(short) of \(runs.count) runs are 1–2 samples long")
        let fraction = Double(visible.filter { $0 }.count) / Double(visible.count)
        #expect(fraction > 0.35 && fraction < 0.75)
    }

    // MARK: SHD-06 dashed sampled curves

    /// y = x/2 + 0.3 sampled every point (1/12 unit), as CurveSampler samples f′, F(x), inverses and
    /// Taylor polynomials, from x = −4 to 4.
    private func sampledLine(dashed: Bool) throws -> [Bool] {
        let points = (0...96).map { i -> SIMD2<Double> in
            let x = -4 + Double(i) / 12
            return SIMD2(x, x / 2 + 0.3)
        }
        var scene = GraphScene()
        scene.curves = [GraphScene.Curve(id: "line", points: points, color: .rgba(1, 1, 1), dashed: dashed)]
        let pixels = try render(scene)
        // The pixel of each column whose centre is within half a pixel (vertically) of the line.
        return (0..<Self.size).map { px in
            let cx = Double(px) + 0.5 - Double(Self.size) / 2
            let cy = 0.5 * cx + 0.3 * Self.pixelsPerUnit
            let row = Int((Double(Self.size) / 2 - cy).rounded(.down))
            return pixels[row * Self.size + px] > 128
        }
    }

    /// Its segments are 3.4 px long, shorter than the visible 60 % (25.2 px) of the 14 pt dash period, and
    /// every segment restarted the pattern, so the dashed curve was solid. With the arc length carried
    /// across segments the curve has gaps (emulation: 70 of 240 columns hidden in 7 gaps of 10 px;
    /// the round caps of the neighbouring segments overlap 3–4 px of each 16.8 px gap).
    @Test func dashedSampledCurveHasGaps() throws {
        let visible = try sampledLine(dashed: true)
        let hidden = visible.filter { !$0 }.count
        #expect(hidden >= Self.size * 3 / 20, "\(hidden) hidden columns")
        #expect(hidden <= Self.size * 3 / 5, "\(hidden) hidden columns")
        var gaps = 0
        for k in 1..<visible.count where !visible[k] && visible[k - 1] { gaps += 1 }
        #expect(gaps >= 4)
    }

    /// The new point layout (x, y, dash phase, 0) keeps solid curves and markers as they were.
    @Test func solidCurvesAndMarkersAreUnchanged() throws {
        let visible = try sampledLine(dashed: false)
        #expect(!visible.contains(false))
        var scene = GraphScene()
        scene.markers = [GraphScene.Marker(id: "p", position: SIMD2(1, 1), color: .rgba(1, 1, 1))]
        let pixels = try render(scene)
        // Centre of the marker at (1, 1): 36 px right of and 36 px above the view centre.
        let px = Self.size / 2 + 36, py = Self.size / 2 - 36
        #expect(pixels[py * Self.size + px] > 200)
        #expect(pixels[py * Self.size + px - 30] < 50)
    }
}
