import Foundation
import Testing
import UIKit
@testable import Signet

/// The iOS ImageLoader and ArtworkCache ports (upstream's ArtworkCacheTests draw with AppKit).
@Suite struct ImageTests {
    private func png(width: Int, height: Int) -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
            .pngData { context in UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: width, height: height)) }
    }

    @Test func downsamplesToTheLongEdge() throws {
        let image = try #require(ImageLoader.downsample(png(width: 1000, height: 500), maxPixelSize: 200))
        #expect(image.cgImage?.width == 200 && image.cgImage?.height == 100)
        #expect(ImageLoader.downsample(Data("not an image".utf8), maxPixelSize: 200) == nil)
        #expect(ImageLoader.svg(Data("<svg xmlns='http://www.w3.org/2000/svg'/>".utf8)) == nil)
    }

    @Test func cacheRoundTripsAThumbnail() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("artwork-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = ArtworkCache(directory: directory)
        let url = URL(string: "https://ipfs.io/ipfs/QmSowixsFjPYXBbZecwPvgEw7TrV4bm6DN7nfJQmNS1ccv")!
        let image = try #require(ImageLoader.downsample(png(width: 64, height: 32), maxPixelSize: 64))
        cache.store(image, for: url, maxPixelSize: 64)
        // The same IPFS content from another gateway is the same entry.
        let other = URL(string: "https://ipfs.filebase.io/ipfs/QmSowixsFjPYXBbZecwPvgEw7TrV4bm6DN7nfJQmNS1ccv")!
        let back = try #require(cache.image(for: other, maxPixelSize: 64))
        #expect(back.cgImage?.width == 64 && back.cgImage?.height == 32)
        #expect(cache.image(for: url, maxPixelSize: 128) == nil)
    }

    @Test func loaderTriesCandidatesInOrder() async throws {
        let good = png(width: 40, height: 20)
        let loader = ImageLoader(download: { url in url.host == "two.example.org" ? good : nil })
        let image = await loader.image(for: [URL(string: "https://one.example.org/a.png")!, URL(string: "https://two.example.org/b.png")!], maxPixelSize: 100)
        #expect(image?.cgImage?.width == 40)
    }
}
