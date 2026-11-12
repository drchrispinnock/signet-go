import SwiftUI

// NFTs on iPhone, after upstream's NFTGridView, TransferNFTSheet and DownloadNFTsSheet: a grid
// in the dashboard's NFTs tab, a detail screen per token, a Select mode for several, and the
// same Transfer / Burn (approved-limits batch) and Download as on the Mac.

/// The dashboard's NFTs tab: the grid, or what to say instead.
struct NFTGridSection: View {
    @Bindable var model: WalletViewModel
    @Binding var sheet: Sheet?
    @State private var selecting = false
    @State private var selection: Set<NFT.ID> = []

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var perRow: Int { sizeClass == .regular ? 5 : 3 }
    private var rows: [[NFT]] { stride(from: 0, to: nfts.count, by: perRow).map { Array(nfts[$0..<min($0 + perRow, nfts.count)]) } }
    private var nfts: [NFT] { model.visibleNFTs }
    private var selected: [NFT] { nfts.filter { selection.contains($0.id) } }
    private var isUnavailable: Bool { if case .unavailable = model.portfolioState { true } else { false } }

    var body: some View {
        PortfolioStateNote(state: model.portfolioState)
        if nfts.isEmpty {
            Text(model.isLoading ? "Loading…" : (isUnavailable ? "NFT data is unavailable." : model.layerEmptyText(for: "NFTs") ?? "No NFTs in this account."))
                .foregroundStyle(.secondary)
        } else {
            HStack {
                Text("\(nfts.count) NFT\(nfts.count == 1 ? "" : "s")").font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Button(selecting ? "Done" : "Select") { selecting.toggle(); selection = [] }.font(.footnote)
            }
            // One List row per row of tiles, so the List only builds (and loads) what is on
            // screen; a single grid row would start every tile's download at once.
            ForEach(rows, id: \.first!.id) { row in
                HStack(alignment: .top, spacing: 10) {
                    ForEach(row) { nft in
                        NFTTileView(nft: nft, isSelected: selecting && selection.contains(nft.id))
                            .frame(maxWidth: .infinity)
                            .onTapGesture {
                                if selecting {
                                    if selection.contains(nft.id) { selection.remove(nft.id) } else { selection.insert(nft.id) }
                                } else {
                                    sheet = .nft(nft)
                                }
                            }
                    }
                    ForEach(row.count..<perRow, id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                }
                .listRowSeparator(.hidden)
            }
            .onChange(of: nfts.map(\.id)) { _, ids in selection = selection.intersection(ids) }
            if selecting {
                NFTBulkActions(model: model, targets: selected, sheet: $sheet)
            }
        }
    }
}

/// Transfer, Burn and Download for the tokens chosen in Select mode.
struct NFTBulkActions: View {
    @Bindable var model: WalletViewModel
    let targets: [NFT]
    @Binding var sheet: Sheet?

