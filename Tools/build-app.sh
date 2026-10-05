#!/bin/zsh
set -eu
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH=/private/tmp/electromagnet-module-cache
export SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/electromagnet-module-cache
swift build --disable-sandbox -c release --scratch-path .build --cache-path /private/tmp/electromagnet-swift-cache --config-path /private/tmp/electromagnet-swift-config --security-path /private/tmp/electromagnet-swift-security -Xswiftc -module-cache-path -Xswiftc /private/tmp/electromagnet-module-cache
app_path="$PWD/dist/Electro Magnet.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp .build/release/ElectroMagnet "$app_path/Contents/MacOS/ElectroMagnet"
strip -S "$app_path/Contents/MacOS/ElectroMagnet"
if LC_ALL=C /usr/bin/grep -aEq '/(Users|home)/' "$app_path/Contents/MacOS/ElectroMagnet"; then
    print -u2 "Refusing to package an executable containing local home-directory paths."
    exit 1
fi
cp Assets/AppIcon/ElectroMagnet.icns "$app_path/Contents/Resources/ElectroMagnet.icns"
cat > "$app_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ElectroMagnet</string>
<key>CFBundleIdentifier</key><string>com.jeremyscott.ElectroMagnet</string>
<key>CFBundleName</key><string>Electro Magnet</string>
<key>CFBundleDisplayName</key><string>Electro Magnet</string>
<key>CFBundleIconFile</key><string>ElectroMagnet.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
xattr -dr com.apple.FinderInfo "$app_path" 2>/dev/null || true
codesign --force --sign - --identifier com.jeremyscott.ElectroMagnet "$app_path"
print "Built $app_path"
