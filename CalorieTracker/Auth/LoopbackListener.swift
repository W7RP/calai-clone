import Foundation
import Network

/// Tiny HTTP listener on 127.0.0.1 that catches the OAuth redirect while the in-app browser is showing.
/// State is only touched on `queue`, which is why the unchecked Sendable is safe.
final class LoopbackListener: @unchecked Sendable {
    enum ListenerError: LocalizedError {
        case couldNotStart(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .couldNotStart(let reason): "Couldn't start the local sign-in listener: \(reason)"
            case .cancelled: "Sign-in was cancelled."
            }
        }
    }

    private let queue = DispatchQueue(label: "LoopbackListener")
    private var listener: NWListener?
    private var startContinuation: CheckedContinuation<UInt16, Error>?
    private var callbackContinuation: CheckedContinuation<URL, Error>?
    private var receivedURL: URL?

    /// Binds to the preferred port, or any free one if it's taken. Returns the bound port.
    func start(preferredPort: UInt16) async throws -> UInt16 {
        do {
            return try await bind(port: preferredPort)
        } catch {
            return try await bind(port: 0)
        }
    }

    func waitForCallback() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if let url = self.receivedURL {
                    continuation.resume(returning: url)
                } else {
                    self.callbackContinuation = continuation
                }
            }
        }
    }

    func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
            self.callbackContinuation?.resume(throwing: ListenerError.cancelled)
            self.callbackContinuation = nil
        }
    }

    private func bind(port: UInt16) async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let parameters = NWParameters.tcp
                parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1",
                                                             port: NWEndpoint.Port(rawValue: port) ?? .any)
                parameters.allowLocalEndpointReuse = true
                let listener: NWListener
                do {
                    listener = try NWListener(using: parameters)
                } catch {
                    continuation.resume(throwing: ListenerError.couldNotStart(error.localizedDescription))
                    return
                }
                self.startContinuation = continuation
                listener.stateUpdateHandler = { [weak self, weak listener] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.startContinuation?.resume(returning: listener?.port?.rawValue ?? port)
                        self.startContinuation = nil
                    case .failed(let error):
                        listener?.cancel()
                        self.startContinuation?.resume(throwing: ListenerError.couldNotStart(error.localizedDescription))
                        self.startContinuation = nil
                    default:
                        break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    self?.handle(connection)
                }
                self.listener = listener
                listener.start(queue: self.queue)
            }
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self else { return }
            let target = data.flatMap(Self.requestTarget(fromRequest:))
            let isCallback = target.map { $0.hasPrefix(OpenAIAuthConfig.callbackPath) } ?? false
            Self.respond(on: connection, ok: isCallback)
            guard isCallback, let target, let url = URL(string: "http://127.0.0.1\(target)") else { return }
            self.receivedURL = url
            self.callbackContinuation?.resume(returning: url)
            self.callbackContinuation = nil
        }
    }

    /// "GET /auth/callback?code=... HTTP/1.1" -> "/auth/callback?code=..."
    static func requestTarget(fromRequest data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8),
              let firstLine = text.split(separator: "\r\n", maxSplits: 1).first else { return nil }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else { return nil }
        return String(parts[1])
    }

    private static func respond(on connection: NWConnection, ok: Bool) {
        let body = ok
            ? "<html><body style=\"font-family:-apple-system;text-align:center;padding-top:40px\"><h2>Signed in</h2><p>You can return to the app.</p></body></html>"
            : "Not found"
        let response = "HTTP/1.1 \(ok ? "200 OK" : "404 Not Found")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }
}
