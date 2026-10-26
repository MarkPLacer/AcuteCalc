import AcuteCore
import SwiftUI

/// What a 3D sketch shows. Lines and planes are cut to the box around the finite parts.
struct SpaceSketch {
    struct Arrow {
        var from: [Double]
        var to: [Double]
        var color: Color
        var label: String?
    }

    struct Segment {
        var from: [Double]
        var to: [Double]
        var color: Color
        var dashed = false
        var label: String?
    }

    struct Point {
        var position: [Double]
        var color: Color
        var label: String?
        var hollow = false
    }

    struct Polygon {
        var corners: [[Double]]
        var color: Color
    }

    struct Line {
        var line: SpatialGeometry.Line
        var color: Color
        var label: String?
    }

    struct Plane {
        var plane: SpatialGeometry.Plane
        var color: Color
        var label: String?
    }

    var arrows: [Arrow] = []
    var segments: [Segment] = []
    var points: [Point] = []
    var polygons: [Polygon] = []
    var lines: [Line] = []
    var planes: [Plane] = []
    var solid: Solids.Solid?
    var showsAxes = true
    /// A drawing in the xy plane: seen from above, without the z axis and turning.
    var planar = false

    /// The finite points the box is fitted around.
    var anchors: [[Double]] {
        var points = arrows.flatMap { [$0.from, $0.to] } + segments.flatMap { [$0.from, $0.to] }
        points += self.points.map(\.position) + polygons.flatMap(\.corners) + lines.map(\.line.point)
        // The point of each plane nearest to the origin, −d·n⃗/|n⃗|², with n⃗ and d first brought
        // near 1 by a power of two, so |n⃗|² neither overflows nor vanishes.
        points += planes.map { item in
            let unit = Self.unit(of: item.plane.normal)
            let n = item.plane.normal.map { $0 * unit }
            let k = -(item.plane.d * unit) / VectorGeometry.dot(n, n)
            return n.map { $0 * k }
        }
        switch solid?.shape {
        case .polyhedron(let mesh): points += mesh.vertices
        case .sphere(let r): points += [[-r, -r, -r], [r, r, r]]
        case nil: break
        }
        if showsAxes { points.append([0, 0, 0]) }
        return points.map { $0.count == 2 ? $0 + [0] : $0 }
    }

    /// The power of two that brings the largest finite |value| to between 1 and 2 (1 when all
    /// are zero), kept a normal double.
    static func unit(of values: [Double]) -> Double {
        let largest = values.filter(\.isFinite).map { Swift.abs($0) }.max() ?? 0
        guard largest > 0 else { return 1 }
        return Double(sign: .plus, exponent: Swift.min(Swift.max(-largest.exponent, -1022), 1022), significand: 1)
    }

    /// The sketch with every coordinate multiplied by `factor`, a power of two, so the drawing
    /// computes with numbers near 1 whether the values are 10⁻²⁰⁰ or 10³⁰⁰ (a power of two only
    /// moves the exponent). Directions of lines and normals of planes are brought near 1 by
    /// their own powers of two, which leaves the lines and planes where they are.
    func scaled(by factor: Double) -> SpaceSketch {
        func local(_ p: [Double]) -> [Double] { p.map { $0 * factor } }
        var copy = self
        for k in copy.arrows.indices {
            copy.arrows[k].from = local(arrows[k].from)
            copy.arrows[k].to = local(arrows[k].to)
        }
        for k in copy.segments.indices {
            copy.segments[k].from = local(segments[k].from)
            copy.segments[k].to = local(segments[k].to)
        }
        for k in copy.points.indices { copy.points[k].position = local(points[k].position) }
        for k in copy.polygons.indices { copy.polygons[k].corners = polygons[k].corners.map(local) }
        for k in copy.lines.indices {
            let line = lines[k].line
            let unit = Self.unit(of: line.direction)
            copy.lines[k].line = SpatialGeometry.Line(point: local(line.point), direction: line.direction.map { $0 * unit })
        }
        for k in copy.planes.indices {
            let plane = planes[k].plane
            let unit = Self.unit(of: plane.normal)
            copy.planes[k].plane = SpatialGeometry.Plane(normal: plane.normal.map { $0 * unit }, d: plane.d * unit * factor)
        }
        if var solid {
            switch solid.shape {
            case .polyhedron(var mesh):
                mesh.vertices = mesh.vertices.map(local)
                solid.shape = .polyhedron(mesh)
            case .sphere(let r):
                solid.shape = .sphere(radius: r * factor)
            }
            for k in solid.guides.indices {
                solid.guides[k].start = local(solid.guides[k].start)
                solid.guides[k].end = local(solid.guides[k].end)
            }
            for k in solid.marks.indices { solid.marks[k].position = local(solid.marks[k].position) }
            copy.solid = solid
        }
        return copy
    }
}

