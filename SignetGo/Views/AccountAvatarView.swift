import SwiftUI

/// Round avatar for an address. Upstream fetches TzKT's avatar service through
/// `PublicHTTPClient`, which iOS does not have yet, so for now a coloured disc with the
/// address's identity is drawn locally.
struct AccountAvatarView: View {
    let address: Address
    var size: CGFloat = 44

    init(address: Address, network: Network? = nil, size: CGFloat = 44) {
        self.address = address
        self.size = size
    }

    private var hue: Double {
        let sum = address.value.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xffff }
        return Double(sum % 360) / 360
    }

    var body: some View {
        ZStack {
            Circle().fill(Color(hue: hue, saturation: 0.45, brightness: 0.85))
            Text(address.isContract ? "KT" : String(address.value.prefix(3)))
                .font(.system(size: size * 0.3, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
