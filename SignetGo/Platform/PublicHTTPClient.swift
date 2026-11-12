import Foundation
import Network
import Security

/// iOS version of upstream's `PublicHTTPClient`, for untrusted URLs (artwork, token metadata,
/// dApp networking). Upstream runs `/usr/bin/curl` with a pinned DNS answer; iOS has no
/// `Process`, so this does the same with Network.framework, keeping its guarantees:
///
/// - the host is resolved once by `EndpointPolicy.publicAddresses`, which drops loopback, LAN and
///   other private answers, and the connection goes to that checked address, never to a second
///   lookup (no DNS rebinding);
/// - TLS 1.2+ with the original hostname for SNI, and the certificate is evaluated explicitly
///   against that hostname;
/// - no proxies, no cookies, no caches, no automatic redirects (each hop is validated again);
/// - HTTP/1.1, `Connection: close`, at most `limit` body bytes (plus 64 KB of headers), 15 s to
///   connect and 60 s overall, and the same gate of six requests in flight.
enum PublicHTTPClient {
    private static let gate = BridgeCallGate(limit: 6)
    static let connectTimeout: Duration = .seconds(15)
    static let totalTimeout: Duration = .seconds(60)
    static let headerSlack = 64 * 1024

    struct Reply: Sendable {
        let data: Data
        let status: Int
        let headers: [String: String]
    }

    static func data(for request: URLRequest, limit: Int, followRedirects: Bool = false) async throws -> Reply {
        try await gate.acquire()
        defer { Task { await gate.release() } }
        var current = request
        for hop in 0...5 {
            try Task.checkCancellation()
            let reply = try await perform(current, limit: limit)
            if (300..<400).contains(reply.status) {
                guard followRedirects, hop < 5, let location = reply.headers["location"],
                      let base = current.url, let target = URL(string: location, relativeTo: base)?.absoluteURL,
                      EndpointPolicy.isPublicHTTPS(target) else { throw URLError(.redirectToNonExistentLocation) }
                // Artwork requests carry no credentials, cookies or bodies.
                current = URLRequest(url: target)
                continue
            }
            return reply
        }
        throw URLError(.httpTooManyRedirects)
    }

    // MARK: Request

    /// The HTTP/1.1 request bytes for `request`, or an error for anything upstream's curl
    /// configuration would refuse (non-public URL, odd method, header injection, large body).
    static func requestBytes(for request: URLRequest, limit: Int) throws -> (host: String, port: UInt16, bytes: Data) {
        guard let url = request.url, EndpointPolicy.isPublicHTTPS(url), let host = url.host(percentEncoded: false), limit > 0 else {
            throw URLError(.unsupportedURL)
        }
        let port = url.port ?? 443
        guard (1...65535).contains(port) else { throw URLError(.badURL) }
        let method = request.httpMethod ?? "GET"
        guard method.count <= 16, method.allSatisfy({ $0.isASCII && $0.isUppercase }) else { throw URLError(.badURL) }
        var target = url.path(percentEncoded: true)
        if target.isEmpty { target = "/" }
        if let query = url.query(percentEncoded: true) { target += "?" + query }
        guard !target.contains(where: { $0 == "\r" || $0 == "\n" || $0 == " " }) else { throw URLError(.badURL) }
        let hostHeader = (host.contains(":") ? "[\(host)]" : host) + (port == 443 ? "" : ":\(port)")
        var lines = ["\(method) \(target) HTTP/1.1", "Host: \(hostHeader)", "Connection: close", "Accept-Encoding: identity"]
        var hasUserAgent = false
        for (key, value) in request.allHTTPHeaderFields ?? [:] {
            guard !key.isEmpty, !key.contains(where: { $0 == "\r" || $0 == "\n" || $0 == ":" }), !value.contains(where: { $0 == "\r" || $0 == "\n" }) else {
                throw URLError(.badURL)
            }
            let lower = key.lowercased()
            if ["host", "connection", "content-length", "transfer-encoding", "accept-encoding"].contains(lower) { continue }
            if lower == "user-agent" { hasUserAgent = true }
            lines.append("\(key): \(value)")
        }
        if !hasUserAgent { lines.append("User-Agent: Signet") }
        var body = Data()
        if let httpBody = request.httpBody {
            guard httpBody.count <= 1 << 20 else { throw URLError(.dataLengthExceedsMaximum) }
            body = httpBody
            lines.append("Content-Length: \(httpBody.count)")
        } else if method != "GET" && method != "HEAD" {
            lines.append("Content-Length: 0")
        }
        var bytes = Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
        bytes.append(body)
        return (host, UInt16(port), bytes)
    }

