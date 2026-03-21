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
scenedetect
open_clip_torch
torch
pysrt
scipy
fastapi
uvicorn
python-multipart
EOF

echo "==============================="

cat > analisa_viral/server.py <<'EOF'
from fastapi import FastAPI
import subprocess
import json
import os

app = FastAPI()

OUTPUT="/app/output/template.json"

@app.get("/")
def health():
    return {"status":"video analyzer running"}

@app.post("/analyze")
def analyze():

    subprocess.run(["python3","/app/analyzer.py"])

    if os.path.exists(OUTPUT):
        with open(OUTPUT) as f:
            data=json.load(f)
        return data

    return {"error":"template not generated"}
EOF

echo "==============================="

cat > analisa_viral/analyzer.py <<'EOF'
import os
import cv2
import json
import numpy as np
import librosa
import pysrt
import torch
import open_clip
import subprocess
import math
from PIL import Image
from collections import Counter

from scenedetect import VideoManager, SceneManager
from scenedetect.detectors import ContentDetector

VIDEO_DIR="/app/raw_video"
AUDIO_DIR="/app/raw_audio"
SUB_DIR="/app/raw_transkrip"
OUTPUT_DIR="/app/output"

os.makedirs(OUTPUT_DIR,exist_ok=True)

# -----------------------------
# JSON SAFE
# -----------------------------
def json_safe(obj):

    if isinstance(obj,np.integer):
        return int(obj)

    if isinstance(obj,np.floating):
        val=float(obj)
        if math.isnan(val) or math.isinf(val):
            return 0.0
        return val

    if isinstance(obj,float):
        if math.isnan(obj) or math.isinf(obj):
            return 0.0
        return obj

    if isinstance(obj,np.ndarray):
        return obj.tolist()

    return obj

def safe_mean(arr):
    return float(np.mean(arr)) if len(arr)>0 else 0.0

# -----------------------------
# NORMALIZE VIDEO
# -----------------------------
def normalize_video(input_path):

    output_path="/tmp/normalized.mp4"

    cmd=[
        "ffmpeg","-y",
        "-i",input_path,
        "-vf","scale=1280:720,fps=30",
        "-c:v","libx264",
        "-preset","fast",
        "-crf","23",
        "-pix_fmt","yuv420p",
        "-c:a","aac",
        "-ar","22050",
        output_path
    ]

    subprocess.run(cmd,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)

    return output_path

# -----------------------------
# FIND FILE
# -----------------------------
def find_file(folder,ext):
    for f in os.listdir(folder):
        if f.lower().endswith(ext):
            return os.path.join(folder,f)
    return None

# -----------------------------
# LOAD CLIP
# -----------------------------
device="cuda" if torch.cuda.is_available() else "cpu"

model,_,preprocess=open_clip.create_model_and_transforms(
    "ViT-B-16",
    pretrained="openai"
)

model.to(device)

semantic_labels=[
    "person talking","reaction face","b-roll footage",
    "podcast conversation","youtube talking head","motivational speech",
    "slow motion footage","dark room","low quality blurry image"
    "screen recording","product shot","presentation slide","gaming footage"
]

emotion_labels=[
    "happy face","sad face","angry face","surprised face","neutral face","excited face"
]

meme_labels=[
    "funny scene","meme template","reaction meme","text overlay meme"
]

with torch.no_grad():
    text_features=model.encode_text(open_clip.tokenize(semantic_labels).to(device))
    emotion_features=model.encode_text(open_clip.tokenize(emotion_labels).to(device))
    meme_features=model.encode_text(open_clip.tokenize(meme_labels).to(device))

# -----------------------------
# CLIP CLASSIFIER
# -----------------------------
def clip_classify(frame,features,labels):

    image=Image.fromarray(cv2.cvtColor(frame,cv2.COLOR_BGR2RGB))
    image=preprocess(image).unsqueeze(0).to(device)

    with torch.no_grad():
        img=model.encode_image(image)
        sim=(img @ features.T).softmax(dim=-1)

    return labels[sim.argmax().item()]

def semantic_scene(frame):
    return clip_classify(frame,text_features,semantic_labels)

def detect_emotion(frame):
    return clip_classify(frame,emotion_features,emotion_labels)

def detect_meme(frame):
    return clip_classify(frame,meme_features,meme_labels)

