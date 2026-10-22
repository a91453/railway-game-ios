#!/usr/bin/env python3
"""Measure a recording of a train running for the running loops (decision 343).

Prints the median third-octave band levels of a stretch of a recording, in
dB below its loudest band, as `make_game_audio.py`'s `RUNNING_SPECTRA`
holds them. Only these numbers go into the game: the recordings are not
committed, bundled or copied (the research note
`docs/research/JAPAN_RAIL_DATA_2026-10-21.md` §7.3). Where each was
downloaded from, its licence and the stretch measured are in
`tools/audio/README.md`.

    python3 -I tools/audio/measure_running_spectrum.py RECORDING START END [RECORDING START END ...]

START and END are seconds. With several recordings the levels are the
mean of each one's, in dB. Needs numpy, and ffmpeg on the PATH to decode.
"""

import subprocess
import sys

import numpy as np

SR = 48_000
# Third-octave bands from 31.5 Hz to 12.5 kHz (exact centres 1000 * 2^(n/3)).
CENTRES = [1000 * 2 ** (n / 3) for n in range(-15, 12)]
WINDOW = 2 * SR


def decoded(path):
    raw = subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
        check=True, capture_output=True,
    ).stdout
    return np.frombuffer(raw, dtype="<f4").astype(float)


def band_levels(x):
    """The median level of each band over 2-second windows, in dB."""
    freqs = np.fft.rfftfreq(WINDOW, 1 / SR)
    masks = [(freqs >= c * 2 ** (-1 / 6)) & (freqs < c * 2 ** (1 / 6)) for c in CENTRES]
    rows = []
    for start in range(0, len(x) - WINDOW + 1, WINDOW):
        power = np.abs(np.fft.rfft(x[start : start + WINDOW] * np.hanning(WINDOW))) ** 2
        rows.append([10 * np.log10(power[m].sum() + 1e-20) for m in masks])
    return np.median(np.array(rows), axis=0)


def main(args):
    if len(args) < 3 or len(args) % 3:
        sys.exit(__doc__)
    levels = []
    for path, start, end in zip(args[::3], args[1::3], args[2::3]):
        x = decoded(path)[int(float(start) * SR) : int(float(end) * SR)]
        own = band_levels(x)
        levels.append(own - own.max())
    mean = np.mean(levels, axis=0)
    mean -= mean.max()
    print("[" + ", ".join(f"{v:.0f}" for v in mean) + "]")


if __name__ == "__main__":
    main(sys.argv[1:])
