// Stage: a "video call" look layered over either renderer.
//   * blurred living-room photo behind the avatar, graded by local time of day
//   * Zoom-style lighting on the face (real three.js lights for the 3D avatar, a canvas grade for Simli)
//   * person cutout for Simli's video (MediaPipe selfie segmentation) so the room can sit behind it
// Renderers are untouched; this module only adds layers and nudges lights.

// ---- time of day -----------------------------------------------------------
// tint/win are [r,g,b,a]; key/amb are light colours; keyI/ambI are three.js intensities;
// theta swings the key light from the window side (morning) to the lamp side (evening).
const KEYFRAMES = [
  // hour, profile
  [0,    { tint: [20, 30, 80, .40],   bright: .46, sat: .8, win: [30, 45, 105, .78],    lamp: 1,   key: [150, 175, 255], keyI: 22, amb: [150, 165, 235], ambI: 1.25, theta: 2.0, vig: .55, faceTint: [90, 120, 255, .06], faceBright: 1.0 }],
  [5,    { tint: [20, 30, 80, .40],   bright: .46, sat: .8, win: [30, 45, 105, .78],    lamp: 1,   key: [150, 175, 255], keyI: 22, amb: [150, 165, 235], ambI: 1.25, theta: 2.0, vig: .55, faceTint: [90, 120, 255, .06], faceBright: 1.0 }],
  [6.5,  { tint: [255, 196, 150, .22], bright: .80, sat: .95, win: [255, 190, 140, .30], lamp: .5, key: [255, 214, 180], keyI: 20, amb: [255, 230, 215], ambI: 1.5,  theta: 1.2, vig: .40, faceTint: [255, 190, 140, .06], faceBright: 1.0 }],
  [9,    { tint: [255, 238, 210, .10], bright: 1.0, sat: 1.0,  win: [255, 230, 190, .10], lamp: 0,  key: [255, 244, 228], keyI: 22, amb: [255, 250, 245], ambI: 1.6,  theta: 1.0, vig: .30, faceTint: [255, 235, 205, .04], faceBright: 1.04 }],
  [13,   { tint: [255, 255, 252, 0],   bright: 1.05, sat: 1.02, win: [255, 255, 255, 0],  lamp: 0,   key: [255, 255, 250], keyI: 22, amb: [255, 255, 255], ambI: 1.6,  theta: 2.0, vig: .26, faceTint: [255, 255, 255, 0],   faceBright: 1.05 }],
  [17,   { tint: [255, 196, 130, .22], bright: .95, sat: 1.05, win: [255, 170, 90, .55],  lamp: .25, key: [255, 214, 165], keyI: 30, amb: [255, 228, 205], ambI: 1.8,  theta: 3.0, vig: .36, faceTint: [255, 190, 130, .07], faceBright: 1.0 }],
  [19.5, { tint: [255, 150, 95, .30],  bright: .58, sat: .9,  win: [120, 70, 100, .75],  lamp: .85, key: [255, 190, 140], keyI: 20, amb: [255, 205, 175], ambI: 1.35,  theta: 3.0, vig: .46, faceTint: [255, 170, 110, .07], faceBright: .98 }],
  [21.5, { tint: [20, 30, 80, .40],   bright: .46, sat: .8, win: [30, 45, 105, .78],    lamp: 1,   key: [150, 175, 255], keyI: 22, amb: [150, 165, 235], ambI: 1.25, theta: 2.0, vig: .55, faceTint: [90, 120, 255, .06], faceBright: 1.0 }],
  [24,   { tint: [20, 30, 80, .40],   bright: .46, sat: .8, win: [30, 45, 105, .78],    lamp: 1,   key: [150, 175, 255], keyI: 22, amb: [150, 165, 235], ambI: 1.25, theta: 2.0, vig: .55, faceTint: [90, 120, 255, .06], faceBright: 1.0 }],
];

