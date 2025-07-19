#!/bin/bash

# Simple DMG Creator for Claude Terminal Navigator
# Creates a professional DMG without Python dependencies

set -e

APP_NAME="ClaudeNavigator"
DMG_NAME="Claude-Terminal-Navigator-Installer"
VERSION="1.2.0"
SOURCE_APP="ClaudeNavigator.app"
FINAL_DMG_NAME="${DMG_NAME}-${VERSION}.dmg"

# Clean up any existing DMG files
rm -rf "${FINAL_DMG_NAME}"

echo "🚀 Creating DMG installer for ${APP_NAME} v${VERSION}..."

# Check if app exists
if [ ! -d "${SOURCE_APP}" ]; then
    echo "❌ Error: ${SOURCE_APP} not found!"
    echo "Please build the app first"
    exit 1
fi

# Create the DMG using create-dmg with minimal options
echo "📦 Creating DMG with create-dmg..."

create-dmg \
  --volname "${APP_NAME} ${VERSION}" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 128 \
  --icon "${SOURCE_APP}" 150 170 \
  --hide-extension "${SOURCE_APP}" \
  --app-drop-link 450 170 \
  --text-size 16 \
  --no-internet-enable \
  "${FINAL_DMG_NAME}" \
  "${SOURCE_APP}"

# Check if DMG was created successfully
if [ -f "${FINAL_DMG_NAME}" ]; then
    echo "🎉 DMG installer created successfully!"
    echo "📦 File: ${FINAL_DMG_NAME}"
    echo "📊 Size: $(du -h "${FINAL_DMG_NAME}" | cut -f1)"
    
    # Show file info
    ls -la "${FINAL_DMG_NAME}"
    
    echo ""
    echo "✅ DMG is ready for distribution!"
    echo "Users can:"
    echo "  1. Double-click the DMG to mount it"
    echo "  2. Drag ClaudeNavigator to Applications folder"
    echo "  3. Eject the DMG"
    echo "  4. Launch ClaudeNavigator from Applications"
else
    echo "❌ Failed to create DMG!"
    exit 1
fi