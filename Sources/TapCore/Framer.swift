import Foundation

/// Streaming linear resampler to a fixed output rate.
struct Resampler {
    let outRate: Double
    private var inRate: Double = 0
    private var carry: [Float] = []
    private var pos: Double = 0

    init(outRate: Double) { self.outRate = outRate }

    mutating func process(_ input: [Float], inRate rate: Double) -> [Float] {
        if rate != inRate { inRate = rate; carry = []; pos = 0 }
        if rate == outRate { return input }
        let step = rate / outRate
        let buf = carry + input
        var out: [Float] = []
        out.reserveCapacity(Int(Double(input.count) / step) + 2)
        while pos + 1 < Double(buf.count) {
            let i = Int(pos)
            let f = Float(pos - Double(i))
            out.append(buf[i] * (1 - f) + buf[i + 1] * f)
            pos += step
        }
        let drop = min(Int(pos), buf.count)
        carry = Array(buf[drop...])
        pos -= Double(drop)
        return out
    }
}

/// Resamples to 48 kHz and cuts fixed 20 ms (960-sample) frames.
final class Framer {
    static let sampleRate = 48_000.0
    static let frameSamples = 960

    private var resampler = Resampler(outRate: Framer.sampleRate)
    private var pending: [Float] = []
    var onFrame: (Data, _ peak: Float, _ rms: Float) -> Void

    init(onFrame: @escaping (Data, Float, Float) -> Void) { self.onFrame = onFrame }

    func push(_ mono: [Float], sampleRate: Double) {
        pending += resampler.process(mono, inRate: sampleRate)
        var offset = 0
        while pending.count - offset >= Framer.frameSamples {
            let slice = pending[offset..<offset + Framer.frameSamples]
            var peak: Float = 0, sum: Float = 0
            for s in slice { peak = max(peak, abs(s)); sum += s * s }
            let rms = (sum / Float(Framer.frameSamples)).squareRoot()
            let data = slice.withUnsafeBufferPointer { Data(buffer: $0) }   // native (little-endian) Float32
            onFrame(data, peak, rms)
            offset += Framer.frameSamples
        }
        if offset > 0 { pending.removeFirst(offset) }
    }
}
