import AcuteCore
import CoreText
import SwiftUI

/// Colours used when drawing math boxes.
struct MathPalette {
    var primary: Color
    var secondary: Color
    var accent: Color
    var placeholder: Color
}

/// Draws a laid-out `MathBox` into a SwiftUI graphics context.
enum MathRenderer {
    static func draw(_ box: MathBox, in context: inout GraphicsContext, origin: CGPoint, palette: MathPalette) {
        let environment = context.environment
        let primary = palette.primary.resolve(in: environment).cgColor
        let resolved: [MathInk: CGColor] = [
            .primary: primary,
            .secondary: palette.secondary.resolve(in: environment).cgColor,
            .accent: palette.accent.resolve(in: environment).cgColor,
            .placeholder: palette.placeholder.resolve(in: environment).cgColor,
        ]
        context.withCGContext { cg in
            cg.translateBy(x: origin.x, y: origin.y)
            for item in box.items {
                switch item {
                case .text(let line, let o, let ink):
                    cg.saveGState()
                    cg.setFillColor(resolved[ink] ?? primary)
                    cg.translateBy(x: o.x, y: o.y)
                    cg.scaleBy(x: 1, y: -1)
                    cg.textPosition = .zero
                    CTLineDraw(line, cg)
                    cg.restoreGState()
                case .fill(let path, let ink):
                    cg.setFillColor(resolved[ink] ?? primary)
                    cg.addPath(path)
                    cg.fillPath()
                case .stroke(let path, let width, let ink):
                    cg.setStrokeColor(resolved[ink] ?? primary)
                    cg.setLineWidth(width)
                    cg.setLineCap(.round)
                    cg.setLineJoin(.round)
                    cg.addPath(path)
                    cg.strokePath()
                case .placeholder(let rect):
                    let path = CGPath(roundedRect: rect, cornerWidth: rect.width * 0.18, cornerHeight: rect.width * 0.18, transform: nil)
                    cg.setFillColor(resolved[.placeholder]!.copy(alpha: 0.18) ?? resolved[.placeholder]!)
                    cg.addPath(path)
                    cg.fillPath()
                    cg.setStrokeColor(resolved[.placeholder]!)
                    cg.setLineWidth(1.2)
                    cg.setLineDash(phase: 0, lengths: [3, 2.5])
                    cg.addPath(path)
                    cg.strokePath()
                    cg.setLineDash(phase: 0, lengths: [])
                }
            }
        }
    }
}


/// Static, read-only math (results, history, formulas).
struct MathText: View {
    let row: MathRow
    var fontSize: CGFloat = 20
    var color: Color = .primary
    /// Draws empty slots as boxes (key labels for templates such as □/□).
    var showsPlaceholders = false
    @Environment(AppSettings.self) private var settings

    init(row: MathRow, fontSize: CGFloat = 20, color: Color = .primary, showsPlaceholders: Bool = false) {
        self.row = row
        self.fontSize = fontSize
        self.color = color
        self.showsPlaceholders = showsPlaceholders
    }

    init(expr: Expr, fontSize: CGFloat = 20, color: Color = .primary) {
        self.row = MathRowConverter.row(for: expr)
        self.fontSize = fontSize
        self.color = color
    }

    var body: some View {
        let style = MathStyle(fontSize: fontSize, multiplication: settings.multiplication.symbol,
                              decimalSeparator: settings.decimalSeparator, slovenianNames: settings.notation == .slovenian,
                              showPlaceholders: showsPlaceholders, imaginaryUnit: settings.imaginaryUnit)
        let box = MathLayoutEngine(style: style).layout(row)
        Canvas { context, _ in
            var ctx = context
            MathRenderer.draw(box, in: &ctx, origin: CGPoint(x: 0, y: box.ascent), palette: MathPalette(primary: color, secondary: color.opacity(0.6), accent: .accentColor, placeholder: .secondary))
        }
        .frame(width: max(1, ceil(box.width)), height: max(1, ceil(box.height)))
        .accessibilityElement()
        .accessibilityLabel(MathRowConverter.plainText(row))
    }
}

/// The structured expression editor: blinking animated caret, tap to place, long-press and
/// drag to select, an edit bar for the selection, and a drag handle that resizes matrices.
struct MathEditorView: View {
    @Binding var editor: MathEditor
    var fontSize: CGFloat = 36
    var alignment: Alignment = .trailing
    var isActive = true
    @Environment(AppSettings.self) private var settings
    @State private var caretVisible = true
    @State private var dragAnchor: MathCursor?
    @State private var resizeStart: GridSize?
    @State private var sizeEditorGrid: GridSize?

    private struct GridSize: Equatable, Identifiable {
        var rows: Int
        var columns: Int
        var id: String { "\(rows)x\(columns)" }
    }

