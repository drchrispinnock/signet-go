import Foundation

/// iOS-specific care for the wallet directory, `Library/Application Support/.signet` (upstream's
/// `FileManager.userHome` is Application Support on iOS). It is included in the device's iCloud / computer
/// backup, as `~/.signet` is in the Mac's backups (docs/PLAN.md, "Keys and recovery"): mainnet
/// keys are always password-encrypted (`KeyPolicy`), so a backup holds only octez-encrypted
/// secrets there. The files are unreadable while the device is locked.
enum WalletDirectory {
    static func prepare(_ directory: URL) {
        let fm = FileManager.default
        // Builds before 2026-11-12 kept the wallet at the container's root, which only the
        // simulator allows; move it to the new place once.
        let legacy = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent(".signet", isDirectory: true)
        if legacy.standardizedFileURL != directory.standardizedFileURL, fm.fileExists(atPath: legacy.path), !fm.fileExists(atPath: directory.path) {
            try? fm.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.moveItem(at: legacy, to: directory)
        }
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
