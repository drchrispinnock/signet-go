import SwiftUI

/// The sheets the app can show. One at a time, as on the Mac.
enum Sheet: String, Identifiable {
    case send, receive, staking, rename, forget, exportKey, rememberKey, createAccount, addAddress, importAccount, exportWallet, networks
    var id: String { rawValue }
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
                }
            }
        }
        .task { await model.refresh() }
    }
}
