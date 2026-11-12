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
pkill -x ClaudeAvatar 2>/dev/null && sleep 1 || true   # replace a running older copy
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/ClaudeAvatar.app"
cp -R dist/ClaudeAvatar.app "$HOME/Applications/"
open "$HOME/Applications/ClaudeAvatar.app"

cat <<'GUIDE'

  ✅ Claude Avatar is installed and running (look for the person icon in your menu bar).

  HOW IT WORKS
    The tile pops up by itself when Claude starts speaking, and tucks away
    after ~25 seconds of quiet. Just start voice mode in the Claude desktop app.
      1. Put headphones on (otherwise the mic hears Claude and it interrupts itself).
      2. Start voice mode in the Claude desktop app.
      3. First time only: allow audio capture when macOS asks
         (System Settings > Privacy & Security > Screen & System Audio Recording).

  IT STARTS AT LOGIN
    So the pop-up works without you launching anything. Turn it off in the
    menu-bar panel ("Launch at login"). Same panel: "Pop up when Claude speaks".

  OPEN IT MANUALLY
    open ~/Applications/ClaudeAvatar.app        (or Spotlight: "ClaudeAvatar")
    Show/hide the tile any time: Option+Command+A

  UPDATE
    Re-run the same install line.

  Optional: photoreal face via Simli. Add your own Simli API key in the menu-bar panel.

GUIDE
