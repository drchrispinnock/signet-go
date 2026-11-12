import SwiftUI

/// First iPhone screen: the accounts and the selected one's balances. A scaffold to prove
/// upstream's view model runs on iOS; the real dashboard replaces it.
struct HomeView: View {
    @Bindable var model: WalletViewModel

    var body: some View {
        NavigationStack {
            List {
                Section("Network") { Text(model.network.name) }
                if model.wallets.isEmpty {
                    Section { Text("No accounts yet.").foregroundStyle(.secondary) }
                } else {
                    Section("Accounts") {
                        ForEach(model.wallets) { wallet in
                            Button { model.select(wallet) } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(wallet.alias)
                                        Text(wallet.address.shortened()).font(.caption.monospaced()).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if wallet.id == model.selectedWallet?.id { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    }
                    Section("Balances") {
                        ForEach(model.assets) { asset in
                            LabeledContent(asset.name, value: asset.unavailable ?? asset.formattedAmount)
                        }
                    }
                }
                if let error = model.errorMessage {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Signet Go")
            .refreshable { await model.refresh() }
            .task { await model.refresh() }
        }
    }
}
