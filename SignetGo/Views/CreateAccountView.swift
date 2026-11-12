import SwiftUI

/// A new account (docs/PLAN.md, "Keys and recovery"). As on the Mac, a random key of any
/// supported type (upstream's `createWallet`), recoverable from the device backup or an
/// exported wallet. Or, for tz1 to tz3, a key from a fresh BIP39 recovery phrase: shown once,
/// three of its words checked, then derived by upstream's `KeyImporter` at 44'/1729'/0'/0' and
/// stored like an imported key. The phrase is never stored. Mainnet keys always get a
/// password (`KeyPolicy`).
struct CreateAccountView: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    enum Step { case details, phrase, verify, done }
    enum Method: String, CaseIterable, Identifiable {
        case random = "Key only", phrase = "Recovery phrase"
        var id: String { rawValue }
    }

    /// Curves a phrase can be used with. BIP32-Ed25519 (Ledger style) is for importing only.
    static let curves: [MnemonicCurve] = [.ed25519, .secp256k1, .p256]

    @State private var step: Step = .details
    @State private var method: Method = .random
    @State private var alias: String
    @State private var scheme: AddressScheme = .tz1
    @State private var curve: MnemonicCurve = .ed25519
    @State private var wordCount = 24
    @State private var encrypt: Bool
    @State private var password = ""
    @State private var confirmPassword = ""

    @State private var words: [String] = []
    @State private var revealed = false
    @State private var screenshotTaken = false
    @State private var wroteItDown = false
    @State private var checks: [Int] = []
    @State private var answers: [String] = ["", "", ""]

    @State private var errorMessage: String?
    @State private var isCreating = false

    init(model: WalletViewModel) {
        self.model = model
        _alias = State(initialValue: model.suggestedAlias())
        _encrypt = State(initialValue: model.network.isMainnet)
    }

    private var mustEncrypt: Bool { KeyPolicy.requiresEncryption(on: model.network) }

    private var trimmedAlias: String { alias.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var passwordProblem: String? {
        guard encrypt || mustEncrypt else { return nil }
        return KeyPolicy.passwordProblem(password, confirm: confirmPassword, on: model.network)
    }
    private var aliasTaken: Bool { model.wallets.contains { $0.alias == trimmedAlias } }
    private var canContinue: Bool {
        !trimmedAlias.isEmpty && !aliasTaken && passwordProblem == nil && (method == .phrase || scheme.isSupported) && !isCreating
    }
    private var answersMatch: Bool {
        checks.count == 3 && zip(checks, answers).allSatisfy { index, answer in
            answer.trimmingCharacters(in: .whitespaces).lowercased() == words[index]
        }
    }

    var body: some View {
        Group {
            switch step {
            case .details: details
            case .phrase: phrase
            case .verify: verify
            case .done: done
            }
        }
        .navigationTitle("Create account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if step != .done {
                    Button(step == .details ? "Cancel" : "Back") {
                        switch step {
                        case .details, .done: dismiss()
                        case .phrase: step = .details
                        case .verify: step = .phrase
                        }
                    }
                    .disabled(isCreating)
                }
            }
            ToolbarItem(placement: .confirmationAction) { primaryButton }
        }
        .interactiveDismissDisabled((step != .details && step != .done) || isCreating)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
            if step == .phrase, revealed { screenshotTaken = true }
        }
        // Nothing of the phrase outlives the screen.
        .onDisappear { words = []; answers = ["", "", ""]; password = ""; confirmPassword = "" }
    }

    @ViewBuilder private var primaryButton: some View {
        switch step {
        case .details:
            if isCreating {
                ProgressView()
            } else if method == .phrase {
                Button("Next") { makePhrase() }.disabled(!canContinue)
            } else {
                Button("Create") { createRandom() }.disabled(!canContinue)
            }
        case .phrase:
            Button("Next") { startVerify() }.disabled(!wroteItDown)
        case .verify:
            if isCreating { ProgressView() } else { Button("Create") { createFromPhrase() }.disabled(!answersMatch) }
        case .done:
            Button("Done") { dismiss() }
        }
    }

    // MARK: Step 1

    private var details: some View {
        Form {
            Section {
                TextField("Name", text: $alias)
                if aliasTaken { Text("You already have an account with this name.").font(.footnote).foregroundStyle(.orange) }
            }
            Section {
                Picker("Method", selection: $method) {
                    ForEach(Method.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if method == .random {
                    Picker("Key type", selection: $scheme) {
                        ForEach(AddressScheme.allCases.filter(\.isSupported), id: \.self) { option in
                            Text(option == .tz1 ? "\(option.rawValue) · \(option.displayName) (recommended)" : "\(option.rawValue) · \(option.displayName)").tag(option)
                        }
                    }
                    if let caveat = scheme.caveat {
                        Text(caveat).font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Picker("Key type", selection: $curve) {
                        ForEach(Self.curves) { Text($0.title).tag($0) }
                    }
                    Picker("Words", selection: $wordCount) {
                        Text("24").tag(24)
                        Text("12").tag(12)
                    }
                }
            } footer: {
                Text(method == .random
                     ? "As in Signet on the Mac: a new key, kept on this device and in its iCloud backup. Export the wallet to keep a copy of your own."
                     : "A phrase to write down that restores this account in any wallet that supports BIP39 recovery phrases. Available for tz1, tz2 and tz3.")
            }
            Section {
                Toggle("Encrypt with a password", isOn: mustEncrypt ? .constant(true) : $encrypt)
                    .disabled(mustEncrypt)
                if encrypt || mustEncrypt {
                    SecureField("Password", text: $password)
                    SecureField("Confirm password", text: $confirmPassword)
                    if let passwordProblem, !password.isEmpty { Text(passwordProblem).font(.footnote).foregroundStyle(.secondary) }
                }
            } footer: {
                if mustEncrypt {
                    Text("Mainnet keys are always encrypted: the key is in this device's backups, and the password is what protects it there. It is asked for when you send, and cannot be recovered.")
                } else if encrypt {
                    Text("The password is asked for when you send, and cannot be recovered.")
                } else {
                    Text("Unencrypted keys are stored unprotected. Only sensible on test networks.")
                }
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
    }

    // MARK: Done (random keys)

    @State private var showsExport = false

    private var done: some View {
        Form {
            Section {
                Label("“\(trimmedAlias)” is ready.", systemImage: "checkmark.circle.fill").font(.headline)
            }
            Section {
                Text("The key is on this device and, with iCloud Backup on, in its backup. To keep a copy of your own, export the wallet to Files.")
                    .font(.callout)
                Button("Export wallet…") { showsExport = true }
            }
        }
        .sheet(isPresented: $showsExport) { NavigationStack { ExportWalletView(model: model) } }
    }

    // MARK: Step 2

    private var phrase: some View {
        Form {
            Section {
                Label("Write these words down, in order, on paper. Anyone who has them can take everything in this account. Signet Go cannot show them again.", systemImage: "exclamationmark.shield")
                    .font(.callout)
            }
            Section {
                ZStack {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                        ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                            HStack(spacing: 6) {
                                Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 22, alignment: .trailing)
                                Text(word).font(.body.monospaced())
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    .blur(radius: revealed && scenePhase == .active ? 0 : 9)
                    .privacySensitive()
                    if !revealed {
                        Button { revealed = true } label: {
                            Label("Tap to show the phrase", systemImage: "eye").padding(10).background(.regularMaterial, in: Capsule())
                        }
                    }
                }
            }
            if screenshotTaken {
                Section {
                    Label("A screenshot of the phrase may be copied to your photo library and iCloud. Delete it, and consider starting again with a new phrase.", systemImage: "camera.badge.ellipsis")
                        .font(.footnote).foregroundStyle(.orange)
                }
            }
            Section {
                Toggle("I have written the phrase down", isOn: $wroteItDown).disabled(!revealed)
            }
        }
    }

    // MARK: Step 3

    private var verify: some View {
        Form {
            Section {
                Text("Check your copy: enter these words from it.").font(.callout)
            }
            Section {
                ForEach(Array(checks.enumerated()), id: \.offset) { slot, index in
                    TextField("Word \(index + 1)", text: $answers[slot])
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                }
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
    }

    // MARK: Actions

    private func makePhrase() {
        do {
            words = try RecoveryPhrase.generate(words: wordCount)
            revealed = false
            wroteItDown = false
            screenshotTaken = false
            step = .phrase
        } catch {
            errorMessage = "Could not make a recovery phrase."
        }
    }

    private func startVerify() {
        checks = Array(words.indices.shuffled().prefix(3)).sorted()
        answers = ["", "", ""]
        errorMessage = nil
        step = .verify
    }

    private func createRandom() {
        errorMessage = nil
        isCreating = true
        Task {
            defer { isCreating = false }
            do {
                try await model.createWallet(alias: trimmedAlias, scheme: scheme, passphrase: (encrypt || mustEncrypt) ? password : nil)
                password = ""; confirmPassword = ""
                await model.refresh()
                if model.network.isMainnet { step = .done } else { dismiss() }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func createFromPhrase() {
        errorMessage = nil
        isCreating = true
        let phrase = words.joined(separator: " ")
        Task {
            defer { isCreating = false }
            do {
                let material = try await model.keyImporter.key(fromMnemonic: phrase, passphrase: nil, derivationPath: "44'/1729'/0'/0'", curve: curve)
                try await model.importAccount(alias: trimmedAlias, material: material, storePassphrase: (encrypt || mustEncrypt) ? password : nil)
                await model.refresh()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
