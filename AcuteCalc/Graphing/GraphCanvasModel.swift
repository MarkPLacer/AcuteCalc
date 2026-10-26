import AcuteCore
import Foundation
import Observation
import QuartzCore

/// A function or relation drawn on a 2D graph.
nonisolated struct PlotItem: Identifiable, Equatable, Sendable {
    var id: String
    var kind: GraphKind
    var color: RGBA
    var visible = true
    var width: Float = 3
    var dashed = false
    /// Shade ∫ from lower to upper (between this curve and `shadeLower`, or the x axis).
    var shade: ClosedRange<Double>?
    var shadeLower: Expr?
    /// Participates in automatic special points (zeros, extrema, intersections).
    var analyzed = true
    /// Drawn in the theme's axis colour instead of `color` (points that belong to no curve),
    /// so a change of appearance recolours it.
    var axisColored = false
}

/// A labelled point picked from the special points or by tracing.
nonisolated struct GraphPointInfo: Equatable, Sendable {
    var point: SpecialPoint
    var itemID: String?
    var color: RGBA
    /// Slope of the traced curve at the point (for the tangent and the normal).
    var slope: Double?
}

/// An asymptote of a function, drawn as a dashed line with the special points.
nonisolated struct GraphAsymptote: Equatable, Sendable {
    enum Line: Equatable, Sendable {
        case vertical(Double)
        case slanted(slope: Double, intercept: Double)
    }

    var line: Line
    var color: RGBA
}

/// State of an interactive 2D graph: definitions, viewport, sampled geometry and analysis.
@Observable
final class GraphCanvasModel: GraphViewportSource {
    var viewport = GraphViewport()
    /// Also colours the intersection markers (see `markerColor`).
    var theme = GraphTheme.dark { didSet { if theme != oldValue { rebuildScene() } } }
    var items: [PlotItem] = [] { didSet { if items != oldValue { invalidate(analysis: true) } } }
    var parameters: [String: Double] = [:] { didSet { if parameters != oldValue { invalidate(analysis: true) } } }
    var angleUnit = AngleUnit.radians
    /// One scale on both axes, so circles stay round (pinch and "fit" keep it).
    var lockAspect = true {
        didSet {
            guard lockAspect, !oldValue else { return }
            viewport.equalizeAxes()
            viewportDidChange(final: true)
        }
    }
    var showSpecialPoints = true { didSet { rebuildScene() } }
    var highlightIntersections = true
    /// Allows labelling the x axis in π for trigonometric graphs (a setting).
    var piAxisEnabled = true { didSet { if piAxisEnabled != oldValue { rebuildScene() } } }

    /// The x axis in multiples of π: a trigonometric function of x is drawn.
    var piAxis: Bool {
        piAxisEnabled && items.contains { item in
            guard item.visible, case .explicit(let e) = item.kind else { return false }
            return Self.isTrigonometric(e)
        }
    }

    nonisolated static func isTrigonometric(_ e: Expr) -> Bool {
        e.contains { node in
            guard case .function(let f, let args) = node, args.contains(where: { $0.dependsOn("x") }) else { return false }
            return f == .sin || f == .cos || f == .tan || f == .cot || f == .sec || f == .csc
        }
    }

    private(set) var scene = GraphScene()
    private(set) var specialPoints: [GraphPointInfo] = []
    var selectedPoint: GraphPointInfo?
    var tracePoint: GraphPointInfo?
    /// Tangent at the traced point (shown as a dashed line).
    var showTangent = false { didSet { rebuildScene() } }
    private(set) var isComputing = false

    @ObservationIgnored var requestRedraw: (() -> Void)?
    @ObservationIgnored var setContinuousRendering: ((Bool) -> Void)?

    @ObservationIgnored private var sampled: [String: SampledCurve] = [:]
    @ObservationIgnored private var fills: [String: [GraphScene.Fill]] = [:]
    @ObservationIgnored private var samplingTask: Task<Void, Never>?
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var sampledViewport: GraphViewport?
    @ObservationIgnored private var functions: [String: (Double) -> Double] = [:]
    @ObservationIgnored private var branchCache: [String: [Expr]] = [:]
    @ObservationIgnored private var asymptotes: [GraphAsymptote] = []

    // Inertial panning
    @ObservationIgnored private var velocity = SIMD2<Double>(0, 0)
    @ObservationIgnored private var lastStep: CFTimeInterval = 0

    // MARK: Definitions

