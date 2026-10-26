import AcuteCore
import Foundation
import UIKit

/// The apps that install Acute Calc (they sign the unsigned IPA), opened through their URL
/// schemes. Only installed ones are offered: `canOpenURL` needs each scheme listed in
/// LSApplicationQueriesSchemes (Config/Info.plist).
enum SideloadManager: String, CaseIterable, Identifiable {
    case feather, sidestore, altstore, esign

    var id: String { rawValue }

    var name: String {
        switch self {
        case .feather: "Feather"
        case .sidestore: "SideStore"
        case .altstore: "AltStore"
        case .esign: "eSign"
        }
    }

    /// Opens the manager with this version's IPA, ready to install.
    func installURL(for version: AppVersionInfo) -> URL? {
        guard let ipa = version.downloadURL else { return URL(string: "\(rawValue)://") }
        switch self {
        case .feather:
            // Feather asks "Download and install?" (FeatherApp.swift: feather://install/<https URL>).
            return URL(string: "feather://install/\(ipa.absoluteString)")
        case .sidestore, .altstore:
            // AltStore and SideStore download, sign and install it (…://install?url=<URL>).
            var components = URLComponents()
            components.scheme = rawValue
            components.host = "install"
            components.queryItems = [URLQueryItem(name: "url", value: ipa.absoluteString)]
            return components.url
        case .esign:
            // eSign has no documented install link: it opens, and its source offers the update.
            return URL(string: "esign://")
        }
    }

    /// The managers on this device, in the order the popup offers them.
    static var installed: [SideloadManager] {
        allCases.filter { manager in
            URL(string: "\(manager.rawValue)://").map { UIApplication.shared.canOpenURL($0) } ?? false
        }
    }
}
