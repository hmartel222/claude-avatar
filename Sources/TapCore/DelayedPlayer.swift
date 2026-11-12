import AVFoundation
import Foundation
import os

/// Plays 20 ms mono 48 kHz frames to the current output device, each held back by `delayMs`.
/// Used in sync mode: Claude's own output is muted while tapped, and this plays it again in step
/// with a video face that arrives late.
public final class DelayedPlayer {
    private static let frameSamples = 960
    private let capacity = 150                       // 3 s of frames
    private let samples: UnsafeMutablePointer<Float>
    private let dues: UnsafeMutablePointer<UInt64>   // uptime (ns) at which each frame may start
    private var head = 0, count = 0, offset = 0
    private var playing = false
    private var delayNs: UInt64 = 0
    private var lock = os_unfair_lock_s()

    private var engine: AVAudioEngine?
    private var observer: NSObjectProtocol?
    public private(set) var isEnabled = false

    public init() {
        samples = .allocate(capacity: capacity * Self.frameSamples)
        samples.initialize(repeating: 0, count: capacity * Self.frameSamples)
        dues = .allocate(capacity: capacity)
        dues.initialize(repeating: 0, count: capacity)
    }

    deinit { samples.deallocate(); dues.deallocate() }

    /// Starts/stops the audio engine. Disabled = no output device activity at all.
    public func setEnabled(_ on: Bool) {
        guard on != isEnabled else { return }
        isEnabled = on
        if on { startEngine() } else { stopEngine(); flush() }
    }

    public func setDelay(ms: Double) {
        let ns = UInt64(max(0, ms) * 1_000_000)
        os_unfair_lock_lock(&lock); delayNs = ns; os_unfair_lock_unlock(&lock)
    }

    /// Drop everything not yet played. Output goes silent within one render quantum.
    public func flush() {
        os_unfair_lock_lock(&lock)
        head = 0; count = 0; offset = 0; playing = false
        os_unfair_lock_unlock(&lock)
    }

    public func enqueue(_ frame: Data) {
        guard isEnabled, frame.count == Self.frameSamples * MemoryLayout<Float>.size else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        if count == capacity { head = (head + 1) % capacity; count -= 1; offset = 0 }   // overflow: drop oldest
        let slot = (head + count) % capacity
        frame.withUnsafeBytes { raw in
            (samples + slot * Self.frameSamples).update(from: raw.bindMemory(to: Float.self).baseAddress!, count: Self.frameSamples)
        }
        dues[slot] = now + delayNs
        count += 1
    }

    // MARK: - engine

    private func startEngine() {
        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let node = AVAudioSourceNode(format: format) { [unowned self] _, _, frames, abl in
            self.render(Int(frames), abl)
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        do { try engine.start() } catch { print("[player] engine start failed: \(error)") }
        self.engine = engine
        // Output device changed (headphones plugged in, AirPods connected): the engine stops itself.
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let self, self.isEnabled, let e = self.engine, !e.isRunning else { return }
            try? e.start()
        }
    }

    private func stopEngine() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        engine?.stop(); engine = nil
    }

    private func render(_ frames: Int, _ abl: UnsafeMutablePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(abl)
        guard let out = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        var written = 0
        os_unfair_lock_lock(&lock)
        while written < frames {
            if !playing {
                if count > 0, now >= dues[head] { playing = true; offset = 0 } else { break }
            }
            let take = min(Self.frameSamples - offset, frames - written)
            (out + written).update(from: samples + head * Self.frameSamples + offset, count: take)
            written += take; offset += take
            if offset == Self.frameSamples {
                head = (head + 1) % capacity; count -= 1; offset = 0
                if count == 0 { playing = false }      // drained: the next frame waits for its due time
            }
        }
        os_unfair_lock_unlock(&lock)
        if written < frames { (out + written).update(repeating: 0, count: frames - written) }
    }
}
