"""Post-processing for this video only: splice the opening clip, add the music, shift captions and chapters.

Run after `make.mjs . all` and `bash opening.sh`. Writes out/video.mp4 (replacing the skill's), then
the caller runs `make.mjs . page` to rebuild the page from the shifted captions, chapters and transcript.
"""
import json, os, re, shutil, subprocess

os.chdir(os.path.dirname(os.path.abspath(__file__)))
os.makedirs("tmp", exist_ok=True)
FPS = 30
SCENE1_FRAMES = 164           # out/segments/enochs-0.mp4
OPEN = 8.0                    # tmp/opening.mp4, 240 frames
PRE = 1.5                     # music and storefront before Brian starts
SHIFT = OPEN - SCENE1_FRAMES / FPS
HOLD = 2.0                    # the invite card holds while the last chord rings
BAR = 4 * 60 / 112

def run(*a):
    subprocess.run(a, check=True)

def probe(path):
    return float(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path]))

src = "tmp/skill-video.mp4"
if not os.path.exists(src):
    shutil.copy("out/video.mp4", src)
base = probe(src)
total = base + SHIFT + HOLD
s1 = SCENE1_FRAMES / FPS

# Narration: scene 1 delayed by PRE inside the 8 s opening, the rest shifted by SHIFT.
run("ffmpeg", "-loglevel", "error", "-y", "-i", src, "-filter_complex",
    f"[0:a]asplit[a][b];[a]atrim=0:{s1},asetpts=N/SR/TB,adelay={int(PRE*1000)}:all=1,apad,atrim=0:{OPEN}[a1];"
    f"[b]atrim=start={s1},asetpts=N/SR/TB[b1];[a1][b1]concat=n=2:v=0:a=1,apad,atrim=0:{total}[n]",
    "-map", "[n]", "-ar", "48000", "-ac", "1", "tmp/narration.wav")

# Music: the held chord starts on the bar after the last line ends; delay the music so it lands there.
transcript = json.load(open("out/transcript.json"))
last_end = transcript[-1]["end"] + SHIFT
bars = int(last_end // BAR) + 1          # music.py holds the chord on its last bar
chord_at = (bars - 1) * BAR
delay = max(0.0, last_end + 0.15 - chord_at)
run("python3", "music.py", str(bars * BAR), "tmp/music-raw.wav")
run("ffmpeg", "-loglevel", "error", "-y", "-i", "tmp/music-raw.wav", "-af",
    f"aecho=0.8:0.5:60|120:0.25|0.15,loudnorm=I=-16:TP=-1.5,adelay={int(delay*1000)}:all=1,apad,atrim=0:{total},"
    f"afade=t=out:st={total-0.6}:d=0.6", "-ar", "48000", "-ac", "2", "tmp/music.wav")

# Mix: duck the music under the narration, as in the approved sample.
run("ffmpeg", "-loglevel", "error", "-y", "-i", "tmp/music.wav", "-i", "tmp/narration.wav", "-filter_complex",
    "[1:a]aformat=channel_layouts=stereo,asplit[vk][vm];"
    "[0:a][vk]sidechaincompress=threshold=0.03:ratio=8:attack=80:release=600:makeup=1[duck];"
    "[duck][vm]amix=inputs=2:duration=first:normalize=0,loudnorm=I=-16:TP=-1.5",
    "-ar", "48000", "tmp/mix.wav")

# Captions, chapters, transcript: scene 1 moves by PRE, everything after by SHIFT.
def shift(t, scene):
    return round(t + (PRE if scene == "enochs" else SHIFT), 2)
for c in transcript:
    c["start"], c["end"] = shift(c["start"], c["scene"]), shift(c["end"], c["scene"])
json.dump(transcript, open("out/transcript.json", "w"), indent=2)
chapters = json.load(open("out/chapters.json"))
for i, c in enumerate(chapters):
    c["start"] = 0 if i == 0 else round(c["start"] + SHIFT, 2)
json.dump(chapters, open("out/chapters.json", "w"), indent=2)

def stamp(t, sep):
    ms = int(round(t * 1000))
    return f"{ms//3600000:02d}:{ms%3600000//60000:02d}:{ms%60000//1000:02d}{sep}{ms%1000:03d}"
def cues(path, sep):
    text = open(path).read()
    def fix(m):
        a, b = m.group(1), m.group(2)
        def sec(x):
            h, mi, rest = x.split(":"); s, ms = re.split("[.,]", rest)
            return int(h) * 3600 + int(mi) * 60 + int(s) + int(ms) / 1000
        sa, sb = sec(a), sec(b)
        d = PRE if sa < s1 else SHIFT
        return f"{stamp(sa + d, sep)} --> {stamp(sb + d, sep)}"
    open(path, "w").write(re.sub(r"(\d\d:\d\d:\d\d[.,]\d\d\d) --> (\d\d:\d\d:\d\d[.,]\d\d\d)", fix, text))
cues("out/captions.vtt", ".")
cues("out/captions.srt", ",")

# Video: opening + the skill's video from scene 2 on + a held last frame; mix and captions muxed in.
run("ffmpeg", "-loglevel", "error", "-y", "-i", "tmp/opening.mp4", "-i", src, "-i", "tmp/mix.wav", "-i", "out/captions.srt",
    "-filter_complex",
    f"[1:v]trim=start_frame={SCENE1_FRAMES},setpts=PTS-STARTPTS[r];[0:v][r]concat=n=2:v=1:a=0,"
    f"tpad=stop_mode=clone:stop_duration={HOLD},format=yuv420p[v]",
    "-map", "[v]", "-map", "2:a", "-map", "3:s", "-c:v", "libx264", "-crf", "20", "-preset", "slow", "-r", str(FPS),
    "-c:a", "aac", "-b:a", "160k", "-c:s", "mov_text", "-metadata:s:s:0", "language=eng",
    "-movflags", "+faststart", "-t", f"{total:.3f}", "out/video.mp4")
print(f"total {total:.2f}s · shift {SHIFT:.3f}s · last line ends {last_end:.2f}s · chord at {chord_at+delay:.2f}s")
