import AcuteCore
import MetalKit
import SwiftUI
import UIKit

/// Interactive 2D graph: Metal canvas + SwiftUI axis labels and point callouts.
struct GraphCanvasView: View {
    let model: GraphCanvasModel
    var interactive = true
    var showsLabels = true
    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                GraphMetalView(model: model, backendKind: settings.rendererBackend, interactive: interactive)
                if showsLabels {
                    GraphAxisLabels(model: model, decimalSeparator: settings.decimalSeparator)
                        .allowsHitTesting(false)
                }
                GraphCallouts(model: model)
                    .allowsHitTesting(false)
            }
            .onAppear { updateSize(geometry.size) }
            .onChange(of: geometry.size) { _, size in updateSize(size) }
        }
        .onChange(of: colorScheme, initial: true) { _, scheme in
            let theme: GraphTheme = scheme == .dark ? .dark : .light
            guard model.theme != theme else { return }
            model.theme = theme
            model.requestRedraw?()
        }
        .onChange(of: settings.equalAxes, initial: true) { _, equal in
            if model.lockAspect != equal { model.lockAspect = equal }
        }
        .onChange(of: settings.trigPiAxis, initial: true) { _, enabled in
            model.piAxisEnabled = enabled
        }
    }

    private func updateSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0, model.viewport.size != size else { return }
        model.viewport.size = size
        model.viewportDidChange(final: true)
    }
}

/// Hosts the MTKView and its gesture recognisers.
struct GraphMetalView: UIViewRepresentable {
    let model: GraphCanvasModel
    let backendKind: RendererBackendKind
    var interactive = true

    func makeCoordinator() -> GraphMetalCoordinator {
        GraphMetalCoordinator(model: model)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MetalContext.shared.device)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.preferredFramesPerSecond = 120
        view.autoResizeDrawable = true
        view.isOpaque = true
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.isMultipleTouchEnabled = true
        context.coordinator.attach(to: view, backendKind: backendKind, interactive: interactive)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.updateModel(model)
        if context.coordinator.backendKind != backendKind {
            context.coordinator.attach(to: view, backendKind: backendKind, interactive: interactive)
        }
        view.setNeedsDisplay()
    }

    static func dismantleUIView(_ view: MTKView, coordinator: GraphMetalCoordinator) {
        view.delegate = nil
        view.isPaused = true
    }
}

final class GraphMetalCoordinator: NSObject, MTKViewDelegate, UIGestureRecognizerDelegate {
    private(set) var model: GraphCanvasModel
    private var backend: RenderBackend?
    private(set) var backendKind: RendererBackendKind = .metal4
    private weak var view: MTKView?
    private let encoder = Graph2DEncoder()
    private var activeGestures = 0
    private var lastPinchSpread: CGPoint?
    private var recognizers: [UIGestureRecognizer] = []

    init(model: GraphCanvasModel) {
        self.model = model
    }

    func updateModel(_ newModel: GraphCanvasModel) {
        guard newModel !== model else { return }
        model = newModel
        connectModel()
    }

    func attach(to view: MTKView, backendKind: RendererBackendKind, interactive: Bool) {
        self.view = view
        self.backendKind = backendKind
        view.delegate = self
        backend = makeRenderBackend(preferred: backendKind, view: view)
        connectModel()
        recognizers.forEach { view.removeGestureRecognizer($0) }
        recognizers = []
        guard interactive else { return }

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 2
        pan.delegate = self
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.require(toFail: doubleTap)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.25
        longPress.delegate = self
        // Apple Pencil hover (iPad Pro): trace the curve under the hovering tip.
        let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
        for r in [pan, pinch, doubleTap, tap, longPress, hover] as [UIGestureRecognizer] {
            view.addGestureRecognizer(r)
            recognizers.append(r)
        }
    }

    private func connectModel() {
        model.requestRedraw = { [weak self] in self?.view?.setNeedsDisplay() }
        model.setContinuousRendering = { [weak self] continuous in self?.setContinuous(continuous) }
        view?.setNeedsDisplay()
    }

    private func setContinuous(_ on: Bool) {
        guard let view else { return }
        view.enableSetNeedsDisplay = !on
        view.isPaused = !on
        if !on { view.setNeedsDisplay() }
    }

