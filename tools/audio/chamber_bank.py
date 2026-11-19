"""The chamber bank (THEME-PLAIN item 1, decision 815's later note).

Builds a SoundFont from recorded samples of a concert grand (Salamander
Grand Piano V3, CC BY 3.0) and a chamber string section and harp (VS
Chamber Orchestra: Community Edition, CC0), as `sampled/chamber.json`
says. The music's renderer plays it in front of GeneralUser GS: its
programs (piano, pizzicato, slow strings, harp) take the place of the
General MIDI bank's, and every other program (celesta, tubular bells, the
jingle bell) still comes from GeneralUser GS.

GeneralUser GS plays one looped piano sample at about 31 kHz for every
velocity, a pizzicato sampled four times across five octaves at 22 kHz,
and a harp at 22 kHz; the Salamander grand has sixteen velocity layers
every minor third at 48 kHz, ringing out unlooped, and the string section
is sampled every two or three semitones at 44.1 kHz in two dynamics.

Every file is fetched from its source at the pinned commit into a cache
outside the repository and checked against `sampled/chamber-files.json`
(SHA-256); the bank is built into the same cache and checked against
`chamber.json`'s `sha256`. Like the bank and the renderer, it is a tool:
it makes the audio files and is not in the app.

    python3 tools/audio/chamber_bank.py            # build (or find) the bank, print its path
    python3 tools/audio/chamber_bank.py --lock     # after changing the sources: record the
                                                   # files' and the bank's SHA-256
"""

import concurrent.futures
import hashlib
import io
import json
import os
import re
import struct
import subprocess
import sys
import urllib.parse
import urllib.request
import wave
import zlib

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
SAMPLED = os.path.join(HERE, "sampled")
SPEC = os.path.join(SAMPLED, "chamber.json")
LOCK = os.path.join(SAMPLED, "chamber-files.json")
CACHE = os.path.join(os.path.expanduser("~"), ".cache", "railway-game-ios", "chamber")
# Decibels below a sample's peak where an unlooped sample is cut (after a
# short fade): the room's reverb and the master cover what is left.
TAIL_DB = -66
TAIL_FADE = 0.25
# The longest an unlooped sample is kept, seconds (the music's longest
# piano note with its pedal and release is under four).
LONGEST = 8.0
# A sustained sample's loop: its length at most, its crossfade.
LOOP_SECONDS = 4.0
LOOP_FADE = 0.25
# SpessaSynth multiplies initialAttenuation by 0.4 (the E-mu correction).
EMU = 0.4


def load(path):
    with open(path, encoding="utf-8") as file:
        return json.load(file)


def spec():
    return load(SPEC)


def keys(program):
    """The keys the chamber bank's preset `program` has recordings for,
    as (lowest, highest) per part, or None when the bank has no such
    preset (GeneralUser GS plays it). A preset of this bank takes the
    place of GeneralUser GS's whole program, so a key outside these
    plays nothing at all (decision 883's later note: melody 2's C7)."""
    for preset in spec()["presets"]:
        if preset["program"] == program:
            return [tuple(part["keys"]) for part in preset["parts"]]
    return None


def unplayable(program, pitches):
    """Those of `pitches` the chamber bank's `program` would leave silent."""
    ranges = keys(program)
    if ranges is None:
        return []
    return sorted({p for p in pitches if not any(lo <= p <= hi for lo, hi in ranges)})


def fetch(name, source, path, lock, record):
    """The bytes of `path` in `source` at its commit, from the cache or
    downloaded once; checked against the lock (or recorded in it)."""
    local = os.path.join(CACHE, name, source["commit"], path)
    if not os.path.exists(local):
        os.makedirs(os.path.dirname(local), exist_ok=True)
        raw = source["repository"].replace("https://github.com/", "https://raw.githubusercontent.com/")
        url = f"{raw}/{source['commit']}/" + urllib.parse.quote(path)
        with urllib.request.urlopen(url) as response:
            data = response.read()
        with open(local + ".part", "wb") as out:
            out.write(data)
        os.replace(local + ".part", local)
    with open(local, "rb") as file:
        data = file.read()
    digest = hashlib.sha256(data).hexdigest()
    if record is not None:
        record.setdefault(name, {})[path] = digest
    else:
        want = lock.get(name, {}).get(path)
        if want is None:
            raise SystemExit(f"{name}/{path}: not in {os.path.basename(LOCK)} (run with --lock)")
        if digest != want:
            raise SystemExit(f"{name}/{path}: SHA-256 {digest}, not the pinned {want}")
    return data


