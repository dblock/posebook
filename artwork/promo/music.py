"""Simple upbeat instrumental, synthesised from scratch with numpy (no samples, no rights questions).

Usage: python3 music.py <seconds> <out.wav>
112 BPM, C major, I-V-vi-IV. Kick, clap, shaker, plucked bass, marimba-like chords and a short
pentatonic hook. The last bar holds a C chord and rings out.
"""
import sys, wave
import numpy as np

SR = 44100
BPM = 112
BEAT = 60 / BPM
BAR = 4 * BEAT
rng = np.random.default_rng(7)


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def env(n, attack=0.005, decay=0.3):
    t = np.arange(n) / SR
    a = np.clip(t / attack, 0, 1)
    return a * np.exp(-t / decay)


def marimba(freq, dur, amp):
    n = int(dur * SR)
    t = np.arange(n) / SR
    tone = np.sin(2 * np.pi * freq * t) + 0.35 * np.sin(2 * np.pi * freq * 4 * t) * np.exp(-t / 0.05)
    return amp * tone * env(n, 0.003, 0.35)


def pluck_bass(freq, dur, amp):
    n = int(dur * SR)
    t = np.arange(n) / SR
    tone = np.tanh(1.8 * (np.sin(2 * np.pi * freq * t) + 0.3 * np.sin(2 * np.pi * 2 * freq * t)))
    return amp * tone * env(n, 0.004, 0.22)


def bell(freq, dur, amp):
    n = int(dur * SR)
    t = np.arange(n) / SR
    tone = np.sin(2 * np.pi * freq * t + 0.8 * np.sin(2 * np.pi * freq * 2 * t) * np.exp(-t / 0.2))
    return amp * tone * env(n, 0.004, 0.45)


def kick(amp):
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    f = 50 + 90 * np.exp(-t / 0.04)
    phase = 2 * np.pi * np.cumsum(f) / SR
    return amp * np.sin(phase) * np.exp(-t / 0.12)


def noise_hit(dur, decay, amp, bright):
    n = int(dur * SR)
    x = rng.standard_normal(n)
    if bright:  # crude high-pass: difference
        x = np.diff(x, prepend=0)
    else:  # band-ish: smooth then difference
        x = np.convolve(x, np.ones(4) / 4, mode="same")
        x = np.diff(x, prepend=0) * 1.5
    return amp * x * env(n, 0.001, decay)


def clap(amp):
    out = np.zeros(int(0.3 * SR))
    for i, d in enumerate((0, 0.011, 0.022)):
        h = noise_hit(0.25, 0.012 if i < 2 else 0.08, amp, False)
        s = int(d * SR)
        out[s:s + len(h)] += h[: len(out) - s]
    return out


def add(buf, sig, start, pan=0.0):
    s = int(start * SR)
    if s >= buf.shape[1]:
        return
    e = min(buf.shape[1], s + len(sig))
    sig = sig[: e - s]
    buf[0, s:e] += sig * (1 - pan) * 0.5 ** 0.5 * 1.41
    buf[1, s:e] += sig * (1 + pan) * 0.5 ** 0.5 * 1.41 / 1.0


def main():
    seconds = float(sys.argv[1])
    out = sys.argv[2]
    bars = int(np.ceil(seconds / BAR))
    total = int((bars * BAR + 3) * SR)
    buf = np.zeros((2, total))

    # C, G, Am, F voicings (MIDI), bass roots.
    chords = [[60, 64, 67, 72], [59, 62, 67, 71], [57, 60, 64, 69], [57, 60, 65, 69]]
    roots = [36, 43, 45, 41]
    # Pentatonic hook over two bars (beat offset, midi, length in beats).
    hook = [(0, 76, 0.5), (0.5, 79, 0.5), (1, 81, 1), (2.5, 79, 0.5), (3, 76, 1),
            (4, 74, 0.5), (4.5, 76, 0.5), (5, 79, 1.5), (7, 72, 1)]

    for b in range(bars):
        t0 = b * BAR
        last = b == bars - 1
        ci = b % 4
        if last:
            for n in chords[0]:
                add(buf, marimba(midi(n), 3.5, 0.12), t0, pan=0.2)
            add(buf, pluck_bass(midi(36), 2.5, 0.35), t0)
            add(buf, kick(0.8), t0)
            break
        intro = b < 1  # first bar: chords only, then the groove drops in
        for beat in range(4):
            tb = t0 + beat * BEAT
            if not intro:
                add(buf, kick(0.8), tb) if beat in (0, 2) else add(buf, clap(0.35), tb, pan=-0.1)
            # Off-beat chord stabs.
            for n in chords[ci]:
                add(buf, marimba(midi(n), 0.6, 0.07), tb + BEAT / 2, pan=0.25)
            if not intro:
                # Shaker on every eighth, accent off-beats.
                for k in range(2):
                    add(buf, noise_hit(0.08, 0.018, 0.08 if k else 0.045, True), tb + k * BEAT / 2, pan=0.35)
                # Bass: root, root, octave, fifth on eighths.
                pattern = [0, 0, 12, 7, 0, 0, 12, 7]
                for k in range(2):
                    step = beat * 2 + k
                    add(buf, pluck_bass(midi(roots[ci] + pattern[step]), BEAT / 2 * 0.9, 0.3), tb + k * BEAT / 2)
        # Hook on bars 2-3, 6-7, ... (every other pair), so it does not tire under the voice.
        if not intro and (b // 2) % 2 == 1:
            base = (b % 2) * 4
            for off, n, ln in hook:
                if base <= off < base + 4:
                    add(buf, bell(midi(n), ln * BEAT + 0.3, 0.11), t0 + (off - base) * BEAT, pan=-0.25)

    buf = buf[:, : int((seconds + 2.5) * SR)]
    # Fade the last 2 seconds of the requested length into the tail.
    peak = np.max(np.abs(buf))
    buf = buf / peak * 0.85
    pcm = (buf.T * 32767).astype(np.int16)
    with wave.open(out, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


if __name__ == "__main__":
    main()
