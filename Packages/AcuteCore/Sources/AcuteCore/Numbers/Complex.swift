import Foundation

/// Double-precision complex number with the elementary and special functions the
/// calculator needs (including Γ and the Riemann ζ function).
public struct Complex: Hashable, Sendable, Codable {
    public var re: Double
    public var im: Double

    public init(_ re: Double, _ im: Double = 0) {
        self.re = re
        self.im = im
    }

    public static let zero = Complex(0, 0)
    public static let one = Complex(1, 0)
    public static let i = Complex(0, 1)

    public var isReal: Bool { im == 0 }
    public var isFinite: Bool { re.isFinite && im.isFinite }
    public var isNaN: Bool { re.isNaN || im.isNaN }
    public var magnitude: Double { hypot(re, im) }
    public var argument: Double { atan2(im, re) }
    public var conjugate: Complex { Complex(re, -im) }
    public var squaredMagnitude: Double { re * re + im * im }

    public static func polar(_ r: Double, _ theta: Double) -> Complex {
        Complex(r * Foundation.cos(theta), r * Foundation.sin(theta))
    }

    // MARK: Arithmetic

    public static func + (a: Complex, b: Complex) -> Complex { Complex(a.re + b.re, a.im + b.im) }
    public static func - (a: Complex, b: Complex) -> Complex { Complex(a.re - b.re, a.im - b.im) }
    public static prefix func - (a: Complex) -> Complex { Complex(-a.re, -a.im) }
    public static func * (a: Complex, b: Complex) -> Complex {
        Complex(a.re * b.re - a.im * b.im, a.re * b.im + a.im * b.re)
    }
    public static func * (a: Double, b: Complex) -> Complex { Complex(a * b.re, a * b.im) }
    public static func * (a: Complex, b: Double) -> Complex { Complex(a.re * b, a.im * b) }

    /// Smith's algorithm: avoids overflow for large components.
    public static func / (a: Complex, b: Complex) -> Complex {
        if abs(b.re) >= abs(b.im) {
            if b.re == 0 && b.im == 0 { return Complex(.nan, .nan) }
            let r = b.im / b.re
            let d = b.re + b.im * r
            return Complex((a.re + a.im * r) / d, (a.im - a.re * r) / d)
        } else {
            let r = b.re / b.im
            let d = b.re * r + b.im
            return Complex((a.re * r + a.im) / d, (a.im * r - a.re) / d)
        }
    }
    public static func / (a: Complex, b: Double) -> Complex { Complex(a.re / b, a.im / b) }

    public static func += (a: inout Complex, b: Complex) { a = a + b }
    public static func -= (a: inout Complex, b: Complex) { a = a - b }
    public static func *= (a: inout Complex, b: Complex) { a = a * b }

    // MARK: Elementary functions

    public static func exp(_ z: Complex) -> Complex {
        let e = Foundation.exp(z.re)
        if z.im == 0 { return Complex(e, 0) }
        return Complex(e * Foundation.cos(z.im), e * Foundation.sin(z.im))
    }

    /// Principal logarithm.
    public static func log(_ z: Complex) -> Complex {
        Complex(Foundation.log(z.magnitude), z.argument)
    }

    public static func sqrt(_ z: Complex) -> Complex {
        if z.im == 0 {
            return z.re >= 0 ? Complex(Foundation.sqrt(z.re), 0) : Complex(0, Foundation.sqrt(-z.re))
        }
        let m = z.magnitude
        let re = Foundation.sqrt((m + z.re) / 2)
        let im = Foundation.sqrt((m - z.re) / 2)
        return Complex(re, z.im < 0 ? -im : im)
    }

    public static func pow(_ base: Complex, _ exponent: Complex) -> Complex {
        if base.re == 0 && base.im == 0 {
            if exponent.re > 0 { return .zero }
            return Complex(.nan, .nan)
        }
        if exponent.im == 0, exponent.re == exponent.re.rounded(), abs(exponent.re) <= 64 {
            return powInt(base, Int(exponent.re))
        }
        return exp(exponent * log(base))
    }

    public static func powInt(_ base: Complex, _ n: Int) -> Complex {
        if n < 0 { return Complex.one / powInt(base, -n) }
        var result = Complex.one
        var b = base
        var e = n
        while e > 0 {
            if e & 1 == 1 { result = result * b }
            b = b * b
            e >>= 1
        }
        return result
    }

