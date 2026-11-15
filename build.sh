#!/bin/sh
# Builds disfreetext.app in this folder. Drag it to /Applications if you like.
set -e
cd "$(dirname "$0")"

# Make the icon once (delete Resources/AppIcon.icns to redraw it).
if [ ! -f Resources/AppIcon.icns ]; then
    mkdir -p Resources
    swift icon/make_icon.swift .build/AppIcon.iconset
    iconutil -c icns .build/AppIcon.iconset -o Resources/AppIcon.icns
fi

swift build -c release

APP=disfreetext.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/disfreetext "$APP/Contents/MacOS/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>disfreetext</string>
    <key>CFBundleIdentifier</key><string>local.disfreetext</string>
    <key>CFBundleName</key><string>disfreetext</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"
echo "Built $APP"
