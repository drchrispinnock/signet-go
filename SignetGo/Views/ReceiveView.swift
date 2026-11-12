import SwiftUI

/// The selected account's address as a QR code, with copy and share (upstream's ReceiveSheet).
/// With Layer 2 on, a switch shows the account's address on Etherlink's EVM side, but only once
/// it is linked on chain (`EtherlinkAliasStatus.linked`): until the account's first
/// cross-interface call, tez sent there would sit at an address nobody controls, so the screen
/// offers to link it instead (a no-op gateway call paid on Etherlink).
struct ReceiveView: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var side: ChainSide = .tezos
    @State private var alias: AliasState = .checking
    @State private var estimate: TransferEstimate?
    @State private var passphrase = ""
    @State private var copied = false

    enum AliasState: Equatable {
        case checking
        case linked(String)
        case unlinked(fee: Decimal?, problem: String?, unfunded: Bool = false)
        case linking
        case failed(String)
    }

    private var wallet: Wallet? { model.selectedWallet }
    private var showsEtherlink: Bool { model.network.hasL2 && wallet?.address.isUsableOnEtherlink == true }
    private var needsPassphrase: Bool { wallet?.keyKind == .encrypted }
    private var address: String? {
        switch side {
        case .tezos: wallet?.address.value
        case .etherlink: if case .linked(let evm) = alias { evm } else { nil }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if showsEtherlink {
                    Picker("Chain", selection: $side) {
                        ForEach(ChainSide.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if let wallet {
                    VStack(spacing: 4) {
                        Text(wallet.alias).font(.headline)
                        if side == .tezos {
                            ForEach(model.domains, id: \.self) { Text($0).font(.callout).foregroundStyle(.secondary) }
                        } else {
                            Text("on Etherlink").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                if let address { addressViews(address) } else { linkViews }
            }
            .padding()
        }
        .navigationTitle("Receive")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(alias == .linking) } }
        .onChange(of: side) { copied = false }
        .task(id: side) { if side == .etherlink { await checkAlias() } }
        .onDisappear { passphrase = "" }
    }

    @ViewBuilder private func addressViews(_ address: String) -> some View {
        if let image = QRCode.image(for: address, size: 240) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .frame(width: 240, height: 240)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 16).fill(.white))
                .accessibilityLabel("QR code of the address")
        }
        Text(address).font(.callout.monospaced()).multilineTextAlignment(.center).textSelection(.enabled)
        HStack(spacing: 12) {
            Button {
                UIPasteboard.general.string = address
                copied = true
            } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.bordered)
            ShareLink(item: address) { Label("Share", systemImage: "square.and.arrow.up") }.buttonStyle(.bordered)
        }
        Text(side == .tezos
             ? "Only send tez and Tezos tokens on \(model.network.name) to this address."
             : "This account's address on Etherlink's EVM side. Tez sent to it on Etherlink are forwarded to this account; its own address on Etherlink's Michelson side is the Tezos one.")
            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
    }

    @ViewBuilder private var linkViews: some View {
        VStack(spacing: 12) {
            switch alias {
            case .checking:
                ProgressView()
                Text("Checking whether this account is known on Etherlink…").font(.callout).foregroundStyle(.secondary)
            case .linking:
                ProgressView()
                Text("Linking to Etherlink…").font(.callout).foregroundStyle(.secondary)
            case .failed(let message):
                Text(message).font(.callout).foregroundStyle(.red).multilineTextAlignment(.center)
                Button("Try again") { Task { await checkAlias() } }
            case .unlinked(let fee, let problem, let unfunded):
                Text("This account has no address on Etherlink's EVM side yet. Etherlink creates one the first time the account calls across from its Tezos side; tez sent there before that would be stuck at an address nobody controls.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if unfunded {
                    Text("Linking sends a small no-op call from this account on Etherlink, paid there, and this account holds no tez on Etherlink yet. Use Bridge to move a little across, then come back here.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Check again") { Task { await checkAlias() } }
                } else if wallet?.keyKind.canSign == true {
                    if needsPassphrase, let wallet {
                        SecureField("Password for “\(wallet.alias)”", text: $passphrase).textFieldStyle(.roundedBorder)
                    }
                    if let problem { Text(problem).font(.callout).foregroundStyle(.orange).multilineTextAlignment(.center) }
                    Button(fee.map { "Link to Etherlink (fee \(AssetBalance.format($0, symbol: "tz")))" } ?? "Link to Etherlink") { Task { await link() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(fee == nil || (needsPassphrase && passphrase.isEmpty))
                } else {
                    Text("Link it from a wallet that holds this account's key.").font(.callout).foregroundStyle(.secondary)
                }
            case .linked:
                EmptyView()
            }
        }
        .frame(maxWidth: 360, minHeight: 240)
    }

    private func checkAlias() async {
        guard let wallet else { return }
        alias = .checking
        do {
            guard let status = try await model.etherlinkAliasStatus() else { alias = .failed("Layer 2 is off for this network."); return }
            if case .linked(let evm) = status { alias = .linked(evm); return }
            guard wallet.keyKind.canSign else { alias = .unlinked(fee: nil, problem: nil); return }
            if model.etherlinkSpendable == 0 { alias = .unlinked(fee: nil, problem: nil, unfunded: true); return }
            do {
                let fee = try await model.estimateEtherlinkLink()
                estimate = fee
                alias = .unlinked(fee: fee.fee, problem: nil)
            } catch ChainError.cannotPayFee {
                alias = .unlinked(fee: nil, problem: nil, unfunded: true)
            } catch {
                alias = .unlinked(fee: nil, problem: "The link cannot be estimated: \(error.localizedDescription)")
            }
        } catch {
            alias = .failed(error.localizedDescription)
        }
    }

    private func link() async {
        let fee = estimate?.fee
        alias = .linking
        do {
            _ = try await model.linkToEtherlink(limits: estimate?.limits, passphrase: needsPassphrase ? passphrase : nil)
            passphrase = ""
            await checkAlias()
        } catch ChainError.cannotPayFee {
            alias = .unlinked(fee: nil, problem: nil, unfunded: true)
        } catch {
            alias = .unlinked(fee: fee, problem: error.localizedDescription)
        }
    }
}
