#!/bin/bash

# ====== Cau hinh ======
read -p "Nhap ten mien (vd: nocodb.example.com): " DOMAIN
read -p "Nhap email de dang ky SSL (vd: admin@example.com): " EMAIL

DATA_DIR="/opt/nocodb/data"
APP_DIR="/opt/nocodb"
COMPOSE_FILE="$APP_DIR/docker-compose.yml"

# ====== Kiem tra quyen ======
if [ "$EUID" -ne 0 ]; then
    echo "Hay chay script voi quyen root hoac sudo"
    exit 1
fi

# ====== Cap nhat va cai dat ======
echo "Cap nhat he thong va cai dat Docker, Docker Compose, Nginx, Certbot"
apt update && apt upgrade -y
apt install -y docker.io docker-compose nginx certbot python3-certbot-nginx ufw curl unzip

systemctl enable --now docker

# ====== Tao thu muc ======
mkdir -p $DATA_DIR

# ====== Tao docker-compose.yml ======
echo "Tao file docker-compose.yml"
cat > $COMPOSE_FILE <<EOF
version: "3"
services:
  nocodb:
    image: nocodb/nocodb:latest
    restart: always
    ports:
      - "127.0.0.1:8080:8080"
    environment:
      NC_DB: "sqlite:///data/nocodb.db"
    volumes:
      - $DATA_DIR:/usr/app/data
EOF

# ====== Khoi dong NocoDB ======
cd $APP_DIR
docker-compose up -d

# ====== Kiem tra NocoDB ======
echo "Dang doi NocoDB khoi dong (toi da 60s)..."
for i in {1..12}; do
    if curl -s http://127.0.0.1:8080 > /dev/null; then
        echo "✅ NocoDB da san sang tren 127.0.0.1:8080"
        break
    else
        echo "⏳ Dang doi..."
        sleep 5
    fi
done

# ====== Cau hinh firewall ======
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable

# ====== Cau hinh Nginx ======
echo "Cau hinh Nginx"
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

# ====== Cai SSL ======
echo "Dang cai SSL voi Certbot cho $DOMAIN"
certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL

# ====== Auto renew SSL ======
echo "0 3 * * * root certbot renew --quiet && systemctl reload nginx" > /etc/cron.d/certbot-renew

# ====== Tao menu quan ly ======
MANAGER="$APP_DIR/nocodb-manager.sh"
cat > $MANAGER <<'EOM'
#!/bin/bash
APP_DIR="/opt/nocodb"

while true; do
    clear
    echo "========== NocoDB All-In-One Manager =========="
    echo "1. Khoi dong NocoDB"
    echo "2. Dung NocoDB"
    echo "3. Cap nhat NocoDB"
    echo "4. Xem log NocoDB"
    echo "5. Backup data"
    echo "6. Phuc hoi data"
    echo "0. Thoat"
    echo "==============================================="
    read -p "Chon chuc nang: " choice
    case $choice in
        1) cd $APP_DIR && docker-compose up -d ;;
        2) cd $APP_DIR && docker-compose down ;;
        3) cd $APP_DIR && docker-compose pull && docker-compose up -d ;;
        4) docker logs -f nocodb ;;
        5) tar -czvf $APP_DIR/nocodb_backup_$(date +%F).tar.gz $APP_DIR/data ;;
        6) read -p "Nhap ten file backup (.tar.gz): " FILE
           tar -xzvf $APP_DIR/$FILE -C $APP_DIR ;;
        0) exit 0 ;;
        *) echo "Lua chon khong hop le"; sleep 2 ;;
    esac
done
EOM

chmod +x $MANAGER

echo "==== ✅ Cai dat hoan tat ===="
echo "Truy cap NocoDB tai: https://$DOMAIN"
echo "Quan ly bang lenh: sudo bash $MANAGER"
