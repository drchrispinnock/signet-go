import SwiftUI

/// Loads an image through `ImageLoader`, trying each URL in turn (upstream's `RemoteImage`).
struct RemoteImage<Content: View, Placeholder: View>: View {
    let urls: [URL]
    var maxPixelSize = 400
    @ViewBuilder let content: (UIImage) -> Content
    @ViewBuilder let placeholder: (_ failed: Bool) -> Placeholder

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image { content(image) } else { placeholder(failed) }
        }
        .task(id: urls) {
            failed = false
            image = await ImageLoader.shared.image(for: urls, maxPixelSize: maxPixelSize)
            if image == nil { failed = true }
        }
    }
}
