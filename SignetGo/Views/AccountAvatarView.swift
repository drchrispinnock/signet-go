import SwiftUI

/// Round avatar for an address from TzKT's avatar service (TzProfiles logo, known-account logo,
/// or an identicon), always mainnet's since a TzProfile is a mainnet identity. Until it loads,
/// or if it cannot, a coloured disc with the address's prefix.
struct AccountAvatarView: View {
    let address: Address
    var size: CGFloat = 44

    init(address: Address, network: Network? = nil, size: CGFloat = 44) {
        self.address = address
        self.size = size
    }

    var body: some View {
        Group {
            if let url = Profiles.avatarURL(for: address) {
                RemoteImage(urls: [url], maxPixelSize: 192) { image in
                    Image(uiImage: image).resizable().scaledToFill()
                } placeholder: { _ in
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.secondary.opacity(0.25)))
        .accessibilityHidden(true)
    }

    private var hue: Double {
        let sum = address.value.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xffff }
        return Double(sum % 360) / 360
    }

    private var placeholder: some View {
        ZStack {
            Circle().fill(Color(hue: hue, saturation: 0.45, brightness: 0.85))
            Text(address.isContract ? "KT" : String(address.value.prefix(3)))
                .font(.system(size: size * 0.3, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}
