# Workflows

## `facebook-reel-draft.json`

Dirakit **2026-08-24**, sebagai bagian dari uji pipeline penuh
`hibernate→wake→CloudShell→deploy→analisa→konten→n8n`. **BELUM PERNAH
DIUJI LIVE** (gogobuda `.61` offline saat dirakit, dan Page Access Token
Facebook belum ada) — anggap ini draft solid, bukan yang final terverifikasi.
Rencana: import + 1x dry-run begitu token + gogobuda live bersamaan, lalu
perbaiki kalau ada quirk endpoint Meta yang meleset dari dokumentasi.

### Alur

1. **List VN-exports** — `rclone lsjson gfootage:VN-exports/` (remote
   `gfootage` baru disambung ke rclone.conf gogobuda, lihat bagian rclone di
   `README.md` utama repo ini).
2. **Pick Latest Reel** — pilih `.mp4` dengan `ModTime` terbaru; caption
   diasumsikan file kembar `<nama-video>.story-script.md` di folder yang sama
   (sesuai SOP `ir_to_vn.py` wajib keluarkan story-script). Kalau file caption
   tidak ada, fallback ke teks placeholder generik (tidak fatal).
3. **Copy Video/Caption Locally** — `rclone copy` ke `/app/output/` (volume
   yang sama dipetakan compose ke host).
4. **Read Video File** — baca jadi binary.
5. **FB: Start Upload → FB: Upload Binary → FB: Finish Upload (Draft)** —
   Meta **Reels Publishing API** 3-fase (`/​{page-id}/video_reels`):
   `upload_phase=start` → dapat `video_id`+`upload_url` → POST body biner ke
   `upload_url` (header `offset`/`file_size`) → `upload_phase=finish` dengan
   `video_state=DRAFT` (**TIDAK auto-publish** — masuk Page sbg draft,
   direview manual sebelum tayang, sesuai keputusan user).

### Sebelum jalan pertama kali — 2 kredensial WAJIB dibuat manual di n8n UI

Node mengacu kredensial by-name, tapi n8n TAK bisa auto-buat kredensial dari
import JSON (secret tak pernah ikut ter-export). Buka
`http://10.66.66.61:5678` (WireGuard saja) → **Credentials → New**:

1. **`Facebook Graph API Token`** (tipe *Query Auth*) — Name: `access_token`,
   Value: `<Page Access Token>`. Dipakai node `FB: Start Upload` +
   `FB: Finish Upload (Draft)`.
2. **`Facebook Reels Upload OAuth Header`** (tipe *Header Auth*) — Name:
   `Authorization`, Value: `OAuth <Page Access Token>` (huruf besar-kecil
   persis, ini format yang didokumentasikan Meta utk endpoint upload biner,
   BEDA dari `Bearer` yang dipakai 2 node lain). Dipakai node
   `FB: Upload Binary`.

Token yang sama dipakai di keduanya, cuma beda format header. Long-lived Page
Access Token (60 hari) direkomendasikan, bukan short-lived (1 jam) dari Graph
API Explorer.

Setelah 2 kredensial itu ada, buka tiap node `FB: *` di editor n8n dan
pastikan field Credential-nya ke-link (biasanya otomatis match by-name kalau
nama persis sama; kalau tidak, pilih manual dari dropdown).

### Page ID di-hardcode

`896095410254698` (asset Page "Go Go Bud" / gogobud13) muncul di 2 tempat
(`FB: Start Upload`, `FB: Finish Upload (Draft)`). Kalau pindah Page, cari
string ini di JSON dan ganti di kedua node.

### Cara import

```bash
# di gogobuda (.61), setelah container n8n hidup:
docker cp facebook-reel-draft.json n8n:/tmp/facebook-reel-draft.json
docker exec n8n n8n import:workflow --input=/tmp/facebook-reel-draft.json
```

Cara ini (`import:workflow` di dalam container) dipilih drpd REST API n8n
langsung — bypass HTTP auth sepenuhnya, sesuai rekomendasi lama di
`project_medsos_agent` memory (belum ada kredensial login UI n8n tersimpan).

### Belum dikerjakan / batasan yang disadari

- Belum ada **Schedule Trigger** — sengaja Manual Trigger dulu untuk uji
  terkendali; ganti setelah pipeline terbukti stabil.
- Belum ada **polling status pasca-`finish`** (Meta butuh waktu proses video
  sebelum benar-benar muncul di draft) — cek manual dulu di Page setelah
  eksekusi, tambahkan `GET /{video-id}?fields=status` + `Wait` node kalau mau
  otomatis.
- Belum menangani **file besar** (upload biner ini single-shot, bukan
  chunked) — cukup untuk Reel pendek (puluhan MB seperti yang sudah teruji di
  `gfootage:VN-exports/`), tapi kalau suatu saat video jauh lebih besar,
  perlu direvisi ke multi-request chunked upload sesuai resumable upload API
  Meta.
- **IG/YT belum digarap sama sekali** — sesuai keputusan user, scope hari ini
  cuma Facebook Reel.
