import Foundation

/// Vector analysis (Matematika II): gradient, divergence, curl and Laplacian, potentials of
/// conservative fields, line integrals along parametrised curves and surface integrals over
/// parametrised surfaces — the two sides of the theorems of Green, Gauss and Stokes.
/// Fields are written in x, y (and z).
public enum VectorCalculus {
    static let names = ["x", "y", "z"]

    // MARK: Differential operators

    /// div F⃗ = ∂P/∂x + ∂Q/∂y (+ ∂R/∂z)
    public static func divergence(_ field: [Expr]) throws(MathError) -> Expr {
        guard (2...3).contains(field.count) else { throw .domain("polje ima dve ali tri komponente") }
        var terms: [Expr] = []
        for (component, name) in zip(field, names) {
            terms.append(try Differentiator.derivative(of: component, withRespectTo: name))
        }
        return Simplifier.simplify(.sum(terms))
    }

    /// rot F⃗ = ∇ × F⃗; in the plane the single component ∂Q/∂x − ∂P/∂y.
    public static func curl(_ field: [Expr]) throws(MathError) -> [Expr] {
        guard (2...3).contains(field.count) else { throw .domain("polje ima dve ali tri komponente") }
        func d(_ i: Int, _ name: String) throws(MathError) -> Expr {
            try Differentiator.derivative(of: field[i], withRespectTo: name)
        }
        func difference(_ a: Expr, _ b: Expr) -> Expr { Simplifier.simplify(.sum([a, .negation(b)])) }
        let qx = try d(1, "x"), py = try d(0, "y")
        guard field.count == 3 else { return [difference(qx, py)] }
        let ry = try d(2, "y"), qz = try d(1, "z"), pz = try d(0, "z"), rx = try d(2, "x")
        return [difference(ry, qz), difference(pz, rx), difference(qx, py)]
    }

    /// Δf = ∂²f/∂x² + ∂²f/∂y² (+ ∂²f/∂z²)
    public static func laplacian(_ f: Expr, variables: [String]) throws(MathError) -> Expr {
        var terms: [Expr] = []
        for name in variables {
            terms.append(try Differentiator.derivative(of: f, withRespectTo: name, order: 2))
        }
        return Simplifier.simplify(.sum(terms))
    }

    // MARK: Conservative fields

    /// ∂Fᵢ/∂xⱼ = ∂Fⱼ/∂xᵢ at sample points: the field has a potential on simply connected regions.
    public static func isConservative(_ field: [Expr]) -> Bool {
        let n = field.count
        guard (2...3).contains(n) else { return false }
        for i in 0..<n {
            for j in (i + 1)..<n {
                guard let a = try? Differentiator.derivative(of: field[i], withRespectTo: names[j]),
                      let b = try? Differentiator.derivative(of: field[j], withRespectTo: names[i]),
                      agree(a, b) else { return false }
            }
        }
        return true
    }

    /// φ with ∇φ = F⃗: integrate P in x, then what ∂φ/∂y still lacks in y, and so on; nil when
    /// the field is not conservative or an integral has no closed form.
    public static func potential(_ field: [Expr]) -> Expr? {
        guard isConservative(field) else { return nil }
        var phi = Expr.zero
        for (i, component) in field.enumerated() {
            guard let current = try? Differentiator.derivative(of: phi, withRespectTo: names[i]) else { return nil }
            let missing = Simplifier.simplify(.sum([component, .negation(current)]))
            if agree(missing, .zero) { continue }
            guard let part = Antiderivative.integrate(missing, variable: names[i]) else { return nil }
            phi = Simplifier.simplify(.sum([phi, part]))
        }
        for (i, component) in field.enumerated() {
            guard let partial = try? Differentiator.derivative(of: phi, withRespectTo: names[i]), agree(partial, component) else { return nil }
        }
        return phi
    }

    static let samples: [[Double]] = [
        [0.37, 1.13, 0.71], [-0.83, 0.41, 1.29], [1.57, -0.62, -0.33], [2.21, 1.71, 0.53], [-1.41, -1.07, 1.83], [0.93, 2.37, -1.19],
    ]

