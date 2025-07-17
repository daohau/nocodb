#!/bin/bash

# ================================
# NocoDB Manager - Version 2.0
# Author: modaviet (Hau Dao Van)
# ================================

LOG_FILE="/opt/nocodb/install.log"
mkdir -p /opt/nocodb && touch $LOG_FILE
exec > >(tee -a $LOG_FILE) 2>&1

echo "[📝] Bat dau cai dat NocoDB Manager..."

# Kiem tra Docker
if ! command -v docker >/dev/null 2>&1; then
    echo "[❌] Docker chua duoc cai dat. Cai dat Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker --now
else
    echo "[✅] Docker da duoc cai dat"
fi

# Kiem tra Docker Compose
if command -v docker compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
else
    echo "[❌] Docker Compose chua duoc cai dat. Cai dat..."
    curl -L "https://github.com/docker/compose/releases/download/v2.23.0/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
    COMPOSE_CMD="docker-compose"
fi
echo "[✅] Docker Compose da duoc cai dat"

# Di chuyen vao thu muc
cd /opt/nocodb || exit 1
echo "[📁] Thu muc lam viec: $(pwd)"

# Tao docker-compose.yml
cat <<EOF > docker-compose.yml
version: '3'
services:
  postgres:
    image: postgres:14
    container_name: nocodb_postgres
    restart: always
    environment:
      POSTGRES_USER=nocodb
      POSTGRES_PASSWORD=nocodb123
      POSTGRES_DB=nocodb
    volumes:
      - postgres_data:/var/lib/postgresql/data
  nocodb:
    image: nocodb/nocodb:latest
    container_name: nocodb_nocodb
    restart: always
    ports:
      - "8080:8080"
    environment:
      NC_DB: "pg://nocodb:nocodb123@postgres:5432/nocodb"
    depends_on:
      - postgres
volumes:
  postgres_data:
EOF
echo "[📝] File docker-compose.yml da duoc tao"

# Khoi dong Docker Compose
echo "[⬆️] Dang khoi dong Docker Compose..."
$COMPOSE_CMD up -d || { echo "[💥] Loi khi khoi dong Docker Compose!"; exit 1; }

# Cho PostgreSQL khoi dong
echo "[⏳] Cho PostgreSQL khoi dong (20s)..."
sleep 20

# Kiem tra container
echo "[🔍] Kiem tra trang thai container..."
if docker ps | grep -q nocodb_postgres; then
    echo "[✅] PostgreSQL dang chay"
else
    echo "[❌] PostgreSQL khong chay"
fi

if docker ps | grep -q nocodb_nocodb; then
    echo "[✅] NocoDB dang chay tren port 8080"
else
    echo "[❌] NocoDB khong chay. Kiem tra log..."
    docker logs nocodb_nocodb
    exit 1
fi

# Menu quan ly
while true; do
    echo ""
    echo "1. Cai dat Nginx + SSL"
    echo "2. Khoi dong lai NocoDB"
    echo "3. Xem log NocoDB"
    echo "4. Thoat"
    read -rp "Chon mot tuy chon [1-4]: " opt
    case $opt in
    1)
        read -rp "Nhap domain (vi du: crm.example.com): " domain
        read -rp "Nhap email cho SSL: " email
        apt install -y nginx certbot python3-certbot-nginx
        cat <<NGINX > /etc/nginx/sites-available/nocodb
server {
    listen 80;
    server_name $domain;
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
NGINX
        ln -s /etc/nginx/sites-available/nocodb /etc/nginx/sites-enabled/
        nginx -t && systemctl restart nginx
        certbot --nginx -d $domain --email $email --agree-tos --non-interactive
        echo "[✅] Cai dat SSL thanh cong"
        ;;
    2)
        echo "[🔄] Dang khoi dong lai NocoDB..."
        $COMPOSE_CMD restart
        ;;
    3)
        docker logs -f nocodb_nocodb
        ;;
    4)
        echo "[👋] Thoat NocoDB Manager"
        exit 0
        ;;
    *)
        echo "[⚠️] Lua chon khong hop le"
        ;;
    esac
done
