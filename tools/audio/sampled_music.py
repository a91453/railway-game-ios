"""The game's music played on sampled instruments (decision 815, later note).

The notes are the music's stem scores (MML → `scores/*.score.json`, decision
219). `sampled/arrangements.json` says, for each tune, the files it makes and
which instrument plays each track:
a General MIDI program, or the synth's own rail joint. The programs are
played on two SoundFont banks, never committed: the chamber bank
(`chamber_bank.py`, THEME-PLAIN item 1), built from recordings of a
concert grand (Salamander, CC BY 3.0) and a chamber string section and
harp (VSCO 2 CE, CC0), for the piano, the pizzicato, the slow strings and
the harp, in front of GeneralUser GS (a bank whose licence allows use in
games, fetched at a pinned commit and checked by SHA-256) for the rest. The scores become one
MIDI file, played twice through so the second time round carries the first
one's tails, which SpessaSynth (`sampled/render.mjs`, npm, Apache-2.0)
renders; the second time round is the loop. A room reverb and a gentle
master, both circular, keep the loop seamless; it is levelled to
`MUSIC_LUFS` by the caller. A tune played once (the winter event's turns)
is rendered once through instead, from silence, and its last chord rings
out (`RING`), so one turn gives way to the next as a record changes songs.

The notes are played as a player would (`midi_file`): each phrase swells
to its middle and eases off, the first beat leans a little, the
accompaniment sits a few milliseconds either side of the beat and a
piano's pedal catches the first beat of each bar, all from a fixed seed.

The bank and the npm package are tools, as ffmpeg is: they make the audio
files and are not in the app.
"""

import hashlib
import json
import zlib
import os
import struct
import subprocess
import tempfile
import urllib.request

import numpy as np

import chamber_bank

HERE = os.path.dirname(os.path.abspath(__file__))
SAMPLED = os.path.join(HERE, "sampled")
ARRANGEMENTS = os.path.join(SAMPLED, "arrangements.json")
SR = 48_000
# MIDI ticks a beat in the file handed to the renderer (the scores' 960).
TPB = 960
# Seconds of tail rendered after the second time round (the longest the
# strings and the reverb ring on).
TAIL = 5.0
# Seconds a tune played once rings on after its last bar, the last
# `RING_FADE` of them eased to silence.
RING = 3.0
RING_FADE = 1.5


def arrangements():
    with open(ARRANGEMENTS, encoding="utf-8") as file:
        return json.load(file)


