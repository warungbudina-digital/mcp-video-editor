#!/bin/bash

echo "==============================="
echo "🚀 STARTING DEPLOYMENT PROCESS"
echo "==============================="

echo "📦 Install tools pendukung (htop, jq)..."
sudo apt update
sudo apt install -y htop jq

git clone https://github.com/sun-guannan/VectCutAPI.git

mkdir -p VectCutAPI/raw_transkrip
mkdir -p VectCutAPI/raw_video
mkdir -p VectCutAPI/raw_audio
mkdir -p VectCutAPI/output

cat > VectCutAPI/requirements.txt <<'EOF'

imageio
psutil
flask
requests
oss2
aiohttp>=3.8.0
pydantic>=2.0.0
json5
EOF

sudo chown -R 1000:1000 VectCutAPI

echo "⬇️ Install rclone..."
curl https://rclone.org/install.sh | sudo bash

# ========================
# KONFIGURASI RCLONE DAN TUNNEL
# ========================
REMOTE_NAME="gdrive"
TOKEN_FILE="./token.json"
RCLONE_CONF_PATH="$HOME/.config/rclone/rclone.conf"
DEST_FOLDER="$(pwd)"
GDRIVE_FOLDER="Project-Tutorial/n8n"
IMAGE_FILE="n8n.tar"

echo ""
echo "==============================="
echo "⚙️  CONFIGURING RCLONE"
echo "==============================="

if [ ! -f "$TOKEN_FILE" ]; then
  echo "❌ File token.json tidak ditemukan di path: $TOKEN_FIlE"
  exit 1
fi

echo "⚙️ Menyiapkan rclone.conf..."
mkdir -p "$(dirname "$RCLONE_CONF_PATH")"
TOKEN=$(jq -c . "$TOKEN_FILE")

cat > "$RCLONE_CONF_PATH" <<EOF
[$REMOTE_NAME]
type = drive
scope = drive
token = $TOKEN
EOF

echo "✅ rclone.conf berhasil dibuat."

# ========================
# DOWNLOAD IMAGE n8n.tar
# ========================
echo ""
echo "==============================="
echo "⬇️  DOWNLOADING n8n.tar FROM GOOGLE DRIVE"
echo "==============================="

echo "📁 Folder Drive: $GDRIVE_FOLDER"
echo "📁 Tujuan: $DEST_FOLDER"

sudo rclone copy --config="$RCLONE_CONF_PATH" "$REMOTE_NAME:$GDRIVE_FOLDER/$IMAGE_FILE" "$DEST_FOLDER" --progress

if [ $? -ne 0 ]; then
  echo "❌ Gagal men-download n8n.tar dari Google Drive!"
  exit 1
fi

echo "✅ Download selesai."

# ========================
# LOAD DOCKER IMAGE
# ========================
echo ""
echo "==============================="
echo "🐳  LOADING DOCKER IMAGE"
echo "==============================="

if [ ! -f "$IMAGE_FILE" ]; then
  echo "❌ File $IMAGE_FILE tidak ditemukan setelah download!"
  exit 1
fi

mkdir n8n_data
mkdir -p n8n_data/cookies
mkdir -p vendor
mkdir -p analisa_viral

curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
-o vendor/yt-dlp

sudo docker load -i "$IMAGE_FILE"

echo "🏷️ Menandai image menjadi custom-n8n:latest ..."
sudo docker tag n8nio/n8n:latest custom-n8n:latest

echo "✅ Image berhasil diload & ditag."

echo ""
echo "==============================="
echo "🔧  BUILDING EXTENDED N8N IMAGE (FFMPEG + YT-DLP)"
echo "==============================="

cat > VectCutAPI/Dockerfile <<'EOF'

FROM python:3.10-slim

WORKDIR /app
COPY . /app
RUN pip install --no-cache-dir -r requirements.txt

EXPOSE 9000

CMD ["python", "capcut_server.py"]
EOF

echo "==============================="

cat > analisa_viral/requirements.txt <<'EOF'
opencv-python-headless
numpy
librosa
moviepy
scikit-learn
EOF

echo "==============================="
cat > analisa_viral/analyzer.py <<'EOF'
import os
import json
import cv2
import numpy as np
import librosa
import pysrt

VIDEO_DIR="/app/raw_video"
AUDIO_DIR="/app/raw_audio"
SUB_DIR="/app/raw_transkrip"
OUTPUT_DIR="/app/output"

