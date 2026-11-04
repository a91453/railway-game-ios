#!/usr/bin/env python3
"""Measure a recording of a diesel railcar for the diesel running loops
(decision 567).

Prints, for a stretch of a recording, what `make_game_audio.py`'s
`DIESEL_ENGINES` holds:

- `f0`: the engine's fundamental in Hz, to 0.125 Hz (a whole number of
  cycles in an 8-second loop): the frequency whose first 12 harmonics are
  together loudest, between 25 and 90 Hz, the median over 4-second windows;
- `harmonics`: the level of each of those 12 harmonics, in dB below the
  loudest band of the floor;
- `floor`: the third-octave band levels from 31.5 Hz to 12.5 kHz of what
  is left under the tones (each window's spectrum median-filtered over
  about 15 Hz, which leaves the noise and drops the engine's lines), in dB
  below its loudest band.

All are medians over 4-second windows. Only these numbers go into the
game: the recordings are not committed, bundled or copied. Where each was
downloaded from, its terms and the stretch measured are in
`tools/audio/README.md` and decision 567.

    python3 -I tools/audio/measure_diesel_engine.py RECORDING START END

START and END are seconds. Needs numpy, and ffmpeg on the PATH to decode.
"""

import subprocess
import sys

import numpy as np

SR = 48_000
CENTRES = [1000 * 2 ** (n / 3) for n in range(-15, 12)]
WINDOW = 4 * SR
HARMONICS = 12


def decoded(path):
    raw = subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
        check=True, capture_output=True,
    ).stdout
    return np.frombuffer(raw, dtype="<f4").astype(float)


def running_median(power, width):
    """`power` median-filtered over `width` bins (odd)."""
    half = width // 2
    padded = np.pad(power, half, mode="edge")
    view = np.lib.stride_tricks.sliding_window_view(padded, width)
    return np.median(view, axis=1)


def window(x):
    """One window's fundamental, harmonic levels and floor bands, in dB
    (not yet relative)."""
    power = np.abs(np.fft.rfft(x * np.hanning(len(x)))) ** 2
    freqs = np.fft.rfftfreq(len(x), 1 / SR)
    per_hz = len(x) / SR
    logs = np.log(power + 1e-20)
    candidates = np.arange(25, 90, 0.125)
    scores = [np.mean([logs[int(round(k * c * per_hz))] for k in range(1, HARMONICS + 1)]) for c in candidates]
    f0 = candidates[int(np.argmax(scores))]
    floor = running_median(power, int(15 * per_hz) | 1)
    bands = []
    for c in CENTRES:
        mask = (freqs >= c * 2 ** (-1 / 6)) & (freqs < c * 2 ** (1 / 6))
        bands.append(10 * np.log10(floor[mask].sum() + 1e-20))
    tones = []
    for k in range(1, HARMONICS + 1):
        at = int(round(k * f0 * per_hz))
        near = slice(at - 3, at + 4)
        # The line's power over the floor under it (the Hann window spreads
        # a line over a few bins).
        above = max(power[near].sum() - floor[near].sum(), 1e-20)
        tones.append(10 * np.log10(above))
    return f0, np.array(tones), np.array(bands)


def main(args):
    if len(args) != 3:
        sys.exit(__doc__)
    path, start, end = args[0], float(args[1]), float(args[2])
    x = decoded(path)[int(start * SR) : int(end * SR)]
    if len(x) < WINDOW:
        # A short loop (the idle one is 2 seconds): played round.
        x = np.tile(x, -(-WINDOW // len(x)))[:WINDOW]
    rows = [window(x[s : s + WINDOW]) for s in range(0, len(x) - WINDOW + 1, WINDOW // 2)]
    f0 = float(np.median([r[0] for r in rows]))
    tones = np.median([r[1] for r in rows], axis=0)
    bands = np.median([r[2] for r in rows], axis=0)
    top = bands.max()
    print(f"f0 = {round(f0 * 8) / 8}")
    print("harmonics = [" + ", ".join(f"{v - top:.0f}" for v in tones) + "]")
    print("floor = [" + ", ".join(f"{v - top:.0f}" for v in bands) + "]")


if __name__ == "__main__":
    main(sys.argv[1:])