# --- Reading the sampler files -------------------------------------------

def _opcodes(text):
    return dict(re.findall(r"([A-Za-z_][A-Za-z0-9_]*)=(\S+)", text))


def sfz_regions(text, default_path=""):
    """The regions of a plain SFZ file (no #include): each the opcodes of
    its <global>, <group> and <region>. Of round-robin groups
    (`seq_position`, `lorand`), only the first is kept: a SoundFont has no
    round robin."""
    text = re.sub(r"//[^\n]*", "", text)
    path = default_path
    control = re.search(r"default_path=([^\n<]+)", text)
    if control:
        path = control.group(1).strip().replace("\\", "/")
    regions, scope, group, glob = [], None, {}, {}
    for header, body in re.findall(r"<(\w+)>([^<]*)", text):
        ops = _opcodes(body.replace("default_path=", "x_default_path="))
        if header == "global":
            glob = ops
        elif header == "group":
            group = ops
        elif header == "region":
            if group.get("seq_position", "1") != "1" or float(group.get("lorand", "0")) > 0:
                continue
            merged = {**glob, **group, **ops}
            merged["sample"] = path + merged["sample"].replace("\\", "/")
            regions.append(merged)
    return regions


def salamander_regions(name, source, base, lock, record):
    """The Salamander layout: the note regions of `region.txt` (its first
    25: the ones played from a key, not the release noises) in each
    velocity group of `notes.txt`."""
    read = lambda p: fetch(name, source, f"{base}/{p}", lock, record).decode()
    rows = re.findall(r"<region>[^\n]*lokey=(\d+) hikey=(\d+) pitch_keycenter=(\d+) sample=(\w#?\d)\$VEL", read("region.txt"))
    regions = []
    for vel, lo, hi in re.findall(r'#include "Data/(vel_\d+)\.txt" lovel=(\d+) hivel=(\d+)', read("notes.txt")):
        tag = re.search(r"#define \$VEL (\w+)", read(f"{vel}.txt")).group(1)
        ampeg = {}
        for lokey, hikey, center, note in rows:
            regions.append(
                {
                    "sample": f"Samples/{note}{tag}.flac",
                    "lokey": lokey, "hikey": hikey, "pitch_keycenter": center,
                    "lovel": lo, "hivel": hi, **ampeg,
                }
            )
    return regions


def part_regions(name, source, part, lock, record):
    if "salamander" in part:
        regions = salamander_regions(name, source, part["salamander"], lock, record)
    else:
        regions = sfz_regions(fetch(name, source, part["sfz"], lock, record).decode("utf-8", "replace"))
    lo, hi = part["keys"]
    kept = []
    for region in regions:
        a, b = max(int(region["lokey"]), lo), min(int(region["hikey"]), hi)
        if a <= b:
            kept.append({**region, "lokey": a, "hikey": b})
    if not kept:
        raise SystemExit(f"{part}: no region in keys {lo}–{hi}")
    # The part's lowest and highest regions reach its bounds.
    low, high = min(r["lokey"] for r in kept), max(r["hikey"] for r in kept)
    for region in kept:
        region["lokey"] = lo if region["lokey"] == low else region["lokey"]
        region["hikey"] = hi if region["hikey"] == high else region["hikey"]
    return kept


# --- Samples ---------------------------------------------------------------

