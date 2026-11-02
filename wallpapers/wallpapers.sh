#!/usr/bin/env bash
# Phone wallpapers: renders wallpapers/shots.lua through trailer/trailer.lua 600 x 800 (a 360 x 800 portrait is cropped
# from each, the drift car kept centred), and the trailer's title card for the name, then wallpapers/compose.py makes
# wallpapers/proprush-*.png. Usage, from the repo root: wallpapers/wallpapers.sh. Needs edgetx-cli and python3 (PIL).
set -euo pipefail

FRAMES=$(mktemp -d)
trap 'rm -rf "$FRAMES"' EXIT

SIM=(edgetx-cli dev simulator --radios-dir ../edgetx-firmware/radios --radio "RadioMaster Boxer" --headless
  --script trailer/trailer.lua)
# 76.5 degrees on 600 x 800 is about 70 on the 360 x 800 crop
OUT=$FRAMES SHOTS=wallpapers/shots.lua SIZE=600x800 FOV=76.5 "${SIM[@]}" | grep -E "frames" || true
OUT=$FRAMES SHOT=title "${SIM[@]}" | grep -E "frames" || true
python3 wallpapers/compose.py "$FRAMES" wallpapers
