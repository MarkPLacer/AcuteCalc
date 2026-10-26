import AcuteCore
import CoreTransferable
import SwiftUI
import UIKit
import UniformTypeIdentifiers

extension UTType {
    /// Structured math copied inside Acute Calc (declared in Info.plist).
    nonisolated static let acuteCalcMath = UTType(exportedAs: "com.markplacer.acutecalc.math", conformingTo: .json)
}

/// What is copied and pasted: the structured row, with plain text for other apps.
nonisolated struct MathClipboardItem: Codable, Transferable {
    var row: MathRow

    init(row: MathRow) {
        self.row = row
    }

    /// Text from other apps: LaTeX (contains a backslash or the decimal comma `{,}`) or plain math such as `sin(x)/x`.
    init(text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("\\") || trimmed.contains("{,}") {
            row = try LaTeXConverter.row(fromLaTeX: trimmed)
            return
        }
        // A number copied from the app's own results (12 345, 1,5×10^-8, 2,5·10⁻³) pastes as that number.
        if let number = DisplayedNumber.machineText(trimmed) {
            row = MathRowConverter.rowPreservingStructure(for: try Parser.parse(number))
            return
        }
        // A lone decimal number with a comma (2,5) uses the Slovenian decimal comma.
        var normalized = trimmed
        if trimmed.allSatisfy({ $0.isNumber || $0 == "," || $0 == "-" || $0 == "−" || $0 == " " }), trimmed.contains(",") {
            normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        }
        row = MathRowConverter.rowPreservingStructure(for: try Parser.parse(normalized))
    }

    var plainText: String { MathRowConverter.plainText(row) }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(for: MathClipboardItem.self, contentType: .acuteCalcMath)
        ProxyRepresentation(exporting: { (item: MathClipboardItem) in item.plainText },
                            importing: { (text: String) in try MathClipboardItem(text: text) })
    }
}

enum MathClipboard {
    /// Copies structured math plus plain text (both readable by other apps).
    static func copy(_ row: MathRow, decimalComma: Bool) {
        var item: [String: Any] = [UTType.utf8PlainText.identifier: MathRowConverter.plainText(row)]
        if let data = try? JSONEncoder().encode(MathClipboardItem(row: row)) {
            item[UTType.acuteCalcMath.identifier] = data
        }
        UIPasteboard.general.setItems([item])
    }

    static func copyLaTeX(_ row: MathRow, decimalComma: Bool) {
        UIPasteboard.general.string = LaTeXConverter.latex(row, decimalComma: decimalComma)
    }
}

/// System Copy / Cut / Paste (⌘C, ⌘X, ⌘V and the edit menu) for a structured editor.
struct MathClipboardSupport: ViewModifier {
    @Binding var editor: MathEditor

    func body(content: Content) -> some View {
        content
            .copyable(copiedItems())
            .cuttable(for: MathClipboardItem.self) {
                guard let row = editor.takeSelection() else { return [] }
                return [MathClipboardItem(row: row)]
            }
            .pasteDestination(for: MathClipboardItem.self) { items in
                if let item = items.first { editor.paste(item.row) }
            }
    }

    private func copiedItems() -> [MathClipboardItem] {
        let row = editor.selectedRow ?? editor.root
        return row.isEmpty ? [] : [MathClipboardItem(row: row)]
    }
}

extension View {
    func mathClipboard(_ editor: Binding<MathEditor>) -> some View {
        modifier(MathClipboardSupport(editor: editor))
    }
}
