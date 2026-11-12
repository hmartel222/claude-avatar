#!/bin/bash
# Build dist/ClaudeAvatar.app (window + in-process audio tap + bundled web page) and sign it
# with your Apple Development identity. Override: SIGN_IDENTITY="Apple Development: ... (TEAMID)"
set -euo pipefail
cd "$(dirname "$0")"

APP="dist/ClaudeAvatar.app"
IDENTIFIER="com.harrisonmartel.claude-avatar"

IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)
fi
if [ -z "$IDENTITY" ]; then
    IDENTITY="-"   # ad-hoc signing: works for local use, no Apple ID needed
    echo "No Apple Development identity found; signing ad-hoc."
else
    echo "Signing identity: $IDENTITY"
fi

if [ ! -d web/node_modules ]; then (cd web && npm ci --no-audit --no-fund); fi

# Simli's SDK has bare imports; bundle it into one file the page can load.
(cd web && npx esbuild renderers/simli-entry.js --bundle --format=esm --platform=browser --minify --outfile=vendor/simli.js --log-level=warning)

swift build -c release --product ClaudeAvatar
BIN="$(swift build -c release --show-bin-path)/ClaudeAvatar"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/web"
cp "$BIN" "$APP/Contents/MacOS/ClaudeAvatar"
cp Resources/App-Info.plist "$APP/Contents/Info.plist"

# Only what the page needs at runtime (no npm metadata, no Node).
W="$APP/Contents/Resources/web"
M=web/node_modules/@met4citizen
cp web/index.html web/pcm-player.js web/stage.js "$W/"
mkdir -p "$W/renderers" "$W/vendor"
cp -R web/backdrops "$W/backdrops"
cp -R web/vendor/mediapipe "$W/vendor/mediapipe"
MP=web/node_modules/@mediapipe/tasks-vision
mkdir -p "$W/node_modules/@mediapipe/tasks-vision/wasm"
cp "$MP/vision_bundle.mjs" "$W/node_modules/@mediapipe/tasks-vision/"
cp "$MP"/wasm/vision_wasm_internal.* "$W/node_modules/@mediapipe/tasks-vision/wasm/"
cp web/renderers/simli.js "$W/renderers/"
cp web/vendor/simli.js "$W/vendor/"
cp -R web/avatars "$W/avatars"
mkdir -p "$W/node_modules/@met4citizen/talkinghead" "$W/node_modules/@met4citizen/headaudio"
cp -R "$M/talkinghead/modules" "$W/node_modules/@met4citizen/talkinghead/modules"
mkdir -p "$W/node_modules/@met4citizen/talkinghead/node_modules/three"
cp -R "$M/talkinghead/node_modules/three/build" "$M/talkinghead/node_modules/three/examples" \
      "$W/node_modules/@met4citizen/talkinghead/node_modules/three/"
rm -rf "$W/node_modules/@met4citizen/talkinghead/node_modules/three/examples/"{textures,models,fonts} 2>/dev/null || true
cp -R "$M/headaudio/dist" "$W/node_modules/@met4citizen/headaudio/dist"

codesign --force --sign "$IDENTITY" --identifier "$IDENTIFIER" --timestamp=none "$APP"
codesign --verify --strict --verbose=2 "$APP"
codesign -dvv "$APP" 2>&1 | grep -E 'Identifier|Authority=Apple Dev|TeamIdentifier' || true
echo "Built $APP ($(du -sh "$APP" | cut -f1))"
