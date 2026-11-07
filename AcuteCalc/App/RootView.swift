import AcuteCore
import SwiftUI
import UIKit

enum AppTab: String, Hashable, CaseIterable, Identifiable {
    case calculator, graphs, tools, formulas

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calculator: "Računalo"
        case .graphs: "Grafi"
        case .tools: "Orodja"
        case .formulas: "Formule"
        }
    }

    var systemImage: String {
        switch self {
        case .calculator: "plus.forwardslash.minus"
        case .graphs: "chart.xyaxis.line"
        case .tools: "wrench.and.screwdriver"
        case .formulas: "book.closed"
        }
    }
}

/// Switches to the Graphs tab (2D): `openInGraphs()`. An action value like SwiftUI's
/// `OpenURLAction`, so the environment entry is comparable (a stored closure is not).
nonisolated struct OpenInGraphsAction: Equatable {
    private let handler: @MainActor () -> Void

    init(_ handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    @MainActor func callAsFunction() { handler() }

    /// The handler only reaches stable storage (@SceneStorage tab, UserDefaults.standard), so every
    /// instance behaves the same and readers need not be updated when RootView builds a new one.
    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

/// Inserts math into the calculator and switches to it: `insertIntoCalculator(row)`.
nonisolated struct InsertIntoCalculatorAction: Equatable {
    private let handler: @MainActor (MathRow) -> Void

    init(_ handler: @escaping @MainActor (MathRow) -> Void) {
        self.handler = handler
    }

    @MainActor func callAsFunction(_ row: MathRow) { handler(row) }

    /// The handler only reaches stable storage (@State calculator, @SceneStorage tab), so every
    /// instance behaves the same.
    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

extension EnvironmentValues {
    /// Switches to the Graphs tab (2D) — e.g. after a tool added a function there.
    @Entry var openInGraphs: OpenInGraphsAction = OpenInGraphsAction {}
    /// Inserts math into the calculator and switches to it (formulas, constants, tools).
    @Entry var insertIntoCalculator: InsertIntoCalculatorAction = InsertIntoCalculatorAction { _ in }
    /// The selected section; the section menu changes it where the tab bar is hidden (iPhone).
    @Entry var appSection: Binding<AppTab> = .constant(.calculator)
}

/// Top-level sections: a sidebar on iPad; on iPhone the tab bar is hidden for a cleaner
/// calculator and the sections switch from a menu at the top instead.
struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppStore.self) private var store
    @Environment(UpdateChecker.self) private var updates
    @Environment(\.scenePhase) private var scenePhase
    @SceneStorage("selectedTab") private var tab: AppTab = .calculator
    @State private var calculator = CalculatorModel()

    var body: some View {
        @Bindable var updates = updates
        TabView(selection: $tab) {
            Tab(AppTab.calculator.title, systemImage: AppTab.calculator.systemImage, value: AppTab.calculator) {
                CalculatorScreen(model: calculator)
                    .hidesTabBarWhenCompact()
            }
            Tab(AppTab.graphs.title, systemImage: AppTab.graphs.systemImage, value: AppTab.graphs) {
                GraphsScreen()
                    .hidesTabBarWhenCompact()
            }
            Tab(AppTab.tools.title, systemImage: AppTab.tools.systemImage, value: AppTab.tools) {
                ToolsScreen()
                    .hidesTabBarWhenCompact()
            }
            Tab(AppTab.formulas.title, systemImage: AppTab.formulas.systemImage, value: AppTab.formulas) {
                FormulasScreen()
                    .hidesTabBarWhenCompact()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .environment(\.appSection, $tab)
        // The iPadOS menu bar (AppCommands): the sections in the View menu, the calculator's commands.
        .focusedSceneValue(\.appSection, $tab)
        .focusedSceneValue(\.calculator, calculator)
        .environment(\.openInGraphs, OpenInGraphsAction {
            UserDefaults.standard.set(GraphSpace.plane.rawValue, forKey: "graphSpace")
            tab = .graphs
        })
        .environment(\.insertIntoCalculator, InsertIntoCalculatorAction { row in
            calculator.insert(row: row)
            tab = .calculator
        })
        .tint(settings.accent.color)
        .preferredColorScheme(settings.appearance.colorScheme)
        // A newer build: the update popup (see UpdateChecker for when it appears).
        .sheet(item: $updates.presented, onDismiss: { updates.popupClosed() }) { update in
            UpdateSheet(update: update)
        }
        // Data that another build could not read and kept aside (AppStore); this build can, so it is offered
        // once, with the day it was kept aside, so that old data is not restored by mistake. Only the buttons
        // answer it: each one clears restorableFile.
        .alert("Obnovim prejšnje podatke?", isPresented: Binding(get: { store.restorableFile != nil }, set: { _ in }),
               presenting: store.restorableFile) { _ in
            Button("Obnovi") { store.restoreFile() }
            Button("Obdrži trenutne", role: .cancel) { store.keepCurrentData() }
        } message: { _ in
            Text("Druga različica aplikacije teh podatkov ni mogla prebrati in jih je shranila posebej\(keptAsideDate). Obnova zamenja trenutno zgodovino, spremenljivke, grafe in podatke statistike.")
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                reloadStoreIfNeeded()
                Task { await updates.becameActive() }
            case .background: updates.scheduleBackgroundCheck()
            default: break
            }
        }
        // The device was unlocked after the app became active (a launch can run before the unlock completes).
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
            reloadStoreIfNeeded()
        }
        // Background App Refresh changed while the app runs: Posodobitve and the popup's offer follow it. UIKit posts
        // this on the main actor (its message type, BackgroundRefreshStatusDidChangeMessage, is a MainActorMessage).
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.backgroundRefreshStatusDidChangeNotification)) { _ in
            updates.refreshBackgroundRefreshStatus()
        }
        // acutecalc://graphs, acutecalc://tools … opens a tab; acutecalc://update checks for updates.
        .onOpenURL { url in
            if url.host() == "update" {
                Task { await updates.checkNow() }
            } else if let host = url.host(), let target = AppTab(rawValue: host) {
                tab = target
            }
        }
        // CI smoke test and README screenshots on the simulator (Debug builds only).
        .task {
            await SmokeTest.run(calculator: calculator, store: store, settings: settings, updates: updates) { tab = $0 }
            await Showcase.run(calculator: calculator, store: store, settings: settings) { tab = $0 }
        }
    }

    /// The data file is protected until the device is unlocked. A launch for Background App Refresh on a
    /// locked device could not read it (AppStore), so it is read again as soon as it can be.
    private func reloadStoreIfNeeded() {
        guard UIApplication.shared.isProtectedDataAvailable else { return }
        store.reloadIfReadFailed()
    }

    /// " (27. oktober 2026)": the day the offered data was kept aside, written as the update popup writes dates.
    private var keptAsideDate: String {
        store.restorableDate.map { " (\($0.formatted(date: .long, time: .omitted)))" } ?? ""
    }
}

