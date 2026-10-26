import SwiftUI

@main
struct AcuteCalcApp: App {
    @State private var settings = AppSettings()
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(store)
        }
    }
}
