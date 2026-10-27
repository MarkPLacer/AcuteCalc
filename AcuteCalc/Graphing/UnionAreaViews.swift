import AcuteCore
import SwiftUI

/// The area of a union row in Grafi: Σ area(D_n), or why it is not known.
nonisolated enum UnionAreaSummary: Equatable, Sendable {
    case computed(UnionArea)
    case unavailable(String)
}

/// Texts about the area of a union D₁ ∪ D₂ ∪ … (the calculator's result and the rows in Grafi).
enum UnionAreaFormatting {
    /// P = 1,5708 (± 3·10⁻¹² for a sum without an exact value) when no two members overlap,
    /// otherwise the sum of the areas as an upper bound.
    static func headline(_ union: UnionArea, options: NumberFormatOptions) -> String {
        let value = NumberFormatting.format(union.sum, options: options).plainTextLocalized
        var bound = ""
        if union.exact == nil, union.sum.isFinite, let error = union.errorBound, error > 0 {
            let rough = NumberFormatOptions(significantDigits: 2, decimalSeparator: options.decimalSeparator)
            bound = " ± " + NumberFormatting.format(error, options: rough).plainTextLocalized
        }
        switch union.overlap {
        case .disjoint: return (union.exact == nil && union.sum.isFinite ? "P ≈ " : "P = ") + value + bound
        case .members, .unknown: return "Σ ploščin = " + value + bound + " ≥ P"
        }
    }

    /// Why the number is the area of the union, or only an upper bound for it.
    static func explanation(_ union: UnionArea) -> String {
        switch union.overlap {
        case .disjoint:
            var text = "D_n se ne prekrivajo, zato je ploščina unije vsota ploščin D_n"
            if let q = union.ratio {
                let quotient = Rational.approximating(q, maxDenominator: 1000).map { "\($0)" } ?? NumberFormatting.plain(q)
                text += " (geometrijska vrsta, q = \(quotient))"
            } else if union.sum.isFinite, union.errorBound == nil {
                text += " (napake vsote ne znam oceniti)"
            }
            return text + "."
        case .members(let i, let j):
            return "\(member(i)) in \(member(j)) se prekrivata, zato je vsota ploščin le zgornja meja za ploščino unije."
        case .unknown:
            return "Prekrivanja D_n ni bilo mogoče preveriti, zato je vsota ploščin le zgornja meja za ploščino unije."
        }
    }

    /// D₁, D₁₂, D₋₁ …
    static func member(_ n: Int) -> String {
        let digits: [Character: Character] = ["-": "₋", "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉"]
        return "D" + String(String(n).map { digits[$0] ?? $0 })
    }
}

/// The area line of a union row: P = π/2 ≈ 1,5708, and what it means.
struct UnionAreaLabel: View {
    let summary: UnionAreaSummary
    var color: Color
    @Environment(AppSettings.self) private var settings

    var body: some View {
        switch summary {
        case .computed(let union):
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "circle.circle.fill").foregroundStyle(color)
                    if let exact = union.exact, union.overlap == .disjoint {
                        Text("P =")
                        MathText(expr: exact.expr, fontSize: 14)
                        Text("≈ " + NumberFormatting.format(union.sum, options: settings.numberFormat).plainTextLocalized)
                    } else {
                        Text(UnionAreaFormatting.headline(union, options: settings.numberFormat))
                    }
                }
                .font(.caption.monospacedDigit())
                Text(UnionAreaFormatting.explanation(union))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .unavailable(let reason):
            Label(reason, systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
