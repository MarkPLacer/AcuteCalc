import AcuteCore
import Foundation

/// Everything the 2D renderer draws, in graph coordinates.
nonisolated struct GraphScene: Sendable {
    nonisolated struct Curve: Identifiable, Sendable {
        let id: String
        var points: [SIMD2<Double>]
        var color: RGBA
        /// Width in points.
        var width: Float = 3
        var dashed = false
    }

    /// A filled band between two curves sampled at the same x positions
    /// (a definite integral: lower is y = 0 or the second function).
    nonisolated struct Fill: Identifiable, Sendable {
        let id: String
        /// Triangle strip in graph coordinates (pairs of lower/upper points).
        var strip: [SIMD2<Double>]
        var color: RGBA
    }

    nonisolated struct Implicit: Identifiable, Sendable {
        let id: String
        var program: Program
        var parameters: [Float]
        var color: RGBA
        var fillColor: RGBA
        /// 0: curve only, 1: <, 2: ≤, 3: >, 4: ≥
        var mode: Int32
        var width: Float = 3
    }

    nonisolated struct Marker: Identifiable, Hashable, Sendable {
        let id: String
        var position: SIMD2<Double>
        var color: RGBA
        /// Radius in points.
        var radius: Float = 5.5
        var hollow = false
    }

    var curves: [Curve] = []
    var fills: [Fill] = []
    var implicits: [Implicit] = []
    var markers: [Marker] = []
    /// Straight dashed lines (asymptotes, tangents) as point pairs.
    var guides: [Curve] = []
    /// Grid and labels of the x axis in multiples of π (trigonometric graphs).
    var piAxis = false
    /// Linear or logarithmic axes. All the geometry above is in their plot coordinates (log₁₀ of the
    /// values on a logarithmic axis); the grid and the implicit curves are drawn for them.
    var axes = AxisScales.linear
}

/// Theme colours for graphs (dark like the original Acute Calc by default).
nonisolated struct GraphTheme: Equatable, Sendable {
    var background: RGBA
    var minorGrid: RGBA
    var majorGrid: RGBA
    var axis: RGBA
    var label: RGBA
    var showGrid = true
    var showAxes = true
    /// Curves, guides and markers are darkened to at least this contrast against the (white)
    /// background; nil draws the palette colours unchanged.
    var minimumCurveContrast: Double?

    /// The colour a curve, guide or marker is drawn with on this theme.
    func curveColor(_ color: RGBA) -> RGBA {
        guard let minimumCurveContrast else { return color }
        return color.darkened(toContrastOnWhite: minimumCurveContrast)
    }

    static let dark = GraphTheme(
        background: .rgba(0, 0, 0),
        minorGrid: .rgba(1, 1, 1, 0.07),
        majorGrid: .rgba(1, 1, 1, 0.16),
        axis: .rgba(1, 1, 1, 0.75),
        label: .rgba(1, 1, 1, 0.6)
    )

    static let light = GraphTheme(
        background: .rgba(1, 1, 1),
        minorGrid: .rgba(0, 0, 0, 0.06),
        majorGrid: .rgba(0, 0, 0, 0.14),
        axis: .rgba(0, 0, 0, 0.7),
        label: .rgba(0, 0, 0, 0.55)
    )

    /// Increase Contrast on the light theme: six of the eight curve colours have less than 3:1
    /// against white (yellow 1.4:1), so curves are darkened to 3.2:1 (WCAG 3:1 for graphics).
    static let lightIncreasedContrast = GraphTheme(
        background: .rgba(1, 1, 1),
        minorGrid: .rgba(0, 0, 0, 0.06),
        majorGrid: .rgba(0, 0, 0, 0.14),
        axis: .rgba(0, 0, 0, 0.7),
        label: .rgba(0, 0, 0, 0.55),
        minimumCurveContrast: 3.2
    )
}

/// The curve palette (first colour matches the original app's blue).
nonisolated enum GraphPalette {
    static let colors: [RGBA] = [
        .rgba(0.0, 0.66, 1.0),     // blue
        .rgba(1.0, 0.27, 0.36),    // red
        .rgba(0.20, 0.84, 0.42),   // green
        .rgba(1.0, 0.62, 0.04),    // orange
        .rgba(0.69, 0.40, 1.0),    // purple
        .rgba(1.0, 0.84, 0.04),    // yellow
        .rgba(0.35, 0.86, 0.90),   // teal
        .rgba(1.0, 0.42, 0.75),    // pink
    ]

    static func color(_ index: Int) -> RGBA { colors[((index % colors.count) + colors.count) % colors.count] }
}
