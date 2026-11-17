#!/usr/bin/env python3
"""The intro video's music: the theme cut to the picture (THEME-PLAIN).

usage: make_video_music.py OUT.wav

The website's intro video (railway-assets-private
`promo-material/2026-11-18/`) is scored with the game's theme, the D minuet
of decision 815's later note, played on the same sampled instruments
(`sampled_music.py`, `sampled/arrangements.json`): the video and the game
sound the same. The video is 30.4 seconds; the theme is 76.8. So the
theme's own bars are re-ordered into a cue whose phrases start at the
video's cuts (a bar is 1.2 seconds at 150 bpm, a phrase four bars):

    0.0  one bar of the accompaniment alone (the opening logo)
    1.2  bars 1-8 (the melody starts under the logo; #1 at 2.0, #2 at 6.0)
   10.8  bars 9-12 (#3, the high-speed train)
   15.6  bars 13-16, the climb to D and the half close (#4, the cities)
   20.4  bars 25, 26, 27, 30, 31: I - IV6 - V6 - I6/4 - V7 (#5, day to night)
   26.4  the tonic, a full chord, ringing on to the end (the end card)

`CUE` is that list. The notes are the theme's, bar for bar, except the
first bar (the harmony stems only) and the last (`ending`). The cue is
rendered once from silence, as the game's tunes played once are, its last
chord ringing `RING` seconds with the last `RING_FADE` eased to nothing,
then limited and levelled to the game music's loudness (`MUSIC_LUFS`),
so the video sounds as loud as the game. Written as a 16-bit WAV for the
video's build (`promo-material/2026-11-18/tools/retime.py`).

When the arrangement changes (another bank, other instruments), run this
again and rebuild the video: the cue follows `arrangements.json`.
"""

import copy
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import make_game_audio as audio  # noqa: E402
import sampled_music  # noqa: E402
import score as scores  # noqa: E402

TUNE = "theme"
# The theme's bars (1-based) in the cue's order; "intro" is bar 1's
# accompaniment without the melody, "end" the closing chord.
CUE = ["intro"] + list(range(1, 17)) + [25, 26, 27, 30, 31] + ["end"]
# Bars of the cue at which a phrase starts (the video's cuts), for the
# players' phrasing (each swells to its middle and eases off).
PHRASES = [1, 5, 9, 13, 17]
# Seconds the last chord rings after the last bar; the video's end card
# is 4.0 seconds from its downbeat (1.2 of them the bar itself).
RING = 2.8
RING_FADE = 1.6


def bar_notes(track, bar, length):
    """The notes of `track` starting in 0-based `bar`, moved to start at 0."""
    lo, hi = bar * length, (bar + 1) * length
    return [dict(note, start=note["start"] - lo) for note in track["notes"] if lo <= note["start"] < hi]


def ending(name, index, source, length):
    """The closing bar: the theme's last bar (its 32nd) made a final chord.
    The melody's C holds and the piano adds the chord under it; the
    pizzicato plays its three notes together on the first beat, not on the
    second and third; the strings hold C and add G and E; the rail joint
    rests."""
    notes = bar_notes(source, 31, length)
    if name == "theme-melody":
        top = notes[0]
        return [dict(top, pitch=pitch, length=2 * length, velocity=top["velocity"] - (0 if pitch == top["pitch"] else 14))
                for pitch in (64, 67, top["pitch"])]
    if name == "theme-harmony":
        if index == 3:
            low = notes[0]
            return [dict(low, pitch=pitch, length=2 * length) for pitch in (55, low["pitch"], 64)]
        first = notes[0]
        return [dict(first, start=0, length=length // 2)]
    return []


def cue_sheets():
    """The theme's stem scores cut to `CUE`: same tempo and metre, `CUE`'s
    bars long, every track's notes taken bar by bar."""
    names = sampled_music.stems(TUNE)
    sheets = [scores.load(os.path.join(HERE, "scores", f"{name}.score.json")) for name in names]
    bar = sheets[0]["beatsPerBar"] * sampled_music.TPB
    out = []
    for name, sheet in zip(names, sheets):
        cut = copy.deepcopy(sheet)
        cut["length"] = len(CUE) * bar
        for index, track in enumerate(cut["tracks"]):
            notes = []
            for at, source in enumerate(CUE):
                if source == "intro":
                    moved = [] if name == "theme-melody" else bar_notes(track, 0, bar)
                elif source == "end":
                    moved = ending(name, index, track, bar)
                else:
                    moved = bar_notes(track, source - 1, bar)
                notes += [dict(note, start=note["start"] + at * bar) for note in moved]
            track["notes"] = sorted(notes, key=lambda note: (note["start"], note["pitch"]))
        out.append(cut)
    return out, bar


def phrased(sheets, bar):
    """`sampled_music.played` swells each four bars from the cue's start;
    the cue's phrases start a bar later (after the intro bar), so its
    notes are played a bar early in the phrase count: shifted for the
    phrasing, not in time."""
    shift = (4 - PHRASES[0] % 4) % 4 * bar
    played = sampled_music.played

    def at_phrase(name, index, track, entry, beats_per_bar, tempo, phrase_bars):
        moved = dict(track, notes=[dict(note, start=note["start"] + shift) for note in track["notes"]])
        return [(start - shift, length, velocity, pitch)
                for start, length, velocity, pitch in played(name, index, moved, entry, beats_per_bar, tempo, phrase_bars)]

    return at_phrase


def render():
    sheets, bar = cue_sheets()
    original = sampled_music.played
    sampled_music.played = phrased(sheets, bar)
    try:
        rendered, n, seconds_per_tick = sampled_music._render(
            TUNE, sheets, 1, lambda n: n / sampled_music.SR + sampled_music.TAIL)
    finally:
        sampled_music.played = original
    sr = sampled_music.SR
    cue = rendered[: n + round(sampled_music.TAIL * sr)].copy()
    sampled_music._synth_tracks(cue, TUNE, sheets, seconds_per_tick, lambda name: audio.clack(), wrap=None)
    cue = sampled_music.master(sampled_music.reverb(cue, sampled_music.tunes()[TUNE]["reverb"]))[: n + round(RING * sr)]
    fade = round(RING_FADE * sr)
    cue[-fade:] *= (0.5 + 0.5 * np.cos(np.pi * np.arange(1, fade + 1) / fade))[:, None]
    gain = 10 ** ((audio.MUSIC_LUFS - audio.loudness_lufs(cue[:n])) / 20)
    cue = sampled_music.limit(cue, gain, audio.MUSIC_CEILING) * gain
    if np.abs(cue).max() > 0.9:
        raise SystemExit(f"the cue peaks at {np.abs(cue).max():.2f}")
    return cue, n


def main(path):
    cue, n = render()
    audio.write_wav(path, cue)
    sr = sampled_music.SR
    print(f"{path}: {len(cue) / sr:.2f} s ({n / sr:.2f} s of bars), {audio.loudness_lufs(cue):.2f} LUFS, "
          f"peak {20 * np.log10(np.abs(cue).max()):.2f} dBFS")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    main(sys.argv[1])
