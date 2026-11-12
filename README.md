# Claude Avatar Companion

A Zoom-style window that puts a lip-synced face on Claude's voice while you use voice mode in the Claude desktop app. It taps only the Claude app's audio output (Core Audio process tap), so you still hear Claude normally. Design details are in [SPEC.md](SPEC.md).

## Install and run (one line)

```sh
curl -fsSL https://raw.githubusercontent.com/hmartel222/claude-avatar/main/install.sh | bash
```

This builds from source, installs to `~/Applications/ClaudeAvatar.app`, and launches it. Re-run the same line to update.

Requires macOS 14.2+, Xcode Command Line Tools (`xcode-select --install`) and Node.js (`brew install node`).

Reopen later with `open ~/Applications/ClaudeAvatar.app`.

## Using it

1. Put headphones on, otherwise the mic picks up Claude's voice and it interrupts itself.
2. Start voice mode in the Claude desktop app.
3. The tile pops up by itself when Claude starts speaking and hides after ~25 s of quiet. The app lives in the menu bar and starts at login (both can be turned off in its panel). Show/hide manually with ⌥⌘A.
4. First launch only: approve **System Audio Recording** in System Settings → Privacy & Security.

The optional photoreal Simli renderer needs your own Simli API key, entered in the app and stored in your Keychain.

## Project layout

| Path | Contents |
| --- | --- |
| `Sources/` | Swift app: audio tap and window shell |
| `web/` | Avatar page (TalkingHead + HeadAudio) |
| `Resources/` | Info.plists |
| `install.sh`, `build-app.sh` | Installer and app builder |
