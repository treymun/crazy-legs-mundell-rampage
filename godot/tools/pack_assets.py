"""Pack game assets into plain binary blobs the Godot port reads directly.

Godot's import pipeline is bypassed for three reasons: the software renderer
wants raw indexed pixels, the port must load exactly the Python project's art,
and a raw blob works unchanged inside an exported PCK.

Outputs (in ``godot/assets_gen``):
  tiles.bin    TILES-order 128x128x3 RGB
  art.bin      concatenated RGBA images + art_index.json
  sfx.bin      the audio manifest's cues, mono 16-bit PCM + sfx_index.json
  music.bin    concatenated Ogg Vorbis (chapter tracks, menu theme, tally tune)
               + music_index.json and music_ends.json
  palette.bin  32768x3 RGB555 grade
  grain.bin    6 frames of 320x156 signed grain, stored +2 biased

Art, tiles and the palette come from the Python project's assets/. Sound comes
from audio_src/final/sfx and godot/assets/music, which scripts/audio_build.py
finishes from the stored source recordings.
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
SRC_SFX = REF / "audio_src" / "final" / "sfx"
MANIFEST = REF / "audio_src" / "manifest.json"
SFX_RATE = 22050
SRC_MUSIC = PROJECT / "assets" / "music"
OUT = PROJECT / "assets_gen"
REQUIRED_MUSIC = {
    "title", "victory", "music", "county_line", "porchlight_stomp", "fair_score",
    "tickets_after_dark", "closing_time_shuffle", "mill_score", "green_chain", "apron_run",
    "quarry_score", "copper_and_steam", "last_load",
}


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
    """The effect bank: every cue in the audio manifest, nothing else.

    The cues are the finished files scripts/audio_build.py writes. A cue that
    is missing or is not mono 16-bit at the bank rate stops the build: the
    runtime drops unknown cues silently, so a skipped file would only be found
    by ear.
    """
    names = sorted(json.loads(MANIFEST.read_text(encoding="utf-8"))["cues"])
    index = {}
    blob = bytearray()
    wrong = []
    for name in names:
        path = SRC_SFX / f"{name}.wav"
        if not path.is_file():
            wrong.append(f"{name}: no file")
            continue
        with wave.open(str(path), "rb") as pcm:
            shape = (pcm.getnchannels(), pcm.getsampwidth(), pcm.getframerate())
            frames = pcm.getnframes()
            raw = pcm.readframes(frames)
        if shape != (1, 2, SFX_RATE) or frames == 0:
            wrong.append(f"{name}: {shape[0]} ch, {shape[1] * 8}-bit, {shape[2]} Hz, {frames} frames")
            continue
        index[name] = {"offset": len(blob), "frames": frames}
        blob += raw
    if wrong:
        raise SystemExit("Effect bank not written, fix these cues first: " + "; ".join(wrong))
    (OUT / "sfx.bin").write_bytes(blob)
    (OUT / "sfx_index.json").write_text(json.dumps({"rate": SFX_RATE, "cues": index},
                                                   separators=(",", ":")))
    print(f"sfx.bin {len(blob)/1e6:.2f} MB, {len(index)} cues at {SFX_RATE} Hz")


def music():
    """Chapter tracks plus the menu theme ("title") and the tally tune ("victory")."""
    index = {}
    blob = bytearray()
    for path in sorted(SRC_MUSIC.glob("*.ogg")):
        data = path.read_bytes()
        if data[:4] != b"OggS" or b"vorbis" not in data[:64]:
            raise SystemExit(f"{path.name} is not Ogg Vorbis (Godot cannot stream Opus).")
        index[path.stem] = {"offset": len(blob), "length": len(data)}
        blob += data
    missing = sorted(REQUIRED_MUSIC - set(index))
    if missing:
        raise SystemExit(f"Music missing from {SRC_MUSIC}: {', '.join(missing)}")
    (OUT / "music.bin").write_bytes(blob)
    (OUT / "music_index.json").write_text(json.dumps(index, separators=(",", ":")))
    ends = json.loads((SRC_MUSIC / "playback_ends.json").read_text(encoding="utf-8"))
    (OUT / "music_ends.json").write_text(json.dumps(ends, separators=(",", ":")))
    for stale in ("streams.bin", "streams_index.json"):      # the old PCM jingle bank
        (OUT / stale).unlink(missing_ok=True)
    print(f"music.bin {len(blob)/1e6:.2f} MB, {len(index)} tracks")


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
    luts()
