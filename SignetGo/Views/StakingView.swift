import SwiftUI

/// Delegation and staking for the selected account, after upstream's `StakingSheet`: delegate,
/// change or remove the delegate; stake, unstake, finalize. Each action is estimated first and
/// sent with exactly those limits (upstream's `estimateStaking` / `performStaking`).
struct StakingView: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    enum Mode: Equatable { case overview, chooseDelegate, amount(Kind), confirm(StakingOperation), working(StakingOperation), done(hash: String, level: Int, StakingOperation) }
    enum Kind { case stake, unstake }

    @State private var mode: Mode = .overview
    @State private var bakers: [BakerCandidate] = []
    @State private var bakerFilter = ""
    @State private var amountText = ""
    @State private var estimate: TransferEstimate?
    @State private var passphrase = ""
    @State private var errorMessage: String?
    @State private var delegateName: String?

    private var wallet: Wallet? { model.selectedWallet }
    private var info: DelegateInfo? { model.delegateInfo }
    private var balance: TezBalance? { model.tezBalance }
    private var needsPassphrase: Bool { wallet?.keyKind == .encrypted }
    private var canOperate: Bool { wallet?.keyKind.canSign == true }

    var body: some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .interactiveDismissDisabled(isWorking)
            .task { bakers = await model.bakers() }
            .task(id: model.delegateInfo?.delegate) {
                delegateName = nil
                guard let delegate = model.delegateInfo?.delegate else { return }
                let known = model.displayName(for: delegate, indexerAlias: bakers.first { $0.address == delegate }?.alias)
                delegateName = known.isOurs || known.name != delegate.shortened() ? known.name : (await model.profileName(for: delegate) ?? delegate.shortened())
            }
    }

    private var isWorking: Bool { if case .working = mode { true } else { false } }

    private var title: String {
        switch mode {
        case .overview: "Staking"
        case .chooseDelegate: "Choose a baker"
        case .amount(.stake): "Stake tez"
        case .amount(.unstake): "Unstake tez"
        case .confirm(let op), .working(let op): op.title
        case .done(_, _, let op): op.title
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        switch mode {
        case .overview, .done:
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    if case .done = mode { Task { await model.refreshAfterOperation() } }
                    dismiss()
                }
            }
        case .chooseDelegate:
            ToolbarItem(placement: .cancellationAction) { Button("Back") { mode = .overview } }
        case .amount(let kind):
            ToolbarItem(placement: .cancellationAction) { Button("Back") { mode = .overview } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Next") { if let amount = parsedAmount { startConfirm(kind == .stake ? .stake(amount) : .unstake(amount)) } }
                    .disabled(parsedAmount == nil)
            }
        case .confirm:
            ToolbarItem(placement: .cancellationAction) { Button("Back") { mode = .overview; errorMessage = nil } }
        case .working:
            ToolbarItem(placement: .confirmationAction) { ProgressView() }
        }
    }

    @ViewBuilder private var content: some View {
        switch mode {
        case .overview: overview
        case .chooseDelegate: bakerPicker
        case .amount(let kind): amountForm(kind)
        case .confirm(let op): confirmation(op, working: false)
        case .working(let op): confirmation(op, working: true)
        case .done(let hash, let level, _): doneView(hash: hash, level: level)
        }
    }

    // MARK: Overview

    private var overview: some View {
        Form {
            if !canOperate {
                Section { Label("Signet Go holds only this address's public key, so it can show but not change its delegation.", systemImage: "eye").foregroundStyle(.secondary) }
            }
            Section("Delegation") {
                if let info {
                    if info.isBaker {
                        Label { Text(canOperate ? "This account is a baker (self-delegated). Manage it under Baking." : "This address is a baker (self-delegated).") } icon: { Text("👨‍🍳") }
                    } else if let delegate = info.delegate {
                        HStack(spacing: 10) {
                            AccountAvatarView(address: delegate, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(delegateName ?? delegate.shortened())
                                Text(delegate.shortened()).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                        LabeledContent("Accepts staking", value: info.delegateAcceptsStaking.map { $0 ? "Yes" : "No" } ?? "Unknown")
                        if canOperate {
                            Button("Change delegate…") { mode = .chooseDelegate }
                            Button("Remove delegation", role: .destructive) { startConfirm(.delegate(to: nil)) }
                        }
                    } else {
                        Text("Not delegated. Delegating lets a baker earn rewards with your balance; the tez never leave your account.")
                            .foregroundStyle(.secondary)
                        if canOperate { Button("Delegate…") { mode = .chooseDelegate } }
                    }
                } else {
                    ProgressView()
                }
            }
            Section {
                if let balance {
                    LabeledContent("Spendable", value: AssetBalance.format(balance.spendable, symbol: "tz"))
                    LabeledContent("Staked", value: AssetBalance.format(balance.staked, symbol: "tz"))
                    if balance.unstakedFrozen > 0 { LabeledContent("Unstaking", value: AssetBalance.format(balance.unstakedFrozen, symbol: "tz")) }
                    if balance.unstakedFinalizable > 0 { LabeledContent("Ready to finalize", value: AssetBalance.format(balance.unstakedFinalizable, symbol: "tz")) }
                }
                if canOperate {
                    Button("Stake…") { amountText = ""; mode = .amount(.stake) }
                        .disabled(info?.canStake != true || (balance?.spendable ?? 0) <= 0)
                    Button("Unstake…") { amountText = ""; mode = .amount(.unstake) }
                        .disabled((balance?.staked ?? 0) <= 0)
                    Button("Finalize unstaked tez") { startConfirm(.finalizeUnstake) }
                        .disabled((balance?.unstakedFinalizable ?? 0) <= 0)
                }
            } header: {
                Text("Staking")
            } footer: {
                Text(info?.isBaker == true
                     ? "Staking your own tez raises your baking power and the stake others may add. Staked tez are frozen and can be slashed. Unstaking takes a few cycles, then needs finalizing."
                     : info?.canStake == true
                     ? "Staked tez earn more than delegated tez but are frozen and can be slashed if your baker misbehaves. Unstaking takes a few cycles, then needs finalizing."
                     : "Staking needs a delegate that accepts stakers.")
            }
        }
    }

    // MARK: Baker picker

    private var bakerPicker: some View {
        List {
            let pasted = Address(bakerFilter.trimmingCharacters(in: .whitespaces))
            if pasted.isValidAccount {
                Button { startConfirm(.delegate(to: pasted)) } label: {
                    HStack(spacing: 8) { AccountAvatarView(address: pasted, size: 28); Text("Use \(pasted.shortened())") }
                }
            }
            ForEach(filteredBakers) { baker in
                Button { startConfirm(.delegate(to: baker.address)) } label: {
                    HStack(spacing: 10) {
                        AccountAvatarView(address: baker.address, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(baker.alias ?? baker.address.shortened())
                            Text("\(baker.delegators) delegators · \(baker.stakers) stakers\(baker.acceptsStaking == true ? " · accepts staking" : baker.acceptsStaking == false ? " · no staking" : "")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(AssetBalance.format(baker.stakingBalance, symbol: "tz")).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
            }
            if bakers.isEmpty {
                Text("No baker list for this network; paste a baker's address in the search field.").font(.callout).foregroundStyle(.secondary)
            }
        }
        .searchable(text: $bakerFilter, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search bakers or paste an address")
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    }

    private var filteredBakers: [BakerCandidate] {
        let needle = bakerFilter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return bakers }
        return bakers.filter { ($0.alias?.lowercased().contains(needle) ?? false) || $0.address.value.lowercased().hasPrefix(needle) }
    }

    // MARK: Amount

    private func amountForm(_ kind: Kind) -> some View {
        Form {
            Section {
                HStack {
                    TextField("0.0", text: $amountText).font(.title3.monospacedDigit()).keyboardType(.decimalPad)
                    Text("tz").foregroundStyle(.secondary)
                    // No Max for staking: the fee comes out of the spendable balance.
                    if kind == .unstake {
                        Button("Max") { amountText = NSDecimalNumber(decimal: balance?.staked ?? 0).stringValue }.buttonStyle(.bordered)
                    }
                }
                LabeledContent(kind == .stake ? "Spendable" : "Staked", value: AssetBalance.format(kind == .stake ? (balance?.spendable ?? 0) : (balance?.staked ?? 0), symbol: "tz"))
            } footer: {
                Text(kind == .stake ? "Staked tez stay in your account but are frozen and shared in your baker's risk." : "Unstaked tez become spendable after a few cycles; come back to finalize them.")
            }
        }
    }

    private var parsedAmount: Decimal? {
        guard let value = Decimal(string: amountText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")), value > 0 else { return nil }
        if case .amount(.stake) = mode, value > (balance?.spendable ?? 0) { return nil }
        if case .amount(.unstake) = mode, value > (balance?.staked ?? 0) { return nil }
        return value
    }

    // MARK: Confirm

    private func confirmation(_ op: StakingOperation, working: Bool) -> some View {
        Form {
            Section {
                LabeledContent("Operation", value: op.title)
                if case .delegate(let to) = op, let to {
                    LabeledContent("Baker") {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(bakers.first { $0.address == to }?.alias ?? model.displayName(for: to, indexerAlias: nil).name)
                            Text(to.shortened()).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
                if case .stake(let a) = op { LabeledContent("Amount", value: AssetBalance.format(a, symbol: "tz")) }
                if case .unstake(let a) = op { LabeledContent("Amount", value: AssetBalance.format(a, symbol: "tz")) }
                if let estimate { LabeledContent("Fee", value: AssetBalance.format(estimate.fee, symbol: "tz")) } else { LabeledContent("Fee") { ProgressView() } }
            }
            if needsPassphrase, let wallet {
                Section { SecureField("Password for “\(wallet.alias)”", text: $passphrase) }
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            Section {
                Button {
                    Task { await perform(op) }
                } label: {
                    HStack {
                        Spacer()
                        if working { ProgressView(); Text("Waiting for the next block…") } else { Text("Confirm").fontWeight(.semibold) }
                        Spacer()
                    }
                }
                .disabled(working || estimate == nil || (needsPassphrase && passphrase.isEmpty))
            }
        }
    }

    private func doneView(hash: String, level: Int) -> some View {
        Form {
            Section {
                Label("Included in block \(level.formatted())", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Text(hash).font(.caption.monospaced()).textSelection(.enabled)
                if let url = model.network.explorerURL(operation: hash) { Link("View in the explorer", destination: url) }
            }
        }
    }

    // MARK: Actions

    private func startConfirm(_ op: StakingOperation) {
        errorMessage = nil
        estimate = nil
        mode = .confirm(op)
        Task {
            do { estimate = try await model.estimateStaking(op) } catch { errorMessage = error.localizedDescription }
        }
    }

    private func perform(_ op: StakingOperation) async {
        errorMessage = nil
        mode = .working(op)
        do {
            let result = try await model.performStaking(op, limits: estimate?.limits, passphrase: needsPassphrase ? passphrase : nil)
            passphrase = ""
            mode = .done(hash: result.hash, level: result.level, op)
        } catch {
            errorMessage = error.localizedDescription
            mode = .confirm(op)
        }
    }
}

/// One line under the balances: who the account delegates to, or that it is a baker. Tap → Staking.
struct DelegateRowView: View {
    @Bindable var model: WalletViewModel
    let open: () -> Void
    @State private var delegateName: String?

    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                icon.frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline).font(.subheadline.weight(.medium))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.primary)
        .task(id: model.delegateInfo?.delegate) {
            delegateName = nil
            guard let delegate = model.delegateInfo?.delegate, model.delegateInfo?.isBaker != true else { return }
            let known = model.displayName(for: delegate, indexerAlias: nil)
            if known.isOurs { delegateName = known.name; return }
            delegateName = await model.profileName(for: delegate) ?? delegate.shortened()
        }
    }

    @ViewBuilder private var icon: some View {
        if let info = model.delegateInfo, let delegate = info.delegate, !info.isBaker {
            AccountAvatarView(address: delegate, size: 36)
        } else {
            ZStack {
                Circle().fill(.quaternary)
                if model.delegateInfo?.isBaker == true { Text("👨‍🍳") } else { Image(systemName: "person.crop.circle.badge.questionmark").foregroundStyle(.secondary) }
            }
        }
    }

    private var headline: String {
        guard let info = model.delegateInfo else { return "Delegation" }
        if info.isBaker { return model.selectedWallet?.keyKind.canSign == true ? "You are a baker" : "This address is a baker" }
        if let delegate = info.delegate { return "Delegated to \(delegateName ?? delegate.shortened())" }
        return "Not delegated"
    }

    private var subtitle: String {
        guard let info = model.delegateInfo else { return "Checking…" }
        if model.selectedWallet?.address.isContract == true { return "A multisig delegates with its signers' signatures." }
        if let baker = info.baker { return baker.deactivated ? "Deactivated; reactivate under Baking" : "Self-delegated" }
        if info.delegate != nil {
            switch info.delegateAcceptsStaking {
            case .some(true): return "This baker accepts staking"
            case .some(false): return "This baker does not accept staking"
            case .none: return "Tap to stake or change delegate"
            }
        }
        return "Delegate to a baker to earn rewards"
    }
}
