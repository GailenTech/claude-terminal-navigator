---
name: terminal-nav
description: Da conciencia de las sesiones de Claude Code activas en otras terminales, proyectos y worktrees de este usuario en macOS, y permite listarlas, saltar a ellas (Terminal.app) o abrir una sesión nueva. Úsalo cuando el usuario pregunte qué otras sesiones/terminales/agentes tiene abiertos, en qué estado están (trabajando/bloqueado/parado), pida saltar o llevarle a otra sesión, o pida abrir/lanzar una sesión nueva en otro proyecto o worktree.
---

# Terminal Navigator

CLI: `/Volumes/DevelopmentProjects/Claude/claude-terminal-navigator/bin/nav`

Da visibilidad y control sobre todas las sesiones de Claude Code activas del
usuario en Terminal.app, agrupadas por proyecto y worktree, con su estado real
(no heurística): `working`, `blocked`, `idle`. El estado lo alimentan hooks
nativos de Claude Code (no polling de CPU ni lectura de pantalla), así que es
exacto.

## Comandos

- `nav list` — todas las sesiones activas, agrupadas por proyecto, con rama,
  ruta del worktree, estado y hora de última actividad.
- `nav jump <patrón>` — activa en Terminal.app la pestaña de la sesión cuyo
  proyecto o ruta de worktree contiene `<patrón>` (case-insensitive). Si hay
  varias coincidencias, lista las opciones en vez de adivinar.
- `nav spawn [--window|--tab] <ruta>` — abre una sesión nueva de `claude` en
  `<ruta>`. Por defecto abre una **pestaña nueva en la ventana actual** de
  Terminal.app; con `--window` fuerza una ventana nueva.
- `nav worktrees <ruta-del-proyecto>` — lista todos los worktrees git de ese
  proyecto (existan o no tengan sesión activa), cruzados con el registro para
  marcar cuáles tienen una sesión de Claude Code corriendo encima.

## Cuándo usarlo

- El usuario pregunta "¿qué tengo abierto?", "¿cómo van mis otras sesiones?",
  "¿hay alguna esperando que le apruebe algo?" → `nav list`.
- El usuario pide ir a otra sesión/proyecto/terminal → `nav jump <patrón>`.
  Si `nav jump` devuelve varias coincidencias, pregunta al usuario cuál en
  vez de elegir por él.
- El usuario pide abrir/lanzar trabajo en otro proyecto o worktree, o
  "arranca una sesión para X" → `nav spawn <ruta>`. Confirma la ruta antes
  si no es inequívoca (p. ej. el usuario da solo un nombre de proyecto).
- El usuario pregunta por los worktrees de un proyecto, o quiere saber cuáles
  están libres para usar → `nav worktrees <ruta>`.

## Limitaciones a tener en cuenta

- Solo Terminal.app en macOS — no funciona con iTerm2, Ghostty, etc.
- El registro vive en `~/.claude-nav/sessions/`, indexado por directorio de
  trabajo: si dos sesiones comparten exactamente el mismo `cwd` (no un
  worktree distinto), solo la más reciente en escribir queda registrada.
- El estado depende de que los hooks estén instalados globalmente en
  `~/.claude/settings.json` (evento `SessionStart`, `UserPromptSubmit`,
  `PreToolUse`, `PermissionRequest`, `Stop`, `SessionEnd` →
  `hooks/hook-handler.sh <evento>`). Sin eso, `nav list` no verá nada.
