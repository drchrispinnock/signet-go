import Foundation

/// Signet Go's rules for keys written to the device (docs/PLAN.md, "Keys and recovery"). The
/// wallet directory reaches iCloud / computer backups, so on mainnet the octez password is all
/// that protects a key in a backup: it is required, and longer than upstream's minimum.
/// Session-only keys never reach the disk and keep upstream's rules.
enum KeyPolicy {
    /// Minimum password for a mainnet key on disk.
    static let mainnetMinimumPassword = 12

    /// Whether a key stored on this network must be encrypted.
    static func requiresEncryption(on network: Network) -> Bool { network.isMainnet }

    static func minimumPassword(on network: Network) -> Int {
        network.isMainnet ? max(mainnetMinimumPassword, WalletViewModel.minimumPassphraseLength) : WalletViewModel.minimumPassphraseLength
    }

    /// Why `password` cannot be used, or `nil`.
    static func passwordProblem(_ password: String, confirm: String, on network: Network) -> String? {
        let minimum = minimumPassword(on: network)
        if password.count < minimum { return "Use at least \(minimum) characters." }
        if password != confirm { return "The passwords do not match." }
        return nil
    }
}
