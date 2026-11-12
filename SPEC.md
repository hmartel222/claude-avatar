Claude Avatar Companion — macOS Build Spec
Nov 10, 2026 · @Harrison Martel
Overview
A small always-on-top "video call" window on your Mac shows a 3D character that lip-syncs to Claude's voice while you use voice mode in the Claude desktop app. Claude does all the thinking, memory and tool use; the companion only listens to Claude's audio output and animates a face. Target: a working build in 2–3 focused days with Claude Code.
Goals
• Capture only the Claude desktop app's audio, digitally, while you keep hearing Claude normally in headphones.
• Drive a free, locally rendered 3D avatar (TalkingHead + HeadAudio) from that audio, with mouth lag under 150 ms.
• Present it as a Zoom-style tile: borderless, draggable, resizable, pinned above other windows, with simple controls.
• Cost nothing to run: no accounts, no API keys, no per-minute fees, no GPU.
Non-goals for v1
• No second AI, no text-to-speech, no separate memory. The voice you hear is Claude's own.
• No screen watching. The avatar knows only what Claude says aloud.
• No photoreal face in v1. Phases 5–6 add it as an optional renderer (see Bring your own avatar).
• Not an official Claude integration. It reads the app's audio output and nothing else.
Architecture
You hear Claude straight from the app. The companion gets a digital copy, turns it into mouth shapes, and never plays any sound itself.
Components
The app has four parts. Build them in this order so each can be tested on its own.
1. Audio tap (Swift)
• Uses Core Audio process taps (macOS 14.2+) to copy the output of every process whose bundle ID starts with Claude's. Claude is an Electron app, so the sound may come from a helper process, not the main one.
• Leaves the original audio untouched. You still hear Claude in your headphones; the tap gets an identical copy.
• Down-mixes to mono, keeps Float32, and sends 20 ms frames (960 samples at 48 kHz) as binary messages over a WebSocket at ws://127.0.0.1:8765.
• Sends JSON status messages: {"type":"status","claudeRunning":true}. Re-attaches automatically when Claude quits and relaunches.
• Fallback if process taps fail: ScreenCaptureKit audio capture filtered to the Claude app (needs Screen Recording permission instead).
2. Avatar page (HTML + JavaScript)
• Loads TalkingHead (three.js) with a GLB avatar that has ARKit and Oculus viseme blend shapes.
• Connects to the WebSocket and feeds each frame into an AudioWorklet buffer, then into HeadAudio, which detects visemes from raw audio with no transcript.
• The audio is routed through a gain node set to 0. The page must never play sound; you already hear Claude directly.
• Visemes drive the mouth. TalkingHead's idle settings handle blinking, eye contact and small head movement.
3. Window shell (SwiftUI)
• Hosts the avatar page in a WKWebView inside a borderless, rounded, always-on-top window (default 360 × 270, aspect locked to 4:3).
• A name label ("Claude") at the bottom left, like a Zoom tile, plus a status dot: grey when Claude isn't running, green when connected, pulsing while speaking.
• Runs the audio tap in-process once Phase 3 merges the two.
4. Controls
• Hover bar: pin/unpin on top, size presets (S/M/L), hide face, settings.
• Menu-bar icon: show/hide window, choose avatar, mouth sensitivity slider, launch at login, quit.
• Global hotkey ⌥⌘A to show or hide the window.
Tech stack and dependencies
Everything is free. The only paid thing you already have is Claude itself.
Dependency
Role
Needed for
Notes
macOS 14.2 (Sonoma) or later
Core Audio process taps
Audio tap
Check in Apple menu → About This Mac. Apple Silicon or Intel both fine.
Claude desktop app
The voice and the brain
Everything
Voice mode is beta and must be enabled.
Headphones
Keeps Claude from hearing itself
Everything
Wired or AirPods both work; capture is digital.
Xcode 15+ (or Command Line Tools)
Swift compiler, SwiftUI, code signing
Tap, window
Free from the App Store.
Apple ID signing identity
Stable signature so macOS remembers permissions
Tap, window
Free "Personal Team" in Xcode is enough.
Node.js 20+
Local dev server for the avatar page
Phase 2 testing
Not needed by the finished app.
TalkingHead
3D avatar, lip-sync, idle motion
Avatar page
MIT license, uses three.js.
HeadAudio
Viseme detection from raw audio, in the browser
Avatar page
Verify its license and model file before bundling.
three.js
WebGL rendering
Avatar page
Pinned to the version TalkingHead documents.
GLB avatar with ARKit + Oculus visemes
The face
Avatar page
Start with TalkingHead's sample avatars; custom later.
BlackHole 2ch (optional)
Virtual audio device
Fallback only
Use only if both process taps and ScreenCaptureKit fail.
macOS permissions and setup
macOS will ask for one permission: system audio recording. Everything else is optional.
1. System audio recording. Required for the process tap. Add NSAudioCaptureUsageDescription to the app's Info.plist (for example, "Reads Claude's voice to animate the avatar"). Approve it in System Settings → Privacy & Security → Screen & System Audio Recording, under the audio-only list.
2. Screen Recording (fallback only). Needed only if you switch to ScreenCaptureKit capture.
3. Microphone (optional, Phase 4). Only if you add the "listening" animation that reacts to your voice. macOS shares the mic, so Claude keeps hearing you.
4. Stable code signing. Sign every build with the same Apple ID team. macOS ties permissions to the signature; ad-hoc builds can lose the permission on every rebuild.
5. Find Claude's bundle ID once: run osascript -e 'id of app "Claude"' in Terminal. The tap matches that ID and any helper IDs that start with it.
6. Audio routing. No changes needed. Keep your headphones as the output device; don't set up BlackHole unless you need the fallback.
Build phases
Phases 0–4 (the free v1): about 14–22 hours, or 2–3 focused days. Phases 5–6 add photoreal faces and the open-source release: about 3–5 more days. Claude Code writes the code; your time goes to granting permissions and testing with your ears and eyes. Finish each phase's check before starting the next.
Phase
What you get
Time
Done when
0. Setup
Tools installed, Claude voice mode confirmed
30 min
Voice mode works in headphones; bundle ID noted
1. Audio tap
Swift command-line tool streaming Claude's audio
3–5 h
A level meter moves only when Claude talks
2. Avatar page
Talking 3D face in Chrome
3–5 h
Mouth follows Claude's voice, page is silent
3. Window shell
Native Zoom-style tile with the tap built in
3–4 h
One app launches, connects, and animates
4. Polish
States, interruptions, controls, reliability
4–8 h
All acceptance tests pass
5. Photoreal + sync mode
Lifelike face from a GPU or cloud renderer, Claude's voice held back to match the lips
8–14 h
Lips and voice line up; interrupting still cuts both at once
6. Bring your own avatar
Renderer picker, GPU server image, open-source release
16–30 h
A new user gets the free 3D face by default and can switch renderers in Settings
Prompts to paste into Claude Code
Start Claude Code in an empty folder (for example ~/claude-avatar), paste this spec into a file named SPEC.md, then give one prompt per phase.
1. Phase 1: "Read SPEC.md. Build a Swift command-line tool claude-tap that uses Core Audio process taps (macOS 14.2+) to capture audio from all processes whose bundle ID starts with Claude's, down-mix to mono Float32 at 48 kHz, and send 20 ms binary frames over a WebSocket server on 127.0.0.1:8765. Print a live level meter in the terminal. Re-attach when Claude relaunches. Include an Info.plist with NSAudioCaptureUsageDescription and a build script that signs with my Apple ID team."
2. Phase 2: "Build web/index.html, a page that loads TalkingHead with a sample avatar, connects to ws://127.0.0.1:8765, pushes the frames through an AudioWorklet into HeadAudio, and drives the avatar's visemes. Route audio through a gain node at 0 so the page never makes sound. Show connection status in a corner. Serve it with a small Node dev server."
3. Phase 3: "Create a SwiftUI macOS app that merges claude-tap in-process and shows web/index.html in a WKWebView inside a borderless, rounded, always-on-top 360×270 window with a 'Claude' name label and status dot, like a Zoom tile. Add a menu-bar icon with show/hide and quit."
4. Phase 4: "Add: idle versus speaking states with a 400 ms silence timeout, mouth closes within 100 ms when audio stops, hover controls (pin, size S/M/L, hide face), avatar picker, mouth-sensitivity slider, launch at login, global hotkey ⌥⌘A, and auto-reconnect. Keep CPU under 15% while speaking."
5. Phase 5: "Read the 'Bring your own avatar' section of SPEC.md. Add a Renderer interface (pushAudio, stop, setState, latencyMs, attach to a video element) and make TalkingHead the first renderer. Add sync mode: set the Core Audio tap's mute behavior so Claude's original output is silenced while tapped, then play the captured audio to the current output device, delayed by the active renderer's measured latency. Flush audio and video within 100 ms when Claude stops. Add a Simli cloud renderer that uses the user's own API key, stored in the macOS Keychain."
6. Phase 6: "Build renderer-server/: a Docker image (Python, FastAPI, WebSocket audio in, WebRTC video out) that runs MuseTalk on an NVIDIA GPU, with a one-command start script for a home PC and a template for rented GPU hosts. Add a 'Remote GPU' renderer that connects by URL and token. Add a Settings pane to pick the renderer and choose a face image. Prepare the repo for open source: MIT license for our code, a README, model weights downloaded on first use with their licenses shown, and no research-only weights bundled."
Phase 5: Photoreal face with sync mode (4–8 h)
Replaces the 3D face with a lifelike video face and keeps lips and voice in step by delaying Claude's audio to match the video.
• Route: set Claude's output to BlackHole 2ch so it plays silently. The companion captures it, sends it to the photoreal renderer, and plays the audio to your headphones only when the matching video frames arrive.
• Renderer options: a cloud service (Simli or Anam, free tiers for testing) or a self-hosted open-source model (MuseTalk, Wav2Lip or LivePortrait) on an NVIDIA GPU, local or rented.
• Interface: plugs in behind the existing Renderer interface (pushAudio, stop, setState), so phases 1–4 stay unchanged.
• Interruptions: on stop(), flush both the delayed audio buffer and queued video frames at once.
• Done when: the voice and lips stay aligned within about 80 ms over 10 minutes, and interrupting Claude stops both within 150 ms.
Prompt: "Read SPEC.md Phase 5. Add a sync mode: capture Claude's audio from BlackHole, send it to a pluggable photoreal renderer behind the Renderer interface, and play the audio to my headphones delayed to match the returned video frames. Measure and display the current audio–video offset. Flush both buffers on interrupt."
Acceptance tests
Tick these off with headphones on and a real voice-mode conversation running.
[ ] Mouth moves when Claude speaks and stays closed when Claude is silent.
[ ] Playing music or a YouTube video does not move the mouth (only Claude's audio is captured).
[ ] You hear Claude exactly once, at normal volume, with no echo or doubling.
[ ] Mouth lag versus the voice looks natural (under about 150 ms) over a 10-minute conversation.
[ ] When you interrupt Claude, the mouth closes within 100 ms.
[ ] Avatar blinks and moves slightly while idle; it never freezes.
[ ] Quitting and reopening Claude reconnects within 5 seconds without restarting the companion.
[ ] Window stays above the Claude app and other windows, can be dragged and resized, and remembers its position.
[ ] Permission survives a rebuild and a Mac restart.
[ ] CPU stays under 15% while speaking and under 5% while idle (Activity Monitor).
Phases 5–6 checks
[ ] In sync mode you hear Claude once, through the companion, with lips and voice lined up to the eye.
[ ] Interrupting Claude stops the voice and the video together within 100 ms.
[ ] Switching renderers in Settings works without restarting the app.
[ ] A fresh install with no GPU and no keys runs the 3D face with zero setup.
[ ] The renderer server starts with one command on an NVIDIA PC and on a rented GPU.
[ ] No API key or token appears in any file in the repo or app folder.
Risks and limitations
The biggest risk is finding which Claude process actually plays the sound; plan to spend Phase 1 time there.
Risk
Effect
Mitigation
Claude's audio comes from an Electron helper process
Tap captures silence
Match every process whose bundle ID starts with Claude's; log PIDs that produce non-zero audio.
Process taps misbehave on your macOS version
No audio
Fall back to ScreenCaptureKit app audio, then BlackHole.
Mouth trails the voice slightly
Looks a little dubbed
Keep frames at 20 ms and the pipeline local. In v1 you hear Claude directly, so the face can't be delayed to match; Phase 5's sync mode fixes this.
A Claude app update changes processes or audio behavior
Companion stops animating
Bundle-ID prefix matching and auto-reconnect; re-run Phase 1 checks after updates.
Permission resets after rebuilds
Silent tap
Sign every build with the same Apple ID team.
Voice mode is beta
Behavior may change
Nothing in the companion depends on Claude's internals, only its sound.
Stylized 3D face, not a real person
Less lifelike
Intentional for v1: free, local, and forgiving of small timing errors. Photoreal comes in Phases 5–6.
What it will never do: see your screen, read your conversation text, or know what Claude is "doing" beyond what Claude says aloud.
Bring your own avatar (Phases 5–6)
The app ships with the free 3D face. Anyone can switch to a photoreal face on hardware or accounts they control, so the project never costs you anything to host.
Renderer
Where it runs
Who pays
Look
User setup
3D face (default)
Any Mac, inside the app
Nobody
Stylized
None
Home GPU
The user's own NVIDIA PC on the same network
Nobody beyond electricity
Photoreal
Run the renderer-server image, paste its URL
Rented GPU
The user's own account on a GPU host
The user, by the hour (often under $1/hour; check current rates)
Photoreal
Launch the template, paste URL and token
Cloud API
Simli, Anam or similar
The user's own key; free tiers cover tens of minutes a month
Photoreal
Paste an API key
How sync mode works
A photoreal face arrives 150–400 ms after the audio that drives it, so the app holds Claude's voice back to match.
1. The audio tap mutes Claude's original output while capturing it, using the Core Audio tap's mute setting, so you never hear Claude twice. Fallback: route Claude through BlackHole.
2. Each captured frame goes to the renderer and into a delay buffer at the same moment.
3. The app measures the renderer's latency (audio frame sent to matching video frame shown) and sizes the buffer to match.
4. The delayed audio plays to your headphones in step with the lips.
5. When Claude stops or you interrupt, the buffer and the video flush together within 100 ms.
Trade-off: Claude's replies reach you a fraction of a second later than with the 3D face. Sync mode stays off for the 3D face, which has no delay worth hiding.
Renderer contract
• Every renderer implements one interface: pushAudio(frame), stop(), setState(idle | speaking), latencyMs, and attach(videoElement).
• The renderer server takes 16 kHz mono audio over a WebSocket and returns video over WebRTC, behind a bearer token. The same Docker image runs on a home PC or a rented GPU.
• MuseTalk is the first server model. Others (LivePortrait, newer real-time models) plug in behind the same protocol.
Open-source release rules
• Your code ships under MIT. No hosted backend and no shared keys: every GPU or paid path uses the user's own account.
• Model weights download on first use, with their license shown. Some face models are research-only or non-commercial (for example, Wav2Lip's original weights and the InsightFace models LivePortrait relies on). Offer those as optional downloads, never bundled. MuseTalk's code is MIT; check each weight file it pulls.
• API keys and tokens live in the macOS Keychain, never in config files.
• Default faces are synthetic. Users can load their own photo, and the README asks them to use only faces they have the right to use.
• A signed, notarized download needs a paid Apple Developer account ($99/year). Without one, ship the source with build instructions.
Open source: bring your own avatar
The tool ships free and open source, with a free face by default and photoreal as an opt-in that each user powers themselves, so the project never pays to host anyone's GPU.
Renderer
Who it's for
Cost to the user
Setup
3D face (TalkingHead), default
Everyone, any Mac
Free
None, works out of the box
Photoreal, local
Users with an NVIDIA GPU
Free
Run the bundled MuseTalk server on their machine
Photoreal, rented GPU
Users without NVIDIA
Pay-as-you-go GPU rental
One-click template to launch the MuseTalk server on a GPU host, then paste its URL
Photoreal, cloud API
Users who want zero setup
Free tier, then the provider's pricing
Paste their own Simli or Anam API key
• Settings picker: a Renderer menu lists these four. Each option shows its cost and what it needs before the user picks it.
• Plugins: every renderer implements the same Renderer interface, so anyone can add a new model or service without touching the audio tap or window.
• Keys stay local: API keys and server URLs are stored in the macOS Keychain, never in the repo or sent anywhere except the chosen renderer.
• Licenses: check each bundled model's license before shipping. Some open-source face models allow research use only; those are offered as optional downloads, not bundled.
• Repo basics: MIT license, a README with a 2-minute quick start for the free face, and separate guides for each photoreal option.