/// A 3D sketch in orthographic projection: drag to turn it, pinch to zoom, double tap for the
/// standard view. Hidden edges of solids are dashed.
struct SpaceSketchView: View {
    let sketch: SpaceSketch
    var accessibilityText = "Prostorska skica"
    @State private var view = Sketch3D.View.standard
    @State private var dragStart: Sketch3D.View?
    @State private var zoom = 1.0
    @State private var zoomStart: Double?

    var body: some View {
        Canvas { context, size in
            SpaceSketchRenderer(sketch: sketch, view: sketch.planar ? .top : view, zoom: zoom, size: size).draw(in: &context)
        }
        .contentShape(.rect)
        // A flat sketch does not turn, so its drag must not keep the list from scrolling.
        .gesture(rotation, including: sketch.planar ? .none : .all)
        .simultaneousGesture(magnification)
        .onTapGesture(count: 2) { reset() }
        .overlay(alignment: .bottomTrailing) {
            if !sketch.planar { viewMenu }
        }
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(sketch.planar ? "" : "Vleci za vrtenje, dva prsta za povečavo, dvojni dotik za prostorski pogled.")
    }

    private var rotation: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard !sketch.planar else { return }
                let start = dragStart ?? view
                if dragStart == nil { dragStart = view }
                view = start.turned(yaw: -value.translation.width * 0.01, pitch: value.translation.height * 0.01)
            }
            .onEnded { _ in dragStart = nil }
    }

    private var magnification: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = zoomStart ?? zoom
                if zoomStart == nil { zoomStart = zoom }
                zoom = Swift.min(4, Swift.max(0.4, start * value.magnification))
            }
            .onEnded { _ in zoomStart = nil }
    }

    private var viewMenu: some View {
        Menu {
            Button("Prostorski pogled", systemImage: "cube") { reset() }
            Button("Od spredaj", systemImage: "square") { view = .front }
            Button("Od desne", systemImage: "square.righthalf.filled") { view = .side }
            Button("Od zgoraj", systemImage: "square.tophalf.filled") { view = .above }
        } label: {
            Label("Pogled", systemImage: "rotate.3d")
                .labelStyle(.iconOnly)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .padding(6)
    }

    private func reset() {
        view = .standard
        zoom = 1
    }
}

/// Draws a sketch: axes, filled faces and planes from back to front, hidden edges dashed,
/// then lines, segments, arrows, points and labels. It draws the sketch in a local unit (see
/// `SpaceSketch.scaled(by:)`); only the numbers on the axes are the values themselves.
private struct SpaceSketchRenderer {
    let sketch: SpaceSketch
    let view: Sketch3D.View
    let zoom: Double
    let size: CGSize

    /// Local coordinates are the values times `factor`.
    private let factor: Double
    private let box: Sketch3D.Box
    private let scale: Double
    private let center: (x: Double, y: Double)