/// Menu that switches between the sections (Računalo, Grafi, Orodja, Formule), plus extra items.
struct SectionMenu<Extra: View, MenuLabel: View>: View {
    @ViewBuilder var extra: Extra
    @ViewBuilder var label: MenuLabel
    @Environment(\.appSection) private var section

    var body: some View {
        Menu {
            Picker("Razdelek", selection: section) {
                ForEach(AppTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.systemImage).tag(tab)
                }
            }
            extra
        } label: {
            label
        }
        .accessibilityLabel("Razdelki")
    }
}

private struct CompactTabBarHidden: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        content.toolbarVisibility(horizontalSizeClass == .compact ? .hidden : .automatic, for: .tabBar)
    }
}

private struct SectionMenuToolbar: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        content.toolbar {
            if horizontalSizeClass == .compact {
                ToolbarItem(placement: .topBarLeading) {
                    SectionMenu {
                        EmptyView()
                    } label: {
                        Label("Razdelki", systemImage: "square.grid.2x2")
                    }
                }
            }
        }
    }
}

extension View {
    /// iPhone: no tab bar — the preference flows up to the enclosing `TabView`.
    func hidesTabBarWhenCompact() -> some View { modifier(CompactTabBarHidden()) }

    /// iPhone: the section menu at the leading edge of the navigation bar.
    func sectionMenuToolbar() -> some View { modifier(SectionMenuToolbar()) }
}
