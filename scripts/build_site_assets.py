"""Build the landing page's images and audio previews from the game's assets.

    python scripts/build_site_assets.py            # images (Pillow)
    python scripts/build_site_assets.py --audio    # also MP3 previews (ffmpeg)

Everything under ``site/img`` and ``site/audio`` comes from files the game
already ships, so the page never shows art or plays sound that is not in the
game. The results are small and committed; rerun this after the art changes.

  site/img/weapons/<name>.png   one strip of view-model frames per weapon
  site/img/faces.png            the twelve status-bar expressions
  site/img/shot_<id>.png        chapter pictures, from window captures in docs/media/site_shots
  site/audio/<stem>.mp3         40-second soundtrack previews and short cues
  site/js/frames.js             frame counts and sizes for the strips
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "assets" / "art"
# The Godot build's finished audio: mastered songs and the effect bank.
MUSIC = ROOT / "godot" / "assets" / "music"
SFX = ROOT / "audio_src" / "final" / "sfx"
SHOTS_DIR = ROOT / "docs" / "media" / "site_shots"
SITE = ROOT / "site"

# Site name -> (art stem, frames shown in order). Guns fire then cycle their
# action; the two blades swing; the stick is lit and thrown.
FIRE = ("idle", "kick", "recover", "open", "eject", "load", "close")
SWING = ("idle", "wind", "strike", "follow", "recover")
WEAPONS = {
    "crowbar": ("crowbar", SWING),
    "revolver": ("revolver", FIRE),
    "shotgun": ("shotgun", FIRE),
    "crossbow": ("crossbow", ("idle", "kick", "open", "eject", "load", "close")),
    "rifle": ("rifle", FIRE),
    "ripsaw": ("ripsaw", ("idle", "kick", "grind", "grind_hot", "open", "load", "close")),
    "armgun": ("armgun", FIRE),
    "tnt": ("tnt", ("idle", "lit", "lit_alt", "throw", "dry")),
    "slingblade": ("slingblade", SWING),
    "bottle_launcher": ("bottle_launcher", FIRE),
    "bowling_ball": ("bowling_ball", FIRE),
    "powder_keg": ("powder_keg", FIRE),
    "cow_launcher": ("cow_launcher", FIRE),
    "teat_gun": ("teat_gun", FIRE),
    "riveter": ("riveter", FIRE),
    "pressure_gun": ("pressure_gun", FIRE),
}
FACES = ("idle_center", "idle_blink", "look_left", "look_right", "grin_rampage", "yell_fire",
         "ouch_shock", "hurt_75", "hurt_50", "hurt_25", "drunk_dizzy", "dead")
COPIES = {
    "wanted_poster": "poster", "title_logo": "logo", "title_backdrop": "backdrop",
    "bessie_0": "bessie", "boss_0": "boss_sheriff", "jerry_0": "boss_jerry",
    "rudy_0": "boss_rudy", "foreman_0": "boss_foreman", "baron_0": "boss_baron",
    "swamp_king_0": "boss_king", "derby_champ_0": "boss_boggs", "maw_0": "boss_maw",
    "player_front_0": "mundell", "hickston_icon": "icon",
}
# Captures from the Godot build's window (docs/media/site_shots, 320x200). The
# old Python frames they once fell back to left with the Python game.
SHOTS = ("shot_hickston", "shot_fair", "shot_sawmill", "shot_quarry", "shot_fight", "shot_hub",
         "shot_bayou", "shot_speedway", "shot_mothership", "shot_range")
TRACKS = ("title", "music", "county_line", "porchlight_stomp", "fair_score", "tickets_after_dark",
          "closing_time_shuffle", "mill_score", "green_chain", "apron_run", "quarry_score",
          "copper_and_steam", "last_load", "bayou_score", "cypress_crawl", "crawdad_boil_hop",
          "music_speedway", "pit_row_boogie", "checkered_flag_rag", "mothership_score",
          "boss_hickston", "boss_fair", "boss_mill", "boss_quarry", "boss_bayou",
          "boss_speedway", "boss_mothership")
CUES = ("yee_haw", "yee_haw_alt", "belch", "gulp", "moonshine", "shotgun_both", "cow_moo",
        "pig", "chicken", "rudy_horn", "sheriff_siren", "got_bessie", "king_holler", "gator_snap",
        "lap_car_pass", "maw_holler")


def strip(name: str, stem: str, poses: tuple[str, ...]) -> dict:
    """Frames trimmed to the box their pixels share, laid side by side."""
    frames = [Image.open(ART / f"gun_{stem}_{pose}.png").convert("RGBA") for pose in poses]
    # A cel can be empty (a hand swung out of view); it does not shape the box.
    boxes = [box for box in (frame.getbbox() for frame in frames) if box]
    left = min(box[0] for box in boxes)
    top = min(box[1] for box in boxes)
    right = max(box[2] for box in boxes)
    bottom = max(box[3] for box in boxes)
    width, height = right - left, bottom - top
    sheet = Image.new("RGBA", (width * len(frames), height), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        sheet.paste(frame.crop((left, top, right, bottom)), (index * width, 0))
    sheet.save(SITE / "img" / "weapons" / f"{name}.png", optimize=True)
    return {"frames": len(frames), "w": width, "h": height}


def faces() -> dict:
    cells = [Image.open(ART / f"face_{name}.png").convert("RGBA") for name in FACES]
    width = max(cell.width for cell in cells)
    height = max(cell.height for cell in cells)
    sheet = Image.new("RGBA", (width * len(cells), height), (0, 0, 0, 0))
    for index, cell in enumerate(cells):
        sheet.paste(cell, (index * width + (width - cell.width) // 2, height - cell.height))
    sheet.save(SITE / "img" / "faces.png", optimize=True)
    return {"frames": len(cells), "w": width, "h": height}


def images() -> None:
    (SITE / "img" / "weapons").mkdir(parents=True, exist_ok=True)
    (SITE / "js").mkdir(parents=True, exist_ok=True)
    table = {name: strip(name, stem, poses) for name, (stem, poses) in WEAPONS.items()}
    table["faces"] = faces()
    for source, target in COPIES.items():
        Image.open(ART / f"{source}.png").save(SITE / "img" / f"{target}.png", optimize=True)
    for name in SHOTS:
        Image.open(SHOTS_DIR / f"{name}.png").convert("RGB").save(
            SITE / "img" / f"{name}.png", optimize=True)
    (SITE / "js" / "frames.js").write_text(
        "// Written by scripts/build_site_assets.py: sprite strip sizes.\n"
        f"window.CLM_FRAMES = {json.dumps(table, separators=(',', ':'))};\n",
        encoding="utf-8", newline="\n")
    print(f"images: {len(table)} strips, {len(COPIES) + len(SHOTS)} pictures")


def audio() -> None:
    tool = shutil.which("ffmpeg")
    if not tool:
        raise SystemExit("ffmpeg is needed for --audio.")
    out = SITE / "audio"
    out.mkdir(parents=True, exist_ok=True)
    for stem in TRACKS:
        # Forty seconds from a little way in, faded at both ends. A boss loop is
        # a short seamless loop (under a minute): it runs into its second time round.
        again = ["-stream_loop", "1"] if stem.startswith("boss_") else []
        subprocess.run([tool, "-y", "-loglevel", "error", *again, "-ss", "12", "-t", "40",
                        "-i", str(MUSIC / f"{stem}.ogg"), "-ar", "44100",
                        "-af", "afade=t=in:d=1.2,afade=t=out:st=37:d=3",
                        "-c:a", "libmp3lame", "-b:a", "112k", str(out / f"{stem}.mp3")],
                       check=True)
    for stem in CUES:
        subprocess.run([tool, "-y", "-loglevel", "error", "-i", str(SFX / f"{stem}.wav"),
                        "-ac", "1", "-ar", "22050", "-c:a", "libmp3lame", "-b:a", "64k",
                        str(out / f"{stem}.mp3")], check=True)
    size = sum(path.stat().st_size for path in out.glob("*.mp3"))
    print(f"audio: {len(TRACKS)} previews, {len(CUES)} cues, {size / 1e6:.1f} MB")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--audio", action="store_true", help="also encode the MP3 previews")
    args = parser.parse_args()
    images()
    if args.audio:
        audio()


if __name__ == "__main__":
    main()
