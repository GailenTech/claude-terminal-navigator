# 📔 Development Diary - Claude Terminal Navigator

## 2025-09-12 - Recent Sessions Threading Fix & Active Session Filtering

### What was done
- **Fixed Recent Sessions filtering**: Added logic to exclude directories with active Claude sessions from Recent Sessions menu
- **Fixed app crash**: Recent Sessions menu was crashing when accessed due to NSWindow creation on background thread
- **Added synchronous method**: Created synchronous `getActiveSessions()` method in ClaudeSessionMonitor for UI operations
- **Removed async Task**: Eliminated Task/async pattern from Recent Sessions menu handler to prevent threading issues
- **Ensured main thread execution**: All UI operations now happen directly on main thread
- **Released v1.4.2**: Created release with both bug fixes

### Decisions made
- **Filter active paths**: Recent Sessions should never show directories that have active sessions running
- **Synchronous for UI**: UI operations should use synchronous methods when possible to avoid threading complexity
- **Avoid Task for menu handlers**: Menu click handlers should avoid async/await patterns when creating windows
- **Dual method approach**: Keep both async and sync versions of getActiveSessions() for different use cases

### Challenges/Learnings
- **NSWindow threading requirement**: NSWindow must be created on main thread - macOS strictly enforces this
- **DispatchQueue.main.async limitations**: Even wrapping in main queue async wasn't sufficient when called from Task context
- **Swift concurrency gotchas**: Task context can cause subtle threading issues with AppKit
- **Multiple crash attempts**: First fix with DispatchQueue.main.async wasn't sufficient, required complete removal of async pattern

### Architecture Changes
- **ClaudeSessionMonitor**: Added synchronous getActiveSessions() method alongside async version
- **ClaudeNavigatorApp**: 
  - Simplified Recent Sessions handler to use synchronous approach
  - Added filtering logic to exclude active session paths from Recent Sessions
- **Thread safety**: Improved overall thread safety by avoiding unnecessary async operations in UI code

### Bug Reports Resolved
- User reported: "Recent Sessions del directorio ClaudeCloud, pero resulta que también tengo una sesion activa de ese mismo directorio"
- User reported: "se ha cerrado al acceder a esa opción de menu" (app crashed when accessing Recent Sessions)
- User reported: "volvió a romperse" (crash persisted after first fix attempt)

### Next steps
- Monitor for any other threading issues with UI operations
- Consider audit of all Task usage in UI-related code
- May need to establish pattern for when to use async vs sync methods

## 2025-09-11 - Session History and Recovery Implementation

### What was done
- **Session History Model**: Created `SessionHistoryEntry.swift` to store complete session history with command recovery data
- **Database Extension**: Added `SessionDatabase+History.swift` with methods for storing and retrieving session history
- **Recovery Manager**: Implemented `SessionRecoveryManager.swift` to handle session recovery by reopening Terminal with original commands
- **Recent Sessions UI**: Added "Recent Sessions" menu item that reuses existing detailed view with recovery actions
- **Command Capture**: Updated `ClaudeSessionMonitor` to capture and store initial Claude commands when sessions start
- **Session Lifecycle**: Integrated session start/end tracking with history database

### Decisions made
- **Reuse existing UI**: Instead of creating new views, reused the existing detailed view with a mode parameter
- **Simple recovery approach**: Open Terminal.app with the original command using AppleScript
- **Command storage**: Store full command line with arguments for accurate recovery
- **Database schema**: Extended existing SQLite database with new history tables

### Challenges/Learnings
- **Access levels**: Had to make some private methods internal for extension access
- **Ambiguous methods**: Renamed `getRecentSessions` to `getRecentHistoryEntries` to avoid conflicts
- **Mode passing**: Needed to track current detail view mode for proper UI updates
- **SQLite3 imports**: Required explicit import in files using database operations

### Architecture Changes
- **New files**: SessionHistoryEntry.swift, SessionDatabase+History.swift, SessionRecoveryManager.swift
- **Modified AppDelegate**: Added DetailViewMode enum and delegate pattern for session clicks
- **Extended SessionDatabase**: Added internal helper methods for extensions
- **Enhanced ClaudeSessionMonitor**: Captures commands and tracks session lifecycle

### Next steps
- Test recovery functionality with real Claude sessions
- Consider adding user preferences for history retention period
- Potential for session statistics and analytics based on history
- Could add export functionality for session history

## 2025-07-25 - Attention Alert System Implementation

### What was done
- **Comprehensive attention detection system**: Sessions that transition from busy (CPU > 1%) to idle (CPU ≤ 1%) now trigger attention alerts after 5 seconds
- **Smart focus detection**: Uses AppleScript to detect which Terminal tab is currently focused, preventing alerts for visible sessions
- **Enhanced UI indicators**: 
  - Badge (⚠️) appears in menu bar icon when sessions need attention
  - Sessions needing attention show 🙋‍♀️ icon instead of 💤
  - Orange pulsing animation for urgent attention (faster than normal activity pulse)
- **Interactive attention clearing**: Clicking on a session automatically clears its attention flag
- **CPU reading history**: Tracks last 5 CPU readings per session for accurate transition detection

### Decisions made
- **5-second delay**: Prevents false positives from brief CPU drops during normal operation
- **Focus exclusion**: Critical feature - never alert for sessions that are currently visible to user
- **AppleScript caching**: Cache focus detection results for 1 second to reduce AppleScript overhead
- **Transition detection**: Requires 3 consecutive low CPU readings after detecting previous high activity
- **Visual hierarchy**: Attention (🙋‍♀️) > Active (🤖) > Idle (💤) for clear status communication