// ---- face light rig -----------------------------------------------------------
// One light story per time of day, shared by both renderers.
//   dir   -1 = from screen left (the window) .. +1 = from the right (the lamp)
//   elev  0 = level with the face .. 1 = straight overhead
//   key   colour of the main source, k its strength; shadow/shadowCol shape the far side
//   fill  colour of the weaker second source (dusk sky, monitor glow), fillK its strength
const LIGHT_NIGHT   = { dir: .85, elev: .15, key: [255, 168, 98],  k: .60, shadow: .42, shadowCol: [20, 26, 66],  fill: [110, 150, 255], fillK: .30, fillElev: -.5, flicker: .02 };
const LIGHT_DAWN    = { dir: -.85, elev: .2, key: [255, 190, 140], k: .50, shadow: .26, shadowCol: [60, 48, 80],  fill: [190, 200, 255], fillK: .12, fillElev: 0,   flicker: 0 };
const LIGHT_MORNING = { dir: -.85, elev: .25, key: [255, 238, 215], k: .60, shadow: .24, shadowCol: [66, 68, 96], fill: [200, 215, 255], fillK: .12, fillElev: 0,   flicker: 0 };
const LIGHT_NOON    = { dir: -.25, elev: .75, key: [255, 252, 245], k: .50, shadow: .26, shadowCol: [72, 68, 84], fill: [210, 220, 255], fillK: .10, fillElev: 0,   flicker: 0 };
const LIGHT_GOLDEN  = { dir: -.9,  elev: .1,  key: [255, 188, 118], k: .75, shadow: .32, shadowCol: [66, 38, 48], fill: [200, 190, 255], fillK: .10, fillElev: 0,   flicker: 0 };
const LIGHT_EVENING = { dir: .85,  elev: .3,  key: [255, 172, 102], k: .65, shadow: .34, shadowCol: [42, 28, 60], fill: [140, 150, 255], fillK: .22, fillElev: 0,   flicker: .015 };
const LIGHT_KEYS = [[0, LIGHT_NIGHT], [5, LIGHT_NIGHT], [6.5, LIGHT_DAWN], [9, LIGHT_MORNING], [13, LIGHT_NOON],
                    [17, LIGHT_GOLDEN], [19.5, LIGHT_EVENING], [21.5, LIGHT_NIGHT], [24, LIGHT_NIGHT]];

const lerp = (a, b, t) => a + (b - a) * t;
function mix(a, b, t) {
  if (Array.isArray(a)) return a.map((v, i) => lerp(v, b[i], t));
  return lerp(a, b, t);
}
function blend(table, hour) {
  let i = 0;
  while (i < table.length - 2 && hour >= table[i + 1][0]) i++;
  const [h0, p0] = table[i], [h1, p1] = table[i + 1];
  const t = Math.min(1, Math.max(0, (hour - h0) / (h1 - h0)));
  const out = {};
  for (const k of Object.keys(p0)) out[k] = mix(p0[k], p1[k], t);
  return out;
}
export function profileAt(hour) {
  return { ...blend(KEYFRAMES, hour), light: blend(LIGHT_KEYS, hour) };
}
export function periodName(hour) {
  return hour < 6 ? "night" : hour < 11.5 ? "morning" : hour < 17 ? "afternoon" : hour < 20.5 ? "evening" : "night";
}
const rgba = (c, aScale = 1) => `rgba(${c[0] | 0},${c[1] | 0},${c[2] | 0},${(c[3] * aScale).toFixed(3)})`;
const hex = (c) => ((c[0] | 0) << 16) | ((c[1] | 0) << 8) | (c[2] | 0);

const CSS = `
#stage-bg { position: fixed; inset: 0; overflow: hidden; background: #111; z-index: 0; }
#stage-bg .photo { position: absolute; left: 50%; top: 50%; width: max(100%, calc(100vh * 1.4988)); aspect-ratio: 1.4988;
  background: url(/backdrops/living-room.jpg) center / cover; transform: translate(-50%, -50%) scale(1.12); }
#stage-bg .photo > * { position: absolute; pointer-events: none; }
#stage-bg .tint { inset: 0; mix-blend-mode: multiply; }
#stage-bg .win { left: 10%; top: 21%; width: 34%; height: 31%; mix-blend-mode: multiply; }
#stage-bg .lamp { left: 47%; top: 28%; width: 18%; aspect-ratio: 1; border-radius: 50%; mix-blend-mode: screen;
  background: radial-gradient(circle, rgba(255,196,120,.95) 0%, rgba(255,170,90,.45) 35%, rgba(255,150,70,0) 70%); }
#stage-vig { position: fixed; inset: 0; z-index: 3; pointer-events: none; }
#avatar { z-index: 1; }
#avatar canvas.cutout { position: absolute; inset: 0; width: 100%; height: 100%; transition: opacity .3s; }
#avatar.cutout video { position: absolute !important; left: 0; top: 0; width: 2px !important; height: 2px !important; opacity: 0 !important; pointer-events: none; }
body.stage-on { background: #111; }
`;