def bank_path():
    """The pinned bank: `AUDIO_SOUNDBANK` if set, else a cache outside the
    repository, downloaded once from the bank's repository at the pinned
    commit. Its SHA-256 must match."""
    bank = arrangements()["bank"]
    path = os.environ.get("AUDIO_SOUNDBANK") or os.path.join(
        os.path.expanduser("~"), ".cache", "railway-game-ios", f"{bank['commit']}-{bank['file']}"
    )
    if not os.path.exists(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        url = bank["repository"].replace("https://github.com/", "https://raw.githubusercontent.com/") + f"/{bank['commit']}/{bank['file']}"
        with urllib.request.urlopen(url) as response, open(path + ".part", "wb") as out:
            out.write(response.read())
        os.replace(path + ".part", path)
    with open(path, "rb") as file:
        digest = hashlib.sha256(file.read()).hexdigest()
    if digest != bank["sha256"]:
        raise SystemExit(f"{path}: SHA-256 {digest}, not the pinned {bank['sha256']}")
    return path


def bank_paths():
    """The banks the music plays on, first first: the chamber bank
    (`chamber_bank.py`: the piano, the pizzicato, the slow strings and the
    harp, recorded) in front of GeneralUser GS (every other program)."""
    return [chamber_bank.bank_path(), bank_path()]


# Banks to play on in place of `bank_paths()`, for comparing (None: those).
BANKS = None


def _vlq(n):
    out = [n & 0x7F]
    n >>= 7
    while n:
        out.append(0x80 | (n & 0x7F))
        n >>= 7
    return bytes(reversed(out))


def _track(events):
    events.sort(key=lambda e: (e[0], e[1]))
    data, last = b"", 0
    for tick, _, message in events:
        data += _vlq(tick - last) + message
        last = tick
    data += _vlq(0) + b"\xff\x2f\x00"
    return b"MTrk" + struct.pack(">I", len(data)) + data


def played(name, index, track, entry, beats_per_bar, tempo, phrase_bars):
    """The notes of track `index` of stem `name` as a player plays them:
    (start, length, velocity), ticks. Each `phrase_bars`-bar phrase swells
    to its middle and eases off (0.90 to 1.04 of the written velocity), a
    bar's first beat leans 5% and a note off the beat gives 5%, a little
    unevenness (2%) on top; `entry["looseness"]` milliseconds (a standard
    deviation, at most twice it) moves each note off the beat, earlier or
    later, the same every time round. Seeded by the stem and track.
    Gives (start, length, velocity, pitch)."""
    rng = np.random.default_rng(zlib.crc32(f"{name}/{index}".encode()))
    bar = beats_per_bar * TPB
    phrase = phrase_bars * bar
    ticks_per_ms = tempo * TPB / 60_000
    loose = entry.get("looseness", 0)
    out = []
    for note in track["notes"]:
        start = note["start"]
        contour = 0.90 + 0.14 * np.sin(np.pi * (start % phrase + note["length"] / 2) / phrase)
        accent = 1.05 if start % bar == 0 else 1.0 if start % TPB == 0 else 0.95
        velocity = int(np.clip(round(note["velocity"] * contour * accent * (1 + 0.02 * rng.standard_normal())), 1, 127))
        shift = 0
        if loose:
            shift = int(round(np.clip(rng.standard_normal(), -2, 2) * loose * ticks_per_ms))
        out.append([start + shift, note["length"], velocity, note["pitch"]])
    # A note ends before the same key is struck again, so its release
    # never cuts the next one short.
    following = {}
    for item in reversed(out):
        if item[3] in following:
            item[1] = max(1, min(item[1], following[item[3]] - item[0] - 1))
        following[item[3]] = item[0]
    return [tuple(item) for item in out]


def midi_file(sheets, plan, names, times=2, phrase_bars=4):
    """A type-1 MIDI file of the stems `sheets` (scores, named `names`),
    each track played on its `plan` entry (`played`), `times` times
    through."""
    first = sheets[0]
    bar = first["beatsPerBar"] * TPB
    meta = [
        (0, 0, b"\xff\x51\x03" + int(60_000_000 / first["tempo"]).to_bytes(3, "big")),
        (0, 0, b"\xff\x58\x04" + bytes([first["beatsPerBar"], 2, 24, 8])),
    ]
    tracks = [_track(meta)]
    channels = iter([c for c in range(16) if c != 9])
    for sheet, entries, name in zip(sheets, plan, names):
        for index, (track, entry) in enumerate(zip(sheet["tracks"], entries)):
            if "synth" in entry:
                continue
            channel = 9 if "drum" in entry else next(channels)
            events = [
                (0, 0, bytes([0xB0 | channel, 7, entry["volume"]])),
                (0, 0, bytes([0xB0 | channel, 10, entry["pan"]])),
                (0, 0, bytes([0xB0 | channel, 91, 0])),
                (0, 0, bytes([0xB0 | channel, 93, 0])),
            ]
            if "program" in entry:
                events.append((0, 0, bytes([0xC0 | channel, entry["program"]])))
            notes = played(name, index, track, entry, first["beatsPerBar"], first["tempo"], phrase_bars)
            for time in range(times):
                lap = time * first["length"]
                for start, length, velocity, pitch in notes:
                    pitch = entry.get("drum", pitch + entry.get("transpose", 0))
                    on = max(0, start + lap)
                    events.append((on, 1, bytes([0x90 | channel, pitch, velocity])))
                    events.append((on + length, 0, bytes([0x80 | channel, pitch, 0])))
                # A pedal held from just after each bar's first beat for
                # `pedal` beats: the downbeat rings, the line stays clear.
                if entry.get("pedal"):
                    for at in range(lap, lap + first["length"], bar):
                        events.append((at + TPB // 16, 0, bytes([0xB0 | channel, 64, 127])))
                        events.append((at + entry["pedal"] * TPB - TPB // 32, 0, bytes([0xB0 | channel, 64, 0])))
            tracks.append(_track(events))
    return b"MThd" + struct.pack(">IHHH", 6, 1, len(tracks), TPB) + b"".join(tracks)


def room_ir(seconds=1.9, seed=11):
    """A small hall: five early reflections, then decaying noise whose
    highs (above 2.5 kHz) die faster than its lows; stereo, fixed seed."""
    rng = np.random.default_rng(seed)
    n = int(SR * seconds)
    t = np.arange(n) / SR
    f = np.fft.rfftfreq(n, 1 / SR)
    ir = np.zeros((n, 2))
    for c in range(2):
        spectrum = np.fft.rfft(rng.standard_normal(n))
        low = np.fft.irfft(spectrum * (f < 2500), n)
        high = np.fft.irfft(spectrum * (f >= 2500), n)
        ir[:, c] = (low * 10 ** (-3 * t / seconds) + 0.6 * high * 10 ** (-3 * t / (0.45 * seconds))) * np.minimum(1, t / 0.02)
        for delay, gain in [(0.011, 0.5), (0.017, 0.35), (0.023, 0.3), (0.031, 0.25), (0.043, 0.2)]:
            ir[int((delay + 0.002 * c) * SR), c] += gain * (1 if (c + int(delay * 1000)) % 2 else -1)
    return ir / np.sqrt((ir**2).sum(0)).max()


def circular(x, response):
    """`x` (a loop) times `response` (per rfft bin), round the circle."""
    return np.fft.irfft(np.fft.rfft(x, axis=0) * response[:, None], len(x), axis=0)


def reverb(loop, wet):
    n = len(loop)
    ir = room_ir()
    out = np.zeros_like(loop)
    for c in range(2):
        out[:, c] = np.fft.irfft(np.fft.rfft(loop[:, c], n) * np.fft.rfft(ir[:, c], n), n)
    return loop + wet * out


def master(loop):
    """A low cut under 60 Hz and a soft roll-off above 9 kHz."""
    f = np.fft.rfftfreq(len(loop), 1 / SR)
    return circular(loop, 1 / np.sqrt(1 + (f / 9000) ** 4) / np.sqrt(1 + (60 / np.maximum(f, 1)) ** 4))


def tunes():
    """The tunes of the arrangement, by name: each says its stems, its
    reverb and the files it makes (`loop`, `once`)."""
    return arrangements()["music"]


def stems(tune):
    """The stem scores of `tune`, in the arrangement's order."""
    return list(tunes()[tune]["stems"])


def _render(tune, sheets, times, seconds):
    """`tune`'s stems played `times` through on the bank: (frames × 2,
    frames a time through, seconds a tick)."""
    music = tunes()[tune]
    plan = list(music["stems"].values())
    first = sheets[0]
    for sheet, entries in zip(sheets, plan):
        if (sheet["tempo"], sheet["length"], sheet["beatsPerBar"]) != (first["tempo"], first["length"], first["beatsPerBar"]):
            raise SystemExit(f"{sheet['title']}: the stems differ in tempo, length or metre")
        if len(entries) != len(sheet["tracks"]):
            raise SystemExit(f"{sheet['title']}: {len(sheet['tracks'])} tracks, {len(entries)} in the arrangement")
        for track, entry in zip(sheet["tracks"], entries):
            if "program" not in entry:
                continue
            silent = chamber_bank.unplayable(entry["program"], [n["pitch"] + entry.get("transpose", 0) for n in track["notes"]])
            if silent:
                raise SystemExit(
                    f"{sheet['title']}: {entry['name']} plays MIDI {silent}, which the chamber bank's program "
                    f"{entry['program']} has no recording for (sampled/chamber.json keys): it would be silent"
                )
    seconds_per_tick = 60 / first["tempo"] / TPB
    n = round(first["length"] * seconds_per_tick * SR)
    if n % 64:
        raise SystemExit(f"{tune}: {n} frames is not whole 64-frame packets")
    with tempfile.TemporaryDirectory() as tmp:
        mid, raw = os.path.join(tmp, "music.mid"), os.path.join(tmp, "music.f32")
        with open(mid, "wb") as out:
            out.write(midi_file(sheets, plan, stems(tune), times=times, phrase_bars=music.get("phraseBars", 4)))
        if not os.path.isdir(os.path.join(SAMPLED, "node_modules")):
            subprocess.run(["npm", "ci", "--silent", "--no-audit", "--no-fund"], cwd=SAMPLED, check=True)
        subprocess.run(
            ["node", os.path.join(SAMPLED, "render.mjs"), mid, raw, str(seconds(n)), *(BANKS or bank_paths())],
            cwd=SAMPLED,
            check=True,
        )
        rendered = np.fromfile(raw, dtype="<f4").reshape(-1, 2).astype(np.float64)
    return rendered, n, seconds_per_tick


def _synth_tracks(out, tune, sheets, seconds_per_tick, synth_voice, wrap):
    """Adds the tracks the arrangement leaves to the synth to `out`, round
    the circle of `wrap` frames, or cut at `out`'s end when `wrap` is None."""
    for sheet, entries in zip(sheets, tunes()[tune]["stems"].values()):
        for track, entry in zip(sheet["tracks"], entries):
            if "synth" not in entry:
                continue
            for note in track["notes"]:
                sound = synth_voice(entry["synth"]) * note["velocity"] / 127 * entry["level"]
                at = round(note["start"] * seconds_per_tick * SR) + np.arange(len(sound))
                if wrap:
                    at %= wrap
                else:
                    sound, at = sound[at < len(out)], at[at < len(out)]
                out[at, 0] += sound
                out[at, 1] += sound


def sampled_loop(tune, sheets, synth_voice):
    """The loop of `tune` from its stem scores `sheets` (in the order of
    `stems(tune)`), as frames × 2, unlevelled. `synth_voice(name)` gives
    the synth's own sound for a track the arrangement leaves to it (the
    rail joint)."""
    rendered, n, seconds_per_tick = _render(tune, sheets, 2, lambda n: 2 * n / SR + TAIL)
    # The second time round already rings with the first one's tails, as
    # every later time round would: it is the loop as it is heard.
    loop = rendered[n : 2 * n].copy()
    _synth_tracks(loop, tune, sheets, seconds_per_tick, synth_voice, wrap=n)
    return master(reverb(loop, tunes()[tune]["reverb"]))


def sampled_once(tune, sheets, synth_voice):
    """`tune` played once through from silence, its last notes and the
    room ringing on `RING` seconds after the last bar, the last
    `RING_FADE` eased to nothing; frames × 2, unlevelled, with the frames
    of the one time through (for its loudness)."""
    rendered, n, seconds_per_tick = _render(tune, sheets, 1, lambda n: n / SR + TAIL)
    # The reverb and the master go round a circle with seconds of silence
    # in it, longer than the room rings, so nothing comes round.
    once = rendered[: n + round(TAIL * SR)].copy()
    _synth_tracks(once, tune, sheets, seconds_per_tick, synth_voice, wrap=None)
    once = master(reverb(once, tunes()[tune]["reverb"]))[: n + round(RING * SR)]
    fade = round(RING_FADE * SR)
    once[-fade:] *= (0.5 + 0.5 * np.cos(np.pi * np.arange(1, fade + 1) / fade))[:, None]
    return once, n


def limit(loop, gain, ceiling):
    """A peak limiter for a loop that will be scaled by `gain`: wherever
    `gain` × the loop would pass `ceiling`, the loop is turned down just
    enough, the turn-down eased over about 10 ms either side (a window
    minimum, then a moving average half its width, so the eased gain is
    never above what the peak needs), round the circle. Coinciding attacks
    of sampled instruments (a chord, a bell and a bass on one beat) peak
    far above the music's loudness; this is a mastering limiter's job."""
    need = np.minimum(1.0, ceiling / gain / np.maximum(np.abs(loop).max(axis=1), 1e-12))
    low = need.copy()
    shift = 1
    while shift <= 512:
        low = np.minimum(low, np.minimum(np.roll(low, shift), np.roll(low, -shift)))
        shift *= 2
    width = 480
    total = np.concatenate([[0.0], np.cumsum(np.concatenate([low[-width // 2 :], low, low[: width // 2]]))])
    eased = (total[width:] - total[:-width])[: len(low)] / width
    return loop * np.minimum(eased, need)[:, None]