    public static func sin(_ z: Complex) -> Complex {
        Complex(Foundation.sin(z.re) * Foundation.cosh(z.im), Foundation.cos(z.re) * Foundation.sinh(z.im))
    }
    public static func cos(_ z: Complex) -> Complex {
        Complex(Foundation.cos(z.re) * Foundation.cosh(z.im), -Foundation.sin(z.re) * Foundation.sinh(z.im))
    }
    public static func tan(_ z: Complex) -> Complex { sin(z) / cos(z) }
    public static func sinh(_ z: Complex) -> Complex {
        Complex(Foundation.sinh(z.re) * Foundation.cos(z.im), Foundation.cosh(z.re) * Foundation.sin(z.im))
    }
    public static func cosh(_ z: Complex) -> Complex {
        Complex(Foundation.cosh(z.re) * Foundation.cos(z.im), Foundation.sinh(z.re) * Foundation.sin(z.im))
    }
    public static func tanh(_ z: Complex) -> Complex { sinh(z) / cosh(z) }

    /// asin z = −i·ln(iz + √(1 − z²))
    public static func asin(_ z: Complex) -> Complex {
        let iz = Complex.i * z
        return -Complex.i * log(iz + sqrt(Complex.one - z * z))
    }
    /// acos z = π/2 − asin z
    public static func acos(_ z: Complex) -> Complex { Complex(.pi / 2, 0) - asin(z) }
    /// atan z = (i/2)·ln((i + z)/(i − z))
    public static func atan(_ z: Complex) -> Complex {
        Complex(0, 0.5) * log((Complex.i + z) / (Complex.i - z))
    }
    public static func asinh(_ z: Complex) -> Complex { log(z + sqrt(z * z + .one)) }
    public static func acosh(_ z: Complex) -> Complex { log(z + sqrt(z + .one) * sqrt(z - .one)) }
    public static func atanh(_ z: Complex) -> Complex { 0.5 * log((.one + z) / (.one - z)) }

    // MARK: Special functions

    private static let lanczosG = 7.0
    private static let lanczosCoefficients: [Double] = [
        0.99999999999980993, 676.5203681218851, -1259.1392167224028,
        771.32342877765313, -176.61502916214059, 12.507343278686905,
        -0.13857109526572012, 9.9843695780195716e-6, 1.5056327351493116e-7,
    ]

    /// Γ(z) via the Lanczos approximation with reflection for Re z < ½.
    public static func gamma(_ z: Complex) -> Complex {
        if z.re < 0.5 {
            // Γ(z)Γ(1−z) = π / sin(πz)
            let s = sin(Complex(.pi, 0) * z)
            return Complex(.pi, 0) / (s * gamma(.one - z))
        }
        let w = z - .one
        var x = Complex(lanczosCoefficients[0], 0)
        for k in 1..<lanczosCoefficients.count {
            x += Complex(lanczosCoefficients[k], 0) / (w + Complex(Double(k), 0))
        }
        let t = w + Complex(lanczosG + 0.5, 0)
        let sqrt2pi = 2.5066282746310002
        return sqrt2pi * pow(t, w + Complex(0.5, 0)) * exp(-t) * x
    }

    /// Riemann ζ(s). Borwein's alternating-series acceleration for Re s ≥ ½,
    /// the functional equation otherwise. Accurate to ~1e−10 for |Im s| ≲ 100.
    public static func zeta(_ s: Complex) -> Complex {
        if s.re == 1 && s.im == 0 { return Complex(.infinity, 0) }
        if s.re < 0.5 {
            // ζ(s) = 2ˢ πˢ⁻¹ sin(πs/2) Γ(1−s) ζ(1−s)
            let oneMinus = Complex.one - s
            let factor = pow(Complex(2, 0), s) * pow(Complex(.pi, 0), s - .one) * sin(Complex(.pi / 2, 0) * s) * gamma(oneMinus)
            return factor * zeta(oneMinus)
        }
        let n = min(240, 30 + Int(abs(s.im) * 1.3))
        // d_k = n Σ_{i=0}^{k} (n+i−1)! 4ⁱ / ((n−i)! (2i)!), computed incrementally.
        var d = [Double](repeating: 0, count: n + 1)
        var term = 1.0 / Double(n) // i = 0: (n−1)!/n! = 1/n
        var sum = term
        d[0] = Double(n) * sum
        for i in 1...n {
            // ratio term_i / term_{i−1} = (n+i−1)(n−i+1)·4 / ((2i)(2i−1))
            term *= Double(n + i - 1) * Double(n - i + 1) * 4 / (Double(2 * i) * Double(2 * i - 1))
            sum += term
            d[i] = Double(n) * sum
        }
        var acc = Complex.zero
        for k in 0..<n {
            let sign = (k % 2 == 0) ? 1.0 : -1.0
            let kp1 = Double(k + 1)
            // (k+1)^(−s) = exp(−s·ln(k+1))
            let power = exp(-s * Foundation.log(kp1))
            acc += (sign * (d[k] - d[n])) * power
        }
        let denominator = Complex(-d[n], 0) * (Complex.one - pow(Complex(2, 0), Complex.one - s))
        return acc / denominator
    }
}

extension Complex: CustomStringConvertible {
    public var description: String { "\(re)\(im >= 0 ? "+" : "-")\(abs(im))i" }
}
