import Testing
@testable import Signet

/// Buy and TzEL shielded transactions are never offered in Signet Go (docs/PLAN.md). Upstream's
/// shielded code is compiled because `WalletViewModel` carries it; these checks make sure nothing
/// turns it on.
@Suite struct NeverIncludedTests {
    @Test func shieldedTransactionsAreOffOnEveryNetwork() {
        for network in Network.all {
            #expect(!network.shieldedEnabled, "\(network.name) has shielded transactions on")
        }
    }

    @Test @MainActor func theAppModelStartsWithShieldedOff() {
        let model = SignetGoApp.makeModel(isTestHost: true)
        #expect(!model.network.shieldedEnabled)
        #expect(model.shieldedWallet == nil)
    }
}
