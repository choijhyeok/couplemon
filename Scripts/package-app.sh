#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"
version=${COUPLEMON_VERSION:-0.2.1}
build=${COUPLEMON_BUILD:-4}

swift build -c release
binary_dir=$(swift build -c release --show-bin-path)
app_dir="$project_dir/dist/CoupleMon.app"

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS"
cp "$binary_dir/CoupleMon" "$app_dir/Contents/MacOS/CoupleMon"

cat > "$app_dir/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>ko</string>
    <key>CFBundleExecutable</key><string>CoupleMon</string>
    <key>CFBundleIdentifier</key><string>com.couplemon.app</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>CoupleMon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>$build</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$app_dir"
echo "$app_dir"