os.makedirs(OUTPUT_DIR, exist_ok=True)

def find_file(folder,ext):
    for f in os.listdir(folder):
        if f.lower().endswith(ext):
            return os.path.join(folder,f)
    return None


video_path=find_file(VIDEO_DIR,".mp4")
audio_path=find_file(AUDIO_DIR,".wav")
sub_path=find_file(SUB_DIR,".srt")

if not video_path:
    raise Exception("Video not found")

if not audio_path:
    raise Exception("Audio not found")

if not sub_path:
    raise Exception("Subtitle not found")


# --------------------------------------------------
# AUDIO ANALYSIS (BPM + BEAT DROP)
# --------------------------------------------------

y,sr=librosa.load(audio_path)

tempo,beats=librosa.beat.beat_track(y=y,sr=sr)

onset_env=librosa.onset.onset_strength(y=y,sr=sr)

onsets=librosa.onset.onset_detect(onset_envelope=onset_env,sr=sr)

onset_times=librosa.frames_to_time(onsets,sr=sr)

beat_drop=[]

threshold=np.mean(onset_env)+np.std(onset_env)

for i,val in enumerate(onset_env):
    if val>threshold:
        t=librosa.frames_to_time(i,sr=sr)
        beat_drop.append(float(t))


# --------------------------------------------------
# VIDEO ANALYSIS
# --------------------------------------------------

cap=cv2.VideoCapture(video_path)

fps=cap.get(cv2.CAP_PROP_FPS)

prev_gray=None
frame_index=0

cuts=[]
motion_strength=[]
zoom_events=[]
shake_events=[]

motion_window=[]

while True:

    ret,frame=cap.read()
    if not ret:
        break

    gray=cv2.cvtColor(frame,cv2.COLOR_BGR2GRAY)

    if prev_gray is not None:

        diff=cv2.absdiff(prev_gray,gray)
        score=diff.mean()

        if score>25:
            cuts.append(frame_index/fps)

        flow=cv2.calcOpticalFlowFarneback(
            prev_gray,gray,None,
            0.5,3,15,3,5,1.2,0
        )

        mag,ang=cv2.cartToPolar(flow[...,0],flow[...,1])

        motion=np.mean(mag)

        motion_strength.append(float(motion))
        motion_window.append(motion)

        if len(motion_window)>10:
            motion_window.pop(0)

        # SHAKE detection
        if np.std(motion_window)>0.8:
            shake_events.append(frame_index/fps)

        # ZOOM detection
        center=flow[
            flow.shape[0]//2-40:flow.shape[0]//2+40,
            flow.shape[1]//2-40:flow.shape[1]//2+40
        ]

        edge=np.concatenate([
            flow[:40,:,:],
            flow[-40:,:,:]
        ])

        center_mag=np.mean(np.linalg.norm(center,axis=2))
        edge_mag=np.mean(np.linalg.norm(edge,axis=2))

        if edge_mag>center_mag*1.3:
            zoom_events.append(frame_index/fps)

    prev_gray=gray
    frame_index+=1

cap.release()


# --------------------------------------------------
# SUBTITLE ANALYSIS
# --------------------------------------------------

subs=pysrt.open(sub_path)

segments=[]
durations=[]
word_counts=[]

for s in subs:

    start=s.start.ordinal/1000
    end=s.end.ordinal/1000
    duration=end-start

    text=s.text.replace("\n"," ")

    segments.append({
        "text":text,
        "start":start,
        "end":end
    })

    durations.append(duration)

    word_counts.append(len(text.split()))


avg_sub_duration=float(np.mean(durations))

if avg_sub_duration<1.5:
    subtitle_pattern="fast"

elif avg_sub_duration<3:
    subtitle_pattern="medium"

else:
    subtitle_pattern="slow"


# --------------------------------------------------
# HOOK DETECTION
# --------------------------------------------------

hook_detected=False
hook_time=None

for c in cuts:
    if c<3:
        hook_detected=True
        hook_time=c
        break

for z in zoom_events:
    if z<2:
        hook_detected=True
        hook_time=z


# --------------------------------------------------
# LOOP ENDING DETECTION
# --------------------------------------------------

loop_detected=False

if cuts:
    last_cut=cuts[-1]

    video_length=frame_index/fps

    if video_length-last_cut<1.2:
        loop_detected=True


