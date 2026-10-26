import AcuteCore
import SwiftUI

/// Every key of the calculator keypad and symbol palette.
enum KeypadKey: Hashable, Identifiable {
    case digit(Int)
    case point
    case symbol(MathSymbol)
    case clear, delete, enter
    case left, right, up, down
    case fraction, power, square, cube, inverse, tenPower, ePower
    case sqrt, cbrt, nthRoot, abs, logBase
    case function(MathFunction)
    case function2(MathFunction)
    case derivative, derivativeAt, integral, indefiniteIntegral, summation, limit, limitLeft, limitRight
    case binomial
    case angleMode
    case variable(String)
    case store
    case memoryPlus, memoryMinus, memoryRecall
    case change
    case expand
    case subscriptKey
    /// Functions with three arguments, e.g. binompdf(n; p; k).
    case functionN(MathFunction, Int)
    case partialDerivative, product
    case matrix(rows: Int, columns: Int)
    case piecewise
    case vectorArrow
    /// (−): toggles the sign of the number before the caret.
    case negate
    case selectAll, undo, redo
    /// A letter typed on a hardware keyboard (s-i-n turns into sin).
    case typedLetter(String)
    /// Sharp MDF: round the answer to the displayed digits.
    case modify

    var id: String { String(describing: self) }

    // MARK: Labels

    /// Label as math (rendered with the math renderer) or plain text.
    enum Label {
        case text(String)
        case math(MathRow)
        case systemImage(String)
    }

