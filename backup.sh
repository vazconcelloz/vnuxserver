#!/bin/bash
# =============================================================================
# vnux-server-template — backup.sh
# Backup completo dos dados críticos do servidor
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SERVER_DIR="/opt/server"
BACKUP_DIR="$SERVER_DIR/backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_NAME="vnux-backup_${TIMESTAMP}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
LOG_FILE="/var/log/vnux-backup.log"
RETENTION_DAYS=30

log()     { echo -e "${GREEN}[✔]${NC} $1" | tee -a "$LOG_FILE"; }
info()    { echo -e "${BLUE}[ℹ]${NC} $1" | tee -a "$LOG_FILE"; }
warn()    { echo -e "${YELLOW}[⚠]${NC} $1" | tee -a "$LOG_FILE"; }
error()   { echo -e "${RED}[✘]${NC} $1" | tee -a "$LOG_FILE"; exit 1; }
section() { echo -e "\n${CYAN}══════════════════════════════════════════${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}══════════════════════════════════════════${NC}"; }

touch "$LOG_FILE"
echo "" >> "$LOG_FILE"
echo "=== Backup iniciado em $(date) ===" >> "$LOG_FILE"

# =============================================================================
section "1/4 — Verificando diretórios"
# =============================================================================

if [[ ! -d "$SERVER_DIR" ]]; then
    error "Diretório $SERVER_DIR não encontrado."
fi

mkdir -p "$BACKUP_DIR"
log "Diretório de backups: $BACKUP_DIR"

# =============================================================================
section "2/4 — Criando backup compactado"
# =============================================================================

info "Compactando arquivos para: $BACKUP_PATH"

# Criar arquivo temporário de manifesto
MANIFEST_FILE="/tmp/vnux_backup_manifest_${TIMESTAMP}.txt"
cat > "$MANIFEST_FILE" << EOF
vnux-server-template — Backup Manifest
======================================
Data/hora:    $(date)
Hostname:     $(hostname)
IP público:   $(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "indisponível")
Servidor dir: $SERVER_DIR
Backup:       $BACKUP_PATH

Conteúdo incluído:
- site/           — arquivos do site
- nginx/          — configurações do Nginx
- certs/          — certificados SSL
- logs/           — logs do servidor
- docker-compose.yml — configuração Docker
- .env            — variáveis de ambiente (SENSÍVEL)
EOF

# Criar o backup (tar compactado com gzip)
tar -czf "$BACKUP_PATH" \
    --absolute-names \
    --transform "s|^${SERVER_DIR}/||" \
    -C "$SERVER_DIR" \
    site/ \
    nginx/ \
    certs/ \
    logs/ \
    docker-compose.yml \
    2>/dev/null || true

# Adicionar .env se existir
if [[ -f "$SERVER_DIR/.env" ]]; then
    tar -rzf "$BACKUP_PATH" \
        --absolute-names \
        --transform "s|^${SERVER_DIR}/||" \
        -C "$SERVER_DIR" \
        .env \
        2>/dev/null || true
fi

# Adicionar manifesto
tar -rzf "$BACKUP_PATH" \
    --transform "s|/tmp/vnux_backup_manifest_${TIMESTAMP}.txt|MANIFEST.txt|" \
    "$MANIFEST_FILE" \
    2>/dev/null || true

rm -f "$MANIFEST_FILE"

# Verificar integridade
if tar -tzf "$BACKUP_PATH" > /dev/null 2>&1; then
    log "Backup criado e verificado com sucesso."
else
    error "Falha na verificação do backup. Arquivo corrompido."
fi

BACKUP_SIZE=$(du -sh "$BACKUP_PATH" | cut -f1)
info "Tamanho do backup: $BACKUP_SIZE"

# =============================================================================
section "3/4 — Calculando checksum (SHA256)"
# =============================================================================

CHECKSUM=$(sha256sum "$BACKUP_PATH" | cut -d' ' -f1)
echo "$CHECKSUM  $BACKUP_NAME.tar.gz" > "${BACKUP_PATH}.sha256"

log "SHA256: $CHECKSUM"
log "Checksum salvo em: ${BACKUP_PATH}.sha256"

# =============================================================================
section "4/4 — Limpando backups antigos (retenção: ${RETENTION_DAYS} dias)"
# =============================================================================

DELETED_COUNT=0
while IFS= read -r -d '' old_backup; do
    rm -f "$old_backup" "${old_backup}.sha256" 2>/dev/null || true
    warn "Backup antigo removido: $(basename "$old_backup")"
    ((DELETED_COUNT++))
done < <(find "$BACKUP_DIR" -name "vnux-backup_*.tar.gz" -mtime "+${RETENTION_DAYS}" -print0)

if [[ $DELETED_COUNT -eq 0 ]]; then
    info "Nenhum backup antigo para remover."
else
    log "$DELETED_COUNT backup(s) antigo(s) removido(s)."
fi

# Listar backups existentes
echo ""
info "Backups disponíveis em $BACKUP_DIR:"
ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null | tee -a "$LOG_FILE" || info "Nenhum backup encontrado."

# =============================================================================
# Resumo
# =============================================================================

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✔  Backup concluído com sucesso!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${CYAN}Arquivo:${NC}   $BACKUP_PATH"
echo -e "  ${CYAN}Tamanho:${NC}   $BACKUP_SIZE"
echo -e "  ${CYAN}SHA256:${NC}    $CHECKSUM"
echo -e "  ${CYAN}Retenção:${NC}  $RETENTION_DAYS dias"
echo ""
echo -e "  ${YELLOW}Para restaurar:${NC}"
echo -e "  ${CYAN}tar -xzf $BACKUP_PATH -C $SERVER_DIR${NC}"
echo ""

echo "=== Backup concluído em $(date) ===" >> "$LOG_FILE"
