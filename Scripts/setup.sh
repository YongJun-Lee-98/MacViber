#!/bin/bash

# MultiTerm Setup Script
# Automatically checks dependencies and builds the project

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Configuration
REQUIRED_SWIFT_VERSION="5.9"
MIN_MACOS_VERSION="14.0"

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   MultiTerm Setup Script v1.0.0       ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Function: Print section header
print_section() {
    echo -e "${BLUE}▶ $1${NC}"
}

# Function: Print success message
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Function: Print warning message
print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Function: Print error message and exit
print_error() {
    echo -e "${RED}✗ Error: $1${NC}"
    exit 1
}

# Function: Compare version numbers
version_ge() {
    [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]
}

# Step 1: Check Swift installation
print_section "Checking Swift installation..."

if ! command -v swift &> /dev/null; then
    print_error "Swift is not installed. Please install Xcode or Swift toolchain."
fi

SWIFT_VERSION=$(swift --version | grep -oE '[0-9]+\.[0-9]+' | head -n1)
print_success "Swift $SWIFT_VERSION found"

if ! version_ge "$SWIFT_VERSION" "$REQUIRED_SWIFT_VERSION"; then
    print_error "Swift $REQUIRED_SWIFT_VERSION or later is required (found $SWIFT_VERSION)"
fi
print_success "Swift version meets minimum requirement ($REQUIRED_SWIFT_VERSION)"

# Step 2: Check macOS version
print_section "Checking macOS version..."

MACOS_VERSION=$(sw_vers -productVersion)
MACOS_MAJOR=$(echo "$MACOS_VERSION" | cut -d. -f1)

print_success "macOS $MACOS_VERSION detected"

if [ "$MACOS_MAJOR" -lt 14 ]; then
    print_warning "macOS 14.0 (Sonoma) or later is recommended (detected $MACOS_VERSION)"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

# Step 3: Check Xcode Command Line Tools
print_section "Checking Xcode Command Line Tools..."

if xcode-select -p &> /dev/null; then
    print_success "Xcode Command Line Tools installed"
else
    print_warning "Xcode Command Line Tools not found"
    echo "Installing Xcode Command Line Tools..."
    xcode-select --install

    echo "Waiting for installation to complete..."
    read -p "Press Enter after installation is complete..."
fi

# Step 4: Verify project structure
print_section "Verifying project structure..."

if [ ! -f "$PROJECT_DIR/Package.swift" ]; then
    print_error "Package.swift not found. Are you in the correct directory?"
fi
print_success "Package.swift found"

if [ ! -d "$PROJECT_DIR/MultiTerm" ]; then
    print_error "MultiTerm source directory not found"
fi
print_success "Source directory found"

if [ ! -d "$PROJECT_DIR/LocalPackages/SwiftTerm" ]; then
    print_error "SwiftTerm dependency not found at LocalPackages/SwiftTerm"
fi
print_success "SwiftTerm local package found"

# Step 5: Resolve dependencies
print_section "Resolving Swift package dependencies..."

cd "$PROJECT_DIR"

# Clear existing build if requested
if [ "$1" = "--clean" ] || [ "$1" = "-c" ]; then
    print_warning "Cleaning build artifacts..."
    rm -rf .build build
    print_success "Build directories cleaned"
fi

# Resolve dependencies
echo "Running: swift package resolve"
if swift package resolve; then
    print_success "Dependencies resolved successfully"
else
    print_error "Failed to resolve dependencies"
fi

# Show resolved dependencies
if [ -f "Package.resolved" ]; then
    echo ""
    echo "Resolved dependencies:"
    echo "────────────────────────────────────────"

    # Parse Package.resolved (simple grep approach)
    if grep -q "swift-argument-parser" Package.resolved; then
        VERSION=$(grep -A3 "swift-argument-parser" Package.resolved | grep "version" | sed 's/.*"\(.*\)".*/\1/')
        echo "  • swift-argument-parser: $VERSION"
    fi

    echo "  • SwiftTerm: Local Package"
    echo "────────────────────────────────────────"
fi

# Step 6: Build project
print_section "Building MultiTerm..."

# Ask user if they want to build now
echo ""
echo "Build options:"
echo "  1) Build debug version (swift build)"
echo "  2) Build release version (swift build -c release)"
echo "  3) Build app bundle (./Scripts/build-app.sh)"
echo "  4) Skip build"
echo ""
read -p "Select option [1-4]: " BUILD_OPTION

case $BUILD_OPTION in
    1)
        echo "Building debug version..."
        if swift build; then
            print_success "Debug build completed successfully"
            echo ""
            echo "Run with: swift run"
        else
            print_error "Build failed"
        fi
        ;;
    2)
        echo "Building release version..."
        if swift build -c release; then
            print_success "Release build completed successfully"
            echo ""
            echo "Binary location: .build/release/MultiTerm"
        else
            print_error "Build failed"
        fi
        ;;
    3)
        if [ -f "$SCRIPT_DIR/build-app.sh" ]; then
            echo "Building app bundle..."
            bash "$SCRIPT_DIR/build-app.sh"
        else
            print_error "build-app.sh not found"
        fi
        ;;
    4)
        print_warning "Skipping build"
        ;;
    *)
        print_warning "Invalid option, skipping build"
        ;;
esac

# Step 7: Final instructions
echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Setup completed successfully!       ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo "Next steps:"
echo "  • Run in debug mode:     swift run"
echo "  • Build release binary:  swift build -c release"
echo "  • Build app bundle:      ./Scripts/build-app.sh"
echo "  • Open in Xcode:         open Package.swift"
echo ""
echo "Documentation:"
echo "  • README.md              - User guide and features"
echo "  • DEVELOPMENT_GUIDE.md   - Developer documentation"
echo "  • docs/LICENSES.md       - Third-party licenses"
echo ""
echo "For issues and contributions, visit:"
echo "  https://github.com/your-username/MultiTerm"
echo ""