    init(sketch: SpaceSketch, view: Sketch3D.View, zoom: Double, size: CGSize) {
        let factor = SpaceSketch.unit(of: Array(sketch.anchors.joined()))
        let local = sketch.scaled(by: factor)
        self.factor = factor
        self.sketch = local
        self.view = view
        self.zoom = zoom
        self.size = size
        box = Sketch3D.Box.around(local.anchors)
        let padding = 22.0
        let width = Swift.max(Double(size.width) - 2 * padding, 1), height = Swift.max(Double(size.height) - 2 * padding, 1)
        if sketch.planar {
            // Seen from above the box is its xy rectangle.
            let w = box.upper[0] - box.lower[0], h = box.upper[1] - box.lower[1]
            scale = zoom * Swift.min(width / w, height / h)
        } else {
            // The sphere around the box keeps its size while the sketch turns.
            scale = zoom * Swift.min(width, height) / (2 * box.radius)
        }
        let c = view.project(box.center)
        center = (c.x, c.y)
    }

    private func point(_ p: [Double]) -> CGPoint {
        let q = view.project(p)
        return CGPoint(x: Double(size.width) / 2 + (q.x - center.x) * scale, y: Double(size.height) / 2 - (q.y - center.y) * scale)
    }

    private func path(_ corners: [[Double]], closed: Bool) -> Path {
        var path = Path()
        path.addLines(corners.map(point))
        if closed { path.closeSubpath() }
        return path
    }

    private static let dashed = StrokeStyle(lineWidth: 1.2, dash: [5, 4])

