#!/usr/bin/env python3
"""Measure a piece of game music for the music review (.claude/skills/music-review).

Prints, for each file: its length; integrated loudness, loudness range and
true peak (ffmpeg's EBU R128 meter); the share of its energy in five bands
(below 120 Hz, which a phone's speaker hardly plays, then 120-300, 300-1000,
1000-4000 and above 4000 Hz); the range of its one-second levels; and the
step between its last and first sample beside the 99th percentile of every
step (a loop seam larger than that can click).

    python3 -I tools/audio/measure_music.py FILE [FILE ...]

Needs numpy, and ffmpeg on the PATH to decode and to meter.
"""

import re
import subprocess
import sys

import numpy as np

SR = 44100
BANDS = [(0, 120), (120, 300), (300, 1000), (1000, 4000), (4000, SR / 2)]


def decoded(path):
    """The first channel at SR, as float32."""
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
        check=True,
        capture_output=True,
    ).stdout
    return np.frombuffer(raw, dtype=np.float32)


def r128(path):
    """Integrated loudness (LUFS), loudness range (LU) and true peak (dBTP)."""
    log = subprocess.run(
        ["ffmpeg", "-nostats", "-i", path, "-af", "ebur128=peak=true", "-f", "null", "-"],
        check=True,
        capture_output=True,
        text=True,
    ).stderr
    summary = log[log.rfind("Summary:") :]

    def value(label):
        return float(re.search(label + r":\s+(-?[\d.]+)", summary).group(1))

    return value("I"), value("LRA"), value("Peak")


def main(paths):
    for path in paths:
        x = decoded(path)
        power = np.abs(np.fft.rfft(x)) ** 2
        freqs = np.fft.rfftfreq(len(x), 1 / SR)
        total = power.sum()
        shares = [100 * power[(freqs >= lo) & (freqs < hi)].sum() / total for lo, hi in BANDS]
        second = [x[i : i + SR] for i in range(0, len(x) - SR + 1, SR)]
        levels = [20 * np.log10(np.sqrt((s**2).mean()) + 1e-9) for s in second]
        seam = abs(float(x[0]) - float(x[-1]))
        p99 = float(np.percentile(np.abs(np.diff(x)), 99))
        lufs, lra, peak = r128(path)
        print(path)
        print(f"  length {len(x) / SR:.1f} s")
        print(f"  loudness {lufs:.1f} LUFS, range {lra:.1f} LU, true peak {peak:.1f} dBTP")
        print(
            "  energy  <120 Hz {:.0f}%  120-300 {:.0f}%  300-1k {:.0f}%  1k-4k {:.0f}%  >4k {:.0f}%".format(
                *shares
            )
        )
        print(f"  one-second levels {min(levels):.1f} to {max(levels):.1f} dBFS")
        print(f"  loop seam step {seam:.4f} (99th percentile of steps {p99:.4f})")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1:])