export class Stage {
  /** @param {{avatar: HTMLElement, params: URLSearchParams}} o */
  constructor({ avatar, params }) {
    this.avatar = avatar;
    this.room = params.get("room") !== "0";
    this.light = params.get("light") !== "0";
    this.blur = params.has("blur") ? parseFloat(params.get("blur")) : 5;
    this.hourOverride = params.has("hour") ? parseFloat(params.get("hour")) : null;
    this.head = null;
    this.cutout = null;

    const style = document.createElement("style");
    style.textContent = CSS;
    document.head.append(style);

    this.bg = document.createElement("div");
    this.bg.id = "stage-bg";
    this.bg.innerHTML = `<div class="photo"><div class="tint"></div><div class="win"></div><div class="lamp"></div></div>`;
    document.body.prepend(this.bg);
    this.photo = this.bg.querySelector(".photo");
    this.tintEl = this.bg.querySelector(".tint");
    this.winEl = this.bg.querySelector(".win");
    this.lampEl = this.bg.querySelector(".lamp");
    this.vig = document.createElement("div");
    this.vig.id = "stage-vig";
    document.body.append(this.vig);

    this.apply();
    setInterval(() => this.apply(), 30000);   // drifts through the day without a restart
  }

  get hour() {
    if (this.hourOverride != null) return this.hourOverride;
    const d = new Date();
    return d.getHours() + d.getMinutes() / 60;
  }

  setOptions({ room, light, blur }) {
    if (room != null) this.room = !!room;
    if (light != null) this.light = !!light;
    if (blur != null) this.blur = blur;
    this.apply();
  }

  /** Connects the 3D avatar so its three.js lights follow the time of day. */
  attachHead(head) { this.head = head; this.applyHeadLights(); }

  /** Cuts the person out of Simli's video and draws them over the room. */
  async attachVideo(video) {
    this.cutout = new Cutout(this.avatar, video, () => (this.light ? this.profile : null));
    this.cutout.enabled = this.room;
    this.apply();
    await this.cutout.init();
  }

  setPaused(p) { if (this.cutout) this.cutout.paused = !!p; }

  apply() {
    const p = this.profile = profileAt(this.hour);
    document.body.classList.toggle("stage-on", this.room);
    this.bg.style.display = this.room ? "" : "none";
    this.avatar.classList.toggle("cutout", this.room && !!this.cutout);
    if (this.cutout) this.cutout.enabled = this.room;

    this.photo.style.filter = `blur(${this.blur}px) brightness(${p.bright}) saturate(${p.sat})`;
    this.tintEl.style.background = rgba(p.tint);
    this.winEl.style.background = rgba(p.win);
    this.lampEl.style.opacity = p.lamp.toFixed(3);

    // Camera feel: soft vignette, deeper at night.
    this.vig.style.background = this.light
      ? `radial-gradient(ellipse at 50% 42%, rgba(0,0,0,0) 55%, rgba(0,0,0,${(p.vig * .55).toFixed(3)}) 100%)`
      : "none";
    this.avatar.style.filter = "";
    this.applyHeadLights();
  }

  applyHeadLights() {
    if (!this.head?.setLighting) return;
    const p = this.profile || profileAt(this.hour);
    if (!this.light) {
      this.head.setLighting({ lightAmbientColor: 0xffffff, lightAmbientIntensity: 2, lightDirectColor: 0x8888aa,
                              lightDirectIntensity: 30, lightDirectPhi: 1, lightDirectTheta: 2 });
      return;
    }
    const L = p.light;
    this.head.setLighting({
      lightAmbientColor: hex(p.amb), lightAmbientIntensity: (1 - L.shadow) * 1.2,
      lightDirectColor: hex(L.key), lightDirectIntensity: 10 + 18 * L.k,
      lightDirectPhi: lerp(1.35, .45, Math.max(0, L.elev)), lightDirectTheta: L.dir * 1.2,
      lightSpotColor: hex(L.fill), lightSpotIntensity: L.fillK * 20,
      lightSpotPhi: 1.2, lightSpotTheta: -L.dir * 1.0, lightSpotDispersion: 1,
    });
    const c = this.head.renderer?.domElement;
    if (c) c.style.filter = "contrast(1.05) saturate(1.04)";
  }
}

