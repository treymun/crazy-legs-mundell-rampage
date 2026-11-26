"""Measure every finished cue and song and say what is wrong with them. Free.

    python scripts/audio_qa.py                 # measure, print the findings
    python scripts/audio_qa.py --check         # exit 1 on any finding not in audio_src/qa_allow.json
    python scripts/audio_qa.py --json out.json # also write every measurement
    python scripts/audio_qa.py --no-music      # effects only (no ffmpeg needed)

Nobody on the agent side can listen, so the bank is held by measurement:

- Levels: EBU R128 integrated loudness (LUFS, K-weighted, gated; cues under
  0.4 s get the K-weighted level of the whole cue), true peak (4x
  oversampled), the loudest 50 ms (the level audio_build.py masters to). Each
  cue is compared with the median of its group: its family, or for a spoken
  line its voice and speaker box.
- Defects: clipping, DC offset, a click at either end (the first or last
  sample far from zero), silence before the sound or after it, a loop whose
  end does not run into its start (the step and the level across the join),
  a take cut off while still sounding, two takes of a set that are the same
  recording.
- Wiring: every cue the game names in a literal (`play("x")`, `sting("x")`,
  `play_voice("x")`, `set_bed(.., "x")`, VARIANTS) made; every cue found
  somewhere in the game's code or data.

A finding the owner has accepted (a cue that is quiet on purpose, a spiky
cue) goes in audio_src/qa_allow.json with the reason; --check fails on any
other. Reads audio_src/final/sfx (what the game packs), godot/assets/music
(ffmpeg for the Vorbis songs) and scripts/audio_spec.py; writes nothing but
the --json report.
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import audio_spec as spec  # noqa: E402
from audio_build import CHAIN, spoken  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
FINAL = ROOT / "audio_src" / "final" / "sfx"
MUSIC = ROOT / "godot" / "assets" / "music"
ALLOW = ROOT / "audio_src" / "qa_allow.json"
GAME = ROOT / "godot"
RATE = 22050

# Families that loop in game (audio_build.py CHAIN `loop`).
LOOPS = {"ambience", "weather", "near", "loop_tool", "jukebox"}
# Families whose hit must land at once (audio_build.py SYNC).
SYNC = {"report", "boom", "attack", "melee", "impact", "reload", "equip", "dry", "pickup",
        "foot", "ui", "scene", "station"}

# Thresholds. A cue more than OUTLIER_DB off its group's median loudness is an
# outlier; the rest are defects.
OUTLIER_DB = 5.0
VOICE_OUTLIER_LU = 4.0          # spoken lines in one voice and box, by LUFS
CLIP = .999                     # a sample at full scale
# Cues peak at -0.8 dB a sample; between samples a little more. The game plays
# an effect at most at .82 (-1.7 dB) into a -0.8 dB limiter, so only a cue
# past this would press that limiter on its own.
TRUE_PEAK_DB = 1.5
DC_SHARE = .03                  # mean as a share of RMS
EDGE_DB = -36.0                 # first / last sample against the cue's peak: a click
LEAD_S = .06                    # silence before a sync cue's sound
LEAD_VOICE_S = .25              # before a spoken line's first word
TRAIL_S = .55                   # silence after the sound (audio_build trims past .42)
SEAM_STEP = 4.0                 # loop join step against the loop's 99.9th percentile step
SEAM_LEVEL_DB = .5              # loop: last 100 ms against the first, over the largest change inside
CUT_HOT_DB = -14.0              # the 30 ms before the end fade, against the loudest 50 ms ...
SHORT_FADE_S = .06              # ... when that fade is this short or shorter
SAME_TAKE = .97                 # normalised cross-correlation of two takes of a set
MUSIC_LUFS = (-16.0, -14.0)     # every song is mastered to -15
LAYER_LU = 1.0                  # a fight loop's layer (pass 15) off its own level
MUSIC_TP = -0.8


# ------------------------------------------------------------------ reading

def read_wav(path: Path) -> np.ndarray:
    with wave.open(str(path), "rb") as pcm:
        if pcm.getframerate() != RATE or pcm.getsampwidth() != 2:
            raise ValueError(f"{path.name}: {pcm.getframerate()} Hz, {pcm.getsampwidth() * 8} bit")
        data = np.frombuffer(pcm.readframes(pcm.getnframes()), "<i2").astype(np.float64) / 32768
        if pcm.getnchannels() == 2:
            data = data.reshape(-1, 2).mean(1)
    return data


def read_song(path: Path, rate: int = 22050) -> np.ndarray:
    """A song as mono samples (for its ends and its loop join)."""
    raw = subprocess.run([shutil.which("ffmpeg"), "-v", "error", "-i", str(path), "-ac", "1", "-ar", str(rate),
                          "-f", "f32le", "-"], check=True, capture_output=True).stdout
    return np.frombuffer(raw, "<f4").astype(np.float64)


def ebur128(path: Path) -> dict:
    """ffmpeg's own R128 meter: integrated loudness and true peak of a song."""
    log = subprocess.run([shutil.which("ffmpeg"), "-hide_banner", "-nostats", "-i", str(path), "-af",
                          "ebur128=peak=true", "-f", "null", "-"], capture_output=True, check=True).stderr.decode(
                              "utf-8", "replace")
    tail = log[log.rindex("Summary"):]
    grab = lambda key: float(tail.split(key)[1].split()[0])  # noqa: E731
    return {"lufs": grab("I:"), "true_peak_db": grab("Peak:")}


