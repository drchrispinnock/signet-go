import SwiftUI

/// The sheets the app can show. One at a time, as on the Mac.
enum Sheet: Identifiable, Hashable {
    case send, receive, staking, rename, forget, exportKey, rememberKey, createAccount, addAddress, importAccount, exportWallet, networks, settings, connectDApp, dappRequest, bridge
    case createMultisig, addMultisig, signMultisig, submitMultisig, baking, governance, proofOfPossession, connectLedger, faucet
    case nft(NFT)
    case nftOperation(NFTOperation)
    case nftDownload(NFTDownload)

    var id: String {
        switch self {
        case .nft(let nft): "nft:" + nft.id
        case .nftOperation(let op): "op:" + op.id
        case .nftDownload(let download): "download:" + download.id
        default: String(describing: self)
        }
    }
}

/// Welcome screen with no accounts, else the dashboard.
struct RootView: View {
    @Bindable var model: WalletViewModel
    @State private var sheet: Sheet?
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Appearance.key) private var appearance: Appearance = .system
    @AppStorage(Disclaimer.key) private var showsDisclaimer = true
    @State private var disclaimerShown = false
    private let isTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    var body: some View {
        NavigationStack {
            Group {
                if model.wallets.isEmpty {
                    WelcomeView(model: model, sheet: $sheet)
                } else {
                    DashboardView(model: model, sheet: $sheet)
                }
            }
        }
        .sheet(item: $sheet) { sheet in
            NavigationStack {
                switch sheet {
                case .send:
                    if let sender = model.selectedWallet { SendSheet(model: model, sender: sender) }
                case .receive: ReceiveView(model: model)
                case .staking: StakingView(model: model)
                case .rename: RenameAccountView(model: model)
                case .forget: ForgetAccountView(model: model)
                case .exportKey: ExportKeyView(model: model)
                case .rememberKey: RememberKeyView(model: model)
                case .createAccount: CreateAccountView(model: model)
                case .addAddress: AddAddressView(model: model)
                case .importAccount: ImportAccountView(model: model)
                case .exportWallet: ExportWalletView(model: model)
                case .networks: NetworksView(model: model)
                case .settings: SettingsView(model: model)
                case .connectDApp: ConnectDAppView(model: model)
                case .bridge: BridgeView(model: model)
                // Expert mode: upstream's sheets, ported by scripts/port-views.py.
                case .createMultisig: CreateMultisigSheet(model: model)
                case .addMultisig: AddMultisigSheet(model: model)
                case .signMultisig: SignMultisigSheet(model: model)
                case .submitMultisig: SubmitMultisigSheet(model: model)
                case .baking: BakingSheet(model: model)
                case .governance: GovernanceSheet(model: model)
                case .proofOfPossession: ProofOfPossessionSheet(model: model)
                case .connectLedger: ConnectLedgerSheet(model: model)
                case .faucet: FaucetSheet(model: model)
                case .dappRequest:
                    if let request = model.dapps.current {
                        DAppRequestView(model: model, request: request).id(request.id)
                    }
                case .nft(let nft): NFTDetailView(model: model, nft: nft, next: $sheet)
                case .nftOperation(let operation): TransferNFTView(model: model, operation: operation)
                case .nftDownload(let download): DownloadNFTsView(download: download)
                }
            }
        }
        // dApp requests open by themselves, one sheet at a time: when another sheet is up they
        // wait for it to close (Connect closes itself when the first request arrives).
        .onChange(of: model.dapps.current?.id) { _, id in
            if id == nil, sheet == .dappRequest { sheet = nil }
            else if id != nil, sheet == nil { sheet = .dappRequest }
        }
        .onChange(of: sheet) { _, new in
            if new == nil, model.dapps.current != nil {
                Task { try? await Task.sleep(for: .milliseconds(400)); if sheet == nil, model.dapps.current != nil { sheet = .dappRequest } }
            }
        }
        // A signet:// pairing link opens Connect, which pairs with it.
        .onChange(of: model.pendingPairingCode) { _, code in
            if code != nil, sheet != .connectDApp { sheet = .connectDApp }
        }
        .preferredColorScheme(appearance.colorScheme)
        .alert(Disclaimer.title, isPresented: $disclaimerShown) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(Disclaimer.message)
        }
        // The node lights poll only while the app is in front.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.nodeMonitor.start(); model.l2Monitor.start()
            } else {
                model.nodeMonitor.stop(); model.l2Monitor.stop()
            }
        }
        .task {
            if showsDisclaimer, !isTestHost { disclaimerShown = true }
            model.nodeMonitor.start()
            model.l2Monitor.start()
            #if DEBUG
            // Screenshots: `simctl launch … -SignetGoActivityTab nfts` opens on that tab.
            if let tab = UserDefaults.standard.string(forKey: "SignetGoActivityTab"),
               let choice = WalletViewModel.ActivityTab.allCases.first(where: { String(describing: $0) == tab }) {
                model.activityTab = choice
            }
            #endif
            await model.refresh()
        }
    }
}