# -----------------------------
# FACE
# -----------------------------
face_model=cv2.CascadeClassifier(
    cv2.data.haarcascades+"haarcascade_frontalface_default.xml"
)

def framing_detection(frame):

    gray=cv2.cvtColor(frame,cv2.COLOR_BGR2GRAY)
    faces=face_model.detectMultiScale(gray,1.3,5)

    result={"faces":[],"speaker_position":"unknown"}
    h,w=frame.shape[:2]

    for (x,y,wf,hf) in faces:

        result["faces"].append({
            "x":int(x),"y":int(y),"w":int(wf),"h":int(hf)
        })

        center=x+wf/2

        if center<w*0.33:
            result["speaker_position"]="left"
        elif center>w*0.66:
            result["speaker_position"]="right"
        else:
            result["speaker_position"]="center"

    return result

# -----------------------------
# MOTION
# -----------------------------
def motion_score(prev,cur):

    flow=cv2.calcOpticalFlowFarneback(prev,cur,None,0.5,3,15,3,5,1.2,0)
    mag,_=cv2.cartToPolar(flow[...,0],flow[...,1])

    val=np.mean(mag)
    if np.isnan(val) or np.isinf(val):
        return 0.0

    return float(val)

def camera_movement(prev,cur):

    if prev is None:
        return "static"

    flow=cv2.calcOpticalFlowFarneback(prev,cur,None,0.5,3,15,3,5,1.2,0)
    mag,_=cv2.cartToPolar(flow[...,0],flow[...,1])

    avg=np.mean(mag)

    if avg<0.5:
        return "static"
    elif avg<2:
        return "slow_move"
    else:
        return "fast_move"

# -----------------------------
# TRANSITION
# -----------------------------
def detect_transition(prev_frame,cur_frame):

    if prev_frame is None:
        return "cut"

    prev_hist=cv2.calcHist([prev_frame],[0],None,[256],[0,256])
    cur_hist=cv2.calcHist([cur_frame],[0],None,[256],[0,256])

    diff=cv2.compareHist(prev_hist,cur_hist,cv2.HISTCMP_BHATTACHARYYA)

    if diff>0.5:
        return "flash"
    if diff>0.3:
        return "fade"

    return "cut"

# -----------------------------
# AUDIO
# -----------------------------
def analyze_audio(audio):

    y,sr=librosa.load(audio,sr=22050)

    tempo,beats=librosa.beat.beat_track(y=y,sr=sr,units="time")

    if isinstance(tempo,np.ndarray):
        tempo=float(tempo[0]) if tempo.size>0 else 0.0
    else:
        tempo=float(tempo)

    return tempo,beats

# -----------------------------
# SUBTITLE
# -----------------------------
def analyze_subtitles(sub_file):

    subs=pysrt.open(sub_file)

    segments=[]
    durations=[]

    for s in subs:

        start=s.start.ordinal/1000
        end=s.end.ordinal/1000
        text=s.text.replace("\n"," ")

        segments.append({"text":text,"start":start,"end":end})
        durations.append(end-start)

    avg=np.mean(durations) if durations else 0

    style={}

    if avg<1.2:
        style["speed"]="fast"
    elif avg<2.5:
        style["speed"]="medium"
    else:
        style["speed"]="slow"

    style["word_count_avg"]=safe_mean([len(x["text"].split()) for x in segments])

    return style,segments

# -----------------------------
# SCENE
# -----------------------------
def detect_scenes(video):

    video_manager=VideoManager([video])
    scene_manager=SceneManager()
    scene_manager.add_detector(ContentDetector(threshold=20))

    video_manager.start()
    scene_manager.detect_scenes(frame_source=video_manager)

    scenes=[]

    for s in scene_manager.get_scene_list():
        start=s[0].get_seconds()
        end=s[1].get_seconds()
        scenes.append({"start":start,"end":end,"duration":end-start})

    return scenes

# -----------------------------
# SAMPLING
# -----------------------------
def sample_frames(cap,start,end,num_samples=3):

    frames=[]

    if end<=start:
        end=start+0.5

    for t in np.linspace(start,end,num_samples):
        cap.set(cv2.CAP_PROP_POS_MSEC,t*1000)
        ret,frame=cap.read()
        if ret:
            frames.append(frame)

    return frames

def majority_vote(arr):
    return Counter(arr).most_common(1)[0][0] if arr else "unknown"

