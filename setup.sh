#!/bin/bash
# setup.sh - Instala terminal-nav en la configuración global de Claude Code
# Uso: ./setup.sh [--check-only]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HANDLER="$SCRIPT_DIR/hooks/hook-handler.sh"
SETTINGS="$HOME/.claude/settings.json"
SETTINGS_BACKUP="$SETTINGS.bak-$(date -u +%Y%m%d%H%M%S)"

if [ ! -f "$HANDLER" ]; then
  echo "Error: hook-handler.sh no encontrado en $HANDLER" >&2
  exit 1
fi

if [ ! -f "$SETTINGS" ]; then
  echo "Error: $SETTINGS no existe. ¿Claude Code está instalado?" >&2
  exit 1
fi

check_only="${1:-}"

# Función para añadir un hook a settings.json si no existe ya
add_hook_if_missing() {
  local event="$1"
  local exists
  exists=$(jq --arg h "$HANDLER" --arg e "$event" \
    '.hooks[$e][]? | select(.hooks[]? | select(.command | contains($h)))' \
    "$SETTINGS" 2>/dev/null)

  if [ -n "$exists" ]; then
    echo "  ✓ $event: ya existe"
    return 0
  fi

  if [ -n "$check_only" ]; then
    echo "  ✗ $event: falta instalar"
    return 1
  fi

  echo "  → $event: instalando..."
  # Usar jq para fusionar el hook nuevo sin tocar lo existente
  jq --arg h "$HANDLER" --arg e "$event" \
    '.hooks[$e] = (.hooks[$e] // []) + [{"hooks":[{"type":"command","command":($h + " " + $e)}]}]' \
    "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
  echo "  ✓ $event: instalado"
}

if [ -n "$check_only" ]; then
  echo "Comprobando hooks de terminal-nav en $SETTINGS..."
  local status=0
  for event in SessionStart UserPromptSubmit PreToolUse PermissionRequest Stop SessionEnd; do
    add_hook_if_missing "$event" || status=1
  done

  if [ $status -eq 0 ]; then
    echo ""
    echo "✓ Todos los hooks están instalados."
    exit 0
  else
    echo ""
    echo "✗ Faltan algunos hooks. Ejecuta: $0 (sin argumentos)"
    exit 1
  fi
fi

# Instalación real
echo "Instalando terminal-nav hooks..."
echo "Backup: $SETTINGS_BACKUP"
cp "$SETTINGS" "$SETTINGS_BACKUP"

for event in SessionStart UserPromptSubmit PreToolUse PermissionRequest Stop SessionEnd; do
  add_hook_if_missing "$event"
done

# Verificar que el JSON es válido
if ! jq . "$SETTINGS" > /dev/null 2>&1; then
  echo ""
  echo "Error: JSON inválido después de la instalación. Revirtiendo..." >&2
  mv "$SETTINGS_BACKUP" "$SETTINGS"
  exit 1
fi

echo ""
echo "✓ terminal-nav instalado correctamente."
echo ""
echo "Siguientes pasos:"
echo "  1. Abre una nueva sesión de Claude Code en cualquier proyecto"
echo "  2. Usa 'nav list' para ver las sesiones activas"
echo "  3. Lee SKILL.md para ver todos los comandos disponibles"
echo ""
echo "Para desinstalar, restaura el backup:"
echo "  mv $SETTINGS_BACKUP $SETTINGS"
