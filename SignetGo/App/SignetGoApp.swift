import SwiftUI

@main
struct SignetGoApp: App {
    /// Under XCTest/Swift Testing the app is only the test host: nothing on disk is touched.
    static var isTestHost: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    /// The iOS composition root, after upstream's `SignetApp.makeModel`. Differences: the wallet
    /// directory is `Library/Application Support/Signet` (upstream's default, through
    /// `FileManager.userHome`),
    /// excluded from device backups and protected while the device is locked; there are no
    /// backup generations, no `~/.tezos-client` import, and shielded state stays in memory
    /// because shielded transactions are never enabled here (docs/PLAN.md).
    @MainActor static func makeModel(isTestHost: Bool = isTestHost) -> WalletViewModel {
        if isTestHost {
            return WalletViewModel(wallets: [], chain: MockChainService(), multisig: MockMultisigService(), walletStore: InMemoryWalletStore(), nodeProbe: { _ in throw URLError(.notConnectedToInternet) })
        }
        WalletDirectory.prepare(TezosClientStore.defaultDirectory)
        TaquitoBridge.shared.configureLog(at: TaquitoBridge.logFileURL)
        TaquitoBridge.shared.operationJournal = OperationJournal(directory: TezosClientStore.defaultDirectory)
        return WalletViewModel(
            chainFactory: { network in TaquitoChainService(network: network) },
            keyGenerator: KeyGenerator(),
            ledger: BridgeLedgerService(),
            keyImporter: BridgeKeyImporter(),
            multisig: BridgeMultisigService(),
            directorySettings: WalletDirectorySettings(),
            storeFactory: { directory in
                (wallets: TezosClientStore(directory: directory), state: FileAppStateStore(directory: directory))
            },
            dappStorageFactory: { directory in OctezConnectStorage(directory: directory) },
            dappDiagnostics: DeveloperSettings.dappDiagnostics,
            startDApps: true
        )
    }

    @State private var model = SignetGoApp.makeModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                // signet://?type=tzip10&data=<pairing code>: dApp pairing links.
                .onOpenURL { url in model.handleIncomingURL(url) }
        }
    }
}
