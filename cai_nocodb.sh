#!/bin/bash

# Kiem tra quyen root
if [ "$(id -u)" -ne 0 ]; then
    echo "Vui long chay script voi quyen root (sudo)"
    exit 1
fi

# Nhap thong tin
read -p "Nhap ten mien (VD: crm.domain.com): " DOMAIN
read -p "Nhap email de dang ky SSL Let's Encrypt: " EMAIL

# Cap nhat he thong
apt update && apt upgrade -y

# Cai dat Docker va Docker Compose
if ! command -v docker >/dev/null 2>&1; then
    echo "Dang cai dat Docker..."
    apt install -y ca-certificates curl gnupg lsb-release
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
    add-apt-repository \
       "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
       $(lsb_release -cs) stable"
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io
fi

if ! command -v docker-compose >/dev/null 2>&1; then
    echo "Dang cai dat Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
fi

# Tao thu muc NocoDB
mkdir -p /opt/nocodb
cd /opt/nocodb

# Tao file docker-compose.yml
cat > docker-compose.yml <<EOF
version: "3"

services:
  postgres:
    image: postgres:14
    container_name: nocodb_postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER=nocodb
      POSTGRES_PASSWORD=matkhau
      POSTGRES_DB=nocodb
    volumes:
      - postgres_data:/var/lib/postgresql/data

  nocodb:
    image: nocodb/nocodb:latest
    container_name: nocodb_app
    restart: unless-stopped
    environment:
      NC_DB: "pg://nocodb:matkhau@postgres:5432/nocodb"
    ports:
      - "127.0.0.1:8080:8080"
    depends_on:
      - postgres

volumes:
  postgres_data:
EOF

# Khoi dong NocoDB
docker-compose up -d

# Cai dat Nginx va Certbot
apt install -y nginx python3-certbot-nginx

# Cau hinh Nginx reverse proxy
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
nginx -t && systemctl reload nginx

# Cai dat SSL va tu dong gia han
certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL

# Kiem tra SSL tu dong gia han
systemctl list-timers | grep certbot || echo "0 3 * * * root certbot renew --quiet" >> /etc/crontab

echo "============================="
echo "NocoDB da duoc cai dat thanh cong!"
echo "Truy cap: https://$DOMAIN"
echo "============================="