// ---- person cutout for the Simli video ---------------------------------------
class Cutout {
  constructor(container, video, getProfile) {
    this.container = container;
    this.video = video;
    this.getProfile = getProfile;
    this.enabled = true;
    this.paused = false;
    this.segmenter = null;
    this.invert = null;            // decided from the first masks (person should be central)
    this.smooth = null;
    this.maskCanvas = document.createElement("canvas");
    this.maskCtx = this.maskCanvas.getContext("2d");
    this.out = document.createElement("canvas");
    this.out.className = "cutout";
    this.out.style.opacity = "0";
    this.ctx = this.out.getContext("2d");
    container.append(this.out);
    this.running = false;
  }

  async init() {
    const base = "/node_modules/@mediapipe/tasks-vision";
    const { FilesetResolver, ImageSegmenter } = await import(`${base}/vision_bundle.mjs`);
    const fileset = await FilesetResolver.forVisionTasks(`${base}/wasm`);
    const make = (delegate) => ImageSegmenter.createFromOptions(fileset, {
      baseOptions: { modelAssetPath: "/vendor/mediapipe/selfie_segmenter.tflite", delegate },
      runningMode: "VIDEO", outputConfidenceMasks: true, outputCategoryMask: false,
    });
    try { this.segmenter = await make("GPU"); } catch { this.segmenter = await make("CPU"); }
    this.running = true;
    this.loop();
  }

  loop() {
    const tick = (now) => { this.frame(now); this.video.requestVideoFrameCallback(tick); };
    this.video.requestVideoFrameCallback(tick);
  }

  frame(now) {
    const v = this.video;
    const live = v.style.opacity !== "0" && v.videoWidth > 0 && v.readyState >= 2;
    this.out.style.opacity = live && this.enabled ? "1" : "0";
    if (!live || !this.enabled || this.paused || !this.segmenter) return;
    this.segmentAndDraw(v, v.videoWidth, v.videoHeight, now);
  }

  /** Draws `source` (cover-cropped like the old <video>, anchored 50% 35%) with the person mask applied. */
  segmentAndDraw(source, sw, sh, now) {
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const W = Math.round(this.container.clientWidth * dpr), H = Math.round(this.container.clientHeight * dpr);
    if (!W || !H) return;
    if (this.out.width !== W || this.out.height !== H) { this.out.width = W; this.out.height = H; }

    this.segmenter.segmentForVideo(source, now, (res) => {
      const m = res.confidenceMasks?.[res.confidenceMasks.length > 1 ? 1 : 0];
      if (!m) return;
      const mw = m.width, mh = m.height, data = m.getAsFloat32Array();
      this.updateMask(data, mw, mh);
    });
    if (!this.smooth) return;

    // cover crop
    const scale = Math.max(W / sw, H / sh);
    const cw = W / scale, ch = H / scale;
    const cx = (sw - cw) * 0.5, cy = (sh - ch) * 0.35;
    const mw = this.maskCanvas.width, mh = this.maskCanvas.height;

    const g = this.ctx;
    g.globalCompositeOperation = "source-over";
    g.clearRect(0, 0, W, H);
    g.drawImage(source, cx, cy, cw, ch, 0, 0, W, H);
    g.globalCompositeOperation = "destination-in";
    g.filter = `blur(${Math.max(1, W / 220).toFixed(1)}px)`;
    g.drawImage(this.maskCanvas, cx / sw * mw, cy / sh * mh, cw / sw * mw, ch / sh * mh, 0, 0, W, H);
    g.filter = "none";

    // Light from a real-feeling source (window, lamp, overhead) on the person only:
    // source-atop keeps every layer off the transparent background.
    const p = this.getProfile?.();
    if (p) this.paintLight(g, W, H, p.light, now);
  }

