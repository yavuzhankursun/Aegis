#!/bin/bash
# Aegis.app paketini üretir: derle → bundle → simge → imzala.
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$PWD"
APP="$ROOT/build/Aegis.app"
CONFIG="${1:-release}"

echo "==> Derleniyor ($CONFIG)"
# AEGIS_SWIFT_FLAGS: swift build'e ek bayraklar. Homebrew gibi zaten sandbox
# içinde koşan ortamlar SwiftPM'in kendi sandbox'ını açamaz (sandbox_apply
# reddedilir); formül buraya --disable-sandbox geçirir. Kelime bölünmesi kasıtlı.
# shellcheck disable=SC2086
swift build -c "$CONFIG" ${AEGIS_SWIFT_FLAGS:-}
# shellcheck disable=SC2086
BIN="$(swift build -c "$CONFIG" ${AEGIS_SWIFT_FLAGS:-} --show-bin-path)/Aegis"
[ -x "$BIN" ] || { echo "Yürütülebilir bulunamadı: $BIN"; exit 1; }

echo "==> Paket oluşturuluyor"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Aegis"

echo "==> Simge üretiliyor"
ICONSET="$ROOT/build/Aegis.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
swift Tools/makeicon.swift "$ROOT/build/icon_1024.png" >/dev/null

for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" \
            "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" \
            "512 512x512" "1024 512x512@2x"; do
  set -- $spec
  sips -z "$1" "$1" "$ROOT/build/icon_1024.png" --out "$ICONSET/icon_$2.png" >/dev/null 2>&1
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Aegis.icns"

echo "==> Info.plist yazılıyor"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Aegis</string>
  <key>CFBundleDisplayName</key><string>Aegis</string>
  <key>CFBundleIdentifier</key><string>io.github.yavuzhankursun.aegis</string>
  <key>CFBundleExecutable</key><string>Aegis</string>
  <key>CFBundleIconFile</key><string>Aegis</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Yavuzhan Kurşun. MIT License.</string>
  <key>NSDesktopFolderUsageDescription</key><string>Masaüstü klasörünün boyutunu hesaplamak için.</string>
  <key>NSDocumentsFolderUsageDescription</key><string>Belgeler klasörünün boyutunu hesaplamak için.</string>
  <key>NSDownloadsFolderUsageDescription</key><string>İndirilenler klasöründe eski dosyaları bulmak için.</string>
  <key>NSRemovableVolumesUsageDescription</key><string>Harici disklerin doluluk oranını göstermek için.</string>
</dict>
</plist>
PLIST

echo "==> İmzalanıyor (ad-hoc)"
codesign --force --deep --sign - --identifier io.github.yavuzhankursun.aegis "$APP"
codesign --verify --verbose=1 "$APP" 2>&1 | tail -2

echo
echo "Hazır: $APP"
