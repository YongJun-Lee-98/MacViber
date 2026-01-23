#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CORE_DIR="$PROJECT_ROOT/core"

BUILD_MODE="${1:-debug}"

echo "=== MacViber Build Script ==="
echo "Mode: $BUILD_MODE"
echo "Project: $PROJECT_ROOT"
echo ""

echo "[1/3] Building Rust core..."
cd "$CORE_DIR"

if [ "$BUILD_MODE" = "release" ]; then
    cargo build --release
    RUST_LIB="$CORE_DIR/target/release/libmacviber_core.a"
else
    cargo build
    RUST_LIB="$CORE_DIR/target/debug/libmacviber_core.a"
fi

if [ ! -f "$RUST_LIB" ]; then
    echo "Error: Rust library not found at $RUST_LIB"
    exit 1
fi

echo "Rust library: $RUST_LIB"
echo ""

echo "[2/3] Building Swift project..."
cd "$PROJECT_ROOT"

if [ "$BUILD_MODE" = "release" ]; then
    swift build -c release
else
    swift build
fi

echo ""
echo "[3/3] Build complete!"
echo ""

if [ "$BUILD_MODE" = "release" ]; then
    echo "Outputs:"
    echo "  - Rust: $RUST_LIB"
    echo "  - Swift: $PROJECT_ROOT/.build/release/MacViber"
else
    echo "Outputs:"
    echo "  - Rust: $RUST_LIB"
    echo "  - Swift: $PROJECT_ROOT/.build/debug/MacViber"
fi
