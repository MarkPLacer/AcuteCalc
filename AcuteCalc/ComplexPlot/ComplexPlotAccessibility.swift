import Accessibility
import AcuteCore
import SwiftUI

/// VoiceOver text for the ℂ domain colouring, which is a Metal view with drawn axis labels: the function and the
/// part of the plane on screen.
enum ComplexPlotAccessibility {
    /// "f(z) = z; Re z od −3 do 3; Im z od −2 do 2".
    static func summary(expression: Expr?, viewport: GraphViewport, style: MathStyle) -> String {
        guard let expression else { return "Brez funkcije" }
        let f = MathAccessibility.label(MathRowConverter.row(for: expression), style: style)
        return "f(z) = \(f); " + visibleRanges(viewport, style: style)
    }

    /// "Re z od −3 do 3; Im z od −2 do 2".
    static func visibleRanges(_ viewport: GraphViewport, style: MathStyle) -> String {
        let re = viewport.visibleX
        let im = viewport.visibleY
        let reRange = SurfaceAccessibility.range(re.lowerBound, re.upperBound, style: style)
        let imRange = SurfaceAccessibility.range(im.lowerBound, im.upperBound, style: style)
        return "Re z \(reRange); Im z \(imRange)"
    }

    /// "z = 0, f(z) = 1", formatted as in the probe callout (ComplexProbeCallout).
    static func readout(z: Complex, w: Complex, style: MathStyle) -> String {
        func text(_ c: Complex, digits: Int) -> String {
            let options = NumberFormatOptions(mode: .norm1, significantDigits: digits, decimalSeparator: style.decimalSeparator)
            return ComplexFormatting.text(unit: style.imaginaryUnit, c, options: options)
        }
        let value = w.isFinite ? text(w, digits: 5) : "∞"
        return "z = \(text(z, digits: 4)), f(z) = \(value)"
    }
}

/// Invisible layer over the ℂ plane for VoiceOver, like GraphAccessibilityLayer: one element with the function and
/// the visible part of the plane, and actions for what otherwise needs a pinch or a tap.
struct ComplexPlotAccessibilityLayer: View {
    let model: ComplexPlotModel
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let style = MathAccessibility.style(settings)
        let value = ComplexPlotAccessibility.summary(expression: model.expression, viewport: model.viewport, style: style)
        Color.clear
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel("Kompleksna ravnina")
            .accessibilityValue(value)
            .accessibilityActions {
                Button("Povečaj") { zoom(by: 1.25, style: style) }
                Button("Pomanjšaj") { zoom(by: 0.8, style: style) }
                Button("Ponastavi pogled") {
                    model.resetView()
                    announce(ComplexPlotAccessibility.visibleRanges(model.viewport, style: style))
                }
                Button("Vrednost v središču") { probeCentre(style: style) }
            }
    }

    private var centre: CGPoint {
        CGPoint(x: model.viewport.size.width / 2, y: model.viewport.size.height / 2)
    }

    /// As a pinch around the centre would.
    private func zoom(by factor: Double, style: MathStyle) {
        model.viewport.zoom(by: SIMD2(factor, factor), around: centre)
        model.requestRedraw?()
        announce(ComplexPlotAccessibility.visibleRanges(model.viewport, style: style))
    }

    /// As a tap in the centre would: the callout and »Izbrana točka« show the value, and VoiceOver reads it.
    private func probeCentre(style: MathStyle) {
        guard model.program != nil else { return }
        model.probe(at: centre)
        guard let probe = model.probeResult else { return }
        announce(ComplexPlotAccessibility.readout(z: probe.z, w: probe.w, style: style))
    }

    /// VoiceOver does not read the value after an action: the action announces what changed.
    private func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }
}
