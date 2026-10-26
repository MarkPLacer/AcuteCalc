import AcuteCore
import Foundation

/// Scripted input for the simulator smoke test in CI (Debug builds only; a no-op in Release).
///
/// `ACUTE_SMOKE` holds expressions separated by `|`, written with the keypad's keys: `^` power,
/// `/` fraction, `→` leaves the current slot, `;` separates the equations of a system, and
/// `{sin}`, `{ln}`, `{sqrt}`, `{abs}`, `{pi}` stand for those keys. Each expression is typed into
/// the calculator key by key, so live evaluation, the graph preview and its special points run
/// as on a device; then all of them are drawn together in the Graphs tab, and every tool of the
/// Tools tab is opened with its default input. The app prints `SMOKE DONE` and exits, so the
/// runner can tell a crash from success.
enum SmokeTest {
    static func run(calculator: CalculatorModel, store: AppStore, select: (AppTab) -> Void) async {
        #if DEBUG
        guard let script = ProcessInfo.processInfo.environment["ACUTE_SMOKE"], !script.isEmpty else { return }
        installCrashReporter()
        let inputs = script.components(separatedBy: "|")
        try? await Task.sleep(for: .seconds(2))
        for input in inputs {
            log("calculator: \(input)")
            calculator.press(.clear)
            for key in keys(input) {
                calculator.press(key)
                try? await Task.sleep(for: .milliseconds(150))
            }
            try? await Task.sleep(for: .seconds(2))
        }
        select(.graphs)
        try? await Task.sleep(for: .seconds(1))
        for (index, input) in inputs.enumerated() {
            log("graphs: \(input)")
            var editor = MathEditor()
            for key in keys(input) { _ = editor.apply(key) }
            store.graphFunctions.append(GraphFunctionDefinition(row: editor.root, colorIndex: index))
            try? await Task.sleep(for: .seconds(2))
        }
        select(.tools)
        try? await Task.sleep(for: .seconds(1))
        for tool in ToolKind.allCases {
            log("tools: \(tool.rawValue)")
            SmokeHooks.openTool?(tool)
            try? await Task.sleep(for: .seconds(3))
        }
        log("DONE")
        // Let the simulator console pass the last line on before the process ends.
        try? await Task.sleep(for: .seconds(1))
        exit(0)
        #endif
    }

    /// Keypad keys for a script line.
    static func keys(_ text: String) -> [KeypadKey] {
        var keys: [KeypadKey] = []
        var rest = Substring(text)
        while let c = rest.first {
            rest = rest.dropFirst()
            if c == "{", let end = rest.firstIndex(of: "}") {
                let name = String(rest[..<end])
                rest = rest[rest.index(after: end)...]
                switch name {
                case "sqrt": keys.append(.sqrt)
                case "abs": keys.append(.abs)
                case "pi": keys.append(.symbol(.constant(.pi)))
                default: if let f = MathFunction(rawValue: name) { keys.append(.function(f)) }
                }
                continue
            }
            if let d = c.wholeNumberValue {
                keys.append(.digit(d))
                continue
            }
            switch c {
            case "^": keys.append(.power)
            case "/": keys.append(.fraction)
            case "→": keys.append(.right)
            case "(": keys.append(.symbol(.leftParenthesis))
            case ")": keys.append(.symbol(.rightParenthesis))
            case "+": keys.append(.symbol(.plus))
            case "-": keys.append(.symbol(.minus))
            case "*": keys.append(.symbol(.times))
            case "=": keys.append(.symbol(.equals))
            case "<": keys.append(.symbol(.less))
            case ">": keys.append(.symbol(.greater))
            case ";": keys.append(.symbol(.comma))
            case ".": keys.append(.point)
            default: if c.isLetter { keys.append(.symbol(.variable(String(c)))) }
            }
        }
        return keys
    }

    private static func log(_ message: String) {
        FileHandle.standardError.write(Data("SMOKE \(message)\n".utf8))
    }

    #if DEBUG
    /// Prints the crashing thread's stack (the runner keeps no crash reports); an alternate
    /// signal stack lets the main thread report a stack overflow too.
    private static func installCrashReporter() {
        let size = 1 << 17
        var stack = stack_t(ss_sp: UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16), ss_size: size, ss_flags: 0)
        sigaltstack(&stack, nil)
        for signal in [SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGABRT, SIGFPE] {
            var action = sigaction()
            action.__sigaction_u.__sa_handler = smokeCrashHandler
            action.sa_flags = SA_ONSTACK
            action.sa_mask = sigset_t()
            sigaction(signal, &action, nil)
        }
    }
    #endif
}

#if DEBUG
/// Lets the smoke test open a tool in the Tools tab.
enum SmokeHooks {
    static var openTool: ((ToolKind) -> Void)?
}

nonisolated private func smokeCrashHandler(_ signal: Int32) {
    let stack = Thread.callStackSymbols.joined(separator: "\n")
    FileHandle.standardError.write(Data("SMOKE CRASH signal \(signal) on \(Thread.isMainThread ? "main" : "background") thread\n\(stack)\n".utf8))
    _exit(128 + signal)
}
#endif
