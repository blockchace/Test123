#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo "La app se compila en macOS 13 o posterior con Xcode Command Line Tools." >&2
  exit 1
fi
command -v swift >/dev/null || { echo 'Instala las herramientas con: xcode-select --install' >&2; exit 1; }
command -v python3 >/dev/null || { echo 'Se requiere Python 3 para empaquetar las bibliotecas.' >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo 'Instala FFmpeg con: brew install ffmpeg' >&2; exit 1; }
ffmpeg -hide_banner -encoders 2>/dev/null | grep libmp3lame >/dev/null || { echo 'FFmpeg necesita el codificador libmp3lame.' >&2; exit 1; }
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="dist/Aire Audio.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin" "$APP/Contents/Frameworks"
cp "$BIN_DIR/AireAudio" "$APP/Contents/MacOS/AireAudio"
ICONSET="$(mktemp -d dist/icon.XXXXXX).iconset"
mkdir -p "$ICONSET"
swift scripts/make-icon.swift "$ICONSET/icon_512x512@2x.png"
for SIZE in 16 32 128 256 512; do
  sips -z "$SIZE" "$SIZE" "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  if [[ "$SIZE" != 512 ]]; then
    DOUBLE=$((SIZE * 2))
    sips -z "$DOUBLE" "$DOUBLE" "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
  fi
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET" "${ICONSET%.iconset}"
python3 scripts/bundle-ffmpeg.py "$(command -v ffmpeg)" "$APP"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>AireAudio</string>
<key>CFBundleIdentifier</key><string>app.aireaudio.recorder</string>
<key>CFBundleName</key><string>Aire Audio</string>
<key>CFBundleDisplayName</key><string>Aire Audio</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.1.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSMicrophoneUsageDescription</key><string>Aire Audio necesita el micrófono para grabar tu voz cuando eliges Micrófono o Sistema + micrófono.</string>
<key>NSScreenCaptureUsageDescription</key><string>Aire Audio necesita acceso a la captura del sistema para grabar el sonido de las aplicaciones. No guarda vídeo.</string>
</dict></plist>
PLIST
plutil -lint "$APP/Contents/Info.plist"
# A developer signing identity can be supplied for distribution.
SIGN_IDENTITY="${AIRE_SIGN_IDENTITY:--}"
find "$APP/Contents/Frameworks" -type f -name '*.dylib' -print0 | while IFS= read -r -d '' file; do
  codesign --force --sign "$SIGN_IDENTITY" "$file"
done
codesign --force --sign "$SIGN_IDENTITY" "$APP/Contents/Resources/bin/ffmpeg"
codesign --force --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
"$APP/Contents/Resources/bin/ffmpeg" -hide_banner -loglevel error -f lavfi -i 'sine=frequency=440:duration=1' -codec:a libmp3lame -y dist/encoder-check.mp3
test -s dist/encoder-check.mp3
rm dist/encoder-check.mp3
STAGING="$(mktemp -d dist/dmg-staging.XXXXXX)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -ov -volname 'Aire Audio' -srcfolder "$STAGING" -format UDZO 'dist/Aire Audio.dmg'
echo 'Creado: dist/Aire Audio.dmg. Ábrelo y arrastra Aire Audio a Aplicaciones.'
