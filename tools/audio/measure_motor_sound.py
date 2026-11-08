#!/usr/bin/env python3
"""Measure a recording of an electric train's motors for the motor loops
(decision 664).

An inverter-driven (VVVF) train's motors sing: tones whose pitch follows
the speed, a carrier that holds still at low speed, steps where the
inverter changes its pattern. This prints, for each of `BANDS` (the speed,
in km/h, each motor loop is made at), what `make_game_audio.py`'s
`MOTOR_TONES` holds:

- `tones`: the 12 loudest tones (none more than 15 dB under the loudest), each `[Hz, dB]`, the frequency to 0.5 Hz
  (a whole number of cycles in a 2-second loop) and the tone's power over
  the noise under it, in dB below the recording's whole power there (the
  wheels, the wind and the motors together, 60 Hz to 8 kHz);
- `level`: those tones together, in dB below the same;
- `steady`: printed when the tones hold still as the speed changes (an
  inverter's carrier at low speed), so the loop plays at its own rate
  rather than faster or slower with the speed.

Each band is the median of the 0.5-second windows (every 1/8 s) whose
speed is within 4% of the band's, or of the 3 nearest where the train sped
through faster, each window's spectrum first stretched by the band's speed
over its own, so tones whose pitch follows the speed line up, and again
unstretched, for tones that hold still: whichever has the louder loudest
tone. A tone is a local peak 6 dB over the spectrum median-filtered over
about 30 Hz.

The recording's speed at each moment is given on the command line, as
`seconds:kmh` points joined by straight lines: read off the motors' own
fundamental, which follows the speed (`--fundamental` prints it every half
second, the frequency in 15–140 Hz whose harmonics 1, 2, 4, 6, 8 and 12 are
together loudest over the noise). How it was turned into km/h is in
decision 664.

Only these numbers go into the game: the recordings are not committed,
bundled or copied. Where each was downloaded from, its terms and the
stretch measured are in `tools/audio/README.md` and decision 664.

    python3 -I tools/audio/measure_motor_sound.py RECORDING SECONDS:KMH ...
    python3 -I tools/audio/measure_motor_sound.py --fundamental RECORDING

Needs numpy, and ffmpeg on the PATH to decode.
"""

import subprocess
import sys

import numpy as np

SR = 48_000
WINDOW = SR // 2
HOP = SR // 8
# The speeds the motor loops are made at, in km/h: each about 1.5 times the
# last, so a loop plays at about 0.82 to 1.22 of its rate before the next
# takes over.
BANDS = [4, 6, 9, 14, 20, 30, 45, 68]
TONES = 12
# How near a window's speed is to the band's, and the fewest windows a band
# is the median of.
NEAR = 0.04
MIN_WINDOWS = 3
# How far under a band's loudest tone the quietest kept is, in dB.
QUIETEST = 15


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


def spectra(x):
    """Each window's middle in seconds and its power spectrum."""
    hann = np.hanning(WINDOW)
    for start in range(0, len(x) - WINDOW + 1, HOP):
        yield (start + WINDOW / 2) / SR, np.abs(np.fft.rfft(x[start : start + WINDOW] * hann)) ** 2


def fundamentals(x):
    """The motors' fundamental every half second (see the docstring)."""
    for start in range(0, len(x) - SR + 1, SR // 2):
        power = np.abs(np.fft.rfft(x[start : start + SR] * np.hanning(SR))) ** 2
        over = 10 * np.log10(power / running_median(power, 31))
        best = max(
            (np.mean([over[int(round(k * c)) - 1 : int(round(k * c)) + 2].max() for k in (1, 2, 4, 6, 8, 12) if k * c < 2400]), c)
            for c in np.arange(15, 140, 0.5)
        )
        print(f"{(start + SR / 2) / SR:5.1f} s  {best[1]:5.1f} Hz  ({best[0]:.1f} dB)")


def band(x, speed_at, kmh):
    """The tones and their level at `kmh` (see the docstring)."""
    freqs = np.fft.rfftfreq(WINDOW, 1 / SR)
    near = []
    for t, power in spectra(x):
        v = speed_at(t)
        if v > 0:
            near.append((abs(v / kmh - 1), v, power))
    near.sort(key=lambda w: w[0])
    if not near or near[0][0] > NEAR:
        return None
    # Those within 4%, or the nearest MIN_WINDOWS where the train sped
    # through faster.
    chosen = [w for w in near if w[0] <= NEAR] if len([w for w in near if w[0] <= NEAR]) >= MIN_WINDOWS else near[:MIN_WINDOWS]
    # The window's tone at f sounds at f × kmh / v at the band's speed, if
    # it follows the speed; an inverter's carrier at low speed holds still.
    # Both are tried, and the one whose loudest tone is louder is kept (not
    # the louder together: a tone measured the wrong way is smeared over
    # the windows and splits into several weaker peaks).
    following = tones_of([np.interp(freqs, freqs * kmh / v, power) for _, v, power in chosen], freqs)
    steady = tones_of([power for _, _, power in chosen], freqs)
    tones, level = max(following, steady, key=lambda measured: max((d for _, d in measured[0]), default=-999))
    return tones, round(level, 1), len(chosen), tones is steady[0]


def tones_of(spectra, freqs):
    """The tones of the median of `spectra` (which keeps a tone heard
    through the windows and drops the noise's chance peaks), each `(Hz,
    dB)`, and their level together."""
    power = np.median(spectra, axis=0)
    floor = running_median(power, int(30 * WINDOW / SR) | 1)
    audible = (freqs >= 60) & (freqs < 8000)
    whole = power[audible].sum()
    over = 10 * np.log10(power / floor)
    peaks = [
        i for i in np.where((freqs >= 60) & (freqs < 4000))[0]
        if over[i] > 6 and power[i] >= power[i - 1] and power[i] >= power[i + 1]
    ]
    tones = []
    for i in peaks:
        near = slice(i - 2, i + 3)
        above = max(power[near].sum() - floor[near].sum(), 1e-20)
        tones.append((above, freqs[i]))
    tones = sorted(tones, reverse=True)[:TONES]
    # Far under the loudest, a peak is more likely the noise's than a tone.
    tones = [(a, f) for a, f in tones if a >= tones[0][0] * 10 ** (-QUIETEST / 10)]
    level = 10 * np.log10(max(sum(a for a, _ in tones), 1e-20) / whole)
    return sorted((round(f * 2) / 2, round(10 * np.log10(a / whole))) for a, f in tones), level


def main(args):
    if len(args) == 2 and args[0] == "--fundamental":
        fundamentals(decoded(args[1]))
        return
    if len(args) < 3:
        sys.exit(__doc__)
    points = sorted(tuple(float(v) for v in p.split(":")) for p in args[1:])
    times, speeds = zip(*points)

    def speed_at(t):
        if t < times[0] or t > times[-1]:
            return 0
        return float(np.interp(t, times, speeds))

    x = decoded(args[0])
    for kmh in BANDS:
        measured = band(x, speed_at, kmh)
        if measured is None:
            print(f"{kmh}: not in the recording")
            continue
        tones, level, windows, steady = measured
        if not tones:
            print(f"{kmh}: no tone heard  # {windows} windows")
            continue
        held = ", \"steady\": True" if steady else ""
        print(f"{kmh}: {{\"level\": {level}{held}, \"tones\": {[[f, d] for f, d in tones]}}},  # {windows} windows")


if __name__ == "__main__":
    main(sys.argv[1:])
