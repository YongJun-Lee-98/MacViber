#!/bin/bash
set -e

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

APP_NAME="MacViber"
VERSION="${1:-1.0.0}"
BUILD_DIR="${PROJECT_ROOT}/build"
DMG_NAME="${APP_NAME}-v${VERSION}.dmg"

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

# Create DMG
hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${BUILD_DIR}/${APP_NAME}.app" \
    -ov \
    -format UDZO \
    "${BUILD_DIR}/${DMG_NAME}"

echo ""
echo "=========================================="
echo "  DMG created successfully!"
echo "=========================================="
echo ""
echo "Output: ${BUILD_DIR}/${DMG_NAME}"
echo ""
echo "File size: $(du -h "${BUILD_DIR}/${DMG_NAME}" | cut -f1)"
echo ""
