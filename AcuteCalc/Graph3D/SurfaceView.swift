import AcuteCore
import MetalKit
import SwiftUI
import UIKit

/// Encodes a surface frame: bounding box, axes and the procedural surface.
@MainActor
struct SurfaceEncoder {
    let context = MetalContext.shared

    func encode(model: SurfaceModel, encoder: GPUEncoder, info: RenderPassInfo, ring: FrameRing, backend: RendererBackendKind) {
        let aspect = Float(info.drawableSize.width / max(info.drawableSize.height, 1))
        var u = SurfaceUniforms()
        u.viewProjection = model.viewProjection(aspect: aspect)
        u.lightDirection = SIMD4<Float>(simd_normalize(SIMD3<Float>(0.4, 1.0, 0.55)), 0)
        u.cameraPosition = SIMD4<Float>(model.eyePosition, 1)
        u.domain = SIMD4<Float>(Float(model.domain.x), Float(model.domain.y), Float(model.domain.z), Float(model.domain.w))
        u.zRange = SIMD4<Float>(Float(model.zRange.x), Float(model.zRange.y), Float(model.zScale), 1)
        u.baseColor = model.baseColor
        u.resolution = Int32(max(8, min(512, model.resolution)))
        u.colorMode = model.colorMode.rawValue
        u.surfaceKind = model.kind.rawValue
        u.gridLines = model.showGrid ? Float(GridSpacing.choose(scale: 160 / max(model.domain.y - model.domain.x, 1e-9), targetPoints: 160).major) : 0
        guard let uniforms = ring.write(u) else { return }

        let spec = { (vertex: String, fragment: String, blending: Bool) in
            PipelineSpec(vertex: vertex, fragment: fragment, blending: blending, sampleCount: info.sampleCount, depth: info.hasDepth)
        }

        // Axes and bounding box
        if let axisPipeline = context.pipeline(spec("axis_vertex", "axis_fragment", true), backend: backend) {
            let vertices = SurfaceEncoder.boxVertices(scale: Float(model.zScale), kind: model.kind)
            if let geometry = ring.write(array: vertices) {
                encoder.setPipeline(axisPipeline)
                encoder.setDepthState(context.depthState(writes: false))
                encoder.bind(uniforms, at: Int(BufferIndex.frame.rawValue))
                encoder.bind(geometry, at: Int(BufferIndex.geometry.rawValue))
                encoder.draw(.line, vertexCount: vertices.count / 7)
            }
        }

        // Surface
        guard let program = model.program,
              let pipeline = context.pipeline(spec("surface_vertex", "surface_fragment", false), backend: backend) else { return }
        let instructions = program.instructions.map { BCInstruction(op: $0.op.rawValue, value: Float($0.value)) }
        var params = model.parameterNames.map { Float(model.parameters[$0] ?? 0) }
        if params.isEmpty { params = [0] }
        guard let programSlice = ring.write(array: instructions), let paramSlice = ring.write(array: params) else { return }
        var uniformsWithLength = u
        uniformsWithLength.programLength = Int32(instructions.count)
        guard let finalUniforms = ring.write(uniformsWithLength) else { return }
        encoder.setPipeline(pipeline)
        encoder.setDepthState(context.depthState(writes: true))
        encoder.setCullMode(.none)
        encoder.bind(finalUniforms, at: Int(BufferIndex.frame.rawValue))
        encoder.bind(programSlice, at: Int(BufferIndex.program.rawValue))
        encoder.bind(paramSlice, at: Int(BufferIndex.parameters.rawValue))
        let n = Int(u.resolution)
        encoder.draw(.triangle, vertexCount: (n - 1) * (n - 1) * 6)
    }

    /// Bounding box edges and the three axes, 7 floats per vertex (xyz + rgba).
    static func boxVertices(scale: Float, kind: SurfaceKind) -> [Float] {
        var v: [Float] = []
        func line(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD4<Float>) {
            v += [a.x, a.y, a.z, c.x, c.y, c.z, c.w, b.x, b.y, b.z, c.x, c.y, c.z, c.w]
        }
        let h = kind == .revolution ? Float(1) : scale
        let box = SIMD4<Float>(1, 1, 1, 0.18)
        let corners: [SIMD3<Float>] = [
            SIMD3(-1, -h, -1), SIMD3(1, -h, -1), SIMD3(1, -h, 1), SIMD3(-1, -h, 1),
            SIMD3(-1, h, -1), SIMD3(1, h, -1), SIMD3(1, h, 1), SIMD3(-1, h, 1),
        ]
        let edges = [(0, 1), (1, 2), (2, 3), (3, 0), (4, 5), (5, 6), (6, 7), (7, 4), (0, 4), (1, 5), (2, 6), (3, 7)]
        for (a, b) in edges { line(corners[a], corners[b], box) }
        // Axes through the centre: x red, y (depth) green, z (up) blue.
        line(SIMD3(-1.1, 0, 0), SIMD3(1.1, 0, 0), SIMD4(1, 0.35, 0.35, 0.9))
        line(SIMD3(0, 0, 1.1), SIMD3(0, 0, -1.1), SIMD4(0.35, 0.9, 0.45, 0.9))
        line(SIMD3(0, -h * 1.1, 0), SIMD3(0, h * 1.1, 0), SIMD4(0.4, 0.6, 1, 0.9))
        return v
    }
}

