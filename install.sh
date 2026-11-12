#!/bin/bash
# One-line installer:  curl -fsSL https://raw.githubusercontent.com/OWNER/claude-avatar/main/install.sh | bash
set -euo pipefail
REPO_URL="${CLAUDE_AVATAR_REPO:-https://github.com/OWNER/claude-avatar.git}"
DEST="${CLAUDE_AVATAR_HOME:-$HOME/.claude-avatar}"

[ "$(uname)" = Darwin ] || { echo "macOS only." >&2; exit 1; }
v=$(sw_vers -productVersion); major=${v%%.*}; minor=${v#*.}; minor=${minor%%.*}
if [ "$major" -lt 14 ] || { [ "$major" -eq 14 ] && [ "$minor" -lt 2 ]; }; then echo "Needs macOS 14.2+ (you have $v)." >&2; exit 1; fi
command -v swift >/dev/null || { echo "Install Xcode Command Line Tools first: xcode-select --install" >&2; exit 1; }
command -v node  >/dev/null || { echo "Install Node.js first: brew install node" >&2; exit 1; }

if [ -f "$(dirname "$0")/Package.swift" ] 2>/dev/null; then
  cd "$(dirname "$0")"
elif [ -d "$DEST/.git" ]; then
  git -C "$DEST" pull --ff-only; cd "$DEST"
else
  git clone --depth 1 "$REPO_URL" "$DEST"; cd "$DEST"
fi

./build-app.sh
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/ClaudeAvatar.app"
cp -R dist/ClaudeAvatar.app "$HOME/Applications/"
echo "Installed to ~/Applications/ClaudeAvatar.app"
open "$HOME/Applications/ClaudeAvatar.app"