    // MARK: MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        view.setNeedsDisplay()
    }

    func draw(in view: MTKView) {
        if !view.isPaused { model.stepAnimation() }
        guard let backend else { return }
        let scene = model.scene
        let viewport = model.viewport
        let theme = model.theme
        let scale = Double(view.contentScaleFactor)
        let ring = backend.ring
        let kind = backend.kind
        backend.render(in: view) { gpu, info in
            encoder.encode(scene: scene, viewport: viewport, theme: theme, contentScale: scale,
                           encoder: gpu, info: info, ring: ring, backend: kind)
        }
    }

    // MARK: Gestures

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // Pan + pinch together; long-press tracing excludes panning.
        if gestureRecognizer is UILongPressGestureRecognizer || other is UILongPressGestureRecognizer { return false }
        return true
    }

    private func beginInteraction() {
        activeGestures += 1
        model.stopInertia()
        setContinuous(true)
    }

    private func endInteraction() {
        activeGestures = max(0, activeGestures - 1)
        if activeGestures == 0 {
            setContinuous(false)
            model.viewportDidChange(final: true)
        }
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard let view else { return }
        switch recognizer.state {
        case .began:
            beginInteraction()
        case .changed:
            let t = recognizer.translation(in: view)
            model.viewport.pan(byPoints: CGSize(width: t.x, height: t.y))
            recognizer.setTranslation(.zero, in: view)
            model.viewportDidChange(final: false)
        case .ended:
            let v = recognizer.velocity(in: view)
            activeGestures = max(0, activeGestures - 1)
            if activeGestures == 0 {
                model.startInertia(velocityPoints: v)
                if hypot(Double(v.x), Double(v.y)) <= 40 { endInteractionAfterInertia() }
            }
        case .cancelled, .failed:
            endInteraction()
        default:
            break
        }
    }

    private func endInteractionAfterInertia() {
        setContinuous(false)
        model.viewportDidChange(final: true)
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        guard let view else { return }
        switch recognizer.state {
        case .began:
            beginInteraction()
            lastPinchSpread = spread(recognizer, in: view)
        case .changed:
            let anchor = recognizer.location(in: view)
            var factor = SIMD2<Double>(Double(recognizer.scale), Double(recognizer.scale))
            // With free axes, pinching along one axis stretches only that axis (like Desmos).
            if !model.lockAspect, recognizer.numberOfTouches == 2, let last = lastPinchSpread {
                let now = spread(recognizer, in: view)
                if abs(last.x) > 30 && abs(last.y) < 30 && abs(now.y) < 40 {
                    factor = SIMD2(Double(abs(now.x) / max(abs(last.x), 1)), 1)
                } else if abs(last.y) > 30 && abs(last.x) < 30 && abs(now.x) < 40 {
                    factor = SIMD2(1, Double(abs(now.y) / max(abs(last.y), 1)))
                }
                lastPinchSpread = now
            }
            model.viewport.zoom(by: factor, around: anchor)
            recognizer.scale = 1
            model.viewportDidChange(final: false)
        case .ended, .cancelled, .failed:
            lastPinchSpread = nil
            endInteraction()
        default:
            break
        }
    }

    private func spread(_ recognizer: UIPinchGestureRecognizer, in view: UIView) -> CGPoint {
        guard recognizer.numberOfTouches >= 2 else { return .zero }
        let a = recognizer.location(ofTouch: 0, in: view)
        let b = recognizer.location(ofTouch: 1, in: view)
        return CGPoint(x: b.x - a.x, y: b.y - a.y)
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard let view else { return }
        model.viewport.zoom(by: SIMD2(2, 2), around: recognizer.location(in: view))
        model.viewportDidChange(final: true)
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard let view else { return }
        _ = model.selectPoint(near: recognizer.location(in: view))
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard let view else { return }
        switch recognizer.state {
        case .began, .changed:
            model.trace(at: recognizer.location(in: view))
        default:
            break
        }
    }

    @objc private func handleHover(_ recognizer: UIHoverGestureRecognizer) {
        guard let view else { return }
        switch recognizer.state {
        case .began, .changed:
            model.trace(at: recognizer.location(in: view))
        default:
            break
        }
    }
}

// MARK: - Axis labels

/// Anything that exposes a 2D viewport and theme for axis labels.
protocol GraphViewportSource: AnyObject {
    var viewport: GraphViewport { get }
    var theme: GraphTheme { get }
    /// Label the x axis in multiples of π.
    var piAxis: Bool { get }
}

extension GraphViewportSource {
    var piAxis: Bool { false }
}

struct GraphAxisLabels<Source: GraphViewportSource>: View {
    let model: Source
    let decimalSeparator: String

    var body: some View {
        Canvas { context, size in
            let viewport = model.viewport
            let spacingX = model.piAxis ? GridSpacing.choosePi(scale: viewport.scale.x) : GridSpacing.choose(scale: viewport.scale.x)
            let spacingY = GridSpacing.choose(scale: viewport.scale.y)
            let origin = viewport.point(for: .zero)
            let labelColor = Color(.sRGB, red: Double(model.theme.label.x), green: Double(model.theme.label.y), blue: Double(model.theme.label.z), opacity: Double(model.theme.label.w))
            // x labels along the x axis (or pinned to the bottom/top edge)
            let axisY = min(max(origin.y + 4, 4), size.height - 18)
            let xs = viewport.visibleX
            var x = (xs.lowerBound / spacingX.major).rounded(.up) * spacingX.major
            var guardCount = 0
            while x <= xs.upperBound && guardCount < 400 {
                guardCount += 1
                defer { x += spacingX.major }
                if abs(x) < spacingX.major * 1e-6 { continue }
                let p = viewport.point(for: SIMD2(x, 0))
                let text = Text(spacingX.inPi ? GraphAxisLabels.formatPi(x) : GraphAxisLabels.format(x, step: spacingX.major, separator: decimalSeparator))
                    .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(labelColor)
                context.draw(text, at: CGPoint(x: p.x, y: axisY), anchor: .top)
            }
            // y labels along the y axis (or pinned to the left/right edge)
            let axisX = min(max(origin.x - 5, 30), size.width - 4)
            let ys = viewport.visibleY
            var y = (ys.lowerBound / spacingY.major).rounded(.up) * spacingY.major
            guardCount = 0
            while y <= ys.upperBound && guardCount < 400 {
                guardCount += 1
                defer { y += spacingY.major }
                if abs(y) < spacingY.major * 1e-6 { continue }
                let p = viewport.point(for: SIMD2(0, y))
                let text = Text(GraphAxisLabels.format(y, step: spacingY.major, separator: decimalSeparator))
                    .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(labelColor)
                context.draw(text, at: CGPoint(x: axisX, y: p.y), anchor: .trailing)
            }
        }
    }

