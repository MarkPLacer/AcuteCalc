import AcuteCore
import SwiftUI

/// Vector analysis (Matematika II): grad, div, rot, Δ and potentials of fields, line integrals
/// along parametrised curves and surface integrals (area, flux) over parametrised surfaces.
struct VectorAnalysisToolView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case field, line, surface
        var id: String { rawValue }
        var title: String {
            switch self {
            case .field: "Polje"
            case .line: "Krivuljni"
            case .surface: "Ploskovni"
            }
        }
    }

    @AppStorage("vectorAnalysisMode") private var mode: Mode = .field

    var body: some View {
        List {
            Section {
                Picker("Način", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            switch mode {
            case .field: FieldOperatorsSection()
            case .line: LineIntegralSection()
            case .surface: SurfaceIntegralSection()
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
    }
}

/// A typed component; empty text is nil without an error, `f = …` keeps the right side.
private func parseComponent(_ text: String) -> (expr: Expr?, error: String?) {
    guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return (nil, nil) }
    do {
        var expr = try Parser.parse(text)
        if case .relation(_, .equal, let rhs) = expr { expr = rhs }
        return (expr, nil)
    } catch {
        return (nil, error.errorDescription ?? error.shortDescription)
    }
}

/// Components typed in order; the optional last one may stay empty. Nil while one does not parse.
private func components(_ texts: [String], optionalLast: Bool) -> [Expr]? {
    var result: [Expr] = []
    for (i, text) in texts.enumerated() {
        if optionalLast, i == texts.count - 1, text.trimmingCharacters(in: .whitespaces).isEmpty { break }
        guard let e = parseComponent(text).expr else { return nil }
        result.append(e)
    }
    return result
}

/// The integrand of a line or surface integral with its value (and closed form when found).
nonisolated private struct IntegralResult: Equatable, Sendable {
    var integrand: Expr
    var value: Double
    var exact: Expr?
}

private struct IntegralRows: View {
    let title: String
    let integrandTitle: String
    let result: Result<IntegralResult, MathError>?

    var body: some View {
        switch result {
        case .success(let r):
            LabeledContent(integrandTitle) { MathText(expr: r.integrand, fontSize: 15) }
            ResultRow(title: title, value: r.value, exact: r.exact ?? ExactRecognizer.recognize(r.value, tolerance: 1e-9).map(\.expr))
        case .failure(let error):
            Text(error.errorDescription ?? error.shortDescription).font(.callout).foregroundStyle(.red)
        case nil:
            ProgressView()
        }
    }
}

// MARK: - Fields

private struct FieldOperatorsSection: View {
    @AppStorage("vectorFieldP") private var p = "2x*y + z"
    @AppStorage("vectorFieldQ") private var q = "x^2"
    @AppStorage("vectorFieldR") private var r = "x"
    @AppStorage("vectorScalar") private var scalar = "x^2*y + x*z"
    @State private var potential: Expr?
    @State private var conservative = false

    var body: some View {
        let P = parseComponent(p), Q = parseComponent(q), R = parseComponent(r)
        let field = components([p, q, r], optionalLast: true)
        Section {
            ExpressionInputField(title: "P =", text: $p, expr: P.expr, error: P.error)
            ExpressionInputField(title: "Q =", text: $q, expr: Q.expr, error: Q.error)
            ExpressionInputField(title: "R = (prazno za polje v ravnini)", text: $r, expr: R.expr, error: R.error)
        } header: {
            Text("Vektorsko polje F⃗ = (P, Q, R)")
        }
        if let field {
            Section {
                if let div = try? VectorCalculus.divergence(field) {
                    LabeledContent("div F⃗") { MathText(expr: div, fontSize: 17) }
                }
                if let rot = try? VectorCalculus.curl(field) {
                    LabeledContent(field.count == 2 ? "rot F⃗ = ∂Q/∂x − ∂P/∂y" : "rot F⃗") {
                        MathText(expr: rot.count == 1 ? rot[0] : .matrix(rows: rot.count, columns: 1, entries: rot), fontSize: 16)
                    }
                }
                if let potential {
                    LabeledContent("Potencial φ") { MathText(expr: .sum([potential, .variable("C")]), fontSize: 17) }
                } else {
                    Text(conservative ? "Polje je potencialno (rot F⃗ = 0), potenciala pa ne znam zapisati v zaprti obliki."
                                      : "Polje ni potencialno: rot F⃗ ≠ 0.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Odvodi polja")
            } footer: {
                Text("Potencialno polje (∇φ = F⃗) ima krivuljni integral neodvisen od poti: ∫ F⃗·dr⃗ = φ(B) − φ(A).")
            }
        }
        scalarSection
            .task(id: "\(p)|\(q)|\(r)") { await findPotential(field) }
    }

    @ViewBuilder
    private var scalarSection: some View {
        let f = parseComponent(scalar)
        Section {
            ExpressionInputField(title: "f(x, y, z) =", text: $scalar, expr: f.expr, error: f.error)
            if let fe = f.expr {
                let names = fe.dependsOn("z") ? ["x", "y", "z"] : ["x", "y"]
                if let gradient = try? Multivariable.gradient(fe, variables: names) {
                    LabeledContent("grad f") { MathText(expr: .matrix(rows: gradient.count, columns: 1, entries: gradient), fontSize: 16) }
                }
                if let laplace = try? VectorCalculus.laplacian(fe, variables: names) {
                    LabeledContent("Δf") { MathText(expr: laplace, fontSize: 17) }
                }
            }
        } header: {
            Text("Skalarno polje")
        } footer: {
            Text("Za vsako gladko polje velja rot grad f = 0 in div rot F⃗ = 0; Δf = div grad f.")
        }
    }

    private func findPotential(_ field: [Expr]?) async {
        guard let field else {
            potential = nil
            conservative = false
            return
        }
        let found = await Task.detached(priority: .userInitiated) {
            (VectorCalculus.isConservative(field), VectorCalculus.potential(field))
        }.value
        guard !Task.isCancelled else { return }
        conservative = found.0
        potential = found.1
    }
}

// MARK: - Line integrals

private struct LineIntegralSection: View {
    @AppStorage("lineCurveX") private var x = "cos(t)"
    @AppStorage("lineCurveY") private var y = "sin(t)"
    @AppStorage("lineCurveZ") private var z = ""
    @AppStorage("lineFrom") private var from = "0"
    @AppStorage("lineTo") private var to = "2pi"
    @AppStorage("lineFieldP") private var p = "-y"
    @AppStorage("lineFieldQ") private var q = "x"
    @AppStorage("lineFieldR") private var r = ""
    @AppStorage("lineScalar") private var scalar = "1"
    @State private var work: Result<IntegralResult, MathError>?
    @State private var arc: Result<IntegralResult, MathError>?
    @State private var pathIndependent: Double?

    var body: some View {
        let X = parseComponent(x), Y = parseComponent(y), Z = parseComponent(z)
        let P = parseComponent(p), Q = parseComponent(q), R = parseComponent(r), f = parseComponent(scalar)
        Section {
            ExpressionInputField(title: "x(t) =", text: $x, expr: X.expr, error: X.error)
            ExpressionInputField(title: "y(t) =", text: $y, expr: Y.expr, error: Y.error)
            ExpressionInputField(title: "z(t) = (prazno v ravnini)", text: $z, expr: Z.expr, error: Z.error)
            BoundsRow(name: "t", from: $from, to: $to)
        } header: {
            Text("Krivulja r⃗(t)")
        }
        Section {
            ExpressionInputField(title: "P =", text: $p, expr: P.expr, error: P.error)
            ExpressionInputField(title: "Q =", text: $q, expr: Q.expr, error: Q.error)
            ExpressionInputField(title: "R = (le za krivuljo v prostoru)", text: $r, expr: R.expr, error: R.error)
            IntegralRows(title: "∫ F⃗·dr⃗", integrandTitle: "F⃗(r⃗(t))·r⃗′(t)", result: work)
            if let pathIndependent {
                ResultRow(title: "φ(r⃗(b)) − φ(r⃗(a))", value: pathIndependent)
            }
        } header: {
            Text("Delo vektorskega polja F⃗ = (P, Q, R)")
        } footer: {
            Text("Za sklenjeno krivuljo v ravnini je to cirkulacija; Greenov izrek: ∮ P dx + Q dy = ∬ (∂Q/∂x − ∂P/∂y) dx dy.")
        }
        Section {
            ExpressionInputField(title: "f(x, y, z) =", text: $scalar, expr: f.expr, error: f.error)
            IntegralRows(title: "∫ f ds", integrandTitle: "f(r⃗(t))·|r⃗′(t)|", result: arc)
        } header: {
            Text("Krivuljni integral skalarnega polja")
        } footer: {
            Text("Za f = 1 je to dolžina krivulje.")
        }
        .task(id: [x, y, z, from, to, p, q, r, scalar].joined(separator: "|")) { await compute() }
    }

    private func compute() async {
        let curve = components([x, y, z], optionalLast: true)
        let field = components([p, q, r], optionalLast: true)
        let f = parseComponent(scalar).expr
        guard let curve, let a = try? Parser.parse(from), let b = try? Parser.parse(to) else {
            work = .failure(.syntax("krivulja ali meje parametra"))
            arc = work
            pathIndependent = nil
            return
        }
        work = nil
        arc = nil
        let results = await Task.detached(priority: .userInitiated) {
            () -> (Result<IntegralResult, MathError>, Result<IntegralResult, MathError>, Double?) in
            let work = LineIntegralSection.work(field, along: curve, from: a, to: b)
            let arc = LineIntegralSection.arc(f, along: curve, from: a, to: b)
            var difference: Double?
            if let field, field.count == curve.count, let phi = VectorCalculus.potential(field) {
                difference = LineIntegralSection.potentialDifference(phi, curve: curve, from: a, to: b)
            }
            return (work, arc, difference)
        }.value
        guard !Task.isCancelled else { return }
        work = results.0
        arc = results.1
        pathIndependent = results.2
    }

    /// ∫ F⃗·dr⃗ along the curve.
    nonisolated static func work(_ field: [Expr]?, along curve: [Expr], from a: Expr, to b: Expr) -> Result<IntegralResult, MathError> {
        guard let field else { return .failure(.syntax("komponente polja")) }
        do throws(MathError) {
            let g = try VectorCalculus.workIntegrand(field, curve: curve, parameter: "t")
            let result = try VectorCalculus.integrate(g, parameter: "t", from: a, to: b)
            return .success(IntegralResult(integrand: g, value: result.value, exact: result.exact))
        } catch {
            return .failure(error)
        }
    }

    /// ∫ f ds along the curve.
    nonisolated static func arc(_ f: Expr?, along curve: [Expr], from a: Expr, to b: Expr) -> Result<IntegralResult, MathError> {
        guard let f else { return .failure(.syntax("f")) }
        do throws(MathError) {
            let g = try VectorCalculus.arcIntegrand(f, curve: curve, parameter: "t")
            let result = try VectorCalculus.integrate(g, parameter: "t", from: a, to: b)
            return .success(IntegralResult(integrand: g, value: result.value, exact: result.exact))
        } catch {
            return .failure(error)
        }
    }

    /// φ at the end of the curve minus φ at its start.
    nonisolated static func potentialDifference(_ phi: Expr, curve: [Expr], from a: Expr, to b: Expr) -> Double? {
        func value(at t: Expr) -> Double? {
            guard let time = try? RealEvaluator.evaluate(t) else { return nil }
            var point: [String: Double] = [:]
            for (name, component) in zip(["x", "y", "z"], curve) {
                guard let v = try? RealEvaluator.evaluate(component, context: EvaluationContext(variables: ["t": time])) else { return nil }
                point[name] = v
            }
            return try? RealEvaluator.evaluate(phi, context: EvaluationContext(variables: point))
        }
        guard let start = value(at: a), let end = value(at: b) else { return nil }
        return NumericCalculus.clean(end - start)
    }
}

/// "od … do …" for a parameter.
private struct BoundsRow: View {
    let name: String
    @Binding var from: String
    @Binding var to: String

    var body: some View {
        HStack {
            TextField("od", text: $from)
                .multilineTextAlignment(.center)
            Text("≤ \(name) ≤").font(.callout).foregroundStyle(.secondary).fixedSize()
            TextField("do", text: $to)
                .multilineTextAlignment(.center)
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    }
}

// MARK: - Surface integrals

private struct SurfaceIntegralSection: View {
    @AppStorage("surfaceX") private var x = "sin(u)*cos(v)"
    @AppStorage("surfaceY") private var y = "sin(u)*sin(v)"
    @AppStorage("surfaceZ") private var z = "cos(u)"
    @AppStorage("surfaceUFrom") private var uFrom = "0"
    @AppStorage("surfaceUTo") private var uTo = "pi"
    @AppStorage("surfaceVFrom") private var vFrom = "0"
    @AppStorage("surfaceVTo") private var vTo = "2pi"
    @AppStorage("surfaceFieldP") private var p = "x"
    @AppStorage("surfaceFieldQ") private var q = "y"
    @AppStorage("surfaceFieldR") private var r = "z"
    @AppStorage("surfaceScalar") private var scalar = "1"
    @State private var normal: [Expr]?
    @State private var flux: Result<IntegralResult, MathError>?
    @State private var scalarIntegral: Result<IntegralResult, MathError>?

    var body: some View {
        let X = parseComponent(x), Y = parseComponent(y), Z = parseComponent(z)
        let P = parseComponent(p), Q = parseComponent(q), R = parseComponent(r), f = parseComponent(scalar)
        Section {
            ExpressionInputField(title: "x(u, v) =", text: $x, expr: X.expr, error: X.error)
            ExpressionInputField(title: "y(u, v) =", text: $y, expr: Y.expr, error: Y.error)
            ExpressionInputField(title: "z(u, v) =", text: $z, expr: Z.expr, error: Z.error)
            BoundsRow(name: "u", from: $uFrom, to: $uTo)
            BoundsRow(name: "v", from: $vFrom, to: $vTo)
            if let normal {
                LabeledContent("r⃗_u × r⃗_v") { MathText(expr: .matrix(rows: 3, columns: 1, entries: normal), fontSize: 15) }
            }
        } header: {
            Text("Ploskev r⃗(u, v)")
        } footer: {
            Text("Meje za v smejo vsebovati u. Primer: sfera s polmerom 1 (u od 0 do π, v od 0 do 2π).")
        }
        Section {
            ExpressionInputField(title: "P =", text: $p, expr: P.expr, error: P.error)
            ExpressionInputField(title: "Q =", text: $q, expr: Q.expr, error: Q.error)
            ExpressionInputField(title: "R =", text: $r, expr: R.expr, error: R.error)
            IntegralRows(title: "∬ F⃗·dS⃗", integrandTitle: "F⃗(r⃗)·(r⃗_u × r⃗_v)", result: flux)
        } header: {
            Text("Pretok polja F⃗ = (P, Q, R)")
        } footer: {
            Text("Smer normale r⃗_u × r⃗_v določa predznak. Gaussov izrek: pretok skozi sklenjeno ploskev = ∭ div F⃗ dV; Stokesov: ∬ rot F⃗·dS⃗ = ∮ F⃗·dr⃗.")
        }
        Section {
            ExpressionInputField(title: "f(x, y, z) =", text: $scalar, expr: f.expr, error: f.error)
            IntegralRows(title: "∬ f dS", integrandTitle: "f(r⃗)·|r⃗_u × r⃗_v|", result: scalarIntegral)
        } header: {
            Text("Ploskovni integral skalarnega polja")
        } footer: {
            Text("Za f = 1 je to površina ploskve.")
        }
        .task(id: [x, y, z, uFrom, uTo, vFrom, vTo, p, q, r, scalar].joined(separator: "|")) { await compute() }
    }

    private func compute() async {
        let surface = components([x, y, z], optionalLast: false)
        let field = components([p, q, r], optionalLast: false)
        let f = parseComponent(scalar).expr
        guard let surface, let u0 = try? Parser.parse(uFrom), let u1 = try? Parser.parse(uTo),
              let v0 = try? Parser.parse(vFrom), let v1 = try? Parser.parse(vTo) else {
            normal = nil
            flux = .failure(.syntax("ploskev ali meje parametrov"))
            scalarIntegral = flux
            return
        }
        flux = nil
        scalarIntegral = nil
        let results = await Task.detached(priority: .userInitiated) {
            () -> ([Expr]?, Result<IntegralResult, MathError>, Result<IntegralResult, MathError>) in
            let n = try? VectorCalculus.normal(surface, parameters: "u", "v")
            let flux = SurfaceIntegralSection.flux(field, through: surface, lower: [u0, v0], upper: [u1, v1])
            let scalar = SurfaceIntegralSection.scalar(f, over: surface, lower: [u0, v0], upper: [u1, v1])
            return (n, flux, scalar)
        }.value
        guard !Task.isCancelled else { return }
        normal = results.0
        flux = results.1
        scalarIntegral = results.2
    }

    /// ∬ F⃗·dS⃗ with the normal r⃗_u × r⃗_v.
    nonisolated static func flux(_ field: [Expr]?, through surface: [Expr], lower: [Expr], upper: [Expr]) -> Result<IntegralResult, MathError> {
        guard let field else { return .failure(.syntax("komponente polja")) }
        do throws(MathError) {
            let g = try VectorCalculus.fluxIntegrand(field, surface: surface, parameters: "u", "v")
            let value = try Multivariable.iteratedIntegral(g, variables: ["u", "v"], lower: lower, upper: upper)
            return .success(IntegralResult(integrand: g, value: value, exact: nil))
        } catch {
            return .failure(error)
        }
    }

    /// ∬ f dS.
    nonisolated static func scalar(_ f: Expr?, over surface: [Expr], lower: [Expr], upper: [Expr]) -> Result<IntegralResult, MathError> {
        guard let f else { return .failure(.syntax("f")) }
        do throws(MathError) {
            let g = try VectorCalculus.areaIntegrand(f, surface: surface, parameters: "u", "v")
            let value = try Multivariable.iteratedIntegral(g, variables: ["u", "v"], lower: lower, upper: upper)
            return .success(IntegralResult(integrand: g, value: value, exact: nil))
        } catch {
            return .failure(error)
        }
    }
}