    var label: Label {
        switch self {
        case .digit(let d): return .text("\(d)")
        case .point: return .text(",")
        case .symbol(let s):
            switch s {
            case .plus: return .systemImage("plus")
            case .minus: return .systemImage("minus")
            case .times: return .systemImage("multiply")
            case .divide: return .systemImage("divide")
            case .equals: return .systemImage("equal")
            case .leftParenthesis: return .text("(")
            case .rightParenthesis: return .text(")")
            case .variable(let v): return .math(MathRow([.symbol(.variable(v))]))
            case .constant(let c): return .math(MathRow([.symbol(.constant(c))]))
            case .factorial: return .text("x!")
            case .percent: return .text("%")
            case .exponent10: return .text("EE")
            case .ans: return .text("ANS")
            case .degreeMark: return .text("°")
            case .minuteMark: return .text("′")
            case .secondMark: return .text("″")
            case .plusMinus: return .text("±")
            case .less: return .text("<")
            case .greater: return .text(">")
            case .lessOrEqual: return .text("≤")
            case .greaterOrEqual: return .text("≥")
            case .notEqual: return .text("≠")
            case .comma: return .text(";")
            case .digit(let d): return .text("\(d)")
            case .decimalPoint: return .text(",")
            case .crossProduct: return .text("×")
            case .transposeMark: return .math(MathRow([.symbol(.variable("A")), .symbol(.transposeMark)]))
            case .angleSign: return .text("∠")
            case .parallel: return .text("∥")
            }
        case .clear: return .text("C")
        case .delete: return .systemImage("delete.left.fill")
        case .enter: return .systemImage("arrow.right")
        case .left: return .systemImage("chevron.left")
        case .right: return .systemImage("chevron.right")
        case .up: return .systemImage("chevron.up")
        case .down: return .systemImage("chevron.down")
        case .fraction: return .math(MathRow([.fraction(numerator: MathRow(), denominator: MathRow())]))
        case .power: return .text("^")
        case .square: return .math(MathRow([.symbol(.variable("x")), .power(exponent: .text("2"))]))
        case .cube: return .math(MathRow([.symbol(.variable("x")), .power(exponent: .text("3"))]))
        case .inverse: return .math(MathRow([.symbol(.variable("x")), .power(exponent: MathRow([.symbol(.minus), .symbol(.digit(1))]))]))
        case .tenPower: return .math(MathRow([.symbol(.digit(1)), .symbol(.digit(0)), .power(exponent: MathRow([.symbol(.variable("x"))]))]))
        case .ePower: return .math(MathRow([.symbol(.constant(.e)), .power(exponent: MathRow([.symbol(.variable("x"))]))]))
        case .sqrt: return .math(MathRow([.squareRoot(MathRow())]))
        case .cbrt: return .math(MathRow([.nthRoot(index: .text("3"), radicand: MathRow())]))
        case .nthRoot: return .math(MathRow([.nthRoot(index: MathRow([.symbol(.variable("n"))]), radicand: MathRow())]))
        case .abs: return .math(MathRow([.absoluteValue(MathRow([.symbol(.variable("a"))]))]))
        case .logBase: return .math(MathRow([.logarithm(base: MathRow([.symbol(.variable("a"))]), argument: MathRow())]))
        case .function(let f):
            switch f {
            case .log10: return .text("log")
            case .rand: return .text("Rand")
            case .dice: return .text("Dice")
            case .coin: return .text("Coin")
            default: return .text(f.internationalName)
            }
        case .function2(let f):
            switch f {
            case .gcd: return .text("GCD")
            case .lcm: return .text("LCM")
            case .idiv: return .text("int÷")
            case .mod: return .text("mod")
            case .randInt: return .text("R.Int")
            case .pol: return .text("→rθ")
            case .rec: return .text("→xy")
            case .nPr: return .text("nPr")
            case .nCr: return .text("nCr")
            default: return .text(f.internationalName)
            }
        case .derivative: return .math(MathRow([.fraction(numerator: MathRow([.symbol(.variable("d"))]), denominator: MathRow([.symbol(.variable("d")), .symbol(.variable("x"))]))]))
        case .derivativeAt: return .text("d/dx|ₐ")
        case .integral: return .math(MathRow([.integral(lower: .text("a"), upper: .text("b"), body: MathRow())]))
        case .indefiniteIntegral: return .text("∫ dx")
        case .summation: return .text("Σ")
        case .limit: return .text("lim")
        case .limitLeft: return .text("lim⁻")
        case .limitRight: return .text("lim⁺")
        case .binomial: return .math(MathRow([.binomial(MathRow([.symbol(.variable("n"))]), MathRow([.symbol(.variable("k"))]))]))
        case .angleMode: return .text("DRG")
        case .variable(let v): return .math(MathRow([.symbol(.variable(v))]))
        case .store: return .text("STO")
        case .memoryPlus: return .text("M+")
        case .memoryMinus: return .text("M−")
        case .memoryRecall: return .text("RCL")
        case .change: return .systemImage("arrow.triangle.2.circlepath")
        case .expand: return .systemImage("ellipsis")
        case .subscriptKey: return .math(MathRow([.symbol(.variable("x")), .subscriptRow(MathRow([.symbol(.variable("n"))]))]))
        case .functionN(let f, _):
            switch f {
            case .binompdf: return .text("binomPdf")
            case .binomcdf: return .text("binomCdf")
            case .normpdf: return .text("normPdf")
            default: return .text(f.internationalName)
            }
        case .partialDerivative:
            return .math(MathRow([.fraction(numerator: MathRow([.symbol(.variable("∂"))]), denominator: MathRow([.symbol(.variable("∂")), .symbol(.variable("x"))]))]))
        case .product: return .text("Π")
        case .matrix(let rows, let columns):
            switch (rows, columns) {
            case (2, 2): return .systemImage("square.grid.2x2")
            case (3, 3): return .systemImage("square.grid.3x3")
            case (2, 1): return .systemImage("rectangle.split.1x2")
            case (3, 1): return .systemImage("rectangle.split.3x1")
            default: return .text("\(rows)×\(columns)")
            }
        case .piecewise: return .text("{ ⋮")
        case .vectorArrow: return .math(MathRow([.vectorArrow(MathRow([.symbol(.variable("a"))]))]))
        case .negate: return .text("(−)")
        case .selectAll: return .systemImage("selection.pin.in.out")
        case .undo: return .systemImage("arrow.uturn.backward")
        case .redo: return .systemImage("arrow.uturn.forward")
        case .typedLetter(let letter): return .math(MathRow([.symbol(.variable(letter))]))
        case .modify: return .text("MDF")
        }
    }

