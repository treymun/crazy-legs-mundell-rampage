"""The fight music's layers (pass 15): free, made from each chapter's own
finished fight loop, so they are in its key and tempo and as long as it to
the sample. src/score_layers.gd plays them locked to the loop
(AudioStreamSynchronized):

    pulse_<chapter>  the loop's drums alone (its percussive part, median-
                     filtered apart from the tune), low-passed: BUILD, a hand
                     awake and the fight not on the player yet.
    peak_<chapter>   the loop's tune alone (its harmonic part), high-passed
                     and driven a little: its top riff, laid over the whole
                     loop at a PEAK (a director's peak, a RAMPAGE).

    python scripts/audio_build.py --layers            # every chapter's
    python scripts/audio_build.py --layers --only fight_bayou

Every step works on the loop as a ring (it is padded with its own end before
its start and its start after its end), so nothing new happens at the join;
each layer is checked to decode to exactly the loop's length and for the step
across its join. Deterministic: the same loops give the same files.
"""
from __future__ import annotations

import subprocess
from pathlib import Path

import numpy as np

RATE = 44100
FFT = 4096
HOP = 1024
# Median windows: along time for the tune (sustained), along frequency for
# the drums (broadband hits). 17 frames is 0.39 s; 17 bins is 183 Hz.
TIME_MEDIAN = 17
FREQ_MEDIAN = 17
PAD = 2.0                 # seconds of the ring each side while filtering


def _ffmpeg() -> str:
    import shutil
    tool = shutil.which("ffmpeg")
    if not tool:
        raise SystemExit("ffmpeg is needed")
    return tool


def decode(path: Path) -> np.ndarray:
    raw = subprocess.run([_ffmpeg(), "-v", "error", "-i", str(path), "-ac", "2", "-ar", str(RATE),
                          "-f", "f32le", "-"], check=True, capture_output=True).stdout
    return np.frombuffer(raw, "<f4").astype(np.float64).reshape(-1, 2)


def encode(x: np.ndarray, target: Path, quality: int, mono: bool) -> None:
    data = (x.mean(1, keepdims=True) if mono else x).astype("<f4")
    target.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([_ffmpeg(), "-v", "error", "-y", "-f", "f32le", "-ar", str(RATE), "-ac", "1" if mono else "2",
                    "-i", "-", "-c:a", "libvorbis", "-q:a", str(quality), "-map_metadata", "-1", "-bitexact",
                    str(target)], input=data.tobytes(), check=True, capture_output=True)


def ebur128(x: np.ndarray) -> dict:
    log = subprocess.run([_ffmpeg(), "-hide_banner", "-nostats", "-f", "f32le", "-ar", str(RATE), "-ac", "2",
                          "-i", "-", "-af", "ebur128=peak=true", "-f", "null", "-"],
                         input=x.astype("<f4").tobytes(), capture_output=True, check=True).stderr.decode(
                             "utf-8", "replace")
    tail = log[log.rindex("Summary"):]
    grab = lambda key: float(tail.split(key)[1].split()[0])  # noqa: E731
    return {"lufs": grab("I:"), "true_peak_db": grab("Peak:")}


def _stft(x: np.ndarray) -> np.ndarray:
    window = np.hanning(FFT)
    frames = 1 + (len(x) - FFT) // HOP
    idx = np.arange(FFT)[None, :] + HOP * np.arange(frames)[:, None]
    return np.fft.rfft(x[idx] * window, axis=1)


def _istft(spec: np.ndarray, length: int) -> np.ndarray:
    window = np.hanning(FFT)
    frames = spec.shape[0]
    out = np.zeros(length)
    norm = np.zeros(length)
    parts = np.fft.irfft(spec, n=FFT, axis=1) * window
    for i in range(frames):
        at = i * HOP
        out[at:at + FFT] += parts[i]
        norm[at:at + FFT] += window * window
    return out / np.maximum(norm, 1e-6)


