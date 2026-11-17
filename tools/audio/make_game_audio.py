#!/usr/bin/env python3
"""Synthesize the game's music and sound effects (RailwayGameApp/Resources/Audio/).

The same synth as the first promo video's soundtrack, so the game sounds as
the video does: the theme, a melody over the video's pad, plucked arpeggio
and rail joints on I - vi - IV - V in C (decision 815's supplement), a
station chime, a whoosh, a rail joint, and the sounds of something
put up and of money coming in (decision 117), and of something refused
and a warning (decision 184), a ticket issued (decision 373), the
followed train's horn (decision 403) and the evening garbage truck's tune
(decision 437, Für Elise, public domain). Everything is made here from
sine waves and seeded noise: no samples or third-party audio. The output is
the same on every run.

Decision 219: the station chimes are played from scores of railway game ios
(`scores/*.score.json`, checked by `score.py`): the local chime (the
station chime above), the metro interchange chime and the tourist chime,
each also as its motif, the first notes alone, for high speed. Decision
256: the goal-met tune is played from its score too (`scores/goal-met`,
kept to the chime rules), as a whole only, and so is decision 315's
line-acquired tune (`scores/line-acquired`). Decision 815:
the winter tune (`music-winter.caf`, Jingle Bells, public domain) is mixed
from three stems written in MML (`mml/winter-*.mml`), as loud as the theme
by ITU-R BS.1770 loudness. Every file
is listed in `manifest.json` with its source, SHA-256, peak, RMS and its
loop seam or end, and the music its loudness.

    python3 tools/audio/make_game_audio.py RailwayGameApp/Resources/Audio
    python3 tools/audio/make_game_audio.py --check RailwayGameApp/Resources/Audio

`--check` makes everything again in a temporary folder and fails unless
every file and the manifest are byte for byte the committed ones (and the
scores match their MML, when Node is on the PATH).

Needs numpy, and ffmpeg on the PATH for the music's IMA4 CAF.
"""

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import wave

import numpy as np

import score as scores

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
MANIFEST = os.path.join(HERE, "manifest.json")
MML_CORE = os.path.join(HERE, "mml-core", "core.js")
# The mml-tools commit `mml-core/core.js` was copied from (mml-core/README.md).
MML_CORE_COMMIT = "0a974f68c05112f2d871c5de837ae15d29fc9af2"

SR = 48_000


