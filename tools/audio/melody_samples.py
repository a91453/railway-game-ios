"""The piano notes the app plays the player's melodies on (decision 883).

A melody the player writes in the melody workshop is made on the device
(`Sources/GamePresentation/PlayerMelodySynth.swift`) from these few notes of
the music's sampled piano (the chamber bank's, Salamander, CC BY 3.0, the
one the official departure melodies are played on, decision 853): one note
every major third over C5–C7, each struck at the official melodies'
velocity and held, dry (the synth adds the room), mono, at the synth's
32 kHz, all with one gain so their levels stay the piano's own. The synth
plays each melody note on the nearest of them, at most two semitones off,
but B♭6 to C7 on A6, the highest key the chamber bank's piano has
(`sampled/chamber.json`: keys 55–93).
"""

import os
import struct
import subprocess
import tempfile
import wave

import numpy as np

import sampled_music

# The synth's (`PlayerMelodySynth.roots`, `rate`).
ROOTS = [74, 78, 82, 86, 90, 93]
RATE = 32_000
# How long each note is held and kept: the longest a melody's last note
# rings, less what the synth's room adds.
HELD = 3.4
KEEP = 3.6
VELOCITY = 92
# The loudest note's peak.
PEAK = 0.9


def file_name(root):
    return f"melody-piano-{root}.wav"


def _midi(root):
    tpb = sampled_music.TPB
    meta = [(0, 0, b"\xff\x51\x03" + int(60_000_000 / 150).to_bytes(3, "big"))]
    held = round(HELD * 150 / 60 * tpb)
    events = [
        (0, 0, bytes([0xB0, 7, 96])),
        (0, 0, bytes([0xB0, 10, 64])),
        (0, 0, bytes([0xB0, 91, 0])),
        (0, 0, bytes([0xB0, 93, 0])),
        (0, 0, bytes([0xC0, 0])),
        (0, 1, bytes([0x90, root, VELOCITY])),
        (held, 0, bytes([0x80, root, 0])),
    ]
    tracks = [sampled_music._track(meta), sampled_music._track(events)]
    return b"MThd" + struct.pack(">IHHH", 6, 1, len(tracks), tpb) + b"".join(tracks)


def _render(root):
    """Note `root` on the piano, mono at 48 kHz."""
    with tempfile.TemporaryDirectory() as tmp:
        mid, raw = os.path.join(tmp, "note.mid"), os.path.join(tmp, "note.f32")
        with open(mid, "wb") as out:
            out.write(_midi(root))
        if not os.path.isdir(os.path.join(sampled_music.SAMPLED, "node_modules")):
            subprocess.run(["npm", "ci", "--silent", "--no-audit", "--no-fund"], cwd=sampled_music.SAMPLED, check=True)
        subprocess.run(
            ["node", os.path.join(sampled_music.SAMPLED, "render.mjs"), mid, raw, str(KEEP), *sampled_music.bank_paths()],
            cwd=sampled_music.SAMPLED,
            check=True,
        )
        stereo = np.fromfile(raw, dtype="<f4").reshape(-1, 2).astype(np.float64)
    return stereo.mean(axis=1)


def _to_rate(x):
    """48 kHz to `RATE` through the spectrum, the highs above 14 kHz eased
    off so nothing folds back."""
    n = round(len(x) * RATE / sampled_music.SR)
    spectrum = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / sampled_music.SR)
    spectrum *= 1 / np.sqrt(1 + (f / 14_000) ** 8) / np.sqrt(1 + (60 / np.maximum(f, 1)) ** 4)
    kept = spectrum[: n // 2 + 1]
    return np.fft.irfft(kept, n) * n / len(x)


def notes():
    """The notes, by root, mono at `RATE`, levelled together."""
    made = {root: _to_rate(_render(root)) for root in ROOTS}
    fade = int(0.25 * RATE)
    for x in made.values():
        x[-fade:] *= np.linspace(1, 0, fade)
    gain = PEAK / max(np.abs(x).max() for x in made.values())
    return {root: x * gain for root, x in made.items()}


def write(path, x):
    pcm = (x * 32767).round().clip(-32768, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())
