import Foundation

/// WCAG 2 contrast for the Increase Contrast colour variants. The default colours stay as they
/// are; the darker variants are used only when the system setting is on.
nonisolated enum Contrast {
    /// sRGB component → linear light.
    static func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// Linear light → sRGB component.
    static func encoded(_ l: Double) -> Double {
        l <= 0.0031308 ? 12.92 * l : 1.055 * pow(l, 1 / 2.4) - 0.055
    }

    /// Relative luminance of an sRGB colour (alpha ignored).
    static func luminance(_ c: RGBA) -> Double {
        0.2126 * linear(Double(c.x)) + 0.7152 * linear(Double(c.y)) + 0.0722 * linear(Double(c.z))
    }

    /// Contrast ratio (1…21) of two opaque colours.
    static func ratio(_ a: RGBA, _ b: RGBA) -> Double {
        let la = luminance(a)
        let lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}

extension SIMD4 where Scalar == Float {
    /// The same hue, scaled down in linear light until it has at least `ratio`:1 against white
    /// (unchanged when it already has); alpha is kept.
    nonisolated func darkened(toContrastOnWhite ratio: Double) -> RGBA {
        let luminance = Contrast.luminance(self)
        // White has luminance 1: (1 + 0.05) / (L + 0.05) ≥ ratio.
        let target = 1.05 / ratio - 0.05
        guard luminance > target else { return self }
        // Luminance is linear in linear light, so one factor reaches the target exactly.
        let k = target / luminance
        func channel(_ c: Float) -> Float { Float(Contrast.encoded(Contrast.linear(Double(c)) * k)) }
        return RGBA(channel(x), channel(y), channel(z), w)
    }
}
