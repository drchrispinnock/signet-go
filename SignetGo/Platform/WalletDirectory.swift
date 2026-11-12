import Foundation

/// iOS-specific care for the wallet directory, `Library/Application Support/Signet` (upstream's
/// `FileManager.userHome` is Application Support on iOS, and its folder is `Signet` there). It is included in the device's iCloud / computer
/// backup, as `~/.signet` is in the Mac's backups (docs/PLAN.md, "Keys and recovery"): mainnet
/// keys are always password-encrypted (`KeyPolicy`), so a backup holds only octez-encrypted
/// secrets there. The files are unreadable while the device is locked.
enum WalletDirectory {
    static func prepare(_ directory: URL) {
        let fm = FileManager.default
        // Earlier development builds kept the wallet at the container's root (which only the
        // simulator allows) and then at Application Support/.signet; move it here once.
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let legacy = [URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent(".signet", isDirectory: true),
                      support.appendingPathComponent(".signet", isDirectory: true)]
        for old in legacy where old.standardizedFileURL != directory.standardizedFileURL {
            guard fm.fileExists(atPath: old.path), !fm.fileExists(atPath: directory.path) else { continue }
            try? fm.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.moveItem(at: old, to: directory)
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
