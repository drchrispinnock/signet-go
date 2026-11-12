import SwiftUI

/// Which chain a Send works on: Tezos itself, or Etherlink through its Michelson interface.
enum ChainSide: String, CaseIterable, Identifiable {
    case tezos = "Tezos", etherlink = "Etherlink"
    var id: String { rawValue }
}

/// Send tez, iOS: compose (recipient + amount), confirm (you → them, fee, total), then the
/// result. Upstream's `SendViewModel` does all of it: the approved estimate is the execution
/// limit (S14), and a lost node reply is an unknown outcome that can only be resent as the same
/// signed bytes (S15). With Layer 2 on, a segmented control switches to Etherlink.
struct SendSheet: View {
    /// Everything a side needs, captured together when the screen opened (S16, S31): the network
    /// shown and linked to is the one the chain service talks to, whatever Settings does later,
    /// and neither side ever borrows the other's service.
    struct SideContext {
        let network: Network
        let chain: any ChainService
        let spendable: Decimal?
        let implicitAccountsOnly: Bool
    }

    @Bindable var model: WalletViewModel
    @State private var send: SendViewModel
    @State private var side: ChainSide = .tezos
    private let sender: Wallet
    private let wallets: [Wallet]
    private let layer1: SideContext
    private let layer2: SideContext?
    @Environment(\.dismiss) private var dismiss

    private var context: SideContext { side == .etherlink ? (layer2 ?? layer1) : layer1 }
    private var canSwitch: Bool { layer2 != nil && sender.address.isUsableOnEtherlink }

    init(model: WalletViewModel, sender: Wallet) {
        self.model = model
        self.sender = sender
        self.wallets = model.wallets
        (layer1, layer2) = Self.capture(model)
        _send = State(initialValue: Self.makeSend(model: model, sender: sender, wallets: model.wallets, context: layer1))
    }

    /// Both sides as they are now; the Etherlink side exists only when its network and service
    /// are both there, and the pair never changes afterwards. Same name and signature as
    /// upstream's, so its `SendSideContextTests` run here.
    static func capture(_ model: WalletViewModel) -> (layer1: SideContext, layer2: SideContext?) {
        let layer1 = SideContext(network: model.network, chain: model.chainService, spendable: model.tezBalance?.spendable, implicitAccountsOnly: false)
        guard let network = model.network.layer2, let chain = model.layer2Chain else { return (layer1, nil) }
        return (layer1, SideContext(network: network, chain: chain, spendable: model.etherlinkSpendable, implicitAccountsOnly: true))
    }

    static func makeSend(model: WalletViewModel, sender: Wallet, wallets: [Wallet], context: SideContext) -> SendViewModel {
        SendViewModel(
            sender: sender,
            wallets: wallets,
            chain: context.chain,
            spendable: context.spendable,
            implicitAccountsOnly: context.implicitAccountsOnly,
            // SendViewModel is @MainActor and calls this from there.
            signerProvider: { [model] wallet, passphrase in try MainActor.assumeIsolated { try model.signingKey(for: wallet, passphrase: passphrase) } },
            proofProvider: { [model] wallet, passphrase in try await model.proofOfPossession(for: wallet, passphrase: passphrase) }
        )
    }

    var body: some View {
        Group {
            switch send.step {
            case .compose:
                ComposeTransferView(send: send, network: context.network, side: $side, canSwitch: canSwitch)
            case .confirm, .sending:
                ConfirmTransferView(send: send, network: context.network)
            case .sent, .unknown, .confirmed:
                TransferResultView(send: send, network: context.network)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            switch send.step {
            case .compose:
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Next") { Task { await send.proceedToConfirm() } }.disabled(!send.canProceed)
                }
            case .confirm, .sending:
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { send.backToCompose() }.disabled(send.step == .sending)
                }
            case .sent, .unknown, .confirmed:
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                        Task { await model.refreshAfterOperation() }
                    }
                }
            }
        }
        // Outstanding work from an earlier send (a lost reply) comes back before anything new.
        .task(id: side) { await send.recoverPending() }
        .onChange(of: side) { send = Self.makeSend(model: model, sender: sender, wallets: wallets, context: context) }
        .animation(.easeInOut(duration: 0.15), value: send.step)
        .interactiveDismissDisabled(send.step == .sending)
    }

    private var title: String {
        switch send.step {
        case .compose: side == .etherlink ? "Send on Etherlink" : "Send tez"
        case .confirm, .sending: "Confirm"
        default: "Sent"
        }
    }
}

