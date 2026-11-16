# Checks, CI and picture references

Every check is a headless Godot script in `godot/tools/` that prints one line
when it passes (`... OK`). Run the quick set after every change and the whole
set at the end of a piece of work. The full command list is in
[commands.md](commands.md).

## check_all

```
godot --headless --path godot --script res://tools/check_all.gd -- lint    # everything, plus gdformat and gdlint
godot --headless --path godot --script res://tools/check_all.gd -- quick   # about a minute: the set to run after every change
godot --headless --path godot --script res://tools/check_all.gd -- fast    # without the walkthrough and the quest reach
godot --headless --path godot --script res://tools/check_all.gd -- only=check_fixes,net_lag   # some rows
godot --headless --path godot --script res://tools/check_all.gd -- shard=2/6 jobs=2 full     # what CI's "Checks 2 of 6" runs
```

Each check runs in its own Godot process with its own scratch profile and
cache folder (`PROFILE_VARS`: APPDATA and LOCALAPPDATA on Windows,
XDG_DATA_HOME and XDG_CACHE_HOME on Linux), so none of them touches your
saves or another check's files. The cache folder matters: the tools keep
boss checkpoints, County Run and range records under `OS.get_cache_dir()`,
and two checks starting chapters at once would otherwise clear each other's
checkpoints (seen as `boss_rematch_check` failing only beside other checks).
One table at the end with each row's time, and the end of each failing
check's output. `lint` also runs gdformat --check and gdlint from the repo's
`.venv`. Exit 1 if anything failed.

- **check_fixes runs as its parts** (`check_fixes_1` ... `check_fixes_6`, one
  process each, from its `PARTS`), so the longest check no longer sets the
  pace: about 50 s each on the desktop instead of 4 1/2 minutes in one.
