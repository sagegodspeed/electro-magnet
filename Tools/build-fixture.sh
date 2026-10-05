#!/bin/zsh
set -eu
cd "${0:A:h:h}"
fixture_path="$PWD/dist/Electro Magnet Test Windows.app"
mkdir -p "$fixture_path/Contents/MacOS"
swiftc -target arm64-apple-macosx14.0 -module-cache-path /private/tmp/electromagnet-module-cache Tools/TestWindows.swift -o "$fixture_path/Contents/MacOS/TestWindows"
cat > "$fixture_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TestWindows</string>
<key>CFBundleIdentifier</key><string>com.jeremyscott.ElectroMagnet.Fixture</string>
<key>CFBundleName</key><string>Electro Magnet Test Windows</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST
xattr -dr com.apple.FinderInfo "$fixture_path" 2>/dev/null || true
codesign --force --sign - "$fixture_path"
