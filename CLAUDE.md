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
| `godot/tools/levels/` | The level builder: `level_builder.gd` (yards, rooms, buildings, fences, doors, fixtures, signs, actors; works out the walls, skins rooms, bands building fronts, checks the plan) with its kit (gates, lamps, poles, fingerposts, booths, trailers, stations, `town()` props, rock risers per floor) and each level's plan: `hickston_plan.gd` (+ `hickston_cast.gd`), `fair_plan.gd`, `sawmill_plan.gd`, `quarry_plan.gd`, `bayou_plan.gd` (+ `bayou_cast.gd`; chapter 5), `speedway_plan.gd` (chapter 6), `mothership_plan.gd` (+ `mothership_cast.gd`; chapter 7, all indoors, the last), `range_plan.gd` (the firing range, not a chapter), `hub_plan.gd` (the Crossroads). Every prop is placed by hand: nothing scatters things to fill ground (the owner: "don't fill a spot just to fill it"); a yard that reads unfinished gets a set piece, a few things that belong together against a wall. After the plan, `mount_signs()` turns any flat sign or piece of equipment whose face looks into a wall, puts a plank backing behind one with nothing behind it, and posts under one up off the ground (cut-outs get posts only; ground decals are left alone). Quest props (`quest()`: a station's or the exit's modelled prop, `town_quest_<name>`, lit by its signal) stand free on the floor and get neither: stand one in a cell's middle or half a cell off a wall face, near its station (within 3.5). `build_level.gd` prints how much open ground has nothing near it (red on its map picture): information, not a target. `build_level.gd -- <id> map=<png>` writes `data/<id>.json` and a top-down picture, and stops on problems: a thing in a wall or furniture, furniture cutting a path, a picture missing, anything the start cannot walk to |
| `godot/tools/art/` | The art builders (GDScript, run like the other tools): `build_fx_art` (the soft older effects the software view draws), `build_gun_fx_art` (the shader view's muzzle flashes, blasts, soot, scraps, dust ring and strikes), `build_gore_art`, `build_menu_art`, `build_building_tiles`, `build_town_signs` (Hickston's painted signs and the corn tile), `build_bayou_art`, `build_speedway_art` and `build_ship_art` (each new chapter's tiles, sky or signs; the Mothership's alien-lettered signs and Maw's floor marks), `build_quest_art` (every chapter's quest props, modelled in Blender by `scripts/blender/quest_props.py` as freestanding props that read from any side: control boxes on posts with a throw lever, the relay cabinet, brake, bell, exit signal posts, valves, the bayou's generator and ignition, the speedway's fuel dump and flags, the Mothership's consoles; each station as `town_quest_<name>_off` (lamp lit, lever up) and `_on` (lamp dark, green pilot, lever thrown and tagged), cropped to one frame; the keys and the PA patch lead as rendered pickups; and, painted, Hickston's pen sign, the locked gate's barricade, the Crossroads' later gate boards and markers, the fingerpost's arms and the beam pad's order: signs, not stations), `build_town_props` (runs `scripts/blender/town_props.py`, which execs `props_more.py` and each chapter's `props_<chapter>.py`, then `props_range.py`: every chapter's modelled props, `town_<name>`, their sizes in `assets/art/town_props.json` for the level builder's `town()`), and `build_enemy_actors` / `build_weapon_views`, which run Blender and then shrink, grade and digitize its renders; `paint.gd` is their drawing library. Each takes `out=<dir>` to write somewhere else for a comparison. Their pictures have the old Python builders' look, not their exact bytes |
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
godot --headless --path godot --script res://tools/art/build_gun_fx_art.gd   # the shader view's flashes, blasts, strikes
godot --path godot --audio-driver Dummy --resolution 1280x800 --script res://tools/gun_frames.gd -- out=<dir>   # every gun firing, a blast
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
godot --headless --path godot --script res://tools/quest_reach.gd      # QUEST REACH OK (tour=<json> for pictures of each prop)
godot --headless --path godot --script res://tools/net_check.gd       # NET CHECK OK (players, snapshots, determinism; quick: check_fixes's part)
godot --headless --path godot --script res://tools/multi_bots.gd -- players=1,2,4 seconds=60   # MULTI BOTS OK (whole: to the end; mortal; diff=)
godot --headless --path godot --script res://tools/net_loopback.gd -- seconds=180 lag=50 loss=0.05   # NET LOOPBACK OK (websocket: over WebSocket)
godot --headless --path godot --script res://tools/mode_check.gd      # MODE CHECK OK (co-op, deathmatch; quick: check_fixes's part)
godot --headless --path godot --script res://tools/tactical_check.gd -- rounds=3   # TACTICAL CHECK OK (the 5v5 modes, ten bots, every map)
godot --headless --path godot --script res://tools/gun_sheet.gd   # the 5v5 guns' numbers side by side (md=<file>)
godot --headless --path godot --script res://tools/map_timing.gd   # 5v5 maps: run times to sites, bots' routes and holds checked (strict)
godot --headless --path godot --script res://tools/net_showdown_check.gd   # NET SHOWDOWN OK (online 5v5 lobby to lobby; lag= loss= seconds=)
godot --path godot -- --host-online[=port] --online-name=TREY [--online-password=x]   # straight into a lobby
godot --path godot -- --join-online=<code or address> --online-name=BOB   # (tests: --online-start=2 --online-bot)
godot --headless --path godot --script res://tools/levels/build_level.gd -- grainyard   # the 5v5 maps: grainyard, holler, salvage
godot --headless --path godot --script res://tools/bench.gd -- 150    # frame time, CPU side
godot --headless --path godot --script res://tools/net_bench.gd -- levels=hickston players=1,2,4 [host]   # ticks, snapshots, deltas
godot --headless --path godot -- --server=fair --server-players=2 --server-ticks=12000   # a host, no window (server_loop.gd)

# Pacing and balance (not in CI)
godot --headless --path godot --script res://tools/first_minutes.gd   # a bot plays each chapter's opening: first fight, kills, health (old-ai: enemies do not hunt)
godot --headless --path godot --script res://tools/ttk.gd -- ../docs/weapon_ttk.md   # time to kill, every gun against every enemy
godot --headless --path godot --script res://tools/route_map.gd -- <dir>   # each level's objective route, long detours flagged, PNGs
godot --headless --path godot --script res://tools/boss_rematch_check.gd -- bot   # the bot fights every boss rematch: time to kill (boss_rematch.gd PAR)
godot --headless --path godot --script res://tools/boss_rematch_check.gd -- only-bot kinds=boss,rudy difficulty=0,1,2,3   # per difficulty

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
  `tools/picture_check.gd` still guards the software fallback. The start-up
  check of a player's driver (`main_state.gd _check_view`) judges one frame
  drawn as the software view would draw it: at HIGH and without lights, glows,
  fog or grade (`hd_held`, `Effects.enabled` off for that frame only). It used
  to judge the full picture, which a moody level (Hickston) always failed, and
  that kept the whole session in software: no lights, no HD, four times slower.
  It waits until play is a third of a second in, treats a blank grab as not
  ready, and needs two real mismatches in a row: until dev.34 it judged a
  level's first frame, still black in a normal launch, and every player's
  session fell back to software. `--launch-check` (any build, the exported EXE
  too, with APPDATA pointed at a profile holding an options.json) launches as
  a player does and writes one line to the log (`LAUNCH CHECK: ... graphics-card
  view true  HD true`); `tools/launch_check.gd` is the project-folder twin.
- **VIEW DETAIL HD** (setting value 3, off by default) is `Renderer.set_detail(-1)`:
  the view is drawn 640x312 at twice the focal length and the display shader
  shows it at that size (`view_mul`), while the weapon, HUD and their effects
  stay 320x200. The software view has no HD: a frame drawn in software
  (a screenshot, the start-up check) draws at HIGH and keeps the wish
  (`set_detail(0, true)`, `hd_wanted`), so the next shader frame is HD again;
  never `set_detail(0)` for one frame. The film look (grain, dither, vignette)
  works on the view's own grid, so HD keeps its detail under it; HIGH is the
  320 grid as before. Rows past 255 exist in HD: pack a row into 10 bits, not
  8 (wall spans and the shader's wall table do). It costs about 1.5x the
  shader view's frame time on the desktop. Changing a setting shows what it
  did and that it was saved where the hint goes (`main_flow.gd`).
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
  something on screen; give `blit_rgba` a cache name. Each rect is a command,
  so what is drawn every frame from many shapes is drawn once in software and
  shown as a cached texture (the status bar, banners, the objective pin:
  `hud.gd _pin_texture`). Headless (tools, CI) and `--cpu-canvas` draw in
  software.
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
  `pane_row`, `dist_start`), as do the wall spans' rows (only as many as the
  fullest column needs, then the counts row at `count_row`, the sprites from
  `sprite_row`, the shader's wall table from `wall_row`). Each part carries only
  the view rows it wrote anything in: every band that writes a wall pixel, an
  overlay pixel or a pane sets that row's byte in `px_hit`, `over_hit` or
  `pane_hit` (a few rows too many at worst, never too few), `render_end()`
  turns them into `px_span`, `over_span`, `pane_span`, and the shader gets
  `px_rows`, `over_rows`, `pane_rows` and treats a pixel outside them as empty.
  A new pass that writes `depth`, `frame`, `wall_code`, `over*` or `pane_*`
  must mark its rows too. A texture is kept for each size it has been (heights
  rounded up to eight sizes an octave, `_tall`), and a shader number is only
  set when it changes (`_set_param`). Layered, the renderer keeps its pass
  buffers from frame to frame (only the overlay, span counts, distances and
  glass start cleared, and only when the frame before wrote in them; the
  overlay's distances never, being read only where its coverage is set; the
  counts are their own row, `span_c`): never hand one of its arrays to an
  Image or texture directly, copy it (`scene_layers.gd` does). Once
  `frame()` has copied the parts, `clear_ahead()` clears them on the idle
  set-up thread while the main thread finishes the frame and ticks;
  `frame_begin()` waits for it (`_settle_clear`, static: the thread is shared).
- **The shader finds most walls itself.** In the shader view the band threads
  no longer work out every wall's span down every column: `_prepare()` runs on
  the whole crew in chunks (`_prepare_chunk`) and, while projecting, packs each
  wall for the shader (four texels: columns, nearest distance, the per-column
  terms of t and u in double precision, rows it can reach, tile, light), a crew
  job beside the bands lists each block of columns' walls nearest first
  (`_fill_lists`), and `palette.gdshader walk_walls` finds each pixel's nearest
  wall with `_wall_band`'s own tests, stopping at the first wall past what it
  has. The bands draw walls only in columns that need the renderer's answer
  (`cpu_n`, `_cpu_columns`): a mirror's or glazing's columns, up to that wall,
  and a wall mark's columns, up to the last wall as near as the mark; the shader
  walks the rest of those columns after them. Over `GPU_WALLS` walls in view, or
  with `--cpu-walls`, the bands draw everything as before (a tour with
  `--cpu-walls` matches the old code exactly). Against the old shader view the
  walk differs only where float32 lands on the other side of a texel or row
  boundary than the CPU's double did: a few single pixels a view (tour: 7 of 75
  pictures, 176 window pixels; HD 11 of 66, one a row along a wall's top seen
  dead on). Sort keys are nearest << 32 | wall << 16 | table place.
