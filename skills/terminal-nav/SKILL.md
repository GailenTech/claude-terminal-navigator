---
name: terminal-nav
description: Da consciencia de OTRAS sesiones de Claude Code (no esta) activas en otras pestañas/terminales/proyectos/worktrees de este usuario en macOS — listarlas, saltar a ellas, abrir una nueva, o liberar un worktree. TRIGGER — dispara cuando el usuario pregunte "qué tengo abierto", "cómo van mis otras sesiones/terminales/agentes", "hay alguna esperando que le apruebe algo/bloqueada", pida "salta a", "llévame a", "ve a la sesión/terminal de X"; pida "abre/lanza/arranca una sesión/terminal nueva" (en otro proyecto, worktree, o rama); pida "llévate esto a otra sesión/worktree" o "sigue esto en paralelo"; pregunte por los worktrees de un repo o cuáles están libres; o pida "cierra/libera/borra ese worktree". Palabras clave: sesiones, pestañas, terminales, worktree(s), rama nueva, otra sesión, en paralelo, background. NO dispares para preguntas sobre esta misma conversación/sesión actual.
---

# Terminal Navigator

CLI: `${CLAUDE_PLUGIN_ROOT}/bin/nav` (una vez instalado el plugin, `bin/`
queda en el PATH, así que también funciona como `nav` a secas en cualquier
terminal).

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
- `nav spawn [--window|--tab] [--worktree <rama> [--from <rama-base>]] [--prompt <texto>] [--permission-mode <modo>] <ruta>` —
  abre una sesión nueva de `claude` en `<ruta>`. Por defecto abre una
  **pestaña nueva en la ventana actual** de Terminal.app; con `--window`
  fuerza una ventana nueva.
  - `--worktree <rama>`: crea (o reutiliza si ya existe) un worktree
    hermano del repo en `<ruta>` para esa rama, y lanza ahí en vez de en
    `<ruta>` directamente. Parte de la rama actual del worktree de origen
    salvo que se indique `--from <rama-base>`.
  - **Modo de permisos**: la sesión nueva arranca en el MISMO modo que la que
    la abre (auto, acceptEdits, plan, bypass…). El modo lo dejan los hooks en el
    registro con cada evento, así que es el de AHORA y no el de arranque — la
    diferencia importa cuando se ha cambiado a mano con shift+tab. Con
    `--permission-mode <modo>` se fuerza otro; si no hay nada que heredar
    (hooks sin instalar) avisa y cae en `--dangerously-skip-permissions`, que
    es lo que nav hacía siempre.
  - `--prompt <texto>`: la sesión nueva arranca ya con ese prompt (`claude
    "<texto>"`) en vez de con el prompt vacío. Útil para "llevarse" un
    hilo de trabajo a una sesión/worktree nuevo: compón un resumen de
    contexto y pásalo aquí en vez de pedirle al usuario que lo reescriba.
  - Si `--worktree` crea una rama **nueva** (no reutiliza una existente),
    se antepone automáticamente al prompt una nota avisando a la sesión
    nueva de que ya está en la rama pensada para eso y no debe crear otra
    encima. No hace falta que tú añadas ese aviso a mano.
  - Por defecto lanza con `claude --remote-control "<nombre>"`, usando
    la rama de `--worktree` (o la rama actual de `<ruta>`, o el nombre
    del directorio si no hay rama) como nombre de sesión — así se
    identifica en el móvil/otro dispositivo cuál es cuál. `--no-remote-
    control` lo desactiva para esa sesión. Requiere suscripción Pro/Max/
    Team/Enterprise y `/login` ya hecho; si no se cumple, la sesión
    arranca igual y solo se ve una notificación de fallo, no bloquea nada.
  - Por defecto lanza también con `--dangerously-skip-permissions` (así
    trabaja el usuario habitualmente). `--no-skip-permissions` lo
    desactiva para esa sesión si hace falta más cuidado (p. ej. un
    worktree en el que no confías tanto).
  - `--fork`: en vez de (o además de) `--prompt`, hereda el **historial
    completo** de la sesión de Claude Code registrada en `<ruta>` (vía
    `claude --resume <session_id> --fork-session`), usando el
    `session_id` que ya guarda el registro de `nav` — no un resumen
    escrito a mano. Solo funciona si esa sesión pasó por los hooks
    (arrancó o interactuó después de instalarlos; una sesión detectada
    solo por `nav scan` no tiene `session_id`, avisa por stderr y lanza
    sin fork en vez de fallar). **Ojo con la working copy**: `--resume`
    restaura la conversación, no el estado de ficheros — si el origen
    tiene cambios sin commitear, no se copian al worktree nuevo, y la
    conversación heredada puede hablar de ediciones que ahí no existen.
    Se avisa por stderr si detecta esto, no se bloquea (a diferencia de
    `nav prune`, forkear no es destructivo).