    var body: some View {
        let rule = NFTRules(model: model, targets: targets)
        HStack {
            Button("Transfer") { sheet = .nftOperation(NFTOperation(kind: .transfer, nfts: targets)) }.disabled(!rule.canOperate)
            Spacer()
            Button("Burn", role: .destructive) { sheet = .nftOperation(NFTOperation(kind: .burn, nfts: targets)) }.disabled(!rule.canOperate)
            Spacer()
            Button("Download") { sheet = .nftDownload(NFTDownload(nfts: targets)) }.disabled(targets.isEmpty || !rule.hasArtwork)
        }
        .buttonStyle(.bordered)
        if let reason = rule.reason, !targets.isEmpty {
            Text(reason).font(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// When Transfer and Burn are allowed, as upstream's context menu decides.
struct NFTRules {
    let model: WalletViewModel
    let targets: [NFT]
    private var layer: Int { targets.first?.layer ?? 1 }
    private var sameLayer: Bool { Set(targets.map(\.layer)).count == 1 }
    private var transferable: Bool { targets.allSatisfy(\.isTransferable) }
    var hasArtwork: Bool { targets.allSatisfy { !$0.artifactURLs.isEmpty || !$0.imageURLs.isEmpty } }
    @MainActor var canOperate: Bool {
        !targets.isEmpty && sameLayer && transferable && targets.count <= TokenTransferRequest.maxTokens && model.canTransferTokens(on: layer)
    }
    @MainActor var reason: String? {
        if !sameLayer { return "Choose NFTs on one chain at a time." }
        if !transferable { return targets.count == 1 ? "This token cannot be transferred." : "One of these tokens cannot be transferred." }
        if targets.count > TokenTransferRequest.maxTokens { return "At most \(TokenTransferRequest.maxTokens) NFTs at once." }
        if !model.canTransferTokens(on: layer) { return layer == 2 ? "Signet Go cannot sign for this account on Etherlink." : "Signet Go cannot sign for this account." }
        return nil
    }
}

struct NFTTileView: View {
    let nft: NFT
    var isSelected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { thumbnail }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary.opacity(0.25)), lineWidth: isSelected ? 3 : 1))
                .overlay(alignment: .topTrailing) {
                    if isSelected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, .tint).padding(5) }
                }
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: 4) {
                        if nft.isMoving { Image(systemName: "play.circle.fill").foregroundStyle(.white).shadow(radius: 2) }
                        if nft.isLayer2 { Image("EtherlinkLogo").resizable().frame(width: 16, height: 16) }
                    }
                    .padding(5)
                }
            Text(nft.name).font(.caption).lineLimit(1)
            if nft.balance > 1 {
                Text("×\(NSDecimalNumber(decimal: nft.balance).stringValue)").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(nft.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var thumbnail: some View {
        RemoteImage(urls: nft.imageURLs, maxPixelSize: 400) { image in
            Image(uiImage: image).resizable().scaledToFill()
        } placeholder: { failed in
            ZStack {
                Rectangle().fill(.quaternary)
                if failed { Image(systemName: "photo").foregroundStyle(.secondary) } else { ProgressView() }
            }
        }
    }
}

/// One token: its artwork, what it is, and what can be done with it.
struct NFTDetailView: View {
    @Bindable var model: WalletViewModel
    let nft: NFT
    @Binding var next: Sheet?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        let rule = NFTRules(model: model, targets: [nft])
        let network = model.tokenNetwork(on: nft.layer)
        List {
            Section {
                RemoteImage(urls: nft.imageURLs, maxPixelSize: 1200) { image in
                    Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12))
                } placeholder: { failed in
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(.quaternary).aspectRatio(1, contentMode: .fit)
                        if failed { Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary) } else { ProgressView() }
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            Section {
                LabeledContent("Name", value: nft.name)
                if nft.balance > 1 { LabeledContent("Editions held", value: NSDecimalNumber(decimal: nft.balance).stringValue) }
                LabeledContent("Contract") { Text(Address(nft.contract).shortened()).font(.callout.monospaced()) }
                LabeledContent("Token ID", value: nft.tokenId)
                if nft.isLayer2 { LabeledContent("Chain", value: "Etherlink") }
                if nft.isMoving { LabeledContent("Artwork", value: "Video or sound") }
            }
            Section {
                Button("Transfer…", systemImage: "paperplane") { open(.nftOperation(NFTOperation(kind: .transfer, nfts: [nft]))) }
                    .disabled(!rule.canOperate)
                Button("Burn…", systemImage: "flame", role: .destructive) { open(.nftOperation(NFTOperation(kind: .burn, nfts: [nft]))) }
                    .disabled(!rule.canOperate)
                Button("Download", systemImage: "arrow.down.circle") { open(.nftDownload(NFTDownload(nfts: [nft]))) }
                    .disabled(!rule.hasArtwork)
            } footer: {
                if let reason = rule.reason { Text(reason) }
            }
            Section {
                if let url = network.explorerURL(token: nft.contract, id: nft.tokenId) {
                    Button("Open in the explorer", systemImage: "safari") { openURL(url) }
                }
                if let url = network.objktURL(token: nft.contract, id: nft.tokenId) {
                    Button("Open on objkt.com", systemImage: "safari") { openURL(url) }
                }
                if let url = nft.artifactURLs.first {
                    Button(nft.isMoving ? "View artwork (plays in the browser)" : "View full artwork", systemImage: "photo") { openURL(url) }
                }
                Button("Copy contract address", systemImage: "doc.on.doc") { UIPasteboard.general.string = nft.contract }
                Button("Copy token ID", systemImage: "number") { UIPasteboard.general.string = nft.tokenId }
            }
        }
        .navigationTitle(nft.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }

    /// Replaces this sheet with another (one sheet at a time).
    private func open(_ sheet: Sheet) {
        dismiss()
        Task { try? await Task.sleep(for: .milliseconds(450)); next = sheet }
    }
}

