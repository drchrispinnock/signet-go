import SwiftUI

/// One operation, after upstream's `TransactionRowView`: counterparty, direction, amount, fee.
/// Tapping opens the operation in the network's explorer.
struct TransactionRowView: View {
    @Bindable var model: WalletViewModel
    let transaction: TezosTransaction
    @Environment(\.openURL) private var openURL

    private var network: Network? { transaction.isLayer2 ? model.network.layer2 : model.network }

    private var party: (name: String, isOurs: Bool) {
        guard let address = transaction.counterparty else { return ("Unknown", false) }
        return model.displayName(for: address, indexerAlias: transaction.counterpartyAlias)
    }

    private var role: TezosTransaction.DelegationRole? {
        model.selectedWallet.flatMap { transaction.delegationRole(for: $0.address) }
    }

    var body: some View {
        Button {
            if let url = network?.explorerURL(operation: transaction.hash) { openURL(url) }
        } label: {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    if let address = transaction.counterparty {
                        AccountAvatarView(address: address, size: 36)
                    } else {
                        Circle().fill(.quaternary).frame(width: 36, height: 36)
                    }
                    directionBadge.offset(x: 4, y: 4)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(headline).font(.subheadline.weight(.medium)).lineLimit(1)
                        if party.isOurs {
                            Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(.green)
                        }
                        if !transaction.isApplied {
                            Text("Failed").font(.caption2.weight(.semibold)).foregroundStyle(.red)
                        }
                    }
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    figure
                    if transaction.direction != .incoming, transaction.fee > 0 {
                        Text("fee \(AssetBalance.format(transaction.fee, symbol: "tz"))")
                            .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .foregroundStyle(.primary)
    }

    @ViewBuilder private var figure: some View {
        if transaction.amount > 0 {
            Text(signedAmount)
                .font(.subheadline.monospacedDigit().weight(.medium))
                .foregroundStyle(transaction.direction == .incoming ? .green : .primary)
        } else if transaction.kind == .delegation, let balance = transaction.delegatedBalance, balance > 0 {
            Text(AssetBalance.format(balance, symbol: "tz")).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
        } else {
            Text(transaction.kind == .delegation ? "Delegation" : "Call").font(.callout).foregroundStyle(.secondary)
        }
    }

    private var directionBadge: some View {
        let (symbol, color): (String, Color) = switch (role, transaction.direction) {
        case (.delegatorJoined, _): ("person.fill.badge.plus", .green)
        case (.delegatorLeft, _), (.delegatorMoved, _): ("person.fill.badge.minus", .orange)
        case (.weDelegated, _), (.weUndelegated, _): ("person.fill", .blue)
        case (_, .incoming): ("arrow.down", .green)
        case (_, .outgoing): ("arrow.up", .blue)
        case (_, .selfTransfer): ("arrow.triangle.2.circlepath", .gray)
        }
        return Image(systemName: symbol)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 15, height: 15)
            .background(Circle().fill(color))
    }

    private var headline: String {
        if let role {
            switch role {
            case .weDelegated: return "Delegated to \(party.name)"
            case .weUndelegated: return "Undelegated"
            case .delegatorJoined: return "\(party.name) delegated to you"
            case .delegatorLeft: return "\(party.name) undelegated"
            case .delegatorMoved: return "\(party.name) moved their delegation"
            }
        }
        return switch (transaction.kind, transaction.direction) {
        case (.origination, _): "Originated \(party.name)"
        case (_, .incoming): "From \(party.name)"
        case (_, .selfTransfer): "To yourself"
        case (_, .outgoing): "To \(party.name)"
        }
    }

    private var subtitle: String {
        var parts = [Self.relative.localizedString(for: transaction.timestamp, relativeTo: Date())]
        if let entrypoint = transaction.entrypoint { parts.append(entrypoint) }
        else if transaction.isContractCall { parts.append("contract") }
        if let via = transaction.via { parts.append("via \(model.displayName(for: via, indexerAlias: nil).name)") }
        return parts.joined(separator: " · ")
    }

    private var signedAmount: String {
        let sign = transaction.direction == .incoming ? "+" : (transaction.direction == .outgoing ? "−" : "")
        return sign + AssetBalance.format(transaction.amount, symbol: "tz")
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}
