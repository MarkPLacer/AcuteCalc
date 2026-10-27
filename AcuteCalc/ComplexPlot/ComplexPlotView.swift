import AcuteCore
import MetalKit
import Observation
import SwiftUI
import UIKit

/// Domain colouring of w = f(z) on the complex plane.
@Observable
final class ComplexPlotModel: GraphViewportSource {
    var viewport = GraphViewport(center: .zero, scale: SIMD2(60, 60), size: CGSize(width: 320, height: 320))
    var theme = GraphTheme.dark
    private(set) var expression: Expr?
    private(set) var program: Program?
    private(set) var errorMessage: String?
    var parameters: [String: Double] = [:] { didSet { recompile() } }
    var contourStrength: Double = 0.9 { didSet { requestRedraw?() } }
    var phaseLines: Double = 0.6 { didSet { requestRedraw?() } }
    var showGrid = true { didSet { requestRedraw?() } }
    /// Readout for the last tapped point.
    var probeResult: (z: Complex, w: Complex)?
    var interacting = false

    @ObservationIgnored var requestRedraw: (() -> Void)?

    var parameterNames: [String] { parameters.keys.sorted() }

    func setFunction(_ expr: Expr) {
        expression = expr
        recompile()
    }

    private func recompile() {
        guard let expression else { program = nil; return }
        var slots: [String: VariableSlot] = ["z": .z]
        for (i, name) in parameterNames.enumerated() { slots[name] = .parameter(i) }
        do {
            program = try BytecodeCompiler(slots: slots, complexMode: true).compile(expression)
            errorMessage = nil
        } catch {
            program = nil
            errorMessage = error.localizedDescription
        }
        requestRedraw?()
    }

    /// Heavy functions (ζ, Γ) render at reduced resolution while the user pans.
    var isExpensive: Bool { (program?.estimatedCost ?? 0) > 150 }

    func probe(at location: CGPoint) {
        guard let program else { return }
        let g = viewport.graphPoint(for: location)
        let z = Complex(g.x, g.y)
        let vm = ComplexVM(program: program, parameters: parameterNames.map { Complex(parameters[$0] ?? 0, 0) })
        probeResult = (z, vm.evaluate(z: z))
    }
}

@MainActor
struct ComplexEncoder {
    let context = MetalContext.shared

