import SwiftUI

/// Which network Signet talks to. Node and Layer 2 settings come later.
struct NetworksView: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ForEach(Network.all, id: \.name) { network in
                    Button {
                        model.switchNetwork(to: network)
                        Task { await model.refresh() }
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(network.name)
                                Text(network.isMainnet ? "Real tez" : "Test network").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if network.name == model.network.name { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            } footer: {
                Text("Node: \(model.network.rpcURL.absoluteString)")
            }
        }
        .navigationTitle("Networks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}
