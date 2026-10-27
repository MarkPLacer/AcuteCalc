import AcuteCore
import Foundation
import Observation
import QuartzCore
import simd

nonisolated enum SurfaceKind: Int32, CaseIterable, Identifiable, Codable, Sendable {
    case heightField = 0
    case revolution = 1
    case complexModulus = 2
    case complexReal = 3
    case complexImaginary = 4

    var id: Int32 { rawValue }

    var title: String {
        switch self {
        case .heightField: "z = f(x, y)"
        case .revolution: "Vrtenina"
        case .complexModulus: "|f(z)|"
        case .complexReal: "Re f(z)"
        case .complexImaginary: "Im f(z)"
        }
    }

    var isComplex: Bool { rawValue >= 2 }
}

nonisolated enum SurfaceColorMode: Int32, CaseIterable, Identifiable, Codable, Sendable {
    case height = 0, solid = 1, phase = 2
    var id: Int32 { rawValue }
    var title: String {
        switch self {
        case .height: "Višina"
        case .solid: "Enobarvno"
        case .phase: "Faza (arg)"
        }
    }
}

/// State of a 3D surface plot: compiled function, domain, camera and appearance.
@Observable
final class SurfaceModel {
    private(set) var expression: Expr?
    private(set) var program: Program?
    var kind: SurfaceKind = .heightField { didSet { recompile() } }
    var colorMode: SurfaceColorMode = .height { didSet { requestRedraw?() } }
    var parameters: [String: Double] = [:] { didSet { recompile() } }
    /// The workspace assigns it on every apply, also on a parameter tick: an unchanged domain keeps its z range.
    var domain = SIMD4<Double>(-4, 4, -4, 4) { didSet { if domain != oldValue { updateZRange(); requestRedraw?() } } }
    var zRange = SIMD2<Double>(-1, 1)
    var zScale: Double = 0.75 { didSet { requestRedraw?() } }
    var autoZ = true { didSet { updateZRange(); requestRedraw?() } }
    var showGrid = true { didSet { requestRedraw?() } }
    var resolution = 160 { didSet { requestRedraw?() } }
    var baseColor: RGBA = .rgba(0.0, 0.66, 1.0)
    private(set) var errorMessage: String?

    // Camera (orbit around the origin)
    var yaw: Double = 0.75
    var pitch: Double = 0.55
    var distance: Double = 4.2

    @ObservationIgnored var requestRedraw: (() -> Void)?
    @ObservationIgnored var setContinuousRendering: ((Bool) -> Void)?
    @ObservationIgnored private var angularVelocity = SIMD2<Double>(0, 0)
    @ObservationIgnored private var lastStep: CFTimeInterval = 0
    /// Samplings of the z range so far (up to 49 × 49 evaluations on the CPU each); tests count them.
    @ObservationIgnored private(set) var zRangeSamplings = 0

    var parameterNames: [String] { parameters.keys.sorted() }

    func setFunction(_ expr: Expr, parameters: [String: Double]? = nil) {
        expression = expr
        // Assigning the parameters compiles the new expression (their didSet); compiling it once more
        // would sample the z range a second time.
        if let parameters { self.parameters = parameters } else { recompile() }
    }

    private func recompile() {
        guard let expression else { program = nil; return }
        var slots: [String: VariableSlot] = [:]
        if kind.isComplex {
            slots["z"] = .z
        } else {
            slots["x"] = .x
            slots["y"] = .y
        }
        for (i, name) in parameterNames.enumerated() { slots[name] = .parameter(i) }
        do {
            program = try BytecodeCompiler(slots: slots, complexMode: kind.isComplex).compile(expression)
            errorMessage = nil
        } catch {
            program = nil
            errorMessage = error.localizedDescription
        }
        updateZRange()
        requestRedraw?()
    }

