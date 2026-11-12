import AppKit
import Foundation
import TapCore

// MARK: - Options

struct Options {
    var prefix = "com.anthropic.claudefordesktop"
    var port: UInt16 = 8765
    var probe = false
    var delayMs: Double?
}

func parseOptions() -> Options {
    var o = Options()
    var args = CommandLine.arguments.dropFirst()
    while let a = args.popFirst() {
        switch a {
        case "--bundle-prefix": if let v = args.popFirst() { o.prefix = v }
        case "--port": if let v = args.popFirst(), let p = UInt16(v) { o.port = p }
        case "--probe": o.probe = true
        case "--delay-ms": if let v = args.popFirst(), let d = Double(v) { o.delayMs = d }
        case "-h", "--help":
            print("""
            usage: claude-tap [--bundle-prefix ID] [--port N] [--probe]

              --bundle-prefix  capture processes whose bundle ID starts with this
                               (default com.anthropic.claudefordesktop)
              --port           WebSocket port on 127.0.0.1 (default 8765)
              --delay-ms N     sync-mode test: mute the original output and play it back N ms late
              --probe          tap each matching process separately and print the peak level
                               per PID, to find which helper actually plays the sound
            """)
            exit(0)
        default:
            FileHandle.standardError.write(Data("unknown argument: \(a)\n".utf8))
            exit(2)
        }
    }
    return o
}

func log(_ s: String) {
    FileHandle.standardError.write(Data(("\r\u{1B}[K" + s + "\n").utf8))
}

// MARK: - Level meter

final class Level {
    private let lock = NSLock()
    private var peak: Float = 0
    private var rms: Float = 0
    func update(peak p: Float, rms r: Float) {
        lock.lock(); peak = max(peak, p); rms = r; lock.unlock()
    }
    func take() -> (peak: Float, rms: Float) {
        lock.lock(); defer { lock.unlock() }
        let v = (peak, rms); peak = 0; return v
    }
}

func db(_ x: Float) -> Float { x > 1e-6 ? 20 * log10(x) : -120 }

func meterLine(_ level: (peak: Float, rms: Float), pids: [pid_t], clients: Int, capturing: Bool) -> String {
    let width = 40
    let d = db(level.rms)
    let filled = max(0, min(width, Int((d + 60) / 60 * Float(width))))
    let bar = String(repeating: "█", count: filled) + String(repeating: "·", count: width - filled)
    let dbText = d <= -100 ? "  -inf" : String(format: "%6.1f", d)
    let state = capturing ? "pids \(pids.map(String.init).joined(separator: ","))" : "waiting for Claude"
    return "\(bar) \(dbText) dBFS  peak \(String(format: "%5.1f", db(level.peak)))  clients \(clients)  \(state)"
}

// MARK: - Probe mode

func runProbe(_ opts: Options) -> Never {
    guard let outUID = CA.defaultOutputDeviceUID() else { log("no default output device"); exit(1) }
    let procs = CA.processes().filter { $0.bundleID.hasPrefix(opts.prefix) }
    guard !procs.isEmpty else { log("no audio processes matching \(opts.prefix)"); exit(1) }
    var levels: [pid_t: Level] = [:]
    var taps: [ProcessTap] = []
    for p in procs {
        let lv = Level(); levels[p.pid] = lv
        let tap = ProcessTap(processObjects: [p.objectID], outputUID: outUID) { mono, _ in
            lv.update(peak: mono.reduce(0) { max($0, abs($1)) }, rms: 0)
        }
        do { try tap.start(); taps.append(tap) } catch { log("pid \(p.pid) (\(p.bundleID)): \(error)") }
    }
    print("Probing \(taps.count) processes. Make Claude speak. Ctrl-C to stop.")
    Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
        let row = procs.map { p -> String in
            let pk = levels[p.pid]?.take().peak ?? 0
            return "\(p.pid) \(pk > 0 ? String(format: "%.1f dB", db(pk)) : "silent")"
        }
        print(row.joined(separator: "  |  "))
    }
    RunLoop.main.run()
    exit(0)
}

// MARK: - Controller

final class Controller {
    private let engine: TapEngine
    private let level = Level()
    private let isTTY = isatty(STDOUT_FILENO) != 0
    private var timer: Timer?

    init(_ opts: Options) {
        engine = TapEngine(prefix: opts.prefix, port: opts.port)
        let level = self.level
        engine.onFrame = { peak, rms in level.update(peak: peak, rms: rms) }
        engine.onLog = { log($0) }
        engine.onFatal = { log($0); exit(1) }
        if let d = opts.delayMs {
            engine.player.setDelay(ms: d)
            engine.detectInterrupts = true
            engine.onInterrupt = { log("interrupt detected: delayed audio flushed") }
            engine.muteOriginal = true     // original is silenced while this runs; it returns on exit
        }
    }

    func run() throws {
        try engine.start()
        print("claude-tap: ws://127.0.0.1:\(engine.port)  matching bundle IDs starting with \(engine.prefix)")
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.drawMeter() }
    }

    func shutdown() {
        timer?.invalidate()
        engine.stop()
        print()
    }

    private func drawMeter() {
        guard isTTY else { return }
        let line = meterLine(level.take(), pids: engine.activePIDs, clients: engine.clientCount, capturing: engine.capturing)
        FileHandle.standardOutput.write(Data(("\r\u{1B}[K" + line).utf8))
    }
}

// MARK: - Entry

let options = parseOptions()
setvbuf(stdout, nil, _IOLBF, 0)
if options.probe { runProbe(options) }

let controller = Controller(options)
do { try controller.run() } catch {
    log("failed to start: \(error)")
    exit(1)
}

var signalSources: [DispatchSourceSignal] = []
for sig in [SIGINT, SIGTERM] {
    signal(sig, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    src.setEventHandler { controller.shutdown(); exit(0) }
    src.resume()
    signalSources.append(src)
}
RunLoop.main.run()