    func setItems(_ newItems: [PlotItem], fitIfNeeded: Bool = false) {
        items = newItems
        if fitIfNeeded { fitToContent() }
    }

    private func invalidate(analysis: Bool) {
        sampledViewport = nil
        functions = [:]
        branchCache = [:]
        refresh(analysis: analysis)
    }

    /// Re-sample when the view left the sampled window or the zoom changed noticeably.
    func viewportDidChange(final: Bool) {
        requestRedraw?()
        guard let old = sampledViewport else { refresh(analysis: final); return }
        let zoomRatio = max(viewport.scale.x / old.scale.x, old.scale.x / viewport.scale.x,
                            viewport.scale.y / old.scale.y, old.scale.y / viewport.scale.y)
        let oldX = old.visibleX
        let width = oldX.upperBound - oldX.lowerBound
        let covered = (oldX.lowerBound - width)...(oldX.upperBound + width)
        let visible = viewport.visibleX
        let outside = visible.lowerBound < covered.lowerBound || visible.upperBound > covered.upperBound
        let oldY = old.visibleY
        let heightOld = oldY.upperBound - oldY.lowerBound
        let yOutside = abs(viewport.center.y - old.center.y) > heightOld
        if zoomRatio > 1.6 || outside || yOutside || (final && zoomRatio > 1.05) {
            refresh(analysis: final)
        } else if final {
            scheduleAnalysis()
        }
    }

    // MARK: Compilation

    private var parameterNames: [String] { parameters.keys.sorted() }

    func makeFunction(_ expr: Expr, variable: String = "x") -> (Double) -> Double {
        var context = EvaluationContext(angleUnit: angleUnit, variables: parameters)
        context.randomSeed = 1
        return FunctionAnalyzer.makeFunction(expr, variable: variable, context: context)
    }

    private func implicitProgram(_ lhs: Expr, _ rhs: Expr) -> Program? {
        var slots: [String: VariableSlot] = ["x": .x, "y": .y]
        for (i, name) in parameterNames.enumerated() { slots[name] = .parameter(i) }
        let difference = Expr.sum([lhs, .negation(rhs)])
        return try? BytecodeCompiler(slots: slots, angleUnit: angleUnit).compile(difference)
    }

    // MARK: Sampling

