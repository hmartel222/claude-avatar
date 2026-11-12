# Claude Avatar Companion

A small always-on-top tile with an avatar that lip-syncs to Claude's voice mode in the Claude desktop app. It taps only the Claude app's audio output (Core Audio process tap); you still hear Claude normally. See `SPEC.md` for the design.

## Install (one line)

```sh
curl -fsSL https://raw.githubusercontent.com/OWNER/claude-avatar/main/install.sh | bash
```

Or from a clone: `./install.sh`

Requires macOS 14.2+, Xcode Command Line Tools (`xcode-select --install`) and Node.js (`brew install node`). It builds from source, installs to `~/Applications/ClaudeAvatar.app`, and launches it. Re-run to update. Grant the audio-capture permission when macOS asks.

Optional: the photoreal Simli renderer needs your own Simli API key, entered in the app and stored in your Keychain.