def _median(a: np.ndarray, width: int, axis: int) -> np.ndarray:
    """A running median of `width` along `axis` (edges held), in chunks."""
    half = width // 2
    a = np.moveaxis(a, axis, -1)
    padded = np.pad(a, [(0, 0)] * (a.ndim - 1) + [(half, half)], mode="edge")
    out = np.empty_like(a)
    step = max(1, 4_000_000 // (a.shape[-1] * width))
    for first in range(0, a.shape[0], step):
        view = np.lib.stride_tricks.sliding_window_view(padded[first:first + step], width, axis=-1)
        out[first:first + step] = np.median(view, axis=-1)
    return np.moveaxis(out, -1, axis)


def split(x: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """The ring `x` (stereo) as its drums and its tune (soft masks from the
    mono mix, so both sides part the same way); each the length of `x`."""
    n = len(x)
    pad = int(PAD * RATE)
    ring = np.concatenate([x[-pad:], x, x[:pad]])
    mono = ring.mean(1)
    mag = np.abs(_stft(mono))
    tune = _median(mag, TIME_MEDIAN, 0)
    hits = _median(mag, FREQ_MEDIAN, 1)
    hits_mask = hits ** 2 / (hits ** 2 + tune ** 2 + 1e-12)
    drums = np.zeros_like(ring)
    rest = np.zeros_like(ring)
    for ch in range(2):
        s = _stft(ring[:, ch])
        drums[:, ch] = _istft(s * hits_mask, len(ring))
        rest[:, ch] = _istft(s * (1.0 - hits_mask), len(ring))
    return drums[pad:pad + n], rest[pad:pad + n]


def _ring_filter(x: np.ndarray, filters: str) -> np.ndarray:
    """ffmpeg filters run over the ring: padded with itself, then cut back."""
    n = len(x)
    pad = int(PAD * RATE)
    ring = np.concatenate([x[-pad:], x, x[:pad]]).astype("<f4")
    raw = subprocess.run([_ffmpeg(), "-v", "error", "-f", "f32le", "-ar", str(RATE), "-ac", "2", "-i", "-",
                          "-af", filters, "-f", "f32le", "-ar", str(RATE), "-ac", "2", "-"],
                         input=ring.tobytes(), check=True, capture_output=True).stdout
    y = np.frombuffer(raw, "<f4").astype(np.float64).reshape(-1, 2)
    return y[pad:pad + n]


def _to_lufs(x: np.ndarray, lufs: float, peak_db: float = -1.5) -> np.ndarray:
    # Measured as a ring repeated twice, so a short loop's gating sees all of it.
    now = ebur128(np.concatenate([x, x]))["lufs"]
    y = x * 10 ** ((lufs - now) / 20)
    top = float(np.abs(y).max())
    if top > 10 ** (peak_db / 20):
        y *= 10 ** (peak_db / 20) / top
    return y


def seam(x: np.ndarray) -> dict:
    """The step across the join (the file's end into its start) against the
    99.9th percentile step inside, as audio_qa.py measures a loop."""
    mono = x.mean(1)
    steps = np.abs(np.diff(mono))
    return {"seam_step": round(abs(float(mono[-1] - mono[0])) / max(float(np.percentile(steps, 99.9)), 1e-9), 2)}


def build_layer(loop_path: Path, target: Path, kind: str, shape: dict, loop_lufs: float) -> dict:
    """One layer of the loop at `loop_path`: "pulse" (its drums) or "peak"
    (its tune's top), shaped by `shape` (audio_spec.LAYER_SHAPE)."""
    x = decode(loop_path)
    drums, tune = split(x)
    if kind == "pulse":
        y = _ring_filter(drums, f"lowpass=f={shape['lp']}:p=2,lowpass=f={shape['lp']}:p=2,"
                                f"bass=g={shape['low']}:f=90:w=0.8")
        # Drums alone are spiky: brought to their level, their peaks held
        # under the ceiling by a limiter run over the ring.
        for _ in range(3):
            y = _to_lufs(y, shape["lufs"], 6.0)
            y = _ring_filter(y, "alimiter=limit=0.75:attack=1:release=60:level=0:latency=1")
    else:
        y = _ring_filter(tune, f"highpass=f={shape['hp']}:p=2,highpass=f={shape['hp']}:p=2,"
                               f"equalizer=f=2800:t=q:w=1:g={shape['pres']}")
        y = np.tanh(y * shape["drive"] / max(1e-9, float(np.abs(y).max()))) / np.tanh(shape["drive"])
        # As loud as makes the loop and it together `sum_lift` LU over the loop.
        y = _to_lufs(y, loop_lufs - 6.0)
        for _ in range(6):
            lift = ebur128(np.concatenate([x + y, x + y]))["lufs"] - loop_lufs
            y *= 10 ** ((shape["sum_lift"] - lift) / 20 * .9)
    encode(y, target, shape["quality"], shape.get("mono", False))
    back = decode(target)
    facts = ebur128(np.concatenate([back, back]))
    out = {"seconds": round(len(back) / RATE, 3), "samples": len(back), "loop_samples": len(x),
           "lufs": facts["lufs"], "true_peak_db": facts["true_peak_db"], **seam(back),
           "loop_seam_step": seam(x)["seam_step"]}
    if kind == "peak":
        n = min(len(back), len(x))
        both = x[:n] + back[:n]
        out["with_loop_lufs"] = ebur128(np.concatenate([both, both]))["lufs"]
        out["with_loop_peak_db"] = round(20 * np.log10(float(np.abs(both).max()) + 1e-12), 2)
    return out
