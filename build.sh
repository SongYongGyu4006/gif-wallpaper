#!/bin/zsh
# 움짤배경.app 빌드
set -e
cd "$(dirname "$0")"

APP="움짤배경.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -o "$APP/Contents/MacOS/GifWallpaper" GifWallpaper.swift

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>움짤배경</string>
  <key>CFBundleDisplayName</key><string>움짤배경</string>
  <key>CFBundleIdentifier</key><string>local.gifwallpaper</string>
  <key>CFBundleExecutable</key><string>GifWallpaper</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"
echo "완료: $(pwd)/$APP"
