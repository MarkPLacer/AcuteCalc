import AcuteCore
import SwiftUI

/// VoiceOver description of a 2D graph, which is a Metal view with drawn labels that VoiceOver
/// cannot read: the visible functions and the special points, formatted as on screen.
enum GraphAccessibility {
    /// "y = sin(x); x² + y² = 9" and, with special points, how many there are.
    static func summary(items: [PlotItem], pointCount: Int, style: MathStyle) -> String {
        let functions = items.filter(\.visible).compactMap { describe($0.kind, style: style) }
        var parts = functions.isEmpty ? ["Brez funkcij"] : functions
        if pointCount > 0 { parts.append("posebne točke: \(pointCount)") }
        return parts.joined(separator: "; ")
    }

    /// "Ničla: x = π, y = 0" (exact where the callout shows it, otherwise 5 significant digits).
    static func point(_ info: GraphPointInfo, style: MathStyle) -> String {
        func coordinate(_ exact: ExactReal?, _ value: Double) -> String {
            if let exact, !exact.isRational || !(exact.rational?.isInteger ?? true), exact.complexity <= 8 {
                return MathAccessibility.label(MathRowConverter.row(for: exact.expr), style: style)
            }
            let options = NumberFormatOptions(mode: .norm1, significantDigits: 5, decimalSeparator: style.decimalSeparator)
            return MathAccessibility.number(NumberFormatting.format(value, options: options))
        }
        let p = info.point
        return "\(p.kind.title): x = \(coordinate(p.exactX, p.x)), y = \(coordinate(p.exactY, p.y))"
    }

    private static func describe(_ kind: GraphKind, style: MathStyle) -> String? {
        func math(_ e: Expr) -> String { MathAccessibility.label(MathRowConverter.row(for: e), style: style) }
        switch kind {
        case .explicit(let e): return "y = " + math(e)
        case .explicitInY(let e): return "x = " + math(e)
        case .implicit(let lhs, let relation, let rhs): return math(.relation(lhs, relation, rhs))
        case .sequence(let e): return "zaporedje " + math(e)
        case .point(let x, let y): return "točka (" + math(x) + "; " + math(y) + ")"
        case .segment(_, _, _, _, let arrow): return arrow ? "vektor" : "daljica"
        case .polyline(_, let closed): return closed ? "mnogokotnik" : "lomljena črta"
        case .parametric(let x, let y, _, _): return "parametrična krivulja x = " + math(x) + ", y = " + math(y)
        case .slopeField: return "smerno polje"
        case .odeSolution: return "rešitev diferencialne enačbe"
        default: return nil
        }
    }
}

/// Invisible layer over the graph for VoiceOver: a container "Graf" whose first element is the
/// summary and the others the special points. It observes the model itself, so the graph view
/// (and its Metal view) is not updated more often.
struct GraphAccessibilityLayer: View {
    let model: GraphCanvasModel
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let style = MathAccessibility.style(settings)
        let points = model.showSpecialPoints ? model.specialPoints.map { GraphAccessibility.point($0, style: style) } : []
        let summary = GraphAccessibility.summary(items: model.items, pointCount: points.count, style: style)
        Color.clear
            .allowsHitTesting(false)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Graf")
            .accessibilityValue(summary)
            .accessibilityChildren {
                VStack {
                    Text(summary)
                        .accessibilityLabel("Graf")
                        .accessibilityValue(summary)
                    ForEach(points.indices, id: \.self) { index in
                        Text(points[index])
                    }
                }
            }
    }
}
