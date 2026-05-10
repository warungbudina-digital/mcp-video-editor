#!/bin/bash

write_extend_dockerfile() {
  cat > Dockerfile.extend <<'DOCKER'
FROM custom-n8n:latest

USER root
RUN apk add --no-cache \
    ffmpeg \
    python3
COPY vendor/yt-dlp /usr/local/bin/yt-dlp
RUN chmod +x /usr/local/bin/yt-dlp
USER node
DOCKER
}
