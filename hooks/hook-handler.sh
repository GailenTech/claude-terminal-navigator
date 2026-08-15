#!/bin/bash
# hook-handler.sh - Único punto de entrada para todos los hooks de Claude Code.
# Uso: hook-handler.sh <EventName>   (el payload JSON llega por stdin)
#
# $PPID dentro de un hook es el propio proceso `claude` (verificado empíricamente:
# ver .claude/debug-hooks.log). `ps -o tty= -p $PPID` da el tty real de la pestaña,
# aunque el propio hook corre desatado de terminal (su stdin/stdout no son un tty).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/registry.sh
source "$SCRIPT_DIR/../lib/registry.sh"

EVENT="${1:-}"
PAYLOAD=$(cat)

CWD=$(echo "$PAYLOAD" | jq -r '.cwd // empty')
SESSION_ID=$(echo "$PAYLOAD" | jq -r '.session_id // empty')

# Sin cwd no podemos indexar nada; salir en silencio sin bloquear a Claude.
[ -z "$CWD" ] && exit 0

CLAUDE_PID="$PPID"
TTY=$(ps -o tty= -p "$CLAUDE_PID" 2>/dev/null | tr -d ' ')
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

case "$EVENT" in
  SessionStart)
    GIT_INFO=$(registry_git_info "$CWD")
    MODEL=$(echo "$PAYLOAD" | jq -r '.model // empty')
    PATCH=$(jq -n \
      --arg cwd "$CWD" --arg session_id "$SESSION_ID" \
      --arg pid "$CLAUDE_PID" --arg tty "$TTY" \
      --arg status "idle" --arg started_at "$NOW" --arg updated_at "$NOW" \
      --arg model "$MODEL" --argjson git "$GIT_INFO" \
      '{cwd:$cwd, session_id:$session_id, pid:($pid|tonumber), tty:$tty,
        status:$status, started_at:$started_at, updated_at:$updated_at,
        model:$model} * $git')
    registry_merge "$CWD" "$PATCH"
    ;;

  UserPromptSubmit)
    PROMPT=$(echo "$PAYLOAD" | jq -r '.prompt // empty' | cut -c1-120)
    PATCH=$(jq -n --arg status "working" --arg updated_at "$NOW" --arg last_prompt "$PROMPT" \
      '{status:$status, updated_at:$updated_at, last_prompt:$last_prompt}')
    registry_merge "$CWD" "$PATCH"
    ;;

  PreToolUse)
    TOOL=$(echo "$PAYLOAD" | jq -r '.tool_name // empty')
    PATCH=$(jq -n --arg status "working" --arg updated_at "$NOW" --arg last_tool "$TOOL" \
      '{status:$status, updated_at:$updated_at, last_tool:$last_tool}')
    registry_merge "$CWD" "$PATCH"
    ;;

  PermissionRequest)
    TOOL=$(echo "$PAYLOAD" | jq -r '.tool_name // empty')
    PATCH=$(jq -n --arg status "blocked" --arg updated_at "$NOW" --arg blocked_tool "$TOOL" \
      '{status:$status, updated_at:$updated_at, blocked_tool:$blocked_tool}')
    registry_merge "$CWD" "$PATCH"
    ;;

  Stop)
    PATCH=$(jq -n --arg status "idle" --arg updated_at "$NOW" \
      '{status:$status, updated_at:$updated_at, blocked_tool:null}')
    registry_merge "$CWD" "$PATCH"
    ;;

  SessionEnd)
    registry_remove "$CWD"
    ;;

  *)
    : # evento no manejado, ignorar
    ;;
esac

exit 0
