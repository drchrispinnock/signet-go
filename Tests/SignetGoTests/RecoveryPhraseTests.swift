import Foundation
import Testing
@testable import Signet

@Suite struct RecoveryPhraseTests {
    @Test func wordListIsTheBIP39EnglishList() {
        #expect(RecoveryPhrase.wordList.count == 2048)
        #expect(RecoveryPhrase.wordList.first == "abandon" && RecoveryPhrase.wordList.last == "zoo")
    }

    /// Trezor's reference vectors (python-mnemonic vectors.json).
    @Test func matchesReferenceVectors() throws {
        #expect(try RecoveryPhrase.phrase(fromEntropy: [UInt8](repeating: 0, count: 16)).joined(separator: " ")
                == "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about")
        #expect(try RecoveryPhrase.phrase(fromEntropy: [UInt8](repeating: 0x7f, count: 16)).joined(separator: " ")
                == "legal winner thank year wave sausage worth useful legal winner thank yellow")
        #expect(try RecoveryPhrase.phrase(fromEntropy: [UInt8](repeating: 0xff, count: 32)).joined(separator: " ")
                == "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo vote")
    }

    @Test func refusesOddLengths() {
        #expect(throws: RecoveryPhrase.PhraseError.self) { try RecoveryPhrase.phrase(fromEntropy: [1, 2, 3]) }
        #expect(throws: RecoveryPhrase.PhraseError.self) { try RecoveryPhrase.generate(words: 13) }
    }

    @Test func generatesFreshPhrasesOfTheRightLength() throws {
        let a = try RecoveryPhrase.generate(words: 24), b = try RecoveryPhrase.generate(words: 24)
        #expect(a.count == 24 && b.count == 24 && a != b)
        #expect(try RecoveryPhrase.generate(words: 12).count == 12)
    }

    /// The bridge (upstream's BIP39 code in Taquito) accepts what Swift makes and derives the
    /// same address every time: the phrase is good for any BIP39 Tezos wallet.
    @Test func bridgeAcceptsGeneratedPhrasesAndDerivesStably() async throws {
        let importer = BridgeKeyImporter()
        for words in [12, 24] {
            let phrase = try RecoveryPhrase.generate(words: words).joined(separator: " ")
            let check = try await importer.check(mnemonic: phrase)
            #expect(check.isValid && check.wordCount == words)
            let one = try await importer.key(fromMnemonic: phrase, passphrase: nil, derivationPath: "44'/1729'/0'/0'", curve: .ed25519)
            let two = try await importer.key(fromMnemonic: phrase, passphrase: nil, derivationPath: "44'/1729'/0'/0'", curve: .ed25519)
            #expect(one.address == two.address && one.address.hasPrefix("tz1"))
        }
    }

    /// Pins what Taquito derives for the all-"abandon" reference phrase at Tezos's default path,
    /// so a change in derivation shows up. (To confirm against another wallet: import the phrase
    /// into Temple or Umami, Ed25519, account 0.)
    @Test func knownPhraseDerivesTheKnownAddress() async throws {
        let phrase = try RecoveryPhrase.phrase(fromEntropy: [UInt8](repeating: 0, count: 16)).joined(separator: " ")
        let key = try await BridgeKeyImporter().key(fromMnemonic: phrase, passphrase: nil, derivationPath: "44'/1729'/0'/0'", curve: .ed25519)
        #expect(key.address == "tz1VQA4RP4fLjEEMW2FR4pE9kAg5abb5h5GL")
    }
}

/// The promise of Create account: the phrase brings the account back. Create through the model
/// as the screen does, then restore from the phrase alone into an empty wallet.
@MainActor @Suite struct CreateAndRestoreTests {
    @Test func phraseRestoresTheCreatedAccount() async throws {
        for curve in CreateAccountView.curves {
            let phrase = try RecoveryPhrase.generate(words: 24).joined(separator: " ")
            let created = WalletViewModel(wallets: [], chain: MockChainService(), keyImporter: BridgeKeyImporter(), walletStore: InMemoryWalletStore(), nodeProbe: { _ in throw URLError(.notConnectedToInternet) })
            let material = try await created.keyImporter.key(fromMnemonic: phrase, passphrase: nil, derivationPath: "44'/1729'/0'/0'", curve: curve)
            try await created.importAccount(alias: "Mine", material: material, storePassphrase: "correct horse")
            let account = try #require(created.wallets.first { $0.alias == "Mine" })
            #expect(account.keyKind == .encrypted)
            #expect(account.address.value == material.address)

            // Lost the device: a new wallet, the phrase typed in.
            let restored = try await BridgeKeyImporter().key(fromMnemonic: phrase, passphrase: nil, derivationPath: "44'/1729'/0'/0'", curve: curve)
            #expect(restored.address == account.address.value, "\(curve) did not restore")
            #expect(restored.publicKey == account.publicKey)
        }
    }
}
