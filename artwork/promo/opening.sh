#!/bin/bash
# Builds tmp/opening.mp4: 8.0 s (240 frames) of the enochs.nyc storefront zooming toward the window,
# dissolving into a pan across the session photo, with the @artdblockdotorg caption.
set -euo pipefail
cd "$(dirname "$0")"
node caption.mjs
FILTER='[0:v]split[s][t];[t]crop=224:22:713:743,boxblur=5:2[bl];[s][bl]overlay=713:743,crop=1545:869:200:122,scale=3840:2160:flags=lanczos,zoompan=z=1+0.12*on/162:x=(iw-iw/zoom)*0.42:y=(ih-ih/zoom)*0.12:d=1:s=1920x1080:fps=30,setsar=1,format=yuv420p[a];'
FILTER+='[1:v]scale=2560:1920:flags=lanczos,crop=1920:1080:x=560*t/3.4:y=380,setsar=1,format=yuv420p[b];'
FILTER+='[a][b]xfade=transition=fade:duration=0.8:offset=4.6[ab];'
FILTER+='[2:v]format=rgba,fade=in:st=0.9:d=0.5:alpha=1,fade=out:st=7.2:d=0.5:alpha=1[c];'
FILTER+='[ab][c]overlay=0:0:shortest=1,fade=in:st=0:d=0.4,format=yuv420p[v]'
ffmpeg -loglevel error -y \
  -ss 2.0 -t 5.4 -i sources/enochs.mp4 \
  -loop 1 -framerate 30 -t 3.4 -i sources/session.jpg \
  -loop 1 -framerate 30 -t 8 -i tmp/caption.png \
  -filter_complex "$FILTER" -map '[v]' -frames:v 240 -r 30 -c:v libx264 -crf 14 -preset slow tmp/opening.mp4
ffprobe -v error -count_frames -show_entries stream=nb_read_frames,width,height -of csv=p=0 tmp/opening.mp4
ffmpeg -loglevel error -y -i tmp/opening.mp4 \
  -vf "select='eq(n,15)+eq(n,100)+eq(n,150)+eq(n,172)+eq(n,200)+eq(n,236)',scale=960:-1,tile=2x3" -frames:v 1 tmp/open-sheet.jpg
ffmpeg -loglevel error -y -ss 4.5 -i tmp/opening.mp4 -frames:v 1 -vf 'crop=700:500:500:450' tmp/open-poster.png
echo ok