# -----------------------------
# HOOK
# -----------------------------
def viral_hook(scene):

    score=0

    if scene["duration"]<2: score+=2
    if scene["motion"]>1: score+=2
    if scene["beat_sync"]: score+=1
    if len(scene["framing"]["faces"])>0: score+=2

    if score>=5: return "strong_hook"
    if score>=3: return "medium_hook"
    return "weak_hook"

# -----------------------------
# MAIN
# -----------------------------
def run():

    video=find_file(VIDEO_DIR,".mp4")
    audio=find_file(AUDIO_DIR,".mp3")
    sub=find_file(SUB_DIR,".srt")

    video=normalize_video(video)

    tempo,beats=analyze_audio(audio)
    subtitle_style,subs=analyze_subtitles(sub)

    scenes=detect_scenes(video)

    cap=cv2.VideoCapture(video)

    if not cap.isOpened():
        raise Exception("Video gagal dibuka")

    if len(scenes)==0:
        fps=cap.get(cv2.CAP_PROP_FPS)
        total=cap.get(cv2.CAP_PROP_FRAME_COUNT)
        dur=total/fps if fps>0 else 0
        scenes=[{"start":0,"end":dur,"duration":dur}]

    prev_gray=None
    prev_frame=None

    scene_data=[]

    for s in scenes:

        frames=sample_frames(cap,s["start"],s["end"],3)
        if not frames:
            continue

        semantics,emotions,memes,motions,framings=[],[],[],[],[]

        local_prev_gray=prev_gray

        for f in frames:

            gray=cv2.cvtColor(f,cv2.COLOR_BGR2GRAY)

            semantics.append(semantic_scene(f))
            emotions.append(detect_emotion(f))
            memes.append(detect_meme(f))
            framings.append(framing_detection(f))

            if local_prev_gray is not None:
                motions.append(motion_score(local_prev_gray,gray))

            local_prev_gray=gray

        semantic=majority_vote(semantics)
        emotion=majority_vote(emotions)
        meme=majority_vote(memes)
        motion=safe_mean(motions)

        framing=framings[len(framings)//2] if framings else {"faces":[],"speaker_position":"unknown"}

        camera=camera_movement(prev_gray,local_prev_gray)
        transition=detect_transition(prev_frame,frames[0])
        beat_sync=any(abs(b-s["start"])<0.2 for b in beats)

        obj={
            "start":s["start"],
            "end":s["end"],
            "duration":s["duration"],
            "semantic":semantic,
            "emotion":emotion,
            "meme":meme,
            "motion":motion,
            "camera_movement":camera,
            "transition":transition,
            "beat_sync":beat_sync,
            "framing":framing
        }

        obj["hook_strength"]=viral_hook(obj)

        scene_data.append(obj)

        prev_gray=local_prev_gray
        prev_frame=frames[-1]

    cap.release()

    if not scene_data:
        scene_data=[{"start":0,"end":0,"duration":0,"semantic":"unknown"}]

    output={
        "video":os.path.basename(video),
        "bpm":tempo,
        "subtitle_style":subtitle_style,
        "subtitle_segments":subs,
        "scene_analysis":scene_data
    }

    with open(os.path.join(OUTPUT_DIR,"template.json"),"w") as f:
        json.dump(output,f,indent=4,default=json_safe)

if __name__=="__main__":
    run()

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
COPY server.py .

EXPOSE 9010

CMD ["uvicorn","server:app","--host","0.0.0.0","--port","9010"]
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

sudo docker build -f Dockerfile.extend -t custom-n8n:latest .

echo "✅ Extended image built: custom-n8n:latest"

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
      #- N8N_DATA_TABLES_MAX_SIZE_BYTES=
      - NODE_ENV=production
      - EXECUTIONS_PROCESS=main
    volumes:
      - ./n8n_data:/home/node/.n8n
      - ./VectCutAPI/raw_transkrip:/app/raw_transkrip
      - ./VectCutAPI/raw_video:/app/raw_video
      - ./VectCutAPI/raw_audio:/app/raw_audio
      - ./VectCutAPI/output:/app/output
      #- /var/run/docker.sock:/var/run/docker.sock
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
#sudo rm -r docker-compose.yml
#sudo rm -r analisa_viral
#sudo rm -r VectCutAPI

ping 8.8.8.8
