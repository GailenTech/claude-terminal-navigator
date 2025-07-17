# Claude Terminal Navigator 🚀

Navegación automática e inteligente entre pestañas de terminal donde tienes sesiones activas de Claude.

## ✨ Características

- **Navegación automática**: Salta directamente a la pestaña correcta donde está tu sesión Claude
- **Detección inteligente**: Identifica sesiones por TTY en Terminal.app
- **Multi-terminal**: Soporte para Terminal.app (completo) y Ghostty (parcial)
- **Gestión de sesiones**: Rastrea y limpia automáticamente sesiones muertas
- **Sin configuración**: Funciona inmediatamente después de la instalación

## 🎯 ¿Cómo funciona?

1. **Al iniciar Claude**: El wrapper registra la sesión (TTY, PID, directorio)
2. **Al ejecutar jump**: Busca la sesión y navega automáticamente a la pestaña correcta
3. **Al cerrar Claude**: La sesión se limpia automáticamente

## 📦 Instalación

### Instalación rápida

```bash
cd /Users/jorge/claude-terminal-navigator
./install.sh
```

### Instalación manual

1. **Añade los aliases a tu shell** (`~/.zshrc` o `~/.bashrc`):

```bash
# Claude Terminal Navigator
export PATH="/Users/jorge/claude-terminal-navigator/bin:$PATH"
alias claude='claude-nav'
alias clj='claude-jump'
```

2. **Recarga tu configuración**:

```bash
source ~/.zshrc  # o ~/.bashrc
```

3. **Verifica permisos** (solo la primera vez):

```bash
check-permissions
```

## 🚀 Uso

### Uso básico

1. **Inicia Claude con tracking**:
```bash
claude  # Ahora registra la sesión automáticamente
```

2. **Salta a cualquier sesión Claude**:
```bash
clj  # Navegación automática
```

### Comandos disponibles

- `claude` - Ejecuta Claude con registro de sesión
- `clj` - Salta automáticamente a pestañas Claude
- `check-permissions` - Verifica permisos de Terminal
- `claude-cleanup` - Limpia manualmente sesiones muertas

## 🖥️ Soporte por Terminal

### Terminal.app ✅ (Soporte completo)
- Navegación automática por TTY
- Identifica exactamente la pestaña correcta
- Activa ventana y pestaña automáticamente

### Ghostty ⚠️ (Soporte parcial)
- Activa la aplicación
- Muestra información de la sesión
- Requiere navegación manual con `Cmd+1`, `Cmd+2`, etc.

### iTerm2 🔜 (Próximamente)
- En desarrollo

## 🔧 Configuración avanzada

### Cambiar directorio de sesiones

```bash
export CLAUDE_NAV_DIR="$HOME/.config/claude-navigator"
```

### Desactivar limpieza automática

Edita `claude-nav` y comenta la línea de limpieza.

## 🐛 Solución de problemas

### Error "Terminal ha detectado un error (-10000)"

Este es un problema de permisos. Ejecuta:

```bash
check-permissions
```

Y sigue las instrucciones para otorgar permisos de accesibilidad a Terminal.

### No encuentra las pestañas

1. Asegúrate de estar usando el wrapper (`claude`, no el comando original)
2. Verifica que hay sesiones activas: `ls ~/.claude/sessions/`
3. Ejecuta limpieza manual: `claude-cleanup`

### Sesión no se registra

Verifica que estás usando el alias correcto:
```bash
which claude  # Debe mostrar claude-nav
```

## 📂 Estructura del proyecto

```
claude-terminal-navigator/
├── bin/
│   ├── claude-nav          # Wrapper que registra sesiones
│   ├── claude-jump         # Navegador automático
│   ├── claude-cleanup      # Limpiador de sesiones
│   └── check-permissions   # Verificador de permisos
├── docs/
│   └── TROUBLESHOOTING.md  # Guía detallada de problemas
├── config/
│   └── example.conf        # Configuración de ejemplo
├── install.sh              # Instalador automático
└── README.md              # Este archivo
```

## 🤝 Contribuir

¿Tienes ideas para mejorar? ¡Bienvenidas!

1. Reporta bugs o sugiere mejoras
2. Añade soporte para tu terminal favorito
3. Mejora la documentación

## 📜 Licencia

MIT - Úsalo como quieras

## 🙏 Créditos

Creado con Claude 🤖 para mejorar la experiencia de usar Claude