  paintLight(g, W, H, L, now) {
    const flick = 1 + L.flicker * (Math.sin(now / 700) + .5 * Math.sin(now / 230));
    const k = L.k * flick;
    const c = (col, a) => `rgba(${col[0] | 0},${col[1] | 0},${col[2] | 0},${Math.max(0, Math.min(1, a)).toFixed(3)})`;
    const sd = L.dir < 0 ? -1 : 1;                        // -1: lit from the left, +1: from the right
    const cx = W * .5;
    const fx = (u) => cx + sd * u * W;                    // u<0 toward the light, u>0 away from it
    g.globalCompositeOperation = "source-atop";

    // 1. falloff across the face: lit cheek -> shadowed cheek (face spans roughly +-0.15 W)
    let gr = g.createLinearGradient(fx(-.17), 0, fx(.17), 0);
    gr.addColorStop(0, c(L.shadowCol, 0));
    gr.addColorStop(1, c(L.shadowCol, L.shadow * 1.6));
    g.fillStyle = gr; g.fillRect(0, 0, W, H);

    // 2. overhead light: forehead bright, under the chin and neck dark
    if (L.elev > .05) {
      gr = g.createLinearGradient(0, 0, 0, H);
      gr.addColorStop(0, c(L.shadowCol, 0));
      gr.addColorStop(.35, c(L.shadowCol, 0));
      gr.addColorStop(1, c(L.shadowCol, L.shadow * L.elev * 1.1));
      g.fillStyle = gr; g.fillRect(0, 0, W, H);
    }

    // 3. the key source's glow, centred toward the lamp/window
    const sx = fx(-.32), sy = H * (.42 - L.elev * .3);
    gr = g.createRadialGradient(sx, sy, 0, sx, sy, W * .5);
    gr.addColorStop(0, c(L.key, k * .5));
    gr.addColorStop(1, c(L.key, 0));
    g.fillStyle = gr; g.fillRect(0, 0, W, H);

    // 4. skin sheen on the lit cheek / forehead
    const hx = fx(-.05), hy = H * (.38 - L.elev * .06);
    gr = g.createRadialGradient(hx, hy, 0, hx, hy, W * .14);
    gr.addColorStop(0, c([255, 250, 240], k * .22));
    gr.addColorStop(1, c([255, 250, 240], 0));
    g.fillStyle = gr; g.fillRect(0, 0, W, H);

    // 5. rim light along the edge of the head nearest the source
    gr = g.createLinearGradient(fx(-.15), 0, fx(-.07), 0);
    gr.addColorStop(0, c(L.key, k * .4));
    gr.addColorStop(1, c(L.key, 0));
    g.fillStyle = gr; g.fillRect(0, 0, W, H);

    // 6. second, weaker source: monitor glow from below at night, sky bounce on the shadow side otherwise
    if (L.fillElev < 0) {
      gr = g.createLinearGradient(0, H, 0, H * .5);
      gr.addColorStop(0, c(L.fill, L.fillK * .35));
      gr.addColorStop(1, c(L.fill, 0));
    } else {
      gr = g.createLinearGradient(fx(.2), 0, fx(.06), 0);
      gr.addColorStop(0, c(L.fill, L.fillK * .7));
      gr.addColorStop(1, c(L.fill, 0));
    }
    g.fillStyle = gr; g.fillRect(0, 0, W, H);
    g.globalCompositeOperation = "source-over";
  }

  /** Mask → alpha canvas, with orientation check, edge contrast and temporal smoothing. */
  updateMask(data, mw, mh) {
    if (this.maskCanvas.width !== mw || this.maskCanvas.height !== mh) {
      this.maskCanvas.width = mw; this.maskCanvas.height = mh; this.smooth = null;
    }
    if (this.invert == null) {
      // The person sits in the middle of the frame, the background at the edges.
      let centre = 0, edge = 0, nc = 0, ne = 0;
      for (let y = 0; y < mh; y++) for (let x = 0; x < mw; x++) {
        const v = data[y * mw + x];
        if (x > mw * .3 && x < mw * .7 && y > mh * .3) { centre += v; nc++; }
        else if (x < mw * .1 || x > mw * .9) { edge += v; ne++; }
      }
      this.invert = centre / nc < edge / ne;
    }
    const n = mw * mh;
    if (!this.smooth) this.smooth = new Float32Array(n);
    const img = this.maskCtx.createImageData(mw, mh), px = img.data;
    for (let i = 0; i < n; i++) {
      let v = this.invert ? 1 - data[i] : data[i];
      v = Math.min(1, Math.max(0, (v - 0.35) / 0.4));          // firm up the edge
      v = this.smooth[i] = this.smooth[i] * 0.35 + v * 0.65;   // light temporal smoothing
      px[i * 4 + 3] = v * 255;
    }
    this.maskCtx.putImageData(img, 0, 0);
  }
}
