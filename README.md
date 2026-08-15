# n8n-uploader

Stack **n8n** untuk otomasi upload konten ke media sosial: ambil sumber video dari
Google Drive, jalankan workflow n8n (download → proses → upload) ke tiap platform
sosial media yang sudah dihubungkan di workflow.

Dirancang untuk jalan sebagai node terjadwal di Cloud Shell (ephemeral) sambil
tetap **stabil lintas VM-recycle**: seluruh state (workflow, kredensial, histori
eksekusi) disimpan di **Postgres eksternal (DB-VPS)**, bukan di disk lokal VM yang
bisa hilang kapan saja.

## Isi repo

- `n8n-script.sh` / `n8n-script-v2.sh` — entrypoint (keduanya wrapper ke `scripts/v2/deploy.sh`)
- `scripts/v2/deploy.sh` — orkestrator utama
- `scripts/v2/lib/` — helper generator (Dockerfile extend, docker-compose.yml)
- `.gitignore` — mencegah kredensial dan artefak runtime ke-commit
- `token.json` — placeholder token lokal rclone/Google Drive (JANGAN commit isi token asli — file ini di-`.gitignore`)

## Arsitektur

- **Image dasar: `n8nio/n8n:latest` resmi dari Docker Hub** (bukan tarball pribadi) — di-extend dgn `ffmpeg`+`yt-dlp` via `Dockerfile.extend`.
- **State di Postgres DB-VPS** (`DB_TYPE=postgresdb`) — workflow/kredensial/histori TAHAN VM-recycle Cloud Shell.
- **`N8N_ENCRYPTION_KEY` WAJIB di-pin & disimpan durable** di luar repo — kalau berubah, seluruh kredensial tersimpan di n8n jadi tak bisa didekripsi.
- **Akses HANYA via WireGuard** (`10.66.66.61:5678`) — TANPA tunnel publik (Cloudflare Tunnel sengaja dihapus: instance ini memegang kredensial OAuth akun sosial media asli, jadi tak boleh diekspos ke internet).
- **Basic auth n8n aktif** sebagai lapis kedua selain onboarding-gate bawaan n8n.

## Prasyarat

- Ubuntu/Debian dengan `sudo`
- Docker + Docker Compose plugin
- `token.json` valid untuk Google Drive (isi token OAuth rclone)
- Env kredensial (lihat di bawah) — WAJIB di-set sebelum jalan, skrip akan berhenti kalau kosong

## Cara pakai

```bash
export DB_POSTGRESDB_HOST='10.122.31.251'
export DB_POSTGRESDB_PORT='5432'
export DB_POSTGRESDB_DATABASE='n8n_uploader'
export DB_POSTGRESDB_USER='n8n_uploader'
export DB_POSTGRESDB_PASSWORD='...'
export N8N_ENCRYPTION_KEY='...'          # WAJIB sama tiap redeploy, jangan biarkan auto-generate
export N8N_BASIC_AUTH_USER='...'
export N8N_BASIC_AUTH_PASSWORD='...'
bash n8n-script.sh
```

Kredensial di atas disimpan durable di sisi hub (`~/.config/n8n-uploader/credentials.env`,
tidak di repo) dan diinject otomatis oleh proses bring-up.

## Workflow upload

Workflow n8n (JSON export) sebaiknya disimpan di folder `workflows/` (opsional,
belum ada — tambahkan begitu workflow upload pertama selesai dirakit di editor
n8n) supaya redeploy bisa auto-import, bukan dirakit ulang manual tiap VM baru.

## Catatan perbaikan (2026-08-15)

- **Dihapus**: komponen `analisa_viral` (viral-video analyzer duplikat) — analisis
  video sudah ditangani tuntas oleh pipeline `tool-analisa-video` terpisah; repo
  ini fokus murni pada distribusi/upload, bukan analisis ulang.
- **Dihapus**: `docker load` image `n8n.tar` dari Google Drive tanpa verifikasi
  — diganti `docker pull n8nio/n8n:latest` resmi.
- **Dihapus**: Cloudflare Tunnel + expose publik — diganti akses WireGuard-only.
- **Ditambah**: koneksi Postgres DB-VPS + `N8N_ENCRYPTION_KEY` durable + basic auth.
- `token.json` benar-benar di-untrack dari git (dulu masih ter-track meski sudah
  di `.gitignore`).
- rclone diinstal via `apt` (bukan `curl | sudo bash`).
- Bug format YAML pada perintah `cloudflared` (backslash line-continuation yang
  tak berfungsi di YAML folded block) jadi tak relevan — servicenya dihapus.
