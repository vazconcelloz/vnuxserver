#!/bin/bash
# =============================================================================
# vnux-server-template — deploy.sh
# Deploy seguro: valida configuração Nginx e reinicia apenas o container
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SERVER_DIR="/opt/server"
LOG_FILE="/var/log/vnux-deploy.log"
NGINX_CONTAINER="vnux-nginx"

log()     { echo -e "${GREEN}[✔]${NC} $1" | tee -a "$LOG_FILE"; }
info()    { echo -e "${BLUE}[ℹ]${NC} $1" | tee -a "$LOG_FILE"; }
warn()    { echo -e "${YELLOW}[⚠]${NC} $1" | tee -a "$LOG_FILE"; }
error()   { echo -e "${RED}[✘]${NC} $1" | tee -a "$LOG_FILE"; exit 1; }
section() { echo -e "\n${CYAN}══════════════════════════════════════════${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}══════════════════════════════════════════${NC}"; }

touch "$LOG_FILE"
echo "" >> "$LOG_FILE"
echo "=== Deploy iniciado em $(date) ===" >> "$LOG_FILE"

cd "$SERVER_DIR"

# =============================================================================
section "1/3 — Verificando se o container Nginx está rodando"
# =============================================================================

if ! docker ps --format '{{.Names}}' | grep -q "^${NGINX_CONTAINER}$"; then
    error "Container '${NGINX_CONTAINER}' não está em execução. Execute: docker compose up -d"
fi

log "Container '${NGINX_CONTAINER}' está em execução."

# =============================================================================
section "2/3 — Testando configuração do Nginx (nginx -t)"
# =============================================================================

info "Executando nginx -t dentro do container..."

if docker exec "$NGINX_CONTAINER" nginx -t 2>&1 | tee -a "$LOG_FILE"; then
    log "Configuração do Nginx validada com sucesso."
else
    error "Configuração do Nginx inválida. Verifique os arquivos em $SERVER_DIR/nginx/ e tente novamente."
fi

# =============================================================================
section "3/3 — Recarregando Nginx (reload gracioso)"
# =============================================================================

info "Enviando sinal de reload ao Nginx..."

docker exec "$NGINX_CONTAINER" nginx -s reload 2>&1 | tee -a "$LOG_FILE"

log "Nginx recarregado com sucesso (zero downtime)."

# =============================================================================
# Resumo
# =============================================================================

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✔  Deploy concluído com sucesso!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${CYAN}Container:${NC} $NGINX_CONTAINER"
echo -e "  ${CYAN}Log:${NC}       $LOG_FILE"
echo ""
echo -e "  ${YELLOW}Dica:${NC} Para publicar um novo build React, copie os arquivos para"
echo -e "  ${CYAN}$SERVER_DIR/site/${NC} e execute este script novamente."
echo ""

echo "=== Deploy concluído em $(date) ===" >> "$LOG_FILE"
