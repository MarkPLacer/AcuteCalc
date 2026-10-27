import AcuteCore
import SwiftUI

// MARK: N-BASE

/// Sharp N-BASE: integer arithmetic and logic in BIN, PEN, OCT, DEC and HEX.
struct NBaseToolView: View {
    @AppStorage("nbaseBase") private var baseRaw = NumberBase.decimal.rawValue
    @AppStorage("nbaseBits") private var bits = 16
    @State private var input = ""
    @Environment(AppSettings.self) private var settings

    private var base: NumberBase { NumberBase(rawValue: baseRaw) ?? .decimal }

    private var result: Result<Int64, MathError>? {
        guard !input.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return Result { () throws(MathError) -> Int64 in try BaseConversion.evaluate(input, base: base, bits: bits) }
    }

    var body: some View {
        VStack(spacing: 10) {
            Picker("Sistem", selection: Binding(get: { baseRaw }, set: { newValue in convertInput(to: newValue) })) {
                ForEach(NumberBase.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            VStack(alignment: .trailing, spacing: 6) {
                Text(input.isEmpty ? "0" : input)
                    .font(.system(size: 30, weight: .light, design: .monospaced))
                    .lineLimit(2)
                    .minimumScaleFactor(0.4)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                switch result {
                case .success(let value)?:
                    resultTable(value)
                case .failure(let error)?:
                    Text(error.errorDescription ?? error.shortDescription).font(.footnote).foregroundStyle(.red)
                case nil:
                    EmptyView()
                }
            }
            .padding()
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
            .padding(.horizontal)

            HStack {
                Text("Velikost besede")
                Picker("Biti", selection: $bits) {
                    ForEach(BaseConversion.wordSizes, id: \.self) { Text("\($0) bitov").tag($0) }
                }
                .pickerStyle(.menu)
            }
            .font(.footnote)

            NBaseKeypad(base: base, input: $input)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
    }

    private func resultTable(_ value: Int64) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            ForEach(NumberBase.allCases) { b in
                GridRow {
                    Text(b.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(b == base ? Color.accentColor : .secondary)
                    Text(BaseConversion.grouped(BaseConversion.format(value, base: b, bits: bits), base: b))
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
        }
    }

    /// Changing the base converts the current value (Sharp behaviour).
    private func convertInput(to newBase: Int) {
        let old = base
        baseRaw = newBase
        guard let b = NumberBase(rawValue: newBase), !input.isEmpty,
              let value = try? BaseConversion.evaluate(input, base: old, bits: bits) else { return }
        input = BaseConversion.format(value, base: b, bits: bits)
    }
}

private struct NBaseKeypad: View {
    let base: NumberBase
    @Binding var input: String
    @Environment(AppSettings.self) private var settings
    @State private var taps = 0

    /// Digit rows with the operator that ends each row.
    private let digitRows: [(digits: [String], operation: String)] = [
        (["D", "E", "F"], "×"), (["A", "B", "C"], "÷"), (["7", "8", "9"], "+"), (["4", "5", "6"], "−"),
    ]

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    key("AND", role: .function); key("OR", role: .function); key("XOR", role: .function); key("XNOR", role: .function)
                }
                GridRow {
                    key("NOT", role: .function); key("NEG", role: .function); key("(", role: .function); key(")", role: .function)
                }
                ForEach(digitRows.indices, id: \.self) { i in
                    GridRow {
                        ForEach(digitRows[i].digits, id: \.self) { d in key(d) }
                        key(digitRows[i].operation, role: .operation)
                    }
                }
                GridRow {
                    key("1"); key("2"); key("3")
                    Button { input = "" } label: { keyLabel("C") }
                        .glassEffect(.regular.tint(Color.white.opacity(0.55)).interactive(), in: .capsule)
                        .foregroundStyle(.black)
                }
                GridRow {
                    key("0")
                        .gridCellColumns(3)
                    Button {
                        if !input.isEmpty { input.removeLast() }
                        while input.last == " " { input.removeLast() }
                    } label: { keyLabel("⌫") }
                        .glassEffect(.regular.tint(Color.white.opacity(0.10)).interactive(), in: .capsule)
                }
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: taps) { _, _ in settings.haptics }
    }

    private enum Role { case digit, function, operation }

    private func key(_ label: String, role: Role = .digit) -> some View {
        let enabled = role != .digit || base.digitCharacters.contains(Character(label))
        return Button {
            taps += 1
            append(label, role: role)
        } label: {
            keyLabel(label)
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .glassEffect(.regular.tint(role == .operation ? settings.accent.color : (role == .function ? Color.white.opacity(0.25) : Color.white.opacity(0.10))).interactive(), in: .capsule)
    }

    private func keyLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: text.count > 2 ? 15 : 22, weight: .medium, design: .rounded))
            .frame(maxWidth: .infinity, minHeight: 40)
            .contentShape(.capsule)
    }

    private func append(_ label: String, role: Role) {
        switch role {
        case .digit:
            input += label
        case .function, .operation:
            let symbol = label == "−" ? "-" : (label == "×" ? "*" : (label == "÷" ? "/" : label))
            input += (label.count > 1 ? " \(symbol) " : symbol)
        }
    }
}

