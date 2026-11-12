import SwiftUI

/// One balance, after upstream's `AssetRowView`: rows with a breakdown expand on tap.
struct AssetRowView: View {
    let asset: AssetBalance
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                icon.frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(asset.name).font(.subheadline).foregroundStyle(.secondary)
                    if let unavailable = asset.unavailable {
                        Text(unavailable).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    } else {
                        Text(asset.formattedAmount).font(.title3.monospacedDigit())
                    }
                }
                Spacer()
                if !asset.details.isEmpty {
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !asset.details.isEmpty else { return }
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            }
            if isExpanded {
                ForEach(asset.details) { line in
                    HStack {
                        Text(line.label).foregroundStyle(.secondary)
                        Spacer()
                        Text(AssetBalance.format(line.amount, symbol: asset.symbol)).monospacedDigit()
                    }
                    .font(.callout)
                    .padding(.leading, 50)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(asset.name) balance \(asset.unavailable ?? asset.formattedAmount)")
    }

    @ViewBuilder private var icon: some View {
        switch asset.kind {
        case .tez: Image("TezosToken").resizable().scaledToFit()
        case .etherlink: Image("EtherlinkLogo").resizable().scaledToFit()
        case .shielded: EmptyView() // never enabled in Signet Go
        case .token:
            RemoteImage(urls: asset.iconURLs, maxPixelSize: 128) { image in
                Image(uiImage: image).resizable().scaledToFit().clipShape(Circle())
            } placeholder: { _ in
                ZStack {
                    Circle().strokeBorder(.secondary, lineWidth: 1.5)
                    Text(String(asset.symbol.prefix(4))).font(.caption2.weight(.semibold))
                }
            }
        }
    }
}
