# DIARY.md - Diario de Desarrollo

## 2025-01-17 - Cumplimiento de normas básicas y setup inicial

### Lo que se hizo
- Análisis de cumplimiento con normas establecidas en CLAUDE.md global
- Inicialización de repositorio Git
- Push del código a GitHub en organización GailenTech
- Creación de DOCS.md como índice central de documentación
- Creación de este diario de desarrollo

### Decisiones tomadas
- Usar GailenTech como organización GitHub en lugar de cuenta personal
- Mantener estructura de documentación en `/docs` como ya estaba establecida
- Priorizar cumplimiento de normas básicas antes de nuevas features

### Desafíos/Aprendizajes
- El proyecto no tenía Git inicializado, violando principio fundamental
- Faltaban archivos esenciales: DOCS.md y DIARY.md
- No hay tests implementados aún (pendiente para cuando sea necesario)

### Próximos pasos
- Hacer commit de los cambios de documentación
- Considerar implementación de tests básicos
- Evaluar necesidad de directorio `claude_tools/`

---

## 2025-01-17 - Widget de barra de menú para macOS

### Lo que se hizo
- Investigación de opciones para widget de macOS (xbar, rumps, SwiftUI)
- Implementación de plugin xbar para monitoreo desde la barra de menú
- Monitoreo de CPU, memoria y estado de sesiones en tiempo real
- Navegación rápida a sesiones con un click
- Instalador automático para el widget

### Decisiones tomadas
- Usar xbar como plataforma por su integración perfecta con bash
- Actualización cada 5 segundos (configurable)
- Estados de sesión: activa (CPU > 5%) vs esperando
- Mantener consistencia con scripts existentes

### Desafíos/Aprendizajes
- xbar permite crear widgets complejos solo con bash
- El monitoreo de CPU requiere parsing cuidadoso de `ps`
- La integración con AppleScript funciona bien desde xbar

### Próximos pasos
- Considerar notificaciones cuando las sesiones terminen
- Añadir gráficos de uso histórico
- Posible versión standalone con rumps/Python

---

## 2025-01-17 - Aplicación Swift nativa implementada

### Lo que se hizo
- Implementación completa de app Swift nativa para menu bar
- Integración con scripts bash existentes (híbrido)
- Monitoreo asíncrono de CPU y memoria
- UI nativa con menús y submenús detallados
- Script de compilación automatizado

### Decisiones tomadas
- Enfoque híbrido: Swift llama a scripts bash existentes
- Usar SwiftUI/AppKit para máxima compatibilidad
- Cachear valores de CPU/memoria para mejor rendimiento
- Mantener compatibilidad con macOS 11+

### Desafíos/Aprendizajes
- Propiedades async en Swift requieren manejo especial
- NSUserNotification deprecado, pero alternativas requieren más setup
- La compilación con Swift Package Manager simplifica distribución

### Próximos pasos
- Añadir preferencias de usuario
- Implementar auto-update con Sparkle
- Mejorar iconos y recursos visuales
- Considerar firma y notarización para distribución

---

## 2025-01-16 - Creación inicial del proyecto

### Lo que se hizo
- Implementación completa de Claude Terminal Navigator
- Sistema de tracking de sesiones basado en TTY
- Navegación automática para Terminal.app
- Soporte parcial para Ghostty
- Instalador automático con detección de shell
- Documentación comprehensiva y troubleshooting

### Decisiones tomadas
- Usar TTY como identificador único de pestañas
- Implementar wrapper pattern para interceptar llamadas a Claude
- Archivos JSON simples para almacenar sesiones (sin daemon)
- AppleScript para integración con Terminal.app

### Desafíos/Aprendizajes
- Terminal.app requiere permisos de accesibilidad específicos
- Ghostty tiene API limitada, requiere navegación manual
- La limpieza automática de sesiones es crítica para evitar acumulación

### Próximos pasos
- Añadir soporte para iTerm2
- Mejorar detección de terminales
- Implementar tests automatizados