    var body: some View {
        let style = MathStyle(fontSize: fontSize, multiplication: settings.multiplication.symbol,
                              decimalSeparator: settings.decimalSeparator, slovenianNames: settings.notation == .slovenian,
                              showPlaceholders: true, imaginaryUnit: settings.imaginaryUnit)
        let box = MathLayoutEngine(style: style).layout(editor.root)
        let caret = box.caret(for: editor.cursor)
        let width = max(ceil(box.width) + 6, fontSize * 0.4)
        let height = max(ceil(box.height), fontSize * 1.1)
        let origin = CGPoint(x: 3, y: max(box.ascent, fontSize * 0.85))
        let grid = isActive ? activeGrid(in: box) : nil
        let isPiecewiseGrid: Bool = {
            guard let grid, case .piecewise? = node(at: grid) else { return false }
            return true
        }()

        VStack(alignment: alignment == .trailing ? .trailing : .leading, spacing: 4) {
            if isActive, editor.selection != nil {
                MathEditBar(editor: $editor)
                    .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        if let highlight = selectionRect(in: box) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.accentColor.opacity(0.28))
                                .frame(width: highlight.width, height: highlight.height)
                                .offset(x: origin.x + highlight.minX, y: origin.y + highlight.minY)
                                .allowsHitTesting(false)
                        }
                        Canvas { context, _ in
                            var ctx = context
                            MathRenderer.draw(box, in: &ctx, origin: origin, palette: MathPalette(primary: .primary, secondary: .secondary, accent: .accentColor, placeholder: .accentColor))
                        }
                        .frame(width: width, height: height + fontSize * 0.2)
                        .contentShape(Rectangle())
                        .onTapGesture(coordinateSpace: .local) { location in
                            let point = CGPoint(x: location.x - origin.x, y: location.y - origin.y)
                            if let slot = box.caretSlot(near: point) {
                                editor.setCursor(path: slot.path, index: slot.index)
                            }
                        }
                        .gesture(selectionGesture(box: box, origin: origin))
                        if isActive, editor.selection == nil, let caret {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.accentColor)
                                .frame(width: max(2, fontSize * 0.055), height: max(8, caret.bottom - caret.top))
                                .offset(x: origin.x + caret.x - 1, y: origin.y + caret.top)
                                .opacity(caretVisible ? 1 : 0.15)
                                .animation(.snappy(duration: 0.14), value: caret.x)
                                .animation(.snappy(duration: 0.14), value: caret.top)
                                .id("caret")
                                .allowsHitTesting(false)
                        }
                        if let grid {
                            gridHandle(grid, origin: origin)
                        }
                    }
                    .coordinateSpace(.named("mathEditor"))
                    .frame(minWidth: 0, alignment: .leading)
                }
                .defaultScrollAnchor(alignment == .trailing ? .trailing : .leading)
                .onChange(of: editor) { _, _ in
                    caretVisible = true
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("caret", anchor: .center) }
                }
            }
            .frame(height: height + fontSize * 0.2)
        }
        .animation(.snappy(duration: 0.2), value: editor.selection != nil)
        .task(id: isActive) {
            guard isActive else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(530))
                withAnimation(.easeInOut(duration: 0.18)) { caretVisible.toggle() }
            }
        }
        .popover(item: $sizeEditorGrid) { size in
            GridSizePopover(rows: size.rows, columns: size.columns, fixedColumns: isPiecewiseGrid) { rows, columns in
                if let grid { editor.resizeGrid(at: grid.path, index: grid.index, rows: rows, columns: columns) }
            }
            .presentationCompactAdaptation(.popover)
        }
        .accessibilityElement()
        .accessibilityLabel(editor.plainText.isEmpty ? "Prazen izraz" : editor.plainText)
        .accessibilityHint("Dolg pritisk in vlečenje izbereta del izraza.")
    }

    // MARK: Selection

    private func selectionGesture(box: MathBox, origin: CGPoint) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                func cursor(at location: CGPoint) -> MathCursor? {
                    box.caretSlot(near: CGPoint(x: location.x - origin.x, y: location.y - origin.y))
                        .map { MathCursor(path: $0.path, index: $0.index) }
                }
                if dragAnchor == nil { dragAnchor = cursor(at: drag.startLocation) }
                guard let anchor = dragAnchor, let current = cursor(at: drag.location) else { return }
                if anchor == current {
                    // A press without movement selects the node under the finger.
                    editor.select(path: anchor.path, range: max(0, anchor.index - 1)..<anchor.index)
                } else {
                    editor.select(from: anchor, to: current)
                }
            }
            .onEnded { _ in dragAnchor = nil }
    }

    private func selectionRect(in box: MathBox) -> CGRect? {
        guard let selection = editor.selection else { return nil }
        let slots = box.carets.filter {
            $0.path == selection.path && $0.index >= selection.range.lowerBound && $0.index <= selection.range.upperBound
        }
        guard let start = slots.first(where: { $0.index == selection.range.lowerBound }),
              let end = slots.first(where: { $0.index == selection.range.upperBound }) else { return nil }
        let top = slots.map(\.top).min() ?? start.top
        let bottom = slots.map(\.bottom).max() ?? start.bottom
        return CGRect(x: start.x - 1, y: top - 2, width: max(4, end.x - start.x + 2), height: bottom - top + 4)
    }

    // MARK: Matrix resizing

    /// The innermost grid containing the caret (or just left of it).
    private func activeGrid(in box: MathBox) -> MathGridFrame? {
        let cursor = editor.cursor
        let containing = box.grids.filter { g in
            let prefix = g.path + [MathCursor.Step(node: g.index, slot: 0)]
            if cursor.path.count >= prefix.count, Array(cursor.path.prefix(g.path.count)) == g.path,
               cursor.path[g.path.count].node == g.index { return true }
            return cursor.path == g.path && cursor.index == g.index + 1 && prefix.count > 0
        }
        return containing.max { $0.path.count < $1.path.count }
    }

    private func node(at grid: MathGridFrame) -> MathNode? {
        guard let row = editor.subrow(at: grid.path), grid.index < row.nodes.count else { return nil }
        return row.nodes[grid.index]
    }

    private func gridHandle(_ grid: MathGridFrame, origin: CGPoint) -> some View {
        Text("\(grid.rows)×\(grid.columns)")
            .font(.system(size: max(11, fontSize * 0.32), weight: .semibold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.accentColor, in: .capsule)
            .fixedSize()
            .offset(x: origin.x + grid.rect.maxX - 6, y: origin.y + grid.rect.maxY - 10)
            // High priority so dragging the badge resizes instead of scrolling the editor.
            .highPriorityGesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named("mathEditor"))
                    .onChanged { value in
                        let start = resizeStart ?? GridSize(rows: grid.rows, columns: grid.columns)
                        if resizeStart == nil { resizeStart = start }
                        let columns = start.columns + Int((value.translation.width / max(8, grid.cellSize.width)).rounded())
                        let rows = start.rows + Int((value.translation.height / max(8, grid.cellSize.height)).rounded())
                        editor.resizeGrid(at: grid.path, index: grid.index, rows: rows, columns: columns)
                    }
                    .onEnded { _ in resizeStart = nil }
            )
            .onTapGesture { sizeEditorGrid = GridSize(rows: grid.rows, columns: grid.columns) }
            .sensoryFeedback(.selection, trigger: grid.rows * 100 + grid.columns)
            .accessibilityLabel("Velikost \(grid.rows) krat \(grid.columns)")
            .accessibilityHint("Povleci za spremembo velikosti ali se dotakni za vnos")
    }
}

