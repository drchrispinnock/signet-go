import Foundation

/// iOS-specific care for the wallet directory: it must never reach iCloud or computer backups
/// (recovery is the phrase or an exported encrypted wallet, docs/PLAN.md), and its files are
/// unreadable while the device is locked.
enum WalletDirectory {
    static func prepare(_ directory: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
