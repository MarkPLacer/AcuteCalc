import AcuteCore
import SwiftUI
import UIKit
import UserNotifications

/// The update popup: what is new since the installed version, and one tap to the app that
/// installs it (Feather, SideStore, AltStore or eSign) or to the release on GitHub.
struct UpdateSheet: View {
    let update: AvailableUpdate
    @Environment(UpdateChecker.self) private var updates
    @Environment(AppSettings.self) private var settings
    @Environment(\.openURL) private var openURL
    @State private var managers: [SideloadManager] = []
    @State private var appeared = false
    @State private var showsAllChanges = false
    @State private var copied = false
    /// The manager used last time comes first when several are installed.
    @AppStorage("updates.manager") private var preferredManager = ""

    /// Longer changelogs fold behind "Pokaži vse".
    private static let foldedChanges = 8

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 26) {
                    header
                    whatsNew
                    // Notifications come from the automatic checks, so they are offered only with them.
                    if updates.automaticChecks && !updates.notifications && updates.notificationStatus != .denied {
                        notificationOffer
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .animation(.snappy, value: updates.notifications)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaBar(edge: .bottom) { actions }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { updates.remindLater() }
                        .accessibilityLabel("Zapri (spomni me jutri)")
                }
            }
        }
        .presentationDetents([.fraction(0.8), .large])
        .presentationSizing(.form)
        .presentationDragIndicator(.visible)
        .task {
            // Without an IPA link the managers have nothing to install: GitHub instead.
            let installed = update.latest.downloadURL == nil ? [] : SideloadManager.installed
            managers = installed.filter { $0.rawValue == preferredManager } + installed.filter { $0.rawValue != preferredManager }
            await updates.refreshNotificationStatus()
            appeared = true
        }
        .sensoryFeedback(.impact(weight: .light), trigger: appeared) { _, _ in settings.haptics }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 16) {
            AppIconPreview(choice: currentIcon, cornerRadius: 21)
                .frame(width: 92, height: 92)
                .shadow(color: settings.accent.color.opacity(0.35), radius: 18, y: 8)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, settings.accent.color)
                        .background { Circle().fill(Color(.systemBackground)).padding(1) }
                        .offset(x: 9, y: 9)
                        .symbolEffect(.bounce, value: appeared)
                }
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Nova različica je na voljo")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                versionChange
                if !details.isEmpty {
                    Text(details)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.top, 4)
    }

    private var versionChange: some View {
        HStack(spacing: 8) {
            Text(updates.installed.version)
                .foregroundStyle(.secondary)
            Image(systemName: "arrow.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.tertiary)
            Text(update.latest.version)
                .fontWeight(.semibold)
                .foregroundStyle(settings.accent.color)
        }
        .font(.subheadline.monospacedDigit())
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.fill.tertiary, in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Z različice \(updates.installed.version) na \(update.latest.version)")
    }

    /// "build 42 · 27. oktober 2026 · 24,1 MB"
    private var details: String {
        var parts: [String] = []
        if let build = update.latest.build { parts.append("build \(build)") }
        if let date = update.latest.date { parts.append(date.formatted(date: .long, time: .omitted)) }
        if let size = update.latest.size { parts.append(size.formatted(.byteCount(style: .file))) }
        return parts.joined(separator: " · ")
    }

    private var currentIcon: AppIconPicker.Choice {
        let name = UIApplication.shared.alternateIconName
        return AppIconPicker.choices.first { $0.name == name } ?? AppIconPicker.choices[0]
    }

    // MARK: What's new

    private struct ChangeGroup: Identifiable {
        let version: AppVersionInfo
        let changes: [String]
        var id: String { version.id }
    }

    /// The changes of every newer version, newest first, folded after `foldedChanges` lines.
    private var groups: [ChangeGroup] {
        var remaining = showsAllChanges ? Int.max : Self.foldedChanges
        var groups: [ChangeGroup] = []
        for version in update.versions where remaining > 0 {
            let changes = Array(version.changes.prefix(remaining))
            remaining -= max(changes.count, 1)
            groups.append(ChangeGroup(version: version, changes: changes))
        }
        return groups
    }

    private var changeCount: Int { update.versions.reduce(0) { $0 + $1.changes.count } }

    private var whatsNew: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Kaj je novega")
                .font(.headline)
            VStack(alignment: .leading, spacing: 18) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 9) {
                        if update.versions.count > 1 {
                            HStack(alignment: .firstTextBaseline) {
                                Text(group.version.version)
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                                Spacer()
                                if let date = group.version.date {
                                    Text(date, format: .relative(presentation: .named))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        if group.changes.isEmpty {
                            Text("Manjše izboljšave.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(group.changes.enumerated()), id: \.offset) { _, change in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("•")
                                    .font(.callout.weight(.black))
                                    .foregroundStyle(settings.accent.color)
                                    .accessibilityHidden(true)
                                Text(change)
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                if !showsAllChanges && changeCount > Self.foldedChanges {
                    Button {
                        withAnimation(.snappy) { showsAllChanges = true }
                    } label: {
                        Label("Pokaži vse spremembe (\(changeCount))", systemImage: "chevron.down")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.fill.quinary, in: .rect(cornerRadius: 20, style: .continuous))
        }
    }

    // MARK: Notifications

    /// Asks for notifications where their use is obvious (best practice: in context, not at launch).
    private var notificationOffer: some View {
        HStack(spacing: 14) {
            Image(systemName: "bell.badge.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(settings.accent.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Obvesti me o novih različicah")
                    .font(.subheadline.weight(.semibold))
                Text("iPhone in iPad v ozadju občasno preverita, ali je izšla nova različica.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Vklopi") {
                Task { await updates.enableNotifications() }
            }
            .accessibilityLabel("Vklopi obvestila o novih različicah")
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
        }
        .padding(14)
        .background(.fill.quinary, in: .rect(cornerRadius: 18, style: .continuous))
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 12) {
            GlassEffectContainer(spacing: 10) {
                VStack(spacing: 10) {
                    primaryButton
                    HStack(spacing: 10) {
                        if managers.isEmpty {
                            if let ipa = update.latest.downloadURL {
                                Button { leave(to: ipa) } label: {
                                    Label("Prenesi IPA", systemImage: "arrow.down.doc").frame(maxWidth: .infinity)
                                }
                            }
                        } else {
                            Button { leave(to: UpdateChecker.releaseURL) } label: {
                                Label("GitHub", systemImage: "safari").frame(maxWidth: .infinity)
                            }
                        }
                        moreMenu
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                }
            }
            HStack {
                Button("Kasneje") { updates.remindLater() }
                Spacer()
                Button("Preskoči to različico") { updates.skip(update) }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .buttonStyle(.borderless)
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var primaryButton: some View {
        if let manager = managers.first {
            Button { install(with: manager) } label: {
                Label("Posodobi v \(manager.name)", systemImage: "arrow.down.app.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        } else {
            Button { leave(to: UpdateChecker.releaseURL) } label: {
                Label("Odpri izdajo na GitHubu", systemImage: "safari")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
    }

    private var moreMenu: some View {
        Menu {
            ForEach(managers.dropFirst()) { manager in
                Button("Posodobi v \(manager.name)", systemImage: "arrow.down.app") { install(with: manager) }
            }
            Button(copied ? "Povezava kopirana" : "Kopiraj povezavo vira", systemImage: copied ? "checkmark" : "doc.on.doc") {
                UIPasteboard.general.url = UpdateChecker.sourceURL
                copied = true
            }
            if !managers.isEmpty, let ipa = update.latest.downloadURL {
                Button("Prenesi IPA", systemImage: "arrow.down.doc") { leave(to: ipa) }
            }
        } label: {
            Label("Več", systemImage: "ellipsis")
                .frame(maxWidth: .infinity)
        }
    }

    private func install(with manager: SideloadManager) {
        preferredManager = manager.rawValue
        leave(to: manager.installURL(for: update.latest))
    }

    /// Opens the link; once another app took it, the popup closes for the next hour.
    private func leave(to url: URL?) {
        guard let url else { return }
        openURL(url) { accepted in
            if accepted { updates.didStartUpdate() }
        }
    }
}
