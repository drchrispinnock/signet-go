import SwiftUI

/// No accounts yet: the ways in. Ledger waits on Bluetooth.
struct WelcomeView: View {
    @Bindable var model: WalletViewModel
    @Binding var sheet: Sheet?

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image("SignetRing")
                .resizable().scaledToFit()
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 26))
            VStack(spacing: 8) {
                Text("Signet Go").font(.largeTitle.bold())
                Text("A Tezos wallet").foregroundStyle(.secondary)
            }
            Spacer()
            VStack(spacing: 12) {
                Button { sheet = .createAccount } label: {
                    Label("Create an account", systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button { sheet = .importAccount } label: {
                    Label("Import an account", systemImage: "key").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button { sheet = .addAddress } label: {
                    Label("Watch an address", systemImage: "eye").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            Button("Network: \(model.network.name)") { sheet = .networks }
                .font(.footnote)
        }
        .padding(24)
    }
}
