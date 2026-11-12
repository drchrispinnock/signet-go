import SwiftUI

/// The selected account's address as a QR code, with copy and share. Tezos side only; the
/// Etherlink alias (and linking it) comes with the Etherlink work.
struct ReceiveView: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        if let wallet = model.selectedWallet {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 4) {
                        Text(wallet.alias).font(.headline)
                        ForEach(model.domains, id: \.self) { Text($0).font(.callout).foregroundStyle(.secondary) }
                    }
                    if let image = QRCode.image(for: wallet.address.value, size: 240) {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 240, height: 240)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 16).fill(.white))
                            .accessibilityLabel("QR code of the address")
                    }
                    Text(wallet.address.value)
                        .font(.callout.monospaced())
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                        .padding(.horizontal)
                    HStack(spacing: 12) {
                        Button {
                            UIPasteboard.general.string = wallet.address.value
                            copied = true
                        } label: {
                            Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        ShareLink(item: wallet.address.value) { Label("Share", systemImage: "square.and.arrow.up") }
                            .buttonStyle(.bordered)
                    }
                    Text("Only send tez and Tezos tokens on \(model.network.name) to this address.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding()
            }
            .navigationTitle("Receive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
