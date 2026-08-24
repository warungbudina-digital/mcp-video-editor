#!/bin/bash

write_extend_dockerfile() {
  local base_image="$1"
  # n8nio/n8n resmi kini "Docker Hardened Image" (Alpine tanpa package manager
  # sama sekali - `apk`/`apt-get` TAK ADA, ditemukan 2026-08-15 lewat kegagalan
  # nyata `apk: not found`). Solusi: JANGAN install via package manager sama
  # sekali - ambil ffmpeg/ffprobe sbg biner statis via multi-stage COPY dari
  # image `mwader/static-ffmpeg` (dipakai luas persis utk kasus ini), sama pola
  # dgn yt-dlp yg sudah COPY biner mentah (bukan pip/apk install).
  # rclone (2026-08-24, fix gap Execute Command node butuh akses gfootage) pakai
  # pola sama: COPY biner statis dari image resmi `rclone/rclone` (Go binary,
  # TANPA dependency dinamis - terverifikasi `ldd` balas "Not a valid dynamic
  # program" = statically linked, aman di-COPY lintas base image apa pun).
  cat > Dockerfile.extend <<DOCKER
FROM mwader/static-ffmpeg:latest AS ffmpeg
FROM rclone/rclone:latest AS rclone

FROM ${base_image}

USER root
COPY --from=ffmpeg /ffmpeg /usr/local/bin/ffmpeg
COPY --from=ffmpeg /ffprobe /usr/local/bin/ffprobe
COPY --from=rclone /usr/local/bin/rclone /usr/local/bin/rclone
COPY vendor/yt-dlp /usr/local/bin/yt-dlp
RUN chmod +x /usr/local/bin/ffmpeg /usr/local/bin/ffprobe /usr/local/bin/rclone /usr/local/bin/yt-dlp
USER node
DOCKER
}
