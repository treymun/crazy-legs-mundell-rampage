"""Bake short multi-tap room tails for loud world cues (indoor reverb zones)."""
from pathlib import Path
import wave

import numpy as np

from sound_production import RATE, delay, edge, peak

ROOT = Path(__file__).resolve().parent
WAV = ROOT / "assets" / "wav"

# Loud cues that should carry a room tail when the listener is under a roof.
ROOM_CUES = (
    "explosion", "rocket_pop", "arm_impact", "deputy_shot", "tosser_throw",
    "chain_crack", "glass_break", "window_smash", "bowling_hit", "tnt_bounce",
    "gate", "door", "secret_slide", "saw_hit", "foreman_cut", "rudy_horn",
    "boiler_release", "toilet_burst", "vending_clunk", "tv_pop", "sink_flush",
    "can_kick", "baron_blast", "splat",
)


def load(path):
    with wave.open(str(path), "rb") as pcm:
        assert pcm.getnchannels() == 1
        return np.frombuffer(pcm.readframes(pcm.getnframes()), dtype=np.int16).astype(np.float32) / 32768.


def save(path, samples):
    data = (np.clip(samples, -1., 1.) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as pcm:
        pcm.setnchannels(1)
        pcm.setsampwidth(2)
        pcm.setframerate(RATE)
        pcm.writeframes(data.tobytes())


def wet(dry):
    """Wet-only tail: the dry report is played separately by Sound.play."""
    padded = np.pad(dry, (0, round(.16 * RATE)))
    tail = .62 * delay(padded, .039) + .39 * delay(padded, .081) + .27 * delay(padded, .113)
    return edge(peak(tail, .26), .001, .070)


def bake():
    made = []
    for name in ROOM_CUES:
        source = WAV / f"{name}.wav"
        if not source.is_file():
            continue
        save(WAV / f"room_{name}.wav", wet(load(source)))
        made.append(name)
    return made


if __name__ == "__main__":
    print(f"{len(bake())} room tails")
