#!/bin/bash

write_compose_file() {
  local shared_root="$1"
  local image="$2"
  local rclone_conf_path="$3"
  cat > docker-compose.yml <<COMPOSE
services:
  n8n:
    image: ${image}
    container_name: n8n
    restart: always
    networks:
      - n8n_net
    ports:
      - "5678:5678"
    environment:
      # State durable di Postgres DB-VPS - VM Cloud Shell ephemeral BOLEH recycle,
      # workflow+kredensial+histori TETAP AMAN (bukan SQLite lokal yang ikut hilang).
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=\${DB_POSTGRESDB_HOST}
      - DB_POSTGRESDB_PORT=\${DB_POSTGRESDB_PORT}
      - DB_POSTGRESDB_DATABASE=\${DB_POSTGRESDB_DATABASE}
      - DB_POSTGRESDB_USER=\${DB_POSTGRESDB_USER}
      - DB_POSTGRESDB_PASSWORD=\${DB_POSTGRESDB_PASSWORD}
      # Kunci enkripsi kredensial n8n WAJIB tetap sama lintas redeploy - JANGAN
      # biarkan n8n auto-generate (lihat require_n8n_secrets di deploy.sh).
      - N8N_ENCRYPTION_KEY=\${N8N_ENCRYPTION_KEY}
      # Basic auth: lapis kedua selain onboarding-gate bawaan n8n - WAJIB krn
      # instance ini memegang kredensial OAuth akun sosial media asli.
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=\${N8N_BASIC_AUTH_USER}
      - N8N_BASIC_AUTH_PASSWORD=\${N8N_BASIC_AUTH_PASSWORD}
      - N8N_DEFAULT_BINARY_DATA_MODE=filesystem
      - NODE_ENV=production
      - EXECUTIONS_PROCESS=main
      # Diakses via WireGuard SAJA (10.66.66.61:5678), TANPA tunnel publik -
      # N8N_HOST/WEBHOOK_URL sengaja tak di-set (default localhost, cukup utk
      # akses internal; isi manual kalau nanti benar2 butuh webhook publik).
      # rclone.conf di-mount read-only ke path ini (lihat volumes) - env ini
      # bikin panggilan "rclone ..." di Execute Command node tak perlu --config
      # eksplisit tiap kali.
      - RCLONE_CONFIG=/home/node/.config/rclone/rclone.conf
    volumes:
      - ./n8n_data:/home/node/.n8n
      - ./${shared_root}/raw_transkrip:/app/raw_transkrip
      - ./${shared_root}/raw_video:/app/raw_video
      - ./${shared_root}/raw_audio:/app/raw_audio
      - ./${shared_root}/output:/app/output
      # rclone.conf HOST (ditulis configure_rclone() di deploy.sh, berisi remote
      # [gdrive]=akun gogobuda65 sendiri + [gfootage]=akun tempat RN7 export Reel
      # mendarat) - TANPA mount ini, Execute Command node tak bisa baca rclone.conf
      # sama sekali (container jalan sbg user 'node', bukan host).
      - ${rclone_conf_path}:/home/node/.config/rclone/rclone.conf:ro
    mem_limit: 1g
    cpus: 1.5

networks:
  n8n_net:
    driver: bridge
COMPOSE
}
