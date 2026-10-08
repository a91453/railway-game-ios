#!/usr/bin/env python3
"""Synthesize the game's music and sound effects (RailwayGameApp/Resources/Audio/).

The same synth as the first promo video's soundtrack, so the game sounds as
the video does: a pad, a plucked arpeggio and rail joints over I - vi - IV - V
in C, a station chime, a whoosh and a rail joint. Everything is made here from
sine waves and seeded noise: no samples or third-party audio. The output is
the same on every run.

    python3 tools/audio/make_game_audio.py RailwayGameApp/Resources/Audio

Needs numpy, and ffmpeg on the PATH for the music's IMA4 CAF.
"""

import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 48_000
# 100 bpm makes a cycle of the chords exactly 921,600 frames: a whole number
# of IMA4 packets (64 frames), so the CAF ends without padding and loops
# without a gap.
BPM = 100
BEAT = 60 / BPM
BAR = 4 * BEAT
CHORDS = [[60, 64, 67, 71], [57, 60, 64, 67], [53, 57, 60, 64], [55, 59, 62, 65]]
CYCLE_BARS = 8  # each chord for two bars


def note_hz(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def pluck(m, length=0.9):
    k = np.arange(int(SR * length)) / SR
    f = note_hz(m)
    env = np.exp(-k * 5.5) * np.minimum(1, k * 400)
    return env * (np.sin(2 * np.pi * f * k) + 0.35 * np.sin(4 * np.pi * f * k) + 0.12 * np.sin(6 * np.pi * f * k))


def pad(ms, length):
    k = np.arange(int(SR * length)) / SR
    env = np.minimum(1, k / 0.6) * np.minimum(1, (length - k) / 0.8).clip(0)
    out = np.zeros_like(k)
    for m in ms:
        f = note_hz(m)
        for det in (-0.12, 0.0, 0.12):
            out += np.sin(2 * np.pi * f * (1 + det / 100) * k + det)
    return env * out / (3 * len(ms))


def clack():
    k = np.arange(int(SR * 0.08)) / SR
    noise = np.random.default_rng(7).standard_normal(len(k))
    noise = np.convolve(noise, np.ones(6) / 6, mode="same")
    return noise * np.exp(-k * 70) + 0.6 * np.sin(2 * np.pi * 180 * k) * np.exp(-k * 50)


def bell(m, length=2.2):
    k = np.arange(int(SR * length)) / SR
    f = note_hz(m)
    return np.exp(-k * 2.2) * (np.sin(2 * np.pi * f * k) + 0.4 * np.sin(2 * np.pi * f * 2.76 * k) * np.exp(-k * 3))


def whoosh(length):
    k = np.arange(int(SR * length)) / SR
    noise = np.random.default_rng(int(length * 1000)).standard_normal(len(k))
    u = k / length
    # A one-pole low-pass swept up and back down: the noise rises and falls.
    cut = 0.02 + 0.25 * np.sin(np.pi * u) ** 2
    out = np.zeros_like(noise)
    y = 0.0
    for j in range(len(noise)):
        y += cut[j] * (noise[j] - y)
        out[j] = y
    return out * np.sin(np.pi * u) ** 1.5


def music(cycles):
    """`cycles` cycles of the chords in steady state, so they loop seamlessly.

    One more cycle is played before them (its tails ring into the first) and
    one after; only the middle is kept, and since the music repeats, its end
    runs on into its start.
    """
    cycle = int(round(SR * CYCLE_BARS * BAR))
    total = cycles + 2
    n = cycle * total
    mix = np.zeros((n, 2))

    def add(sig, start, pan=0.0, gain=1.0):
        i = int(round(start * SR))
        if i >= n:
            return
        sig = sig[: n - i] * gain
        mix[i : i + len(sig), 0] += sig * (1 - pan) / 2**0.5
        mix[i : i + len(sig), 1] += sig * (1 + pan) / 2**0.5

    for b in range(CYCLE_BARS * total):
        start = b * BAR
        chord = CHORDS[(b // 2) % 4]
        if b % 2 == 0:
            add(pad([m - 12 for m in chord], 2 * BAR + 0.6), start, gain=0.55)
            add(pad([chord[0] - 24], 2 * BAR + 0.4), start, gain=0.45)
        for j, p in enumerate([0, 2, 1, 3, 2, 1, 3, 2]):
            add(pluck(chord[p] + 12), start + j * BEAT / 2, pan=(-0.35 if j % 2 else 0.35), gain=0.20)
        add(clack(), start + 2 * BEAT, gain=0.18)
        add(clack(), start + 2 * BEAT + 0.13, gain=0.14)
    # A ping-pong echo of a dotted eighth.
    d = int(SR * BEAT * 0.75)
    echo = np.zeros_like(mix)
    echo[d:, 0] = mix[:-d, 1] * 0.25
    echo[d:, 1] = mix[:-d, 0] * 0.25
    mix += echo
    return mix[cycle : cycle * (1 + cycles)]


def normalized(x, peak):
    return x / np.abs(x).max() * peak


def write_wav(path, x):
    if x.ndim == 1:
        x = np.repeat(x.reshape(-1, 1), 2, axis=1)
    pcm = (x * 32767).round().clip(-32768, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def main(out_dir):
    os.makedirs(out_dir, exist_ok=True)

    loop = normalized(music(cycles=2), 0.7)
    assert len(loop) % 64 == 0, "the loop must be whole IMA4 packets"
    with tempfile.TemporaryDirectory() as tmp:
        source = os.path.join(tmp, "music.wav")
        write_wav(source, loop)
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", source, "-c:a", "adpcm_ima_qt",
             "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact",
             os.path.join(out_dir, "music-loop.caf")],
            check=True,
        )

    chime = bell(84)
    chime[int(0.25 * SR) :] += 0.6 * bell(91)[: len(chime) - int(0.25 * SR)]
    write_wav(os.path.join(out_dir, "station-chime.wav"), normalized(chime, 0.6))
    write_wav(os.path.join(out_dir, "whoosh.wav"), normalized(whoosh(1.0), 0.6))
    joint = np.zeros(int(0.35 * SR))
    a = clack()
    joint[: len(a)] += a
    joint[int(0.13 * SR) : int(0.13 * SR) + len(a)] += 0.8 * a
    write_wav(os.path.join(out_dir, "rail-joint.wav"), normalized(joint, 0.6))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
