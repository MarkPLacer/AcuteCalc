import Accessibility
import AcuteCore
import SwiftUI

/// VoiceOver text for the 3D view, which is a Metal view with drawn numbers that VoiceOver cannot read: the
/// surface, the ranges the box spans and where the camera is. The function reads as in the list (MathAccessibility).
enum SurfaceAccessibility {
    /// One camera step of the VoiceOver actions: 15°.
    static let step = Double.pi / 12

    /// "Prostorski graf", or "Kompleksna pokrajina" for |f|, Re f and Im f (ℂ › 3D uses the same view).
    static func title(_ kind: SurfaceKind) -> String {
        kind.isComplex ? "Kompleksna pokrajina" : "Prostorski graf"
    }

    /// "z = x; x od −4 do 4; y od −4 do 4; z od −4,4 do 4,4": the function with a spoken prefix for its kind (not
    /// `SurfaceKind.title`, which is "|f(z)|"), the domain and the range of the vertical axis.
    static func summary(_ model: SurfaceModel, style: MathStyle) -> String {
        guard let expression = model.expression else { return "Brez funkcije" }
        let f = MathAccessibility.label(MathRowConverter.row(for: expression), style: style)
        let d = model.domain
        let xs = range(d.x, d.y, style: style)
        let ys = range(d.z, d.w, style: style)
        let zs = range(model.zRange.x, model.zRange.y, style: style)
        let parts: [String]
        switch model.kind {
        case .heightField:
            parts = ["z = \(f)", "x \(xs)", "y \(ys)", "z \(zs)"]
        case .implicit:
            // There z spans the x domain (SurfaceModel.updateZRange), so it is not repeated.
            parts = ["\(f) = 0", "x \(xs)", "y \(ys)"]
        case .revolution:
            parts = ["vrtenina krivulje y = \(f) okoli osi x", "x \(xs)", "polmer do \(number(model.zRange.y, style: style))"]
        case .complexModulus:
            parts = ["absolutna vrednost funkcije f(z) = \(f)", "Re z \(xs)", "Im z \(ys)", "višina \(zs)"]
        case .complexReal:
            parts = ["realni del funkcije f(z) = \(f)", "Re z \(xs)", "Im z \(ys)", "višina \(zs)"]
        case .complexImaginary:
            parts = ["imaginarni del funkcije f(z) = \(f)", "Re z \(xs)", "Im z \(ys)", "višina \(zs)"]
        }
        return parts.joined(separator: "; ")
    }

    /// "zasuk 43°, naklon 32°, povečava 100 %": where the camera looks from, relative to the start.
    static func camera(_ model: SurfaceModel) -> String {
        func degrees(_ radians: Double) -> Int { Int((radians * 180 / .pi).rounded()) }
        let turn = (degrees(model.yaw) % 360 + 360) % 360
        let zoom = Int((SurfaceModel.defaultDistance / model.distance * 100).rounded())
        return "zasuk \(turn)°, naklon \(degrees(model.pitch))°, povečava \(zoom) %"
    }

    /// "od −4 do 4", in spoken numbers with three significant digits.
    static func range(_ lower: Double, _ upper: Double, style: MathStyle) -> String {
        "od \(number(lower, style: style)) do \(number(upper, style: style))"
    }

    static func number(_ value: Double, style: MathStyle) -> String {
        let options = NumberFormatOptions(mode: .norm1, significantDigits: 3, decimalSeparator: style.decimalSeparator)
        return MathAccessibility.number(NumberFormatting.format(value, options: options))
    }
}

/// Invisible layer over the 3D view for VoiceOver, like GraphAccessibilityLayer: one element with the surface and
/// the camera. Swiping up or down turns the camera by 15°, and VoiceOver reads the value, which ends with the
/// camera. The actions raise, lower, zoom and reset it, which otherwise need a drag, a pinch or a double tap.
struct SurfaceAccessibilityLayer: View {
    let model: SurfaceModel
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let summary = SurfaceAccessibility.summary(model, style: MathAccessibility.style(settings))
        let value = summary + "; " + SurfaceAccessibility.camera(model)
        Color.clear
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel(SurfaceAccessibility.title(model.kind))
            .accessibilityValue(value)
            .accessibilityHint("Vrti kamero okoli ploskve.")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: model.turn(yaw: SurfaceAccessibility.step, pitch: 0)
                case .decrement: model.turn(yaw: -SurfaceAccessibility.step, pitch: 0)
                @unknown default: break
                }
            }
            .accessibilityActions {
                Button("Dvigni kamero") { changeCamera { model.turn(yaw: 0, pitch: SurfaceAccessibility.step) } }
                Button("Spusti kamero") { changeCamera { model.turn(yaw: 0, pitch: -SurfaceAccessibility.step) } }
                Button("Povečaj") { changeCamera { model.zoom(by: 1.25) } }
                Button("Pomanjšaj") { changeCamera { model.zoom(by: 0.8) } }
                Button("Ponastavi kamero") { changeCamera { model.resetCamera() } }
            }
    }

    /// VoiceOver reads the value after a swipe but not after an action, so an action announces the new camera.
    private func changeCamera(_ change: () -> Void) {
        change()
        AccessibilityNotification.Announcement(SurfaceAccessibility.camera(model)).post()
    }
}
