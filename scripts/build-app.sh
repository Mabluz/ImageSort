#!/bin/bash
# Bygger ImageSort.app. Bruk:  scripts/build-app.sh            (bygger til build/)
#                              scripts/build-app.sh --install  (installerer i /Applications)
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/ImageSort.app"
echo "▸ Bygger (release) …"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/ImageSort"

echo "▸ Lager app-pakke …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ImageSort"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "▸ Lager ikon …"
TMP="$(mktemp -d)"
swift scripts/make-icon.swift "$TMP/icon.png"
ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$TMP/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$TMP"

echo "▸ Signerer lokalt (ad-hoc, ingen utviklerkonto nødvendig) …"
codesign --force --deep --sign - "$APP"

if [[ "${1:-}" == "--install" ]]; then
  echo "▸ Installerer i /Applications …"
  rm -rf /Applications/ImageSort.app
  cp -R "$APP" /Applications/
  echo "✓ Ferdig! Start ImageSort fra Programmer eller Spotlight."
else
  echo "✓ Ferdig: $APP  (kjør med --install for å legge den i /Applications)"
fi
