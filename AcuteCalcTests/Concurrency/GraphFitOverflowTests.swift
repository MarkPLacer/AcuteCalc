import AcuteCore
import Foundation
import Testing
@testable import AcuteCalc

/// Health audit concurrency:2: fitting the view to a curve at about ±10³⁰⁸ ("Prilagodi pogled", or the
/// calculator's live preview of (t; 10^308)) put its centre at ±∞, because (a + b) / 2 overflowed, and the
/// sampling task then built the range NaN...NaN, which traps in release builds too. The middle of a frame is
/// a / 2 + b / 2 now, and a window without a finite size is not sampled.
@MainActor
@Suite struct GraphFitOverflowTests {
    private static let t = Expr.variable("t")
    /// The value of 10^308.
    private static let huge = Expr.decimal(1e308)

    /// A 400 × 400 canvas with the parametric curve (x(t); y(t)), t ∈ [−10; 10], as the calculator draws
    /// (t; 10^308) (CalculationEngine.parametricCurve).
    private func makeCanvas(_ x: Expr, _ y: Expr, lockAspect: Bool) -> GraphCanvasModel {
        let canvas = GraphCanvasModel()
        canvas.viewport.size = CGSize(width: 400, height: 400)
        canvas.lockAspect = lockAspect
        canvas.items = [PlotItem(id: "curve", kind: .parametric(x: x, y: y, from: -10, to: 10), color: GraphPalette.color(0))]
        return canvas
    }

    /// The centre and the bounds of the visible ranges are finite numbers.
    private func isFinite(_ viewport: GraphViewport) -> Bool {
        let values = [viewport.center.x, viewport.center.y, viewport.visibleX.lowerBound, viewport.visibleX.upperBound,
                      viewport.visibleY.lowerBound, viewport.visibleY.upperBound]
        return values.allSatisfy(\.isFinite)
    }

    /// Waits until the curves of the current view are sampled (unfixed, the sampling task trapped).
    private func sampled(_ canvas: GraphCanvasModel) async throws -> Bool {
        try await ConcurrencyTesting.eventually { !canvas.isComputing }
    }

    /// (t; ±10^308) and (±10^308; t): a horizontal or vertical line at ±10³⁰⁸ (the ±1 put around a line is lost
    /// at that size), framed with one scale on both axes (GraphViewport.fit) or a scale of its own on each axis
    /// (fitToContent).
    @Test(arguments: [true, false])
    func fitToALineNearTheLargestDouble(lockAspect: Bool) async throws {
        let lines: [(x: Expr, y: Expr, at: SIMD2<Double>)] = [
            (Self.t, Self.huge, SIMD2(0, 1e308)), (Self.t, -Self.huge, SIMD2(0, -1e308)),
            (Self.huge, Self.t, SIMD2(1e308, 0)), (-Self.huge, Self.t, SIMD2(-1e308, 0)),
        ]
        for line in lines {
            let canvas = makeCanvas(line.x, line.y, lockAspect: lockAspect)
            canvas.fitToContent()
            #expect(isFinite(canvas.viewport), "\(line.at): \(canvas.viewport)")
            // The view is on the line.
            #expect(canvas.viewport.visibleX.contains(line.at.x) && canvas.viewport.visibleY.contains(line.at.y),
                    "\(line.at): \(canvas.viewport)")
            let done = try await sampled(canvas)
            #expect(done)
        }
    }

    /// (t; 10^307·t) reaches from −10³⁰⁸ to 10³⁰⁸: the difference of its bounds is ∞, their sum 0. The view stays
    /// centred on 0 (a guard: a + (b − a) / 2 would put the centre at ∞).
    @Test(arguments: [true, false])
    func fitToACurveAcrossZeroNearTheLargestDouble(lockAspect: Bool) async throws {
        let canvas = makeCanvas(Self.t, Expr.decimal(1e307) * Self.t, lockAspect: lockAspect)
        canvas.fitToContent()
        #expect(isFinite(canvas.viewport), "\(canvas.viewport)")
        #expect(canvas.viewport.center == .zero)
        let done = try await sampled(canvas)
        #expect(done)
    }

    /// A logarithmic y axis panned up to 10^307,9 … 10^308,2 and then made linear: the view is centred on the
    /// values it showed, 7,9·10³⁰⁷ … 1,6·10³⁰⁸, whose sum overflowed to ∞ (axesDidChange).
    @Test func linearAxisAfterTheHighestDecades() async throws {
        let canvas = GraphCanvasModel()
        canvas.viewport.size = CGSize(width: 400, height: 400)
        canvas.axes = AxisScales(x: .linear, y: .logarithmic)
        canvas.viewport.center.y = 308.05
        canvas.viewport.scale.y = 400 / 0.3
        let shown = AxisScale.logarithmic.valueRange(canvas.viewport.visibleY)
        try #require(shown.upperBound.isFinite && shown.lowerBound > 7e307)
        canvas.axes = .linear
        #expect(isFinite(canvas.viewport), "\(canvas.viewport)")
        #expect(shown.contains(canvas.viewport.center.y), "\(canvas.viewport.center.y)")
        let done = try await sampled(canvas)
        #expect(done)
    }

    /// A window without a finite size is not sampled (no fit gives one any more): from a centre at ∞ the
    /// sampling task built NaN...NaN, which traps.
    @Test func aWindowAtInfinityIsNotSampled() async throws {
        let canvas = GraphCanvasModel()
        canvas.viewport.size = CGSize(width: 400, height: 400)
        canvas.viewport.center = SIMD2(0, .infinity)
        canvas.items = [PlotItem(id: "curve", kind: .parametric(x: Self.t, y: Self.t, from: -10, to: 10), color: GraphPalette.color(0))]
        let done = try await sampled(canvas)
        #expect(done)
        #expect(canvas.scene.curves.isEmpty)
    }
}
