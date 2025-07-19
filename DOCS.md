# 📚 Claude Terminal Navigator Documentation

This document serves as an index to all documentation in the `/docs` directory.

## 📔 Development Documentation

- **[Development Diary](docs/DIARY.md)** - Daily development log with decisions, challenges, and progress
- **[Metrics Proposal](docs/metrics-proposal.md)** - Detailed proposal for session analytics implementation

## 📸 Screenshots

- **[Quick Menu View](docs/quick-menu.png)** - The main menu bar dropdown interface
- **[Detailed Session View](docs/detailed-view.png)** - Extended session information window

## 📖 Other Documentation

- **[README](README.md)** - Main project documentation and usage instructions
- **[CHANGELOG](CHANGELOG.md)** - Version history and release notes
- **[CLAUDE Instructions](CLAUDE.md)** - Project-specific instructions for Claude Code

## 🛠️ Technical Documentation

### Architecture
The app follows a modular architecture with:
- `ClaudeSessionMonitor` - Process detection and monitoring
- `SessionDatabase` - SQLite persistence layer
- `SessionTracker` - Real-time metrics collection
- `ClaudeNavigatorApp` - Main UI and coordination

### Key Features
1. **Session Detection** - Automatic discovery of Claude CLI processes
2. **Metrics Collection** - CPU, memory, duration tracking
3. **Navigation** - One-click terminal tab switching
4. **Analytics** - Historical session data and insights

### Development Workflow
1. Check `DIARY.md` for recent context
2. Run tests after changes
3. Update diary with significant progress
4. Create feature branches for new work
5. Use semantic versioning for releases

For contributing guidelines and technical details, see the source code documentation in each Swift file.