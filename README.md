# vnux-server-template

Template profissional de servidor de produção para hospedagem de sites estáticos e SPAs (React/Vite).  
Construído sobre Ubuntu Server 24.04 LTS, Docker, Nginx e Cloudflare.

---

## Índice

1. [Visão Geral](#visão-geral)
2. [Pré-requisitos](#pré-requisitos)
3. [Estrutura do Projeto](#estrutura-do-projeto)
4. [Instalação](#instalação)
5. [Configuração Cloudflare](#configuração-cloudflare)
6. [Como Ativar Full Strict](#como-ativar-full-strict)
7. [Publicar Novo Build React/Vite](#publicar-novo-build-reactvite)
8. [Atualizar o Servidor](#atualizar-o-servidor)
9. [Trocar o Certificado SSL](#trocar-o-certificado-ssl)
10. [Backup e Restauração](#backup-e-restauração)
11. [Variáveis de Ambiente](#variáveis-de-ambiente)
12. [Logs](#logs)
13. [Firewall](#firewall)
14. [Segurança](#segurança)
15. [Troubleshooting](#troubleshooting)

---

## Visão Geral

Este template configura um servidor web de produção completo com:

- **Nginx** rodando em Docker (Alpine), com HTTP/2
- **Cloudflare Proxy** com modo **Full (Strict)** via Origin Certificate
- **SSL** exclusivo via Cloudflare Origin Certificate (sem Certbot)
- **Gzip** para compressão de assets
- **Cache** agressivo para assets estáticos com hash (React/Vite)
- **SPA Fallback** (`try_files $uri /index.html`) para roteamento client-side
- **Headers de segurança** completos (CSP, HSTS, X-Frame-Options, etc.)
- **Rate limiting** para proteção contra DDoS
- **Fail2Ban** para proteção SSH
- **UFW** com apenas as portas necessárias abertas (22, 80, 443)
- **Backup automático** com retenção configurável

---

## Pré-requisitos

- Ubuntu Server 24.04 LTS (fresh install recomendado)
- Acesso root via SSH
- Domínio apontando para o IP do servidor no Cloudflare
- Cloudflare Origin Certificate gerado (ver [seção específica](#configuração-cloudflare))

---

## Estrutura do Projeto

```
vnux-server-template/
│
├── install.sh              # Instalação completa do ambiente
├── update.sh               # Atualização do sistema e containers
├── deploy.sh               # Deploy: valida e recarrega Nginx
├── backup.sh               # Backup compactado com retenção
├── docker-compose.yml      # Stack Docker (apenas Nginx)
├── .env.example            # Modelo de variáveis de ambiente
├── .gitignore              # Arquivos excluídos do Git
├── README.md               # Esta documentação
│
├── certs/
│   ├── origin.crt          # Cloudflare Origin Certificate (você fornece)
│   └── origin.key          # Cloudflare Origin Private Key (você fornece)
│
├── nginx/
│   ├── nginx.conf          # Configuração principal do Nginx
│   ├── security.conf       # Headers de segurança HTTP
│   ├── gzip.conf           # Compressão Gzip
│   ├── ssl.conf            # Configuração TLS/SSL
│   ├── cloudflare-realip.conf  # Restauração do IP real do visitante
│   ├── cache.conf          # Regras de cache para assets estáticos
│   └── conf.d/
│       ├── vnux.tech.conf  # Virtual host principal
│       └── redirects.conf  # Catch-all e redirecionamentos
│
├── site/                   # Arquivos do site (build do React/Vite)
├── logs/                   # Logs do Nginx (persistidos no host)
└── backups/                # Backups compactados (gerados pelo backup.sh)
```

---

## Instalação

### 1. Clonar o repositório no servidor

```bash
git clone https://github.com/seu-usuario/vnux-server-template.git
cd vnux-server-template
```

### 2. Adicionar os certificados SSL

Antes de executar o instalador, adicione seus certificados Cloudflare:

```bash
nano certs/origin.crt    # Cole o Origin Certificate
nano certs/origin.key    # Cole a Origin Private Key
```

### 3. Configurar o domínio

Edite o arquivo de virtual host para seu domínio:

```bash
nano nginx/conf.d/vnux.tech.conf
```

Substitua todas as ocorrências de `vnux.tech` pelo seu domínio real.

### 4. Configurar variáveis de ambiente

```bash
cp .env.example .env
nano .env
```

### 5. Executar o instalador

```bash
sudo bash install.sh
```

O script irá:

1. Atualizar o Ubuntu
2. Instalar Docker Engine, Docker Compose, UFW, Fail2Ban, curl, git, unzip, ca-certificates
3. Habilitar Docker e Fail2Ban como serviços do sistema
4. Criar a estrutura em `/opt/server`
5. Copiar todos os arquivos para `/opt/server`
6. Configurar o UFW (portas 22, 80, 443)
7. Iniciar a stack Docker

### 6. Verificar se está funcionando

```bash
cd /opt/server
docker compose ps
docker compose logs nginx
```

Acesse `https://seudominio.com` — o site deve estar no ar.

---

## Configuração Cloudflare

### Passo 1: Adicionar o domínio ao Cloudflare

1. Acesse [dash.cloudflare.com](https://dash.cloudflare.com)
2. Adicione seu domínio
3. Troque os nameservers no seu registrador para os fornecidos pelo Cloudflare
4. Aguarde a propagação (geralmente < 24h)

### Passo 2: Configurar DNS

No Cloudflare DNS, crie os registros:

| Tipo | Nome | Conteúdo | Proxy |
|------|------|----------|-------|
| A    | @    | IP-DO-SERVIDOR | ✅ Proxied |
| A    | www  | IP-DO-SERVIDOR | ✅ Proxied |

> **Importante**: O ícone laranja (Proxied) deve estar ativo para que o Cloudflare atue como proxy.

### Passo 3: Gerar o Origin Certificate

1. Cloudflare Dashboard → seu domínio → **SSL/TLS** → **Origin Server**
2. Clique em **Create Certificate**
3. Selecione:
   - Key type: RSA (2048)
   - Hostnames: `vnux.tech, *.vnux.tech`
   - Certificate validity: 15 years
4. Clique em **Create**
5. **Copie imediatamente** o Origin Certificate e a Private Key (a chave só é exibida uma vez)

### Passo 4: Instalar os certificados

```bash
# No servidor:
nano /opt/server/certs/origin.crt   # Cole o Origin Certificate
nano /opt/server/certs/origin.key   # Cole a Private Key

# Ajustar permissões
chmod 644 /opt/server/certs/origin.crt
chmod 600 /opt/server/certs/origin.key
```

### Passo 5: Configurar SSL/TLS Mode

1. Cloudflare Dashboard → SSL/TLS → Overview
2. Selecione **Full (Strict)**

> **Full (Strict)** valida o certificado do servidor de origem. Requer o Origin Certificate instalado corretamente.

---

## Como Ativar Full Strict

O modo **Full (Strict)** é o mais seguro. Para ativá-lo:

1. **Confirme** que `origin.crt` e `origin.key` estão em `/opt/server/certs/`
2. **Confirme** que o Nginx está servindo HTTPS na porta 443 com esses certificados
3. No Cloudflare: SSL/TLS → Overview → selecione **Full (Strict)**
4. Aguarde alguns segundos — a conexão Cloudflare ↔ servidor agora é verificada

### Ativar HSTS (opcional, mas recomendado)

Após confirmar que HTTPS funciona corretamente há pelo menos 24h:

```bash
nano /opt/server/nginx/conf.d/vnux.tech.conf
```

Descomente a linha:

```nginx
# add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
```

Aplique o deploy:

```bash
sudo bash /opt/server/deploy.sh
```

> **Atenção**: Após ativar HSTS com `max-age=31536000`, todos os browsers visitantes vão forçar HTTPS por 1 ano. Só ative se tiver certeza de que SSL funcionará permanentemente.

---

## Publicar Novo Build React/Vite

### Método 1: Upload manual (SCP)

No seu computador local:

```bash
# Gerar o build de produção
cd meu-projeto-react
npm run build

# Enviar para o servidor via SCP
scp -r dist/* usuario@IP-DO-SERVIDOR:/opt/server/site/
```

### Método 2: Upload manual (Rsync) — recomendado

```bash
rsync -avz --delete dist/ usuario@IP-DO-SERVIDOR:/opt/server/site/
```

A flag `--delete` remove arquivos antigos que não existem mais no build novo.

### Método 3: SSH direto

```bash
ssh usuario@IP-DO-SERVIDOR
cd /opt/server/site
# Limpar build antigo
rm -rf *
# Fazer upload via outro método e extrair aqui
```

### Aplicar o deploy (recarregar Nginx)

Após copiar os arquivos do site:

```bash
sudo bash /opt/server/deploy.sh
```

O script:
1. Verifica se o container está rodando
2. Executa `nginx -t` (valida a configuração)
3. Executa `nginx -s reload` (reload gracioso, zero downtime)

> **Nota**: O Nginx serve os arquivos diretamente do volume `/opt/server/site`. Não é necessário reiniciar o container para que os novos arquivos sejam servidos. O `deploy.sh` apenas recarrega as configurações.

---

## Atualizar o Servidor

```bash
sudo bash /opt/server/update.sh
```

O script executa:

1. `apt-get update && apt-get upgrade` — atualiza o Ubuntu
2. `docker compose pull` — baixa imagens mais recentes
3. `docker compose down && docker compose up -d` — recria os containers
4. `docker image prune -f` — limpa imagens antigas

---

## Trocar o Certificado SSL

### Quando trocar

- O Origin Certificate está próximo do vencimento
- Você gerou um novo certificado por segurança

### Procedimento

1. Gere um novo certificado no Cloudflare (ver [seção Cloudflare](#configuração-cloudflare))

2. Substitua os arquivos no servidor:

```bash
# Fazer backup dos certificados antigos
cp /opt/server/certs/origin.crt /opt/server/certs/origin.crt.bak
cp /opt/server/certs/origin.key /opt/server/certs/origin.key.bak

# Substituir pelos novos
nano /opt/server/certs/origin.crt   # Cole o novo certificado
nano /opt/server/certs/origin.key   # Cole a nova chave privada

# Ajustar permissões
chmod 644 /opt/server/certs/origin.crt
chmod 600 /opt/server/certs/origin.key
```

3. Aplicar sem downtime:

```bash
sudo bash /opt/server/deploy.sh
```

4. Verificar:

```bash
# Dentro do container, verificar datas do certificado
docker exec vnux-nginx openssl x509 -in /etc/nginx/certs/origin.crt -noout -dates
```

---

## Backup e Restauração

### Criar backup manual

```bash
sudo bash /opt/server/backup.sh
```

O backup inclui: `site/`, `nginx/`, `certs/`, `logs/`, `docker-compose.yml`, `.env`

### Listar backups disponíveis

```bash
ls -lh /opt/server/backups/
```

### Verificar integridade do backup

```bash
sha256sum -c /opt/server/backups/vnux-backup_YYYYMMDD_HHMMSS.tar.gz.sha256
```

### Restaurar backup

```bash
# ATENÇÃO: Isso sobrescreve os arquivos atuais
tar -xzf /opt/server/backups/vnux-backup_YYYYMMDD_HHMMSS.tar.gz -C /opt/server/

# Reiniciar a stack após restauração
cd /opt/server
docker compose down
docker compose up -d
```

### Backup automático via cron

```bash
# Abrir o crontab do root
crontab -e

# Adicionar linha para backup diário às 3:00 AM
0 3 * * * /bin/bash /opt/server/backup.sh >> /var/log/vnux-backup-cron.log 2>&1
```

---

## Variáveis de Ambiente

Copie `.env.example` para `.env` e edite:

| Variável | Padrão | Descrição |
|----------|--------|-----------|
| `TIMEZONE` | `America/Sao_Paulo` | Fuso horário do servidor |
| `DOMAIN` | `vnux.tech` | Domínio principal |
| `DOMAIN_ALIASES` | `www.vnux.tech` | Domínios alternativos |
| `SSL_CERT` | `/etc/nginx/certs/origin.crt` | Caminho do certificado (não altere) |
| `SSL_KEY` | `/etc/nginx/certs/origin.key` | Caminho da chave (não altere) |
| `CLIENT_MAX_BODY_SIZE` | `100M` | Tamanho máximo de upload |
| `BACKUP_RETENTION_DAYS` | `30` | Retenção de backups em dias |

---

## Logs

### Localização

```
/opt/server/logs/nginx/
├── access.log              # Acessos gerais
├── error.log               # Erros do Nginx
├── vnux.tech-access.log    # Acessos do virtual host
└── vnux.tech-error.log     # Erros do virtual host
```

### Visualizar logs em tempo real

```bash
# Todos os logs do container
docker compose -f /opt/server/docker-compose.yml logs -f nginx

# Log de acesso
tail -f /opt/server/logs/nginx/vnux.tech-access.log

# Log de erros
tail -f /opt/server/logs/nginx/vnux.tech-error.log

# Filtrar por código de status 4xx ou 5xx
grep ' [45][0-9][0-9] ' /opt/server/logs/nginx/access.log
```

### Rotação de logs

O logrotate é configurado automaticamente pelo `install.sh` em `/etc/logrotate.d/vnux-nginx`.  
Os logs são rotacionados diariamente e mantidos por 30 dias.

---

## Firewall

O UFW é configurado pelo `install.sh` com as seguintes regras:

| Porta | Protocolo | Serviço | Status |
|-------|-----------|---------|--------|
| 22    | TCP       | SSH     | ✅ Aberta |
| 80    | TCP       | HTTP    | ✅ Aberta |
| 443   | TCP       | HTTPS   | ✅ Aberta |
| Resto | —         | —       | ❌ Bloqueada |

### Verificar status do firewall

```bash
sudo ufw status verbose
```

### Comandos úteis do UFW

```bash
# Ver regras numeradas
sudo ufw status numbered

# Remover uma regra (exemplo: remover a regra 3)
sudo ufw delete 3

# Adicionar porta temporária (exemplo: para debug)
sudo ufw allow 8080/tcp comment 'Debug temporário'

# Remover porta
sudo ufw delete allow 8080/tcp
```

---

## Segurança

### Headers HTTP implementados

| Header | Valor | Proteção |
|--------|-------|----------|
| `X-Frame-Options` | `SAMEORIGIN` | Anti-clickjacking |
| `X-Content-Type-Options` | `nosniff` | Anti-MIME sniffing |
| `X-XSS-Protection` | `1; mode=block` | XSS (browsers legados) |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | Privacidade de referrer |
| `Permissions-Policy` | Desabilita APIs não usadas | Anti-fingerprinting |
| `Content-Security-Policy` | Configurável | Anti-XSS, anti-injection |
| `Strict-Transport-Security` | Comentado (ative manualmente) | Força HTTPS |

### Rate Limiting

- **Zona `general`**: 10 requisições/segundo por IP, burst de 20
- **Zona `api`**: 5 requisições/segundo por IP
- **Zona `addr`**: máx. 50 conexões simultâneas por IP

### Fail2Ban

Monitorando:
- Tentativas de autenticação SSH (máx. 3 falhas → ban de 24h)
- Auth HTTP do Nginx
- Bots escaneando o Nginx

### Métodos HTTP bloqueados

Apenas `GET`, `HEAD`, `POST` e `OPTIONS` são permitidos.  
`TRACE`, `DELETE`, `PATCH`, `PUT` retornam `405 Method Not Allowed`.

---

## Troubleshooting

### Nginx não inicia

```bash
# Verificar logs do container
docker compose -f /opt/server/docker-compose.yml logs nginx

# Testar configuração manualmente
docker exec vnux-nginx nginx -t
```

### Certificado SSL inválido

```bash
# Verificar dados do certificado
docker exec vnux-nginx openssl x509 -in /etc/nginx/certs/origin.crt -noout -text | grep -E "(Subject|Issuer|Not)"

# Verificar se o certificado e a chave são compatíveis
docker exec vnux-nginx openssl x509 -noout -modulus -in /etc/nginx/certs/origin.crt | md5sum
docker exec vnux-nginx openssl rsa  -noout -modulus -in /etc/nginx/certs/origin.key | md5sum
# Os hashes devem ser iguais
```

### Site retorna 502/504

```bash
# Verificar status dos containers
docker compose -f /opt/server/docker-compose.yml ps

# Reiniciar stack completa
cd /opt/server && docker compose down && docker compose up -d
```

### IP real do visitante não está correto nos logs

Verifique se o Cloudflare Proxy (ícone laranja) está ativo.  
O header `CF-Connecting-IP` só é enviado quando o proxy está ativo.

### Permissão negada em /opt/server

```bash
# Ajustar permissões
sudo chown -R root:root /opt/server
sudo chmod -R 755 /opt/server
sudo chmod 600 /opt/server/certs/origin.key
```

### Backup falha

```bash
# Verificar espaço em disco
df -h

# Verificar permissões do diretório de backups
ls -la /opt/server/backups/
```

---

## Licença

MIT License — use e adapte livremente.

---

*vnux-server-template — Feito para produção, do primeiro ao último detalhe.*
