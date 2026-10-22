#!/usr/bin/env python3
"""Measure recordings of thunder for the thunder of the weather (decision 346).

Prints, for claps of thunder in recordings of rain, what
`make_game_audio.py`'s `THUNDER` holds: the third-octave band levels of the
clap's first second and of its rumble (2 to 10 s after it), each above the
rain before it and in dB below its loudest band, and how fast the rumble
dies away, in dB a second (a straight line through the loudest quarter
second of each second, for 12 s). Only these numbers go into the game: the
recordings are not committed, bundled or copied. Where each was downloaded
from, its licence and the claps measured are in `tools/audio/README.md`.

    python3 -I tools/audio/measure_thunder.py RECORDING CLAP RAIN_START RAIN_END [...]

CLAP, RAIN_START and RAIN_END are seconds: when the clap begins, and a
stretch of rain without thunder before it. With several claps the levels
and the rate are the mean of each one's. Needs numpy, and ffmpeg on the
PATH to decode.
"""

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from measure_running_spectrum import CENTRES, SR, decoded

QUARTER = SR // 4


def band_powers(x):
    """The power of each band in each quarter second, frames × bands."""
    freqs = np.fft.rfftfreq(QUARTER, 1 / SR)
    masks = [(freqs >= c * 2 ** (-1 / 6)) & (freqs < c * 2 ** (1 / 6)) for c in CENTRES]
    rows = []
    for start in range(0, len(x) - QUARTER + 1, QUARTER):
        power = np.abs(np.fft.rfft(x[start : start + QUARTER] * np.hanning(QUARTER))) ** 2
        rows.append([power[m].sum() for m in masks])
    return np.array(rows)


def above(power, rain):
    """Band levels of `power` above the rain's, in dB below the loudest."""
    level = 10 * np.log10(np.maximum(power - rain, rain * 1e-3))
    return level - level.max()


def clap(x, at, rain_start, rain_end):
    rain = np.median(band_powers(x[int(rain_start * SR) : int(rain_end * SR)]), axis=0)
    after = band_powers(x[int(at * SR) : int((at + 12) * SR)])
    first = above(after[:4].mean(axis=0), rain)
    rumble = above(after[8:40].mean(axis=0), rain)
    total = 10 * np.log10(np.maximum(after.sum(axis=1) - rain.sum(), rain.sum() * 1e-3))
    loudest = total.reshape(-1, 4).max(axis=1)
    rate = np.polyfit(np.arange(len(loudest)), loudest, 1)[0]
    return first, rumble, rate


def main(args):
    if len(args) < 4 or len(args) % 4:
        sys.exit(__doc__)
    claps = []
    for path, at, start, end in zip(args[::4], args[1::4], args[2::4], args[3::4]):
        claps.append(clap(decoded(path), float(at), float(start), float(end)))
    for name, index in [("first second", 0), ("rumble", 1)]:
        mean = np.mean([c[index] for c in claps], axis=0)
        mean -= mean.max()
        print(f"{name}: [" + ", ".join(f"{v:.0f}" for v in mean) + "]")
    print(f"dies away: {np.mean([c[2] for c in claps]):.1f} dB/s")


if __name__ == "__main__":
    main(sys.argv[1:])
