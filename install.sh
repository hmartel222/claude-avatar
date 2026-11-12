#!/bin/bash
# One-line installer:  curl -fsSL https://raw.githubusercontent.com/hmartel222/claude-avatar/main/install.sh | bash
set -euo pipefail
REPO_URL="${CLAUDE_AVATAR_REPO:-https://github.com/hmartel222/claude-avatar.git}"
DEST="${CLAUDE_AVATAR_HOME:-$HOME/.claude-avatar}"

[ "$(uname)" = Darwin ] || { echo "macOS only." >&2; exit 1; }
v=$(sw_vers -productVersion); major=${v%%.*}; minor=${v#*.}; minor=${minor%%.*}
if [ "$major" -lt 14 ] || { [ "$major" -eq 14 ] && [ "$minor" -lt 2 ]; }; then echo "Needs macOS 14.2+ (you have $v)." >&2; exit 1; fi
command -v swift >/dev/null || { echo "Install Xcode Command Line Tools first: xcode-select --install" >&2; exit 1; }
command -v node  >/dev/null || { echo "Install Node.js first: brew install node" >&2; exit 1; }

SELF="${BASH_SOURCE[0]:-}"
if [ -n "$SELF" ] && [ -f "$SELF" ] && [ -f "$(dirname "$SELF")/Package.swift" ]; then
  cd "$(dirname "$SELF")"
elif [ -d "$DEST/.git" ]; then
  git -C "$DEST" pull --ff-only; cd "$DEST"
else
  git clone --depth 1 "$REPO_URL" "$DEST"; cd "$DEST"
fi

./build-app.sh
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/ClaudeAvatar.app"
cp -R dist/ClaudeAvatar.app "$HOME/Applications/"
open "$HOME/Applications/ClaudeAvatar.app"

cat <<'GUIDE'

  ✅ Claude Avatar is installed and launching.

  HOW TO USE
    1. Put headphones on (otherwise the mic hears Claude and it interrupts itself).
    2. Open the Claude desktop app and start voice mode.
    3. The avatar tile floats on top of your windows; its face moves when Claude speaks.
    4. First launch: macOS asks for audio capture permission. Click Allow
       (System Settings > Privacy & Security > Screen & System Audio Recording).

  REOPEN IT LATER
    open ~/Applications/ClaudeAvatar.app        (or Spotlight: "ClaudeAvatar")
    Hotkey to show/hide the tile: Option+Command+A

  UPDATE
    Re-run the same install line.

  Optional: photoreal face via Simli. Add your own Simli API key in the app's settings.

GUIDE
