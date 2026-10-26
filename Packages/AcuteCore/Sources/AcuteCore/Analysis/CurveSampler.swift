import Foundation

/// A polyline in graph coordinates. `NaN` points separate disconnected pieces
/// (domain gaps, poles, jumps) so the renderer can upload it as one buffer.
public struct SampledCurve: Sendable {
    public var points: [SIMD2<Double>]
    /// x-range (or parameter range) that was sampled.
    public var domain: ClosedRange<Double>
    /// Units per pixel used for sampling; resample when zooming in beyond it.
    public var resolution: Double

    public init(points: [SIMD2<Double>], domain: ClosedRange<Double>, resolution: Double) {
        self.points = points
        self.domain = domain
        self.resolution = resolution
    }

    public static let breakPoint = SIMD2<Double>(.nan, .nan)
}

/// Viewport-aware adaptive sampling. Refines where the curve bends (in pixels),
/// finds domain edges by bisection and breaks at poles and jumps.
public struct CurveSampler {
    /// Graph units per screen pixel along each axis.
    public var unitsPerPixel: SIMD2<Double>
    /// Visible y-range (used to skip refinement far off screen).
    public var visibleY: ClosedRange<Double>
    public var maxPoints = 40_000
    public var maxDepth = 12
    /// Allowed deviation from a straight segment, in pixels.
    public var tolerance = 0.2

    public init(unitsPerPixel: SIMD2<Double>, visibleY: ClosedRange<Double>) {
        self.unitsPerPixel = unitsPerPixel
        self.visibleY = visibleY
    }

    // MARK: Explicit y = f(x)

    public func sampleExplicit(_ f: (Double) -> Double, over domain: ClosedRange<Double>) -> SampledCurve {
        var out: [SIMD2<Double>] = []
        out.reserveCapacity(4096)
        let width = domain.upperBound - domain.lowerBound
        let basePixels = width / unitsPerPixel.x
        let n = Swift.max(16, Swift.min(6000, Int(basePixels / 2)))
        let step = width / Double(n)
        let visibleHeight = visibleY.upperBound - visibleY.lowerBound
        let margin = visibleHeight * 2
        let farLow = visibleY.lowerBound - margin
        let farHigh = visibleY.upperBound + margin

        var x0 = domain.lowerBound
        var y0 = f(x0)
        if y0.isFinite { out.append(SIMD2(x0, y0)) }
        var budget = maxPoints

        func emitBreak() {
            if let last = out.last, !last.x.isNaN { out.append(SampledCurve.breakPoint) }
        }

        /// Finds the edge of the domain between a defined point and an undefined one.
        func domainEdge(_ defined: Double, _ undefined: Double) -> (Double, Double)? {
            var a = defined
            var b = undefined
            var fa = f(a)
            for _ in 0..<40 {
                let m = 0.5 * (a + b)
                let fm = f(m)
                if fm.isFinite { a = m; fa = fm } else { b = m }
                if Swift.abs(b - a) < unitsPerPixel.x * 1e-3 { break }
            }
            return fa.isFinite ? (a, fa) : nil
        }

        /// `parentJump` is the vertical extent (px) of the parent segment: at a jump or pole the
        /// extent does not shrink when bisecting, while for continuous curves it does.
        func refine(_ xa: Double, _ ya: Double, _ xb: Double, _ yb: Double, _ depth: Int, _ parentJump: Double = .infinity) {
            guard budget > 0 else {
                if yb.isFinite { out.append(SIMD2(xb, yb)) }
                return
            }
            let aOK = ya.isFinite
            let bOK = yb.isFinite
            if !aOK && !bOK {
                // Possibly a tiny defined island: probe the middle once at shallow depth.
                if depth < 3 {
                    let xm = 0.5 * (xa + xb)
                    let ym = f(xm)
                    if ym.isFinite {
                        refine(xa, ya, xm, ym, depth + 1)
                        refine(xm, ym, xb, yb, depth + 1)
                    }
                }
                return
            }
            if aOK != bOK {
                // Domain edges (√(r² − x²) at ±r) have vertical tangents: refine up to the exact edge
                // so semicircles meet the axis without a visible gap or kink.
                if aOK {
                    if let (ex, ey) = domainEdge(xa, xb), ex > xa {
                        refine(xa, ya, ex, ey, depth + 1)
                    }
                    emitBreak()
                } else {
                    if let (ex, ey) = domainEdge(xb, xa), ex < xb {
                        emitBreak()
                        out.append(SIMD2(ex, ey))
                        budget -= 1
                        refine(ex, ey, xb, yb, depth + 1)
                    } else {
                        out.append(SIMD2(xb, yb))
                        budget -= 1
                    }
                }
                return
            }
            // Both ends defined.
            let farAway = (ya > farHigh && yb > farHigh) || (ya < farLow && yb < farLow)
            let xm = 0.5 * (xa + xb)
            let ym = f(xm)
            if !ym.isFinite {
                refine(xa, ya, xm, ym, depth + 1)
                refine(xm, ym, xb, yb, depth + 1)
                return
            }
            let deviation = Swift.abs(ym - 0.5 * (ya + yb)) / unitsPerPixel.y
            let jumpPixels = Swift.abs(yb - ya) / unitsPerPixel.y
            // Big vertical steps are always refined so jumps (sign x, floor x) are never bridged.
            let smooth = deviation <= tolerance && jumpPixels < 40
            if depth >= maxDepth || (farAway && depth >= 2) || smooth {
                // Pole or jump: at full depth the segment still spans many pixels and the
                // extent did not shrink compared to the parent (tan x at π/2, 1/x at 0, floor x).
                if depth >= maxDepth, jumpPixels > 3, jumpPixels > 0.85 * parentJump {
                    emitBreak()
                }
                out.append(SIMD2(xb, yb))
                budget -= 1
                return
            }
            refine(xa, ya, xm, ym, depth + 1, jumpPixels)
            refine(xm, ym, xb, yb, depth + 1, jumpPixels)
        }

        for i in 1...n {
            let x1 = i == n ? domain.upperBound : domain.lowerBound + Double(i) * step
            let y1 = f(x1)
            refine(x0, y0, x1, y1, 0)
            x0 = x1
            y0 = y1
        }
        return SampledCurve(points: out, domain: domain, resolution: unitsPerPixel.x)
    }

