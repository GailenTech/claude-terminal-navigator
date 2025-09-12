# Scaffolding Plan: History and Recovery Feature

## Feature Overview
Simple session history and recovery system that allows users to:
- View recent Claude sessions (reusing existing detail view)
- Recover terminated sessions by reopening Terminal with the original `claude` command
- Track command history for recovery purposes

## Refined Requirements
- **Recovery**: Reopen terminal with the initial command that started the session
- **UX**: "Recent Sessions" menu option showing same detail view with different title
- **Simplicity**: Reuse existing UI components where possible

## Architectural Patterns Detected
- **SwiftUI App**: Menu bar app with NSApplicationDelegateAdaptor
- **Model Pattern**: Struct-based models with Codable conformance
- **Database Layer**: SQLite3 integration with SessionDatabase class
- **Monitor Pattern**: Background monitoring with ClaudeSessionMonitor
- **UI Pattern**: NSMenu-based interface with detail windows
- **State Management**: Class-based managers with @Published properties

## Components to Scaffold

### 1. Core Components (ClaudeNavigator/)

- [ ] **SessionHistoryEntry.swift** - Model for historical sessions with command data
  - Pattern: Struct extending existing SessionHistory
  - Fields: command, arguments, endTime, exitCode
  - Integration: Works with SessionDatabase

- [ ] **SessionRecoveryManager.swift** - Handles session recovery
  - Pattern: Singleton class
  - Methods: recoverSession(), getRecentSessions()
  - Integration: Opens Terminal.app with stored command

### 2. Database Updates

- [ ] **SessionDatabase+History.swift** - Extension for history operations
  - New table: session_commands (session_id, command, arguments)
  - Methods: saveCommand(), getRecentSessions(), getCommand()
  - Migration: Add command tracking to existing sessions

### 3. UI Modifications

- [ ] **AppDelegate+RecentSessions** - Extend existing AppDelegate
  - Add "Recent Sessions" menu item
  - Reuse showDetailedView() with different data source
  - Add recovery action to session clicks

### 4. Integration Points

- [ ] Update **ClaudeSessionMonitor.swift** - Capture initial command
- [ ] Update **SessionDatabase.swift** - Add command storage
- [ ] Update **ClaudeNavigatorApp.swift** - Add menu separator and item

## File Creation Order
1. SessionHistoryEntry.swift (Model)
2. SessionDatabase+History.swift (Database extension)
3. SessionRecoveryManager.swift (Recovery logic)
4. Integration updates to existing files

## Implementation Details

### Command Capture Strategy
- Monitor wrapper script already tracks sessions
- Need to capture the full command line from process info
- Store in database when session starts

### Recovery Implementation
```swift
// Open Terminal with original command
let script = """
tell application "Terminal"
    activate
    do script "\(originalCommand)"
end tell
"""
```

### UI Reuse Strategy
- showDetailedView() accepts optional "mode" parameter
- Recent mode shows ended sessions from database
- Active mode shows current sessions (existing behavior)
- Same UI, different data source and title

## Success Criteria
- [x] Simplified scope focused on command recovery
- [ ] Reuses existing UI components
- [ ] Captures full command for recovery
- [ ] Opens Terminal with exact command
- [ ] Recent sessions accessible from menu
- [ ] No breaking changes to existing features