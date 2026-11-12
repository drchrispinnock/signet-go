import Foundation
import Testing
@testable import Signet

@Suite struct KeyPolicyTests {
    @Test func mainnetRequiresALongerPassword() {
        #expect(KeyPolicy.requiresEncryption(on: .mainnet))
        #expect(!KeyPolicy.requiresEncryption(on: .shadownet))
        #expect(KeyPolicy.passwordProblem("elevenchars", confirm: "elevenchars", on: .mainnet) != nil)
        #expect(KeyPolicy.passwordProblem("twelve chars", confirm: "twelve chars", on: .mainnet) == nil)
        #expect(KeyPolicy.passwordProblem("twelve chars", confirm: "twelve charz", on: .mainnet) == "The passwords do not match.")
        #expect(KeyPolicy.passwordProblem("8 chars!", confirm: "8 chars!", on: .shadownet) == nil)
    }

    /// The container's root is read-only on a device (the simulator does not enforce it), so the
    /// wallet lives in Application Support.
    @Test func walletDirectoryIsInApplicationSupport() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #expect(TezosClientStore.defaultDirectory.standardizedFileURL.path.hasPrefix(support.standardizedFileURL.path))
        #expect(TezosClientStore.defaultDirectory.lastPathComponent == "Signet")
    }

    /// The wallet directory is in device backups again, and earlier builds' exclusion is undone.
    @Test func walletDirectoryIsBackedUp() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("signet-go-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        WalletDirectory.prepare(directory)
        url.removeAllCachedResourceValues()
        #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == false)
    }
}

/// Create account's "Key only" method: upstream's random keys, every type the Mac offers.
@MainActor @Suite struct RandomCreateTests {
    @Test func createsEncryptedKeysOfEverySupportedType() async throws {
        let model = WalletViewModel(wallets: [], chain: MockChainService(), walletStore: InMemoryWalletStore(), nodeProbe: { _ in throw URLError(.notConnectedToInternet) })
        for scheme in AddressScheme.allCases.filter(\.isSupported) {
            try await model.createWallet(alias: "Key \(scheme.rawValue)", scheme: scheme, passphrase: "a long password")
            let wallet = try #require(model.wallets.first { $0.alias == "Key \(scheme.rawValue)" })
            #expect(wallet.scheme == scheme && wallet.address.value.hasPrefix(scheme.rawValue))
            #expect(wallet.keyKind == .encrypted)
        }
    }
}