    /// VoiceOver / tooltip name in Slovenian.
    var accessibilityName: String {
        switch self {
        case .digit(let d): "\(d)"
        case .point: "decimalna vejica"
        case .symbol(let s): Self.spokenName(s)
        case .clear: "Počisti"
        case .delete: "Briši"
        case .enter: "Potrdi"
        case .left: "Levo"
        case .right: "Desno"
        case .up: "Gor"
        case .down: "Dol"
        case .fraction: "Ulomek"
        case .power: "Potenca"
        case .square: "Kvadrat"
        case .cube: "Kub"
        case .inverse: "Obratna vrednost"
        case .tenPower: "10 na x"
        case .ePower: "e na x"
        case .sqrt: "Kvadratni koren"
        case .cbrt: "Kubični koren"
        case .nthRoot: "n-ti koren"
        case .abs: "Absolutna vrednost"
        case .logBase: "Logaritem z osnovo a"
        case .function(let f): Self.spokenName(f)
        case .function2(let f): Self.spokenName(f)
        case .derivative: "Odvod"
        case .derivativeAt: "Odvod v točki"
        case .integral: "Določeni integral"
        case .indefiniteIntegral: "Nedoločeni integral"
        case .summation: "Vsota"
        case .limit: "Limita"
        case .limitLeft: "Leva limita"
        case .limitRight: "Desna limita"
        case .binomial: "Binomski simbol"
        case .angleMode: "Kotne enote"
        case .variable(let v): "Spremenljivka \(v)"
        case .store: "Shrani v spremenljivko"
        case .memoryPlus: "Prištej v spomin"
        case .memoryMinus: "Odštej od spomina"
        case .memoryRecall: "Prikliči spomin"
        case .change: "Spremeni obliko rezultata"
        case .expand: "Več simbolov"
        case .subscriptKey: "Indeks"
        case .functionN(let f, _): Self.spokenName(f)
        case .partialDerivative: "Parcialni odvod"
        case .product: "Produkt"
        case .matrix(let rows, let columns): columns == 1 ? "Vektor z \(rows) komponentami" : "Matrika \(rows) × \(columns)"
        case .piecewise: "Odsekoma definirana funkcija"
        case .vectorArrow: "Vektor (puščica)"
        case .negate: "Spremeni predznak"
        case .selectAll: "Izberi vse"
        case .undo: "Razveljavi"
        case .redo: "Uveljavi"
        case .typedLetter(let letter): letter
        case .modify: "Zaokroži rezultat na prikazana mesta (MDF)"
        }
    }

    /// The name with the decimal separator chosen in the settings (the key shows "," or ".").
    func accessibilityName(decimalSeparator: String) -> String {
        self == .point && decimalSeparator == "." ? "decimalna pika" : accessibilityName
    }

    /// The angle unit for VoiceOver (shown as RAD, DEG, GRAD).
    static func spokenName(_ unit: AngleUnit) -> String {
        switch unit {
        case .radians: "radiani"
        case .degrees: "stopinje"
        case .gradians: "gradi"
        }
    }

    /// Descriptive Slovenian names for VoiceOver instead of the key glyphs (· for times, ! …).
    static func spokenName(_ s: MathSymbol) -> String {
        switch s {
        case .plus: "plus"
        case .minus: "minus"
        case .times: "krat"
        case .divide: "deljeno"
        case .equals: "je enako"
        case .less: "manjše od"
        case .greater: "večje od"
        case .lessOrEqual: "manjše ali enako"
        case .greaterOrEqual: "večje ali enako"
        case .leftParenthesis: "levi oklepaj"
        case .rightParenthesis: "desni oklepaj"
        case .comma: "podpičje"
        case .variable(let name): MathSymbol.displayName(name)
        case .constant(.pi): "pi"
        case .constant(.e): "Eulerjevo število e"
        case .constant(.i): "imaginarna enota"
        case .constant(.infinity): "neskončno"
        case .factorial: "fakulteta"
        case .percent: "odstotek"
        case .exponent10: "krat deset na"
        case .degreeMark: "stopinje"
        case .minuteMark: "kotne minute"
        case .secondMark: "kotne sekunde"
        case .ans: "prejšnji rezultat"
        case .plusMinus: "plus minus"
        case .crossProduct: "vektorski produkt"
        case .transposeMark: "transponirano"
        case .angleSign: "kot"
        case .parallel: "vzporedna vezava"
        default: MathRowConverter.plainText(MathRow([.symbol(s)]))
        }
    }

