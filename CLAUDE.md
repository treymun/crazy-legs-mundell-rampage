# Working on Crazy Legs Mundell Rampage

A 1997-style FPS in the spirit of Redneck Rampage. The game is the Godot
4.7.2 project in `godot/`, and it is its own reference. It was ported from a
Python/pygame game, kept at the git tag `python-original` and no longer on the
main line. The levels are `godot/data/*.json`; the art and sound in `assets/`
are made by the Godot art tools in `godot/tools/art/` (with Blender for the
3D renders) and the sound in `audio_src/` by the Python tools in `scripts/`.

## Rules from the owner

- **Redneck Rampage style comes first** in every visual and audio decision,
  but every asset is original: never copy Redneck Rampage art, sound or maps.
- **Never open, print or `cat` `.env`.** It holds the ElevenLabs key. Never
  ask for a key in chat and never put one in code.
- **ElevenLabs: 80,000 credits, cumulative, hard ceiling.** The ledger is
  `audio_src/ledger.json`; check `.venv\Scripts\python.exe scripts/audio_generator.py status`
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
| `godot/data/tuning/` | Weapon, enemy, shot and effect definitions and numbers (`weapons.cfg`, `enemies.cfg`, `shots.cfg`, `effects.cfg`): fire rates, damage, reloads, how each gun fires (hitscan, pellets, projectile, melee), sits in view and sounds; enemy health, speed, reach, voice, boss title and drops; each shot's fall, size, glow and blast; lights and glows. The guns are weapons.cfg's sections in order: a new one goes at the end (section plus art). A new enemy can be a section with `brain=<kind>` (it acts as that kind) plus its art. Edit these, not the scripts; a running game from the project folder reloads them within a second |
| `godot/assets_gen/` | Packed art, sound and levels. Generated, not committed |
| `godot/tools/levels/` | The level builder: `level_builder.gd` (yards, rooms, buildings, fences, doors, fixtures, signs, actors; works out the walls, skins rooms, bands building fronts, checks the plan) with its kit (gates, lamps, poles, booths, trailers, stations, `town()` props, rock risers per floor) and each level's plan: `hickston_plan.gd` (+ `hickston_cast.gd`), `fair_plan.gd`, `sawmill_plan.gd`, `quarry_plan.gd`, `hub_plan.gd` (the Crossroads). Every prop is placed by hand: nothing scatters things to fill ground (the owner: "don't fill a spot just to fill it"); a yard that reads unfinished gets a set piece, a few things that belong together against a wall. After the plan, `mount_signs()` turns any flat sign or piece of equipment whose face looks into a wall, puts a plank backing behind one with nothing behind it, and posts under one up off the ground (cut-outs get posts only; ground decals are left alone). `build_level.gd` prints how much open ground has nothing near it (red on its map picture): information, not a target. `build_level.gd -- <id> map=<png>` writes `data/<id>.json` and a top-down picture, and stops on problems: a thing in a wall or furniture, furniture cutting a path, a picture missing, anything the start cannot walk to |
| `godot/tools/art/` | The art builders (GDScript, run like the other tools): `build_fx_art`, `build_gore_art`, `build_menu_art`, `build_building_tiles`, `build_town_signs` (Hickston's painted signs and the corn tile), `build_town_props` (runs `scripts/blender/town_props.py` and `props_more.py`: every chapter's modelled props, `town_<name>`, their sizes in `assets/art/town_props.json` for the level builder's `town()`), and `build_enemy_actors` / `build_weapon_views`, which run Blender and then shrink, grade and digitize its renders; `paint.gd` is their drawing library. Each takes `out=<dir>` to write somewhere else for a comparison. Their pictures have the old Python builders' look, not their exact bytes |
| `scripts/` | Python: the sound (`audio_*`: ElevenLabs, budget ledger, mastering), the landing page's pictures (`build_site_assets.py`), and the Blender scripts (`blender/`, run inside Blender's own Python) |
| `site/` | The landing page; the browser builds deploy under `play/` and `play/lite/` |
| `.github/workflows/release.yml` | Checks and the shader-view comparison on every push; the four builds, the release and the site on `main`, `v*` tags or a run started by hand (packs are cached until an asset changes) |

## Commands