- **The renderer culls before it draws, and must stay exact.** `_prepare()`
  projects only fixed walls in map blocks the view (or the mirror's view) can
  reach (`_block_walls`; doors, panes and gates are tested every frame), gives
  each wall only the columns its ends span plus the bands' tolerance, and
  `_wall_band` trims columns already covered by nearer walls before setting a
  wall up, drops a span wholly inside one nearer span, and leaves out mirror and
  glass pixels nearer spans hide (a hidden mirror would start a reflection
  pass). The shader's walk keeps the same columns (`seg_c0`, `seg_c1`) and
  order, so ties go the same way. `game_view.gd sprites()` lists only what can show: fixed sprites in
  blocks (`fixed_blocks`), and enemies, pickups and effects through
  `in_view(x, y, reach)`; a new sprite source should use it too. The shader
  draws sprites in list order, so culling only ever leaves sprites out, never
  reorders them. A window tour of old and new code compared pixel for pixel is
  how these were checked: do the same after touching them. `in_view()`'s sums
  are also written out in `_seen()` (blocks from `fixed_cull`/`late_cull`, kept
  beside `fixed_blocks`; breakables' `_widen` updates both) and in the enemy and
  pickup loops: change them all together.
- **Sprites that last one frame come from a pool** (`game.pooled()`,
  game_state.gd; `sprites()` starts it over each frame): enemies (through
  `Enemy.sprite(..., into)`), pickups, shots, specks, puffs, gibs, blasts and
  the effect features' sprites. A pooled sprite comes back with every field at
  its default; never keep one past the frame (a sprite kept from frame to frame,
  like the fixed ones or breakables' resting pieces, is `Renderer.Sprite.new`).
  Cel names are made once (`Enemy.cel_name()`, `EnemyLooks._row()`, cleared when
  the art index changes), not formatted every frame. These were checked exact:
  every sprite of 32 scripted runs (fights, kills, gibs, blasts) listed old and
  new, field for field, plus every enemy's state and the dice each frame.
- **What was tried for the tick and dropped:** enemies far away (past the 32
  cells the renderer draws) ticking at 30 Hz with the time saved up kept the
  dice the same but stepped far patrols coarser, so where a hand stood when the
  player got there could differ from before (not exact, so not kept); cosmetic features stepped at 60 Hz would move choppier on a
  display over 60 Hz. Keep tick changes exact (same state, same dice).
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
  `floorf`, `ceilf`. The crew also projects the walls (`_prepare_worker`, from
  `frame_begin` while the main thread lists sprites) and fills the shader's
  wall lists (job 0 of the band phase); each writes only its own slots of
  preallocated arrays, and the main thread merges (`_prepare_end`, `_pack_end`).
- **A frame's set-up has a thread of its own** (renderer.gd `frame_sprites`,
  `_setup_frame`, layered with threads): `_warm_art`, the sort, `_cpu_columns`
  and starting the bands run there while the main thread paints the gun, the
  view effects and the HUD; `render_end()` waits for it. The art caches
  (`art_cache`, `pivots`, `Assets._art_cache`) are plain Dictionaries, so
  `_look_up_art()` fills them on the main thread first and the set-up thread
  only reads them: nothing on the main thread may touch the renderer between
  `frame_sprites` and `render_end`. The shader's camera, lights, weather and
  shimmer go over in the same gap (`scene_layers.gd early()`, through
  `Game.scene_hook`); `frame()` then only sends what the bands made. Godot's
  own `--render-thread separate` was tried and was slower (and is marked
  experimental). Up to `GPU_WALLS` (16384) walls the shader walks them: the
  speedway seen across the oval has nearly 5,000 in view.
- **Line of sight is the tick's big cost** (`LevelData.visible()`, nine
  `blocked()` steps a cell, from every enemy's look and many effects).
  `index_cells` marks the cells either index lists anything under (furniture,
  doors), so a step over open floor with no panes or locked gates in the level
  is answered from the solid grid alone; the answers are the same, about 2.6
  times faster. Keep it exact: a new collision source must be in
  `near_fixtures`/`near_doors` (built by `_build_indexes`) or `blocked()` loses it.
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
  start (`spawn`) and map window come from the file, not from code. A gate a
  chapter, in campaign order outward from the four-way stop along the county
  line road, the Mothership's beam pad last at the far end of the road north;
  a gate is only ever across a line of y (`side` -1: walked up to from the
  north, its name board and barricade face that way). The fingerpost on the
  stop's island (`fingerpost()`) gets an arm per gate aimed at it by the plan,
  and `check_fixes.gd` holds every arm to its gate. The hub is never saved, so
  a new hub layout needs no save fixtures.
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
- **A fixture with all four corners on whole cells is skinned like a step**
  in a plan with `riser_tiles` (the builder takes its sides for risers): set
  one corner a hair off the grid (.02) to keep the side tile it was given.
  On a raised or sunken floor, stand props with the plan's own base (the
  Mothership's `stand()`): `town()`'s solid base sits at 0, which shows over a
  pit. A tall box round a sprite hides it; give a bunk or a table a base .05 high.
- **The Mothership (the last chapter)**: Maw Glorb's fight is
  `features/mothership.gd` (phases by health, attacks picked at the wind-up
  start with their floor marks, pod crew, the loose beam, her fall and the ship
  coming apart); the crew's own attacks and the tin guard's tailgate are
  `ship_aliens.gd`, hooked from `enemies.gd` attack/hurt/sprite. After the last
  chapter in `Campaign.ORDER`, `finale.gd` draws the true finale (the campaign's
  tally, then the credits). Chapter music not made yet is listed in
  `assets.gd PENDING_MUSIC` (pack_assets and verify_assets note it as pending).
- **Ledges a step won't climb** (more than .245 up) take a jump (about .6);
  the pin and the enemies plan paths without heights, so keep a ramp beside
  any drop on the way. `first_minutes.gd -- <id> whole` hops when stuck and
  shoots a station that is struck (the mill's belt).
- **The objective pin** leads to a station's carried item first while it lies
  somewhere (the fair's PA patch lead). The fair's tin rooster booth is where
  its level puts it (`gallery` in the JSON: the stand; targets 3.58 east).
- **Using things is forgiving, and checked** (`game_world.gd use_target`): a quest device (station, exit, note, jukebox, sink, the tin rooster stand) answers USE at any of its aim points (its own point and the board that lights up for it within 3.5, the slip on a note's table, the jukebox or sink itself), within 1.65 and a wider cone than doors, and is seen when the eye sees it or the face of the wall, counter or pump it is mounted in (`seen_at`: at most .45 back toward the player, so never from the far side of a wall). The one nearest the crosshair wins; doors keep their reach and cone. Keys and the patch lead are taken within .62, over a counter (`reaches_pickup`). `tools/quest_reach.gd` stands the player round every quest prop, gate and item in every level and fails when one is hard to use or works through a wall: run it after moving a station or its board. A station's board should stand on the side it is used from.
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
- **Hits land somewhere** (`src/hit_zones.gd`, the play; `features/hit_reads.gd`,
  the looks and sounds). Every player hit with a `game.hit_point` (hitscan,
  pellets, swings, blades, balls, pierced rounds) gets `Enemy.last_zone` from
  the body's height and how far off its middle: head (`HEAD` by gun: x2 a
  round, x1.35 a pellet), arms x.82 (a held weapon dropped on `game.rng`
  .4, fetched while it fights with its fists: `HitZones.tick` in
  `Enemy.tick`; else a wind-up's aim thrown wide), legs x.78 and a limp.
  No dice in damage; bosses keep `weak_spot`; a blast is the body. Overkill
  ignores the head's extra, one barrel of buckshot throws (both gib), an edge
  blast or the cow launcher throws whole (`blast_gibs`). The killing blow
  shapes the fall (`corpses.gd _throw`: buckshot at arm's length into a
  window or fence breaks it, `wall_breaks.gd crash()`; rifle drops, crowbar
  crumples, milk slides; bodies at rest in water bob). Metal (`METAL`, the
  boilerback's back) sparks and clanks; a bigger instant reels further
  (`REEL`). Hats (`fx_hat_*`) and dropped weapons (`fx_drop_*`) are
  `tools/art/build_hit_art.gd`; actor cels still wear the hat (`Enemy.hatless`
  is there for the art). `features/critters.gd`: chickens and hogs run from
  shots, blasts and a running player (chickens flap: `Enemy.hop`), a hurt hog
  charges (5), a hit gator thrashes, a blast shoves Bessie. Not saved (seconds
  long). `tools/hit_check.gd` (in check_fixes); `physics_frames.gd only=hits`.
- **Squads, idle life and variants** (new code lives outside `enemies.gd`,
  which only has small hooks: `mind`, `Squad.watch/calm/move/startled`,
  `IdleLife.notice/frame`, `Variants.attack/stem/look/wobble`). A hand
  (`Squad.hand`: tactical, turn cels, not a swimmer) gets a `Squad.Mind`
  from `features/squad_feature.gd` on the first tick. Before it notices
  anything it does an activity picked from the props, boards and scenery
  within 2.6 of its place in the level (`idle_life.gd BY_THINGS`; no plan
  changes), faces the thing, loops its fidget/recover/aim cels and notices
  less (`NOTICE`, less so the harder it is); woken it fumbles (`startled`),
  hit from behind unaware it is stunned (`SNEAK_STUN`, no extra damage).
  A shot is heard through walls out to `SHOT_NOISE` x `HEARING`: unaware
  hands come to look. Every .4 s the alerted hands within 18 are a squad:
  a flanker goes round the player along the flow field's rings
  (`_flank_step`), one presses in while another shoots, a lobbed bottle or
  (HARD+, outdoors) a stick of dynamite flushes a player unseen for 2.5 s
  (wind-up, warning mark; enemy dynamite is in `dangers` too), and two or
  three losses make them fall back on the farthest. A hunt that runs out
  becomes a search of the last-seen spot (`SEARCH` s), then `alerted` goes
  off. EASY does none of the squad moves. No new sight lines but the
  flush's one; dice from `game.rng`; nothing saved. Barks for voices:
  `game.enemy_bark(e, moment)` (spot, lost, search, help, flank, cover,
  brawl, idle, surprised, hurt_bad, regroup), throttled per hand (3.5 s),
  per moment (`MOMENT_GAP`) and overall (.7 s).
  **Variants** are enemies.cfg sections (`src/variants.gd` lists the keys):
  `big_billy`, `drunk_coot`, `shield_deputy`, and a tough guy a chapter
  (`tough_for`: BIG EARL, CARNY CLEM, TIMBER TOM, BOILER BUBBA, CHUM-BUCKET
  CHUCK, PIT BOSS PETE, ZORGO THE LARGE; taller via `height`, `tint`ed copies
  of the pictures, `Assets.tinted_art`). `features/variants_feature.gd`
  swaps them in on a chapter's first tick, never on a load: variants by
  difficulty and the enemy's index (`Variants.swaps`, EASY none), the tough
  guy on the regular at the busiest spot in the middle half by distance from
  the start. A save keeps each kind (restore re-derives its stats); the
  doors' hit points are in the features block. The shield deputy's door is
  `Variants.soak` via `ShipAliens.soak`; it is painted in code
  (`made_car_door`). **Art:** `art="billy"` draws a variant with its
  regular's pictures until `<kind>_0` is in the art index, so dropping in
  `big_billy_*` (and `drunk_coot_*`, `shield_deputy_*`) with every cel the
  regular has and running `pack_assets` just works; then delete the `art`
  line, and `door_picture` too if the deputy's art carries the door.
  `tools/squad_check.gd` (in check_fixes) holds it; `tools/squad_frames.gd`
  takes window pictures; `first_minutes.gd -- diff=<0..3>` plays a
  difficulty and prints the damage taken. The bot (`bot_pilot.gd`) steps
  back onto the route from a nook it does not cover and backs off a last
  threat it is pressed against but cannot see (Boggs wedged in a gap).
- **Boss fights share a framework** (`src/boss_kit.gd`, `features/boss_fight.gd`,
  `src/bosses/`). Each of the eight bosses (a `title` in enemies.cfg) has a
  `BossMoves` file (`bosses/boss_moves.gd`: `fight_start`, `phase_changed`,
  `tick` (true skips the brain), `weak_spot` (a damage multiplier, no dice),
  `telegraph`, `looks`, `dying`, `stagger_hit`/`stagger_rest`, `hog_wild(game)`);
  `BossKit.moves(kind)` hands back one instance shared by every game, so keep
  a fight's state on the enemy or in a feature's save. `Enemy.boss_phase` (2
  under half, 3 under a fifth; Maw by her own lines) is worked out from health,
  never saved. A player's hit sets `game.hit_point`/`hit_from` before `hurt()`,
  which asks the weak spot and forgets the point. A big instant (`struck_sum`
  past `BossKit.STAGGER`) staggers; the entrance holds the world only when
  `game.lessons` (never in tools, tours, benches, bots) and once a save; backup
  at phases 2 and 3 joins the enemies after the level's own (the posse feature
  saves them; `game.boss_backup` off for a rematch); a fall sets `game.slowmo`
  (game.gd steps the world at `SLOWMO_PACE`, the player and gun at full speed).
  Signals for voices and the like: `boss_intro`, `boss_phase`, `boss_staggered`,
  `boss_weak_hit`, `boss_down(e, seconds)`. `tools/boss_check.gd` (in check_fixes)
  holds it; `physics_frames.gd only=boss` takes its pictures.
- **The arenas of the sheriff, Jerry, Rudy and the foreman** (`features/boss_arena.gd`,
  `bosses/arena_moves.gd` under `sheriff.gd`, `jerry.gd`, `rudy.gd`, `foreman.gd`).
  Each plan gives `meta["boss_arena"]` (level JSON `boss_arena`, `LevelData.boss_arena`):
  per kind its `box` (Hickston's two are BossFight.in_arena_at's test: the bar,
  the music, the checkpoint), `floods` (floodlight towers that cut at phase 3
  and come back when it falls), `lights`, `approach` (the picture tool's walk-in)
  and its hazards' places. The feature keeps fire (a fuel tank, gas can or drum
  going up in an arena leaves the ground burning, sawdust too; it bites the
  player and any boss or hand), strikes, lobs, rollers (tumble.gd), the mill's
  carriage and the big top's horn lanes; it saves nothing. A boss's shot breaks
  the cover it meets. All four: a desperate boss shrugs off staggers longer and a
  gun's plain hit counts .7 (`guarded`). Per boss:
  sheriff: the rodeo grounds north of the corn (chute gate under STAMPEDE RODEO,
  the ring, grandstand, the saucer in its crater, Bessie's pen); stands before
  the wreck, seen through the gate; propane, alien fuel cells, bales; weak spot
  the power pack from behind (2x, shoulder 1.5x), and once mad he vents it with
  his back turned; phase 3 the saucer strike (rings, then bolts that burn him
  too), reactor red, fire round the wreck, lights out; HOG WILD a plasma ring.
  Jerry: the Hogs' field west of the rodeo behind a stock gate the sheriff's
  fall opens (trigger `field-gate`); midfield; tyre stacks that roll, the
  concession propane; weak spot the knees (2x, a blast at his feet 1.5x),
  helmet .6x; phase 3 the blitz down a marked lane (into a post or wall he rings
  his bell, stunned), the scoreboard shorts, bleachers burn, lights out; HOG
  WILD a flaming pigskin. Rudy: the pavilion is his big top (ring, bleachers, PA
  horn stacks at its corners, helium, balloons, bulbs, RUDY'S BIG TOP over the
  stage); in the ring, seen from the stage where the broadcast is cut; mad, the
  stacks fire lanes at the player (and hurt him); weak spot the drum low in front
  1.75x, the horns while he blows 2.25x; phase 3 the grand finale rings with
  spokes showing the gaps, spotlights sweep; HOG WILD balloon bombs (shoot them).
  His horn volley now flies at chest height (it used to pass over the player).
  Foreman: the saw floor with its carriage track clear end to end (the
  carriage runs on a bell, every 9/6.5/4 s by phase, and hits him too), head saw,
  log decks, sawdust; across the track from the shed's south door; weak spot
  the saw rig from behind 2x; phase 3 the big cut (a fan of blades that bounce),
  the saw speeds up; HOG WILD a kicked fuel drum (shoot it). `tools/arena_check.gd`
  (in check_fixes) holds it; `tools/arena_frames.gd` takes window pictures of
  each arena (`docs/boss_arenas/`).
- **The bosses' art wears the fight** (`src/boss_looks.gd`, called from
  `Enemy.sprite()` for bosses only). `build_enemy_actors.gd` renders the eight
  bosses on a dusk stage (warm key, two rims, more samples; `enemy_actors.py
  light_for`, the graphics card when Cycles has one) with less grain, plus a
  wind-up cel `<kind>_wind` (the first half of a wind-up; then `_aim`) and a
  battle-damaged copy of every living cel per phase: `<kind>_p2_<cel>` under
  half health, `<kind>_p3_<cel>` under a fifth (Maw: `maw_p2_` from her fight's
  phase two, two thirds, housecoat on fire; `maw_p3_bare_` out of it). The
  damage is `DAMAGE` in the Blender scripts: every material scorched (`mat`
  `_battle_worn`) plus each boss's own rags, smoke, flames and breakage; falls
  are drawn beaten. A cel without a variant keeps its name. `tools/boss_closeups.gd
  -- out=<png>` draws every boss in its level in each state (software view).
  `pack_assets.gd` stores identical pictures once (the old three-cel walk names).
- **The regular hands' art wears the fight too** (`src/enemy_looks.gd`, called
  from `Enemy.sprite()` for every non-boss hostile). They are drawn on the same
  dusk stage with the cleaner grain, with a wind-up cel `<kind>_wind` (racking,
  cocking, rearing, revving, charging; a glint on the business end) and a hurt
  copy of every living cel, `<kind>_hurt_<cel>`, shown under half health: blood
  soaked in (`actors_wounds.py _wounded`, green for `blood="plasma"` kinds, dents
  and scratches on metal), a split brow, a gut wound the free hand clutches, a
  limp in the walk (`skeleton()` while `WOUND`); creatures mark their own (torn
  wing, cracked shell, smoke, sparks). A cel without a variant keeps its name.
  The variants `big_billy`, `drunk_coot` and `shield_deputy` (behaviour in
  enemies.cfg with `brain=`) are drawn in `scripts/blender/actors_variants.py`
  with their base kind's cels (big_billy at 1.15x Billy's frame); they are in
  art.bin, not a chapter pack. `tools/enemy_closeups.gd -- out=<png>` draws each
  kind in a level (whole, walking, wind-up, aim, attack, hurt, limping, pain,
  down); `tools/art/enemy_sheet.gd -- dirs=<old>,<new>` lays cels side by side
  (`docs/enemy_art/`). The chicken, pig and Bessie are not Blender actors.
- **The last four bosses' arenas** (`features/boss_arenas.gd`, from each plan's
  `boss_arena` meta, `LevelData.boss_arena`): hazards that hurt the boss as
  well as the player, each third phase's arena change, `drop()` (a throw onto
  a marked spot whose ring closes in: copper rain, dynamite, curlers), `burn()`
  (burning fuel or oil), and the arena's own `lights` and valve `steam`.
  Nothing saved: the change follows the boss's health. `tools/arena_frames_late.gd`
  (a window) takes pictures of each: the way in, the reveal, the fight, phase 3.
  - *Baron*: the still house (quarry layout 4), the north end of the bottling
    works walled off behind a three-bay gate the relay (now beside it) throws
    open; he waits on the boiler deck between two giant boilers. His outlets
    are the nearest three to where the player stood as he wound up
    (`pressure_ports` reads them off him); one blowing under him scalds him.
    Phase 3 COPPER RAIN (five marked spots round the player, steam) and the
    wall pipes bursting (`jets`). Weak spot: the boiler on his back (from
    behind, body high, x2). HOG WILD: BLOWDOWN, every outlet every third time.
    `BaronMoves.outlets_next` is the one test of outlets vs. steam sweep.
  - *Swamp King*: the lagoon (bayou layout 2) is open all round the feed
    platform (the dock walk came out); fish houses on the north shore,
    cypress in the deep, fuel drums on the dock edge that a beached run sets
    off. Phase 3 DYNAMITE (three lit sticks onto marked spots) and burning
    slicks off his holed tank. Weak spot: the engine cage (from behind, x2).
    HOG WILD: a broadside of the punt gun at the end of every run.
  - *Boggs*: the derby bowl (speedway layout 2, was the figure 8), one long
    tyre-walled bowl, a three-bay gate by the flag, a clear run up the middle;
    wrecks, tyre stacks, nitro and gas cans (his crashes set them off,
    `derby_champ.gd _crash`). Phase 3 NITRO RAM (three legs off the walls,
    painted, then a long stall) and the floodlights blow (`floods`, his
    headlights the light left). Weak spot: the radiator (front, low, x2).
    HOG WILD: burning oil down every charge lane.
  - *Maw*: her throne on a dais in the core's south (Mothership layout 2),
    seen past the column from the iris; crates, jars and two shine barrels.
    Her last phase adds HOT CURLERS (mothership.gd) and the core going
    critical: pulses roll out from the column to be jumped, burning her too.
    Weak spot: her curlers (top of her head, x2) and in her last phase the
    power-cell girdle (x1.6). HOG WILD: the rolling pin comes down twice.
    A rematch keeps the escape hatch and the derby bowl's back gate shut
    (`BossRematch.SHUT`), so it starts by the iris and by the flag. The bot's
    times (`boss_rematch_check.gd -- bot`, now with `diff=` and `runs=`) set
    their PAR.
- **Fight music** (`features/fight_music.gd`, `sound.gd` crossfade) swaps a
  chapter's music for its fight track (`assets/music/fight_*.ogg`, made by
  `audio_build.py --fights`) while hands hunt or attack nearby. Each chapter
  also has a boss loop (`boss_<chapter>`, `Sound.BOSSES`), faster and heavier,
  that takes over while its last boss is alive, awake and the player is in its
  arena (as far as the boss bar shows), holds `BOSS_HOLD` seconds after the
  player steps out and hands back the moment the boss falls.