    /// Descriptive Slovenian function names for VoiceOver (the keys show sin, nCr, Φ …).
    static func spokenName(_ f: MathFunction) -> String {
        switch f {
        case .sin: "sinus"
        case .cos: "kosinus"
        case .tan: "tangens"
        case .cot: "kotangens"
        case .sec: "sekans"
        case .csc: "kosekans"
        case .asin: "arkus sinus"
        case .acos: "arkus kosinus"
        case .atan: "arkus tangens"
        case .acot: "arkus kotangens"
        case .asec: "arkus sekans"
        case .acsc: "arkus kosekans"
        case .sinh: "hiperbolični sinus"
        case .cosh: "hiperbolični kosinus"
        case .tanh: "hiperbolični tangens"
        case .coth: "hiperbolični kotangens"
        case .sech: "hiperbolični sekans"
        case .csch: "hiperbolični kosekans"
        case .asinh: "area sinus"
        case .acosh: "area kosinus"
        case .atanh: "area tangens"
        case .acoth: "area kotangens"
        case .asech: "area sekans"
        case .acsch: "area kosekans"
        case .exp: "eksponentna funkcija"
        case .ln: "naravni logaritem"
        case .log10: "desetiški logaritem"
        case .log2: "dvojiški logaritem"
        case .log: "logaritem"
        case .sqrt: "kvadratni koren"
        case .cbrt: "kubični koren"
        case .root: "koren"
        case .abs: "absolutna vrednost"
        case .sign: "predznak"
        case .floor: "zaokroži navzdol"
        case .ceil: "zaokroži navzgor"
        case .round: "zaokroži"
        case .frac: "neceli del"
        case .ipart: "celi del"
        case .gcd: "največji skupni delitelj"
        case .lcm: "najmanjši skupni večkratnik"
        case .mod: "ostanek pri deljenju"
        case .idiv: "celoštevilsko deljenje"
        case .nCr: "kombinacije, n nad r"
        case .nPr: "variacije"
        case .gamma: "funkcija gama"
        case .zeta: "funkcija zeta"
        case .erf: "funkcija napake"
        case .normcdf: "porazdelitvena funkcija Fi"
        case .re: "realni del"
        case .im: "imaginarni del"
        case .arg: "argument"
        case .conj: "konjugirana vrednost"
        case .degrees: "stopinje"
        case .pol: "v polarne koordinate"
        case .rec: "v pravokotne koordinate"
        case .rand: "naključno število"
        case .dice: "met kocke"
        case .coin: "met kovanca"
        case .randInt: "naključno celo število"
        case .det: "determinanta"
        case .transpose: "transponirana matrika"
        case .trace: "sled"
        case .rank: "rang"
        case .inv: "inverzna matrika"
        case .dot: "skalarni produkt"
        case .cross: "vektorski produkt"
        case .norm: "dolžina vektorja"
        case .angle: "kot med vektorjema"
        case .unit: "enotski vektor"
        case .eig: "lastne vrednosti"
        case .charpoly: "karakteristični polinom"
        case .rref: "reducirana stopničasta oblika"
        case .kernel: "jedro"
        case .binompdf: "binomska porazdelitev, verjetnost"
        case .binomcdf: "binomska porazdelitev, kumulativna"
        case .poissonpdf: "Poissonova porazdelitev, verjetnost"
        case .poissoncdf: "Poissonova porazdelitev, kumulativna"
        case .normpdf: "gostota normalne porazdelitve"
        case .invnorm: "inverzna normalna porazdelitev"
        case .tpdf: "gostota porazdelitve t"
        case .tcdf: "porazdelitvena funkcija t"
        case .invt: "inverzna porazdelitev t"
        case .chi2pdf: "gostota porazdelitve hi kvadrat"
        case .chi2cdf: "porazdelitvena funkcija hi kvadrat"
        case .invchi2: "inverzna porazdelitev hi kvadrat"
        case .fpdf: "gostota porazdelitve F"
        case .fcdf: "porazdelitvena funkcija F"
        case .invf: "inverzna porazdelitev F"
        default: f.internationalName
        }
    }
}

