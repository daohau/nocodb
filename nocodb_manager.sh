#!/bin/bash

clear
echo "============================================"
echo " NOCODB + POSTGRESQL ALL-IN-ONE MANAGER "
echo "============================================"

INSTALL_DIR="/opt/nocodb"
DOMAIN_FILE="$INSTALL_DIR/domain.conf"
DB_FILE="$INSTALL_DIR/db.conf"

# ==== Ham tao mat khau ngau nhien ====
gen_pass() {
    tr -dc A-Za-z0-9 </dev/urandom | head -c 16
}

# ==== Ham cai dat ====
install_nocodb_postgres() {
    read -p "Nhap ten mien (vi du: modaviet.pro.vn): " DOMAIN
    read -p "Nhap email cho SSL (vi du: admin@$DOMAIN): " EMAIL

    echo "$DOMAIN" > $DOMAIN_FILE

    POSTGRES_USER="nocodb"
    POSTGRES_DB="nocodb_db"
    POSTGRES_PASSWORD=$(gen_pass)
    echo "$POSTGRES_USER|$POSTGRES_DB|$POSTGRES_PASSWORD" > $DB_FILE

    echo "[1/7] Cai dat Docker & Docker Compose..."
    apt update -y
    apt install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://get.docker.com | bash
    apt install -y docker-compose
    systemctl enable docker
    systemctl start docker

    echo "[2/7] Tao thu muc NocoDB..."
    mkdir -p $INSTALL_DIR
    cd $INSTALL_DIR

    echo "[3/7] Tao file docker-compose.yml..."
    cat > docker-compose.yml <<EOF
version: "3"
services:
  postgres:
    image: postgres:15
    container_name: nocodb_postgres
    restart: always
    environment:
      POSTGRES_USER: $POSTGRES_USER
      POSTGRES_PASSWORD: $POSTGRES_PASSWORD
      POSTGRES_DB: $POSTGRES_DB
    volumes:
      - ./postgres_data:/var/lib/postgresql/data
    networks:
      - nocodb_net

  nocodb:
    image: nocodb/nocodb:latest
    container_name: nocodb_nocodb
    restart: always
    environment:
      NC_DB: "pg://$POSTGRES_USER:$POSTGRES_PASSWORD@postgres:5432/$POSTGRES_DB"
      NC_PUBLIC_URL: "https://$DOMAIN"
    depends_on:
      - postgres
    ports:
      - "8080:8080"
    volumes:
      - ./data:/usr/app/data
    networks:
      - nocodb_net

networks:
  nocodb_net:
EOF

    echo "[4/7] Khoi dong NocoDB + PostgreSQL..."
    docker compose down
    docker compose up -d

    echo "[5/7] Cai Nginx & SSL..."
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

    echo "[6/7] Cai tu dong gia han SSL..."
    (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet && systemctl reload nginx") | crontab -

    echo "[7/7] Hoan tat!"
    echo "============================================"
    echo " Truy cap: https://$DOMAIN "
    echo " PostgreSQL:"
    echo "   User: $POSTGRES_USER"
    echo "   Password: $POSTGRES_PASSWORD"
    echo "============================================"
}

# ==== Menu quan ly ====
manage_nocodb() {
    DOMAIN=$(cat $DOMAIN_FILE 2>/dev/null)
    IFS="|" read POSTGRES_USER POSTGRES_DB POSTGRES_PASSWORD < $DB_FILE

    while true; do
        echo ""
        echo "============ MENU QUAN LY NOCODB ============"
        echo "1. Start NocoDB + PostgreSQL"
        echo "2. Stop NocoDB + PostgreSQL"
        echo "3. Restart NocoDB + PostgreSQL"
        echo "4. Update NocoDB"
        echo "5. Xem log NocoDB"
        echo "6. Backup PostgreSQL"
        echo "7. Exit"
        echo "============================================"
        read -p "Chon tuy chon [1-7]: " choice

        case $choice in
            1)
                echo "Starting..."
                cd $INSTALL_DIR && docker compose up -d
                ;;
            2)
                echo "Stopping..."
                cd $INSTALL_DIR && docker compose down
                ;;
            3)
                echo "Restarting..."
                cd $INSTALL_DIR && docker compose down && docker compose up -d
                ;;
            4)
                echo "Updating..."
                cd $INSTALL_DIR && docker compose pull && docker compose down && docker compose up -d
                ;;
            5)
                echo "Xem log NocoDB..."
                docker logs -f nocodb_nocodb
                ;;
            6)
                BACKUP_FILE="$INSTALL_DIR/postgres_backup_$(date +%Y%m%d_%H%M%S).sql"
                echo "Backing up PostgreSQL to $BACKUP_FILE..."
                docker exec nocodb_postgres pg_dump -U $POSTGRES_USER $POSTGRES_DB > $BACKUP_FILE
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
    install_nocodb_postgres
    manage_nocodb
fi
