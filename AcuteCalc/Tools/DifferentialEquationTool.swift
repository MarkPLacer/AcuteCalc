import AcuteCore
import SwiftUI

/// Differential equations (Matematika II, transients in Osnove elektrotehnike II, oscillations in
/// statics and mechanics): y′ = f(x, y) with its slope field, or y″ = f(x, y, y′); the solution
/// through the initial values (numeric RK45) and a closed form when one is found.
struct DifferentialEquationToolView: View {
    @AppStorage("odeOrder") private var order = 1
    @AppStorage("odeFirstOrder") private var firstOrderText = "x - y"
    @AppStorage("odeSecondOrder") private var secondOrderText = "-3y' - 2y"
    @State private var x0: Double? = 0
    @State private var y0: Double? = 1
    @State private var slope0: Double? = 0
    @State private var canvas = GraphCanvasModel()
    @State private var closedForm: DifferentialEquation.ClosedForm?
    @State private var searching = false

    private var text: Binding<String> { order == 1 ? $firstOrderText : $secondOrderText }

    /// The right-hand side; y′ may be written as y' or y′.
    private var parsed: (expr: Expr?, error: String?) {
        let source = text.wrappedValue
            .replacingOccurrences(of: "y′", with: DifferentialEquation.slopeName)
            .replacingOccurrences(of: "y'", with: DifferentialEquation.slopeName)
        do {
            var expr = try Parser.parse(source, options: ParserOptions(knownVariables: [DifferentialEquation.slopeName]))
            if case .relation(_, .equal, let rhs) = expr { expr = rhs }
            let allowed: Set<String> = order == 1 ? ["x", "y"] : ["x", "y", DifferentialEquation.slopeName]
            if let unknown = expr.freeVariables.subtracting(allowed).sorted().first {
                return (nil, "neznana spremenljivka \(unknown)")
            }
            return (expr, nil)
        } catch {
            return (nil, error.errorDescription ?? error.shortDescription)
        }
    }

    private var initial: [Double]? {
        guard let y0 else { return nil }
        if order == 1 { return [y0] }
        guard let slope0 else { return nil }
        return [y0, slope0]
    }

    /// Everything the graph and the closed form depend on.
    private var key: String {
        "\(order)|\(text.wrappedValue)|\(x0 ?? .nan)|\(y0 ?? .nan)|\(slope0 ?? .nan)"
    }

    var body: some View {
        let parsed = self.parsed
        Form {
            Section {
                Picker("Red enačbe", selection: $order) {
                    Text("y′ = f(x, y)").tag(1)
                    Text("y″ = f(x, y, y′)").tag(2)
                }
                .pickerStyle(.segmented)
                ExpressionInputField(title: order == 1 ? "y′ =" : "y″ =", text: text,
                                     expr: parsed.expr.map(display), error: parsed.error)
            } footer: {
                Text(order == 1 ? "Primeri: x − y, x·y, y², −x/y, 2y + eˣ" : "Primeri: −y, −3y′ − 2y, y + x, −y′/x + y/x² (y′ zapiši kot y')")
            }
            Section("Začetni pogoj") {
                NumberInputField(title: "x₀", value: $x0)
                NumberInputField(title: "y(x₀)", value: $y0)
                if order == 2 { NumberInputField(title: "y′(x₀)", value: $slope0) }
            }
            Section("Rešitev") {
                if let closedForm {
                    LabeledContent("Splošna") { solution(closedForm.general) }
                    if let particular = closedForm.particular {
                        LabeledContent("Skozi začetni pogoj") { solution(particular) }
                    }
                    Text(closedForm.method.prefix(1).uppercased() + closedForm.method.dropFirst())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if searching {
                    ProgressView()
                } else if parsed.expr != nil {
                    Text("Zaprte oblike ne najdem – graf prikazuje numerično rešitev (Runge–Kutta).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                GraphCanvasView(model: canvas)
                    .frame(height: 340)
                    .listRowInsets(EdgeInsets())
            }
        }
        .task(id: key) { await update() }
    }

    /// y′ instead of the internal name in the typed expression.
    private func display(_ e: Expr) -> Expr {
        e.substituting(DifferentialEquation.slopeName, with: .variable("y′"))
    }

    @ViewBuilder
    private func solution(_ e: Expr) -> some View {
        if case .relation = e {
            MathText(expr: e, fontSize: 17)
        } else {
            MathText(expr: .relation(.variable("y"), .equal, e), fontSize: 17)
        }
    }

    private func update() async {
        guard let f = parsed.expr, let x0, let initial else {
            canvas.items = []
            closedForm = nil
            return
        }
        let order = self.order
        var items: [PlotItem] = []
        if order == 1 {
            items.append(PlotItem(id: "field", kind: .slopeField(f), color: RGBA(0.55, 0.57, 0.62, 0.85), width: 1.3, analyzed: false))
        }
        items.append(PlotItem(id: "solution", kind: .odeSolution(f, order: order, x0: x0, initial: initial), color: GraphPalette.color(0), width: 3, analyzed: false))
        items.append(PlotItem(id: "start", kind: .point(x: .decimal(x0), y: .decimal(initial[0])), color: GraphPalette.color(0), analyzed: false))
        canvas.items = items
        searching = true
        closedForm = await Task.detached(priority: .userInitiated) {
            DifferentialEquation.closedForm(f, order: order, x0: x0, initial: initial)
        }.value
        searching = false
    }
}