/// A named page of the symbol palette.
struct SymbolPage: Identifiable, Hashable {
    let id: String
    let title: String
    let keys: [KeypadKey]

    static let main = SymbolPage(id: "main", title: "Glavna", keys: [
        .abs, .symbol(.constant(.pi)), .function(.sin), .function(.cos), .function(.tan),
        .fraction, .symbol(.constant(.e)), .function(.ln), .function(.log10), .logBase,
        .sqrt, .nthRoot, .symbol(.exponent10), .inverse, .square,
        .derivative, .integral, .symbol(.factorial), .symbol(.ans), .angleMode,
    ])

    static let trigonometry = SymbolPage(id: "trig", title: "Trigonometrija", keys: [
        .function(.sin), .function(.cos), .function(.tan), .function(.cot), .symbol(.degreeMark),
        .function(.asin), .function(.acos), .function(.atan), .function(.acot), .symbol(.minuteMark),
        .function(.sec), .function(.csc), .function(.asec), .function(.acsc), .symbol(.secondMark),
        .function2(.pol), .function2(.rec), .symbol(.constant(.pi)), .function(.degrees), .angleMode,
    ])

    static let hyperbolic = SymbolPage(id: "hyp", title: "Hiperbolične", keys: [
        .function(.sinh), .function(.cosh), .function(.tanh), .function(.coth), .function(.sech),
        .function(.asinh), .function(.acosh), .function(.atanh), .function(.acoth), .function(.csch),
    ])

    static let analysis = SymbolPage(id: "analysis", title: "Analiza", keys: [
        .derivative, .derivativeAt, .partialDerivative, .integral, .indefiniteIntegral,
        .summation, .product, .limit, .limitLeft, .limitRight,
        .piecewise, .symbol(.constant(.infinity)), .symbol(.equals), .symbol(.less), .symbol(.greater),
        .symbol(.lessOrEqual), .symbol(.greaterOrEqual), .symbol(.plusMinus), .symbol(.comma), .subscriptKey,
    ])

    /// Matrices and vectors (drag the corner of a matrix to resize it).
    static let matrices = SymbolPage(id: "matrices", title: "Matrike in vektorji", keys: [
        .matrix(rows: 2, columns: 2), .matrix(rows: 3, columns: 3), .matrix(rows: 2, columns: 1), .matrix(rows: 3, columns: 1), .vectorArrow,
        .function(.det), .symbol(.transposeMark), .inverse, .function2(.dot), .symbol(.crossProduct),
        .abs, .function2(.angle), .function(.unit), .function(.rank), .function(.trace),
        .symbol(.comma), .variable("A"), .variable("B"), .variable("C"), .store,
    ])

    /// Eigenvalues, det(A − λI), Gauss–Jordan form and null space (Matematika I/II at university).
    static let linearAlgebra = SymbolPage(id: "linalg", title: "Linearna algebra", keys: [
        .matrix(rows: 2, columns: 2), .matrix(rows: 3, columns: 3), .matrix(rows: 4, columns: 4), .matrix(rows: 3, columns: 4), .matrix(rows: 3, columns: 1),
        .function(.eig), .function(.charpoly), .function(.rref), .function(.kernel), .function(.rank),
        .function(.det), .inverse, .symbol(.transposeMark), .function(.trace), .symbol(.variable("λ")),
        .variable("A"), .variable("B"), .variable("C"), .symbol(.comma), .store,
    ])

