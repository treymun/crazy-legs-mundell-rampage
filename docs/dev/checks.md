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
```

Each check runs in its own Godot process with its own scratch profile
(APPDATA), so none of them touches your saves or another check's files; one
table at the end, and the end of each failing check's output. `lint` also
runs gdformat --check and gdlint from the repo's `.venv`. Exit 1 if anything
failed.

| Check | Passes with | In quick | What it holds |
| --- | --- | --- | --- |
| `check_shader` | SHADER OK | yes | texture counts: `display.gdshader` at most 9 (incl. TEXTURE), each view3d shader with its includes at most 10 |
| `view3d_check` | VIEW3D CHECK OK | yes | every level's 3D mesh builds headless; every prop and actor scene loads |
| `verify_assets` | ASSETS OK | yes | assets and levels load; chapter-only kinds really are one chapter's; pending music noted |
| `check_fixes` | PARITY FIXES OK | | the parity regression checks and the quick parts of many others (below) |
| `save_fixtures` | OLD SAVES OK | yes | saves from every earlier version still load |
| `level_edit_check` | LEVEL EDIT OK | yes | level editing keeps the walls right |
| `quest_reach` | QUEST REACH OK | | every quest prop, gate and item can be used from where it is seen, and never through a wall (slow; `tour=<json>` for pictures of each prop) |
| `bot_campaign` | CAMPAIGN WALKTHROUGH OK | | the bot plays the campaign through (slow) |
| `net_showdown_check` | NET SHOWDOWN OK | | online 5v5, host plus three clients, lobby to lobby (`lag= loss= seconds=`) |
| `net_server_check` | NET SERVER OK | | an always-open lobby with no host player |
| `menu_touch_check` | MENU TOUCH OK | yes | taps through every menu, the 5v5 store, the County Run screens as touch events |
| `county_check` | COUNTY CHECK OK | | County Run rules; each map through a death and a retry |
| `county_net_check` | COUNTY NET CHECK OK | | a County Run party of two over ENet and WebSocket against a lobby server |

### What check_fixes runs

Besides its own parity checks (including the settings count, 59 now, and the
fingerpost arms), check_fixes runs or holds: `hit_check`, `squad_check`,
`chatter_check`, `boss_check`, `arena_check`, `break_check`, `feel_check`
(penetration), `weather_check`, the quick parts of `net_check` (determinism),
`multi_bots` (Hickston with four for 12 s, the bayou with two for 6 s),
`net_loopback` (ENet 6 s with 40 ms, jitter and 5% loss; WebSocket 2 s),
`mode_check`, `county_check` and `boss_rematch_check`, `range_check` (the firing range), the CRASH LOG block
(`CrashLog.start(main, dir)` in a cache folder), and `geometry_check` and
`map_check` (map sources, MAP_AUTHORING.md).

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

`.github/workflows/release.yml`:

- **checks** (every push): boots the game headless and fails on script
  errors; runs the art tools `build_fx_art`, `build_building_tiles`,
  `build_menu_art`, `build_gore_art` into a scratch folder; then
  `verify_assets`, `view3d_check`, `check_fixes`, `net_showdown_check`,
  `net_server_check`, `menu_touch_check`, `county_check -- seconds=45`,
  `county_net_check -- seconds=30`, `save_fixtures`, `level_edit_check`,
  `quest_reach`, `bot_campaign`, and a headless frame time (`bench.gd`).
- **window** (after checks): Xvfb and Mesa's software OpenGL
  (`--rendering-driver opengl3`) tour the 3D view through
  `tools/picture_views.json` into a folder, fail on SCRIPT ERROR, Parse Error
  or SHADER ERROR, then `tools/compare_3d.gd` holds the pictures against
  `tools/pictures_3d/` (PICTURES 3D OK). The frames are kept as an artifact.
- **Windows EXE, Android APK and the browser builds, the release and the
  site** run on `main`, `v*` tags or a run started by hand (packs are cached
  until an asset changes). The Windows and Android builds also run on
  `refs/heads/godot-3d`, as run artifacts only: no release, no site.

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
  `wet`, `lightning`, and `actors`.
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
- In a window: `-- --view-bench=300`; `--play-bench=<seconds>` has the bot
  play each chapter and prints the slowest frames with the tick's and the
  draw's share; `first_minutes.gd -- whole hitches` times every tick of a
  bot's playthrough.
- Network: `tools/net_bench.gd -- levels=hickston players=1,2,4 [host]`.
- **The browser:** export both builds, serve each with COOP/COEP headers, add
  a page whose `GODOT_CONFIG` args are `["--", "--view-bench=300"]`, and run
  headless Chrome with its own `--user-data-dir` and
  `--disable-frame-rate-limit --disable-gpu-vsync` (otherwise it caps at
  about 240 fps, as vsync would); the numbers are in its console log
  (`--enable-logging=stderr`).
- Close browser tabs and preview servers after testing: the owner has heard
  game audio from tabs left open.
