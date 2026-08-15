---
name: navs
description: Muestra directamente el listado de sesiones de Claude Code activas (equivalente a "nav list"), sin interpretación adicional. Solo se invoca explícitamente por el usuario con /terminal-nav:navs — nunca de forma proactiva.
disable-model-invocation: true
---

Sesiones de Claude Code activas ahora mismo:

!`${CLAUDE_PLUGIN_ROOT}/bin/nav list`

Muestra esta salida tal cual, sin añadir interpretación, resumen ni comentario
adicional — el usuario solo quiere ver el estado en crudo.
