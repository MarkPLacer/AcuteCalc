import AcuteCore
import SwiftUI
import UIKit

/// The Formulas tab: formula sheets for the math and physics matura.
struct FormulasScreen: View {
    @AppStorage("formulaSubject") private var subject: FormulaSubject = .mathematics
    @State private var search = ""

    private var sections: [FormulaSection] {
        let all = FormulaLibrary.sections(subject)
        guard !search.isEmpty else { return all }
        return all.compactMap { section in
            let matches = section.formulas.filter {
                $0.title.localizedCaseInsensitiveContains(search) || section.title.localizedCaseInsensitiveContains(search)
            }
            return matches.isEmpty ? nil : FormulaSection(title: section.title, systemImage: section.systemImage, formulas: matches)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.formulas) { formula in
                            FormulaRow(formula: formula)
                        }
                    } header: {
                        Label(section.title, systemImage: section.systemImage)
                    }
                }
                Section {
                    Text("Dolg pritisk na formulo: kopiraj (tudi kot LaTeX) ali vstavi v računalo.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Formule")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Išči formulo")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Predmet", selection: $subject) {
                        ForEach(FormulaSubject.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
            .sectionMenuToolbar()
            .overlay {
                if sections.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
        }
    }
}

struct FormulaRow: View {
    let formula: Formula
    @Environment(AppSettings.self) private var settings
    @Environment(\.insertIntoCalculator) private var insertIntoCalculator

    var body: some View {
        let row = try? LaTeXConverter.row(fromLaTeX: formula.latex)
        VStack(alignment: .leading, spacing: 6) {
            Text(formula.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let row {
                ViewThatFits(in: .horizontal) {
                    MathText(row: row, fontSize: 22)
                    MathText(row: row, fontSize: 18)
                    MathText(row: row, fontSize: 14)
                    ScrollView(.horizontal, showsIndicators: false) { MathText(row: row, fontSize: 14) }
                }
            } else {
                Text(formula.latex).font(.caption.monospaced())
            }
            if let note = formula.note {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .contextMenu {
            if let row {
                Button("Vstavi v računalo", systemImage: "plus.forwardslash.minus") { insertIntoCalculator(row) }
                Button("Kopiraj", systemImage: "doc.on.doc") { MathClipboard.copy(row, decimalComma: settings.decimalComma) }
            }
            Button("Kopiraj kot LaTeX", systemImage: "chevron.left.forwardslash.chevron.right") {
                UIPasteboard.general.string = formula.latex
            }
        }
    }
}
