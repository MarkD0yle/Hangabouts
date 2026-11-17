#!/usr/bin/env bash
# Build Hangabouts in release mode and assemble app/build/Hangabouts.app.
# Works from any current directory.
set -euo pipefail

if [ "$(uname)" != "Darwin" ]; then
  echo "Hangabouts builds on macOS only." >&2
  exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
  echo "swift not found. Install the Xcode Command Line Tools: xcode-select --install" >&2
  exit 1
fi

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$APP_DIR"

echo "Building (release)…"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

BUNDLE="$APP_DIR/build/Hangabouts.app"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

cp "$BIN_DIR/Hangabouts" "$BUNDLE/Contents/MacOS/Hangabouts"
cp -R "$APP_DIR/Resources/." "$BUNDLE/Contents/Resources/"
cp "$APP_DIR/Info.plist" "$BUNDLE/Contents/Info.plist"

# Ad-hoc sign the whole bundle so macOS treats it as one consistent app.
codesign --force --sign - "$BUNDLE" >/dev/null 2>&1 || echo "Warning: ad-hoc codesign failed; the app should still run." >&2

echo
echo "Built: $BUNDLE"
echo "Run:   open \"$BUNDLE\""
