import CoreGraphics
import Foundation

/// The visible window of a 2D graph. Positions are in graph units (Double), the view in points.
nonisolated struct GraphViewport: Equatable, Sendable {
    var center = SIMD2<Double>(0, 0)
    /// Points per graph unit along x and y.
    var scale = SIMD2<Double>(48, 48)
    var size = CGSize(width: 320, height: 320)

    static let minimumScale = 1e-6
    static let maximumScale = 1e9

    var unitsPerPoint: SIMD2<Double> { SIMD2(1 / scale.x, 1 / scale.y) }

    var visibleX: ClosedRange<Double> {
        let half = Double(size.width) / 2 / scale.x
        return (center.x - half)...(center.x + half)
    }

    var visibleY: ClosedRange<Double> {
        let half = Double(size.height) / 2 / scale.y
        return (center.y - half)...(center.y + half)
    }

    /// Graph coordinates → view point (origin top-left, y down).
    func point(for p: SIMD2<Double>) -> CGPoint {
        CGPoint(x: Double(size.width) / 2 + (p.x - center.x) * scale.x,
                y: Double(size.height) / 2 - (p.y - center.y) * scale.y)
    }

    func graphPoint(for p: CGPoint) -> SIMD2<Double> {
        SIMD2(center.x + (Double(p.x) - Double(size.width) / 2) / scale.x,
              center.y - (Double(p.y) - Double(size.height) / 2) / scale.y)
    }

    /// Zooms keeping the graph point under `anchor` (a view point) fixed.
    mutating func zoom(by factor: SIMD2<Double>, around anchor: CGPoint) {
        let before = graphPoint(for: anchor)
        scale = (scale * factor).clamped(lowerBound: SIMD2(repeating: GraphViewport.minimumScale),
                                         upperBound: SIMD2(repeating: GraphViewport.maximumScale))
        let after = graphPoint(for: anchor)
        center += before - after
    }

    mutating func pan(byPoints delta: CGSize) {
        center.x -= Double(delta.width) / scale.x
        center.y += Double(delta.height) / scale.y
    }

    /// Fits a graph-space rectangle with some margin.
    mutating func fit(x: ClosedRange<Double>, y: ClosedRange<Double>, margin: Double = 0.08) {
        let w = max(x.upperBound - x.lowerBound, 1e-9)
        let h = max(y.upperBound - y.lowerBound, 1e-9)
        center = SIMD2((x.lowerBound + x.upperBound) / 2, (y.lowerBound + y.upperBound) / 2)
        scale = SIMD2(Double(size.width) / (w * (1 + 2 * margin)), Double(size.height) / (h * (1 + 2 * margin)))
    }

    /// Equal units on both axes (circles look round).
    mutating func equalizeAxes() {
        let s = min(scale.x, scale.y)
        scale = SIMD2(s, s)
    }
}

/// Grid line spacing: 1, 2, 5 × 10ᵏ in graph units, about `targetPoints` apart on screen.
nonisolated struct GridSpacing: Equatable, Sendable {
    var major: Double
    var minor: Double
    /// The steps are fractions or multiples of π (labels π/2, π, 3π/2 …).
    var inPi = false

    /// Steps of π/12 … 100π for trigonometric graphs; plain numbers when zoomed far in or out.
    static func choosePi(scale: Double, targetPoints: Double = 90) -> GridSpacing {
        let raw = targetPoints / max(scale, 1e-300) / .pi
        let steps: [(factor: Double, subdivisions: Double)] = [(1.0 / 12, 2), (1.0 / 6, 2), (1.0 / 4, 2), (1.0 / 2, 2), (1, 2), (2, 2), (4, 4), (10, 5), (20, 4), (50, 5), (100, 4)]
        guard raw >= 1.0 / 20, raw <= 100, let step = steps.first(where: { $0.factor >= raw * 0.75 }) else {
            return choose(scale: scale, targetPoints: targetPoints)
        }
        return GridSpacing(major: step.factor * .pi, minor: step.factor * .pi / step.subdivisions, inPi: true)
    }

    static func choose(scale: Double, targetPoints: Double = 90) -> GridSpacing {
        let raw = targetPoints / max(scale, 1e-300)
        let exponent = floor(log10(raw))
        let base = pow(10, exponent)
        let fraction = raw / base
        let step: Double
        let subdivisions: Double
        if fraction < 1.5 {
            step = 1; subdivisions = 5
        } else if fraction < 3.5 {
            step = 2; subdivisions = 4
        } else if fraction < 7.5 {
            step = 5; subdivisions = 5
        } else {
            step = 10; subdivisions = 5
        }
        let major = step * base
        return GridSpacing(major: major, minor: major / subdivisions)
    }
}

/// Colours in linear 0…1 RGBA used by the renderers.
typealias RGBA = SIMD4<Float>

extension SIMD4 where Scalar == Float {
    nonisolated static func rgba(_ r: Float, _ g: Float, _ b: Float, _ a: Float = 1) -> RGBA { RGBA(r, g, b, a) }

    nonisolated func withAlpha(_ a: Float) -> RGBA { RGBA(x, y, z, a) }
}
