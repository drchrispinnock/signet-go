import SwiftUI

// iOS versions of upstream's RenameWalletSheet, ForgetAccountSheet, ExportKeySheet and
// RememberKeySheet: same model calls and warnings, worded for a phone.

/// Renames the selected account's alias (in the octez files), optionally to its TzProfile name.
struct RenameAccountView: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var alias: String
    @State private var errorMessage: String?
    @State private var isSyncing = false

    init(model: WalletViewModel) {
        self.model = model
        _alias = State(initialValue: model.selectedWallet?.alias ?? "")
    }

    private var trimmedAlias: String { alias.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canRename: Bool { !trimmedAlias.isEmpty && trimmedAlias != model.selectedWallet?.alias }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $alias)
                Button {
                    syncWithProfile()
                } label: {
                    HStack { Label("Use its TzProfile name", systemImage: "person.crop.circle.badge.checkmark"); if isSyncing { Spacer(); ProgressView() } }
                }
                .disabled(isSyncing)
            } footer: {
                if let wallet = model.selectedWallet { Text(wallet.address.value).font(.caption.monospaced()) }
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .navigationTitle("Rename account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Rename", action: rename).disabled(!canRename) }
        }
    }

    private func syncWithProfile() {
        guard let wallet = model.selectedWallet else { return }
        errorMessage = nil
        isSyncing = true
        Task {
            defer { isSyncing = false }
            if let name = await model.profileName(for: wallet.address) { alias = name } else { errorMessage = "This address has no TzProfile name." }
        }
    }

    private func rename() {
        errorMessage = nil
        do {
            try model.renameSelectedWallet(to: trimmedAlias)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Forgets the selected account, with a second warning when Signet holds its secret key.
struct ForgetAccountView: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var second = false
    @State private var passphrase = ""
    @State private var errorMessage: String?
    @State private var isWorking = false

    private var wallet: Wallet? { model.selectedWallet }
    private var holdsSecret: Bool { [.unencrypted, .encrypted].contains(wallet?.keyKind) || wallet?.isSessionOnly == true }
    private var needsPassphrase: Bool { wallet?.keyKind == .encrypted }
    private var isSessionOnly: Bool { wallet?.isSessionOnly == true }

    private var firstText: String {
        if isSessionOnly {
            return "This is a paper key held in memory for this session only; it was never written to the device. Forgetting wipes it now. Without the key or its recovery phrase elsewhere, the account and its tez are lost."
        }
        return switch wallet?.keyKind {
        case .unencrypted, .encrypted: "Signet Go holds this account's secret key. Forgetting deletes it from this device. Without another copy of the key, an exported wallet or the recovery phrase, the account and its tez are lost."
        case .ledger: "This account's key stays on your Ledger; Signet Go will only forget how to reach it."
        case .remote, .unknown: "Signet Go will forget this account's signer entry. The key itself lives elsewhere and is not touched."
        default: "This is an address-book entry. Signet Go will forget the name and address; nothing else changes."
        }
    }

    var body: some View {
        Form {
            Section {
                if let wallet {
                    HStack(spacing: 10) {
                        AccountAvatarView(address: wallet.address, size: 36)
                        VStack(alignment: .leading) { Text(wallet.alias); Text(wallet.address.shortened()).font(.caption.monospaced()).foregroundStyle(.secondary) }
                    }
                }
            }
            if !second {
                Section {
                    Label(firstText, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                } footer: {
                    Text("The account itself stays on the chain with everything in it; forgetting only changes what this device knows.")
                }
            } else {
                Section {
                    Label(isSessionOnly
                          ? "Last chance. The key will be wiped from memory. Make sure you have the paper copy or the recovery phrase first."
                          : "Last chance. The secret key will be deleted from this device. Make sure you have exported it, or have the recovery phrase, first.",
                          systemImage: "exclamationmark.octagon.fill")
                        .foregroundStyle(.red)
                    if !isSessionOnly {
                        Label("Earlier backups of this device and exported wallets may still contain the key.", systemImage: "externaldrive.badge.exclamationmark")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if needsPassphrase, let wallet {
                    Section {
                        SecureField("Password for “\(wallet.alias)”", text: $passphrase)
                    } footer: {
                        Text("The key is encrypted; its password is needed before it can be thrown away.")
                    }
                }
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            Section {
                if !second && holdsSecret {
                    Button("Continue…") { second = true }
                } else {
                    Button(second ? "Forget for good" : "Forget", role: .destructive, action: forget)
                        .disabled(isWorking || (second && needsPassphrase && passphrase.isEmpty))
                }
            }
        }
        .navigationTitle(second ? "Are you sure?" : "Forget account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isWorking) } }
        .onDisappear { passphrase = "" }
    }

    private func forget() {
        errorMessage = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await model.forgetSelectedWallet(passphrase: needsPassphrase ? passphrase : nil)
                passphrase = ""
                await model.refresh()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Shows the selected account's secret key, after its password for encrypted keys.
struct ExportKeyView: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var passphrase = ""
    @State private var exported: WalletViewModel.ExportedKey?
    @State private var revealed = false
    @State private var copied: String?
    @State private var errorMessage: String?
    @State private var isWorking = false

    private var wallet: Wallet? { model.selectedWallet }
    private var needsPassphrase: Bool { wallet?.keyKind == .encrypted }

    var body: some View {
        Form {
            Section {
                Label("Anyone who has this secret key controls the account and everything in it. Never share it, never type it into a website or a chat, and keep any copy offline.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
            }
            if let exported {
                Section("Secret key") { keyRow(exported.clear, maskable: true) }
                if let encrypted = exported.encrypted {
                    Section {
                        keyRow(encrypted, maskable: false)
                    } header: {
                        Text("Encrypted form")
                    } footer: {
                        Text("What this device stores; it still needs this account's password. octez-client accepts both.")
                    }
                }
            } else if needsPassphrase, let wallet {
                Section {
                    SecureField("Password for “\(wallet.alias)”", text: $passphrase)
                    Button("Unlock", action: unlock).disabled(isWorking || passphrase.isEmpty)
                } footer: {
                    Text("The key is stored encrypted. Enter its password to decrypt and show it.")
                }
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .navigationTitle("Export secret key")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { close() } } }
        .onAppear { if !needsPassphrase { unlock() } }
        .onDisappear { exported = nil; passphrase = ""; revealed = false }
    }

    private func keyRow(_ value: String, maskable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(maskable && !revealed ? String(repeating: "•", count: 32) : value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .blur(radius: scenePhase == .active ? 0 : 8)
                .privacySensitive()
            HStack {
                if maskable {
                    Button(revealed ? "Hide" : "Reveal") { revealed.toggle() }.buttonStyle(.bordered)
                }
                Button(copied == value ? "Copied" : "Copy") { copy(value) }.buttonStyle(.bordered)
            }
        }
    }

    private func unlock() {
        errorMessage = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                exported = try await model.exportSecretKey(passphrase: needsPassphrase ? passphrase : nil)
                passphrase = ""
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// The pasteboard entry stays on this device and expires after two minutes.
    private func copy(_ value: String) {
        UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: value]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)])
        copied = value
        Task { try? await Task.sleep(for: .seconds(1.5)); if copied == value { copied = nil } }
    }

    private func close() {
        exported = nil
        revealed = false
        dismiss()
    }
}

/// Writes a session-only paper key to the device. On mainnet a clear key must take a password
/// (`KeyPolicy`).
struct RememberKeyView: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var protects = false
    @State private var passphrase = ""
    @State private var confirmation = ""
    @State private var errorMessage: String?
    @State private var isWorking = false

    private var wallet: Wallet? { model.selectedWallet }
    private var isClear: Bool { wallet?.keyKind == .unencrypted }
    private var mustProtect: Bool { isClear && KeyPolicy.requiresEncryption(on: model.network) }
    private var passphraseProblem: String? {
        guard isClear, protects || mustProtect else { return nil }
        return KeyPolicy.passwordProblem(passphrase, confirm: confirmation, on: model.network)
    }

    var body: some View {
        Form {
            Section {
                Label("This key is held in memory for this session only and would be forgotten when Signet Go quits. Remembering it writes it to this device, where it is kept like any other account and included in the device's backups.", systemImage: "clock.badge.exclamationmark")
                    .foregroundStyle(.orange)
            }
            Section {
                if isClear {
                    Toggle("Protect it with a password", isOn: mustProtect ? .constant(true) : $protects).disabled(mustProtect)
                    if protects || mustProtect {
                        SecureField("Password", text: $passphrase)
                        SecureField("Confirm password", text: $confirmation)
                        if let passphraseProblem, !passphrase.isEmpty { Text(passphraseProblem).font(.footnote).foregroundStyle(.secondary) }
                    }
                } else {
                    Text("The key is encrypted and will be stored as it is; its password stays the same.").foregroundStyle(.secondary)
                }
            } footer: {
                if mustProtect { Text("Mainnet keys are always encrypted on this device.") }
                else if isClear && !protects { Text("Without a password the key is written unencrypted.") }
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .navigationTitle("Remember key")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isWorking) }
            ToolbarItem(placement: .confirmationAction) {
                Button("Remember", action: remember).disabled(isWorking || passphraseProblem != nil || wallet?.isSessionOnly != true)
            }
        }
        .onDisappear { passphrase = ""; confirmation = "" }
    }

    private func remember() {
        errorMessage = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await model.rememberSelectedWallet(storePassphrase: isClear && (protects || mustProtect) ? passphrase : nil)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
