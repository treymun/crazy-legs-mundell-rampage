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
- Rows in `ALONE` (`net_lag`: its limits are on online timing) run last,
  with nothing beside them.
- check_all reads the children's output every 10 ms: a child whose output
  pipe is full waits until it is read, and at the old 100 ms net_lag's
  timing came out differently (13% of hits judged misses, over its 12%
  limit, where a plain run has 8%) and every check ran slower.

| Check | Passes with | In quick | What it holds |
| --- | --- | --- | --- |
| `check_shader` | SHADER OK | yes | texture counts: `display.gdshader` at most 9 (incl. TEXTURE), each view3d shader with its includes at most 10 |
| `view_perf_check` | VIEW PERF CHECK OK | yes | the 3D view's frame stays cheap (pass 10): a line of HUD text draws with one texture a style (the canvas's letter pages); its global uniforms match `project.godot` and the shaders, no view3d shader keeps a uniform array, no frame number goes to a material; two to four turns round Hickston's spawn with its hands awake make no prop or model again after the first, nothing past where it shows gets a model, no view3d shader has instance uniforms and the parts with them stay in WebGL's room with margin; `frame()`'s lower quartile under 1.5 times a yardstick of plain GDScript |
| `stress_bench` (`check`) | STRESS CHECK OK | no | the busy scenes (wreck48, arena, county) built headless with a 3D view made by hand: every frame's model parts with instance uniforms under WebGL's room (60) less 20, and the global uniforms and their blocks under its 1024 slots with the same margin (none since pass 10: each part has its own material); each scene's tick under its budget in yardsticks (`TICK_YARDS`, a fixed piece of GDScript work timed in the same process); `hash` prints each frame's play as hashes, the same on two builds that play the same |
| `view3d_check` | VIEW3D CHECK OK | yes | every level's 3D mesh builds headless; every prop and actor scene loads (a station's with both looks, every quest picture modelled); every slab (pickups, loose things, range targets) builds at its picture's size; no fallen body's part stays up at `down` (fit.json `down_high` for the cow's raised legs); the hanging lamp is the shop_lamp model and a tipped cow rolls on her hooves (`ActorView.tipped`) |
| `actor_check` | ACTOR CHECK OK | yes | the actors' models (polish pass 9): every actors.json kind's glb, scene and looks (square, a power of two), keys numbered once each, bone labels, canvas; fit.json names only models and numbers ActorModels reads; every kind has the frames the game asks for (walk with its closing `w4`, fall, hurt set, a boss's recover, a critter's -1/0/1); texels a metre over each body and head at least `TEXEL_MIN`/`HEAD_MIN` (`report` prints them), the hound's at least `HOUND_MIN`/`HOUND_HEAD_MIN`; the hound's fourteen motions and ten poses (pass 10), each motion's keys in a row, played on the gait, a one-shot ending on its last key, his own fit.json blend, and his drawn size (shoulder .33-.41 and head top .41-.52 of Mundell's drawn height, measured on his skinned model); ActorView's looks-only motion: pose blends, no blend between walk beats, hit flinches by zone with their own dice and still after `FLINCH`, idle breath, mirrored scripted falls (never a boss), game.rng untouched; specks between `View.SPECK_PX_MIN` and `SPECK_PX_MAX` pixels; a partner on the riding mower shows Mundell's `sit` ([view3d.md](view3d.md#actors)) |
| `verify_assets` | ASSETS OK | yes | assets and levels load; chapter-only kinds really are one chapter's; pending music noted |
| `radio_check` | RADIO CHECK OK | yes | the county radio: every line of `radio_lines.json` in the bank with a caption of two lines at most, a gap between songs opens with an ID and ends on the way back, news first (a boss's fall before the rest), lines dealt without coming round soon, the scanner's calls and their spacing, three deaths make news, CUSSIN'/CLEAN/OFF for Dub's crude lines, the RADIO setting, a boss fight holds it and a boss's line hushes it, anyone talking ducks it and Dub over the music ducks the music, a vehicle tuned in, a chapter's events reach the station and its lines are captioned, game.rng untouched ([audio.md](audio.md#the-county-radio-content-pass-8)) |
| `audio_qa_check` | AUDIO QA OK | yes | the sound's wiring and finish (pass 9): every cue the game names in a literal is made, every finished cue starts and ends at silence and every loop runs into its start, every CLEAN copy within 2 dB of its cussing take, play's hold on the music stacks with Dub's and a jukebox's and goes with play, no hand says a line twice running; the full measurement is `scripts/audio_qa.py --check` (lint) ([audio.md](audio.md#audio-qa-pass-9)) |
| `voice_check` | VOICE CHECK OK | yes | every spoken line in the audio manifest is mastered from its transcript, has its CLEAN copy (cuss lines) and loads from the packed bank at 0.3 to 6 s; every caption the game shows for a line (bosses, hands, tough guys, Maw, the fair PA, Mundell, the cuss pack, the county radio) is the text it was made from; every recording, transcript and kept take is booked in the ledger, which adds up to the account's drop ([audio.md](audio.md#voices)) |
| `pack_check` | PACK CHECK OK | | the browser build's split ([the browser packs](#the-browser-packs)): the name rule, every picture and cue in its home file, no level's data naming another chapter's assets, each level played 12 s by the bot asking only for the first download's and its own chapter's pictures and cues (and drawing no picture the art does not have), the export presets' lists (`fix` rewrites the chapters' models), the lighter copy when built (`lite` requires it: every picture opens, WebP or deflated; every cue in its file, a spoken line's Vorbis as long as its QOA, the rest the same bytes), the budgets; `build=<dir>` also reads an exported index.pck and every pack |
| `warm_check` | WARM CHECK OK | yes | the hitches the 3D view takes out of play ([view3d.md](view3d.md#the-warm-up-polish-pass-9)): a level's first frames draw every hidden piece (twister, storm wall, rain, seat views) as a speck and then put each back; the level's props, the events' hogs and raiders and its vehicles' seat views made at its first frame; every speck kind `game.burst` throws by name has its picture |
| `check_fixes` | PARITY FIXES OK | | the parity regression checks and the quick parts of many others (below), in six parts side by side |
| `physics_check` | PHYSICS OK | yes | gibs, brass, chunks and bodies dropped on decks, ramps and stairs and thrown at walls rest on a surface, never inside anything; the loose-things features on a loft ([gameplay.md](gameplay.md#loose-things-on-the-real-3d-shape-v300-remaster)); ragdolls lie on decks, treads, ramps and past a rail and sleep, no model sunk past 1 cm, one body on another, slow-mo finishers start on the last kill and never with company (`physics_ragdolls.gd`); loose things settle with no snap; nothing thrown fast passes a thin wall; water splashes, sinks and drifts (`physics_water.gd`); the shared physics core: the exact solver the same to the bit as the pins' old one, the grid, boxes stacking and waking what lies on them, a body on a wreck piece and a board on a body (`physics_core.gd`, [gameplay.md](gameplay.md#the-shared-physics-core-engine-pass-6)) |
| `live_props_check` | LIVE PROPS OK | yes | things taken up, held, thrown (a hand hurt and shoved, a propane tank breaking and going up, jugs spilling shine, a brute heaving a tank), set down and saved; fire spreading over hay, never onto stone or dirt, burning out, the same twice, sooner in rain; a still spraying and going up; a snapshot carrying a throw and a fire on tick for tick; all of it off with LIVE PROPS AND FIRE off ([gameplay.md](gameplay.md#picking-things-up-fire-that-spreads-the-stills)) |
| `brawl_check` | BRAWL OK | yes | the boot (slide, slam, domino, a door kicked in), smashes, a finisher of each gun class and every move, slow motion from the blow (alone only), co-op, each hazard kind (and a hand walking by), bosses never finished and only hurt by a hazard, two runs the same, a snapshot mid-slide played on the same ([gameplay.md](gameplay.md#dirty-fighting-content-pass-8)) |
| `climb_check` | CLIMB CHECK OK | yes | every chapter has ladders, each joined foot to top in the nav graph; a ladder takes the player up and down, JUMP lets go; pull-ups onto a chest-high stack and from it onto a roof, not onto one too high; a hand comes up a ladder to the player on a lookout and drops off it to get at them below; a hand under fire ducks out of sight, peeks out, fires and goes back; a hand kicks a door open (not EASY or CLASSIC); the same run twice comes out the same |
| `vehicle_cab_check` | VEHICLE CAB OK | yes | the seat view: every kind's cab model, art and moving parts are there; the driver's eye gets the cab (not on foot, in PHOTO MODE or without a window: then the car's painted dash), its own model is left out, the wheel turns clockwise right with the hands on it, needles rise, the prop turns, the blade lever goes forward; drawn, it sits between the near plane and the nearest wall; SCREEN SHAKE and STILL stop what they should, the view widens at speed but never past a wider FIELD OF VIEW; spray lands in the view; the driving plate in every HUD mode and with touch; driving the same with the cab drawn ([gameplay.md](gameplay.md#vehicles)) |
| `moonshine_check` | MOONSHINE CHECK OK | no | the Moonshine Run (content pass 8): in the campaign between the speedway and the Mothership with its gate, pack, guns, rematch and trophy plinth; its stations and the barn doors; the MOONSHINE RUN driven from the barn through both roadblocks (every barricade rammed, the agents woken, in time, the tally); on foot past the barricades to the cave; the patrol cruisers drawn, flashing, running a man down and pulled over by the radio; an agent's radio call and the gas man's tear gas; the Revenue Man's burst, axe charge into the rock, shades, the still blowing and the roof coming down; a v8 campaign save at the Mothership and an old unlocks file ([levels.md](levels.md#the-moonshine-run-content-pass-8)) |
| `vehicle_set_check` | VEHICLE SET OK | no | finding the vehicles and what is built round them (feature pass 7): on each map with one, its KEYS IN IT sign by it, its lamps on (dark once burnt out), its radio heard near and not far, the automap's mark, USE's prompt from further off looked at (not away), the wider reach, its line said once; the bayou's CHANNEL RUN and the speedway's HEAT RACE driven to the end in time by a pilot (the hands they wake held back till then, the pin and objective on the next gate, the plate, the flare, the reward, the tally, a save), run out of time and needing another pass, the race only the lap cars' way and in their time; the car's window gun (one-handed only, not back through the cage, wilder, steering less, the cab's right hand off) and a partner riding shotgun who shoots and sees the cab from their seat ([gameplay.md](gameplay.md#vehicles)) |
| `gun_find_check` | GUN FIND OK | no | finding the guns (feature pass 7): in each chapter every gun new in campaign order within reach of the way through (route_map's legs) with no secret in front, a gun sign where the way is left for one further off and out of sight, a secret's gun teased by its rounds; every gun sign hung on something facing out; GunFinder's table of each chapter's guns the levels'; every gun lying out shines, is lit, is named looked at and not looked away from, goes on the automap once seen (NEW IRON in the key), is smelled once, and has none of it once had; a secret's gun gives nothing away; the tally's GUNS row; the trophy shack's board and card; none of it in County Run, the range or a versus map ([gameplay.md](gameplay.md#finding-the-guns-feature-pass-7)) |
| `pacing_check` | PACING OK | no | pacing (polish pass 9): each chapter's way through (route_map's legs) step by step, the longest run walked for the first time with no hand within 10 cells, no pickup within 3.5 and no station or sign within 5 at most 24 steps (the Moonshine Run's north blacktop was 31 before its pull-offs); each versus map as a DEATHMATCH arena has rounds and something to heal with (its plan's `arena_loot()`), every pickup walked to from the start, no spawn point more than 26 cells from one ([levels.md](levels.md#pacing-and-dressing-polish-pass-9)) |
| `balance` | BALANCE OK | no | difficulty and pacing as numbers (polish pass 9, `tools/balance.gd -- check`, five rows `balance_1`..`_5`): a retried boss fight brings the `[boss_retry]` health and rounds; every boss fought in its rematch by the REGULAR balance bot at NORMAL (two seeds) falls inside its `BOSS_BANDS` seconds; every chapter played from its chapter kit by the SHARP bot at NORMAL is cleared within `CHAPTER_DEATHS` deaths and inside its `CHAPTER_BANDS` seconds. Play is exact, so a change that moves a band moved play: measure with the long report and set the band again, saying why ([gameplay.md](gameplay.md#difficulty-and-pacing-as-numbers-polish-pass-9)) |
| `bench_check` | BENCH CHECK OK | no | Mundell's junk bench (content pass 8): none with WORKBENCH off, in County Run, the range, a versus map or a deathmatch (mods count for nothing there); the Crossroads' bench and each chapter's by its start; scrap laid out, taken for its worth, dropped by a hand, a breakable, a wrecked vehicle and a set piece; buying at a bench only, never twice, without the gun or the scrap; each mod's change; every modded gun picture and the bench's pictures; saves (version 10, a version 9 save upgraded), kits and the hub's buys carried; co-op's own buys, lockstep and a snapshot copy. `-- audit` prints the scrap the campaign bot finds a chapter ([gameplay.md](gameplay.md#mundells-junk-bench-content-pass-8)) |
| `events_check` | EVENTS CHECK OK | no | the county events (content pass 8): EVENTS off casts no die, OFTEN always and SOMETIMES about half the chapters plan one, varied, no blackout off the night levels, none in the hub, range, Mothership, County Run or a versus match; the twister makes for a barn, pulls and knocks flat a player under the sky but not one under a roof, smashes a breakable, brings the barn down, flings a loose thing and lifts; the herd tramples a player and a hand, a blast kills a hog, the herd is gone; the raid's squad comes in unseen, counts, shoots it out with a hand, busts the still, ends when they are down; the blackout's dark, flashlight (key, Controls.item, battery, flat), the hands' sight in the dark and with the light, lanterns, the breaker and the power back in time; none in a boss fight and one cut short by one; the exit still reachable after each; saves mid-event; lockstep and a snapshot copy through each; the hogs' frames, the lantern, the cues, the settings row ([gameplay.md](gameplay.md#county-events-content-pass-8)) |
| `hound_check` | HOUND CHECK OK | no | BLUE the hound (content pass 8): heels and catches up, none where he is off, bays at a secret door and new iron, points at a hidden pickup, holds a hand (stunned, never killed by him, kicked at, finished by the player), a told SIC, never a boss, fetches to the player's feet, goes down and is got up (held USE, a rind, by himself), STAY and COME by key, replay op and controls, saved, co-op's two hounds, lockstep and a snapshot copy with him about, his art and badge; pass 10: every state's pose a frame of his model (gaits by pace, limp, tracking, idle wag, scratch, sniff, sit, lying, point, howl, lunge and bite, the hold's shake, yelp, going down, on his side, got up, getting up, the shake), no game.rng; the badge's job and mood words fit, the marker behind a wall and at the view's edge, the point's brackets, GETTIN' BLUE UP, the prompt naming the key; pass 10's ranging, stepping out of the sights, a hazard, backing off, a boss's aim, the free seat, the sulk, howl, cower, growl and still, his pant, shake and barks dealt at random; ([gameplay.md](gameplay.md#the-hound-content-pass-8)) |
| `hound_walk_check` | HOUND WALK OK | no | BLUE never stuck (pass 10): walks every chapter, the hub and the range with him, never stuck over 2 s, far over 8 s, seen jumping or in a hazard; a load far off, a ride in each vehicle, every chapter's start (`-- verbose`, `-- trace=`) |
| `vehicle_check` | VEHICLES OK | yes | each vehicle (airboat, car, mower) is got into with USE, drives, strikes something and bounces off never inside a wall, runs a hand down and is got out of; the airboat keeps to water, the car's driver holds the .38 out of the window, a wreck throws its driver out, a rider rides along in co-op, a snapshot copy drives the same ([gameplay.md](gameplay.md#vehicles)) |
| `plank_check` | PLANK CHECK OK | yes | a barn's and a pen's wall at the fair, the sawmill's shed, a bayou shack and a gabled barn on County Run's Hickston: one may open, shot about it shows its boards out (a merged run cut at the cell), broken through it is floor to bodies, sight and both flow fields and walked through, a shed keeps its roof (and gable) over the gap, a pen's neighbours stand their own height, its planks rest on a floor, a snapshot and a save open it the same with the same walls ([gameplay.md](gameplay.md#walls-break-too)) |
| `set_piece_check` | SET PIECE CHECK OK | no | each chapter's set pieces stand; a barn with two posts shot out creaks, its hand runs, it comes down, hurts and pins the player under it and lies as cover; a wall panel shot about shows its boards out and shot through opens the way; the mower rammed into a post takes it out; dynamite in the hay brings the shed down; a water tower's two legs out on a side: it goes over that way, its tank bursts and floods the street, puts out the fire there and shoves a hand; a holed fuel line leaks gas its length, fire runs it and the propane at its end goes up; the same breaks twice match; a snapshot and a save carry it with its cover; with every set piece down every way it may fall every station, key and exit is still reached; idle costs next to nothing ([gameplay.md](gameplay.md#the-big-breaks-content-pass-8)) |
| `wall_looks_check` | WALL LOOKS CHECK OK | yes | plank walls (the fair): a round knocks out the plank it struck round where it struck, the next breaks it further, a light pellet only wears it, two cells struck in different places differ, buckshot tears several planks, a blast tears out those facing it, a hole goes with its plank, the view's rows decode as the shader reads them, a client makes the knocks up, play is the same without the looks, gone through it bursts along the shot; windows (Hickston): the crack web lies where the round struck, shot out it throws shards cut fresh (struck elsewhere: different), they break again landing into glints, a blast shows `_bst` and throws the frame; a pane's cut covers it, small near the hole; each material's hole its own picture and size ([gameplay.md](gameplay.md#how-walls-look-taking-a-beating-destruction-pass-11-walls)) |
| `wreck_motion_check` | WRECK MOTION OK | yes | how wreck pieces move (pass 11): a ring of staves left standing goes over, a hoop rolls on its rim and wobbles down flat, a can rolls, a lid spins down, glass skids short, a tin sheet flutters, a shot knocks a lying board at its hit point (spinning it by the side struck), a blast throws near pieces harder, a player, a hand and a vehicle kick pieces, one barrel shot on its left and its right comes apart differently (and the same twice alike), glass cracks, knock sounds stay under their cap, a heap rests with nothing inside anything ([gameplay.md](gameplay.md#how-the-pieces-move-pass-11)) |
| `blast_check` | BLAST CHECK OK | yes | every blast look throws what it should (its fire, lobes, column, scraps, dust ring, crater); what blew picks the look; four sticks in a row look four ways; water throws a column and no crater, the hay loft no crater, a wall throws the fire off it; a chain keeps each fireball under the cap; the stock car wrecked throws its own parts away from the blast, leaves a charring hulk and burns, hurt it smokes; play the same whatever the looks' dice ([gameplay.md](gameplay.md#blasts-and-wrecks-destruction-pass-11)) |
| `wreck_check` | WRECK CHECK OK | yes | every kind of breakable with `pieces`, windows and fence cells on the chapters, a County Run map and the hub throw real pieces that all come to rest on a floor, never inside anything; none on the versus maps; the cap holds; a save put back throws nothing; asleep costs next to nothing ([gameplay.md](gameplay.md#in-real-pieces-of-themselves)) |
| `save_fixtures` | OLD SAVES OK | yes | saves from every earlier version still load |
| `level_edit_check` | LEVEL EDIT OK | yes | level editing keeps the walls right |
| `user_map_check` | USER MAP CHECK OK | yes | player maps: the examples, hostile files refused, the MAP SHED's calls, a map played alone, in a 5v5 round, County Run and deathmatch, its saves, sent to a lobby's joiner ([levels.md](levels.md#player-maps)) |
| `quest_reach` | QUEST REACH OK | | every quest prop, gate and item can be used from where it is seen, and never through a wall (slow; `tour=<json>` for pictures of each prop) |
| `bot_campaign` | CAMPAIGN WALKTHROUGH OK | | the bot plays the campaign through (slow) |
| `net_showdown_check` | NET SHOWDOWN OK | | online 5v5, host plus three clients, lobby to lobby (`lag= loss= seconds=`) |
| `net_server_check` | NET SERVER OK | | an always-open lobby with no host player |
| `menu_touch_check` | MENU TOUCH OK | yes | taps through every menu, the 5v5 store, the County Run screens as touch events; in play the junk bench's board (a tag bought, a tap off it), the USE button held (`Controls.hold`) and a tap skipping an opener ([ui.md](ui.md#touch-in-play-polish-pass-9)) |
| `opener_check` | OPENER CHECK OK | yes | the chapter openers: every chapter's shots inside its map, card, tagline, boss cel and cues, the narrator's two lines STT-matched and in the bank; the OPENERS setting (FIRST TIME once, ALWAYS, OFF), never the hub, COUNTY RUN, a retry or a loaded save; a key or click skips it, it ends by itself, play's snapshot and clock unchanged in every chapter, two seconds of play after it the same as without; every opener draws its key moments; the sound: a bed of the chapter's own song from start to end and past it, played by the score player as the chapter's score, no gap over 0.5 s with nothing sounding in the mix plan, the bed never held to nothing and at play's level at the end, every line 6 dB over it, every cue in the bank and in its chapter's pack or the first download; played out the bed goes on at play's level, skipped the duck, sting and opener effects stop (`-- plan <file>` writes the mix plans) ([view3d.md](view3d.md#the-chapter-openers-content-pass-8)) |
| `opener_camera_check` | OPENER CAMERA OK | yes | every opener's camera sampled 60 times a second: never in or skimming a wall, roof, deck, door, prop or the ground (`OpenerCamera.clear_at`); between cuts turns under 45 deg/s, tilts under 30, speed under 8 cells/s, velocity continuous (changes under 12 cells/s^2), a lean of at most 2.3 degrees; it lands in the player's own eye with his picture out of the way (`-- report` prints each chapter's numbers) |
| `boss_end_check` | BOSS END OK | no | the boss endings (`src/boss_ending.gd`), every boss: felled in its rematch, the arena stood down (no hazard, no enemy shot, a hand near stunned), the ending started and run through the front end's frame to the result board in its band (5.1 to 5.8 s), its camera never in a wall, roof or the ground (`OpenerCamera.clear_at`) and keeping the boss in the shot, no HUD laid, the end sting still playing over the score's hand-back, the music as asked never silent over 0.5 s, the last word captioned, the board's time and ribbon; a key held off at first and a key a second in skipping to the board; in the campaign with two players it plays its length and hands back to play; the foreman's fall with and without it leaves the same game (play exact) |
| `bark_check` | BARK CHECK OK | no | the county's talk in play: the balance bot plays Hickston and the mill (4 minutes or to the end) with an ear that times every line on the game clock; the hands' barks come at 1.5 to 14 lines a minute, never the same line twice running, never one over another still playing (a boss's line or a tough guy's piece cuts in), Mundell sizes up the chapter, and a minute of it is the same game as with CHATTER OFF ([audio.md](audio.md#voices)) |
| `camera_check` | CAMERA CHECK OK | yes | the QUALITY tiers (pick, presets, AUTO's meter, physics steps); the HUD's Control boxes compose to `HUD.draw`'s bar pixel for pixel (campaign, 5v5, County Run, full and MINIMAL); PHOTO MODE in and out, flying, the player in view, a filter, a picture saved; the KILL CAM noted, sampled, replayed with stand-ins and skipped, never a boss's fall; play's snapshot unchanged by either; the view polish (`view_polish_check.gd`): SHADOWS' pairs and blobs, marks on a prop's model (holes, scorch, char, kept and handed on), the storm wall's curtains and ring |
| `hud_layout_check` | HUD LAYOUT OK | yes | the HUD's layout ([ui.md](ui.md#the-huds-layout)): crowded moments (campaign, SMALL TEXT, MINIMAL, driving with a run, the lap, co-op watching and reviving, a boss, versus, the fair, COUNTY RUN, 5v5) drawn headless with each piece's ink measured: no two touch, all inside the margins, each expected piece there; the layout's rules; the status bar's meter captions fit their wells |
| `county_check` | COUNTY CHECK OK | | County Run rules; each map through a death and a retry |
| `county_net_check` | COUNTY NET CHECK OK | | a County Run party of two over ENet and WebSocket against a lobby server (`seconds=30`, as CI always ran it) |
| `net_party_check` | NET PARTY OK | | online CAMPAIGN CO-OP, DEATHMATCH and TEAM DEATHMATCH hosted by the real front end through a lobby server's party line: chapter to hub to chapter, the boss checkpoint's retry, downs, revives, watching, late joins, leaving, THE PARTY SAVE, the kill feed, a deathmatch by bots (`only=coop` or `only=versus`) |
| `relay_check` | RELAY CHECK OK | | the party line in a lobby server: its limits, the lag it adds, a hosted 5v5 and a County Run with players through it over ENet and WebSocket (a fallback from the host's address, a late joiner straight in, a kick, the host gone), copies kept with the host (`quick` in check_all; `ping=<address>:<port>` times a line running elsewhere) |
| `games_check` | GAMES CHECK OK | yes | the range's board on a lobby server over ENet (posts, a name's best, refusals, asks, the County Run board beside it), the fair's shooting gallery (the bell, each target's points, a can flying and bouncing, the house paying, the prizes saved, no station or door added), the hub's trophy shack (statuettes by the gates open, cups, gnomes, its card), the range's duck row (a duck turned at the rail's end spins round on its stick) |
| `leak_check` | LEAK CHECK OK | yes | every game let go is freed: games made and disposed (campaign, co-op, deathmatch, County Run, range, Crossroads, a host's) and the front end's own flow (a chapter, the Crossroads, the range, a County Run, co-op, a deathmatch, back to the title) come back to the same object count round after round ([architecture.md](architecture.md#letting-a-game-go)) |
| `ai_check` | AI CHECK OK | yes | the tick's spike fixes and the enemies' level of detail: sight lines with the quick tests answer as step by step (nine maps, flat and at heights, furniture broken out), flow walks reach the same cells, cover's whole search finds the old spot (both HANDS settings) and in play stays within `cover_budget` spots a tick and ends where the whole search would, idle activities by cell, far calm enemies wait and near or engaged ones do not, a shot heard or a hit wakes one at once, `lod=false`, a snapshot mid-wait goes on the same ([gameplay.md](gameplay.md#speed-of-the-tick)) |
| `cpu_check` | CPU CHECK OK | yes | the frame's and the tick's CPU work (pass 10, PERFCPU): text_width kept by text answers as letter by letter (every style, SMALL TEXT CLEAR either way), the kept glyphs read-only, 20,000 measures under 40 yardsticks; polygons fill the old scanline pixels; a line's runs on the Godot canvas cover the Bresenham pixels once in fewer rectangles; a label's kept letters where the software's stand; the feature hook lists are the features with their own, in order; every live enemy asked its level of detail once a tick; the bot game's tick under 2 yardsticks and no feature's tick past 0.3 (a yardstick: a fixed piece of GDScript work timed in the same process, so a busy runner slows both alike; `report` prints the numbers) |
| `cover_check` | COVER CHECK OK | yes | the 5v5 maps' boarded cover: shot through (floor, sight, a shorter way), stood up again each round, kept by snapshots alone |
| `bot_check` | BOT CHECK OK | | the 5v5 bots' aim per BOT SKILL against a strafing target at 5, 12 and 20 cells (first hit, hit rate, kills inside 6 s within bounds; EASY slower than HARD; no laser up close), a target behind smoke never taken for a foe or shot at (and with the lane clear it is), ten-bot matches where they plant, carry and rescue a hostage and the team radio speaks, and a bomb planted with the outlaws down cut by the deputy bots on grainyard, salvage and pineacres (`bench` prints the before/after table: four skills, 4..22 cells, standing and strafing) |
| `replay_check` | REPLAY CHECK OK | | replays play back exactly (`replay_check.gd`, run `-- quick`): bots record chapter one from a fresh game, sawmill from the middle with its keys as actions and a cheat and a wound outside them, the quarry boss fight, County Run with card picks and co-op with two; each from its bytes onto a fresh game matches every hash and the whole end snapshot; a recording past its cap plays across its gap; a nudged game is caught within a hash; the front end's own recorder (advance, act, a setting changed mid-run), `replay save`, a death's file and the crash log keeping the session's replay. Prints the recording's cost a tick. Without quick, twice as long |
| `load_check` | LOAD CHECK OK | | the faster level load hands play what the slow way gave, on every level: the nav graph node for node and edge for edge in the same order, the grids, walls and plane bounds number for number (against `tools/load_reference.gd`, the old code kept); the open floor kept for a level played again as measured, untouched by what a game did with its own; the wreck pieces cut on a worker while a level's first frames run the same piece for piece as cut at once ([gameplay.md](gameplay.md#loading-a-level)) |
| `load_speed_check` | LOAD SPEED OK | | pass 10's load speed ([view3d.md](view3d.md#loading-and-the-warm-up-pass-10-perfload)): every kind's baked ragdoll rig bit for bit the rig found from its model (`tools/rig_reference.gd`, the old build; a stale one names `tools/art/bake_rigs.gd`); the packed made cues (`made_cues.bin`) the samples made at once; the title's warm-up draws every view3d shader but the sky's and takes its pieces away; the eight chapters loaded headless find no rig from vertices, leave no model with the loader, keep no model's looks as pixels, stay within their start and first-frame budgets, and loaded again stay within the memory ceiling and grow it under 40 MB (`-- report` prints each chapter) |
| `tune_check` | TUNE CHECK OK | yes | the dev console's tuning and overlays (`dev_tune.gd`, `dev_overlays.gd`): `tune set` takes in a running game (a gun's fire time, an enemy kind's health on the one in play and a new one, static values from modes.cfg, hits.cfg and difficulty.cfg, a whole number keeping a float's type), `tune get` reads it, a change is a replay keyframe, online it is refused, `tune reload` puts the files' values back and says each change (a second says none); `tune save`'s rewrite on bosses.cfg's text (a key, a multi-line value, a new key and section; every other value, comment and line ending kept) and on a copy of weapons.cfg, read back; the watch reads a saved copy again; every overlay on over a bot's fight drawn headless (traces, tick and listener times come in, the picture changes), the run recorded with them on plays back exactly without them, and turned off the `ticked` listeners are as before, in order. Prints the static values watched and what a reload of every file costs |
| `net_errors_check` | NET ERRORS OK | yes | what a player is told when joining goes wrong: another version or protocol (both versions named), a full lobby, nobody at the address (COULD NOT REACH THE HOST), a host that never answers the HELLO (THE HOST NEVER ANSWERED, pass 9: it waited for ever); a client that lost the host lands on the JOIN form with ENTER TO TRY AGAIN and gets back in; a refusal or a closed lobby goes to the title |
| `predict_check` | PREDICT CHECK OK | yes | an online client's own shots, reloads and pickups shown at the press and put right by the host's word (`net_shot_predict.gd`), with no network: a range deathmatch as the copy, a hand-filled `NetSync.Client` as its link, each input played 12 ticks on. A shot played (one bang, kick and tracer, rounds down at the press and never back up, its mark and tick once), refused (rounds back, mark and blood withdrawn), out of rounds (one dry click), a hit judged a miss (mark and blood withdrawn), a gun taken up and fired at once, a pickup played and one refused (back in the picture), a reload pressed mid-burst with the trigger held (every cue, tracer and shell counted as often as a copy without prediction), a stick of dynamite lit and thrown (and one the host never lit: struck once, the stick back), the crowbar's blow on player two before the copy plays it, USE's boot in co-op, and nothing on a game nobody watches |
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
| `main` | the browser builds (`pack_lite.gd`, `Web`, `Web Lite`, the chapter packs, `pack_check.gd -- quick lite build=`), deployed with the landing page to Pages |
| a `v*` tag | the EXE (smoke-tested on Windows), the installer, the APK (after `pack_lite.gd`), then the GitHub release with the three files |
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
