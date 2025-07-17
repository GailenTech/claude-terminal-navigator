#!/bin/bash
# install.sh - Instalador automático para Claude Terminal Navigator

set -e

# Colores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Banner
echo -e "${BLUE}"
echo "╔════════════════════════════════════════╗"
echo "║   Claude Terminal Navigator Installer   ║"
echo "╚════════════════════════════════════════╝"
echo -e "${NC}"

# Detectar shell
detect_shell() {
    if [ -n "$BASH_VERSION" ]; then
        echo "bash"
    elif [ -n "$ZSH_VERSION" ]; then
        echo "zsh"
    else
        echo "unknown"
    fi
}

# Obtener archivo de configuración del shell
get_shell_config() {
    local shell_type=$(detect_shell)
    
    if [ "$shell_type" = "zsh" ]; then
        echo "$HOME/.zshrc"
    elif [ "$shell_type" = "bash" ]; then
        if [ -f "$HOME/.bash_profile" ]; then
            echo "$HOME/.bash_profile"
        else
            echo "$HOME/.bashrc"
        fi
    else
        echo ""
    fi
}

# Directorio del proyecto
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$PROJECT_DIR/bin"

echo -e "${BLUE}📍 Directorio del proyecto:${NC} $PROJECT_DIR"
echo ""

# 1. Verificar que los scripts existen
echo -e "${YELLOW}1. Verificando archivos...${NC}"
required_files=("claude-nav" "claude-jump" "claude-cleanup" "check-permissions")
missing_files=()

for file in "${required_files[@]}"; do
    if [ ! -f "$BIN_DIR/$file" ]; then
        missing_files+=("$file")
    fi
done

if [ ${#missing_files[@]} -gt 0 ]; then
    echo -e "${RED}❌ Faltan archivos:${NC} ${missing_files[*]}"
    exit 1
fi

echo -e "${GREEN}✅ Todos los archivos necesarios están presentes${NC}"

# 2. Hacer ejecutables los scripts
echo ""
echo -e "${YELLOW}2. Configurando permisos...${NC}"
chmod +x "$BIN_DIR"/*
echo -e "${GREEN}✅ Permisos configurados${NC}"

# 3. Detectar shell y archivo de configuración
echo ""
echo -e "${YELLOW}3. Detectando configuración del shell...${NC}"
SHELL_CONFIG=$(get_shell_config)

if [ -z "$SHELL_CONFIG" ]; then
    echo -e "${RED}❌ No se pudo detectar el shell${NC}"
    echo "Por favor, añade manualmente estas líneas a tu archivo de configuración del shell:"
    echo ""
    echo "export PATH=\"$BIN_DIR:\$PATH\""
    echo "alias claude='claude-nav'"
    echo "alias clj='claude-jump'"
    exit 1
fi

echo -e "${BLUE}📄 Archivo de configuración:${NC} $SHELL_CONFIG"

# 4. Verificar si ya está instalado
echo ""
echo -e "${YELLOW}4. Verificando instalación previa...${NC}"

if grep -q "Claude Terminal Navigator" "$SHELL_CONFIG" 2>/dev/null; then
    echo -e "${YELLOW}⚠️  Ya existe una instalación previa${NC}"
    echo -n "¿Quieres actualizar la configuración? (s/n): "
    read -r response
    if [[ ! "$response" =~ ^[sS]$ ]]; then
        echo "Instalación cancelada"
        exit 0
    fi
else
    echo -e "${GREEN}✅ No se encontró instalación previa${NC}"
fi

# 5. Añadir configuración al shell
echo ""
echo -e "${YELLOW}5. Añadiendo configuración al shell...${NC}"

# Crear backup
cp "$SHELL_CONFIG" "$SHELL_CONFIG.backup.$(date +%Y%m%d_%H%M%S)"
echo -e "${BLUE}📋 Backup creado${NC}"

# Añadir configuración
cat >> "$SHELL_CONFIG" << EOF

# Claude Terminal Navigator
export PATH="$BIN_DIR:\$PATH"
alias claude='claude-nav'
alias clj='claude-jump'
EOF

echo -e "${GREEN}✅ Configuración añadida${NC}"

# 6. Verificar permisos de Terminal
echo ""
echo -e "${YELLOW}6. Verificando permisos de Terminal...${NC}"
echo "Ejecutando verificación de permisos..."
echo ""

"$BIN_DIR/check-permissions"

# 7. Instrucciones finales
echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║      ¡Instalación completada! 🎉        ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Para empezar a usar Claude Terminal Navigator:${NC}"
echo ""
echo "1. Recarga tu configuración del shell:"
echo -e "   ${YELLOW}source $SHELL_CONFIG${NC}"
echo ""
echo "2. Inicia Claude en cualquier directorio:"
echo -e "   ${YELLOW}claude${NC}"
echo ""
echo "3. Desde otra pestaña, salta a la sesión:"
echo -e "   ${YELLOW}clj${NC}"
echo ""
echo -e "${BLUE}Comandos disponibles:${NC}"
echo "  • claude - Ejecuta Claude con tracking de sesión"
echo "  • clj    - Salta a pestañas con sesiones Claude"
echo ""
echo -e "${YELLOW}💡 Tip:${NC} Si tienes problemas con permisos, ejecuta: check-permissions"
echo ""