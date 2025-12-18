#!/bin/bash

# MultiTerm App Bundle Builder
# Creates a proper macOS .app bundle

set -e

# Configuration
APP_NAME="MultiTerm"
BUNDLE_ID="com.multiterm.app"
VERSION="1.0.0"
BUILD_NUMBER="1"

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_BUNDLE="$PROJECT_DIR/build/${APP_NAME}.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Kill running app if exists
echo "🛑 Checking for running $APP_NAME..."
if pgrep -x "$APP_NAME" > /dev/null 2>&1; then
    echo "   Terminating running $APP_NAME..."
    pkill -x "$APP_NAME" || true
    sleep 1
fi

# Clear caches
echo "🧹 Clearing caches..."
rm -rf "$PROJECT_DIR/.build"
rm -rf "$PROJECT_DIR/build"
rm -rf ~/Library/Caches/com.multiterm.app 2>/dev/null || true

echo "🔨 Building $APP_NAME..."

# Create build directory
mkdir -p "$PROJECT_DIR/build"

# Build release binary
cd "$PROJECT_DIR"
swift build -c release

echo "📦 Creating app bundle..."

# Create bundle structure
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy executable
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/"

# Create Info.plist
cat > "$CONTENTS_DIR/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
    <key>LSUIElement</key>
    <false/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSUserNotificationAlertStyle</key>
    <string>alert</string>
</dict>
</plist>
EOF

# Create PkgInfo
echo -n "APPL????" > "$CONTENTS_DIR/PkgInfo"

# Create app icon from icon.png
ICON_SOURCE="$PROJECT_DIR/icon.png"
if [ -f "$ICON_SOURCE" ]; then
    echo "🎨 Creating app icon from icon.png..."

    ICONSET_DIR="$PROJECT_DIR/build/AppIcon.iconset"
    mkdir -p "$ICONSET_DIR"

    # Generate all required icon sizes
    sips -z 16 16     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" > /dev/null 2>&1
    sips -z 32 32     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" > /dev/null 2>&1
    sips -z 32 32     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" > /dev/null 2>&1
    sips -z 64 64     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" > /dev/null 2>&1
    sips -z 128 128   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" > /dev/null 2>&1
    sips -z 256 256   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" > /dev/null 2>&1
    sips -z 256 256   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" > /dev/null 2>&1
    sips -z 512 512   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" > /dev/null 2>&1
    sips -z 512 512   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" > /dev/null 2>&1
    sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" > /dev/null 2>&1

    # Convert iconset to icns
    iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"

    # Cleanup
    rm -rf "$ICONSET_DIR"

    echo "✅ App icon created successfully"
else
    echo "⚠️  icon.png not found, skipping icon creation"
fi

echo "✅ App bundle created at: $APP_BUNDLE"

# Launch the app
echo "🚀 Launching $APP_NAME..."
open "$APP_BUNDLE"

echo ""
echo "To install to Applications:"
echo "  cp -R \"$APP_BUNDLE\" /Applications/"
