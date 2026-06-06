#!/bin/bash
set -e

echo "=== Building Sindri PDF App Bundle ==="

# Step 1: Create Icons
echo "Generating App Icons..."
swift icon_generator_sindri.swift
iconutil -c icns SindriPDF.iconset
rm -rf SindriPDF.iconset

# Step 2: Create Bundle Structure
echo "Structuring App Bundle..."
APP_DIR="Sindri PDF.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Step 3: Compile Binary
echo "Compiling Swift files..."
swiftc -O -target arm64-apple-macos14.0 Sources/*.swift -o "$APP_DIR/Contents/MacOS/Sindri PDF"

# Step 4: Copy Assets
cp SindriPDF.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
rm -f SindriPDF.icns

# Step 5: Write Info.plist
cat <<EOF > "$APP_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Sindri PDF</string>
    <key>CFBundleIdentifier</key>
    <string>com.jonas.SindriPDF</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Sindri PDF</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>PDF Document</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.adobe.pdf</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

echo "Sindri PDF.app successfully created!"
