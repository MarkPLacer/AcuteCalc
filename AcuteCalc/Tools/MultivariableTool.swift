import AcuteCore
import SwiftUI

/// Functions of several variables (Matematika II): partial derivatives, gradient, tangent plane,
/// extrema with and without constraints, double and triple integrals, contour lines and Jacobians.
struct MultivariableToolView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case derivatives, extrema, integral, contours, jacobian
        var id: String { rawValue }
        var title: String {
            switch self {
            case .derivatives: "Odvodi"
            case .extrema: "Ekstremi"
            case .integral: "Integral"
            case .contours: "Nivojnice"
            case .jacobian: "Jacobi"
            }
        }
    }

    @AppStorage("multivariableMode") private var mode: Mode = .derivatives

    var body: some View {
        List {
            Section {
                Picker("Način", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            switch mode {
            case .derivatives: PartialDerivativesSection()
            case .extrema: ExtremaSection()
            case .integral: MultipleIntegralSection()
            case .contours: ContourSection()
            case .jacobian: JacobianSection()
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
    }
}

/// Parses a typed expression; `g = h` becomes g − h (constraints).
private func parseInput(_ text: String) -> (expr: Expr?, error: String?) {
    guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return (nil, nil) }
    do {
        let expr = try Parser.parse(text)
        if case .relation(let lhs, .equal, let rhs) = expr { return (Simplifier.simplify(.sum([lhs, .negation(rhs)])), nil) }
        return (expr, nil)
    } catch {
        return (nil, error.errorDescription ?? error.shortDescription)
    }
}

/// x, y (and z when the function uses it).
private func variables(of exprs: [Expr]) -> [String] {
    exprs.contains { $0.dependsOn("z") } ? ["x", "y", "z"] : ["x", "y"]
}

private func displayNumber(_ value: Double, exact: ExactReal?) -> Expr {
    if let exact, exact.complexity <= 8 { return exact.expr }
    return .decimal(NumericCalculus.clean(value))
}

// MARK: - Partial derivatives

private struct PartialDerivativesSection: View {
    @AppStorage("multiDerivativesText") private var text = "x^2*y + sin(x*y)"
    @State private var x0: Double? = 1
    @State private var y0: Double? = 0
    @State private var z0: Double? = 0
    @State private var direction = "(1, 1)"

    var body: some View {
        let parsed = parseInput(text)
        Section {
            ExpressionInputField(title: "f(x, y) ali f(x, y, z) =", text: $text, expr: parsed.expr, error: parsed.error)
        } footer: {
            Text("Parcialni odvodi, gradient, smerni odvod, Hessejeva matrika ter tangentna ravnina in Taylorjev polinom 2. reda.")
        }
        if let f = parsed.expr {
            let names = variables(of: [f])
            if let gradient = try? Multivariable.gradient(f, variables: names),
               let hessian = try? Multivariable.hessian(f, variables: names) {
                Section("Parcialni odvodi") {
                    ForEach(Array(names.enumerated()), id: \.offset) { i, v in
                        LabeledContent("∂f/∂\(v)") { MathText(expr: gradient[i], fontSize: 17) }
                    }
                    ForEach(Array(names.enumerated()), id: \.offset) { i, v in
                        ForEach(Array(names.enumerated()).filter { $0.offset >= i }, id: \.offset) { j, w in
                            LabeledContent(i == j ? "∂²f/∂\(v)²" : "∂²f/∂\(v)∂\(w)") { MathText(expr: hessian[i][j], fontSize: 17) }
                        }
                    }
                }
                Section("V točki") {
                    NumberInputField(title: "x₀", value: $x0)
                    NumberInputField(title: "y₀", value: $y0)
                    if names.count == 3 { NumberInputField(title: "z₀", value: $z0) }
                    if let point = point(names.count) {
                        pointResults(f, names: names, gradient: gradient, at: point)
                    }
                }
            }
        }
    }

    private func point(_ n: Int) -> [Double]? {
        guard let x0, let y0 else { return nil }
        if n == 3 { return z0.map { [x0, y0, $0] } }
        return [x0, y0]
    }

    @ViewBuilder
    private func pointResults(_ f: Expr, names: [String], gradient: [Expr], at point: [Double]) -> some View {
        let context = EvaluationContext(variables: Dictionary(uniqueKeysWithValues: zip(names, point)))
        let values = gradient.map { (try? RealEvaluator.evaluate($0, context: context)) ?? .nan }
        ResultRow(title: "f", value: try? RealEvaluator.evaluate(f, context: context))
        LabeledContent("∇f") {
            MathText(expr: .matrix(rows: values.count, columns: 1, entries: values.map { displayNumber($0, exact: ExactRecognizer.recognize($0)) }), fontSize: 16)
        }
        ResultRow(title: "|∇f|", value: values.map { $0 * $0 }.reduce(0, +).squareRoot())
        LabeledContent("Smer s⃗") {
            TextField("(1, 1)", text: $direction)
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
        }
        if let s = directionVector(names.count) {
            let length = s.map { $0 * $0 }.reduce(0, +).squareRoot()
            ResultRow(title: "∂f/∂s⃗ = ∇f·s⃗/|s⃗|", value: length > 0 ? zip(values, s).map(*).reduce(0, +) / length : nil)
        }
        if names.count == 2 {
            if let plane = try? Multivariable.taylor(f, variables: names, at: point, order: 1) {
                LabeledContent("Tangentna ravnina") { MathText(expr: .relation(.variable("z"), .equal, plane), fontSize: 15) }
            }
            if let taylor = try? Multivariable.taylor(f, variables: names, at: point, order: 2) {
                LabeledContent("T₂(x, y)") { MathText(expr: taylor, fontSize: 15) }
            }
        }
    }

    private func directionVector(_ n: Int) -> [Double]? {
        guard let expr = try? Parser.parse(direction), case .matrix(let rows, 1, let entries) = expr, rows == n else { return nil }
        let values = entries.compactMap { try? RealEvaluator.evaluate($0) }
        return values.count == n ? values : nil
    }
}

// MARK: - Extrema

private struct ExtremaSection: View {
    @AppStorage("multiExtremaText") private var text = "x^3 - 3x + y^2"
    @AppStorage("multiConstraint1") private var constraint1 = ""
    @AppStorage("multiConstraint2") private var constraint2 = ""
    @State private var from: Double? = -5
    @State private var to: Double? = 5
    @State private var points: [Multivariable.CriticalPoint] = []
    @State private var searching = false

    var body: some View {
        let f = parseInput(text)
        let g1 = parseInput(constraint1), g2 = parseInput(constraint2)
        let constraints = self.constraints
        Section {
            ExpressionInputField(title: "f(x, y) ali f(x, y, z) =", text: $text, expr: f.expr, error: f.error)
            ExpressionInputField(title: "Vez g(x, y) = 0 (neobvezno)", text: $constraint1, expr: g1.expr, error: g1.error)
            if !constraint1.isEmpty {
                ExpressionInputField(title: "Druga vez (neobvezno)", text: $constraint2, expr: g2.expr, error: g2.error)
            }
        } footer: {
            Text("Brez vezi: stacionarne točke (∇f = 0) in njihova vrsta. Z vezjo: vezani ekstremi po Lagrangeu (∇f = Σ λᵢ∇gᵢ), vrsta iz d²L na tangentnem prostoru vezi (dgᵢ = 0).")
        }
        Section("Območje iskanja") {
            NumberInputField(title: "Od (za vse spremenljivke)", value: $from)
            NumberInputField(title: "Do", value: $to)
        }
        Section("Točke") {
            if searching {
                ProgressView()
            } else if points.isEmpty {
                Text(f.expr == nil ? "Vnesi funkcijo." : (constraints == nil ? "Popravi zapis vezi." : "V območju ni stacionarnih točk."))
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                CriticalPointRow(point: point, names: variables(of: [f.expr ?? .zero] + (constraints ?? [])))
            }
        }
        .task(id: "\(text)|\(constraint1)|\(constraint2)|\(from ?? .nan)|\(to ?? .nan)") { await search(f.expr, constraints) }
    }

    /// The typed constraints, or nil while one of them does not parse; the second field is
    /// shown, and used, only together with the first.
    private var constraints: [Expr]? {
        let typed = [constraint1, constraint2].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard typed.first == constraint1 else { return [] }
        var result: [Expr] = []
        for text in typed {
            guard let g = parseInput(text).expr else { return nil }
            result.append(g)
        }
        return result
    }

    private func search(_ f: Expr?, _ constraints: [Expr]?) async {
        guard let f, let constraints, let from, let to, from < to else {
            points = []
            searching = false
            return
        }
        let names = variables(of: [f] + constraints)
        let box = names.map { _ in from...to }
        points = []
        searching = true
        let found = await Task.detached(priority: .userInitiated) {
            constraints.isEmpty
                ? Multivariable.stationaryPoints(f, variables: names, box: box)
                : Multivariable.constrainedExtrema(f, constraints: constraints, variables: names, box: box)
        }.value
        // Newer input started another search while this one ran.
        guard !Task.isCancelled else { return }
        points = found
        searching = false
    }
}

private struct CriticalPointRow: View {
    let point: Multivariable.CriticalPoint
    let names: [String]
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(point.kind.title.prefix(1).uppercased() + point.kind.title.dropFirst())
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 4) {
                MathText(expr: .matrix(rows: 1, columns: point.coordinates.count,
                                       entries: zip(point.coordinates, point.exact).map { displayNumber($0, exact: $1) }), fontSize: 16)
                Text("f =").foregroundStyle(.secondary)
                MathText(expr: displayNumber(point.value, exact: point.exactValue), fontSize: 16)
            }
            if !point.multipliers.isEmpty {
                Text(point.multipliers.map { "λ = " + NumberFormatting.format($0, options: settings.numberFormat).plainText }.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let d = point.discriminant {
                Text("D = f_xx·f_yy − f_xy² = " + NumberFormatting.format(d, options: settings.numberFormat).plainText)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Double and triple integrals

private struct MultipleIntegralSection: View {
    enum Coordinates: String, CaseIterable, Identifiable {
        case cartesian2, polar, cartesian3, cylindrical, spherical
        var id: String { rawValue }
        var title: String {
            switch self {
            case .cartesian2: "∬ kartezične"
            case .polar: "∬ polarne"
            case .cartesian3: "∭ kartezične"
            case .cylindrical: "∭ cilindrične"
            case .spherical: "∭ sferne"
            }
        }
        /// Integration variables, outermost first, as typed in the limits.
        var variables: [String] {
            switch self {
            case .cartesian2: ["x", "y"]
            case .polar: ["φ", "r"]
            case .cartesian3: ["x", "y", "z"]
            case .cylindrical: ["φ", "r", "z"]
            case .spherical: ["φ", "θ", "r"]
            }
        }
        var labels: [String] {
            switch self {
            case .cartesian2: ["x", "y(x)"]
            case .polar: ["φ (phi)", "r(φ)"]
            case .cartesian3: ["x", "y(x)", "z(x, y)"]
            case .cylindrical: ["φ (phi)", "r(φ)", "z(φ, r)"]
            case .spherical: ["φ (phi)", "θ (theta)", "r(φ, θ)"]
            }
        }
        /// Limits filled in on switching: a triangle, the unit disk, the unit cube, a cylinder, the unit ball.
        var defaultLimits: (lower: String, upper: String) {
            switch self {
            case .cartesian2: ("0|0", "1|x")
            case .polar: ("0|0", "2π|1")
            case .cartesian3: ("0|0|0", "1|1|1")
            case .cylindrical: ("0|0|0", "2π|1|1")
            case .spherical: ("0|0|0", "2π|π|1")
            }
        }
        var note: String {
            switch self {
            case .cartesian2, .cartesian3: "Meje notranjih spremenljivk smejo vsebovati zunanje (y od 0 do x)."
            case .polar: "x = r·cos φ, y = r·sin φ, dS = r dr dφ"
            case .cylindrical: "x = r·cos φ, y = r·sin φ, z = z, dV = r dz dr dφ"
            case .spherical: "x = r·sin θ·cos φ, y = r·sin θ·sin φ, z = r·cos θ, dV = r²·sin θ dr dθ dφ"
            }
        }

        /// f(x, y, z) in these coordinates times the Jacobian.
        func transform(_ f: Expr) -> Expr {
            let r = Expr.variable("r"), phi = Expr.variable("φ"), theta = Expr.variable("θ")
            switch self {
            case .cartesian2, .cartesian3:
                return f
            case .polar, .cylindrical:
                let mapped = f.substituting("x", with: .product([r, .function(.cos, [phi])])).substituting("y", with: .product([r, .function(.sin, [phi])]))
                return .product([mapped, r])
            case .spherical:
                let mapped = f.substituting("x", with: .product([r, .function(.sin, [theta]), .function(.cos, [phi])]))
                    .substituting("y", with: .product([r, .function(.sin, [theta]), .function(.sin, [phi])]))
                    .substituting("z", with: .product([r, .function(.cos, [theta])]))
                return .product([mapped, .power(r, .int(2)), .function(.sin, [theta])])
            }
        }
    }

    @AppStorage("multiIntegralCoordinates") private var coordinates: Coordinates = .cartesian2
    @AppStorage("multiIntegrand") private var integrand = "x*y"
    @AppStorage("multiLower") private var lowerText = "0|0|0"
    @AppStorage("multiUpper") private var upperText = "1|x|1"
    @State private var result: Double?
    @State private var error: String?
    @State private var computing = false

    var body: some View {
        let f = parseInput(integrand)
        let names = coordinates.variables
        Section {
            Picker("Koordinate", selection: $coordinates) {
                ForEach(Coordinates.allCases) { Text($0.title).tag($0) }
            }
            ExpressionInputField(title: "f(x, y" + (names.count == 3 ? ", z" : "") + ") =", text: $integrand, expr: f.expr, error: f.error)
        } footer: {
            Text(coordinates.note)
        }
        .onChange(of: coordinates) { _, newValue in
            lowerText = newValue.defaultLimits.lower
            upperText = newValue.defaultLimits.upper
        }
        Section("Meje (od zunanje proti notranji)") {
            ForEach(Array(coordinates.labels.enumerated()), id: \.offset) { i, label in
                HStack {
                    TextField("od", text: bound(lower: true, i))
                        .multilineTextAlignment(.center)
                    Text("≤ \(label) ≤").font(.callout).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                    TextField("do", text: bound(lower: false, i))
                        .multilineTextAlignment(.center)
                }
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            }
        }
        Section("Rezultat") {
            if computing {
                ProgressView()
            } else if let result {
                ResultRow(title: names.count == 2 ? "∬ f dS" : "∭ f dV", value: result, exact: ExactRecognizer.recognize(result, tolerance: 1e-8).map(\.expr))
            } else if let error {
                Text(error).foregroundStyle(.red).font(.callout)
            }
            if let f = f.expr, coordinates != .cartesian2, coordinates != .cartesian3 {
                LabeledContent("Integrand") { MathText(expr: Simplifier.simplify(coordinates.transform(f)), fontSize: 15) }
            }
        }
        .task(id: "\(coordinates.rawValue)|\(integrand)|\(lowerText)|\(upperText)") { await compute(f.expr) }
    }

    /// One of the `|`-separated limits of the current coordinate system.
    private func bound(lower: Bool, _ i: Int) -> Binding<String> {
        Binding(get: {
            let parts = (lower ? lowerText : upperText).components(separatedBy: "|")
            return i < parts.count ? parts[i] : ""
        }, set: { newValue in
            var parts = (lower ? lowerText : upperText).components(separatedBy: "|")
            while parts.count < 3 { parts.append("") }
            parts[i] = newValue.replacingOccurrences(of: "|", with: "")
            if lower { lowerText = parts.joined(separator: "|") } else { upperText = parts.joined(separator: "|") }
        })
    }

    private func compute(_ f: Expr?) async {
        result = nil
        error = nil
        computing = false
        guard let f else { return }
        // Wait until typing pauses: every change cancels this task and starts a new one.
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        let names = coordinates.variables
        let lowers = lowerText.components(separatedBy: "|"), uppers = upperText.components(separatedBy: "|")
        var lower: [Expr] = [], upper: [Expr] = []
        for i in names.indices {
            guard i < lowers.count, i < uppers.count, let a = try? Parser.parse(lowers[i]), let b = try? Parser.parse(uppers[i]) else {
                error = "Vnesi obe meje za \(coordinates.labels[i])."
                return
            }
            lower.append(a)
            upper.append(b)
        }
        let integrand = coordinates.transform(f)
        computing = true
        let outcome: Result<Double, MathError> = await Task.detached(priority: .userInitiated) {
            do throws(MathError) {
                return .success(try Multivariable.iteratedIntegral(integrand, variables: names, lower: lower, upper: upper))
            } catch {
                return .failure(error)
            }
        }.value
        // Newer input started another calculation while this one ran.
        guard !Task.isCancelled else { return }
        computing = false
        switch outcome {
        case .success(let value): result = value
        case .failure(let failure): error = failure.errorDescription ?? failure.shortDescription
        }
    }
}

// MARK: - Contour lines

private struct ContourSection: View {
    @AppStorage("multiContourText") private var text = "x^2 - y^2"
    @State private var canvas = GraphCanvasModel()
    @State private var levels: [Double] = []
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let f = parseInput(text)
        Section {
            ExpressionInputField(title: "f(x, y) =", text: $text, expr: f.expr, error: f.error)
        } footer: {
            Text("Nivojnice f(x, y) = c za okrogle vrednosti c med najmanjšo in največjo vrednostjo na sliki; točke so stacionarne točke.")
        }
        Section {
            GraphCanvasView(model: canvas)
                .frame(height: 360)
                .listRowInsets(EdgeInsets())
            if !levels.isEmpty {
                Text("c ∈ {" + levels.map { NumberFormatting.format($0, options: settings.numberFormat).plainText }.joined(separator: "; ") + "}")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        // The levels depend on the function and on the visible part of the plane.
        .task(id: "\(text)|\(canvas.viewport.visibleX)|\(canvas.viewport.visibleY)") { await update(f.expr) }
    }

    private func update(_ f: Expr?) async {
        guard let f, !f.dependsOn("z") else {
            canvas.items = []
            levels = []
            return
        }
        // Wait until panning or zooming pauses; a newer window cancels this one.
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }
        let xs = canvas.viewport.visibleX, ys = canvas.viewport.visibleY
        let result = await Task.detached(priority: .userInitiated) {
            (Multivariable.contourLevels(f, x: xs, y: ys, count: 10),
             Multivariable.stationaryPoints(f, variables: ["x", "y"], box: [xs, ys]))
        }.value
        guard !Task.isCancelled else { return }
        levels = result.0
        var items: [PlotItem] = []
        for (i, c) in result.0.enumerated() {
            let t = result.0.count > 1 ? Float(i) / Float(result.0.count - 1) : 0.5
            items.append(PlotItem(id: "level-\(i)", kind: .implicit(lhs: f, relation: .equal, rhs: .decimal(c)),
                                  color: RGBA(0.25 + 0.7 * t, 0.45, 0.95 - 0.7 * t, 1), width: 2, analyzed: false))
        }
        for (i, p) in result.1.enumerated() {
            items.append(PlotItem(id: "critical-\(i)", kind: .point(x: .decimal(p.coordinates[0]), y: .decimal(p.coordinates[1])),
                                  color: RGBA(1, 1, 1, 1), analyzed: false))
        }
        canvas.items = items
    }
}

// MARK: - Jacobian

private struct JacobianSection: View {
    @AppStorage("multiJacobian1") private var first = "r*cos(phi)"
    @AppStorage("multiJacobian2") private var second = "r*sin(phi)"
    @AppStorage("multiJacobian3") private var third = ""
    @AppStorage("multiJacobianVariables") private var variablesText = "r, phi"

    var body: some View {
        let f1 = parseInput(first), f2 = parseInput(second), f3 = parseInput(third)
        Section {
            ExpressionInputField(title: "u =", text: $first, expr: f1.expr, error: f1.error)
            ExpressionInputField(title: "v =", text: $second, expr: f2.expr, error: f2.error)
            ExpressionInputField(title: "w = (neobvezno)", text: $third, expr: f3.expr, error: f3.error)
            LabeledContent("Spremenljivke") {
                TextField("x, y", text: $variablesText)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
        } footer: {
            Text("Jacobijeva matrika ∂(u, v, w)/∂(…) in njena determinanta, npr. r·cos φ, r·sin φ po r, phi.")
        }
        let functions = [f1.expr, f2.expr, f3.expr].compactMap { $0 }
        if let names = parsedVariables, functions.count == names.count, (2...3).contains(names.count),
           let matrix = try? Multivariable.jacobian(functions, variables: names) {
            Section("Rezultat") {
                LabeledContent("J") {
                    MathText(expr: .matrix(rows: matrix.count, columns: names.count, entries: matrix.flatMap { $0 }), fontSize: 16)
                }
                if let det = Multivariable.determinant(matrix) {
                    LabeledContent("det J") { MathText(expr: det, fontSize: 17) }
                }
            }
        } else if parsedVariables == nil {
            Section { Text("Spremenljivke zapiši z imeni, ločenimi z vejico, npr. r, phi.").foregroundStyle(.secondary) }
        } else if !functions.isEmpty {
            Section { Text("Število funkcij mora biti enako številu spremenljivk (2 ali 3).").foregroundStyle(.secondary) }
        }
    }

    /// Variable names typed as letters or Greek names (phi → φ); nil when one of them is not a name.
    private var parsedVariables: [String]? {
        var names: [String] = []
        for part in variablesText.split(separator: ",", omittingEmptySubsequences: false) {
            guard case .variable(let name)? = try? Parser.parse(part.trimmingCharacters(in: .whitespaces)) else { return nil }
            names.append(name)
        }
        return names
    }
}