def note_hz(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def pluck(m, length=0.9):
    return pluck_frames(m, int(SR * length))


def pluck_frames(m, frames):
    k = np.arange(frames) / SR
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
    return bell_frames(m, int(SR * length))


def bell_frames(m, frames):
    k = np.arange(frames) / SR
    f = note_hz(m)
    return np.exp(-k * 2.2) * (np.sin(2 * np.pi * f * k) + 0.4 * np.sin(2 * np.pi * f * 2.76 * k) * np.exp(-k * 3))


def glock_frames(m, frames):
    """Decision 815: a glockenspiel, the bell's brighter, shorter cousin:
    the bar's first three modes (1, 2.756 and 5.404 times the note), the
    upper ones dying fast, struck in a millisecond."""
    k = np.arange(frames) / SR
    f = note_hz(m)
    return np.minimum(1, k * 1000) * (
        np.exp(-k * 2.6) * np.sin(2 * np.pi * f * k)
        + 0.25 * np.exp(-k * 9) * np.sin(2 * np.pi * f * 2.756 * k)
        + 0.08 * np.exp(-k * 20) * np.sin(2 * np.pi * f * 5.404 * k)
    )


def sleigh_frames(m, frames):
    """Decision 815: a shake of sleigh bells: four little jingles within
    35 ms, each a handful of inharmonic partials between 2.5 and 7 kHz
    (where a phone's speaker still plays them) that die in a few
    hundredths of a second, over a breath of high-passed noise. The note's pitch only picks the shake (its seed),
    so a pattern of pitches does not repeat one shake mechanically."""
    rng = np.random.default_rng(1_000 + m)
    k = np.arange(frames) / SR
    out = np.zeros(frames)
    offsets = np.concatenate([[0.0], np.sort(rng.uniform(0.004, 0.035, 3))])
    for j, at in enumerate(offsets):
        i = int(at * SR)
        t = k[: frames - i]
        jingle = np.zeros(len(t))
        for _ in range(5):
            f = rng.uniform(2_500, 7_000)
            jingle += rng.uniform(0.3, 1.0) * np.exp(-t * rng.uniform(25, 45)) * np.sin(2 * np.pi * f * t + rng.uniform(0, 2 * np.pi))
        out[i:] += (1.0 if j == 0 else rng.uniform(0.5, 0.9)) * np.minimum(1, t * 2000) * jingle
    noise = np.diff(rng.standard_normal(frames + 1))
    out += 0.3 * noise * np.exp(-k * 60)
    return out / 5


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


def ticket():
    """Decision 373: a ticket issued, as a ticket machine prints one: the
    printer's feed, a buzz of filtered noise pulsing at its stepper's 180
    steps a second over the stepper's own faint 360 Hz, for a third of a
    second; the cutter's snap; the ticket dropping into the tray."""
    out = np.zeros(int(0.7 * SR))
    feed = int(0.32 * SR)
    k = np.arange(feed) / SR
    noise = np.random.default_rng(373).standard_normal(feed)
    # The difference of two one-pole low-passes: a band around 1.5-4 kHz.
    lows = []
    for cut in (0.45, 0.12):
        y = 0.0
        low = np.zeros(feed)
        for j in range(feed):
            y += cut * (noise[j] - y)
            low[j] = y
        lows.append(low)
    band = lows[0] - lows[1]
    steps = 0.55 + 0.45 * np.sin(2 * np.pi * 180 * k) ** 2
    hum = 0.25 * np.sin(2 * np.pi * 360 * k)
    # In and out over 20 ms, so the feed starts and stops without a click.
    edge = np.minimum(1, np.minimum(k, k[-1] - k) / 0.02)
    out[:feed] += 0.8 * edge * (band / np.abs(band).max() * steps + hum)
    snap = clack()
    snap = np.diff(snap, prepend=0.0)  # brighter: a blade, not a joint
    start = int(0.35 * SR)
    out[start : start + len(snap)] += 0.6 * snap / np.abs(snap).max()
    drop = clack()
    start = int(0.47 * SR)
    out[start : start + len(drop)] += 0.5 * drop
    return out


# Decision 403 (續二): the followed train's horn, by the kind of train. The
# owner's OpenWorld reference sounds a car's horn as two square waves a
# major third apart (365 and 455 Hz) in one short envelope: in over 25 ms,
# held to 0.18 s, out by 0.32 s (`engine/audio.js` `horn()`). The trains'
# horns keep its shape, two or three tones sounded together, with each
# kind's own tones, timbre and length; the tones are notes of the music's
# C major (the music plays under them), near the pitch of each kind's real
# horn (no recording is measured: estimated, as README.md says).
HORNS = {
    # A Taiwan Railway EMU's or electric locomotive's air horn: two
    # tones a major third apart, G4 and B4, brassy, a second long.
    "electric": {"notes": [67, 71], "shape": "saw", "attack": 0.04, "hold": 0.8, "release": 0.18, "bright": 2600},
    # A diesel locomotive's three-chime air horn, lower, longer and fuller:
    # A3, C4 and E4, an A minor chord, as the chimes of a locomotive horn
    # are tuned to a chord.
    "diesel": {"notes": [57, 60, 64], "shape": "saw", "attack": 0.07, "hold": 1.2, "release": 0.25, "bright": 1800},
    # A steam whistle: breath first, a D5 over its octave, slow to speak.
    "steam": {"notes": [74, 86], "shape": "whistle", "attack": 0.16, "hold": 1.3, "release": 0.35, "bright": 4000},
    # The high-speed train's electronic horn: E5 and G5, smooth and short.
    "highSpeed": {"notes": [76, 79], "shape": "square", "attack": 0.015, "hold": 0.55, "release": 0.12, "bright": 3000},
    # A metro train's electronic horn: OpenWorld's envelope as it is, on
    # A5 and C#6 (its own third, an octave and a fifth above its car's).
    "metro": {"notes": [81, 85], "shape": "square", "attack": 0.025, "hold": 0.155, "release": 0.14, "bright": 5000},
}


# Each horn's RMS: -12 dBFS, about the station chimes' loudness.
HORN_RMS = 10 ** (-12 / 20)


def horn(kind):
    """Decision 403 (續二): one blow of `kind`'s horn (``HORNS``): its tones
    sounded together, each a band-limited saw (an air horn's), square (an
    electronic horn's, OpenWorld's) or a whistle's sine with breath,
    softened above the kind's `bright` cut, in OpenWorld's envelope (in
    over `attack`, held, out over `release`, both curved as its
    exponential ramps). An air horn's pitch rises the last 3% as the air
    comes in, as real ones do."""
    h = HORNS[kind]
    length = h["attack"] + h["hold"] + h["release"]
    n = int(round((length + 0.05) * SR))
    t = np.arange(n) / SR
    out = np.zeros(n)
    for i, m in enumerate(h["notes"]):
        f = note_hz(m)
        bend = np.ones(n)
        if h["shape"] == "saw":
            bend = 1 - 0.03 * np.exp(-t / max(h["attack"], 0.01))
        phase = 2 * np.pi * np.cumsum(f * bend) / SR
        tone = np.zeros(n)
        harmonic = 1
        while harmonic * f < min(h["bright"] * 3, SR / 2 - 1000):
            # A gentle low-pass: each harmonic above the cut down by its
            # share past it.
            soft = 1 / (1 + (harmonic * f / h["bright"]) ** 2)
            if h["shape"] == "saw":
                tone += soft * np.sin(harmonic * phase) / harmonic
            elif h["shape"] == "square" and harmonic % 2:
                tone += soft * np.sin(harmonic * phase) / harmonic
            elif h["shape"] == "whistle" and harmonic == 1:
                tone += np.sin(phase)
            harmonic += 1
        out += tone * (1.0 - 0.15 * i)
    if h["shape"] == "whistle":
        # The steam's breath: noise in a band round the whistle's tone
        # (the difference of two one-pole low-passes, about 300 Hz to
        # 2 kHz, as the ticket's feed), louder as it speaks than once it
        # sings.
        noise = np.random.default_rng(403).standard_normal(n)
        lows = []
        for cut in (0.25, 0.04):
            y = 0.0
            low = np.zeros(n)
            for j in range(n):
                y += cut * (noise[j] - y)
                low[j] = y
            lows.append(low)
        breath = lows[0] - lows[1]
        breath = breath / np.abs(breath).max()
        out = out / np.abs(out).max() + breath * (0.15 + 0.45 * np.exp(-t / 0.2))
    a, hold, r = h["attack"], h["hold"], h["release"]
    rise = np.clip(t / a, 0, 1)
    fall = np.clip((t - a - hold) / r, 0, 1)
    env = (1 - (1 - rise) ** 3) * (1 - fall) ** 3
    return out * env


# Decision 343: the running loops, made to the spectra of recordings of
# trains running (`measure_running_spectrum.py`; the recordings, their
# licences and the stretches measured are in README.md). Median
# third-octave band levels from 31.5 Hz to 12.5 kHz, in dB below the
# loudest band.
RUNNING_BANDS = [1000 * 2 ** (n / 3) for n in range(-15, 12)]
RUNNING_SPECTRA = {
    # A KTX between two cars at speed (Wu's two are commuter trains).
    "highSpeed": [-0, 0, -3, -2, -1, -4, -13, -11, -10, -8, -10, -14, -16, -19,
                  -22, -21, -20, -26, -29, -32, -36, -39, -36, -42, -46, -49, -53],
    # Two trains in Taiwan, near Guishan and near Banqiao, the mean of each.
    "electric": [-3, -4, -4, -0, -4, -5, -1, 0, -5, -7, -10, -9, -15, -14,
                 -16, -19, -22, -19, -19, -19, -21, -23, -27, -29, -31, -27, -33],
}
# 8 s at 48 kHz: whole IMA4 packets (64 frames), so the CAF loops without
# a gap.
RUNNING_FRAMES = 8 * SR


def shaped(levels, n, seed):
    """`n` frames of seeded noise shaped to third-octave band `levels` (dB,
    from 31.5 Hz to 12.5 kHz) in one circular FFT, so its end runs into its
    start; RMS 1."""
    spectrum = np.fft.rfft(np.random.default_rng(seed).standard_normal(n))
    freqs = np.fft.rfftfreq(n, 1 / SR)
    # The levels are per band, a third of an octave wide: per bin, less by
    # the band's width.
    bands = np.array(RUNNING_BANDS)
    density = np.array(levels) - 10 * np.log10(bands)
    level = np.interp(np.log(np.maximum(freqs, 1)), np.log(bands), density)
    gain = 10 ** (level / 20)
    gain[(freqs < bands[0] * 2 ** (-1 / 6)) | (freqs > bands[-1] * 2 ** (1 / 6))] = 0
    x = np.fft.irfft(spectrum * gain, n)
    return x / np.sqrt(np.mean(x**2))


def from_zero(x):
    """`x` turned to start where it crosses zero, as an IMA4 packet decodes
    from silence: a loop that started away from it would click at every
    turn."""
    turn = int(np.argmin(np.abs(x[: SR // 4]) + np.abs(np.diff(x[: SR // 4 + 1]))))
    return np.roll(x, -turn)


def running(kind):
    """An 8-second loop of a train running: seeded noise shaped to the
    measured spectrum (`shaped`) under a slow swell of about a decibel;
    the electric one with a rail joint every 1.6 s (25 m rails at 60 km/h,
    the speed it plays at its own rate), struck by both axles of the near
    bogie and then, softer, of the far one."""
    n = RUNNING_FRAMES
    x = shaped(RUNNING_SPECTRA[kind], n, 343 + len(kind))
    k = np.arange(n) / n
    swell = 1 + 0.06 * np.sin(2 * np.pi * k) + 0.04 * np.sin(2 * np.pi * 3 * k + 1) + 0.03 * np.sin(2 * np.pi * 5 * k + 2)
    x = x * swell
    if kind == "electric":
        joint = clack()
        joint = joint / np.abs(joint).max() * 2.5
        for start in np.arange(0.4, 8, 1.6):
            for at, strength in [(0, 1.0), (0.126, 0.8), (0.84, 0.5), (0.966, 0.4)]:
                first = int(round((start + at) * SR))
                where = (first + np.arange(len(joint))) % n
                x[where] += strength * joint
    return from_zero(x)


# Decision 567: the diesel running loops, made to the Gepponkoku's
# (Simulation Country GAPAN 月本國, https://gepponkoku.nation.jp) recording
# of a KiHa 41 2000 on the Bantan Line (`measure_diesel_engine.py`; the
# files, the stretches measured and the site's terms are in README.md and
# decision 567). Each: the engine's fundamental in Hz, the level of its
# first 12 harmonics and the third-octave bands of the noise under them
# (31.5 Hz to 12.5 kHz), in dB below the noise's loudest band.
DIESEL_ENGINES = {
    # Standing, the engine idling (`dc40r_stn`, 0–2 s).
    "dieselIdle": {
        "f0": 33.75,
        "harmonics": [-5, 2, -10, -9, -7, 1, -17, -2, -2, -15, -6, -11],
        "floor": [-17, -18, -19, -13, -12, -14, -11, -8, -3, 0, -3, -7, -8, -9,
                  -12, -10, -10, -13, -12, -14, -17, -20, -22, -19, -20, -19, -20],
    },
    # Pulling away, the engine notched up (`dc40r_go-a`, 26–38 s).
    "diesel": {
        "f0": 38.25,
        "harmonics": [-23, 7, 4, -2, -7, -7, 7, -7, -8, -14, -22, -13],
        "floor": [-19, -18, -17, -11, -7, -8, -6, -7, -2, 0, -1, -4, -2, -5,
                  -9, -12, -11, -12, -12, -15, -17, -20, -20, -14, -11, -13, -19],
    },
    # Coasting to a stop, the engine back at idle under the wheels
    # (`dc40r_i-stop`, 0–32 s).
    "dieselCoast": {
        "f0": 33.75,
        "harmonics": [-9, -2, -10, -18, -19, 1, -19, -8, -10, -13, -12, -20],
        "floor": [-19, -18, -16, -10, -9, -5, -4, -4, -1, 0, -2, -4, -4, -5,
                  -10, -12, -13, -15, -15, -17, -20, -22, -24, -22, -22, -23, -26],
    },
}
# The idle loop is 4 s (no wheels, nothing slow to repeat); the others 8 s,
# as the running loops. Every harmonic of each fundamental runs a whole
# number of cycles in its loop (33.75 Hz × 4 s = 135, 38.25 Hz × 8 s = 306).
DIESEL_FRAMES = {"dieselIdle": 4 * SR, "diesel": 8 * SR, "dieselCoast": 8 * SR}


def diesel(kind):
    """A loop of a diesel railcar: seeded noise shaped to the measured floor
    (`shaped`) and, over it, the engine's 12 harmonics at their measured
    levels, the fundamental wavering by about half a percent twice in each
    4 seconds as a real engine's does; moving (not idling), the electric
    loop's swell and rail joints (`running`)."""
    engine = DIESEL_ENGINES[kind]
    n = DIESEL_FRAMES[kind]
    x = shaped(engine["floor"], n, 567 + len(kind))
    # The noise is RMS 1: the bands' power together is 1, so a level of 0 dB
    # is that over the bands' sum.
    reference = 1 / np.sum(10 ** (np.array(engine["floor"]) / 10))
    t = np.arange(n) / SR
    waver = 0.4 * np.sin(2 * np.pi * 0.5 * t)
    phases = np.random.default_rng(567).uniform(0, 2 * np.pi, len(engine["harmonics"]))
    for k, (level, phase) in enumerate(zip(engine["harmonics"], phases), start=1):
        amplitude = np.sqrt(2 * reference * 10 ** (level / 10))
        x += amplitude * np.sin(2 * np.pi * k * engine["f0"] * t + k * waver + phase)
    if kind != "dieselIdle":
        k = np.arange(n) / n
        x *= 1 + 0.06 * np.sin(2 * np.pi * k) + 0.04 * np.sin(2 * np.pi * 3 * k + 1) + 0.03 * np.sin(2 * np.pi * 5 * k + 2)
        joint = clack()
        joint = joint / np.abs(joint).max() * 2.5 * np.sqrt(np.mean(x**2))
        for start in np.arange(0.4, 8, 1.6):
            for at, strength in [(0, 1.0), (0.126, 0.8), (0.84, 0.5), (0.966, 0.4)]:
                first = int(round((start + at) * SR))
                where = (first + np.arange(len(joint))) % n
                x[where] += strength * joint
    return from_zero(x)


# Decision 664: the motor loops of an electric train, made to the
# Gepponkoku's (Simulation Country GAPAN 月本國, https://gepponkoku.nation.jp)
# recordings of a JR Central 313 series (3000 番台, IGBT VVVF) on the Gotemba
# Line (`measure_motor_sound.py`; the files, the stretches measured, how
# their speed was read and the site's terms are in README.md and decision
# 664). For each speed (km/h) a loop is made at, pulling away (`power`, from
# `313-3k_go-top`) and braking (`brake`, from `313-3k_top-stop`): the
# motors' tones, each [Hz, dB], and their level together, both in dB under
# the recording's whole sound there; `steady` where the tones hold still
# as the speed changes (the inverter's carrier at low speed), so the app
# plays that loop at its own rate rather than faster or slower with the
# speed. Where no tone was heard (pulling away at 45 km/h) there is no
# loop: the app plays the nearest one faster or slower.
MOTOR_TONES = {
    "power": {
        4: {"level": -5.2, "steady": True, "tones": [[60.0, -23], [64.0, -22], [134.0, -22], [160.0, -18], [166.0, -21], [220.0, -11], [224.0, -11], [256.0, -11], [360.0, -24], [408.0, -23], [796.0, -26], [938.0, -24]]},
        6: {"level": -4.0, "steady": True, "tones": [[142.0, -14], [148.0, -5], [186.0, -13], [218.0, -20]]},
        9: {"level": -9.0, "steady": True, "tones": [[64.0, -22], [114.0, -20], [154.0, -17], [222.0, -20], [252.0, -22], [406.0, -19], [430.0, -25], [506.0, -17], [612.0, -15], [972.0, -25], [1194.0, -24], [1752.0, -26]]},
        14: {"level": -7.1, "steady": True, "tones": [[362.0, -21], [638.0, -23], [690.0, -24], [754.0, -19], [758.0, -20], [818.0, -12], [848.0, -18], [860.0, -15], [866.0, -15], [880.0, -23], [912.0, -18], [1012.0, -23]]},
        20: {"level": -8.2, "tones": [[94.0, -25], [158.0, -11], [218.0, -20], [754.0, -25], [800.0, -15], [882.0, -20], [932.0, -18]]},
        30: {"level": -11.3, "tones": [[242.0, -11]]},
        68: {"level": -12.2, "tones": [[92.0, -13], [690.0, -19]]},
    },
    "brake": {
        4: {"level": -7.7, "steady": True, "tones": [[60.0, -18], [118.0, -16], [126.0, -15], [194.0, -19], [214.0, -20], [276.0, -20], [318.0, -18], [426.0, -24], [1470.0, -23], [1476.0, -23], [1540.0, -17], [1562.0, -18]]},
        6: {"level": -6.6, "steady": True, "tones": [[92.0, -20], [120.0, -18], [148.0, -12], [188.0, -14], [316.0, -20], [692.0, -17], [728.0, -13], [1486.0, -27], [1550.0, -23]]},
        9: {"level": -6.0, "tones": [[76.0, -19], [102.0, -22], [260.0, -8], [310.0, -13], [966.0, -15]]},
        14: {"level": -5.6, "tones": [[160.0, -8], [178.0, -15], [250.0, -13], [794.0, -18]]},
        20: {"level": -6.2, "tones": [[100.0, -18], [190.0, -8], [260.0, -20], [380.0, -13]]},
        30: {"level": -5.4, "tones": [[428.0, -22], [642.0, -20], [692.0, -11], [830.0, -7]]},
        45: {"level": -15.5, "tones": [[62.0, -15]]},
        68: {"level": -9.7, "tones": [[94.0, -11], [372.0, -15], [556.0, -23]]},
    },
}
# 2 s at 48 kHz: whole IMA4 packets; every tone (to 0.5 Hz) runs a whole
# number of cycles in it, so the loop has no seam.
MOTOR_FRAMES = 2 * SR
# How much louder the motors are made than measured, in dB: the recordings
# are from inside a two-car train with one motor car, and a phone's speaker
# would lose them under the wheels.
MOTOR_LIFT = 6


def motor_files():
    """Each motor loop's file name, mode and speed."""
    return [(f"run-motor-{mode}-{kmh:02d}.caf", mode, kmh) for mode in MOTOR_TONES for kmh in MOTOR_TONES[mode]]


def motor(mode, kmh):
    """A 2-second loop of an electric train's motors at `kmh`: the measured
    tones, each a sine at its level, under a slow swell of about half a
    decibel; its RMS the electric running loop's (decision 343, as the app
    plays it) times the tones' level and `MOTOR_LIFT`, so the app plays both
    at the same volume and the motors sit under the wheels, a little above
    where they are in the recording."""
    entry = MOTOR_TONES[mode][kmh]
    n = MOTOR_FRAMES
    t = np.arange(n) / SR
    phases = np.random.default_rng(664 + kmh).uniform(0, 2 * np.pi, len(entry["tones"]))
    x = np.zeros(n)
    for (hz, level), phase in zip(entry["tones"], phases):
        assert (hz * n / SR).is_integer(), "every tone runs whole cycles in the loop"
        x += np.sqrt(2 * 10 ** (level / 10)) * np.sin(2 * np.pi * hz * t + phase)
    x *= 1 + 0.03 * np.sin(2 * np.pi * t / (n / SR))
    wheels = normalized(running("electric"), 0.5)
    rms = np.sqrt(np.mean(wheels**2)) * 10 ** ((entry["level"] + MOTOR_LIFT) / 20)
    x = x / np.sqrt(np.mean(x**2)) * rms
    assert np.abs(x).max() < 0.95, "the motor loop clips"
    return from_zero(x)


# Decision 346: the weather's rain and the thunder of its storms, made to
# recordings of rain and thunder in Taipei and Tamsui
# (`measure_running_spectrum.py` and `measure_thunder.py`; the recordings,
# their licences and what was measured are in README.md). Band levels as
# RUNNING_SPECTRA's.
WEATHER_SPECTRA = {
    # Rain in Taipei (a park, the railway workshop) and Tamsui, the mean of
    # each.
    "rain": [-14, -11, -11, -4, -3, -6, -3, -3, -3, -2, -3, -2, -2, -1,
             -0, 0, -1, -1, -2, -3, -4, -6, -8, -10, -11, -10, -12],
    # A typhoon's wind and rain in Tamsui.
    "typhoon": [-20, -20, -18, -13, -12, -7, -7, -13, -5, -5, -5, -2, -4, -3,
                -5, -4, -3, -2, 0, -1, -3, -7, -12, -16, -17, -17, -20],
}
# How the loudness of each half second wanders (its standard deviation in
# dB, measured from the same recordings), and how slowly: the typhoon's
# gusts last about a second (their loudness half forgotten after one),
# the rain drifts.
WEATHER_SWING = {"rain": (1.8, 0.25), "typhoon": (3.0, 0.4)}
# Whole IMA4 packets: the rain 8 s, the typhoon 12 s, so its gusts repeat
# less often.
WEATHER_FRAMES = {"rain": 8 * SR, "typhoon": 12 * SR}
THUNDER = {
    # The clap's first second, above the rain, and its rumble 2-10 s after.
    "first": [-17, -13, -11, -4, -3, -2, 0, -3, -2, -3, -6, -9, -14, -18,
              -22, -24, -33, -28, -34, -28, -29, -34, -40, -52, -57, -57, -59],
    "rumble": [-17, -12, -15, -9, -6, -5, 0, -4, -5, -5, -8, -12, -17, -19,
               -21, -24, -24, -25, -28, -29, -31, -33, -34, -38, -45, -43, -46],
    # How fast the rumble dies away, in dB a second.
    "diesAway": -1.2,
}
THUNDER_FRAMES = 10 * SR


def weather(kind):
    """A loop of rain (or of a typhoon's wind and rain): seeded noise shaped
    to the measured spectrum, its loudness wandering as the recordings'
    does, in a circular envelope so the loop still runs into its start."""
    n = WEATHER_FRAMES[kind]
    x = shaped(WEATHER_SPECTRA[kind], n, 346 + len(kind))
    swing, below = WEATHER_SWING[kind]
    wander = np.fft.rfft(np.random.default_rng(3460 + len(kind)).standard_normal(n))
    freqs = np.fft.rfftfreq(n, 1 / SR)
    wander[(freqs == 0) | (freqs > below)] = 0
    db = np.fft.irfft(wander, n)
    db = db / db.std() * swing
    return from_zero(x * 10 ** (db / 20))


def thunder():
    """A clap of thunder, 10 s: a crack with the spectrum of the measured
    claps' first second, gone in about a second, and under it the rumble's
    spectrum rolling every 1.5 to 2 s (as the Tamsui clap's quarter
    seconds do) and dying away at the measured rate, faded out over its
    last 1.5 s."""
    n = THUNDER_FRAMES
    t = np.arange(n) / SR
    crack = shaped(THUNDER["first"], n, 3461) * np.minimum(t / 0.01, 1) * np.exp(-t / 0.35)
    rng = np.random.default_rng(3462)
    rolls = np.zeros(n)
    at = 0.6
    while at < 10:
        rolls += np.exp(-0.5 * ((t - at) / 0.35) ** 2)
        at += 1.5 + 0.5 * rng.random()
    swell = np.minimum(t / 0.2, 1) * (0.35 + rolls) * 10 ** (THUNDER["diesAway"] * t / 20)
    rumble = shaped(THUNDER["rumble"], n, 3463) * swell
    x = crack + 0.8 * rumble
    fade = np.clip((10 - t) / 1.5, 0, 1)
    return x * (0.5 - 0.5 * np.cos(np.pi * fade))


# Decision 437: the evening garbage truck's tune, the opening of
# Beethoven's 〈給愛麗絲〉 (Für Elise, WoO 59, public domain) as Taiwan's
# trucks play it, note for note as the owner's Taiwan 3D city
# (`tw3d-reference-clean/source/js/garbage-truck.js`) has it: MIDI notes
# and lengths in eighths, `None` a rest. Its eighth is the reference's
# 0.19 s, 9,120 frames, so the 50 eighths are 456,000 frames: whole IMA4
# packets, and the loop plays on without a gap.
GARBAGE_EIGHTH = int(0.19 * SR)
GARBAGE_PHRASE = [
    (76, 1), (75, 1), (76, 1), (75, 1), (76, 1), (71, 1), (74, 1), (72, 1), (69, 2), (None, 1),
    (60, 1), (64, 1), (69, 1), (71, 2), (None, 1),
    (64, 1), (68, 1), (71, 1), (72, 2), (None, 1),
    (64, 1), (76, 1), (75, 1), (76, 1), (75, 1), (76, 1), (71, 1), (74, 1), (72, 1), (69, 2), (None, 1),
    (60, 1), (64, 1), (69, 1), (71, 2), (None, 1),
    (64, 1), (72, 1), (71, 1), (69, 3), (None, 3),
]
# The loudspeaker on the truck's roof: nothing below 400 Hz or much above
# 3.2 kHz (the reference's low-pass), a little louder round 1.6 kHz.
GARBAGE_BAND = (400, 3_200)


def garbage_truck():
    """Decision 437: one turn of the garbage truck's tune as its roof
    loudspeaker plays it. Each note a band-limited square wave (a chip's
    voice) struck at 12 ms, falling to half by its end and let go over
    25 ms; the whole driven a little into soft clipping (an amplifier
    pushed hard) and filtered round the circle to the loudspeaker's band,
    so its end runs into its start."""
    n = GARBAGE_EIGHTH * sum(length for _, length in GARBAGE_PHRASE)
    assert n % 64 == 0
    out = np.zeros(n)
    at = 0
    for m, length in GARBAGE_PHRASE:
        frames = GARBAGE_EIGHTH * length
        if m is not None:
            t = np.arange(frames) / SR
            f = note_hz(m)
            phase = 2 * np.pi * f * t
            tone = np.zeros(frames)
            harmonic = 1
            while harmonic * f < 6_000:
                tone += np.sin(harmonic * phase) / harmonic
                harmonic += 2
            attack = np.clip(t / 0.012, 0, 1)
            decay = 0.5 + 0.5 * np.exp(-t / (frames / SR * 0.6))
            release = np.clip((frames / SR - t) / 0.025, 0, 1)
            out[at : at + frames] += tone * attack * decay * release
        at += frames
    out = np.tanh(2.2 * out / np.abs(out).max()) / np.tanh(2.2)
    spectrum = np.fft.rfft(out)
    freqs = np.fft.rfftfreq(n, 1 / SR)
    low, high = GARBAGE_BAND
    gain = (freqs / low) ** 4 / (1 + (freqs / low) ** 4) / (1 + (freqs / high) ** 4)
    gain *= 1 + 0.6 * np.exp(-((np.log2(np.maximum(freqs, 1) / 1_600)) ** 2) / 0.5)
    return np.fft.irfft(spectrum * gain, n)


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


def write_caf(path, loop):
    """A loop as an IMA4 CAF, which loops without a gap when it is whole
    packets."""
    assert len(loop) % 64 == 0, "the loop must be whole IMA4 packets"
    with tempfile.TemporaryDirectory() as tmp:
        source = os.path.join(tmp, "loop.wav")
        write_wav(source, loop)
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", source, "-c:a", "adpcm_ima_qt",
             "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact", path],
            check=True,
        )


# Decision 219: how long a struck voice rings when its note is shorter (a
# bell or a pluck sounds on past its written length, as the chimes and the
# music above always played them), cut at the score's end.
RING_FRAMES = {"bell": int(SR * 2.2), "pluck": int(SR * 0.9), "glock": int(SR * 1.6), "sleigh": int(SR * 0.4)}
# The official chimes' peak (§3 of the research note: the station chime's).
CHIME_PEAK = 0.6


def frames_per_tick(score):
    """Whole frames a tick: the synth needs 48,000 × 60 a multiple of
    tempo × 960 (100 bpm: 30 frames)."""
    numerator = SR * 60
    denominator = score["tempo"] * scores.TICKS_PER_BEAT
    if numerator % denominator:
        raise scores.ScoreError(f"{score['title']}: tempo {score['tempo']} is not a whole number of frames a tick")
    return numerator // denominator


def voice(name, pitch, frames):
    if name == "bell":
        return bell_frames(pitch, max(frames, RING_FRAMES["bell"]))
    if name == "pluck":
        return pluck_frames(pitch, max(frames, RING_FRAMES["pluck"]))
    if name == "pad":
        return pad([pitch], frames / SR)
    if name == "glock":
        return glock_frames(pitch, max(frames, RING_FRAMES["glock"]))
    if name == "sleigh":
        return sleigh_frames(pitch, max(frames, RING_FRAMES["sleigh"]))
    return clack()


def fade_tail(x, frames):
    """A linear fade over the last `frames`, as the reference's chime ends
    (`chimeBuffer`'s `tail`)."""
    if frames <= 0:
        return x
    n = len(x)
    tail = np.minimum(1, (n - 1 - np.arange(n)) / frames)
    return x * (tail if x.ndim == 1 else tail[:, None])


def render(score, only=None, frames=None):
    """The score's sound, unnormalized: mono unless a track is panned.

    Velocities are relative to the loudest note (the file is normalized to
    its peak), times the track's gain. `only` keeps those notes (the
    motif); `frames` cuts the sound there instead of at the score's end.
    """
    step = frames_per_tick(score)
    n = frames if frames is not None else score["length"] * step
    loudest = max(note["velocity"] for t in score["tracks"] for note in t["notes"])
    stereo = any(t["pan"] for t in score["tracks"])
    out = np.zeros((n, 2) if stereo else n)
    for track in score["tracks"]:
        for note in track["notes"]:
            if only is not None and not any(note is m for m in only):
                continue
            start = note["start"] * step
            if start >= n:
                continue
            amp = (note["velocity"] / loudest) * (track["gain"] / 100)
            sig = amp * voice(track["voice"], note["pitch"], note["length"] * step)[: n - start]
            if stereo:
                pan = track["pan"] / 100
                out[start : start + len(sig), 0] += sig * (1 - pan) / 2**0.5
                out[start : start + len(sig), 1] += sig * (1 + pan) / 2**0.5
            else:
                out[start : start + len(sig)] += sig
    return out


def chime(score):
    return normalized(fade_tail(render(score), score["fadeOut"] * frames_per_tick(score)), CHIME_PEAK)


def motif(score):
    """The motif file: the first notes alone, 0.8 s, the last 0.12 s faded
    (§6: 600× and faster play it for the watched train)."""
    sound = render(score, only=scores.motif_notes(score), frames=int(SR * scores.MOTIF_SECONDS))
    return normalized(fade_tail(sound, int(SR * scores.MOTIF_FADE_SECONDS)), CHIME_PEAK)


# Decision 815: a pad note in a stem rings this long past its written
# length, as decision 79's theme always overlapped its pads into the next chord (it
# gives each 0.6 s more), so a chord held over a bar line does not dip.
STEM_PAD_OVERLAP = 0.6
# The longest any voice rings past its note: the bell.
STEM_TAIL = int(SR * 2.2)


def stem_voice(name, pitch, frames):
    if name == "pad":
        return pad([pitch], frames / SR + STEM_PAD_OVERLAP)
    return voice(name, pitch, frames)


def stems_loop(names):
    """Decision 815: the loop the stems `names` make together (research
    note §2.5): every stem the same tempo and length, mixed at the
    velocities written (velocity ÷ 127 × gain ÷ 100, not each stem by its
    own loudest note, so the stems keep their balance), the tails past the
    end folded back onto the start so the loop runs on into itself, then
    the theme's ping-pong echo of a dotted eighth, round the circle."""
    sheets = [scores.load(os.path.join(HERE, "scores", f"{name}.score.json")) for name in names]
    first = sheets[0]
    for sheet in sheets:
        if sheet["role"] != "stem":
            raise SystemExit(f"{sheet['title']} is not a stem")
        if (sheet["tempo"], sheet["length"], sheet["beatsPerBar"]) != (first["tempo"], first["length"], first["beatsPerBar"]):
            raise SystemExit(f"{sheet['title']}: the stems differ in tempo, length or metre")
    step = frames_per_tick(first)
    n = first["length"] * step
    assert n % 64 == 0, "the loop must be whole IMA4 packets"
    mix = np.zeros((n + STEM_TAIL + int(SR * STEM_PAD_OVERLAP), 2))
    for sheet in sheets:
        for track in sheet["tracks"]:
            pan = track["pan"] / 100
            for note in track["notes"]:
                start = note["start"] * step
                amp = note["velocity"] / 127 * track["gain"] / 100
                sig = amp * stem_voice(track["voice"], note["pitch"], note["length"] * step)
                sig = sig[: len(mix) - start]
                mix[start : start + len(sig), 0] += sig * (1 - pan) / 2**0.5
                mix[start : start + len(sig), 1] += sig * (1 + pan) / 2**0.5
    loop = mix[:n].copy()
    loop[: len(mix) - n] += mix[n:]
    d = int(SR * 60 / first["tempo"] * 0.75)
    echo = np.zeros_like(loop)
    echo[:, 0] = np.roll(loop[:, 1], d) * 0.25
    echo[:, 1] = np.roll(loop[:, 0], d) * 0.25
    return loop + echo


# Decision 815: the game's two tunes, each from its stems in mixing order:
# the theme (decision 79's chords with a melody, the 815 supplement) and
# the winter tune, played from 1 December to 6 January (`MusicTune`).
THEME_STEMS = ["theme-melody", "theme-harmony", "theme-rhythm"]
WINTER_STEMS = ["winter-melody", "winter-harmony", "winter-rhythm"]
MUSIC_STEMS = {"music-loop.caf": THEME_STEMS, "music-winter.caf": WINTER_STEMS}


def k_weighted_power(x):
    """ITU-R BS.1770's K-weighting (its two 48 kHz biquads) applied to a
    loop round the circle, through the filters' exact frequency response:
    a loop has no start, so this is the filters' steady state. Returns the
    weighted signal, frames × channels."""
    z = np.exp(-1j * 2 * np.pi * np.fft.rfftfreq(len(x)))
    shelf = (1.53512485958697 - 2.69169618940638 * z + 1.19839281085285 * z**2) / (1 - 1.69065929318241 * z + 0.73248077421585 * z**2)
    high = (1 - 2 * z + z**2) / (1 - 1.99004745483398 * z + 0.99007225036621 * z**2)
    return np.fft.irfft(np.fft.rfft(x, axis=0) * (shelf * high)[:, None], len(x), axis=0)


def loudness_lufs(x):
    """Integrated loudness (LUFS, ITU-R BS.1770-4) of a stereo loop: 400 ms
    blocks every 100 ms, gated at -70 LUFS and then 10 LU under the
    blocks' loudness. The manifest records it for the music; the winter
    tune is levelled to the theme's."""
    y = k_weighted_power(x)
    block, hop = int(0.4 * SR), int(0.1 * SR)
    power = np.array([np.sum(np.mean(y[i : i + block] ** 2, axis=0)) for i in range(0, len(y) - block + 1, hop)])
    loud = -0.691 + 10 * np.log10(np.maximum(power, 1e-20))
    power = power[loud > -70]
    relative = -0.691 + 10 * np.log10(power.mean()) - 10
    power = power[-0.691 + 10 * np.log10(power) > relative]
    return -0.691 + 10 * np.log10(power.mean())


# The music's loudness: the theme's as decision 79 made it (normalized to a
# peak of 0.7, it measured -15.95 LUFS), kept when the theme was rewritten
# (decision 815's supplement) so the player's music volume means what it
# did; both tunes are levelled to it.
MUSIC_LUFS = -15.95


def level_to(x, lufs):
    """`x` scaled to `lufs`; it must not peak above 0.9."""
    y = x * 10 ** ((lufs - loudness_lufs(x)) / 20)
    if np.abs(y).max() > 0.9:
        raise SystemExit(f"levelled to {lufs:.2f} LUFS the loop peaks at {np.abs(y).max():.2f}")
    return y


# Decision 219: the station chimes, by score: (score, chime file, motif file).
CHIMES = [
    ("chime-local", "station-chime.wav", "chime-local-motif.wav"),
    ("chime-metro", "chime-metro.wav", "chime-metro-motif.wav"),
    ("chime-tourist", "chime-tourist.wav", "chime-tourist-motif.wav"),
]

# Decision 256: the tunes, by score: (score, file). Played whole, at the
# chimes' peak; no motif.
TUNES = [
    ("goal-met", "goal-met.wav"),
    # Decision 315: a real line bought.
    ("line-acquired", "line-acquired.wav"),
    # Decision 566: a model new to the fleet came ashore.
    ("new-train", "new-train.wav"),
]


def sha256(path):
    with open(path, "rb") as file:
        return hashlib.sha256(file.read()).hexdigest()


def relative(path):
    return os.path.relpath(path, ROOT).replace(os.sep, "/")


def read_pcm(path):
    """A file's samples as floats (-1...1), frames × channels: WAV read
    directly, anything else decoded by ffmpeg to 16-bit stereo."""
    if path.endswith(".wav"):
        with wave.open(path, "rb") as w:
            channels = w.getnchannels()
            raw = w.readframes(w.getnframes())
    else:
        channels = 2
        raw = subprocess.run(
            ["ffmpeg", "-loglevel", "error", "-i", path, "-f", "s16le", "-ac", "2", "-"],
            check=True, capture_output=True,
        ).stdout
    return np.frombuffer(raw, dtype="<i2").reshape(-1, channels) / 32768


def dbfs(x):
    return round(20 * np.log10(max(x, 1e-9)), 2)


def measured(path, loops):
    """What the manifest says of a file: peak and RMS (dBFS), its largest
    step between two frames, and its loop seam (the jump from the last
    frame to the first, which a click would show as larger than the
    largest step) or, for a one-shot, its end level."""
    x = read_pcm(path)
    entry = {
        "sha256": sha256(path),
        "frames": len(x),
        "seconds": round(len(x) / SR, 4),
        "peakDbfs": dbfs(np.abs(x).max()),
        "rmsDbfs": dbfs(float(np.sqrt(np.mean(x**2)))),
        "largestStep": round(float(np.abs(np.diff(x, axis=0)).max()), 5),
    }
    if loops:
        entry["loopSeam"] = round(float(np.abs(x[0] - x[-1]).max()), 5)
    else:
        entry["endLevel"] = round(float(np.abs(x[-1]).max()), 5)
    return entry


# The files `main` makes that no score describes, and what makes them.
SYNTH_SOURCES = {
    "rail-joint.wav": "clack()",
    "whoosh.wav": "whoosh()",
    "build-done.wav": "clack() and pluck(), decision 117",
    "coins.wav": "bell(), decision 117",
    "refused.wav": "pluck(), decision 184",
    "warning.wav": "bell(), decision 184",
    "run-electric.caf": "running(\"electric\"), decision 343",
    "run-highspeed.caf": "running(\"highSpeed\"), decision 343",
    "run-diesel.caf": "diesel(\"diesel\"), decision 567",
    "run-diesel-idle.caf": "diesel(\"dieselIdle\"), decision 567",
    "run-diesel-coast.caf": "diesel(\"dieselCoast\"), decision 567",
    **{
        file: f"motor(\"{mode}\", {kmh}){', steady' if MOTOR_TONES[mode][kmh].get('steady') else ''}, decision 664"
        for file, mode, kmh in motor_files()
    },
    "rain-steady.caf": "weather(\"rain\"), decision 346",
    "rain-typhoon.caf": "weather(\"typhoon\"), decision 346",
    "thunder.caf": "thunder(), decision 346",
    "ticket-issued.wav": "ticket(), decision 373",
    **{f"horn-{kind}.wav": f"horn(\"{kind}\"), decision 403" for kind in HORNS},
    "garbage-truck.caf": "garbage_truck(), decision 437",
}


def manifest(out_dir):
    """The manifest of everything in `out_dir`, as text."""
    files = []
    by_file = {}
    for name, full, short in CHIMES:
        path = os.path.join(HERE, "scores", f"{name}.score.json")
        source = {"score": relative(path), "scoreSha256": sha256(path)}
        mml = scores.load(path).get("source", "")
        if mml.startswith("tools/audio/mml/"):
            source["mml"] = mml
            source["mmlSha256"] = sha256(os.path.join(ROOT, mml))
        by_file[full] = dict(source, kind="chime")
        by_file[short] = dict(source, kind="motif")
    for name, file in TUNES:
        path = os.path.join(HERE, "scores", f"{name}.score.json")
        by_file[file] = {"score": relative(path), "scoreSha256": sha256(path), "kind": "tune"}
    # Decision 815: the tunes, from their stems.
    for file, names in MUSIC_STEMS.items():
        stems = []
        for name in names:
            path = os.path.join(HERE, "scores", f"{name}.score.json")
            stem = {"score": relative(path), "scoreSha256": sha256(path)}
            mml = scores.load(path).get("source", "")
            if mml.startswith("tools/audio/mml/"):
                stem["mml"] = mml
                stem["mmlSha256"] = sha256(os.path.join(ROOT, mml))
            stems.append(stem)
        by_file[file] = {"stems": stems, "kind": "music"}
    for file in sorted(os.listdir(out_dir)):
        entry = {"file": file}
        if file in by_file:
            entry.update(by_file[file])
        else:
            entry["kind"] = (
                "running" if file.startswith("run-")
                else "weather" if file.startswith(("rain-", "thunder"))
                else "street" if file.startswith("garbage-truck")
                else "music" if file.endswith(".caf")
                else "sound"
            )
            entry["synth"] = f"make_game_audio.py {SYNTH_SOURCES[file]}"
        # The thunder is a CAF too (IMA4 keeps it small), but plays once.
        loops = file.endswith(".caf") and not file.startswith("thunder")
        entry.update(measured(os.path.join(out_dir, file), loops=loops))
        if entry["kind"] == "music":
            # Decision 815: the music's loudness, so its tunes stay level.
            entry["loudnessLufs"] = round(float(loudness_lufs(read_pcm(os.path.join(out_dir, file)))), 2)
        files.append(entry)
    data = {
        "about": "Made by tools/audio/make_game_audio.py (decision 219); never edit by hand.",
        "mmlCore": {
            "path": relative(MML_CORE),
            "repository": "a91453/mml-tools",
            "commit": MML_CORE_COMMIT,
            "sha256": sha256(MML_CORE),
            "license": "MIT, Copyright (c) 2026 a91453 (mml-core/LICENSE)",
        },
        "files": files,
    }
    text = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
    rms = [f["rmsDbfs"] for f in files if f["kind"] == "chime"]
    if max(rms) - min(rms) > 3:
        raise SystemExit(f"the chimes' RMS spread {max(rms) - min(rms):.2f} dB, more than §3's 3 dB")
    return text


def main(out_dir):
    os.makedirs(out_dir, exist_ok=True)

    # Decision 815: the two tunes from their stems, equally loud.
    for file, stems in MUSIC_STEMS.items():
        write_caf(os.path.join(out_dir, file), level_to(stems_loop(stems), MUSIC_LUFS))
    # Decision 343: the running loops.
    write_caf(os.path.join(out_dir, "run-electric.caf"), normalized(running("electric"), 0.5))
    write_caf(os.path.join(out_dir, "run-highspeed.caf"), normalized(running("highSpeed"), 0.5))
    # Decision 567: the diesel railcar's three.
    write_caf(os.path.join(out_dir, "run-diesel.caf"), normalized(diesel("diesel"), 0.5))
    write_caf(os.path.join(out_dir, "run-diesel-idle.caf"), normalized(diesel("dieselIdle"), 0.5))
    write_caf(os.path.join(out_dir, "run-diesel-coast.caf"), normalized(diesel("dieselCoast"), 0.5))
    # Decision 664: an electric train's motors, pulling away and braking.
    for file, mode, kmh in motor_files():
        write_caf(os.path.join(out_dir, file), motor(mode, kmh))
    # Decision 346: the weather's loops and its thunder.
    write_caf(os.path.join(out_dir, "rain-steady.caf"), normalized(weather("rain"), 0.5))
    write_caf(os.path.join(out_dir, "rain-typhoon.caf"), normalized(weather("typhoon"), 0.5))
    write_caf(os.path.join(out_dir, "thunder.caf"), normalized(thunder(), 0.7))
    # Decision 437: the evening garbage truck's tune.
    write_caf(os.path.join(out_dir, "garbage-truck.caf"), normalized(garbage_truck(), 0.5))

    # Decision 219: the station chimes from their scores. The local one is
    # decision 79's station chime, a bell on C6 and, 0.25 s later, a softer
    # one on G6, byte for byte as before.
    for name, full, short in CHIMES:
        sheet = scores.load(os.path.join(HERE, "scores", f"{name}.score.json"))
        write_wav(os.path.join(out_dir, full), chime(sheet))
        write_wav(os.path.join(out_dir, short), motif(sheet))
    for name, file in TUNES:
        write_wav(os.path.join(out_dir, file), chime(scores.load(os.path.join(HERE, "scores", f"{name}.score.json"))))
    write_wav(os.path.join(out_dir, "whoosh.wav"), normalized(whoosh(1.0), 0.6))
    joint = np.zeros(int(0.35 * SR))
    a = clack()
    joint[: len(a)] += a
    joint[int(0.13 * SR) : int(0.13 * SR) + len(a)] += 0.8 * a
    write_wav(os.path.join(out_dir, "rail-joint.wav"), normalized(joint, 0.6))

    # Decision 117: something put up, a soft thud under a rising pluck
    # (G, then C an octave up), and money in, two bright bells a fifth apart.
    done = np.zeros(int(0.8 * SR))
    thud = clack()
    done[: len(thud)] += 0.7 * thud
    rise = pluck(79, 0.5)
    done[int(0.04 * SR) : int(0.04 * SR) + len(rise)] += 0.8 * rise
    top = pluck(84, 0.6)
    done[int(0.12 * SR) : int(0.12 * SR) + len(top)] += top
    write_wav(os.path.join(out_dir, "build-done.wav"), normalized(done, 0.6))
    coins = np.zeros(int(0.9 * SR))
    for i, (m, at) in enumerate([(96, 0.0), (103, 0.09)]):
        ding = bell(m, 0.8)
        start = int(at * SR)
        coins[start : start + len(ding)] += (1.0 - 0.25 * i) * ding[: len(coins) - start]
    write_wav(os.path.join(out_dir, "coins.wav"), normalized(coins, 0.5))

    # Decision 184: something refused, two soft low plucks falling a minor
    # third (E, then C#); and a warning, two short bells a tone apart
    # (A, then B), quieter than the station chime.
    refused = np.zeros(int(0.55 * SR))
    for m, at, gain in [(52, 0.0, 1.0), (49, 0.14, 0.9)]:
        tone = pluck(m, 0.4)
        start = int(at * SR)
        refused[start : start + len(tone)] += gain * tone
    write_wav(os.path.join(out_dir, "refused.wav"), normalized(refused, 0.5))
    warning = np.zeros(int(0.9 * SR))
    for m, at in [(81, 0.0), (83, 0.16)]:
        ding = bell(m, 0.7)
        start = int(at * SR)
        warning[start : start + len(ding)] += ding[: len(warning) - start]
    write_wav(os.path.join(out_dir, "warning.wav"), normalized(warning, 0.45))

    # Decision 373: a day pass on sale, a ticket printed, cut and dropped.
    write_wav(os.path.join(out_dir, "ticket-issued.wav"), normalized(ticket(), 0.5))

    # Decision 403 (續二): the followed train's horn, one for each kind.
    # Levelled by RMS, not peak: an air horn's in-phase harmonics peak
    # some 7 dB higher than an electronic horn's square at the same
    # loudness.
    for kind in HORNS:
        x = horn(kind)
        x = x * HORN_RMS / np.sqrt(np.mean(x**2))
        if np.abs(x).max() > 0.95:
            raise SystemExit(f"horn {kind} would clip")
        write_wav(os.path.join(out_dir, f"horn-{kind}.wav"), x)


def check(out_dir):
    """Fails unless making everything again gives `out_dir` and the
    manifest byte for byte."""
    problems = []
    with tempfile.TemporaryDirectory() as tmp:
        main(tmp)
        made = sorted(os.listdir(tmp))
        committed = sorted(os.listdir(out_dir))
        if made != committed:
            problems.append(f"files differ: made {made}, committed {committed}")
        for file in made:
            path = os.path.join(out_dir, file)
            if os.path.exists(path) and sha256(path) != sha256(os.path.join(tmp, file)):
                problems.append(f"{file} is not what the script makes")
        with open(MANIFEST, encoding="utf-8") as f:
            if f.read() != manifest(tmp):
                problems.append("manifest.json is not what the script makes")
    if shutil.which("node"):
        if subprocess.run(["node", os.path.join(HERE, "mml_to_score.mjs"), "--check"]).returncode:
            problems.append("a score differs from its MML")
    else:
        print("node is not on the PATH: the scores were not compared with their MML")
    for p in problems:
        print(p, file=sys.stderr)
    if problems:
        sys.exit(1)
    print("every file and the manifest are as the script makes them")


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--check":
        check(sys.argv[2])
    elif len(sys.argv) == 2:
        main(sys.argv[1])
        with open(MANIFEST, "w", encoding="utf-8") as f:
            f.write(manifest(sys.argv[1]))
    else:
        sys.exit(__doc__)
