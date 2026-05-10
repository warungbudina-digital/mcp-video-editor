#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/generate_analyzer.sh"
source "$SCRIPT_DIR/lib/generate_extend.sh"
source "$SCRIPT_DIR/lib/generate_compose.sh"

REMOTE_NAME="gdrive"
TOKEN_FILE="$REPO_ROOT/token.json"
RCLONE_CONF_PATH="$HOME/.config/rclone/rclone.conf"
DEST_FOLDER="$REPO_ROOT"
GDRIVE_FOLDER="Project-Tutorial/n8n"
IMAGE_FILE="n8n.tar"
SHARED_ROOT="workspace"

install_tools() {
  log_section "📦 INSTALLING REQUIRED TOOLS"
  sudo apt update
  sudo apt install -y htop jq
  require_cmd curl
  require_cmd git
  require_cmd docker
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

install_rclone() {
  log_section "⬇️ INSTALLING RCLONE"
  curl https://rclone.org/install.sh | sudo bash
}

configure_rclone() {
  log_section "⚙️ CONFIGURING RCLONE"
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

require_tunnel_token() {
  ensure_env TUNNEL_TOKEN
}

download_n8n_image() {
  log_section "⬇️ DOWNLOADING n8n.tar FROM GOOGLE DRIVE"
  sudo rclone copy --config="$RCLONE_CONF_PATH" "$REMOTE_NAME:$GDRIVE_FOLDER/$IMAGE_FILE" "$DEST_FOLDER" --progress
  ensure_file "$IMAGE_FILE"
}

prepare_vendor_tools() {
  log_section "🧰 PREPARING LOCAL TOOLS"
  curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o vendor/yt-dlp
  chmod +x vendor/yt-dlp
}

load_base_image() {
  log_section "🐳 LOADING DOCKER IMAGE"
  sudo docker load -i "$IMAGE_FILE"
  sudo docker tag n8nio/n8n:latest custom-n8n:latest
}

build_extended_n8n() {
  log_section "🔧 BUILDING EXTENDED N8N IMAGE"
  write_extend_dockerfile
  sudo docker build -f Dockerfile.extend -t custom-n8n:latest .
}

generate_runtime_files() {
  log_section "📝 GENERATING ANALYZER + COMPOSE FILES"
  write_viral_analyzer_files
  write_compose_file "$SHARED_ROOT"
}

deploy_stack() {
  log_section "🚀 STARTING DOCKER COMPOSE"
  sudo docker compose up -d --build
}

cleanup_temp() {
  rm -f "$IMAGE_FILE" Dockerfile.extend
  rm -rf vendor
  echo "ℹ️  token.json, workspace, analisa_viral, dan script dipertahankan untuk rerun/debug."
}

main() {
  install_tools
  prepare_shared_workspace
  install_rclone
  configure_rclone
  require_tunnel_token
  download_n8n_image
  prepare_vendor_tools
  load_base_image
  generate_runtime_files
  build_extended_n8n
  deploy_stack
  cleanup_temp
}

main "$@"
