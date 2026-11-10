"""Finish the game's audio from the stored source recordings. Costs nothing.

    python scripts/audio_build.py            # effects, voices, music, manifest
    python scripts/audio_build.py --sfx      # only the effect bank sources
    python scripts/audio_build.py --music    # only the songs
    python scripts/audio_build.py --check    # validate what is on disk, exit 1 on failure

Reads   audio_src/generated/   raw ElevenLabs recordings (committed)
        audio_src/supplied/    the menu theme supplied by the author
        scripts/audio_spec.py  what every cue is and how it is derived
Writes  audio_src/final/sfx/<cue>.wav     mono 16-bit 22050 Hz, the bank's format
        godot/assets/music/<stem>.ogg     stereo 44.1 kHz Vorbis
        godot/assets/music/playback_ends.json
        audio_src/manifest.json           one record per cue, with measurements

Needs numpy and ffmpeg (ffprobe is not needed). Every step is deterministic:
the same sources give the same files, so a rebuild never needs a paid request.
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import audio_spec as spec  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "audio_src"
GEN = SRC / "generated"
FINAL = SRC / "final" / "sfx"
OLD = ROOT / "assets" / "wav"                 # the cues the mix was tuned around
MUSIC_OUT = ROOT / "godot" / "assets" / "music"
RATE = 22050
MUSIC_LUFS = -15.0

# Finishing chain per family: high-pass, low-pass (Hz), low shelf and presence
# lift (dB), how the tail is faded, and the level used when the game never had
# this cue before. `match` keeps the cue as loud as the one it replaces.
CHAIN = {
    "report":   dict(hp=45, lp=10500, low=1.5, pres=3.5, fade=.35, level=-1.0, drive=1.6),
    "boom":     dict(hp=30, lp=9500, low=4.0, pres=0.0, fade=.4, level=-1.0, drive=1.8),
    "attack":   dict(hp=60, lp=10000, low=1.0, pres=2.0, fade=.3, level=-3.0, drive=1.3),
    "warn":     dict(hp=120, lp=10500, low=0.0, pres=3.5, fade=.08, level=-3.0, drive=1.2),
    "alert":    dict(hp=110, lp=10000, low=0.0, pres=2.5, fade=.2, level=-4.0),
    "death":    dict(hp=80, lp=10000, low=1.0, pres=1.5, fade=.3, level=-4.0),
    "player":   dict(hp=90, lp=10000, low=1.0, pres=2.0, fade=.2, level=-3.0),
    "consume":  dict(hp=100, lp=10000, low=0.0, pres=1.5, fade=.2, level=-7.0),
    "melee":    dict(hp=70, lp=10000, low=1.5, pres=1.5, fade=.25, level=-4.0),
    "impact":   dict(hp=70, lp=10500, low=1.0, pres=2.0, fade=.3, level=-5.0),
    "reload":   dict(hp=140, lp=10500, low=0.0, pres=3.0, fade=.25, level=-8.0),
    "equip":    dict(hp=120, lp=10500, low=0.0, pres=2.5, fade=.25, level=-8.0),
    "dry":      dict(hp=180, lp=10500, low=0.0, pres=3.0, fade=.3, level=-9.0),
    "pickup":   dict(hp=160, lp=10500, low=0.0, pres=2.5, fade=.25, level=-7.0),
    "foot":     dict(hp=90, lp=8500, low=0.5, pres=0.0, fade=.35, level=-12.0),
    "door":     dict(hp=70, lp=9500, low=1.0, pres=1.0, fade=.25, level=-6.0),
    "scene":    dict(hp=70, lp=10500, low=1.0, pres=1.5, fade=.3, level=-4.0),
    "station":  dict(hp=60, lp=10000, low=1.5, pres=1.5, fade=.25, level=-4.0),
    "ambience": dict(hp=50, lp=6800, low=2.0, pres=-2.5, fade=0, level=-22.0, loop=.6),
    "loop_tool": dict(hp=90, lp=10000, low=0.0, pres=1.0, fade=0, level=-8.0, loop=.09),
    "jukebox":  dict(hp=220, lp=4200, low=-3.0, pres=2.0, fade=0, level=-12.0, loop=.4, drive=1.4),
    "distant":  dict(hp=140, lp=3800, low=0.0, pres=-2.0, fade=.3, level=-14.0, fade_in=.04),
    "ui":       dict(hp=200, lp=10500, low=0.0, pres=2.0, fade=.4, level=-9.0),
    "sting":    dict(hp=45, lp=10500, low=1.0, pres=1.0, fade=.12, level=-3.0),
    "voice":    dict(hp=110, lp=9000, low=0.0, pres=2.0, fade=.06, level=-3.0),
    "room":     dict(hp=160, lp=5200, low=0.0, pres=0.0, fade=.6, level=-10.0),
}
# Families whose main hit has to land when the game event does: any lead-in
# longer than this is cut. Voices, creatures and rising warnings keep theirs.
SYNC = {"report", "boom", "attack", "melee", "impact", "reload", "equip", "dry", "pickup",
        "foot", "ui", "scene", "station"}
LEAD = .03
# Performances: a word or a groan is kept to its own end rather than to a
# stopwatch, up to this many times the length of the cue it replaces.
NATURAL = {"voice": 6.0, "player": 1.8, "death": 1.8, "alert": 1.6, "consume": 1.6}

SPEAKER = {   # the box a spoken line comes out of: band, grit, noise floor
    "radio": dict(lo=380, hi=2900, drive=3.0, hiss=.012),
    "pa":    dict(lo=260, hi=3600, drive=2.0, hiss=.004, slap=.085),
    "horn":  dict(lo=520, hi=2600, drive=4.0, hiss=.006, slap=.06),
}


def ffmpeg() -> str:
    tool = shutil.which("ffmpeg")
    if not tool:
        raise SystemExit("ffmpeg is needed (put it on PATH).")
    return tool


def decode(path: Path, rate: int = RATE, cents: float = 0.0) -> np.ndarray:
    """Any audio file -> mono float32 at `rate`, optionally retuned."""
    filters = []
    if cents:                                   # play faster or slower, like tape
        filters.append(f"asetrate=44100*{2 ** (cents / 1200):.6f}")
    filters.append(f"aresample={rate}:resampler=soxr")
    command = [ffmpeg(), "-v", "error", "-i", str(path), "-ac", "1",
               "-af", ",".join(filters), "-ar", str(rate), "-f", "f32le", "-"]
    raw = subprocess.run(command, check=True, capture_output=True).stdout
    return np.frombuffer(raw, "<f4").astype(np.float64)


def read_wav(path: Path) -> np.ndarray:
    with wave.open(str(path), "rb") as pcm:
        data = np.frombuffer(pcm.readframes(pcm.getnframes()), "<i2").astype(np.float64) / 32768
        if pcm.getnchannels() == 2:
            data = data.reshape(-1, 2).mean(1)
    return data


def write_wav(path: Path, x: np.ndarray) -> None:
    rng = np.random.default_rng(len(x))                       # fixed per length: reproducible
    dither = (rng.random(len(x)) - rng.random(len(x))) / 32768
    pcm = np.clip(np.round((x + dither) * 32767), -32768, 32767).astype("<i2")
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(pcm.tobytes())


def db(value: float) -> float:
    return float(20 * np.log10(max(value, 1e-9)))


def envelope(x: np.ndarray, window: float = .004) -> np.ndarray:
    size = max(1, int(RATE * window))
    return np.sqrt(np.convolve(x * x, np.ones(size) / size, "same"))


def loudness(x: np.ndarray) -> float:
    """Loudest 50 ms, in dB: what the ear takes as the level of a short cue."""
    if len(x) == 0:
        return -120.0
    return db(float(envelope(x, .05).max()))


def events(x: np.ndarray, gap: float = .09, floor: float = -30.0) -> list[tuple[int, int]]:
    """Separate hits in a recording: runs above `floor` dB of peak, split by silence."""
    env = envelope(x)
    peak = env.max()
    if peak <= 0:
        return []
    loud = np.flatnonzero(env > peak * 10 ** (floor / 20))
    if len(loud) == 0:
        return []
    breaks = np.flatnonzero(np.diff(loud) > gap * RATE)
    starts = np.r_[loud[0], loud[breaks + 1]]
    ends = np.r_[loud[breaks], loud[-1]]
    return [(int(a), int(b)) for a, b in zip(starts, ends) if b - a > .012 * RATE]


def tone(x: np.ndarray, hp: float, lp: float, low: float = 0.0, pres: float = 0.0,
         circular: bool = False) -> np.ndarray:
    """High-pass, low-pass, a low shelf and a presence lift, as one smooth curve.

    `circular` filters a loop as the ring it is, so the join stays closed.
    """
    if len(x) < 16:
        return x
    size = len(x) if circular else len(x) + 2048
    spectrum = np.fft.rfft(x, size)
    f = np.fft.rfftfreq(size, 1 / RATE)
    f[0] = 1e-6
    gain = 1 / np.sqrt(1 + (hp / f) ** 4) / np.sqrt(1 + (f / lp) ** 6)
    gain *= 10 ** (low / 20 / (1 + (f / 140) ** 2))                  # shelf below ~140 Hz
    gain *= 10 ** (pres * np.exp(-(np.log2(f / 3200)) ** 2 / 1.2) / 20)  # bell at 3.2 kHz
    return np.fft.irfft(spectrum * gain, size)[: len(x)]


def band(x: np.ndarray, lo: float, hi: float) -> np.ndarray:
    return tone(x, lo, hi)


def drive(x: np.ndarray, amount: float) -> np.ndarray:
    """Soft saturation that keeps the peak where it was."""
    peak = np.abs(x).max()
    if peak <= 0 or amount <= 1:
        return x
    return np.tanh(x / peak * amount) / np.tanh(amount) * peak


def fades(x: np.ndarray, out: float, into: float = .0015) -> np.ndarray:
    x = x.copy()
    n = min(len(x) // 2, max(2, int(into * RATE)))
    x[:n] *= np.linspace(0, 1, n)
    n = min(len(x) - 1, max(int(.004 * RATE), int(out * len(x)))) if out else int(.004 * RATE)
    x[-n:] *= np.linspace(1, 0, n) ** 2
    return x


def seamless(x: np.ndarray, keep: int, cross: float) -> np.ndarray:
    """A loop of `keep` samples whose end runs into its own start."""
    n = min(int(cross * RATE), len(x) // 4)
    keep = min(keep, len(x) - n)
    body = x[: keep + n].copy()
    ramp = np.sin(np.linspace(0, np.pi / 2, n)) ** 2
    body[:n] = body[:n] * ramp + body[keep: keep + n] * (1 - ramp)
    return body[:keep]


def level_to(x: np.ndarray, target: float, ceiling: float = -0.8) -> np.ndarray:
    current = loudness(x)
    x = x * 10 ** ((target - current) / 20)
    peak = np.abs(x).max()
    limit = 10 ** (ceiling / 20)
    if peak > limit:                                  # soft knee instead of clipping
        x = np.tanh(x / peak * 1.5) / np.tanh(1.5) * limit if peak < limit * 2 else x / peak * limit
    return x


def reverb(x: np.ndarray, seconds: float) -> np.ndarray:
    """The room alone: what a board-walled shack gives back, without the dry hit."""
    rng = np.random.default_rng(1997)
    length = int(.5 * RATE)
    t = np.arange(length) / RATE
    impulse = rng.standard_normal(length) * np.exp(-t / .085)
    impulse[: int(.012 * RATE)] = 0                   # pre-delay
    for tap, gain in ((.017, .8), (.029, .6), (.043, .45)):   # first boards
        impulse[int(tap * RATE)] += gain * 6
    wet = np.convolve(x, impulse)[: int(seconds * RATE)]
    return wet


def speaker(x: np.ndarray, kind: str) -> np.ndarray:
    box = SPEAKER[kind]
    x = band(x, box["lo"], box["hi"])
    x = drive(x / max(np.abs(x).max(), 1e-9), box["drive"])
    if "slap" in box:
        delay = int(box["slap"] * RATE)
        echo = np.zeros(len(x) + delay * 2)
        echo[: len(x)] += x
        echo[delay: delay + len(x)] += x * .35
        x = echo
    rng = np.random.default_rng(7)
    x = x + band(rng.standard_normal(len(x)), 600, 3000) * box["hiss"]
    return band(x, box["lo"], box["hi"])


def spoken(name: str, caption: str) -> tuple[float, float] | str:
    """Where the caption's words sit in the recording, from its transcript.

    Returns (start, end) in seconds, or a sentence saying what was heard
    instead. Voice models like to add an "uh" before a three-word line or keep
    talking after it; the transcript's word times let the cue hold exactly the
    caption and nothing else.
    """
    path = GEN / "stt" / f"{name}.json"
    if not path.is_file():
        return "no transcript (run audio_produce.py --transcribe)"
    heard = json.loads(path.read_text(encoding="utf-8"))
    plain = lambda text: "".join(ch for ch in text.lower() if ch.isalpha() or ch == "'")
    want = [plain(word) for word in caption.split()]
    words = [(plain(w["text"]), w["start"], w["end"]) for w in heard["words"]]
    for i in range(len(words) - len(want) + 1):
        if [w[0] for w in words[i: i + len(want)]] == want:
            return words[i][1], words[i + len(want) - 1][2]
    return f"says {heard['text']!r}, caption is {caption!r}"


def old_seconds(name: str, inventory: dict) -> float | None:
    cue = inventory["cues"].get(name)
    return float(cue["seconds"]) if cue else None


def source_of(name: str) -> tuple[Path | None, str]:
    """The stored recording a cue is made from, following derivations."""
    entry = spec.CUES[name]
    if entry["make"] == "derive":
        return source_of(entry["base"])
    kind = "tts" if entry["make"] == "voice" else "sfx"
    path = GEN / kind / f"{name}.mp3"
    return (path if path.is_file() else None), kind


def build_cue(name: str, inventory: dict, done: dict[str, np.ndarray]) -> tuple[np.ndarray | None, dict]:
    entry = spec.CUES[name]
    family = spec.FAMILY[name]
    chain = CHAIN[family]
    was = old_seconds(name, inventory)
    recipe: dict = {"family": family, "chain": chain}
    path, _kind = source_of(name)
    if path is None:
        return None, {"status": "missing source", **recipe}
    keep = entry.get("keep") or was or 1.0
    how = entry.get("how", "")
    if how == "room":
        base = done.get(entry["base"])
        if base is None:
            return None, {"status": "base not built", **recipe}
        seconds = (was or len(base) / RATE + .16) * 1.25
        x = reverb(base, seconds)
        recipe["derived"] = f"reverb tail of {entry['base']} ({seconds:.2f} s)"
    else:
        x = decode(path, cents=entry.get("cents", 0.0))
        if entry["make"] == "voice":
            found = spoken(name, entry["text"])
            if isinstance(found, str):
                return None, {"status": found, **recipe}
            a = max(0, int((found[0] - .05) * RATE))
            b = min(len(x), int((found[1] + .14) * RATE))
            x = x[a:b]
            recipe["words_at"] = [round(found[0], 2), round(found[1], 2)]
        hits = events(x)
        if not hits:
            return None, {"status": "source is silent", **recipe}
        stop = len(x)
        if "event" in entry:
            start, stop = hits[entry["event"] % len(hits)]
            stop = min(len(x), stop + int(.25 * RATE))
            recipe["event"] = f"hit {entry['event'] % len(hits) + 1} of {len(hits)}"
        else:
            start = hits[0][0]
        start = max(0, start - int(.003 * RATE))
        if family in NATURAL:
            # To the end of the performance (the last sound before real silence).
            last = hits[-1][1] + int(.07 * RATE)
            natural = (last - start) / RATE
            keep = min(natural, keep * NATURAL[family]) if natural > keep else max(natural, keep * .6)
            recipe["natural_seconds"] = round(natural, 3)
        if family in SYNC:
            # Where the sound first reaches a third of its peak, less the lead.
            env = envelope(x[start:stop])
            strong = int(np.argmax(env >= env.max() * .33))
            if strong > LEAD * RATE:
                start += strong - int(LEAD * RATE)
                recipe["lead_trimmed_ms"] = round((strong / RATE - LEAD) * 1000)
        if chain.get("loop"):
            x = seamless(x[start:], int(keep * RATE), chain["loop"])
        else:
            x = x[start: start + int(keep * RATE)]
        if how == "pitch":
            recipe["derived"] = f"{entry['base']} retuned {entry['cents']:+.0f} cents"
        elif how == "event":
            recipe["derived"] = f"another step from {entry['base']}'s recording"
    x = x - x.mean()
    x = tone(x, chain["hp"], chain["lp"], chain["low"], chain["pres"], bool(chain.get("loop")))
    if entry.get("fx"):
        x = speaker(x, entry["fx"])
        recipe["speaker"] = entry["fx"]
    if chain.get("drive"):
        x = drive(x, chain["drive"])
    x = x - x.mean()
    if not chain.get("loop"):
        x = fades(x, chain["fade"], chain.get("fade_in", .0015))
    target = chain["level"]
    old = OLD / f"{name}.wav"
    if old.is_file():
        heard = loudness(read_wav(old))
        # Stay within 6 dB of the cue this replaces: the mix was balanced on it.
        target = float(np.clip(heard, chain["level"] - 6, chain["level"] + 6))
        recipe["level"] = f"{target:.1f} dB (replaced cue was {heard:.1f})"
    else:
        recipe["level"] = f"{target:.1f} dB (new cue)"
    x = level_to(x, target)
    recipe["keep_seconds"] = round(keep, 3)
    return x, {"status": "built", **recipe}


def measure(name: str, x: np.ndarray, loop: bool) -> dict:
    env = envelope(x)
    peak = float(np.abs(x).max())
    first = int(np.argmax(env > env.max() * .1)) if env.max() > 0 else len(x)
    spectrum = np.abs(np.fft.rfft(x * np.hanning(len(x)))) ** 2
    f = np.fft.rfftfreq(len(x), 1 / RATE)
    facts = {
        "seconds": round(len(x) / RATE, 3),
        "peak_db": round(db(peak), 1),
        "loud_db": round(loudness(x), 1),
        "dc": round(float(abs(x.mean()) / max(np.sqrt((x * x).mean()), 1e-9)), 4),
        "onset_ms": round(first / RATE * 1000, 1),
        "centroid_hz": int((f * spectrum).sum() / max(spectrum.sum(), 1e-12)),
        "end_db": round(db(float(np.abs(x[-32:]).max())), 1),
    }
    problems = []
    if peak >= .999:
        problems.append("clips")
    if facts["dc"] > .08:                        # mean as a share of RMS
        problems.append("dc offset")
    if facts["loud_db"] < -50:
        problems.append("silent")
    if loop:
        # The step across the join against the steps inside the loop.
        jump = abs(x[0] - x[-1])
        steps = np.abs(np.diff(x))
        facts["seam_jump"] = round(float(jump), 4)
        facts["seam_vs_p999"] = round(float(jump / max(np.percentile(steps, 99.9), 1e-9)), 2)
        if jump > steps.max():
            problems.append("loop seam")
    else:
        if facts["onset_ms"] > 45 and spec.FAMILY[name] in SYNC:
            problems.append("late onset")
        if facts["end_db"] > -40:
            problems.append("ends abruptly")
    facts["problems"] = problems
    return facts


def build_sfx(inventory: dict) -> dict:
    done: dict[str, np.ndarray] = {}
    report: dict = {}
    order = sorted(spec.CUES, key=lambda n: spec.CUES[n].get("how") == "room")
    for name in order:
        x, recipe = build_cue(name, inventory, done)
        record = {"recipe": recipe}
        if x is not None:
            done[name] = x
            write_wav(FINAL / f"{name}.wav", x)
            record["measured"] = measure(name, x, bool(CHAIN[spec.FAMILY[name]].get("loop")))
        report[name] = record
    for stale in FINAL.glob("*.wav"):
        if stale.stem not in spec.CUES:
            stale.unlink()
    return report


# --------------------------------------------------------------------- music

def run(*args: str) -> str:
    return subprocess.run([ffmpeg(), "-hide_banner", "-nostats", *args], check=True,
                          capture_output=True, text=True, encoding="utf-8", errors="replace").stderr


def loudnorm_stats(path: Path, pre: str) -> dict:
    log = run("-i", str(path), "-af", f"{pre},loudnorm=I={MUSIC_LUFS}:TP=-1.5:LRA=11:print_format=json",
              "-f", "null", "-")
    return json.loads(log[log.rindex("{"): log.rindex("}") + 1])


def master(source: Path, target: Path, pre: str, ending: float = .35) -> dict:
    """Trim silence, shape, bring to the shared loudness, encode as Vorbis."""
    trim = ("silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.02,"
            "areverse,silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.15,areverse")
    pre = f"aresample=44100:resampler=soxr,{trim},{pre}"
    s = loudnorm_stats(source, pre)
    two = (f"loudnorm=I={MUSIC_LUFS}:TP=-1.5:LRA=11:measured_I={s['input_i']}:measured_TP={s['input_tp']}"
           f":measured_LRA={s['input_lra']}:measured_thresh={s['input_thresh']}:offset={s['target_offset']}"
           ":linear=true")
    temp = target.with_suffix(".tmp.wav")
    run("-y", "-i", str(source), "-af", f"{pre},{two},aresample=44100", "-ac", "2", str(temp))
    with wave.open(str(temp), "rb") as pcm:
        seconds = pcm.getnframes() / pcm.getframerate()
    fade = f"afade=t=in:d=0.01,afade=t=out:st={max(0, seconds - ending):.3f}:d={ending}"
    target.parent.mkdir(parents=True, exist_ok=True)
    run("-y", "-i", str(temp), "-af", fade, "-c:a", "libvorbis", "-q:a", "5",
        "-map_metadata", "-1", "-bitexact", str(target))
    temp.unlink()
    log = run("-i", str(target), "-af", "ebur128=peak=true", "-f", "null", "-")
    tail = log[log.rindex("Summary"):]
    grab = lambda key: float(tail.split(key)[1].split()[0])
    return {"seconds": round(seconds, 2), "lufs": grab("I:"), "lra": grab("LRA:"),
            "true_peak_db": grab("Peak:"), "source_lufs": float(s["input_i"])}


def build_music() -> dict:
    report: dict = {}
    ends: dict = {}
    # Calibration: the generated band sits ~4 dB under the reference soundtrack
    # between 400 Hz and 4 kHz and ~1.5 dB over it below 400 Hz.
    gentle = ("highpass=f=32,bass=g=-1.5:f=160:w=0.8,equalizer=f=1000:t=q:w=1:g=2.5,"
              "equalizer=f=3000:t=q:w=1.2:g=3")
    for stem, title, bpm, _text in spec.MUSIC:
        source = GEN / "music" / f"{stem}.mp3"
        if not source.is_file():
            report[stem] = {"status": "missing source", "title": title}
            continue
        facts = master(source, MUSIC_OUT / f"{stem}.ogg", gentle)
        ends[stem] = round(facts["seconds"] - .05, 3)
        report[stem] = {"status": "built", "title": title, "bpm_asked": bpm, **facts}
    source = GEN / "music" / "victory.mp3"
    if source.is_file():
        report["victory"] = {"status": "built", "title": "Tally", **master(source, MUSIC_OUT / "victory.ogg", gentle, .8)}
    else:
        report["victory"] = {"status": "missing source"}
    supplied = sorted((SRC / "supplied").glob("menu_theme.*"))
    if supplied:
        # The supplied mix is light below 400 Hz and hot in the upper mids
        # (measured): give it a floor and ease 2-4 kHz so it sits with the band tracks.
        shaped = ("highpass=f=30,bass=g=4:f=110:w=0.7,equalizer=f=250:t=q:w=1:g=2,"
                  "equalizer=f=3000:t=q:w=1.4:g=-2.5")
        report["title"] = {"status": "built", "title": "Main menu theme (supplied)",
                           "supplied": supplied[0].name, **master(supplied[0], MUSIC_OUT / "title.ogg", shaped, 1.2)}
    else:
        report["title"] = {"status": "missing source"}
    (MUSIC_OUT / "playback_ends.json").write_text(json.dumps(ends, indent=1) + "\n", encoding="utf-8", newline="\n")
    return report


def manifest(sfx: dict, music: dict, inventory: dict) -> dict:
    ledger = json.loads((SRC / "ledger.json").read_text(encoding="utf-8")) if (SRC / "ledger.json").is_file() else {"entries": []}
    cost: dict[str, int] = {}
    for entry in ledger["entries"]:
        if entry.get("name"):
            key = f"{entry['kind']}/{entry['name']}"
            cost[key] = cost.get(key, 0) + int(entry.get("actual", 0))
    cues = {}
    for name, record in sfx.items():
        entry = spec.CUES[name]
        known = inventory["cues"].get(name, {})
        path, kind = source_of(name)
        origin = {"gen": "generated", "voice": "generated speech", "derive": f"derived from {entry.get('base')}"}[entry["make"]]
        cues[name] = {
            "purpose": known.get("trigger", "new cue"),
            "refs": known.get("refs", []),
            "family": spec.FAMILY[name],
            "origin": origin,
            "source": path.relative_to(ROOT).as_posix() if path else None,
            "prompt": entry.get("prompt") or entry.get("text"),
            "credits": cost.get(f"{kind}/{name}", 0) if entry["make"] != "derive" else 0,
            "destination": f"audio_src/final/sfx/{name}.wav -> godot/assets_gen/sfx.bin",
            "format": "mono 16-bit PCM 22050 Hz",
            "replaced_seconds": known.get("seconds"),
            **record,
        }
        problems = record.get("measured", {}).get("problems", [record["recipe"].get("status", "not built")])
        cues[name]["validation"] = "ok" if not problems else ", ".join(problems)
    songs = {}
    for stem, record in music.items():
        songs[stem] = {**record, "credits": cost.get(f"music/{stem}", 0),
                       "origin": "supplied by the author" if stem == "title" else "generated",
                       "destination": f"godot/assets/music/{stem}.ogg -> godot/assets_gen/music.bin",
                       "format": "stereo Vorbis 44.1 kHz"}
    return {"cues": cues, "music": songs,
            "dropped_from_bank": inventory.get("unused", []),
            "added": [n for n in spec.CUES if n not in inventory["cues"]]}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--sfx", action="store_true")
    parser.add_argument("--music", action="store_true")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    inventory = json.loads((SRC / "cue_inventory.json").read_text(encoding="utf-8"))
    path = SRC / "manifest.json"
    previous = json.loads(path.read_text(encoding="utf-8")) if path.is_file() else {"cues": {}, "music": {}}
    if args.check:
        bad = {n: c["validation"] for n, c in previous["cues"].items() if c["validation"] != "ok"}
        bad.update({s: m["status"] for s, m in previous["music"].items() if m["status"] != "built"})
        missing = [n for n in spec.CUES if not (FINAL / f"{n}.wav").is_file()]
        print(f"{len(previous['cues'])} cues, {len(previous['music'])} songs; "
              f"{len(bad)} with problems, {len(missing)} files missing")
        for name, why in sorted(bad.items()):
            print(f"  {name}: {why}")
        raise SystemExit(1 if bad or missing else 0)
    everything = not (args.sfx or args.music)
    sfx = build_sfx(inventory) if args.sfx or everything else {n: {k: c[k] for k in ("recipe", "measured") if k in c} for n, c in previous["cues"].items()}
    music = build_music() if args.music or everything else {s: {k: v for k, v in m.items() if k not in ("credits", "origin", "destination", "format")} for s, m in previous["music"].items()}
    result = manifest(sfx, music, inventory)
    path.write_text(json.dumps(result, indent=1) + "\n", encoding="utf-8", newline="\n")
    built = sum(1 for c in result["cues"].values() if c["validation"] == "ok")
    print(f"cues ok {built}/{len(result['cues'])}; songs built "
          f"{sum(1 for m in result['music'].values() if m['status'] == 'built')}/{len(result['music'])}")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
