import Foundation
import Network

/// Serves the avatar page from a folder on 127.0.0.1 (random free port).
/// WKWebView can't load ES modules / import maps from file://, so we serve over loopback HTTP.
final class StaticServer {
    private let root: URL
    private let queue = DispatchQueue(label: "claude-avatar.http")
    private var listener: NWListener?
    // Only these top-level entries are exposed.
    private let allowed: Set<String> = ["index.html", "pcm-player.js", "avatars", "node_modules", "renderers", "vendor"]

    private static let types = [
        "html": "text/html; charset=utf-8", "js": "text/javascript; charset=utf-8",
        "mjs": "text/javascript; charset=utf-8", "json": "application/json",
        "glb": "model/gltf-binary", "wasm": "application/wasm", "css": "text/css; charset=utf-8",
    ]

    private let userAvatars: URL

    /// `userAvatars` is served read-only at /user-avatars/ (GLB files only).
    init(root: URL, userAvatars: URL) {
        self.root = root.standardizedFileURL
        self.userAvatars = userAvatars.standardizedFileURL
    }

    /// Starts listening and calls `ready` (on main) with the chosen port, or nil on failure.
    func start(ready: @escaping (UInt16?) -> Void) {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        guard let l = try? NWListener(using: params) else { DispatchQueue.main.async { ready(nil) }; return }
        l.stateUpdateHandler = { state in
            switch state {
            case .ready: let p = l.port?.rawValue; DispatchQueue.main.async { ready(p) }
            case .failed: DispatchQueue.main.async { ready(nil) }
            default: break
            }
        }
        l.newConnectionHandler = { [weak self] c in self?.handle(c) }
        l.start(queue: queue)
        listener = l
    }

    func stop() { listener?.cancel() }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else { conn.cancel(); return }
            self.respond(to: request, on: conn)
        }
    }

    private func respond(to request: String, on conn: NWConnection) {
        let parts = request.prefix(while: { $0 != "\r" && $0 != "\n" }).split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" || parts[0] == "HEAD",
              var path = URL(string: String(parts[1]))?.path.removingPercentEncoding else {
            return send(status: "400 Bad Request", body: Data(), type: "text/plain", on: conn)
        }
        if path == "/" { path = "/index.html" }
        if path.hasPrefix("/user-avatars/") {
            let f = userAvatars.appendingPathComponent(String(path.dropFirst("/user-avatars/".count))).standardizedFileURL
            guard f.path.hasPrefix(userAvatars.path + "/"), f.pathExtension == "glb",
                  let body = try? Data(contentsOf: f) else {
                return send(status: "404 Not Found", body: Data("not found".utf8), type: "text/plain", on: conn)
            }
            return send(status: "200 OK", body: parts[0] == "HEAD" ? Data() : body, type: "model/gltf-binary",
                        length: body.count, on: conn)
        }
        let file = root.appendingPathComponent(path).standardizedFileURL
        let rel = file.path.hasPrefix(root.path + "/") ? String(file.path.dropFirst(root.path.count + 1)) : ""
        guard let top = rel.split(separator: "/").first, allowed.contains(String(top)),
              let body = try? Data(contentsOf: file) else {
            return send(status: "404 Not Found", body: Data("not found".utf8), type: "text/plain", on: conn)
        }
        send(status: "200 OK", body: parts[0] == "HEAD" ? Data() : body,
             type: Self.types[file.pathExtension] ?? "application/octet-stream", length: body.count, on: conn)
    }

    private func send(status: String, body: Data, type: String, length: Int? = nil, on conn: NWConnection) {
        let head = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(length ?? body.count)\r\n"
            + "Cache-Control: no-cache\r\nConnection: close\r\n\r\n"
        conn.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in conn.cancel() })
    }
}
