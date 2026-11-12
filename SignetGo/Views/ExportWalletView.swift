import SwiftUI
import UniformTypeIdentifiers

/// The wallet's octez-client files as a folder, for saving to Files (or anywhere the share
/// destinations reach). octez-client and Signet on the Mac read it as a wallet directory.
struct WalletExport: FileDocument {
    static let readableContentTypes: [UTType] = [.folder]
    let files: [(String, Data)]

    init(files: [(String, Data)]) { self.files = files }
    init(configuration: ReadConfiguration) throws { throw CocoaError(.featureUnsupported) }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(directoryWithFileWrappers: Dictionary(uniqueKeysWithValues: files.map { name, data in
            (name, FileWrapper(regularFileWithContents: data))
        }))
    }

    /// The key files and contract aliases, read as one locked snapshot.
    static func current() throws -> WalletExport {
        WalletExport(files: try TezosClientStore.snapshot(in: TezosClientStore.defaultDirectory, files: TezosClientStore.aliasFiles))
    }

    static var defaultName: String { "Signet wallet \(Date().formatted(.iso8601.year().month().day()))" }
}

/// Explains what is exported, then hands the folder to the system's file exporter.
struct ExportWalletView: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var export: WalletExport?
    @State private var isExporting = false
    @State private var result: String?
    @State private var errorMessage: String?

    private var clearMainnetKeys: Bool {
        model.network.isMainnet && model.wallets.contains { $0.keyKind == .unencrypted && !$0.isSessionOnly }
    }
    private var sessionKeys: Int { model.wallets.filter(\.isSessionOnly).count }

    var body: some View {
        Form {
            Section {
                Text("Saves your accounts as a folder in octez-client's format: the address book, public keys and secret keys. octez-client and Signet on the Mac can use it as a wallet directory, and Import can read a key from it.")
                    .font(.callout)
            }
            Section {
                Label("Encrypted keys stay encrypted with their passwords. Keep the folder somewhere private all the same.", systemImage: "lock")
                if clearMainnetKeys {
                    Label("Some keys are not encrypted. Anyone who gets the folder can spend from them.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                if sessionKeys > 0 {
                    Label("Keys kept only for this session are not included.", systemImage: "clock")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.footnote)
            Section {
                Button("Export wallet…") {
                    do {
                        export = try WalletExport.current()
                        isExporting = true
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            if let result { Section { Text(result).foregroundStyle(.secondary) } }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .navigationTitle("Export wallet")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .fileExporter(isPresented: $isExporting, document: export, contentType: .folder, defaultFilename: WalletExport.defaultName) { outcome in
            switch outcome {
            case .success(let url): result = "Saved to \(url.lastPathComponent)."
            case .failure(let error): errorMessage = error.localizedDescription
            }
            export = nil
        }
    }
}
