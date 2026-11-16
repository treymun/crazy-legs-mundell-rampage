# Commands

Building and checking the game, and making its art, need only Godot (and
Blender for the enemy, weapon and prop renders and the 3D models). Python is
only for the sound tools, the landing page's pictures and gdformat/gdlint, all
in the repo's one `.venv` (`requirements-dev.txt`: numpy, Pillow, elevenlabs,
dotenv, gdtoolkit): run them with `.venv\Scripts\python.exe`, and lint with
`.venv\Scripts\gdformat` and `gdlint`. Godot is
`C:\Users\treym\OneDrive\Desktop\Tools\Godot_v4.7.2-stable_win64_console.exe`
(written `godot` below). Run from the repo root.

What each check holds is in [checks.md](checks.md).

## Packing and importing

```
godot --headless --path godot --script res://tools/pack_assets.gd   # rebuild godot/assets_gen (no Python)
godot --headless --path godot --import                               # after adding a class_name script or new .glb files
```

## Art (then pack_assets)

See [art.md](art.md).

```
godot --headless --path godot --script res://tools/art/build_fx_art.gd       # also gore, menu, building tiles
godot --headless --path godot --script res://tools/art/build_gun_fx_art.gd   # the LIGHTS AND GLOW flashes, blasts, strikes
godot --path godot --audio-driver Dummy --resolution 1280x800 --script res://tools/gun_frames.gd -- out=<dir>   # every gun firing, a blast
godot --headless --path godot --script res://tools/art/build_enemy_actors.gd -- kinds=billy no-render   # weapon views likewise
godot --headless --path godot --script res://tools/art/build_town_props.gd -- names=outhouse,still      # Blender; no-render reuses

# The 3D models (then pack_assets and --import, then the scenes)
godot --headless --path godot --script res://tools/art/build_prop_meshes.gd -- names=outhouse,tractor [no-render]
godot --headless --path godot --script res://tools/art/build_prop_scenes.gd [-- names=a,b]
godot --headless --path godot --script res://tools/art/build_actor_meshes.gd -- kinds=billy,coot [no-render]
godot --headless --path godot --script res://tools/art/build_actor_scenes.gd [-- kinds=a,b]
```

## Checks (all run in CI too)

One command runs them all at once, each in its own process and scratch
profile, with one table (`lint`: gdformat and gdlint too; `fast`: without the
walkthrough and the quest reach; `quick`: about a minute):

