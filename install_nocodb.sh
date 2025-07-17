#!/bin/bash

# ================================
# Script Cai Dat NocoDB + PostgreSQL
# Ubuntu 20.04 / 22.04
# ================================

set -e

# Kiem tra quyen root
if [ "$EUID" -ne 0 ]; then
    echo "Vui long chay script voi quyen root (sudo)"
    exit 1
fi

# Nhap thong tin
read -p "Nhap domain cho NocoDB (vi du: nocodb.example.com): " DOMAIN
read -p "Nhap email de dang ky SSL Let's Encrypt: " EMAIL

# Cap nhat va cai dat cac goi can thiet
apt update && apt upgrade -y
apt install -y curl wget sudo git unzip ufw

# Cai Docker va Docker Compose
if ! command -v docker &> /dev/null; then
    echo "Dang cai dat Docker..."
    curl -fsSL https://get.docker.com | bash
    systemctl enable docker
    systemctl start docker
fi

if ! command -v docker-compose &> /dev/null; then
    echo "Dang cai dat Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/download/v2.24.7/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
fi

# Tao thu muc lam viec
mkdir -p /opt/nocodb
cd /opt/nocodb

# Tao file docker-compose.yml
cat > docker-compose.yml <<EOF
version: "3.8"

services:
  postgres:
    image: postgres:15
    container_name: nocodb_postgres
    restart: always
    environment:
      POSTGRES_USER=nocodb
      POSTGRES_PASSWORD=nocodb123
      POSTGRES_DB=nocodb
    volumes:
      - ./postgres-data:/var/lib/postgresql/data

  nocodb:
    image: nocodb/nocodb:latest
    container_name: nocodb_app
    restart: always
    environment:
      NC_DB: "pg://nocodb:nocodb123@postgres:5432/nocodb"
    depends_on:
      - postgres
    networks:
      - nocodb_net

networks:
  nocodb_net:
    driver: bridge
EOF

# Khoi dong NocoDB + PostgreSQL
docker-compose up -d

# Cai dat Nginx va Certbot
apt install -y nginx python3-certbot-nginx

# Cau hinh Nginx
cat > /etc/nginx/sites-available/nocodb <<EOL
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOL

ln -s /etc/nginx/sites-available/nocodb /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx

# Cai SSL tu dong
certbot --nginx --non-interactive --agree-tos -m $EMAIL -d $DOMAIN

# Kiem tra va bat lai dich vu
systemctl enable nginx
systemctl restart nginx

echo "============================================="
echo "Cai dat thanh cong!"
echo "Truy cap NocoDB tai: https://$DOMAIN"
echo "Du lieu luu tai: /opt/nocodb"
echo "SSL da cai dat va tu dong gia han"
echo "============================================="
