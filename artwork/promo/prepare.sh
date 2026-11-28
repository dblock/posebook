#!/bin/bash
# Turns the raw captures in tmp/ into the committed inputs in sources/ and shots/.
# Run after `node capture-sources.mjs` (tmp/igfull, tmp/enochs-frames) and `node capture.mjs` (shots/n-*.png).
set -euo pipefail
cd "$(dirname "$0")"
if [ -f tmp/enochs-frames/list.txt ]; then
  # x264 needs an even height, so the 1920x993 screencast is scaled to 1920x994.
  ffmpeg -loglevel error -y -f concat -safe 0 -i tmp/enochs-frames/list.txt \
    -vf "fps=30,scale=1920:994,format=yuv420p" -c:v libx264 -crf 12 -preset slow sources/enochs.mp4
fi
if [ -d tmp/igfull ]; then
  cp tmp/igfull/DINSnrgNrN5.jpg sources/session.jpg
  cp tmp/igfull/DaAcd1CtZZV.jpg shots/drawing-figure.jpg
  cp tmp/igfull/DdK6XYcjeFl.jpg shots/drawing-profile.jpg
  sips -Z 1200 shots/drawing-figure.jpg shots/drawing-profile.jpg >/dev/null
fi
if [ -f shots/n-settings.png ]; then
  crop() { ffmpeg -loglevel error -y -i "shots/n-$1.png" -vf "crop=$2" "shots/k-$1.png"; }
  ffmpeg -loglevel error -y -i shots/n-settings.png \
    -filter_complex "[0]split[a][b];[a]crop=1872:630:0:1460[x];[b]crop=1872:160:0:3025[y];[x][y]vstack" shots/k-settings.png
  crop notifications 1868:1000:0:0
  crop confirmed 1872:540:0:0
  crop google 1872:720:0:0
  crop org 917:1790:50:345
  crop model 900:1400:40:360
  cp shots/n-close.png shots/k-close.png
fi
cp ../posebook-logo-source.png shots/logo.png
sips -Z 600 shots/logo.png >/dev/null
node -e '
const QR = require("qrcode");
QR.toFile("shots/qr.png", "https://art.dblock.org/2026/05/25/figure-drawing-at-enochs.html",
  { width: 640, margin: 2, errorCorrectionLevel: "M", color: { dark: "#3b1a0e", light: "#fffaf3" } }, (e) => { if (e) throw e; });'
