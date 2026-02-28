#!/bin/bash

echo "==============================="
echo "🚀 STARTING DEPLOYMENT PROCESS"
echo "==============================="

echo "📦 Install tools pendukung (htop, jq)..."
#sudo apt update
sudo apt install -y htop jq

git clone https://github.com/sun-guannan/VectCutAPI.git

mkdir -p VectCutAPI/raw_video
mkdir -p VectCutAPI/raw_audio
mkdir -p VectCutAPI/output

cat > VectCutAPI/requirements.txt <<'EOF'

imageio
psutil
flask
requests
oss2
aiohttp>=3.8.0
pydantic>=2.0.0
json5
EOF

sudo chown -R 1000:1000 VectCutAPI

echo "⬇️ Install rclone..."
curl https://rclone.org/install.sh | sudo bash

# ========================
# KONFIGURASI RCLONE
# ========================
REMOTE_NAME="gdrive"
TOKEN_FILE="./token.json"
RCLONE_CONF_PATH="$HOME/.config/rclone/rclone.conf"
DEST_FOLDER="$(pwd)"
GDRIVE_FOLDER="Project-Tutorial/n8n"
IMAGE_FILE="n8n.tar"

echo ""
echo "==============================="
echo "⚙️  CONFIGURING RCLONE"
echo "==============================="

if [ ! -f "$TOKEN_FILE" ]; then
  echo "❌ File token.json tidak ditemukan di path: $TOKEN_FILE"
  exit 1
fi

echo "⚙️ Menyiapkan rclone.conf..."
mkdir -p "$(dirname "$RCLONE_CONF_PATH")"
TOKEN=$(jq -c . "$TOKEN_FILE")

cat > "$RCLONE_CONF_PATH" <<EOF
[$REMOTE_NAME]
type = drive
scope = drive
token = $TOKEN
EOF

echo "✅ rclone.conf berhasil dibuat."

# ========================
# DOWNLOAD IMAGE n8n.tar
# ========================
echo ""
echo "==============================="
echo "⬇️  DOWNLOADING n8n.tar FROM GOOGLE DRIVE"
echo "==============================="

echo "📁 Folder Drive: $GDRIVE_FOLDER"
echo "📁 Tujuan: $DEST_FOLDER"

rclone copy --config="$RCLONE_CONF_PATH" "$REMOTE_NAME:$GDRIVE_FOLDER/$IMAGE_FILE" "$DEST_FOLDER" --progress

if [ $? -ne 0 ]; then
  echo "❌ Gagal men-download n8n.tar dari Google Drive!"
  exit 1
fi

echo "✅ Download selesai."

# ========================
# LOAD DOCKER IMAGE
# ========================
echo ""
echo "==============================="
echo "🐳  LOADING DOCKER IMAGE"
echo "==============================="

if [ ! -f "$IMAGE_FILE" ]; then
  echo "❌ File $IMAGE_FILE tidak ditemukan setelah download!"
  exit 1
fi

mkdir n8n_data
mkdir -p n8n_data/cookies
sudo mv $HOME/mcp-video-editor/cookies.txt $HOME/mcp-video-editor/n8n_data/cookies
mkdir -p vendor

curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
-o vendor/yt-dlp

chmod +x vendor/yt-dlp

docker load -i "$IMAGE_FILE"

echo "🏷️ Menandai image menjadi custom-n8n:latest ..."
docker tag n8nio/n8n:latest custom-n8n:latest

echo "✅ Image berhasil diload & ditag."

echo ""
echo "==============================="
echo "🔧  BUILDING EXTENDED N8N IMAGE (FFMPEG + YT-DLP)"
echo "==============================="

cat > VectCutAPI/Dockerfile <<'EOF'

FROM python:3.10-slim

WORKDIR /app
COPY . /app
RUN pip install --no-cache-dir -r requirements.txt

EXPOSE 9000

CMD ["python", "capcut_server.py"]
EOF

echo "==============================="

cat > Dockerfile.extend <<'EOF'
FROM custom-n8n:latest

USER root

RUN apk add --no-cache \
    ffmpeg \
    python3

COPY vendor/yt-dlp /usr/local/bin/yt-dlp

RUN mkdir -p /home/node/.n8n/download && \
    chown -R node:node /home/node/.n8n

USER node
EOF

docker build -f Dockerfile.extend -t custom-n8n:ffmpeg .

echo "✅ Extended image built: custom-n8n:ffmpeg"


# ========================
# MEMBUAT DOCKER-COMPOSE
# ========================
echo ""
echo "==============================="
echo "📝  GENERATING docker-compose.yml"
echo "==============================="

cat > docker-compose.yml <<'EOF'
version: "3.8"

services:
  n8n:
    image: custom-n8n:ffmpeg
    container_name: n8n
    restart: always
    networks:
      - n8n_net
    ports:
      - "5678:5678"
    environment:
      - N8N_HOST=n8n.delitourandphotography.com
      - N8N_PROTOCOL=https
      - WEBHOOK_URL=https://n8n.delitourandphotography.com
      - N8N_EDITOR_BASE_URL=https://n8n.delitourandphotography.com
      - N8N_DEFAULT_BINARY_DATA_MODE=filesystem
      #- N8N_DATA_TABLES_MAX_SIZE_BYTES=
      - NODE_ENV=production
      - EXECUTIONS_PROCESS=main
    volumes:
      - ./n8n_data:/home/node/.n8n
    mem_limit: 1g
    cpus: 1.5

  vectcutapi:
    build: ./VectCutAPI
    container_name: VectCutAPI
    restart: always
    networks:
      - n8n_net
    volumes:
      - ./VectCutAPI/raw_video:/app/raw_video
      - ./VectCutAPI/raw_audio:/app/raw_audio
      - ./VectCutAPI/output:/app/output
    mem_limit: 2g
    cpus: 2.0

  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflared
    restart: always
    networks:
      - n8n_net
    command: >
      tunnel --no-autoupdate run --token xx

networks:
  n8n_net:
    driver: bridge
EOF

echo "✅ docker-compose.yml berhasil dibuat."

# ========================
# DEPLOY DOCKER COMPOSE
# ========================
echo ""
echo "==============================="
echo "🚀  STARTING DOCKER COMPOSE"
echo "==============================="

docker compose up -d

if [ $? -eq 0 ]; then
    echo "🎉 Deploy berhasil!"
    echo "🌐 Aplikasi berjalan di port 5678"
else
    echo "❌ Deploy gagal!"
fi
sudo rm -r n8n.tar
sudo rm -r n8n-script.sh
sudo rm -r token.json
sudo rm -r Dockerfile.extend
sudo rm -r vendor

ping 8.8.8.8
