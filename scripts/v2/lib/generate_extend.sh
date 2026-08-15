#!/bin/bash

write_extend_dockerfile() {
  local base_image="$1"
  cat > Dockerfile.extend <<DOCKER
FROM ${base_image}

USER root
RUN apk add --no-cache \
    ffmpeg \
    python3
COPY vendor/yt-dlp /usr/local/bin/yt-dlp
RUN chmod +x /usr/local/bin/yt-dlp
USER node
DOCKER
}
