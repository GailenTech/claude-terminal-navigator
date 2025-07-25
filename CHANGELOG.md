# Changelog

All notable changes to Claude Terminal Navigator will be documented in this file.

## [1.4.1] - 2025-07-25

### Added
- **🚨 Session Attention Alert System**: Revolutionary new feature that alerts when Claude sessions need user attention
- **Smart Transition Detection**: Monitors CPU usage patterns to detect when sessions go from busy to idle
- **Focus-Aware Alerts**: Only shows alerts for sessions that are NOT currently visible/focused
- **Intelligent Badge System**: Compact 🚨 badge in menu bar for sessions requiring attention
- **Priority Sorting**: Sessions needing attention always appear first in all lists and views
- **AppleScript Focus Detection**: Deep Terminal.app integration to detect which session is currently active

### Changed
- **Consistent Iconography**: Unified 🚨 emergency icon across menu bar, detailed view, and dropdown menus
- **Ultra-Compact Badge**: Optimized badge width to avoid camera notch issues on modern MacBooks
- **Immediate Alert Clearing**: Attention flags clear instantly when user interacts with flagged sessions
- **Reduced Protection Period**: Lowered manual attention clearing protection from 30s to 10s for better UX

### Fixed
- **Eliminated UI Race Conditions**: Fixed concurrent session updates that caused inconsistent sorting ("dancing" behavior)
- **Consistent Session Ordering**: All views now maintain proper sorting: attention → active → idle
- **CPU Reading Accumulation**: Fixed critical bug where CPU readings weren't properly accumulated for transition detection
- **Focus Detection Reliability**: Improved AppleScript integration for accurate session focus detection

### Technical
- Implemented thread-safe session update queue to prevent concurrent modifications
- Added comprehensive debugging logs for attention state tracking and transitions
- Enhanced session state persistence across refresh cycles
- Optimized attention logic with proper transition validation (requires 3+ readings with prior activity)
- 5-second delay before triggering attention alerts to prevent false positives

## [1.4.0] - 2025-07-25

### Added
- **Initial Attention Alert System**: First implementation of session attention detection
- **Focus Detection Framework**: Basic AppleScript integration for Terminal.app focus detection
- **Session State Tracking**: Enhanced ClaudeSession model with attention tracking properties

### Fixed
- **Session State Management**: Improved session data persistence and restoration
- **Badge Width Optimization**: Initial fixes for camera notch compatibility

## [1.3.0] - 2025-07-21

### Added
- **Session Caching**: Implemented intelligent session caching system for instant window display
- **Auto-refresh**: Detail window now automatically updates when cache refreshes (every 5 seconds)
- **Cache Age Indicator**: Shows when cached data is being displayed (only when meaningful, >2 seconds)

### Changed
- **Single-Click Navigation**: Simplified from double-click to single-click for jumping to sessions
- **Instant Window Display**: Detail window now opens immediately with cached data instead of showing loading state
- **Improved Performance**: Window appears instantly, fresh data loads in background

### Fixed
- **Scroll Position Preservation**: Scroll position is now properly maintained during auto-refresh
- **Cache UX**: Removed unhelpful "cached 0s ago" messages
- **Memory Management**: Proper cleanup of scroll view references to prevent memory leaks

### Technical
- Implemented in-place content updates to preserve UI state
- Added smooth fade transitions when updating from cache to fresh data
- Optimized session comparison logic to detect meaningful changes

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