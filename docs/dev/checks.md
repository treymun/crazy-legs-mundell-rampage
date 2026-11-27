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

**The scratch-profile guard** (pass 15, `tools/scratch_profile.gd`): check_all
also sets `CLMR_SCRATCH_PROFILE` to the row's folder. The tools that write
the game's profile through the real flow refuse to run (a line saying so,
exit 2, nothing written) unless user:// is under that folder or under the
system's TEMP: `road_check`, `bot_campaign`, `check_fixes`,
`touch_screens_check`, `replay_check`, `leak_check`, `bench_frames`, and
`map.gd`'s render without `out=` (its check, flow, pictures and shot start
themselves again in a scratch profile under TEMP instead). Run one by hand with APPDATA and
LOCALAPPDATA pointed under TEMP (or set `CLMR_SCRATCH_PROFILE` to the folder
APPDATA names). Before pass 15 these wrote into a player's profile when run
on their own (the campaign entry and unlocks, `hickston-quick.json`,
replays, `features-check.json`, `trigger-check.json`). A tool run keeps
NEW PLAYER TIPS' taught tips under the cache folder (`Lessons.file`), not
in `user://lessons.json`. A new tool that writes user:// calls
`ScratchProfile.refuse(self, NAME)` first thing in `_init`.

One table at the end with each row's time, and the end of each failing
check's output. `lint` also runs `scripts/audio_qa.py --check`, gdformat --check and gdlint from the repo's
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
- **The net checks' ports** come from `tools/net_ports.gd` (`NetPorts.pick`):
  under 49152 (past it Windows hands out every outgoing socket's port, and a
  server bound to 127.0.0.1 may share one with such a socket without an
  error and take its packets), each tried quietly first with a plain UDP
  socket and TCP listener on all addresses and on 127.0.0.1 (ENet's own
  failure prints an engine error, which the checks count). Pass 9: before
  it a clash between checks run at once, or with another program, failed a
  check now and then.
- Timing a check asserts is the quickest of a few batches (set_piece_check's
  idle tick), never one batch a busy PC can preempt; online checks count
  ticks, not the wall clock.
- Rows in `ALONE` (`net_lag`, `net_pace` and `net_feel`: their limits are on
  online timing) run last, one at a time, with nothing beside them.
- check_all reads the children's output every 10 ms: a child whose output
  pipe is full waits until it is read, and at the old 100 ms net_lag's
  timing came out differently (13% of hits judged misses, over its 12%
  limit, where a plain run has 8%) and every check ran slower.