```
godot --headless --path godot --script res://tools/check_all.gd -- lint
godot --headless --path godot --script res://tools/check_all.gd -- quick
godot --headless --path godot --script res://tools/check_all.gd -- only=check_fixes,county_check   # some rows (a script names all its parts)
godot --headless --path godot --script res://tools/check_all.gd -- shard=2/6 jobs=2 full          # what CI's "Checks 2 of 6" runs
cd godot && gdformat --check src tools addons && gdlint src tools addons
godot --headless --path godot --script res://tools/check_shader.gd    # SHADER OK
godot --headless --path godot --script res://tools/view3d_check.gd    # VIEW3D CHECK OK
godot --headless --path godot --script res://tools/verify_assets.gd   # ASSETS OK
godot --headless --path godot --script res://tools/check_fixes.gd     # PARITY FIXES OK (part=K: one of its PARTS; only=a,b: named steps)
godot --headless --path godot --script res://tools/bot_campaign.gd    # CAMPAIGN WALKTHROUGH OK
godot --headless --path godot --script res://tools/save_fixtures.gd   # OLD SAVES OK (-- make: add saves of the new version)
godot --headless --path godot --script res://tools/level_edit_check.gd  # LEVEL EDIT OK
godot --headless --path godot --script res://tools/physics_check.gd   # PHYSICS OK (loose things on decks, ramps, stairs, walls; levels=a,b)
godot --headless --path godot --script res://tools/live_props_check.gd # LIVE PROPS OK (pick up and throw, spreading fire, the stills)
godot --headless --path godot --script res://tools/vehicle_check.gd    # VEHICLES OK (get in, drive, bump, run down, get out)
godot --headless --path godot --script res://tools/vehicle_cab_check.gd    # VEHICLE CAB OK (the seat view, the driving plate)
godot --headless --path godot --script res://tools/wreck_check.gd     # WRECK CHECK OK (broken scenery in real pieces; levels=a,b)
godot --headless --path godot --script res://tools/load_check.gd      # LOAD CHECK OK (the fast level load the same as the old one; levels=a,b)
godot --headless --path godot --script res://tools/plank_check.gd     # PLANK CHECK OK (shed, barn, pen and shack walls open)
godot --headless --path godot --script res://tools/quest_reach.gd      # QUEST REACH OK (tour=<json> for pictures of each prop)
godot --headless --path godot --script res://tools/menu_touch_check.gd # MENU TOUCH OK
godot --headless --path godot --script res://tools/camera_check.gd     # CAMERA CHECK OK (photo mode, kill cam, quality, HUD on Controls, shadows, marks on props, storm wall)
godot --headless --path godot --script res://tools/tune_check.gd       # TUNE CHECK OK (the console's tune set/get/reload/save, every overlay drawn headless, play unchanged)
godot --headless --path godot --script res://tools/net_check.gd       # NET CHECK OK (players, snapshots, determinism; quick: check_fixes's part)
godot --headless --path godot --script res://tools/multi_bots.gd -- players=1,2,4 seconds=60   # MULTI BOTS OK (whole: to the end; mortal; diff=)
godot --headless --path godot --script res://tools/net_loopback.gd -- seconds=180 lag=50 loss=0.05   # NET LOOPBACK OK (websocket: over WebSocket)
godot --headless --path godot --script res://tools/mode_check.gd      # MODE CHECK OK (co-op, deathmatch; quick: check_fixes's part)
godot --headless --path godot --script res://tools/tactical_check.gd -- rounds=3   # TACTICAL CHECK OK (the 5v5 modes, ten bots, every map; rules=shotguns etc.)
godot --headless --path godot --script res://tools/bot_check.gd   # BOT CHECK OK (the bots' aim by skill, smoke, objectives, radio; -- bench for the full table)
godot --headless --path godot --script res://tools/net_showdown_check.gd   # NET SHOWDOWN OK (online 5v5 lobby to lobby; lag= loss= seconds=)
godot --headless --path godot --script res://tools/net_server_check.gd     # NET SERVER OK (always-open lobby, no host player)
godot --headless --path godot --script res://tools/county_check.gd     # COUNTY CHECK OK (COUNTY RUN: rules, maps, a death and a retry)
godot --headless --path godot --script res://tools/county_net_check.gd # COUNTY NET CHECK OK
godot --headless --path godot --script res://tools/wall_break_check.gd # every level's breakable cells opened at once
```

## The 3D view in a window

The 3D view only runs with a window.

```
godot --path godot --audio-driver Dummy --resolution 1280x800 -- --view-bench=300
godot --path godot --audio-driver Dummy --resolution 1280x800 -- --view-tour=res://tools/picture_views.json --view-out=<dir>
godot --headless --path godot --script res://tools/compare_3d.gd -- <dir>          # against tools/pictures_3d (PICTURES 3D OK)
godot --headless --path godot --script res://tools/compare_3d.gd -- <dir> update   # pictures changed on purpose: rewrite and commit
godot --headless --path godot --script res://tools/compare_sheet.gd -- <old dir> <new dir> <out dir> [mode=fx] [left=fx]
godot --path godot -- --play-bench=<seconds>     # the bot plays each chapter; slowest frames with tick and draw shares
godot --path godot -- --launch-check             # launch as a player; one LAUNCH CHECK line in the log (tools/launch_check.gd is the twin)
godot --path godot -- --cpu-canvas               # draw the HUD/menu canvas in software
godot --path godot -- --rematch-all              # open every boss rematch
```

## Window pictures (not in CI)