    private func refresh(analysis: Bool) {
        samplingTask?.cancel()
        let snapshot = viewport
        let currentItems = items.filter(\.visible)
        let params = parameters
        let unit = angleUnit
        sampledViewport = snapshot
        isComputing = true
        samplingTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                GraphCanvasModel.sample(items: currentItems, viewport: snapshot, parameters: params, angleUnit: unit)
            }.value
            guard let self, !Task.isCancelled else { return }
            self.sampled = result.curves
            self.fills = result.fills
            self.isComputing = false
            self.rebuildScene()
            if analysis { self.scheduleAnalysis() }
        }
    }

    nonisolated private struct SampleResult: Sendable {
        var curves: [String: SampledCurve]
        var fills: [String: [GraphScene.Fill]]
    }

    nonisolated private static func sample(items: [PlotItem], viewport: GraphViewport, parameters: [String: Double], angleUnit: AngleUnit) -> SampleResult {
        var curves: [String: SampledCurve] = [:]
        var fills: [String: [GraphScene.Fill]] = [:]
        let visibleX = viewport.visibleX
        let visibleY = viewport.visibleY
        let width = visibleX.upperBound - visibleX.lowerBound
        let height = visibleY.upperBound - visibleY.lowerBound
        let domain = (visibleX.lowerBound - width)...(visibleX.upperBound + width)
        let domainY = (visibleY.lowerBound - height)...(visibleY.upperBound + height)
        // Sample at roughly retina resolution of the visible window.
        let sampler = CurveSampler(unitsPerPixel: viewport.unitsPerPoint * 0.5, visibleY: visibleY)
        let samplerY = CurveSampler(unitsPerPixel: SIMD2(viewport.unitsPerPoint.y, viewport.unitsPerPoint.x) * 0.5, visibleY: visibleX)
        let context = EvaluationContext(angleUnit: angleUnit, variables: parameters)
        for item in items {
            switch item.kind {
            case .explicit(let expr):
                let f = FunctionAnalyzer.makeFunction(expr, variable: "x", context: context)
                curves[item.id] = sampler.sampleExplicit(f, over: domain)
                if let shade = item.shade {
                    let lower = item.shadeLower.map { FunctionAnalyzer.makeFunction($0, variable: "x", context: context) }
                    fills[item.id] = shadeBands(f: f, g: lower, range: shade, visible: domain, color: item.color)
                }
            case .explicitInY(let expr):
                let g = FunctionAnalyzer.makeFunction(expr, variable: "y", context: context)
                var curve = samplerY.sampleExplicit(g, over: domainY)
                curve.points = curve.points.map { SIMD2($0.y, $0.x) }
                curves[item.id] = curve
            case .parametric(let x, let y, let from, let to):
                let fx = FunctionAnalyzer.makeFunction(x, variable: "t", context: context)
                let fy = FunctionAnalyzer.makeFunction(y, variable: "t", context: context)
                curves[item.id] = sampler.sampleParametric(fx, fy, over: from...to)
            case .slopeField(let f):
                // About one segment per 34 points, over the window that is kept while panning.
                let columns = 3 * Swift.max(8, Swift.min(30, Int(Double(viewport.size.width) / 34)))
                let rows = 3 * Swift.max(6, Swift.min(30, Int(Double(viewport.size.height) / 34)))
                let points = DifferentialEquation.slopeField(f, x: domain, y: domainY, columns: columns, rows: rows,
                                                             aspect: viewport.scale.y / viewport.scale.x, parameters: parameters)
                curves[item.id] = SampledCurve(points: points, domain: domain, resolution: viewport.unitsPerPoint.x)
            case .odeSolution(let f, let order, let x0, let initial):
                let points = DifferentialEquation.solve(f, order: order, x0: x0, initial: initial, over: domain, parameters: parameters)
                curves[item.id] = SampledCurve(points: points, domain: domain, resolution: viewport.unitsPerPoint.x)
            default:
                continue
            }
        }
        return SampleResult(curves: curves, fills: fills)
    }

    /// Triangle strips for ∫ₐᵇ (f − g): positive parts tinted with the curve colour,
    /// negative parts in a contrasting red, so the signed area is visible.
    nonisolated static func shadeBands(f: (Double) -> Double, g: ((Double) -> Double)?, range: ClosedRange<Double>, visible: ClosedRange<Double>, color: RGBA) -> [GraphScene.Fill] {
        let a = max(range.lowerBound, visible.lowerBound)
        let b = min(range.upperBound, visible.upperBound)
        guard b > a else { return [] }
        let n = 720
        var positive: [SIMD2<Double>] = []
        var negative: [SIMD2<Double>] = []
        positive.reserveCapacity(2 * (n + 1))
        negative.reserveCapacity(2 * (n + 1))
        for i in 0...n {
            let x = a + (b - a) * Double(i) / Double(n)
            let top = f(x)
            let bottom = g?(x) ?? 0
            guard top.isFinite, bottom.isFinite else {
                positive.append(SIMD2(x, bottom)); positive.append(SIMD2(x, bottom))
                negative.append(SIMD2(x, bottom)); negative.append(SIMD2(x, bottom))
                continue
            }
            let above = max(top, bottom)
            let below = min(top, bottom)
            if top >= bottom {
                positive.append(SIMD2(x, bottom)); positive.append(SIMD2(x, above))
                negative.append(SIMD2(x, bottom)); negative.append(SIMD2(x, bottom))
            } else {
                negative.append(SIMD2(x, below)); negative.append(SIMD2(x, bottom))
                positive.append(SIMD2(x, bottom)); positive.append(SIMD2(x, bottom))
            }
        }
        return [
            GraphScene.Fill(id: "pos", strip: positive, color: color.withAlpha(0.32)),
            GraphScene.Fill(id: "neg", strip: negative, color: RGBA(1.0, 0.33, 0.33, 0.30)),
        ]
    }

    // MARK: Analysis

    private func scheduleAnalysis() {
        analysisTask?.cancel()
        guard showSpecialPoints || highlightIntersections else {
            specialPoints = []
            asymptotes = []
            rebuildScene()
            return
        }
        let snapshot = viewport
        let currentItems = items.filter { $0.visible && $0.analyzed }
        let params = parameters
        let unit = angleUnit
        let wantSpecial = showSpecialPoints
        let wantIntersections = highlightIntersections
        analysisTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .utility) {
                GraphCanvasModel.analyze(items: currentItems, viewport: snapshot, parameters: params, angleUnit: unit,
                                         special: wantSpecial, intersections: wantIntersections)
            }.value
            guard let self, !Task.isCancelled else { return }
            self.specialPoints = result.points
            self.asymptotes = result.asymptotes
            self.rebuildScene()
        }
    }

    nonisolated private static func analyze(items: [PlotItem], viewport: GraphViewport, parameters: [String: Double], angleUnit: AngleUnit,
                                            special: Bool, intersections: Bool) -> (points: [GraphPointInfo], asymptotes: [GraphAsymptote]) {
        let context = EvaluationContext(angleUnit: angleUnit, variables: parameters)
        let range = viewport.visibleX
        var result: [GraphPointInfo] = []
        var asymptotes: [GraphAsymptote] = []
        // Curves y = g(x): explicit functions, plus the branches of implicit equations linear or
        // quadratic in y (lines, circles, conics), so their intercepts, vertices and intersections
        // are found too. Branches of the same curve are not intersected with each other.
        var curves: [(item: PlotItem, expr: Expr, isBranch: Bool)] = []
        for item in items {
            switch item.kind {
            case .explicit(let e):
                curves.append((item, e, false))
            case .implicit(let lhs, .equal, let rhs):
                for branch in ImplicitBranches.branches(lhs, rhs) ?? [] { curves.append((item, branch, true)) }
            default:
                break
            }
        }
        if special {
            for curve in curves {
                let analysis = FunctionAnalyzer.analyze(curve.expr, range: range, context: context, includeAsymptotes: true)
                for p in analysis.allPoints where viewport.visibleY.contains(p.y) {
                    result.append(GraphPointInfo(point: p, itemID: curve.item.id, color: curve.item.color))
                }
                // Branches of hyperbolas give their asymptotes too (y = ±(b/a)x).
                asymptotes += Self.asymptotes(of: curve.expr, analysis: analysis, context: context, color: curve.item.color)
                if curve.isBranch { continue }
                // The analysis has searched them already (HoleFinder, same expression, x, range and context).
                for hole in analysis.holes {
                    result.append(GraphPointInfo(point: hole, itemID: curve.item.id, color: curve.item.color))
                }
                // Filled / hollow ends of the pieces of a piecewise function.
                for end in PiecewiseEndpoints.points(curve.expr, context: context) where range.contains(end.x) {
                    result.append(GraphPointInfo(point: end, itemID: curve.item.id, color: curve.item.color))
                }
            }
        }
        if intersections, curves.count >= 2 {
            for i in 0..<curves.count {
                for j in (i + 1)..<curves.count where curves[i].item.id != curves[j].item.id {
                    let points = FunctionAnalyzer.intersections(curves[i].expr, curves[j].expr, range: range, context: context, otherCurve: j)
                    guard !points.isEmpty else { continue }
                    // The angle between the curves (presečni kot) from their slopes.
                    let f = FunctionAnalyzer.makeFunction(curves[i].expr, variable: "x", context: context)
                    let g = FunctionAnalyzer.makeFunction(curves[j].expr, variable: "x", context: context)
                    for var p in points {
                        p.angle = SpecialPoint.intersectionAngle(slope: NumericCalculus.derivative(of: f, at: p.x),
                                                                 slope: NumericCalculus.derivative(of: g, at: p.x))
                        result.append(GraphPointInfo(point: p, itemID: curves[i].item.id, color: RGBA(1, 1, 1, 1)))
                    }
                }
            }
        }
        return (result, asymptotes)
    }

    /// Poles and horizontal or oblique asymptotes, unless the function is that line itself.
    nonisolated private static func asymptotes(of expr: Expr, analysis: FunctionAnalysis, context: EvaluationContext, color: RGBA) -> [GraphAsymptote] {
        let f = FunctionAnalyzer.makeFunction(expr, variable: "x", context: context)
        func isTheCurve(_ k: Double, _ n: Double) -> Bool {
            [-3.7, 1.3, 5.9].allSatisfy { x in
                let v = f(x)
                return v.isFinite && Swift.abs(v - (k * x + n)) < 1e-9 * max(1, Swift.abs(v))
            }
        }
        var lines = analysis.poles.map { GraphAsymptote(line: .vertical($0), color: color) }
        var levels = [analysis.horizontalAsymptoteLeft, analysis.horizontalAsymptoteRight].compactMap { $0 }
        if levels.count == 2, Swift.abs(levels[0] - levels[1]) <= 1e-6 * max(1, Swift.abs(levels[0])) { levels.removeLast() }
        for c in levels where !isTheCurve(0, c) {
            lines.append(GraphAsymptote(line: .slanted(slope: 0, intercept: c), color: color))
        }
        if let oblique = analysis.obliqueAsymptote, !isTheCurve(oblique.slope, oblique.intercept) {
            lines.append(GraphAsymptote(line: .slanted(slope: oblique.slope, intercept: oblique.intercept), color: color))
        }
        return lines
    }

    // MARK: Scene

    func rebuildScene() {
        var scene = GraphScene()
        scene.piAxis = piAxis
        for item in items where item.visible {
            switch item.kind {
            case .explicit, .explicitInY, .parametric, .slopeField, .odeSolution:
                if let curve = sampled[item.id] {
                    scene.curves.append(GraphScene.Curve(id: item.id, points: curve.points, color: item.color, width: item.width, dashed: item.dashed))
                }
                if let bands = fills[item.id] {
                    scene.fills.append(contentsOf: bands.map { GraphScene.Fill(id: item.id + $0.id, strip: $0.strip, color: $0.color) })
                }
            case .implicit(let lhs, let relation, let rhs):
                guard let program = implicitProgram(lhs, rhs) else { continue }
                let mode: Int32 = switch relation {
                case .equal, .notEqual: 0
                case .less: 1
                case .lessOrEqual: 2
                case .greater: 3
                case .greaterOrEqual: 4
                }
                scene.implicits.append(GraphScene.Implicit(
                    id: item.id, program: program,
                    parameters: parameterNames.map { Float(parameters[$0] ?? 0) },
                    color: item.color, fillColor: item.color.withAlpha(0.22), mode: mode, width: item.width))
            case .sequence(let term):
                // Terms a₁, a₂, … in the visible range (at most about 600 points).
                let f = function(for: item.id, expr: term.substituting("n", with: .x))
                let visible = viewport.visibleX
                let first = max(1, ceil(max(visible.lowerBound, -1e6)))
                let last = floor(min(visible.upperBound, 1e6))
                guard last >= first else { continue }
                let step = max(1, Int((last - first) / 600))
                for n in stride(from: Int(first), through: Int(last), by: step) {
                    let value = f(Double(n))
                    guard value.isFinite else { continue }
                    scene.markers.append(GraphScene.Marker(id: "\(item.id)#\(n)", position: SIMD2(Double(n), value), color: item.color, radius: 4.5))
                }
            case .point(let x, let y):
                guard let p = figurePoint(x, y) else { continue }
                let color = item.axisColored ? theme.axis.withAlpha(1) : item.color
                scene.markers.append(GraphScene.Marker(id: item.id, position: p, color: color, radius: 6))
            case .polyline(let coordinates, let closed):
                var corners = figurePoints(coordinates)
                if closed, let first = corners.first { corners.append(first) }
                guard corners.count >= 2 else { continue }
                scene.curves.append(GraphScene.Curve(id: item.id, points: corners, color: item.color, width: item.width))
            case .segment(let x0, let y0, let x1, let y1, let arrow):
                guard let a = figurePoint(x0, y0), let b = figurePoint(x1, y1) else { continue }
                scene.curves.append(GraphScene.Curve(id: item.id, points: [a, b], color: arrow ? item.color : item.color.withAlpha(0.7),
                                                     width: arrow ? item.width : 1.5, dashed: !arrow))
                if arrow, let head = arrowHead(from: a, to: b) {
                    scene.curves.append(GraphScene.Curve(id: item.id + "^", points: head, color: item.color, width: item.width))
                }
            case .surface:
                continue
            }
        }
        if showSpecialPoints {
            let xs = viewport.visibleX, ys = viewport.visibleY
            let spanX = xs.upperBound - xs.lowerBound, spanY = ys.upperBound - ys.lowerBound
            for (index, asymptote) in asymptotes.enumerated() {
                let ends: [SIMD2<Double>]
                switch asymptote.line {
                case .vertical(let x):
                    ends = [SIMD2(x, ys.lowerBound - spanY), SIMD2(x, ys.upperBound + spanY)]
                case .slanted(let k, let n):
                    let x0 = xs.lowerBound - spanX, x1 = xs.upperBound + spanX
                    ends = [SIMD2(x0, k * x0 + n), SIMD2(x1, k * x1 + n)]
                }
                scene.guides.append(GraphScene.Curve(id: "asymptote-\(index)", points: ends, color: asymptote.color.withAlpha(0.55), width: 1.5, dashed: true))
            }
        }
        if showSpecialPoints || highlightIntersections {
            for info in specialPoints {
                let isIntersection = info.point.kind == .intersection
                if !showSpecialPoints && !isIntersection { continue }
                scene.markers.append(GraphScene.Marker(
                    id: info.point.id, position: SIMD2(info.point.x, info.point.y),
                    color: markerColor(info),
                    radius: isIntersection ? 6 : 5, hollow: info.point.kind == .hole || info.point.kind == .openEnd))
            }
        }
        if let selected = selectedPoint {
            scene.markers.append(GraphScene.Marker(id: "selected", position: SIMD2(selected.point.x, selected.point.y), color: markerColor(selected), radius: 8))
        }
        if let trace = tracePoint {
            scene.markers.append(GraphScene.Marker(id: "trace", position: SIMD2(trace.point.x, trace.point.y), color: trace.color, radius: 7))
            if showTangent, let slope = trace.slope {
                let span = (viewport.visibleX.upperBound - viewport.visibleX.lowerBound)
                let x0 = trace.point.x - span, x1 = trace.point.x + span
                let y0 = trace.point.y + slope * (x0 - trace.point.x)
                let y1 = trace.point.y + slope * (x1 - trace.point.x)
                scene.guides.append(GraphScene.Curve(id: "tangent", points: [SIMD2(x0, y0), SIMD2(x1, y1)], color: trace.color.withAlpha(0.85), width: 2, dashed: true))
            }
        }
        self.scene = scene
        requestRedraw?()
    }

    /// Intersections belong to two curves, so they take the axis colour: white on the dark
    /// theme, black on the light one (a white marker vanished on a light background).
    private func markerColor(_ info: GraphPointInfo) -> RGBA {
        info.point.kind == .intersection ? theme.axis.withAlpha(1) : info.color
    }

    private func function(for id: String, expr: Expr) -> (Double) -> Double {
        if let f = functions[id] { return f }
        let f = makeFunction(expr)
        functions[id] = f
        return f
    }

    /// Points given as x₁, y₁, x₂, y₂, … expressions.
    private func figurePoints(_ coordinates: [Expr]) -> [SIMD2<Double>] {
        stride(from: 0, to: coordinates.count - 1, by: 2).compactMap { figurePoint(coordinates[$0], coordinates[$0 + 1]) }
    }

    /// A point given by expressions (they may use the parameters).
    private func figurePoint(_ x: Expr, _ y: Expr) -> SIMD2<Double>? {
        let p = SIMD2(makeFunction(x)(0), makeFunction(y)(0))
        return p.x.isFinite && p.y.isFinite ? p : nil
    }

    /// The two strokes of an arrow head at `b`, 13 pt long at the current zoom.
    private func arrowHead(from a: SIMD2<Double>, to b: SIMD2<Double>) -> [SIMD2<Double>]? {
        // Work in screen points (y down), then convert back to graph units.
        let d = SIMD2((b.x - a.x) * viewport.scale.x, -(b.y - a.y) * viewport.scale.y)
        let length = (d * d).sum().squareRoot()
        guard length > 2 else { return nil }
        let u = d / length
        let size = min(13, length / 2.5)
        func wing(_ angle: Double) -> SIMD2<Double> {
            let back = SIMD2(-u.x * cos(angle) + u.y * sin(angle), -u.y * cos(angle) - u.x * sin(angle)) * size
            return SIMD2(b.x + back.x / viewport.scale.x, b.y - back.y / viewport.scale.y)
        }
        return [wing(0.45), b, wing(-0.45)]
    }

    private func branches(for id: String, _ lhs: Expr, _ rhs: Expr) -> [Expr] {
        if let cached = branchCache[id] { return cached }
        let result = ImplicitBranches.branches(lhs, rhs) ?? []
        branchCache[id] = result
        return result
    }

    // MARK: Interaction

    /// Picks a special point near a view location (tap).
    func selectPoint(near location: CGPoint, tolerance: CGFloat = 22) -> Bool {
        let candidates = specialPoints.map { info -> (GraphPointInfo, CGFloat) in
            let p = viewport.point(for: SIMD2(info.point.x, info.point.y))
            return (info, hypot(p.x - location.x, p.y - location.y))
        }
        if let best = candidates.min(by: { $0.1 < $1.1 }), best.1 <= tolerance {
            selectedPoint = best.0
            rebuildScene()
            return true
        }
        if selectedPoint != nil || tracePoint != nil {
            selectedPoint = nil
            tracePoint = nil
            rebuildScene()
        }
        return false
    }

    /// Traces the curve closest to the touch at the touch's x position (implicit lines and
    /// conics through their branches y = g(x)).
    func trace(at location: CGPoint) {
        let g = viewport.graphPoint(for: location)
        var best: (item: PlotItem, point: SIMD2<Double>, distance: CGFloat, slope: Double?)?
        for item in items where item.visible {
            let curves: [Expr]
            switch item.kind {
            case .explicit(let expr):
                curves = [expr]
            case .implicit(let lhs, .equal, let rhs):
                curves = branches(for: item.id, lhs, rhs)
            case .parametric:
                // The sampled point of the curve nearest to the touch.
                for q in sampled[item.id]?.points ?? [] where q.x.isFinite && q.y.isFinite {
                    let p = viewport.point(for: q)
                    let distance = hypot(p.x - location.x, p.y - location.y)
                    if best == nil || distance < best!.distance { best = (item, q, distance, nil) }
                }
                continue
            default:
                continue
            }
            for (k, expr) in curves.enumerated() {
                let f = function(for: k == 0 ? item.id : "\(item.id)~\(k)", expr: expr)
                let y = f(g.x)
                guard y.isFinite else { continue }
                let p = viewport.point(for: SIMD2(g.x, y))
                let distance = abs(p.y - location.y)
                if best == nil || distance < best!.distance {
                    let slope = NumericCalculus.derivative(of: f, at: g.x)
                    best = (item, SIMD2(g.x, y), distance, slope.isFinite ? slope : nil)
                }
            }
        }
        guard let best else { return }
        let point = SpecialPoint(kind: .yIntercept, x: best.point.x, y: best.point.y)
        tracePoint = GraphPointInfo(point: point, itemID: best.item.id, color: best.item.color, slope: best.slope)
        rebuildScene()
    }

    func endTrace() {}

    /// Frames the visible curves: functions over the current x range, closed relations
    /// (circles, ellipses …) completely. With `lockAspect` both axes keep one scale.
    func fitToContent() {
        let xs = viewport.visibleX
        let visibleY = viewport.visibleY
        var frameX: ClosedRange<Double>?
        var frameY: ClosedRange<Double>?
        func include(x: ClosedRange<Double>, y: ClosedRange<Double>) {
            frameX = frameX.map { min($0.lowerBound, x.lowerBound)...max($0.upperBound, x.upperBound) } ?? x
            frameY = frameY.map { min($0.lowerBound, y.lowerBound)...max($0.upperBound, y.upperBound) } ?? y
        }
        var ys: [Double] = []
        for item in items where item.visible {
            switch item.kind {
            case .explicit(let expr):
                let f = makeFunction(expr)
                for i in 0...200 {
                    let x = xs.lowerBound + (xs.upperBound - xs.lowerBound) * Double(i) / 200
                    let y = f(x)
                    if y.isFinite { ys.append(y) }
                }
            case .implicit(let lhs, _, let rhs):
                // Look for the curve in a window five times the visible one.
                guard let program = implicitProgram(lhs, rhs) else { continue }
                let w = xs.upperBound - xs.lowerBound, h = visibleY.upperBound - visibleY.lowerBound
                let box = ImplicitBounds.find(program: program, parameters: parameterNames.map { parameters[$0] ?? 0 },
                                              x: (viewport.center.x - 2.5 * w)...(viewport.center.x + 2.5 * w),
                                              y: (viewport.center.y - 2.5 * h)...(viewport.center.y + 2.5 * h))
                if let box, box.isBounded { include(x: box.x, y: box.y) }
            case .sequence(let term):
                // Frame the first twenty terms.
                let f = makeFunction(term.substituting("n", with: .x))
                let values = (1...20).map { f(Double($0)) }.filter(\.isFinite)
                if let low = values.min(), let high = values.max() { include(x: 0...21, y: min(low, 0)...max(high, 0)) }
            case .point(let x, let y):
                if let p = figurePoint(x, y) { include(x: p.x...p.x, y: p.y...p.y) }
            case .parametric(let x, let y, let from, let to):
                let fx = makeFunction(x, variable: "t"), fy = makeFunction(y, variable: "t")
                let points = (0...400).map { i -> SIMD2<Double> in
                    let t = from + (to - from) * Double(i) / 400
                    return SIMD2(fx(t), fy(t))
                }.filter { $0.x.isFinite && $0.y.isFinite }
                if let x0 = points.map(\.x).min(), let x1 = points.map(\.x).max(), let y0 = points.map(\.y).min(), let y1 = points.map(\.y).max() {
                    include(x: x0...x1, y: y0...y1)
                }
            case .polyline(let coordinates, _):
                for p in figurePoints(coordinates) { include(x: p.x...p.x, y: p.y...p.y) }
            case .segment(let x0, let y0, let x1, let y1, _):
                if let a = figurePoint(x0, y0), let b = figurePoint(x1, y1) {
                    include(x: min(a.x, b.x)...max(a.x, b.x), y: min(a.y, b.y)...max(a.y, b.y))
                }
            default:
                continue
            }
        }
        if ys.count > 10 {
            ys.sort()
            // Robust range: ignore the extreme 3 % (asymptotes).
            var lo = ys[Int(Double(ys.count) * 0.03)]
            var hi = ys[Int(Double(ys.count) * 0.97)]
            if hi - lo < 1e-9 { lo -= 1; hi += 1 }
            include(x: xs, y: lo...hi)
        }
        guard var fx = frameX, var fy = frameY else { return }
        // A single point is shown together with the origin.
        if fx.upperBound - fx.lowerBound < 1e-9, fy.upperBound - fy.lowerBound < 1e-9 {
            fx = min(fx.lowerBound, 0)...max(fx.upperBound, 0)
            fy = min(fy.lowerBound, 0)...max(fy.upperBound, 0)
        }
        // A single point or a horizontal/vertical segment still gets a window around it.
        if fx.upperBound - fx.lowerBound < 1e-9 { fx = (fx.lowerBound - 1)...(fx.upperBound + 1) }
        if fy.upperBound - fy.lowerBound < 1e-9 { fy = (fy.lowerBound - 1)...(fy.upperBound + 1) }
        // Sequences (2ⁿ, n² …) need their own scale on each axis to be readable.
        let visibleItems = items.filter(\.visible)
        let onlySequences = !visibleItems.isEmpty && visibleItems.allSatisfy { item in
            if case .sequence = item.kind { return true }
            return false
        }
        if onlySequences {
            viewport.fit(x: fx, y: fy, margin: 0.1)
        } else if lockAspect {
            viewport.fit(x: fx, y: fy, margin: 0.12)
            viewport.equalizeAxes()
        } else {
            let margin = (fy.upperBound - fy.lowerBound) * 0.15
            viewport.scale.y = Double(viewport.size.height) / (fy.upperBound - fy.lowerBound + 2 * margin)
            viewport.center.y = (fy.lowerBound + fy.upperBound) / 2
            if fx != xs {
                let marginX = (fx.upperBound - fx.lowerBound) * 0.15
                viewport.scale.x = Double(viewport.size.width) / (fx.upperBound - fx.lowerBound + 2 * marginX)
                viewport.center.x = (fx.lowerBound + fx.upperBound) / 2
            }
        }
        viewport.scale = viewport.scale.clamped(lowerBound: SIMD2(repeating: GraphViewport.minimumScale),
                                                upperBound: SIMD2(repeating: GraphViewport.maximumScale))
        viewportDidChange(final: true)
    }

    func resetView() {
        viewport.center = .zero
        viewport.scale = SIMD2(48, 48)
        viewportDidChange(final: true)
    }

    // MARK: Inertia

    func startInertia(velocityPoints: CGPoint) {
        velocity = SIMD2(Double(velocityPoints.x), Double(velocityPoints.y))
        lastStep = CACurrentMediaTime()
        if (velocity * velocity).sum().squareRoot() > 40 { setContinuousRendering?(true) }
    }

    func stopInertia() {
        velocity = .zero
    }

    /// Called every frame by the renderer while continuous rendering is on.
    func stepAnimation() {
        let now = CACurrentMediaTime()
        let dt = min(max(now - lastStep, 0), 1.0 / 30)
        lastStep = now
        guard (velocity * velocity).sum().squareRoot() > 8 else {
            if velocity != .zero {
                velocity = .zero
                setContinuousRendering?(false)
                viewportDidChange(final: true)
            }
            return
        }
        viewport.pan(byPoints: CGSize(width: velocity.x * dt, height: velocity.y * dt))
        velocity *= exp(-dt * 4.5)
        viewportDidChange(final: false)
    }
}