    /// x as a multiple of π: π/6, π/2, −π, 3π/2, 2π …
    static func formatPi(_ value: Double) -> String {
        let r = value / .pi
        for q in [1, 2, 3, 4, 6, 12] {
            let p = (r * Double(q)).rounded()
            // For x ≥ π·2⁶³ (≈ 2,9·10¹⁹) p is outside Int: the plain number label below is used.
            guard Swift.abs(r * Double(q) - p) < 1e-6, p != 0, let n = Int(exactly: Swift.abs(p)) else { continue }
            let sign = p < 0 ? "−" : ""
            let numerator = n == 1 ? "π" : "\(n)π"
            return q == 1 ? sign + numerator : sign + numerator + "/\(q)"
        }
        return String(format: "%.2f", value).replacingOccurrences(of: "-", with: "−")
    }

    static func format(_ value: Double, step: Double, separator: String) -> String {
        let magnitude = abs(value)
        if magnitude >= 1e6 || (magnitude < 1e-4 && magnitude > 0) {
            let f = NumberFormatting.format(value, options: NumberFormatOptions(mode: .norm1, significantDigits: 3, decimalSeparator: separator))
            if let e = f.exponent { return "\(f.mantissa)·10^\(e)" }
            return f.mantissa
        }
        let decimals = max(0, -Int(floor(log10(step))) + (step / pow(10, floor(log10(step))) < 1.5 ? 0 : 1))
        var text = String(format: "%.\(min(decimals, 8))f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        text = text.replacingOccurrences(of: "-", with: "−")
        return text.replacingOccurrences(of: ".", with: separator)
    }
}

// MARK: - Callouts for selected / traced points

struct GraphCallouts: View {
    let model: GraphCanvasModel
    @Environment(AppSettings.self) private var settings

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let info = model.selectedPoint ?? model.tracePoint {
                let p = model.viewport.point(for: SIMD2(info.point.x, info.point.y))
                PointCallout(info: info, isTrace: model.selectedPoint == nil, showsTangent: model.showTangent, settings: settings)
                    .fixedSize()
                    .position(x: p.x, y: max(30, p.y - 34))
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.snappy(duration: 0.2), value: model.selectedPoint)
    }
}

struct PointCallout: View {
    let info: GraphPointInfo
    let isTrace: Bool
    var showsTangent = false
    let settings: AppSettings

    var body: some View {
        VStack(spacing: 2) {
            if !isTrace {
                Text(info.point.kind.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                Text("(")
                coordinate(info.point.exactX, info.point.x)
                Text(";")
                coordinate(info.point.exactY, info.point.y)
                Text(")")
            }
            .font(.callout.monospacedDigit())
            if !isTrace, let angle = info.point.angle {
                Text("φ = " + NumberFormatting.format(angle * 180 / .pi, options: NumberFormatOptions(mode: .fix, places: 2, decimalSeparator: settings.decimalSeparator)).plainText + "°")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if isTrace, showsTangent, let k = info.slope {
                // Tangent and normal through the traced point.
                Text("t: " + line(slope: k))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("n: " + (Swift.abs(k) < 1e-12 ? "x = " + number(info.point.x) : line(slope: -1 / k)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private func number(_ value: Double) -> String {
        NumberFormatting.format(value, options: NumberFormatOptions(mode: .norm1, significantDigits: 4, decimalSeparator: settings.decimalSeparator)).plainText
    }

    /// y = kx + n through the traced point.
    private func line(slope k: Double) -> String {
        let n = info.point.y - k * info.point.x
        let intercept = Swift.abs(n) < 1e-12 ? "" : (n < 0 ? " − " : " + ") + number(Swift.abs(n))
        if Swift.abs(k) < 1e-12 { return "y = " + number(n) }
        return "y = " + number(k) + "x" + intercept
    }

    @ViewBuilder
    private func coordinate(_ exact: ExactReal?, _ value: Double) -> some View {
        if let exact, !exact.isRational || !(exact.rational?.isInteger ?? true), exact.complexity <= 8 {
            MathText(expr: exact.expr, fontSize: 15)
        } else {
            Text(NumberFormatting.format(value, options: NumberFormatOptions(mode: .norm1, significantDigits: 5, decimalSeparator: settings.decimalSeparator)).plainText)
        }
    }
}
