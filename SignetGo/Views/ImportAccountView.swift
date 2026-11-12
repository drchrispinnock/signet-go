import SwiftUI

/// iOS version of upstream's `ImportAccountSheet` (same state and logic, iPhone layout).
/// Brings in an existing account from a recovery phrase or a pasted secret key. The secret is
/// derived or checked through the bridge, previewed, then written to the key store (clear, or
/// encrypted with a password like Create account), or kept in memory for this session only: a
/// paper key that is never written to disk and is forgotten when Signet quits.
struct ImportAccountView: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    enum Source: String, CaseIterable, Identifiable {
        case secretKey = "Secret key"
        case phrase = "Recovery phrase"
        var id: String { rawValue }
    }

    /// Where the key goes: the wallet directory, or memory until the app quits.
    enum Keep: Hashable {
        case directory, session
    }

    @State private var source: Source = .secretKey
    @State private var alias: String
    // Phrase
    @State private var phrase = ""
    @State private var phrasePassphrase = ""
    @State private var curve: MnemonicCurve = .ed25519
    @State private var account = 0
    @State private var legacy = false
    @State private var fundraiserEmail = ""
    @State private var fundraiserPassword = ""
    @State private var phraseCheck: MnemonicCheck?
    // Secret key
    @State private var secretKeyText = ""
    @State private var keyPassphrase = ""
    @State private var inspected: InspectedSecretKey?
    // Storage
    @State private var keep: Keep = .directory
    @State private var encrypt: Bool
    @State private var password = ""
    @State private var confirmPassword = ""

    @State private var preview: KeyMaterial?
    @State private var previewTask: Task<Void, Never>?
    @State private var previewError: String?
    @State private var errorMessage: String?
    @State private var isImporting = false

    init(model: WalletViewModel) {
        self.model = model
        _alias = State(initialValue: model.suggestedAlias(base: "Imported"))
        _encrypt = State(initialValue: model.network.isMainnet)
    }

    private var trimmedAlias: String { alias.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var derivationPath: String { "44'/1729'/\(account)'/0'" }
    private var existing: Wallet? { preview.flatMap { m in model.wallets.first { $0.address.value == m.address } } }
    /// An encrypted key pasted in is stored as it is; the storage password question does not apply.
    private var keepsOwnEncryption: Bool { source == .secretKey && inspected?.isEncrypted == true }
    private var passwordProblem: String? {
        guard encrypt, !keepsOwnEncryption else { return nil }
        if password.count < WalletViewModel.minimumPassphraseLength { return "Use at least \(WalletViewModel.minimumPassphraseLength) characters." }
        if password != confirmPassword { return "The passwords do not match." }
        return nil
    }
    private var canImport: Bool { preview != nil && existing == nil && !trimmedAlias.isEmpty && passwordProblem == nil && !isImporting }

    var body: some View {
        Form {
            Section {
                Picker("Source", selection: $source) {
                    ForEach(Source.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Section {
                TextField("Name", text: $alias, prompt: Text("Imported"))
            }
            Section {
                switch source {
                case .secretKey: secretKeyFields
                case .phrase: phraseFields
                }
            }
            Section("Address") { previewRow }
            Section("Storage") { storageFields }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Import account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isImporting) }
            ToolbarItem(placement: .confirmationAction) {
                if isImporting { ProgressView() } else { Button("Import", action: importAccount).disabled(!canImport) }
            }
        }
        .onChange(of: source) { refreshPreview() }
        .onChange(of: phrase) { refreshPreview() }
        .onChange(of: phrasePassphrase) { refreshPreview() }
        .onChange(of: curve) { refreshPreview() }
        .onChange(of: account) { refreshPreview() }
        .onChange(of: legacy) { refreshPreview() }
        .onChange(of: fundraiserEmail) { refreshPreview() }
        .onChange(of: fundraiserPassword) { refreshPreview() }
        .onChange(of: secretKeyText) { refreshPreview() }
        .onChange(of: keyPassphrase) { refreshPreview() }
    }

    // MARK: Phrase

    @ViewBuilder
    private var phraseFields: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recovery phrase").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $phrase)
                .font(.body.monospaced())
                .frame(minHeight: 96)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if let phraseCheck, phraseCheck.wordCount > 0 {
                if !phraseCheck.unknownWords.isEmpty {
                    Text("Not in the word list: \(phraseCheck.unknownWords.joined(separator: ", "))").font(.caption).foregroundStyle(.orange)
                } else if !phraseCheck.isValid {
                    Text("\(phraseCheck.wordCount) words; a phrase has 12, 15, 18, 21 or 24 words and a valid checksum.").font(.caption).foregroundStyle(.orange)
                } else {
                    Text("\(phraseCheck.wordCount)-word phrase").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        Toggle("Legacy fundraiser derivation", isOn: $legacy)
        if legacy {
            TextField("Email", text: $fundraiserEmail).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress)
            SecureField("Fundraiser password", text: $fundraiserPassword)
            Text("For keys from the 2017 fundraiser and some very old wallets.").font(.footnote).foregroundStyle(.secondary)
        } else {
            SecureField("Phrase passphrase (optional)", text: $phrasePassphrase)
            Picker("Key type", selection: $curve) {
                ForEach(MnemonicCurve.allCases) { Text($0.title).tag($0) }
            }
            Stepper("Account \(account)", value: $account, in: 0...100)
            Text("Path \(derivationPath). Temple, Kukai, Umami and most wallets use Ed25519 at account 0.").font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: Secret key

    @ViewBuilder
    private var secretKeyFields: some View {
        SecureField("Secret key", text: $secretKeyText, prompt: Text("edsk… / spsk… / p2sk… / BLsk… / edesk…"))
            .font(.body.monospaced())
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        if inspected?.isEncrypted == true || ["edesk", "spesk", "p2esk", "BLesk", "mdesk"].contains(where: secretKeyText.hasPrefix) {
            SecureField("Password for this key", text: $keyPassphrase)
            Text("An octez-client encrypted key. It is stored as it is and keeps this password.").font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: Preview and storage

    @ViewBuilder
    private var previewRow: some View {
        if let preview {
            HStack(spacing: 8) {
                AccountAvatarView(address: Address(preview.address), size: 28)
                Text(preview.address).font(.caption.monospaced()).textSelection(.enabled)
            }
            if let existing {
                Label("Already in your list as “\(existing.alias)”", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
        } else if let previewError {
            Text(previewError).font(.callout).foregroundStyle(.orange)
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var storageFields: some View {
        Picker("Keep the key", selection: $keep) {
            Text("On this device").tag(Keep.directory)
            Text("Only until Signet Go quits").tag(Keep.session)
        }
        .pickerStyle(.inline)
        .labelsHidden()
        if keep == .session {
            Label("A paper key for one session: held in memory only, never written to the device, and gone when the app quits. Import it again next time.", systemImage: "clock")
                .font(.footnote).foregroundStyle(.secondary)
        }
        if !keepsOwnEncryption {
            Toggle(keep == .session ? "Encrypt in memory with a password" : "Encrypt with a password", isOn: $encrypt)
            if encrypt {
                SecureField("Password", text: $password)
                SecureField("Confirm password", text: $confirmPassword)
                if let passwordProblem, !password.isEmpty { Text(passwordProblem).font(.footnote).foregroundStyle(.secondary) }
            } else if keep == .directory {
                Label("Unencrypted keys are stored unprotected. Only sensible on test networks.", systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.orange)
            }
        }
    }

    private func refreshPreview() {
        previewTask?.cancel()
        preview = nil
        previewError = nil
        inspected = nil
        let importer = model.keyImporter
        switch source {
        case .phrase:
            let words = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !words.isEmpty else { phraseCheck = nil; return }
            let (passphrase, path, curve, legacy, email, password) = (phrasePassphrase, derivationPath, curve, legacy, fundraiserEmail, fundraiserPassword)
            previewTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                do {
                    let check = try await importer.check(mnemonic: words)
                    guard !Task.isCancelled else { return }
                    phraseCheck = check
                    guard check.isValid else { return }
                    let material = legacy
                        ? try await importer.key(fromFundraiserEmail: email, password: password, mnemonic: words)
                        : try await importer.key(fromMnemonic: words, passphrase: passphrase.isEmpty ? nil : passphrase, derivationPath: path, curve: curve)
                    guard !Task.isCancelled else { return }
                    preview = material
                } catch {
                    if !Task.isCancelled { previewError = error.localizedDescription }
                }
            }
        case .secretKey:
            let key = secretKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            let passphrase = keyPassphrase
            previewTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                do {
                    let result = try await importer.inspect(secretKey: key, passphrase: passphrase.isEmpty ? nil : passphrase)
                    guard !Task.isCancelled else { return }
                    inspected = result
                    if result.needsPassphrase {
                        previewError = "Enter the key's password."
                    } else if let pk = result.publicKey, let address = result.address, let sk = result.secretKey {
                        preview = KeyMaterial(scheme: address.scheme ?? .tz1, publicKey: pk, address: address.value, secretKey: sk)
                    }
                } catch {
                    if !Task.isCancelled { previewError = error.localizedDescription }
                }
            }
        }
    }

    private func importAccount() {
        guard let preview else { return }
        errorMessage = nil
        isImporting = true
        Task {
            defer { isImporting = false }
            do {
                try await model.importAccount(alias: trimmedAlias, material: preview, alreadyEncrypted: keepsOwnEncryption,
                                              storePassphrase: (!keepsOwnEncryption && encrypt) ? password : nil,
                                              keepForSession: keep == .session)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
