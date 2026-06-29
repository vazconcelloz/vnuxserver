#!/bin/bash
# =============================================================================
# vnux-server-template — install.sh
# Instalação completa do ambiente de produção
# Ubuntu Server 24.04 LTS
# =============================================================================

set -euo pipefail

# ─── Cores ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ─── Variáveis ───────────────────────────────────────────────────────────────
SERVER_DIR="/opt/server"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/vnux-install.log"

# ─── Funções de log ──────────────────────────────────────────────────────────
log()     { echo -e "${GREEN}[✔]${NC} $1" | tee -a "$LOG_FILE"; }
info()    { echo -e "${BLUE}[ℹ]${NC} $1" | tee -a "$LOG_FILE"; }
warn()    { echo -e "${YELLOW}[⚠]${NC} $1" | tee -a "$LOG_FILE"; }
error()   { echo -e "${RED}[✘]${NC} $1" | tee -a "$LOG_FILE"; }
section() { echo -e "\n${CYAN}══════════════════════════════════════════${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}══════════════════════════════════════════${NC}"; }

# ─── Verificação de root ─────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    error "Este script deve ser executado como root ou com sudo."
    exit 1
fi

# ─── Inicializar log ─────────────────────────────────────────────────────────
touch "$LOG_FILE"
echo "=== Instalação iniciada em $(date) ===" >> "$LOG_FILE"

# =============================================================================
section "1/8 — Atualizando o sistema"
# =============================================================================

export DEBIAN_FRONTEND=noninteractive

apt-get update -y 2>&1 | tee -a "$LOG_FILE"
apt-get upgrade -y 2>&1 | tee -a "$LOG_FILE"
apt-get dist-upgrade -y 2>&1 | tee -a "$LOG_FILE"
apt-get autoremove -y 2>&1 | tee -a "$LOG_FILE"
apt-get autoclean -y 2>&1 | tee -a "$LOG_FILE"

log "Sistema atualizado com sucesso."

# =============================================================================
section "2/8 — Instalando dependências base"
# =============================================================================

apt-get install -y \
    curl \
    git \
    unzip \
    ca-certificates \
    gnupg \
    lsb-release \
    apt-transport-https \
    software-properties-common \
    ufw \
    fail2ban \
    htop \
    nano \
    wget \
    jq \
    cron \
    logrotate \
    2>&1 | tee -a "$LOG_FILE"

log "Dependências base instaladas."

# =============================================================================
section "3/8 — Instalando Docker Engine"
# =============================================================================

# Remover versões antigas
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    apt-get remove -y "$pkg" 2>/dev/null || true
done

# Adicionar repositório oficial do Docker
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y 2>&1 | tee -a "$LOG_FILE"

apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin \
    2>&1 | tee -a "$LOG_FILE"

# Habilitar e iniciar Docker
systemctl enable docker
systemctl start docker

log "Docker instalado e habilitado."

# Verificar instalação
DOCKER_VERSION=$(docker --version)
COMPOSE_VERSION=$(docker compose version)
info "Docker: $DOCKER_VERSION"
info "Compose: $COMPOSE_VERSION"

# =============================================================================
section "4/8 — Configurando Fail2Ban"
# =============================================================================

systemctl enable fail2ban
systemctl start fail2ban

# Configuração básica do Fail2Ban
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime  = 3600
findtime  = 600
maxretry = 5
backend = systemd

[sshd]
enabled = true
port    = ssh
logpath = %(sshd_log)s
maxretry = 3
bantime = 86400

[nginx-http-auth]
enabled = true

[nginx-botsearch]
enabled = true
EOF

systemctl restart fail2ban
log "Fail2Ban configurado e iniciado."

# =============================================================================
section "5/8 — Configurando UFW (Firewall)"
# =============================================================================

# Resetar regras existentes
ufw --force reset

# Políticas padrão
ufw default deny incoming
ufw default allow outgoing

# Permitir SSH (porta 22) — IMPORTANTE: sempre primeiro!
ufw allow 22/tcp comment 'SSH'

# Permitir HTTP e HTTPS
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'

# Habilitar firewall
ufw --force enable

log "UFW configurado. Portas abertas: 22, 80, 443."
ufw status verbose | tee -a "$LOG_FILE"

# =============================================================================
section "6/8 — Criando estrutura de diretórios em /opt/server"
# =============================================================================

mkdir -p "$SERVER_DIR"/{nginx/conf.d,certs,site,logs/{nginx,app},backups,scripts}

log "Estrutura de diretórios criada em $SERVER_DIR."

# =============================================================================
section "7/8 — Copiando arquivos do template"
# =============================================================================

# Verificar se estamos executando a partir do diretório do projeto
if [[ ! -f "$SCRIPT_DIR/docker-compose.yml" ]]; then
    warn "docker-compose.yml não encontrado em $SCRIPT_DIR"
    warn "Execute este script a partir da raiz do projeto vnux-server-template."
    warn "Estrutura criada em $SERVER_DIR, mas os arquivos não foram copiados."
