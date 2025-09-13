# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### Development and Testing
```bash
# Install the navigator
./install.sh

# Test the wrapper functionality
claude  # This runs the wrapper that tracks sessions

# Test navigation between sessions
clj  # Jump to active Claude sessions

# Clean up dead sessions manually
claude-cleanup

# Verify Terminal.app permissions
check-permissions
```

### Troubleshooting Commands
```bash
# View all active sessions
ls -la ~/.claude/sessions/

# Debug wrapper execution
bash -x bin/claude-nav

# Check if Claude process is running
ps aux | grep -E 'claude\s+$' | grep -v grep

# Get current terminal TTY
tty
```

## Release Process

### Creating a New Release

1. **Build the release binary**:
```bash
swift build -c release
cp .build/release/ClaudeNavigator ClaudeNavigator.app/Contents/MacOS/ClaudeNavigator
```

2. **Update version in Info.plist**:
   - Edit `ClaudeNavigator.app/Contents/Info.plist`
   - Update `CFBundleShortVersionString` (e.g., "1.4.2")
   - The build number auto-increments via GitHub Actions

3. **Commit changes**:
```bash
git add .
git commit -m "Release v1.4.2: Description of changes"
```

4. **Create and push tag**:
```bash
git tag v1.4.2
git push origin main
git push origin v1.4.2
```

5. **Create GitHub release**:
```bash
# The GitHub Actions workflow will automatically create ZIP and DMG artifacts
# But you can also create the release manually:
gh release create v1.4.2 \
  --title "Claude Terminal Navigator v1.4.2" \
  --notes "Release notes here" \
  --draft
```

6. **Wait for GitHub Actions**:
   - The workflow automatically builds both ZIP and DMG installers
   - Downloads will be attached to the release automatically

### Release Artifacts

The release includes:
- **ClaudeNavigator-vX.Y.Z.zip**: Direct app bundle
- **ClaudeNavigator-vX.Y.Z.dmg**: Drag-and-drop installer with custom background

### Version Management

- Version format: `vMAJOR.MINOR.PATCH` (e.g., v1.4.2)
- Tags must match the pattern `v*` to trigger release workflow
- Build numbers are automatically set to GitHub Actions run number

## Architecture Overview

### Project Purpose
Claude Terminal Navigator is a shell utility that enables automatic navigation between terminal tabs where Claude CLI sessions are active. It solves the problem of having multiple Claude sessions across different terminal tabs by providing instant navigation.

### Core Components

1. **Session Tracking System**
   - `bin/claude-nav`: Wrapper script that intercepts `claude` command calls
   - Creates JSON session files in `~/.claude/sessions/` with:
     - Process ID (PID)
     - Terminal TTY
     - Working directory
     - Terminal type (Terminal.app, Ghostty, etc.)
   - Automatically cleans up when Claude exits

2. **Navigation Engine**
   - `bin/claude-jump`: Finds active Claude sessions and navigates to them
   - Uses AppleScript for Terminal.app integration
   - Falls back to window title matching when TTY navigation fails
   - Supports multi-session selection menu

3. **Terminal Integration**
   - Full support for Terminal.app via AppleScript
   - Partial support for Ghostty (activates app, requires manual tab switching)
   - Extensible design for adding new terminals

4. **Installation System**
   - `install.sh`: Automated installer that:
     - Detects shell type (bash/zsh)
     - Adds PATH and aliases to shell config
     - Creates backups before modifying files
     - Verifies Terminal.app accessibility permissions

### Key Design Decisions

1. **TTY-based Tracking**: Uses terminal TTY as the primary identifier for tabs, as it's unique per terminal tab and persistent during the session.

2. **JSON Session Files**: Simple file-based session storage allows easy debugging and doesn't require a daemon process.

3. **AppleScript Integration**: Direct AppleScript usage for Terminal.app provides reliable tab switching without external dependencies.

4. **Wrapper Pattern**: The `claude-nav` wrapper transparently intercepts Claude calls, requiring no changes to user workflow.

5. **Automatic Cleanup**: Sessions are cleaned up both on exit (via trap) and proactively before new operations to prevent stale data.

### Terminal Support Strategy

- **Terminal.app**: Full AppleScript API access enables complete automation
- **Ghostty**: Limited API requires manual intervention (Cmd+1, Cmd+2, etc.)
- **iTerm2**: Planned support via its AppleScript API
- **Other terminals**: Can be added by implementing terminal-specific navigation functions in `claude-jump`

### Error Handling

1. **Permission Errors**: Dedicated `check-permissions` script guides users through macOS accessibility setup
2. **Session Cleanup**: Automatic cleanup prevents accumulation of dead session files
3. **Fallback Navigation**: Multiple strategies (TTY → window title → create new) ensure navigation succeeds
4. **User Feedback**: Clear error messages with actionable solutions