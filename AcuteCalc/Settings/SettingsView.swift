import AcuteCore
import SwiftUI
import UIKit

/// App settings (General, History, Haptics like the original, plus graphs and number display).
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false

    private static let surfaceResolutions = [96, 128, 160, 224, 320]

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section("Videz") {
                    Picker("Tema", selection: $settings.appearance) {
                        ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Barva poudarka", selection: $settings.accent) {
                        ForEach(AccentTheme.allCases) { theme in
                            Label {
                                Text(theme.title)
                            } icon: {
                                Image(systemName: "circle.fill").foregroundStyle(theme.color)
                            }
                            .tag(theme)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    AppIconPicker()
                }

                Section {
                    Picker("Znak za množenje", selection: $settings.multiplication) {
                        ForEach(MultiplicationSign.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Zapis funkcij", selection: $settings.notation) {
                        ForEach(FunctionNotation.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Decimalna vejica", isOn: $settings.decimalComma)
                    Toggle("Združuj števke po tri", isOn: $settings.digitGrouping)
                } header: {
                    Text("Splošno")
                } footer: {
                    Text("Decimalna vejica je slovenski zapis (3,14). Argumente funkcij takrat ločuje podpičje.")
                }

                Section {
                    Picker("Kotne enote", selection: $settings.angleUnit) {
                        ForEach(AngleUnit.allCases, id: \.self) { Text($0.shortLabel).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Prikaz števil", selection: $settings.displayMode) {
                        ForEach(DisplayMode.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    switch settings.displayMode {
                    case .fix, .sci, .eng:
                        Stepper("Decimalna mesta: \(settings.fixedPlaces)", value: $settings.fixedPlaces, in: 0...9)
                    case .norm1, .norm2:
                        Stepper("Značilna mesta: \(settings.significantDigits)", value: $settings.significantDigits, in: 4...15)
                    }
                    Toggle("Kompleksni rezultati", isOn: $settings.complexResults)
                    Toggle("Imaginarna enota j (elektrotehnika)", isOn: $settings.imaginaryJ)
                    Toggle("Periodična decimalna števila", isOn: $settings.recurringDecimals)
                } header: {
                    Text("Računanje")
                } footer: {
                    Text("NORM1, NORM2, FIX, SCI in ENG delujejo kot na kalkulatorju Sharp EL-W531. Računa se z dvojno natančnostjo (π na 15 decimalk), točni rezultati ostanejo v ulomkih in korenih.")
                }

                Section("Tipkovnica") {
                    Toggle("Haptični odziv", isOn: $settings.haptics)
                    LabeledContent("Zamik ponavljanja") {
                        Slider(value: $settings.keyRepeatDelay, in: 0.2...1.0, step: 0.05)
                            .frame(maxWidth: 220)
                    }
                    LabeledContent("Hitrost ponavljanja") {
                        Slider(value: $settings.keyRepeatRate, in: 0.03...0.3, step: 0.01)
                            .frame(maxWidth: 220)
                    }
                }

                Section("Zgodovina") {
                    Toggle("Dodaj ob potrditvi (=)", isOn: $settings.addOnEnter)
                    Toggle("Dodaj ob brisanju (C)", isOn: $settings.addOnClear)
                    Toggle("Dodaj grafe", isOn: $settings.addGraphsToHistory)
                    Toggle("Dodaj nedokončane izraze", isOn: $settings.addIncomplete)
                    Button("Počisti starejše (obdrži 20)") { store.clearHistory(keepingRecent: 20) }
                        .disabled(store.history.count <= 20)
                    Button("Počisti zgodovino", role: .destructive) { confirmClear = true }
                        .disabled(store.history.isEmpty)
                }

                Section {
                    Toggle("Enako merilo na oseh", isOn: $settings.equalAxes)
                    Toggle("Os x v večkratnikih π pri kotnih funkcijah", isOn: $settings.trigPiAxis)
                    Toggle("Logaritemska os x", isOn: $settings.logarithmicX)
                    Toggle("Logaritemska os y", isOn: $settings.logarithmicY)
                    Toggle("Posebne točke (ničle, ekstremi …)", isOn: $settings.showSpecialPoints)
                    LabeledContent("Debelina črt") {
                        Slider(value: $settings.graphLineWidth, in: 1.5...6, step: 0.5)
                            .frame(maxWidth: 220)
                    }
                    Picker("Ločljivost 3D ploskev", selection: $settings.surfaceResolution) {
                        ForEach(Self.surfaceResolutions, id: \.self) { Text("\($0) × \($0)").tag($0) }
                    }
                    Picker("Upodabljanje", selection: $settings.rendererBackend) {
                        ForEach(RendererBackendKind.allCases) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text("Grafi")
                } footer: {
                    Text("Z enakim merilom ostane krožnica okrogla; brez njega lahko s ščipom vzdolž ene osi raztegneš samo to os. Na logaritemski osi (zavihek Grafi) je vsaka dekada, od 1 do 10, od 10 do 100 …, enako dolga, zato gre na en graf tudi količina čez veliko potenc števila 10, npr. frekvenca od 10⁰ do 10²⁰ Hz; vrednosti ≤ 0 se na njej ne rišejo, enako merilo pa velja le, ko sta obe osi linearni ali obe logaritemski. Grafe riše GPU (Metal) pri do 120 Hz na zaslonih ProMotion.")
                }

                UpdateSettingsSection()

                Section("O aplikaciji") {
                    LabeledContent("Različica", value: Self.versionString)
                    LabeledContent("Povezava", value: "Ni potrebna – vse se računa na napravi")
                    Text("Po zgledu aplikacije Acute Calc (Andrew Zheng), na novo napisano za iOS 27 s SwiftUI, Liquid Glass in Metal 4.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Nastavitve")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .confirmationDialog("Počistim celotno zgodovino?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Počisti vse", role: .destructive) { store.clearHistory() }
            }
        }
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

/// The four app icons (like the original: default, classic, midnight, stealth).
struct AppIconPicker: View {
    struct Choice: Identifiable {
        let name: String?
        let title: String
        let colors: [Color]
        let curve: Color
        let axes: Color
        var id: String { name ?? "AppIcon" }
    }

    static let choices: [Choice] = [
        Choice(name: nil, title: "Acute", colors: [Color(red: 0.02, green: 0.12, blue: 0.36), Color(red: 0, green: 0.58, blue: 1)], curve: .white, axes: .white.opacity(0.6)),
        Choice(name: "AppIcon-Classic", title: "Klasična", colors: [Color(red: 0.96, green: 0.98, blue: 1), Color(red: 0.78, green: 0.87, blue: 1)], curve: Color(red: 0.04, green: 0.39, blue: 0.84), axes: .black.opacity(0.45)),
        Choice(name: "AppIcon-Midnight", title: "Polnočna", colors: [Color(red: 0.01, green: 0.02, blue: 0.07), Color(red: 0.09, green: 0.10, blue: 0.29)], curve: Color(red: 0.36, green: 0.88, blue: 1), axes: Color(red: 0.56, green: 0.64, blue: 1).opacity(0.45)),
        Choice(name: "AppIcon-Stealth", title: "Prikrita", colors: [.black, Color(red: 0.12, green: 0.12, blue: 0.13)], curve: Color(white: 0.9), axes: .gray.opacity(0.35)),
    ]

    @State private var current: String? = UIApplication.shared.alternateIconName
    @State private var failed = false

    var body: some View {
        if UIApplication.shared.supportsAlternateIcons {
            HStack(spacing: 14) {
                ForEach(Self.choices) { choice in
                    Button {
                        select(choice)
                    } label: {
                        VStack(spacing: 6) {
                            AppIconPreview(choice: choice)
                                .frame(width: 58, height: 58)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(current == choice.name ? Color.accentColor : .clear, lineWidth: 3)
                                }
                            Text(choice.title).font(.caption2)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ikona \(choice.title)")
                    .accessibilityAddTraits(current == choice.name ? .isSelected : [])
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .alert("Ikone ni bilo mogoče zamenjati", isPresented: $failed) {
                Button("V redu", role: .cancel) {}
            }
        }
    }

    private func select(_ choice: Choice) {
        guard choice.name != current else { return }
        Task {
            do {
                try await UIApplication.shared.setAlternateIconName(choice.name)
                current = UIApplication.shared.alternateIconName
            } catch {
                failed = true
            }
        }
    }
}

/// A drawn preview of an app icon (gradient, axes and the curve).
struct AppIconPreview: View {
    let choice: AppIconPicker.Choice
    var cornerRadius: CGFloat = 14

    var body: some View {
        Canvas { context, size in
            let s = size.width / 1024
            var axes = Path()
            axes.move(to: CGPoint(x: 120 * s, y: 512 * s)); axes.addLine(to: CGPoint(x: 904 * s, y: 512 * s))
            axes.move(to: CGPoint(x: 512 * s, y: 120 * s)); axes.addLine(to: CGPoint(x: 512 * s, y: 904 * s))
            context.stroke(axes, with: .color(choice.axes), style: StrokeStyle(lineWidth: 22 * s, lineCap: .round))
            var curve = Path()
            curve.move(to: CGPoint(x: 150 * s, y: 600 * s))
            curve.addCurve(to: CGPoint(x: 420 * s, y: 300 * s), control1: CGPoint(x: 250 * s, y: 600 * s), control2: CGPoint(x: 300 * s, y: 300 * s))
            curve.addCurve(to: CGPoint(x: 690 * s, y: 724 * s), control1: CGPoint(x: 540 * s, y: 300 * s), control2: CGPoint(x: 560 * s, y: 724 * s))
            curve.addCurve(to: CGPoint(x: 880 * s, y: 420 * s), control1: CGPoint(x: 790 * s, y: 724 * s), control2: CGPoint(x: 830 * s, y: 470 * s))
            context.stroke(curve, with: .color(choice.curve), style: StrokeStyle(lineWidth: 78 * s, lineCap: .round, lineJoin: .round))
        }
        .background(LinearGradient(colors: choice.colors, startPoint: .top, endPoint: .bottom))
        .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }
}