- `nav worktrees <ruta-del-proyecto>` — lista todos los worktrees git de ese
  proyecto (existan o no tengan sesión activa), cruzados con el registro para
  marcar cuáles tienen una sesión de Claude Code corriendo encima.
- `nav scan` — reconciliación completa del registro: purga entradas con
  pid muerto Y da de alta sesiones de Claude Code que ya estaban corriendo
  antes de instalar los hooks (o que aún no han pasado por ninguno) —
  busca procesos `claude` con tty real y los registra. Úsalo justo después
  de instalar, o si `nav list` muestra menos sesiones de las que sabes que
  tienes abiertas. Las sesiones dadas de alta así aparecen con estado `❔`
  hasta que interactúes con ellas (entonces se corrige solo).
- `nav sweep [<ruta>] [--no-fetch]` — **decide qué se puede retirar, y no borra
  nada.** Recorre los worktrees del proyecto y los reparte en tres grupos, con el
  motivo de cada veredicto: **EN USO** (sesión viva), **CONSERVAR** (cambios sin
  commitear, o commits que no están en `origin/<principal>`) y **PODABLES**
  (contenido a salvo). Para los podables imprime el `nav prune` correspondiente,
  uno por línea. Hace `fetch` primero: sin eso, una rama principal local
  desactualizada inventa commits propios que no existen.
  - Marca con ⚠ el caso peligroso: commits que no están en la base, **sin PR y
    con la rama remota borrada** — trabajo que no está en ningún otro sitio.
  - Deliberadamente **no ejecuta nada**: un barrido que decide y borra a la vez
    puede llevarse varios worktrees por un único fallo de señal.
- `nav prune <ruta-del-worktree> [--delete-branch [--force]]` — libera un
  worktree con seguridad. **Por defecto solo quita el worktree** (barato,
  reversible: la rama y sus commits siguen intactos). Se niega a tocar
  nada si hay una sesión de Claude viva ahí dentro, o si hay cambios sin
  commitear — en ambos casos para y te lo dice, nunca descarta nada solo.
  - `--delete-branch`: además borra la rama, con `git branch -d` (el
    seguro: se niega si no está mergeada).
  - `--delete-branch --force`: borra la rama aunque no esté mergeada
    (`git branch -D` — commits perdidos para siempre). Solo cuando el
    usuario lo pida explícitamente sabiendo lo que implica.

## Cuándo usarlo

- El usuario pregunta "¿qué tengo abierto?", "¿cómo van mis otras sesiones?",
  "¿hay alguna esperando que le apruebe algo?" → `nav list`.
- El usuario pide ir a otra sesión/proyecto/terminal → `nav jump <patrón>`.
  Si `nav jump` devuelve varias coincidencias, pregunta al usuario cuál en
  vez de elegir por él.
- El usuario pide abrir/lanzar trabajo en otro proyecto o worktree, o
  "arranca una sesión para X" → `nav spawn <ruta>`. Confirma la ruta antes
  si no es inequívoca (p. ej. el usuario da solo un nombre de proyecto).
