import SwiftUI

/// Pair with a dApp by pasting or scanning its Octez Connect code, and manage the connected
/// dApps (upstream's ConnectDAppSheet). The relay runs while Signet Go is in front.
struct ConnectDAppView: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var isPairing = false
    @State private var message: String?
    @State private var scanning = false

    private var dapps: DAppConnectionManager { model.dapps }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 6) {
                    Circle().fill(dapps.isStarted ? .green : (dapps.lastError == nil ? .gray : .red)).frame(width: 8, height: 8)
                    Text(dapps.isStarted ? "Octez Connect running" : (dapps.lastError == nil ? "Starting…" : "Octez Connect failed"))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error = dapps.lastError, !dapps.isStarted {
                    Text(error).font(.footnote).foregroundStyle(.red)
                    Button("Try again") { Task { await dapps.restart() } }
                }
            }
            Section {
                // Masked like a password: whoever holds the code can pair their own wallet with
                // that dApp session.
                SecureField("Pairing code", text: $code, prompt: Text("Paste the code from the dApp"))
                    .font(.callout.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button { scanning = true } label: { Label("Scan the dApp's QR code", systemImage: "qrcode.viewfinder") }
                Button {
                    pair()
                } label: {
                    HStack { Text("Pair"); if isPairing { Spacer(); ProgressView() } }
                }
                .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPairing)
            } footer: {
                Text("In the dApp choose Octez Connect (or Beacon), then “Pair wallet on another device”, and scan or copy the code. Signet Go connects over the Tezos relay; the dApp can be in any browser, on any device.")
            }
            switch dapps.pairing {
            case .waiting(let name):
                Section { HStack { ProgressView(); Text("Pairing with \(name)… waiting for the dApp to answer over the relay.").font(.callout).foregroundStyle(.secondary) } }
            case .paired(let name):
                Section { Text("Paired with \(name). It will now ask for permission.").font(.callout).foregroundStyle(.green) }
            case .failed(let why):
                Section { Text(why).font(.callout).foregroundStyle(.red) }
            case .idle:
                EmptyView()
            }
            if let message { Section { Text(message).foregroundStyle(.red) } }
            Section("Connected dApps") {
                if dapps.permissions.isEmpty {
                    Text("None yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(dapps.permissions) { permission in
                        HStack(spacing: 10) {
                            DAppIconView(url: permission.appIcon, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(permission.appName)
                                Text("\(walletName(for: permission.address)) · \(permission.networkType) · \(permission.scopes.joined(separator: ", "))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions { Button("Disconnect", role: .destructive) { Task { await dapps.disconnect(permission) } } }
                    }
                    Button("Disconnect all", role: .destructive) { Task { await dapps.disconnectAll() } }
                }
            }
        }
        .navigationTitle("dApps")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task { await dapps.reloadPermissions() }
        .onAppear { takePendingCode() }
        .onChange(of: model.pendingPairingCode) { takePendingCode() }
        // One sheet at a time: step aside when the dApp's first request arrives.
        .onChange(of: dapps.current?.id) { if dapps.current != nil { dismiss() } }
        .sheet(isPresented: $scanning) {
            NavigationStack {
                QRScannerView(title: "Scan pairing code") { scanned in
                    code = DAppScannedCode.code(from: scanned)
                    pair()
                }
            }
        }
    }

    private func walletName(for address: String) -> String {
        model.wallets.first { $0.address.value == address }?.alias ?? Address(address).shortened()
    }

    /// A code that arrived through a signet:// link is paired automatically.
    private func takePendingCode() {
        guard let pending = model.pendingPairingCode else { return }
        model.pendingPairingCode = nil
        code = pending
        pair()
    }

    private func pair() {
        isPairing = true
        message = nil
        Task {
            defer { isPairing = false }
            do {
                _ = try await dapps.pair(code: code)
                code = ""
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

/// A scanned pairing QR: a wallet link carrying `type=tzip10&data=<code>` (any scheme, as
/// dApps print `tezos://…` or a web link), or the bare code.
enum DAppScannedCode {
    static func code(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let components = URLComponents(string: trimmed), let items = components.queryItems,
           items.first(where: { $0.name.lowercased() == "type" })?.value?.lowercased() == "tzip10",
           let data = items.first(where: { $0.name.lowercased() == "data" })?.value, !data.isEmpty {
            return data
        }
        return trimmed
    }
}

/// dApp icon or a generic placeholder.
struct DAppIconView: View {
    let url: URL?
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let url {
                RemoteImage(urls: [url], maxPixelSize: 128) { image in
                    Image(uiImage: image).resizable().scaledToFit()
                } placeholder: { _ in placeholder }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22).fill(.quaternary)
            Image(systemName: "globe").font(.system(size: size * 0.5)).foregroundStyle(.secondary)
        }
    }
}
