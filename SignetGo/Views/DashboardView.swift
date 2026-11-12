import SwiftUI

/// The selected account: who it is, what it can do, what it holds and what it did.
struct DashboardView: View {
    @Bindable var model: WalletViewModel
    @Binding var sheet: Sheet?

    var body: some View {
        List {
            Section {
                AccountHeaderView(model: model)
                ActionButtonsView(model: model, sheet: $sheet)
                    .listRowSeparator(.hidden)
            }
            if model.accountNotOnChain {
                Section { AccountNotOnChainView(model: model) }
            } else {
                Section {
                    ForEach(model.assets) { AssetRowView(asset: $0) }
                    if !(model.selectedWallet?.address.isContract ?? true) {
                        DelegateRowView(model: model) { sheet = .staking }
                    }
                }
            }
            Section {
                Picker("Activity", selection: $model.activityTab) {
                    Text("Activity").tag(WalletViewModel.ActivityTab.transactions)
                    Text("Tokens").tag(WalletViewModel.ActivityTab.assets)
                    Text("NFTs").tag(WalletViewModel.ActivityTab.nfts)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                switch model.activityTab {
                case .nfts:
                    NFTGridSection(model: model, sheet: $sheet)
                case .transactions:
                    if model.visibleTransactions.isEmpty {
                        Text(model.isLoading ? "Loading…" : "No transactions yet.").foregroundStyle(.secondary)
                    }
                    ForEach(model.visibleTransactions) { TransactionRowView(model: model, transaction: $0) }
                case .assets:
                    if model.visibleTokens.isEmpty {
                        Text(model.isLoading ? "Loading…" : "No tokens.").foregroundStyle(.secondary)
                    }
                    PortfolioStateNote(state: model.portfolioState)
                    ForEach(model.visibleTokens) { AssetRowView(asset: $0) }
                }
            }
            if let error = model.errorMessage {
                Section { Text(error).foregroundStyle(.red) }
            }
            Section {
                Button { sheet = .networks } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "network")
                        Text(model.network.name)
                        if !model.network.isMainnet { BadgeLabel(text: "Test network") }
                    }
                    .font(.footnote)
                }
                NodeStatusRow(monitor: model.nodeMonitor, label: "Layer 1")
                if model.network.hasL2 { NodeStatusRow(monitor: model.l2Monitor, label: "Layer 2") }
            }
        }
        .navigationTitle(model.selectedWallet?.alias ?? "Signet Go")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                AccountSwitcher(model: model)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if model.selectedWallet != nil {
                        Section(model.selectedWallet?.alias ?? "") {
                            Button("Rename…", systemImage: "pencil") { sheet = .rename }
                            if model.canExportSelectedKey {
                                Button("Export secret key…", systemImage: "key.viewfinder") { sheet = .exportKey }
                            }
                            if model.canRememberSelectedKey {
                                Button("Remember key…", systemImage: "square.and.arrow.down") { sheet = .rememberKey }
                            }
                            Button("Forget…", systemImage: "trash", role: .destructive) { sheet = .forget }
                        }
                    }
                    Button("Create account…", systemImage: "plus") { sheet = .createAccount }
                    Button("Import account…", systemImage: "key") { sheet = .importAccount }
                    Button("Watch an address…", systemImage: "eye") { sheet = .addAddress }
                    Button("Export wallet…", systemImage: "square.and.arrow.up") { sheet = .exportWallet }
                    Divider()
                    Button("dApps…", systemImage: "app.connected.to.app.below.fill") { sheet = .connectDApp }
                    Divider()
                    Button("Networks…", systemImage: "network") { sheet = .networks }
                    Button("Settings…", systemImage: "gear") { sheet = .settings }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .refreshable { await model.refresh() }
    }
}

/// The account list as a menu: ours first, then the address book.
struct AccountSwitcher: View {
    @Bindable var model: WalletViewModel

    var body: some View {
        Menu {
            let owned = model.wallets.filter { $0.keyKind != .none }
            let watched = model.wallets.filter { $0.keyKind == .none }
            if !owned.isEmpty {
                Section("My accounts") { ForEach(owned) { item($0) } }
            }
            if !watched.isEmpty {
                Section("Address book") { ForEach(watched) { item($0) } }
            }
        } label: {
            Image(systemName: "person.crop.circle")
        }
        .accessibilityLabel("Switch account")
    }

    private func item(_ wallet: Wallet) -> some View {
        Button {
            model.select(wallet)
            Task { await model.refresh() }
        } label: {
            if wallet.id == model.selectedWallet?.id {
                Label(wallet.alias, systemImage: "checkmark")
            } else {
                Text(wallet.alias)
            }
        }
    }
}

/// Avatar, alias, address with copy, Tezos Domains names, and what kind of account it is.
struct AccountHeaderView: View {
    @Bindable var model: WalletViewModel
    @State private var copied = false

    var body: some View {
        if let wallet = model.selectedWallet {
            HStack(spacing: 14) {
                AccountAvatarView(address: wallet.address, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(wallet.alias).font(.headline)
                        if wallet.keyKind == .none { BadgeLabel(text: "Watch only") }
                        if wallet.isSessionOnly { BadgeLabel(text: "This session") }
                    }
                    Button {
                        UIPasteboard.general.string = wallet.address.value
                        copied = true
                        Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                    } label: {
                        HStack(spacing: 4) {
                            Text(wallet.address.shortened()).font(.callout.monospaced())
                            Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.caption)
                        }
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(copied ? "Copied" : "Copy address")
                    ForEach(model.domains, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct BadgeLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(.secondary.opacity(0.15)))
            .foregroundStyle(.secondary)
    }
}

/// Send, Receive, Get tez (test networks), Stake.
struct ActionButtonsView: View {
    @Bindable var model: WalletViewModel
    @Binding var sheet: Sheet?

    var body: some View {
        HStack(spacing: 0) {
            action("Send", "arrow.up") { sheet = .send }
                .disabled(model.selectedWallet?.keyKind.canSign != true || model.accountNotOnChain)
            action("Receive", "arrow.down") { sheet = .receive }
            if !model.network.isMainnet, model.network.faucetURL != nil {
                action("Get tez", "drop") { Task { await model.requestTestTez() } }
                    .disabled(model.selectedWallet?.address.isContract != false || isFaucetBusy)
            }
            action("Stake", "lock") { sheet = .staking }
                .disabled(model.selectedWallet?.address.isContract != false || model.accountNotOnChain)
        }
        .buttonStyle(.borderless)
    }

    private var isFaucetBusy: Bool {
        if case .solving = model.faucetStatus { return true }
        return false
    }

    private func action(_ title: String, _ symbol: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(.tint.opacity(0.12)))
                Text(title).font(.caption)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// An account the node has never seen: nothing to show yet.
struct AccountNotOnChainView: View {
    @Bindable var model: WalletViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Key not found on chain", systemImage: "questionmark.circle").font(.headline)
            Text(model.network.isMainnet
                 ? "This account has never received tez on \(model.network.name). Use Receive to fund it."
                 : "This account has never received tez on \(model.network.name). Use Get tez to fund it from the faucet.")
                .font(.callout).foregroundStyle(.secondary)
            switch model.faucetStatus {
            case .solving(let done, let total): ProgressView(value: Double(done), total: Double(max(total, 1))) { Text("Asking the faucet…").font(.caption) }
            case .sent: Text("Faucet sent the tez; waiting for the block…").font(.caption)
            case .failed(let message): Text(message).font(.caption).foregroundStyle(.red)
            default: EmptyView()
            }
        }
        .padding(.vertical, 4)
    }
}