    /// Robust automatic z range from a coarse CPU sampling (ignores spikes near poles).
    func updateZRange() {
        guard autoZ, let program else { return }
        zRangeSamplings += 1
        let params = parameterNames.map { parameters[$0] ?? 0 }
        var values: [Double] = []
        let n = 48
        switch kind {
        case .heightField:
            let vm = RealVM(program: program, parameters: params)
            for i in 0...n {
                for j in 0...n {
                    let x = domain.x + (domain.y - domain.x) * Double(i) / Double(n)
                    let y = domain.z + (domain.w - domain.z) * Double(j) / Double(n)
                    let v = vm.evaluate(x: x, y: y)
                    if v.isFinite { values.append(v) }
                }
            }
        case .revolution:
            let vm = RealVM(program: program, parameters: params)
            for i in 0...n {
                let x = domain.x + (domain.y - domain.x) * Double(i) / Double(n)
                let v = vm.evaluate(x: x)
                if v.isFinite { values.append(abs(v)); values.append(-abs(v)) }
            }
        case .complexModulus, .complexReal, .complexImaginary:
            let vm = ComplexVM(program: program, parameters: params.map { Complex($0, 0) })
            for i in 0...n {
                for j in 0...n {
                    let x = domain.x + (domain.y - domain.x) * Double(i) / Double(n)
                    let y = domain.z + (domain.w - domain.z) * Double(j) / Double(n)
                    let w = vm.evaluate(z: Complex(x, y))
                    let v = kind == .complexModulus ? w.magnitude : (kind == .complexReal ? w.re : w.im)
                    if v.isFinite { values.append(v) }
                }
            }
        }
        guard values.count > 8 else { zRange = SIMD2(-1, 1); return }
        values.sort()
        var lo = values[Int(Double(values.count - 1) * 0.02)]
        var hi = values[Int(Double(values.count - 1) * 0.98)]
        if kind == .complexModulus { lo = 0 }
        if hi - lo < 1e-9 { lo -= 1; hi += 1 }
        let pad = (hi - lo) * 0.05
        zRange = SIMD2(lo - pad, hi + pad)
    }

    // MARK: Camera

    func viewProjection(aspect: Float) -> simd_float4x4 {
        let projection = Matrix4.perspective(fovyRadians: 0.72, aspect: aspect, near: 0.05, far: 50)
        let view = Matrix4.lookAt(eye: eyePosition, center: SIMD3<Float>(0, 0, 0), up: SIMD3<Float>(0, 1, 0))
        return projection * view
    }

    var eyePosition: SIMD3<Float> {
        let d = Float(distance)
        let cp = Float(cos(pitch))
        return SIMD3<Float>(d * cp * Float(sin(yaw)), d * Float(sin(pitch)), d * cp * Float(cos(yaw)))
    }

    func rotate(by delta: CGSize) {
        yaw -= Double(delta.width) * 0.008
        pitch = min(1.45, max(-1.45, pitch + Double(delta.height) * 0.008))
        requestRedraw?()
    }

    func zoom(by factor: Double) {
        distance = min(20, max(1.4, distance / factor))
        requestRedraw?()
    }

    func resetCamera() {
        yaw = 0.75
        pitch = 0.55
        distance = 4.2
        requestRedraw?()
    }

    func startInertia(_ velocity: CGPoint) {
        angularVelocity = SIMD2(Double(velocity.x), Double(velocity.y)) * 0.008
        lastStep = CACurrentMediaTime()
        if (angularVelocity * angularVelocity).sum().squareRoot() > 0.2 { setContinuousRendering?(true) }
    }

    func stopInertia() { angularVelocity = .zero }

    func stepAnimation() {
        let now = CACurrentMediaTime()
        let dt = min(max(now - lastStep, 0), 1.0 / 30)
        lastStep = now
        guard (angularVelocity * angularVelocity).sum().squareRoot() > 0.05 else {
            // Only called while continuous rendering is on: switch it off even when a grab
            // already zeroed the velocity, or the view keeps drawing at 120 Hz.
            angularVelocity = .zero
            setContinuousRendering?(false)
            return
        }
        yaw -= angularVelocity.x * dt
        pitch = min(1.45, max(-1.45, pitch + angularVelocity.y * dt))
        angularVelocity *= exp(-dt * 3.2)
    }
}

/// Minimal matrix helpers (right-handed, Metal clip space z ∈ [0, 1]).
enum Matrix4 {
    static func perspective(fovyRadians: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let y = 1 / tan(fovyRadians * 0.5)
        let x = y / max(aspect, 0.01)
        let z = far / (near - far)
        return simd_float4x4(columns: (
            SIMD4<Float>(x, 0, 0, 0),
            SIMD4<Float>(0, y, 0, 0),
            SIMD4<Float>(0, 0, z, -1),
            SIMD4<Float>(0, 0, z * near, 0)
        ))
    }

    static func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let f = simd_normalize(center - eye)
        let s = simd_normalize(simd_cross(f, up))
        let u = simd_cross(s, f)
        return simd_float4x4(columns: (
            SIMD4<Float>(s.x, u.x, -f.x, 0),
            SIMD4<Float>(s.y, u.y, -f.y, 0),
            SIMD4<Float>(s.z, u.z, -f.z, 0),
            SIMD4<Float>(-simd_dot(s, eye), -simd_dot(u, eye), simd_dot(f, eye), 1)
        ))
    }
}