- **The boss checkpoint and BOSS REMATCH.** A beat after a boss fight begins
  (`BossFight.on`, the boss bar's test) `features/boss_checkpoint.gd` saves the
  game, in SessionStore's own format (no new version), to
  `boss-checkpoint-<chapter>[-replay].json` in the profile; the door is the
  last spot the player stood clear of the arena. On the death screen ENTER
  then retries the fight (`main_flow.gd retry_fight`, `boss_door.gd`: boss
  whole, player at the door, health and rounds as they were) and RELOAD's key
  starts the chapter over. A win clears it, another chapter's start clears it.
  The title's BOSS REMATCH (`boss_rematch.gd`, `features/boss_rematch.gd`)
  loads a beaten chapter with only that boss, every station done and door
  open, the `GUNS` table full and the player `DOOR_STEPS` flow-field steps
  from the boss; it is timed to the fall and ribboned by `PAR` (from
  `boss_rematch_check.gd -- bot`: run it again after changing a fight). Bests
  and beaten chapters live in `boss-rematch.json`, never in a save; nothing in
  a rematch saves or carries out. `--rematch-all` or the console's `rematch`
  opens every boss. Tool scripts keep both files under the cache folder.
  `fight_began(foe)` in both features is the one place a fight's start is
  noticed (the boss framework's intro signal can call it).
  `tools/boss_rematch_check.gd` holds both (its quick part runs in check_fixes).
- **Tool scripts never write the player's settings** (`main_state.gd
  persist_options` returns when a script runs the main loop), and tests write
  saves under `OS.get_cache_dir()`. The gun pictures warm on a thread that
  `Weapons.Armory.settle()` waits for when the program closes.
- **Enemies path on a flow field** (`src/flow_field.gd`): out of sight, an
  alerted enemy walks downhill on the steps from the player for a few seconds
  (`Enemy.hunt_until`). The objective pin walks a second field measured from
  the objective (`Game.route`) through doors the player can open now. That one
  walks the whole level (5 to 10 ms), so it has a `budget` (1500 cells a
  tick): a new walk (a door opened, a key, something broken, the boss moving a
  cell) finishes over a few frames while the last answer stands; the first
  walk is always whole. Stutters: `first_minutes.gd -- whole hitches` times
  every tick of a bot's playthrough; `--play-bench=<seconds>` has the same bot
  (`tools/bot_pilot.gd`) play each chapter in a real window and prints the
  slowest frames with the tick's and the draw's share.
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
  `ticks` to show one gun firing; viewpoints after it keep firing it.
  **The shader view's gun and blast effects** (LIGHTS AND GLOW on) are a
  layer of their own, drawn only while `Effects.rich` (game_view.gd sets it:
  layered and lights on), so the software view and the shader view without
  lights stay as they were (picture_check and compare_views hold that):
  `features/gun_fx.gd` (blasts: a white star, a fireball rolling up into soot
  with two smaller beside it, a smoke column, charred scraps trailing smoke, a
  dust ring on the ground, lights `blast_flash` and `boom_glow`; strikes by
  material, `fx_hit_<kind>`, with more chips; wadding, smoke and sparks off
  the muzzle; fuse and rocket sparks; all capped, a chain of blasts throwing
  less each, its own dice, made whatever the view), `gun_flash.gd` (each gun's
  muzzle flash: weapons.cfg `flash_art`/`flash_size`, over the old flash as a
  glow), weapon_fx's fatter tracers with a glowing head, and each gun's own
  muzzle light (`[light.muzzle_<gun>]`). game_view.gd leaves the old `fx_blast`
  fireball out then. The pictures are `tools/art/build_gun_fx_art.gd` (hard
  edged, few colours, committed to the VGA palette; `fx_mf_*`, `fx_boom_*`,
  `fx_soot_*`, `fx_chunk_*`, `mark_shock_*`, `fx_hit_*`). `tools/gun_frames.gd`
  renders every gun firing at a plank wall, a blast, a chain and the .38 into
  each material, in a window, as rows of frames (run it on the old build too
  for a before; `docs/weapon_fx/` has the contact sheet). A new piece of play goes in `src/features/` as a
  `GameFeature` (see `game_feature.gd`), listed in `features.gd`: it connects
  to those, saves its own state in the save's `features` block (restore gets
  {} from older saves, so no new save version), and may add a tally row.
  Triggers, lessons and chapter stats are features, and so is the polish that
  only looks: `weather` (lightning and thunder), `debris` (brass, hulls,
  embers, scorches, smoke, blood trails), `ambient` (crows, fireflies),
  `callouts` (TWOFER, HAT TRICK, HOG WILD, RAMPAGE) and `tally` (rows that
  thud down and a ribbon). Features may add sprites and ground marks; looks-only
  ones use their own dice so play never changes.
- **Things break and loose things move** (`features/breakables.gd`,
  `features/corpses.gd`, `gore.gd`, `tumble.gd`). `data/tuning/breakables.cfg`
  names each picture that breaks (a board's image or `prop_<name>`), its broken
  picture (props: `scripts/blender/props_broken.py` through
  `build_town_props.gd`; signs' `<name>_shot` and the bits `fx_brk_*`:
  `tools/art/build_break_art.gd`), hp, bits, cues and, for explosives, the blast
  (`shots.cfg`) it sets off a moment later, which can set off the next (chain).
  Quest props, signal or glowing boards, anything on furniture it shares with
  something whole, and anything whose base alone parts two stretches of floor
  never break; a broken piece's base leaves `collision_volumes`
  (`LevelData.drop_volume`) and its cells reopen for both flow fields
  (`FlowField.reopen`). game_combat.gd asks it first in `hitscan`, `_hits` and
  `explode` (`_blast_shoves` also throws gibs, bodies, bits, loose barrels and
  rolling shots). `tumble.gd` is the one stepper for gibs, bits, bodies, the
  player's dynamite and bowling balls (walls axis by axis, ledges, furniture
  tops, slopes from the floor sampled .45 each way, drag). Bodies take a knock
  from `Enemy.killed_by`/`killed_from` (an overkill still gibs); their place is
  the enemy's saved x, y. Breakables save in the features block. Sounds wanted
  for them: `docs/physics_audio.md`. `tools/break_check.gd` (in check_fixes)
  and `tools/physics_frames.gd` (window pictures of each effect) cover it.
- **Walls break too** (`features/wall_breaks.gd`, breakables.cfg `[windows]`
  and `[fence.<tile>]`). A window face is one wall piece showing a `_win`/`_lit`
  tile (or `trailer_window`); shot in its glass or blasted it swaps in place to
  `<material>_brk` (`tools/art/wall_break_art.gd`; `_brk` is laid by height
  like `_win`, `render_state.gd` tile_mode) and stays a wall. A fence cell
  (stockyard) shot down to `damaged` swaps its faces to `stockyard_hit`, and at
  0 hp `LevelData.open_cell()` makes it floor: its own face pieces leave
  `walls`, each solid neighbour gets the face `implied_walls` would give it,
  `walls_version`/`solid_version` bump (the renderer's `_block_walls` key and
  the automap signature), both flow fields reopen it, and `stockyard_gap`
  stands in it as two plane sprites. This stays exact because nothing is
  rebuilt until something breaks: window and stockyard tiles are not
  `RenderState.TILED`, so their pieces are never merged runs and a swap or a
  removal touches only that cell's own pieces (keep a breakable fence tile out
  of TILED). `index_cells` needs nothing (no fixture or door moves); `solid`
  answers `blocked()`/`visible()`. Only cells whose opening joins no two
  stretches of floor the level keeps apart (`regions()`: doors a key, station,
  trigger, secret or blast opens counted shut), off the map's edge, outdoors,
  level with their neighbours and with nothing on them may open; the rest get
  shot about but hold. `tools/wall_break_check.gd` holds it (every level's
  cells opened at once). The Crossroads breaks nothing.
- **What a bullet strikes is a material** (`src/materials.gd`: a level's tile
  names map to wood, timber, tin, steel, mesh, brick, stone, dirt, brush,
  glass, rubber, water; `_lit`/`_win` variants are their base). Hitscan sets
  `impact_kind` before `traced`, picks the speck and sound by it, and gives a
  hole its picture (`fx_hole_<kind>`); `traced`'s "wall:<surface>" stays the
  old four. The game's `burst()` spends the game's `rng`, so a strike still
  bursts the same count it always did. **Penetration is play**
  (`src/penetration.gd`): a gun with `penetrate` in weapons.cfg goes through
  that much wall (planks 1.0 a cell, tin .75, wire .25, brush .6; anything
  else stops it) and hurts the first hand behind for `penetrate_damage`, by
  the game's own tests, no dice (`pierced` announces it; `tools/feel_check.gd`,
  run by check_fixes, holds it). `features/impacts.gd` throws the chips and
  keeps the marks: holes, floor pocks, wall scorches, blood running down from
  `gore.walls`, each to a cap and a life from effects.cfg `[debris]`, the
  oldest fading first (`Assets.faded_art`, alpha-scaled copies). Features add
  wall marks through `wall_marks()`. `features/dust.gd` is gun smoke, boot
  dust, race-car and derby dust and embers off fires (`dust_cap`), drifting on
  `[debris] wind_<level>`. `features/feel.gd` puts the gun on springs (sway,
  each gun's kick from recoil/retreat/view_rise/settle/spring_damp, landing,
  blows) into `player.weapon_lag` and the view's kick into `view_kick`
  (game_view.gd adds it to the eye like the shake, never to the aim); VIEW BOB
  scales sway and landing, SCREEN SHAKE the blows, off means none. Sounds it
  wants are in `docs/feel_audio.md`.
- **A level's mood** is `effects.cfg` `[level.<id>]`: fog colour and distance,
  grade, cloud drift, lightning, rain (`rain`, `showers` for spells),
  `fog_banks`, `heat` spots, crows, fireflies; `[anim.<tile>]` makes a sign
  buzz or pulse. All of it is the shader's, behind LIGHTS AND GLOW.
- **Weather, water, relief and shimmer** (shader only, behind `effects_on`):
  `features/weather.gd` keeps `rain` and `wet` (puddles on `[puddles]`
  floors, a sheen on walls under the sky, streaks over the view) and the
  lightning's `flash_dir`; `features/water.gd` keeps the rings bodies leave
  wading on `[water]` floors (the shader takes the nearest 16). What each tile
  is to them (`[water]`, signed `[relief]`, `[puddles]`) is one row of
  `tiles_tex` (`info_row`), and "under the open sky" is the cells' second
  band's g (roof at the floor): no new texture. Lights come from
  `view_lights.gd` (moved out of `game_view.gd`): `[light.*]` takes `pool`,
  `hot` (the shimmer's width; strength 0 only shimmers) and `props` (every
  prop with that picture carries it). Rain never on the Mothership;
  `tools/weather_check.gd` (in check_fixes) holds where it falls. A view tour
  viewpoint may hold the weather: `rain`, `wet`, `lightning`.
- **World loops** (`features/soundscape.gd`, `Sound.set_bed`): four voices of
  their own keep the rain (`rain_loop`, muffled under a roof, and `rain_roof`
  overhead, both following `weather.rain`), the nearest burn barrel, grill,
  still, generator or the Mothership's core within 9 cells (`SOURCES`, by
  picture) and the swamp king's wake. `pause_world()` stops them. The sounds
  for breaking, strikes, the gun's feel, weather and water were made in
  dev.32 (`docs/*_audio.md` say where each plays); breakables.cfg's `chip` is
  the knock of a shot that does not break a thing yet.
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

## Multiplayer foundation

This is what co-op or deathmatch rules and the transport (next section)
build on. `src/players.gd`, `src/player_voice.gd`, `src/game_snapshot.gd`,
`src/snap_codec.gd`, the authoritative host (`src/game_host.gd`,
`src/net_track.gd`, `src/quiet_sound.gd`, `src/server_loop.gd`), the client's
`src/game_mirror.gd`, `tools/net_check.gd` and `tools/net_bench.gd` hold it.
One player plays exactly as before (checked
tick by tick against the old build: state hashes of bot runs in every
chapter at NORMAL and HOG WILD, `first_minutes.gd -- whole`, the rematch
times, the duels).

- **Players are a list.** `game.players: Array[Player]` by slot (index 0 is
  player one; `Player.slot` is never reused and is how a snapshot names a
  player). `game.local_player` is the one this machine shows and hears.
  `Players.join(game, x, y, angle)` adds one (Game._init joins player one),
  `Players.set_local(game, p)` changes whose view this is.
- **`game.player` is the ACTING player** (`game.focus(p, own)`): the local
  player outside the tick; during the tick each player in turn while their
  controls play (`own` true: their sounds come from where they stand, their
  notices are not shown here), an enemy's hunted player while that enemy
  ticks, a shot's thrower while it flies (`Shot.slot`). `game.armory`,
  `flow`, `inventory`, `keys`, `task_items`, `inventory_slot`, `sprint`,
  `step_number` and `next_belch` are the acting player's (`armory`/`flow` are
  swapped in by focus, the rest are properties over `game.player`). Code that
  acts for "the player" (damage, pickups, use, the guns, an enemy's sight,
  aim, blows and flow field) keeps reading `game.player` and acts on the
  right one. Code about the world goes over `game.players`: blasts, enemy
  shots (`_shot_finds_player`), hazards, doors held open
  (`LevelData.update(dt, players, enemies)`), triggers (`Triggers._met_any`:
  the first player who meets it is left acting), arena fire, rollers, the
  log carriage, steam jets, slicks, core pulses, race cars. A new hazard
  loops over `game.players` and calls `game.damage(amount, source, cause,
  who)`; a knock-back focuses the player first (`move_actor` tests the
  acting player). `game.reopen_paths()` opens a broken piece's cells in
  every player's flow field and the route. After focusing someone else,
  focus back: `game.focus(game.local_player)`.
- **Controls per player.** `game.tick(dt, controls)`: one `Game.Controls` is
  the local player's (anyone else stands idle, the single-player path), or a
  Dictionary slot -> Controls (a slot left out stands idle). Controls also
  carry `use` (a fresh press), `weapon` (a slot), `item` (a pocket) and
  `cycle` (+1/-1 gun) for a player who is not the local front end; the local
  front end still calls `interact()`, `Armory.select()`, `use_item()`
  between ticks. The tick plays every live player's body (`_step_body`),
  then rooms that open (`_discover`), the doors once, every player's hands
  (`_step_hands`: controls' actions, pickups, gun, the tin rooster booth for
  the player who opened it), then each player's flow field, the enemies, the
  shots, the hazards. The world stops when nobody is alive; a dead player's
  steps are skipped (respawning is the co-op rules' to write).
- **Per player vs shared** is `Players.SHARED` and nowhere else: `keys` and
  `task_items` (the PA patch lead) are one object the party shares,
  `inventory` (rinds, beer...) each player's own; flip one there. Always each
  player's own: place, health, gut, drunk, guns and rounds (`Player.armory`),
  sprint, footsteps, flow field. Always the world's: stations, doors, the
  pickups lying about (whoever touches one takes it), kills and secrets,
  clock, rng, enemies, scenery, triggers, `cheats.god`. With more than one
  player there is no world-stopping hitstop or boss entrance hold, and no
  ADAPTIVE DIFFICULTY (each is one machine's game feel).
- **Enemies pick a player** (`Players.hunted(game, e)`, only with more than
  one): it keeps its pick `RETARGET` (.5 s), then a player who hurt it within
  `SPITE` (`Enemy.spite`, set in `hurt()`), else the nearest it can see
  (14 cells), else the one nearest where it last heard something, else the
  nearest alive; ties to the lower slot, no dice. `Enemy.hunted` is the pick;
  the enemy ticks with that player acting, so its sight, flow field (each
  player has one), aim marks, flanks and blows are about them. Squads form
  per hunted player (`squad_feature.gd _step(only)`); Maw follows hers (her
  wind-up, curlers and crew calls too). A hostile body keeps out of every
  player's way; in co-op and versus players who are up block each other
  (`move_actor`, `GameMode.bodies_block`; the campaign's two-player runs pass
  through, as the foundation's checks expect).
- **Presentation follows the local player**: the HUD, view, automap,
  objective pin, camera shake (a blast's by distance to the local player),
  the face (`set_face`), barks, messages, the crosshair's hit mark, the hurt
  flash, item feedback, captions, the room's sound, the place names, the
  walked map, the gun's kick (`feel`), tracers and muzzle smoke (`weapon_fx`,
  `gun_fx`), chapter stats, kill callouts, fight music and boss taunts are
  the local player's (`game.acting_local()`). Sound is placed for the local
  player's ears (`sound_position`, `sound_at` through `game.speaker`); while
  another player acts by their own hand `game.sound` is their `PlayerVoice`,
  which places their gun, pickups and grunts where they stand and ignores
  the local-only calls (fuse, room, music, stings). A message during another
  player's own step is not shown here (one said while an enemy is after
  them is).
- **Simulation vs presentation** is written down in `GameSnapshot`: every
  field of Game is in `SIM_FIELDS`, `PLAYER_FIELDS` or `VIEW_FIELDS`, every
  feature in `SIM_FEATURES` or `LOOKS_FEATURES`; `net_check.gd` fails on a
  field or feature in none, so put a new one in one. Simulation is everything
  that can change play and comes from `game.rng` or the features' own state;
  presentation uses its own dice and is never carried (specks and blast
  flashes are looks, though a save keeps them). Known mixes kept for exact
  single-player play: the HIT FEEDBACK setting decides the hitstop, footstep
  splashes spend `game.rng`, `cheats.god` is the game's.
- **Stable ids.** Players by slot; enemies, shots and pickups by a uid from
  `game.take_uid()` in the order they come into being (`Enemy.uid`,
  `Shot.uid`, a pickup's fourth element; enemies and shots that joined during
  a tick are named at its end, `game.name_new()`), so two machines running
  the same ticks agree. Doors, stations and scenery by their place in the
  level's lists; breakables and wall breaks by their place in their
  feature's lists. A save keeps pickups as `[name, x, y]` (no new version);
  their ids are handed out again on load. An enemy's instance id in carried
  state (a shot's thrower, a dictionary keyed by enemy) travels as its uid.
- **Snapshots** (`src/game_snapshot.gd`, version 2): `GameSnapshot.capture(game)`
  is a Dictionary of plain values that never changes as play goes on (packed
  arrays are shared by reference in Godot 4: encode and decode copy them):
  "game" (SIM_FIELDS), "world" (each door's progress, opened and discovered by
  its place in the level's list; the panes broken, in breaking order),
  "facts" (`FACT_FEATURES`' own save(): what breakables and wall breaks broke,
  which changes the level's walls and floor), "players" (every carried field
  by slot, each player's own, whoever is acting), "enemies" (by uid) with
  "order", "features" (each simulation feature's variables), "statics" (play
  in static variables: `DerbyChamp.state`; new play belongs on the enemy or in
  a feature). No save and no presentation inside it. `GameSnapshot.apply(game,
  data)` puts it onto a Game of that level, just made OR already running: the
  players it lacks join, the doors and panes are set, each fact feature's
  restore() breaks what is not broken yet (only when its facts differ from
  what the game was last given, `game.net_facts`), enemies are matched by uid
  (new ones made), every carried field is set, and a finished station's
  lights follow `stations_done` (`game.lit_stations`, kept by
  `set_station_lights`). `apply_delta(game, d, full)` puts on only what a
  delta touches, each field from `full` (its patched snapshot). A flow field
  travels as the cells its last walk reached and their steps (`@flow`); a
  level's windows, fences, breakable pieces and boards carry only what can
  change (`SnapCodec.ONLY_FIELDS`), a feature's tuning and lookups not at all
  (`SKIP_FIELDS`). `to_bytes`/`from_bytes` (var_to_bytes, zstd),
  `delta(base, now)` (dictionaries walked, each value compared once, bit for
  bit; a changed dictionary is `{"@new": value}`, anything else travels as it
  is; gone keys under "@gone", a new key order under "@order"), `patch`,
  `patch_into` (into the caller's own copy), `merge(older, newer)` (two deltas
  as one), `same(a, b)` (bit for bit, key order too), `first_difference`.
  `snap_codec.gd` turns objects into plain values by reflection (script
  variables, read in one call through a script made per class, `packer()`);
  a class it cannot name is listed in "unknown" and fails the check; decoding
  fills what is there in place, so what a snapshot does not carry (a sprite)
  stays.
- **The host** (`src/game_host.gd`): `GameHost.new(level_id, slots, options)`
  makes a host Game (`game.host`: no looks-only features, `Features.LOOKS`;
  a `QuietSound` for `sound` and `speaker`; no voices, no talk, no room sound
  or place names, `sound_at` returns at once; nothing is ever drawn) and runs
  it `step({slot: controls})` one fixed 120 Hz tick at a time (`tick`
  counts them). `snapshot()` is bytes of `{"tick", "full"}`;
  `delta_since(acked)` is bytes of `{"tick", "base": acked, "d"}`, or a whole
  snapshot when the base is older than `HISTORY` ticks (or -1). `adopt(game)`
  wraps a game already made; `join_near(game)` seats one more player.
  Presentation that play still leans on stays on a host: specks and gore
  (their count gates `burst()` and its rng), the renderer object (hitscan's
  `wall_mark` picks the material), and so on; a host game and an ordinary one
  fed the same controls stay identical (net_check). `main.gd --server=<level>`
  (`--server-players=N`, `--server-ticks=N` to time flat out and quit,
  `--server-report=S`, `--server-difficulty=D`; run it `--headless`) runs a
  host in `ServerLoop` with no window, picture, sound or menu work and prints
  the tick's and the deltas' cost; players stand idle until a transport hands
  their controls to `ServerLoop.controls`.
- **How the host finds a delta** (`src/net_track.gd`): `NetTrack` keeps every
  carried field's last value (plain values as they are, arrays and
  dictionaries as bytes, packed arrays copied, objects by identity with a
  watch over each object carried by value: a mind, a gun rack, a shot, a
  flow field). Each look (once a tick at most, when a snapshot or delta is
  asked for) compares the `HOT` fields one by one and the rest of an object
  and everything inside it as ONE var_to_bytes, so a field is only looked at
  alone when its part changed; floats to the sign of zero. A feature with
  `NET_GUARDED` lists (wall breaks' windows and fences, breakables' pieces)
  is looked through only when its `net_version` moved: anything that changes
  a window, fence or piece must bump it. The changes per look are logged;
  `delta_since` merges the log since the base (`GameSnapshot.merge`). Never
  "@order": enemies that change places send the enemies whole.
- **The mirror** (`src/game_mirror.gd`): `GameMirror.new(client_game)`,
  `take(bytes)` puts a whole snapshot on (`apply`, onto its running game too)
  or a delta made against the tick it holds (`acked`, the tick to acknowledge)
  by patching its copy of the snapshot and `apply_delta`. It does not tick
  its game; prediction is not here. `NetSync` (the transport) still diffs
  whole captures; switching it to `GameHost.delta_since` / `GameMirror` is the
  transport's to do, and `NetSync.APPLY_RUNNING` can go on.
- **Several players cost little more than one** (one player's tick is the
  same code as before): an enemy's pick stands `RETARGET` and is tested in
  the enemy loop before any call; a new pick draws sight lines to the players
  in reach nearest first and stops at the first seen (none with one alive);
  each player's flow field is walked when something first needs it in a
  tick (`Player.flow_due`, `focus()`; any left are walked after the enemies,
  so every field is current after the tick for a bot or the next tick), and
  a walk from a cell another player's field was walked from this tick copies
  it (`flow_walks`, `FlowField.adopt`: a copy, packed arrays being shared by
  reference); players' bodies look only at the enemies in the cells
  round them (`body_cells`). New per-player work should be on demand like
  these, never a loop over every enemy for every player each tick.
- **Costs** (headless, this PC loaded by other work, so only roughly; see
  `tools/net_bench.gd`, which times old and new alike, run side by side):
  a whole capture 3 to 8 ms (was 10 to 30), 15 to 24 KB packed (was 23 to
  38); the host's delta for 4 ticks 1.2 to 2.6 ms with bots playing (was a
  capture and a diff, 20 to 57 ms), 0.6 to 2 KB (was 1.3 to 3.5 KB), put on
  by a mirror in 0.3 to 0.9 ms; up to 4 ms in Hickston with all 99 hands
  alive (`--server`, idle players). A whole snapshot onto a fresh game 8 to
  18 ms. The enemies are most of a delta (every field of every one is read
  each look: about 10 to 20 us an enemy). One player's tick is unchanged;
  four bots cost 1.2 to 1.9 times one (Hickston .62 -> .88 ms).
- **The determinism check** (`tools/net_check.gd`; its quick part runs in
  `check_fixes.gd`): two games fed the bot's recorded controls stay
  identical, snapshot for snapshot; capture, apply to a fresh game, capture
  is the same; bytes and a delta round-trip; the fresh game then runs on
  beside the first and stays identical (the snapshot carries all the play
  there is); with two players both are hunted, player two is hurt by a hand
  and by a blast, takes shells and a beer for themselves and a key for the
  party, opens a door with USE; two two-player games stay identical and
  round-trip; a snapshot kept from tick 600 has not changed by the end. The
  host: its game has the simulation's features and no looks-only ones and no
  sound; it and an ordinary game fed the same controls stay identical; a
  mirror over a fresh client game, kept up by deltas alone every 4 ticks and
  once by a whole snapshot onto its running game, matches the host each time
  it is compared (the patched snapshot and a capture of its game), in every
  chapter and with 2 and 4 players; deltas merge. The bot (`bot_pilot.gd
  as_controls`) asks for USE and the next gun through its controls so a
  lockstep game gets them too.
- **Not done yet:** per-player stats, messages and kill feed; player bodies
  blocking each other; respawn; Maw's area attacks hit only the player she
  is after; a slick or a race car bites one player at a time; the objective
  pin, boss bar, boss checkpoint and rematch think of one player; client
  prediction; the transport using GameHost/GameMirror. The steam scald is
  marked on the hazard now (`Hazard.scalded`, `boss_arenas.scald_count`).

## Multiplayer tests, the crash log and the transport

`docs/multiplayer.md` is the plan (model, rates, transports per platform,
what a networking pass still needs).

- **Presentation must never change play, whoever is local.** Play that reads
  `game.player` outside an enemy's or a player's own step (in a `ticked`
  handler, say) reads the LOCAL player, so two machines would play it
  differently. `multi_bots.gd` holds this: its twin game is seen from the
  last player's machine (`Players.set_local`), and the two must stay
  identical. It found three (the chickens spooked by the local player's run
  only, floating bodies bobbing near the local player only, a race car's
  kill blamed on the local player): now any player, the nearest player.
  Single-player play is unchanged by them.
- **`tools/multi_bots.gd`**: 1 to 4 players in one game, each its own
  `bot_pilot` (`as_controls`) through `game.tick(dt, {slot: controls})`, every
  chapter for `seconds=` or to the end (`whole`), god mode unless `mortal`
  (the harness fills a dry gun in both runs alike, never the pilot's own
  `whole`, which touches one game). Per player: kills (credited to the acting
  player when an enemy dies), damage taken, deaths, stuck time (still, with
  no foe in sight) and the share of the enemies' hunting; the tick's median,
  p99 and max. Fails on any script or engine error (a
  `CrashLog.tally()` round the run), a position that is not a number, a
  player's middle inside a solid cell for half a second, or the twin parting
  (snapshots compared every 600 ticks and at the end). Its quick part
  (`run()`: Hickston with four for 12 s, the bayou with two for 6 s) is in
  check_fixes. Two bots on Hickston idle about 30 s at (45.5, 57.7) in a
  minute: a bot or route matter, not looked into.
- **The crash and error log** (`src/crash_log.gd`, a Godot `Logger` added
  with `OS.add_logger` in `main.gd _ready`, closed in `main_state.gd
  _exit_tree`): a real launch (not a tool, not the browser) writes every
  error and warning to `user://logs/session.log` with the version, screen,
  level, tick, mode, each player's place, health and gun, the last controls
  (`main.last_controls`, set in `advance()`), the last lines of output and
  the script backtrace (debug builds; a release export has none unless
  `always_track_call_stacks`, which costs every call, is on). The same error
  at one place is written REPEATS times, then counted; the file stops at 2
  MB. `CrashLog.note(text)` leaves a line (each level started); a clean exit
  appends a summary (counts, the busiest places, the last notes) and removes
  `session.lock`. A launch that finds the lock keeps the old log as
  `crash-<stamp>.log` and prints one `CRASH LOG:` line; a phone sent to the
  background marks the lock so a system kill there is not a crash; another
  copy running on the profile gets `live-<pid>.log`. KEEP (5) of each kind.
  Nothing runs per frame. check_fixes's CRASH LOG block holds it in a cache
  folder (`CrashLog.start(main, dir)`).
- **The transport** (`src/net/`): `NetSession` wraps ENet or WebSocket
  (`MultiplayerPeer`, packets only), with test latency, jitter and loss on
  what it sends (on the clock handed to `poll`; loss only unreliable).
  `NetWire` is every packet's layout (protocol 3: controls in 14 bytes, buys,
  reloads and the host's rewind among them; inputs sent redundantly with the
  tick the client shows; snapshots with their base, tick, input ack and the
  inputs played since the base; the lobby's messages). `NetSync.Host` plays
  the authoritative game and sends deltas from each client's acknowledged
  snapshot (whole while it has none); `NetSync.Client` rebuilds them and
  steps a copy of the game with the inputs the host played (`play_out`: a
  few ticks behind the newest, smoothly), and puts a snapshot onto the copy
  (`REBUILD_RUNNING`: the running game, no hitch) when it cannot step or a
  check finds it parted. Both can be fed by whoever polls the session
  (`take`, `play`, `add_remote`): the online lobby does. **Shots are judged
  where the shooter saw them**: the host sets `Controls.rewind` (ticks back,
  from the tick the client said it shows, at most `NetSync.MAX_REWIND`) and
  `game.gd _rewound_hands` stands everyone else where `game.place_log` (60
  ticks a second, never carried, every copy keeps its own) had them for that
  player's hands. The rewind travels in the echoed inputs, so every copy
  plays it the same. Two things about snapshots the tests
  found, both fixed in snapshot version 2: a capture shared the game's packed
  arrays (it copies them now; `NetSync.capture`'s deep copy is no longer
  needed), and the save part followed the acting player and carried
  presentation (there is no save part now; `NetSync.comparable` passes a
  version 2 snapshot through as it is).
- **`tools/net_loopback.gd`**: one process, a host and a client peer on
  127.0.0.1 (a port from the process id, so parallel checks do not meet),
  two games, the game's own clock. The host's bot plays player one, the
  client's bot (steered from its copy) player two. Checks every snapshot the
  client rebuilt against the host's (`GameSnapshot.same`), the copy against
  the snapshots once a second, that the client's inputs move player two, and
  no errors; prints bandwidth each way, snapshot and input sizes, lag and the
  host's costs. Its quick part (ENet 6 s with 40 ms, jitter and 5% loss;
  WebSocket 2 s) is in check_fixes.
- **5v5 gun feel** (`TacticalMode.shot_tuning`, `TacticalShop.MOVE_SPREAD`,
  `REACH`, `FALLOFF`): weapons.gd asks `Modes.shot_spread` for every hitscan
  and pellet shot's spread and reach; outside the 5v5 modes it is the gun's
  own, unchanged (the campaign never asks the rules). In them a gun strays more
  on the move by its kind, more in the air, less crouched and still, and some
  guns reach further with their damage falling off (`pvp_damage`); the spread
  is shown as ticks round the crosshair (`TacticalScreens._spread_marks`). The
  bots stand to shoot with the guns that need it, scope a sniper rifle past
  arm's length, and buy by a style per slot (`TacticalBot.STYLES`). The 5v5
  maps' fences never break (`breakables.cfg` `never`). The bots' attack
  gathers at the last route point no hold of the target site can see
  (`TacticalBot._stage_for`, `_released`, `STAGE_MOST`) and goes in together,
  guns on the site's holds (`_corner_to_check`). Hostage rescue has nearer
  rescue points (`tactical` `rescue_more`, `HostageMode.rescue_boxes`) and
  carriers run. The 5v5 HUD: `hud.gd _draw_team_bar` (VEST, side and goal,
  THROWN; `TacticalScreens.bar_state`), the results
  (`TacticalScreens.results`), the players drawn as `billy` (outlaws) and
  `yard_deputy` (deputies) cels at the hit box's height
  (`TacticalScreens.player_sprite`). Balance is read off `tactical_check.gd`'s
  summary (side wins per map and mode, kills by gun, plants, `deaths=` for
  where players fell); bot matches, so only a guide. The ten side guns'
  models wear their side (`weapon_views.py` `O_*` outlaw materials: bluing
  rubbed brown, rust, brass tacks, twine, snakeskin, XXX; `D_*` deputy ones:
  blue-black steel, black polymer, silver stars, brass county tags, a light
  on the riot pump); `pbr(edge=, cavity=)` rubs real edges and darkens
  creases, used only by those materials so the campaign guns render as before.
- **Online 5v5** (`src/net/net_play.gd`, `lobby_screens.gd`, `net_upnp.gd`;
  `docs/online.md` is the how-to). `NetPlay.host_lobby` / `join_lobby`;
  the front end polls it every frame (`main.gd _net_frame`) and acts on
  `take_changes()` (a match began, back to the lobby, a bot or a person
  took a slot). HELLO carries name, password and version (refused: wrong
  password, another version, full, a match on without LATE JOIN). The host's
  settings are `NetPlay.LOBBY_ROWS` and `MATCH_ROWS`; the match ones reach
  the mode through `Modes.HOST_SETTINGS` (freeze, buy and round seconds,
  start cash, friendly fire, bot skill, bots, `teams` and `names` by slot:
  the host is slot 0, then the people, then bots to the team size). A match
  is made by `main_flow.gd net_match_game` on every machine alike (the
  host's play settings, START's "sim", over each machine's own), then
  played: the host ticks at `NetSync.STEP` with its own player and the
  bots (`_net_host_tick`); a client sends controls and plays its copy out
  (`_net_advance`), and draws its own aim with the turns the host has not
  played yet (`_net_aim`; never on a frame the start-up view check redraws).
  Someone leaving mid-match: a bot plays on in their slot; LATE JOIN: a
  newcomer takes the bot's slot on the team with fewer people. ESC asks
  before leaving; nobody pauses or saves. The router is asked for the port
  by UPnP on a thread; the join code is the outside IPv4 and port in ten
  characters (`NetPlay.to_code`). ENet peers wait `NetSession.PATIENCE_MS`
  of silence before giving up (a machine loading a map stalls). Play that
  reads `game.local_player` must not change anything carried: the 5v5's
  "last one standing" call used to, and the online check found it.
  `tools/net_showdown_check.gd` holds it all (host plus three clients in one
  process, lag and loss as asked; in check_all and CI).
  breaks or the posse); per-player stats (chapter stats and the tally are
  the local player's) and a kill feed; the steam scald list is keyed by
  hazard instance id (not carried). Respawn, bodies blocking, area attacks
  on every player and the group's boss fight are the modes' (below).

## Modes

`src/modes/` holds the rules a game plays by; `features/mode_feature.gd`
(id `mode`, a simulation feature, last in `Features.ALL`) holds what they
remember and runs their hooks. The **campaign** is the default and nothing
in either runs for it: its feature saves nothing (old saves, fixtures and
every single-player check are as before).

- **Framework.** `GameMode` (`game_mode.gd`) is one shared, stateless object
  per mode (`Modes.rules_for(name)`): `start` (first tick, after the posse),
  `joined`/`left`, `tick`, `downed(p, by)` (health reached 0; `by` the slot
  whose hit landed, from `st.blame`, -1 the world or an enemy), `respawn`,
  `defeated` (the death screen: `game.defeated()`, which the front end asks
  instead of `player.health <= 0`), `over` (versus results), `pickup`,
  `hurt_scale(attacker, victim, blast)` (friendly fire), `won`, `scores`.
  State lives on the players (`Player.down_at`, `revive`, `holding`,
  `frags`, `deaths`, `team`, `downed_by`) and in the feature (plain values:
  `mode`, `scaled_upto`, limits, arena, spawns, pickups coming back). A
  save keeps the mode and every player past the first (place, health, guns,
  pockets; frags for all) in the features block (no new save version), so a
  co-op save loads as co-op with its partners. `Modes.setup(game, name,
  count, options)` before the first tick; `Modes.rules(game)`,
  `Modes.mode_of(game)`, `Modes.is_versus(game)`. A player's hit on another
  goes through `Modes.player_in_line`/`player_hit` (hitscan),
  `shot_strikes` (`_hits`) and `blast_hit` (explode), which blame the
  shooter; `Controls.hold` is USE held down (the front end sets it from the
  bound key).
- **Co-op** (`coop_mode.gd`): keys and the PA lead shared (`Players.SHARED`),
  guns, health, rounds and pockets each player's own. A gun or ammo pickup
  goes to EVERY player up (each gets the toucher's amount); pocket items to
  the toucher. At 0 a player is DOWN: a partner holding USE within 1.3 for 3 s
  stands them up with 35 (`REVIVE_*`; letting go eases the progress back);
  left 20 s they come back beside the nearest partner with 50, guns kept.
  Lost only when everyone is down at once. A partner's bullets pass through
  you, their blasts bite at half, your own in full. A boss fight begins when
  ANY player up walks into its arena (`BossKit.party_in_arena`); the bar,
  boss loop and checkpoint follow the local player; a retried fight, a
  loaded save or a rematch brings the partners to player one's side
  (`Modes.gather`, main_flow `_take_mode`); the entrance hold and hitstop are
  single-player only (as before). The exit ends the chapter for the whole
  party (anyone down comes along with 35) and each partner carries their own
  kit into the next game (`Modes.carry`). Every area attack hits everyone in
  it: steam and chalk (`update_hazards`), burning slicks (per-player bites:
  `s[3]` player one, `s[4+slot]` the rest), race cars (`car[2]`, `car[3+slot]`;
  the shake and the hit sound only on a hit now), Maw's rolling pin, stomp
  rings (`ring[3]` player one, bits of `ring[4]` the rest) and loose beam
  (`beam_hurt`), arena fire, rollers, the log carriage, steam jets and core
  pulses (already per player).
- **Scaling** (`CoopMode.SCALE`, applied on the first tick and to every enemy
  that joins later, `scale_new`):

  | players | hands' health | bosses' health | extra hands at the start |
  | --- | --- | --- | --- |
  | 1 | x1 | x1 | none |
  | 2 | x1.25 | x1.6 | a partner beside every 3rd hand about |
  | 3 | x1.5 | x2.2 | every 2nd |
  | 4 | x1.75 | x2.8 | every hand |

  The extras join after the level's own (the posse feature saves them).
- **Deathmatch** (`deathmatch_mode.gd`): no enemies (cleared at the start:
  the level's own, posse, critters); spawn points worked out from the arena
  (`Modes.spawn_points`: open dry cells with nothing within .45, reachable
  from the middle, spread farthest-first, inside a boss kind's `box` when the
  arena names one); everyone starts with `Modes.give_kit` (crowbar, .38,
  shotgun). Every hit lands at `Modes.PVP_SCALE` (.5) of what it does to a
  hand, your own blast too. A kill is a frag, a fall to the world or your
  own blast takes one off; back 3 s later at the spawn point farthest from
  everyone up, full health, the kit again. Pickups come back 20 s after they
  are taken. The frag limit (10) or the time limit (300 s) ends the match:
  `game.won` (play stops) and the results screen in the tally's county-fair
  look (`ModeScreens.results`, from `hud.gd intermission`; ENTER another round,
  ESC the title). Never saved (F5 says so); never the death screen. On the
  range the medic, refills and station cards are off. Arenas
  (`Modes.ARENAS`): `range`, `hub`, `hickston:boss`, `hickston:jerry`,
  `fair:rudy`, `sawmill:foreman`.
- **Team deathmatch** (`team_deathmatch_mode.gd`): RED slots 0 and 2, BLUE 1
  and 3; teammates' bullets and blasts pass by; the frag limit is the team's
  score.
- **The 5v5 round modes** (`tactical_mode.gd`, under it `bomb_mode.gd` search
  and destroy and `hostage_mode.gd` hostage rescue; money and guns
  `tactical_shop.gd`, the HUD and buy menu `tactical_screens.gd`, the bots
  `tactical_bot.gd` with `tactical_nav.gd`'s whole-map step fields). Ten
  players, teams by slot (HOGS the even slots, GATORS the odd); each half one
  plays the OUTLAWS (`st.outlaws`), sides and money swap after
  `rounds_to_win - 1` rounds, first to `rounds_to_win` (7, `--rounds=`) wins, a
  draw after twice that less two. A round: FREEZE (6 s, held still, the buy
  menu on B), live play (bomb 105 s, hostage 115 s), POST (5 s). Buying near
  your own spawn through the freeze and BUY_WINDOW (20 s) after. Survivors keep
  guns (topped up) and vest; the fallen get the crowbar and .38. The outlaws
  plant the shine bomb (hold USE 2.6 s on site A or B; 35 s fuse; deputies
  hold USE 7 s, 3.5 s with wire snips, to cut it; a blast of 420 falling off
  over 10 cells); in hostage rescue the deputies attack, carry a hostage (USE,
  walking) into the rescue box, one out wins. Hits between players use
  TacticalShop's table (`GameMode.pvp_damage`/`blast_damage`: times what the
  gun does to a hand, a head multiplier above `HEAD_FROM`, the part a vest lets
  through), never a teammate's; teammates walk through each other. The
  economy is TacticalShop's header (800 start, 16000 cap, 3250/3500 a win,
  1400 + 500 a loss in a row up to 3400, +800 each for a lost round with the
  bomb planted, kill rewards by gun). The bots (`TacticalBot`) play every
  slot but this machine's, in any build (main_flow `_take_mode`); they buy a
  rifle or save, take the map's `routes` to the team's site of the round
  (`plan_site`), hold the map's `holds` on defence, call foes seen on a site,
  plant, defuse, carry and chase, pick the gun for the distance, and aim with
  a reaction time and a wobble by DIFFICULTY. While this machine's player is
  out the view follows a teammate up (`main.gd _follow_view`;
  `TacticalScreens.human` is the slot the keys drive). The maps are
  `tools/levels/grainyard_plan.gd` (Puckett Grain Co-op), `holler_plan.gd`
  (Holler Distillery) and `salvage_plan.gd` (Mundell's Salvage), original
  layouts each built for both modes; a plan's `meta["tactical"]` (level JSON
  `tactical`, `LevelData.tactical`) holds `attack_spawns`, `defend_spawns`,
  `sites`, `hostages`, `rescue`, the bots' `routes` and `holds`. The title's
  5V5 SHOWDOWN picks mode, map and length (`main_state.gd showdown_*`); the
  command line is `--mode=bomb|hostage [--arena=holler] [--rounds=7]`.
  Ten guns were added for it, at the end of weapons.cfg (so saves and number
  keys keep the old order), each side with its own pistol, shotgun, SMG,
  sniper and machine gun (TacticalShop.ITEMS `who`; SIDE_PISTOL the kit's):
  `hunter` (HOG HUNTER .30-06, scoped bolt-action) and `mower` (CORN MOWER,
  belt-fed) the outlaws', with `hogleg` (HOGLEG .44) and `grease_gun`; the
  deputies' `county45` (their kit pistol), `star357`, `riot_pump`, `tommy`
  (SQUAD TOMMY), `patrol_bar` and `marksman` (COUNTY MARKSMAN, scoped
  semi-auto). Weapons.HUNTER..MARKSMAN are 16..25. Each is modelled in
  `scripts/blender/weapon_views.py` (pistols on the revolver plate's rig,
  the grease gun too; the rest the shotgun plate's), cut by
  `build_weapon_views.gd`, has its own flash style (`build_gun_fx_art.gd`
  STYLES: hunter, mower, auto45, magnum, pump, smg, bar, marksman), muzzle
  light (`[light.muzzle_<gun>]`) and sounds in audio_spec (a report, room
  twin, dry, equip and reloads each; ElevenLabs, about 365 credits for all
  ten). The throwables are four more (Weapons.FLASH_JAR..FIRECRACKER_CAN, 26..29;
  weapons.cfg `thrown`: dynamite-like poses, `shot_life` a fuse; shots.cfg
  `rolls`: they tumble as thrown dynamite does; the cocktail bursts on impact),
  modelled on the crowbar plate's rig, with their own flight pictures
  (`fx_<name>`, cut from the raw render by `build_weapon_views.gd`).
  `game_combat.gd explode()` hands them to `src/modes/tactical_utility.gd`:
  a flash blinds by distance and facing (`st.blind`, the white-out over the
  view, bots blind too), smoke clouds (`st.clouds`, `fx_smokecloud_*`; bots'
  sight held by `smoked()`), fire (`st.fires`, `fx_flame_*`, bites blamed on
  the thrower; smoke puts it out) and decoys (`st.decoys`, the thrower's gun
  in bursts). They tick in any mode (the range has them). The store has two
  pages (guns, gear + thrown; four throwables at most); the barker announces
  over the PA (`ann_*` voice cues) and the planted bomb beeps faster. A gun with weapons.cfg `scope` puts the
  scope up and down on ALT FIRE (game.gd `_step_hands`, `Player.scoped`, carried
  in snapshots with the player), fires with `scope_spread` while it is up
  (weapons.gd), and `src/scope.gd` zooms the view (Renderer.base_focal =
  `fov_focal` times the zoom; aiming slopes use the same focal, so the
  cross-hair stays true) and masks it to a glass; the mouse turns slower by the
  zoom. No campaign pickup gives them; the 5v5 store sells them and the range
  and console can hand them out. In a 5v5 round the number keys are the round
  shooters' (1 long gun, 2 sidearm, 3 crowbar, 4 dynamite; TacticalScreens).
  `tools/tactical_check.gd` plays every map and mode out with ten bots (round
  by round: who, how, when; `verbose` lists every death); `tools/tactical_frames.gd
  -- out=<dir>` (a window) takes pictures of the picker, buy menu, sites,
  automap, planted bomb, hostage, scoreboard and results. Never saved.
- **Presentation** (`mode_screens.gd`, drawn only with more than one player):
  partners in the world (`player_<heading>_<step>` cels, tinted by slot,
  squat when down), each partner's tag and health over their head or at the
  view's edge with an arrow, `E  HOLD TO REVIVE P2` where the use prompts go
  and the progress, the frags and clock in versus, the down screen
  (`game_view.gd`: YOU'RE DOWN with the respawn count, FRAGGED BY P2) instead
  of the death screen while play goes on, and the results.
- **Running them locally** (no networking): `--mode=coop --players=2
  [--level=hickston]` (without `--level` the title's NEW GAME), `--mode=
  deathmatch --players=2 [--arena=hickston:boss] [--frag-limit=5]
  [--time-limit=120]`, `--mode=team_deathmatch --players=4`. Every player but
  this machine's is played by `tools/mode_bot.gd` (bot_pilot plus reviving and
  following in co-op, hunting in versus), from the project folder only
  (`DevConsole.available()`); an exported build leaves them standing.
  `tools/mode_check.gd` (its quick part in check_fixes; `-- seconds=90` plays
  longer) holds the rules; `tools/mode_frames.gd -- out=<dir>` (a window)
  takes pictures of the partner tags, the revive, the down screen, a
  deathmatch and both results screens (`docs/modes/`).
- **Not done:** online play outside the 5v5 modes (co-op and deathmatch);
  the browser build online (it would need WebRTC or a WebSocket relay); a
  relay or NAT punch-through for hosts whose router will not open the port
  (forward it, or a VPN); client prediction of walking (only the aim); a
  second local input set (split keyboard);
  a kill feed outside the 5v5 modes; a lying-down picture for a player
  who is down (the standing one, squat); spawn points from the plans outside
  the 5v5 maps (only worked out); versus pickups other than the level's own;
  the title menu's only mode entry is 5V5 SHOWDOWN (the rest command line
  only). A save or snapshot taken while player
  one is down does not load (SessionStore refuses a player at 0; the
  quicksave is refused then anyway). The co-op boss checkpoint's retry with
  partners is put together from the save round-trip and `gather`, with no
  check of its own; the boss PARs and the tuning are single-player numbers.
