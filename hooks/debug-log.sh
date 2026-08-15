#!/bin/bash
# debug-log.sh - Vuelca lo que realmente manda cada hook, para verificar antes de construir sobre supuestos.
# No hace nada más: solo registra. Bórralo cuando ya no lo necesitemos.

LOG_FILE="$(dirname "$0")/../debug-hooks.log"
STDIN_JSON=$(cat)

# Recorre el árbol de procesos hacia arriba desde $PPID hasta encontrar
# el primero con un tty real (debería ser el shell de login de la pestaña).
walk_tree() {
  local pid="$PPID"
  local i=0
  while [ -n "$pid" ] && [ "$i" -lt 10 ]; do
    local line
    line=$(ps -o pid=,ppid=,tty=,comm= -p "$pid" 2>/dev/null)
    echo "  [$i] $line"
    local tty_val
    tty_val=$(echo "$line" | awk '{print $3}')
    if [ -n "$tty_val" ] && [ "$tty_val" != "??" ]; then
      echo "  -> FOUND TTY: $tty_val (pid $pid)"
      return
    fi
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    i=$((i + 1))
  done
  echo "  -> no real tty found in tree"
}

{
  echo "=== $(date -u +"%Y-%m-%dT%H:%M:%SZ") ==="
  echo "argv: $*"
  echo "PPID: $PPID"
  echo "tty (own): $(tty 2>/dev/null || echo 'no-tty')"
  echo "process tree walk:"
  walk_tree
  echo "stdin:"
  echo "$STDIN_JSON"
  echo ""
} >> "$LOG_FILE"

# No bloquear nada: siempre salir 0
exit 0