# --------------------------------------------------
# TEMPLATE OUTPUT
# --------------------------------------------------

template={

    "video":os.path.basename(video_path),

    "bpm":float(tempo),

    "beat_drop":beat_drop[:10],

    "cuts":cuts[:30],

    "motion_avg":float(np.mean(motion_strength)) if motion_strength else 0,

    "zoom_events":zoom_events[:10],

    "shake_events":shake_events[:10],

    "subtitle_pattern":subtitle_pattern,

    "subtitle_segments":segments[:20],

    "hook":{
        "detected":hook_detected,
        "time":hook_time
    },

    "loop_ending":loop_detected

}


output_path=os.path.join(OUTPUT_DIR,"template.json")

with open(output_path,"w") as f:
    json.dump(template,f,indent=4)


print("Template generated")
print(json.dumps(template,indent=2))
EOF

echo "==============================="

cat > analisa_viral/Dockerfile <<'EOF'
FROM python:3.11-slim

WORKDIR /app

USER root

RUN apt-get update && apt-get install -y \
    ffmpeg \
    libgl1 \
    libglib2.0-0 \
    build-essential \
    && rm -rf /var/lib/apt/lists/*
    
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY analyzer.py .

CMD ["sleep","infinity"]
EOF

echo "✅ container analisa berhasil"

echo "==============================="

cat > Dockerfile.extend <<'EOF'
FROM custom-n8n:latest

USER root

RUN apk add --no-cache \
    ffmpeg \
    python3 

COPY vendor/yt-dlp /usr/local/bin/yt-dlp
RUN chmod +x /usr/local/bin/yt-dlp

USER node
EOF

sudo docker build -f Dockerfile.extend -t custom-n8n:ffmpeg .

echo "✅ Extended image built: custom-n8n:ffmpeg"

# ========================
# MEMBUAT DOCKER-COMPOSE
# ========================
echo ""
echo "==============================="
echo "📝  GENERATING docker-compose.yml"
echo "==============================="

cat > docker-compose.yml <<'EOF'
version: "3.8"

services:
  n8n:
    image: custom-n8n:ffmpeg
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
      #- N8N_DATA_TABLES_MAX_SIZE_BYTES=
      - NODE_ENV=production
      - EXECUTIONS_PROCESS=main
    volumes:
      - ./n8n_data:/home/node/.n8n
      - ./VectCutAPI/raw_transkrip:/app/raw_transkrip
      - ./VectCutAPI/raw_video:/app/raw_video
      - ./VectCutAPI/raw_audio:/app/raw_audio
      - ./VectCutAPI/output:/app/output
    mem_limit: 1g
    cpus: 1.5

  vectcutapi:
    build: ./VectCutAPI
    container_name: VectCutAPI
    restart: always
    networks:
      - n8n_net
    volumes:
      - ./VectCutAPI/raw_transkrip:/app/raw_transkrip
      - ./VectCutAPI/raw_video:/app/raw_video
      - ./VectCutAPI/raw_audio:/app/raw_audio
      - ./VectCutAPI/output:/app/output
    mem_limit: 2g
    cpus: 2.0

  viral_analyzer:
    build: ./analisa_viral
    container_name: analisa_viral
    restart: always
    networks:
      - n8n_net
    volumes:
      - ./VectCutAPI/raw_transkrip:/app/raw_transkrip
      - ./VectCutAPI/raw_video:/app/raw_video
      - ./VectCutAPI/raw_audio:/app/raw_audio
      - ./VectCutAPI/output:/app/output
    mem_limit: 2g
    cpus: 2.0

  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflared
    restart: always
    networks:
      - n8n_net
    command: >
      tunnel --no-autoupdate run --token x

networks:
  n8n_net:
    driver: bridge
EOF

echo "✅ docker-compose.yml berhasil dibuat."

# ========================
# DEPLOY DOCKER COMPOSE
# ========================
echo ""
echo "==============================="
echo "🚀  STARTING DOCKER COMPOSE"
echo "==============================="

sudo docker compose up -d

if [ $? -eq 0 ]; then
    echo "🎉 Deploy berhasil!"
    echo "🌐 Aplikasi berjalan di port 5678"
else
    echo "❌ Deploy gagal!"
fi
sudo rm -r n8n.tar
sudo rm -r n8n-script.sh
sudo rm -r token.json
sudo rm -r Dockerfile.extend
sudo rm -r vendor

ping 8.8.8.8