else
    # Copiar todos os arquivos do projeto
    cp "$SCRIPT_DIR/docker-compose.yml"        "$SERVER_DIR/"
    cp "$SCRIPT_DIR/nginx/nginx.conf"           "$SERVER_DIR/nginx/"
    cp "$SCRIPT_DIR/nginx/security.conf"        "$SERVER_DIR/nginx/"
    cp "$SCRIPT_DIR/nginx/gzip.conf"            "$SERVER_DIR/nginx/"
    cp "$SCRIPT_DIR/nginx/ssl.conf"             "$SERVER_DIR/nginx/"
    cp "$SCRIPT_DIR/nginx/cloudflare-realip.conf" "$SERVER_DIR/nginx/"
    cp "$SCRIPT_DIR/nginx/cache.conf"           "$SERVER_DIR/nginx/"
    cp "$SCRIPT_DIR/nginx/conf.d/vnux.tech.conf"  "$SERVER_DIR/nginx/conf.d/"
    cp "$SCRIPT_DIR/nginx/conf.d/redirects.conf"  "$SERVER_DIR/nginx/conf.d/"
    cp "$SCRIPT_DIR/scripts/"*                  "$SERVER_DIR/scripts/" 2>/dev/null || true
    chmod +x "$SERVER_DIR/scripts/"*.sh 2>/dev/null || true

    # Copiar scripts raiz
    cp "$SCRIPT_DIR/update.sh"   "$SERVER_DIR/"
    cp "$SCRIPT_DIR/deploy.sh"   "$SERVER_DIR/"
    cp "$SCRIPT_DIR/backup.sh"   "$SERVER_DIR/"
    chmod +x "$SERVER_DIR/"*.sh

    # Copiar .env se não existir
    if [[ ! -f "$SERVER_DIR/.env" ]]; then
        cp "$SCRIPT_DIR/.env.example" "$SERVER_DIR/.env"
        warn ".env copiado a partir de .env.example. Edite antes de iniciar!"
    fi

    # Copiar certificados se existirem no template
    if ls "$SCRIPT_DIR/certs/"*.crt 1> /dev/null 2>&1; then
        cp "$SCRIPT_DIR/certs/"*.crt "$SERVER_DIR/certs/" 2>/dev/null || true
        cp "$SCRIPT_DIR/certs/"*.key "$SERVER_DIR/certs/" 2>/dev/null || true
        chmod 600 "$SERVER_DIR/certs/"*.key 2>/dev/null || true
        log "Certificados copiados."
    else
        warn "Nenhum certificado .crt encontrado em $SCRIPT_DIR/certs/"
        warn "Adicione seus arquivos .crt e .key em $SERVER_DIR/certs/ antes de iniciar."
    fi

    log "Arquivos copiados para $SERVER_DIR."
fi

# Ajustar permissões
chown -R root:root "$SERVER_DIR"
chmod -R 755 "$SERVER_DIR"
chmod -R 750 "$SERVER_DIR/certs" 2>/dev/null || true
chmod -R 755 "$SERVER_DIR/logs"
chmod -R 755 "$SERVER_DIR/backups"
chmod -R 755 "$SERVER_DIR/site"

log "Permissões configuradas."

# =============================================================================
section "8/8 — Iniciando a stack Docker"
# =============================================================================

if [[ -f "$SERVER_DIR/docker-compose.yml" ]]; then
    if ! ls "$SERVER_DIR/certs/"*.crt 1> /dev/null 2>&1; then
        warn "Certificados SSL ausentes. A stack não será iniciada automaticamente."
        warn "Adicione os certificados e execute: cd $SERVER_DIR && docker compose up -d"
    else
        cd "$SERVER_DIR"

        # Pull das imagens mais recentes
        docker compose pull

        # Subir a stack
        docker compose up -d

        # Verificar saúde dos containers
        sleep 5
        docker compose ps | tee -a "$LOG_FILE"

        log "Stack Docker iniciada com sucesso."
    fi
else
    warn "docker-compose.yml não encontrado. Stack não iniciada."
fi

# =============================================================================
# Configurar logrotate para os logs do Nginx
# =============================================================================

cat > /etc/logrotate.d/vnux-nginx << 'EOF'
/opt/server/logs/nginx/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    sharedscripts
    postrotate
        docker exec vnux-nginx nginx -s reopen 2>/dev/null || true
    endscript
}
EOF

log "Logrotate configurado para logs do Nginx."

# =============================================================================
# Resumo final
# =============================================================================

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✔  Instalação concluída com sucesso!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${CYAN}Diretório do servidor:${NC} $SERVER_DIR"
echo -e "  ${CYAN}Logs de instalação:${NC}   $LOG_FILE"
echo ""
echo -e "  ${YELLOW}Próximos passos:${NC}"
echo -e "  1. Edite o arquivo ${CYAN}$SERVER_DIR/.env${NC} com suas configurações"
echo -e "  2. Adicione os certificados SSL em ${CYAN}$SERVER_DIR/certs/${NC}"
echo -e "  3. Coloque os arquivos do site em ${CYAN}$SERVER_DIR/site/${NC}"
echo -e "  4. Execute: ${CYAN}cd $SERVER_DIR && docker compose up -d${NC}"
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════${NC}"

echo "=== Instalação concluída em $(date) ===" >> "$LOG_FILE"