    // MARK: Connection

    private static func perform(_ request: URLRequest, limit: Int) async throws -> Reply {
        let (host, port, bytes) = try requestBytes(for: request, limit: limit)
        let addresses = await Task.detached { EndpointPolicy.publicAddresses(host) }.value
        guard !addresses.isEmpty else { throw URLError(.cannotFindHost) }
        var lastError: Error = URLError(.cannotConnectToHost)
        // A few of the checked addresses, in the resolver's order, as curl's --resolve does.
        for address in addresses.prefix(4) {
            try Task.checkCancellation()
            do {
                let raw = try await exchange(address: address, port: port, serverName: host, request: bytes, limit: limit + headerSlack)
                return try decode(raw, limit: limit)
            } catch let error as Exchange.ConnectFailure {
                lastError = error.underlying   // try the next address
            }
        }
        throw lastError
    }

    /// One connection to `address`: TLS with `serverName`, send `request`, read to EOF.
    private static func exchange(address: String, port: UInt16, serverName: String, request: Data, limit: Int) async throws -> Data {
        let exchange = Exchange(address: address, port: port, serverName: serverName, request: request, limit: limit)
        return try await withTaskCancellationHandler {
            try await exchange.run()
        } onCancel: {
            exchange.cancel()
        }
    }

    private final class Exchange: @unchecked Sendable {
        /// Failure before the TLS session was up: the caller may try another address.
        struct ConnectFailure: Error { let underlying: Error }

        private let queue = DispatchQueue(label: "PublicHTTPClient.exchange")
        private let connection: NWConnection
        private let request: Data
        private let limit: Int
        private var buffer = Data()
        private var continuation: CheckedContinuation<Data, Error>?
        private var ready = false
        private var finished = false

        init(address: String, port: UInt16, serverName: String, request: Data, limit: Int) {
            self.request = request
            self.limit = limit
            let tls = NWProtocolTLS.Options()
            let sec = tls.securityProtocolOptions
            sec_protocol_options_set_tls_server_name(sec, serverName)
            sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv12)
            sec_protocol_options_add_tls_application_protocol(sec, "http/1.1")
            // Evaluate the chain against the original hostname, not the address we dialled.
            sec_protocol_options_set_verify_block(sec, { _, trust, complete in
                let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
                SecTrustSetPolicies(secTrust, SecPolicyCreateSSL(true, serverName as CFString))
                complete(SecTrustEvaluateWithError(secTrust, nil))
            }, DispatchQueue.global(qos: .userInitiated))
            let tcp = NWProtocolTCP.Options()
            tcp.connectionTimeout = Int(PublicHTTPClient.connectTimeout.components.seconds)
            let parameters = NWParameters(tls: tls, tcp: tcp)
            parameters.preferNoProxies = true
            let host = NWEndpoint.Host(address)
            connection = NWConnection(host: host, port: NWEndpoint.Port(rawValue: port)!, using: parameters)
        }