# --------------------------------------------------------------- measuring

def db(v: float) -> float:
    return float(20 * np.log10(max(float(v), 1e-12)))


def envelope(x: np.ndarray, rate: int, window: float) -> np.ndarray:
    """RMS over a sliding `window` (centred), by running sums."""
    size = max(1, int(rate * window))
    c = np.concatenate([[0.0], np.cumsum(x * x)])
    lo = np.clip(np.arange(len(x)) - size // 2, 0, len(x))
    hi = np.clip(lo + size, 0, len(x))
    return np.sqrt(np.maximum((c[hi] - c[lo]) / size, 0))


def _biquad(b: tuple, a: tuple, w: np.ndarray) -> np.ndarray:
    z1, z2 = np.exp(-1j * w), np.exp(-2j * w)
    return (b[0] + b[1] * z1 + b[2] * z2) / (a[0] + a[1] * z1 + a[2] * z2)


def k_weight(x: np.ndarray, rate: int) -> np.ndarray:
    """BS.1770 K-weighting (its shelf and high-pass, designed for `rate`),
    applied as the filters' response on a padded FFT: the same power."""
    def shelf() -> tuple:
        g, q, fc = 3.999843853973347, .7071752369554196, 1681.974450955533
        a_ = 10 ** (g / 40)
        w0 = 2 * np.pi * fc / rate
        al = np.sin(w0) / (2 * q)
        c = np.cos(w0)
        return ((a_ * ((a_ + 1) + (a_ - 1) * c + 2 * np.sqrt(a_) * al), -2 * a_ * ((a_ - 1) + (a_ + 1) * c),
                 a_ * ((a_ + 1) + (a_ - 1) * c - 2 * np.sqrt(a_) * al)),
                ((a_ + 1) - (a_ - 1) * c + 2 * np.sqrt(a_) * al, 2 * ((a_ - 1) - (a_ + 1) * c),
                 (a_ + 1) - (a_ - 1) * c - 2 * np.sqrt(a_) * al))

    def highpass() -> tuple:
        q, fc = .5003270373238773, 38.13547087602444
        w0 = 2 * np.pi * fc / rate
        al = np.sin(w0) / (2 * q)
        c = np.cos(w0)
        return (((1 + c) / 2, -(1 + c), (1 + c) / 2), (1 + al, -2 * c, 1 - al))

    size = 1 << int(np.ceil(np.log2(len(x) + rate // 2)))
    spectrum = np.fft.rfft(x, size, axis=0)
    w = 2 * np.pi * np.fft.rfftfreq(size, 1 / rate) / rate
    h = _biquad(*shelf(), w) * _biquad(*highpass(), w)
    if spectrum.ndim == 2:
        h = h[:, None]
    return np.fft.irfft(spectrum * h, size, axis=0)[: len(x)]


def lufs(x: np.ndarray, rate: int) -> float:
    """Integrated loudness (mono or stereo). Under 0.4 s: the whole cue's level."""
    y = k_weight(x, rate)
    power = y * y if y.ndim == 1 else (y * y).sum(1)
    block, hop = int(.4 * rate), int(.1 * rate)
    if len(power) < block:
        return -0.691 + 10 * np.log10(max(float(power.mean()), 1e-12))
    c = np.concatenate([[0.0], np.cumsum(power)])
    starts = np.arange(0, len(power) - block + 1, hop)
    z = (c[starts + block] - c[starts]) / block
    level = -0.691 + 10 * np.log10(np.maximum(z, 1e-12))
    z = z[level > -70]
    if len(z) == 0:
        return -70.0
    rel = -0.691 + 10 * np.log10(z.mean()) - 10
    z = z[-0.691 + 10 * np.log10(z) > rel]
    return float(-0.691 + 10 * np.log10(z.mean()))


def true_peak(x: np.ndarray) -> float:
    n = len(x)
    if n < 4:
        return db(np.abs(x).max() if n else 0)
    spectrum = np.fft.rfft(x, axis=0)
    up = np.fft.irfft(spectrum, n * 4, axis=0) * 4
    return db(max(float(np.abs(up).max()), float(np.abs(x).max())))


def corr(a: np.ndarray, b: np.ndarray) -> float:
    """Peak normalised cross-correlation of two cues (same recording -> ~1)."""
    n = len(a) + len(b)
    size = 1 << int(np.ceil(np.log2(n)))
    c = np.fft.irfft(np.fft.rfft(a, size) * np.conj(np.fft.rfft(b, size)), size)
    return float(np.abs(c).max() / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-12))


def measure(name: str, x: np.ndarray, family: str, entry: dict) -> dict:
    loop = family in LOOPS
    peak = float(np.abs(x).max()) if len(x) else 0.0
    env4 = envelope(x, RATE, .004)
    loud50 = db(envelope(x, RATE, .05).max()) if len(x) else -120.0
    rms = float(np.sqrt(np.mean(x * x))) if len(x) else 0.0
    m = {
        "seconds": round(len(x) / RATE, 3),
        "lufs": round(lufs(x, RATE), 1),
        "loud50_db": round(loud50, 1),
        "peak_db": round(db(peak), 2),
        "true_peak_db": round(true_peak(x), 2),
        "dc": round(abs(float(x.mean())) / max(rms, 1e-9), 4),
        "clipped": int(np.sum(np.abs(x) >= CLIP)),
        "first_db": round(db(abs(x[0])) - db(peak), 1),
        "last_db": round(db(abs(x[-1])) - db(peak), 1),
    }
    above = np.flatnonzero(env4 > peak * 10 ** (-40 / 20))
    m["lead_s"] = round(above[0] / RATE, 3) if len(above) else m["seconds"]
    above = np.flatnonzero(env4 > peak * 10 ** (-50 / 20))
    m["trail_s"] = round((len(x) - above[-1]) / RATE, 3) if len(above) else 0.0
    if loop:
        m.update(seam(x, RATE))
    else:
        # The 30 ms just before the end fade (audio_build fades the last
        # `fade` share of a cue): near full level there, under a short fade,
        # is a take stopped mid-sound.
        n = len(x)
        fade = max(int(.004 * RATE), int(CHAIN.get(family, {}).get("fade", .25) * n))
        seg = x[max(0, n - fade - int(.03 * RATE)):n - fade]
        m["fade_s"] = round(fade / RATE, 3)
        m["before_fade_db"] = round(db(np.sqrt(np.mean(seg ** 2))) - loud50, 1) if len(seg) else -120.0
    return m


def problems(name: str, m: dict, family: str, entry: dict) -> list[str]:
    out = []
    loop = family in LOOPS
    if m["clipped"]:
        out.append(f"clips ({m['clipped']} samples)")
    if m["true_peak_db"] > TRUE_PEAK_DB:
        out.append(f"true peak {m['true_peak_db']} dBTP")
    if m["dc"] > DC_SHARE:
        out.append(f"dc offset {m['dc']}")
    if m["loud50_db"] < -50:
        out.append("silent")
    if loop:
        if m["seam_step"] > SEAM_STEP:
            out.append(f"loop seam step {m['seam_step']}x")
        if abs(m["seam_level_db"]) > m["inside_level_db"] + SEAM_LEVEL_DB:
            out.append(f"loop seam level {m['seam_level_db']:+} dB")
    else:
        if m["first_db"] > EDGE_DB:
            out.append(f"click at start ({m['first_db']} dB)")
        if m["last_db"] > EDGE_DB:
            out.append(f"click at end ({m['last_db']} dB)")
        lead = LEAD_VOICE_S if entry.get("make") == "voice" else LEAD_S
        if (family in SYNC or entry.get("make") == "voice") and m["lead_s"] > lead:
            out.append(f"lead silence {m['lead_s']} s")
        if m["trail_s"] > TRAIL_S:
            out.append(f"trailing silence {m['trail_s']} s")
        # A short cue's fade is short anyway, a warning ends hard on purpose
        # (on the attack) and a CLEAN line may end on its cover ringing out.
        long_enough = m["seconds"] >= .4 and family != "warn" and not name.endswith("_clean")
        if long_enough and m["before_fade_db"] > CUT_HOT_DB and m["fade_s"] < SHORT_FADE_S:
            out.append(f"cut while sounding ({m['before_fade_db']} dB before the fade)")
        if entry.get("make") == "voice":
            # The caption's words, from the line's transcript: the cue must hold
            # all of them.
            found = spoken(name, entry.get("heard", entry.get("text", "")))
            if isinstance(found, tuple) and m["seconds"] + .02 < found[1] - found[0]:
                out.append(f"cut before its last word ({m['seconds']} s for {found[1] - found[0]:.2f} s of words)")
    return out


def group_of(name: str, family: str, entry: dict) -> str:
    if entry.get("make") == "voice" or (entry.get("make") == "derive" and entry.get("how") == "bleep"):
        base = entry if entry.get("make") == "voice" else spec.CUES.get(entry["base"], {})
        return f"voice:{base.get('voice', '?')}:{base.get('fx', '') or 'dry'}"
    return f"family:{family}"


# ------------------------------------------------------------------ wiring

LITERAL = re.compile(r'"([a-z][a-z0-9_\-]*)"')
CALL = re.compile(r'\.(?:play|play_at_rate|sting|play_voice|opener_music|set_bed|sound_at|report)\(\s*'
                  r'(?:[A-Za-z_.]+\s*,\s*)?"([a-z][a-z0-9_\-]*)"')


def game_text() -> str:
    parts = []
    for folder, pattern in ((GAME / "src", "*.gd"), (GAME / "data", "*.json"), (GAME / "data", "*.cfg")):
        for path in folder.rglob(pattern):
            parts.append(path.read_text(encoding="utf-8", errors="replace"))
    return "\n".join(parts)


def made_at_run_time() -> set[str]:
    """Assets.MADE_CUES: the cues the game synthesises itself."""
    text = (GAME / "src" / "assets.gd").read_text(encoding="utf-8")
    body = text[text.index("const MADE_CUES"):]
    return set(re.findall(r'"([a-z0-9_]+)"', body[: body.index("]")]))


def wiring(cues: set[str]) -> dict:
    text = game_text()
    literals = set(LITERAL.findall(text))
    called = set(CALL.findall(text))
    words = set(re.findall(r"[a-z][a-z0-9_\-]*", text))
    # Names built at run time: a format string ("bark_%s_%d") or a prefix
    # joined to something ("amb_" + room) covers every cue it can make.
    patterns = []
    for fmt in re.findall(r'"([a-z][a-z0-9_\-]*%[sd][a-z0-9_%\-]*)"', text):
        rx = re.escape(fmt).replace("%s", "[a-z0-9_-]+").replace("%d", "[0-9]+")
        patterns.append(re.compile("^" + rx + "$"))
    for prefix in re.findall(r'"([a-z][a-z0-9_\-]*_)"\s*\+', text):
        patterns.append(re.compile("^" + re.escape(prefix)))
    for suffix in re.findall(r'\+\s*"(_[a-z0-9_\-]+)"', text):
        patterns.append(re.compile(re.escape(suffix) + "$"))
    # The radio's lines are dealt from its data (radio_station.gd _line):
    # <dj_|scan_><group>_<n> for each line of a group.
    radio = json.loads((GAME / "data" / "tuning" / "radio_lines.json").read_text(encoding="utf-8"))
    for section, prefix in (("dj", "dj_"), ("scanner", "scan_")):
        for group, lines in radio.get(section, {}).items():
            if isinstance(lines, list):
                literals.update(f"{prefix}{group}_{n}" for n in range(len(lines)))
    # An enemy's cries with several takes (Enemy.voice_cue, enemies.cfg
    # voice_takes): <voice>_pain_<k> and <voice>_down_<k>, k from 1.
    cfg = (GAME / "data" / "tuning" / "enemies.cfg").read_text(encoding="utf-8")
    takes = re.search(r"^voice_takes=(.*)$", cfg, re.M)
    for voice, count in (json.loads(takes.group(1)) if takes else {}).items():
        literals.update(f"{voice}_{moment}_{k}" for moment in ("pain", "down") for k in range(1, count + 1))
    missing = sorted(c for c in called if c not in cues and not c.endswith("_") and c not in made_at_run_time())
    unused = []
    named = literals | words
    for cue in sorted(cues):
        if cue in named:
            continue
        # One take of a numbered set named means the set is dealt at run time
        # (Enemy.voice_cue: "hick_pain_%d" from a take count in enemies.cfg).
        stem = re.sub(r"_\d+$", "", cue)
        if stem != cue and any(re.fullmatch(re.escape(stem) + r"_\d+", n) for n in named):
            continue
        if any(p.search(cue) for p in patterns):
            continue
        unused.append(cue)
    return {"missing": missing, "unreferenced": unused}


# ------------------------------------------------------------------- songs

def seam(x: np.ndarray, rate: int) -> dict:
    """A loop's join: the sample step across it against the steps inside, and
    the level of its last 100 ms against its first, against the largest such
    change between any two neighbouring 100 ms inside the loop."""
    win = int(.1 * rate)
    steps = np.abs(np.diff(x))
    levels = np.array([db(np.sqrt(np.mean(x[i:i + win] ** 2))) for i in range(0, len(x) - win + 1, win)])
    inside = float(np.abs(np.diff(levels)).max()) if len(levels) > 1 else 0.0
    return {"seam_step": round(abs(float(x[-1] - x[0])) / max(float(np.percentile(steps, 99.9)), 1e-9), 2),
            "seam_level_db": round(db(np.sqrt(np.mean(x[-win:] ** 2))) - db(np.sqrt(np.mean(x[:win] ** 2))), 2),
            "inside_level_db": round(inside, 2)}


def measure_song(path: Path, loops: bool) -> dict:
    x = read_song(path)
    m = {"seconds": round(len(x) / 22050, 2), **ebur128(path),
         "dc": round(abs(float(x.mean())) / max(float(np.sqrt((x * x).mean())), 1e-9), 4)}
    if loops:
        m.update(seam(x, 22050))
    else:
        m["first_db"] = round(db(abs(x[0])) - db(np.abs(x).max()), 1)
        m["last_db"] = round(db(abs(x[-1])) - db(np.abs(x).max()), 1)
    return m


def layer_facts(stem: str) -> dict:
    """A fight loop's layer (audio_spec.LAYERS, pass 15) against its loop: both
    as long to the sample (they play locked together), and the pulse at its
    own level or the loop with its peak layer `sum_lift` LU over the loop."""
    name, loop, kind = next(row for row in spec.LAYERS if row[0] == stem)
    x = read_song(MUSIC / f"{name}.ogg", 44100)
    base = read_song(MUSIC / f"{loop}.ogg", 44100)
    facts = {"layer_of": loop, "samples": len(x), "loop_samples": len(base)}
    if kind == "peak" and len(x) == len(base):
        facts["with_loop_lift_lu"] = round(lufs_of(np.concatenate([x + base] * 2)) - lufs_of(
            np.concatenate([base] * 2)), 2)
    return facts


def lufs_of(mono: np.ndarray) -> float:
    """R128 integrated loudness of mono samples at 44.1 kHz, as both sides."""
    stereo = np.repeat(mono[:, None], 2, 1).astype("<f4")
    log = subprocess.run([shutil.which("ffmpeg"), "-hide_banner", "-nostats", "-f", "f32le", "-ar", "44100",
                          "-ac", "2", "-i", "-", "-af", "ebur128", "-f", "null", "-"],
                         input=stereo.tobytes(), capture_output=True, check=True).stderr.decode("utf-8", "replace")
    tail = log[log.rindex("Summary"):]
    return float(tail.split("I:")[1].split()[0])


def layer_problems(m: dict, stem: str) -> list[str]:
    kind = stem.split("_")[0]
    shape = spec.LAYER_SHAPE[kind]
    out = []
    if m["samples"] != m["loop_samples"]:
        out.append(f"{m['samples']} samples, its loop {m['loop_samples']}")
    if kind == "pulse" and abs(m["lufs"] - shape["lufs"]) > LAYER_LU:
        out.append(f"loudness {m['lufs']} LUFS")
    if kind == "peak" and abs(m.get("with_loop_lift_lu", 99.0) - shape["sum_lift"]) > LAYER_LU:
        out.append(f"with its loop {m.get('with_loop_lift_lu')} LU over it")
    return out


def song_problems(m: dict, loops: bool, layer: bool = False) -> list[str]:
    out = []
    if not layer and not MUSIC_LUFS[0] <= m["lufs"] <= MUSIC_LUFS[1]:
        out.append(f"loudness {m['lufs']} LUFS")
    if m["true_peak_db"] > MUSIC_TP:
        out.append(f"true peak {m['true_peak_db']} dBTP")
    if m["dc"] > DC_SHARE:
        out.append(f"dc offset {m['dc']}")
    if loops:
        if m["seam_step"] > SEAM_STEP:
            out.append(f"loop seam step {m['seam_step']}x")
        if abs(m["seam_level_db"]) > m["inside_level_db"] + SEAM_LEVEL_DB:
            out.append(f"loop seam level {m['seam_level_db']:+} dB")
    else:
        if m["first_db"] > EDGE_DB:
            out.append(f"click at start ({m['first_db']} dB)")
        if m["last_db"] > EDGE_DB:
            out.append(f"click at end ({m['last_db']} dB)")
    return out


# -------------------------------------------------------------------- main

def variant_sets() -> list[list[str]]:
    """The takes Sound.VARIANTS deals in turn, read from sound.gd."""
    text = (GAME / "src" / "sound.gd").read_text(encoding="utf-8")
    body = text[text.index("const VARIANTS"):]
    body = body[: body.index("\n}")]
    out = []
    for row in re.findall(r"\[([^\]]+)\]", body):
        names = list(dict.fromkeys(re.findall(r'"([a-z0-9_]+)"', row)))
        if len(names) > 1:
            out.append(names)
    return out


def run(music: bool) -> dict:
    report: dict = {"cues": {}, "songs": {}, "groups": {}, "findings": {}}
    cues = sorted(p.stem for p in FINAL.glob("*.wav"))
    data: dict[str, np.ndarray] = {}
    for name in cues:
        entry = spec.CUES.get(name, {})
        family = spec.FAMILY.get(name, "?")
        x = read_wav(FINAL / f"{name}.wav")
        data[name] = x
        m = measure(name, x, family, entry)
        m["family"] = family
        m["group"] = group_of(name, family, entry)
        report["cues"][name] = m
        found = problems(name, m, family, entry)
        if name not in spec.CUES:
            found.append("not in audio_spec")
        if found:
            report["findings"][name] = found
    for name in spec.CUES:
        if name not in report["cues"]:
            report["findings"][name] = ["in audio_spec but not built"]
    # Group medians and the cues far off them.
    groups: dict[str, list[str]] = {}
    for name, m in report["cues"].items():
        groups.setdefault(m["group"], []).append(name)
    for group, names in sorted(groups.items()):
        voice = group.startswith("voice:")
        key = "lufs" if voice else "loud50_db"
        values = np.array([report["cues"][n][key] for n in names])
        med = float(np.median(values))
        report["groups"][group] = {"cues": len(names), "median_" + key: round(med, 1),
                                   "median_lufs": round(float(np.median([report["cues"][n]["lufs"] for n in names])), 1),
                                   "spread": round(float(values.max() - values.min()), 1)}
        limit = VOICE_OUTLIER_LU if voice else OUTLIER_DB
        if len(names) < 3:
            continue
        for n in names:
            off = report["cues"][n][key] - med
            if abs(off) > limit:
                report["findings"].setdefault(n, []).append(
                    f"{'loud' if off > 0 else 'quiet'} for {group} ({off:+.1f} {'LU' if voice else 'dB'})")
    # Two takes of a set that are one recording.
    for names in variant_sets():
        names = [n for n in names if n in data]
        for i, a in enumerate(names):
            for b in names[i + 1:]:
                c = corr(data[a], data[b])
                if c > SAME_TAKE:
                    report["findings"].setdefault(b, []).append(f"same take as {a} (correlation {c:.3f})")
    wired = wiring(set(cues))
    report["wiring"] = wired
    for name in wired["missing"]:
        report["findings"].setdefault(name, []).append("named by the game, not made")
    for name in wired["unreferenced"]:
        report["findings"].setdefault(name, []).append("never named by the game")
    if music and shutil.which("ffmpeg"):
        ends = json.loads((MUSIC / "playback_ends.json").read_text(encoding="utf-8"))
        # The fight and boss loops wrap seamlessly; the menu theme loops too,
        # but as a song that ends and starts again (faded both ways).
        loops = {s for s, *_ in spec.FIGHTS + spec.BOSSES}
        layered = {row[0] for row in spec.LAYERS}
        for path in sorted(MUSIC.glob("*.ogg")):
            stem = path.stem
            m = measure_song(path, stem in loops or stem in layered)
            found = song_problems(m, stem in loops or stem in layered, stem in layered)
            if stem in layered:
                m.update(layer_facts(stem))
                found += layer_problems(m, stem)
            report["songs"][stem] = m
            if stem in ends and ends[stem] > m["seconds"] + .01:
                found.append(f"playback end {ends[stem]} s past the song's {m['seconds']} s")
            if found:
                report["findings"]["music/" + stem] = found
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--json", default="")
    parser.add_argument("--no-music", action="store_true")
    args = parser.parse_args()
    report = run(not args.no_music)
    allow = json.loads(ALLOW.read_text(encoding="utf-8")) if ALLOW.is_file() else {}
    allowed = allow.get("allow", {})
    fresh = {}
    for name, found in sorted(report["findings"].items()):
        rules = allowed.get(name, {})
        left = [f for f in found if not any(f.startswith(k) for k in rules)]
        if left:
            fresh[name] = left
    stale = sorted(n for n in allowed if n not in report["findings"] and not n.startswith("music/")
                   or n.startswith("music/") and not args.no_music and n not in report["findings"])
    report["new_findings"] = fresh
    report["stale_allowances"] = stale
    if args.json:
        Path(args.json).write_text(json.dumps(report, indent=1) + "\n", encoding="utf-8")
    print(f"{len(report['cues'])} cues, {len(report['songs'])} songs; "
          f"{len(report['findings'])} with findings, {len(fresh)} not allowed, "
          f"{len(stale)} stale allowances")
    for name, found in fresh.items():
        print(f"  {name}: {'; '.join(found)}")
    for name in stale:
        print(f"  stale allowance (no longer found): {name}")
    if args.check:
        ok = not fresh and not stale
        print("AUDIO QA OK" if ok else "AUDIO QA FAILED")
        raise SystemExit(0 if ok else 1)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
