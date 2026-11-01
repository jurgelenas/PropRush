#!/usr/bin/env bash
# Trailer: renders trailer/trailer.lua's frames and cuts them into a 1080p video, each LCD pixel 15 x 15 with the
# panel's pixel grid over it, and each scene on its own as <out dir>/trailer-scenes/NN-shot.mp4 for review. A scene
# approved by moving it to <out dir>/trailer-approved/ under the same name is used from there as it is, never
# rendered again. The soundtrack (trailer/trailer_music.py) is scored to the cuts.
# Usage, from the repo root: trailer/trailer.sh [out.mp4] (default dist/trailer.mp4).
# Needs edgetx-cli, ffmpeg and python3.
set -euo pipefail

OUT_MP4=${1:-dist/trailer.mp4}
FRAMES=$(mktemp -d)
WORK=$(mktemp -d)
trap 'rm -rf "$FRAMES" "$WORK"' EXIT

OUT=$FRAMES edgetx-cli dev simulator --radio "RadioMaster Boxer" --headless --script trailer/trailer.lua |
  grep -E "frames|hits|axis" || true

# Shot, first frame, frame count (0: to its end)
SEGMENTS=(
  "drift 1 0"
  "title 1 0"
  "menu 1 0"
  "racing 1 0"
  "super8 1 170"
  "freestyle 1 0"
  "trainyard 1 0"
  "oldmilldive 1 0"
  "windfarm 1 0"
  "harbor 1 0"
  "cityslot 1 0"
  "crash 1 0"
  "end 1 0"
)

SCENES="$(dirname "$OUT_MP4")/trailer-scenes"
APPROVED="$(dirname "$OUT_MP4")/trailer-approved"
rm -rf "$SCENES"
mkdir -p "$SCENES"

# The trailer's first frame, the thumbnail uploads show (else the opening static): this scene's frame at this second
POSTER=(title 1)

LOOK="scale=1920:960:flags=neighbor,drawgrid=w=15:h=15:t=1:c=0x8a8c80@0.6,pad=1920:1080:0:60:0x101010"
: >"$WORK/list.txt"
i=0
durations=()
for seg in "${SEGMENTS[@]}"; do
  read -r name first count <<<"$seg"
  limit=()
  if [ "$count" -gt 0 ]; then
    limit=(-frames:v "$count")
  fi
  i=$((i + 1))
  file=$(printf "%02d-%s.mp4" "$i" "$name")
  scene=$APPROVED/$file
  if [ ! -f "$scene" ]; then
    scene=$SCENES/$file
    ffmpeg -loglevel error -y -framerate 30 -start_number "$first" -i "$FRAMES/${name}_%04d.png" "${limit[@]}" \
      -vf "$LOOK" -c:v libx264 -preset slow -crf 16 -pix_fmt yuv420p -r 30 "$scene"
  fi
  echo "file '$(realpath "$scene")'" >>"$WORK/list.txt"
  durations+=("$name=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$scene")")
  if [ "$name" = "${POSTER[0]}" ]; then
    ffmpeg -loglevel error -y -ss "${POSTER[1]}" -i "$scene" -frames:v 1 "$WORK/poster.png"
  fi
done

# One frame, as the scenes are encoded, ahead of them all; the music starts after it
ffmpeg -loglevel error -y -framerate 30 -i "$WORK/poster.png" -frames:v 1 -c:v libx264 -preset slow -crf 16 \
  -pix_fmt yuv420p -r 30 "$WORK/poster.mp4"
sed -i "1i file '$WORK/poster.mp4'" "$WORK/list.txt"
durations=("poster=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$WORK/poster.mp4")" "${durations[@]}")

mkdir -p "$(dirname "$OUT_MP4")"
python3 trailer/trailer_music.py "$WORK/music.wav" "${durations[@]}"
ffmpeg -loglevel error -y -f concat -safe 0 -i "$WORK/list.txt" -i "$WORK/music.wav" -map 0:v -map 1:a -c:v copy \
  -c:a aac -b:a 192k -movflags +faststart "$OUT_MP4"
echo "$SCENES: $(ls "$SCENES" | wc -l) scenes"
echo "$OUT_MP4: $(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT_MP4") s"