def decode(data):
    """(rate, frames × channels float64) of an audio file's bytes."""
    out = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", "pipe:0", "-acodec", "pcm_s32le", "-f", "wav", "pipe:1"],
        input=data, capture_output=True, check=True,
    ).stdout
    # ffmpeg writes an unknown length into a piped WAV header; read it raw.
    with wave.open(io.BytesIO(out)) as w:
        rate, channels = w.getframerate(), w.getnchannels()
    start = out.index(b"data") + 8
    pcm = np.frombuffer(out[start : start + (len(out) - start) // (4 * channels) * 4 * channels], dtype="<i4")
    return rate, pcm.reshape(-1, channels).astype(np.float64) / 2**31


def image(x, part):
    """The part's stereo image: `mic` keeps one microphone of a stereo
    pair (mono), `width` scales the side signal (1 keeps it)."""
    if "mic" in part:
        x = x[:, [{"left": 0, "right": 1}[part["mic"]]]]
    if x.shape[1] == 2 and "width" in part:
        mid, side = x.mean(axis=1), (x[:, 0] - x[:, 1]) / 2 * part["width"]
        return np.stack([mid + side, mid - side], axis=1)
    return x


def presence(x, rate, part):
    """The part's `presence` bell, [Hz, dB, octaves wide (standard
    deviation)], applied to the whole sample (zero phase)."""
    if "presence" not in part:
        return x
    centre, decibels, width = part["presence"]
    f = np.fft.rfftfreq(len(x), 1 / rate)
    bell = np.exp(-0.5 * (np.log2(np.maximum(f, 1) / centre) / width) ** 2)
    gain = 10 ** (decibels * bell / 20)
    return np.fft.irfft(np.fft.rfft(x, axis=0) * gain[:, None], len(x), axis=0)


def ring_out(x, rate):
    """An unlooped sample cut where it has faded `TAIL_DB` below its peak
    (at most `LONGEST` seconds), the last `TAIL_FADE` eased out."""
    level = np.abs(x).max(axis=1)
    loud = np.nonzero(level > level.max() * 10 ** (TAIL_DB / 20))[0]
    end = min(len(x), loud[-1] + 1 if len(loud) else len(x), int(LONGEST * rate))
    x = x[:end].copy()
    fade = min(int(TAIL_FADE * rate), end // 2)
    x[end - fade :] *= (0.5 + 0.5 * np.cos(np.pi * np.arange(1, fade + 1) / fade))[:, None]
    return x, None


def sustain_loop(x, rate):
    """A sustained sample with a loop in its steady part: at most
    `LOOP_SECONDS` long, ending before the bow lifts, its start moved
    (±20 ms) to where the wave best matches its end, and the last
    `LOOP_FADE` before its end crossfaded (equal power) into what comes
    before its start, so it goes round without a click. Gives (samples,
    (loop start, loop end))."""
    mono = x.mean(axis=1)
    hop = int(0.05 * rate)
    env = np.sqrt(np.convolve(mono**2, np.ones(hop) / hop, mode="same"))
    plateau = np.median(env[env > 0.3 * env.max()])
    steady = np.nonzero(env >= 0.8 * plateau)[0]
    first, last = steady[0] + int(0.3 * rate), steady[-1] - int(0.3 * rate)
    if last - first < int(1.0 * rate):
        first, last = steady[0], steady[-1]
    end = last
    start = max(first, end - int(LOOP_SECONDS * rate))
    window, reach = int(0.01 * rate), int(0.02 * rate)
    target = mono[end - window : end + window]
    best, best_score = start, -np.inf
    for s in range(max(window + int(LOOP_FADE * rate), start - reach), min(end - int(rate), start + reach)):
        here = mono[s - window : s + window]
        score = float(np.dot(here, target)) / (np.linalg.norm(here) * np.linalg.norm(target) + 1e-12)
        if score > best_score:
            best, best_score = s, score
    start = best
    fade = min(int(LOOP_FADE * rate), (end - start) // 3)
    t = np.arange(fade) / fade
    out = x[: end + 64].copy()
    out[end - fade : end] = (
        np.cos(np.pi / 2 * t)[:, None] * x[end - fade : end] + np.sin(np.pi / 2 * t)[:, None] * x[start - fade : start]
    )
    # What follows the loop's end is its start, for the interpolator.
    out[end : end + 64] = out[start : start + 64]
    return out, (start, end)


def loudness(x, rate, seconds):
    """Decibels (RMS) of the first `seconds` after a sample's onset."""
    mono = np.abs(x).mean(axis=1)
    onset = int(np.argmax(mono > 0.05 * mono.max()))
    part = x[onset : onset + int(seconds * rate)]
    return 10 * np.log10((part**2).mean() + 1e-20)


def evening(preset, regions, cooked):
    """Decibels each sample of an `even` part is raised by so that every
    sample of one velocity layer is as loud as the layer's median: the
    sections were recorded note by note, some notes plucked or bowed
    louder than their neighbours (up to 10 dB), and a line played across
    them would jump."""
    out = {}
    for part in preset["parts"]:
        if not part.get("even"):
            continue
        layers = {}
        for p, name, region in regions:
            if p is part:
                layers.setdefault(region.get("hivel", "127"), set()).add((name, region["sample"]))
        for files in layers.values():
            level = {f: loudness(cooked[f][1], cooked[f][0], part["even"]) for f in files}
            middle = float(np.median(list(level.values())))
            for f, value in level.items():
                out[f] = out.get(f, 0.0) + middle - value
    return out


def to_int16(x, seed):
    """Floats in −1…1 to 16-bit with triangular dither (fixed seed)."""
    rng = np.random.default_rng(seed)
    noise = rng.random(x.shape) - rng.random(x.shape)
    return np.clip(np.round(x * 32767 + noise), -32768, 32767).astype("<i2")


# --- Writing the SoundFont -------------------------------------------------

def _chunk(tag, data):
    return tag + struct.pack("<I", len(data)) + data + (b"\0" if len(data) % 2 else b"")


def _list(tag, chunks):
    body = tag + b"".join(chunks)
    return b"LIST" + struct.pack("<I", len(body)) + body


def _name(text):
    return text.encode("ascii", "replace")[:19].ljust(20, b"\0")


def timecents(seconds):
    return int(round(1200 * np.log2(max(seconds, 0.001))))


def write_sf2(name, comment, presets, samples):
    """`presets`: (program, name, zones), each zone a dict of generators
    (keyRange and velRange as (lo, hi), sampleID last) and its modulators;
    `samples`: (name, int16 data, rate, root, loop, type, link)."""
    smpl, shdr = b"", b""
    offset = 0
    for sname, data, rate, root, loop, kind, link in samples:
        start, end = offset, offset + len(data)
        loop_start, loop_end = (start + loop[0], start + loop[1]) if loop else (start, end)
        shdr += _name(sname) + struct.pack("<IIIIIBbHH", start, end, loop_start, loop_end, rate, root, 0, link, kind)
        smpl += data.tobytes() + b"\0" * 92  # 46 zero samples after each one
        offset = end + 46
    shdr += _name("EOS") + b"\0" * 26
    phdr = pbag = pgen = inst = ibag = igen = imod = b""
    pmod = b"\0" * 10
    bag_gen = bag_mod = ibag_gen = ibag_mod = 0
    for index, (program, pname, zones) in enumerate(presets):
        phdr += _name(pname) + struct.pack("<HHHIII", program, 0, index, 0, 0, 0)
        pbag += struct.pack("<HH", bag_gen, 0)
        pgen += struct.pack("<HBB", 43, 0, 127) + struct.pack("<HH", 41, index)
        bag_gen += 2
        inst += _name(pname) + struct.pack("<H", len(ibag) // 4)
        for zone in zones:
            ibag += struct.pack("<HH", ibag_gen, ibag_mod)
            for oper, value in zone["gens"]:
                if oper in (43, 44):
                    igen += struct.pack("<HBB", oper, value[0], value[1])
                elif oper in (53, 54, 58):
                    igen += struct.pack("<HH", oper, value)
                else:
                    igen += struct.pack("<Hh", oper, value)
                ibag_gen += 1
            for mod in zone["mods"]:
                imod += struct.pack("<HHhHH", *mod)
                ibag_mod += 1
    phdr += _name("EOP") + struct.pack("<HHHIII", 0, 0, len(presets), 0, 0, 0)
    pbag += struct.pack("<HH", bag_gen, 0)
    pgen += b"\0" * 4
    inst += _name("EOI") + struct.pack("<H", len(ibag) // 4)
    ibag += struct.pack("<HH", ibag_gen, ibag_mod)
    igen += b"\0" * 4
    imod += b"\0" * 10
    info = _list(b"INFO", [
        _chunk(b"ifil", struct.pack("<HH", 2, 1)),
        _chunk(b"isng", b"EMU8000\0"),
        _chunk(b"INAM", name.encode() + b"\0"),
        _chunk(b"ICMT", comment.encode("ascii", "replace") + b"\0"),
    ])
    sdta = _list(b"sdta", [_chunk(b"smpl", smpl)])
    pdta = _list(b"pdta", [
        _chunk(b"phdr", phdr), _chunk(b"pbag", pbag), _chunk(b"pmod", pmod), _chunk(b"pgen", pgen),
        _chunk(b"inst", inst), _chunk(b"ibag", ibag), _chunk(b"imod", imod), _chunk(b"igen", igen),
        _chunk(b"shdr", shdr),
    ])
    body = b"sfbk" + info + sdta + pdta
    return b"RIFF" + struct.pack("<I", len(body)) + body


# --- The bank --------------------------------------------------------------

def build(record=None):
    """The bank's bytes. With `record` (a dict), the files' SHA-256 are
    recorded in it instead of checked."""
    bank = spec()
    lock = {} if record is not None else load(LOCK)
    sources = bank["sources"]
    presets, samples = [], []
    for preset in bank["presets"]:
        regions = []
        for part in preset["parts"]:
            name = part["source"]
            for region in part_regions(name, sources[name], part, lock, record):
                regions.append((part, name, region))
        files = sorted({(name, region["sample"]) for _, name, region in regions})
        with concurrent.futures.ThreadPoolExecutor(8) as pool:
            datas = list(pool.map(lambda f: fetch(f[0], sources[f[0]], f[1], lock, record), files))
        cooked = {}
        for (name, path), data in zip(files, datas):
            rate, x = decode(data)
            part = next(p for p, n, r in regions if (n, r["sample"]) == (name, path))
            x = presence(image(x, part), rate, part)
            looped = part.get("loop", False)
            cooked[(name, path)] = (rate, *(sustain_loop(x, rate) if looped else ring_out(x, rate)))
        # Each sample is stored at full scale (the most of 16 bits); how
        # much it was raised goes into its zones' attenuation, so the
        # recordings keep their own balance.
        ids, raised = {}, {}
        evened = evening(preset, regions, cooked)
        for (name, path), (rate, x, loop) in cooked.items():
            seed = zlib.crc32(f"{name}/{path}".encode())
            scale = 0.95 / np.abs(x).max()
            raised[(name, path)] = 20 * np.log10(scale) - evened.get((name, path), 0.0)
            channels = [to_int16(x[:, c] * scale, seed + c) for c in range(x.shape[1])]
            first = len(samples)
            base = f"{preset['program']:02d}-{len(ids):03d}"
            if len(channels) == 1:
                samples.append((base, channels[0], rate, 60, loop, 1, 0))
            else:
                samples.append((base + "L", channels[0], rate, 60, loop, 4, first + 1))
                samples.append((base + "R", channels[1], rate, 60, loop, 2, first))
            ids[(name, path)] = (first, len(channels))
        level = lambda part, name, region: float(region.get("volume", 0)) + part.get("gain", 0) - raised[(name, region["sample"])]
        loudest = max(level(*item) for item in regions)
        zones = []
        mods = []
        if "velocity" in preset:
            # Velocity → attenuation, negative concave unipolar: replaces the default 960.
            mods.append((0x0502, 48, preset["velocity"], 0, 0))
        for part, name, region in sorted(regions, key=lambda item: (item[2]["lokey"], int(item[2].get("lovel", 0)))):
            first, count = ids[(name, region["sample"])]
            decibels = loudest - level(part, name, region)
            release = preset.get("release", float(region.get("ampeg_release", 0.5)))
            loop = cooked[(name, region["sample"])][2]
            for channel in range(count):
                gens = [
                    (43, (region["lokey"], region["hikey"])),
                    (44, (int(region.get("lovel", 0)), int(region.get("hivel", 127)))),
                    (48, int(round(decibels * 10 / EMU))),
                    (38, timecents(release)),
                ]
                if preset.get("attack"):
                    gens.append((34, timecents(preset["attack"])))
                if count == 2:
                    gens.append((17, -500 if channel == 0 else 500))
                if "tune" in region:
                    gens.append((52, int(region["tune"])))
                gens += [(54, 1 if loop else 0), (58, int(region["pitch_keycenter"])), (53, first + channel)]
                zones.append({"gens": gens, "mods": mods})
        presets.append((preset["program"], preset["name"], zones))
    credits = "; ".join(s["credit"] for s in sources.values())
    return write_sf2(bank["name"], f"Built by railway game ios tools/audio/chamber_bank.py from: {credits}", presets, samples)


def bank_path():
    """The built bank, built once into the cache, its SHA-256 checked."""
    want = spec()["sha256"]
    path = os.path.join(CACHE, f"railway-chamber-{want[:16]}.sf2")
    if not os.path.exists(path):
        data = build()
        digest = hashlib.sha256(data).hexdigest()
        if digest != want:
            raise SystemExit(f"the chamber bank built to SHA-256 {digest}, not the pinned {want}")
        os.makedirs(CACHE, exist_ok=True)
        with open(path + ".part", "wb") as out:
            out.write(data)
        os.replace(path + ".part", path)
    return path


def main():
    if "--lock" in sys.argv[1:]:
        record = {}
        data = build(record)
        with open(LOCK, "w", encoding="utf-8") as out:
            json.dump({k: dict(sorted(v.items())) for k, v in sorted(record.items())}, out, indent=1, ensure_ascii=False)
            out.write("\n")
        text = open(SPEC, encoding="utf-8").read()
        digest = hashlib.sha256(data).hexdigest()
        text = re.sub(r'"sha256": "[0-9a-f]*"', f'"sha256": "{digest}"', text, count=1)
        open(SPEC, "w", encoding="utf-8").write(text)
        print(f"{len(data) / 1e6:.1f} MB, SHA-256 {digest}")
    print(bank_path())


if __name__ == "__main__":
    main()
