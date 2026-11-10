"""Pack game assets into plain binary blobs the Godot port reads directly.

Godot's import pipeline is bypassed for three reasons: the software renderer
wants raw indexed pixels, the port must load exactly the Python project's art,
and a raw blob works unchanged inside an exported PCK.

Outputs (in ``godot/assets_gen``):
  tiles.bin    TILES-order 128x128x3 RGB
  art.bin      concatenated RGBA images + art_index.json
  sfx.bin      concatenated mono 16-bit PCM + sfx_index.json
  music.bin    concatenated Ogg Vorbis + music_index.json
  palette.bin  32768x3 RGB555 grade
  grain.bin    6 frames of 320x156 signed grain, stored +2 biased
  streams.bin  stereo 16-bit PCM for the title/victory jingles
  music_ends.json  per-track cut-off points from the reference
"""
from __future__ import annotations

import json
import sys
import wave
from pathlib import Path

import numpy as np
from PIL import Image

def _find_ref() -> Path:
    """Reference project: env override, then the repository this folder sits in."""
    import os
    env = os.environ.get("CRAZY_LEGS_REF")
    if env:
        return Path(env)
    here = Path(__file__).resolve().parent
    # godot/tools/ lives inside the Python project it is ported from; the
    # reference/ candidates cover a standalone copy of the godot folder.
    for candidate in (here.parent.parent, here.parent / "reference",
                      here.parent.parent / "reference"):
        if (candidate / "main.py").is_file():
            return candidate
    raise SystemExit("Python reference project not found: set CRAZY_LEGS_REF to its folder.")


REF = _find_ref()
HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent
# Source art lives in the reference copy: keeping a second 145 MB mirror inside
# the project only duplicated what reference/assets already holds. The one thing
# that cannot be regenerated without ffmpeg is music/ (the reference ships .opus
# and Godot's Ogg loader rejects Opus), so those transcodes stay in the project.
SRC_TILES = REF / "assets" / "tiles"
SRC_ART = REF / "assets" / "art"
SRC_WAV = REF / "assets" / "wav"
SRC_MUSIC = PROJECT / "assets" / "music"
OUT = PROJECT / "assets_gen"


def tiles():
    sys.path.insert(0, str(REF))
    import level_hickston

    blob = bytearray()
    missing = []
    for name in level_hickston.TILES:
        path = SRC_TILES / f"{name}.png"
        if not path.is_file():
            missing.append(name)
            pixels = np.zeros((128, 128, 3), np.uint8)
        else:
            pixels = np.asarray(Image.open(path).convert("RGB"), dtype=np.uint8)
            assert pixels.shape == (128, 128, 3), (name, pixels.shape)
        blob += pixels.tobytes()
    (OUT / "tiles.bin").write_bytes(blob)
    (OUT / "tiles_index.json").write_text(json.dumps({"names": list(level_hickston.TILES)}))
    print(f"tiles.bin {len(blob)/1e6:.2f} MB, {len(level_hickston.TILES)} tiles, "
          f"missing={missing}")


def art():
    index = {}
    blob = bytearray()
    for path in sorted(SRC_ART.glob("*.png")):
        image = Image.open(path).convert("RGBA")
        w, h = image.size
        data = np.asarray(image, dtype=np.uint8)
        index[path.stem] = {"offset": len(blob), "w": w, "h": h}
        blob += data.tobytes()
    (OUT / "art.bin").write_bytes(blob)
    (OUT / "art_index.json").write_text(json.dumps(index, separators=(",", ":")))
    print(f"art.bin {len(blob)/1e6:.2f} MB, {len(index)} images")


def sfx():
    index = {}
    blob = bytearray()
    rate = None
    odd = []
    for path in sorted(SRC_WAV.glob("*.wav")):
        with wave.open(str(path), "rb") as pcm:
            channels, width, framerate, frames = (pcm.getnchannels(), pcm.getsampwidth(),
                                                  pcm.getframerate(), pcm.getnframes())
            raw = pcm.readframes(frames)
        if rate is None:
            rate = framerate
        if framerate != rate or width != 2 or channels != 1:
            odd.append((path.name, channels, width, framerate))
            continue
        index[path.stem] = {"offset": len(blob), "frames": frames}
        blob += raw
    (OUT / "sfx.bin").write_bytes(blob)
    (OUT / "sfx_index.json").write_text(json.dumps({"rate": rate, "cues": index},
                                                   separators=(",", ":")))
    print(f"sfx.bin {len(blob)/1e6:.2f} MB, {len(index)} cues at {rate} Hz, odd={odd[:4]}")


def music():
    index = {}
    blob = bytearray()
    for path in sorted(SRC_MUSIC.glob("*.ogg")):
        data = path.read_bytes()
        index[path.stem] = {"offset": len(blob), "length": len(data)}
        blob += data
    (OUT / "music.bin").write_bytes(blob)
    (OUT / "music_index.json").write_text(json.dumps(index, separators=(",", ":")))
    print(f"music.bin {len(blob)/1e6:.2f} MB, {len(index)} tracks")


def streams():
    """title/victory are stereo jingles in the reference's wav folder: they are
    played through the music device, not the effect sample bank."""
    index = {}
    blob = bytearray()
    rate = None
    for name in ("title", "victory"):
        path = REF / "assets" / "wav" / f"{name}.wav"
        with wave.open(str(path), "rb") as pcm:
            channels, width, framerate, frames = (pcm.getnchannels(), pcm.getsampwidth(),
                                                  pcm.getframerate(), pcm.getnframes())
            raw = pcm.readframes(frames)
        assert width == 2 and channels == 2, (name, channels, width)
        rate = framerate
        index[name] = {"offset": len(blob), "frames": frames}
        blob += raw
    (OUT / "streams.bin").write_bytes(blob)
    (OUT / "streams_index.json").write_text(json.dumps({"rate": rate, "streams": index},
                                                       separators=(",", ":")))
    print(f"streams.bin {len(blob)/1e6:.2f} MB, {len(index)} jingles at {rate} Hz")

    ends = (REF / "assets" / "music" / "playback_ends.json").read_text(encoding="utf-8")
    (OUT / "music_ends.json").write_text(ends)


def luts():
    palette = np.load(REF / "assets" / "tiles" / "vga_rgb555.npy", allow_pickle=False)
    (OUT / "palette.bin").write_bytes(np.ascontiguousarray(palette, np.uint8).tobytes())

    rng = np.random.default_rng(11 + 320 * 7 + 156)
    frames = [rng.integers(-2, 3, (320, 156, 1), dtype=np.int16) for _ in range(6)]
    grain = np.concatenate(frames, axis=1).astype(np.int8) + 2  # 0..4
    (OUT / "grain.bin").write_bytes(np.ascontiguousarray(grain, np.uint8).tobytes())
    print("palette.bin / grain.bin written")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    tiles()
    art()
    sfx()
    music()
    streams()
    luts()
