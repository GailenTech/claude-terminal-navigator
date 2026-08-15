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

# Sin cwd no podemos indexar nada; salir en silencio sin bloquear a Claude.
[ -z "$CWD" ] && exit 0

# Camino rápido para SessionEnd: solo hace falta el cwd para borrar la
# entrada. SessionEnd comparte un presupuesto de tiempo muy ajustado entre
# todos sus hooks, así que evitamos cualquier trabajo (ps, date, más jq)
# que no sea estrictamente necesario para el borrado.
if [ "$EVENT" = "SessionEnd" ]; then
  registry_remove "$CWD"
  exit 0
fi

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Bootstrap: si no hay entrada para este cwd, o la que hay tiene un pid
# que ya no está vivo (sesión anterior distinta reusando el mismo cwd),
# la rellenamos aquí con lo que tengamos disponible AHORA. Esto hace que
# cualquier hook pueda dar de alta una sesión, no solo SessionStart —
# importante para sesiones que ya estaban corriendo antes de instalar
# los hooks: su primer evento nunca será SessionStart, pero sí llegará
# un UserPromptSubmit/PreToolUse/Stop tarde o temprano.
EXISTING_PID=$(registry_get "$CWD" | jq -r '.pid // empty' 2>/dev/null || true)
if [ -z "$EXISTING_PID" ] || ! kill -0 "$EXISTING_PID" 2>/dev/null; then
  BOOTSTRAP_SESSION_ID=$(echo "$PAYLOAD" | jq -r '.session_id // empty')
  BOOTSTRAP_PID="$PPID"
  BOOTSTRAP_TTY=$(ps -o tty= -p "$BOOTSTRAP_PID" 2>/dev/null | tr -d ' ') || true
  BOOTSTRAP_GIT=$(registry_git_info "$CWD")
  BOOTSTRAP_PATCH=$(jq -n \
    --arg cwd "$CWD" --arg session_id "$BOOTSTRAP_SESSION_ID" \
    --arg pid "$BOOTSTRAP_PID" --arg tty "$BOOTSTRAP_TTY" --arg started_at "$NOW" \
    --argjson git "$BOOTSTRAP_GIT" \
    '{cwd:$cwd, session_id:$session_id, pid:($pid|tonumber), tty:$tty,
      started_at:$started_at} * $git')
  registry_merge "$CWD" "$BOOTSTRAP_PATCH"
fi

case "$EVENT" in
  SessionStart)
    MODEL=$(echo "$PAYLOAD" | jq -r '.model // empty')
    PATCH=$(jq -n --arg status "idle" --arg updated_at "$NOW" --arg model "$MODEL" \
      '{status:$status, updated_at:$updated_at, model:$model}')
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
