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
            guard lockAspect, !oldValue, keepsAspect else { return }
            viewport.equalizeAxes()
            viewportDidChange(final: true)
        }
    }
    /// Linear or logarithmic axes (a setting of the Graphs tab). The viewport, the scene and the
    /// sampled curves are in plot coordinates, log₁₀ of the values on a logarithmic axis, so panning
    /// and pinching work in decades there; definitions, special points and traced points stay values.
    var axes = AxisScales.linear { didSet { if axes != oldValue { axesDidChange(from: oldValue) } } }
    /// Both axes keep one scale: asked for, and both axes linear or both logarithmic (a unit and a
    /// decade of the same length mean nothing).
    var keepsAspect: Bool { lockAspect && axes.x == axes.y }
    var showSpecialPoints = true { didSet { if showSpecialPoints != oldValue { rebuildScene() } } }
    /// Marks the intersections (the scene shows their markers by it also when the special points are off).
    var highlightIntersections = true { didSet { if highlightIntersections != oldValue { rebuildScene() } } }
    /// Allows labelling the x axis in π for trigonometric graphs (a setting).
    var piAxisEnabled = true { didSet { if piAxisEnabled != oldValue { rebuildScene() } } }

    /// The x axis in multiples of π: a trigonometric function of x is drawn on a linear x axis.
    var piAxis: Bool {
        piAxisEnabled && axes.x == .linear && items.contains { item in
            guard item.visible, case .explicit(let e) = item.kind else { return false }
            return Self.isTrigonometric(e)
        }
    }

    /// The values shown along the x axis.
    var visibleValuesX: ClosedRange<Double> { axes.x.valueRange(viewport.visibleX) }

    /// The view point of a point given by its values; nil where an axis cannot show it (x ≤ 0 on a
    /// logarithmic x axis).
    func viewPoint(for point: SIMD2<Double>) -> CGPoint? {
        plotPoint(point).map(viewport.point(for:))
    }

    /// The plot coordinates of a point given by its values (nil where an axis cannot show it).
    private func plotPoint(_ point: SIMD2<Double>) -> SIMD2<Double>? {
        let plot = axes.plotPoint(point)
        return plot.x.isFinite && plot.y.isFinite ? plot : nil
    }

    /// Keeps the shown values where it can when an axis changes its scale: a linear stretch becomes
    /// the decades of its positive part (three below its top when it reaches 0), a logarithmic one
    /// the values it showed; without positive values a logarithmic axis shows 0,1 … 1000.
    private func axesDidChange(from old: AxisScales) {
        for (axis, (from, to)) in [(old.x, axes.x), (old.y, axes.y)].enumerated() where from != to {
            let values = from.valueRange(axis == 0 ? viewport.visibleX : viewport.visibleY)
            let plot = to.plotExtent(of: values) ?? (to == .logarithmic ? -1...3 : -10...10)
            let length = Double(axis == 0 ? viewport.size.width : viewport.size.height)
            viewport.center[axis] = (plot.lowerBound + plot.upperBound) / 2
            viewport.scale[axis] = min(max(length / max(plot.upperBound - plot.lowerBound, 1e-9), GraphViewport.minimumScale),
                                       GraphViewport.maximumScale)
        }
        if keepsAspect { viewport.equalizeAxes() }
        // The old curves are in the old plot coordinates.
        sampled = [:]
        fills = [:]
        rebuildScene()
        invalidate(analysis: true)
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
    /// The members of each union D₁ ∪ D₂ ∪ … that are drawn (in the sampled window, larger than a pixel).
    @ObservationIgnored private var unionMembers: [String: [Int]] = [:]
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
        let scales = axes
        sampledViewport = snapshot
        isComputing = true
        samplingTask = Task { [weak self] in
            let result = await BackgroundWork.run(priority: .userInitiated) {
                GraphCanvasModel.sample(items: currentItems, viewport: snapshot, parameters: params, angleUnit: unit, axes: scales)
            }
            guard let self, !Task.isCancelled else { return }
            self.sampled = result.curves
            self.fills = result.fills
            self.unionMembers = result.unions
            self.isComputing = false
            self.rebuildScene()
            if analysis { self.scheduleAnalysis() }
        }
    }

    nonisolated private struct SampleResult: Sendable {
        var curves: [String: SampledCurve]
        var fills: [String: [GraphScene.Fill]]
        var unions: [String: [Int]]
    }

    /// Most members of a union in one per-pixel program (about ten instructions each, at most 512).
    nonisolated static let unionMemberLimit = 48

    nonisolated private static func sample(items: [PlotItem], viewport: GraphViewport, parameters: [String: Double], angleUnit: AngleUnit,
                                           axes: AxisScales) -> SampleResult {
        let signpost = Signposts.signposter.beginInterval("Sample curves", id: Signposts.signposter.makeSignpostID())
        defer { Signposts.signposter.endInterval("Sample curves", signpost) }
        var curves: [String: SampledCurve] = [:]
        var fills: [String: [GraphScene.Fill]] = [:]
        var unions: [String: [Int]] = [:]
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
        // The samplers work in plot coordinates: on a logarithmic x axis f is read at x = 10ᵘ, on a
        // logarithmic y axis log₁₀ f(x) is drawn (NaN, a gap, where f ≤ 0).
        let toX = axes.x, toY = axes.y
        for item in items {
            // Newer items, parameters or viewport: the caller discards this result.
            if Task.isCancelled { break }
            switch item.kind {
            case .explicit(let expr):
                let f = FunctionAnalyzer.makeFunction(expr, variable: "x", context: context)
                let plotted: (Double) -> Double = axes.isLinear ? f : { u in toY.plotCoordinate(f(toX.value(atPlotCoordinate: u))) }
                curves[item.id] = sampler.sampleExplicit(plotted, over: domain)
                if let shade = item.shade {
                    let lower = item.shadeLower.map { FunctionAnalyzer.makeFunction($0, variable: "x", context: context) }
                    fills[item.id] = shadeBands(f: f, g: lower, range: shade, visible: domain, color: item.color, axes: axes)
                }
            case .explicitInY(let expr):
                let g = FunctionAnalyzer.makeFunction(expr, variable: "y", context: context)
                let plotted: (Double) -> Double = axes.isLinear ? g : { v in toX.plotCoordinate(g(toY.value(atPlotCoordinate: v))) }
                var curve = samplerY.sampleExplicit(plotted, over: domainY)
                curve.points = curve.points.map { SIMD2($0.y, $0.x) }
                curves[item.id] = curve
            case .parametric(let x, let y, let from, let to):
                let fx = FunctionAnalyzer.makeFunction(x, variable: "t", context: context)
                let fy = FunctionAnalyzer.makeFunction(y, variable: "t", context: context)
                curves[item.id] = axes.isLinear ? sampler.sampleParametric(fx, fy, over: from...to)
                    : sampler.sampleParametric({ toX.plotCoordinate(fx($0)) }, { toY.plotCoordinate(fy($0)) }, over: from...to)
            case .slopeField(let f):
                // About one segment per 34 points, over the window that is kept while panning (the tools
                // that draw these keep linear axes; on logarithmic ones the segments' ends are mapped).
                let columns = 3 * Swift.max(8, Swift.min(30, Int(Double(viewport.size.width) / 34)))
                let rows = 3 * Swift.max(6, Swift.min(30, Int(Double(viewport.size.height) / 34)))
                let points = DifferentialEquation.slopeField(f, x: toX.valueRange(domain), y: toY.valueRange(domainY), columns: columns, rows: rows,
                                                             aspect: viewport.scale.y / viewport.scale.x, parameters: parameters)
                curves[item.id] = SampledCurve(points: axes.isLinear ? points : points.map(axes.plotPoint), domain: domain,
                                               resolution: viewport.unitsPerPoint.x)
            case .odeSolution(let f, let order, let x0, let initial):
                let points = DifferentialEquation.solve(f, order: order, x0: x0, initial: initial, over: toX.valueRange(domain), parameters: parameters)
                curves[item.id] = SampledCurve(points: axes.isLinear ? points : points.map(axes.plotPoint), domain: domain,
                                               resolution: viewport.unitsPerPoint.x)
            case .union(let family):
                // Members down to a pixel (a third of a point on a 3× screen) in the window kept while panning,
                // in values; a pixel of a logarithmic axis is smallest at the low end of the window.
                let windowX = toX.valueRange(domain), windowY = toY.valueRange(domainY)
                let pixelX = (toX == .linear ? 1 : windowX.lowerBound * log(10)) * viewport.unitsPerPoint.x / 3
                let pixelY = (toY == .linear ? 1 : windowY.lowerBound * log(10)) * viewport.unitsPerPoint.y / 3
                unions[item.id] = family.drawnMembers(x: windowX, y: windowY, minimumSize: Swift.min(pixelX, pixelY),
                                                      parameters: parameters, limit: unionMemberLimit)
            default:
                continue
            }
        }
        return SampleResult(curves: curves, fills: fills, unions: unions)
    }

    /// Triangle strips for ∫ₐᵇ (f − g): positive parts tinted with the curve colour,
    /// negative parts in a contrasting red, so the signed area is visible. `visible` and the strips
    /// are in plot coordinates: on a logarithmic x axis the strip is sampled evenly in decades, and on
    /// a logarithmic y axis a band down to 0 (or below) reaches past the bottom edge.
    nonisolated static func shadeBands(f: (Double) -> Double, g: ((Double) -> Double)?, range: ClosedRange<Double>, visible: ClosedRange<Double>,
                                       color: RGBA, axes: AxisScales = .linear) -> [GraphScene.Fill] {
        let shown = axes.x.valueRange(visible)
        let a = max(range.lowerBound, shown.lowerBound)
        let b = min(range.upperBound, shown.upperBound)
        guard b > a else { return [] }
        let start = axes.x.plotCoordinate(a), end = axes.x.plotCoordinate(b)
        func plotY(_ y: Double) -> Double { axes.y == .logarithmic && y <= 0 ? -.infinity : axes.y.plotCoordinate(y) }
        let n = 720
        var positive: [SIMD2<Double>] = []
        var negative: [SIMD2<Double>] = []
        positive.reserveCapacity(2 * (n + 1))
        negative.reserveCapacity(2 * (n + 1))
        for i in 0...n {
            let u = start + (end - start) * Double(i) / Double(n)
            let x = axes.x.value(atPlotCoordinate: u)
            let top = f(x)
            let bottom = g?(x) ?? 0
            let base = SIMD2(u, plotY(bottom))
            guard top.isFinite, bottom.isFinite else {
                positive.append(base); positive.append(base)
                negative.append(base); negative.append(base)
                continue
            }
            let above = SIMD2(u, plotY(max(top, bottom)))
            let below = SIMD2(u, plotY(min(top, bottom)))
            if top >= bottom {
                positive.append(base); positive.append(above)
                negative.append(base); negative.append(base)
            } else {
                negative.append(below); negative.append(base)
                positive.append(base); positive.append(base)
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
        let scales = axes
        analysisTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let result = await BackgroundWork.run(priority: .utility) {
                GraphCanvasModel.analyze(items: currentItems, viewport: snapshot, parameters: params, angleUnit: unit,
                                         special: wantSpecial, intersections: wantIntersections, axes: scales)
            }
            guard let self, !Task.isCancelled else { return }
            self.specialPoints = result.points
            self.asymptotes = result.asymptotes
            self.rebuildScene()
        }
    }

    nonisolated private static func analyze(items: [PlotItem], viewport: GraphViewport, parameters: [String: Double], angleUnit: AngleUnit,
                                            special: Bool, intersections: Bool, axes: AxisScales) -> (points: [GraphPointInfo], asymptotes: [GraphAsymptote]) {
        let signpost = Signposts.signposter.beginInterval("Find special points", id: Signposts.signposter.makeSignpostID())
        defer { Signposts.signposter.endInterval("Find special points", signpost) }
        let context = EvaluationContext(angleUnit: angleUnit, variables: parameters)
        // The values shown; a logarithmic x axis is searched decade by decade.
        let range = axes.x.valueRange(viewport.visibleX)
        let visibleY = axes.y.valueRange(viewport.visibleY)
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
                // Newer items, parameters or viewport: the caller discards this result.
                if Task.isCancelled { return (result, asymptotes) }
                var analysis = FunctionAnalyzer.analyze(curve.expr, range: range, scale: axes.x, context: context, includeAsymptotes: true)
                // x → −∞ is not on a logarithmic x axis.
                if axes.x == .logarithmic { analysis.horizontalAsymptoteLeft = nil }
                analysis.poles = uncrowded(analysis.poles, axes: axes) { x in
                    viewport.point(for: SIMD2(axes.x.plotCoordinate(x), viewport.center.y))
                }
                let points = uncrowded(analysis.allPoints.filter { visibleY.contains($0.y) }, axes: axes) { p in
                    viewport.point(for: axes.plotPoint(SIMD2(p.x, p.y)))
                }
                for p in points {
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
                    if Task.isCancelled { return (result, asymptotes) }
                    let found = FunctionAnalyzer.intersections(curves[i].expr, curves[j].expr, range: range, scale: axes.x,
                                                               context: context, otherCurve: j)
                    let points = uncrowded(found, axes: axes) { p in viewport.point(for: axes.plotPoint(SIMD2(p.x, p.y))) }
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

    /// On a logarithmic x axis a periodic function has thousands of zeros, extrema and poles in the
    /// high decades (sin x has some 3000 over 1 … 10⁴), which would draw as chains of markers and a
    /// wall of asymptotes: there an element within 12 points of two others of its list is left out,
    /// while a pair of close points (a zero beside an extremum) stays. Linear axes keep everything.
    nonisolated private static func uncrowded<Element>(_ elements: [Element], axes: AxisScales,
                                                       at position: (Element) -> CGPoint) -> [Element] {
        guard axes.x == .logarithmic, elements.count > 2 else { return elements }
        let points = elements.map(position)
        // Points an axis cannot show (NaN) are not drawn and crowd nothing.
        let order = points.indices.filter { points[$0].x.isFinite && points[$0].y.isFinite }.sorted { points[$0].x < points[$1].x }
        var crowded = Set<Int>()
        for (k, i) in order.enumerated() {
            var neighbours = 0
            for step in [-1, 1] {
                var m = k + step
                while m >= 0, m < order.count, neighbours < 2, Swift.abs(points[order[m]].x - points[i].x) < 12 {
                    if hypot(points[order[m]].x - points[i].x, points[order[m]].y - points[i].y) < 12 { neighbours += 1 }
                    m += step
                }
            }
            if neighbours >= 2 { crowded.insert(i) }
        }
        return elements.indices.filter { !crowded.contains($0) }.map { elements[$0] }
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
        scene.axes = axes
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
                // The engine draws F ≠ G as a region (CalculationEngine.implicitKind). Mode 0 would draw the curve
                // F = G, exactly the points that are not solutions, so a ≠ here is a bug: nothing is drawn for it.
                guard relation != .notEqual else {
                    assertionFailure("F ≠ G must arrive as the region of CalculationEngine.implicitKind")
                    continue
                }
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
            case .union(let family):
                // D₁ ∪ D₂ ∪ … as one region: the greatest margin of the members drawn, per pixel (a member is outside
                // where it is undefined, RegionFamily.drawnGaps).
                var members = unionMembers[item.id] ?? []
                var program: Program?
                while program == nil, !members.isEmpty {
                    let gaps = family.drawnGaps(members)
                    program = implicitProgram(gaps.count == 1 ? gaps[0] : .function(.max, gaps), .zero)
                    // Too long for one program: drop the last quarter (the smallest members of a shrinking family).
                    if program == nil { members.removeLast(Swift.max(1, members.count / 4)) }
                }
                guard let program else { continue }
                scene.implicits.append(GraphScene.Implicit(
                    id: item.id, program: program,
                    parameters: parameterNames.map { Float(parameters[$0] ?? 0) },
                    color: item.color, fillColor: item.color.withAlpha(0.22), mode: family.strict ? 3 : 4, width: item.width))
            case .sequence(let term):
                // Terms a₁, a₂, … in the visible range (at most about 600 points).
                let f = function(for: item.id, expr: term.substituting("n", with: .x))
                for n in sequenceIndices() {
                    let value = f(Double(n))
                    guard value.isFinite, let position = plotPoint(SIMD2(Double(n), value)) else { continue }
                    scene.markers.append(GraphScene.Marker(id: "\(item.id)#\(n)", position: position, color: item.color, radius: 4.5))
                }
            case .point(let x, let y):
                guard let p = figurePoint(x, y).flatMap(plotPoint) else { continue }
                let color = item.axisColored ? theme.axis.withAlpha(1) : item.color
                scene.markers.append(GraphScene.Marker(id: item.id, position: p, color: color, radius: 6))
            case .polyline(let coordinates, let closed):
                // Straight between the corners as drawn; a corner an axis cannot show breaks the line.
                var corners = figurePoints(coordinates).map(axes.plotPoint)
                if closed, let first = corners.first { corners.append(first) }
                guard corners.count >= 2 else { continue }
                scene.curves.append(GraphScene.Curve(id: item.id, points: corners, color: item.color, width: item.width))
            case .segment(let x0, let y0, let x1, let y1, let arrow):
                guard let a = figurePoint(x0, y0), let b = figurePoint(x1, y1) else { continue }
                let points = segmentPoints(from: a, to: b)
                guard points.count >= 2 else { continue }
                scene.curves.append(GraphScene.Curve(id: item.id, points: points, color: arrow ? item.color : item.color.withAlpha(0.7),
                                                     width: arrow ? item.width : 1.5, dashed: !arrow))
                if arrow, let head = arrowHead(at: points) {
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
                    let u = axes.x.plotCoordinate(x)
                    guard u.isFinite else { continue }
                    ends = [SIMD2(u, ys.lowerBound - spanY), SIMD2(u, ys.upperBound + spanY)]
                case .slanted(let k, let n) where axes.isLinear:
                    let x0 = xs.lowerBound - spanX, x1 = xs.upperBound + spanX
                    ends = [SIMD2(x0, k * x0 + n), SIMD2(x1, k * x1 + n)]
                case .slanted(let k, let n):
                    ends = curvedLine(slope: k, intercept: n)
                }
                scene.guides.append(GraphScene.Curve(id: "asymptote-\(index)", points: ends, color: asymptote.color.withAlpha(0.55), width: 1.5, dashed: true))
            }
        }
        if showSpecialPoints || highlightIntersections {
            for info in specialPoints {
                let isIntersection = info.point.kind == .intersection
                if !showSpecialPoints && !isIntersection { continue }
                guard let position = plotPoint(SIMD2(info.point.x, info.point.y)) else { continue }
                scene.markers.append(GraphScene.Marker(
                    id: info.point.id, position: position,
                    color: markerColor(info),
                    radius: isIntersection ? 6 : 5, hollow: info.point.kind == .hole || info.point.kind == .openEnd))
            }
        }
        if let selected = selectedPoint, let position = plotPoint(SIMD2(selected.point.x, selected.point.y)) {
            scene.markers.append(GraphScene.Marker(id: "selected", position: position, color: markerColor(selected), radius: 8))
        }
        if let trace = tracePoint, let position = plotPoint(SIMD2(trace.point.x, trace.point.y)) {
            scene.markers.append(GraphScene.Marker(id: "trace", position: position, color: trace.color, radius: 7))
            if showTangent, let slope = trace.slope {
                let points: [SIMD2<Double>]
                if axes.isLinear {
                    let span = (viewport.visibleX.upperBound - viewport.visibleX.lowerBound)
                    let x0 = trace.point.x - span, x1 = trace.point.x + span
                    let y0 = trace.point.y + slope * (x0 - trace.point.x)
                    let y1 = trace.point.y + slope * (x1 - trace.point.x)
                    points = [SIMD2(x0, y0), SIMD2(x1, y1)]
                } else {
                    // The tangent y = y₀ + k(x − x₀) of the callout, curved on logarithmic axes.
                    points = curvedLine(slope: slope, intercept: trace.point.y - slope * trace.point.x)
                }
                scene.guides.append(GraphScene.Curve(id: "tangent", points: points, color: trace.color.withAlpha(0.85), width: 2, dashed: true))
            }
        }
        self.scene = scene
        requestRedraw?()
    }

    /// The line y = kx + n in plot coordinates on logarithmic axes, where it is curved (straight
    /// only for a constant y, or y = kx on two logarithmic axes): sampled like a function over the
    /// visible x range and its width on either side.
    private func curvedLine(slope k: Double, intercept n: Double) -> [SIMD2<Double>] {
        let xs = viewport.visibleX
        let width = xs.upperBound - xs.lowerBound
        let scales = axes
        let sampler = CurveSampler(unitsPerPixel: viewport.unitsPerPoint * 0.5, visibleY: viewport.visibleY)
        return sampler.sampleExplicit({ u in scales.y.plotCoordinate(k * scales.x.value(atPlotCoordinate: u) + n) },
                                      over: (xs.lowerBound - width)...(xs.upperBound + width)).points
    }

    /// The indices n = 1, 2, 3 … of the terms shown: at most about 600 evenly spread on a linear x
    /// axis; on a logarithmic one every n while they are far apart, then about 600 per visible width.
    private func sequenceIndices() -> [Int] {
        let visible = visibleValuesX
        let limit = axes.x == .logarithmic ? 1e15 : 1e6
        let first = max(1, ceil(max(visible.lowerBound, -limit)))
        let last = floor(min(visible.upperBound, limit))
        guard last >= first else { return [] }
        guard axes.x == .logarithmic else {
            let step = max(1, Int((last - first) / 600))
            return Array(stride(from: Int(first), through: Int(last), by: step))
        }
        let ratio = pow(10, (viewport.visibleX.upperBound - viewport.visibleX.lowerBound) / 600)
        var indices: [Int] = []
        var n = first
        while n <= last, indices.count < 1200 {
            indices.append(Int(n))
            n = max(n + 1, (n * ratio).rounded(.down))
        }
        return indices
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

    /// A segment between two points given by their values, in plot coordinates: straight on linear
    /// axes. On logarithmic ones the straight segment between the values is a curve that runs to −∞
    /// toward 0, so it is cut a view's height below the visible decades and sampled (a vector from the
    /// origin comes in from that edge; a segment wholly at x ≤ 0 or y ≤ 0 is not drawn).
    private func segmentPoints(from a: SIMD2<Double>, to b: SIMD2<Double>) -> [SIMD2<Double>] {
        guard !axes.isLinear else { return [a, b] }
        var start = 0.0, end = 1.0
        for (axis, scale) in [axes.x, axes.y].enumerated() where scale == .logarithmic {
            let visible = axis == 0 ? viewport.visibleX : viewport.visibleY
            let floor = pow(10, 2 * visible.lowerBound - visible.upperBound)
            let delta = b[axis] - a[axis]
            if delta == 0 {
                guard a[axis] >= floor else { return [] }
            } else if delta > 0 {
                start = max(start, (floor - a[axis]) / delta)
            } else {
                end = min(end, (floor - a[axis]) / delta)
            }
        }
        guard start < end else { return [] }
        let p = a + (b - a) * start, q = a + (b - a) * end
        let scales = axes
        let sampler = CurveSampler(unitsPerPixel: viewport.unitsPerPoint * 0.5, visibleY: viewport.visibleY)
        return sampler.sampleParametric({ t in scales.x.plotCoordinate(p.x + (q.x - p.x) * t) },
                                        { t in scales.y.plotCoordinate(p.y + (q.y - p.y) * t) }, over: 0...1).points
    }

    /// The arrow head at the end of a segment drawn through `points` (plot coordinates), pointing
    /// along its last 13 pt (a sampled segment bends on logarithmic axes).
    private func arrowHead(at points: [SIMD2<Double>]) -> [SIMD2<Double>]? {
        guard points.count >= 2, let tip = points.last, tip.x.isFinite, tip.y.isFinite else { return nil }
        func farEnough(_ p: SIMD2<Double>) -> Bool {
            let d = (p - tip) * viewport.scale
            return (d * d).sum().squareRoot() >= 13
        }
        let back = points.dropLast().last { $0.x.isFinite && $0.y.isFinite && farEnough($0) } ?? points[0]
        return arrowHead(from: back, to: tip)
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
        let candidates = specialPoints.compactMap { info -> (GraphPointInfo, CGFloat)? in
            guard let p = viewPoint(for: SIMD2(info.point.x, info.point.y)) else { return nil }
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
        let x = axes.x.value(atPlotCoordinate: viewport.graphPoint(for: location).x)
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
                    if best == nil || distance < best!.distance { best = (item, axes.point(atPlot: q), distance, nil) }
                }
                continue
            default:
                continue
            }
            for (k, expr) in curves.enumerated() {
                let f = function(for: k == 0 ? item.id : "\(item.id)~\(k)", expr: expr)
                let y = f(x)
                guard y.isFinite, let p = viewPoint(for: SIMD2(x, y)) else { continue }
                let distance = abs(p.y - location.y)
                if best == nil || distance < best!.distance {
                    let slope = NumericCalculus.derivative(of: f, at: x)
                    best = (item, SIMD2(x, y), distance, slope.isFinite ? slope : nil)
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
    /// (circles, ellipses …) completely. With `lockAspect` both axes keep one scale. The frame is
    /// in plot coordinates, so on a logarithmic axis it holds the decades of the positive values.
    func fitToContent() {
        let xs = viewport.visibleX
        let visibleY = viewport.visibleY
        var frameX: ClosedRange<Double>?
        var frameY: ClosedRange<Double>?
        func include(x: ClosedRange<Double>, y: ClosedRange<Double>) {
            frameX = frameX.map { min($0.lowerBound, x.lowerBound)...max($0.upperBound, x.upperBound) } ?? x
            frameY = frameY.map { min($0.lowerBound, y.lowerBound)...max($0.upperBound, y.upperBound) } ?? y
        }
        /// A point given by its values, where the axes can show it.
        func includePoint(_ point: SIMD2<Double>) {
            guard let p = plotPoint(point) else { return }
            include(x: p.x...p.x, y: p.y...p.y)
        }
        var ys: [Double] = []
        // F ≠ G is framed by its curve F = G: the region it is drawn as has no sign change to find. So is a system with
        // F ≠ G, by its curves (CalculationEngine.framedCurves): its region changes sign only at grid points on them.
        let typed = items.filter(\.visible).compactMap { CalculationEngine.typedKind($0.kind) }
        let kinds = typed.flatMap { kind -> [GraphKind] in
            guard let curves = CalculationEngine.framedCurves(kind) else { return [kind] }
            return curves.map { GraphKind.implicit(lhs: $0.lhs, relation: .equal, rhs: $0.rhs) }
        }
        for kind in kinds {
            switch kind {
            case .explicit(let expr):
                let f = makeFunction(expr)
                for i in 0...200 {
                    let x = xs.lowerBound + (xs.upperBound - xs.lowerBound) * Double(i) / 200
                    let y = axes.y.plotCoordinate(f(axes.x.value(atPlotCoordinate: x)))
                    if y.isFinite { ys.append(y) }
                }
            case .implicit(let lhs, _, let rhs):
                // Look for the curve in a window five times the visible one, in plot coordinates (in
                // decades on a logarithmic axis, where a relation through 0 runs off like a line).
                guard let program = implicitProgram(lhs, rhs) else { continue }
                let w = xs.upperBound - xs.lowerBound, h = visibleY.upperBound - visibleY.lowerBound
                let box = ImplicitBounds.find(program: program, parameters: parameterNames.map { parameters[$0] ?? 0 },
                                              plotX: (viewport.center.x - 2.5 * w)...(viewport.center.x + 2.5 * w),
                                              plotY: (viewport.center.y - 2.5 * h)...(viewport.center.y + 2.5 * h), axes: axes)
                if let box, box.isBounded { include(x: box.x, y: box.y) }
            case .union(let family):
                // The frame of the members is in values: on a logarithmic axis its positive part.
                if let frame = family.frame(parameters: parameters), let x = axes.x.plotExtent(of: frame.x), let y = axes.y.plotExtent(of: frame.y) {
                    include(x: x, y: y)
                }
            case .sequence(let term):
                // Frame the first twenty terms.
                let f = makeFunction(term.substituting("n", with: .x))
                if axes.isLinear {
                    let values = (1...20).map { f(Double($0)) }.filter(\.isFinite)
                    if let low = values.min(), let high = values.max() { include(x: 0...21, y: min(low, 0)...max(high, 0)) }
                } else {
                    for n in 1...20 { includePoint(SIMD2(Double(n), f(Double(n)))) }
                }
            case .point(let x, let y):
                if let p = figurePoint(x, y) { includePoint(p) }
            case .parametric(let x, let y, let from, let to):
                let fx = makeFunction(x, variable: "t"), fy = makeFunction(y, variable: "t")
                let points = (0...400).map { i -> SIMD2<Double> in
                    let t = from + (to - from) * Double(i) / 400
                    return axes.plotPoint(SIMD2(fx(t), fy(t)))
                }.filter { $0.x.isFinite && $0.y.isFinite }
                if let x0 = points.map(\.x).min(), let x1 = points.map(\.x).max(), let y0 = points.map(\.y).min(), let y1 = points.map(\.y).max() {
                    include(x: x0...x1, y: y0...y1)
                }
            case .polyline(let coordinates, _):
                for p in figurePoints(coordinates) { includePoint(p) }
            case .segment(let x0, let y0, let x1, let y1, _):
                if let a = figurePoint(x0, y0), let b = figurePoint(x1, y1) {
                    includePoint(a)
                    includePoint(b)
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
        // A single point is shown together with the origin (which logarithmic axes do not have).
        if axes.isLinear, fx.upperBound - fx.lowerBound < 1e-9, fy.upperBound - fy.lowerBound < 1e-9 {
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
        } else if keepsAspect {
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

    /// Shows at least the values x × y, with equal axes where both have the same scale (the smoke
    /// test and the README screenshots frame the graph with it).
    func show(x: ClosedRange<Double>, y: ClosedRange<Double>) {
        guard let plotX = axes.x.plotExtent(of: x), let plotY = axes.y.plotExtent(of: y) else { return }
        viewport.fit(x: plotX, y: plotY, margin: 0)
        if axes.x == axes.y { viewport.equalizeAxes() }
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
