"""Build the landing page's images and audio previews from the game's assets.

    python scripts/build_site_assets.py                 # images (Pillow)
    python scripts/build_site_assets.py --audio         # also MP3 previews (ffmpeg)
    python scripts/build_site_assets.py --take <dir>    # finish new window captures first

Everything under ``site/img`` and ``site/audio`` comes from files the game
already ships, so the page never shows art or plays sound that is not in the
game. The results are small and committed; rerun this after the art changes.

  site/img/weapons/<name>.png   one strip of view-model frames per weapon
  site/img/faces.png            the twelve status-bar expressions
  site/img/shot_<id>.png        chapter pictures          } window captures of the
  site/img/fight_<boss>.png     each boss in its arena    } 3D view, kept finished in
  site/img/feature_<name>.png   the "what's in it" board  } docs/media/site_shots
  site/audio/<stem>.mp3         40-second soundtrack previews and short cues
  site/js/frames.js             frame counts and sizes for the strips

The captures come from the game in a window, run with a scratch APPDATA and
``--audio-driver Dummy --resolution 1280x800`` (never the player's profile):

  shot_*      ``-- --view-tour=<abs path>/scripts/site_views.json --view-out=<dir>``
              (the ``<tag>_fx.png`` files; most viewpoints are the chapter
              openers' cameras from data/tuning/openers.json)
  fight_*     tools/arena_frames.gd and arena_frames_late.gd (a fight or its
              third phase); the Revenue Man is site_views.json's ``rev_f``
  feature_*   tools/mode_frames.gd (coop_partner, tdm_play, tac_bodies),
              county_frames.gd (county_hickston_cards), vehicle_set_frames.gd
              (run_heat_1_turn), hound_frames.gd (hound_bay), events_frames.gd
              (event_twister_far, event_breaker), set_piece_frames.gd
              (hickston_town-tower_3_burst) and ``--opener=moonshine
              --opener-out=<dir>`` (moonshine_line). Pass 13 (3.8 to 3.11):
              break_frames.gd (barrel_gun_2: feature_break), blast_frames.gd
              (wreck_side_15: feature_wreck), onboard_walk.gd
              (onboard_07_tip_fire: feature_tips), set_piece_frames.gd
              (hickston_gas-line_2_running: feature_fuel); feature_blue, _barn,
              _blast, _ragdoll and _fivev5 from a throwaway script built on
              hound_frames (the trot posed, gait 0), set_piece_frames
              (Hickston's orchard shed 102 ticks after its posts go, from the
              tool's own spot), blast_frames (a powder keg six cells off, 54
              ticks on), death_frames (a coot, buckshot from his side, 30
              ticks on, each tick drawn) and tactical_frames (bots playing a
              holler round, the shine bomb just planted)

Copy the ones wanted into one folder under the site's names (shot_hickston.png
and so on) and pass it to --take: each is cut to the 4:3 picture the game
shows (the window's bars either side dropped), brought back to the game's own
320x200 pixels and colours (at most 256, so nothing is lost) and stretched to
640x480 as the game stretches it, then kept in docs/media/site_shots.
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
    "revenue_man_0": "boss_revenue_man",
    "player_front_0": "mundell", "hickston_icon": "icon",
}
# Window captures of the 3D view, finished by --take into docs/media/site_shots
# (640x480: the game's 320x200 stretched to 4:3).
SHOTS = ("shot_hickston", "shot_fair", "shot_sawmill", "shot_quarry", "shot_hub", "shot_bayou",
         "shot_speedway", "shot_moonshine", "shot_mothership", "shot_range")
# The fight card: each boss in its arena.
FIGHTS = ("fight_sheriff", "fight_jerry", "fight_rudy", "fight_foreman", "fight_baron",
          "fight_king", "fight_boggs", "fight_revenue", "fight_maw")
# The "what's in it" board: the modes and the newer features.
FEATURES = ("feature_coop", "feature_deathmatch", "feature_showdown", "feature_county",
            "feature_vehicle", "feature_blue", "feature_twister", "feature_blackout",
            "feature_destruction", "feature_opener", "feature_county_xp",
            # Pass 13: the site brought up to 3.11 (breaking, blasts, wrecks,
            # bodies, the tips, a 5v5 round).
            "feature_break", "feature_barn", "feature_blast", "feature_wreck",
            "feature_ragdoll", "feature_tips", "feature_fivev5", "feature_fuel")
TRACKS = ("title", "music", "county_line", "porchlight_stomp", "fair_score", "tickets_after_dark",
          "closing_time_shuffle", "mill_score", "green_chain", "apron_run", "quarry_score",
          "copper_and_steam", "last_load", "bayou_score", "cypress_crawl", "crawdad_boil_hop",
          "music_speedway", "pit_row_boogie", "checkered_flag_rag", "moonshine_score",
          "fight_moonshine", "mothership_score",
          "boss_hickston", "boss_fair", "boss_mill", "boss_quarry", "boss_bayou",
          "boss_speedway", "boss_moonshine", "boss_mothership")
CUES = ("yee_haw", "yee_haw_alt", "belch", "gulp", "moonshine", "shotgun_both", "cow_moo",
        "pig", "chicken", "rudy_horn", "sheriff_siren", "got_bessie", "king_holler", "gator_snap",
        "lap_car_pass", "maw_holler",
        # The bosses talking (their trash talk on the holler board).
        "boss_sheriff_intro", "boss_jerry_taunt_1", "boss_rudy_intro", "boss_foreman_intro",
        "boss_baron_intro", "boss_swamp_king_intro", "boss_boggs_taunt_0", "boss_maw_worried",
        "boss_revenue_man_taunt_0",
        # The hound, the county radio and the county events (content pass 8).
        "hound_bay", "hound_whistle", "dj_id_0", "tornado_siren", "raid_siren")


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


def finish(source: Path, target: Path) -> None:
    """A window capture as the site shows it: the 4:3 picture only, at the
    game's own 320x200 pixels and colours, stretched to 640x480."""
    image = Image.open(source).convert("RGB")
    width, height = image.size
    wide = round(height * 4 / 3)
    if width > wide:  # the window's bars either side of the 4:3 picture
        left = (width - wide) // 2
        image = image.crop((left, 0, left + wide, height))
    image = image.resize((320, 200), Image.NEAREST)
    colours = image.getcolors(256)
    if colours is not None:  # the game's grade: an exact palette, nothing lost
        flat = [channel for _, rgb in colours for channel in rgb]
        palette = Image.new("P", (1, 1))
        palette.putpalette(flat + [0] * (768 - len(flat)))
        image = image.quantize(palette=palette, dither=Image.Dither.NONE)
    else:
        image = image.quantize(256, dither=Image.Dither.NONE)
    image.resize((640, 480), Image.NEAREST).save(target, optimize=True)