| Check | Passes with | In quick | What it holds |
| --- | --- | --- | --- |
| `check_shader` | SHADER OK | yes | texture counts: `display.gdshader` at most 9 (incl. TEXTURE), each view3d shader with its includes at most 10 |
| `view_perf_check` | VIEW PERF CHECK OK | yes | the 3D view's frame stays cheap (pass 10): a line of HUD text draws with one texture a style (the canvas's letter pages); its global uniforms match `project.godot` and the shaders, no view3d shader keeps a uniform array, no frame number goes to a material; two to four turns round Hickston's spawn with its hands awake make no prop or model again after the first, nothing past where it shows gets a model, no view3d shader has instance uniforms and the parts with them stay in WebGL's room with margin; `frame()`'s lower quartile under 1.5 times a yardstick of plain GDScript |
| `heavy_check` | HEAVY CHECK OK | yes | the heavy scenes' speed work stays exact and cheap (pass 13): `WreckPairs.leasts` gives exactly `WreckPhysics._least` both ways on 4,000 random box pairs; `LevelSight.visible` and `PhysCore.way_out` answer exactly as v3.10.0's own code (kept in the check) on random sight lines and points on five maps; on hickston with a few breaks drawn by a view made by hand, a frame drawn again unchanged sets no wreck piece's transform (`WreckLayer3D.placed`) and hands no MultiMesh its rows again (`SpriteLayer3D.uploads`) |
| `stress_bench` (`check`) | STRESS CHECK OK | no | the busy scenes (wreck48, arena, county, and since pass 16 town: 36 houses of geometry, 40 hands awake) built headless with a 3D view made by hand: every frame's model parts with instance uniforms under WebGL's room (60) less 20, and the global uniforms and their blocks under its 1024 slots with the same margin (none since pass 10: each part has its own material); each scene's tick under its budget in yardsticks (`TICK_YARDS`, a fixed piece of GDScript work timed in the same process); `hash` prints each frame's play as hashes, the same on two builds that play the same |
| `view3d_check` | VIEW3D CHECK OK | yes | every level's 3D mesh builds headless; every prop and actor scene loads (a station's with both looks, every quest picture modelled); every slab (pickups, loose things, range targets) builds at its picture's size; no fallen body's part stays up at `down` (fit.json `down_high` for the cow's raised legs); the hanging lamp is the shop_lamp model and a tipped cow rolls on her hooves (`ActorView.tipped`) |
| `actor_check` | ACTOR CHECK OK | yes | the actors' models (polish pass 9): every actors.json kind's glb, scene and looks (square, a power of two), keys numbered once each, bone labels, canvas; fit.json names only models and numbers ActorModels reads; every kind has the frames the game asks for (walk with its closing `w4`, fall, hurt set, a boss's recover, a critter's -1/0/1); texels a metre over each body and head at least `TEXEL_MIN`/`HEAD_MIN`, a boss's `BOSS_MIN`/`BOSS_HEAD_MIN` (pass 13; `report` prints them), the hound's at least `HOUND_MIN`/`HOUND_HEAD_MIN`; the hound's fourteen motions and ten poses (pass 10), each motion's keys in a row, played on the gait, a one-shot ending on its last key, his own fit.json blend, and his drawn size (shoulder .33-.41 and head top .41-.52 of Mundell's drawn height, measured on his skinned model); ActorView's looks-only motion: pose blends, no blend between walk beats, hit flinches by zone with their own dice and still after `FLINCH`, idle breath, mirrored scripted falls (never a boss), game.rng untouched; specks between `View.SPECK_PX_MIN` and `SPECK_PX_MAX` pixels; a partner on the riding mower shows Mundell's `sit` ([view3d.md](view3d.md#actors)) |
| `verify_assets` | ASSETS OK | yes | assets and levels load; chapter-only kinds really are one chapter's; pending music noted |
| `radio_check` | RADIO CHECK OK | yes | the county radio: every line of `radio_lines.json` in the bank with a caption of two lines at most, a gap between songs opens with an ID and ends on the way back, news first (a boss's fall before the rest), lines dealt without coming round soon, the scanner's calls and their spacing, three deaths make news, CUSSIN'/CLEAN/OFF for Dub's crude lines, the RADIO setting, a boss fight holds it and a boss's line hushes it, anyone talking ducks it and Dub over the music ducks the music, a vehicle tuned in, a chapter's events reach the station and its lines are captioned, game.rng untouched ([audio.md](audio.md#the-county-radio-content-pass-8)) |
| `audio_qa_check` | AUDIO QA OK | yes | the sound's wiring and finish (pass 9): every cue the game names in a literal is made, every finished cue starts and ends at silence and every loop runs into its start, every CLEAN copy within 2 dB of its cussing take, play's hold on the music stacks with Dub's and a jukebox's and goes with play, no hand says a line twice running; the full measurement is `scripts/audio_qa.py --check` (lint) ([audio.md](audio.md#audio-qa-pass-9)) |
| `voice_check` | VOICE CHECK OK | yes | every spoken line in the audio manifest is mastered from its transcript, has its CLEAN copy (cuss lines) and loads from the packed bank at 0.3 to 6 s; every caption the game shows for a line (bosses, hands, tough guys, Maw, the fair PA, Mundell, the cuss pack, the county radio) is the text it was made from; every recording, transcript and kept take is booked in the ledger, which adds up to the account's drop ([audio.md](audio.md#voices)) |
| `pack_check` | PACK CHECK OK | | the browser build's split ([the browser packs](#the-browser-packs)): the name rule, every picture and cue in its home file, no level's data naming another chapter's assets, each level played 12 s by the bot asking only for the first download's and its own chapter's pictures and cues (and drawing no picture the art does not have), the export presets' lists (`fix` rewrites the chapters' models), the lighter copy when built (`lite` requires it: every picture opens, WebP or deflated; every cue in its file, a spoken line's Vorbis as long as its QOA, the rest the same bytes), the budgets; `build=<dir>` also reads an exported index.pck and every pack |
| `warm_check` | WARM CHECK OK | yes | the hitches the 3D view takes out of play ([view3d.md](view3d.md#the-warm-up-polish-pass-9)): a level's first frames draw every hidden piece (twister, storm wall, rain, seat views) as a speck and then put each back; the level's props, the events' hogs and raiders and its vehicles' seat views made at its first frame; every speck kind `game.burst` throws by name has its picture |
| `check_fixes` | PARITY FIXES OK | | the parity regression checks and the quick parts of many others (below), in six parts side by side |
| `physics_check` | PHYSICS OK | yes | gibs, brass, chunks and bodies dropped on decks, ramps and stairs and thrown at walls rest on a surface, never inside anything; the loose-things features on a loft ([gameplay.md](gameplay.md#loose-things-on-the-real-3d-shape-v300-remaster)); ragdolls lie on decks, treads, ramps and past a rail and sleep, no model sunk past 1 cm, one body on another, slow-mo finishers start on the last kill of a fight of three (not of two, pass 15) and never with company (`physics_ragdolls.gd`); loose things settle with no snap; nothing thrown fast passes a thin wall; water splashes, sinks and drifts (`physics_water.gd`); the beasts' ragdolls and the bosses' hand-over (`physics_beasts.gd`, pass 13); the shared physics core: the exact solver the same to the bit as the pins' old one, the grid, boxes stacking and waking what lies on them, a body on a wreck piece and a board on a body (`physics_core.gd`, [gameplay.md](gameplay.md#the-shared-physics-core-engine-pass-6)) |
| `live_props_check` | LIVE PROPS OK | yes | things taken up, held, thrown (a hand hurt and shoved, a propane tank breaking and going up, jugs spilling shine, a brute heaving a tank), set down and saved; fire spreading over hay, never onto stone or dirt, burning out, the same twice, sooner in rain; a still spraying and going up; a snapshot carrying a throw and a fire on tick for tick; all of it off with LIVE PROPS AND FIRE off ([gameplay.md](gameplay.md#picking-things-up-fire-that-spreads-the-stills)) |
| `brawl_check` | BRAWL OK | yes | the boot (slide, slam, domino, a door kicked in), smashes, a finisher of each gun class and every move, slow motion from the blow (alone only), co-op, each hazard kind (and a hand walking by), a hazard kill's bonus (pass 15: COUNTY JUSTICE!, the scrap with the bench live, his drop at the body, the hazard_killed event, the same on two runs, nothing with the bench off and NO DROPS), bosses never finished and only hurt by a hazard, two runs the same, a snapshot mid-slide played on the same ([gameplay.md](gameplay.md#dirty-fighting-content-pass-8)) |
| `punch_check` | PUNCH CHECK OK | yes | punchier hits (pass 15, [gameplay.md](gameplay.md#hits-that-land-hard-pass-15-punch)): the world's hold by closeness and weight (a far kill `kill_hold`, a heavy close kill `close_hold`, the sawed-off at arm's length `sawed_hold`, a heavy hit `hit_hold`, a light one none, never with two players), the close kill's view kick and none for a far one, the flinch floor, a ding for each head hit (none on the body, once a load) as a made cue, a head kill's splat marks, one barrel at arm's length takes the body apart (from three cells not), more and bigger chunks further over the overkill line and never past `gib_most`, no slow motion for a lone hand, the director's peak's end slowing `peak_length` (`print`: the numbers) |
| `live_body_check` | LIVE BODY OK | yes | the living bodies (pass 15, [gameplay.md](gameplay.md#living-bodies-pass-15-the-active-bodies-step-one)): play's stagger (a bigger push reels further with more catch steps, both barrels at arm's length are more than the steps catch, a leg hit's shorter steps, a hit on the run goes on forward, staggers stack, the same twice, no dice drawn, never into a wall, off the old jump); the looks' physics on a coot's rig (the same push at the chest, head, an arm and a leg four ways, the head snaps, a leg hit buckles that knee, catch steps for a hit and none for a tap, the hand on a chest wound, knocked down he drops and gets up, the muscles off a heap, on he is back in his pose and hands back, no link far off its length); play the same to the bit with live bodies stepped beside it (`print`: the numbers) |
| `active_body_check` | ACTIVE BODY OK | yes | the active bodies (pass 15 T11, [gameplay.md](gameplay.md#active-bodies-pass-15-t11-the-active-bodies-steps-two-and-three)): play's say (into the loft's rail hard he goes over and falls to the ground, gently he stays; a reel the steps cannot catch holds on to the rail in reach and in the open goes down; a boot's slam and a vehicle put him down; a drunk lurches and now and then goes down; the same twice, no dice; off, none of it); the looks on a coot's rig (the same shove at the hips, chest and head and a bigger one react four ways, higher tips further, hard he windmills; knocked over a hand reaches the floor first, the arms point where he lands, the head held off it, without the behaviours no hand goes down; a hand grabs the rail and is held there and lets go; feet step onto the stair treads; carried over the rail his legs catch and every ball goes over its top; a drunk's steps go wide both ways; a dying man goes slack over time, his muscles still working a second in, his arms holding at first, a hand down first as he falls, writhing then still, crawling a little, the muscles off a plain ragdoll); play the same to the bit with the bodies beside it (`print`: the numbers) |
| `danger_check` | DANGER CHECK OK | yes | reading danger (pass 15, [gameplay.md](gameplay.md#reading-danger-pass-15)): a blow from off the view draws one chevron on its side (white as it lands, then red, drawn at that edge only), a heavy one doubled, at most `arrows_most`, gone after `arrow_for`, none with no source, his own blast or a cloud right on him, one for a cloud's middle and the steam, on the picture's edge in ASPECT WIDE, slid clear of a touch button; the hurt banner names only what hit; DANGER ARROWS off: no arrows, the arc and the side as before, the setting on by default and reaching the game; a hand winding up behind: an amber arrow at the foot, one in the view none; the model's amber over the last `tell_share` only, flickering, under a hit's wash, never on a boss; a big wind-up's floor mark at its aim, none for a short one; a ranged gun's glint over the same share; the skull only when the boot's slide meets a hazard (not off the line, not past the slide, not with no one to kick) and drawn under the crosshair; the brackets for an awake hand in the sights only; booted where the skull said, he dies in the saw |
| `bar_door_check` | BAR DOOR CHECK OK | yes | the barred doors (pass 15's loops, [levels.md](levels.md#barred-doors-the-loops-pass-15)): the level file's sides read; each chapter's barred doors are the ones wanted (Hickston's rodeo back gate), hung in a wall with open floor both sides; from the wrong side the prompt says BARRED, USE leaves it shut and says so, a running boot, the bot and a hand leave it; a doors-open walk goes through it only from the bar's side; from there USE boots it open for good (nothing to close) and the way goes through both ways; every station, key and the exit is reached from the start with the bars shut; two runs the same |
| `stuck_check` | STUCK CHECK OK | no | the stuck spots pass 15's bots found ([gameplay.md](gameplay.md#stuck-spots-the-bots-found-pass-15)): a player on the bayou's lagoon bank inside a dock piling's square walks off every way and the ROOKIE bot from there reaches the exit; a player put against a corner of each chapter's small furniture walks out; every chapter played through by the SHARP bot (god mode): after each boss falls the pin's way reaches the player within 3 s, and the chapter is cleared (about 140 s) |
| `climb_check` | CLIMB CHECK OK | yes | every chapter has ladders, each joined foot to top in the nav graph; a ladder takes the player up and down, JUMP lets go; pull-ups onto a chest-high stack and from it onto a roof, not onto one too high; a hand comes up a ladder to the player on a lookout and drops off it to get at them below; a hand under fire ducks out of sight, peeks out, fires and goes back; a hand kicks a door open (not EASY or CLASSIC); the same run twice comes out the same |
| `vehicle_cab_check` | VEHICLE CAB OK | yes | the seat view: every kind's cab model, art and moving parts are there; the driver's eye gets the cab (not on foot, in PHOTO MODE or without a window: then the car's painted dash), its own model is left out, the wheel turns clockwise right with the hands on it, needles rise, the prop turns, the blade lever goes forward; drawn, it sits between the near plane and the nearest wall; SCREEN SHAKE and STILL stop what they should, the view widens at speed but never past a wider FIELD OF VIEW; spray lands in the view; the driving plate in every HUD mode and with touch; driving the same with the cab drawn ([gameplay.md](gameplay.md#vehicles)) |
| `moonshine_check` | MOONSHINE CHECK OK | no | the Moonshine Run (content pass 8): in the campaign between the speedway and the Mothership with its gate, pack, guns, rematch and trophy plinth; its stations and the barn doors; the MOONSHINE RUN driven from the barn through both roadblocks (every barricade rammed, the agents woken, in time, the tally); on foot past the barricades to the cave; the patrol cruisers drawn, flashing, running a man down and pulled over by the radio; an agent's radio call and the gas man's tear gas; the Revenue Man's burst, axe charge into the rock, shades, the still blowing and the roof coming down; a v8 campaign save at the Mothership and an old unlocks file ([levels.md](levels.md#the-moonshine-run-content-pass-8)) |
| `vehicle_set_check` | VEHICLE SET OK | no | finding the vehicles and what is built round them (feature pass 7): on each map with one, its KEYS IN IT sign by it, its lamps on (dark once burnt out), its radio heard near and not far, the automap's mark, USE's prompt from further off looked at (not away), the wider reach, its line said once; the bayou's CHANNEL RUN and the speedway's HEAT RACE driven to the end in time by a pilot (the hands they wake held back till then, the pin and objective on the next gate, the plate, the flare, the reward, the tally, a save), run out of time and needing another pass, the race only the lap cars' way and in their time; the car's window gun (one-handed only, not back through the cage, wilder, steering less, the cab's right hand off) and a partner riding shotgun who shoots and sees the cab from their seat ([gameplay.md](gameplay.md#vehicles)) |
| `gun_find_check` | GUN FIND OK | no | finding the guns (feature pass 7): in each chapter every gun new in campaign order within reach of the way through (route_map's legs) with no secret in front, a gun sign where the way is left for one further off and out of sight, a secret's gun teased by its rounds; every gun sign hung on something facing out; GunFinder's table of each chapter's guns the levels'; every gun lying out shines, is lit, is named looked at and not looked away from, goes on the automap once seen (NEW IRON in the key), is smelled once, and has none of it once had; a secret's gun gives nothing away; the tally's GUNS row; the trophy shack's board and card; none of it in County Run, the range or a versus map ([gameplay.md](gameplay.md#finding-the-guns-feature-pass-7)) |
| `pacing_check` | PACING OK | no | pacing (polish pass 9): each chapter's way through (route_map's legs) step by step, the longest run walked for the first time with no hand within 10 cells, no pickup within 3.5 and no station or sign within 5 at most 24 steps (the Moonshine Run's north blacktop was 31 before its pull-offs); each versus map as a DEATHMATCH arena has rounds and something to heal with (its plan's `arena_loot()`), every pickup walked to from the start, no spawn point more than 26 cells from one ([levels.md](levels.md#pacing-and-dressing-polish-pass-9)) |
| `rampage_check` | RAMPAGE CHECK OK | yes | the RAMPAGE meter (pass 15, [gameplay.md](gameplay.md#rampage-pass-15)): a kill of the player's own fills it by `kill`, one by another hand nothing; a head, an overkill, a boss, a brawl finisher and a hazard kill add their shares, a chain its links; it holds `hold` and then drains `drain` a second to nothing; full, RAMPAGE: hits `damage` times as hard (a hand's blow on a hand as ever), a second's run `speed` times as far, a kill adds `extend` up to `rampage_most`, then over with the meter empty and the boost gone; co-op each player his own and the local player left acting; on in County Run, off in deathmatch, team deathmatch, the 5v5, the hub and the range; a snapshot mid-RAMPAGE carries it and both games play on alike; a save through its JSON brings it back and it runs on, one with no block an empty meter; the balance bot with a meter near full goes on a RAMPAGE and plays the same twice |
| `move_check` | MOVE CHECK OK | yes | the walk and the quick hands (pass 15, [gameplay.md](gameplay.md#moves-pass-15)): on a range lane, scripted keys time the run to 90 % of its speed, the stop (time and cells), the air's side speed after a quarter second and a slide (speed, cells, seconds, against a crouch-walk), each in its band; a walk does not slide, letting go of CROUCH ends one, the next waits `slide_rest`, a jump hops out at more than the run, a wall stops it; `NetPredict.step` walks the same keys to the same place; KICK boots a man in front and at a shut door stood still is the boot, never USE's door (USE opens it); THROW tosses a stick from the .38 and the .38 comes back, no sticks nothing; a swap takes `switch_time`; FIRE stops a reload with rounds in, not one from empty; KICK and THROW through the net codec (PROTOCOL 6, dropped by `held_only`, kept by `merged`); a replay with them plays back exactly, and so does one written in format 1. `-- numbers` prints the feel numbers |
| `looks_check` | LOOKS CHECK OK | yes | the pass 15 LOOKS ([view3d.md](view3d.md#looks-that-read-pass-15)): every effects.cfg section and light it reads; an awake hostile hand wears the warm rim (stronger far off), asleep, held, dead or a player's stand-in none, the listed critters a cool one; a rim waking in sight fades in, one first seen whole; it is its own pass (actor_rim.gdshader, the parts' back faces swollen out: an outline, the body's shader untouched) hung on a part only with a rim and taken off without, off under a hit's wash and giving way to the wind-up's amber, with LIGHTS AND GLOW only; ENEMY RIM SOFT by default and reaching the view, OFF none, SOFT at most a pixel and dull, BOLD wider and brighter, both thinner far off, the edge tested behind the body; ammo, food and scrap glint (both frames, a short share of the time, each its own beat), keys, guns and the task item do not, EASY ON THE EYES rarer and STILL no bob, the star packed; a blow draws the vignette and it fades, low health drains the colour and holds it, the heart thumps under `heart_from` and quicker lower, none in the menus, with SCREEN FLASHES OFF or in PHOTO MODE's eye; a gunman's shot lights the yard a moment (the scattergun brighter), a melee hand's swing none, a volley still within MAX_LIGHTS; every gun in [casings] throws its own shells, drawn as its picture, the eight newer guns their own brass; smoke off the muzzle after a burst or a big gun's shot, not a lone round, ended by another shot, the gun down or its life, rising and thinning; none of it draws on game.rng |
| `music_check` | MUSIC CHECK OK | | the fight music in four levels (pass 15, [audio.md](audio.md#the-fight-music-in-four-levels-pass-15)): every chapter's loop has its pulse and peak layers, as long as it, played as one synchronized stream; the layers' gains jump to a level while the fight player is silent, the loop comes in over its `RISE` while the drums still play, PEAK is the loop and the riff, CALM leaves them be; one hand on the player BUILD, a blow or `CROWD` hands (fight_music.cfg) the FIGHT, held `HOLD` s after and then gone; a director's breather takes it out of the FIGHT within 4 s; a peak with a hand on him and a RAMPAGE are the PEAK; the Crossroads CALM; the REGULAR balance bot on Hickston and the Fair hears the whole loop under 60 % of the chapter, and BUILD and PEAK both |
| `director_check` | DIRECTOR CHECK OK | yes | the fight-rhythm director (pass 15, [gameplay.md](gameplay.md#fight-rhythm-pass-15)): in every chapter at NORMAL it holds hands back and never one a trigger wakes or waits on, a partner pair, the wave, a patrol, a boss, the tough guy, a hand whose id the level's file uses anywhere else, or one at the start; the REGULAR balance bot on Hickston and the Fair for 240 s meets a peak or more on Hickston and two or more on the Fair (pass 15 PUNCH re-set Hickston: its stagger moved this seed's second peak past 240 s), each a group of two or more and followed by a breather that runs its full `breather_for` with no hand sent, intensity in 0..1 (a peak's .7 or more) and `pace_changed` for every move; one seed plays to the same snapshot twice; a snapshot mid-peak put on another game carries the beats and both play on alike; a save mid-peak through its JSON brings back the beats and every hand (the extras too); a save with no director block holds nothing and a tin guard saved at 185 health comes back at its kind's 130; a save from a chapter's first moment plays with it; co-op runs it, a station brings a peak out of both players' sight and leaves the local player acting; off in deathmatch, team deathmatch, County Run, the hub, the range, a rematch, a chapter revisited and with `DirectorData.ON` false; drops by need (`src/drop_need.gd`): full shells and an empty .38 turn a shell drop into bullets, a roll past `need_share` keeps the kind's own, food under `need_health`, a boilerback's always-drop through `enemy_down` is bullets for an empty .38, County Run drops as before |
| `balance` | BALANCE OK | no | difficulty and pacing as numbers (polish pass 9, `tools/balance.gd -- check`, five rows `balance_1`..`_5`): a retried boss fight brings the `[boss_retry]` health and rounds; every boss fought in its rematch by the REGULAR balance bot at NORMAL (two seeds) falls inside its `BOSS_BANDS` seconds; every chapter played from its chapter kit by the SHARP bot at NORMAL is cleared within `CHAPTER_DEATHS` deaths and inside its `CHAPTER_BANDS` seconds, a death retried as the death screen does (`retry_death`). Play is exact, so a change that moves a band moved play: measure with the long report and set the band again, saying why ([gameplay.md](gameplay.md#difficulty-and-pacing-as-numbers-polish-pass-9)). Pass 15 set them all again (and `CHAPTER_DEATHS` 0: the SHARP bot dies nowhere at NORMAL now) |
| `bench_check` | BENCH CHECK OK | no | Mundell's junk bench (content pass 8): none with WORKBENCH off, in County Run, the range, a versus map or a deathmatch (mods count for nothing there); the Crossroads' bench and each chapter's by its start; scrap laid out, taken for its worth, dropped by a hand, a breakable, a wrecked vehicle and a set piece; buying at a bench only, never twice, without the gun or the scrap; each mod's change; every modded gun picture and the bench's pictures; saves (version 10, a version 9 save upgraded), kits and the hub's buys carried; co-op's own buys, lockstep and a snapshot copy. `-- audit` prints the scrap the campaign bot finds a chapter ([gameplay.md](gameplay.md#mundells-junk-bench-content-pass-8)) |
| `events_check` | EVENTS CHECK OK | no | the county events (content pass 8): EVENTS off casts no die, OFTEN always and SOMETIMES about half the chapters plan one, varied, no blackout off the night levels, none in the hub, range, Mothership, County Run or a versus match; the twister makes for a barn, pulls and knocks flat a player under the sky but not one under a roof, smashes a breakable, brings the barn down, flings a loose thing and lifts; the herd tramples a player and a hand, a blast kills a hog, the herd is gone; the raid's squad comes in unseen, counts, shoots it out with a hand, busts the still, ends when they are down; the blackout's dark, flashlight (key, Controls.item, battery, flat), the hands' sight in the dark and with the light, lanterns, the breaker and the power back in time; none in a boss fight and one cut short by one; the exit still reachable after each; saves mid-event; lockstep and a snapshot copy through each; the hogs' frames, the lantern, the cues, the settings row ([gameplay.md](gameplay.md#county-events-content-pass-8)) |
| `hound_check` | HOUND CHECK OK | no | BLUE the hound (content pass 8): heels and catches up, none where he is off, bays at a secret door and new iron, points at a hidden pickup, holds a hand (stunned, never killed by him, kicked at, finished by the player), a told SIC, never a boss, fetches to the player's feet, goes down and is got up (held USE, a rind, by himself), STAY and COME by key, replay op and controls, saved, co-op's two hounds, lockstep and a snapshot copy with him about, his art and badge; pass 10: every state's pose a frame of his model (gaits by pace, limp, tracking, idle wag, scratch, sniff, sit, lying, point, howl, lunge and bite, the hold's shake, yelp, going down, on his side, got up, getting up, the shake), no game.rng; the badge's job and mood words fit, the marker behind a wall and at the view's edge, the point's brackets, GETTIN' BLUE UP, the prompt naming the key; pass 10's ranging, stepping out of the sights, a hazard, backing off, a boss's aim, the free seat, the sulk, howl, cower, growl and still, his pant, shake and barks dealt at random; pass 15's LEAD: held still and no nearer the objective 30 s he takes the lead, within 3 s he is on the way ahead, stops down it out of the line of fire, points, the badge says LEADIN', Mundell says it once, the tip's words, a snapshot carries the job and both lead alike, his player come near he goes on, a hand awake near ends it, never with a fight on, back on the way ends it, co-op's two hounds each lead their own player, with HOUND DOG off the pin pulses and Mundell says the pin's line ([gameplay.md](gameplay.md#blue-shows-the-way-pass-15)) |
| `hound_pace` | HOUND PACE OK | no | BLUE calm and easy to look at (pass 12, run with `check`): a row a tick of him beside a scripted player walking, running, standing, looking round, stopping and going, turning back, a told SIC, a point, a car, co-op, on two chapters; each scene's turn rate (95th percentile under 330 degrees a second), his feet against the ground in each gait (at least .6, off his model's own keys), how much of the view and the crosshair, at rest no wandering or fidgeting; over the calm scenes the middle and worst share dashing past his player, sprints, acceleration, darts, off his facing, pose pops, nearest the eye and speed across the view (`BUDGETS`, `WORST`); `-- out=<dir>` the rows, `draw` (a window) the drawn feet ([gameplay.md](gameplay.md#calm-and-easy-to-look-at-pass-12)) |
| `hound_walk_check` | HOUND WALK OK | no | BLUE never stuck (pass 10): walks every chapter, the hub and the range with him, never stuck over 2 s, far over 8 s, seen jumping or in a hazard; a load far off, a ride in each vehicle, every chapter's start (`-- verbose`, `-- trace=`); his legs alone, with leading the way off (`HoundLead.ON`: a lead stands him at a stop on purpose) |
| `vehicle_check` | VEHICLES OK | yes | each vehicle (airboat, car, mower) is got into with USE, drives, strikes something and bounces off never inside a wall, runs a hand down and is got out of; the airboat keeps to water, the car's driver holds the .38 out of the window, a wreck throws its driver out, a rider rides along in co-op, a snapshot copy drives the same ([gameplay.md](gameplay.md#vehicles)) |
| `plank_check` | PLANK CHECK OK | yes | a barn's and a pen's wall at the fair, the sawmill's shed, a bayou shack and a gabled barn on County Run's Hickston: one may open, shot about it shows its boards out (a merged run cut at the cell), broken through it is floor to bodies, sight and both flow fields and walked through, a shed keeps its roof (and gable) over the gap, a pen's neighbours stand their own height, its planks rest on a floor, a snapshot and a save open it the same with the same walls ([gameplay.md](gameplay.md#walls-break-too)) |
| `set_piece_check` | SET PIECE CHECK OK | no | each chapter's set pieces stand; a barn with two posts shot out creaks, its hand runs, it comes down, hurts and pins the player under it and lies as cover; a wall panel shot about shows its boards out and shot through opens the way; the mower rammed into a post takes it out; dynamite in the hay brings the shed down; a water tower's two legs out on a side: it goes over that way, its tank bursts and floods the street, puts out the fire there and shoves a hand; a holed fuel line leaks gas its length, fire runs it and the propane at its end goes up; the same breaks twice match; a snapshot and a save carry it with its cover; with every set piece down every way it may fall every station, key and exit is still reached; idle costs next to nothing ([gameplay.md](gameplay.md#the-big-breaks-content-pass-8)) |
| `wall_looks_check` | WALL LOOKS CHECK OK | yes | plank walls (the fair): a round knocks out the plank it struck round where it struck, the next breaks it further, a light pellet only wears it, two cells struck in different places differ, buckshot tears several planks, a blast tears out those facing it, a hole goes with its plank, the view's rows decode as the shader reads them, a client makes the knocks up, play is the same without the looks, gone through it bursts along the shot; windows (Hickston): the crack web lies where the round struck, shot out it throws shards cut fresh (struck elsewhere: different), they break again landing into glints, a blast shows `_bst` and throws the frame; a pane's cut covers it, small near the hole; each material's hole its own picture and size ([gameplay.md](gameplay.md#how-walls-look-taking-a-beating-destruction-pass-11-walls)) |
| `wreck_motion_check` | WRECK MOTION OK | yes | how wreck pieces move (pass 11): a ring of staves left standing goes over, a hoop rolls on its rim and wobbles down flat, a can rolls, a lid spins down, glass skids short, a tin sheet flutters, a shot knocks a lying board at its hit point (spinning it by the side struck), a blast throws near pieces harder, a player, a hand and a vehicle kick pieces, one barrel shot on its left and its right comes apart differently (and the same twice alike), glass cracks, knock sounds stay under their cap, a heap rests with nothing inside anything ([gameplay.md](gameplay.md#how-the-pieces-move-pass-11)) |
| `blast_check` | BLAST CHECK OK | yes | every blast look throws what it should (its fire, lobes, column, scraps, dust ring, crater); what blew picks the look; four sticks in a row look four ways; water throws a column and no crater, the hay loft no crater, a wall throws the fire off it; a chain keeps each fireball under the cap; the stock car wrecked throws its own parts away from the blast, leaves a charring hulk and burns, hurt it smokes; play the same whatever the looks' dice ([gameplay.md](gameplay.md#blasts-and-wrecks-destruction-pass-11)) |
| `rumble_check` | RUMBLE CHECK OK | yes | controller rumble and phone buzz (pass 14), a recorder in place of Input's vibration calls: every gun in weapons.cfg has its own pulse and the pad gets its weak and strong, stopped as it runs out (the .38 cracks, the sawed-off thumps, a fast gun's pulse shorter than its fire time, both barrels harder, the rip saw's grind one held buzz); a melee blow on a man and on a wall, the dynamite's match and throw; a hurt from the right leans weak, from the left strong, heavy more than light; the boot on a man and into the air; a blast near more than far, none past its reach, none shown twice online; a hard landing by the drop, none for a hop; each vehicle's engine hums standing and harder moving, the car's wall struck, its wreck, the mower's cylinder; each boss moment, a quake (by the bigger), the caps; OFF none, LOW scaled, an idle pad still, the phone the strongest new pulse and none weak or where it cannot; only the local player; a menu, the focus lost, the down screen and quitting stop it; a run with RUMBLE FULL and OFF ends in the same state, rng and snapshot ([gameplay.md](gameplay.md#rumble-and-haptics-pass-14)) |
| `doppler_check` | DOPPLER CHECK OK | yes | Doppler on fast movers (pass 14, [audio.md](audio.md#doppler-pass-14)): doppler.cfg read, every flight loop it names made and every family it names tuned; a source passing 2 cells off at the stock car's top speed comes in high (+1.57) and goes away low (-1.44), the plain ratio far off, only falling from highest to lowest, at most `slew` a frame, clamped at 40 cells a second; standing still exactly 1, the listener running past a standing source bends too; a tied engine note keeps exactly its own spread x rate standing and is that x the Doppler moving, the same note through a wall (1300 Hz) by the same factor, a 0.3 s whistle not tied; a 20-cell jump of the mover and a teleported listener give no spike; OFF and a family's scale 0 exactly 1, a tied note its own pitch; in a game a bottle rocket past the player plays `fly_rocket` up then down and lets it go when gone, and driving the car its own engine bends under 0.15 semitone; a run with the movers' sounds every frame and one with neither end in the same state, rng and snapshot |
| `set_piece_check` | SET PIECE CHECK OK | no | each chapter's set pieces stand; a barn with two posts shot out creaks, its hand runs, it comes down, hurts and pins the player under it and lies as cover; a wall panel shot about shows its boards out and shot through opens the way; the mower rammed into a post takes it out; dynamite in the hay brings the shed down; a water tower's two legs out on a side: it goes over that way, its tank bursts and floods the street, puts out the fire there and shoves a hand; a holed fuel line leaks gas its length, fire runs it and the propane at its end goes up; the same breaks twice match; a snapshot and a save carry it with its cover; with every set piece down every way it may fall every station, key and exit is still reached; idle costs next to nothing; and how they come apart (looks): a barn in pieces of itself within its budget, its posts snapped, every piece on the ground or the pile, merged once still, the same fall the same and another fall (other posts, a blast, another time) otherwise, a save showing the pile; a tower's legs snapped, tank torn, hoops in bands on the ground, deck splintered ([gameplay.md](gameplay.md#the-big-breaks-content-pass-8)) |
| `wreck_check` | WRECK CHECK OK | yes | every kind of breakable with `pieces`, windows and fence cells on the chapters, a County Run map and the hub throw real pieces that all come to rest on a floor, never inside anything; none on the versus maps; the cap holds; a save put back throws nothing; asleep costs next to nothing ([gameplay.md](gameplay.md#in-real-pieces-of-themselves)) |
| `save_fixtures` | OLD SAVES OK | yes | saves from every earlier version still load |
| `level_edit_check` | LEVEL EDIT OK | yes | level editing keeps the walls right |
| `user_map_check` | USER MAP CHECK OK | yes | player maps: the examples, hostile files refused, the MAP SHED's calls, a map played alone, in a 5v5 round, County Run and deathmatch, its saves, sent to a lobby's joiner ([levels.md](levels.md#player-maps)) |
| `map_review_check` | MAP REVIEW CHECK OK | yes | map check and the design review (pass 16, T2, [levels.md](levels.md#map-check-pass-16)): six test maps built in memory, each with one fault planted (a lever nobody reaches, six hands with no rounds before them, an open lot with no cover, a hand that sees the start, a dead end with nothing in it, a 31-step quiet walk), each flagged with its code and the same map without it not; hickston, sawmill and grainyard as built have no MUST FIX; every line filled in, the verdicts, the auto tour of the demo map, the report, `map.gd`'s command table, paths from the repo root, the contact sheet, and the bot clearing the demo map the same twice |
| `map_share_check` | MAP SHARE OK | yes | sharing player maps (pass 16, [multiplayer.md](multiplayer.md#the-map-shelf-pass-16)): long codes and shelf codes round trip, mangled, cut, zip-bomb and newer-game codes refused; the MAP packet zstd'd past 4 KB and every bad size refused; THE MAP SHELF in process (put, list newest and most taken, a search, get, the counts once a house a day, a restart, the caps a day, an hour and a minute, a full shelf, every hostile put refused with nothing kept, the owner's remove.txt, a broken or tampered index); a lobby server on 127.0.0.1 over ENet and WebSocket (put, list, get; a protocol 6 knock and HELLO told to update; a message past 256 KB dropped unread); the shelf's map hosted in a player's lobby and sent to a joiner packed; CUSTOM MAPS' shelf, a pasted and a typed code, SHARE IT, by taps and keys |
| `geometry2_check` | GEOMETRY 2 CHECK OK | | geometry version 2 (pass 16, [levels.md](levels.md#geometry-version-2-pass-16-shapes)) on a level of its own: the version written only when used, the same level twice; terrain (the surface at its corners and between, every cell's ground under it, a cliff found), walked up and down a hill, held by a cliff and walked off it, the ridge stood on, a raked wall's low end in the way; the nav graph on the hill, round the cliff, a hand coming up the hill; sight over the crest, past the raked wall, a flat look; the mesh (the hill at every height, no floor under it, the cliff upright, the rakes); an eight-cut deck; a save on the hillside; broken terrain refused; a glTF gable and steep roof face imported and built (`write=<file>` writes its level for a window tour) |
| `kit_check` | KIT CHECK OK | | the map kit (pass 16 T5, [levels.md](levels.md#the-map-kit-pass-16-kit)): every piece at its smallest and largest size, 4 turns, mirrored and not, in a gallery level: the geometry reads, ids unique, each piece on its footprint and within its cost, the same parts twice (the hash); the nav graph from the yard in through every doorway and to every floor and roof meant to be reached, a body walking in through every doorway in two of the frames; the plain house and the farmhouse in detail (sight out of windows and not through walls, the gables, the stairs, the roof ladder, over the ridge, out of the balcony door onto the porch roof, the ridge and gable in the mesh); every refusal's line; `town=N` times the town stress_bench and cpu_check play; `write=<dir>` writes the galleries and a picture tour for `tools/map/map_pictures.gd` (folds in the audit's house_spike_check) |
| `quest_reach` | QUEST REACH OK | | every quest prop, gate and item can be used from where it is seen, and never through a wall (slow; `tour=<json>` for pictures of each prop) |
| `bot_campaign` | CAMPAIGN WALKTHROUGH OK | | the bot plays the campaign through (slow), each chapter on by THE CROSSROADS |
| `net_showdown_check` | NET SHOWDOWN OK | | online 5v5, host plus three clients, lobby to lobby (`lag= loss= seconds=`) |
| `net_server_check` | NET SERVER OK | | an always-open lobby with no host player; server/lobbies.json held to servers.json (one lobby on the party line server's ports, 60 snapshots a second, one match, it opens) |
| `menu_touch_check` | MENU TOUCH OK | yes | taps through every menu, the 5v5 store, the County Run screens as touch events; in play the junk bench's board (a tag bought, a tap off it), the USE button held (`Controls.hold`) and a tap skipping an opener ([ui.md](ui.md#touch-in-play-polish-pass-9)) |
| `touch_settings_check` | TOUCH SETTINGS OK | yes | SETTINGS by touch alone, as the engine delivers fingers (`Input.parse_input_event`, the project's mouse emulation): opened from the title, every page's tab and list drag, then every setting of `SessionStore.setup_pages()` (so a new setting is covered with no edit) picked and changed: a choice's arrow, a switch's name, a bar dragged end to end, a KEYS row (waits, a tap keeps the key), KEEP / UNDO, MOVE THEM and DONE; RESET PAGE, a second finger ignored, BACK. Once with a phone browser's finger (index 7340, the `pointermove` echo after each drag), once with Android's (0, no echo). Fails naming any setting a finger cannot change ([ui.md](ui.md#how-a-finger-reaches-a-menu-pass-14)) |
| `touch_screens_check` | TOUCH SCREENS OK | yes | the same fingers on the rest: each title screen and its BACK, CONTROLS on its TOUCH page, the MAP SHED (its plate, a quick stroke painting every cell, MAP NAME typed in as `WebTyping` types a browser's answer), JOIN WITH A CODE's field, LOAD / SAVE (SAVE, a slot, CANCEL, LOAD); in play every shown touch button does its job (held ones held), the stick, a turning drag; the death screen with a trail marker (a tap BACK TO THE MARKER, a tap on TAP HERE the chapter's start); a won chapter's card (the touch buttons step aside, a tap on its left half straight on, on THE CROSSROADS plate the Crossroads); no two buttons overlap on a phone held upright |
| `opener_check` | OPENER CHECK OK | yes | the chapter openers: every chapter's shots inside its map, card, tagline, boss cel and cues, the narrator's two lines STT-matched and in the bank; the OPENERS setting (FIRST TIME once, ALWAYS, OFF), never the hub, COUNTY RUN, a retry or a loaded save; a key or click skips it, it ends by itself, play's snapshot and clock unchanged in every chapter, two seconds of play after it the same as without; every opener draws its key moments; the sound: a bed of the chapter's own song from start to end and past it, played by the score player as the chapter's score, no gap over 0.5 s with nothing sounding in the mix plan, the bed never held to nothing and at play's level at the end, every line 6 dB over it, every cue in the bank and in its chapter's pack or the first download; played out the bed goes on at play's level, skipped the duck, sting and opener effects stop (`-- plan <file>` writes the mix plans) ([view3d.md](view3d.md#the-chapter-openers-content-pass-8)) |
| `opener_camera_check` | OPENER CAMERA OK | yes | every opener's camera sampled 60 times a second: never in or skimming a wall, roof, deck, door, prop or the ground (`OpenerCamera.clear_at`); between cuts turns under 45 deg/s, tilts under 30, speed under 8 cells/s, velocity continuous (changes under 12 cells/s^2), a lean of at most 2.3 degrees; it lands in the player's own eye with his picture out of the way (`-- report` prints each chapter's numbers) |
| `boss_end_check` | BOSS END OK | no | the boss endings (`src/boss_ending.gd`), every boss: felled in its rematch, the arena stood down (no hazard, no enemy shot, a hand near stunned), the ending started and run through the front end's frame to the result board in its band (5.1 to 5.8 s), its camera never in a wall, roof or the ground (`OpenerCamera.clear_at`) and keeping the boss in the shot, no HUD laid, the end sting still playing over the score's hand-back, the music as asked never silent over 0.5 s, the last word captioned, the board's time and ribbon; a key held off at first and a key a second in skipping to the board; in the campaign with two players it plays its length and hands back to play; the foreman's fall with and without it leaves the same game (play exact) |
| `bark_check` | BARK CHECK OK | no | the county's talk in play: the balance bot plays Hickston and the mill (4 minutes or to the end) with an ear that times every line on the game clock; the hands' barks come at 1.5 to 14 lines a minute, never the same line twice running, never one over another still playing (a boss's line or a tough guy's piece cuts in), Mundell sizes up the chapter, and a minute of it is the same game as with CHATTER OFF ([audio.md](audio.md#voices)) |
| `audio_flow_check` | AUDIO FLOW OK | no | Mundell's voice and the player's sounds through Hickston, the fair, the mill and the quarry in turn on the real Sound (3.13.1: the loops set looping on the stream their cues' one-shots share, which then held every effect voice for good): every cue Sound loops still plays once as an effect (`Assets.looped`), a looping take on an effect voice stops at `pause_world`, and in each chapter, with the bot playing and the fuse, ripsaw and burn-barrel loops heard beside their one-shots, Mundell's lines and the steps are heard, every effect voice comes free once its take has played out (the mixer kept on the game clock), and none is left after the level ends (`chapters= seconds= natural`) ([audio.md](audio.md#voices)) |
| `camera_check` | CAMERA CHECK OK | yes | the QUALITY tiers (pick, presets, AUTO's meter, physics steps); the HUD's Control boxes compose to `HUD.draw`'s bar pixel for pixel (campaign, 5v5, County Run, full and MINIMAL); PHOTO MODE in and out, flying, the player in view, a filter, a picture saved; the KILL CAM noted, sampled, replayed with stand-ins and skipped, never a boss's fall; play's snapshot unchanged by either; the view polish (`view_polish_check.gd`): SHADOWS' pairs and blobs, marks on a prop's model (holes, scorch, char, kept and handed on), the storm wall's curtains and ring |
| `frame_smooth` (`check`) | FRAME SMOOTH OK | yes | single player drawn between ticks (pass 14, `SoloBlend`, [view3d.md](view3d.md#drawn-between-ticks-single-player-pass-14)): Hickston walked through and turned among woken hands throwing bolts and firing, and a cluster of breakables blown with three hands shot down by it, each at 144 Hz through the front end's own frame (`advance`, `net_draw_begin`, `render`, `net_draw_end`) with a 3D view made by hand: the camera, its turn, the gun's sway, every hand's model, the shots, the wreck pieces, the ragdolls' bones and the casings each move on at least 97% of the drawn frames they are moving in (v3.11.0: 83%), the turn on every frame the mouse turned; the same frames with the blend off play to the same state hash and snapshot; the rules: a blended frame puts the game back to the bit, a share of 1 draws the tick as it stands, the view turns by all of the mouse not yet played and the next tick faces where that frame was drawn, a 4-cell jump and a seat taken are drawn where they land, PHOTO MODE and a FRAME LIMIT of 60 blend nothing |
| `hud_layout_check` | HUD LAYOUT OK | yes | the HUD's layout ([ui.md](ui.md#the-huds-layout)): crowded moments (campaign, SMALL TEXT, MINIMAL, a new player's tip over a notice and alone, driving with a run, the lap, co-op watching and reviving, a boss, versus, the fair, COUNTY RUN, 5v5) drawn headless with each piece's ink measured: no two touch, all inside the margins, each expected piece there; the layout's rules; the status bar's meter captions fit their wells; the notice and the tip draw over the hurt arc (and DANGER ARROWS' chevron) of a hit from in front (their pixels the same with and without it) |
| `wide_check` | WIDE CHECK OK | yes | ASPECT WIDE ([view3d.md](view3d.md#aspect-wide-pass-14)): the picture's columns for 16:9, 21:9, 32:9, a 19.5:9 phone, 8:5, 4:3 and upright screens, the picture placed at that shape with no bars to speak of (DOS 4:3 and SQUARE 8:5 as before); the 3D view that many columns wide in HIGH, HD and LOW at the same focal length, a point ahead and to either side drawn by the camera where the canvas (centred) draws it, to 0.01 of a pixel; HUD pieces hugging an edge keep it (`HudLayout.side_of`); the status bar's parts at the picture's edges with the planks between, and at 320 exactly the old boxes; the scope's mask the picture's width, its glass round (1.2 wide at DOS 4:3); a bar across the canvas spans the picture, a wide piece is left alone; the setting's WIDE choice, the default DOS 4:3 |
| `marker_check` | MARKER CHECK OK | no | the trail markers (pass 15, [gameplay.md](gameplay.md#trail-markers-pass-15)): taken on the clock, a key, a station and a new district, not before `gap_least`; not while hurt, in the air, on a ladder, a hand on top, a hostile shot or a fire near, beside an awake boss, a feature holding it back, a partner down (a long-due clock's taken with hands about); a death offers BACK TO THE MARKER (keys, pad and touch lines) and puts the save back exactly, the floor given, R the chapter's start; dead again straight after, the marker before it; a bot's 100 s the same with markers and on BOSSES ONLY; a marker loaded twice plays the same, a run from one plays back; co-op's own file, both players back; the state round trips a quicksave, an older save has none, a replay run's file apart; BOSSES ONLY takes none; the pin's way after a load uses the game's key ring, and a way that stopped short of the player is walked again (1.11); the root leaving the tree waits for a marker still being written (a write never waited for crashed the program on quit). `-- stall` also plays the 1.11 run (HARD, minutes) |
| `road_check` | ROAD CHECK OK | yes | between chapters and the end card (pass 15, [gameplay.md](gameplay.md#between-chapters-pass-15), [ui.md](ui.md#the-end-card-pass-15)): from a won chapter one ENTER (once the rows are down) starts the next chapter, kit carried, entry and unlocks written, the won chapter kept; a press in the moment of the win does nothing, one while the rows come down puts them down; the MAP key the Crossroads in front of the next gate (USE takes it), every gate with room; THE CROSSROADS setting swaps them; the bests (a first run, a slower run keeps them, a better one NEW BEST and the stamp, by difficulty, none with cheats or in co-op); TRY TO BEAT IT (a replay with the gate's kit, the campaign gone on, HIT THE ROAD after); the opener once, one key skips it; the card's layout at every row count and font, every chapter's card drawn. Runs only in a scratch profile (the guard above) |
| `onboard_check` | ONBOARD CHECK OK | no | a new player's first minutes (pass 12, [gameplay.md](gameplay.md#a-new-players-first-minutes-pass-12-onboard)): every one-time tip at its moment on Hickston, once, kept on the profile, nothing before its moment; none with NEW PLAYER TIPS off or in a tool's game; the right key (as bound), pad or touch button; the CONTROLS rows; the same game with tips on and off; the new player (`newbie_pilot.gd`, ROOKIE) from NEW GAME to the sheriff within 300 s on NORMAL, at most one death, the fire tip with the first fight, no tip twice (`quick`: without the walk) |
| `county_check` | COUNTY CHECK OK | | County Run rules; each map through a death and a retry |
| `county_net_check` | COUNTY NET CHECK OK | | a County Run party of two over ENet and WebSocket against a lobby server (`seconds=30`, as CI always ran it): two levels' XP handed inside the tick on every machine, the leader's two cards through the held world, no parting at all (`lag=120` over a laggy link, `clock=1`/`0` the playout by the clock or not) |
| `net_soak_all` | NET SOAK ALL OK | | every online mode soaked on the tool's own clock with lag, jitter and loss and the world broken on purpose ([multiplayer.md](multiplayer.md#soaking-every-mode-pass-12)); `quick`: County Run co-op for two minutes (its objects and memory flat over the second) and campaign co-op for 30 s, put back every 5 s |
| `net_party_check` | NET PARTY OK | | online CAMPAIGN CO-OP, DEATHMATCH and TEAM DEATHMATCH hosted by the real front end through a lobby server's party line: chapter to hub (the host's MAP key, player one at the next gate) to chapter, a chapter won straight into the next (the host's ENTER), the boss checkpoint's retry, downs, revives, watching, a trail marker gone back to by the host, late joins, leaving, THE PARTY SAVE, the kill feed, a deathmatch by bots (`only=coop` or `only=versus`) |
| `relay_check` | RELAY CHECK OK | | the party line in a lobby server: its limits, the lag it adds, a hosted 5v5 and a County Run with players through it over ENet and WebSocket (a fallback from the host's address, a late joiner straight in, a kick, the host gone), copies kept with the host (`quick` in check_all; `ping=<address>:<port>` times a line running elsewhere) |
| `games_check` | GAMES CHECK OK | yes | the range's board on a lobby server over ENet (posts, a name's best, refusals, asks, the County Run board beside it), the fair's shooting gallery (the bell, each target's points, a can flying and bouncing, the house paying, the prizes saved, no station or door added), the hub's trophy shack (statuettes by the gates open, cups, gnomes, its card), the range's duck row (a duck turned at the rail's end spins round on its stick) |
| `leak_check` | LEAK CHECK OK | yes | every game let go is freed: games made and disposed (campaign, co-op, deathmatch, County Run, range, Crossroads, a host's) and the front end's own flow (a chapter, the Crossroads, the range, a County Run, co-op, a deathmatch, back to the title) come back to the same object count round after round ([architecture.md](architecture.md#letting-a-game-go)) |
| `ai_check` | AI CHECK OK | yes | the tick's spike fixes and the enemies' level of detail: sight lines with the quick tests answer as step by step (nine maps, flat and at heights, furniture broken out), flow walks reach the same cells, cover's whole search finds the old spot (both HANDS settings) and in play stays within `cover_budget` spots a tick and ends where the whole search would, idle activities by cell, far calm enemies wait and near or engaged ones do not, a shot heard or a hit wakes one at once, `lod=false`, a snapshot mid-wait goes on the same ([gameplay.md](gameplay.md#speed-of-the-tick)) |
| `cpu_check` | CPU CHECK OK | yes | the frame's and the tick's CPU work (pass 10, PERFCPU): text_width kept by text answers as letter by letter (every style, SMALL TEXT CLEAR either way), the kept glyphs read-only, 20,000 measures under 40 yardsticks; polygons fill the old scanline pixels; a line's runs on the Godot canvas cover the Bresenham pixels once in fewer rectangles; a label's kept letters where the software's stand; the feature hook lists are the features with their own, in order; every live enemy asked its level of detail once a tick; the bot game's tick under 2 yardsticks and no feature's tick past 0.3; the bot in a fight in a town of geometry (pass 16) under 1.5 (a yardstick: a fixed piece of GDScript work timed in the same process, so a busy runner slows both alike; `report` prints the numbers) |
| `cover_check` | COVER CHECK OK | yes | the 5v5 maps' boarded cover: shot through (floor, sight, a shorter way), stood up again each round, kept by snapshots alone |
| `bot_check` | BOT CHECK OK | | the 5v5 bots' aim per BOT SKILL against a strafing target at 5, 12 and 20 cells (first hit, hit rate, kills inside 6 s within bounds; EASY slower than HARD; no laser up close), a target behind smoke never taken for a foe or shot at (and with the lane clear it is), ten-bot matches where they plant, carry and rescue a hostage and the team radio speaks, and a bomb planted with the outlaws down cut by the deputy bots on grainyard, salvage and pineacres (`bench` prints the before/after table: four skills, 4..22 cells, standing and strafing) |
| `replay_check` | REPLAY CHECK OK | | replays play back exactly (`replay_check.gd`, run `-- quick`): bots record chapter one from a fresh game, sawmill from the middle with its keys as actions and a cheat and a wound outside them, the quarry boss fight, County Run with card picks and co-op with two; each from its bytes onto a fresh game matches every hash and the whole end snapshot; a recording past its cap plays across its gap; a nudged game is caught within a hash; the front end's own recorder (advance, act, a setting changed mid-run), `replay save`, a death's file and the crash log keeping the session's replay. Prints the recording's cost a tick. Without quick, twice as long |
| `load_check` | LOAD CHECK OK | | the faster level load hands play what the slow way gave, on every level: the nav graph node for node and edge for edge in the same order, the grids, walls and plane bounds number for number (against `tools/load_reference.gd`, the old code kept); the open floor kept for a level played again as measured, untouched by what a game did with its own; the wreck pieces cut on a worker while a level's first frames run the same piece for piece as cut at once ([gameplay.md](gameplay.md#loading-a-level)) |
| `load_speed_check` | LOAD SPEED OK | | pass 10's load speed ([view3d.md](view3d.md#loading-and-the-warm-up-pass-10-perfload)): every kind's baked ragdoll rig the rig found from its model (`tools/rig_reference.gd`, the old build): whole numbers to the bit, measures to 1e-4 m and hulls as shapes (each segment's reach along every fine way), since CI's Linux rounds the vertex sums a hair differently than Windows (3.14: alien, chalk_spitter, chum_tosser, nitro_huffer); a stale one names `tools/art/bake_rigs.gd`; the packed made cues (`made_cues.bin`) the samples made at once; the title's warm-up draws every view3d shader but the sky's and takes its pieces away; the eight chapters loaded headless find no rig from vertices, leave no model with the loader, keep no model's looks as pixels, stay within their start and first-frame budgets, and loaded again stay within the memory ceiling and grow it under 40 MB (`-- report` prints each chapter) |
| `prebake_check` | PREBAKE CHECK OK | | the pack-time bakes ([levels.md](levels.md#the-bakes-pass-14)): every level with geometry reads its nav graph from its bake and it is the graph built with the bakes off, node for node, edge for edge and in order; every key a level's breakables cut is read from the bake (parts() and a level's pump()) piece for piece and float for float, with the same fracture origin and variant count; a scratch copy with the level file's MD5, the tile list's, the format, the scripts' or a source's changed, or a file missing (a chapter's cuts file not fetched yet too), is not read and the level builds as before; a level a tool hands in and the player's example maps are never baked. Fails on a missing or stale bake: run `pack_assets.gd -- bake` |
| `tune_check` | TUNE CHECK OK | yes | the dev console's tuning and overlays (`dev_tune.gd`, `dev_overlays.gd`): `tune set` takes in a running game (a gun's fire time, an enemy kind's health on the one in play and a new one, static values from modes.cfg, hits.cfg and difficulty.cfg, a whole number keeping a float's type), `tune get` reads it, a change is a replay keyframe, online it is refused, `tune reload` puts the files' values back and says each change (a second says none); `tune save`'s rewrite on bosses.cfg's text (a key, a multi-line value, a new key and section; every other value, comment and line ending kept) and on a copy of weapons.cfg, read back; the watch reads a saved copy again; every overlay on over a bot's fight drawn headless (traces, tick and listener times come in, the picture changes), the run recorded with them on plays back exactly without them, and turned off the `ticked` listeners are as before, in order. Prints the static values watched and what a reload of every file costs |
| `net_errors_check` | NET ERRORS OK | yes | what a player is told when joining goes wrong: another version or protocol (both versions named), a full lobby, nobody at the address (COULD NOT REACH THE HOST), a host that never answers the HELLO (THE HOST NEVER ANSWERED, pass 9: it waited for ever); a client that lost the host lands on the JOIN form with ENTER TO TRY AGAIN and gets back in; a refusal or a closed lobby goes to the title |
| `update_flow_check` | UPDATE FLOW OK | yes | the in-game Android update ([ui.md](ui.md#the-in-game-android-update-pass-14)) against its own HTTP server on 127.0.0.1 (a 302 to an asset store that answers Range with 206) and a stand-in for the Android plugin: update.json read and refused (other version, bad hash or size, garbage); the files' names and `tidy`; the download whole, cut off and picked up with a Range, a server ignoring the Range, a mangled copy failing SHA-256, a missing file, HOLD IT and on again, nobody answering; the stages through GIT IT to the system's prompt, the "install unknown apps" switch off and on, a no, no answer, the installer not opening, no room (nothing fetched), mangled once and twice, a game going, no update.json, CHECK FOR UPDATES off mid-download (nothing more asked), an APK from an earlier run, the updated game's first run tidying; the panel's words fit in every stage |
| `update_check` | UPDATE CHECK OK | yes | the update notice (pass 14, [ui.md](ui.md#the-update-notice-pass-14)) without the network: versions compared as numbers (3.10 after 3.9, equal, older, pre-releases, garbage), the sign only for a newer version (not on an error page, offline, a timeout, too long an answer, nor with CHECK FOR UPDATES off), the APK on Android and the installer on Windows, the rules on when to ask (never the browser, headless, a tool, a tour or a bench), a tool's game makes no request; the title's sign by keys, ENTER and a click, clear of the board; the Android preset's package name and version code; the preset a Gradle build with compressed native code, the updater addon on, its manifest part (REQUEST_INSTALL_PACKAGES, the plugin's class) and the Java's method and signal names matching `ApkInstaller` |
| `voice_chat_check` | VOICE CHAT OK | | online voice chat with a made-up voice (no mic, no sound card): the codec's SNR and bytes, PUSH TO TALK and OPEN MIC's gate, the jitter buffer (order, wrap, a lost frame covered, a late one dropped, catching up); where a voice is heard from (left and right, past the radius, through a wall); a lobby server with 40 ms, jitter and 5% loss and one player on WebSocket: in the lobby all hear, flat, never their own; in a match only within the radius, placed; muted and VOICE CHAT off are sent nothing; the dead hear the living near their team and only the dead hear the dead; the copies' snapshots and partings the same with everyone talking; a player's own lobby through the party line. Pass 14's CLEAR 16K (`tools/voice_measure.gd`): two voiced lines from `audio_src` through CB 8K and CLEAR 16K, each band's codec SNR and the speech band's spectral SNR against the source (CLEAR nearer by 2 dB, the 3.4 to 7 kHz band by 4), the bytes a second, a CLEAR frame cut to 163 bytes a CB frame; a line's trouble putting it on CB 8K a while; in the lobby who sends and gets CLEAR (an older listener, a CB 8K talker and listener, an older lobby, three talking past `clear_heard_most`, the lobby's budget, a line in trouble). `bench` times a 5v5 of ten talkers on CB 8K and then CLEAR 16K at 60 snapshots a second (`snaps=2`: 30); `bench server=` talks on a server elsewhere beside `net_pace` |
| `predict_check` | PREDICT CHECK OK | yes | an online client's own shots, reloads and pickups shown at the press and put right by the host's word (`net_shot_predict.gd`), with no network: a range deathmatch as the copy, a hand-filled `NetSync.Client` as its link, each input played 12 ticks on. A shot played (one bang, kick and tracer, rounds down at the press and never back up, its mark and tick once), refused (rounds back, mark and blood withdrawn), out of rounds (one dry click), a hit judged a miss (mark and blood withdrawn), a gun taken up and fired at once, a pickup played and one refused (back in the picture), a reload pressed mid-burst with the trigger held (every cue, tracer and shell counted as often as a copy without prediction), a stick of dynamite lit and thrown (and one the host never lit: struck once, the stick back), the crowbar's blow on player two before the copy plays it, USE's boot in co-op; pass 13 (`predict_check_kills.gd`): a sure kill drawn dead from the press and never up again (one fall moment through the copy's own kill), a killing hit on a hand free to walk reeling till the copy kills it, a refused sure kill taken back, a finisher (its move the copy's, the swing at the press, the man down at the blow, its sound once), a sure break (broken and its pieces thrown at the press, never whole again, its sound once), each also with its looks off; and nothing on a game nobody watches |
| `net_lag` | NET LAG OK | | what a player feels online (`net_lag.gd`, run `-- quick`: a 120 ms link, limits on rubber band, missed hits, stalls, lost inputs, bandwidth); without quick, three links and the full table (`oldserver`: the 3.9.0 server's side, `snaps=1`: 60 snapshots a second, `p12`: pass 12's playout, `rewind=N`, `allbases`; it prints the longest rewind asked and the ticks cut to `MAX_REWIND`) |
| `net_feel` | NET FEEL OK | | how smooth an online client looks frame by frame (`net_feel.gd`, run `-- quick`: the 5v5 at 120 ms on a 144 Hz screen at 30 and at 60 snapshots a second (the others drawn at most `QUICK_BEHIND` behind the host, and sooner at 60), a client drawn by main.gd's own calls; limits on the view's and the others' frozen frames and jerk, the turn held against the mouse, snaps, no parting); without quick, every scene (5v5, deathmatch, co-op as a client and as the host, County Run co-op; `kit`: press to screen for the scope, a bolt's and a stick's blast, USE on a door, a hand's flinch; pass 13: a sure kill, a kill on a walking hand, a finisher, a crate broken) at 50/120/250 ms against single-player ([multiplayer.md](multiplayer.md#frame-by-frame-pass-12-net_feelgd)) |
| `net_pace` | NET PACE OK | | how evenly a lobby server's snapshots go out (pass 12): on a made-up clock a stall is caught up with one snapshot a room and a 2 s stall let go, a whole snapshot carries its rows, a split one's first part gives its rows, the host's input buffer fills before playing on; on the real clock two lobbies in matches with extra work each tick, no snapshot bunched, gap p99 under 45 ms (server) and 50 (a probe), arrivals' wander p95 under 20 ms, nothing over the MTU. `server=<address:port>` measures a lobby server in another process instead ([multiplayer.md](multiplayer.md#pacing-packets-and-the-one-core-server-pass-12)) |

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
`map_check` (map sources, MAP_AUTHORING.md), `leak_check`, and polish pass
9's `save_numbers` (saves round-tripped through JSON mid-ride, mid-raid and
mid-blackout: a vehicle's seats and the event's hand lists come back whole
numbers) and `polish_bugs` (a twister lifting past the map's edge, a save with
a hand running from a barn creaking down, co-op's twister and hogs shoving
player two, the blackout's key words).

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
| `net_soak` | NET SOAK OK | an always-open lobby server soaked on the real clock: `people` probes (2 to 4) join, a match by TacticalBots, a probe hangs `stall` seconds, the last leaves and joins again, the admin leaves (the lobby passes on) and joins again; drops, partings, put-backs, round trips, bandwidth and memory (`server=<address:port>` a real one, knocked first and left alone if anyone is in; without it a lobby of this build in the process; `grew=1` lists what grew in each game between samples) |
| `mode_check` | MODE CHECK OK | co-op, deathmatch (`-- seconds=90` plays longer) |
| `tactical_check` | TACTICAL CHECK OK | the 5v5 modes, ten bots, every map (`rounds=3`, `rules=shotguns`, `verbose`, `deaths=`) |
| `wall_break_check` | | every level's breakable cells opened at once |
| `boss_rematch_check` | | the rematch rules; `-- bot` times the bot on every boss (PAR) |
| `bench.gd` | SPEED OK | frame time, CPU side (`-- 150`; CI runs `120 max=60` and only catches a big slowdown) |
| `rampage_frames.gd` | | pictures of the RAMPAGE meter filling, the RAMPAGE as it flares, burning and guttering, and the meter and burn in ASPECT WIDE and with the touch buttons up (a window: `--audio-driver Dummy --resolution 1280x800 --script res://tools/rampage_frames.gd -- out=<dir>`, scratch APPDATA) |
| `looks_frames.gd` | | pictures of the pass 15 LOOKS: awake hands' rim near and far by day and the same asleep, the critters, the ridge's hands by night; pickups glinting over ten moments; the hurt vignette at 60, 30 and 15 health (and 15 a beat later, 30 in ASPECT WIDE, 25 under a RAMPAGE); hands firing in the dark (the ridge by night, a blackout); the newer guns' brass in the air and on the ground; the smoke off the tommy gun's, shotgun's and Hogleg's muzzle. It uses only what the game had before, so the same run on an older build makes the before pictures (a window: `--audio-driver Dummy --resolution 1280x800 --script res://tools/looks_frames.gd -- out=<dir> [only=rim,glint,hurt,muzzle,casings,smoke]`, scratch APPDATA and LOCALAPPDATA) |
| `flow_report.gd` | FLOW RUN DONE | not a check but the yardstick of pass 15 for every play change: the balance bot plays the campaign (`-- run skill= seed= [diff=] [chapters=] [director=0] out=`) and `-- report in=<dir>` prints, per chapter, the fight and walk shares, the fights and the quiet between them, how many alerted hands at once (and the 3+ share), damage from out of view, melee and dry seconds, the fight music's share and each of its four levels' (pass 15) with the RAMPAGES and seconds on one, what each death cost, time to kill by kind, the director's beats, a line per skill against the pass's targets, and (T9) lost episodes, backtracking and BLUE leading; `lead=0` plays with BLUE never leading. Run it before and after on the chapters a change touched (REGULAR, SHARP and ROOKIE at NORMAL, seeds 1-2: about six minutes a campaign; three at once is fine). [gameplay.md](gameplay.md#fight-rhythm-pass-15) has the pass 15 tables |

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
| a branch push | none, but a push to `android-check` builds the APK (whatever the checks say), to prove it before a tag |
| `main` | the browser builds (`pack_lite.gd`, `Web`, `Web Lite`, the chapter packs, `pack_check.gd -- quick lite build=`), deployed with the landing page to Pages |
| a `v*` tag | the EXE (smoke-tested on Windows), the installer, the APK (below), then the GitHub release with the three files and `update.json` (the version, each file's size and SHA-256: what the in-game Android update checks against) |
| Run workflow (by hand) | input `builds` (on by default): all four as run artifacts; on `main` it deploys the site, on a tag it releases |

**The APK** (job `android`) is a Gradle build: Java 17, sdkmanager's
`platform-tools`, `build-tools;36.1.0` and `platforms;android-36` (the 4.7.2
template's), Gradle's downloads cached, `pack_lite.gd`, the updater's AAR
(`tools/android_plugin.gd`, ANDROID PLUGIN BUILT), then `--install-android-build-template
--export-release "Android"` (fails on `export ... failed`, BUILD FAILED or
the AAR missing). It is signed with the lasting `ANDROID_KEYSTORE_*` key
when those secrets are set; without them (so far: the owner's call on
2026-11-24) a tag still publishes, signed with a throwaway key and a warning
saying so. The package step checks the package name, a version code not
under 3.11.0's, warns of a throwaway key on a tag, and checks the manifest:
REQUEST_INSTALL_PACKAGES, the plugin entry and class, the FileProvider and
VIBRATE, and the plugin's class in the dex; it writes the APK's size and
SHA-256 to the run's summary.

**A passed commit is not checked twice.** On a push to `main` or a `v*` tag
the job `earlier` asks the API for a passed run of this workflow on the same
commit (the branch's, which `tools/release.gd` waits for before it moves main
and tags). If there is one, lint, checks and window are skipped and the
builds start at once; if not (a push to main by hand, or the API failing),
everything runs and the builds wait for it as on a branch. Either way
nothing builds or publishes on a commit whose checks did not pass.

**Caches** (`.github/actions/godot`): the Godot editor and, for the build
jobs only, the export templates (fixed keys); the asset packs (keyed on the
art, sound and `pack_assets.gd`; the levels' bakes are not in it: the set-up
makes them after its import every run, `pack_assets.gd -- bake`, about 4 s); the import cache `godot/.godot` (keyed on
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
`tools/pictures_3d/` (the tour's viewpoints include one from each vehicle's
seat: a viewpoint's `seat` puts the player at the wheel of the level's ride
first, `angle` then off its heading; `bayou_seat_0`, `bayou_seat_back_0`,
`speedway_seat_0`, `hickston_seat_0`): the tour writes `<tag>_fx.png` (lights and glows on, as
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

- **Contrast floors.** A viewpoint with `contrast` (the ridge by night,
  `moonshine_night_field_0` 6.5 and `moonshine_night_yard_0` 8.5, and the
  blackout's `hickston_blackout_0` 5.2) is drawn again without its `actors`
  (`<tag>_bare_fx.png`, `<tag>_bare_3d.png`); `compare_3d.gd` takes the pixels
  that differ in the 3D pictures as the cast and fails (TOO DARK) when the
  cast's mean |dL*| against what it hides in the finished frame
  (`tools/night_contrast.gd`) is under the floor. With the moon's rim off they
  read 5.3, 7.7 and 4.1; on, 7.4, 9.4 and 6.3. `update` never copies the bare
  pictures.
- **A view tour always draws with the default settings**, never the
  profile's (the owner's own copy shares it): a lowered gun or the film look
  in a local reference fails CI's Mesa window, which has none.
- Changing how text draws changes every reference (a tour, then `update`).
- **After a model changes, refresh every view it shows in, not only those
  over the limit here.** CI's Mesa adds 1-2% of its own on the `_fx`
  pictures (lights and glows), so a reference left 2-3% off by a remade
  model passes here and fails CI (3.14: `wide_hickston_photo_fx`,
  `sawmill_fight_5_16_fx`, `hickston_windup_0_fx`, `hickston_fight_9_16_fx`
  at 3.2-4.6% on CI, 1.9-2.8% here). The tour is deterministic run to run
  here (two runs 102 of 102 identical), so print each picture's share and
  refresh the views whose difference is the new look, both modes.
- An actor's `state` may be `windup` (pass 15: `left` of his kind's wind-up
  to go, at the player, its floor mark `mark` cells ahead):
  `hickston_windup_0` holds the amber wind-up, the glint at a raised gun
  hand and a big wind-up's floor mark (made alone: a tour of a scratch file
  holding just that viewpoint, then `update` on its folder).
- A tour viewpoint may set `map`/`map_zoom`, `gun`/`fire`/`ticks`, `rain`,
  `wet`, `lightning`, `actors`, `cels` and `motion` (EASY ON THE EYES); and
  (pass 14) `screen` [w, h] (the window that shape with ASPECT WIDE), `scope`
  (the gun's scope up), `photo` [back, up] (PHOTO MODE, its camera that far
  from the eye), `menu` (a front-end state's screen, `page` its settings
  page), each put back after the viewpoint; (pass 15) `health` (the
  player's, for the hurt looks: it stays for the viewpoints after, so the
  one using it comes last or after a fresh load, `unlock`).
- **The looks pictures** (pass 15, [view3d.md](view3d.md#looks-that-read-pass-15)):
  `looks_rim_0` (Hickston's street, three awake hands at 3, 7.5 and 15
  cells: the warm rim, the far one a warm figure), `looks_critters_0` (a
  cow, a pig and a chicken: the cool rim) and `looks_hurt_18_0` (18 health:
  the drain toward sepia and the held vignette). The rim moved none of the
  older pictures past `MOST_OFF` (the night casts read better: the ridge's
  field 7.9 to 9.0 L*, the yard 9.7 to 10.2, the blackout 5.6 to 6.1).
- **The wide pictures** (pass 14): `wide_*` viewpoints at 16:9 (712x400, 356
  columns: Hickston with a notice, the fair's fight, the scope, the automap,
  PHOTO MODE, the DISPLAY page), a 19.5:9 phone (868x400, 434 columns: the
  airboat's seat) and `wide32_speedway_oval_0` at 32:9 (712x200, 712
  columns). Windows no bigger than CI's 1280x800 screen. `compare_3d.gd`
  takes a window that is not 8:5 as WIDE's (`PictureShape`) and holds it at
  its own columns by 200.
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
- In a window: `-- --view-bench=300` (the title's warm-up first, `TITLE`;
  each chapter: its load, `start()` and the first frame, then the frame, its
  parts, and the 3D view's own parts, `WorldView3D.parts_us`); `--play-bench=<seconds>`
  has the bot play each chapter and prints the slowest frames with the tick's
  and the draw's share; `first_minutes.gd -- whole hitches` times every tick
  of a bot's playthrough.
- **The worst moments**, in a window: `tools/stress_bench.gd -- [only=a,b]
  [frames=240]` builds idle (hickston, a reference), strike (a bowling
  strike), wreck48 (48 wreck pieces flying), fire (hickston's hay burning),
  chain6 (six blasts nine ticks apart in hickston's yard), arena (Maw's third phase, the arena coming apart), fivev5 (ten bots in a
  grainyard round) and county (County Run at 12 minutes, the storm closing,
  38 hands) and prints each one's frame median, p99 and max, tick and render
  means, the view's parts, what is on screen, the model parts drawn (and
  those with instance uniforms, and the props and models parked out of
  view) and the memory (static, textures, buffers, video); `shots=<dir>`
  saves each scene's last window picture. Give it a scratch `APPDATA` with
  an options.json to pick a QUALITY tier. `check` runs headless (in
  check_all, above).
- **The first-time hitches**, in a window: `tools/hitch_bench.gd -- [only=a,b]
  [frames=90]` times the frame something is drawn or made for the first time
  and the big moments that come once: turn (a 180 at Hickston's spawn), the
  twister, rain, a wreck, getting in the mower (cab), a barn and the water
  tower coming down, the hogs' stampede, a finisher. Each prints the first
  frame, the worst, p99 and median, and the first frame's tick, render and
  view parts over 2 ms. Give each run a new empty scratch `APPDATA` (a cold
  shader cache, as the browser always has).
- **The worst ticks:** `tools/tick_spikes.gd -- [level=hickston] [players=1] [ticks=7200] [runs=3] [top=20]` plays net_bench's bot game `runs` times (play is exact: the same tick does the same work), keeps each tick at its least (the PC's own hiccups left out) and prints the worst ticks with their costliest features and event listeners (the rest is "core"), then what the ticks over three times the median spent past the usual by part.
- **The tick, by listener:** `tools/tick_profile.gd -- 300 [levels=a,b]`
  times each feature's tick (`tick_with`, sleeping ones skipped) and the
  rest ("core": bodies, enemies, shots), idle and in a fight, per chapter;
  `plain` times the whole tick only (the timers cost a little themselves),
  the number to hold old against new.
- **Loading:** `tools/load_bench.gd -- [rounds=3] [levels=a,b]`: per level
  the game made the first time (cold: nav graph and wreck caches empty) and
  again (warm), the 3D level mesh's whole build, the wreck cutting alone
  (since the load pass not part of the load: it runs on a worker in the
  level's first frames).

### Measured in pass 16, SHAPES (2026-11-27)

The geometry engine for heavy maps ([levels.md](levels.md#geometry-version-2-pass-16-shapes)),
on the audit's town (then `house_spike_check.gd`, now `kit_check.gd town_level`: 36 two- and
three-storey houses, 744 slabs, 2,125 segments, 40 hands) against the same
level flat, the base (pass16 at a513a48b, the spike merged) and this back to
back on a quiet machine, three runs each:

| | base | pass 16 | target |
| --- | --- | --- | --- |
| first nav graph (`FlowField.new`, no bake) | 1,801-1,827 ms | 166-175 ms | 300 |
| 4,000 looks at .95 against the level flat | 287-289 ms, 9.1-9.2 times | 71-72 ms, 2.25 times | 2.5 times |
| level parse plus 3D mesh | 206-212 ms | 142-148 ms | 150 |
| wall rows (the gables' strips become 576 rakes) | 25,488 | 10,904 | 12,000 |

The same graphs (load_check: 13 baked graphs and 20 open floors as the
reference; the town's graph hashes the same) and the same answers (36,000
looks with and without heights on every level with geometry and the town,
the same as the base). The town in a window (`stress_bench only=town`): frame
median 2.20 ms, p99 3.38, tick mean .79; its headless tick 1.35 yardsticks
(budget 3). `cpu_check`'s fight there: .72 yardsticks (budget 1.5).

Nothing else moved, base against this, two rounds each in a 1280x800
window: stress_bench frame medians idle 2.41/2.43 -> 2.42/2.41 ms, wreck48
7.06/7.25 -> 7.20/7.08, fivev5 3.39/3.38 -> 3.39/3.38, county 8.53/8.71 ->
8.68/8.63; `cpu_check` tick .880/.884 -> .878/.882 ms; `load_speed_check`'s
chapter starts 725/732 -> 725/727 ms, first frames 1,141/1,140 -> 1,138/1,134
ms (after `pack_assets.gd -- bake`: the nav scripts changed, so the bakes'
key did); `stress_bench -- check hash` the same on idle, wreck48, arena,
fivev5 and county; compare_3d: 118 pictures unchanged.

### Measured in pass 15, PERF (2026-11-25)

v3.12.1 (`dac2ca57`), the pass 15 tip before PERF (`ea8d19c6`) and PERF,
back to back, alternating, three rounds (the PC shared with two other
tracks' runs; medians of the rounds), `stress_bench.gd` in a window
(1280x800, scratch `APPDATA`), frame median / p99 in ms:

| Scene | v3.12.1 | tip | PERF | PERF vs v3.12.1 | the view's actors part |
| --- | --- | --- | --- | --- | --- |
| idle | 2.65 / 4.30 | 2.82 / 4.87 | 2.70 / 4.17 | +1.9% | .01 / .01 / .01 |
| strike | 3.71 / 5.72 | 3.59 / 5.20 | 3.56 / 5.57 | -4.0% | .01 / .01 / .01 |
| wreck48 | 9.42 / 16.88 | 8.86 / 17.03 | 8.51 / 15.46 | -9.7% | .01 / .01 / .01 |
| fire | 3.58 / 6.08 | 3.51 / 5.87 | 3.67 / 6.28 | +2.5% | .01 / .01 / .01 |
| chain6 | 5.06 / 10.04 | 5.16 / 10.20 | 5.22 / 9.56 | +3.2% | .01 / .01 / .01 |
| arena | 3.36 / 4.70 | 3.38 / 4.93 | 3.25 / 4.78 | -3.3% | .12 / .14 / .13 |
| fivev5 | 3.74 / 5.52 | 3.89 / 6.46 | 3.84 / 5.99 | +2.7% | .06 / .09 / .08 |
| county | 9.37 / 17.58 | 10.77 / 18.28 | 10.58 / 17.80 | +12.9% | 1.19 / 2.52 / 2.34 |

**county is not the scene it was.** Pass 15 changed play (the director,
lighter sponges, the bot's run), so the County Run bot at 12 minutes stands
somewhere else: over the timed frames the view shows 31.9 models on average
(v3.12.1 26.8), 10.2 dead bodies (7.5) of which 2.1 are still moving (0.4),
and 252 sprites at the end (94). The play hash of every scene is the same on
the tip and PERF (`stress_bench -- check hash`). With the live and dying
bodies turned off on the same scene the frame is about .45 ms less; the
rest of the gap is the scene's own models and bodies. PERF took the doll
steps 13-25% cheaper (the same sums, below) and the actors part from 2.52 to
2.34 ms.

`--view-bench=300`, the eight chapters' frame medians summed, three rounds:
v3.12.1 25.02 ms, tip 25.28 (+1.0%), PERF 25.20 (+0.7%); the graphics
card's 26.13, 26.42, 26.35.

`--play-bench=30` (the bot plays each chapter; play changed in pass 15, so
these are other runs too), the chapters' medians summed, three rounds:
v3.12.1 28.67 ms, tip 30.02 (+4.7%), PERF 30.31 (+5.7%; a moonshine and
mothership run alone, three rounds each, put PERF and the tip level: 3.67
and 3.83 against 3.69 and 3.82). The tip crashed on quit every time (a
marker's write left on a worker), PERF never. `tick_spikes.gd` (hickston's
bot game): median v3.12.1 .913 ms, tip .965 to 1.018, PERF .944 to 1.014;
by listener the tip's tick spends +173 us a tick more in wreckage (the bot
breaks more; wreckage's code is unchanged), +37 in gun_fx (the hands'
muzzle check, now about half), +11 breakables, +7 the hound, +6 the fight
music, +4 the director, and 62 less in the core.

What PERF changed, all with the very same results (a scratch bench stepped
ragdolls, dying dolls, live and active bodies near county_hickston's walls
and hashed every ball and every bone posed: the same on the tip and PERF;
the window picture tour byte for byte the same):

- `Ragdoll.step`: the floor done for every ball in one call
  (`_floor_balls`; a beast's own `_floor` still asked ball by ball), the
  legs' joints a constant, `_walls` asks no rail where the geometry's grid
  says nothing is near and no rail twice, `_on_bodies`/`_on_boxes` read the
  other body's balls and the wreck piece's middle once.
- `LiveBody.live_step`: each group's stiffness worked out once a step
  (`_st`), the clutch and limp arm once a pass.
- `RagdollRig`: the rest pose's sums kept (each segment's start and end,
  each rest frame turned back, each bone's size).
- `ActorView._shade` compares fields, not an array made every frame.
- `MuzzleLooks.tick_hands` asks the reach first (most hands are far off).

### Measured in pass 14, WIDE (2026-11-24)

`--view-bench=300`, the eight chapters' frame medians summed, three runs
each, back to back on the noisy desktop (medians of the runs):

| | frames | the graphics card's time |
| --- | --- | --- |
| v3.11.0 (`p14_base`), 1280x800, DOS 4:3 | 26.89 ms | 28.39 ms |
| pass 14 WIDE track, 1280x800, DOS 4:3 | 27.11 (+0.8%) | 28.71 (+1.1%) |
| WIDE track, 1280x720, DOS 4:3 (320 columns) | 26.92 | 28.51 |
| WIDE track, 1280x720, WIDE (356 columns) | 27.42 (+1.9%) | 28.78 (+0.9%) |

Run by run the default moved +1.0, -2.6 and +0.8% (noise). WIDE at 16:9
draws 11% more of the view's pixels; the frame costs about 2% more.

### Measured in pass 13, HEAVY (2026-11-19)

v3.10.0 (`5cdc8d74`) against the HEAVY branch, back to back, alternating,
three pairs (the PC shared with four other tracks' runs: the first pair ran
busy, the medians of the three are given), `stress_bench.gd` in a window
(1280x800, scratch `APPDATA`), frame median / p99 in ms. Play and the wreck
pieces are exact: `stress_bench -- check hash` prints the same on both, the
picture references did not move (94 of 94).

| Scene | v3.10.0 | pass 13 | median x | p99 x |
| --- | --- | --- | --- | --- |
| idle | 2.91 / 5.57 | 2.78 / 6.56 | 1.05 | 0.85 |
| strike | 3.81 / 6.22 | 3.81 / 6.95 | 1.00 | 0.89 |
| wreck48 | 9.66 / 21.58 | 8.73 / 17.28 | 1.11 | 1.25 |
| fire | 4.03 / 9.04 | 3.82 / 8.59 | 1.06 | 1.05 |
| chain6 | 5.38 / 11.20 | 4.92 / 11.64 | 1.09 | 0.96 |
| arena | 3.19 / 8.40 | 3.16 / 4.84 | 1.01 | 1.74 |
| fivev5 | 3.59 / 5.29 | 3.59 / 4.95 | 1.00 | 1.07 |
| county | 7.96 / 13.76 | 7.57 / 13.91 | 1.05 | 0.99 |

(The p99s of the light scenes wander by 10 to 70 % from run to run on this
PC; their medians are within 1 %.) `set_piece_frames.gd -- bench` (the CPU's
share, the window is vsync-paced), the orchard shed coming down, median
4.29, 4.22 -> 4.11, 3.60 ms; the town tower 3.67, 3.37 -> 3.42, 3.27.
`tick_profile.gd -- 300 plain`, all chapters: 0.771, 0.747 -> 0.754,
0.737 ms. Headless (`wreck_bench`'s scene with a hash of every piece each
tick, the same both ways): wreckage's tick 2.7 -> 2.2 ms in wreck48 (-20 %),
2.3 -> 2.0 in every; County Run's sight lines, 2,849 recorded and replayed,
20 to 30 % less a line.

Where the time goes (the frame's parts, `-d --profiling` in a window and
`WorldView3D.parts_us`): wreck48 is the wreck physics (2.5 ms a tick: the
contacts' solve, each piece's points against the level, the pairs), the
breakables' bits tumbling, the view's sprite and slab rows, the wreck layer
and the listing of 350 sprites; fire is the burning pallet's pieces settling
(0.5 ms a tick) on top of a level's ordinary frame; County Run is the hands'
thinking (sight lines, walking), their AnimationPlayer seeks and ragdolls
(1 ms of the view) and 160 ground marks. Most of it is spread over many
small costs: no single part of the three is over 15 % of its frame but the
wreck physics. What did not help, or was left: inlining the contacts' solve
into its loop (a field read from outside the contact costs what the call
saved); a render thread (`--render-thread separate` is the engine's
experimental mode: it warns, and is not for a release); trimming the actors'
constant animation tracks (Blender's export leaves almost none exactly
constant: 124 of 8,396); caching way_out across ticks or within one (no
point is asked twice in a tick, and the level's furniture has no version to
key on); a cheaper skeleton pose (the seeks are the engine's own).

### Measured in pass 11, the big breaks coming apart (COLLAPSE, 2026-11-18)

v3.8.0 (`deffaa87`) against the COLLAPSE branch, back to back, three pairs,
medians (the PC was shared with the other tracks' runs; the cleanest round).
`hitch_bench.gd -- only=barn,tower frames=240` (vsync off, a fresh scratch
`APPDATA` each run): the 4 s from the strike that brings Hickston's barn or
water tower down.

| What | v3.8.0 | pass 11 |
| --- | --- | --- |
| barn: median / p99 / worst frame | 3.72 / 10.34 / 12.97 ms | 4.30 / 11.23 / 13.66 ms |
| tower: median / p99 / worst frame | 3.48 / 11.87 / 15.61 ms | 3.79 / 8.08 / 16.62 ms |

Headless, the tick and the set pieces' and wreckage's `sprites()` over the six
seconds after each of the seven set pieces is brought down (three pairs):
tick median 0.48 to 0.56 ms, sprites 0.025 to 0.077 ms, worst tick the same
(about 12 ms, play's own landing work). The worst frame stays within +10 %;
the median while a barn comes down is about +0.5 ms (+15 %), for those
seconds only, spent on the pieces drawn on their own as they land, the dust
and the splinters (the cut, which was a 33 ms spike when done at once, runs
on a worker in the creak; a part's riding pieces are one mesh until they go;
merges run on a worker). Once it lies still the ruin is a few merged meshes,
as before.

### Measured in pass 10, the 3D view's draw (PERFGPU, 2026-11-17)

Desktop, 1280x800 window, scratch `APPDATA`, v3.7.0 (`4972aec9`) against
the PERFGPU branch alone (pass 10's BLUE and openers in, the other speed
tracks not), six pairs run back to back alternating, medians of the six;
the PC was busy (other tracks' runs), so single rows wander by 10%.
The view's own work (`WorldView3D.parts_us`, all parts) fell about 2.2
times; the whole frame, mostly the tick and the HUD and gun stage outside
the view, by the factors below. The graphics card's time stayed 0.1 to
0.4 ms a frame (35 draw calls, 50 to 60 objects in the 3D view).

| What | v3.7.0 | PERFGPU | x |
| --- | --- | --- | --- |
| `--view-bench`, 8 chapters, frame median (geometric mean of the speed-ups) | | | 1.19 |
| the same, p99 | | | 1.25 |
| `--view-bench` LOW, frame median / p99 | | | 1.18 / 1.22 |
| the view's parts, hickston HIGH / bayou HIGH / hickston LOW | 2.46 / 1.94 / 2.40 ms | 1.09 / 0.70 / 0.98 ms | 2.3 / 2.8 / 2.4 |
| stress_bench, 7 scenes, frame median / p99 / max | | | 1.16 / 1.21 / 1.17 |
| stress wreck48 frame median / p99 | 12.43 / 23.38 ms | 9.42 / 17.27 ms | 1.32 / 1.35 |
| stress county frame median / p99, the view's parts | 10.23 / 21.27, 2.95 ms | 9.16 / 16.23, 2.25 ms | 1.12 / 1.31, 1.31 |
| the view's `frame()` turning round Hickston headless (median) | 1.7 ms | 0.8 ms | 2.1 |

Still the view's: posing many bodies close by (County Run late: 0.3 to
0.5 ms of AnimationPlayer seeks, 0.2 ms of ragdolls), the sprites' and
slabs' rows (0.1 to 0.6 ms with hundreds of bits about), the engine's own
frame (about 0.5 ms, little of it the view's draw).

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

### Measured in pass 10, PERFCPU (2026-11-18)

v3.7.0 (`4972aec9`) against the PERFCPU branch with pass 10 merged in
(`e1a006d5`: the new BLUE, the openers, PERFGPU's view, the boss endings),
back to back, three pairs, medians (the PC busy with other tracks). "Our
CPU" is the frame's parts outside the 3D view: tick + sprites + weapon (the
HUD's layout, the features' drawing and the gun) + hud.

| What | v3.7.0 | pass 10 + PERFCPU |
| --- | --- | --- |
| `--view-bench=300` default, frame mean, 8 chapters (geomean) | 1x | 1.61x faster (hickston 8.06 -> 6.00, moonshine 7.73 -> 4.01 ms) |
| ... the same at LOW | 1x | 1.86x faster |
| ... our CPU per frame (geomean, default / LOW) | 1x | 1.80x / 2.08x (weapon part 1.5-3.4 -> 0.5-0.7 ms) |
| `--view-bench=300` against pass 10 before PERFCPU (`945a9993`), frame / our CPU, two pairs | 1x | 1.66x / 2.39x |
| `bench.gd -- 150` tick / draw (software HUD) | 0.85 / 4.97 ms | 0.82 / 2.64 ms |
| `tick_spikes` hickston, bayou, mothership, 1 and 2 players, median tick (geomean) | 1x | 1.03x (1.05-1.17x on five; mothership with two players 0.76x, from the merged work: against `e1a006d5` alone PERFCPU is 5% faster there) |

The window's weapon part held the HUD's layout, which measured its words
letter by letter, parsing each letter's hex every time: kept by text now
(with the labels' letters, the plates' polygon spans, the lines' runs and
the per-frame feature hooks). The tick is many small costs spread over
120-odd features and every enemy; what came off it (about 8% against
pass 10's own start) is the level of detail on the enemies' own fields,
the walking test on locals and loops asking the cheap thing first; pass
10's BLUE and the hands' barks add their own (the barks under 3 us a tick;
`cpu_check -- report` names the costliest feature, BLUE at 70-90 us).

**The worst moments (rounds 2 and 3, `tools/stress_bench.gd` in a window,
v3.7.0 against pass 10 `5ac86ac5` plus round 3, three pairs, medians; the
render column is before PERFGPU's work on these scenes):**

| Scene | frame median v3.7.0 -> now | p99 | tick (ms) | render (ms) |
| --- | --- | --- | --- | --- |
| idle | 3.21 -> 2.59 (1.24x) | 1.25x | 0.55 -> 0.52 | 1.95 -> 1.48 |
| strike | 5.99 -> 3.98 (1.51x) | 1.58x | 1.66 -> 1.46 | 2.99 -> 1.21 |
| wreck48 | 9.44 -> 6.80 (1.39x) | 1.44x | 4.14 -> 3.01 | 4.11 -> 3.07 |
| fire | 4.01 -> 3.31 (1.21x) | 1.08x | 1.15 -> 1.10 | 2.35 -> 1.86 |
| arena | 4.29 -> 3.27 (1.31x) | 1.29x | 0.82 -> 0.80 | 2.90 -> 2.02 |
| fivev5 | 5.28 -> 3.54 (1.49x) | 1.60x | 3.04 -> 2.04 | 1.32 -> 0.85 |
| county | 9.37 -> 7.57 (1.24x) | 1.36x | 2.51 -> 2.26 | 4.93 -> 3.51 |

Round 3: `PhysCore.way_out` (a stuck wreck piece's corner probed eighty
times, most of them in vain, where the breakables' furniture still lists
in the cell) works out a probe's answer once for each cell and set of the
cell's furniture holding it: at the point's one height that is all
`_in_something` reads there (a cell with geometry, a door, a pane near or a
gate is still asked probe by probe); an open cell with nothing listed now
(`PhysCore.empty_cell`: broken furniture leaves index_cells marked) answers
its floor and solid() from its ground; the pairs ask the reach first.
Round 2's tick work, all exact (`stress_bench -- check hash` prints the
same on the old and new builds for every scene): the panes indexed by row
(`LevelData.pane_at` asked every pane on every blocked() of a level with
glass) and LevelSight's quick tests on levels with glass outside the cells a
pane can meet (`pane_cells`): the 5v5's sight lines and bodies; the sight
loop on locals; the wreck pieces' and pins' solvers on the contacts' own
fields (`Contact.prepare`, `solve_once`, `solve_exact`, the same sums in the
same order); `PhysCore.way_out` passing wall cells itself; blocked() asking a
point's one cell once; `use_target` passing devices farther than any of
their aim points. What is left: idle, fire, arena and county are held by the
render and the frame's wait more than the tick; wreck48's tick is the wreck
pieces' contacts against the level (`way_out`'s probes into furniture, the
floors) and against each other; County Run's is its 38 hands' own thinking
and sight lines. `stress_bench -- check` holds each scene's tick to a budget
in yardsticks (`TICK_YARDS`).

Remaining worst cases: County Run late (12 to 14 ms a frame on this desktop:
33 rigged hands posed every frame, 1.4 to 1.7 ms of AnimationPlayer seeks);
the first visit to a chapter (0.35 to 0.57 s headless: the nav graph, 0.2 to
0.3 s, and the wreck cutting, up to 0.29 s on the Mothership); the web pack
(below). Not measured: a phone, the browser build's frame times, the APK.

**Export sizes** (2026-11-16): Windows EXE 302.6 MB (the 109 MB engine and a
193 MB pack: `assets_gen` 140 MB of which art 76 MB, sfx 13 MB and music
63 MB; the models' imported scenes 39.5 MB), unchanged by the browser work
below. Art is deflated per picture, the sound is QOA, the model scenes are
uncompressed meshes (mesh compression would change how they look).

- Network: `tools/net_bench.gd -- levels=hickston players=1,2,4 [host]`.
- **The browser:** export both builds, serve each with COOP/COEP headers, add
  a page whose `GODOT_CONFIG` args are `["--", "--view-bench=300"]`, and run
  headless Chrome with its own `--user-data-dir` and
  `--disable-frame-rate-limit --disable-gpu-vsync` (otherwise it caps at
  about 240 fps, as vsync would); the numbers are in its console log
  (`--enable-logging=stderr`).
- Close browser tabs and preview servers after testing: the owner has heard
  game audio from tabs left open.

### Measured in pass 10 (PERFLOAD)

Desktop (RTX 5070 Ti laptop, 1280x800 window, a fresh profile each run, the
PC busy with the other tracks), v3.7.0 (`4972aec9`) against `eng10-perfload`,
back to back, medians of three pairs; the browser in headless Chrome
(SwiftShader), two pairs. Every number is in the track's report.

| What | v3.7.0 | pass 10 |
| --- | --- | --- |
| a level's load in a window, start() + first frame, the 11 levels summed | 7.06 s | 4.86 s (1.45x) |
| ... Hickston, the first level of a session | 2.06 s | 1.13 s |
| `load_bench.gd` view's first frame, 16 levels (new: `view`) | 6.08 s | 3.58 s (1.70x) |
| `load_bench.gd` cold / warm / mesh / cuts, 16 levels | 1.92 / 0.85 / 0.68 / 1.50 s | 1.87 / 0.82 / 0.68 / 1.42 s (the same) |
| `hitch_bench.gd` worst frame over the settled median: cab / hogs / turn | 18.6 / 21.7 / 7.0 ms | 5.6 / 8.6 / 4.7 ms |
| ... the worst frame of all the moments | 27.7 ms | 13.4 ms |
| static memory after ten levels (window) | 506 MB | 387 MB |
| browser: the first level's load (start to its first frame) | 12.1 s | 1.0 to 1.3 s, after the title's warm-up (10.5 s under the title) |
| browser: the other seven chapters' loads summed | 4.3, 4.5 s | 4.1, 3.4 s |
| browser, CPU slowed 4x: Hickston's load | 19.6 s | 3.1 s (after 12.9 s under the title) |
| browser: the title up (from the page's start; 4x slower CPU) | 4.9 s (13.3 s) | 4.7 s (13.6 to 16.2 s) |
| browser `--view-bench=60`, all chapters | 15.0, 16.9 ms | 19.2, 15.0 ms (the same within the noise) |

Not faster: the boot (4.5 s of the project folder's start, 1.5 s of the
browser build's, is GDScript compiling every script with main.gd, one at a
time: threaded loads did not run any of it at once), Game.new (the level
read, the nav graph, the features: spread thin, no part over 15 ms), the
level's mesh and the wreck cutting.

### The browser packs

What a browser downloads, gzipped as GitHub Pages sends it (measured on the
exported builds, 2026-11-16, pass 7):

| | before | after |
| --- | --- | --- |
| first visit (wasm, index.pck, js): the title and Hickston | 133.9 MB | 77.2 MB |
| ... and Hickston's music | 143.5 MB | 83.5 MB |
| everything, all seven chapter packs | 206.6 MB | 178.3 MB |
| Web Lite first visit (iPhone, iPad) | 133.9 MB | 77.1 MB |
| APK (estimated from its pack, against the 221 MB 3.4.0 APK) | 221 MB | about 192 MB |

Polish pass 9 (2026-11-17, `b483fdc9` against the web track, the exported
Web build, gzipped at level 6 as Pages sends it):

| | before | after |
| --- | --- | --- |
| first download's packed files (pack_check, the lighter copy) | 86.5 MB | 71.8 MB |
| index.pck as exported | 90.8 MB | 76.0 MB |
| first visit (wasm, index.pck, js), gzipped | 90.2 MB | 76.6 MB |
| ... and Hickston's music | 96.6 MB | 82.9 MB |
| everything, all eight chapter packs, gzipped | 204.1 MB | 181.1 MB |
| headless Chrome, 20 Mbit/s and the CPU slowed 4x: index.pck in / the title up (two runs) | 56.6, 56.2 / 105.7, 86.6 s | 50.4, 50.2 / 83.3, 81.2 s |
| headless Chrome `--view-bench=60` (SwiftShader, CPU not slowed): all chapters, two runs | 26.8, 24.5 ms | 28.9, 25.5 ms |

The frame times are the same within the noise (the PC was busy; SwiftShader
draws on the CPU); the load is quicker by the bytes.

- **The split.** `index.pck` holds the title, Hickston, the hub, the range
  and the versus maps. Each other chapter's own files are a pack of their
  own (`tools/make_packs.gd`, `chapter_<id>-<hash>.pck`, 13 to 18 MB):
  its music, its enemies' pictures, baked looks, sounds and models, and the
  props only its levels show. What is a chapter's is decided by name
  (`Assets.chapter_of`: a chapter enemy's kind, `<kind>_...`,
  `actor3d_<kind>...`, `boss_<kind>_...`; one rule for art, cues and models,
  so new sound such as voice lines finds its pack by its name) and, for the
  props, by the levels' data (`tools/prop_homes.gd`: shown only by one
  chapter's levels and named by no script or tuning file). Anything else
  stays in the first download, so a new asset is safe by default.
- **Streaming.** `src/pack_loader.gd` fetches the packs after the title is
  up, in chapter order, the chapter asked for first; keeps them in the
  browser's storage (named by hash, so a changed pack is fetched again);
  mounts each and registers its models' ids. A chapter started before its
  pack is here waits on the menu with a line of its own (`ROAD_LINES`, with
  how far it has come) and starts when it lands; its enemies are drawn as
  their sprites and its props as their pictures until then (`kind_ready`,
  `art_ready`). Packs are read 4 MB a frame.
- **The lighter copy.** The browser and phone builds read
  `assets_gen/lite` (`tools/pack_lite.gd`, needs ffmpeg): the 18 model
  textures over 512 texels a side halved (the bosses and the seat views; at
  the 320x200 view a boss looks the same: 276 pixels of a 1280x800 frame
  moved), the music re-encoded at Vorbis q3 (about 100 kbps, two thirds of
  the bytes, the same samples). Since pass 9 every picture is kept as
  lossless WebP where that is smaller (4,537 of 5,158: the art 76.2 -> 59.5
  MB, the very same pixels, and no slower to open than the deflated ones),
  and the sound bank has a lighter copy too (`lite/sfx*.bin`,
  `lite/sfx_index.json`): the 814 spoken lines (the audio manifest's
  "voice" family) as mono Ogg Vorbis q1 (about 40 kbps against the QOA's
  70) with their stream headers kept once at the front of `sfx.bin` (the
  same for every line, 3.4 KB each: `Assets.cue` puts them back), the rest
  the QOA it was (22.3 -> 14.7 MB). A line opens in about 0.2 ms on this
  desktop. The desktop builds leave the lighter copy out and never read it;
  `--lite-assets` reads it on a desktop to look and listen.
- **Ambience by chapter.** The beds only one chapter plays
  (`Assets.CHAPTER_AMBIENCE`: amb_fair..., amb_mill..., amb_quarry...,
  amb_bayou..., amb_ridge, amb_mothership) come with that chapter's pack.
- **The check.** `tools/pack_check.gd` (above); CI's browser job runs it on
  the export with `lite build=build/web`. Budgets: the first download's
  packed files 75 MB (71.8 at pass 9; 87 before it), a chapter pack 20 MB
  (16.4).
- **Not cut:** the sound effects other than the spoken lines stay QOA (short
  cues, loops that must meet their start); the models' imported scenes
  (about 23 MB of the first download: mesh compression or fewer LODs would
  change how they look); the engine's wasm (10 MB gzipped) is the stock
  template.
- **Trying it:** export Web, `make_packs.gd -- <dir>`, serve the folder with
  COOP/COEP headers and open `index.html` with `GODOT_CONFIG` args
  `["--", "--play-at=fair"]`: the menu says `TOWING THE FAIRGROUNDS IN...`
  and the fair starts when its pack lands. The built-in browser pane runs a
  hidden tab at a frame or two a second and did not finish a pack in a
  minute, old build or new; use a headless Chrome (`--headless=new --mute-audio --enable-unsafe-swiftshader`).
