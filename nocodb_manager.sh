#!/bin/bash

clear
echo "============================================"
echo " NOCODB ALL-IN-ONE INSTALLER & MANAGER "
echo "============================================"

INSTALL_DIR="/opt/nocodb"
DOMAIN_FILE="$INSTALL_DIR/domain.conf"

# ==== Ham cai dat ====
install_nocodb() {
    read -p "Nhap ten mien (vi du: modaviet.pro.vn): " DOMAIN
    read -p "Nhap email cho SSL (vi du: admin@$DOMAIN): " EMAIL

    echo "$DOMAIN" > $DOMAIN_FILE

    echo "[1/6] Cai dat Docker & Docker Compose..."
    apt update -y
    apt install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://get.docker.com | bash
    apt install -y docker-compose
    systemctl enable docker
    systemctl start docker

    echo "[2/6] Tao thu muc NocoDB..."
    mkdir -p $INSTALL_DIR
    cd $INSTALL_DIR

    echo "[3/6] Tao file docker-compose.yml..."
    cat > docker-compose.yml <<EOF
version: "3"
services:
  nocodb:
    image: nocodb/nocodb:latest
    container_name: nocodb_nocodb_1
    restart: always
    ports:
      - "8080:8080"
    environment:
      NC_PUBLIC_URL: "https://$DOMAIN"
    volumes:
      - ./data:/usr/app/data
EOF

    echo "[4/6] Khoi dong NocoDB..."
    docker compose down
    docker compose up -d

    echo "[5/6] Cai Nginx & SSL..."
    apt install -y nginx certbot python3-certbot-nginx
    cat > /etc/nginx/sites-available/$DOMAIN <<EOF
server {
    listen 80;
    server_name $DOMAIN;

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

    ln -s /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
    nginx -t && systemctl reload nginx

    echo "Dang cai SSL cho $DOMAIN..."
    certbot --nginx --non-interactive --agree-tos --redirect -m $EMAIL -d $DOMAIN

    echo "[6/6] Cai tu dong gia han SSL..."
    (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet && systemctl reload nginx") | crontab -

    echo "============================================"
    echo " Cai dat hoan tat! Truy cap: https://$DOMAIN "
    echo "============================================"
}

# ==== Menu quan ly ====
manage_nocodb() {
    DOMAIN=$(cat $DOMAIN_FILE 2>/dev/null)

    while true; do
        echo ""
        echo "============ MENU QUAN LY NOCODB ============"
        echo "1. Start NocoDB"
        echo "2. Stop NocoDB"
        echo "3. Restart NocoDB"
        echo "4. Update NocoDB"
        echo "5. Xem log NocoDB"
        echo "6. Backup data"
        echo "7. Exit"
        echo "============================================"
        read -p "Chon tuy chon [1-7]: " choice

        case $choice in
            1)
                echo "Starting NocoDB..."
                cd $INSTALL_DIR && docker compose up -d
                ;;
            2)
                echo "Stopping NocoDB..."
                cd $INSTALL_DIR && docker compose down
                ;;
            3)
                echo "Restarting NocoDB..."
                cd $INSTALL_DIR && docker compose down && docker compose up -d
                ;;
            4)
                echo "Updating NocoDB..."
                cd $INSTALL_DIR && docker compose pull && docker compose down && docker compose up -d
                ;;
            5)
                echo "Xem log NocoDB..."
                docker logs -f nocodb_nocodb_1
                ;;
            6)
                BACKUP_DIR="$INSTALL_DIR/backup_$(date +%Y%m%d_%H%M%S)"
                echo "Backup data to $BACKUP_DIR..."
                mkdir -p $BACKUP_DIR
                cp -r $INSTALL_DIR/data $BACKUP_DIR/
                echo "Backup hoan tat!"
                ;;
            7)
                echo "Thoat..."
                exit 0
                ;;
            *)
                echo "Lua chon khong hop le!"
                ;;
        esac
    done
}

# ==== Kiem tra co cai dat chua ====
if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
    manage_nocodb
else
    install_nocodb
    manage_nocodb
fi