/// Glass bar shown above a selection: copy, cut, copy as LaTeX, paste, select all, delete.
struct MathEditBar: View {
    @Binding var editor: MathEditor
    @Environment(AppSettings.self) private var settings

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                Button("Kopiraj", systemImage: "doc.on.doc") {
                    if let row = editor.selectedRow { MathClipboard.copy(row, decimalComma: settings.decimalComma) }
                }
                Button("Izreži", systemImage: "scissors") {
                    if let row = editor.takeSelection() { MathClipboard.copy(row, decimalComma: settings.decimalComma) }
                }
                Button("LaTeX", systemImage: "chevron.left.forwardslash.chevron.right") {
                    if let row = editor.selectedRow { MathClipboard.copyLaTeX(row, decimalComma: settings.decimalComma) }
                }
                PasteButton(payloadType: MathClipboardItem.self) { items in
                    if let item = items.first { editor.paste(item.row) }
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.capsule)
                Button("Izberi vse", systemImage: "selection.pin.in.out") { editor.selectAll() }
                Button("Izbriši", systemImage: "delete.left", role: .destructive) { _ = editor.takeSelection() }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .font(.system(size: 15, weight: .medium))
        }
    }
}

/// Rows × columns typed directly ("you can also type the size").
struct GridSizePopover: View {
    @State var rows: Int
    @State var columns: Int
    var fixedColumns = false
    var onChange: (Int, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(fixedColumns ? "Število vrstic" : "Velikost matrike").font(.headline)
            Stepper("Vrstice: \(rows)", value: $rows, in: 1...MathEditor.maximumMatrixSize)
            if !fixedColumns {
                Stepper("Stolpci: \(columns)", value: $columns, in: 1...MathEditor.maximumMatrixSize)
            }
        }
        .padding()
        .frame(minWidth: 240)
        .onChange(of: rows) { _, r in onChange(r, columns) }
        .onChange(of: columns) { _, c in onChange(rows, c) }
    }
}
