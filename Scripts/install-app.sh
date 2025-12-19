#!/bin/bash

# MultiTerm App Installer
# Installs the built app to /Applications

set -e

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_BUNDLE="$PROJECT_DIR/build/MultiTerm.app"
INSTALL_DIR="/Applications"

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
if [ -d "$INSTALL_DIR/MultiTerm.app" ]; then
    echo "🗑️  Removing existing installation..."
    rm -rf "$INSTALL_DIR/MultiTerm.app"
fi

# Install
echo "📦 Installing MultiTerm.app to $INSTALL_DIR..."
cp -R "$APP_BUNDLE" "$INSTALL_DIR/"

echo "✅ MultiTerm.app installed successfully!"
echo ""
echo "You can now launch MultiTerm from:"
echo "  - Spotlight (Cmd+Space, type 'MultiTerm')"
echo "  - Finder > Applications > MultiTerm"
echo "  - Terminal: open /Applications/MultiTerm.app"
