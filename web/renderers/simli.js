// Simli cloud renderer: photoreal video face over WebRTC (https://docs.simli.com).
// Implements the Renderer contract: pushAudio(frame), stop(), setState(), latencyMs, attach(video).
//
// The API key never reaches this page. The native shell holds it in the macOS Keychain, mints a
// short-lived session token and hands it over via claudeAvatar.setSimliToken().
import { SimliClient, LogLevel } from "simli";

const SPEECH_PEAK = 0.002;
const DEFAULT_LATENCY_MS = 350;   // used until the first measurement
const MEASURE_WINDOW = 5;         // median of the last N onsets

export class SimliRenderer {
  /** @param {{requestToken: () => Promise<string>, onSync: (s: object) => void}} io */
  constructor(io) {
    this.io = io;
    this.client = null;
    this.state = "idle";          // idle | connecting | ready | error
    this.paused = false;
    this.speaking = false;
    this.lastLoud = 0;
    this.silentFrames = 0;
    this.samples = [];
    this.latencyMs = DEFAULT_LATENCY_MS;
    this.onset = null;            // performance.now() of the last audio onset awaiting its video
    this.motion = { prev: null, baseline: 0 };
  }

  async init(container) {
    this.video = document.createElement("video");
    Object.assign(this.video.style, { width: "100%", height: "100%", objectFit: "cover", objectPosition: "50% 35%", opacity: "0", transition: "opacity .3s" });
    this.video.autoplay = true; this.video.playsInline = true; this.video.muted = true;   // the page never plays sound
    // The SDK wants an <audio> element for the avatar's speech. It is muted: you hear Claude through the native app.
    this.audio = document.createElement("audio");
    this.audio.muted = true; this.audio.volume = 0;
    container.append(this.video);
    this.attach(this.video);
    this.canvas = document.createElement("canvas");
    this.canvas.width = 32; this.canvas.height = 24;
    this.g = this.canvas.getContext("2d", { willReadFrequently: true });
    this.sync();
  }

  attach(video) {
    this.video = video;
    const tick = (now) => { this.onVideoFrame(now); video.requestVideoFrameCallback?.(tick); };
    video.requestVideoFrameCallback?.(tick);
  }

  sync() { this.io.onSync({ renderer: "simli", state: this.state, latencyMs: this.latencyMs }); }
  setState(s) { this.speaking = s === "speaking"; }
  setSensitivity() {}

  setPaused(p) {
    this.paused = p;
    if (p) this.disconnect();     // don't burn session minutes while the tile is hidden
  }

  async connect() {
    if (this.state === "connecting" || this.state === "ready" || this.paused) return;
    this.state = "connecting"; this.sync();
    try {
      const token = await this.io.requestToken();
      const client = new SimliClient(token, this.video, this.audio, null, LogLevel.ERROR);
      client.on("stop", () => { if (this.client === client) this.fail("idle"); });
      client.on("error", () => { if (this.client === client) this.fail("error"); });
      client.on("startup_error", () => { if (this.client === client) this.fail("error"); });
      this.client = client;
      await client.start();                 // resolves when the first video frame shows
      this.state = "ready";
      this.video.style.opacity = "1";
      this.sync();
    } catch (e) {
      console.error("Simli connect failed", e);
      this.fail("error");
      // back off so a bad key doesn't hammer the API
      this.retryAfter = performance.now() + 15000;
    }
  }

  fail(state) {
    this.client?.stop?.().catch?.(() => {});
    this.client = null;
    this.state = state;
    this.video.style.opacity = "0";
    this.sync();
  }

  disconnect() {
    if (this.client) this.fail("idle");
    else if (this.state !== "idle") { this.state = "idle"; this.sync(); }
  }

  /** @param {Float32Array} frame 960 samples, mono, 48 kHz */
  pushAudio(frame) {
    let peak = 0;
    for (let i = 0; i < frame.length; i++) { const a = frame[i] < 0 ? -frame[i] : frame[i]; if (a > peak) peak = a; }
    const now = performance.now();
    if (peak >= SPEECH_PEAK) {
      if (now - this.lastLoud > 400 && this.state === "ready") this.onset = now;   // new utterance
      this.lastLoud = now;
      if (this.state === "idle" || (this.state === "error" && now > (this.retryAfter || 0))) this.connect();
    }
    if (this.state !== "ready" || !this.client) return;
    this.client.sendAudioData(to16kPcm16(frame));
  }

  /** Interrupt: drop everything Simli has not yet spoken. */
  stop() {
    this.onset = null;
    try { this.client?.ClearBuffer(); } catch {}
  }

  // ---- latency: audio onset -> first visible mouth motion -----------------
  onVideoFrame(now) {
    if (this.state !== "ready" || this.video.videoWidth === 0) return;
    this.g.drawImage(this.video, 0, 0, 32, 24);
    const px = this.g.getImageData(0, 0, 32, 24).data;
    const prev = this.motion.prev;
    let diff = 0;
    if (prev) { for (let i = 0; i < px.length; i += 4) diff += Math.abs(px[i] - prev[i]); diff /= px.length / 4; }
    this.motion.prev = px;
    if (!prev) return;
    const m = this.motion;
    if (this.onset == null) { m.baseline = m.baseline * 0.95 + diff * 0.05; return; }   // idle motion level
    const t = performance.now() - this.onset;
    if (t > 1500) { this.onset = null; return; }                                          // gave up
    if (diff > Math.max(m.baseline * 3, 2.5) && t > 80) {
      this.onset = null;
      this.samples.push(t);
      if (this.samples.length > MEASURE_WINDOW) this.samples.shift();
      const sorted = [...this.samples].sort((a, b) => a - b);
      this.latencyMs = Math.round(sorted[Math.floor(sorted.length / 2)]);
      this.sync();
    }
  }
}

/** 48 kHz Float32 -> 16 kHz PCM16 little-endian bytes (3:1 average, a cheap low-pass). */
function to16kPcm16(frame) {
  const out = new Int16Array(frame.length / 3 | 0);
  for (let i = 0, j = 0; j < out.length; i += 3, j++) {
    const s = (frame[i] + frame[i + 1] + frame[i + 2]) / 3;
    out[j] = Math.max(-32768, Math.min(32767, Math.round(s * 32767)));
  }
  return new Uint8Array(out.buffer);
}
