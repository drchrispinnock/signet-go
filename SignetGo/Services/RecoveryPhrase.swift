import CryptoKit
import Foundation
import Security

/// BIP39 recovery phrases, made in Swift so the entropy never passes through JavaScript: random
/// bytes from the system generator, a SHA-256 checksum, 11 bits per word from the English list
/// (`bip39-english.txt`, SHA-256 2f5eed53…dbda). The key is then derived by upstream's
/// `KeyImporter.key(fromMnemonic:…)`, the same path Import uses, so a phrase made here restores
/// in any BIP39 Tezos wallet. A candidate to move upstream for the Mac.
enum RecoveryPhrase {
    enum PhraseError: Error { case wordList, randomness, entropyLength }

    /// Words for a phrase of this many bits of entropy: 128 → 12 words, 256 → 24.
    static let allowedEntropyBits = [128, 160, 192, 224, 256]

    static let wordList: [String] = {
        guard let url = Bundle.main.url(forResource: "bip39-english", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline).map(String.init)
    }()

    /// A new phrase from fresh system randomness.
    static func generate(words: Int = 24) throws -> [String] {
        let bits = words * 11 * 32 / 33
        guard allowedEntropyBits.contains(bits) else { throw PhraseError.entropyLength }
        var entropy = [UInt8](repeating: 0, count: bits / 8)
        defer { entropy.withUnsafeMutableBytes { _ = memset_s($0.baseAddress, $0.count, 0, $0.count) } }
        guard SecRandomCopyBytes(kSecRandomDefault, entropy.count, &entropy) == errSecSuccess else { throw PhraseError.randomness }
        return try phrase(fromEntropy: entropy)
    }

    /// The phrase for `entropy` (16 to 32 bytes, a multiple of 4), per BIP39.
    static func phrase(fromEntropy entropy: [UInt8]) throws -> [String] {
        guard allowedEntropyBits.contains(entropy.count * 8) else { throw PhraseError.entropyLength }
        guard wordList.count == 2048 else { throw PhraseError.wordList }
        let checksumBits = entropy.count * 8 / 32
        let hash = Array(SHA256.hash(data: entropy))
        var bits: [Bool] = []
        bits.reserveCapacity(entropy.count * 8 + checksumBits)
        for byte in entropy { for i in (0..<8).reversed() { bits.append(byte >> i & 1 == 1) } }
        for i in 0..<checksumBits { bits.append(hash[i / 8] >> (7 - i % 8) & 1 == 1) }
        return stride(from: 0, to: bits.count, by: 11).map { start in
            wordList[bits[start..<start + 11].reduce(0) { $0 << 1 | ($1 ? 1 : 0) }]
        }
    }
}