    // MARK: Parametric (x(t), y(t)) and polar r(θ)

    public func sampleParametric(_ fx: (Double) -> Double, _ fy: (Double) -> Double, over range: ClosedRange<Double>) -> SampledCurve {
        var out: [SIMD2<Double>] = []
        out.reserveCapacity(4096)
        let n = 2000
        let step = (range.upperBound - range.lowerBound) / Double(n)
        var budget = maxPoints
        func point(_ t: Double) -> SIMD2<Double> { SIMD2(fx(t), fy(t)) }
        func pixelDistance(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
            let d = (b - a) / unitsPerPixel
            return (d.x * d.x + d.y * d.y).squareRoot()
        }
        func refine(_ ta: Double, _ pa: SIMD2<Double>, _ tb: Double, _ pb: SIMD2<Double>, _ depth: Int) {
            let aOK = pa.x.isFinite && pa.y.isFinite
            let bOK = pb.x.isFinite && pb.y.isFinite
            if !aOK || !bOK {
                if bOK {
                    if let last = out.last, !last.x.isNaN { out.append(SampledCurve.breakPoint) }
                    out.append(pb)
                } else if let last = out.last, !last.x.isNaN {
                    out.append(SampledCurve.breakPoint)
                }
                return
            }
            let tm = 0.5 * (ta + tb)
            let pm = point(tm)
            let chord = pixelDistance(pa, pb)
            let midDeviation = pm.x.isFinite ? pixelDistance(pm, 0.5 * (pa + pb)) : 0
            if budget <= 0 || depth >= maxDepth || (chord < 3 && midDeviation < tolerance) {
                if depth >= maxDepth && chord > 200 {
                    out.append(SampledCurve.breakPoint)
                }
                out.append(pb)
                budget -= 1
                return
            }
            refine(ta, pa, tm, pm, depth + 1)
            refine(tm, pm, tb, pb, depth + 1)
        }
        var t0 = range.lowerBound
        var p0 = point(t0)
        if p0.x.isFinite && p0.y.isFinite { out.append(p0) }
        for i in 1...n {
            let t1 = range.lowerBound + Double(i) * step
            let p1 = point(t1)
            refine(t0, p0, t1, p1, 0)
            t0 = t1
            p0 = p1
        }
        return SampledCurve(points: out, domain: range, resolution: unitsPerPixel.x)
    }

    public func samplePolar(_ r: (Double) -> Double, over range: ClosedRange<Double>) -> SampledCurve {
        sampleParametric({ t in r(t) * cos(t) }, { t in r(t) * sin(t) }, over: range)
    }
}
