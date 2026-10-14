"""The score of 《沿線》, format 1 (decision 219; research note
docs/research/RAILWAY_SOUND_2026-10-14.md §2.14 and §3): read and check.

A score is event data, not a notation language: whole ticks, 960 a beat;
one tempo; tracks, each one synth voice with a gain (0–100) and a pan
(-100–100); notes with a MIDI pitch, a start and a length in ticks and a
velocity (1–127). It also says how many of its first notes are the motif
played at high speed, and how long (in ticks) its end fades.

`check` refuses anything else, the way GameCore will check a player's score
with `Codable` later (stage 4): unknown keys, wrong types, notes past the
end, and for the official chimes the limits of §3 (at most 3 s, 4 tracks,
C3–C7, C major pentatonic, a motif of 2 or 3 notes that start within the
first 0.68 s, so they sound before the motif's fade).
"""

import json

FORMAT = 1
TICKS_PER_BEAT = 960
ROLES = ("chime", "departure", "stem")
VOICES = ("bell", "pluck", "pad", "clack")
# §3: C D E G A, the official chimes' scale.
PENTATONIC = {0, 2, 4, 7, 9}
# §3 and §6: a chime lasts at most 3 s; the motif file is 0.8 s, and its
# last 0.12 s fade, so the motif's notes start within the first 0.68 s.
CHIME_SECONDS = 3.0
MOTIF_SECONDS = 0.8
MOTIF_FADE_SECONDS = 0.12

_TOP = {"format", "role", "title", "source", "tempo", "beatsPerBar", "length", "motif", "fadeOut", "tracks"}
_REQUIRED = _TOP - {"source"}
_TRACK = {"voice", "gain", "pan", "notes"}
_NOTE = {"pitch", "start", "length", "velocity"}


class ScoreError(ValueError):
    pass


def _int(value, low, high, what):
    if type(value) is not int or not low <= value <= high:
        raise ScoreError(f"{what} must be a whole number in {low}...{high}, not {value!r}")
    return value


def _keys(obj, allowed, required, what):
    if not isinstance(obj, dict):
        raise ScoreError(f"{what} must be an object")
    unknown = set(obj) - allowed
    if unknown:
        raise ScoreError(f"{what} has unknown keys {sorted(unknown)}")
    missing = required - set(obj)
    if missing:
        raise ScoreError(f"{what} lacks {sorted(missing)}")


def seconds(score, ticks):
    return ticks * 60 / (score["tempo"] * TICKS_PER_BEAT)


def motif_notes(score):
    """The score's first `motif` notes, in order of start (then track, then
    pitch)."""
    notes = sorted(
        ((n["start"], t, n["pitch"], n) for t, track in enumerate(score["tracks"]) for n in track["notes"]),
        key=lambda item: item[:3],
    )
    return [n for *_, n in notes[: score["motif"]]]


def check(score, name="score"):
    """`score` if it is a valid score of format 1; raises ScoreError."""
    _keys(score, _TOP, _REQUIRED, name)
    if score["format"] != FORMAT:
        raise ScoreError(f"{name}: format {score['format']!r} is not {FORMAT}")
    if score["role"] not in ROLES:
        raise ScoreError(f"{name}: role {score['role']!r} is not one of {ROLES}")
    if not isinstance(score["title"], str) or not score["title"]:
        raise ScoreError(f"{name}: needs a title")
    if "source" in score and not isinstance(score["source"], str):
        raise ScoreError(f"{name}: source must be text")
    _int(score["tempo"], 20, 300, f"{name}: tempo")
    _int(score["beatsPerBar"], 1, 16, f"{name}: beatsPerBar")
    length = _int(score["length"], 1, 10_000 * 16 * TICKS_PER_BEAT, f"{name}: length")
    _int(score["fadeOut"], 0, length, f"{name}: fadeOut")
    tracks = score["tracks"]
    if not isinstance(tracks, list) or not tracks:
        raise ScoreError(f"{name}: needs at least one track")
    for t, track in enumerate(tracks):
        what = f"{name} track {t + 1}"
        _keys(track, _TRACK, _TRACK, what)
        if track["voice"] not in VOICES:
            raise ScoreError(f"{what}: voice {track['voice']!r} is not one of {VOICES}")
        _int(track["gain"], 0, 100, f"{what}: gain")
        _int(track["pan"], -100, 100, f"{what}: pan")
        notes = track["notes"]
        if not isinstance(notes, list) or not notes:
            raise ScoreError(f"{what}: needs at least one note")
        previous = None
        for i, note in enumerate(notes):
            nwhat = f"{what} note {i + 1}"
            _keys(note, _NOTE, _NOTE, nwhat)
            _int(note["pitch"], 0, 127, f"{nwhat}: pitch")
            start = _int(note["start"], 0, length - 1, f"{nwhat}: start")
            _int(note["length"], 1, length - start, f"{nwhat}: length (it must end by the score's end)")
            _int(note["velocity"], 1, 127, f"{nwhat}: velocity")
            key = (start, note["pitch"])
            if previous is not None and key <= previous:
                raise ScoreError(f"{nwhat}: notes go in order of start, then pitch, once each")
            previous = key
    motif = score["motif"]
    if score["role"] == "stem":
        _int(motif, 0, 0, f"{name}: a stem's motif")
    else:
        _int(motif, 2, 3, f"{name}: motif")
        if sum(len(t["notes"]) for t in tracks) < motif:
            raise ScoreError(f"{name}: fewer notes than the motif")
        last = max(n["start"] for n in motif_notes(score))
        if seconds(score, last) > MOTIF_SECONDS - MOTIF_FADE_SECONDS:
            raise ScoreError(f"{name}: the motif's notes must start within {MOTIF_SECONDS - MOTIF_FADE_SECONDS:.2f} s")
    if score["role"] == "chime":
        if seconds(score, length) > CHIME_SECONDS:
            raise ScoreError(f"{name}: a chime lasts at most {CHIME_SECONDS} s")
        if len(tracks) > 4:
            raise ScoreError(f"{name}: a chime has at most 4 tracks")
        for track in tracks:
            for note in track["notes"]:
                if not 48 <= note["pitch"] <= 96:
                    raise ScoreError(f"{name}: a chime's notes are C3–C7 (48–96), not {note['pitch']}")
                if note["pitch"] % 12 not in PENTATONIC:
                    raise ScoreError(f"{name}: an official chime keeps to C D E G A, not pitch {note['pitch']}")
    return score


def load(path):
    with open(path, encoding="utf-8") as file:
        return check(json.load(file), name=path)
