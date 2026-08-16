# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## What this project is

**Terminal Navigator** is a Claude Code plugin (bash CLI + two skills) that gives
visibility and control over multiple Claude Code sessions running across
terminals, projects, and git worktrees on macOS. It replaced an earlier Swift
menu bar app (see `legacy/swift-app` branch) — this repo now contains no
Swift code.

## Architecture

```
bin/nav                    CLI entry point (list/jump/spawn/worktrees/scan/prune)
lib/registry.sh             Shared functions: read/write/query the session registry
hooks/hook-handler.sh        Single entry point for all Claude Code hooks
skills/terminal-nav/SKILL.md Proactive skill — Claude decides when to use nav
skills/navs/SKILL.md         Manual slash command (/terminal-nav:navs) — raw `nav list`
.claude-plugin/plugin.json   Plugin manifest
.claude-plugin/marketplace.json  Marketplace entry (source: "./", this same repo)
setup.sh                     Installs hooks into ~/.claude/settings.json
```

### The registry

One JSON file per active session in `~/.claude-nav/sessions/`, indexed by
**cwd** (not PID or session_id) — in practice there's never two live Claude
Code sessions in the exact same directory at once; worktrees already give
each one a distinct path. See comments at the top of `lib/registry.sh`.

### Why hooks instead of polling

The original Swift app guessed session state (working/idle) from CPU usage,
which needed constant tuning (see the old `docs/DIARY.md` history on
`legacy/swift-app` for what that cost in bugs). This version uses Claude
Code's native hooks (`SessionStart`, `UserPromptSubmit`, `PreToolUse`,
`PermissionRequest`, `Stop`, `SessionEnd`) for exact, real-time state —
no heuristics.

Key facts verified empirically before building on them (see commit history
for the debug sessions that confirmed these):
- `$PPID` inside a hook is the actual `claude` process PID.
- `ps -o tty= -p $PPID` gives the real tty even though the hook's own
  stdin/stdout aren't attached to one.
- `PermissionRequest` is the reliable "blocked" signal; `Notification` did
  not fire in testing.
- Any hook (not just `SessionStart`) can bootstrap a registry entry — this
  matters for sessions that were already running before hooks were
  installed.

### Why `set -e` needs care here

Every script has `set -e` set. A few real bugs came from unguarded external
commands (`git`, `lsof`, `tail`, `sed`) failing under `set -e` and silently
aborting — sometimes before reaching the error-handling code meant to catch
exactly that case. Pattern used throughout: `cmd=$(...) || true` for
anything that can plausibly fail in normal operation (non-git directories,
missing processes, transient tool failures). See commit history around
`nav scan`/`nav list` for the specific bugs this caught.

One subtlety confirmed by direct testing: a failing command *inside a
function* does **not** abort the script if that function is itself called
via another command substitution (`x=$(myfunc)`) — `set -e` only reliably
aborts on **direct, top-level** command substitution assignments. Don't
assume nested calls are safe without checking which pattern applies.

### AppleScript / Terminal.app quirks

- Terminal.app's `tty` property returns `/dev/ttysNNN`; `ps -o tty=` returns
  bare `ttysNNN`. Always normalize before comparing (see `jump_to_tty`).
- `do script "..." in front window` does **not** reliably create a new tab —
  it has opened a new window instead in testing. The working approach is
  simulating Cmd+T via System Events, then `do script ... in front window`
  targeting the freshly created tab.
- `nav spawn`'s launcher never interpolates dynamic text (prompts, paths)
  directly into the AppleScript string. It writes a static launcher script
  to `~/.claude-nav/tmp/launch.XXXXXX/run.sh` (heredoc with a **quoted**
  delimiter, zero interpolation) that reads its inputs from sibling files
  via `$(cat ...)`. Only that script's own path — always safe,
  `mktemp`-generated — goes into the AppleScript string. Do not shortcut
  this for new spawn options; it's the fix for a real injection-shaped bug
  class (bash → AppleScript → shell, triple-escaping).

## Testing

No app to build. CI (`.github/workflows/test.yml`) runs on every push:
`bash -n` on all shell scripts, `jq` validation of the plugin JSON files,
and a frontmatter check on every `SKILL.md`. Run the same checks locally
before pushing — they're cheap:

```bash
for f in bin/nav hooks/*.sh lib/*.sh setup.sh; do bash -n "$f"; done
jq . .claude-plugin/plugin.json .claude-plugin/marketplace.json > /dev/null
```

There's no automated test for the AppleScript/Terminal.app paths (`jump`,
`spawn`) — those need a real Terminal.app session to verify. Don't claim
they work without testing them live; several bugs here only ever showed up
that way (e.g. `tail`/`sed` missing in some sandboxes, `git` failing in
non-repo directories, `/dev/` prefix mismatches).

## Release process

Tag `vX.Y.Z` and push the tag — that's it, no build step:

```bash
git tag -a vX.Y.Z -m "vX.Y.Z: <summary>"
git push origin main
git push origin vX.Y.Z
```

## Installing for testing

```bash
/plugin marketplace add GailenTech/claude-terminal-navigator
/plugin install terminal-nav@GailenTech
```

If you've registered the marketplace before and pulled a schema fix, clear
the cache first: `rm -rf ~/.claude/plugins/marketplaces/GailenTech-claude-terminal-navigator`.

## Known gaps

- No native `hooks/hooks.json` plugin-managed hooks yet — hooks are
  installed by `setup.sh` merging into `~/.claude/settings.json` directly.
  Claude Code plugins support declaring hooks natively (auto-installed/
  removed with the plugin); migrating to that would remove the need for
  `setup.sh` entirely. Worth doing, not yet done.
- Only Terminal.app on macOS. No iTerm2/Ghostty/Windows support.
