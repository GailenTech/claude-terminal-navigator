#!/bin/bash
# registry.sh - Funciones compartidas para leer/escribir el registro de sesiones.
#
# Una sesión = un fichero JSON, indexado por su cwd (no por PID ni session_id):
# en la práctica no hay dos sesiones de Claude Code vivas a la vez en el mismo
# directorio exacto (worktrees ya dan rutas distintas), así que cwd es la clave
# más simple y evita tener que correlacionar PID <-> session_id entre el hook
# y ningún wrapper externo.

REGISTRY_DIR="${CLAUDE_NAV_DIR:-$HOME/.claude-nav}/sessions"

registry_ensure_dir() {
  mkdir -p "$REGISTRY_DIR"
}

# Convierte un cwd absoluto en un nombre de fichero seguro, con el mismo
# esquema que usa el propio Claude Code para sus directorios de proyecto.
registry_key_for_cwd() {
  local cwd="$1"
  echo "$cwd" | sed 's/[^A-Za-z0-9]/-/g'
}

registry_path_for_cwd() {
  local cwd="$1"
  echo "$REGISTRY_DIR/$(registry_key_for_cwd "$cwd").json"
}

# Info de git para un cwd: project (nombre del worktree principal),
# project_root (ruta del worktree principal), worktree (ruta de ESTE
# worktree) y branch. Todo vacío si no es un repo git.
registry_git_info() {
  local cwd="$1"
  local project_root project worktree branch

  # Ojo: esta función se usa "source"ada dentro de scripts con `set -e`
  # (hook-handler.sh, nav). Sin el `|| true`, un cwd que NO es repo git
  # haría que `git rev-parse` fallase y matase el script entero aquí
  # mismo, ANTES de llegar al `if` que se supone que maneja ese caso.
  worktree=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || true
  if [ -z "$worktree" ]; then
    echo '{}'
    return
  fi

  project_root=$(git -C "$cwd" worktree list 2>/dev/null | head -1 | awk '{print $1}') || true
  [ -z "$project_root" ] && project_root="$worktree"
  project=$(basename "$project_root")
  branch=$(git -C "$cwd" branch --show-current 2>/dev/null) || true

  jq -n \
    --arg project "$project" \
    --arg project_root "$project_root" \
    --arg worktree "$worktree" \
    --arg branch "$branch" \
    '{project: $project, project_root: $project_root, worktree: $worktree, branch: $branch}'
}

# Mezcla los campos de $2 (JSON) sobre la entrada existente de $1 (cwd),
# creándola si no existe. Escritura atómica (fichero temporal + mv).
registry_merge() {
  local cwd="$1"
  local patch_json="$2"
  registry_ensure_dir
  local path
  path=$(registry_path_for_cwd "$cwd")
  local existing="{}"
  [ -f "$path" ] && existing=$(cat "$path")

  local tmp
  tmp=$(mktemp "${path}.XXXXXX")
  jq -n --argjson existing "$existing" --argjson patch "$patch_json" \
    '$existing * $patch' > "$tmp" && mv "$tmp" "$path"
}

registry_get() {
  local cwd="$1"
  local path
  path=$(registry_path_for_cwd "$cwd")
  [ -f "$path" ] && cat "$path"
}

registry_remove() {
  local cwd="$1"
  rm -f "$(registry_path_for_cwd "$cwd")"
}

# Comprueba si el PID de una entrada sigue vivo.
registry_pid_alive() {
  local pid="$1"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

# ¿Sigue viva ESTA sesión, y no otro proceso que heredó su número?
#
# `kill -0` solo dice que ALGÚN proceso tiene ese pid. Los PID se reciclan, y
# entonces una sesión muerta parece viva: medido el 18-ago-2026 — el registro de
# un worktree abandonado apuntaba al pid 15968, que para entonces pertenecía a
# una sesión de Claude Code de OTRO worktree, abierta ese mismo día.
#
# Para decidir un borrado eso no basta. Aquí se exige, además del pid:
#   · que el proceso sea realmente `claude`, y
#   · que su directorio de trabajo sea el que dice el registro.
#
# El falso positivo (creer viva una sesión muerta) solo estorba; el falso
# negativo BORRA trabajo. Por eso, si no se puede comprobar el cwd —sin `lsof`,
# permisos denegados— se responde "viva": ante la duda, no se toca.
registry_session_alive() {
  local pid="$1" cwd="$2"
  [ -n "$pid" ] || return 1
  kill -0 "$pid" 2>/dev/null || return 1

  local args
  args=$(ps -o args= -p "$pid" 2>/dev/null) || return 0
  case "$args" in
    *claude*) ;;
    *) return 1 ;;   # el pid se reutilizó: no es una sesión de Claude Code
  esac

  [ -n "$cwd" ] || return 0
  command -v lsof >/dev/null 2>&1 || return 0

  local proc_cwd
  proc_cwd=$(lsof -a -d cwd -p "$pid" -Fn 2>/dev/null | sed -n 's/^n//p' | head -1) || return 0
  [ -z "$proc_cwd" ] && return 0
  # El cwd real puede ser un subdirectorio del worktree (nav registra por cwd).
  case "$proc_cwd" in
    "$cwd"|"$cwd"/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Imprime todas las entradas vivas (una por línea, JSON compacto),
# purgando de paso los ficheros de sesiones muertas.
registry_list_live() {
  registry_ensure_dir
  local f pid
  for f in "$REGISTRY_DIR"/*.json; do
    [ -e "$f" ] || continue
    pid=$(jq -r '.pid // empty' "$f" 2>/dev/null)
    if registry_pid_alive "$pid"; then
      jq -c '.' "$f"
    else
      rm -f "$f"
    fi
  done
}
