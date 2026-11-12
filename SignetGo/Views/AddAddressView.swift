import SwiftUI

/// Adds an address book entry, after upstream's `AddAddressSheet`: a named address Signet holds
/// no key for, with its TzProfiles name offered as the alias.
struct AddAddressView: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var alias = ""
    @State private var address = ""
    @State private var previewDomains: [String] = []
    @State private var suggestedName: String?
    @State private var errorMessage: String?
    @State private var isAdding = false
    @State private var scanning = false

    private var trimmedAddress: Address { Address(address.trimmingCharacters(in: .whitespacesAndNewlines)) }
    private var addressLooksValid: Bool { trimmedAddress.isValidAccount }
    private var canAdd: Bool { !alias.trimmingCharacters(in: .whitespaces).isEmpty && addressLooksValid && !isAdding }

    var body: some View {
        Form {
            Section {
                TextField("Address", text: $address, prompt: Text("tz1… or KT1…"))
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button { scanning = true } label: { Label("Scan a QR code", systemImage: "qrcode.viewfinder") }
                TextField("Name", text: $alias, prompt: Text("e.g. Alice"))
                if let suggestedName, suggestedName != alias.trimmingCharacters(in: .whitespaces) {
                    Button("Use “\(suggestedName)” from TzProfiles") { alias = suggestedName }
                }
            } footer: {
                Text("This only records the address. You can watch its balance and send to it, but not spend from it.")
            }
            Section("Preview") {
                if addressLooksValid {
                    HStack(spacing: 10) {
                        AccountAvatarView(address: trimmedAddress, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(trimmedAddress.shortened()).font(.callout.monospaced())
                            ForEach(previewDomains, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                            if let scheme = trimmedAddress.scheme {
                                Text(scheme.displayName).font(.caption).foregroundStyle(.tertiary)
                            } else if trimmedAddress.isContract {
                                Text("Smart contract").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                } else if address.isEmpty {
                    Text("Paste or type an address").foregroundStyle(.tertiary)
                } else {
                    Label("Not a valid Tezos address", systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                }
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Watch an address")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Add", action: add).disabled(!canAdd) }
        }
        .sheet(isPresented: $scanning) {
            NavigationStack { QRScannerView(title: "Scan address") { address = ScannedRecipient.text(from: $0) } }
        }
        .task(id: address) {
            previewDomains = []
            suggestedName = nil
            guard addressLooksValid else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            async let domains = model.domainNames(for: trimmedAddress)
            async let profile = model.profileName(for: trimmedAddress)
            previewDomains = await domains
            suggestedName = await profile
            if let suggestedName, alias.trimmingCharacters(in: .whitespaces).isEmpty { alias = suggestedName }
        }
    }

    private func add() {
        errorMessage = nil
        isAdding = true
        Task {
            defer { isAdding = false }
            do {
                try await model.addWatchOnlyWallet(alias: alias, address: address)
                await model.refresh()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