    static let greek = SymbolPage(id: "greek", title: "Grške črke", keys: [
        "α", "β", "γ", "δ", "ε", "ζ", "η", "θ", "λ", "μ", "ν", "ξ", "ρ", "σ", "τ", "φ", "ψ", "ω", "Δ", "Ω",
    ].map { KeypadKey.symbol(.variable($0)) })

    static let probability = SymbolPage(id: "probability", title: "Verjetnost", keys: [
        .function2(.nCr), .function2(.nPr), .binomial, .symbol(.factorial), .symbol(.percent),
        .functionN(.binompdf, 3), .functionN(.binomcdf, 3), .function2(.poissonpdf), .function2(.poissoncdf), .function(.normcdf),
        .function(.normpdf), .functionN(.normpdf, 3), .function(.invnorm), .functionN(.invnorm, 3), .function(.erf),
        .function(.rand), .function(.dice), .function(.coin), .function2(.randInt), .negate,
    ])

    /// Student t, χ² and F (statistics at university): densities, P(X ≤ x) and quantiles.
    static let statistics = SymbolPage(id: "statistics", title: "Porazdelitve t, χ², F", keys: [
        .function2(.tpdf), .function2(.tcdf), .function2(.invt), .function(.normcdf), .function(.invnorm),
        .function2(.chi2pdf), .function2(.chi2cdf), .function2(.invchi2), .functionN(.normpdf, 3), .functionN(.invnorm, 3),
        .functionN(.fpdf, 3), .functionN(.fcdf, 3), .functionN(.invf, 3), .function(.erf), .symbol(.factorial),
        .sqrt, .square, .symbol(.comma), .symbol(.ans), .negate,
    ])

    static let numbers = SymbolPage(id: "numbers", title: "Števila", keys: [
        .function2(.nCr), .function2(.nPr), .binomial, .symbol(.factorial), .function2(.gcd),
        .function2(.lcm), .function2(.idiv), .function2(.mod), .function(.floor), .function(.ceil),
        .function(.round), .function(.ipart), .function(.frac), .function(.sign), .symbol(.percent),
        .function(.rand), .function(.dice), .function(.coin), .function2(.randInt), .modify,
    ])

    static let complexAndSpecial = SymbolPage(id: "complex", title: "ℂ in posebne", keys: [
        .symbol(.constant(.i)), .function(.re), .function(.im), .function(.arg), .function(.conj),
        .function(.gamma), .function(.zeta), .function(.erf), .function(.normcdf), .function(.exp),
        .tenPower, .ePower, .cbrt, .function(.log2), .symbol(.ans),
        .cube, .negate, .change, .symbol(.exponent10), .angleMode,
    ])

    /// Electrical engineering: phasors r∠φ, parallel connections, the imaginary unit (i or j)
    /// and the ; for systems of node or mesh equations.
    static let electrical = SymbolPage(id: "ee", title: "Elektrotehnika", keys: [
        .symbol(.constant(.i)), .symbol(.angleSign), .symbol(.parallel), .symbol(.degreeMark), .symbol(.constant(.pi)),
        .function(.re), .function(.im), .abs, .function(.arg), .function(.conj),
        .ePower, .sqrt, .square, .inverse, .symbol(.exponent10),
        .symbol(.comma), .symbol(.equals), .symbol(.ans), .change, .angleMode,
    ])

    /// Sharp-style memories (STO/RCL A–F, X, Y, M) and ANS.
    static let variables = SymbolPage(id: "vars", title: "Spremenljivke", keys: [
        .store, .variable("A"), .variable("B"), .variable("C"), .memoryPlus,
        .symbol(.ans), .variable("D"), .variable("E"), .variable("F"), .memoryMinus,
        .change, .variable("X"), .variable("Y"), .variable("M"), .memoryRecall,
    ])

    static let all: [SymbolPage] = [.main, .trigonometry, .hyperbolic, .analysis, .matrices, .linearAlgebra, .numbers, .probability, .statistics, .complexAndSpecial, .electrical, .greek, .variables]
}
