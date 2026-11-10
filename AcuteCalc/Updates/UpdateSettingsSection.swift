import AcuteCore
import SwiftUI
import UIKit
import UserNotifications

/// Settings › Posodobitve: the installed version, a manual check, automatic checks, notifications,
/// the app that installs updates and the source to add to AltStore, SideStore, Feather or eSign.
struct UpdateSettingsSection: View {
    @Environment(UpdateChecker.self) private var updates
    @Environment(\.openURL) private var openURL
    @State private var copied = false

    var body: some View {
        @Bindable var updates = updates
        Section {
            LabeledContent("Nameščena različica", value: versionText(updates.installed))
            status
            Button {
                Task { await updates.checkNow() }
            } label: {
                Label("Preveri zdaj", systemImage: "arrow.clockwise")
            }
            .disabled(updates.status == .checking)
            Toggle("Samodejno preverjaj", isOn: $updates.automaticChecks)
            Toggle(isOn: Binding(get: { updates.notifications }, set: { on in
                if on { Task { await updates.enableNotifications() } } else { updates.notifications = false }
            })) {
                Text("Obvestila o novih različicah")
            }
            .disabled(!updates.automaticChecks)
            if updates.notificationStatus == .denied {
                Button("Dovoli obvestila v Nastavitvah", systemImage: "bell.slash") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
            }
            // Notifications come from the checks in the background, which Background App Refresh runs.
            if updates.automaticChecks && updates.notifications, let note = updates.backgroundRefreshNote {
                switch note {
                case .turnedOff:
                    Button("Vklopi osveževanje v ozadju v Nastavitvah", systemImage: "arrow.clockwise.circle") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                case .lowPowerMode:
                    Label("Način nizke porabe energije začasno ustavi preverjanje v ozadju", systemImage: "battery.25percent")
                        .foregroundStyle(.secondary)
                }
            }
            // Per device: Feather on the iPad, eSign on the iPhone …
            Picker("Namesti z", selection: $updates.manager) {
                Text("Vprašaj ob posodobitvi").tag(SideloadManager?.none)
                ForEach(SideloadManager.allCases) { manager in
                    Text(manager.name).tag(Optional(manager))
                }
            }
            Button {
                UIPasteboard.general.url = UpdateChecker.sourceURL
                withAnimation(.snappy) { copied = true }
            } label: {
                LabeledContent {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                } label: {
                    Text("Kopiraj povezavo vira")
                    Text("AltStore, SideStore, Feather, eSign")
                }
            }
            .task(id: copied) {
                guard copied else { return }
                try? await Task.sleep(for: .seconds(2))
                withAnimation(.snappy) { copied = false }
            }
            Link(destination: UpdateChecker.releaseURL) {
                Label("Izdaja na GitHubu", systemImage: "safari")
            }
        } header: {
            Text("Posodobitve")
        } footer: {
            Text(footer)
        }
        .task {
            updates.refreshBackgroundRefreshStatus()
            await updates.refreshNotificationStatus()
        }
    }

    @ViewBuilder private var status: some View {
        switch updates.status {
        case .checking:
            LabeledContent("Preverjam …") { ProgressView() }
        case .available:
            if let update = updates.update { availableRow(update) }
        case .upToDate:
            Label("Imaš najnovejšo različico", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Label("Preverjanje ni uspelo – si povezan v splet?", systemImage: "wifi.exclamationmark")
                .foregroundStyle(.secondary)
            // The red dot still announces what the last good check found: it opens offline too.
            if let update = updates.update { availableRow(update) }
        case .idle:
            EmptyView()
        }
    }

    /// "Na voljo je 2.0.42 · Prikaži": opens the popup.
    private func availableRow(_ update: AvailableUpdate) -> some View {
        Button {
            updates.presented = update
        } label: {
            LabeledContent {
                Text("Prikaži")
            } label: {
                Label("Na voljo je \(update.latest.version)", systemImage: "arrow.down.circle.fill")
                    .symbolRenderingMode(.hierarchical)
            }
        }
    }

    private var footer: String {
        var text = "Aplikacija prebere le datoteko z različicami v izdaji na GitHubu (isti vir, ki ga berejo AltStore, SideStore, Feather in eSign) in ničesar ne pošilja."
        // Nothing is promised while Background App Refresh is off, or while Low Power Mode pauses it (the row above
        // says so, and iOS may then report it as denied); restricted (parental controls) gets no warning.
        if updates.automaticChecks && updates.notifications {
            if updates.backgroundRefreshStatus == .available && !updates.lowPowerMode {
                text += " Za obvestila iOS občasno preveri v ozadju, ko se mu zdi primerno (Osveževanje v ozadju)."
            } else if updates.backgroundRefreshNote == .turnedOff {
                text += " Osveževanje v ozadju je izklopljeno, zato iOS v ozadju ne preverja novih različic in obvestil ne bo."
            }
        }
        if let lastChecked = updates.lastChecked {
            text += " Zadnje preverjanje: \(lastChecked.formatted(.relative(presentation: .named)))."
        }
        return text
    }

    private func versionText(_ installed: BundleVersion) -> String {
        installed.build.map { "\(installed.version) (\($0))" } ?? installed.version
    }
}
