# mcp-video-editor

Open-source code untuk download, analyse, dan edit video menggunakan ffmpeg, lalu disiapkan untuk automation lewat n8n.

## Isi repo

- `n8n-script.sh` — bootstrap utama untuk menyiapkan stack
- `.gitignore` — mencegah token dan artefak runtime ikut ter-commit
- `token.json` — token lokal pengguna untuk rclone/Google Drive (jangan commit token asli)

## Alur script

Script akan:
- install tool sistem yang dibutuhkan
- siapkan shared workspace lokal untuk video/audio/transkrip/output
- siapkan konfigurasi `rclone` dari `token.json`
- download `n8n.tar` dari Google Drive
- load image n8n dan build image extended (`ffmpeg + yt-dlp`)
- generate service `viral_analyzer` dan `docker-compose.yml`
- menjalankan stack Docker

## Prasyarat

- Ubuntu/Debian dengan `sudo`
- Docker + Docker Compose plugin
- `token.json` valid untuk Google Drive
- env `TUNNEL_TOKEN` valid untuk Cloudflare Tunnel

## Cara pakai

```bash
export TUNNEL_TOKEN='isi-token-cloudflared'
bash n8n-script.sh
```

## Catatan perbaikan

Perbaikan yang sudah diterapkan tanpa mengubah alur besar script:
- script dibuat `fail-fast` dengan `set -euo pipefail`
- clone dan mkdir dibuat lebih aman untuk rerun
- typo variabel `TOKEN_FILE` diperbaiki
- bug list label CLIP diperbaiki
- `cloudflared` tidak lagi hardcoded token `x`, sekarang pakai env `TUNNEL_TOKEN`
- cleanup tidak lagi menghapus script dan token yang dibutuhkan untuk rerun/debug
- `docker compose up` dibuat eksplisit `--build`


## V2 tanpa VectCutAPI

Versi terbaru sudah menghilangkan dependensi `VectCutAPI` dari flow deploy. Folder data sekarang dipusatkan ke `workspace/` dengan subfolder:

- `workspace/raw_video`
- `workspace/raw_audio`
- `workspace/raw_transkrip`
- `workspace/output`

Entry point lama `n8n-script.sh` tetap dipertahankan sebagai wrapper agar workflow lama tidak putus.