// MARK: - Step 1

private struct ComposeTransferView: View {
    @Bindable var send: SendViewModel
    let network: Network
    @Binding var side: ChainSide
    let canSwitch: Bool
    @FocusState private var focus: Field?
    @State private var scanning = false
    private enum Field { case recipient, amount }

    var body: some View {
        Form {
            if canSwitch {
                Section {
                    Picker("Chain", selection: $side) {
                        ForEach(ChainSide.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            Section("From") {
                HStack(spacing: 10) {
                    AccountAvatarView(address: send.sender.address, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(send.sender.alias)
                        Text(send.sender.address.shortened()).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let spendable = send.spendable {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(AssetBalance.format(spendable, symbol: "tz")).font(.callout.monospacedDigit())
                            Text("spendable").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                TextField("To", text: $send.recipientText,
                          prompt: Text(send.implicitAccountsOnly ? "tz1, tz2 or tz3 address, or name.tez" : "Address or name.tez"),
                          axis: .vertical)
                    .font(.body.monospaced())
                    .focused($focus, equals: .recipient)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button { scanning = true } label: { Label("Scan a QR code", systemImage: "qrcode.viewfinder") }
                recipientStatus
                if send.recipient == nil {
                    ForEach(send.suggestions.prefix(6)) { wallet in
                        Button { send.choose(wallet) } label: {
                            HStack(spacing: 8) {
                                AccountAvatarView(address: wallet.address, size: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(wallet.alias)
                                    Text(wallet.address.shortened()).font(.caption.monospaced()).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(wallet.keyKind == KeyKind.none ? "Address book" : "My account")
                                    .font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            } header: {
                Text("To")
            }
            Section("Amount") {
                HStack {
                    TextField("0.0", text: $send.amountText)
                        .font(.title3.monospacedDigit())
                        .keyboardType(.decimalPad)
                        .focused($focus, equals: .amount)
                    Text("tz").foregroundStyle(.secondary)
                    Button("Max") { send.useMaximum() }
                        .buttonStyle(.bordered)
                        .disabled(send.spendable == nil)
                }
            }
            if send.needsPassphraseForProof {
                Section {
                    SecureField("Password for “\(send.sender.alias)”", text: $send.passphrase)
                } footer: {
                    Text("Sending to a tz4 account for the first time needs a proof of possession, signed with this account's key.")
                }
            }
            if let error = send.errorMessage {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .onAppear { focus = .recipient }
        .sheet(isPresented: $scanning) {
            NavigationStack { QRScannerView(title: "Scan recipient") { send.recipientText = ScannedRecipient.text(from: $0) } }
        }
    }

    @ViewBuilder private var recipientStatus: some View {
        if let recipient = send.recipient {
            HStack(spacing: 8) {
                AccountAvatarView(address: recipient.address, size: 24)
                Text(recipient.displayName).font(.callout)
                VerificationTag(recipient: recipient)
                Spacer()
            }
        } else if send.isResolving {
            HStack(spacing: 6) { ProgressView(); Text("Looking up name…").font(.callout).foregroundStyle(.secondary) }
        } else if !send.recipientText.isEmpty, send.suggestions.isEmpty, send.errorMessage == nil {
            Label("Not a valid address or .tez name", systemImage: "exclamationmark.triangle")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

/// "Verified" when the recipient is one of ours; otherwise the name is hearsay from an indexer.
struct VerificationTag: View {
    let recipient: SendViewModel.Recipient

    var body: some View {
        if recipient.isVerified {
            Label(recipient.wallet?.keyKind == KeyKind.none ? "Address book" : "My account", systemImage: "checkmark.seal.fill")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(.green.opacity(0.15)))
                .foregroundStyle(.green)
        } else {
            Label("Not verified", systemImage: "questionmark.circle")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(.orange.opacity(0.15)))
                .foregroundStyle(.orange)
                .accessibilityHint("This name comes from the recipient's public profile, not from your own records. Check the address.")
        }
    }
}

// MARK: - Step 2

private struct ConfirmTransferView: View {
    @Bindable var send: SendViewModel
    let network: Network

    var body: some View {
        Form {
            if let recipient = send.recipient, let amount = send.amount {
                Section {
                    HStack(alignment: .top, spacing: 0) {
                        party(address: send.sender.address, name: send.sender.alias, tag: nil)
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.right").font(.title2.weight(.semibold)).foregroundStyle(.tint)
                            Text(AssetBalance.format(amount, symbol: "tz")).font(.subheadline.monospacedDigit().weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                        party(address: recipient.address, name: recipient.displayName, tag: AnyView(VerificationTag(recipient: recipient)))
                    }
                    .padding(.vertical, 8)
                }
                Section {
                    LabeledContent("To") {
                        Text(recipient.address.value).font(.caption.monospaced()).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Network", value: network.name)
                    if let estimate = send.estimate {
                        LabeledContent("Amount", value: AssetBalance.format(amount, symbol: "tz"))
                        LabeledContent("Fee", value: AssetBalance.format(estimate.fee, symbol: "tz"))
                        if estimate.burn > 0 {
                            LabeledContent("Allocation", value: AssetBalance.format(estimate.burn, symbol: "tz"))
                        }
                        LabeledContent("Total", value: AssetBalance.format(estimate.total, symbol: "tz")).fontWeight(.semibold)
                    }
                } footer: {
                    if let estimate = send.estimate, estimate.burn > 0 {
                        Text("The recipient has never held tez; the chain charges once to create the account.")
                    }
                }
            }
            if send.needsPassphrase {
                Section {
                    SecureField("Password for “\(send.sender.alias)”", text: $send.passphrase)
                        .onSubmit { if !send.passphrase.isEmpty { Task { await send.send() } } }
                }
            }
            if let error = send.errorMessage {
                Section { Text(error).foregroundStyle(.red) }
            }
            Section {
                Button {
                    Task { await send.send() }
                } label: {
                    HStack {
                        Spacer()
                        if send.step == .sending {
                            ProgressView()
                            Text("Signing and sending…")
                        } else {
                            Text("Confirm and Send").fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(send.step == .sending || send.isBusy || (send.needsPassphrase && send.passphrase.isEmpty))
            }
        }
    }

    private func party(address: Address, name: String, tag: AnyView?) -> some View {
        VStack(spacing: 6) {
            AccountAvatarView(address: address, size: 56)
            Text(name).font(.subheadline.weight(.medium)).lineLimit(1)
            Text(address.shortened(prefix: 6, suffix: 4)).font(.caption.monospaced()).foregroundStyle(.secondary)
            if let tag { tag }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Step 3

private struct TransferResultView: View {
    let send: SendViewModel
    let network: Network
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                switch send.step {
                case .sent:
                    header("paperplane.fill", "Sent", "Waiting for the next block…", spinning: true)
                case .confirmed(_, let level):
                    header("checkmark.circle.fill", "Confirmed", "Included in block \(level.formatted())", spinning: false)
                case .unknown:
                    header("questionmark.circle.fill", "Not confirmed by the node", send.isBusy ? "Watching the chain…" : "The node's answer was lost", spinning: send.isBusy)
                default:
                    EmptyView()
                }
            }
            if let hash {
                Section("Operation") {
                    Text(hash).font(.caption.monospaced()).textSelection(.enabled)
                    if let url = network.explorerURL(operation: hash) {
                        Button("View in the explorer") { openURL(url) }
                    }
                }
            }
            if case .unknown = send.step {
                Section {
                    Button("Send the same operation again") { Task { await send.rebroadcast() } }.disabled(send.isBusy)
                } footer: {
                    Text("The operation was signed and handed to the node, but its answer did not arrive. Signet Go is watching the chain for it. Sending again sends the same signed operation, so it cannot be paid twice.")
                }
            }
            if let error = send.errorMessage {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
    }

    private var hash: String? {
        switch send.step {
        case .sent(let hash), .unknown(let hash): hash
        case .confirmed(let hash, _): hash
        default: nil
        }
    }

    private func header(_ symbol: String, _ title: String, _ subtitle: String, spinning: Bool) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 44)).foregroundStyle(.tint)
            Text(title).font(.title3.weight(.semibold))
            HStack(spacing: 6) {
                if spinning { ProgressView() }
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}
