# Working on Crazy Legs Mundell Rampage

A 1997-style FPS in the spirit of Redneck Rampage. The game is the Godot
4.7.2 project in `godot/`, and it is its own reference. It was ported from a
Python/pygame game, kept at the git tag `python-original` and no longer on the
main line. The world is drawn by a 3D view (`godot/src/view3d/`) that keeps
the old 320x200 look; the software renderer is gone. The levels are
`godot/data/*.json`; the art and sound in `assets/` are made by the Godot art
tools in `godot/tools/art/` (with Blender for the 3D renders and models) and
the sound in `audio_src/` by the Python tools in `scripts/`. The detail is in
`docs/dev/` (index at the end).

## Rules from the owner

- **Redneck Rampage style comes first** in every visual and audio decision,
  but every asset is original: never copy Redneck Rampage art, sound or maps.
- **Never open, print or `cat` `.env`.** It holds the ElevenLabs key. Never
  ask for a key in chat and never put one in code.
- **ElevenLabs: 100,000 credits, cumulative, hard ceiling** (raised from
  80,000 by the owner on 2026-11-13). The ledger is `audio_src/ledger.json`;
  check `.venv\Scripts\python.exe scripts/audio_generator.py status` before
  spending. Never run two generation processes at once. Any separate dollar
  billing needs the owner's approval first.
- **Never run `git clean` or delete untracked files.**
- Work on branch `combat-overhaul`; `main` is fast-forwarded to it when the
  owner says to publish. A `v*` tag publishes the EXE, installer and APK.
  Ask before publishing. Since v3.0.0 the 3D rewrite (once branch
  `godot-3d`) is the main line; `godot-3d` is kept only as history.
- Say plainly what was not checked. Nobody on the agent side can listen to
  the audio, play the game by hand, or try it on a phone.

## Layout

| Path | What it is |
| --- | --- |
| `godot/src/` | The game (GDScript). Two chains of layers, each file extending the one before: front end `main_state` -> `main_flow` -> `main_input` -> `main`; play `game_state` -> `game_world` -> `game_combat` -> `game_view` -> `game`. `view3d/` the 3D view (`View`, `WorldView3D`), `display.gdshader` the picture players see, `ui/` the menu screens, `core/` the event hub and tuning loaders, `features/`, `modes/`, `bosses/`, `net/` |
| `godot/tools/` | Headless checks and tools (excluded from exports); `levels/` the level builder and plans; `art/` the art builders |
| `godot/data/` | Levels (`<id>.json`) and `tuning/`: every number (weapons, enemies, shots, effects, breakables, store, difficulty, hits, modes, bosses, lobby, County Run). Edit these, not the scripts |
| `godot/assets_gen/` | Packed art, sound and levels. Generated, not committed |
| `godot/assets3d/`, `godot/scenes/` | The 3D models (`props/`, `actors/` glb + json) and their scenes (`PropView`, `ActorView`) |
| `scripts/` | Python: the sound (`audio_*`: ElevenLabs, budget ledger, mastering), the landing page's pictures (`build_site_assets.py`), and the Blender scripts (`blender/`, run inside Blender's own Python) |
| `site/` | The landing page; the browser builds deploy under `play/` and `play/lite/` |
| `.github/workflows/release.yml` | Checks and the 3D view's picture comparison on every push; the builds, the release and the site on `main`, `v*` tags or a run started by hand |
| `docs/dev/` | The developer docs this file points to |

## Commands

Godot is `C:\Users\treym\OneDrive\Desktop\Tools\Godot_v4.7.2-stable_win64_console.exe`
(written `godot`). Python only for sound, the site's pictures and lint, from
the repo's `.venv` (`requirements-dev.txt`). The full list is
[docs/dev/commands.md](docs/dev/commands.md).

```
godot --headless --path godot --script res://tools/pack_assets.gd   # rebuild godot/assets_gen (after any art)
godot --headless --path godot --import                               # after adding a class_name script or .glb

# Checks: all at once, each in its own process and scratch profile
godot --headless --path godot --script res://tools/check_all.gd -- quick   # about a minute: after every change
godot --headless --path godot --script res://tools/check_all.gd -- lint    # everything + gdformat/gdlint: end of a piece of work
cd godot && gdformat --check src tools addons && gdlint src tools addons   # .venv\Scripts\gdformat, gdlint
godot --headless --path godot --script res://tools/check_fixes.gd     # PARITY FIXES OK
godot --headless --path godot --script res://tools/view3d_check.gd    # VIEW3D CHECK OK
godot --headless --path godot --script res://tools/save_fixtures.gd   # OLD SAVES OK
godot --headless --path godot --script res://tools/quest_reach.gd     # QUEST REACH OK

# The 3D view needs a window
godot --path godot --audio-driver Dummy --resolution 1280x800 -- --view-tour=res://tools/picture_views.json --view-out=<dir>
godot --headless --path godot --script res://tools/compare_3d.gd -- <dir>   # against tools/pictures_3d (update: rewrite, commit)
godot --path godot --audio-driver Dummy --resolution 1280x800 -- --view-bench=300

# Version; publish (ask the owner first)
godot --headless --path godot --script res://tools/version.gd -- 3.0.N
godot --headless --path godot --script res://tools/release.gd -- 3.0.N
```

## Never forget