/// Transfer or burn one or more NFTs, after upstream's `TransferNFTSheet`: the recipient
/// resolved as Send does, a count per token held in several editions, the fee, then the batch
/// sent with exactly the approved limits (S14, S31).
struct TransferNFTView: View {
    @Bindable var model: WalletViewModel
    let operation: NFTOperation
    @Environment(\.dismiss) private var dismiss

    enum Step: Hashable { case compose, working, done(hash: String, level: Int) }

    @State private var recipient: SendViewModel
    @State private var counts: [NFT.ID: Int]
    @State private var estimate: WalletViewModel.TokenTransferApproval?
    @State private var estimateError: String?
    @State private var passphrase = ""
    @State private var understoodBurn = false
    @State private var errorMessage: String?
    @State private var step: Step = .compose
    @State private var submitted: WalletViewModel.TokenTransferApproval?

    init(model: WalletViewModel, operation: NFTOperation) {
        self.model = model
        self.operation = operation
        let sender = model.selectedWallet ?? Wallet(alias: "", address: Address(""), keyKind: .none)
        let chain = operation.layer == 2 ? (model.layer2Chain ?? model.chainService) : model.chainService
        _recipient = State(initialValue: SendViewModel(sender: sender, wallets: model.wallets, chain: chain, spendable: nil,
                                                       implicitAccountsOnly: operation.layer == 2, signerProvider: { _, _ in nil }))
        _counts = State(initialValue: Dictionary(uniqueKeysWithValues: operation.nfts.map { ($0.id, 1) }))
    }

    private var isBurn: Bool { operation.kind == .burn }
    private var wallet: Wallet? { submitted?.context.wallet ?? model.selectedWallet }
    private var network: Network { model.tokenNetwork(on: operation.layer) }
    private var needsPassphrase: Bool { wallet?.keyKind == .encrypted }
    private var editions: Int { operation.nfts.reduce(0) { $0 + (counts[$1.id] ?? 1) } }

    private var request: TokenTransferRequest? {
        if let submitted { return submitted.request }
        guard let to = isBurn ? TokenTransferRequest.burnAddress : recipient.recipient?.address else { return nil }
        guard operation.nfts.allSatisfy({ (counts[$0.id] ?? 1) >= 1 && Decimal(counts[$0.id] ?? 1) <= $0.balance }) else { return nil }
        let request = TokenTransferRequest(to: to, transfers: operation.nfts.map { TokenTransfer(nft: $0, amount: counts[$0.id] ?? 1) })
        return request.isValid ? request : nil
    }

    private var canConfirm: Bool {
        guard let request, let estimate, estimate.request == request, estimate.context == model.bridgeContext else { return false }
        return step == .compose && model.canTransferTokens(on: operation.layer) && !(needsPassphrase && passphrase.isEmpty) && (!isBurn || understoodBurn)
    }

    private struct EstimateKey: Hashable {
        let request: TokenTransferRequest?
        let context: WalletViewModel.BridgeContext?
        let step: Step
    }