/// Interactive 3D surface (drag to orbit, pinch to zoom, double tap to reset).
struct SurfaceView: View {
    let model: SurfaceModel
    @Environment(AppSettings.self) private var settings

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            SurfaceMetalView(model: model, backendKind: settings.rendererBackend)
            SurfaceAxisLegend(model: model)
                .padding(10)
                .allowsHitTesting(false)
        }
    }
}

struct SurfaceAxisLegend: View {
    let model: SurfaceModel

    var body: some View {
        HStack(spacing: 10) {
            legend(model.kind.isComplex ? "Re z" : "x", .red)
            legend(model.kind.isComplex ? "Im z" : "y", .green)
            legend(model.kind == .revolution ? "r" : (model.kind.isComplex ? model.kind.title : "z"), .blue)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title)
        }
    }
}

struct SurfaceMetalView: UIViewRepresentable {
    let model: SurfaceModel
    let backendKind: RendererBackendKind

    func makeCoordinator() -> SurfaceCoordinator { SurfaceCoordinator(model: model) }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MetalContext.shared.device)
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.sampleCount = 4
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.preferredFramesPerSecond = 120
        context.coordinator.attach(to: view, backendKind: backendKind)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        if context.coordinator.backendKind != backendKind {
            context.coordinator.attach(to: view, backendKind: backendKind)
        }
        view.setNeedsDisplay()
    }

    static func dismantleUIView(_ view: MTKView, coordinator: SurfaceCoordinator) {
        view.delegate = nil
        view.isPaused = true
    }
}

final class SurfaceCoordinator: NSObject, MTKViewDelegate, UIGestureRecognizerDelegate {
    let model: SurfaceModel
    private var backend: RenderBackend?
    private(set) var backendKind: RendererBackendKind = .metal4
    private weak var view: MTKView?
    private let encoder = SurfaceEncoder()
    private var recognizers: [UIGestureRecognizer] = []

    init(model: SurfaceModel) {
        self.model = model
    }

    func attach(to view: MTKView, backendKind: RendererBackendKind) {
        self.view = view
        self.backendKind = backendKind
        view.delegate = self
        backend = makeRenderBackend(preferred: backendKind, view: view)
        model.requestRedraw = { [weak self] in self?.view?.setNeedsDisplay() }
        model.setContinuousRendering = { [weak self] on in
            guard let view = self?.view else { return }
            view.enableSetNeedsDisplay = !on
            view.isPaused = !on
        }
        recognizers.forEach { view.removeGestureRecognizer($0) }
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        pan.delegate = self
        pinch.delegate = self
        recognizers = [pan, pinch, doubleTap]
        recognizers.forEach { view.addGestureRecognizer($0) }
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { view.setNeedsDisplay() }

    func draw(in view: MTKView) {
        if !view.isPaused { model.stepAnimation() }
        guard let backend else { return }
        let ring = backend.ring
        let kind = backend.kind
        backend.render(in: view) { gpu, info in
            encoder.encode(model: model, encoder: gpu, info: info, ring: ring, backend: kind)
        }
    }

    @objc private func handlePan(_ r: UIPanGestureRecognizer) {
        guard let view else { return }
        switch r.state {
        case .began:
            model.stopInertia()
        case .changed:
            let t = r.translation(in: view)
            model.rotate(by: CGSize(width: t.x, height: t.y))
            r.setTranslation(.zero, in: view)
        case .ended:
            model.startInertia(r.velocity(in: view))
        default:
            break
        }
    }

    @objc private func handlePinch(_ r: UIPinchGestureRecognizer) {
        if r.state == .changed {
            model.zoom(by: Double(r.scale))
            r.scale = 1
        }
    }

    @objc private func handleDoubleTap() {
        model.resetCamera()
    }
}