- `only=a,b` runs the named rows (a script's name takes all its parts); an
  unknown name fails.
- `shard=K/N` shares every row out over N shards, longest first onto the
  lightest (by `CI_SECONDS`), and runs the K-th. CI's matrix runs the six
  shards, so **a row added to `CHECKS` is in CI with no workflow edit**; give
  it a `CI_SECONDS` entry once a run shows its time (unlisted rows count 8 s).
- `jobs=J` runs at most J rows at once (CI: 2 on a 4-core runner); `full`
  prints every row's whole output, in folded groups on GitHub Actions.
- Rows in `ALONE` (`net_lag`: its limits are on online timing) run last,
  with nothing beside them.
- check_all reads the children's output every 10 ms: a child whose output
  pipe is full waits until it is read, and at the old 100 ms net_lag's
  timing came out differently (13% of hits judged misses, over its 12%
  limit, where a plain run has 8%) and every check ran slower.

| Check | Passes with | In quick | What it holds |
| --- | --- | --- | --- |
| `check_shader` | SHADER OK | yes | texture counts: `display.gdshader` at most 9 (incl. TEXTURE), each view3d shader with its includes at most 10 |
| `view3d_check` | VIEW3D CHECK OK | yes | every level's 3D mesh builds headless; every prop and actor scene loads (a station's with both looks, every quest picture modelled); every slab (pickups, loose things, range targets) builds at its picture's size; no fallen body's part stays up at `down` (fit.json `down_high` for the cow's raised legs); the hanging lamp is the shop_lamp model and a tipped cow rolls on her hooves (`ActorView.tipped`) |
| `verify_assets` | ASSETS OK | yes | assets and levels load; chapter-only kinds really are one chapter's; pending music noted |
| `check_fixes` | PARITY FIXES OK | | the parity regression checks and the quick parts of many others (below), in six parts side by side |
| `physics_check` | PHYSICS OK | yes | gibs, brass, chunks and bodies dropped on decks, ramps and stairs and thrown at walls rest on a surface, never inside anything; the loose-things features on a loft ([gameplay.md](gameplay.md#loose-things-on-the-real-3d-shape-v300-remaster)); ragdolls lie on decks, treads, ramps and past a rail and sleep, no model sunk past 1 cm, one body on another, slow-mo finishers start on the last kill and never with company (`physics_ragdolls.gd`); loose things settle with no snap; nothing thrown fast passes a thin wall; water splashes, sinks and drifts (`physics_water.gd`); the shared physics core: the exact solver the same to the bit as the pins' old one, the grid, boxes stacking and waking what lies on them, a body on a wreck piece and a board on a body (`physics_core.gd`, [gameplay.md](gameplay.md#the-shared-physics-core-engine-pass-6)) |
| `live_props_check` | LIVE PROPS OK | yes | things taken up, held, thrown (a hand hurt and shoved, a propane tank breaking and going up, jugs spilling shine, a brute heaving a tank), set down and saved; fire spreading over hay, never onto stone or dirt, burning out, the same twice, sooner in rain; a still spraying and going up; a snapshot carrying a throw and a fire on tick for tick; all of it off with LIVE PROPS AND FIRE off ([gameplay.md](gameplay.md#picking-things-up-fire-that-spreads-the-stills)) |
| `climb_check` | CLIMB CHECK OK | yes | every chapter has ladders, each joined foot to top in the nav graph; a ladder takes the player up and down, JUMP lets go; pull-ups onto a chest-high stack and from it onto a roof, not onto one too high; a hand comes up a ladder to the player on a lookout and drops off it to get at them below; a hand under fire ducks out of sight, peeks out, fires and goes back; a hand kicks a door open (not EASY or CLASSIC); the same run twice comes out the same |
| `vehicle_check` | VEHICLES OK | yes | each vehicle (airboat, car, mower) is got into with USE, drives, strikes something and bounces off never inside a wall, runs a hand down and is got out of; the airboat keeps to water, the car holds no gun, a wreck throws its driver out, a rider rides along in co-op, a snapshot copy drives the same ([gameplay.md](gameplay.md#vehicles)) |
| `plank_check` | PLANK CHECK OK | yes | a barn's and a pen's wall at the fair, the sawmill's shed, a bayou shack and a gabled barn on County Run's Hickston: one may open, shot about it shows its boards out (a merged run cut at the cell), broken through it is floor to bodies, sight and both flow fields and walked through, a shed keeps its roof (and gable) over the gap, a pen's neighbours stand their own height, its planks rest on a floor, a snapshot and a save open it the same with the same walls ([gameplay.md](gameplay.md#walls-break-too)) |
| `wreck_check` | WRECK CHECK OK | yes | every kind of breakable with `pieces`, windows and fence cells on the chapters, a County Run map and the hub throw real pieces that all come to rest on a floor, never inside anything; none on the versus maps; the cap holds; a save put back throws nothing; asleep costs next to nothing ([gameplay.md](gameplay.md#in-real-pieces-of-themselves)) |
| `save_fixtures` | OLD SAVES OK | yes | saves from every earlier version still load |
| `level_edit_check` | LEVEL EDIT OK | yes | level editing keeps the walls right |
| `quest_reach` | QUEST REACH OK | | every quest prop, gate and item can be used from where it is seen, and never through a wall (slow; `tour=<json>` for pictures of each prop) |
| `bot_campaign` | CAMPAIGN WALKTHROUGH OK | | the bot plays the campaign through (slow) |
| `net_showdown_check` | NET SHOWDOWN OK | | online 5v5, host plus three clients, lobby to lobby (`lag= loss= seconds=`) |
| `net_server_check` | NET SERVER OK | | an always-open lobby with no host player |
| `menu_touch_check` | MENU TOUCH OK | yes | taps through every menu, the 5v5 store, the County Run screens as touch events |
| `camera_check` | CAMERA CHECK OK | yes | the QUALITY tiers (pick, presets, AUTO's meter, physics steps); the HUD's Control boxes compose to `HUD.draw`'s bar pixel for pixel (campaign, 5v5, County Run, full and MINIMAL); PHOTO MODE in and out, flying, the player in view, a filter, a picture saved; the KILL CAM noted, sampled, replayed with stand-ins and skipped; play's snapshot unchanged by either; the view polish (`view_polish_check.gd`): SHADOWS' pairs and blobs, marks on a prop's model (holes, scorch, char, kept and handed on), the storm wall's curtains and ring |
| `county_check` | COUNTY CHECK OK | | County Run rules; each map through a death and a retry |
| `county_net_check` | COUNTY NET CHECK OK | | a County Run party of two over ENet and WebSocket against a lobby server (`seconds=30`, as CI always ran it) |
| `games_check` | GAMES CHECK OK | yes | the range's board on a lobby server over ENet (posts, a name's best, refusals, asks, the County Run board beside it), the fair's shooting gallery (the bell, each target's points, a can flying and bouncing, the house paying, the prizes saved, no station or door added), the hub's trophy shack (statuettes by the gates open, cups, gnomes, its card), the range's duck row (a duck turned at the rail's end spins round on its stick) |
| `leak_check` | LEAK CHECK OK | yes | every game let go is freed: games made and disposed (campaign, co-op, deathmatch, County Run, range, Crossroads, a host's) and the front end's own flow (a chapter, the Crossroads, the range, a County Run, co-op, a deathmatch, back to the title) come back to the same object count round after round ([architecture.md](architecture.md#letting-a-game-go)) |
| `cover_check` | COVER CHECK OK | yes | the 5v5 maps' boarded cover: shot through (floor, sight, a shorter way), stood up again each round, kept by snapshots alone |
| `bot_check` | BOT CHECK OK | | the 5v5 bots' aim per BOT SKILL against a strafing target at 5, 12 and 20 cells (first hit, hit rate, kills inside 6 s within bounds; EASY slower than HARD; no laser up close), a target behind smoke never taken for a foe or shot at (and with the lane clear it is), ten-bot matches where they plant, carry and rescue a hostage and the team radio speaks, and a bomb planted with the outlaws down cut by the deputy bots on grainyard, salvage and pineacres (`bench` prints the before/after table: four skills, 4..22 cells, standing and strafing) |
| `replay_check` | REPLAY CHECK OK | | replays play back exactly (`replay_check.gd`, run `-- quick`): bots record chapter one from a fresh game, sawmill from the middle with its keys as actions and a cheat and a wound outside them, the quarry boss fight, County Run with card picks and co-op with two; each from its bytes onto a fresh game matches every hash and the whole end snapshot; a recording past its cap plays across its gap; a nudged game is caught within a hash; the front end's own recorder (advance, act, a setting changed mid-run), `replay save`, a death's file and the crash log keeping the session's replay. Prints the recording's cost a tick. Without quick, twice as long |
| `net_lag` | NET LAG OK | | what a player feels online (`net_lag.gd`, run `-- quick`: a 120 ms link, limits on rubber band, missed hits, stalls, lost inputs, bandwidth); without quick, three links and the full table |

### What check_fixes runs

Its steps (`STEPS`, each independent: it starts the levels it needs): its own
parity checks (`parity`: including the settings count, 69 plus the key
bindings now, and the fingerpost arms), `weather_check`, `climate_check`
(puddles, mud, wind, the County Run storm front, the critters' physics), the
quest props, `break_check`, `hit_check`, `range_check` (the firing range and
its games row), `feel_check` (penetration), `boss_rematch_check`, the
Mothership and the boss music, `boss_check`, `arena_check`,
`arena_wreck_check` (the arenas coming apart and the bosses' gear shot off),
`boss_lock_check` (locked in with each boss: nothing starts at the door, every
way in shuts once well in, holds, opens at the fall, the retry; co-op brought
in, a snapshot copy, a save),
`squad_check`, `chatter_check`, `sound_check`, the quick parts of
`net_check` (determinism), `multi_bots` (Hickston with four for 12 s, the
bayou with two for 6 s), `net_loopback` (ENet 6 s with 40 ms, jitter and 5%
loss; WebSocket 2 s), the CRASH LOG block (`CrashLog.start(main, dir)` in a
cache folder), `mode_check`, `county_check`, and `geometry_check` and
`map_check` (map sources, MAP_AUTHORING.md).

```
godot --headless --path godot --script res://tools/check_fixes.gd               # every step, in order
godot --headless --path godot --script res://tools/check_fixes.gd -- part=3     # PARTS[2] only
godot --headless --path godot --script res://tools/check_fixes.gd -- only=boss_check,arena_check
```

Every run ends with `STEP TIMES (s)`, each step's time. `PARTS` holds six
lists balanced by those times (about 45 s each on the desktop, 2 1/2 to 4
minutes on a GitHub runner); the last part also runs any step no part
names, so a new step is never left out, and a step named twice or not in
`STEPS` fails the run. Add a new step to `STEPS` and to the lightest part.

A check that prints OK and does not quit has been the mixer before
(audio.md "Levels": every level change of a playing voice ticked inside one
frame is cleaned up on the next, at a cost growing with their square); a
probe that times the frames after the work (`await process_frame` twice,
`Performance.TIME_PROCESS`) shows which frame holds it up.

### Other checks, not in check_all

| Check | Passes with | What it holds |
| --- | --- | --- |
| `net_check` | NET CHECK OK | players, snapshots, determinism in full ([multiplayer.md](multiplayer.md#the-determinism-check)) |
| `multi_bots` | MULTI BOTS OK | 1 to 4 bots in one game, twin from the last player's machine (`players=1,2,4 seconds=60`; `whole`, `mortal`, `diff=`) |
| `net_loopback` | NET LOOPBACK OK | a host and client on 127.0.0.1 (`seconds=180 lag=50 loss=0.05`; `websocket`) |
| `mode_check` | MODE CHECK OK | co-op, deathmatch (`-- seconds=90` plays longer) |
| `tactical_check` | TACTICAL CHECK OK | the 5v5 modes, ten bots, every map (`rounds=3`, `rules=shotguns`, `verbose`, `deaths=`) |
| `wall_break_check` | | every level's breakable cells opened at once |
| `boss_rematch_check` | | the rematch rules; `-- bot` times the bot on every boss (PAR) |
| `bench.gd` | SPEED OK | frame time, CPU side (`-- 150`; CI runs `120 max=60` and only catches a big slowdown) |

## CI

`.github/workflows/release.yml` runs its checks side by side on free
GitHub runners (the repository is public: standard runners cost nothing, up
to 20 jobs at once). Every push:

- **lint** (`Format and lint the GDScript`): gdformat --check and gdlint, from
  a cached venv of the `gdtoolkit` pinned in `requirements-dev.txt`.
- **checks** (`Checks 1 of 6` ... `6 of 6`): a matrix; each runs
  `check_all.gd -- shard=K/6 jobs=2 full`, so every row of check_all (with
  check_fixes in its six parts) runs in exactly one shard, two at a time.
  Each row's output is in a folded group; the table with each row's time is
  on the run's summary page (use those times for `CI_SECONDS`).
- **window** (`Boot, art tools, the 3D view's pictures, frame time`): boots
  the game headless and fails on script errors; runs the art tools
  `build_fx_art`, `build_building_tiles`, `build_menu_art`, `build_gore_art`
  into a scratch folder; Xvfb and Mesa's software OpenGL
  (`--rendering-driver opengl3`) tour the 3D view through
  `tools/picture_views.json`, failing on SCRIPT ERROR, Parse Error or SHADER
  ERROR, and `tools/compare_3d.gd` holds the pictures against
  `tools/pictures_3d/` (PICTURES 3D OK; the frames are kept as an artifact);
  last the headless frame time (`bench.gd -- 120 max=60`), alone on its
  runner.

The builds wait for all of those (every shard, the lint and the window job):

| Run | Builds |
| --- | --- |
| a branch push | none |
| `main` | the browser builds (`Web`, `Web Lite`, music packs), deployed with the landing page to Pages |
| a `v*` tag | the EXE (smoke-tested on Windows), the installer, the APK, then the GitHub release with the three files |
| Run workflow (by hand) | input `builds` (on by default): all four as run artifacts; on `main` it deploys the site, on a tag it releases |

**A passed commit is not checked twice.** On a push to `main` or a `v*` tag
the job `earlier` asks the API for a passed run of this workflow on the same
commit (the branch's, which `tools/release.gd` waits for before it moves main
and tags). If there is one, lint, checks and window are skipped and the
builds start at once; if not (a push to main by hand, or the API failing),
everything runs and the builds wait for it as on a branch. Either way
nothing builds or publishes on a commit whose checks did not pass.

**Caches** (`.github/actions/godot`): the Godot editor and, for the build
jobs only, the export templates (fixed keys); the asset packs (keyed on the
art, sound and `pack_assets.gd`); the import cache `godot/.godot` (keyed on
the models, icons and `.import` files; an older one is restored otherwise
and the import redoes only what changed); the gdtoolkit venv. Packs and the
import cache are saved only by `Checks 1 of 6` and by main's browser build,
so parallel jobs do not race; a branch can restore main's caches but not
another branch's.

**Times** (estimated from the v3.2.0 runs before the split, where
check_fixes alone took 12 to 20 minutes; replace with a real run's): a
branch push about 5 minutes (was 19 to 28); main and
a tag after a passed branch about 2 and 4 minutes (each was about 30); so
`release.gd` about 10 to 12 minutes in all (was 45 to 50). The first run after
a cache key changes downloads again (the templates are 1.3 GB).

`gh` is not logged in on this machine: read CI through the public API with
curl.

## Picture references

`tools/compare_3d.gd` holds a window tour's pictures against
`tools/pictures_3d/`: the tour writes `<tag>_fx.png` (lights and glows on, as
players see it) and `<tag>_gpu.png` (off), and each is compared with
`tools/pictures_3d/<tag>_<mode>.png`. Graphics cards rasterise edges a little
differently (the references come from one machine, CI draws with Mesa), so a
picture passes while at most `MOST_OFF` (.03) of its pixels are more than
`NEAR` (24, any channel) apart.

```
godot --path godot --audio-driver Dummy --resolution 1280x800 -- --view-tour=res://tools/picture_views.json --view-out=<dir>
godot --headless --path godot --script res://tools/compare_3d.gd -- <dir>          # compare
godot --headless --path godot --script res://tools/compare_3d.gd -- <dir> update   # pictures changed on purpose: rewrite, then commit
godot --headless --path godot --script res://tools/compare_sheet.gd -- <old dir> <new dir> <out dir> [mode=fx] [left=fx]   # side-by-side sheets
```

- **A view tour always draws with the default settings**, never the
  profile's (the owner's own copy shares it): a lowered gun or the film look
  in a local reference fails CI's Mesa window, which has none.
- Changing how text draws changes every reference (a tour, then `update`).
- A tour viewpoint may set `map`/`map_zoom`, `gun`/`fire`/`ticks`, `rain`,
  `wet`, `lightning`, `actors`, `cels` and `motion` (EASY ON THE EYES).
- The old software-view references (`tools/pictures/`, `picture_check.gd`)
  and shader-view references (`tools/pictures_gpu/`, `compare_views.gd`) were
  deleted with the software renderer.

## Launch check

`--launch-check` (any build, the exported EXE too, with APPDATA pointed at a
profile holding an options.json) launches as a player does, from the title
into Hickston, and writes one line to the log (`LAUNCH CHECK: 3D view ...  HD
...  window ...  mode ...`); `tools/launch_check.gd` is the project-folder
twin.

## Benchmarks

**Benchmarks are noisy.** The owner's own copy of the game, Steam and other
apps often run on this PC. Compare old and new back to back, never against a
number from earlier. Window runs that change settings get a scratch `APPDATA`
(the owner's profile is shared).

- Headless, CPU side: `tools/bench.gd -- 150`.
- In a window: `-- --view-bench=300` (each chapter: the frame, its parts, and
  the 3D view's own parts, `WorldView3D.parts_us`); `--play-bench=<seconds>`
  has the bot play each chapter and prints the slowest frames with the tick's
  and the draw's share; `first_minutes.gd -- whole hitches` times every tick
  of a bot's playthrough.
- **The worst moments**, in a window: `tools/stress_bench.gd -- [only=a,b]
  [frames=240]` builds idle (hickston, a reference), strike (a bowling
  strike), wreck48 (48 wreck pieces flying), fire (hickston's hay burning),
  arena (Maw's third phase, the arena coming apart), fivev5 (ten bots in a
  grainyard round) and county (County Run at 12 minutes, the storm closing,
  38 hands) and prints each one's frame median, p99 and max, tick and render
  means, the view's parts, what is on screen, the shader instance slots held
  and the memory (static, textures, buffers, video). Give it a scratch
  `APPDATA` with an options.json to pick a QUALITY tier.
- **The tick, by listener:** `tools/tick_profile.gd -- 300 [levels=a,b]`
  times each feature's tick (`tick_with`, sleeping ones skipped) and the
  rest ("core": bodies, enemies, shots), idle and in a fight, per chapter;
  `plain` times the whole tick only (the timers cost a little themselves),
  the number to hold old against new.
- **Loading:** `tools/load_bench.gd -- [rounds=3] [levels=a,b]`: per level
  the game made the first time (cold: nav graph and wreck caches empty) and
  again (warm), the 3D level mesh's whole build, the wreck cutting alone.

### Measured before v3.3.0 (track R, 2026-11-16)

Desktop (RTX 5070 Ti laptop, 1280x800 window, the PC busy with other work),
`88b05d3` against track R's branch, back to back, medians of the runs.
Whole details: `docs/godot3d/optimize/R/results.md`.

| What | Before | After |
| --- | --- | --- |
| `--view-bench` all chapters, HIGH / MEDIUM / LOW (3 runs) | 7.20 / 7.17 / 6.03 ms | 6.93 / 6.26 / 5.44 ms |
| hickston fight, the view's actors part (HIGH) | 1.29 ms | 0.74 ms |
| the view's shader numbers (`uniforms`), mothership HIGH | 0.45 ms | 0.30 ms |
| stress county (HIGH): frame median / render | 13.3 / 7.41 ms | 13.0 / 7.04 ms |
| stress county (LOW): frame median / p99 | 11.4 / 32.1 ms | 10.2 / 23.5 ms |
| stress fivev5 (HIGH): frame median | 6.77 ms | 5.76 ms |
| stress arena (HIGH): frame median / p99 | 5.62 / 14.9 ms | 5.15 / 11.8 ms |
| shader instance slots held, arena / county / fivev5 | 772 / 760 / 448 | 468 / 504 / 164 |
| a wall broken through (whole level mesh vs its chunks) | 59 ms | 3.4 ms |
| load, 15 levels, warm (a retry, a load) / cold | 4.64 / 5.79 s | 1.54 / 5.12 s |
| game tick, all chapters idle and fighting (headless) | 0.78 ms | 0.77 ms |

Remaining worst cases: County Run late (12 to 14 ms a frame on this desktop:
33 rigged hands posed every frame, 1.4 to 1.7 ms of AnimationPlayer seeks);
the first visit to a chapter (0.35 to 0.57 s headless: the nav graph, 0.2 to
0.3 s, and the wreck cutting, up to 0.29 s on the Mothership); the web pack
(below). Not measured: a phone, the browser build's frame times, the APK.

**Export sizes** (2026-11-16): Windows EXE 302.6 MB (the 109 MB engine and a
193 MB pack: `assets_gen` 140 MB of which art.bin 49 MB, sfx.bin 13 MB and the
music packs 63 MB; the models' imported scenes 39.5 MB); Web and Web Lite
119.9 MB pack (the chapter art and music packs fetched later) plus 38.8 /
39.5 MB wasm. Art is already deflated per picture; the sound is 16-bit PCM;
the model scenes are uncompressed meshes (mesh compression would change how
they look). Nothing was trimmed: nothing unused was found that is safe to
drop.
- Network: `tools/net_bench.gd -- levels=hickston players=1,2,4 [host]`.
- **The browser:** export both builds, serve each with COOP/COEP headers, add
  a page whose `GODOT_CONFIG` args are `["--", "--view-bench=300"]`, and run
  headless Chrome with its own `--user-data-dir` and
  `--disable-frame-rate-limit --disable-gpu-vsync` (otherwise it caps at
  about 240 fps, as vsync would); the numbers are in its console log
  (`--enable-logging=stderr`).
- Close browser tabs and preview servers after testing: the owner has heard
  game audio from tabs left open.
