#!/bin/bash
# =============================================================================
# vnux-server-template — update.sh
# Atualiza o sistema, imagens Docker e recria containers
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SERVER_DIR="/opt/server"
LOG_FILE="/var/log/vnux-update.log"

log()     { echo -e "${GREEN}[✔]${NC} $1" | tee -a "$LOG_FILE"; }
info()    { echo -e "${BLUE}[ℹ]${NC} $1" | tee -a "$LOG_FILE"; }
warn()    { echo -e "${YELLOW}[⚠]${NC} $1" | tee -a "$LOG_FILE"; }
error()   { echo -e "${RED}[✘]${NC} $1" | tee -a "$LOG_FILE"; exit 1; }
section() { echo -e "\n${CYAN}══════════════════════════════════════════${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}══════════════════════════════════════════${NC}"; }

if [[ $EUID -ne 0 ]]; then
    error "Execute este script como root ou com sudo."
fi

touch "$LOG_FILE"
echo "" >> "$LOG_FILE"
echo "=== Update iniciado em $(date) ===" >> "$LOG_FILE"

# =============================================================================
section "1/4 — Atualizando sistema Ubuntu"
# =============================================================================

export DEBIAN_FRONTEND=noninteractive

apt-get update -y 2>&1 | tee -a "$LOG_FILE"
apt-get upgrade -y 2>&1 | tee -a "$LOG_FILE"
apt-get dist-upgrade -y 2>&1 | tee -a "$LOG_FILE"
apt-get autoremove -y 2>&1 | tee -a "$LOG_FILE"
apt-get autoclean -y 2>&1 | tee -a "$LOG_FILE"

log "Sistema Ubuntu atualizado."

# =============================================================================
section "2/4 — Baixando imagens Docker mais recentes"
# =============================================================================

cd "$SERVER_DIR"

docker compose pull 2>&1 | tee -a "$LOG_FILE"

log "Imagens Docker atualizadas."

# =============================================================================
section "3/4 — Recriando containers"
# =============================================================================

# Parar containers com segurança
docker compose down --remove-orphans 2>&1 | tee -a "$LOG_FILE"

# Subir novamente com imagens atualizadas
docker compose up -d --force-recreate 2>&1 | tee -a "$LOG_FILE"

log "Containers recriados com sucesso."

# =============================================================================
section "4/4 — Limpando imagens antigas"
# =============================================================================

# Remover imagens não utilizadas
docker image prune -f 2>&1 | tee -a "$LOG_FILE"

log "Imagens antigas removidas."

# =============================================================================
# Status final
# =============================================================================

echo ""
echo -e "${CYAN}Status dos containers:${NC}"
docker compose ps | tee -a "$LOG_FILE"

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✔  Update concluído com sucesso!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════${NC}"

echo "=== Update concluído em $(date) ===" >> "$LOG_FILE"
