import SwiftUI

/// Which network Signet Go talks to, and for each network its node, Layer 2 and links
/// (upstream's NetworksSheet, as a list with a screen per network).
struct NetworksView: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.showsTestNetworksKey) private var showsTestNetworks = true
    @State private var editing: String?

    private var networks: [Network] { Network.all.filter { showsTestNetworks || $0.isMainnet || $0.name == model.network.name } }

    var body: some View {
        List {
            Section {
                ForEach(networks, id: \.name) { network in
                    HStack {
                        Button {
                            model.switchNetwork(to: network)
                            Task { await model.refresh() }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(network.name)
                                    Text(network.isMainnet ? "Real tez" : "Test network").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if network.name == model.network.name { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                        .foregroundStyle(.primary)
                        Button { editing = network.name } label: { Image(systemName: "info.circle") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("\(network.name) settings")
                    }
                }
            } header: {
                Text("In use")
            } footer: {
                Text("Tap a network to use it; ⓘ opens its node, Layer 2 and links.")
            }
            Section {
                Toggle("Show test networks", isOn: $showsTestNetworks)
            }
            Section("Node") {
                NodeStatusRow(monitor: model.nodeMonitor, label: "Layer 1")
                if model.network.hasL2 { NodeStatusRow(monitor: model.l2Monitor, label: "Layer 2") }
            }
        }
        .navigationTitle("Networks")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $editing) { name in
            if let base = Network.named(name) { NetworkDetailView(model: model, base: base) }
        }
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}

/// One network's node (checked against its pinned chain before it is used), Layer 2 node and
/// Etherlink governance contracts, and the TzKT, explorer and faucet links.
struct NetworkDetailView: View {
    @Bindable var model: WalletViewModel
    let base: Network

    @State private var nodeText = ""
    @State private var nodeError: String?
    @State private var nodeWarning: NodeIdentity?
    @State private var nodeChecking = false
    @State private var l2NodeText = ""
    @State private var l2NodeError: String?
    @State private var l2NodeWarning: NodeIdentity?
    @State private var l2NodeChecking = false

    var body: some View {
        Form {
            Section {
                TextField("https://…", text: $nodeText)
                    .font(.callout.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onSubmit(applyNode)
                fieldNote(error: nodeError, warning: nodeWarning, checking: nodeChecking, layer: .one)
                HStack {
                    Button("Use default") { model.useDefaultNode(for: base); sync() }
                        .disabled(model.nodeURL(for: base) == base.defaultRPCURL)
                    Spacer()
                    if nodeWarning != nil {
                        Button("Use anyway") { model.setNode(nodeText, for: base); sync() }
                    } else {
                        Button("Apply", action: applyNode).disabled(Network.nodeURL(from: nodeText) == model.nodeURL(for: base) || nodeChecking)
                    }
                }
                .buttonStyle(.borderless)
            } header: {
                Text("Node")
            } footer: {
                Text(nodeHelp)
            }
            Section {
                Toggle("Enable Layer 2", isOn: Binding(get: { model.isL2Enabled(for: base) }, set: { model.setL2Enabled($0, for: base); sync() }))
                if model.isL2Enabled(for: base) {
                    TextField("Layer 2 Michelson node", text: $l2NodeText, prompt: Text("https://…"))
                        .font(.callout.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .onSubmit(applyL2Node)
                    if model.l2NodeURL(for: base) == nil, l2NodeError == nil {
                        Text("Enter the Layer 2 Michelson node to use; the balance is not shown until then.").font(.footnote).foregroundStyle(.orange)
                    }
                    fieldNote(error: l2NodeError, warning: l2NodeWarning, checking: l2NodeChecking, layer: .two)
                    HStack {
                        Button("Use default") { model.useDefaultL2Node(for: base); sync() }
                            .disabled(base.l2DefaultRPCURL == nil || model.l2NodeURL(for: base) == base.l2DefaultRPCURL)
                        Spacer()
                        if l2NodeWarning != nil {
                            Button("Use anyway") { model.setL2Node(l2NodeText, for: base); sync() }
                        } else {
                            Button("Apply", action: applyL2Node).disabled(Network.nodeURL(from: l2NodeText) == model.l2NodeURL(for: base) || l2NodeChecking)
                        }
                    }
                    .buttonStyle(.borderless)
                }
            } header: {
                Text("Layer 2 (Etherlink)")
            } footer: {
                Text("With Layer 2 on, the dashboard shows each tz1, tz2 or tz3 account's balance on Etherlink, and Send, Receive and Bridge can work there.")
            }
            if model.isL2Enabled(for: base) {
                Section {
                    ForEach(EtherlinkGovernance.Process.allCases) { process in
                        SettingRow(title: process.settingTitle,
                                   current: model.etherlinkGovernanceContract(for: process, in: base),
                                   defaultValue: base.defaultEtherlinkGovernance[process]?.value ?? "",
                                   prompt: "KT1…",
                                   apply: { model.setEtherlinkGovernanceContract($0, for: process, in: base) },
                                   problem: { _ in "Enter the governance contract's address (KT1…), or leave it empty to do without this process." },
                                   useDefault: { model.useDefaultEtherlinkGovernanceContract(for: process, in: base) })
                            .id("\(base.name)/governance/\(process.rawValue)")
                    }
                } header: {
                    Text("Etherlink governance")
                } footer: {
                    Text("Etherlink's kernel-upgrade votes on layer 1 (\(base.defaultEtherlinkGovernance.isEmpty ? "none shipped for \(base.name)" : "mainnet's are shipped")). Leave a field empty to do without that process.")
                }
            }
            Section {
                ForEach(Network.Service.allCases.filter { base.offers($0) }, id: \.self) { service in
                    SettingRow(title: service.title,
                               current: model.serviceURL(for: service, in: base)?.nodeDisplayTextStandalone ?? "",
                               defaultValue: base.defaultURL(for: service)?.nodeDisplayTextStandalone ?? "",
                               prompt: "https://…",
                               apply: { model.setServiceURL($0, for: service, in: base) },
                               problem: { Network.nodeURLProblem($0) },
                               useDefault: { model.useDefaultServiceURL(for: service, in: base) })
                        .id("\(base.name)/\(service.rawValue)")
                }
            } header: {
                Text("Links")
            } footer: {
                Text("The TzKT API feeds the history, token and NFT lists; the explorer is where operations are opened; the faucet is behind Get tez. Leave a link empty to do without it." + (base.isMainnet ? " Mainnet has no faucet." : ""))
            }
        }
        .navigationTitle(base.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: sync)
        .onChange(of: nodeText) { nodeWarning = nil }
        .onChange(of: l2NodeText) { l2NodeWarning = nil }
    }

    @ViewBuilder private func fieldNote(error: String?, warning: NodeIdentity?, checking: Bool, layer: NodeMonitor.Layer) -> some View {
        if let error {
            Text(error).font(.footnote).foregroundStyle(.red)
        } else if let warning {
            Text(warningText(warning, layer: layer)).font(.footnote).foregroundStyle(.orange)
        } else if checking {
            HStack { ProgressView(); Text("Checking which chain the node serves…").font(.footnote).foregroundStyle(.secondary) }
        }
    }

    private var nodeHelp: String {
        var text = base.chain == "custom" ? "Custom is yours to point anywhere, for example a node you run yourself." : "The default is \(base.defaultRPCURL.absoluteString)."
        if base.chain == "weeklynet" { text += " Weeklynet restarts every Wednesday and its address carries that date, so the default follows the calendar." }
        if base.expectedChainID != nil { text += " A new node is asked which chain it serves before it is used, and one on another chain is warned about." }
        text += " Plain http is accepted only for this device's local network."
        return text
    }

    private func warningText(_ identity: NodeIdentity, layer: NodeMonitor.Layer) -> String {
        let name = layer == .two ? "\(base.name)'s Etherlink" : base.name
        switch identity {
        case .mismatch(let found, let expected): return "This node serves chain \(found), not \(name) (\(expected)). Signet Go would show it in red and refuse to sign through it."
        case .unchecked(let reason): return "Signet Go could not check which chain this node serves. \(reason)."
        case .unpinned, .matches: return ""
        }
    }

    private func sync() {
        nodeText = model.nodeURL(for: base).nodeDisplayTextStandalone
        l2NodeText = model.l2NodeURL(for: base)?.nodeDisplayTextStandalone ?? ""
        nodeError = nil; l2NodeError = nil; nodeWarning = nil; l2NodeWarning = nil
    }

    private func applyNode() {
        guard Network.nodeURL(from: nodeText) != nil else { nodeError = Network.nodeURLProblem(nodeText); return }
        nodeError = nil
        nodeChecking = true
        let text = nodeText
        Task {
            let identity = await model.checkNode(text, for: base)
            nodeChecking = false
            guard text == nodeText else { return }
            switch identity {
            case .unpinned, .matches: model.setNode(text, for: base); sync()
            case .mismatch, .unchecked: nodeWarning = identity
            }
        }
    }

    private func applyL2Node() {
        guard Network.nodeURL(from: l2NodeText) != nil else { l2NodeError = Network.nodeURLProblem(l2NodeText); return }
        l2NodeError = nil
        l2NodeChecking = true
        let text = l2NodeText
        Task {
            let identity = await model.checkNode(text, for: base, layer: .two)
            l2NodeChecking = false
            guard text == l2NodeText else { return }
            switch identity {
            case .unpinned, .matches: model.setL2Node(text, for: base); sync()
            case .mismatch, .unchecked: l2NodeWarning = identity
            }
        }
    }
}

/// One text setting with its error line and Use default / Apply (upstream's SettingField).
struct SettingRow: View {
    let title: String
    let current: String
    let defaultValue: String
    let prompt: String
    let apply: (String) -> Bool
    let problem: (String) -> String
    let useDefault: () -> Void
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .font(.callout.monospaced())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit(submit)
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            HStack {
                Button(defaultValue.isEmpty ? "Clear" : "Use default") { useDefault(); error = nil }.disabled(current == defaultValue)
                Spacer()
                Button("Apply", action: submit).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines) == current)
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
        .onAppear { text = current; error = nil }
        .onChange(of: current) { text = current; error = nil }
    }

    private func submit() {
        if apply(text) { error = nil } else { error = problem(text) }
    }
}

/// A node's light, host and state; tap to check again (upstream's NodeStatusBar line).
struct NodeStatusRow: View {
    let monitor: NodeMonitor
    let label: String

    var body: some View {
        Button {
            Task { await monitor.checkNow() }
        } label: {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 9, height: 9)
                Text(label).foregroundStyle(.secondary)
                Text(monitor.endpoint?.host() ?? "—").lineLimit(1)
                Spacer()
                Text(monitor.status.summary).foregroundStyle(.secondary).lineLimit(1)
            }
            .font(.footnote)
        }
        .foregroundStyle(.primary)
        .accessibilityLabel("\(label) node \(monitor.endpoint?.host() ?? ""): \(monitor.status.detail)")
    }

    private var color: Color {
        switch monitor.status.light {
        case .grey: .gray
        case .green: .green
        case .yellow: .yellow
        case .red: .red
        }
    }
}
