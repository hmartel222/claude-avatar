import Foundation
import Network

/// Minimal broadcast-only WebSocket server bound to loopback.
final class WebSocketServer {
    private final class Client {
        let connection: NWConnection
        var inflight = 0
        init(_ c: NWConnection) { connection = c }
    }

    private let port: NWEndpoint.Port
    private let queue = DispatchQueue(label: "claude-tap.ws")
    private var listener: NWListener?
    private var clients: [ObjectIdentifier: Client] = [:]
    private var claudeRunning = false
    var onFailed: ((Error) -> Void)?
    private let maxInflight = 50   // ~1 s of frames; drop beyond that for slow clients

    init(port: UInt16) { self.port = NWEndpoint.Port(rawValue: port)! }

    func start() throws {
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true
        // Any web page can reach loopback; only accept local pages (or non-browser clients with no Origin).
        ws.setClientRequestHandler(queue) { _, headers in
            let origin = headers.first { $0.name.lowercased() == "origin" }?.value
            return NWProtocolWebSocket.Response(status: WebSocketServer.originAllowed(origin) ? .accept : .reject,
                                                subprotocol: nil)
        }
        let params = NWParameters.tcp
        params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
        params.allowLocalEndpointReuse = true

        let l = try NWListener(using: params)
        l.stateUpdateHandler = { [unowned self] state in
            if case .failed(let e) = state { self.onFailed?(e) }
        }
        l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        l.start(queue: queue)
        listener = l
    }

    func stop() {
        queue.sync {
            listener?.cancel()
            clients.values.forEach { $0.connection.cancel() }
            clients.removeAll()
        }
    }

    func setClaudeRunning(_ running: Bool) {
        queue.async {
            guard running != self.claudeRunning else { return }
            self.claudeRunning = running
            for c in self.clients.values { self.sendStatus(to: c) }
        }
    }

    func broadcast(frame: Data) {
        queue.async {
            let ctx = NWConnection.ContentContext(identifier: "frame",
                                                  metadata: [NWProtocolWebSocket.Metadata(opcode: .binary)])
            for c in self.clients.values where c.inflight < self.maxInflight {
                c.inflight += 1
                c.connection.send(content: frame, contentContext: ctx, isComplete: true,
                                  completion: .contentProcessed { [weak c] _ in
                    self.queue.async { c?.inflight -= 1 }
                })
            }
        }
    }

    func broadcast(text: String) {
        queue.async {
            let ctx = NWConnection.ContentContext(identifier: "text",
                                                  metadata: [NWProtocolWebSocket.Metadata(opcode: .text)])
            for c in self.clients.values {
                c.connection.send(content: Data(text.utf8), contentContext: ctx, isComplete: true,
                                  completion: .contentProcessed { _ in })
            }
        }
    }

    var clientCount: Int { queue.sync { clients.count } }

    // MARK: - private

    private static func originAllowed(_ origin: String?) -> Bool {
        guard let origin, !origin.isEmpty else { return true }
        if origin == "null" { return true }   // file:// pages / WKWebView
        guard let host = URL(string: origin)?.host else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
    }

    private func accept(_ conn: NWConnection) {
        let client = Client(conn)
        let id = ObjectIdentifier(client)
        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.clients[id] = client
                self.sendStatus(to: client)
                self.receiveLoop(client, id: id)
            case .failed, .cancelled:
                self.clients[id] = nil
            default: break
            }
        }
        conn.start(queue: queue)
    }

    private func receiveLoop(_ client: Client, id: ObjectIdentifier) {
        client.connection.receiveMessage { [weak self] _, _, _, error in
            guard let self else { return }
            if error != nil { client.connection.cancel(); self.clients[id] = nil; return }
            self.receiveLoop(client, id: id)
        }
    }

    private func sendStatus(to client: Client) {
        let json = #"{"type":"status","claudeRunning":\#(claudeRunning)}"#
        let ctx = NWConnection.ContentContext(identifier: "status",
                                              metadata: [NWProtocolWebSocket.Metadata(opcode: .text)])
        client.connection.send(content: Data(json.utf8), contentContext: ctx, isComplete: true,
                               completion: .contentProcessed { _ in })
    }
}
