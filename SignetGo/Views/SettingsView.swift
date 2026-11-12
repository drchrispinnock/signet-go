import SwiftUI

/// Preferences kept in UserDefaults (never secrets).
enum AppSettings {
    static let showsTestNetworksKey = "showsTestNetworks"
}

/// Light, dark, or follow the system (upstream's `Appearance`, applied with
/// `preferredColorScheme` instead of `NSApp.appearance`).
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    static let key = "appearance"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// The launch warning, shown once per launch until turned off in Settings. iOS apps do not
/// quit themselves, so there is only OK.
enum Disclaimer {
    static let key = "showsDisclaimer"
    static let title = "⚠️ Signet Go - Warning"
    static let message = "Signet Go is very new software and should be used with care. Protect your keys with a password, and export your wallet.\n\nYou can turn off this warning in Settings."
}

struct SettingsView: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Appearance.key) private var appearance: Appearance = .system
    @AppStorage(Disclaimer.key) private var showsDisclaimer = true
    @AppStorage(AppSettings.showsTestNetworksKey) private var showsTestNetworks = true
    @State private var verboseDAppLog = DeveloperSettings.dappDiagnosticsArmed

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Warning at launch", isOn: $showsDisclaimer)
            }
            Section {
                Toggle("Show test networks", isOn: $showsTestNetworks)
            } footer: {
                Text("Shadownet, Bakingnet and the other test networks hold test tez only.")
            }
            Section {
                Toggle("Verbose dApp log on the next launch", isOn: $verboseDAppLog)
                    .onChange(of: verboseDAppLog) { _, on in DeveloperSettings.dappDiagnosticsArmed = on }
            } header: {
                Text("Developer")
            } footer: {
                Text("Records the dApp connection's diagnostics in the bridge log for one launch. The log never holds keys or message bodies.")
            }
            Section("About") {
                LabeledContent("Version", value: version)
                LabeledContent("Wallet", value: "\(model.wallets.filter { !$0.isSessionOnly }.count) accounts")
                Link("Signet on GitHub", destination: URL(string: "https://github.com/drchrispinnock/signet")!)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}
