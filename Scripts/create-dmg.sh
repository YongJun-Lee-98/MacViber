#!/bin/bash
set -e

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
INFO_PLIST="${PROJECT_ROOT}/MacViber/Resources/Info.plist"

APP_NAME="MacViber"
# Read version from Info.plist (source of truth), or use argument if provided
VERSION="${1:-$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")}"
BUILD_DIR="${PROJECT_ROOT}/build"
DMG_NAME="${APP_NAME}-v${VERSION}.dmg"
BACKGROUND="${SCRIPT_DIR}/dmg-resources/background.png"

echo "=========================================="
echo "  MacViber DMG Creator"
echo "=========================================="
echo ""

# Check if app exists
if [ ! -d "${BUILD_DIR}/${APP_NAME}.app" ]; then
    echo "Error: ${APP_NAME}.app not found in ${BUILD_DIR}"
    echo "Please run ./Scripts/build-app.sh first"
    exit 1
fi

echo "Creating DMG: ${DMG_NAME}"
echo "  Source: ${BUILD_DIR}/${APP_NAME}.app"
echo "  Output: ${BUILD_DIR}/${DMG_NAME}"
echo ""

# Remove existing DMG
rm -f "${BUILD_DIR}/${DMG_NAME}"

# Check if create-dmg is available
if command -v create-dmg &> /dev/null; then
    echo "Using create-dmg for styled installer..."

    # Use create-dmg for styled DMG
    create-dmg \
        --volname "${APP_NAME}" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "${APP_NAME}.app" 150 185 \
        --app-drop-link 450 185 \
        --hide-extension "${APP_NAME}.app" \
        --background "${BACKGROUND}" \
        "${BUILD_DIR}/${DMG_NAME}" \
        "${BUILD_DIR}/${APP_NAME}.app" \
        || true  # create-dmg returns non-zero even on success sometimes
else
    echo "create-dmg not found, using basic hdiutil..."

    # Fallback: Create temporary folder with app and Applications symlink
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf ${TEMP_DIR}" EXIT

    echo "Preparing DMG contents..."
    cp -R "${BUILD_DIR}/${APP_NAME}.app" "${TEMP_DIR}/"
    ln -s /Applications "${TEMP_DIR}/Applications"

    # Create DMG
    hdiutil create \
        -volname "${APP_NAME}" \
        -srcfolder "${TEMP_DIR}" \
        -ov \
        -format UDZO \
        "${BUILD_DIR}/${DMG_NAME}"
fi

echo ""
echo "=========================================="
echo "  DMG created successfully!"
echo "=========================================="
echo ""
echo "Output: ${BUILD_DIR}/${DMG_NAME}"
echo ""
echo "File size: $(du -h "${BUILD_DIR}/${DMG_NAME}" | cut -f1)"
echo ""
