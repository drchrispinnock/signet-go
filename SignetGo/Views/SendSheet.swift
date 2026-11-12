import SwiftUI

/// Send tez, iOS. For now only the side capture shared with upstream's `SendSheet` (same name and
/// signature, so upstream's `SendSideContextTests` run here): everything a side needs is captured
/// together when the screen opens (S16, S31), and neither side borrows the other's service.
@MainActor
struct SendSheet {
    struct SideContext {
        let network: Network
        let chain: any ChainService
        let spendable: Decimal?
        let implicitAccountsOnly: Bool
    }

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
}
