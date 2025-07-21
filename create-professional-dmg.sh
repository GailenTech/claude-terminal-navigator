#!/bin/bash

# Professional DMG Creator for Claude Terminal Navigator
# Uses create-dmg tool for professional appearance

set -e

APP_NAME="ClaudeNavigator"
DMG_NAME="Claude-Terminal-Navigator-Installer"
VERSION="1.3.0"
SOURCE_APP="ClaudeNavigator.app"
FINAL_DMG_NAME="${DMG_NAME}-${VERSION}.dmg"

# Clean up any existing DMG files
rm -rf "${FINAL_DMG_NAME}"

echo "🚀 Creating professional DMG installer for ${APP_NAME} v${VERSION}..."

# Check if app exists
if [ ! -d "${SOURCE_APP}" ]; then
    echo "❌ Error: ${SOURCE_APP} not found!"
    echo "Please build the app first with: swift build"
    exit 1
fi

# Create a background image first
echo "🎨 Creating background image..."
BACKGROUND_IMG="dmg_background.png"
python3 -c "
from PIL import Image, ImageDraw, ImageFont
import os

# Create a 600x400 image with a subtle gradient
width, height = 600, 400
image = Image.new('RGB', (width, height), color='#f8f8f8')
draw = ImageDraw.Draw(image)

# Create a subtle gradient
for i in range(height):
    alpha = i / height
    gray = int(248 - alpha * 8)  # Light gray to slightly darker
    color = (gray, gray, gray)
    draw.line([(0, i), (width, i)], fill=color)

# Add instruction text
try:
    font = ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc', 18)
    small_font = ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc', 14)
except:
    font = ImageFont.load_default()
    small_font = font

# Main instruction
text = 'Drag ClaudeNavigator to Applications folder to install'
text_bbox = draw.textbbox((0, 0), text, font=font)
text_width = text_bbox[2] - text_bbox[0]
text_x = (width - text_width) // 2
text_y = height - 80

draw.text((text_x, text_y), text, fill='#333333', font=font)

# Add arrow pointing from app to Applications
arrow_start_x = 280
arrow_end_x = 380
arrow_y = 220

# Draw arrow line
draw.line([(arrow_start_x, arrow_y), (arrow_end_x, arrow_y)], fill='#666666', width=3)

# Draw arrow head
draw.polygon([
    (arrow_end_x, arrow_y),
    (arrow_end_x - 10, arrow_y - 5),
    (arrow_end_x - 10, arrow_y + 5)
], fill='#666666')

image.save('${BACKGROUND_IMG}')
print('Background image created successfully')
"

# Create the DMG using create-dmg
echo "📦 Creating DMG with create-dmg..."

create-dmg \
  --volname "${APP_NAME} ${VERSION}" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 128 \
  --icon "${SOURCE_APP}" 150 200 \
  --hide-extension "${SOURCE_APP}" \
  --app-drop-link 450 200 \
  --background "${BACKGROUND_IMG}" \
  --text-size 14 \
  --no-internet-enable \
  "${FINAL_DMG_NAME}" \
  "${SOURCE_APP}"

# Check if DMG was created successfully
if [ -f "${FINAL_DMG_NAME}" ]; then
    echo "🎉 Professional DMG installer created successfully!"
    echo "📦 File: ${FINAL_DMG_NAME}"
    echo "📊 Size: $(du -h "${FINAL_DMG_NAME}" | cut -f1)"
    
    # Show file info
    ls -la "${FINAL_DMG_NAME}"
    
    # Test the DMG by mounting it
    echo "🔍 Testing DMG..."
    TEST_MOUNT=$(mktemp -d)
    hdiutil attach "${FINAL_DMG_NAME}" -readonly -mountpoint "${TEST_MOUNT}"
    
    echo "✅ DMG contents:"
    ls -la "${TEST_MOUNT}/"
    
    # Unmount test
    hdiutil detach "${TEST_MOUNT}"
    echo "✅ DMG test completed successfully!"
    
    # Clean up background image
    rm -f "${BACKGROUND_IMG}"
    echo "🧹 Cleanup completed"
    
else
    echo "❌ Failed to create DMG!"
    # Clean up background image on failure too
    rm -f "${BACKGROUND_IMG}"
    exit 1
fi