        func run() async throws -> Data {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                queue.async { [self] in
                    self.continuation = continuation
                    connection.stateUpdateHandler = { [weak self] state in self?.handle(state) }
                    connection.start(queue: queue)
                    queue.asyncAfter(deadline: .now() + .seconds(Int(PublicHTTPClient.totalTimeout.components.seconds))) { [weak self] in
                        self?.finish(.failure(URLError(.timedOut)))
                    }
                }
            }
        }

        func cancel() {
            queue.async { [self] in finish(.failure(CancellationError())) }
        }

        private func handle(_ state: NWConnection.State) {
            switch state {
            case .ready:
                ready = true
                connection.send(content: request, completion: .contentProcessed { [weak self] error in
                    guard let self else { return }
                    if let error { finish(.failure(error)) } else { receive() }
                })
            case .waiting(let error), .failed(let error):
                finish(.failure(ready ? error : ConnectFailure(underlying: error)))
            case .cancelled:
                finish(.failure(CancellationError()))
            default:
                break
            }
        }

        private func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] content, _, isComplete, error in
                guard let self, !finished else { return }
                if let content {
                    guard buffer.count + content.count <= limit else { return finish(.failure(URLError(.dataLengthExceedsMaximum))) }
                    buffer.append(content)
                }
                if let error {
                    finish(.failure(error))
                } else if isComplete {
                    finish(.success(buffer))
                } else {
                    receive()
                }
            }
        }

        private func finish(_ result: Result<Data, Error>) {
            guard !finished else { return }
            finished = true
            connection.stateUpdateHandler = nil
            connection.cancel()
            continuation?.resume(with: result)
            continuation = nil
            buffer = Data()
        }
    }

    // MARK: Response

    /// Parses a raw HTTP/1.1 response: skips 1xx interim responses, refuses headers over 64 KB
    /// or a body over `limit`, and undoes chunked transfer encoding. Same contract as upstream's
    /// `decode`, which parsed curl's `--include` output.
    static func decode(_ bytes: Data, limit: Int) throws -> Reply {
        var remaining = bytes
        for _ in 0..<8 {
            guard let boundary = remaining.range(of: Data("\r\n\r\n".utf8)), boundary.lowerBound - remaining.startIndex <= 64 * 1024,
                  let header = String(data: remaining[..<boundary.lowerBound], encoding: .utf8) else { throw URLError(.cannotParseResponse) }
            let lines = header.components(separatedBy: "\r\n")
            guard let statusLine = lines.first, statusLine.hasPrefix("HTTP/1."),
                  let statusText = statusLine.split(separator: " ").dropFirst().first, let status = Int(statusText) else { throw URLError(.cannotParseResponse) }
            remaining = Data(remaining[boundary.upperBound...])
            if (100..<200).contains(status) { continue }
            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                guard let colon = line.firstIndex(of: ":") else { continue }
                headers[String(line[..<colon]).lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            var body = remaining
            if headers["transfer-encoding"]?.lowercased().contains("chunked") == true {
                body = try dechunk(remaining, limit: limit)
            } else if let length = headers["content-length"].flatMap({ Int($0) }) {
                guard length >= 0, length <= limit else { throw URLError(.dataLengthExceedsMaximum) }
                guard body.count >= length else { throw URLError(.networkConnectionLost) }
                body = Data(body.prefix(length))
            }
            guard body.count <= limit else { throw URLError(.dataLengthExceedsMaximum) }
            return Reply(data: body, status: status, headers: headers)
        }
        throw URLError(.cannotParseResponse)
    }

    /// Undoes `Transfer-Encoding: chunked`, stopping at the zero-length chunk.
    static func dechunk(_ data: Data, limit: Int) throws -> Data {
        var out = Data()
        var index = data.startIndex
        let crlf = Data("\r\n".utf8)
        while true {
            guard let lineEnd = data.range(of: crlf, in: index..<data.endIndex), lineEnd.lowerBound - index <= 1024,
                  let sizeLine = String(data: data[index..<lineEnd.lowerBound], encoding: .ascii),
                  let size = Int(sizeLine.split(separator: ";").first?.trimmingCharacters(in: .whitespaces) ?? "", radix: 16), size >= 0 else {
                throw URLError(.cannotParseResponse)
            }
            index = lineEnd.upperBound
            if size == 0 { return out }
            guard out.count + size <= limit else { throw URLError(.dataLengthExceedsMaximum) }
            guard data.endIndex - index >= size + 2 else { throw URLError(.networkConnectionLost) }
            out.append(data[index..<index + size])
            index += size
            guard data[index..<index + 2] == crlf else { throw URLError(.cannotParseResponse) }
            index += 2
        }
    }
}