### Challenges/Learnings
- **AppleScript frontmost detection**: Combined Terminal.app frontmost check with specific tab TTY matching for accuracy
- **Session state persistence**: Extended ClaudeSession with non-persisted attention tracking properties
- **CPU history management**: Implemented sliding window of readings to detect meaningful transitions
- **Thread-safe updates**: Used DispatchQueue for safe session state modifications
- **Boolean AppleScript results**: Fixed NSAppleScript boolean value handling in Swift

### Architecture Changes
- **New FocusDetector class**: Handles all Terminal.app focus detection with caching
- **Extended ClaudeSession model**: Added `needsAttention`, `lastCPUReadings`, `lastStateChange` properties
- **Enhanced ClaudeSessionMonitor**: Integrated attention logic into main session processing loop
- **UI updates in AppDelegate**: Modified icon badges, session icons, and animations

### Performance Impact
- **Minimal overhead**: Focus detection cached for 1 second, only checks when sessions transition
- **Efficient AppleScript**: Uses targeted scripts that return quickly
- **Memory usage**: CPU reading history limited to 5 values per session

### Next steps
- Monitor real-world usage patterns to adjust timing thresholds if needed
- Consider adding user preferences for attention alert sensitivity
- Potential sound notifications for high-priority attention alerts
- Analytics integration to track attention patterns

## 2025-07-21 - Session Cache Implementation

### What was done
- Implemented complete session caching system for instant window display
- Added cache update mechanism in the 5-second refresh cycle
- Window now shows cached sessions immediately on open
- Fresh data loads asynchronously and updates if different
- Added cache age indicator in header (e.g., "cached 3s ago")
- Implemented smooth fade transition when updating from cache to fresh data
- Added auto-refresh for open detail window when cache updates

### Decisions made
- Cache updates every 5 seconds with the regular refresh cycle
- Used sessionEqual() helper to detect meaningful changes in sessions
- Show cache age to users for transparency
- Fade animation (0.25s) provides visual feedback on data updates

### Challenges/Learnings
- Swift Array comparison requires Equatable conformance - used custom comparison function
- Showing cached data first dramatically improves perceived performance
- Auto-refresh keeps window data current without user interaction

### Next steps
- Consider persisting cache between app launches
- Add visual indicator (spinner) when refreshing in background
- Implement cache expiration policy if needed

## 2025-07-19 - UX Improvements: Single-Click Navigation & Performance

### What was done
- Changed double-click to single-click for session navigation
- Improved window opening performance by showing UI immediately
- Added loading indicator while sessions are being fetched
- Window now appears instantly with "Loading sessions..." message
- Sessions are loaded asynchronously and UI updates when ready

### Decisions made
- Single-click is more intuitive and faster for users
- Show UI immediately rather than waiting for data (perceived performance)
- Use NSProgressIndicator for visual feedback during loading

### Challenges/Learnings
- Async loading pattern prevents UI blocking
- Perceived performance is as important as actual performance
- Simple UX changes can significantly improve user experience

## 2025-07-19 - Major Release: Session Analytics & DMG Installer

### What was done
- Implemented complete session analytics system with SQLite database
- Created real-time metrics collection (CPU, memory, duration)
- Added analytics dashboard with time period selector (24h, 7d, 30d, all time)
- Built professional DMG installer with drag-and-drop interface
- Fixed scroll position issue using FlippedView implementation
- Added window toggle behavior (click menu bar icon to close)
- Automated GitHub Actions workflow for releases

### Decisions made
- Chose SQLite for local session storage (lightweight, no dependencies)
- Used FlippedView pattern to fix macOS coordinate system issues
- Implemented GitHub Actions workflow that creates both ZIP and DMG
- Version now updates automatically from git tags
- Build number uses GitHub run number for auto-increment

### Challenges/Learnings
- Swift concurrency error in release builds - fixed by capturing variables before async blocks
- GitHub Actions icon copy error - resolved by checking if file exists first
- NSScrollView coordinate system is bottom-up by default - FlippedView solves this elegantly
- DMG creation requires `create-dmg` tool - added to workflow

### Next steps
- Add performance metrics (disk I/O, network) - currently pending
- Consider adding export functionality for analytics data
- Implement session search/filter capabilities
- Add keyboard shortcuts for power users

## 2025-07-18 - Session Metrics Proposal

### What was done
- Created comprehensive metrics proposal document
- Designed database schema for session history
- Planned SessionTracker and analytics implementation

### Decisions made
- Track sessions locally vs cloud storage
- Use native Swift/AppKit for all UI components
- Implement non-intrusive background tracking

## 2025-07-17 - Initial Release v1.0.0

### What was done
- Transformed from shell script-based tool to native Swift application
- Implemented automatic Claude session detection
- Added real-time CPU and memory monitoring
- Created floating detailed view window
- Added Git branch and status information display

### Decisions made
- Moved from bash scripts to native macOS app for better integration
- Used SwiftUI/AppKit hybrid approach
- Removed all shell script dependencies for cleaner architecture

### Challenges/Learnings
- Process discovery required multiple fallback methods
- Working directory detection needed special handling for lsof output
- macOS permissions for Terminal control require user approval