    func draw(in context: inout GraphicsContext) {
        if sketch.showsAxes { drawAxes(in: &context) }
        drawFills(in: &context)
        if let solid = sketch.solid { drawSolid(solid, in: &context) }
        for item in sketch.lines {
            guard let part = Sketch3D.clip(item.line, to: box) else { continue }
            context.stroke(path([part.start, part.end], closed: false), with: .color(item.color), lineWidth: 1.8)
            if let label = item.label { text(label, at: point(part.end), awayFrom: point(part.start), color: item.color, in: &context) }
        }
        for item in sketch.segments {
            let line = path([item.from, item.to], closed: false)
            if item.dashed {
                context.stroke(line, with: .color(item.color), style: Self.dashed)
            } else {
                context.stroke(line, with: .color(item.color), lineWidth: 1.5)
            }
            if let label = item.label { midLabel(label, item.from, item.to, color: item.color, in: &context) }
        }
        for item in sketch.arrows { drawArrow(item, in: &context) }
        for item in sketch.points {
            let p = point(item.position)
            let dot = Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7))
            if item.hollow {
                context.fill(dot, with: .color(Color(.systemBackground)))
                context.stroke(dot, with: .color(item.color), lineWidth: 1.5)
            } else {
                context.fill(dot, with: .color(item.color))
            }
            if let label = item.label {
                context.draw(Text(label).font(.caption.weight(.semibold)).foregroundStyle(item.color),
                             at: CGPoint(x: p.x + 9, y: p.y - 9))
            }
        }
    }

    // MARK: Parts

    private func drawAxes(in context: inout GraphicsContext) {
        let names = ["x", "y", "z"]
        // Ticks at round values (1, 2 or 5 times a power of ten) of the coordinates themselves,
        // placed in the local unit. The step is 70 points in local units over the factor, which
        // stays finite for values near 10⁻³⁰⁸ as well as 10³⁰⁸, where scale · factor would not.
        let step = GridSpacing.choose(raw: 70 / scale / factor).major
        let localStep = step * factor
        for i in 0..<(sketch.planar ? 2 : 3) {
            var start = [0.0, 0, 0], end = [0.0, 0, 0]
            start[i] = box.lower[i]
            end[i] = box.upper[i]
            let a = point(start), b = point(end)
            let length = hypot(b.x - a.x, b.y - a.y)
            guard length > 4 else { continue }
            var axis = Path()
            axis.move(to: a)
            axis.addLine(to: b)
            context.stroke(axis, with: .color(.secondary.opacity(0.8)), lineWidth: 1)
            let ux = (b.x - a.x) / length, uy = (b.y - a.y) / length
            arrowHead(at: b, ux: ux, uy: uy, color: .secondary, in: &context)
            context.draw(Text(names[i]).font(.callout.italic()).foregroundStyle(.secondary), at: CGPoint(x: b.x + ux * 12, y: b.y + uy * 12))
            // Ticks across the axis, numbered as often as there is room.
            let spacing = localStep * Double(length) / (box.upper[i] - box.lower[i])
            guard spacing.isFinite, spacing > 4 else { continue }
            let every = Swift.max(1, Int((26 / spacing).rounded(.up)))
            let first = Int((box.lower[i] / localStep).rounded(.up)), last = Int((box.upper[i] / localStep).rounded(.down))
            guard first <= last, last - first < 400 else { continue }
            for k in first...last where k != 0 {
                var p = [0.0, 0, 0]
                p[i] = Double(k) * localStep
                let q = point(p)
                var tick = Path()
                tick.move(to: CGPoint(x: q.x - uy * 3, y: q.y + ux * 3))
                tick.addLine(to: CGPoint(x: q.x + uy * 3, y: q.y - ux * 3))
                context.stroke(tick, with: .color(.secondary.opacity(0.8)), lineWidth: 1)
                guard k % every == 0, Double(k) * localStep < box.upper[i] - localStep * 0.3 else { continue }
                // roundNoise, not clean: a tick of a tiny drawing (10⁻²⁰) is not zero.
                context.draw(Text(NumberFormatting.plain(NumericCalculus.roundNoise(Double(k) * step))).font(.caption2).foregroundStyle(.secondary),
                             at: CGPoint(x: q.x - uy * 11, y: q.y + ux * 11))
            }
        }
    }

    /// Planes and polygons, filled from back to front.
    private func drawFills(in context: inout GraphicsContext) {
        var fills: [(corners: [[Double]], color: Color, outline: Bool, label: String?)] = []
        for item in sketch.planes {
            let corners = Sketch3D.section(item.plane, in: box)
            if !corners.isEmpty { fills.append((corners, item.color, true, item.label)) }
        }
        for item in sketch.polygons where item.corners.count >= 3 { fills.append((item.corners, item.color, false, nil)) }
        for fill in fills.sorted(by: { Sketch3D.depth($0.corners, view) < Sketch3D.depth($1.corners, view) }) {
            let shape = path(fill.corners, closed: true)
            context.fill(shape, with: .color(fill.color.opacity(0.16)))
            if fill.outline { context.stroke(shape, with: .color(fill.color.opacity(0.55)), lineWidth: 1) }
            if let label = fill.label, let corner = fill.corners.min(by: { point($0).y < point($1).y }) {
                let p = point(corner)
                context.draw(Text(label).font(.callout.weight(.semibold)).foregroundStyle(fill.color),
                             at: CGPoint(x: p.x + (p.x < size.width / 2 ? 14 : -14), y: p.y + 12))
            }
        }
    }

    private func drawSolid(_ solid: Solids.Solid, in context: inout GraphicsContext) {
        // A fixed blue rather than the app's accent, so the orange guides always stand apart.
        let color = Color.blue
        let middle: CGPoint
        switch solid.shape {
        case .polyhedron(let mesh):
            for face in Sketch3D.frontFaces(of: mesh, in: view) {
                context.fill(path(face, closed: true), with: .color(color.opacity(0.12)))
            }
            let edges = Sketch3D.edges(of: mesh, in: view)
            for edge in edges where !edge.visible {
                context.stroke(path([edge.start, edge.end], closed: false), with: .color(color.opacity(0.7)), style: Self.dashed)
            }
            for edge in edges where edge.visible {
                context.stroke(path([edge.start, edge.end], closed: false), with: .color(color),
                               style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            }
            let screen = mesh.vertices.map(point)
            middle = CGPoint(x: screen.map(\.x).reduce(0, +) / Double(screen.count), y: screen.map(\.y).reduce(0, +) / Double(screen.count))
            for (k, label) in solid.labels.enumerated() where k < screen.count && !label.isEmpty {
                text(label, at: screen[k], awayFrom: middle, color: .primary, in: &context)
            }
        case .sphere(let r):
            let c = point([0, 0, 0])
            let radius = r * scale
            let outline = Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: 2 * radius, height: 2 * radius))
            context.fill(outline, with: .color(color.opacity(0.12)))
            context.stroke(outline, with: .color(color), lineWidth: 1.8)
            // The equator: its front half solid, the back half dashed.
            let steps = 144
            let circle = (0...steps).map { k -> [Double] in
                let t = 2 * Double.pi * Double(k) / Double(steps)
                return [r * cos(t), r * sin(t), 0]
            }
            var front = Path(), back = Path()
            for k in 0..<steps {
                let a = point(circle[k]), b = point(circle[k + 1])
                if Sketch3D.depth([circle[k], circle[k + 1]], view) >= 0 {
                    front.move(to: a)
                    front.addLine(to: b)
                } else {
                    back.move(to: a)
                    back.addLine(to: b)
                }
            }
            context.stroke(back, with: .color(color.opacity(0.7)), style: Self.dashed)
            context.stroke(front, with: .color(color), lineWidth: 1.4)
            middle = c
        }
        for guide in solid.guides {
            context.stroke(path([guide.start, guide.end], closed: false), with: .color(.orange), style: Self.dashed)
            midLabel(guide.label, guide.start, guide.end, color: .orange, in: &context)
        }
        for mark in solid.marks {
            text(mark.label, at: point(mark.position), awayFrom: middle, color: color, italic: true, in: &context)
        }
    }

    private func drawArrow(_ item: SpaceSketch.Arrow, in context: inout GraphicsContext) {
        let a = point(item.from), b = point(item.to)
        let length = hypot(b.x - a.x, b.y - a.y)
        var shaft = Path()
        shaft.move(to: a)
        shaft.addLine(to: b)
        context.stroke(shaft, with: .color(item.color), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        if length > 1 {
            arrowHead(at: b, ux: (b.x - a.x) / length, uy: (b.y - a.y) / length, color: item.color, in: &context)
        }
        if let label = item.label {
            let ux = length > 1 ? (b.x - a.x) / length : 0, uy = length > 1 ? (b.y - a.y) / length : -1
            context.draw(Text(label).font(.callout.weight(.semibold)).foregroundStyle(item.color),
                         at: CGPoint(x: b.x + ux * 14 - uy * 8, y: b.y + uy * 14 + ux * 8))
        }
    }

    private func arrowHead(at tip: CGPoint, ux: Double, uy: Double, color: Color, in context: inout GraphicsContext) {
        var head = Path()
        head.move(to: tip)
        head.addLine(to: CGPoint(x: tip.x - ux * 10 - uy * 4, y: tip.y - uy * 10 + ux * 4))
        head.addLine(to: CGPoint(x: tip.x - ux * 10 + uy * 4, y: tip.y - uy * 10 - ux * 4))
        head.closeSubpath()
        context.fill(head, with: .color(color))
    }

    /// A label beside the middle of a segment.
    private func midLabel(_ label: String, _ from: [Double], _ to: [Double], color: Color, in context: inout GraphicsContext) {
        let a = point(from), b = point(to)
        let length = Swift.max(hypot(b.x - a.x, b.y - a.y), 1)
        let normal = CGPoint(x: -(b.y - a.y) / length, y: (b.x - a.x) / length)
        let m = CGPoint(x: (a.x + b.x) / 2 + normal.x * 11, y: (a.y + b.y) / 2 + normal.y * 11)
        context.draw(Text(label).font(.caption.italic().weight(.semibold)).foregroundStyle(color), at: m)
    }

    /// A label next to a point, pushed away from another (the middle of the figure).
    private func text(_ label: String, at p: CGPoint, awayFrom q: CGPoint, color: Color, italic: Bool = false, in context: inout GraphicsContext) {
        let dx = p.x - q.x, dy = p.y - q.y
        let length = Swift.max(hypot(dx, dy), 1)
        let position = CGPoint(x: p.x + dx / length * 12, y: p.y + dy / length * 12)
        context.draw(Text(label).font(italic ? .callout.italic() : .caption.weight(.semibold)).foregroundStyle(color), at: position)
    }
}
