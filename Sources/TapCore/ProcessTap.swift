import CoreAudio
import AudioToolbox
import Foundation

struct TapError: Error, CustomStringConvertible {
    let description: String
    init(_ what: String, _ status: OSStatus) { description = "\(what) failed (OSStatus \(status))" }
}

/// One process tap + private aggregate device delivering mono Float32 at the device's native rate.
public final class ProcessTap {
    public typealias Handler = (_ mono: [Float], _ sampleRate: Double) -> Void

    private let processObjects: [AudioObjectID]
    private let outputUID: String
    private let queue = DispatchQueue(label: "claude-tap.io", qos: .userInteractive)
    private let handler: Handler
    private let muteOriginal: Bool

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?

    /// `muteOriginal`: silence the tapped processes' own output while this tap is running (sync mode).
    /// The system un-mutes automatically when the tap is destroyed, even if the app crashes.
    public init(processObjects: [AudioObjectID], outputUID: String, muteOriginal: Bool = false, handler: @escaping Handler) {
        self.processObjects = processObjects
        self.outputUID = outputUID
        self.muteOriginal = muteOriginal
        self.handler = handler
    }

    public func start() throws {
        do { try startUnchecked() } catch { stop(); throw error }
    }

    private func startUnchecked() throws {
        let desc = CATapDescription(monoMixdownOfProcesses: processObjects)
        desc.uuid = UUID()
        desc.name = "claude-tap"
        desc.isPrivate = true
        desc.muteBehavior = muteOriginal ? .mutedWhenTapped : .unmuted   // unmuted: you keep hearing Claude

        var status = AudioHardwareCreateProcessTap(desc, &tapID)
        guard status == noErr else { throw TapError("AudioHardwareCreateProcessTap", status) }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "claude-tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: desc.uuid.uuidString,
            ]],
        ]
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
        guard status == noErr else { throw TapError("AudioHardwareCreateAggregateDevice", status) }

        guard let asbd: AudioStreamBasicDescription = CA.get(tapID, kAudioTapPropertyFormat) else {
            throw TapError("read kAudioTapPropertyFormat", -1)
        }
        let rate = asbd.mSampleRate
        let channels = max(Int(asbd.mChannelsPerFrame), 1)
        let interleaved = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0

        let handler = self.handler
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, inData, _, _, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
            guard let mono = ProcessTap.downmix(buffers, channels: channels, interleaved: interleaved) else { return }
            handler(mono, rate)
        }
        guard status == noErr else { throw TapError("AudioDeviceCreateIOProcIDWithBlock", status) }

        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else { throw TapError("AudioDeviceStart", status) }
    }

    public func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
        queue.sync {}   // let any in-flight callback finish
    }

    private static func downmix(_ buffers: UnsafeMutableAudioBufferListPointer, channels: Int, interleaved: Bool) -> [Float]? {
        guard buffers.count > 0 else { return nil }
        if interleaved {
            let buf = buffers[0]
            guard let data = buf.mData?.assumingMemoryBound(to: Float.self) else { return nil }
            let total = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
            let frames = total / channels
            if channels == 1 { return Array(UnsafeBufferPointer(start: data, count: frames)) }
            var out = [Float](repeating: 0, count: frames)
            let inv = 1 / Float(channels)
            for f in 0..<frames {
                var sum: Float = 0
                for c in 0..<channels { sum += data[f * channels + c] }
                out[f] = sum * inv
            }
            return out
        }
        // Non-interleaved: one buffer per channel.
        var frames = Int.max
        for b in buffers { frames = min(frames, Int(b.mDataByteSize) / MemoryLayout<Float>.size) }
        guard frames > 0, frames != Int.max else { return nil }
        var out = [Float](repeating: 0, count: frames)
        for b in buffers {
            guard let d = b.mData?.assumingMemoryBound(to: Float.self) else { continue }
            for f in 0..<frames { out[f] += d[f] }
        }
        let inv = 1 / Float(buffers.count)
        for f in 0..<frames { out[f] *= inv }
        return out
    }
}
