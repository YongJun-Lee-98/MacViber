#!/bin/bash

# MultiTerm App Installer
# Installs the built app to /Applications
# Supports production and test builds

set -e

# Usage
usage() {
    echo "Usage: $0 [--test|-t]"
    echo ""
    echo "Options:"
    echo "  --test, -t    Install as test app ({test} MultiTerm.app)"
    echo "  -h, --help    Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0            Install as MultiTerm.app (production)"
    echo "  $0 --test     Install as {test} MultiTerm.app"
    exit 0
}

# Parse arguments
IS_TEST=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --test|-t)
            IS_TEST=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_BUNDLE="$PROJECT_DIR/build/MultiTerm.app"
INSTALL_DIR="/Applications"

# Set app name based on mode
if [ "$IS_TEST" = true ]; then
    INSTALL_NAME="{test} MultiTerm.app"
    MODE_LABEL="TEST"
else
    INSTALL_NAME="MultiTerm.app"
    MODE_LABEL="PRODUCTION"
fi

INSTALL_PATH="$INSTALL_DIR/$INSTALL_NAME"

echo "🔧 Install Mode: $MODE_LABEL"
echo ""

# Check if app bundle exists
if [ ! -d "$APP_BUNDLE" ]; then
    echo "❌ Error: MultiTerm.app not found at $APP_BUNDLE"
    echo "   Run ./Scripts/build-app.sh first"
    exit 1
fi

# Kill running app if exists
echo "🛑 Checking for running MultiTerm..."
if pgrep -x "MultiTerm" > /dev/null 2>&1; then
    echo "   Terminating running MultiTerm..."
    pkill -x "MultiTerm" || true
    sleep 1
fi

# Remove existing installation
if [ -d "$INSTALL_PATH" ]; then
    echo "🗑️  Removing existing installation..."
    rm -rf "$INSTALL_PATH"
fi

# Install
echo "📦 Installing $INSTALL_NAME to $INSTALL_DIR..."
cp -R "$APP_BUNDLE" "$INSTALL_PATH"

echo ""
echo "✅ $INSTALL_NAME installed successfully!"
echo ""
echo "You can now launch from:"
echo "  - Spotlight (Cmd+Space, type '${INSTALL_NAME%.app}')"
echo "  - Finder > Applications > $INSTALL_NAME"
echo "  - Terminal: open \"$INSTALL_PATH\""
