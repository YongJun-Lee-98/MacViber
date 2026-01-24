#!/bin/bash

# MacViber App Bundle Builder
# Creates a proper macOS .app bundle
#
# Usage:
#   ./build-app.sh              # Build with current version
#   ./build-app.sh patch        # Bump patch version (1.2.3 -> 1.2.4) - for bug fixes
#   ./build-app.sh minor        # Bump minor version (1.2.3 -> 1.3.0) - for new features
#   ./build-app.sh major        # Bump major version (1.2.3 -> 2.0.0) - for major updates
#   ./build-app.sh 1.5.0        # Set specific version

set -e

# Configuration
APP_NAME="MacViber"
BUNDLE_ID="com.macviber.app"

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
INFO_PLIST="$PROJECT_DIR/MacViber/Resources/Info.plist"

# Read current version from Info.plist
CURRENT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST")

# Parse version components
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

# Handle version bump argument
case "$1" in
    major)
        # Major update (a.b.c -> a+1.0.0)
        MAJOR=$((MAJOR + 1))
        MINOR=0
        PATCH=0
        echo "🔼 Bumping MAJOR version (large-scale update)"
        ;;
    minor)
        # Minor update (a.b.c -> a.b+1.0)
        MINOR=$((MINOR + 1))
        PATCH=0
        echo "🔼 Bumping MINOR version (feature update)"
        ;;
    patch)
        # Patch update (a.b.c -> a.b.c+1)
        PATCH=$((PATCH + 1))
        echo "🔼 Bumping PATCH version (bug fix)"
        ;;
    "")
        # No argument, use current version
        echo "📋 Using current version"
        ;;
    *)
        # Specific version provided (e.g., 1.5.0)
        if [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            IFS='.' read -r MAJOR MINOR PATCH <<< "$1"
            echo "📋 Setting specific version: $1"
        else
            echo "❌ Invalid version format. Use: major, minor, patch, or X.Y.Z"
            exit 1
        fi
        ;;
esac

VERSION="${MAJOR}.${MINOR}.${PATCH}"
BUILD_NUMBER=$((BUILD_NUMBER + 1))

# Update Info.plist with new version
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$INFO_PLIST"

echo "📋 Version: $VERSION (Build $BUILD_NUMBER)"

# Build paths
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_BUNDLE="$PROJECT_DIR/build/${APP_NAME}.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"

# Rust paths
RUST_DIR="$PROJECT_DIR/core"
RUST_TARGET_DIR="$RUST_DIR/target/release"
RUST_DYLIB="libmacviber_core.dylib"

# Kill running app if exists
echo "🛑 Checking for running $APP_NAME..."
if pgrep -x "$APP_NAME" > /dev/null 2>&1; then
    echo "   Terminating running $APP_NAME..."
    pkill -x "$APP_NAME" || true
    sleep 1
fi

# Clear caches
echo "🧹 Clearing caches..."
# Force remove with retry for locked files
rm -rf "$PROJECT_DIR/.build" 2>/dev/null || (sleep 1 && rm -rf "$PROJECT_DIR/.build" 2>/dev/null) || true
rm -rf "$PROJECT_DIR/build" 2>/dev/null || true
rm -rf ~/Library/Caches/com.macviber.app 2>/dev/null || true

echo "🔨 Building Rust core..."
cd "$RUST_DIR"
cargo build --release
if [ $? -ne 0 ]; then
    echo "❌ Rust build failed"
    exit 1
fi
echo "✅ Rust core built successfully"

echo "🔨 Building $APP_NAME..."

mkdir -p "$PROJECT_DIR/build"

cd "$PROJECT_DIR"
swift build -c release

echo "📦 Creating app bundle..."

mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$FRAMEWORKS_DIR"

cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/"

if [ -f "$RUST_TARGET_DIR/$RUST_DYLIB" ]; then
    echo "📦 Copying Rust dylib to Frameworks..."
    cp "$RUST_TARGET_DIR/$RUST_DYLIB" "$FRAMEWORKS_DIR/"
    
    install_name_tool -id "@executable_path/../Frameworks/$RUST_DYLIB" "$FRAMEWORKS_DIR/$RUST_DYLIB"
    echo "✅ Rust dylib embedded in app bundle"
else
    echo "⚠️  Rust dylib not found at $RUST_TARGET_DIR/$RUST_DYLIB"
fi

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