    var body: some View {
        Form {
            Section(operation.nfts.count == 1 ? "Token" : "\(operation.nfts.count) tokens") {
                ForEach(operation.nfts) { nft in
                    HStack(spacing: 10) {
                        NFTTileView(nft: nft).frame(width: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(nft.name).lineLimit(1)
                            Text("\(Address(nft.contract).shortened()) #\(nft.tokenId)").font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        if nft.balance > 1 {
                            let held = NSDecimalNumber(decimal: nft.balance).intValue
                            Spacer()
                            Stepper("\(counts[nft.id] ?? 1) of \(held)", value: Binding(get: { counts[nft.id] ?? 1 }, set: { counts[nft.id] = min(max(1, $0), held) }), in: 1...max(1, held))
                                .fixedSize()
                                .disabled(step != .compose)
                        }
                    }
                }
            }
            switch step {
            case .compose: compose
            case .working:
                Section { HStack { ProgressView(); Text(isBurn ? "Burning…" : "Transferring…").foregroundStyle(.secondary) } }
            case .done(let hash, let level):
                Section {
                    Label(isBurn ? "Burnt \(editions == 1 ? "1 token" : "\(editions) tokens")" : "Transferred \(editions == 1 ? "1 token" : "\(editions) tokens")", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    Text("Included in block \(level.formatted()).").foregroundStyle(.secondary)
                    Text(hash).font(.caption.monospaced()).textSelection(.enabled)
                    if let url = network.explorerURL(operation: hash) { Link("View in the explorer", destination: url) }
                }
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .navigationTitle((isBurn ? "Burn" : "Transfer") + (operation.layer == 2 ? " on Etherlink" : ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            switch step {
            case .compose:
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(isBurn ? "Burn" : "Send") { Task { await send() } }.disabled(!canConfirm) }
            case .working:
                ToolbarItem(placement: .confirmationAction) { ProgressView() }
            case .done:
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss(); Task { await model.refreshAfterOperation() } } }
            }
        }
        .interactiveDismissDisabled(step == .working)
        .task(id: EstimateKey(request: request, context: model.bridgeContext, step: step)) { await refreshEstimate() }
    }

    @ViewBuilder private var compose: some View {
        if isBurn {
            Section {
                Label("Burning is permanent.", systemImage: "flame.fill").foregroundStyle(.orange)
                Text("The tokens go to \(TokenTransferRequest.burnAddress.shortened()), an address nobody holds the key to, and can never be recovered or sold.")
                    .font(.callout).foregroundStyle(.secondary)
                Toggle("I understand that \(editions == 1 ? "this token" : "these \(editions) tokens") will be gone for good", isOn: $understoodBurn)
            }
        } else {
            Section("To") {
                TextField("To", text: $recipient.recipientText, prompt: Text(recipient.implicitAccountsOnly ? "tz1, tz2 or tz3 address, or name.tez" : "Address or name.tez"), axis: .vertical)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if let resolved = recipient.recipient {
                    HStack(spacing: 8) { AccountAvatarView(address: resolved.address, size: 24); Text(resolved.displayName); VerificationTag(recipient: resolved) }
                } else if recipient.isResolving {
                    HStack { ProgressView(); Text("Looking up name…").foregroundStyle(.secondary) }
                } else if let error = recipient.errorMessage {
                    Text(error).foregroundStyle(.red)
                } else {
                    ForEach(recipient.suggestions.prefix(6)) { candidate in
                        Button { recipient.choose(candidate) } label: {
                            HStack { AccountAvatarView(address: candidate.address, size: 24); Text(candidate.alias); Spacer(); Text(candidate.address.shortened()).font(.caption.monospaced()).foregroundStyle(.secondary) }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
        }
        Section {
            if let estimate = estimate?.estimate {
                LabeledContent("Fee", value: AssetBalance.format(estimate.fee, symbol: "tz"))
                if estimate.burn > 0 { LabeledContent("Storage", value: AssetBalance.format(estimate.burn, symbol: "tz")) }
                LabeledContent("Total", value: AssetBalance.format(estimate.total, symbol: "tz")).fontWeight(.semibold)
            } else if request != nil {
                if let estimateError { Text(estimateError).foregroundStyle(.orange) } else { LabeledContent("Fee") { ProgressView() } }
            }
            if needsPassphrase, let wallet { SecureField("Password for “\(wallet.alias)”", text: $passphrase) }
        } footer: {
            if !model.canTransferTokens(on: operation.layer) {
                Text(operation.layer == 2 ? "Transfers on Etherlink need Layer 2 on and a tz1, tz2 or tz3 account Signet Go can sign for." : "Signet Go cannot sign for this account.")
            }
        }
    }

    private func refreshEstimate() async {
        estimate = nil
        estimateError = nil
        guard step == .compose, let request, model.canTransferTokens(on: operation.layer) else { return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        do {
            let result = try await model.estimateTokenTransfer(request, on: operation.layer)
            if !Task.isCancelled { estimate = result }
        } catch {
            if !Task.isCancelled { estimateError = error.localizedDescription }
        }
    }

    private func send() async {
        guard let request, let approved = estimate else { return }
        errorMessage = nil
        submitted = approved
        step = .working
        do {
            let (hash, level) = try await model.transferTokens(request, on: operation.layer, approved: approved, passphrase: needsPassphrase ? passphrase : nil)
            passphrase = ""
            step = .done(hash: hash, level: level)
        } catch {
            errorMessage = error.localizedDescription
            submitted = nil
            step = .compose
        }
    }
}

/// Saves NFTs' full artwork into Documents/NFTs, which the Files app shows under
/// On My iPhone › Signet Go (upstream saves into the wallet directory, which is hidden and
/// backed up here).
struct DownloadNFTsView: View {
    let download: NFTDownload
    @Environment(\.dismiss) private var dismiss
    @State private var outcomes: [NFT.ID: Outcome] = [:]

    enum Outcome: Equatable { case saved(URL), failed(String) }

    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("NFTs", isDirectory: true)
    }

    private var downloader: NFTDownloader { NFTDownloader(directory: Self.directory) }
    private var finished: Bool { outcomes.count == download.nfts.count }
    private var saved: [URL] { download.nfts.compactMap { if case .saved(let url) = outcomes[$0.id] { url } else { nil } } }

    var body: some View {
        List {
            Section {
                ForEach(download.nfts) { nft in
                    HStack(spacing: 10) {
                        Group {
                            switch outcomes[nft.id] {
                            case .saved: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                            case nil: ProgressView()
                            }
                        }
                        .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(nft.name).lineLimit(1)
                            switch outcomes[nft.id] {
                            case .saved(let url): Text(url.lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            case .failed(let reason): Text(reason).font(.caption).foregroundStyle(.red)
                            case nil: Text(nft.isMoving ? "Downloading the video or sound…" : "Downloading…").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if case .saved(let url) = outcomes[nft.id] {
                            ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }.buttonStyle(.borderless)
                        }
                    }
                }
            } footer: {
                Text("Saved in the Files app under On My iPhone › Signet Go › NFTs.")
            }
            if finished {
                Section {
                    let failed = download.nfts.count - saved.count
                    if failed == 0 {
                        Label(saved.count == 1 ? "Saved" : "Saved \(saved.count) files", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    } else {
                        Label("Saved \(saved.count) of \(download.nfts.count)", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                }
            }
        }
        .navigationTitle(download.nfts.count == 1 ? "Download NFT" : "Download \(download.nfts.count) NFTs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(finished ? "Done" : "Cancel") { dismiss() } } }
        .task { await run() }
    }

    /// Three at a time: the public client has six slots and the tiles may be loading too.
    private func run() async {
        let downloader = self.downloader
        await withTaskGroup(of: (NFT.ID, Outcome).self) { group in
            var pending = download.nfts[...]
            var running = 0
            func start(_ nft: NFT) {
                group.addTask {
                    do { return (nft.id, .saved(try await downloader.download(nft))) }
                    catch is CancellationError { return (nft.id, .failed("Cancelled")) }
                    catch { return (nft.id, .failed(error.localizedDescription)) }
                }
            }
            while running < 3, let next = pending.popFirst() { start(next); running += 1 }
            for await (id, outcome) in group {
                if !Task.isCancelled { outcomes[id] = outcome }
                if let next = pending.popFirst() { start(next) }
            }
        }
    }
}

/// What the indexer could not give, above the token and NFT lists (upstream's).
struct PortfolioStateNote: View {
    let state: Portfolio.State

    var body: some View {
        switch state {
        case .complete:
            EmptyView()
        case .partial(let fetched):
            Label("Showing the \(fetched) most recently changed tokens; older holdings may be missing.", systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
        case .unavailable(let reason):
            Label("The indexer could not be read (\(reason)). Showing the last known list.", systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange).lineLimit(2)
        }
    }
}