def take(folder: Path) -> None:
    SHOTS_DIR.mkdir(parents=True, exist_ok=True)
    found = 0
    for name in SHOTS + FIGHTS + FEATURES:
        source = folder / f"{name}.png"
        if source.exists():
            finish(source, SHOTS_DIR / f"{name}.png")
            found += 1
    print(f"take: {found} captures finished into docs/media/site_shots")


def images() -> None:
    (SITE / "img" / "weapons").mkdir(parents=True, exist_ok=True)
    (SITE / "js").mkdir(parents=True, exist_ok=True)
    table = {name: strip(name, stem, poses) for name, (stem, poses) in WEAPONS.items()}
    table["faces"] = faces()
    for source, target in COPIES.items():
        Image.open(ART / f"{source}.png").save(SITE / "img" / f"{target}.png", optimize=True)
    for name in SHOTS + FIGHTS + FEATURES:
        shutil.copyfile(SHOTS_DIR / f"{name}.png", SITE / "img" / f"{name}.png")
    (SITE / "js" / "frames.js").write_text(
        "// Written by scripts/build_site_assets.py: sprite strip sizes.\n"
        f"window.CLM_FRAMES = {json.dumps(table, separators=(',', ':'))};\n",
        encoding="utf-8", newline="\n")
    pictures = len(COPIES) + len(SHOTS) + len(FIGHTS) + len(FEATURES)
    print(f"images: {len(table)} strips, {pictures} pictures")


def audio() -> None:
    tool = shutil.which("ffmpeg")
    if not tool:
        raise SystemExit("ffmpeg is needed for --audio.")
    out = SITE / "audio"
    out.mkdir(parents=True, exist_ok=True)
    for stem in TRACKS:
        # Forty seconds from a little way in, faded at both ends. A fight or
        # boss loop is a short seamless loop (under a minute): it runs into
        # its second time round.
        again = ["-stream_loop", "1"] if stem.startswith(("boss_", "fight_")) else []
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
    parser.add_argument("--take", type=Path, help="finish new window captures from this folder first")
    args = parser.parse_args()
    if args.take:
        take(args.take)
    images()
    if args.audio:
        audio()


if __name__ == "__main__":
    main()
