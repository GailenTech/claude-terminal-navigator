# Troubleshooting - Claude Terminal Navigator

## 🔍 Problemas comunes y soluciones

### Error: "Terminal ha detectado un error (-10000)"

**Causa**: Terminal.app no tiene permisos de accesibilidad.

**Solución**:
1. Ejecuta `check-permissions`
2. Ve a: Configuración del Sistema > Privacidad y Seguridad > Accesibilidad
3. Desbloquea con el candado inferior
4. Busca y marca "Terminal"
5. Si no aparece, arrástralo desde `/System/Applications/Utilities/Terminal.app`
6. Reinicia Terminal

### No encuentra las pestañas / No navega automáticamente

**Posibles causas**:
1. No estás usando el wrapper
2. Los permisos no están correctamente configurados
3. La sesión se cerró

**Diagnóstico paso a paso**:

```bash
# 1. Verifica que estás usando el wrapper
which claude
# Debe mostrar: /Users/jorge/claude-terminal-navigator/bin/claude-nav

# 2. Verifica que hay sesiones activas
ls -la ~/.claude/sessions/
# Deberías ver archivos .json con PIDs

# 3. Ejecuta limpieza manual
claude-cleanup

# 4. Verifica permisos
check-permissions
```

### El comando 'claude' ejecuta el Claude original, no el wrapper

**Causa**: El alias no está configurado o hay un conflicto de PATH.

**Solución**:
```bash
# Verifica el alias
alias claude

# Si no muestra nada o muestra el path incorrecto:
alias claude='claude-nav'

# Para hacerlo permanente, añade a ~/.zshrc:
alias claude='claude-nav'
```

### Sesiones fantasma (archivos que no se limpian)

**Causa**: El proceso Claude terminó abruptamente sin ejecutar la limpieza.

**Solución**:
```bash
# Limpieza manual
claude-cleanup

# O elimina todos los archivos de sesión
rm -f ~/.claude/sessions/*.json
```

### Ghostty no navega a la pestaña correcta

**Causa**: Ghostty no tiene API AppleScript completa.

**Solución actual**:
- El script activa Ghostty y muestra información
- Usa `Cmd+1`, `Cmd+2`, etc. para navegar manualmente
- Espera a que Ghostty añada soporte AppleScript

### Error al instalar: "No se pudo detectar el shell"

**Causa**: Estás usando un shell no estándar.

**Solución manual**:
```bash
# Añade estas líneas a tu archivo de configuración del shell:
export PATH="/Users/jorge/claude-terminal-navigator/bin:$PATH"
alias claude='claude-nav'
alias clj='claude-jump'
```

## 🛠️ Comandos de diagnóstico útiles

### Ver todas las sesiones activas
```bash
for f in ~/.claude/sessions/*.json; do
    [ -e "$f" ] || continue
    echo "=== $f ==="
    cat "$f"
    echo ""
done
```

### Verificar si un proceso Claude está vivo
```bash
ps aux | grep -E 'claude\s+$' | grep -v grep
```

### Ver el TTY de la pestaña actual
```bash
tty
```

### Debug del wrapper
```bash
# Ejecuta el wrapper con bash -x para ver cada comando
bash -x claude-nav
```

## 🔧 Configuración avanzada

### Cambiar el directorio de sesiones
```bash
export CLAUDE_NAV_DIR="$HOME/.config/claude-navigator"
```

### Desactivar el registro de sesiones temporalmente
```bash
# Usa el comando claude original directamente
/opt/homebrew/bin/claude
```

### Ver logs de AppleScript
```bash
# Ejecuta el jump script con salida de error
claude-jump 2>&1
```

## ❓ FAQ

**P: ¿Funciona con iTerm2?**
R: Aún no, pero es posible añadir soporte. iTerm2 tiene buena API AppleScript.

**P: ¿Puedo usar esto con tmux/screen?**
R: El TTY será el mismo para todas las ventanas tmux dentro de una pestaña, así que la navegación será a nivel de pestaña del terminal, no de ventana tmux.

**P: ¿Consume muchos recursos?**
R: No, solo crea pequeños archivos JSON temporales que se limpian automáticamente.

**P: ¿Puedo cambiar el comando claude original que se ejecuta?**
R: Sí, edita `CLAUDE_ORIGINAL` en `claude-nav`.

## 📞 Soporte

Si encuentras un problema no listado aquí:
1. Ejecuta `check-permissions` primero
2. Revisa los logs con `claude-jump 2>&1`
3. Verifica la estructura de archivos de sesión

¿Sigue sin funcionar? Crea un issue con:
- Sistema operativo y versión
- Terminal usado
- Salida de `check-permissions`
- Salida de `ls -la ~/.claude/sessions/`