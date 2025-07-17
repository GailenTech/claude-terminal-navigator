#!/bin/bash
# Build script for Claude Navigator Swift app

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}Building Claude Navigator...${NC}"

# Clean previous builds
rm -rf .build
rm -rf ClaudeNavigator.app

# Build the executable
echo -e "${YELLOW}Compiling Swift code...${NC}"
swift build -c release

# Create app bundle structure
echo -e "${YELLOW}Creating app bundle...${NC}"
mkdir -p ClaudeNavigator.app/Contents/MacOS
mkdir -p ClaudeNavigator.app/Contents/Resources

# Copy executable
cp .build/release/ClaudeNavigator ClaudeNavigator.app/Contents/MacOS/

# Copy Info.plist
cp ClaudeNavigator/Info.plist ClaudeNavigator.app/Contents/

# Create a simple icon (we'll use text for now)
echo -e "${YELLOW}Creating icon...${NC}"
cat > ClaudeNavigator.app/Contents/Resources/AppIcon.icns <<'EOF'
Claude 🤖
EOF

# Set executable permissions
chmod +x ClaudeNavigator.app/Contents/MacOS/ClaudeNavigator

# Code sign (for local use)
echo -e "${YELLOW}Code signing...${NC}"
codesign --force --deep --sign - ClaudeNavigator.app

echo -e "${GREEN}✅ Build complete!${NC}"
echo ""
echo "To run the app:"
echo "  open ClaudeNavigator.app"
echo ""
echo "To install to Applications:"
echo "  cp -r ClaudeNavigator.app /Applications/"
echo ""
echo "To see console output while running:"
echo "  ./ClaudeNavigator.app/Contents/MacOS/ClaudeNavigator"