    func encode(model: ComplexPlotModel, encoder: GPUEncoder, info: RenderPassInfo, ring: FrameRing, backend: RendererBackendKind) {
        let size = info.drawableSize
        guard size.width > 0, size.height > 0, let program = model.program else { return }
        // Pixels per unit of the actual drawable (which may be smaller than the view while interacting).
        let drawableScale = Double(size.width) / max(Double(model.viewport.size.width), 1)
        var u = ComplexUniforms()
        u.viewportSize = SIMD2<Float>(Float(size.width), Float(size.height))
        u.pixelsPerUnit = SIMD2<Float>(Float(model.viewport.scale.x * drawableScale), Float(model.viewport.scale.y * drawableScale))
        u.center = SIMD2<Float>(Float(model.viewport.center.x), Float(model.viewport.center.y))
        let instructions = program.instructions.map { BCInstruction(op: $0.op.rawValue, value: Float($0.value)) }
        u.programLength = Int32(instructions.count)
        u.contourStrength = Float(model.contourStrength)
        u.gridStrength = Float(model.phaseLines)
        var params = model.parameterNames.map { Float(model.parameters[$0] ?? 0) }
        if params.isEmpty { params = [0] }
        guard let pipeline = context.pipeline(PipelineSpec(vertex: "complex_vertex", fragment: "complex_fragment", blending: false), backend: backend),
              let uniforms = ring.write(u), let code = ring.write(array: instructions), let paramSlice = ring.write(array: params) else { return }
        encoder.setPipeline(pipeline)
        encoder.bind(uniforms, at: Int(BufferIndex.frame.rawValue))
        encoder.bind(code, at: Int(BufferIndex.program.rawValue))
        encoder.bind(paramSlice, at: Int(BufferIndex.parameters.rawValue))
        encoder.draw(.triangle, vertexCount: 3)

        // Transparent grid and axes on top.
        guard model.showGrid, let gridPipeline = context.pipeline(PipelineSpec(vertex: "grid_vertex", fragment: "grid_fragment"), backend: backend) else { return }
        let pixelScale = model.viewport.scale * drawableScale
        var frame = FrameUniforms()
        frame.viewportSize = SIMD2<Float>(Float(size.width), Float(size.height))
        frame.pixelsPerUnit = SIMD2<Float>(Float(pixelScale.x), Float(pixelScale.y))
        let spacingX = GridSpacing.choose(scale: model.viewport.scale.x)
        let spacingY = GridSpacing.choose(scale: model.viewport.scale.y)
        func phase(_ spacing: Double, _ center: Double, _ ppu: Double) -> Float {
            Float(((center / spacing).rounded() * spacing - center) * ppu)
        }
        var grid = GridStyle()
        grid.minorColor = RGBA(0, 0, 0, 0)
        grid.majorColor = RGBA(1, 1, 1, 0.22)
        grid.axisColor = RGBA(1, 1, 1, 0.85)
        grid.majorSpacing = SIMD2<Float>(Float(spacingX.major * pixelScale.x), Float(spacingY.major * pixelScale.y))
        grid.minorSpacing = grid.majorSpacing
        grid.majorPhase = SIMD2<Float>(phase(spacingX.major, model.viewport.center.x, pixelScale.x), phase(spacingY.major, model.viewport.center.y, pixelScale.y))
        grid.minorPhase = grid.majorPhase
        grid.axisPosition = SIMD2<Float>(Float(max(-1e7, min(1e7, -model.viewport.center.x * pixelScale.x))), Float(max(-1e7, min(1e7, -model.viewport.center.y * pixelScale.y))))
        grid.showGrid = 1
        grid.showAxes = 1
        grid.lineWidth = Float(max(1, drawableScale * 0.6))
        grid.transparentBackground = 1
        // The grid shader declares the tick list of logarithmic axes; the complex plane has none, but
        // Metal validation wants every declared buffer bound.
        guard let frameSlice = ring.write(frame), let gridSlice = ring.write(grid), let tickSlice = ring.write(array: [Float(0)]) else { return }
        encoder.setPipeline(gridPipeline)
        encoder.bind(frameSlice, at: Int(BufferIndex.frame.rawValue))
        encoder.bind(gridSlice, at: Int(BufferIndex.draw.rawValue))
        encoder.bind(tickSlice, at: Int(BufferIndex.geometry.rawValue))
        encoder.draw(.triangle, vertexCount: 3)
    }
}

struct ComplexPlotView: View {
    let model: ComplexPlotModel
    @Environment(AppSettings.self) private var settings

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ComplexMetalView(model: model, backendKind: settings.rendererBackend)
                GraphAxisLabels(model: model, decimalSeparator: settings.decimalSeparator)
                    .allowsHitTesting(false)
                if let probe = model.probeResult {
                    ComplexProbeCallout(z: probe.z, w: probe.w, settings: settings)
                        .position(model.viewport.point(for: SIMD2(probe.z.re, probe.z.im)).applying(CGAffineTransform(translationX: 0, y: -40)))
                        .allowsHitTesting(false)
                }
            }
            .onAppear { model.viewport.size = geometry.size }
            .onChange(of: geometry.size) { _, size in
                model.viewport.size = size
                model.requestRedraw?()
            }
        }
    }
}

struct ComplexProbeCallout: View {
    let z: Complex
    let w: Complex
    let settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("z = \(ComplexFormatting.text(unit: settings.imaginaryUnit, z, options: NumberFormatOptions(mode: .norm1, significantDigits: 4, decimalSeparator: settings.decimalSeparator)))")
            Text("f(z) = \(w.isFinite ? ComplexFormatting.text(unit: settings.imaginaryUnit, w, options: NumberFormatOptions(mode: .norm1, significantDigits: 5, decimalSeparator: settings.decimalSeparator)) : "∞")")
            if w.isFinite {
                Text("|f| = \(NumberFormatting.format(w.magnitude, options: NumberFormatOptions(mode: .norm1, significantDigits: 4, decimalSeparator: settings.decimalSeparator)).plainText)   arg = \(NumberFormatting.format(w.argument, options: NumberFormatOptions(mode: .norm1, significantDigits: 3, decimalSeparator: settings.decimalSeparator)).plainText)")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption.monospacedDigit())
        .padding(8)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .fixedSize()
    }
}

struct ComplexMetalView: UIViewRepresentable {
    let model: ComplexPlotModel
    let backendKind: RendererBackendKind