    /// Equal at the sample points where both are defined (at least three of them).
    static func agree(_ a: Expr, _ b: Expr) -> Bool {
        var checked = 0
        for p in samples {
            let context = EvaluationContext(variables: Dictionary(uniqueKeysWithValues: zip(names, p)))
            guard let u = try? RealEvaluator.evaluate(a, context: context), let v = try? RealEvaluator.evaluate(b, context: context),
                  u.isFinite, v.isFinite else { continue }
            guard Swift.abs(u - v) <= 1e-9 * Swift.max(1, Swift.abs(u), Swift.abs(v)) else { return false }
            checked += 1
        }
        return checked >= 3
    }

    // MARK: Line integrals

    /// F⃗(r⃗(t))·r⃗′(t): the integrand of the work (circulation) ∫_C F⃗·dr⃗ in the parameter t.
    public static func workIntegrand(_ field: [Expr], curve: [Expr], parameter t: String) throws(MathError) -> Expr {
        guard field.count == curve.count, (2...3).contains(field.count) else {
            throw .domain("polje in krivulja morata imeti enako število komponent")
        }
        var terms: [Expr] = []
        for (component, r) in zip(field, curve) {
            let dr = try Differentiator.derivative(of: r, withRespectTo: t)
            terms.append(.product([substitute(component, curve), dr]))
        }
        return Simplifier.simplify(.sum(terms))
    }

    /// f(r⃗(t))·|r⃗′(t)|: the integrand of ∫_C f ds (the length of the curve for f = 1).
    public static func arcIntegrand(_ f: Expr, curve: [Expr], parameter t: String) throws(MathError) -> Expr {
        var squares: [Expr] = []
        for r in curve {
            squares.append(.power(try Differentiator.derivative(of: r, withRespectTo: t), .int(2)))
        }
        return Simplifier.simplify(.product([substitute(f, curve), .power(.sum(squares), .frac(1, 2))]))
    }

    // MARK: Surface integrals

    /// r⃗_u × r⃗_v for a surface r⃗(u, v) in space.
    public static func normal(_ surface: [Expr], parameters u: String, _ v: String) throws(MathError) -> [Expr] {
        guard surface.count == 3 else { throw .domain("ploskev v prostoru ima tri komponente") }
        var ru: [Expr] = [], rv: [Expr] = []
        for r in surface {
            ru.append(try Differentiator.derivative(of: r, withRespectTo: u))
            rv.append(try Differentiator.derivative(of: r, withRespectTo: v))
        }
        func cross(_ i: Int, _ j: Int) -> Expr {
            Simplifier.simplify(.sum([.product([ru[i], rv[j]]), .negation(.product([ru[j], rv[i]]))]))
        }
        return [cross(1, 2), cross(2, 0), cross(0, 1)]
    }

    /// F⃗(r⃗(u, v))·(r⃗_u × r⃗_v): the integrand of the flux ∬_S F⃗·dS⃗.
    public static func fluxIntegrand(_ field: [Expr], surface: [Expr], parameters u: String, _ v: String) throws(MathError) -> Expr {
        guard field.count == 3 else { throw .domain("polje v prostoru ima tri komponente") }
        let n = try normal(surface, parameters: u, v)
        return Simplifier.simplify(.sum(zip(field, n).map { Expr.product([substitute($0, surface), $1]) }))
    }

    /// f(r⃗(u, v))·|r⃗_u × r⃗_v|: the integrand of ∬_S f dS (the area for f = 1).
    public static func areaIntegrand(_ f: Expr, surface: [Expr], parameters u: String, _ v: String) throws(MathError) -> Expr {
        let n = try normal(surface, parameters: u, v)
        return Simplifier.simplify(.product([substitute(f, surface), .power(.sum(n.map { Expr.power($0, .int(2)) }), .frac(1, 2))]))
    }

    // MARK: Integration

