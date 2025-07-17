# Claude Terminal Navigator

<div align="center">
  <img src="https://img.shields.io/badge/macOS-11.0+-blue.svg" alt="macOS 11.0+">
  <img src="https://img.shields.io/badge/Swift-5.9+-orange.svg" alt="Swift 5.9+">
  <img src="https://img.shields.io/github/v/release/yourusername/claude-terminal-navigator" alt="Release">
  <img src="https://img.shields.io/github/license/yourusername/claude-terminal-navigator" alt="License">
</div>

<div align="center">
  <h3>A standalone macOS menu bar app that helps you navigate between active Claude CLI sessions</h3>
  <p>🚀 Jump instantly to any Claude session • 📊 Real-time monitoring • 🎨 Clean native UI</p>
</div>

## ✨ Features

- **🔍 Auto-discovery**: Automatically detects all running Claude sessions without any setup
- **🚀 Instant navigation**: Jump to any session with a double-click
- **📊 Real-time monitoring**: CPU usage, memory consumption, and session duration
- **🌿 Git integration**: Shows current branch and repository status
- **🎨 Smooth visual feedback**: Clean transitions and responsive UI
- **🚫 Zero configuration**: Works out of the box, no scripts or dependencies needed
- **🔄 Auto-refresh**: Updates every 5 seconds to keep information current
- **⚡ Launch at startup**: Optional auto-launch when you start your Mac

## 📦 Installation

### Download from Releases

1. Go to [Releases](https://github.com/GailenTech/claude-terminal-navigator/releases/latest)
2. Download `ClaudeNavigator-latest.zip`
3. Unzip the file
4. Drag `ClaudeNavigator.app` to your Applications folder
5. Launch the app from Applications
6. (Optional) Right-click the menu bar icon and enable "Launch at Startup"

### Build from Source

Requirements:
- macOS 11.0 or later
- Swift 5.9+ or Xcode 13+

```bash
git clone https://github.com/GailenTech/claude-terminal-navigator.git
cd claude-terminal-navigator
swift build -c release

# Create app bundle
./build.sh

# Copy to Applications
cp -r ClaudeNavigator.app /Applications/
```

## 🎯 How to Use

1. **Launch the app**: The 🤖 icon will appear in your menu bar
2. **View sessions**: Click the icon to see all active Claude sessions
3. **Navigate**: Double-click any session to jump to that terminal tab
4. **Detailed view**: Click without Option key to see detailed session information
5. **Quick menu**: Option+click for a compact session list

### Session Information

Each session shows:
- **Status indicator**: 🟢 Active (high CPU) or ⚪ Waiting (idle)
- **CPU usage**: Real-time processor utilization
- **Memory**: RAM consumption in MB
- **Duration**: How long the session has been running
- **Git branch**: Current repository and branch name
- **Working directory**: Current folder path

## 🛠️ Technical Details

### How It Works

The app uses native macOS APIs to:
- Discover Claude processes using `ps` command
- Monitor CPU and memory via system calls
- Navigate between terminal tabs using AppleScript
- Extract git information from working directories

### Terminal Support

- **Terminal.app**: Full support with direct tab navigation
- **Ghostty**: Partial support (activates app, manual tab switching required)
- **iTerm2**: Planned for future releases

### Privacy & Security

- **No network access**: All processing happens locally
- **No data collection**: No analytics or telemetry
- **Minimal permissions**: Only requires accessibility permissions for terminal navigation
- **Open source**: Full source code available for inspection

## 🚀 What's New

### v1.0.1
- 🏗️ Completely standalone - no shell script dependencies
- 🎨 Improved visual feedback and responsive UI
- 🔧 Better CPU parsing for international locales
- 🚫 Removed dangerous operations (kill button)
- ⚡ Added "Launch at Startup" option
- 🧹 Cleaned up menu items and UI

See [CHANGELOG.md](CHANGELOG.md) for full release history.

## 🆚 Why Choose This Over Shell Scripts?

| Feature | Shell Scripts | Native App |
|---------|---------------|------------|
| **Setup complexity** | Complex installation, PATH modification | Drag & drop installation |
| **Performance** | Process spawning overhead | Native Swift performance |
| **UI experience** | Terminal-based menus | Native macOS interface |
| **Error handling** | Manual troubleshooting | Built-in error recovery |
| **Distribution** | Script dependencies | Single app bundle |
| **Visual feedback** | Text-based status | Clean UI & icons |

## 🔧 Development

### Project Structure
```
├── ClaudeNavigator/           # Swift source code
│   ├── ClaudeNavigatorApp.swift    # Main app & UI
│   ├── ClaudeSessionMonitor.swift  # Session discovery & monitoring
│   └── Info.plist                  # App configuration
├── Package.swift              # Swift Package Manager
├── build.sh                   # Build script
└── old_shell_wrapper_version/ # Legacy shell scripts (archived)
```

### Building

```bash
# Debug build
swift build

# Release build
swift build -c release

# Create app bundle
./build.sh

# Run from source
swift run
```

### Debugging

Run from terminal to see console output:
```bash
./ClaudeNavigator.app/Contents/MacOS/ClaudeNavigator
```

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

## 🤝 Contributing

Contributions welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## 🆘 Support

- 🐛 [Report bugs](https://github.com/GailenTech/claude-terminal-navigator/issues/new)
- 💡 [Request features](https://github.com/GailenTech/claude-terminal-navigator/issues/new)
- 💬 [Start a discussion](https://github.com/GailenTech/claude-terminal-navigator/discussions)

---

<div align="center">
  Made with ❤️ for the Claude CLI community
</div>