import AcuteCore
import Foundation

/// The apps that install Acute Calc (they sign the unsigned IPA), opened through their URL
/// schemes. The user picks one in the update popup and the app remembers it on this device:
/// since iOS 27 an app is meant to just open a link and handle failure instead of probing
/// installed apps with `canOpenURL`.
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

    /// AltStore Classic also answers to `altstore`, but so does AltStore PAL, which cannot
    /// install an unsigned IPA.
    var scheme: String { self == .altstore ? "altstore-classic" : rawValue }

    /// Opens the manager with this version's IPA, ready to install:
    /// - Feather asks "Download and install?" and adds it to its library (FeatherApp.swift:
    ///   `feather://install/<https URL>`, the URL not encoded);
    /// - SideStore and AltStore download, sign and install it (`install?url=`, URLHandler.swift
    ///   and SceneDelegate.swift);
    /// - eSign is closed source: `install?url=` is what IPA libraries use for it; at worst eSign
    ///   just opens and its source offers the update.
    func installURL(for version: AppVersionInfo) -> URL? {
        guard let ipa = version.downloadURL else { return URL(string: "\(scheme)://") }
        if self == .feather {
            return URL(string: "feather://install/\(ipa.absoluteString)")
        }
        let encoded = ipa.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        return URL(string: "\(scheme)://install?url=\(encoded)")
    }
}
