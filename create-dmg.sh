#!/bin/bash

# Claude Terminal Navigator DMG Creator
# Creates a professional macOS installer with drag-and-drop interface

set -e

APP_NAME="ClaudeNavigator"
DMG_NAME="Claude-Terminal-Navigator-Installer"
VERSION="1.3.0"
SOURCE_APP="ClaudeNavigator.app"
TEMP_DMG_NAME="temp_${DMG_NAME}"
FINAL_DMG_NAME="${DMG_NAME}-${VERSION}.dmg"

# Clean up any existing temp files
rm -rf "${TEMP_DMG_NAME}.dmg" "${FINAL_DMG_NAME}"

echo "🚀 Creating DMG installer for ${APP_NAME} v${VERSION}..."

# Check if app exists
if [ ! -d "${SOURCE_APP}" ]; then
    echo "❌ Error: ${SOURCE_APP} not found!"
    echo "Please build the app first with: swift build"
    exit 1
fi

# Create a temporary directory for DMG contents
TEMP_DIR=$(mktemp -d)
echo "📁 Using temporary directory: ${TEMP_DIR}"

# Copy the app to temp directory
echo "📦 Copying app to DMG staging area..."
cp -R "${SOURCE_APP}" "${TEMP_DIR}/"

# Create Applications symlink
echo "🔗 Creating Applications symlink..."
ln -s /Applications "${TEMP_DIR}/Applications"

# Create a temporary DMG
echo "💾 Creating temporary DMG..."
hdiutil create -srcfolder "${TEMP_DIR}" -volname "${APP_NAME} ${VERSION}" -fs HFS+ -fsargs "-c c=64,a=16,e=16" -format UDRW -size 100m "${TEMP_DMG_NAME}.dmg"

# Mount the temporary DMG
echo "🔧 Mounting DMG for customization..."
MOUNT_DIR=$(mktemp -d)
hdiutil attach "${TEMP_DMG_NAME}.dmg" -readwrite -noverify -noautoopen -mountpoint "${MOUNT_DIR}"

# Wait a moment for the mount to complete
sleep 2

# Create .DS_Store to customize the view
echo "🎨 Creating custom view settings..."
cat > "${MOUNT_DIR}/.DS_Store_template" << 'EOF'
# This would contain view settings, but we'll use a simpler approach
EOF

# Set basic properties using SetFile if available
if command -v SetFile &> /dev/null; then
    echo "📁 Setting folder properties..."
    SetFile -a V "${MOUNT_DIR}"
fi

echo "✅ DMG customization complete"

# Unmount the DMG
echo "📤 Unmounting DMG..."
hdiutil detach "${MOUNT_DIR}"

# Convert to final read-only DMG
echo "✅ Converting to final DMG..."
hdiutil convert "${TEMP_DMG_NAME}.dmg" -format UDZO -imagekey zlib-level=9 -o "${FINAL_DMG_NAME}"

# Clean up
rm -rf "${TEMP_DMG_NAME}.dmg" "${TEMP_DIR}"

echo "🎉 DMG installer created successfully!"
echo "📦 File: ${FINAL_DMG_NAME}"
echo "📊 Size: $(du -h "${FINAL_DMG_NAME}" | cut -f1)"

# Show file info
ls -la "${FINAL_DMG_NAME}"