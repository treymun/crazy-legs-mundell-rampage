# Working on Crazy Legs Mundell Rampage

A 1997-style FPS in the spirit of Redneck Rampage. The game is the Godot
4.7.2 project in `godot/`, and it is its own reference. It was ported from a
Python/pygame game, kept at the git tag `python-original` and no longer on the
main line. The levels are `godot/data/*.json`; the art and sound in `assets/`
and `audio_src/` are made by the Python tools in `scripts/`.

## Rules from the owner

- **Redneck Rampage style comes first** in every visual and audio decision,
  but every asset is original: never copy Redneck Rampage art, sound or maps.
- **Never open, print or `cat` `.env`.** It holds the ElevenLabs key. Never
  ask for a key in chat and never put one in code.
- **ElevenLabs: 80,000 credits, cumulative, hard ceiling.** The ledger is
  `audio_src/ledger.json`; check `python scripts/audio_generator.py status`
  before spending. Never run two generation processes at once. Any separate
  dollar billing needs the owner's approval first.
- **Never run `git clean` or delete untracked files.**
- Work on branch `combat-overhaul`; `main` is fast-forwarded to it when the
  owner says to publish. A `v*` tag publishes the EXE, installer and APK.
  Ask before publishing.
- Say plainly what was not checked. Nobody on the agent side can listen to
  the audio, play the game by hand, or try it on a phone.

## Layout

| Path | What it is |
| --- | --- |
| `godot/src/` | The game (GDScript). Three chains of layers, each file extending the one before: front end `main_state` -> `main_flow` -> `main_input` -> `main`; play `game_state` -> `game_world` -> `game_combat` -> `game_view` -> `game`; software view `render_state` -> `render_surfaces` -> `render_sprites` -> `renderer`. `palette.gdshader` + `scene_layers.gd` are the graphics-card view |
| `godot/tools/` | Headless checks and tools (excluded from exports) |
| `godot/data/tuning/` | Weapon and enemy numbers (`weapons.cfg`, `enemies.cfg`): fire rates, damage, reloads, how each gun sits in view, enemy health, speed, reach. Edit these, not the scripts; a running game from the project folder reloads them within a second |
| `godot/assets_gen/` | Packed art, sound and levels. Generated, not committed |
| `scripts/` | Python builders: art (`build_*`), audio (`audio_*`), version stamping |
| `site/` | The landing page; the browser builds deploy under `play/` and `play/lite/` |
| `.github/workflows/release.yml` | Checks and the shader-view comparison on every push; the four builds, the release and the site on `main`, `v*` tags or a run started by hand (packs are cached until an asset changes) |

## Commands

Building and checking the game needs only Godot. Python is only for the art
and sound tools in `scripts/` (Blender renders, digitizing, ElevenLabs,
mastering): use the repo's `.venv\Scripts\python.exe` (numpy, Pillow); the audio
scripts need the system Python, which has `dotenv` and `elevenlabs`. Godot is
`C:\Users\treym\OneDrive\Desktop\Tools\Godot_v4.7.2-stable_win64_console.exe`.

```
godot --headless --path godot --script res://tools/pack_assets.gd   # rebuild godot/assets_gen (no Python)
godot --headless --path godot --import        # after adding a class_name script

# Checks (all run in CI too)
cd godot && gdformat --check src tools && gdlint src tools
godot --headless --path godot --script res://tools/verify_assets.gd   # ASSETS OK
godot --headless --path godot --script res://tools/check_fixes.gd     # PARITY FIXES OK
godot --headless --path godot --script res://tools/bot_campaign.gd    # CAMPAIGN WALKTHROUGH OK
godot --headless --path godot --script res://tools/picture_check.gd   # PICTURES OK
godot --headless --path godot --script res://tools/bench.gd -- 150    # frame time, CPU side

# Pictures changed on purpose: rewrite the references and commit them
godot --headless --path godot --script res://tools/picture_check.gd -- update

# In a real window (the graphics-card view only runs with one)
godot --path godot --audio-driver Dummy --resolution 1280x800 -- --view-bench=300
godot --path godot --audio-driver Dummy --resolution 1280x800 -- \
  --view-tour=res://tools/picture_views.json --view-out=<dir>
godot --headless --path godot --script res://tools/compare_views.gd -- <dir>   # shader view against software view

# Version
godot --headless --path godot --script res://tools/version.gd -- 2.0.0-dev.N
```

## Things that are easy to get wrong

- **Two views.** With a window, `palette.gdshader` draws the sky, floors,
  ceilings and wall shading from layers the renderer hands over
  (`Renderer.layered`). Headless, and with FAST VIEW off, the renderer draws
  everything in software. A visual change usually needs both, and
  `tools/compare_views.gd` checks they agree.
- **Two canvases.** With a window the HUD, menus and weapon draw with Godot
  2D (`Canvas.gpu`): the same calls become canvas commands in a 320x200
  viewport the shader lays over the view. Shapes still come down to
  `set_pixel`, `_hspan`, `_vspan` and `fill_rect`, so a new shape drawn
  through those works in both. Never write `canvas.pixels` directly for
  something on screen; give `blit_rgba` a cache name. Headless (tools, CI)
  and `--cpu-canvas` draw in software.
- **Nine textures at most in `palette.gdshader`.** WebGL and many phones give a
  shader 16 texture units and Godot keeps several; past nine the browser
  and Android builds draw nothing while a desktop looks fine.
  `tools/check_shader.gd` (in CI) counts them. Stack new data into an existing
  texture instead of adding one.
- **Chapter music is a separate download in the browser.** `tools/pack_assets.gd`
  writes `music_<chapter>.bin`, the web presets leave them out, CI turns them
  into packs (`tools/make_packs.gd`) and `pack_loader.gd` fetches them after
  start. A browser cannot rename files in its storage and HTTPRequest's
  `download_file` does not write there: keep writing packs from memory.
- **Band threads.** Inside the renderer's band loops, never call a script
  function, read a field of another object or use untyped `round`, `floor`
  or `ceil`. Each costs 5 to 11 times more while the other threads do the
  same. Tabulate on the main thread (see `_warm_art`) and use `roundf`,
  `floorf`, `ceilf`.
- **Benchmarks are noisy.** The owner's own copy of the game, Steam and other
  apps often run on this PC. Compare old and new back to back, never against
  a number from earlier.
- **Gameplay randomness** comes from the game's `rng`. Cosmetic effects use
  their own seeded generator (`gore_fx.dice`), so they never change play.
- **Layers only call down.** In those chains a function may call functions of
  its own layer or the layers below it; calling up is a parse error. New
  fields go in the bottom layer (`game_state.gd`, `render_state.gd`,
  `main_state.gd`). Files stay under 1,500 lines (gdlint).
- **Shell quirks on this machine.** Bash heredocs collapse backslashes and break
  on `'''`: write patch scripts to a file with the Write tool. A failed command
  in a `&&` chain without `set -e` does not stop later ones, so check the diff
  before committing, pushing or tagging. Run `git checkout -- godot/icons`
  before committing.
- **`gh` is not logged in.** Read CI through the public API with curl.
- **Close browser tabs and preview servers after testing.** The owner has
  heard game audio from tabs left open.
