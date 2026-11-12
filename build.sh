#!/bin/bash
# Build claude-tap and sign it with your Apple ID (Apple Development) identity.
# Override with: SIGN_IDENTITY="Apple Development: you@example.com (TEAMID)" ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

IDENTIFIER="com.harrisonmartel.claude-tap"

IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)
fi
if [ -z "$IDENTITY" ]; then
    echo "No 'Apple Development' signing identity found." >&2
    echo "Open Xcode > Settings > Accounts, add your Apple ID, and Manage Certificates > + Apple Development." >&2
    exit 1
fi
echo "Signing identity: $IDENTITY"

swift build -c release
mkdir -p dist
cp "$(swift build -c release --show-bin-path)/claude-tap" dist/claude-tap

codesign --force --sign "$IDENTITY" --identifier "$IDENTIFIER" --timestamp=none dist/claude-tap
codesign --verify --strict --verbose=2 dist/claude-tap
codesign -dvv dist/claude-tap 2>&1 | grep -E 'Identifier|Authority|TeamIdentifier|Info.plist' || true
echo "Built dist/claude-tap"