    func makeCoordinator() -> ComplexCoordinator { ComplexCoordinator(model: model) }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MetalContext.shared.device)
        view.colorPixelFormat = .bgra8Unorm
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.preferredFramesPerSecond = 120
        // The coordinator sets the drawable size (reduced while interacting with heavy functions).
        view.autoResizeDrawable = false
        context.coordinator.attach(to: view, backendKind: backendKind)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        if context.coordinator.backendKind != backendKind {
            context.coordinator.attach(to: view, backendKind: backendKind)
        }
        context.coordinator.updateDrawableSize()
        view.setNeedsDisplay()
    }

    static func dismantleUIView(_ view: MTKView, coordinator: ComplexCoordinator) {
        view.delegate = nil
        // The backend goes away with the coordinator; let the GPU finish its frames first.
        coordinator.backend?.waitUntilIdle()
    }
}

final class ComplexCoordinator: NSObject, MTKViewDelegate, UIGestureRecognizerDelegate {
    let model: ComplexPlotModel
    /// Settable within the module so the lifetime tests can attach a stand-in backend.
    var backend: RenderBackend?
    private(set) var backendKind: RendererBackendKind = .metal4
    private weak var view: MTKView?
    private let encoder = ComplexEncoder()
    private var recognizers: [UIGestureRecognizer] = []

    init(model: ComplexPlotModel) {
        self.model = model
    }

    func attach(to view: MTKView, backendKind: RendererBackendKind) {
        self.view = view
        self.backendKind = backendKind
        view.delegate = self
        backend?.waitUntilIdle()
        backend = makeRenderBackend(preferred: backendKind, view: view)
        model.requestRedraw = { [weak self] in
            self?.updateDrawableSize()
            self?.view?.setNeedsDisplay()
        }
        recognizers.forEach { view.removeGestureRecognizer($0) }
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 2
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        pan.delegate = self
        pinch.delegate = self
        recognizers = [pan, pinch, tap]
        recognizers.forEach { view.addGestureRecognizer($0) }
        updateDrawableSize()
    }

    /// The drawable follows the view's bounds at the display scale (lower while panning a heavy
    /// function). Not the view's own contentScaleFactor: after the drawable was sized while the
    /// view still had no bounds it read back infinite, the drawable became inf × inf and the
    /// plane stayed empty.
    func updateDrawableSize() {
        guard let view, view.bounds.width > 0, view.bounds.height > 0, view.traitCollection.displayScale > 0 else { return }
        let scale = view.traitCollection.displayScale * (model.interacting && model.isExpensive ? 0.4 : 1.0)
        let size = CGSize(width: (view.bounds.width * scale).rounded(), height: (view.bounds.height * scale).rounded())
        if view.drawableSize != size { view.drawableSize = size }
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { view.setNeedsDisplay() }

    func draw(in view: MTKView) {
        // The bounds may have changed since the last layout pass that sized the drawable.
        updateDrawableSize()
        guard let backend else { return }
        let ring = backend.ring
        let kind = backend.kind
        backend.render(in: view) { gpu, info in
            encoder.encode(model: model, encoder: gpu, info: info, ring: ring, backend: kind)
        }
    }

    private func setInteracting(_ on: Bool) {
        guard model.interacting != on else { return }
        model.interacting = on
        updateDrawableSize()
        view?.setNeedsDisplay()
    }

    @objc private func handlePan(_ r: UIPanGestureRecognizer) {
        guard let view else { return }
        switch r.state {
        case .began: setInteracting(true)
        case .changed:
            let t = r.translation(in: view)
            model.viewport.pan(byPoints: CGSize(width: t.x, height: t.y))
            r.setTranslation(.zero, in: view)
            view.setNeedsDisplay()
        default: setInteracting(false)
        }
    }

    @objc private func handlePinch(_ r: UIPinchGestureRecognizer) {
        guard let view else { return }
        switch r.state {
        case .began: setInteracting(true)
        case .changed:
            model.viewport.zoom(by: SIMD2(Double(r.scale), Double(r.scale)), around: r.location(in: view))
            r.scale = 1
            view.setNeedsDisplay()
        default: setInteracting(false)
        }
    }

    @objc private func handleTap(_ r: UITapGestureRecognizer) {
        guard let view else { return }
        model.probe(at: r.location(in: view))
    }
}
