import SwiftUI

@main
struct AcuteCalcApp: App {
    @State private var settings = AppSettings()
    @State private var store = AppStore()
    @State private var updates = UpdateChecker()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(store)
                .environment(updates)
        }
        // The iPadOS menu bar: the sections in the View menu and the menu Računalo.
        .commands { AppCommands() }
        // Background App Refresh: looks for a new build and posts a notification (UpdateChecker).
        .backgroundTask(.appRefresh(UpdateChecker.refreshTaskIdentifier)) { [updates] in
            await updates.checkInBackground()
        }
    }
}
