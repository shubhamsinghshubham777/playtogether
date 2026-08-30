#!/bin/zsh
# Instance B launcher for the R-2 two-instance manual test.
# Clones the debug SyncTogether.app under a different bundle ID so it gets its
# own preferences domain (= its own Supabase session / guest identity), then
# launches it with logs teed to /tmp/pt-b.log. The bundle ID is what does the
# isolating — that was the sandbox container before the app left the sandbox, and
# is NSUserDefaults keying off CFBundleIdentifier now; either way it is where
# supabase_flutter's persisted session lives.
#
# Usage:  ./scripts/pt-instance-b.sh        (instance A = normal `fvm flutter run -d macos`)
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO/build/macos/Build/Products/Debug/SyncTogether.app"
DEST_DIR="$REPO/build/st-instance-b"
DEST="$DEST_DIR/SyncTogether B.app"

if [[ ! -d "$SRC" ]]; then
  echo "No debug build at $SRC — run: fvm flutter build macos --debug" >&2
  exit 1
fi

echo "Cloning $SRC -> $DEST"
rm -rf "$DEST_DIR" && mkdir -p "$DEST_DIR"
cp -R "$SRC" "$DEST"

PLIST="$DEST/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier app.synctogether.macos.b" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleName SyncTogether B" "$PLIST"

echo "Re-signing (ad-hoc)…"
codesign --force --deep --sign - \
  --entitlements "$REPO/macos/Runner/DebugProfile.entitlements" \
  "$DEST" 2>/dev/null

echo "Launching instance B (log: /tmp/st-b.log)…"
"$DEST/Contents/MacOS/SyncTogether" 2>&1 | tee /tmp/st-b.log
