# Changelog

All notable changes to Claude Terminal Navigator will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.2.0] - 2025-07-19

### Added
- Complete session analytics system with SQLite database
- Session history tracking with metrics (CPU, memory, duration)
- Analytics dashboard with time period selector (24h, 7d, 30d, all time)
- Professional DMG installer with drag-and-drop interface
- Automatic version display in About dialog
- Window toggle behavior - click menu bar icon to close open window
- Force Save Snapshot debug functionality
- GitHub Actions workflows for automated releases

### Fixed
- Scroll position now shows first elements at top (FlippedView implementation)
- Window focus issues - window properly gains focus when opened
- Database corruption with empty session IDs
- Total time calculation for active sessions

### Changed
- Improved session icons with visual status indicators
- Enhanced window positioning and sizing
- Better error handling throughout the app

## [1.0.2] - 2025-07-17

### Fixed
- Fixed working directory detection bug where lsof usage message appeared as session name
- Improved error handling for process discovery with multiple fallback methods

### Changed
- Toned down marketing language in README (removed "beautiful animations" hyperbole)
- Cleaned up project structure by removing development artifacts

## [1.0.1] - 2025-07-17

### Changed
- Restructured project to focus solely on macOS widget
- Moved legacy shell scripts to `old_shell_wrapper_version/` directory
- Updated GitHub Actions to build from root instead of SwiftApp subdirectory
- Rewrote README for better presentation and standalone widget focus

## [1.0.0] - 2025-07-17

### Added
- Initial release of Claude Terminal Navigator as a standalone macOS app
- Automatic detection of all running Claude CLI sessions
- Real-time CPU and memory monitoring for each session
- Git branch and status information display
- Session duration tracking
- Double-click navigation to jump to any session
- Visual feedback with hover and press animations
- Floating detailed view window
- Launch at Startup option in settings
- Support for macOS 11.0 and later

### Changed
- Transformed from shell script-based tool to native Swift application
- Removed all bash script dependencies (claude-nav, claude-cleanup, claude-jump)
- Implemented direct process discovery using system commands
- Changed from file-based to memory-based session tracking

### Removed
- Dependency on wrapper scripts
- Need for shell configuration
- "Launch New Claude" menu option
- "Cleanup Dead Sessions" menu option
- "Open Sessions Folder" menu option
- "Refresh Now" menu option (auto-refresh every 5 seconds)

### Security
- No longer requires shell modifications
- Runs completely sandboxed as a standard macOS app
- Only requests Terminal control permission when jumping to sessions

[1.0.0]: https://github.com/GailenTech/claude-terminal-navigator/releases/tag/v1.0.0