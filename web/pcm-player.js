// AudioWorklet: plays 48 kHz mono Float32 frames pushed from the main thread.
// A small jitter buffer keeps latency low: it starts after ~40 ms is queued and drops the
// oldest audio if more than ~150 ms piles up.
class PcmPlayer extends AudioWorkletProcessor {
  constructor() {
    super();
    this.cap = 48000;
    this.ring = new Float32Array(this.cap);
    this.read = 0;
    this.count = 0;
    this.primed = false;
    this.startAt = 1920;
    this.maxQueued = 7200;
    this.port.onmessage = (e) => {
      const m = e.data;
      if (m === "clear") { this.read = 0; this.count = 0; this.primed = false; return; }
      const f = m;
      for (let i = 0; i < f.length; i++) {
        this.ring[(this.read + this.count) % this.cap] = f[i];
        if (this.count < this.cap) this.count++; else this.read = (this.read + 1) % this.cap;
      }
      if (this.count > this.maxQueued) {
        const drop = this.count - this.maxQueued;
        this.read = (this.read + drop) % this.cap;
        this.count -= drop;
      }
    };
  }

  process(_inputs, outputs) {
    const out = outputs[0][0];
    if (!this.primed && this.count >= this.startAt) this.primed = true;
    if (!this.primed) return true;           // outputs silence
    for (let i = 0; i < out.length; i++) {
      if (this.count === 0) { this.primed = false; break; }   // underrun: re-prime
      out[i] = this.ring[this.read];
      this.read = (this.read + 1) % this.cap;
      this.count--;
    }
    return true;
  }
}
registerProcessor("pcm-player", PcmPlayer);
