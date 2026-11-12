import SwiftUI

/// The sheets the app can show. One at a time, as on the Mac.
enum Sheet: Identifiable, Hashable {
    case send, receive, staking, rename, forget, exportKey, rememberKey, createAccount, addAddress, importAccount, exportWallet, networks
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
                case .nft(let nft): NFTDetailView(model: model, nft: nft, next: $sheet)
                case .nftOperation(let operation): TransferNFTView(model: model, operation: operation)
                case .nftDownload(let download): DownloadNFTsView(download: download)
                }
            }
        }
        .task {
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
