#!/bin/bash
clear
echo "============================================"
echo "     🚀 NocoDB Manager - PostgreSQL Edition"
echo "============================================"

INSTALL_DIR="/opt/nocodb"
DOMAIN_NAME=""
EMAIL=""

check_dependencies() {
    echo "[🔍] Kiem tra Docker va Docker Compose..."
    if ! command -v docker &> /dev/null; then
        echo "[❌] Docker chua duoc cai dat. Cai dat ngay..."
        apt update && apt install -y docker.io
        systemctl enable --now docker
    fi

    if ! command -v docker compose &> /dev/null; then
        echo "[❌] Docker Compose chua duoc cai dat. Cai dat ngay..."
        apt install -y docker-compose
    fi
}

install_nocodb() {
    mkdir -p $INSTALL_DIR && cd $INSTALL_DIR

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

    docker compose up -d

    echo "[⏳] Cho PostgreSQL khoi dong..."
    sleep 20

    echo "[🔍] Kiem tra container NocoDB..."
    if docker ps -q -f name=nocodb_app &> /dev/null; then
        echo "[✅] NocoDB dang chay tren port 8080"
    else
        echo "[❌] NocoDB khong chay. Kiem tra log..."
        docker logs -f nocodb_app
        exit 1
    fi
}

setup_nginx_ssl() {
    echo "[🌐] Cai dat Nginx va SSL cho $DOMAIN_NAME"
    apt install -y nginx certbot python3-certbot-nginx

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

    certbot --nginx -d $DOMAIN_NAME --email $EMAIL --agree-tos --non-interactive
    systemctl reload nginx
    echo "[🔒] Da cai SSL va cai dat tu dong gia han"
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
            echo "[🔄] Khoi dong lai NocoDB..."
            docker restart nocodb_app
            ;;
        4)
            docker logs -f nocodb_app
            ;;
        5)
            exit 0
            ;;
        *)
            echo "Lua chon khong hop le!"
            ;;
    esac
    main_menu
}

main_menu