```
godot --path godot ... --script res://tools/physics_frames.gd [-- only=hits|boss]
godot --path godot ... --script res://tools/live_props_frames.gd -- out=<dir>  # a thing held, thrown, landed; a brute; hay burning; a still
godot --path godot ... --script res://tools/physics_frames.gd [-- only=hits|boss|break]
godot --path godot ... --script res://tools/arena_frames.gd        # the first four boss arenas (docs/boss_arenas/)
godot --path godot ... --script res://tools/view_polish_frames.gd -- out=<dir> [only=storm|shadow|marks]   # the storm wall, SHADOWS, marks on props (docs/godot3d/polish/L/)
godot --path godot ... --script res://tools/polish_frames.gd -- out=<dir> [only=photo_car|photo_mower|photo_airboat|skids|sparks]   # the 3.3.0 polish: riders in vehicles, skids, sparks (docs/godot3d/optimize/S/)
godot --path godot ... --script res://tools/arena_frames_late.gd   # the last four
godot --path godot ... --script res://tools/lock_frames.gd -- out=<dir> [kinds=boss,rudy]   # each arena's way in open, then shut (docs/godot3d/polish/P/)
godot --headless --path godot --script res://tools/boss_lock_check.gd [-- rudy coop]   # BOSS LOCK OK (also in check_fixes)
godot --path godot ... --script res://tools/vehicle_frames.gd -- out=<dir> [only=car]   # the vehicles parked, from the seat (ahead, down, back), driving, a wreck (docs/godot3d/features/D/)
godot --headless --path godot --script res://tools/art/build_cab_meshes.gd [-- names=cab_car] [no-render]   # the seat views' models (Blender, vehicle_cabs.py); then pack_assets and --import
godot --path godot ... --script res://tools/squad_frames.gd
godot --path godot ... --script res://tools/climb_frames.gd -- out=<dir>   # ladders in every chapter, a climb, a pull-up, a hand on a ladder
godot --path godot ... --script res://tools/mode_frames.gd -- out=<dir>
godot --path godot ... --script res://tools/tactical_frames.gd -- out=<dir>
godot --path godot ... --script res://tools/county_frames.gd -- out=<dir>
godot --path godot ... --script res://tools/range_frames.gd
godot --path godot ... --script res://tools/camera_frames.gd -- out=<dir>   # the HUD (full, MINIMAL, 5v5, County Run), PHOTO MODE's filters and a saved picture, the KILL CAM
godot --path godot ... --script res://tools/death_frames.gd -- out=<dir> [level=hickston] [gun=shotgun] [classic]   # falls: ragdolls, or the scripted ones
godot --headless --path godot --script res://tools/bowl_lab.gd [-- trace]   # bowling lane: a spread of rolls, what stands, the tick's cost
```

(`...` is `--audio-driver Dummy --resolution 1280x800`.)

## Pacing and balance (not in CI)

