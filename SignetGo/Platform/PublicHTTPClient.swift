import Foundation

/// Upstream's `PublicHTTPClient` (untrusted artwork, token metadata and dApp networking) runs
/// `/usr/bin/curl` with a pinned, validated DNS answer; iOS has no `Process`. Until the
/// Network.framework replacement exists (connect to the validated public address, TLS with the
/// original hostname for SNI and certificate validation, same limits, no automatic redirects),
/// every request is refused rather than made without those guarantees.
enum PublicHTTPClient {
    struct Reply: Sendable {
        let data: Data
        let status: Int
        let headers: [String: String]
    }

    struct Unavailable: LocalizedError {
        var errorDescription: String? { "Fetching from this address is not available on iOS yet." }
    }

    static func data(for request: URLRequest, limit: Int, followRedirects: Bool = false) async throws -> Reply {
        throw Unavailable()
    }
}