Building and checking the game, and making its art, need only Godot (and
Blender for the enemy and weapon renders). Python is only for the sound tools,
the landing page's pictures and gdformat/gdlint, all in the repo's one
`.venv` (`requirements-dev.txt`: numpy, Pillow, elevenlabs, dotenv, gdtoolkit):
run them with `.venv\Scripts\python.exe`, and lint with `.venv\Scripts\gdformat`
and `gdlint`. Godot is
`C:\Users\treym\OneDrive\Desktop\Tools\Godot_v4.7.2-stable_win64_console.exe`.

```
godot --headless --path godot --script res://tools/pack_assets.gd   # rebuild godot/assets_gen (no Python)

# Art (then pack_assets): see godot/tools/art/
godot --headless --path godot --script res://tools/art/build_fx_art.gd       # also gore, menu, building tiles
godot --headless --path godot --script res://tools/art/build_enemy_actors.gd -- kinds=billy no-render   # weapon views likewise
godot --headless --path godot --script res://tools/art/build_town_props.gd -- names=outhouse,still   # Blender; no-render reuses
godot --headless --path godot --import        # after adding a class_name script

# Checks (all run in CI too). One command runs them all at once, each in
# its own process and scratch profile, with one table (lint: gdformat and
# gdlint too; fast: without the walkthrough and the pictures):
godot --headless --path godot --script res://tools/check_all.gd -- lint
cd godot && gdformat --check src tools addons && gdlint src tools addons
godot --headless --path godot --script res://tools/verify_assets.gd   # ASSETS OK
godot --headless --path godot --script res://tools/check_fixes.gd     # PARITY FIXES OK
godot --headless --path godot --script res://tools/bot_campaign.gd    # CAMPAIGN WALKTHROUGH OK
godot --headless --path godot --script res://tools/picture_check.gd   # PICTURES OK
godot --headless --path godot --script res://tools/save_fixtures.gd   # OLD SAVES OK
godot --headless --path godot --script res://tools/level_edit_check.gd  # LEVEL EDIT OK
godot --headless --path godot --script res://tools/bench.gd -- 150    # frame time, CPU side

# Pacing and balance (not in CI)
godot --headless --path godot --script res://tools/first_minutes.gd   # a bot plays each chapter's opening: first fight, kills, health (old-ai: enemies do not hunt)
godot --headless --path godot --script res://tools/ttk.gd -- ../docs/weapon_ttk.md   # time to kill, every gun against every enemy
godot --headless --path godot --script res://tools/route_map.gd -- <dir>   # each level's objective route, long detours flagged, PNGs

# Pictures changed on purpose: rewrite the references and commit them
godot --headless --path godot --script res://tools/picture_check.gd -- update

# In a real window (the graphics-card view only runs with one)
godot --path godot --audio-driver Dummy --resolution 1280x800 -- --view-bench=300
godot --path godot --audio-driver Dummy --resolution 1280x800 -- \
  --view-tour=res://tools/picture_views.json --view-out=<dir>
godot --headless --path godot --script res://tools/compare_views.gd -- <dir>   # shader view (no lights) against software view
godot --headless --path godot --script res://tools/compare_views.gd -- <dir> refs   # shader view against tools/pictures_gpu (update: rewrite them)

# Levels built from a plan (all four chapters): change the plan and rebuild; an edit to
# its JSON is lost at the next build. Bump the plan's "layout" when the map
# changes so old saves of it start the chapter over (see below).
godot --headless --path godot --script res://tools/levels/build_level.gd -- fair map=<png>   # hickston, fair, sawmill, quarry
godot --headless --path godot --script res://tools/first_minutes.gd -- hickston whole   # bot plays it to the end (god mode)

# Levels: godot/data/<id>.json is the source. Change one in the Godot editor's
# Levels screen (addons/clmr_levels: paint walls, floors, enemies, pickups and
# trigger areas, with undo, then Save; Play from here), in the game (F2 when
# running from the project folder) or from the command line; every way the
# wall list is patched (src/level_edit.gd) and a running game reloads the level.
godot --headless --path godot --script res://tools/level_edit.gd -- fair enemy billy 30.5 25.5
godot --headless --path godot --script res://tools/level_edit.gd -- hickston trigger '<json>'   # src/triggers.gd

# Version
godot --headless --path godot --script res://tools/version.gd -- 2.0.0-dev.N

# Publish (ask the owner first): stamps, commits, pushes, waits for CI, moves
# main, tags, then checks the site and the release's three files
godot --headless --path godot --script res://tools/release.gd -- 2.0.0-dev.N
```

