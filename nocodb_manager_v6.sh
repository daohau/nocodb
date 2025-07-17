#!/bin/bash

# ========= THIET LAP MAU =========
XANH="\033[1;32m"
DO="\033[1;31m"
VANG="\033[1;33m"
XAM="\033[1;90m"
RESET="\033[0m"

log() {
    echo -e "${XAM}[$(date '+%Y-%m-%d %H:%M:%S')]${RESET} $1"
}

ok() {
    echo -e "${XANH}[✅]${RESET} $1"
}

err() {
    echo -e "${DO}[❌]${RESET} $1"
}

# ========= THONG TIN =========
WORK_DIR="/opt/nocodb"
DOMAIN=""
EMAIL=""
PORT=443

# ========= KIEM TRA ROOT =========
if [ "$EUID" -ne 0 ]; then
    err "Hay chay script voi quyen root (sudo)."
    exit 1
fi

# ========= CAI DAT DOCKER + DOCKER COMPOSE =========
install_docker() {
    if ! command -v docker &>/dev/null; then
        log "Docker chua duoc cai dat. Cai dat Docker..."
        curl -fsSL https://get.docker.com | sh
        ok "Docker da duoc cai dat"
    else
        ok "Docker da duoc cai dat"
    fi

    if ! command -v docker-compose &>/dev/null; then
        log "Docker Compose chua duoc cai dat. Cai dat Docker Compose..."
        apt install -y docker-compose-plugin >/dev/null 2>&1
        ok "Docker Compose da duoc cai dat"
    else
        ok "Docker Compose da co san"
    fi
}

# ========= CAI NOCODB + POSTGRESQL =========
install_nocodb() {
    mkdir -p $WORK_DIR && cd $WORK_DIR
    log "Tao file docker-compose.yml"

    cat > docker-compose.yml <<EOF
version: "3.8"
services:
  postgres:
    image: postgres:15
    container_name: nocodb_postgres
    environment:
      POSTGRES_USER: nocodb
      POSTGRES_PASSWORD: nocodbpass
      POSTGRES_DB: nocodbdb
    volumes:
      - ./pgdata:/var/lib/postgresql/data
    restart: always

  nocodb:
    image: nocodb/nocodb:latest
    container_name: nocodb_nocodb
    environment:
      NC_DB: "pgsql://nocodb:nocodbpass@postgres:5432/nocodbdb"
    ports:
      - "127.0.0.1:8080:8080"
    depends_on:
      - postgres
    restart: always
EOF

    log "Khoi dong Docker Compose..."
    docker compose up -d

    sleep 10
    if docker ps | grep -q nocodb_nocodb; then
        ok "NocoDB dang chay tren port 8080"
    else
        err "NocoDB khong chay. Xem log voi lua chon 4."
    fi
}

# ========= CAI NGINX + SSL =========
install_nginx_ssl() {
    read -p "Nhap ten mien (vi du: crm.example.com): " DOMAIN
    read -p "Nhap email (de dang ky Let's Encrypt): " EMAIL

    apt update -y && apt install -y nginx certbot python3-certbot-nginx

    log "Cau hinh Nginx"
    cat > /etc/nginx/sites-available/nocodb <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    ln -s /etc/nginx/sites-available/nocodb /etc/nginx/sites-enabled/
    nginx -t && systemctl restart nginx

    log "Cai dat SSL voi Certbot"
    certbot --nginx --non-interactive --agree-tos -m $EMAIL -d $DOMAIN

    ok "SSL da duoc cai dat. Truy cap: https://$DOMAIN"
}

# ========= GO BO NOCODB =========
remove_nocodb() {
    log "Dang go bo NocoDB + PostgreSQL + Nginx"
    docker compose down -v
    rm -rf $WORK_DIR
    rm -f /etc/nginx/sites-available/nocodb /etc/nginx/sites-enabled/nocodb
    systemctl restart nginx
    ok "Da go bo NocoDB"
}

# ========= IN LINK NOCODB =========
print_link() {
    if [ -f "/etc/nginx/sites-available/nocodb" ]; then
        DOMAIN=$(grep "server_name" /etc/nginx/sites-available/nocodb | awk '{print $2}' | tr -d ';')
        echo -e "${VANG}Truy cap: https://$DOMAIN${RESET}"
    else
        err "Khong tim thay cau hinh Nginx."
    fi
}

# ========= THEM ALIAS =========
add_alias() {
    if ! grep -q "nocodb_manager_v6.sh" ~/.bashrc; then
        echo "alias nocodb='bash <(curl -sSL https://raw.githubusercontent.com/daohau/nocodb/main/nocodb_manager_v6.sh)'" >> ~/.bashrc
        ok "Da them alias 'nocodb' vao ~/.bashrc"
        source ~/.bashrc
    fi
}

# ========= MENU =========
show_menu() {
    while true; do
        echo ""
        echo -e "${XANH}=========== NOCODB MANAGER ===========${RESET}"
        echo "1. Cai dat NocoDB + PostgreSQL"
        echo "2. Cai dat Nginx + SSL"
        echo "3. Khoi dong lai NocoDB"
        echo "4. Xem log NocoDB"
        echo "5. Go NocoDB + PostgreSQL + Nginx"
        echo "6. In lai link truy cap NocoDB + SSL"
        echo "7. Thoat"
        echo "======================================"
        read -p "Chon mot tuy chon [1-7]: " choice

        case $choice in
        1) install_docker && install_nocodb ;;
        2) install_nginx_ssl ;;
        3) docker compose restart ;;
        4) docker logs -f nocodb_nocodb ;;
        5) remove_nocodb ;;
        6) print_link ;;
        7) exit 0 ;;
        *) err "Lua chon khong hop le" ;;
        esac
    done
}

# ========= BAT DAU =========
add_alias
show_menu
