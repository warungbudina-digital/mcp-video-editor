#!/bin/bash

write_compose_file() {
  local shared_root="$1"
  cat > docker-compose.yml <<COMPOSE
services:
  n8n:
    image: custom-n8n:latest
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
      - NODE_ENV=production
      - EXECUTIONS_PROCESS=main
    volumes:
      - ./n8n_data:/home/node/.n8n
      - ./${shared_root}/raw_transkrip:/app/raw_transkrip
      - ./${shared_root}/raw_video:/app/raw_video
      - ./${shared_root}/raw_audio:/app/raw_audio
      - ./${shared_root}/output:/app/output
    mem_limit: 1g
    cpus: 1.5

  viral_analyzer:
    build: ./analisa_viral
    container_name: analisa_viral
    restart: always
    networks:
      - n8n_net
    volumes:
      - ./${shared_root}/raw_transkrip:/app/raw_transkrip
      - ./${shared_root}/raw_video:/app/raw_video
      - ./${shared_root}/raw_audio:/app/raw_audio
      - ./${shared_root}/output:/app/output
    mem_limit: 2g
    cpus: 2.0

  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflared
    restart: always
    networks:
      - n8n_net
    command: >
      tunnel --no-autoupdate run --token \
      ${TUNNEL_TOKEN}

networks:
  n8n_net:
    driver: bridge
COMPOSE
}
