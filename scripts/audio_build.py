"""Finish the game's audio from the stored source recordings. Costs nothing.

    python scripts/audio_build.py            # effects, voices, music, manifest
    python scripts/audio_build.py --sfx      # only the effect bank sources
    python scripts/audio_build.py --music    # only the songs (the fight loops too)
    python scripts/audio_build.py --fights   # only the chapters' fight and boss loops
    python scripts/audio_build.py --music --only boss_bayou bayou_score   # just these songs
    python scripts/audio_build.py --check    # validate what is on disk, exit 1 on failure
    python scripts/audio_build.py --sfx --only crowd_cheer   # just these cues, the rest kept as they are

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
    "weather":  dict(hp=60, lp=9000, low=1.0, pres=-1.0, fade=0, level=-15.0, loop=.6),
    "near":     dict(hp=60, lp=9500, low=1.0, pres=0.0, fade=0, level=-11.0, loop=.3),
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


_SOXR: bool | None = None


def resampler() -> str:
    """soxr where this ffmpeg has it (every bank so far was built with it), else
    ffmpeg's own resampler, with a warning: a build without soxr is close but
    not byte for byte the same."""
    global _SOXR
    if _SOXR is None:
        version = subprocess.run([ffmpeg(), "-version"], capture_output=True, text=True).stdout
        _SOXR = "--enable-libsoxr" in version
        if not _SOXR:
            print("warning: this ffmpeg has no soxr; resampling with swr")
    return "soxr" if _SOXR else "swr"


def decode(path: Path, rate: int = RATE, cents: float = 0.0) -> np.ndarray:
    """Any audio file -> mono float32 at `rate`, optionally retuned."""
    filters = []
    if cents:                                   # play faster or slower, like tape
        filters.append(f"asetrate=44100*{2 ** (cents / 1200):.6f}")
    filters.append(f"aresample={rate}:resampler={resampler()}")
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


def punch(x: np.ndarray, thump: tuple[float, float, float] | None = None, body: float = 0.0,
          crack: float = 0.0, tail: float = 0.0, clack: float = 0.0, double: float = 0.0,
          seed: int = 7) -> np.ndarray:
    """Put weight under a gunshot that came out thin.

    A generated report at this bank's sample rate is mostly crack. This lays
    designed layers under it, all locked to the onset and scaled to its peak:
      thump   (start Hz, end Hz, seconds)  a falling sine: the push in the chest
      body    seconds of mid-band noise decaying: the bark of the powder
      crack   level of a 3 ms bright burst right on the onset
      tail    seconds of low-passed noise decaying: the report rolling off
      clack   level of a short metallic ring 35 ms in: the action cycling
      double  seconds between two barrels (repeats thump, body and crack)
    """
    rng = np.random.default_rng(seed)
    peak = float(np.abs(x).max()) or 1.0
    env = envelope(x)
    onset = int(np.argmax(env >= env.max() * .33))
    n = len(x)
    t = np.arange(n) / RATE
    layer = np.zeros(n)

    def at(delay: float, sound: np.ndarray) -> None:
        start = onset + int(delay * RATE)
        if start < n:
            m = min(len(sound), n - start)
            layer[start:start + m] += sound[:m]

    shots = (0.0, double) if double else (0.0,)
    for when in shots:
        if thump:
            f0, f1, seconds = thump
            tt = np.arange(int(seconds * 3.2 * RATE)) / RATE
            freq = f1 + (f0 - f1) * np.exp(-tt / (seconds * .45))
            phase = 2 * np.pi * np.cumsum(freq) / RATE
            at(when, np.sin(phase) * np.exp(-tt / seconds) * peak * .95)
        if body:
            tt = np.arange(int(body * 4 * RATE)) / RATE
            noise = band(rng.standard_normal(len(tt)), 260, 2600)
            noise /= np.abs(noise).max() or 1.0
            at(when, noise * np.exp(-tt / body) * peak * .55)
        if crack:
            tt = np.arange(int(.012 * RATE)) / RATE
            noise = band(rng.standard_normal(len(tt)), 2800, 10000)
            noise /= np.abs(noise).max() or 1.0
            at(when, noise * np.exp(-tt / .003) * peak * crack)
    if tail:
        tt = np.arange(int(tail * 3.5 * RATE)) / RATE
        noise = band(rng.standard_normal(len(tt)), 90, 1300)
        noise /= np.abs(noise).max() or 1.0
        at(.012, noise * np.exp(-tt / tail) * (1 - np.exp(-tt / .01)) * peak * .42)
    if clack:
        tt = np.arange(int(.09 * RATE)) / RATE
        ring = (np.sin(2 * np.pi * 2350 * tt) + .6 * np.sin(2 * np.pi * 3900 * tt + .7)
                + .4 * np.sin(2 * np.pi * 5600 * tt + 1.9)) * np.exp(-tt / .012)
        at(.035, ring / 2.0 * peak * clack)
    mixed = x * .8 + layer
    return mixed / (np.abs(mixed).max() or 1.0) * peak


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


# The county's spellings in the captions and what a transcript writes for them;
# both sides are put in these words before they are compared (canon).
DIALECT = {
    "ya": "you", "yer": "your", "git": "get", "outta": "out of", "yella": "yellow", "whup": "whoop",
    "looky": "lookie", "ol'": "old", "round": "around", "aw": "oh", "ah": "oh", "ow": "oh",
    "drunker'n": "drunker than", "chickenshit": "chicken shit", "dammit": "damn it",
    "sumbitch": "son of a bitch", "sumbitches": "sons of bitches", "hooman": "human",
    "fuses": "fuse is", "'em": "them",
}


def canon(text: str) -> list[str]:
    """`text` as plain words with the county's spellings put the transcript's way."""
    out = []
    for raw in text.lower().split():
        word = "".join(ch for ch in raw if ch.isalnum() or ch == "'").strip("'") if raw != "'em" else raw
        if raw.rstrip(".,!?;:").endswith("in'"):
            word = raw.rstrip(".,!?;:")[:-3] + "ing"
        if not word:
            continue
        for part in DIALECT.get(word, DIALECT.get(raw.strip(".,!?;:"), word)).split():
            out.append(part.replace("'", ""))
    return out


def _heard_words(heard: dict) -> list[tuple[str, float, float]]:
    """The transcript's words in canon, each with its source word's times."""
    out = []
    for w in heard["words"]:
        for part in canon(w["text"]):
            out.append((part, float(w["start"]), float(w["end"])))
    return out


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
    want = canon(caption)
    words = _heard_words(heard)
    for i in range(len(words) - len(want) + 1):
        if [w[0] for w in words[i: i + len(want)]] == want:
            return words[i][1], words[i + len(want) - 1][2]
    return f"says {heard['text']!r}, caption is {caption!r}"


# Where each cuss line's starred words sit in its built cue (samples), for
# its CLEAN copy (spec how="bleep"): filled as the lines are built.
BLEEPS: dict[str, list[tuple[int, int]]] = {}


def bleep_times(name: str, words: list[str], within: tuple[float, float]) -> list[tuple[float, float]]:
    """The seconds each of `words` is said at in the recording (its transcript)."""
    path = GEN / "stt" / f"{name}.json"
    if not path.is_file() or not words:
        return []
    heard = _heard_words(json.loads(path.read_text(encoding="utf-8")))
    out = []
    for word in words:
        want = canon(word)
        for i in range(len(heard) - len(want) + 1):
            run = heard[i: i + len(want)]
            said = [w[0] for w in run]
            # "hell'd", "damn's": the word with a contraction on the end.
            close = said[:-1] == want[:-1] and said[-1].startswith(want[-1]) and len(said[-1]) - len(want[-1]) <= 2
            if (said == want or close) and within[0] - .01 <= run[0][1] <= within[1] + .01:
                span = (run[0][1], run[-1][2])
                if span not in out:
                    out.append(span)
    return sorted(out)


def cover_sound(n: int, kind: str) -> np.ndarray:
    """A duck call ("duck": a nasal wak-wak) or a clown horn ("horn"), n samples."""
    t = np.arange(n) / RATE
    if kind == "horn":
        bend = 1.0 + .03 * np.sin(2 * np.pi * 5.5 * t)
        x = sum(np.sign(np.sin(2 * np.pi * np.cumsum(np.full(n, f) * bend) / RATE)) for f in (349.0, 440.0))
        x = band(x * .5, 300, 3500)
        edge = np.minimum(1.0, np.minimum(t / .012, (t[-1] - t + 1e-9) / .02))
        return x * edge
    # A wak every .17 s, each falling in pitch, through a nasal band.
    x = np.zeros(n)
    step = int(.17 * RATE)
    for at in range(0, n, step):
        m = min(n - at, int(.15 * RATE))
        tt = np.arange(m) / RATE
        f = 560.0 * (1.0 - .35 * tt / .15)
        phase = np.cumsum(f) / RATE
        saw = 2.0 * (phase % 1.0) - 1.0
        env = np.minimum(1.0, tt / .008) * np.exp(-tt / .07)
        x[at: at + m] += saw * env
    return band(x, 650, 3200)


def bleeped(x: np.ndarray, spans: list[tuple[int, int]], kind: str) -> np.ndarray:
    """`x` with every span covered by `kind`, as loud as the words it covers."""
    out = x.copy()
    whole = float(np.sqrt(np.mean(x ** 2)) + 1e-9)
    tail = int(.14 * RATE)
    if spans and max(e for _s, e in spans) + int(.025 * RATE) >= len(x):
        # The line ends on the cuss word: room for the cover to ring out.
        out = np.concatenate([out, np.zeros(tail)])
        x = np.concatenate([x, np.zeros(tail)])
    for s, e in spans:
        s = max(0, s - int(.012 * RATE))
        e = min(len(x), e + int(.025 * RATE))
        if e >= len(x) - tail // 2:
            e = len(x) - int(.01 * RATE)
        if e - s < int(.05 * RATE):
            e = min(len(x), s + int(.05 * RATE))
        part = x[s:e]
        loud = max(float(np.sqrt(np.mean(part ** 2))), whole) * 1.1
        cover = cover_sound(e - s, kind)
        cover *= loud / (float(np.sqrt(np.mean(cover ** 2))) + 1e-9)
        fade = min(int(.006 * RATE), (e - s) // 4)
        ramp = np.ones(e - s)
        if fade > 0:
            ramp[:fade] = np.linspace(0, 1, fade)
            ramp[-fade:] = np.linspace(1, 0, fade)
        if e >= len(x) - tail:
            # Ringing out: the cover dies away instead of stopping dead.
            dies = min(e - s, int(.06 * RATE))
            ramp[-dies:] = np.linspace(1, 0, dies) ** 2
            out[s:e] = cover * ramp
            continue
        out[s:e] = part * (1 - ramp) + cover * ramp
    peak = float(np.max(np.abs(out)) + 1e-9)
    return out * min(1.0, .97 / peak)


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
    if how == "bleep":
        base = done.get(entry["base"])
        spans = BLEEPS.get(entry["base"])
        if base is None or spans is None:
            return None, {"status": "base not built", **recipe}
        if not spans:
            return None, {"status": "no cuss word found in the base's transcript", **recipe}
        kind = entry.get("with", "duck")
        recipe["derived"] = f"{entry['base']} with {len(spans)} word(s) under a {kind}"
        return bleeped(base, spans, kind), {"status": "built", **recipe}
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
            found = spoken(name, entry.get("heard", entry["text"]))
            if isinstance(found, str):
                return None, {"status": found, **recipe}
            a = max(0, int((found[0] - .05) * RATE))
            b = min(len(x), int((found[1] + .14) * RATE))
            x = x[a:b]
            recipe["words_at"] = [round(found[0], 2), round(found[1], 2)]
            cuss = bleep_times(name, entry.get("bleep", []), found)
            if entry.get("bleep"):
                recipe["cuss_at"] = [[round(s, 2), round(e, 2)] for s, e in cuss]
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
        if entry.get("bleep"):
            # In the built cue's samples: the recording from `a`, cut at `start`.
            BLEEPS[name] = [(int(s * RATE) - a - start, int(e * RATE) - a - start)
                            for s, e in cuss]
        if chain.get("loop"):
            x = seamless(x[start:], int(keep * RATE), chain["loop"])
        else:
            x = x[start: start + int(keep * RATE)]
        if how == "pitch":
            recipe["derived"] = f"{entry['base']} retuned {entry['cents']:+.0f} cents"
        elif how == "event":
            recipe["derived"] = f"another step from {entry['base']}'s recording"
    x = x - x.mean()
    if entry.get("punch"):
        x = punch(x, **entry["punch"])
        recipe["punch"] = {key: value for key, value in entry["punch"].items()}
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
    if "level" in entry:
        target = float(entry["level"])
        recipe["level"] = f"{target:.1f} dB (set for this cue)"
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


def build_sfx(inventory: dict, only: list[str] | None = None, previous: dict | None = None) -> dict:
    done: dict[str, np.ndarray] = {}
    report: dict = {}
    order = sorted(spec.CUES, key=lambda n: spec.CUES[n].get("how") in ("room", "bleep"))
    if only:
        # Just these cues; every other one keeps its file and its record.
        kept = (previous or {}).get("cues", {})
        for name in order:
            if name not in only and name in kept:
                report[name] = {k: kept[name][k] for k in ("recipe", "measured") if k in kept[name]}
        order = [n for n in order if n in only]
    for name in order:
        x, recipe = build_cue(name, inventory, done)
        record = {"recipe": recipe}
        if x is not None:
            done[name] = x
            write_wav(FINAL / f"{name}.wav", x)
            record["measured"] = measure(name, x, bool(CHAIN[spec.FAMILY[name]].get("loop")))
        report[name] = record
    if not only:
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


# Calibration: the generated band sits ~4 dB under the reference soundtrack
# between 400 Hz and 4 kHz and ~1.5 dB over it below 400 Hz.
GENTLE = ("highpass=f=32,bass=g=-1.5:f=160:w=0.8,equalizer=f=1000:t=q:w=1:g=2.5,"
          "equalizer=f=3000:t=q:w=1.2:g=3")

# ---------------------------------------------------------------- fight loops
# A fight track loops for as long as a fight lasts, so each take is cut into a
# ring: the join is placed where the bars before the loop's end match the bars
# before its start (drum hits and harmony), and the end crossfades into the
# music that led up to the start. The file then runs straight back into its
# own first sample (sound.gd loops it from 0).
LOOP_RATE = 44100
LOOP_HOP = 256              # onset frames, 5.8 ms
LOOP_BEFORE = 3.0           # seconds compared before the join ...
LOOP_AFTER = 1.0            # ... and after it
LOOP_CROSS = .75            # crossfade at the join, seconds
LOOP_START = (3.2, 16.0)    # where the loop may begin
LOOP_SPAN = 10.0            # how far back from the take's ending its end may go


def pcm(command: list[str], data: bytes | None = None) -> bytes:
    return subprocess.run([ffmpeg(), "-v", "error", *command], input=data, check=True,
                          capture_output=True).stdout


def stereo(path: Path, filters: str) -> np.ndarray:
    raw = pcm(["-i", str(path), "-af", filters, "-ac", "2", "-ar", str(LOOP_RATE), "-f", "f32le", "-"])
    return np.frombuffer(raw, "<f4").astype(np.float64).reshape(-1, 2)


def ebur128(x: np.ndarray) -> dict:
    """Integrated loudness, range and true peak of stereo samples."""
    log = subprocess.run([ffmpeg(), "-hide_banner", "-nostats", "-f", "f32le", "-ar", str(LOOP_RATE),
                          "-ac", "2", "-i", "-", "-af", "ebur128=peak=true", "-f", "null", "-"],
                         input=x.astype("<f4").tobytes(), capture_output=True, check=True).stderr.decode(
                             "utf-8", "replace")
    tail = log[log.rindex("Summary"):]
    grab = lambda key: float(tail.split(key)[1].split()[0])
    return {"lufs": grab("I:"), "lra": grab("LRA:"), "true_peak_db": grab("Peak:")}


def onset_strength(mono: np.ndarray, hop: int = LOOP_HOP, size: int = 2048) -> np.ndarray:
    """Spectral flux per hop: where the drums and picked notes land."""
    frames = 1 + (len(mono) - size) // hop
    window = np.hanning(size)
    flux = np.zeros(frames)
    last = None
    for first in range(0, frames, 512):
        idx = np.arange(size)[None, :] + hop * np.arange(first, min(frames, first + 512))[:, None]
        mag = np.log1p(100 * np.abs(np.fft.rfft(mono[idx] * window, axis=1)))
        prev = np.vstack([mag[:1] if last is None else last, mag[:-1]])
        flux[first:first + len(mag)] = np.maximum(0, mag - prev).sum(1)
        last = mag[-1:]
    flux -= np.convolve(flux, np.ones(43) / 43, "same")          # keep the hits, drop the swell
    return np.maximum(flux, 0)


def chroma(mono: np.ndarray, hop: int = 2048, size: int = 8192) -> np.ndarray:
    """Pitch-class energy per hop, for matching the harmony either side of the join."""
    frames = 1 + (len(mono) - size) // hop
    idx = np.arange(size)[None, :] + hop * np.arange(frames)[:, None]
    mag = np.abs(np.fft.rfft(mono[idx] * np.hanning(size), axis=1))
    f = np.fft.rfftfreq(size, 1 / LOOP_RATE)
    keep = (f > 80) & (f < 2500)
    pitch = np.round(12 * np.log2(f[keep] / 440.0)).astype(int) % 12
    out = np.zeros((frames, 12))
    for pc in range(12):
        out[:, pc] = mag[:, keep][:, pitch == pc].sum(1)
    return out / (out.sum(1, keepdims=True) + 1e-9)


def find_loop(x: np.ndarray) -> dict:
    """The (start, end) sample pair whose surroundings match best."""
    mono = x.mean(1)
    rate = LOOP_RATE / LOOP_HOP
    # The take's body: from where the full band is in to just before its ending.
    second = LOOP_RATE
    rms = np.array([np.sqrt(np.mean(mono[i:i + second] ** 2)) + 1e-9
                    for i in range(0, len(mono) - second, second // 4)])
    level = 20 * np.log10(rms)
    body = np.median(level)
    full = np.flatnonzero(level >= body - 2.0)
    loud = np.flatnonzero(level >= body - 6.0)
    begin = max(LOOP_START[0], full[0] * .25 + 1.0)
    finish = loud[-1] * .25 + 1.0 - 1.0 - LOOP_AFTER          # a second clear of the ending
    env = onset_strength(mono)
    before, after = int(LOOP_BEFORE * rate), int(LOOP_AFTER * rate)

    def windows(lo: float, hi: float) -> tuple[np.ndarray, np.ndarray]:
        at = np.arange(int(lo * rate), int(hi * rate))
        rows = np.stack([env[i - before:i + after] for i in at])
        rows = rows - rows.mean(1, keepdims=True)
        return at, rows / (np.linalg.norm(rows, axis=1, keepdims=True) + 1e-9)

    starts, a = windows(begin, min(LOOP_START[1], finish - 30.0))
    ends, b = windows(finish - LOOP_SPAN, finish)
    rhythm = a @ b.T                                            # [start, end] correlation
    harmony_frames = chroma(mono)
    hop_c = 2048 / LOOP_HOP

    def mean_chroma(at: np.ndarray) -> np.ndarray:
        rows = []
        for i in at:
            lo, hi = int((i - before) / hop_c), int((i + after) / hop_c)
            rows.append(harmony_frames[lo:hi].mean(0))
        rows = np.array(rows)
        rows = rows - rows.mean(1, keepdims=True)
        return rows / (np.linalg.norm(rows, axis=1, keepdims=True) + 1e-9)

    harmony = mean_chroma(starts) @ mean_chroma(ends).T
    # Between near-equal joins, keep more of the take: a longer loop repeats less.
    unused = (starts[:, None] - starts[0] + ends[-1] - ends[None, :]) / rate
    score = rhythm + .5 * harmony - .006 * unused
    i, j = np.unravel_index(int(np.argmax(score)), score.shape)
    start, end = int(starts[i]) * LOOP_HOP, int(ends[j]) * LOOP_HOP
    # Refine the start to the sample on the treble's attack envelope (hats, snare).
    treble = np.abs(np.diff(mono, prepend=mono[0]))
    smooth = np.convolve(treble, np.ones(44) / 44, "same")
    ref = smooth[end - int(LOOP_BEFORE * LOOP_RATE):end + int(LOOP_AFTER * LOOP_RATE)]
    ref = ref - ref.mean()
    best, shift = -2.0, 0
    for k in range(-LOOP_HOP, LOOP_HOP + 1, 4):
        seg = smooth[start + k - int(LOOP_BEFORE * LOOP_RATE):start + k + int(LOOP_AFTER * LOOP_RATE)]
        seg = seg - seg.mean()
        c = float(ref @ seg / (np.linalg.norm(ref) * np.linalg.norm(seg) + 1e-12))
        if c > best:
            best, shift = c, k
    return {"start": start + shift, "end": end, "rhythm": round(float(rhythm[i, j]), 3),
            "harmony": round(float(harmony[i, j]), 3), "attack": round(best, 3)}


def ring(x: np.ndarray, start: int, end: int, cross: float = LOOP_CROSS) -> tuple[np.ndarray, float]:
    """x[start:end] whose last `cross` seconds blend into what led up to `start`."""
    n = int(cross * LOOP_RATE)
    out = x[start:end].copy()
    tail, lead = x[end - n:end], x[start - n:start]
    rho = float(np.sum(tail.mean(1) * lead.mean(1))
                / (np.linalg.norm(tail.mean(1)) * np.linalg.norm(lead.mean(1)) + 1e-12))
    theta = np.linspace(0, np.pi / 2, n)[:, None]
    fade_out, fade_in = np.cos(theta), np.sin(theta)
    # Equal power, corrected for how alike the two passages are, so the join
    # neither dips nor swells.
    out[-n:] = (tail * fade_out + lead * fade_in) / np.sqrt(1 + 2 * fade_out * fade_in * max(0.0, rho))
    return out, rho


def build_fight(source: Path, target: Path) -> dict:
    trim = ("silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.02,"
            "areverse,silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.15,areverse")
    pre = f"aresample={LOOP_RATE}:resampler={resampler()},{trim},{GENTLE}"
    s = loudnorm_stats(source, pre)
    two = (f"loudnorm=I={MUSIC_LUFS}:TP=-1.5:LRA=11:measured_I={s['input_i']}:measured_TP={s['input_tp']}"
           f":measured_LRA={s['input_lra']}:measured_thresh={s['input_thresh']}:offset={s['target_offset']}"
           f":linear=true,aresample={LOOP_RATE}")
    x = stereo(source, f"{pre},{two}")
    found = find_loop(x)
    loop, rho = ring(x, found["start"], found["end"])
    # The cut changes the average a little: bring the ring itself to the target.
    loop *= 10 ** ((MUSIC_LUFS - ebur128(loop)["lufs"]) / 20)
    peak = float(np.abs(loop).max())
    if peak > 10 ** (-1.0 / 20):
        loop *= 10 ** (-1.0 / 20) / peak
    target.parent.mkdir(parents=True, exist_ok=True)
    data = loop.astype("<f4").tobytes()
    subprocess.run([ffmpeg(), "-v", "error", "-y", "-f", "f32le", "-ar", str(LOOP_RATE), "-ac", "2", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "5", "-map_metadata", "-1", "-bitexact", str(target)],
                   input=data, check=True, capture_output=True)
    back = stereo(target, "anull")
    facts = ebur128(back)
    # The join as the game hears it: the file's end running into its start.
    seam = np.concatenate([back[-LOOP_RATE:], back[:LOOP_RATE]]).mean(1)
    win = int(.05 * LOOP_RATE)
    levels = [db(float(np.sqrt(np.mean(seam[i:i + win] ** 2)))) for i in range(0, len(seam) - win + 1, win)]
    step = np.abs(np.diff(back.mean(1)))
    return {"seconds": round(len(back) / LOOP_RATE, 3), **facts, "source_lufs": float(s["input_i"]),
            "loop_from_take": round(found["start"] / LOOP_RATE, 3),
            "loop_to_take": round(found["end"] / LOOP_RATE, 3),
            "match_rhythm": found["rhythm"], "match_harmony": found["harmony"],
            "match_attack": found["attack"], "cross_correlation": round(rho, 3),
            "join_jump": round(float(abs(back[0].mean() - back[-1].mean()) / (np.median(step) + 1e-12)), 2),
            "join_level_spread_db": round(max(levels) - min(levels), 2),
            "body_level_spread_db": _spread(back.mean(1), win)}


def _spread(mono: np.ndarray, win: int) -> float:
    """The 50 ms level spread over a typical two seconds, for comparing with the join."""
    spans = []
    for first in range(LOOP_RATE * 4, len(mono) - LOOP_RATE * 6, LOOP_RATE * 5):
        part = mono[first:first + 2 * LOOP_RATE]
        levels = [db(float(np.sqrt(np.mean(part[i:i + win] ** 2)))) for i in range(0, len(part) - win + 1, win)]
        spans.append(max(levels) - min(levels))
    return round(float(np.median(spans)), 2)


def build_fights(report: dict, ends: dict, only: list[str] | None = None) -> None:
    for stem, title, bpm, _text in spec.FIGHTS + spec.BOSSES:
        if only and stem not in only:
            continue
        source = GEN / "music" / f"{stem}.mp3"
        if not source.is_file():
            report[stem] = {"status": "missing source", "title": title}
            continue
        facts = build_fight(source, MUSIC_OUT / f"{stem}.ogg")
        # A fight loop has no cut-off: it wraps at its own end.
        ends[stem] = facts["seconds"]
        report[stem] = {"status": "built", "title": title, "bpm_asked": bpm, "loop": True, **facts}


def build_music() -> dict:
    report: dict = {}
    ends: dict = {}
    gentle = GENTLE
    for stem, title, bpm, _text in spec.MUSIC:
        source = GEN / "music" / f"{stem}.mp3"
        if not source.is_file():
            report[stem] = {"status": "missing source", "title": title}
            continue
        facts = master(source, MUSIC_OUT / f"{stem}.ogg", gentle)
        ends[stem] = round(min(facts["seconds"] - .05, spec.MUSIC_END.get(stem, 1e9)), 3)
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
    build_fights(report, ends)
    (MUSIC_OUT / "playback_ends.json").write_text(json.dumps(ends, indent=1) + "\n", encoding="utf-8", newline="\n")
    return report


def build_fight_music(previous: dict, only: list[str] | None = None) -> dict:
    """Only the fight and boss loops; every other song and its cut-off stay as they are."""
    path = MUSIC_OUT / "playback_ends.json"
    ends = json.loads(path.read_text(encoding="utf-8")) if path.is_file() else {}
    report = {s: {k: v for k, v in m.items() if k not in ("credits", "origin", "destination", "format")}
              for s, m in previous.items()}
    build_fights(report, ends, only)
    path.write_text(json.dumps(ends, indent=1) + "\n", encoding="utf-8", newline="\n")
    return report


def build_some_music(previous: dict, only: list[str]) -> dict:
    """Just the named chapter tracks and loops; every other song keeps its file and cut-off."""
    path = MUSIC_OUT / "playback_ends.json"
    ends = json.loads(path.read_text(encoding="utf-8")) if path.is_file() else {}
    report = {s: {k: v for k, v in m.items() if k not in ("credits", "origin", "destination", "format")}
              for s, m in previous.items()}
    for stem, title, bpm, _text in spec.MUSIC:
        if stem not in only:
            continue
        source = GEN / "music" / f"{stem}.mp3"
        if not source.is_file():
            report[stem] = {"status": "missing source", "title": title}
            continue
        facts = master(source, MUSIC_OUT / f"{stem}.ogg", GENTLE)
        ends[stem] = round(min(facts["seconds"] - .05, spec.MUSIC_END.get(stem, 1e9)), 3)
        report[stem] = {"status": "built", "title": title, "bpm_asked": bpm, **facts}
    build_fights(report, ends, only)
    path.write_text(json.dumps(ends, indent=1) + "\n", encoding="utf-8", newline="\n")
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
    parser.add_argument("--fights", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--only", nargs="*", default=[])
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
    everything = not (args.sfx or args.music or args.fights)
    sfx = build_sfx(inventory, args.only, previous) if args.sfx or everything else {n: {k: c[k] for k in ("recipe", "measured") if k in c} for n, c in previous["cues"].items()}
    if args.music and args.only:
        music = build_some_music(previous["music"], args.only)
    elif args.music or everything:
        music = build_music()
    elif args.fights:
        music = build_fight_music(previous["music"], args.only)
    else:
        music = {s: {k: v for k, v in m.items() if k not in ("credits", "origin", "destination", "format")} for s, m in previous["music"].items()}
    result = manifest(sfx, music, inventory)
    path.write_text(json.dumps(result, indent=1) + "\n", encoding="utf-8", newline="\n")
    built = sum(1 for c in result["cues"].values() if c["validation"] == "ok")
    print(f"cues ok {built}/{len(result['cues'])}; songs built "
          f"{sum(1 for m in result['music'].values() if m['status'] == 'built')}/{len(result['music'])}")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
