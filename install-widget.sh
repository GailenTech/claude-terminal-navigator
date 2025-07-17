#!/bin/bash
# install-widget.sh - Instalador del widget de barra de menú para Claude Terminal Navigator

set -e

# Colores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Banner
echo -e "${BLUE}"
echo "╔════════════════════════════════════════════════╗"
echo "║  Claude Terminal Navigator - Widget Installer   ║"
echo "╚════════════════════════════════════════════════╝"
echo -e "${NC}"

# Variables
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
XBAR_PLUGIN="$PROJECT_DIR/xbar-plugin/claude-monitor.5s.sh"
XBAR_PLUGINS_DIR="$HOME/Library/Application Support/xbar/plugins"

# 1. Verificar si xbar está instalado
echo -e "${YELLOW}1. Verificando instalación de xbar...${NC}"

if ! command -v xbar &> /dev/null && [ ! -d "/Applications/xbar.app" ]; then
    echo -e "${RED}❌ xbar no está instalado${NC}"
    echo ""
    echo "Para instalar xbar:"
    echo ""
    echo "Opción 1 - Homebrew:"
    echo -e "${BLUE}brew install --cask xbar${NC}"
    echo ""
    echo "Opción 2 - Descarga directa:"
    echo -e "${BLUE}https://xbarapp.com${NC}"
    echo ""
    read -p "¿Deseas instalar xbar con Homebrew ahora? (s/n): " install_xbar
    
    if [[ "$install_xbar" =~ ^[sS]$ ]]; then
        if command -v brew &> /dev/null; then
            echo -e "${YELLOW}Instalando xbar...${NC}"
            brew install --cask xbar
        else
            echo -e "${RED}❌ Homebrew no está instalado${NC}"
            echo "Instala xbar manualmente desde https://xbarapp.com"
            exit 1
        fi
    else
        echo "Por favor, instala xbar primero y vuelve a ejecutar este instalador"
        exit 1
    fi
else
    echo -e "${GREEN}✅ xbar está instalado${NC}"
fi

# 2. Verificar que Claude Terminal Navigator esté instalado
echo ""
echo -e "${YELLOW}2. Verificando Claude Terminal Navigator...${NC}"

if [ ! -f "$PROJECT_DIR/bin/claude-nav" ]; then
    echo -e "${RED}❌ Claude Terminal Navigator no está correctamente instalado${NC}"
    echo "Ejecuta primero: ./install.sh"
    exit 1
fi

echo -e "${GREEN}✅ Claude Terminal Navigator detectado${NC}"

# 3. Crear directorio de plugins si no existe
echo ""
echo -e "${YELLOW}3. Configurando directorio de plugins...${NC}"

if [ ! -d "$XBAR_PLUGINS_DIR" ]; then
    echo "Creando directorio de plugins..."
    mkdir -p "$XBAR_PLUGINS_DIR"
fi

echo -e "${GREEN}✅ Directorio de plugins configurado${NC}"

# 4. Copiar o enlazar el plugin
echo ""
echo -e "${YELLOW}4. Instalando plugin...${NC}"

PLUGIN_DEST="$XBAR_PLUGINS_DIR/claude-monitor.5s.sh"

# Verificar si ya existe
if [ -e "$PLUGIN_DEST" ]; then
    echo -e "${YELLOW}⚠️  Ya existe un plugin instalado${NC}"
    read -p "¿Deseas reemplazarlo? (s/n): " replace
    
    if [[ ! "$replace" =~ ^[sS]$ ]]; then
        echo "Instalación cancelada"
        exit 0
    fi
    
    rm -f "$PLUGIN_DEST"
fi

# Crear enlace simbólico para facilitar actualizaciones
ln -s "$XBAR_PLUGIN" "$PLUGIN_DEST"
echo -e "${GREEN}✅ Plugin instalado${NC}"

# 5. Hacer el plugin ejecutable
chmod +x "$XBAR_PLUGIN"

# 6. Actualizar paths en el plugin
echo ""
echo -e "${YELLOW}5. Configurando paths...${NC}"

# Actualizar el path al directorio bin en el plugin
sed -i.backup "s|SCRIPT_DIR=.*|SCRIPT_DIR=\"$PROJECT_DIR/bin\"|" "$XBAR_PLUGIN"
rm -f "$XBAR_PLUGIN.backup"

echo -e "${GREEN}✅ Paths configurados${NC}"

# 7. Verificar y lanzar xbar
echo ""
echo -e "${YELLOW}6. Lanzando xbar...${NC}"

if pgrep -x "xbar" > /dev/null; then
    echo "xbar ya está ejecutándose. Refrescando plugins..."
    # Intentar refrescar xbar
    osascript -e 'tell application "xbar" to refresh' 2>/dev/null || true
else
    echo "Iniciando xbar..."
    open -a "xbar" 2>/dev/null || true
fi

# 8. Instrucciones finales
echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║    ¡Widget instalado con éxito! 🎉      ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}El widget de Claude Terminal Navigator está listo:${NC}"
echo ""
echo "• Busca el icono 'Claude 🤖' en la barra de menú"
echo "• Click para ver sesiones activas"
echo "• El widget se actualiza cada 5 segundos"
echo ""
echo -e "${BLUE}Características del widget:${NC}"
echo "• 🟢 Sesiones activas (CPU > 5%)"
echo "• 🟡 Sesiones en espera"
echo "• 📊 Monitoreo de CPU y memoria"
echo "• ⏱️  Duración de sesiones"
echo "• 🔍 Click para navegar a cualquier sesión"
echo ""
echo -e "${YELLOW}Configuración de xbar:${NC}"
echo "• Si no ves el widget, abre xbar preferences"
echo "• Asegúrate de que el plugin folder sea:"
echo "  $XBAR_PLUGINS_DIR"
echo ""
echo -e "${YELLOW}💡 Tips:${NC}"
echo "• Click derecho en xbar > Refresh all para actualizar"
echo "• Puedes editar el intervalo cambiando '5s' en el nombre del archivo"
echo "  (ej: claude-monitor.1s.sh para actualizar cada segundo)"
echo ""