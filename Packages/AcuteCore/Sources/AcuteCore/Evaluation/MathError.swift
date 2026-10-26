import Foundation

/// Errors produced while parsing or evaluating. Messages are in Slovenian because
/// they are shown directly in the calculator.
public enum MathError: Error, Hashable, Sendable, LocalizedError {
    case syntax(String)
    case incomplete
    case undefinedVariable(String)
    case domain(String)
    case divisionByZero
    case overflow
    case notReal
    case unsupported(String)
    case tooComplex

    public var errorDescription: String? {
        switch self {
        case .syntax(let detail): "Napaka v zapisu: \(detail)"
        case .incomplete: "Izraz ni dokončan"
        case .undefinedVariable(let name): "Spremenljivka \(name) nima vrednosti"
        case .domain(let detail): "Izven definicijskega območja: \(detail)"
        case .divisionByZero: "Deljenje z 0"
        case .overflow: "Prevelika vrednost"
        case .notReal: "Rezultat ni realno število"
        case .unsupported(let detail): "Ni podprto: \(detail)"
        case .tooComplex: "Izraz je preveč zapleten"
        }
    }

    /// Short label for compact UI (e.g. under the expression).
    public var shortDescription: String {
        switch self {
        case .syntax: "Napaka v zapisu"
        case .incomplete: "Nedokončano"
        case .undefinedVariable(let name): "\(name) ni definirana"
        case .domain: "Ni definirano"
        case .divisionByZero: "Deljenje z 0"
        case .overflow: "Prekoračitev"
        case .notReal: "Ni realno"
        case .unsupported: "Ni podprto"
        case .tooComplex: "Prezapleteno"
        }
    }
}