// MARK: DRILL

/// Sharp DRILL: rounds of 10 questions, mental arithmetic or the multiplication table.
struct DrillToolView: View {
    @AppStorage("drillKind") private var kind: DrillKind = .mixed
    @AppStorage("drillLevel") private var levelRaw = DrillLevel.easy.rawValue
    @AppStorage("drillTable") private var table = 0
    @State private var generator = DrillGenerator()
    @State private var question: DrillQuestion?
    @State private var answer = ""
    @State private var correct = 0
    @State private var asked = 0
    @State private var feedback: Bool?
    @State private var started: Date?
    @State private var finishedAt: Date?
    /// Shows the feedback, then moves on to the next question.
    @State private var feedbackTask: Task<Void, Never>?
    @Environment(AppSettings.self) private var settings

    private let roundLength = 10

    var body: some View {
        VStack(spacing: 14) {
            if question == nil {
                setup
            } else {
                quiz
            }
        }
        .padding()
        .animation(.snappy, value: question?.id)
        .sensoryFeedback(trigger: feedback) { _, new in
            guard settings.haptics, let new else { return nil }
            return new ? .success : .error
        }
    }

    private var setup: some View {
        Form {
            Picker("Vrsta", selection: $kind) {
                ForEach(DrillKind.allCases) { Text($0.title).tag($0) }
            }
            if kind == .multiplicationTable {
                Picker("Poštevanka", selection: $table) {
                    Text("Naključno").tag(0)
                    ForEach(1...10, id: \.self) { Text("\($0)").tag($0) }
                }
            } else {
                Picker("Težavnost", selection: $levelRaw) {
                    ForEach(DrillLevel.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
            }
            if let finishedAt, let started, asked > 0 {
                Section("Zadnji krog") {
                    LabeledContent("Pravilno", value: "\(correct) / \(asked)")
                    LabeledContent("Čas", value: Duration.seconds(finishedAt.timeIntervalSince(started)).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated)))
                }
            }
            Button("Začni (\(roundLength) vprašanj)", systemImage: "play.fill") { start() }
                .buttonStyle(.glassProminent)
                .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
    }

    private var quiz: some View {
        VStack(spacing: 16) {
            HStack {
                Text("\(asked + 1) / \(roundLength)")
                Spacer()
                Label("\(correct)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Button("Končaj", systemImage: "xmark") { finish() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
            }
            .font(.headline)
            if let question {
                Text(question.text + " =")
                    .font(.system(size: 52, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(answer.isEmpty ? "?" : answer)
                    .font(.system(size: 44, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(feedback.map { $0 ? Color.green : Color.red } ?? Color.accentColor)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
            DrillKeypad(answer: $answer, acceptsInput: feedback == nil, onSubmit: submit)
        }
    }

    private func start() {
        feedbackTask?.cancel()
        generator = DrillGenerator()
        correct = 0
        asked = 0
        feedback = nil
        started = .now
        finishedAt = nil
        nextQuestion()
    }

    private func nextQuestion() {
        answer = ""
        question = generator.next(kind, level: DrillLevel(rawValue: levelRaw) ?? .easy, table: table == 0 ? nil : table)
    }

    private func submit() {
        // During the feedback the field holds the answer (or the correct one): a second OK must not score it.
        guard feedback == nil, let question, let value = Int(answer) else { return }
        let ok = value == question.answer
        feedback = ok
        if ok { correct += 1 }
        asked += 1
        if !ok { answer = "\(question.answer)" }
        feedbackTask = Task {
            try? await Task.sleep(for: .milliseconds(ok ? 350 : 1100))
            guard !Task.isCancelled else { return }
            feedback = nil
            if asked >= roundLength { finish() } else { nextQuestion() }
        }
    }

    private func finish() {
        feedbackTask?.cancel()
        finishedAt = .now
        question = nil
    }
}

private struct DrillKeypad: View {
    @Binding var answer: String
    /// False while the feedback on an answer is shown.
    var acceptsInput = true
    var onSubmit: () -> Void
    @Environment(AppSettings.self) private var settings

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                ForEach([["7", "8", "9"], ["4", "5", "6"], ["1", "2", "3"]], id: \.self) { row in
                    GridRow {
                        ForEach(row, id: \.self) { d in digit(d) }
                    }
                }
                GridRow {
                    Button { if acceptsInput, !answer.isEmpty { answer.removeLast() } } label: { label("⌫") }
                        .glassEffect(.regular.interactive(), in: .capsule)
                    digit("0")
                    Button(action: onSubmit) { label("OK") }
                        .glassEffect(.regular.tint(settings.accent.color).interactive(), in: .capsule)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxHeight: 320)
    }

    private func digit(_ d: String) -> some View {
        Button { if acceptsInput, answer.count < 7 { answer += d } } label: { label(d) }
            .glassEffect(.regular.tint(Color.white.opacity(0.10)).interactive(), in: .capsule)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 28, weight: .regular, design: .rounded))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.capsule)
    }
}
