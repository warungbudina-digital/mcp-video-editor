#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/generate_extend.sh"
source "$SCRIPT_DIR/lib/generate_compose.sh"

REMOTE_NAME="gdrive"
TOKEN_FILE="$REPO_ROOT/token.json"
RCLONE_CONF_PATH="$HOME/.config/rclone/rclone.conf"
SHARED_ROOT="workspace"
# PINNED, JANGAN "latest": n8n baru rilis v2.0 (Agu 2026) dgn breaking change
# besar (task runner wajib container terpisah, ExecuteCommand/Code-node akses
# env dibatasi default keamanan baru) yg BENTROK dgn desain single-container +
# ffmpeg/yt-dlp via workflow proyek ini. Jalur 1.x resmi didukung security+
# bugfix 3 bulan pasca rilis 2.0. Cek rilis 1.x terbaru sebelum bump manual:
# https://github.com/n8n-io/n8n/releases
BASE_IMAGE="n8nio/n8n:1.123.71"
EXTENDED_IMAGE="n8n-uploader:latest"

install_tools() {
  log_section "📦 INSTALLING REQUIRED TOOLS"
  sudo apt update
  sudo apt install -y htop jq rclone
  require_cmd curl
  require_cmd git
  require_cmd docker
  require_cmd rclone
}

prepare_shared_workspace() {
  log_section "📁 PREPARING SHARED WORKSPACE"
  ensure_dir "$SHARED_ROOT/raw_transkrip"
  ensure_dir "$SHARED_ROOT/raw_video"
  ensure_dir "$SHARED_ROOT/raw_audio"
  ensure_dir "$SHARED_ROOT/output"
  ensure_dir n8n_data/cookies
  ensure_dir vendor
}

configure_rclone() {
  log_section "⚙️ CONFIGURING RCLONE (sumber konten Gdrive)"
  ensure_file "$TOKEN_FILE"
  mkdir -p "$(dirname "$RCLONE_CONF_PATH")"
  TOKEN=$(jq -c . "$TOKEN_FILE")
  cat > "$RCLONE_CONF_PATH" <<RCLONE
[$REMOTE_NAME]
type = drive
scope = drive
token = $TOKEN
RCLONE
  echo "✅ rclone.conf berhasil dibuat."
}

require_n8n_secrets() {
  # DB Postgres (DB-VPS) + N8N_ENCRYPTION_KEY WAJIB di-inject dari luar (env),
  # BUKAN dibiarkan n8n auto-generate - lihat README bagian "Kredensial durable".
  ensure_env DB_POSTGRESDB_HOST
  ensure_env DB_POSTGRESDB_PORT
  ensure_env DB_POSTGRESDB_DATABASE
  ensure_env DB_POSTGRESDB_USER
  ensure_env DB_POSTGRESDB_PASSWORD
  ensure_env N8N_ENCRYPTION_KEY
  ensure_env N8N_BASIC_AUTH_USER
  ensure_env N8N_BASIC_AUTH_PASSWORD
}

pull_base_image() {
  log_section "🐳 PULLING OFFICIAL n8n IMAGE (n8nio/n8n, Docker Hub resmi)"
  sudo docker pull "$BASE_IMAGE"
}

build_extended_n8n() {
  log_section "🔧 BUILDING EXTENDED N8N IMAGE (+ffmpeg +yt-dlp)"
  curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o vendor/yt-dlp
  chmod +x vendor/yt-dlp
  write_extend_dockerfile "$BASE_IMAGE"
  sudo docker build -f Dockerfile.extend -t "$EXTENDED_IMAGE" .
}

generate_runtime_files() {
  log_section "📝 GENERATING docker-compose.yml + .env"
  write_compose_file "$SHARED_ROOT" "$EXTENDED_IMAGE"
  # .env eksplisit (bukan cuma export shell) - "sudo docker compose" TIDAK
  # mewarisi env pemanggil tanpa -E, jadi substitusi ${VAR} di compose bisa
  # kosong senyap kalau cuma andalkan environment. File ini BUKAN secret baru,
  # cuma salinan operasional dari secret yang sudah di require_n8n_secrets.
  cat > .env <<ENVFILE
DB_POSTGRESDB_HOST=$DB_POSTGRESDB_HOST
DB_POSTGRESDB_PORT=$DB_POSTGRESDB_PORT
DB_POSTGRESDB_DATABASE=$DB_POSTGRESDB_DATABASE
DB_POSTGRESDB_USER=$DB_POSTGRESDB_USER
DB_POSTGRESDB_PASSWORD=$DB_POSTGRESDB_PASSWORD
N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY
N8N_BASIC_AUTH_USER=$N8N_BASIC_AUTH_USER
N8N_BASIC_AUTH_PASSWORD=$N8N_BASIC_AUTH_PASSWORD
ENVFILE
  chmod 600 .env
}

deploy_stack() {
  log_section "🚀 STARTING DOCKER COMPOSE"
  sudo docker compose up -d --build
}

cleanup_temp() {
  rm -f Dockerfile.extend
  rm -rf vendor
  echo "ℹ️  token.json, workspace, dan script dipertahankan untuk rerun/debug."
}

main() {
  install_tools
  prepare_shared_workspace
  configure_rclone
  require_n8n_secrets
  pull_base_image
  build_extended_n8n
  generate_runtime_files
  deploy_stack
  cleanup_temp
}

main "$@"
