import AppKit
import Foundation

/// Finds Claude's audio processes, taps them, and streams 20 ms mono Float32 frames over a loopback WebSocket.
/// Must be started on the main thread (it uses a main run-loop timer).
public final class TapEngine {
    public let prefix: String
    public let port: UInt16

    /// Human-readable events (attach, errors).
    public var onLog: ((String) -> Void)?
    /// Called for every 20 ms frame on an audio queue: peak and RMS of the frame.
    public var onFrame: ((_ peak: Float, _ rms: Float) -> Void)?
    /// Called on the main thread when `claudeRunning` / `capturing` / `activePIDs` change.
    public var onChange: (() -> Void)?
    /// Unrecoverable failure (e.g. port in use).
    public var onFatal: ((String) -> Void)?

    /// When true, frames stop going to WebSocket clients after ~200 ms of silence and resume (with 40 ms of
    /// pre-roll) when sound returns. Saves the page from processing endless silence. Off by default.
    public var suppressSilence = false

    /// Sync mode: mute Claude's own output while tapped and play the captured audio ourselves, delayed
    /// (see `player`). Changing this re-attaches the tap.
    public var muteOriginal = false {
        didSet {
            guard muteOriginal != oldValue else { return }
            player.setEnabled(muteOriginal)
            reattach()
        }
    }
    /// Cut the delayed audio and tell clients to drop their video when Claude's audio stops abruptly
    /// mid-speech (an interruption). Heuristic: 3 loud frames in a row, then digital silence.
    public var detectInterrupts = false
    public var interruptPeak: Float = 0.04
    public var onInterrupt: (() -> Void)?
    public let player = DelayedPlayer()

    public private(set) var claudeRunning = false
    public private(set) var capturing = false
    public private(set) var activePIDs: [pid_t] = []
    public var clientCount: Int { server.clientCount }

    private let server: WebSocketServer
    private let framer: Framer
    private var tap: ProcessTap?
    private var currentKey: String?
    private var retryAt = Date.distantPast
    private var lastLogged: String?
    private var timer: Timer?

    public init(prefix: String = "com.anthropic.claudefordesktop", port: UInt16 = 8765) {
        self.prefix = prefix
        self.port = port
        let server = WebSocketServer(port: port)
        self.server = server
        framer = Framer { _, _, _ in }   // replaced below, once self is available
        framer.onFrame = { [weak self] data, peak, rms in
            guard let self else { return }
            self.onFrame?(peak, rms)
            self.route(data, peak: peak, to: server)
        }
        server.onFailed = { [weak self] e in self?.onFatal?("WebSocket listener failed: \(e)") }
    }

    // Runs on the single audio queue of the active tap.
    private var silentRun = 0
    private var preroll: [Data] = []
    private static let hangoverFrames = 10   // 200 ms
    private static let silencePeak: Float = 0.002

    private var recentPeaks: [Float] = [0, 0, 0]

    private func route(_ data: Data, peak: Float, to server: WebSocketServer) {
        if muteOriginal { player.enqueue(data) }
        if detectInterrupts {
            if peak < 1e-5, recentPeaks.allSatisfy({ $0 >= interruptPeak }) {
                recentPeaks = [0, 0, 0]
                player.flush()
                server.broadcast(text: #"{"type":"interrupt"}"#)
                onInterrupt?()
            } else {
                recentPeaks.removeFirst(); recentPeaks.append(peak)
            }
        }
        guard suppressSilence else { server.broadcast(frame: data); return }
        if peak >= Self.silencePeak {
            silentRun = 0
            preroll.forEach { server.broadcast(frame: $0) }
            preroll.removeAll(keepingCapacity: true)
            server.broadcast(frame: data)
        } else {
            silentRun += 1
            if silentRun <= Self.hangoverFrames {
                server.broadcast(frame: data)
            } else {
                preroll.append(data)
                if preroll.count > 2 { preroll.removeFirst() }
            }
        }
    }

    public func start() throws {
        try server.start()
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }

    public func stop() {
        timer?.invalidate(); timer = nil
        player.setEnabled(false)
        tap?.stop(); tap = nil
        server.stop()
    }

    /// Drop the current tap and re-attach on the next tick (e.g. after sleep/wake or an output-device glitch).
    public func reattach() {
        tap?.stop(); tap = nil
        capturing = false
        currentKey = "reattach"
        retryAt = .distantPast
        tick()
    }

    private func log(_ s: String) { onLog?(s) }

    private func appRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier?.hasPrefix(prefix) == true }
    }

    private func tick() {
        let procs = CA.processes().filter { $0.bundleID.hasPrefix(prefix) }
        let running = !procs.isEmpty || appRunning()
        server.setClaudeRunning(running)
        var changed = running != claudeRunning
        claudeRunning = running

        let outUID = CA.defaultOutputDeviceUID()
        let key = procs.isEmpty || outUID == nil
            ? nil
            : procs.map { String($0.objectID) }.sorted().joined(separator: ",") + "@" + outUID!
        if key != currentKey, key == nil || Date() >= retryAt {
            attach(procs: procs, outputUID: outUID, key: key)
            changed = true
        }
        if changed { onChange?() }
    }

    private func attach(procs: [AudioProcessInfo], outputUID: String?, key: String?) {
        tap?.stop(); tap = nil
        capturing = false; activePIDs = []
        currentKey = key
        guard key != nil, let outputUID else {
            if lastLogged != "idle" { log("Claude audio processes gone; waiting"); lastLogged = "idle" }
            return
        }
        let framer = self.framer
        let t = ProcessTap(processObjects: procs.map(\.objectID), outputUID: outputUID, muteOriginal: muteOriginal) { mono, rate in
            framer.push(mono, sampleRate: rate)
        }
        do {
            try t.start()
            tap = t
            capturing = true
            activePIDs = procs.map(\.pid).sorted()
            lastLogged = nil
            log("attached: " + procs.map { "\($0.pid) \($0.bundleID)" }.joined(separator: ", "))
        } catch {
            t.stop()
            currentKey = nil                       // retry
            retryAt = Date().addingTimeInterval(3)
            if lastLogged != "\(error)" { log("attach failed: \(error)"); lastLogged = "\(error)" }
        }
    }
}
