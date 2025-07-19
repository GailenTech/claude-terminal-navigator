#!/bin/bash

# Prepare Release Script for Claude Terminal Navigator
# This script updates version numbers and builds the release

set -e

# Check if version argument is provided
if [ $# -eq 0 ]; then
    echo "Usage: ./prepare-release.sh <version>"
    echo "Example: ./prepare-release.sh 1.2.1"
    exit 1
fi

VERSION=$1
echo "🚀 Preparing release for version $VERSION..."

# Get current version from Info.plist
CURRENT_VERSION=$(defaults read "$(pwd)/ClaudeNavigator/Info.plist" CFBundleShortVersionString)
CURRENT_BUILD=$(defaults read "$(pwd)/ClaudeNavigator/Info.plist" CFBundleVersion)

echo "📌 Current version: $CURRENT_VERSION (Build $CURRENT_BUILD)"
echo "📌 New version: $VERSION"

# Increment build number
NEW_BUILD=$((CURRENT_BUILD + 1))

# Update Info.plist
echo "📝 Updating Info.plist..."
plutil -replace CFBundleShortVersionString -string "$VERSION" ClaudeNavigator/Info.plist
plutil -replace CFBundleVersion -string "$NEW_BUILD" ClaudeNavigator/Info.plist

# Update CHANGELOG.md
echo "📝 Updating CHANGELOG.md..."
echo "Please update CHANGELOG.md manually with release notes for v$VERSION"

# Update version in DMG creation scripts
echo "📝 Updating DMG scripts..."
sed -i '' "s/VERSION=\"[0-9.]*\"/VERSION=\"$VERSION\"/" create-dmg-simple.sh
sed -i '' "s/VERSION=\"[0-9.]*\"/VERSION=\"$VERSION\"/" create-dmg.sh
sed -i '' "s/VERSION=\"[0-9.]*\"/VERSION=\"$VERSION\"/" create-professional-dmg.sh

# Build the app
echo "🔨 Building app..."
./build.sh

# Create DMG
echo "📦 Creating DMG installer..."
./create-dmg-simple.sh

# Create release archive
echo "📦 Creating release ZIP..."
ZIP_NAME="ClaudeNavigator-${VERSION}.zip"
zip -r "$ZIP_NAME" ClaudeNavigator.app

echo "✅ Release preparation complete!"
echo ""
echo "📋 Next steps:"
echo "1. Test the app: open ClaudeNavigator.app"
echo "2. Update CHANGELOG.md with release notes"
echo "3. Commit changes: git add . && git commit -m \"Release v$VERSION\""
echo "4. Create git tag: git tag v$VERSION"
echo "5. Push changes: git push origin main --tags"
echo "6. Create GitHub release with:"
echo "   - ${ZIP_NAME}"
echo "   - Claude-Terminal-Navigator-Installer-${VERSION}.dmg"
echo ""
echo "📝 Or use GitHub CLI:"
echo "gh release create v$VERSION \\"
echo "  --title \"v$VERSION - Release Title\" \\"
echo "  --notes \"Release notes here\" \\"
echo "  \"$ZIP_NAME\" \\"
echo "  \"Claude-Terminal-Navigator-Installer-${VERSION}.dmg\""