## Things that are easy to get wrong

- **One renderer.** With a window, `palette.gdshader` composes the view from
  layers the renderer hands over (`Renderer.layered`), and that is the picture
  players see; there is no setting to turn it off. The software view is the
  fallback (headless tools and CI, and a graphics driver that fails the start-up
  check) and is frozen: build new visuals in the shader only, behind
  `effects_on` (lights and glows from `data/tuning/effects.cfg`). Two checks
  hold the line: `tools/compare_views.gd` holds the shader view with effects off
  against the software view, and with `refs` holds the full shader view against
  `tools/pictures_gpu/` (rewrite with `update`, from a window tour, and commit).
  A view tour always draws with the default settings, never the profile's
  (the owner's own copy shares it): a lowered gun or the film look in a local
  reference fails CI's Mesa window, which has none.
  `tools/picture_check.gd` still guards the software fallback.
- **VIEW DETAIL HD** (setting value 3, off by default) is `Renderer.set_detail(-1)`:
  the view is drawn 640x312 at twice the focal length and the display shader
  shows it at that size (`view_mul`), while the weapon, HUD and their effects
  stay 320x200. The software view has no HD (game_view.gd drops to HIGH). Rows
  past 255 exist in HD: pack a row into 10 bits, not 8 (wall spans do). It
  costs about 2.3x the shader view's frame time.
- **The automap** (`game_view.gd`) follows the player at a readable zoom
  (PGUP/PGDN, keypad +/-, the mouse wheel; zoom 0 fits the level), from an
  image of the whole map at that scale (walls as lines, ground by kind,
  walked ground painted on as it is walked). A tour viewpoint may set `map`
  and `map_zoom`.
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
  `tools/check_shader.gd` (in CI) counts them; eight are used now (the level's
  plane table and light map have their own `planes`, sent only when the level
  or its light changes). Stack new data into an existing texture instead of
  adding one.
- **What the shader view is sent each frame** (`scene_layers.gd frame()`): only
  the parts the renderer drew. `pixels_on` off (every wall a span: no wall
  pixel, code or distance), `over_on` off (no ground mark or wall mark pixel)
  and `pane_on` off leave those parts out of `colours` and `spans`, and
  uniforms say where each part starts (`over_row`, `stream_row`, `cover_at`,
  `pane_row`, `dist_start`). A texture is kept for each size it has been, and a
  shader number is only set when it changes (`_set_param`). Layered, the
  renderer keeps its pass buffers from frame to frame (only the overlay, span
  counts, distances and glass start cleared): never hand one of its arrays to
  an Image or texture directly, copy it (`scene_layers.gd` does).
- **The renderer culls before it draws, and must stay exact.** `_prepare()`
  projects only fixed walls in map blocks the view (or the mirror's view) can
  reach (`_block_walls`; doors, panes and gates are tested every frame), gives
  each wall only the columns its ends span plus the bands' tolerance, and
  `_wall_band` trims columns already covered by nearer walls before setting a
  wall up, drops a span wholly inside one nearer span, and leaves out mirror and
  glass pixels nearer spans hide (a hidden mirror would start a reflection
  pass). `game_view.gd sprites()` lists only what can show: fixed sprites in
  blocks (`fixed_blocks`), and enemies, pickups and effects through
  `in_view(x, y, reach)`; a new sprite source should use it too. The shader
  draws sprites in list order, so culling only ever leaves sprites out, never
  reorders them. A window tour of old and new code compared pixel for pixel is
  how these were checked: do the same after touching them.
- **A browser build asks the browser for its core count** (`RenderState.processors()`):
  Godot's own answer there is capped at two, which held the browser to one
  band thread although the build keeps 24 worker threads ready
  (`export_presets.cfg`).
- **Chapter music and chapter enemies are a separate download in the browser.**
  `tools/pack_assets.gd` writes `music_<chapter>.bin` and, for the enemies only
  one chapter has (`Assets.CHAPTER_KINDS`), `art_<chapter>.bin`; the web presets
  leave them out, CI turns each chapter's pair into a pack (`tools/make_packs.gd`)
  and `pack_loader.gd` fetches them after start. `main_flow.gd play()` holds a
  chapter until its pictures are there. A new enemy kind used in more than one
  level must not be in `CHAPTER_KINDS` (`verify_assets.gd` checks). A browser
  cannot rename files in its storage and HTTPRequest's `download_file` does not
  write there: keep writing packs from memory.
- **Sound effects are QOA** (`sfx.bin`, about a fifth of 16-bit samples), and
  the tiles and skies are deflated whole (`Assets.pack_whole`). An
  `AudioStreamWAV`'s `data` is then not samples: count frames with
  `get_length() * mix_rate`.
- **Band threads.** Inside the renderer's band loops, never call a script
  function, read a field of another object or use untyped `round`, `floor`
  or `ceil`. Each costs 5 to 11 times more while the other threads do the
  same. Tabulate on the main thread (see `_warm_art`) and use `roundf`,
  `floorf`, `ceilf`.
- **Benchmarks are noisy.** The owner's own copy of the game, Steam and other
  apps often run on this PC. Compare old and new back to back, never against
  a number from earlier. Window runs that change settings get a scratch
  `APPDATA` (the owner's profile is shared). For the browser, export both
  builds, serve each with COOP/COEP headers, add a page whose `GODOT_CONFIG`
  args are `["--", "--view-bench=300"]`, and run headless Chrome with its own
  `--user-data-dir` and `--disable-frame-rate-limit --disable-gpu-vsync`
  (otherwise it caps at about 240 fps, as vsync would); the numbers are in its
  console log (`--enable-logging=stderr`).
- **The Crossroads is `data/hub.json`** (`hub_plan.gd`), its own level (the hub
  game is `make_game("hub")`): its gates, clues, dispatch board (`hub_board`),
  start (`spawn`) and map window come from the file, not from code.
- **Levels have a `layout` number.** A save records it (save version 7); a save
  of an older layout of its level loads at that chapter's start with its guns,
  rounds, health and pockets (`session_store.gd _restart`), and a finished
  chapter of an older layout stays finished. Rebuilding a level's map means
  bumping its plan's `layout`, then `save_fixtures.gd -- make` and fixing the
  old fixtures' expected positions in `tools/saves/expected.json`. A save whose
  doors or enemies no longer match its level (changed without a new layout)
  restarts the chapter too, rather than failing to load.
- **Paths are planned cell to cell** (`flow_field.gd`: a cell is open when a body
  fits at its middle). A thin fixture across the line between two open cells
  traps the objective pin and the enemies alike: stand small pieces in a cell's
  middle and posts on its corners (`build_level.gd` reports any that cut).
- **Ledges a step won't climb** (more than .245 up) take a jump (about .6);
  the pin and the enemies plan paths without heights, so keep a ramp beside
  any drop on the way. `first_minutes.gd -- <id> whole` hops when stuck and
  shoots a station that is struck (the mill's belt).
- **The objective pin** leads to a station's carried item first while it lies
  somewhere (the fair's PA patch lead). The fair's tin rooster booth is where
  its level puts it (`gallery` in the JSON: the stand; targets 3.58 east).
- **Wall runs merge when a level loads** (`LevelData._merge_runs`): straight runs
  of one repeating material become one piece for the renderer, whose cost goes
  with the pieces in view. Files keep a piece per cell for the editors.
- **Saves are versioned.** Changing what a save holds means bumping
  `SessionStore.VERSION`, adding the step from the old version in
  `src/save_upgrade.gd`, and running `tools/save_fixtures.gd -- make` to add
  saves of the new version to `godot/tools/saves/`. Never delete the old ones:
  they are how CI knows players' saves still load.
- **Gameplay randomness** comes from the game's `rng`. Cosmetic effects use
  their own seeded generator (`gore_fx.dice`), so they never change play.
- **Settings** are listed in `src/setup_pages.gd` (one row each: label, key,
  default, choices, hint); `tools/check_fixes.gd` counts them. Settings are not
  part of a save, so a new one needs no save version.
- **The county's hands fight smart** (`enemies.gd`): a hurt hand may duck
  behind cover the player cannot see (`find_cover`), a badly hurt one runs to
  fetch a friend, and a stray shot from another hand starts a brawl (`hurt(...,
  by)` sets a grudge). `hurt()` also takes the gun's name (`how`): the REACTIONS
  table throws back, stuns, soaks (teat gun) or gibs by gun. A boss goes
  fightin' mad at half health (`_enrage`, `boss_enraged`: phase two) and gets a
  death moment (`_boss_falls`). DIFFICULTY runs EASY..HOG WILD (0..3):
  `game_world.gd configure()` sets `sharpness` (attack recovery, notice range,
  aim) and `ammo_scale`, and `features/posse.gd` adds partners on HARD and HOG
  WILD after the level's own enemies (saved in the features block, so a save
  checks its count against `enemy_ids.size()`). Set `alerted` by assignment:
  its setter counts changes, which `player_sheltered()` relies on.
- **Fight music** (`features/fight_music.gd`, `sound.gd` crossfade) swaps a
  chapter's music for its fight track (`assets/music/fight_*.ogg`, made by
  `audio_build.py --fights`) while hands hunt or attack nearby.
- **Tool scripts never write the player's settings** (`main_state.gd
  persist_options` returns when a script runs the main loop), and tests write
  saves under `OS.get_cache_dir()`. The gun pictures warm on a thread that
  `Weapons.Armory.settle()` waits for when the program closes.
- **Enemies path on a flow field** (`src/flow_field.gd`): out of sight, an
  alerted enemy walks downhill on the steps from the player for a few seconds
  (`Enemy.hunt_until`). The objective pin walks a second field measured from
  the objective (`Game.route`) through doors the player can open now.
- **Features listen to events.** `game_state.gd` announces `enemy_killed`,
  `player_hurt`, `pickup_taken`, `station_done`, `shot_fired`, `hit_landed`,
  `level_won`, `ticked`, `exploded`, `gun_reloading` and `traced` (where each
  hitscan shot, pellet, swing or squirt ended and what it struck).
  `weapon_fx` draws every gun's shot from those: fuse sparks, rocket and cow
  trails, blast dirt and cinders as sprites; tracers, rivets, the teat gun's
  milk, the Copperhead's steam and sparks over the view with `draw_view(c)`
  (a feature hook run after the world and before the gun), from the gun's
  muzzle on screen (`Armory.place_muzzle`, `Weapons.muzzle_at`) to where the
  shot struck (`Game.to_canvas` projects a world point onto the canvas).
  Draw lots of pixels there as cached pictures (`blit_rgba` with a key), not
  pixel by pixel: in the shader view each `set_pixel` is a draw command. A
  viewpoint in a window tour may name a `gun` (its index) and `fire` with
  `ticks` to show one gun firing; viewpoints after it keep firing it. A new piece of play goes in `src/features/` as a
  `GameFeature` (see `game_feature.gd`), listed in `features.gd`: it connects
  to those, saves its own state in the save's `features` block (restore gets
  {} from older saves, so no new save version), and may add a tally row.
  Triggers, lessons and chapter stats are features, and so is the polish that
  only looks: `weather` (lightning and thunder), `debris` (brass, hulls,
  embers, scorches, smoke, blood trails), `ambient` (crows, fireflies),
  `callouts` (TWOFER, HAT TRICK, HOG WILD, RAMPAGE) and `tally` (rows that
  thud down and a ribbon). Features may add sprites and ground marks; looks-only
  ones use their own dice so play never changes.
- **A level's mood** is `effects.cfg` `[level.<id>]`: fog colour and distance,
  grade, cloud drift, lightning, crows, fireflies; `[anim.<tile>]` makes a sign
  buzz or pulse. All of it is the shader's, behind LIGHTS AND GLOW.
- **Keep the Redneck Rampage feel** in new polish: dusk and dirt, brass and
  red hulls, crows, county-fair words and ribbons, cartoon wipes; original art
  and sound only (new small sounds can be made in `assets.gd` MADE_CUES).
- **The developer console** (` in play, project folder only, `dev_console.gd`):
  spawn, give, god, tp, time, trigger, reload, stats, and overlays (`show map`:
  walls, enemies by state with the hunting ones' paths, triggers, lights;
  `show fps`). `DevConsole.run()` takes the same text from scripts.
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