- **Layers only call down.** A function may call its own layer or the ones
  below; calling up is a parse error. New fields go in the bottom layer
  (`game_state.gd`, `main_state.gd`). Files stay under 1,500 lines (gdlint).
  [architecture.md](docs/dev/architecture.md)
- **Shell quirks on this machine.** Bash heredocs collapse backslashes and
  break on `'''`: write patch scripts to a file with the Write tool. A failed
  command in a `&&` chain without `set -e` does not stop later ones, so check
  the diff before committing, pushing or tagging. Run `git checkout --
  godot/icons` before committing.
- **`gh` is not logged in.** Read CI through the public API with curl.
  [checks.md](docs/dev/checks.md)
- **Close browser tabs and preview servers after testing.** The owner has
  heard game audio from tabs left open.
- **Benchmarks are noisy** (the owner's game, Steam and more run on this PC).
  Compare old and new back to back; give window runs a scratch `APPDATA`.
  [checks.md](docs/dev/checks.md#benchmarks)
- **Tool scripts never write the player's settings**; tests write saves under
  `OS.get_cache_dir()`. A view tour draws with default settings, never the
  profile's. [gameplay.md](docs/dev/gameplay.md)
- **Saves are versioned.** Changing what a save holds: bump
  `SessionStore.VERSION`, add the step in `src/save_upgrade.gd`, run
  `save_fixtures.gd -- make`. Never delete old fixtures. A map change bumps
  the plan's `layout`. [levels.md](docs/dev/levels.md#layouts-and-saves)
- **Gameplay randomness comes from `game.rng`.** Cosmetic effects use their
  own seeded dice so they never change play; keep tick changes exact.
  [gameplay.md](docs/dev/gameplay.md)
- **Snapshot field lists must include new fields.** Every Game field goes in
  `SIM_FIELDS`, `PLAYER_FIELDS` or `VIEW_FIELDS`, every feature in
  `SIM_FEATURES` or `LOOKS_FEATURES` (`game_snapshot.gd`); `net_check` fails
  otherwise. [multiplayer.md](docs/dev/multiplayer.md#simulation-vs-presentation)
- **`game.player` is the acting player**, not always the local one; play must
  never read `game.local_player` to change anything carried.
  [multiplayer.md](docs/dev/multiplayer.md)
- **Shaders:** a shader that writes ALPHA anywhere becomes transparent (keep
  solid and glass split); texture counts are capped (`check_shader.gd`).
  [view3d.md](docs/dev/view3d.md)
- **Edit tuning, not scripts**, and add new guns at the end of weapons.cfg.
  [data.md](docs/dev/data.md)
- **The game code is strictly typed.** Untyped and unsafe GDScript warnings
  are errors in `src/` (tools and addons are exempt). Type every declaration;
  read an untyped value into a typed variable (`var hp: int = d["hp"]`), not
  `as` or `int()`. `game.sound` is a `GameSound`.
  [architecture.md](docs/dev/architecture.md#static-typing)

## Index

| File | What is in it |
| --- | --- |
| [architecture.md](docs/dev/architecture.md) | The big picture: the layer chains, the 3D view, GameEvents, features, data, UI |
| [view3d.md](docs/dev/view3d.md) | The 3D view: `View`, `WorldView3D`, the shaders, props and actors, HD, draw distance |
| [ui.md](docs/dev/ui.md) | Menu screens as Controls: UiRoot, UiScreen, PixelButton, the screens, input |
| [data.md](docs/dev/data.md) | Every tuning file, its loader, and the rules for adding to them |
| [gameplay.md](docs/dev/gameplay.md) | Play's easy-to-get-wrong parts: events, sprites, levels in play, enemies, hits, squads, chatter, breaking, gore, mood, the tick |
| [audio.md](docs/dev/audio.md) | The sound: making and finishing cues, takes and per-play dice, hearing through walls and floors, the 3.0.0 measurements |
| [bosses.md](docs/dev/bosses.md) | The boss framework, the eight arenas, boss and hand art, fight music, checkpoint and rematch |
| [multiplayer.md](docs/dev/multiplayer.md) | Players, snapshots, the host, the mirror, the transport, online 5v5, lobbies, the crash log |
| [modes.md](docs/dev/modes.md) | Co-op, deathmatch, team DM, the 5v5 rounds, store rules, tag team, prediction, browser online |
| [county_run.md](docs/dev/county_run.md) | County Run: the mode, weapons, XP, offers, spawner, maps, co-op, daily run |
| [levels.md](docs/dev/levels.md) | The level builder, the plans, building and editing levels, layouts and saves |
| [art.md](docs/dev/art.md) | The art builders, Blender scripts, the 3D asset pipeline, gun effects art |
| [checks.md](docs/dev/checks.md) | Every check, check_all, CI, picture references, the launch check, benchmarks |
| [commands.md](docs/dev/commands.md) | The full command catalogue |
| [how_to_add.md](docs/dev/how_to_add.md) | Recipes: a gun, enemy, prop, level, feature, setting, menu, tuning number, event, boss, mode, County Run card |

Other docs: `docs/multiplayer.md` (the networking plan), `docs/online.md`
(playing and serving online), `docs/godot3d/` (the 3D rewrite's plan and
progress), `COUNTY_RUN.md`, `MAP_AUTHORING.md`.
