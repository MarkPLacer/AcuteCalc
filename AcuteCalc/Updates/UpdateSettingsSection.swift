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
        .task { await updates.refreshNotificationStatus() }
    }

    @ViewBuilder private var status: some View {
        switch updates.status {
        case .checking:
            LabeledContent("Preverjam …") { ProgressView() }
        case .available:
            if let update = updates.update {
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
        case .upToDate:
            Label("Imaš najnovejšo različico", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Label("Preverjanje ni uspelo – si povezan v splet?", systemImage: "wifi.exclamationmark")
                .foregroundStyle(.secondary)
        case .idle:
            EmptyView()
        }
    }

    private var footer: String {
        var text = "Aplikacija prebere le datoteko z različicami v izdaji na GitHubu (isti vir, ki ga berejo AltStore, SideStore, Feather in eSign) in ničesar ne pošilja."
        if updates.automaticChecks && updates.notifications {
            text += " Za obvestila iOS občasno preveri v ozadju, ko se mu zdi primerno (Osveževanje v ozadju)."
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
