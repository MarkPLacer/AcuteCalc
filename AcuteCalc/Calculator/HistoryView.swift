import AcuteCore
import SwiftUI
import UIKit

/// Past calculations; tapping one loads it back into the editor.
struct HistoryList: View {
    let model: CalculatorModel
    var showsHeader = false
    var onSelect: () -> Void = {}
    @Environment(AppStore.self) private var store
    @State private var confirmClear = false

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                HStack {
                    Text("Zgodovina").font(.headline)
                    Spacer()
                    clearMenu
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 6)
            }
            if store.history.isEmpty {
                ContentUnavailableView("Ni zgodovine", systemImage: "clock.arrow.circlepath",
                                       description: Text("Izračuni se shranijo, ko pritisneš =."))
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.history) { entry in
                        Button {
                            model.load(entry)
                            onSelect()
                        } label: {
                            HistoryRow(entry: entry)
                        }
                        .listRowBackground(Color.clear)
                        .contextMenu { contextMenu(for: entry) }
                    }
                    .onDelete { offsets in store.history.remove(atOffsets: offsets) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .toolbar {
            if !showsHeader {
                ToolbarItem(placement: .topBarTrailing) { clearMenu }
            }
        }
        .confirmationDialog("Počistim celotno zgodovino?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Počisti vse", role: .destructive) { store.clearHistory() }
            Button("Obdrži zadnjih 20") { store.clearHistory(keepingRecent: 20) }
        }
    }

    private var clearMenu: some View {
        Menu {
            Button("Počisti starejše (obdrži 20)", systemImage: "clock.badge.xmark") { store.clearHistory(keepingRecent: 20) }
            Button("Počisti vse", systemImage: "trash", role: .destructive) { confirmClear = true }
        } label: {
            Label("Počisti", systemImage: "trash")
        }
        .disabled(store.history.isEmpty)
    }

    @ViewBuilder
    private func contextMenu(for entry: HistoryEntry) -> some View {
        Button("Vstavi izraz", systemImage: "text.insert") {
            model.insert(row: entry.expression)
            onSelect()
        }
        if entry.exactResult != nil || entry.numericValue != nil {
            Button("Vstavi rezultat", systemImage: "equal.square") {
                if let exact = entry.exactResult {
                    model.insert(row: exact)
                } else if let value = entry.numericValue {
                    model.insert(row: MathRowConverter.rowPreservingStructure(for: .decimal(value)))
                }
                onSelect()
            }
        }
        Button("Kopiraj izraz", systemImage: "doc.on.doc") {
            // Structured math as well, so ∫, lim and ∂ paste back into the calculator.
            MathClipboard.copy(entry.expression, decimalComma: model.settings?.decimalComma ?? true)
        }
        if !entry.resultText.isEmpty {
            Button("Kopiraj rezultat", systemImage: "doc.on.clipboard") {
                UIPasteboard.general.string = entry.resultText
            }
        }
        Divider()
        Button("Izbriši", systemImage: "trash", role: .destructive) {
            store.history.removeAll { $0.id == entry.id }
        }
    }
}

struct HistoryRow: View {
    let entry: HistoryEntry

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                MathText(row: entry.expression, fontSize: 21)
                MathText(row: entry.expression, fontSize: 16)
                MathText(row: entry.expression, fontSize: 12)
            }
            HStack(spacing: 6) {
                if entry.isGraph {
                    Image(systemName: "chart.xyaxis.line")
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Graf")
                }
                Text(entry.date, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 8)
                if let exact = entry.exactResult {
                    Text("=").foregroundStyle(.secondary)
                    ViewThatFits(in: .horizontal) {
                        MathText(row: exact, fontSize: 19, color: .accentColor)
                        MathText(row: exact, fontSize: 13, color: .accentColor)
                    }
                    if let value = entry.numericValue, !entry.resultText.isEmpty, MathRowConverter.plainText(exact) != entry.resultText {
                        Text("≈ \(NumberFormatting.plain(value))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else if !entry.resultText.isEmpty, !entry.isGraph || entry.resultText != "graf" {
                    Text("= \(entry.resultText)")
                        .font(.body.monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.vertical, 4)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// iPad variables column: STO, the memories A–F, X, Y, M and ANS (like the original's variable panel).
struct VariablesPanel: View {
    let model: CalculatorModel
    @Environment(AppStore.self) private var store
    @Environment(AppSettings.self) private var settings

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    model.press(.store)
                } label: {
                    Label("STO", systemImage: "square.and.arrow.down")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.glassProminent)
                .tint(model.storeMode ? settings.accent.color : .gray.opacity(0.5))
                // "STO" and "ANS" would be read as words; VoiceOver gets the keys' names.
                .accessibilityLabel(KeypadKey.store.accessibilityName)
                // Armed STO is otherwise shown only by the tint.
                .accessibilityAddTraits(model.storeMode ? .isSelected : [])
                .accessibilityHint("Shrani rezultat v izbrano spremenljivko")
                Button { model.press(.symbol(.ans)) } label: {
                    Text("ANS")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 36)
                }
                .buttonStyle(.glass)
                .accessibilityLabel(KeypadKey.symbol(.ans).accessibilityName)
            }
            ScrollView {
                // One container for the glass tiles (as in MainKeypad); its spacing equals the grid
                // spacing, so the tiles do not blend at rest.
                GlassEffectContainer(spacing: 8) {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(AppStore.memoryNames, id: \.self) { name in
                            VariableTile(name: name, value: value(of: name), armed: model.storeMode) {
                                model.press(.variable(name))
                            }
                            .contextMenu {
                                if name == "M" {
                                    Button("Ponastavi M", systemImage: "arrow.counterclockwise") { store.memory = 0 }
                                } else if store.variables[name] != nil {
                                    Button("Izbriši \(name)", systemImage: "trash", role: .destructive) { store.variables[name] = nil }
                                }
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            HStack(spacing: 8) {
                memoryButton("M+", .memoryPlus)
                memoryButton("M−", .memoryMinus)
                memoryButton("RCL", .memoryRecall)
            }
            .buttonStyle(.glass)
        }
    }

    private func memoryButton(_ title: String, _ key: KeypadKey) -> some View {
        Button { model.press(key) } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 32)
        }
        .accessibilityLabel(key.accessibilityName)
    }

    private func value(of name: String) -> Double? {
        if name == "M" { return store.memory }
        return store.variables[name]?.value
    }
}

struct VariableTile: View {
    let name: String
    let value: Double?
    var armed = false
    var action: () -> Void
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                MathText(row: MathRow([.symbol(.variable(name))]), fontSize: 22)
                Text(value.map { NumberFormatting.format($0, options: settings.numberFormat).plainTextLocalized } ?? "—")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(armed ? settings.accent.color.opacity(0.45) : nil).interactive(), in: .rect(cornerRadius: 16))
        .accessibilityLabel("Spremenljivka \(name)")
        // The value as displayed (decimal comma, ·10 exponent), not the machine format.
        .accessibilityValue(value.map { MathAccessibility.number(NumberFormatting.format($0, options: settings.numberFormat)) } ?? "prazna")
        // With STO armed (shown only by the tint) a tap stores the result here.
        .accessibilityHint(armed ? "Shrani rezultat v spremenljivko " + name : "")
    }
}
