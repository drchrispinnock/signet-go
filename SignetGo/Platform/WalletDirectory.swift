import Foundation

/// iOS-specific care for the wallet directory. It is included in the device's iCloud / computer
/// backup, as `~/.signet` is in the Mac's backups (docs/PLAN.md, "Keys and recovery"): mainnet
/// keys are always password-encrypted (`KeyPolicy`), so a backup holds only octez-encrypted
/// secrets there. The files are unreadable while the device is locked.
enum WalletDirectory {
    static func prepare(_ directory: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        // Early development builds excluded the directory from backups; undo that.
        var url = directory
        if (try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup == true {
            var values = URLResourceValues()
            values.isExcludedFromBackup = false
            try? url.setResourceValues(values)
        }
    }
}
