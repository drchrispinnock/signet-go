import Foundation
import Testing
@testable import Signet

/// The iOS PublicHTTPClient: what it sends, what it accepts, and live fetches.
@Suite struct PublicHTTPClientTests {
    @Test func refusesWhatUpstreamRefuses() {
        for url in ["http://example.com/", "https://127.0.0.1/", "https://localhost/", "https://192.168.1.2/x", "https://user:pw@example.com/", "https://printer.local/"] {
            #expect(throws: (any Error).self, "\(url)") { try PublicHTTPClient.requestBytes(for: URLRequest(url: URL(string: url)!), limit: 10) }
        }
        var injected = URLRequest(url: URL(string: "https://example.com/")!)
        injected.setValue("x\r\nEvil: 1", forHTTPHeaderField: "X-Test")
        // Foundation may already drop such a value; either way no injected header reaches the wire.
        if let sent = try? PublicHTTPClient.requestBytes(for: injected, limit: 10) {
            #expect(!String(decoding: sent.bytes, as: UTF8.self).contains("Evil:"))
        }
        var method = URLRequest(url: URL(string: "https://example.com/")!)
        method.httpMethod = "get /x"
        #expect(throws: (any Error).self) { try PublicHTTPClient.requestBytes(for: method, limit: 10) }
    }

    @Test func buildsAPlainHTTP11Request() throws {
        var request = URLRequest(url: URL(string: "https://api.example.com:8443/v1/x?a=1&b=%20")!)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("evil.example", forHTTPHeaderField: "Host")
        let (host, port, bytes) = try PublicHTTPClient.requestBytes(for: request, limit: 100)
        let text = String(decoding: bytes, as: UTF8.self)
        #expect(host == "api.example.com" && port == 8443)
        #expect(text.hasPrefix("POST /v1/x?a=1&b=%20 HTTP/1.1\r\nHost: api.example.com:8443\r\nConnection: close\r\n"))
        #expect(text.contains("Content-Type: application/json\r\n") && text.contains("Content-Length: 2\r\n"))
        #expect(!text.contains("evil.example"))
        #expect(text.hasSuffix("\r\n\r\n{}"))
    }

    @Test func decodesResponsesLikeUpstream() throws {
        let reply = try PublicHTTPClient.decode(Data("HTTP/1.1 200 OK\r\nContent-Type: image/png\r\n\r\nabc".utf8), limit: 3)
        #expect(reply.status == 200 && reply.headers["content-type"] == "image/png" && reply.data == Data("abc".utf8))
        #expect(throws: (any Error).self) { try PublicHTTPClient.decode(Data("HTTP/1.1 200 OK\r\n\r\nabcdef".utf8), limit: 3) }
        let interim = try PublicHTTPClient.decode(Data("HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 404 Not Found\r\n\r\n".utf8), limit: 3)
        #expect(interim.status == 404)
        let lengthy = try PublicHTTPClient.decode(Data("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nabcd".utf8), limit: 10)
        #expect(lengthy.data == Data("ab".utf8))
        #expect(throws: (any Error).self) { try PublicHTTPClient.decode(Data("garbage".utf8), limit: 3) }
    }

    @Test func undoesChunkedEncodingWithinTheLimit() throws {
        let raw = Data("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nWiki\r\n5;ext=1\r\npedia\r\n0\r\n\r\n".utf8)
        #expect(try PublicHTTPClient.decode(raw, limit: 100).data == Data("Wikipedia".utf8))
        #expect(throws: (any Error).self) { try PublicHTTPClient.decode(raw, limit: 5) }
        #expect(throws: (any Error).self) { try PublicHTTPClient.dechunk(Data("zz\r\n".utf8), limit: 10) }
    }

    /// Live: a real HTTPS fetch over the pinned connection, a redirect followed, a size limit hit.
    @Test(.tags(.network), .liveNetwork, .timeLimit(.minutes(1)))
    func fetchesOverTheNetwork() async throws {
        let avatar = try await PublicHTTPClient.data(for: URLRequest(url: URL(string: "https://services.tzkt.io/v1/avatars/tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb")!), limit: 2_000_000, followRedirects: true)
        #expect(avatar.status == 200 && !avatar.data.isEmpty)
        let json = try await PublicHTTPClient.data(for: URLRequest(url: URL(string: "https://api.tzkt.io/v1/head")!), limit: 100_000)
        #expect(json.status == 200 && String(decoding: json.data, as: UTF8.self).contains("\"level\""))
        await #expect(throws: (any Error).self) {
            try await PublicHTTPClient.data(for: URLRequest(url: URL(string: "https://api.tzkt.io/v1/head")!), limit: 10)
        }
    }

    /// Live: a certificate for another name is refused even though the address is right.
    @Test(.tags(.network), .liveNetwork, .timeLimit(.minutes(1)))
    func refusesAWrongCertificate() async throws {
        await #expect(throws: (any Error).self) {
            try await PublicHTTPClient.data(for: URLRequest(url: URL(string: "https://wrong.host.badssl.com/")!), limit: 100_000)
        }
    }
}
