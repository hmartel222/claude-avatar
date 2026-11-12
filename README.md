# Claude Avatar Companion

A Zoom-style window that puts a lip-synced face on Claude's voice while you use voice mode in the Claude desktop app. The full design is in [SPEC.md](SPEC.md).

## Open it from any terminal

Add these two shell functions to `~/.zshrc` once, then run `source ~/.zshrc` (or open a new terminal):

```zsh
# Launch the avatar window from anywhere
avatar() {
  local app
  app=$(ls -d ~/avatar/dist/*.app 2>/dev/null | head -1)
  if [ -n "$app" ]; then
    open "$app"
  else
    echo "No built app in ~/avatar/dist, running from source instead..."
    swift run --package-path ~/avatar
  fi
}

# Reopen the Claude Code session that is building this project
avatar-dev() {
  cd ~/avatar && claude --resume 08c88314-7847-4fe7-8a52-9f54e8a38199
}
```

After that, from any terminal window, in any folder:

| Command | What it does |
| --- | --- |
| `avatar` | Opens the companion window (the built app in `~/avatar/dist`, or builds and runs from source if there isn't one) |
| `avatar-dev` | Resumes the Claude Code build session |

### Without the shortcuts

```zsh
open ~/avatar/dist/*.app                                               # launch the companion
cd ~/avatar && claude --resume 08c88314-7847-4fe7-8a52-9f54e8a38199    # resume the build session
```

**Why the `cd`:** Claude Code keeps sessions per project folder, so `--resume` only finds this session when you run it from the folder where the session started. If you get "No conversation found", run `claude --resume` with no ID from the right folder and pick the session from the list.

**If `swift run` asks which product to run,** add `--product <name>`, using the executable name listed in `Package.swift`.

## Using it

1. Put headphones on. Without them, the mic picks up Claude's voice and Claude interrupts itself.
2. Open the Claude desktop app and start voice mode.
3. Run `avatar`. The face starts moving when Claude speaks.
4. First launch only: approve **System Audio Recording** in System Settings → Privacy & Security → Screen & System Audio Recording.

## Project layout

| Path | Contents |
| --- | --- |
| `Sources/` | Swift app: audio tap and window shell |
| `web/` | Avatar page (TalkingHead + HeadAudio) |
| `Resources/` | App resources and avatar files |
| `dist/` | Built app |
| `SPEC.md` | Build spec: architecture, phases 0–6, acceptance tests |
