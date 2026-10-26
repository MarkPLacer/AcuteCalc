import Foundation

/// One formula of the formula sheets, written in LaTeX (rendered by the math layout engine).
public struct Formula: Identifiable, Hashable, Sendable {
    public var title: String
    public var latex: String
    public var note: String?
    public var id: String { title + latex }

    public init(_ title: String, _ latex: String, note: String? = nil) {
        self.title = title
        self.latex = latex
        self.note = note
    }
}

public struct FormulaSection: Identifiable, Hashable, Sendable {
    public var title: String
    public var systemImage: String
    public var formulas: [Formula]
    public var id: String { title }

    public init(title: String, systemImage: String, formulas: [Formula]) {
        self.title = title
        self.systemImage = systemImage
        self.formulas = formulas
    }
}

public enum FormulaSubject: String, CaseIterable, Identifiable, Sendable {
    case mathematics = "Matematika"
    case physics = "Fizika"
    public var id: String { rawValue }
}

/// Formulas of the Slovenian general matura (mathematics and physics), organised by topic.
public enum FormulaLibrary {
    public static func sections(_ subject: FormulaSubject) -> [FormulaSection] {
        subject == .mathematics ? mathematics : physics
    }

    public static let mathematics: [FormulaSection] = [
        FormulaSection(title: "Algebra", systemImage: "x.squareroot", formulas: [
            Formula("Kvadrat dvočlenika", #"(a\pm b)^{2}=a^{2}\pm 2ab+b^{2}"#),
            Formula("Kub dvočlenika", #"(a\pm b)^{3}=a^{3}\pm 3a^{2}b+3ab^{2}\pm b^{3}"#),
            Formula("Razlika kvadratov", #"a^{2}-b^{2}=(a-b)(a+b)"#),
            Formula("Vsota in razlika kubov", #"a^{3}\pm b^{3}=(a\pm b)(a^{2}\mp ab+b^{2})"#),
            Formula("Množenje potenc", #"a^{m}\cdot a^{n}=a^{m+n}"#),
            Formula("Potenciranje potence", #"(a^{m})^{n}=a^{mn}"#),
            Formula("Negativni eksponent", #"a^{-n}=\frac{1}{a^{n}}"#),
            Formula("Ulomljeni eksponent", #"a^{\frac{m}{n}}=\sqrt[n]{a^{m}}"#),
            Formula("Binomski izrek", #"(a+b)^{n}=\sum_{k=0}^{n}\binom{n}{k}a^{n-k}b^{k}"#),
        ]),
        FormulaSection(title: "Logaritmi in eksponentna funkcija", systemImage: "function", formulas: [
            Formula("Definicija", #"\log_{a}x=y\Leftrightarrow a^{y}=x"#),
            Formula("Logaritem produkta", #"\log_{a}(xy)=\log_{a}x+\log_{a}y"#),
            Formula("Logaritem količnika", #"\log_{a}\left(\frac{x}{y}\right)=\log_{a}x-\log_{a}y"#),
            Formula("Logaritem potence", #"\log_{a}x^{n}=n\log_{a}x"#),
            Formula("Prehod na novo osnovo", #"\log_{a}x=\frac{\log_{b}x}{\log_{b}a}"#),
            Formula("Eksponentna rast", #"N=N_{0}e^{kt}"#),
        ]),
        FormulaSection(title: "Linearna in kvadratna funkcija", systemImage: "chart.line.uptrend.xyaxis", formulas: [
            Formula("Smerni koeficient", #"k=\frac{y_{2}-y_{1}}{x_{2}-x_{1}}"#),
            Formula("Premica skozi točko", #"y-y_{1}=k(x-x_{1})"#),
            Formula("Kot med premicama", #"\tan\varphi=\left|\frac{k_{2}-k_{1}}{1+k_{1}k_{2}}\right|"#),
            Formula("Razdalja točk", #"d=\sqrt{(x_{2}-x_{1})^{2}+(y_{2}-y_{1})^{2}}"#),
            Formula("Razdalja točke od premice", #"d=\frac{|ax_{0}+by_{0}+c|}{\sqrt{a^{2}+b^{2}}}"#),
            Formula("Splošna oblika", #"f(x)=ax^{2}+bx+c"#),
            Formula("Temenska oblika", #"f(x)=a(x-p)^{2}+q"#),
            Formula("Ničelna oblika", #"f(x)=a(x-x_{1})(x-x_{2})"#),
            Formula("Diskriminanta", #"D=b^{2}-4ac"#),
            Formula("Rešitvi kvadratne enačbe", #"x_{1,2}=\frac{-b\pm\sqrt{D}}{2a}"#),
            Formula("Teme", #"p=-\frac{b}{2a},\;q=-\frac{D}{4a}"#),
            Formula("Vietovi pravili", #"x_{1}+x_{2}=-\frac{b}{a},\;x_{1}x_{2}=\frac{c}{a}"#),
        ]),
        FormulaSection(title: "Kotne funkcije", systemImage: "angle", formulas: [
            Formula("Osnovna zveza", #"\sin^{2}x+\cos^{2}x=1"#),
            Formula("Tangens", #"\tan x=\frac{\sin x}{\cos x}"#),
            Formula("Zveza tangensa in kosinusa", #"1+\tan^{2}x=\frac{1}{\cos^{2}x}"#),
            Formula("Adicijski izrek za sinus", #"\sin(x\pm y)=\sin x\cos y\pm\cos x\sin y"#),
            Formula("Adicijski izrek za kosinus", #"\cos(x\pm y)=\cos x\cos y\mp\sin x\sin y"#),
            Formula("Adicijski izrek za tangens", #"\tan(x\pm y)=\frac{\tan x\pm\tan y}{1\mp\tan x\tan y}"#),
            Formula("Dvojni kot (sinus)", #"\sin(2x)=2\sin x\cos x"#),
            Formula("Dvojni kot (kosinus)", #"\cos(2x)=\cos^{2}x-\sin^{2}x"#),
            Formula("Polovični kot", #"\sin^{2}\frac{x}{2}=\frac{1-\cos x}{2}"#),
            Formula("Vsota sinusov", #"\sin x+\sin y=2\sin\frac{x+y}{2}\cos\frac{x-y}{2}"#),
            Formula("Vsota kosinusov", #"\cos x+\cos y=2\cos\frac{x+y}{2}\cos\frac{x-y}{2}"#),
        ]),
        FormulaSection(title: "Geometrija v ravnini", systemImage: "triangle", formulas: [
            Formula("Pitagorov izrek", #"c^{2}=a^{2}+b^{2}"#),
            Formula("Evklidov izrek", #"a^{2}=c\cdot a_{1}"#),
            Formula("Višinski izrek", #"v^{2}=a_{1}b_{1}"#),
            Formula("Sinusni izrek", #"\frac{a}{\sin\alpha}=\frac{b}{\sin\beta}=\frac{c}{\sin\gamma}=2R"#),
            Formula("Kosinusni izrek", #"a^{2}=b^{2}+c^{2}-2bc\cos\alpha"#),
            Formula("Ploščina trikotnika", #"S=\frac{a\cdot v_{a}}{2}=\frac{ab\sin\gamma}{2}"#),
            Formula("Heronov obrazec", #"S=\sqrt{s(s-a)(s-b)(s-c)},\;s=\frac{a+b+c}{2}"#),
            Formula("Polmer očrtane krožnice", #"R=\frac{abc}{4S}"#),
            Formula("Polmer včrtane krožnice", #"r=\frac{S}{s}"#),
            Formula("Krog", #"o=2\pi r,\;S=\pi r^{2}"#),
            Formula("Krožni lok", #"l=\frac{\pi r\alpha}{180^{\circ}}"#),
            Formula("Krožni izsek", #"S=\frac{\pi r^{2}\alpha}{360^{\circ}}"#),
        ]),
        FormulaSection(title: "Geometrija v prostoru", systemImage: "cube", formulas: [
            Formula("Prizma", #"V=O\cdot v,\;P=2O+S_{pl}"#),
            Formula("Valj", #"V=\pi r^{2}v,\;P=2\pi r(r+v)"#),
            Formula("Piramida", #"V=\frac{O\cdot v}{3}"#),
            Formula("Stožec", #"V=\frac{\pi r^{2}v}{3},\;P=\pi r(r+s)"#),
            Formula("Krogla", #"V=\frac{4\pi r^{3}}{3},\;P=4\pi r^{2}"#),
            Formula("Prostornina vrtenine", #"V=\pi\int_{a}^{b}f(x)^{2}\,dx"#),
        ]),
        FormulaSection(title: "Vektorji", systemImage: "arrow.up.right", formulas: [
            Formula("Dolžina vektorja", #"|\vec{a}|=\sqrt{x^{2}+y^{2}+z^{2}}"#),
            Formula("Skalarni produkt", #"\vec{a}\cdot\vec{b}=|\vec{a}||\vec{b}|\cos\varphi=x_{1}x_{2}+y_{1}y_{2}+z_{1}z_{2}"#),
            Formula("Kot med vektorjema", #"\cos\varphi=\frac{\vec{a}\cdot\vec{b}}{|\vec{a}||\vec{b}|}"#),
            Formula("Pravokotnost", #"\vec{a}\perp\vec{b}\Leftrightarrow\vec{a}\cdot\vec{b}=0"#),
        ]),
        FormulaSection(title: "Zaporedja in obresti", systemImage: "list.number", formulas: [
            Formula("Aritmetično zaporedje", #"a_{n}=a_{1}+(n-1)d"#),
            Formula("Vsota aritmetičnega zaporedja", #"s_{n}=\frac{n}{2}(a_{1}+a_{n})"#),
            Formula("Geometrijsko zaporedje", #"a_{n}=a_{1}q^{n-1}"#),
            Formula("Vsota geometrijskega zaporedja", #"s_{n}=a_{1}\frac{q^{n}-1}{q-1}"#),
            Formula("Neskončna geometrijska vrsta", #"s=\frac{a_{1}}{1-q},\;|q|<1"#),
            Formula("Obrestno obrestovanje", #"G_{n}=G_{0}\left(1+\frac{p}{100}\right)^{n}"#),
            Formula("Navadne obresti", #"o=\frac{G_{0}pt}{100}"#),
        ]),
        FormulaSection(title: "Kombinatorika, verjetnost, statistika", systemImage: "dice", formulas: [
            Formula("Permutacije", #"P_{n}=n!"#),
            Formula("Variacije", #"V_{n}^{r}=\frac{n!}{(n-r)!}"#),
            Formula("Variacije s ponavljanjem", #"V_{n}^{(r)}=n^{r}"#),
            Formula("Kombinacije", #"C_{n}^{r}=\binom{n}{r}=\frac{n!}{r!(n-r)!}"#),
            Formula("Verjetnost unije", #"P(A\cup B)=P(A)+P(B)-P(A\cap B)"#),
            Formula("Pogojna verjetnost", #"P(A\mid B)=\frac{P(A\cap B)}{P(B)}"#),
            Formula("Binomska porazdelitev", #"P(X=k)=\binom{n}{k}p^{k}(1-p)^{n-k}"#),
            Formula("Pričakovana vrednost (binomska)", #"E(X)=np,\;D(X)=np(1-p)"#),
            Formula("Standardizacija", #"z=\frac{x-\mu}{\sigma}"#),
            Formula("Aritmetična sredina", #"\bar{x}=\frac{x_{1}+x_{2}+\dots+x_{n}}{n}"#),
            Formula("Standardni odklon", #"\sigma=\sqrt{\frac{(x_{1}-\bar{x})^{2}+\dots+(x_{n}-\bar{x})^{2}}{n}}"#),
        ]),
        FormulaSection(title: "Kompleksna števila", systemImage: "circle.circle", formulas: [
            Formula("Algebrska oblika", #"z=a+bi,\;i^{2}=-1"#),
            Formula("Absolutna vrednost", #"|z|=\sqrt{a^{2}+b^{2}}"#),
            Formula("Konjugirano število", #"\bar{z}=a-bi"#),
            Formula("Polarna oblika", #"z=r(\cos\varphi+i\sin\varphi)"#),
            Formula("De Moivrov obrazec", #"z^{n}=r^{n}(\cos(n\varphi)+i\sin(n\varphi))"#),
        ]),
        FormulaSection(title: "Odvod", systemImage: "chart.line.text.clipboard", formulas: [
            Formula("Potenca", #"(x^{n})'=nx^{n-1}"#),
            Formula("Sinus in kosinus", #"(\sin x)'=\cos x,\;(\cos x)'=-\sin x"#),
            Formula("Tangens", #"(\tan x)'=\frac{1}{\cos^{2}x}"#),
            Formula("Eksponentna funkcija", #"(e^{x})'=e^{x},\;(a^{x})'=a^{x}\ln a"#),
            Formula("Logaritem", #"(\ln x)'=\frac{1}{x},\;(\log_{a}x)'=\frac{1}{x\ln a}"#),
            Formula("Odvod produkta", #"(uv)'=u'v+uv'"#),
            Formula("Odvod količnika", #"\left(\frac{u}{v}\right)'=\frac{u'v-uv'}{v^{2}}"#),
            Formula("Odvod kompozituma", #"(f(g(x)))'=f'(g(x))\cdot g'(x)"#),
            Formula("Tangenta", #"y-f(x_{0})=f'(x_{0})(x-x_{0})"#),
            Formula("Znamenita limita", #"\lim_{x\to 0}\frac{\sin x}{x}=1"#),
        ]),
        FormulaSection(title: "Integral", systemImage: "sum", formulas: [
            Formula("Potenca", #"\int x^{n}\,dx=\frac{x^{n+1}}{n+1}+C"#),
            Formula("Recipročna funkcija", #"\int\frac{1}{x}\,dx=\ln\left|x\right|+C"#),
            Formula("Eksponentna funkcija", #"\int e^{x}\,dx=e^{x}+C"#),
            Formula("Sinus in kosinus", #"\int\sin x\,dx=-\cos x+C"#),
            Formula("Newton–Leibniz", #"\int_{a}^{b}f(x)\,dx=F(b)-F(a)"#),
            Formula("Ploščina med krivuljama", #"S=\int_{a}^{b}(f(x)-g(x))\,dx"#),
        ]),
    ]

    public static let physics: [FormulaSection] = [
        FormulaSection(title: "Kinematika", systemImage: "speedometer", formulas: [
            Formula("Hitrost", #"v=\frac{\Delta s}{\Delta t}"#),
            Formula("Pospešek", #"a=\frac{\Delta v}{\Delta t}"#),
            Formula("Enakomerno pospešeno gibanje", #"v=v_{0}+at"#),
            Formula("Pot", #"s=v_{0}t+\frac{at^{2}}{2}"#),
            Formula("Hitrost in pot", #"v^{2}=v_{0}^{2}+2as"#),
            Formula("Prosti pad", #"h=\frac{gt^{2}}{2}"#),
            Formula("Kotna hitrost", #"\omega=\frac{2\pi}{t_{0}}=2\pi\nu"#),
            Formula("Obodna hitrost", #"v=\omega r"#),
            Formula("Radialni pospešek", #"a_{r}=\frac{v^{2}}{r}=\omega^{2}r"#),
        ]),
        FormulaSection(title: "Dinamika in gravitacija", systemImage: "arrow.right.to.line", formulas: [
            Formula("Newtonov zakon", #"\vec{F}=m\vec{a}"#),
            Formula("Teža", #"F_{g}=mg"#),
            Formula("Trenje", #"F_{tr}=k_{tr}F_{n}"#),
            Formula("Gibalna količina", #"\vec{G}=m\vec{v}"#),
            Formula("Sunek sile", #"\vec{F}\Delta t=\Delta\vec{G}"#),
            Formula("Centripetalna sila", #"F_{r}=\frac{mv^{2}}{r}"#),
            Formula("Gravitacijski zakon", #"F=G\frac{m_{1}m_{2}}{r^{2}}"#),
            Formula("Prožnostna sila", #"F=kx"#),
            Formula("Navor", #"M=rF\sin\varphi"#),
        ]),
        FormulaSection(title: "Delo, energija, moč", systemImage: "bolt", formulas: [
            Formula("Delo", #"A=Fs\cos\varphi"#),
            Formula("Kinetična energija", #"W_{k}=\frac{mv^{2}}{2}"#),
            Formula("Potencialna energija", #"W_{p}=mgh"#),
            Formula("Prožnostna energija", #"W_{pr}=\frac{kx^{2}}{2}"#),
            Formula("Izrek o kinetični in potencialni energiji", #"A=\Delta W_{k}+\Delta W_{p}+\Delta W_{pr}"#),
            Formula("Moč", #"P=\frac{A}{t}"#),
            Formula("Izkoristek", #"\eta=\frac{P_{izh}}{P_{vh}}"#),
        ]),
        FormulaSection(title: "Tlak in tekočine", systemImage: "drop", formulas: [
            Formula("Tlak", #"p=\frac{F}{S}"#),
            Formula("Hidrostatični tlak", #"p=\rho gh"#),
            Formula("Vzgon", #"F_{vzg}=\rho_{t}gV"#),
            Formula("Gostota", #"\rho=\frac{m}{V}"#),
        ]),
        FormulaSection(title: "Termodinamika", systemImage: "thermometer.medium", formulas: [
            Formula("Temperatura", #"T=t+273\,K"#),
            Formula("Toplota", #"Q=mc\Delta T"#),
            Formula("Talilna toplota", #"Q=mq_{t}"#),
            Formula("Plinska enačba", #"pV=\frac{m}{M}RT"#),
            Formula("Prvi zakon termodinamike", #"\Delta W_{n}=A+Q"#),
            Formula("Linearni razteznost", #"\Delta l=\alpha l\Delta T"#),
            Formula("Prevajanje toplote", #"P=\lambda S\frac{\Delta T}{d}"#),
            Formula("Stefanov zakon", #"j=\sigma T^{4}"#),
            Formula("Izkoristek toplotnega stroja", #"\eta=\frac{A}{Q_{1}}\le 1-\frac{T_{2}}{T_{1}}"#),
        ]),
        FormulaSection(title: "Elektrika", systemImage: "bolt.circle", formulas: [
            Formula("Coulombov zakon", #"F=\frac{e_{1}e_{2}}{4\pi\varepsilon_{0}r^{2}}"#),
            Formula("Električna poljska jakost", #"E=\frac{F}{e}"#),
            Formula("Napetost", #"U=\frac{A_{e}}{e}=Ed"#),
            Formula("Kapaciteta", #"C=\frac{e}{U},\;C=\frac{\varepsilon\varepsilon_{0}S}{d}"#),
            Formula("Energija kondenzatorja", #"W_{e}=\frac{CU^{2}}{2}"#),
            Formula("Električni tok", #"I=\frac{e}{t}"#),
            Formula("Ohmov zakon", #"U=RI"#),
            Formula("Upor žice", #"R=\frac{\zeta l}{S}"#),
            Formula("Električna moč", #"P=UI=RI^{2}"#),
            Formula("Zaporedna vezava", #"R=R_{1}+R_{2}"#),
            Formula("Vzporedna vezava", #"\frac{1}{R}=\frac{1}{R_{1}}+\frac{1}{R_{2}}"#),
        ]),
        FormulaSection(title: "Magnetizem", systemImage: "point.3.connected.trianglepath.dotted", formulas: [
            Formula("Sila na vodnik", #"F=IlB\sin\varphi"#),
            Formula("Sila na naboj", #"F=evB\sin\varphi"#),
            Formula("Gostota polja ravnega vodnika", #"B=\frac{\mu_{0}I}{2\pi r}"#),
            Formula("Gostota polja tuljave", #"B=\frac{\mu_{0}NI}{l}"#),
            Formula("Magnetni pretok", #"\Phi=BS\cos\varphi"#),
            Formula("Indukcijski zakon", #"U_{i}=-N\frac{\Delta\Phi}{\Delta t}"#),
            Formula("Induktivnost", #"L=\frac{N\Phi}{I}"#),
            Formula("Energija tuljave", #"W_{m}=\frac{LI^{2}}{2}"#),
            Formula("Transformator", #"\frac{U_{1}}{U_{2}}=\frac{N_{1}}{N_{2}}"#),
        ]),
        FormulaSection(title: "Nihanje in valovanje", systemImage: "waveform", formulas: [
            Formula("Nihanje na vzmeti", #"t_{0}=2\pi\sqrt{\frac{m}{k}}"#),
            Formula("Matematično nihalo", #"t_{0}=2\pi\sqrt{\frac{l}{g}}"#),
            Formula("Odmik", #"x=x_{0}\sin(\omega t)"#),
            Formula("Nihajni krog", #"t_{0}=2\pi\sqrt{LC}"#),
            Formula("Valovanje", #"c=\lambda\nu"#),
            Formula("Hitrost na struni", #"c=\sqrt{\frac{F}{\mu}}"#),
            Formula("Dopplerjev pojav", #"\nu'=\nu\frac{c}{c\mp v}"#),
        ]),
        FormulaSection(title: "Optika", systemImage: "eyeglasses", formulas: [
            Formula("Lomni količnik", #"n=\frac{c_{0}}{c}"#),
            Formula("Lomni zakon", #"\frac{\sin\alpha}{\sin\beta}=\frac{n_{2}}{n_{1}}"#),
            Formula("Enačba leče", #"\frac{1}{f}=\frac{1}{a}+\frac{1}{b}"#),
            Formula("Povečava", #"M=\frac{b}{a}"#),
            Formula("Uklonska mreža", #"d\sin\alpha=N\lambda"#),
        ]),
        FormulaSection(title: "Moderna fizika", systemImage: "atom", formulas: [
            Formula("Energija fotona", #"W_{f}=h\nu"#),
            Formula("Fotoefekt", #"h\nu=A_{i}+W_{k}"#),
            Formula("Masa in energija", #"W=mc^{2}"#),
            Formula("De Brogliejeva valovna dolžina", #"\lambda=\frac{h}{G}"#),
            Formula("Razpadni zakon", #"N=N_{0}2^{-\frac{t}{t_{1/2}}}"#),
            Formula("Aktivnost", #"A=\lambda N"#),
            Formula("Razpolovni čas", #"t_{1/2}=\frac{\ln 2}{\lambda}"#),
        ]),
    ]
}
