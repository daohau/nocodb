#!/bin/bash
clear
echo "============================================"
echo "     🚀 NocoDB Manager - PostgreSQL Edition"
echo "============================================"

INSTALL_DIR="/opt/nocodb"
LOG_FILE="$INSTALL_DIR/install.log"
DOMAIN_NAME=""
EMAIL=""

log() {
    echo "[`date +"%Y-%m-%d %H:%M:%S"`] $1" | tee -a $LOG_FILE
}

check_dependencies() {
    log "[🔍] Kiem tra Docker va Docker Compose..."
    if ! command -v docker &> /dev/null; then
        log "[❌] Docker chua duoc cai dat. Cai dat ngay..."
        apt update && apt install -y docker.io || { log "[💥] Loi cai dat Docker!"; exit 1; }
        systemctl enable --now docker
        log "[✅] Docker da duoc cai dat"
    else
        log "[✅] Docker da co san"
    fi

    if ! docker compose version &> /dev/null; then
        if ! docker-compose version &> /dev/null; then
            log "[❌] Docker Compose chua co. Cai dat ngay..."
            apt install -y docker-compose || { log "[💥] Loi cai dat Docker Compose!"; exit 1; }
            log "[✅] Docker Compose da duoc cai dat"
        else
            COMPOSE_CMD="docker-compose"
            log "[ℹ️] Su dung docker-compose"
        fi
    else
        COMPOSE_CMD="docker compose"
        log "[ℹ️] Su dung docker compose"
    fi
}

install_nocodb() {
    log "[📁] Tao thu muc $INSTALL_DIR va di chuyen vao"
    mkdir -p $INSTALL_DIR && cd $INSTALL_DIR

    log "[📝] Tao file docker-compose.yml"
    cat > docker-compose.yml <<EOF
version: "3.8"
services:
  postgres:
    image: postgres:15
    container_name: nocodb_postgres
    environment:
      POSTGRES_USER=nocodb
      POSTGRES_PASSWORD=nocodb123
      POSTGRES_DB=nocodb_db
    volumes:
      - ./postgres-data:/var/lib/postgresql/data
    restart: unless-stopped

  nocodb:
    image: nocodb/nocodb:latest
    container_name: nocodb_app
    environment:
      NC_DB: "pg://nocodb:nocodb123@postgres:5432/nocodb_db"
    depends_on:
      - postgres
    ports:
      - "127.0.0.1:8080:8080"
    restart: unless-stopped
EOF

    log "[⬆️] Khoi dong Docker Compose..."
    $COMPOSE_CMD up -d 2>&1 | tee -a $LOG_FILE
    if [ $? -ne 0 ]; then
        log "[💥] Loi khi khoi dong Docker Compose! Xem log tai $LOG_FILE"
        exit 1
    fi

    log "[⏳] Cho PostgreSQL khoi dong (20s)..."
    sleep 20

    log "[🔍] Kiem tra trang thai container PostgreSQL"
    if docker ps -q -f name=nocodb_postgres &> /dev/null; then
        log "[✅] PostgreSQL dang chay"
    else
        log "[💥] PostgreSQL khong chay!"
        docker logs nocodb_postgres | tee -a $LOG_FILE
        exit 1
    fi

    log "[🔍] Kiem tra trang thai container NocoDB"
    if docker ps -q -f name=nocodb_app &> /dev/null; then
        log "[✅] NocoDB dang chay tren port 8080"
    else
        log "[💥] NocoDB khong chay!"
        docker logs nocodb_app | tee -a $LOG_FILE
        exit 1
    fi
}

setup_nginx_ssl() {
    log "[🌐] Cai dat Nginx va SSL cho $DOMAIN_NAME"
    apt install -y nginx certbot python3-certbot-nginx || { log "[💥] Loi cai dat Nginx/Certbot!"; exit 1; }

    cat > /etc/nginx/sites-available/$DOMAIN_NAME <<EOF
server {
    listen 80;
    server_name $DOMAIN_NAME;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

    ln -s /etc/nginx/sites-available/$DOMAIN_NAME /etc/nginx/sites-enabled/
    nginx -t && systemctl reload nginx

    log "[🔒] Cai dat SSL voi Certbot"
    certbot --nginx -d $DOMAIN_NAME --email $EMAIL --agree-tos --non-interactive || { log "[💥] Loi khi cai SSL!"; exit 1; }
    systemctl reload nginx
    log "[✅] Da cai SSL va cai dat tu dong gia han"
}

main_menu() {
    echo ""
    echo "1. Cai dat NocoDB + PostgreSQL"
    echo "2. Cai dat Nginx + SSL"
    echo "3. Khoi dong lai NocoDB"
    echo "4. Xem log NocoDB"
    echo "5. Thoat"
    echo ""
    read -p "Chon mot tuy chon [1-5]: " choice
    case $choice in
        1)
            check_dependencies
            install_nocodb
            ;;
        2)
            read -p "Nhap domain (VD: modaviet.pro.vn): " DOMAIN_NAME
            read -p "Nhap email de nhan thong bao SSL: " EMAIL
            setup_nginx_ssl
            ;;
        3)
            log "[🔄] Khoi dong lai NocoDB..."
            docker restart nocodb_app || { log "[💥] Loi khi khoi dong lai NocoDB!"; exit 1; }
            ;;
        4)
            docker logs -f nocodb_app
            ;;
        5)
            log "[👋] Thoat..."
            exit 0
            ;;
        *)
            echo "Lua chon khong hop le!"
            ;;
    esac
    main_menu
}

log "[🚀] Bat dau chay script"
main_menu