```
godot --headless --path godot --script res://tools/bench.gd -- 150    # frame time, CPU side
godot --headless --path godot --script res://tools/tick_profile.gd -- 300   # the tick by listener (features) and core, idle and fighting
godot --headless --path godot --script res://tools/tick_profile.gd -- 300 replay   # and what recording a replay costs a tick
godot --headless --path godot --script res://tools/replay_check.gd [-- quick]   # replays play back exactly (front: the front end's part alone)
godot --path godot -- --replay=<file>   # play a replay in the game's view (a path, or a name in user://replays); Esc leaves
godot --headless --path godot --script res://tools/load_bench.gd -- rounds=3   # level loads cold and warm, the level mesh, the wreck cutting (on a worker, not in the load)
godot --path godot --audio-driver Dummy --resolution 1280x800 --script res://tools/stress_bench.gd -- [only=county]   # the worst moments: frame, parts, slots, memory
godot --headless --path godot --script res://tools/first_minutes.gd   # a bot plays each chapter's opening: first fight, kills, health (old-ai: enemies do not hunt)
godot --headless --path godot --script res://tools/first_minutes.gd -- hickston whole   # bot plays it to the end (god mode; hitches: time every tick; diff=<0..3>)
godot --headless --path godot --script res://tools/ttk.gd -- ../docs/weapon_ttk.md   # time to kill, every gun against every enemy
godot --headless --path godot --script res://tools/route_map.gd -- <dir>   # each level's objective route, long detours flagged, PNGs
godot --headless --path godot --script res://tools/boss_rematch_check.gd -- bot   # the bot fights every boss rematch: time to kill (boss_rematch.gd PAR; diff=, runs=)
godot --headless --path godot --script res://tools/boss_rematch_check.gd -- only-bot kinds=boss,rudy difficulty=0,1,2,3   # per difficulty
godot --headless --path godot --script res://tools/gun_sheet.gd    # the 5v5 guns' numbers side by side (md=<file>)
godot --headless --path godot --script res://tools/map_timing.gd   # 5v5 maps: run times to sites, bots' routes and holds checked (strict)
godot --headless --path godot --script res://tools/county_play.gd -- md=<file>   # County Run played to death and long runs
godot --headless --path godot --script res://tools/net_bench.gd -- levels=hickston players=1,2,4 [host]   # ticks, snapshots, deltas
```

## Levels

See [levels.md](levels.md).

```
godot --headless --path godot --script res://tools/levels/build_level.gd -- fair map=<png>   # hickston, fair, sawmill, quarry, bayou, speedway, mothership, range, hub
godot --headless --path godot --script res://tools/levels/build_level.gd -- grainyard        # the 5v5 maps: grainyard, holler, salvage; 2v2: pumpngo, pineacres, landing
godot --headless --path godot --script res://tools/levels/build_level.gd -- county_quarry    # the County Run maps: county_hickston, county_quarry, county_bayou
godot --headless --path godot --script res://tools/level_edit.gd -- fair enemy billy 30.5 25.5
godot --headless --path godot --script res://tools/level_edit.gd -- hickston trigger '<json>'   # src/triggers.gd
godot --headless --path godot --script res://tools/map.gd -- <command> [args]   # map sources (MAP_AUTHORING.md)
```

## Modes and online

```
godot --path godot -- --mode=coop --players=2 [--level=hickston]
godot --path godot -- --mode=deathmatch --players=2 [--arena=hickston:boss] [--frag-limit=5] [--time-limit=120]
godot --path godot -- --mode=team_deathmatch --players=4
godot --path godot -- --mode=bomb|hostage|tagteam [--arena=holler] [--rounds=7] [--rules=<id>]
godot --path godot -- --host-online[=port] --online-name=TREY [--online-password=x]   # straight into a lobby
godot --path godot -- --join-online=<code or address> --online-name=BOB   # (tests: --online-start=2 --online-bot)
godot --headless --path godot -- --lobby-server=../server/lobbies.json   # always-open lobbies (src/net/lobby_server.gd)
godot --headless --path godot -- --server=fair --server-players=2 --server-ticks=12000   # a host, no window (server_loop.gd)
bash server/deploy.sh root@<server address>   # build the Linux server and install/update it (docs/online.md)
```

## Sound

```
.venv\Scripts\python.exe scripts/audio_generator.py status   # credits used: check before spending
```

The ElevenLabs rules are in CLAUDE.md. Never run two generation processes at
once.

## Version and publishing

```
godot --headless --path godot --script res://tools/version.gd -- 3.0.N

# Publish (ask the owner first): stamps, commits, pushes, waits for the
# branch's CI, moves main, tags, waits for main's and the tag's runs (they
# skip the checks the branch passed and only build), then checks the site
# and the release's three files. About 10 to 12 minutes.
godot --headless --path godot --script res://tools/release.gd -- 3.0.N
```

Builds by hand: Actions, "Build, release and publish", Run workflow (input
`builds`, on by default: the EXE, installer, APK and browser builds as run
artifacts; on main it also deploys the site). CI is described in
[checks.md](checks.md#ci).
