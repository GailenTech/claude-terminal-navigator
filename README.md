# Terminal Navigator

A Claude Code skill for macOS that gives you visibility and control over all your active Claude Code sessions across projects and worktrees.

## What it does

**`nav list`** — See all active Claude Code sessions grouped by project, with real-time state (working 🤖 / blocked 🙋 / idle 💤), branch, and worktree path.

**`nav jump <pattern>`** — Jump to any session in Terminal.app by typing a project or worktree name.

**`nav spawn [--worktree <branch>] [--prompt <text>] <path>`** — Open a new Claude Code session, optionally creating a new worktree and pre-loading a prompt (useful for "transferring" work to another terminal).

**`nav worktrees <path>`** — List all git worktrees in a project and see which ones have active Claude sessions.

## Why this exists

When you have multiple Claude Code sessions running across different terminals, projects, and worktrees, you lose visibility:
- Which sessions are currently working vs. waiting for your approval?
- How do I jump back to session X without hunting through open tabs?
- Can I move this work to a new worktree cleanly?

**Terminal Navigator solves this** using Claude Code's native hooks (not polling or heuristics), giving you real-time semantic state and one-command navigation.

## Installation

### For individuals

```bash
/plugin install github.com/GailenTech/claude-terminal-navigator
```

Claude Code will:
1. Clone the repo
2. Run `setup.sh` to install hooks into `~/.claude/settings.json`
3. Add `nav` to your PATH

### For teams (GitHub organization)

Clone the repo and add it as a plugin source in your org's plugin registry, or share the install command above with your team.

### Manual setup

```bash
git clone https://github.com/GailenTech/claude-terminal-navigator.git
cd claude-terminal-navigator
chmod +x setup.sh
./setup.sh
```

Verify installation:
```bash
nav list
```

## Requirements

- **macOS** (Terminal.app integration via AppleScript)
- **Claude Code** (CLI, hook support)
- **git** (worktree support in spawn)
- **bash** (script engine)

## Usage

See [skills/terminal-nav/SKILL.md](skills/terminal-nav/SKILL.md) for detailed
command reference and examples.

For a quick manual check without going through the model, use
`/terminal-nav:navs` — it runs `nav list` directly and shows the raw output
([skills/navs/SKILL.md](skills/navs/SKILL.md)).

### Want a shorter command, like `/terms`?

Plugin skills are always namespaced (`/plugin-name:skill-name`) to avoid
collisions between plugins — there's no way around that for a
marketplace-installed skill. If you want a bare, un-namespaced shortcut,
add a **personal** skill (these aren't namespaced) pointing at the same
CLI, since `nav` is already on your `PATH` while the plugin is enabled:

```bash
mkdir -p ~/.claude/skills/terms
cat > ~/.claude/skills/terms/SKILL.md <<'EOF'
---
name: terms
description: Alias personal rápido de "/terminal-nav:navs".
disable-model-invocation: true
---

Sesiones de Claude Code activas ahora mismo:

!`nav list`
EOF
```

This lives on your machine only, not in this repo — everyone who wants the
shortcut sets up their own.

Quick start:
```bash
# See what you have running
nav list

# Jump to a session
nav jump my-project

# Start work on a new worktree
nav spawn --worktree feature-x --prompt "continue the auth refactor" /path/to/repo

# See all worktrees in a project
nav worktrees /path/to/repo
```

## How it works

Terminal Navigator uses **Claude Code's native hooks** (SessionStart, UserPromptSubmit, PreToolUse, PermissionRequest, Stop, SessionEnd) to track sessions in real-time, giving you exact state (working/blocked/idle) instead of CPU-based guessing.

The registry lives in `~/.claude-nav/sessions/` and is automatically cleaned up when you close sessions, even abruptly.

## Contributing

Issues and PRs welcome. See [CLAUDE.md](CLAUDE.md) for development workflow.

## License

MIT License — see [LICENSE](LICENSE) for details.