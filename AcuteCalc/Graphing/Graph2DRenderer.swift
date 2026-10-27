import AcuteCore
import Metal
import MetalKit

/// Encodes a `GraphScene` for one frame. Geometry is transformed to drawable pixels
/// relative to the view centre in double precision, so the GPU only sees small floats
/// and panning far from the origin stays perfectly sharp.
@MainActor
struct Graph2DEncoder {
    let context = MetalContext.shared

    func encode(scene: GraphScene, viewport: GraphViewport, theme: GraphTheme, contentScale: Double,
                encoder: GPUEncoder, info: RenderPassInfo, ring: FrameRing, backend: RendererBackendKind) {
        let pixelScale = viewport.scale * contentScale
        let size = SIMD2<Double>(Double(info.drawableSize.width), Double(info.drawableSize.height))
        guard size.x > 0, size.y > 0 else { return }

        let centerHigh = SIMD2<Float>(Float(viewport.center.x), Float(viewport.center.y))
        let centerLow = SIMD2<Float>(Float(viewport.center.x - Double(centerHigh.x)), Float(viewport.center.y - Double(centerHigh.y)))
        var frame = FrameUniforms()
        frame.viewportSize = SIMD2<Float>(Float(size.x), Float(size.y))
        frame.pixelsPerUnit = SIMD2<Float>(Float(pixelScale.x), Float(pixelScale.y))
        frame.centerHigh = centerHigh
        frame.centerLow = centerLow
        frame.contentScale = Float(contentScale)
        let logarithmic = [scene.axes.x == .logarithmic, scene.axes.y == .logarithmic]
        frame.logarithmic = SIMD2<Float>(logarithmic[0] ? 1 : 0, logarithmic[1] ? 1 : 0)
        guard let frameSlice = ring.write(frame) else { return }

        // 1. Background + grid + axes (analytic, one fullscreen triangle)
        if let pipeline = context.pipeline(PipelineSpec(vertex: "grid_vertex", fragment: "grid_fragment", blending: false), backend: backend) {
            let spacingX = scene.piAxis ? GridSpacing.choosePi(scale: viewport.scale.x) : GridSpacing.choose(scale: viewport.scale.x)
            let spacingY = GridSpacing.choose(scale: viewport.scale.y)
            var grid = GridStyle()
            grid.background = theme.background
            grid.minorColor = theme.minorGrid
            grid.majorColor = theme.majorGrid
            grid.axisColor = theme.axis
            grid.minorSpacing = SIMD2<Float>(Float(spacingX.minor * pixelScale.x), Float(spacingY.minor * pixelScale.y))
            grid.majorSpacing = SIMD2<Float>(Float(spacingX.major * pixelScale.x), Float(spacingY.major * pixelScale.y))
            // Pixel position of the grid line nearest to the centre (computed in Double).
            func phase(_ spacing: Double, _ center: Double, _ ppu: Double) -> Float {
                let nearest = (center / spacing).rounded() * spacing
                return Float((nearest - center) * ppu)
            }
            grid.minorPhase = SIMD2<Float>(phase(spacingX.minor, viewport.center.x, pixelScale.x), phase(spacingY.minor, viewport.center.y, pixelScale.y))
            grid.majorPhase = SIMD2<Float>(phase(spacingX.major, viewport.center.x, pixelScale.x), phase(spacingY.major, viewport.center.y, pixelScale.y))
            // A logarithmic axis has no 0 for the other axis to pass through: that one is not drawn.
            let axisX = logarithmic[0] ? -1e7 : (0 - viewport.center.x) * pixelScale.x
            let axisY = logarithmic[1] ? -1e7 : (0 - viewport.center.y) * pixelScale.y
            grid.axisPosition = SIMD2<Float>(Float(max(-1e7, min(1e7, axisX))), Float(max(-1e7, min(1e7, axisY))))
            grid.showGrid = theme.showGrid ? 1 : 0
            grid.showAxes = theme.showAxes ? 1 : 0
            grid.lineWidth = Float(max(1, contentScale * 0.6))
            grid.transparentBackground = 0
            // The lines of logarithmic axes in pixels from the centre: major x, minor x, major y, minor y.
            var lines: [Float] = []
            for axis in 0..<2 where logarithmic[axis] {
                let visible = axis == 0 ? viewport.visibleX : viewport.visibleY
                let margin = 4 / pixelScale[axis]
                let ticks = LogarithmicAxis.ticks(in: (visible.lowerBound - margin)...(visible.upperBound + margin),
                                                  pointsPerDecade: viewport.scale[axis], labels: false)
                let center = viewport.center[axis], scale = pixelScale[axis]
                let major = ticks.filter(\.isMajor).map { Float(($0.position - center) * scale) }
                let minor = ticks.filter { !$0.isMajor }.map { Float(($0.position - center) * scale) }
                lines += major + minor
                grid.tickCounts[2 * axis] = UInt32(major.count)
                grid.tickCounts[2 * axis + 1] = UInt32(minor.count)
            }
            // The tick list is bound even when empty: the pipeline declares it.
            if let gridSlice = ring.write(grid), let lineSlice = ring.write(array: lines.isEmpty ? [Float(0)] : lines) {
                encoder.setPipeline(pipeline)
                encoder.bind(frameSlice, at: Int(BufferIndex.frame.rawValue))
                encoder.bind(gridSlice, at: Int(BufferIndex.draw.rawValue))
                encoder.bind(lineSlice, at: Int(BufferIndex.geometry.rawValue))
                encoder.draw(.triangle, vertexCount: 3)
            }
        }

        // 2. Filled integral areas
        if !scene.fills.isEmpty, let pipeline = context.pipeline(PipelineSpec(vertex: "fill_vertex", fragment: "fill_fragment"), backend: backend) {
            encoder.setPipeline(pipeline)
            encoder.bind(frameSlice, at: Int(BufferIndex.frame.rawValue))
            for fill in scene.fills where fill.strip.count >= 4 {
                guard let geometry = transform(fill.strip, viewport: viewport, pixelScale: pixelScale, ring: ring) else { continue }
                var style = LineStyle()
                style.color = fill.color
                guard let styleSlice = ring.write(style) else { continue }
                encoder.bind(geometry, at: Int(BufferIndex.geometry.rawValue))
                encoder.bind(styleSlice, at: Int(BufferIndex.draw.rawValue))
                encoder.draw(.triangleStrip, vertexCount: fill.strip.count)
            }
        }

        // 3. Implicit curves and inequality regions (per pixel on the GPU)
        if !scene.implicits.isEmpty, let pipeline = context.pipeline(PipelineSpec(vertex: "grid_vertex", fragment: "implicit_fragment"), backend: backend) {
            encoder.setPipeline(pipeline)
            encoder.bind(frameSlice, at: Int(BufferIndex.frame.rawValue))
            for implicit in scene.implicits {
                let instructions = implicit.program.instructions.map { BCInstruction(op: $0.op.rawValue, value: Float($0.value)) }
                var style = ImplicitStyle()
                style.color = theme.curveColor(implicit.color)
                style.fillColor = implicit.fillColor
                style.halfWidth = implicit.width * Float(contentScale) * 0.5
                style.mode = implicit.mode
                style.programLength = Int32(instructions.count)
                style.parameterCount = Int32(implicit.parameters.count)
                let parameters = implicit.parameters.isEmpty ? [Float(0)] : implicit.parameters
                guard let styleSlice = ring.write(style),
                      let programSlice = ring.write(array: instructions),
                      let parameterSlice = ring.write(array: parameters) else { continue }
                encoder.bind(styleSlice, at: Int(BufferIndex.draw.rawValue))
                encoder.bind(programSlice, at: Int(BufferIndex.program.rawValue))
                encoder.bind(parameterSlice, at: Int(BufferIndex.parameters.rawValue))
                encoder.draw(.triangle, vertexCount: 3)
            }
        }

        // 4. Curves, guides and markers as anti-aliased capsules
        guard let linePipeline = context.pipeline(PipelineSpec(vertex: "line_vertex", fragment: "line_fragment"), backend: backend) else { return }
        encoder.setPipeline(linePipeline)
        encoder.bind(frameSlice, at: Int(BufferIndex.frame.rawValue))
        for curve in scene.guides + scene.curves where curve.points.count >= 2 {
            let dashPeriod = curve.dashed ? 14 * contentScale : 0
            guard let geometry = lineGeometry(curve.points, viewport: viewport, pixelScale: pixelScale, dashPeriod: dashPeriod, ring: ring) else { continue }
            var style = LineStyle()
            style.color = theme.curveColor(curve.color)
            style.halfWidth = curve.width * Float(contentScale) * 0.5
            style.dashPeriod = Float(dashPeriod)
            guard let styleSlice = ring.write(style) else { continue }
            encoder.bind(geometry, at: Int(BufferIndex.geometry.rawValue))
            encoder.bind(styleSlice, at: Int(BufferIndex.draw.rawValue))
            encoder.draw(.triangleStrip, vertexCount: 4, instanceCount: curve.points.count - 1)
        }
        // Markers: white halo, then the coloured dot (or ring for holes).
        for marker in scene.markers {
            let pair = [marker.position, marker.position]
            guard let geometry = lineGeometry(pair, viewport: viewport, pixelScale: pixelScale, dashPeriod: 0, ring: ring) else { continue }
            var halo = LineStyle()
            halo.color = theme.background.withAlpha(0.9)
            halo.halfWidth = (marker.radius + 2) * Float(contentScale)
            var dot = LineStyle()
            dot.color = theme.curveColor(marker.color)
            dot.halfWidth = marker.radius * Float(contentScale)
            dot.ringThickness = marker.hollow ? Float(2.2 * contentScale) : 0
            for style in [halo, dot] {
                guard let styleSlice = ring.write(style) else { continue }
                encoder.bind(geometry, at: Int(BufferIndex.geometry.rawValue))
                encoder.bind(styleSlice, at: Int(BufferIndex.draw.rawValue))
                encoder.draw(.triangleStrip, vertexCount: 4, instanceCount: 1)
            }
        }
    }

