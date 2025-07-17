# Claude Navigator - Native Swift Menu Bar App

Native macOS menu bar application for Claude Terminal Navigator.

## Features

- 🟢 Real-time session monitoring with CPU/memory usage
- 🖱️ One-click navigation to any Claude session
- 🔄 Auto-refresh every 5 seconds
- 📊 Detailed session information
- 🎯 Native macOS experience

## Building

### Requirements
- macOS 11.0+
- Xcode 13+ or Swift 5.7+
- Command Line Tools installed

### Quick Build
```bash
./build.sh
```

### Manual Build
```bash
swift build -c release
# Executable will be in .build/release/ClaudeNavigator
```

### Xcode Project (Optional)
```bash
swift package generate-xcodeproj
open ClaudeNavigator.xcodeproj
```

## Installation

After building:
```bash
# Copy to Applications
cp -r ClaudeNavigator.app /Applications/

# Or run directly
open ClaudeNavigator.app
```

## Development

### Project Structure
```
SwiftApp/
├── Package.swift              # Swift Package Manager config
├── ClaudeNavigator/
│   ├── ClaudeNavigatorApp.swift    # Main app & UI
│   ├── ClaudeSessionMonitor.swift  # Session monitoring logic
│   └── Info.plist                  # App configuration
├── build.sh                   # Build script
└── README.md                  # This file
```

### Key Components

1. **ClaudeNavigatorApp.swift**
   - Main application entry point
   - Menu bar UI management
   - User interaction handling

2. **ClaudeSessionMonitor.swift**
   - Session file reading
   - Process monitoring
   - Shell command execution
   - AppleScript integration

### Integration with Bash Scripts

The Swift app calls the existing bash scripts:
- `claude-jump` - For session navigation
- `claude-cleanup` - For cleaning dead sessions

Paths are hardcoded to:
```
/Volumes/DevelopmentProjects/Claude/claude-terminal-navigator/bin/
```

Update these in `ClaudeSessionMonitor.swift` if needed.

## Debugging

Run from terminal to see console output:
```bash
./ClaudeNavigator.app/Contents/MacOS/ClaudeNavigator
```

## Distribution

For distributing to others:

1. **Code Sign with Developer ID** (requires paid developer account):
   ```bash
   codesign --force --deep --sign "Developer ID Application: Your Name" ClaudeNavigator.app
   ```

2. **Notarize** (required for distribution):
   ```bash
   ditto -c -k --keepParent ClaudeNavigator.app ClaudeNavigator.zip
   xcrun notarytool submit ClaudeNavigator.zip --apple-id your@email.com
   ```

3. **Create DMG** (optional):
   ```bash
   hdiutil create -volname "Claude Navigator" -srcfolder ClaudeNavigator.app -ov ClaudeNavigator.dmg
   ```

## Comparison with xbar Version

| Feature | xbar | Swift Native |
|---------|------|--------------|
| Setup complexity | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| Performance | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| UI flexibility | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| Distribution | ⭐⭐ | ⭐⭐⭐⭐ |
| Debugging | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| Code complexity | ⭐⭐⭐⭐⭐ | ⭐⭐ |

## Future Enhancements

- [ ] Preferences window
- [ ] Keyboard shortcuts
- [ ] Session history graphs
- [ ] Auto-update via Sparkle
- [ ] Custom status bar icons
- [ ] iTerm2 support