- El usuario ha estado profundizando en un tema lateral y pide "llévate
  esto a otra sesión/worktree y sigamos aquí con lo de antes":
  - Si necesitas que la sesión nueva tenga el **historial real y
    completo** (código exacto probado, errores concretos, matices que un
    resumen perdería) → `nav spawn --worktree <rama-nueva> --fork
    <ruta-del-repo>`. Si además quieres añadir instrucciones concretas
    encima de ese historial, combina `--fork --prompt "<texto>"`.
  - Si un resumen escrito por ti basta (el hilo lateral es corto o
    autocontenido) → compón un resumen conciso y llama a
    `nav spawn --worktree <rama-nueva> --prompt "<resumen>" <ruta-del-repo>`.
  - En ambos casos, después retoma tú (la sesión actual) el tema
    original — no hace falta nada más por tu parte.
- El usuario pregunta por los worktrees de un proyecto, o quiere saber cuáles
  están libres para usar → `nav worktrees <ruta>`.
- `nav list` muestra menos sesiones de las que el usuario dice tener
  abiertas (típicamente justo tras instalar) → sugiere o ejecuta
  `nav scan`.
- El usuario ha terminado con un worktree y quiere "cerrarlo" o
  "liberarlo" → `nav prune <ruta>` (sin `--delete-branch` salvo que
  pida explícitamente borrar también la rama). Nunca uses `--force` sin
  que el usuario lo pida de forma inequívoca sabiendo que puede perder
  commits.
- El usuario pregunta qué worktrees sobran, quiere hacer limpieza, o dice
  cosas como "esto ya está mergeado, ¿no?" → `nav sweep`. **Enséñale los tres
  grupos y deja que elija**: tú no decides qué se retira. Después ejecuta un
  `nav prune` por cada uno que apruebe — nunca en bucle sobre todos los
  podables. El propio `prune` vuelve a comprobarlo todo en ese momento, así
  que un informe de hace un rato no puede hacer daño.
- Si `sweep` marca alguno con ⚠ (commits sin PR y con la remota borrada),
  dilo explícitamente: ahí hay trabajo que solo existe en ese disco.

## Limitaciones a tener en cuenta

- Solo Terminal.app en macOS — no funciona con iTerm2, Ghostty, etc.
- El registro vive en `~/.claude-nav/sessions/`, indexado por directorio de
  trabajo: si dos sesiones comparten exactamente el mismo `cwd` (no un
  worktree distinto), solo la más reciente en escribir queda registrada.
- El estado depende de que los hooks estén instalados globalmente en
  `~/.claude/settings.json` (evento `SessionStart`, `UserPromptSubmit`,
  `PreToolUse`, `PermissionRequest`, `Stop`, `SessionEnd` →
  `hooks/hook-handler.sh <evento>`). Sin eso, `nav list` no verá nada.
- `nav prune` y `nav sweep` comprueban contra `origin/<principal>`, con
  `fetch` previo — no contra la rama principal local, que suele ir por detrás
  (medido: dos PR de retraso daban 37 commits propios a una rama recién
  creada). Con squash-merge, `git branch -d` se niega aunque el contenido esté
  integrado; `prune` lo detecta y borra igual, pero sólo tras comprobar por su
  cuenta que no queda nada fuera de la base.
- El "¿hay sesión viva aquí?" no se fía sólo del PID: **los PID se reciclan**
  (visto en vivo — el registro de un worktree abandonado apuntaba a un pid que
  ya era de otra sesión). Se exige además que el proceso sea `claude` y que su
  cwd caiga dentro del worktree. Si eso no se puede comprobar (sin `lsof`, o
  permisos), se asume **viva**: ante la duda no se borra.
- `nav sweep` usa `gh` para ver si hay PR mergeado. Sin `gh` disponible o
  autenticado sigue funcionando, pero pierde esa señal: las ramas integradas
  por squash aparecerán como conservables en vez de podables. Falla hacia el
  lado seguro.