    /// Graph coordinates → drawable pixels relative to the centre (y up), NaN preserved.
    private func transform(_ points: [SIMD2<Double>], viewport: GraphViewport, pixelScale: SIMD2<Double>, ring: FrameRing) -> BufferSlice? {
        let center = viewport.center
        let limit = 4.0e6
        return ring.write(count: points.count, of: SIMD2<Float>.self) { out in
            for i in 0..<points.count {
                let p = points[i]
                if p.x.isNaN || p.y.isNaN {
                    out[i] = SIMD2<Float>(.nan, .nan)
                    continue
                }
                var q = (p - center) * pixelScale
                // Clamp far-away points so float conversion stays finite (lines keep direction).
                q.x = max(-limit, min(limit, q.x))
                q.y = max(-limit, min(limit, q.y))
                out[i] = SIMD2<Float>(Float(q.x), Float(q.y))
            }
        }
    }

    /// `transform` for line_vertex: (x, y, dash phase, 0) per point. The phase is the arc length in
    /// pixels from the start of the polyline (restarting after each NaN gap) modulo `dashPeriod`,
    /// accumulated in Double, so the dash pattern runs on across the short segments of sampled curves.
    private func lineGeometry(_ points: [SIMD2<Double>], viewport: GraphViewport, pixelScale: SIMD2<Double>,
                              dashPeriod: Double, ring: FrameRing) -> BufferSlice? {
        let center = viewport.center
        let limit = 4.0e6
        return ring.write(count: points.count, of: SIMD4<Float>.self) { out in
            var arc = 0.0
            var previous: SIMD2<Double>?
            for i in 0..<points.count {
                let p = points[i]
                if p.x.isNaN || p.y.isNaN {
                    out[i] = SIMD4<Float>(.nan, .nan, 0, 0)
                    previous = nil
                    continue
                }
                var q = (p - center) * pixelScale
                q.x = max(-limit, min(limit, q.x))
                q.y = max(-limit, min(limit, q.y))
                if let previous {
                    let d = q - previous
                    arc += (d.x * d.x + d.y * d.y).squareRoot()
                } else {
                    arc = 0
                }
                previous = q
                let phase = dashPeriod > 0 ? arc.truncatingRemainder(dividingBy: dashPeriod) : 0
                out[i] = SIMD4<Float>(Float(q.x), Float(q.y), Float(phase), 0)
            }
        }
    }
}