    /// ∫ₐᵇ g(t) dt numerically and, when g has an antiderivative in closed form, exactly.
    public static func integrate(_ g: Expr, parameter t: String, from a: Expr, to b: Expr) throws(MathError) -> (value: Double, exact: Expr?) {
        let lower = try RealEvaluator.evaluate(a)
        let upper = try RealEvaluator.evaluate(b)
        let f = FunctionAnalyzer.makeFunction(g, variable: t, context: EvaluationContext())
        let value = NumericCalculus.clean(try Integrator.integrate(f, from: lower, to: upper))
        guard value.isFinite else { throw .domain("integral ne konvergira") }
        var exact: Expr?
        if let G = Antiderivative.integrate(g, variable: t) {
            let candidate = Simplifier.simplify(.sum([G.substituting(t, with: b), .negation(G.substituting(t, with: a))]))
            if candidate.freeVariables.isEmpty, let v = try? RealEvaluator.evaluate(candidate),
               Swift.abs(v - value) <= 1e-8 * Swift.max(1, Swift.abs(value)) {
                exact = candidate
            }
        }
        return (value, exact)
    }

    /// x, y and z replaced by the components at once (a component may itself contain x).
    static func substitute(_ e: Expr, _ point: [Expr]) -> Expr {
        var result = e
        for (i, name) in names.prefix(point.count).enumerated() { result = result.substituting(name, with: .variable("⟨\(i)⟩")) }
        for (i, value) in point.enumerated() { result = result.substituting("⟨\(i)⟩", with: value) }
        return result
    }
}

/// A spherical triangle (Geodezija): the sides a, b, c are central angles and α, β, γ the angles
/// opposite to them, all in radians.
public struct SphericalTriangle: Sendable, Hashable {
    public var a: Double
    public var b: Double
    public var c: Double
    public var alpha: Double
    public var beta: Double
    public var gamma: Double

    /// The spherical excess ε = α + β + γ − π; the area on a sphere of radius R is R²ε.
    public var excess: Double { alpha + beta + gamma - .pi }

    /// From three sides (cosine rule for sides).
    public static func sides(_ a: Double, _ b: Double, _ c: Double) -> SphericalTriangle? {
        guard [a, b, c].allSatisfy({ $0 > 0 && $0 < .pi }), a + b + c < 2 * .pi, a < b + c, b < a + c, c < a + b else { return nil }
        func angle(_ opposite: Double, _ p: Double, _ q: Double) -> Double {
            acos(clamped((cos(opposite) - cos(p) * cos(q)) / (sin(p) * sin(q))))
        }
        return SphericalTriangle(a: a, b: b, c: c, alpha: angle(a, b, c), beta: angle(b, a, c), gamma: angle(c, a, b))
    }

    /// From three angles (cosine rule for angles).
    public static func angles(_ alpha: Double, _ beta: Double, _ gamma: Double) -> SphericalTriangle? {
        guard [alpha, beta, gamma].allSatisfy({ $0 > 0 && $0 < .pi }), alpha + beta + gamma > .pi,
              alpha + beta < gamma + .pi, alpha + gamma < beta + .pi, beta + gamma < alpha + .pi else { return nil }
        func side(_ opposite: Double, _ p: Double, _ q: Double) -> Double {
            acos(clamped((cos(opposite) + cos(p) * cos(q)) / (sin(p) * sin(q))))
        }
        return SphericalTriangle(a: side(alpha, beta, gamma), b: side(beta, alpha, gamma), c: side(gamma, alpha, beta),
                                 alpha: alpha, beta: beta, gamma: gamma)
    }

    /// From two sides and the angle between them: cos a = cos b cos c + sin b sin c cos α.
    public static func sides(_ b: Double, _ c: Double, included alpha: Double) -> SphericalTriangle? {
        guard alpha > 0, alpha < .pi, b > 0, b < .pi, c > 0, c < .pi else { return nil }
        return sides(acos(clamped(cos(b) * cos(c) + sin(b) * sin(c) * cos(alpha))), b, c)
    }

    /// From two angles and the side between them: cos α = −cos β cos γ + sin β sin γ cos a.
    public static func angles(_ beta: Double, _ gamma: Double, included a: Double) -> SphericalTriangle? {
        guard a > 0, a < .pi, beta > 0, beta < .pi, gamma > 0, gamma < .pi else { return nil }
        return angles(acos(clamped(-cos(beta) * cos(gamma) + sin(beta) * sin(gamma) * cos(a))), beta, gamma)
    }

    static func clamped(_ x: Double) -> Double { Swift.min(1, Swift.max(-1, x)) }
}
