# Gameplay: things that are easy to get wrong

The play code is the chain `game_state` -> `game_world` -> `game_combat` ->
`game_view` -> `game` in `godot/src/` (see [architecture.md](architecture.md)).
Bosses are in [bosses.md](bosses.md), modes in [modes.md](modes.md), the
level builder in [levels.md](levels.md).

## Rules that hold everywhere

- **Gameplay randomness** comes from the game's `rng`. Cosmetic effects use
  their own seeded generator (`gore_fx.dice`), so they never change play.
  `tools/replay_check.gd` holds play exact: recorded runs must play back to
  the same hashes and end ([multiplayer.md](multiplayer.md#replays)). The
  front end's keys that change play go through `main.act()` so a replay
  keeps them.
- **Saves are versioned.** Changing what a save holds means bumping
  `SessionStore.VERSION`, adding the step from the old version in
  `src/save_upgrade.gd`, and running `tools/save_fixtures.gd -- make` to add
  saves of the new version to `godot/tools/saves/`. Never delete the old ones:
  they are how CI knows players' saves still load.
- **A save file's numbers come back as floats** (JSON). A feature's
  `restore()` reads each into a typed variable (`var slot: int = row[0]`)
  before it is compared, looked up with `has()`/`find()` or used as an index:
  `[0.0].find(0)` is -1. A seat list read back raw left a player saved at the
  wheel on foot and the seat taken for good (polish pass 9;
  `tools/save_numbers_check.gd` round-trips saves through JSON mid-ride,
  mid-raid and mid-blackout).
- **Tool scripts never write the player's settings** (`main_state.gd
  persist_options` returns when a script runs the main loop), and tests write
  saves under `OS.get_cache_dir()`. The gun pictures warm on a thread that
  `Weapons.Armory.settle()` waits for when the program closes.
- **Settings** are listed in `src/setup_pages.gd` (one row each: label, key,
  default, choices, hint); `tools/check_fixes.gd` counts them (88 now;
  pass 15's CHECKPOINTS, under PLAY, and DANGER ARROWS, under DISPLAY, are
  the newest). Settings are not part of a save, so a
  new one needs no save version. Changing a setting shows what it did and that
  it was saved where the hint goes (`main_flow.gd`).
- **Keep the Redneck Rampage feel** in new polish: dusk and dirt, brass and
  red hulls, crows, county-fair words and ribbons, cartoon wipes; original art
  and sound only (new small sounds can be made in `assets.gd` MADE_CUES;
  since pass 10 `tools/pack_assets.gd` makes them once into
  `assets_gen/made_cues.bin`, so run it after changing one).

## Features listen to events

Signals live on `game.events`, a `GameEvents` object
(`src/core/game_events.gd`). Connect with `game.events.<signal>.connect(...)`.
Signals are synchronous and called in the order they connected, so play that
listens stays the same on every machine. They include `level_started`,
`level_won`, `enemy_killed`, `player_hurt`, `pickup_taken`, `station_done`,
`shot_fired`, `hit_landed`, `ticked`, `exploded`, `gun_reloading`, `traced`
(where each hitscan shot, pellet, swing or squirt ended and what it struck),
`pierced`, `boss_intro`, `boss_phase`, `boss_staggered`, `boss_weak_hit`,
`boss_down`, `blood_sprayed`, `enemy_gibbed`, `enemy_bled_out`,
`wall_struck`, `blast_shoved`, `prop_struck` and `prop_broken` (a breakable
shot or broken). `game.events` is a VIEW field in
`GameSnapshot`.

A new piece of play goes in `src/features/` as a `GameFeature` (see
`game_feature.gd`), listed in `features.gd`: it connects to those, saves its
own state in the save's `features` block (restore gets {} from older saves,
so no new save version), and may add a tally row. Put it in `SIM_FEATURES` or
`LOOKS_FEATURES` in `game_snapshot.gd` ([multiplayer.md](multiplayer.md)).
Triggers, lessons and chapter stats are features, and so is the polish that
only looks: `weather` (lightning and thunder), `debris` (brass, hulls,
embers, scorches, smoke, blood trails), `ambient` (crows, fireflies),
`callouts` (TWOFER, HAT TRICK, HOG WILD, RAMPAGE) and `tally` (rows that
thud down and a ribbon). Features may add sprites and ground marks;
looks-only ones use their own dice so play never changes.

### Gun effects

`weapon_fx` draws every gun's shot from the events: fuse sparks, rocket and
cow trails, blast dirt and cinders as sprites; tracers, rivets, the teat gun's
milk, the Copperhead's steam and sparks over the view with `draw_view(c)` (a
feature hook run after the world and before the gun), from the gun's muzzle on
screen (`Armory.place_muzzle`, `Weapons.muzzle_at`) to where the shot struck
(`Game.to_canvas` projects a world point onto the canvas). Draw lots of pixels
there as cached pictures (`blit_rgba` with a key), not pixel by pixel: on the
Godot 2D canvas each `set_pixel` is a draw command. A viewpoint in a window
tour may name a `gun` (its index) and `fire` with `ticks` to show one gun
firing; viewpoints after it keep firing it.

**The gun and blast effects with LIGHTS AND GLOW on** are a layer of their
own, drawn only while `Effects.rich` (game_view.gd sets it: `view.layered`
and `Effects.enabled`), so the view without lights stays as it was
(`compare_3d.gd`'s `_gpu` pictures hold that): `features/gun_fx.gd` (blasts,
by `src/blast_looks.gd`: see "Blasts and wrecks" below; strikes by material,
`fx_hit_<kind>`, four frames with a dark rim, with more chips; wadding,
smoke and sparks off the muzzle; fuse and rocket sparks; its own dice, made
whatever the view), `gun_flash.gd` (each gun's muzzle flash: weapons.cfg
`flash_art`/`flash_size`, over the old flash as a glow), weapon_fx's fatter
tracers with a glowing head, and each gun's own muzzle light
(`[light.muzzle_<gun>]`). Pass 15 adds a hand's shot lighting the yard round
him and the smoke curling off the player's muzzle after a burst
(`src/muzzle_looks.gd`), and each gun's own brass (effects.cfg `[casings]`,
`features/debris.gd`): [view3d.md](view3d.md#looks-that-read-pass-15). game_view.gd leaves the old `fx_blast` fireball out
then. The pictures are in [art.md](art.md#gun-effects-art).

### Blasts and wrecks (destruction pass 11)

`src/blast_looks.gd` (owned by gun_fx), numbers in
`data/tuning/blast_looks.cfg`. Looks only: none of it touches a blast's
damage, reach or shove (shots.cfg), and nothing is saved or carried.

- **A look a blast**: by its shots.cfg kind (`[kinds]`: tnt, keg, fuel,
  gas_can, cow, rocket, still, nitro, small) or, over it, by what blew
  (`[from]`: the breakable whose picture went up there, a propane tank or a
  hazard drum both being "fuel" blasts in play, or a vehicle wrecked this
  tick). A look says the fireball's fire (`d` yellow-white, `f` fuel's deep
  orange going to oily black), size and life, lobes, the column (soot or a
  keg's grey-white powder) and its mushroom cap, scraps (charred wood, torn
  tin, meat), clods, the dirt puffs of the dust ring, sparks, embers,
  burning drops, glass, the crater, the light and the view's kick.
- **Fire, then smoke**: the fireball shows only its fire frames (`SHOWN`, a
  bright core out fast, then lobes rolling up) over four fifths of its life;
  the smoke is the column's billows (`fx_billow*`, three shapes, mirrored at
  random: lumps lit on top, a darker core, lighter lumpy edges, no outline),
  a stream of them rolling up off the fire one after another, three big ones
  taking over where the fireball was as it goes, the cap's spreading at the
  top; young ones are lit orange from under (`fx_billowhot`). Smoke and dust
  (translucent sprites) take only the brightness of the area's tint
  (`sprite_layer.gd`): a pond yard's green tint turned neutral smoke teal
  and brown soot olive.
- **The shine cocktail** (the 5v5 throwable; `modes/tactical_utility.gd`
  calls `gun_fx.firebomb()` where its fire patch starts) bursts through its
  look (`cocktail`): a fuel ball, the bottle's glass, burning shine, no
  crater. Its fire patch is play, as before.
- **No two alike**: each blast reseeds the layer's own dice from where and
  when it went (`burst`), so a replay looks the same and every blast its own:
  one of three fireball shapes (`fx_boom_<fire><shape>_N`, 12 frames),
  mirrored or not, size and life within 15 %, one to `lobes` smaller balls
  bursting beside it at their own angles and moments, the column's lean,
  counts within 30 %, every scrap's arc, one of four craters
  (`mark_crater_N`) turned and sized its own way.
- **Where**: in standing water (an effects.cfg `[water]` floor, not a puddle)
  a column of water (`fx_geyser_N`), spray, steam, a smaller fireball and no
  crater; on a deck or any floor that is not the ground splinters instead of
  clods and no crater (debris.gd's scorch stays); within `WALL_NEAR` of a
  wall the fire is set off it and the lobes, scraps and clods go the other
  way.
- **Chains**: a blast within a second of the last throws `chain_less` fewer
  bits (down to `chain_least`), never a smaller fireball or flash, so a row
  of drums reads as boom after boom.
- **The view's kick**: within `kick_reach` a blast punches the local view
  (`feel.gd punch()`: yaw away from it, a pitch, a drop, the gun shoved) by
  the square of how near, times the look's `kick`; SCREEN SHAKE scales it.
  game_combat.gd's distance shake is as it was.
- **Lights**: a look's `flash` and `glow` scale `[light.blast_flash]` and
  `[light.boom_glow]`; side lobes have none; a burning wreck has
  `[light.wreck_fire]`.
- **Sounds**: a look's `layer` plays with the blast's own cue (the fuel
  looks: `fuel_whoomp`); a blast throwing `debris_from` scraps or more plays
  `debris_cue` (`blast_debris`) `debris_after` seconds later.
- **Cost**: `most_bits` in the air (200; `most_bits_low` 90 on a phone or
  QUALITY LOW), the oldest going first; craters `CRATERS` (16, 8 on LOW),
  fading after `CRATER_LIFE`. Measured against v3.8.0 back to back:
  stress_bench's new `chain6` (six blasts nine ticks apart) and strike,
  wreck48, fire, arena are all within noise ([checks.md](checks.md#benchmarks)).
- **Vehicles** (`src/vehicle_wreck_looks.gd`, owned by gun_fx): see
  "Hurt and wrecked" under Vehicles.
- Checks: `tools/blast_check.gd` (BLAST CHECK OK, check_all, quick too);
  `tools/blast_frames.gd -- out=<dir>` pictures every kind, a wall, the loft,
  water, a chain, two side by side, each vehicle wrecked, the fireball's arc
  every 3 ticks (`arc_tnt`, `arc_fuel`) and the stock car's first second
  wrecked from the side and from the front (`wreck_side`, `wreck_front`)
  (`docs/godot3d/destruction/BLASTS/`, before and after).

## The automap, canvas and sprites

- **The automap** (`game_automap.gd`, the game's `map_view`) follows the
  player at a readable zoom (PGUP/PGDN, keypad +/-, the mouse wheel; zoom 0
  fits the level), from an
  image of the whole map at that scale (walls as lines, ground by kind,
  walked ground painted on as it is walked). A tour viewpoint may set `map`
  and `map_zoom`.
- **Two canvases.** With a window the HUD, menus and weapon draw with Godot
  2D (`Canvas.gpu`) in a 320x200 viewport that the display shader lays over
  the 3D view. Headless tools (and `--cpu-canvas`) draw the canvas in
  software, with no world. Shapes still come down to `set_pixel`, `_hspan`,
  `_vspan` and `fill_rect`, so a new shape drawn through those works in both.
  Never write `canvas.pixels` directly for something on screen; give
  `blit_rgba` a cache name. Each rect is a command, so what is drawn every
  frame from many shapes is drawn once in software and shown as a cached
  texture (the status bar, banners, the objective pin: `hud.gd
  _pin_texture`).
- **Sprites that last one frame come from a pool** (`game.pooled()`,
  game_state.gd; `sprites()` starts it over each frame): enemies (through
  `Enemy.sprite(..., into)`), pickups, shots, specks, puffs, gibs, blasts and
  the effect features' sprites. A pooled sprite comes back with every field at
  its default; never keep one past the frame (a sprite kept from frame to
  frame, like the fixed ones or breakables' resting pieces, is
  `View.Sprite.new`). Cel names are made once (`Enemy.cel_name()`,
  `EnemyLooks._row()`, cleared when the art index changes), not formatted
  every frame. These were checked exact: every sprite of 32 scripted runs
  (fights, kills, gibs, blasts) listed old and new, field for field, plus
  every enemy's state and the dice each frame. `game_view.gd sprites()` lists
  only what can show: fixed sprites in blocks (`fixed_blocks`), and enemies,
  pickups and effects through `in_view(x, y, reach)`; a new sprite source
  should use it too. Culling only ever leaves sprites out, never reorders
  them. `in_view()`'s sums are also written out in `_seen()` (blocks from
  `fixed_cull`/`late_cull`, kept beside `fixed_blocks`; breakables' `_widen`
  updates both) and in the enemy and pickup loops: change them all together.
  A window tour of old and new code compared picture for picture is how these
  were checked: do the same after touching them.
- **Text has an outline** (dev.43, `Canvas.OUTLINE`): `label()` with
  `shadow` draws the dark shade on every side and the drop below, so text
  reads over the view; `HUD.DIM`, `Menu.DIM` and `Menu.FADED` are brighter.
  Changing how text draws changes every picture reference (a window tour,
  then `compare_3d.gd -- <dir> update`).
- **SMALL TEXT** (dev.45, setting `small_text`): `PixelType.clear_small`
  draws and measures the 5-pixel style in the 7-pixel letters.
- **The developer console** (` in play, project folder only,
  `dev_console.gd`): spawn, give, god, tp, time, trigger, reload, stats, and
  overlays (`show map`: walls, enemies by state with the hunting ones' paths,
  triggers, lights; `show fps`). `DevConsole.run()` takes the same text from
  scripts. Every command that changes the game is a keyframe in the run's
  replay.
- **Overlays over the view** (`show ai|paths|hits|net|ticks`, each on and off
  by itself, `show off` clears all; `dev_overlays.gd`): drawn on the canvas
  after the game, with points put on screen by the view's own sums
  (`game.view_frame`'s eye and horizon, `game.view.focal`), so they sit on the
  3D view and draw headless too. `ai`: each enemy's kind and state (ASLEEP,
  IDLE, FIGHT, HUNT, LOST, plus WIND, STUN, COVER, FETCH, BRAWL...), its squad
  part (`Squad.Mind`: FLANK, PRESS, FLUSH, SEARCH, an idle activity...), who
  it is after and how long it has seen the player. `paths`: the flow field's
  arrows round the player and the next ten steps of each alerted enemy, its
  `target` marked. `hits`: each body's cylinder with the legs and head lines
  (`HitZones.LEGS_BELOW`, `HEAD_AT`) and the last eight `traced` hitscan
  lines (red on an enemy). `net`: online, the link's bytes a second, input to
  ack (the round trip plus playout), ticks behind the newest snapshot,
  mismatches, the prediction's last gap, the host's last full and delta
  snapshot sizes; read by name, so they tolerate the net code moving on.
  `ticks`: a bar a tick (8 px a ms) and the costliest `ticked` listeners, by
  probes woven between them as `tick_profile.gd` times them (each listener
  connected again in its own order and flags, so play is the same; woven
  again when one joins or leaves; taken out when off), the rest as CORE
  (main.gd times the tick only while it is on). Looks only, and nothing is
  listened to or timed while off; `tune_check.gd` holds both.
- **Live tuning** (`tune ...`, `dev_tune.gd`): `tune set <file> <section>
  <key> <value>` changes the file as read (Godot value text; a whole number
  given for a float stays a float), `tune get <section.key>` finds it in
  every file, `tune reload [file]` reads from disk, `tune save [file]` writes
  the set values into the .cfg (`tune_text.gd`: just those keys' lines, a
  multi-line value whole; comments, order and line endings kept). A saved
  file is read again by itself within a second (`Tuning.changed()`, asked from
  the console's tick). Each change prints `file [section] key: old -> new
  (where)`: `live` for weapons, enemies, shots and effects (their loaders run
  again; enemies in play are scaled by their kind's new hp, speed, radius,
  height over the old, so co-op toughness and variants stay), `live:
  Class.VAR` for a `static var` whose line reads tuning (re-worked out with
  an `Expression` on its script and set; about 400 of them), `level: reload`
  for a level's mood, `restart the game` for a static whose line could not be
  worked out again, `when read` otherwise (some code reads it only at a
  level's start: `reload`). Refused online (`main.net`), the watch too, till
  the match ends. Only the .cfg files; county.json reads itself again.

## Levels in play

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
  rounds, health and pockets (`save_restore.gd _restart`), and a finished
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
  `ship_aliens.gd`, hooked from `enemy_attacks.gd` attack and `enemies.gd`
  hurt and sprite. After the last
  chapter in `Campaign.ORDER`, `finale.gd` draws the true finale (the campaign's
  tally, then the credits). Chapter music not made yet is listed in
  `assets.gd PENDING_MUSIC` (pack_assets and verify_assets note it as pending).
- **Ledges a step won't climb** (more than .245 up) take a jump (about .6);
  the pin and the enemies plan paths without heights, so keep a ramp beside
  any drop on the way. `first_minutes.gd -- <id> whole` hops when stuck and
  shoots a station that is struck (the mill's belt).
- **Ladders and ledges** (v3.2.0, `src/climbing.gd`; numbers in modes.cfg
  `[climbing]`). A ladder is a level's `LevelGeometry.Ladder` (the plan's
  geometry block, `ladders`; drawn as rails and rungs by `ladder_rows`, it
  stops nothing). Walking into its foot facing it puts the player on it
  (`Player.ladder`): FORWARD climbs, BACK goes down (turned away from it the
  other way round), JUMP lets go; over the top they step off onto the floor
  beyond, and walking off that floor's edge at its top takes it down. JUMP
  and FORWARD at a ledge up to `mantle_max` (1.15) over the floor they stood
  or jumped from pulls them up onto it. Both are a timed move
  (`Player.climb_*`, carried online); `game.gd _step_body` leaves out the
  walk, the jump and the fall while one is under way. The nav graph joins a
  ladder's foot and top (`NavGraph.ladder_ends`, `links`; no diagonals
  through it), so the flow fields, the objective pin and the hands go by it,
  and `level_builder.gd _reach_from` counts it. A hand where its flow field
  leads up or down one takes it (`Climbing.hand_takes_ladder`; every
  setting), climbs it at `hand_ladder_speed`, steps off; a hand that walks
  off an edge more than `DROP` (.5) falls (`Enemy.climb_z`, `fall`) and
  lands winded. Plans build the places to climb with
  `tools/levels/climb_kit.gd` from `climbs.gd` ([levels.md](levels.md#places-to-climb)).
- **The objective pin** leads to a station's carried item first while it lies
  somewhere (the fair's PA patch lead). The fair's tin rooster booth is where
  its level puts it (`gallery` in the JSON: the stand; targets 3.58 east).
- **Using things is forgiving, and checked** (`game_use.gd use_target`): a
  quest device (station, exit, note, jukebox, sink, the tin rooster stand)
  answers USE at any of its aim points (its own point and the board that
  lights up for it within 3.5, the slip on a note's table, the jukebox or sink
  itself), within 1.65 and a wider cone than doors, and is seen when the eye
  sees it or the face of the wall, counter or pump it is mounted in
  (`seen_at`: at most .45 back toward the player, so never from the far side
  of a wall). The one nearest the crosshair wins; doors keep their reach and
  cone. Keys and the patch lead are taken within .62, over a counter
  (`reaches_pickup`). `tools/quest_reach.gd` stands the player round every
  quest prop, gate and item in every level and fails when one is hard to use
  or works through a wall: run it after moving a station or its board. A
  station's board should stand on the side it is used from.
- **Wall runs merge when a level loads** (`LevelLoad.merge_runs`,
  level_load.gd): straight runs of one repeating material become one piece. Files keep a
  piece per cell for the editors.
- **Deep water and steering** (dev.45, `src/deep_steer.gd`): a hand that
  cannot swim and sees the player across deep water (no deck) follows the
  flow field; `LevelData.over_deep` is a deck over the water.

### Loading a level

`Game.new` reads the level, builds its nav graph and flow fields and attaches
the features; the engine pass's load track (2026-11-16) made the first visit
to a chapter about twice as fast and changed nothing play sees:

- **The nav graph** (`LevelNav.build_nav`) has the same nodes, edges
  and order as before in about a third of the time: the orthogonal edges are
  gathered as pairs in the order found and laid out once (no list per node
  copied at every append); a cell with only cells round it (no deck or
  ladder in its 3 by 3) takes its diagonals from each cell's step masks (its
  neighbours are always N, W, E, S in that order, so the slow walk's order
  is NW, NE, SW, SE); `_walks` keeps what it asked at each point on a
  sixteenth of a cell by the exact feet height, so the walk back asks nothing
  again.
- **The level read** takes the grids as packed arrays natively, the walls row
  by row, the plane bounds a row's run of one height at a time, and joins the
  wall runs' keys once a piece (as text, as before).
- **Fences** (`wall_breaks.gd`) ask only the boards, props and volumes in the
  cells round each fence, not all of them; the grit (the old canvas's look,
  `ScreenLook.build_grit`) is made once a wash; a level played again keeps its
  flow field's open floor (`FlowField._opens`) as it keeps its nav graph.
- **The wreck pieces** are cut in the level's first frames, a model's on a
  worker (`WreckCuts.prepare`/`pump`, below), not while it loads.

`tools/load_check.gd` holds every level to the old code kept in
`tools/load_reference.gd` (the nav graph, the grids and walls, the plane
bounds) and the worker's cuts to cuts made at once. Since pass 14 a shipped
level's graph and its breakables' pieces are baked at pack time and read
back while their key holds, anything else built as here
([levels.md](levels.md#the-bakes-pass-14), `tools/prebake_check.gd`).
`tools/load_bench.gd` measures it ([checks.md](checks.md#benchmarks)).

## Enemies

- **Enemies path on a flow field** (`src/flow_field.gd`): out of sight, an
  alerted enemy walks downhill on the steps from the player for a few seconds
  (`Enemy.hunt_until`). The objective pin walks a second field measured from
  the objective (`Game.route`) through doors the player can open now. That one
  walks the whole level (5 to 10 ms), so it has a `budget` (1500 cells a
  tick): a new walk (a door opened, a key, something broken, the boss moving a
  cell) finishes over a few frames while the last answer stands; the first
  walk is always whole. A level with geometry walks its nav graph
  (`LevelGeometry.nav`, about a tenth of a second to build on the desktop
  since the load pass, see "Loading a level"); the graph of a level as read
  from its file (nothing opened yet, keyed by `LevelData.source_key`, the
  file's name, length and hash) is kept for the next game on that level
  (`NAVS_KEPT` 4 levels): a retry, a load, the next match. It is only read
  once built. The flow field's open floor of a level as read is kept the
  same way (`FlowField.OPENS_KEPT`), as a copy each way: a packed array in a
  Variant is shared, and `reopen` writes a game's own. Stutters: `first_minutes.gd -- whole hitches` times
  every tick of a bot's playthrough; `--play-bench=<seconds>` has the same bot
  (`tools/bot_pilot.gd`) play each chapter in a real window and prints the
  slowest frames with the tick's and the draw's share.
- **The county's hands fight smart** (`enemies.gd`, `hand_tactics.gd`): a
  hurt hand may duck behind cover the player cannot see (`find_cover`), a badly hurt one runs to
  fetch a friend, and a stray shot from another hand starts a brawl (`hurt(...,
  by)` sets a grudge). `hurt()` also takes the gun's name (`how`): the REACTIONS
  table throws back, stuns, soaks (teat gun) or gibs by gun. A boss goes
  fightin' mad at half health (`_enrage`, `boss_enraged`: phase two) and gets a
  death moment (`_boss_falls`). DIFFICULTY runs EASY..HOG WILD (0..3):
  `game_world.gd configure()` sets `sharpness` (attack recovery, notice range,
  aim) and `ammo_scale` (numbers in `data/tuning/difficulty.cfg`), and
  `features/posse.gd` adds partners on HARD and HOG WILD after the level's own
  enemies (saved in the features block, so a save checks its count against
  `enemy_ids.size()`). Set `alerted` by assignment: its setter counts changes,
  which `player_sheltered()` relies on.

### Hits land somewhere

`src/hit_zones.gd` is the play; `features/hit_reads.gd` the looks and sounds;
numbers in `data/tuning/hits.cfg` (`HitData`). Every player hit with a
`game.hit_point` (hitscan, pellets, swings, blades, balls, pierced rounds) gets
`Enemy.last_zone` from the body's height and how far off its middle: head
(`HEAD` by gun: x2 a round, x1.35 a pellet), arms x.82 (a held weapon dropped
on `game.rng` .4, fetched while it fights with its fists: `HitZones.tick` in
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

**Critters with physics** (after v3.1.0, track H; all play, the feature's
carried `dice`, never `game.rng`; at most `ACTIVE_MOST` bodies flying or
falling, nothing moves that was not set off):

- A scared chicken flaps up and **glides** off (`_glides`: its run in the air,
  the fall slowed by `GLIDE_FALL`, stopped by a wall).
- A hog **charges** when hurt and, `SPOOK_CHARGE` of the time, when a shot or a
  runner spooks it; its butt **knocks the player flat** (`Player.knocked`:
  `KNOCKED` seconds with no walk or jump, the eye at .3 and the horizon up,
  `game.gd _step_body`). `_charging` keeps the player's slot, never the acting
  player.
- A cow or the mule stands still for a player within `PLACID` (no shying),
  so a cow can be walked up to and the mule's rump stays put.
- The **mule** (enemies.cfg `[mule]`) kicks whoever stands within
  `KICK_REACH` behind it (its rump to them: `Enemy.angle`): a wind-up showing
  `mule_kick` (`Enemy.held_cel`), then `MULE_KICK` and a knockdown.
- A **cow** (`[cow]`) tips at USE beside her (`critters.tip`, called from
  `game_use.gd interact()` before the use targets): a rigid fall about her
  hooves (`TIP_PULL` times the sine of her lean, one bounce), lying `TIPPED_FOR`
  seconds on her `cow_down` cel (`Enemy.squash`, `Enemy.DOWN_SHARE`), then up.
- Their cels: `scripts/blender/actors_farm.py` (cels only, like the chicken
  and hogs; `build_enemy_actors.gd -- kinds=cow,mule`). Two cows and the mule
  graze hickston's orchard (layout 5). The mule brays (`mule_bray`, made in
  `assets.gd`).
- `tools/climate_check.gd` (in check_fixes) plays each; `tools/climate_frames.gd`
  (a window) pictures them.

### Hits that land hard (pass 15, PUNCH)

Ideas 11, 12 and 20 of the pass (numbers in hits.cfg `[punch]` and
`[finisher]`; `tools/punch_check.gd`):

- **The hold by closeness and weight** (`game_world.gd struck`, play, alone
  only as before): a kill holds the world `kill_hold` (.05 s), a boss's
  `boss_hold`, a hit of `heavy_hit` (40) or more `hit_hold`; a kill within
  `close_reach` (3 cells) by an instant's load (`struck_sum`) of `heavy_from`
  (60) holds `close_hold` (.07), the sawed-off within `point_blank` (1.0)
  `sawed_hold` (.09), at most every `hold_gap`. That close kill kicks the
  view (`feel.punch`, `kill_kick` of a blow's jolt, scaled by SCREEN SHAKE).
  `struck()` now takes the one struck and the gun.
- **Every hit reads**: the flinch's floor is `flinch_floor` (.18, was .14).
- **The head ding** (`features/hit_reads.gd`): every head hit of the local
  player rings `head_ding` (a tin sign struck, a made cue in `assets.gd`;
  once a load of buckshot; not with HIT FEEDBACK off; `dings()` counts); a
  head kill draws a red splat ring round the crosshair for `SPLAT_FOR` (.2 s,
  `game_view.gd _splat_ring`, from the kill and head marks: no new field).
  HEADSHOT! stays rare (`CALL_GAP`).
- **Overkill**: the sawed-off within `point_blank` (1 cell) always takes the
  body apart (`HitZones.overkill`, one barrel too; from there to
  corpses.gd's `POINT_BLANK` one barrel still throws him, into a window); a body taken apart throws
  `gib_more` more chunks a share of the excess over the overkill line, each
  `gib_grow` bigger and faster, up to `gib_most` times (`Gore.excess`, gore's
  own dice).
- **The slow motion** (`features/finishers.gd`): only after a fight of
  `fight_least` (3) kills or more (`fight_kills`, the hands' kills since the
  last kill that left nobody fighting), `peak_length` (.8 s) when the kill
  ends the director's peak (`Finishers.peak_end`: its peak's hands all down,
  or its breather begun this tick).
- **Shoves by distance**: the shoves (the `[reaction]` shove, the reel, a hit
  of 20 or more) are `shove_near` times within `close_reach`, eased to
  `shove_far` at `shove_far_from` (`HitZones.shove_by`), and become a stagger
  (below).

**The stagger** (`src/stagger.gd`, play's half of the living bodies): a
hit's shove of d cells is an impulse on the man's middle of d times the
pendulum's rate times `push` (so a step to where it says stops him), divided
by his heft (`heft`: girth squared against `heft_radius`'s). He is then a
linear inverted pendulum (the middle `com_at` of his height up, gravity 9.4)
on the foot he stands on: the ankle moves the centre of pressure within
`ankle` of it; when the capture point (the middle plus its speed over the
rate) is further off, he swings a foot (`first_swing`, then `swing`
seconds) and puts it down where the capture point is then, no further than
`reach` of his height from his middle (`first_share` of it for the first,
hurried step; `buckled` of it for `buckle_time` after a leg hit). He stays
up if the steps catch it; after `steps_most` steps still going, or a capture
point more than `fall_past` reaches off, he goes down: onto a knee
(`knee_for`) on a buckled leg, else pitched over (`pitch_for`), then gets up
(`rise`). A man hit on the move keeps `run_keep` of his run; a hit while
reeling adds (staggers stack); walls stop the middle (`move_actor`, what
moved is the speed kept). Stunned while it lasts. All of it is one note on
the enemy (`Enemy.notes["stagger"]`, `Stagger.KEY`: the stance foot, the
speed, the swing, steps, down, buckle, the last impulse, its height and how
far off the middle it struck): carried and saved like any note (an older
peer or save simply has none; PROTOCOL stays 5), arithmetic only, no dice
(game.rng is untouched, so the rest plays as before). It is copied before
it changes (a snapshot put on another game may share the array). Bosses
(their own `BossKit.stagger`), floaters (`steady`) and climbers do not
stagger. `stagger=false` brings the old instant jumps back. Measured
(`live_body_check -- print`, a billy on open floor): a .38 from 6 cells
reels .14 cells in one catch step, from 2.5 cells .33 in one, a load of
buckshot at 1.4 cells .91 in two, both barrels at a cell put him down; a
hit on the run carries him .29 toward the gun.

### Living bodies (pass 15, the active bodies' step one)

How a living hand takes a hit is physics, not a clip (`src/live_body.gd`,
`LiveBody` under `Ragdoll`; looks only). The 3D view's `ActorView` starts
one when a hand it shows is hit (`_live_begin`, from the pose last drawn)
and the layer's budget allows (`ActorLayer3D._live_ones`: the nearest
`live_most`, 4, of those just hit or reeling; `live_phone`, 2, on a phone or
the LOW physics tier; RAGDOLLS off: none, the old rigid flinch). Every frame
the animation is sought as ever and its pose becomes the target
(`RagdollRig.posed_points`, `aim`), the body is stepped and the bones posed
from its balls (`RagdollRig.pose`); done, it hands back to the animation
eased over `LIVE_EASE` (.18 s).

- **The body** is the dead ragdoll's rig: fifteen balls with their weights,
  the rigid torso and limb halves, the joint ranges, knees that bend only
  forward, gravity, the floor (each ball on play's floor; a foot at the
  height the pose stands it), Verlet steps of 1/60 s, four passes and two
  more after the feet and the floor.
- **The muscles** are springs pulling each ball toward the pose as it stands
  to the torso, and pulling its chain parent back by as much (so no muscle
  moves the body as a whole); stiffness `live_tone`, soft the instant a hit
  lands (down to `live_soft` for a hit of `live_soft_full` and more) and
  back over `live_recover`, then `live_settle` times as stiff as it pulls
  itself together; no muscle pulls harder than `live_muscle_most` a pass and
  no ball goes faster than `live_speed_most`. With the muscles off
  (`muscles`) the body falls in a heap.
- **Standing** is the feet planted where they stand (gripped; dragged along
  the floor only when the hips pull past the leg), the stance legs' push
  holding the hips at the pose's height (`live_support`, at most `live_rise`
  a pass; each hip by its own leg, the torso rolled whole), and the ankle's
  turn of the torso toward the pose's (`live_upright`, at most
  `live_upright_most` a pass, only with a foot on the floor). Play's middle
  pulls the hips along (`live_carry`): a blow above them turns the body
  about them.
- **Catch steps** come from its own balance controller: the capture point
  (the middle plus its speed over the pendulum's rate, `Stagger.rate`)
  further than `live_margin` from where the pose stands its middle over its
  feet swings a foot (the other one than the last) on an arc (`live_swing`
  seconds, `live_lift` high) to put the feet's middle under it, within the
  leg's reach; it plants where it comes down (`catches`, `step_log`). Back
  on his feet a foot off its place in the pose steps back to it once, then
  the feet go with the pose.
- **A hit** (`hit`) is an impulse at the point struck (play's note: the
  impulse's way and strength, its height, how far off the middle;
  `live_strike` of it, `live_head` more on the head, `live_arm` more on a
  shoulder); the hips' share of it is play's (taken back), the rest turns
  him. A hand that can bend (not `RagdollRig.stiff`) goes to a wound on the
  chest, belly or a shoulder and holds it `live_clutch` seconds (`_reach`,
  `live_clutch_pull`; that arm's own muscles let go meanwhile); a shoulder
  hit leaves that arm limp; a leg hit buckles that knee (`live_buckle` of
  the size folded forward and down, `live_buckle_give` of that leg's hold),
  the knee knocked forward. Down (play's note): the legs give
  (`live_down_legs`), the ankle holds `live_down_upright`, the buckled knee
  (both pitched over) goes to the floor (`live_down_knee`); getting up the
  legs take his weight back a little at a time.
- **Online**: play's note is carried, each screen runs its own body with
  its own dice (a hash of the hand and the hit); nothing in it writes play
  (`live_body_check`: play the same to the bit with bodies stepped beside it).
- **Rigs whose limbs are one piece** (`RagdollRig.stiff`: billy's arms and
  legs, the tin guard's arms) bend nowhere there: such a hand clutches with
  the other arm or not at all, such a knee does not fold.
- **Pictures**: `tools/live_frames.gd` (a window) draws motion strips of
  hands taking hits (a chest, a leg, the head, an arm, on the run, two
  stacked, buckshot, knocked down), fifteen moments each.

**Extension points for the later steps (T11: falls with intent, writhing
and crawling, shoves and balance, the drunk stagger).** All on `LiveBody`,
set each frame before `advance`:

| | what it is |
| --- | --- |
| `tone[TORSO/ARMS/LEGS/HEAD_GROUP]` | each group's share of the muscles' stiffness (1 as now): slack when dying, tensed to brace |
| `upright` | the ankle's turn's share (0: he cannot right himself) |
| `muscles` | false: no muscles, ankle or support at all (a ragdoll) |
| `aim_override[i]` | a world target for ball i that wins over the pose (`Vector3.INF`: none): arms out to brace toward a predicted impact, a hand to a rail |
| `pin(i, at)` / `unpin(i)` | ball i held to a world point (a grab constraint: release it by force or time) |
| `push_at(at, dir, strength)` | an impulse at a point (a boot, a blast, a car) |
| `on_floor(i)` | whether ball i touches the floor |
| `planted[f]`, `swing_foot`, `catches`, `step_log` | the feet's state and the steps taken |
| `play_says(reeling, down, pitched)` | play's word each frame; a new play state (a shove, a fall) goes in the stagger note and is read here |

### Active bodies (pass 15, T11: the active bodies' steps two and three)

Falling with intent, not dying at once, shoves and balance, the drunk's
walk, weight. Everything is simulated on the rig above: a behaviour only
says where a limb tries to go and how hard (a target and a tone) or holds a
ball to a point (a pin); masses, links, joint stops, gravity and contacts do
the rest. No clip is played. Play decides where a man goes, whether he goes
down and for how long (`src/body_play.gd`, carried); the limbs' physics is
looks on each screen with its own dice.

**Play's say (`BodyPlay`, hits.cfg `[bodies]`; `play=false` turns it off).**
Arithmetic on play's numbers and the level only, no dice (game.rng untouched),
one note on the enemy (`BodyPlay.KEY`, `[mode, x, y, z, since, until]`,
carried and saved like any note) for what the looks must know:

- **Holding on.** A reel the catch steps cannot stop (Stagger.tick, where he
  would go down) next to an edge within `grab_reach` of his height
  (`BodyPlay.edge`: a point in a rail, fence, furniture, crate or car with
  open air over it, between `grab_low` and `grab_high` of him, looked for
  round the way he goes): he stays up, stunned `grab_hold`; the note keeps
  the point (mode HOLDING) so every screen puts his hand on the same spot.
- **Over a low rail.** Moving faster than `over_speed` and stopped by a rail
  between `over_low` cells and `over_high` of his height (Stagger._move, a
  boot's slide in features/brawl.gd): he is put on the far side if he fits
  there (no more than `over_drop` down; off a loft he falls the rest,
  Climbing) and is down `over_down` times as long as pitched over (mode
  OVER, the bar's point). Gently pushed into it he stays on his side.
- **Slammed.** A boot's slide stopped by a wall faster than `[kick]
  slam_least` puts him down (`slam_down`), as well as the slam's damage.
- **Run into** by a vehicle and left up (features/vehicles.gd `_run_over`):
  knocked flat (`ram_down`), sliding on at `ram_share` of its speed.
- **The drunk's lurch.** A drunk (Variants.STUMBLE, the drunk coot) walking
  lurches across his way every `lurch_gait` of gait (his weave's side),
  `lurch` cells, every `lurch_big`-th `lurch_big_k` times that: a shove for
  the stagger's pendulum, which catches it with steps or puts him down.

**The living body (`src/active_body.gd`, `ActiveBody` under `LiveBody`).**
ActorView runs one for a hand just hit (as before), a drunk near the eye
(`active_drunk_reach`, a player's stand-in on shine past `ActorView.SHINE`
too) within the live budget. Numbers: effects.cfg `[ragdoll] active_*`.

- **The world.** Each ball stands on the floor really under it
  (Tumble.floor_at: a tread, a deck, a ramp) and keeps out of walls, slabs'
  sides and rails (Ragdoll._walls with play's body as the side that is his;
  a ball that went through a thin rail within a step is put back where it met
  it, and a lift onto a bar or a tread gives no speed). A foot is put down on
  the tread under it. Falls are gravity's (`LiveBody.FALL_MOST`, the old
  speed cap holds only across and up).
- **Bracing.** Going over (play's down, pitched, or the torso tipping past
  `active_tip`): the arms swing toward where the shoulders will come down
  (ahead of them by half their height), `active_brace` stiff; the head is
  held off the fall (`active_head_guard`); the ankle lets him go over
  (`active_brace_upright`). A hand reaching the floor is pinned there for
  `active_brace_hold` and the arms then give. `braced_at`, `landed_at`.
- **Getting up** (play's down running out, pitched): the hands go to the
  floor under the shoulders and are pinned there, the arms stiff
  (`active_rise_tone`), pushing him up while the legs take his weight; a hand
  pushed past its reach lets go.
- **Windmilling.** Reeling faster than `active_mill_from`: the arms go round
  in the body's plane the way he goes (`active_mill_rate` turns a second,
  `active_mill_tone`).
- **Shoved** (stunned and moving faster than `active_shoved_from`, a boot's
  slide): reeling; the planted boots skid with play's move (`skid`) so he
  slides back on his heels and steps, not does the splits.
- **Grabbing.** Reeling by an edge (play's HOLDING point, else the looks' own
  `BodyPlay.edge` every .1 s): the near hand reaches and is pinned there;
  let go after `active_grab_hold` (or when play's hold ends), or by force when
  the arm is pulled past `active_grab_force` of its length. `grab_log`.
- **Over a rail.** Play's body jumping across (more than `JUMP` in a frame)
  is carried over `JUMP_FOR`, the feet let go; the bar found on the way turns
  him over it (an impulse to clear it and a spin about it, `OVER_SPIN`), a
  ball left lying on the bar rolls off on the far side; play's body falling
  (Climbing) drops the torso with it.
- **Drunk** (`drunk`): always reeling, so the feet are put down only by the
  balance controller, which looks late (`active_drunk_late`) and steps too
  far (`active_drunk_over` past the capture point, `active_drunk_noise`
  off); arms out, the ankle weak (`active_drunk_upright`), a sway now and then
  from his own dice (`active_drunk_sway`).
- `acts` false: no behaviour sets anything (LiveBody's muscles alone, the
  checks); `muscles` false: a ragdoll.

**The dying body (`src/dying_doll.gd`, `DyingDoll` under `Ragdoll`).** A
hand killed within the live budget dies with muscles still in him (the rest
keep the plain ragdoll); play's body (features/corpses.gd) is where he lies.
Each muscle pulls a limb ball toward a place from its chain parent in the
torso's frame (and the parent back), stiffness the tone `env` times the
group's share. Numbers: `[ragdoll] dying_*`.

- **Going slack:** the muscles hold the pose he was hit in, fading over
  `dying_slack` (a head shot `dying_head`), the legs going first
  (`dying_legs`). A live body's balls go on at their own speeds into it.
- **Half catching himself:** on the way down the arms swing toward where the
  chest lands and the head is held off it, as strong as the tone left; once a
  hand is down they give over `dying_brace_give`.
- **On the ground** (its own dice, `dying_styles` [limp, writhe, get up,
  crawl], a hit below the head and not a blast): writhing (knees drawn up and
  let go, a hand on the wound, the head up, rocking off the floor), trying to
  get up (face down: hands under the shoulders gripping the floor, the arms
  pushing, knees drawn, then the tone goes; again), or crawling (face down: a
  hand reaches ahead, grips, the arm pulls him on to it, then the other; play's
  body's slack `slack` is wider for it), for `dying_writhe`, then slack over
  `dying_slack_end`. Face up, a get-up or a crawl writhes instead.
- **Run down** (killed_by "roadkill"): the vehicle's front a moving box for
  `dying_hood`'s seconds (height, length, width in shares of him): the legs
  swept by its face, the rest falling back onto its top and carried a share.
- `muscles` false (out of the budget, the checks): the plain ragdoll.
  `DyingDoll.force_style` makes every one take a style (the motion strips).

**Budget.** `ActorLayer3D._live_ones`: those just hit, reeling, running a
live body, a drunk near, a body just killed or still dying, the nearest
`live_most` (4; `live_phone`, 2, on a phone or the LOW tier). A dying body
that loses its place goes limp.

**Online.** Play's notes are carried; each screen runs its own bodies with
its own dice (hashes of the hand, the hit, the death). `active_body_check`
holds play to the bit with the bodies stepped beside it.

**Pictures.** `tools/active_frames.gd` (a window, scratch APPDATA): caught,
rail, steps, brace, grab, writhe, crawl, get_up, slack, car, car_flat,
drunk, fifteen moments each.

### Squads, idle life and variants

New code lives outside `enemies.gd`, which only has small hooks: `mind`,
`Squad.watch/calm/move/startled`, `IdleLife.notice/frame`,
`Variants.attack/stem/look/wobble`. Numbers for squads and idle life are in
`data/tuning/modes.cfg`.

- A hand (`Squad.hand`: tactical, turn cels, not a swimmer) gets a
  `Squad.Mind` from `features/squad_feature.gd` on the first tick.
- **Idle life.** Before it notices anything it does an activity picked from
  the props, boards and scenery within 2.6 of its place in the level
  (`idle_life.gd BY_THINGS`; no plan changes), faces the thing, loops its
  fidget/recover/aim cels and notices less (`NOTICE`, less so the harder it
  is); woken it fumbles (`startled`), hit from behind unaware it is stunned
  (`SNEAK_STUN`, no extra damage).
- **Hearing.** A shot is heard through walls out to `SHOT_NOISE` x `HEARING`:
  unaware hands come to look.
- **Squads.** Every .4 s the alerted hands within 18 are a squad: a flanker
  goes round the player along the flow field's rings (`_flank_step`), one
  presses in while another shoots, a lobbed bottle or (HARD+, outdoors) a
  stick of dynamite flushes a player unseen for 2.5 s (wind-up, warning mark;
  enemy dynamite is in `dangers` too), and two or three losses make them fall
  back on the farthest. A hunt that runs out becomes a search of the
  last-seen spot (`SEARCH` s), then `alerted` goes off. EASY does none of the
  squad moves. No new sight lines but the flush's one; dice from `game.rng`;
  nothing saved.
- **Smarter hands** (v3.2.0, `src/hand_tactics.gd`; setting HANDS: SMART,
  the default, or CLASSIC; `game.smart_hands`, a SIM field, a lobby's sim
  option). One hook in `Enemy.tick` (`HandTactics.step`, before it attacks
  or chases) and two one-line ones (`take_cover` asks `HandTactics.cover`, the
  duck after a shot asks `HandTactics.duck`). On NORMAL and up with SMART:
  cover is a spot hidden from the player right behind something solid where
  one is near (else Enemy.find_cover's kind); a ranged hand ducks after a shot
  more often (`duck_chance`), reloads after `magazine` shots (`[hand_tactics]
  reload`, a `reload` cue) and ducks to do it; in cover and ready it steps out
  to the side where it sees the player (`peek_wait`, `peek_out`), fires, and
  goes back to the same spot (`Mind.cover_home`); a closed door between it and
  where it last saw the player, within 1.4, it kicks open (`kick_doors`; not
  a locked, secret, powder, remote door or a hatch: `toggle_door`); up a roof
  or a loft over the player, close, with the way down long (or a brawler who
  sees them), it walks off the edge toward them (`drop_max`). EASY and
  CLASSIC fight as before but for ladders (or a roof would be a safe spot).
  Numbers by difficulty in difficulty.cfg `[hands]`. Dice only from
  `game.rng` (the classic duck's roll is the same one roll); the Mind holds
  it, nothing saved. Flipping tables and knocking crates over for cover is not
  done (a prop's model and box would have to change in play).
- **Barks** for voices: `game.enemy_bark(e, moment)` (spot, lost, search,
  help, flank, cover, brawl, idle, surprised, hurt_bad, regroup), throttled
  per hand (3.5 s), per moment (`MOMENT_GAP`) and overall (.7 s).
- **Variants** are enemies.cfg sections (`src/variants.gd` lists the keys):
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
  (`made_car_door`).
- **Variant art:** `art="billy"` draws a variant with its regular's pictures
  until `<kind>_0` is in the art index, so dropping in `big_billy_*` (and
  `drunk_coot_*`, `shield_deputy_*`) with every cel the regular has and
  running `pack_assets` just works; then delete the `art` line, and
  `door_picture` too if the deputy's art carries the door.
- **Checks.** `tools/squad_check.gd` (in check_fixes) holds it;
  `tools/squad_frames.gd` takes window pictures; `first_minutes.gd --
  diff=<0..3>` plays a difficulty and prints the damage taken. The bot
  (`bot_pilot.gd`) steps back onto the route from a nook it does not cover and
  backs off a last threat it is pressed against but cannot see (Boggs wedged
  in a gap).

### CHATTER, the cuss pack

Setting `chatter`: OFF 0, CLEAN 1, CUSSIN' 2, the owner's default;
`game.chatter`, a VIEW field; `src/cuss_lines.gd`.

- `data/tuning/cuss_lines.json` is the one list (the voice tools read it too):
  original crude lines, never slurs, hate, sex or real people, the cuss words
  *starred*. The hands mix them with their old barks (`enemy_barks.gd`,
  `CUSS_SHARE`).
- Mundell speaks in his own voice (ElevenLabs "mundell", every line at the
  same settings): all his wisecracks (`data/tuning/mundell_lines.json`, cues
  `mundell_<moment>_<n>`, the same words as `Barks.LINES` in capitals;
  chatter_check holds them together) mixed with his cuss lines
  (`Barks._spoken`/`_speak`, `CUSS_SHARE`), and new moments: a boss fight's
  start and end (`boss_intro`/`boss_down` through enemy_barks), a station
  done, a key, a headshot (`Barks.kill(game, head)`), a chapter's start; with
  CHATTER OFF his wisecracks are on screen only, as before.
- In the 5v5/2v2 the bots crow over kills, a bad hit, the plant, the defuse
  and a round won (`enemy_barks.gd _tactical`, a looks feature: a bot is a
  player this machine does not drive and the lobby did not name).
- CLEAN plays each line's `_clean` copy, built by `audio_build.py` (spec
  `how="bleep"`) from the transcript's word times with a duck call or a horn
  over each starred word, and captions them as #@!%. A lobby's CHATTER row
  caps every player's (`main_flow.gd net_match_game`).
- The transcript check reads the county's spellings (`audio_build.py
  DIALECT`, `canon`); `CUSS_HEARD` where it hears a clear line sideways. A cue
  not made yet is simply not said.
- `tools/chatter_check.gd` (in check_fixes) holds it with an ear that has
  every cue. 128 cuss lines and 67 of Mundell's, about 4,600 credits with
  retakes and his voice. Pass 7 added the working men's voice (local: the
  mill, quarry, fish camp and pit hands, 22 lines and 22 cuss lines), more
  lines for every other voice's moments, Mundell's 9 and each chapter's tough
  guy's own line; and turns: nobody talks over a line still playing
  ([audio.md](audio.md#voices)).
- The county radio (content pass 8, `features/radio.gd`, a looks feature):
  KPSM's DJ between the songs and the police scanner react to what Mundell
  does (a blast, a boss down, a car burnt out, a run of kills, drunk, a
  secret, deaths; shots fired and a deputy down for the scanner); its own
  RADIO setting, its crude lines follow CHATTER
  ([audio.md](audio.md#the-county-radio-content-pass-8)).

## Things break

### Breakables and loose things

`features/breakables.gd`, `features/corpses.gd`, `gore.gd`, `tumble.gd`.
`data/tuning/breakables.cfg` names each picture that breaks (a board's image
or `prop_<name>`), its broken picture (props: `scripts/blender/props_broken.py`
through `build_town_props.gd`; signs' `<name>_shot` and the bits `fx_brk_*`:
`tools/art/build_break_art.gd`), hp, bits, cues and, for explosives, the blast
(`shots.cfg`) it sets off a moment later, which can set off the next (chain).

- Quest props, signal or glowing boards, anything on furniture it shares with
  something whole, and anything whose base alone parts two stretches of floor
  never break; a broken piece's base leaves `collision_volumes`
  (`LevelData.drop_volume`) and its cells reopen for both flow fields
  (`FlowField.reopen`).
- game_combat.gd asks it first in `hitscan`, `_hits` and `explode`
  (`_blast_shoves` also throws gibs, bodies, bits, loose barrels and rolling
  shots).
- `tumble.gd` is the one stepper for gibs, bits, bodies, the player's dynamite
  and bowling balls (walls axis by axis, ledges, furniture tops, slopes from
  the floor sampled .45 each way, drag). Bodies take a knock from
  `Enemy.killed_by`/`killed_from` (an overkill still gibs); their place is the
  enemy's saved x, y.
- **The bits are looks** (pass 12): what flies and lies about of a broken
  thing (`bits`, thrown and shoved by the feature's own `dice`) is never
  carried in a snapshot (`SnapCodec.SKIP_FIELDS`), and a snapshot's facts of
  the breakables (`net_facts()`) leave out the bits and the fuses (carried in
  the feature's block): every delta online sent all of them while anything
  flew or cooked (5 to 40 KB raw a delta while things broke). Each machine
  throws its own; a save still keeps them.
- Breakables save in the features block. Sounds wanted for them:
  `docs/physics_audio.md`. `tools/break_check.gd` (in check_fixes) and
  `tools/physics_frames.gd` (window pictures of each effect) cover it.

### Loose things on the real 3D shape (v3.0.0 remaster)

The 3D world has decks, stair slabs, ramps, ceilings and deck undersides
(`LevelGeometry`), and everything loose now keys off them, not the cell
ground (`LevelData.elevation()` is only the ground under a deck: never use it
for something that can be up on one; use `floor_under(x, y, z)` or
`Tumble.floor_at(world, x, y, z, r)`, which adds furniture tops).

- **`tumble.gd`** (shared by play and looks): the floor and the roof are
  looked for from where a body was *before* the step's fall or rise (a fast
  drop never sinks through a deck or a counter top, a fast rise never comes up
  through an underside: `roof_over`, not the cell's roof); the landing floor
  is the highest under any part of the body's radius (a gib against a crate's
  side or a deck's edge sits on it, never half inside); `slope(world, x, y, z)`
  is the walkable slab's own slope under the body (a flat deck over sloping
  ground pulls nothing; a ramp pulls down its fall), the cells' steps only on
  the ground; down a slope a grounded body keeps to it instead of hopping; a
  roof stops the body's top, not its middle; a body almost still holds while
  the pull is at most `HOLD` (1.15) times its drag, so nothing creeps down a
  gentle ramp for ever without resting. `Tumble.unsupported()` tells a resting
  body whose support was broken away (gore, debris and breakables ask one a
  tick; corpses ask each lifted body once a second, `_look_for_unheld`).
  `Tumble.lay(world, mark, from_z)` puts a ground mark on the floor under it
  (deck, stair, counter, ground) and tilts it with a ramp (`GroundMark.gx/gy`,
  drawn tilted by `sprite_layer.gd show_marks`).
- **Play is changed, the same everywhere.** Corpses, breakables' bits, hit
  reads' dropped guns and the player's dynamite and bowling balls are play
  (SIM_FEATURES, game.rng-free arithmetic): their paths differ from dev.45's
  where the shape matters (decks, ramps, ceilings, furniture edges) but stay
  identical across machines (`net_check`). Nothing new is carried or saved
  (breakables picks its resting bit to ask by `game.clock`, not a counter).
- **Looks**: brass and hulls (`features/debris.gd`) are tumble bodies now
  (effects.cfg `[debris] case_*`/`hull_*` bounce, wall, drag): they land on
  the loft they were dumped on, tink and bounce lower, glance off walls, roll
  and slide down ramps; embers and smoke stop at floors and ceilings; scorches,
  blood drops, pools, streaks, oil, boot prints, pocks, enemy shadows and milk
  puddles lie on the surface they were over; wall splats and blood runs count
  up from the floor under them (a loft's), not from 0; specks die on the
  floor under them instead of sinking to z 0; `weapon_fx` chips test walls at
  their own height and land on decks.
- **Spin**: `View.Sprite.spin` turns a billboard about its middle in the
  view's plane, in 32 steps (packed into the flags word: flags + 256 x hurt +
  65536 x step; `sprite_body.gdshaderinc` lifts it so no corner dips under
  its floor). Gibs keep `spin`/`spin_rate` (fast for small ones, most of it
  lost at each bounce, turning with the run on the ground, kept at rest);
  brass flips end over end and rolls on its side; breakables' and weapon_fx
  chips and hit_reads' hats and dropped guns work theirs out from where they
  are (play's bits carry nothing new). The 3D view draws all of these as
  slabs that tumble in 3D from that spin and settle onto the floor
  (`View.Sprite.lying` and `settle`, set by each feature; see "Physics
  polish" below and
  [view3d.md](view3d.md#slabs-pickups-loose-things-range-targets)). The
  firing range's targets lean by `View.Sprite.tilt` (range_targets.gd).
- **The eye**: `feel.gd _plant` drops the 3D eye up to `STEP_DROP` (.018) as
  each boot comes down (sharp at the footfall, nothing in the air, standing
  or with VIEW BOB off), on top of the old horizon bob; the landing dip is as
  before. Movement numbers are untouched.
- `tools/physics_check.gd` (in check_all, quick too) drops a gib, an eye, a
  casing, a chunk and a body on decks, ramps and stair slabs of six levels
  (slow and fast), flings them up under decks, throws them at walls, and
  checks they rest on a surface within .03, never inside anything; then the
  features on hickston's hay loft (brass, scorch, a burst's gibs and blood, a
  chunk left over nothing, a thrown body, the same throw twice).
  `tools/physics_frames.gd -- only=loft` pictures it in a window.

### Ragdolls and finishing shots (v3.2.0)

- **Where a body lies is play** (`features/corpses.gd`, as before): the kill
  throws it (`_throw`), tumble.gd moves it. New: a rail (a geometry segment
  with `sight` false, which tumble.gd lets loose things through) stops a
  thrown body (`_rails`), unless it comes faster than `OVER_SPEED` and the
  rail's top is under `OVER_TOP` over it: then it tips over, slowed and
  lifted, off the loft or walkway. A body come to rest with its middle over
  a drop of more than `EDGE_DROP` (held only by a lip) is pushed off it
  (`_off_edge`, at most `EDGE_TRIES` times). Arithmetic only: `net_check`
  holds it.
- **How it flops is looks** (`src/ragdoll.gd`, driven by the 3D view's
  `ActorView`, its own dice): fifteen balls (`view3d/ragdoll_rig.gd`: hips,
  shoulders, belly, back, head, elbows, hands, knees, feet) held by links
  (the torso rigid, each limb half a stick, knees fold only forwards,
  ranges for the neck and hips, no limb in the torso), Verlet steps of
  1/60 s, four passes, friction on the floor, asleep (no
  steps at all) once still for `SLEEP_AFTER` (or a wreck piece near it
  stirs). The level's questions are the shared core's (`PhysCore`: plain
  floor, walls, rails, each ball's floor kept in `Floors`), and it lies on
  wreck pieces as on another body. The world is tumble.gd's: each
  ball on the highest floor under it (`Tumble.floor_at`: decks, treads,
  ramps, counters), under roofs, never into a wall, a slab's side or a rail
  (a rail play's body went over lifts the ball over its bar; a ball come
  down on a bar rolls off on the body's side). Open floor with nothing near
  (`_plain`) skips the wall tests. It follows play's body: that body's move
  is given to every ball each step (and not kept as their speed), the torso
  is pulled back within `SLACK` of it, and while the body is up (thrown,
  floating) the torso is carried at its height. The kill strikes it where the
  hit landed (pass 11, below). `budget` caps every ragdoll's steps in a frame.
- **Which bodies**: every kind whose labelled parts stand on two legs gets a
  rig (`RagdollRig.ok`); since pass 13 the beasts too (the gator, the
  crawler, the herd's hogs, the cow: a `BeastRig`, below) and the bosses on
  two legs from part way through their scripted falls (below). The derby
  champ's truck, the swamp king's boat and Maw keep their scripted falls
  (their bodies at rest are cels of their own, fit.json `down_cel`), and so
  do the floating kinds (lanterns, probes; saucers and skeeters leave no
  body) and the hound, who never dies. Since pass 11 big Billy,
  the millhand and the tin guard have rigs again (fit.json no longer says
  `"ragdoll": false` for them): the parts the dead body loses (the gun, the
  saw, the shield) are left out of the limbs' shape (`_build`, and
  `tools/rig_reference.gd` alike; their hands had sat at the gun's muzzle, a
  shoulder on the saw), and a limb with nothing of its own left takes the
  other side's mirrored (`_mirror_limbs`). RAGDOLLS (a setting,
  `View.ragdolls`) off brings the old falls back. Lost limbs stay off
  (`Gore.lost`).
- **Pass 11: falls that look heavy, grounded and each their own** (looks only;
  `src/ragdoll.gd`, `view3d/ragdoll_rig.gd`, `view3d/actor_view.gd`). Found
  with `tools/death_frames.gd -- audit` (`tools/death_rows.gd`: kinds, guns,
  zones and places, ten moments a row; `docs/godot3d/destruction/RAGDOLL/`
  before and after):
  - Knees folded backwards and elbows the wrong way before: map space is the
    model's mirrored (y and z swapped), so "ahead" is across x up. Knees now
    fold forwards only (a knee lying on the floor is left be); elbows bend any
    way (the shoulder turns the arm).
  - Each ball has its weight (`WEIGHTS`: torso and hips lead) and the links
    are put right by it, four passes and once more after the floor's lifts.
  - The muscles hold the pose it died in (`_muscles`, `HOLD`) and go slack
    over the death's `fade` (zone row, dealt by its dice); a lying body's ease
    (knees a touch bent, hips straight, arms by its side) pulls a heap out
    flat between `EASE_FROM` and `EASE_TO`. Nothing dead stands, kneels or
    sits up (`_slump`): an upright torso goes over the way it leans and the
    kill sent it, a kneeling leg slides out, a body head down and hips up
    goes over. Each thigh stays within its hip's reach (`HIP_*`, as links:
    no thigh up through the belly, as big Billy's was).
  - The kill strikes where the hit landed (`knock` -> `strike(at, dir,
    strength)`, an impulse at a point): the head for a head shot, the near
    arm's elbow, the near leg's knee (that leg goes out from under it), the
    chest or belly else; a blast the ball nearest it, up and away. effects.cfg
    `[ragdoll]` rows are `[hit, carry, lift, buckle, spin]` by gun and
    `zone_<zone>` rows add to them. No ball is sent faster than `STRIKE_MOST`.
  - The hand-over: started from the pose last drawn (its flinch and all),
    fitted to its links with no speed given (`fit`), moving on at the speed
    the living body was going (`ActorView._track`, `drift`), and drawn eased
    from the animation's last pose over `HANDOVER` (.12 s). It is drawn part
    way between its last two steps (`shown`, `alpha`): smooth in slow motion.
  - Friction slides a fast ball (`SLIDE_DRAG`) rather than pivoting the body
    on stuck boots; a body mostly down loses what is left of its motion
    (`LYING_KEEP`) and lies still on a tremble of `SLEEP_LYING` after
    `SLEEP_LYING_FROM`. Play's body's move goes whole to the torso and DRAG
    of it to a limb on the floor; the torso's pull back to it is no speed of
    its own and never carried into a wall (that stuck balls in stair risers).
    A ball found inside something is lifted onto a tread within `STEP_UP`, or
    pushed out of a rail's bar to play's body's side. Bodies of another level
    are never met.
  - Gear let go of (`RagdollRig.gear_bones`): the lost parts that sit by a
    hand, joined into pieces (two at most), fall as a rigid triangle of
    three balls from the box of their parts (`bone_lo`/`bone_hi`, baked),
    instead of shrinking away; the tin guard's shield and the millhand's saw
    lie beside them. A body-labelled hand rides its forearm (`bone_ride`),
    and a limb modelled as one piece bends nowhere (`stiff`, turned by its
    whole triangle).
  - Cost: a step costs about twice what it did (190 to 210 us against 96 to
    108, twenty bodies, headless) but bodies come to rest sooner (all twenty
    asleep in 482 steps of frame against more than 600; 3,600 steps against
    8,800 in all); `budget` still caps a frame. County Run's horde frame
    median 7.52 / 7.52 ms against 7.29 / 7.16 at v3.8.0 (actors 0.95 against
    0.83 ms).
- **Pass 13: the beasts and the bosses' falls** (looks only; audit and
  pictures in `docs/godot3d/deaths13/`, before and after). Before, a gator
  rolled stiffly onto its back and was flattened to half its height, a
  crawler sank into a flat shell with its legs stuck straight up, a shot cow
  stood for half a second and popped onto its side, and a hog of the herd
  snapped straight to its lying key where it ran; the gator's model also
  walked crabwise (built side on for its cels: fit.json `yaw` turns it to
  its heading) and the gator's and crawler's shins swapped legs from key to
  key (export_actors.py's `same_order`, art.md).
  - **The rig** (`view3d/beast_rig.gd`, `BeastRig` under `RagdollRig`,
    baked like a person's; fit.json `beast`: legs, head and tail balls and
    the way the head points): every part is labelled "body", so it is found
    from where the parts are. The torso is six balls as a person's (its
    corners at its legs' roots, its belly and back), so the person's code
    holds it; each leg is three balls (its root held in the torso, its knee
    the part standing furthest off the line from root to foot, its foot);
    the head a skull and a snout; the tail `tail` balls cut along it. Each
    part rides the nearest segment of its own group.
  - **The doll** (`src/beast_doll.gd`, `BeastDoll` under `Ragdoll`: its
    steps, floor, walls, friction, sleep and the model's shape against the
    floor are the person's, with hooks `_before_passes`, `_rest_floor`,
    `_floors_now`, `_keep_out` and per-ball `_limb`/`_core` flags). Knees
    fold only their own way (`_hinges`, the rig's `bend`), legs no further
    than `FOLD` and within `SWING` of the back, the head nods, each tail ball
    bends `TAIL_BEND` at most on the last; legs are light against the body
    (heavy legs out to one side rolled a hog on its side back onto them).
    The kill strikes the part standing toward the shot (a blast the nearest
    ball), divided by its heft; the tail lashes and the snout jerks up. It
    comes to lie belly down, on its side away from the shot or on its back
    by effects.cfg `[ragdoll] beast_<kind>` (a blast or buckshot at arm's
    length likelier over): `_slump` gives its knees while it stands and
    turns it about its length (`ROLL_RATE`) till its back points that way,
    then lets it be. A ball in water floats `DUNK` of its radius under the
    surface, bobbing with play's body, and one under it rises at
    `FLOAT_RISE` (shot set at the surface at once, a swimming gator leapt
    out of the water). Its legs' roots are lifted with the torso by its
    shape (`_torso_more`): lifted against the torso's links they shook it
    awake for ever.
  - **The herd's hogs**: `EventHerd.blast` kills the hog's stand-in (looks:
    `died_at`, `blast_at`); one first seen down (a client, a save) lies long
    dead. Play's rows are as before.
  - **The bosses** (`ActorView.BOSS_HANDOVER`): the scripted fall runs to
    .6 of its span (boss_ending.gd's camera, slow motion and tally as
    before), then its ragdoll takes the pose drawn, under the turn the fall
    had, every ball going on at the speed its part went (`_fall_speeds`,
    `Ragdoll.carry_on`), no blow; the model eases onto it over `BOSS_EASE`;
    its torso may lie `BOSS_SLACK` from the boss's spot (the fall carries it
    back; pulled to the spot it slid). That fall is no longer flattened.
    Not the Copper Baron (fit.json `hand_over` false): on his back his
    great gut stood up and his bent legs propped him, reading as a man
    squatting; his set fall lays him out flat.
  - Cost (headless, twenty bodies shot and stepped to rest, medians of
    three runs back to back against v3.10.0): a person's step is unchanged
    (billy 232 against 238 us, tin guard 231 against 242; the same steps to
    the step), a gator's 315, a crawler's 318, a hog's 264, the cow's 223 us
    (more balls, fewer links than they could have); `budget` still caps
    every ragdoll's steps in a frame. County Run's stress scene (no beasts)
    8.59 against 8.33 ms frame median over five noisy rounds.
  - Checks: `physics_check`'s `tools/physics_beasts.gd` (each beast shot
    five ways from two sides: no jump at the start, rigid links held, at
    rest with no step after, on the floor, not standing, knees their way,
    two ways two bodies, more than one way of lying; on ramps and stairs; a
    gator floating in Gator Bayou's water; the herd's stand-in; the
    sheriff's, Jerry's and the foreman's hand-over: no part jumps, at rest
    on the floor, near where the fall laid it, sliding no further);
    physics_ragdolls' "no part up, none sunk" now holds every beast too;
    load_speed_check holds the beasts' baked rigs.
- **Slow-mo finishers** (`features/finishers.gd`, play): the kill of an
  alerted hand that leaves nobody of the county's hands within hits.cfg
  `[finisher] reach` (and none alerted within twice that), ending a fight of
  `fight_least` kills or more (pass 15; `peak_length` at the director's
  peak's end), sets
  `game.slowmo` for `length` real seconds at `pace`, eased in and out
  (`game_state.gd slow_pace`, `slowmo_for`, `slowmo_pace`), at most once in
  `rest` seconds. A boss's fall keeps its own (boss_fight.gd, a constant
  `SLOWMO_PACE`). SLOW-MO FINISHERS off (`game.finish_slowmo`, a view field)
  stops both while alone; never with a second player, on a host, in the hub
  or in a mode other than the campaign and County Run (`Finishers.allowed`).
- Checks: `physics_check` (its ragdoll part is `tools/physics_ragdolls.gd`):
  every legged kind shot down lies with no part over half its height and
  none sunk past `SINK` (view3d_check's "no part up at down", for ragdolls);
  bodies dropped, shot and blasted on decks, stair treads and ramps of four
  levels and on hickston's hay loft lie on the floor under them, never
  inside anything, the torso by play's body, and sleep (no step in two more
  seconds); thrown hard at the loft's rail a body goes over and lies below,
  softly it stays up; the last of three kills starts the slow motion (the
  first not), it eases to `pace` and ends; never with the setting off, two
  players or on a host; and pass 11's falls (`_falls`, Billy and the tin
  guard, three kills from two ways): no ball moved at the hand-over, no rigid
  link longer or shorter than `STRETCH` at rest (`STRETCH_HIT` for a frame as
  it lands), knees forwards, thighs within the hip's stops, at rest by
  `REST_BY` and no step after, the same kill from two ways two bodies, buckshot
  at arm's length throws it further than a head shot. `tools/death_frames.gd`
  pictures falls in a window
  (every tick drawn; `classic` for the scripted falls). Pictures:
  `docs/godot3d/features/a/`.

### Physics polish (after v3.2.0, track M)

- **Loose things settle, no snap.** `View.Sprite.settle` (seconds on its
  floor; -1 the old instant lie) and `roll` let the 3D view ease a slab over
  from the turn it came down at onto its nearer face in `SETTLE` (.28 s),
  turned about the floor no more than it must, rocking a little after
  (`ROCK*`), then lying still (`SlabLayer3D.settled`, `turn_of`; propped
  `PROP` .1 to .45 rad by a smooth sum of its place so it reads from a
  standing eye). Each feature keeps when its thing came down and its spin
  then: brass and hulls (`debris.gd landed`, `rested`) lie on their side from
  the first touch and roll about their length by their run (`ROLL_R`),
  easing flat at rest (`ROLL_FLAT`); gibs (`gore.gd`, game_view's chunk)
  tumble on by their roll while they roll and settle from rest (`g.age`);
  weapon_fx and gun_fx chips, hit_reads' hats and guns (`landed`, `spin0`)
  and breakables' bits (`landed` on game.clock, `spin0`; the resting block
  sprites get their settle until `View.SETTLED`) settle from their landing.
  `landed`/`spin0` of the play features are SnapCodec SKIP_FIELDS (looks).
  A bounce puts a thing back in the air: it tumbles again and settles anew.
- **Ragdolls on the floor.** `RagdollRig._hull` keeps each segment's convex
  hull (Godot's QuickHull of its parts' vertices, a lost part left out) in
  the segment's rest frame, sorted into 26 buckets by the fine ways (`FINE`,
  `BUCKET_EDGE`) each point is outermost along; `Ragdoll._hull_floor` turns
  the segments as the view will (`frames_of`, the same equivariant sums),
  finds each one's lowest point in the bucket nearest straight down and
  lifts that segment's balls (the torso by its corners, the head about the
  neck) the least that keeps it out of the floor under its nearest ball; the
  lift stops the fall (no bounce). Skipped for segments well clear of the
  floor (about 25 us a step on top of 80; `budget` still caps a frame). A
  ball on a floor steeper than `SLIDE_FROM` is pulled down it past what
  friction holds, so limbs hang down a ramp. Bodies lie on one another:
  `Ragdoll.others` (ActorLayer3D sets it each frame from those shown and
  kept) pushes a ball out of another body's balls (all the way when that one
  sleeps; a knock faster than `WAKE_HIT` wakes it). A body first seen long
  dead starts lying on its back on the floor (`RagdollRig.lying_points`),
  lowered onto it, takes `ActorView.SETTLE` (10) steps at once and is laid
  still (`settle(..., rest)`): about 1.5 ms once, no stir after.
- **Wreck pieces tip.** A thin piece (`THIN`: a stave, a board) standing on
  an end or an edge (`WreckPhysics.standing`: upright reach over `TALL` times
  its narrow foot, within `TIP_FROM` of upright) with nothing leaning it (no
  contact steeper than `PROP_N`, none holding it above its middle) is set
  turning about its foot's edge on the side it leans, just fast enough to go
  over (`TIP_KICK`, harder each try, every `TIP_EVERY` for `TIP_MOST`, the
  other way after two tries); it never sleeps standing meanwhile. Since pass
  11 a piece leaning only on another piece that itself stands on its end is
  not held (`Body.leans`, `upright`): a ring of staves left standing goes
  over; a wall or a lying piece still props it, and one asleep standing whose
  prop went (`topples()`) is woken. Chunks of bulky things may stand.
- **Water reacts** (`features/water.gd`): `splash(x, y, z, size)` rings,
  gun_fx's water crest and drops (`gun_fx.splash`) and a splash heard (one a
  `SPLASH_GAP`); `Water.splash_if(game, ...)` is how anything landing asks
  (BayouBrains.wet_at; a server has no water feature, so it only answers).
  Brass, hulls and gibs splash in and sink (`SINK_RATE`, `SINK_TIME`), a body
  thrown or falling in splashes (corpses.gd), and so do breakables' bits,
  thrown things (carry), hats and guns and wreck pieces (their hardest knock
  a tick). effects.cfg `[debris] current_<level>` (bayou, County Run's
  bayou) is the current: a floating body near a player drifts on it,
  swaying (`DRIFT_SWAY`, `DRIFT_TURN`; play, arithmetic only, never out of
  the water or into a wall); wreck pieces at rest all over water float off
  on it asleep (wreckage.gd `_in_water`, never into the bank: `inside()`),
  and tin, clay and glass (`SINKS`) go under and shrink away.
- **Fast things never skip a wall**: `Tumble.step` splits a step that would
  move more than `MOVE_MOST` (.14) into up to `MOST_SPLIT` steps (play's
  bodies too: the same on every machine).
- Checks: physics_check (brass and gibs settle with no step over `SNAP` a
  tick, brass rolls; things thrown at 24 a second at thin walls stay their
  side), `tools/physics_water.gd` (splashes, sinking, a body afloat drifts
  the same twice, a crate's boards float off asleep), physics_ragdolls (no
  part of any kind sunk more than `SINK` .01, a body dropped on another lies
  across it, one first seen long dead lies still at once), wreck_check (no
  piece rests on its end unless propped). `tools/physics_polish_frames.gd`
  pictures it (`docs/godot3d/polish/M/`, before and after).

### Picking things up, fire that spreads, the stills

Three SIM features (carried in snapshots), behind LIVE PROPS AND FIRE (PLAY,
`live_props`, on by default; a net match takes the host's), off in the
Crossroads and the versus and 5v5 modes (`allowed()`).

- **`features/carry.gd`** (`data/tuning/carry.cfg`). The things are every
  breakables piece and every board `[thing.<picture>]` names that stands
  loose (no lit board, no quest prop, no base shared or parting floor, at
  most `tallest`). USE (`game.gd interact()`, only when nothing else
  answers it) takes one up: the gun holsters and the thing's own 3D model is
  held low before the eye, small and close (`_held_sprite`, `HELD_*`).
  `game.gd _step_hands` hands FIRE and ALT FIRE to `hands()` while one is
  held: FIRE throws (speed by weight, the view's tilt adds lift), ALT FIRE or
  USE sets it down. In the air it is a `Tumble.Body`; what it touches takes
  `hit` x weight x speed (`hurt(..., "thrown")`, `[reaction] thrown` in
  hits.cfg) and a shove, a breakable it strikes is struck, and a hard landing
  breaks a breakable (`land`): a propane tank goes up. At rest it stands
  there again (`_settle`), and can be taken up again. Brutes (`[brutes]`)
  now and then take up one near them, hold it over their heads and lob it at
  whoever they hunt (game.rng). A breakable piece is moved by breakables'
  `lift()`/`set_down()` (a lifted piece waits off the map); a board is moved
  here. `version` counts changes; each machine's `_reconcile()` puts boards,
  props, bases and the fixed sprites in step with the things (a client after
  a snapshot too). A thing in flight is a pooled sprite with `who` set:
  `PropLayer3D` keeps its model by `who` and turns it by `View.Sprite.turn`
  (`PropView.tumble`) instead of making a new one each frame.
- **`features/fire.gd`** (`data/tuning/fire.cfg`). Each cell's fuel is worked
  out once from its floor tile (`[floors]`; a walkable slab's own tile up on
  it) and the props on it (`[props]`). `ignite()` lights a cell for as long
  as its fuel lasts (`patch` on bare ground, never water or a wall); a
  burning cell tries a random neighbour every `spread_every` (game.rng) by
  that one's catch, same floor height only, so it runs over hay, planks and
  decks and stops at stone, dirt and water. Bounded: `cap` cells at once and
  a `budget` of cells per fire (a blast, a cocktail, a spray adds to it);
  idle with nothing burning or spilled. Every `bite_every` players, enemies
  (`hurt(..., "fire")`) and breakables in a burning cell are burned (a TNT
  crate goes up); a body there burns longer, once. Burnt out, a cell with
  fuel is `charred` (a `mark_scorch` ground mark) and never burns again.
  Blasts of the `lights` kinds light their reach (`game_combat.gd explode()`
  sets `blast_kind` while `exploded` is announced); the mode feature's shine
  cocktail fires light their cell; puddles of shine (`spill()`, from broken
  jugs, mash barrels and stills: `[spills]`, via `GameEvents.prop_broken`)
  catch from a neighbour or a burn barrel. Rain (the level's effects.cfg
  rain, the share of its showers) burns fire out faster under the sky. Quest
  props never burn (they never break) and nothing it does shuts a way.
- **`features/stills.gd`** (`[stills]` in fire.cfg; `[town_still]`,
  `[town_copper_vat]`, `[town_shine_tank]` in breakables.cfg; `[still]` in
  shots.cfg). A still is a breakable; `GameEvents.prop_struck` (a shot that
  does not break it) starts a jet from the holed pipe back toward the shot,
  which lights and spills along its arc and burns whoever is in it. Broken,
  it scatters copper bits (breakables' `scatter`) and goes up as a `still`
  blast, which lights fire and spills its shine.
- `tools/live_props_check.gd` (quick, CI) holds all of it;
  `tools/live_props_frames.gd -- out=<dir>` pictures it in a window
  (`docs/godot3d/features/b/`).

### Dirty fighting (content pass 8)

`features/brawl.gd` (SIM, carried in snapshots by uid, never saved: it is
all seconds long), `src/brawl_hazards.gd`, `features/brawl_looks.gd` (looks);
numbers in hits.cfg `[kick]`, `[finish]`, `[finish.<move>]`, `[hazard]`,
`[hazard.<kind>]`. Everything is game.clock, game.rng and arithmetic, so
co-op and online play it the same (`net_check`, brawl_check's snapshot).

- **The boot.** USE with one of the county's hands in front (within `reach`
  past his edge, `cone` of the aim, the same floor, in sight) is a kick, before
  anything else USE does (`game.gd interact()`); with nobody there USE is as
  before. The boot lands `land` later: `damage`, `stun`, `daze` (open to a
  finisher) and a slide along the aim at `speed`, slowing by `drag`. Into a
  wall faster than `slam_least` he takes `slam` a unit of speed; into another
  hand that one slides on (`domino`); off a drop of more than `drop` he takes
  `drop_damage` a cell; a kill throws the body by `kick` (corpses.gd KNOCK,
  effects.cfg `[ragdoll] kick`: it crashes windows and fences like point-blank
  buckshot). A boss slides `boss_share` as far and takes `boss_damage`. The
  gun is down for `busy`. Running (faster than `door_speed`) at a plain shut
  door (no key wanted, not secret, blast-only, controlled or a crouch hatch),
  USE kicks it in: open at once, splinters, and whoever stands within
  `door_reach` behind it is kicked back.
- **Smashes.** FIRE with a thing held (features/carry.gd) and a hand at arm's
  length (carry.cfg `[smash]`) breaks it over his head instead of throwing:
  `hit` + `per_weight` x its weight (`smashed` in `[reaction]`), reeling and
  dazed; a breakable piece breaks (a jug, a crate, a jar), a board (a rocker)
  drops at his feet.
- **Finishers.** USE, or a swing of the crowbar, sling blade or rip saw, at a
  hand who is down to `low` of his health, reeling (`stun` at least
  `stagger`) or dazed starts a move by the gun in hand (`pistol`, `long`,
  `blade` lists; anything else, holstered too, is the boot's) picked by
  game.rng: PISTOL WHIPPED or SAY AHH (a round in the mouth), BUTT STROKE or
  BELLY FULL OF LEAD (a round), SKULL CRACKED or GUTTED, BOOT TO THE FACE or
  PUNTED. A move that spends a round is left out with none loaded. The blow
  lands `wind` later; the hands are busy `hold`. `end` "head_off" hits the
  head just hard enough for the gore to take it (gore_extras.gd LIMB_HIT,
  short of an overkill), "gib" takes him apart, "fall" drops him. Alone, the
  world slows to `pace` for `slowmo` real seconds from the blow (the finishing
  shot's own is held off meanwhile; never with two players, as finishers.gd).
  The move's name is called on screen and Mundell says a `finisher` line
  (barks.gd, voiced). Bosses are never finished.
- **Hazards.** A man driven into one (only by a slide: a hand walking about
  never is) dies the way it kills: the props named in `[hazard] images` (a
  saw blade or the headrig, the wood chipper, the crushers: gib; the bug
  zapper, the hot fence, the Mothership's beam emitters: shock and sparks; a
  burn barrel: set alight (fire.gd); the well: down it, no body; the cattle
  guard: his ankles); water a little ahead of him while he slides fast, if he
  started dry (BayouBrains.wet_at: the creek, the bayou's deep water; he
  floats); live hogs within `hog_reach` where his slide ends (they close in
  and he is their slop 1.3 s later). A boss takes `boss_share` of his health
  at most once in `boss_rest` and is never killed by one. Calls on screen and
  a `hazard` line. Where they stand: [levels.md](levels.md#the-plans).
  A hazard kill pays a bonus (pass 15, `_bonus`; [Reading
  danger](#reading-danger-pass-15)).
- **Looks** (`brawl_looks.gd`, after feel.gd so it adds to the gun's place):
  the kick is six cels `fx_boot_kick_0..5` (tools/art/build_boot_views.gd
  from scripts/blender/boot_views.py: his brown work boot coming up sole
  first, its tread to the man kicked, the stacked heel and the overalls' cuff
  under it; `PLACES`
  where each sits): lifted (5), chambered (0), out (1), the blow held on
  contact (2, the hit-stop), pulled back (4), away (3); the stomp runs the
  same six. Drawn under the gun over the view's rows only, lit as the
  gun is; the gun ducks out of its way. Each finisher moves and turns the gun
  in hand along its own path (`PATHS`: the revolver cocked low and swung
  across butt first, the long gun driven up stock first, the blade raised
  and brought down or swung flat, a round pushed into his mouth or gut and
  fired) and shows the gun's own frames on the way (`FRAMES`, polish pass 9,
  through `Player.weapon_pose`, looks only: the pistol and long gun cocked
  back on `recover`, driven through the blow on `kick`, back on `recover`;
  the crowbar and sling blade swing their own `wind`, `strike`, `follow`,
  `recover`, the rip saw bites on its grind frames; a round in the mouth or
  gut is cocked, then the shot's own kick and flash show; a gun lacking a
  frame keeps its own pose), holding still on contact while the slow motion stretches it:
  `Player.weapon_turn` (looks, never carried) turns the gun cel about its
  grip on the graphics-card canvas (`Canvas.gpu_texture_turned`; the
  software canvas draws it unturned). Every blow jolts the view
  (`feel.gd punch()`, SCREEN SHAKE scales it). The bug zapper's lantern
  lights the ground about it violet (effects.cfg `[light.bug_zapper]`).
- `tools/brawl_check.gd` (check_all, quick): the slide, the slam, the domino,
  a healthy hand kicked not finished, a finisher of each class (and every
  move by seed) with its slow motion from the blow, the crowbar's swing, the
  setting off, co-op's second player finishing with no slow motion, each
  hazard kind and a hand walking by one, the creek, the hogs, a boss kicked
  not finished and taking only his share, the door kicked in, smashes, two
  runs the same, a snapshot mid-slide played on tick for tick, and the boot's
  cels and their places. `tools/brawl_frames.gd -- out=<dir>` (a window)
  pictures each.

### The bowling lane's pins (second remaster)

The Bowl-O-Rama's ten pins are rigid bodies in three dimensions
(`src/range_pin_physics.gd`, played by `src/range_bowling.gd`): each a
centre of mass, a quaternion, a slide and a spin, with a pin's mass and
moments. The shape is six spheres up a real pin's profile and the six-point
ring of its foot, so a pin rocks back short of about ten degrees and goes
over past it because its centre of mass leaves its foot. Contacts (deck,
gutter channels, kickbacks, the cushion, pin on pin, ball on pin) are solved
by sequential impulses with friction and bounce (the shared core's exact
solver, `PhysCore.prepare`/`solve`), `STEPS` small steps a tick
and `PASSES` passes, penetration pushed out after; still pins sleep and cost
nothing until knocked. While the ball is among the pins (`AMONG`) its roll
for the tick is solved again with them from where it was, so it gives up
momentum and deflects. The level has real gutter channels and a sunken pit
(`range_plan.gd`'s `bowling()`; `floor_at` must match it). A pin's state is
plain numbers in its dictionary (`KEYS`), so snapshots carry it. A roll is
counted once every standing pin sleeps and the deadwood is slower than
`DEADWOOD`. Tune with `tools/bowl_lab.gd` (rolls a spread of lines, prints
what stands and the tick's cost); `range_check.gd` checks the lane.

### The games row (v3.2 feature pass)

South of the armory, down the gravel walk past it (`range_plan.gd`'s
`games_row()`, range layout 5), four booths off a walk, played by
`src/range_games.gd` and `src/range_skeeball.gd` from the range feature
(stations `range-pitch`, `range-dunk`, `range-skee`, `range-bottles`); their
numbers are `data/tuning/range_games.cfg`, their shapes
`src/range_games_shape.gd` (the 3D view draws them from it: `SolidKit`).

- **Horseshoes**: USE in the box pitches a shoe where the player faces, as
  high as they look (the card says how far a pitch carries); `game.rng`
  wobbles each pitch a little (`wobble`, `aim_wobble`). A shoe flies
  spinning, lands dead in the pit, slides; the stake knocks it off when the
  bar meets it from outside, holds it once the stake is inside the ring
  (dropped over it or come in through the mouth). At rest: ringer 3, leaner
  2 (drawn propped on the stake), within `point` 1. Ten shoes a game.
- **Dunk tank**: any shot on the bullseye (traced) drops the plank and the
  hand (a billy stand-in, `ModeBodies.stand_in`) into the water with a
  splash; he stays under, climbs back and jaws. The lever starts a 30 s
  round: the bullseye swings, dunks are counted.
- **Skee-ball**: USE at the foot rolls a ball up the rising lane (how hard by
  the look, `power()`; which way by the facing); off the hump it flies and
  lands on the tilted board; where it lands is its ring (50 to 10, 100 in
  the corner cups), a dead ball rolls back for nothing. Nine balls.
- **Knock 'em down**: ten milk bottles racked on a table, three softballs.
  The bottles are `range_pin_physics.gd` bodies with a bottle's own shape
  (`Body.shape`, `com`, `foot_r`, moments) and the softball a `free` ball
  (falls and bounces in 3D) in the same solve; a bottle below the table top
  moves to a second solve on the ground, so nothing pops up through the
  table. Down 1, off 2, cleared +10; a shot bottle spoils the round.

Each game's finished score goes to `RangeBoard.finished` (records and the
board, below); the station's card shows the score, the best and the
county's top five. Nothing here is saved (the range never is).

### The range's records and board

`src/range_board.gd` (`RangeBoard`): each game's best (bowling, the duck
gallery, the four above, the fair gallery) is kept in `range-records.json`
beside the unlocks (tools: the cache), never in a campaign save. Online the
finished score is posted to the first server in `servers.json` and each
station asks for its game's board (top `shown`, a name's best counting, a
score over `MOST` refused): a BOARD knock carrying `range`, answered by
`RangeBoard.answer` (`CountyBoard.answer` hands a knock with `range` on, so
the lobby server needed no change of its own) from `user://range-board.json`.
`main.gd` calls `RangeBoard.frame` each frame; a tool never knocks unless
`RangeBoard.local`. Offline the card says so and shows the local best.

### The fair's shooting gallery

`features/fair_gallery.gd` (SIM_FEATURES; saved: best, the hat, the bear,
beers): in the fair's game court, the booth east of the prize booth on the
north side. No station, door or wall of its own (the booths are
`fair_plan.gd`'s as built), so it never stands in the quest's way. Shoot
the bell at the counter: 30 s; ducks (2) on the back rail go over flat,
cans (1) and bottles (3) ride the middle rail (a can flies off spinning,
bounces off the booth's back and floor, 2 more shot in the air; a bottle
bursts), the hog (5) runs the front rail now and then. Shots in a round
come back to the gun's pocket. The prize booth pays: 15 a beer into the
pockets, 30 the straw hat, 45 the bear (both then sit on its counter).
Leaving the counter ends a round. Each round goes to the range's records.

### Mundell's trophy shack

`features/trophy_shack.gd` (LOOKS_FEATURES): the Crossroads' shack (hub
layout 4) stands a statuette of each boss beaten (the boss's model through a
stand-in at `STATUE` high on a plinth, its plaque behind) by
`BossRematch.beaten` (the next gate open, the chapter marked won, the
campaign won), a cup per range game with a best, a gnome per County Run map
with a record, and inside a card lists them with the rematch bests. It
reads the existing files only (no new save state); `game_view.gd`'s hub
path adds its sprites. On the west wall north of the door hangs Mundell's
shadow board (`gun_board`, `tools/art/build_gun_signs.gd`): a whitewash
outline for each of the campaign's fourteen guns (`GunFinder.BOARD`: the
riveter and the Copperhead are the range's and the 5v5 store's, a level's
`riveter` and `pressure_gun` pickups giving the bowling ball and the cow
launcher, `game_state.gd ALIAS`), each gun the local player has hung flat on
its outline (a pickup's picture on a `plane` is drawn flat, not as a slab);
the card adds GUN BOARD n OF 14 and STILL OUT THERE: each gun missing that
lies in a chapter already beaten, with where (`GunFinder.CHAPTER_GUNS`).

### Finding the guns (feature pass 7)

Players walked past the new guns, so a gun the local player ain't got yet
("new iron": `armory.owned`) is made easy to find, in every campaign chapter
played alone or in co-op (`GunFinder.on`: not the hub, the range, County
Run, the versus maps or a boss rematch). All of it is looks and sound
(`src/gun_finder.gd`, the LOOKS feature `features/new_iron.gd`); numbers in
`effects.cfg [new_iron]`:

- **It shines**: a warm glint over it (`fx_gun_shine_0..2`, a spark that
  flashes a cross and a star on a beat set by the clock and its place) and a
  pool of light round it (`[light.new_iron]`, through `view_lights.gd`), as
  if a lamp were left on over a display. Gone once it is had.
- **The automap marks it** once seen (in sight within `see_reach`) or
  smelled (within `smell_reach`, about the same floor, no sight needed): a
  little gun in red with a steel barrel (`GunFinder.ICON`; guns lying
  together get one mark), NEW IRON in the key (`map_key.gd`). What was seen
  is saved by where it lies (the feature's save, no save version).
- **USE's prompt names it** looked at from `prompt_reach` off (within
  `prompt_facing`; of a row, the one most in the middle of the view), when
  nothing else is at hand: "RIP SAW  /  NEW IRON" (`game_use.gd`, after a
  vehicle's).
- **Mundell smells it** the first time one is within `smell_reach`: SMELLS
  LIKE GUN OIL ROUND HERE... and two more, said in his voice as the
  `new_iron` bark (Barks LINES, mundell_lines.json, cues
  `mundell_new_iron_0..2`; the message line when he can't, `NewIron.SMELLS`),
  once for the guns lying together.
- **Secrets stay secrets**: a gun in a hidden room behind a secret door not
  found yet (`GunFinder.in_secret`) neither shines, is lit nor goes on the
  map; Mundell can still smell it, a hint and no more.
- **The tally** counts the chapter's guns had under the secrets (GUNS 02 /
  03, `GunFinder.tally`, `hud.gd intermission`); the trophy shack's board
  and card show what is still out there (above).
- **In the levels** each chapter's plan with a first-time gun well off its
  way has a `new_iron()` (see [levels.md](levels.md#the-guns-along-the-way)).

`tools/gun_find_check.gd` (GUN FIND OK, in check_all) holds it: the way
through each chapter (`tools/gun_routes.gd`, route_map's legs), every gun
new to a player arriving in campaign order within `NEAR` steps of it with
no secret in front, signed where the way is left for it when further and
out of sight, a gun only behind a secret teased by its rounds near the way;
every gun lying out shining, lit, named looked at, marked once seen, smelled
once, none of it once had; secrets kept; the tally row; the shack's board;
none of it off the campaign. `-- audit` prints the table and `map=<dir>`
draws each chapter's guns against its way.

### The hound (content pass 8)

BLUE, Mundell's bluetick coonhound, comes along with each player in a
campaign chapter played alone or in co-op (`HoundNose.on`: not the
Crossroads, the range, a boss rematch, County Run or the versus modes:
County Run's runs and its daily board are set for one man and his guns).
HOUND DOG (PLAY page, `hound`, on) turns him off. A game reads `hound` from
its options with 0 when it is missing, so an older replay plays without him,
and the front end sets it to 0 when a tool or a view tour runs the game
(`main.gd`), so every check and picture made before him is the same; a tool
that wants him sets `main.options["hound"] = 1` (`bot_campaign.gd -- hound`
walks the campaign with him). Play, carried and saved: `features/hound.gd`
(a SIM feature, a `Dog` per player slot, its dice `game.rng`), how he gets
about `src/hound_legs.gd`, his ears, moods and rides `src/hound_moods.gd`,
what his nose finds `src/hound_nose.gd`, his looks and badge
`src/hound_looks.gd`, his own little noises `features/hound_voice.gd` (a
looks feature), numbers in `data/tuning/hound.cfg`.

- **What the looks read** (pass 10). `Dog.state`: FOLLOW, STAY, SIC, PIN,
  FETCH, CARRY, BAY, POINT, DOWN, and new HOWL (at a siren), COWER (a
  twister), GREET (got up), TREAT (wagging round a still or scrap), GROWL (a
  hand round a corner, `Dog.look` where), RIDE (in a vehicle's seat,
  `Dog.ride` which). `Dog.job` while FOLLOW (`Hound.JOBS`): HEEL, RANGE
  (`Dog.roam` where to), NOSING (sniffing about there), CIRCLE (back to
  heel), CATCH (running to catch up), ASIDE (out of a player's sights),
  TRAIL (sulking behind), WAIT (where he cannot follow), LEAD (showing
  the way, pass 15: below). `Dog.mood`
  (`Hound.MOODS`): CALM, HAPPY, ALERT, SCARED, SULK, HURT, till
  `Dog.mood_until`. `Dog.pace` is how fast he went last tick, `Dog.stride_v`
  how fast his legs go (eased over a few ticks) and `Dog.gait_kind` the gait
  they go in (pass 12: -1 standing, 0 walk, 1 trot, 2 lope), `Dog.still_at`
  when he last stood still, `Dog.hop` a leap in the air (into a seat, down
  off it).
  `features/hound_voice.gd` (this machine's only) answers `cowering(slot)`
  (the thunder), `howling(slot)` (along with the radio), `shaking(slot)`
  and `panting(slot)`.
- **Getting about** (pass 10, `HoundLegs`). He walks straight where a
  scratch body walked there in short steps the way he moves (walls, steps,
  decks, deep water) gets the whole way, off no ledge and into no harm;
  else he plans a way over the level's floor (`HoundLegs.plan`: a scratch
  flow field from the goal, walked again from nothing every plan so a game
  and its snapshot copy plan alike; closed doors, the standing hazards and
  burning cells shut; `plan_reach` steps) and walks the furthest of its next
  few steps he can walk straight to, planning again when the goal moves, the
  plan is `replan` old or he stalls (under a third of his pace's way in half
  a second, to and fro on the spot counts); else down his player's flow
  field. A stride that is shut or walks into harm takes the nearest turn off
  it that goes somewhere (`HoundLegs.step`). Caught inside something (a
  prop's corner, a door shut on him: no little step goes anywhere) he is put
  on the nearest free spot a short hop away; stalled `unstick` where nobody
  sees, he hops on to the next step of his way. His pace, easing and turning
  are pass 12's ("Calm and easy to look at" below). Cost: whether a way is straight (and how
  far along a plan he can cut) is asked every `Hound.LOOK_AGAIN` (.2 s) or
  when the goal moves, the bosses are looked for when the hands come or go,
  whether it is calm at his sniff, and whether anybody sees him only when
  he is cut off or stuck: about 70 to 80 us a tick headless with the
  campaign bot playing (v3.7.0's heel: 45 to 117), no change measured in the
  whole tick.
- **Ranging.** Calm (no hand awake within 10 of his player, his mood calm,
  his player not driving) he waits at heel `range_rest` or so, then goes out
  to a spot `range_near`..`range_far` from his player and `range_side_min`..
  `range_side_max` off the way they go (round one standing, anywhere but in
  front), somewhere fair (open, near their floor, walkable to them not by a
  long way round) and in nobody's sights (`HoundLegs.roam_spot`, game.rng),
  noses about there and circles back; passed by his player or too far, he
  comes back sooner. Further than `catch_far` he runs back to heel.
- **Out of the line of fire.** In any player's sights (`clear_reach`,
  `clear_cone`), or in his own player's as they swing round toward him, he
  steps aside off their line for at least `aside_for` (across it against
  the swing, the quickest way out); no spot he ranges to is in a player's
  sights.
- **Out of trouble.** `HoundLegs.dangers` each tick: the standing hazards
  (BrawlHazards' saw, chipper, zapper, hot fence, burn barrel, crusher, plus
  `harm_pad`), a twister, steam and chalk, the race's cars, a boss (and
  where one winding up aims, `telegraph_reach`, and the way there); fire and
  deep water are asked where he steps. He never steps into one, gets out of
  one he finds himself in first of all, and never picks a hand standing in
  one.
- **Catching up.** Further than `lost_far`, or cut off (no way planned, off
  his player's flow field) and out of everyone's sight, for `lost_for`, he
  turns up `hide_near`..`hide_far` behind his player where no player sees
  the spot (off their view, `HoundLegs.seen`) and only from where nobody
  saw him go; no such spot (his player on open water), he waits. A new
  chapter starts him at heel; a load puts him where he was, and he catches
  up from there.

- **Vehicles.** One coming at him faster than `ride_from` within `ride_reach`
  ahead: he jumps aside at `ride_hop` (a bark, never hurt); one on him shoves
  him out of its hull (`HoundMoods.clear_of_rides`, deterministic). His
  player at the wheel of one with a free second seat (the airboat, the car;
  pass 10): he runs to it and, within `board_reach` of its end with it
  under `board_speed`, leaps into the seat (`HoundLegs.seat_at`, state
  RIDE) and rides along; his player out, someone in his seat or it wrecked,
  he leaps down beside it. A partner getting in finds the seat free (he is
  never in `Ride.seats`) and he hops out. Else (the mower, the seat taken,
  it gone off fast) he heels `heel` past the vehicle's tail and catches up.
- **Heel.** Behind his player off to one side, out of their sights; a run
  past `run_past`. He walks the level as a body of his own (an Enemy no list
  holds, moved with `LevelData.move`, never carried: `SnapCodec.SKIP_FIELDS`,
  with the scratch body his straight walks are tested with, the level's
  hazards, the tick's dangers and the scratch flow field). The hands do not
  hunt him and the player's shots pass him.
- **Nose.** Calm (no hand awake near the player) he bays at a secret door
  not found yet from its open side (`HoundNose.door_front`) and at a gun his
  player ain't got lying out (GunFinder: never one behind a secret, the door
  gives that away), and points at a pickup his player cannot see; each place
  once (`bayed`, saved), the nose resting `bay_rest`/`point_rest` after. He
  goes to a spot short of it clear of harm, bays from where he got to when
  the way is shut, and leaves it when his player goes on past `catch_far`. Pass 10: a hand awake within `growl_reach` that his
  player cannot see, while none they can see is near, and he stops and
  growls low at it (`HoundNose.unseen_foe`, once a hand: `warned`); a still
  or scrap lying out within `treat_reach` and he runs to it and wags round
  it yipping (`HoundNose.treat_near`, once each, in `bayed`).
- **Fight.** On his own he goes for a hand under `pin_below` of its health,
  one right on top of his player or going for them close by (pass 10: the
  one on his player first, then a hurt one, then the nearest, and one not
  already in a player's sights; never one standing in harm); told (the whistle with the sights on one)
  any hand he takes (`HoundNose.takes`: not a boss, nothing that flies or
  swims). He bites (never for the last of its health: the kill is always a
  player's) and under `pin_below` holds it down `pin_time`: stunned the whole
  time, it cannot fight or walk, dragged half down (its fall's `die_1` held,
  `Enemy.held_cel`, now and then its pain twist), turned to face his player
  so it leans back along their line of sight and their shots land on what
  they see (its hit cylinder never moves). At his real size (pass 10,
  `HoundLooks.SIZE`) his jaws reach its legs from the hold's gap; the .3 he
  was drawn set back since polish pass 9, when his head stood in its chest,
  is gone. The hands within `kick_reach`, the held one
  too, kick at him (`kick_rate`, the kick shown as the hand's attack frame);
  blasts hurt him. A held hand finished counts on the tally (BLUE: FETCHED,
  HELD) and gets a GOOD BOY. Under `back_off` of his health (pass 10) he
  lets go and keeps behind his player, mood HURT, `back_off_for`; no way to
  his hand (a hazard, a ledge) and he gives it up.
- **Fetch.** Told, the pickup the sights are on (ammo or food, never keys,
  quest pieces, guns or dynamite); on his own every `fetch_every` or so,
  food when his player is hurt, rounds for the gun in hand when it runs low.
  He takes it out of `game.pickups`, carries it (saved) and drops it at his
  player's feet with `add_pickup` (a new uid), where they take it as ever.
- **Down.** Hurt to nothing he lies whining; a player holding USE beside him
  for `revive_time` gets him up, USE with a pork rind in the pocket at once
  (`hound.use`, `hound.prompt`, from `game_use.gd`), and after `get_up` he
  gets up himself: he never dies. Up again he greets the one who got him up
  (state GREET, `greet_for`: runs to them, yips).
- **Moods** (pass 10). A shot passing within `shot_near` of him (in front
  of the shooter, in their sight: `shot_fired`) and he sulks `sulk_for`,
  trailing `sulk_heel` behind at a walk. A siren (the twister's warning and
  the raid's anywhere, their first seconds; a cruiser with its siren within
  `siren_reach`): now and then (`howl_chance`, game.rng, at most every
  `howl_rest`) he stops and howls `howl_for`. A twister within its reach and
  `cower_reach`: he runs to his player's side away from it and cowers,
  whimpering, till it is gone. His own noises (`features/hound_voice.gd`,
  looks and sound only, its own dice): a pant after a run, a sniff nosing
  about and now and then at heel, a shake-off out of the water, back on his
  feet or down off the airboat, a whimper and a cower at the thunder (the
  weather is this machine's), and now and then a howl along with the
  radio's song by a set (not the jock, not with RADIO off).
- **Mundell about BLUE** (pass 10, barks.gd, each held back a good while):
  `hound_down` when he goes down, `hound_praise` at a bay or a point,
  `hound_shot` after a shot close by him, `hound_hush` when he howls,
  `hound_greet` getting him up, `hound_shine` at a still.
- **The whistle.** WHISTLE FOR BLUE (G; the pad's BACK held
  `PAD_WHISTLE_HOLD`, a tap is the map on its release, or its share button;
  the touch WHISTLE button, shown with BLUE along, or a tap on his badge): `act(["hound"])` -> `Game.hound_call()`; online and for bots
  `Controls.item == Game.HOUND_CALL` (96, past the pockets, so the wire and
  the replay rows are unchanged). Sights on a hand SIC 'EM, on a pickup
  FETCH, else STAY (he sits) and again COME; Mundell says it in his voice
  (the `hound_*` barks, mundell_lines.json).
- **Looks** (rebuilt in pass 10, `src/hound_looks.gd`, looks only: all of
  it from what play carries and the clock, never `game.rng`). His model
  (`scripts/blender/actors_hound.py`, scene `scenes/actors/hound.tscn`)
  drawn through a stand-in (`ModeBodies.stand_in`, key `hound<slot>`; the
  picture `hound_<cel>`, the model's frame in `Sprite.pose`) posed by
  `HoundLooks.pose` (`hound.frame()`): by `Dog.gait_kind` the walk, the
  trot or the lope (pass 12, below; his sulking trail at `sulk_pace` walks,
  nose down); sore (under `SORE` of his health) a limp and no wag; tracking (on
  his way to a bay or a point, and now and then at heel) his nose down.
  Standing at heel the idle wag, and in his own round a scratch and a
  sniff; STAY sat, lying down after `LIE_AFTER`; the point, the howl (bay),
  the lunge and bite timed on his bites (`GATHER` before, `FOLLOW_THROUGH`
  after), the hold's head shake, the yelp, fetch. Pass 10's states: RIDE
  sat, HOWL the howl, GROWL the bark, COWER lying low (rest), GREET a quick
  wag, TREAT nosing at it (fetch), NOSING the sniff. Down: going down onto his
  side (`FALL_TIME`), whining there, and with a hand on him up onto his
  chest and his forelegs as `revive` grows (back down if it lets go); got
  up (`Dog.up_at`, the one field pass 10 added to play) he gets up
  (`UP_TIME`) and shakes it off (`SHAKE_TIME`). ActorView blends pose into
  pose over his fit.json `blend` (.2 s) and plays each motion's five keys
  on the stand-in's gait. A kick or blast rocks him (`ActorView.flinch`).
  His model is in metres and drawn `HoundLooks.SIZE` (.54) of a world unit
  a metre, so his shoulder stands about .37 and his head about .46 of
  Mundell's height (a co-op partner's model) as a real hound's against a
  man's; before it he was drawn a metre to the unit, near a man's height
  (`actor_check` holds the band).
- **His badge and markers.** The badge in the view's bottom left
  (`HoundLooks.badge`, taken by `hud_fixed` through HudLayout): his head
  (`hound_face_0/1/2/down`), BLUE and his mood (WHIPPED down, SORE low,
  just hurt or backed off, RILED in a fight, KEEN on point, else play's
  `Dog.mood`: EASY, HAPPY, RILED, SKEERED, SULKIN', SORE, `MOOD_WORDS`;
  FRETTIN' when his player is low and PATIENT at STAY when calm), his job
  (by state: STAYIN', LAYIN' UP, SIC 'EM, HOLDIN', FETCHIN', BRINGIN',
  BAYIN', POINTIN', DOWN! blinking, HOWLIN', HIDIN', GLAD, WAGGIN',
  GROWLIN', RIDIN'; going with his player by `Dog.job`: HEELIN', RANGIN',
  SNIFFIN', CIRCLIN', HUSTLIN', DODGIN', TRAILIN', WAITIN'; and UP AGIN,
  SNIFFIN' tracking, LIMPIN' sore), ten health
  ticks. Out of sight behind something a little tin tag BLUE with an arrow
  stands over him in the view; off the view it sits on its edge pointing
  his way (`HoundLooks.marker_at`); down, it is red, BLUE!, and blinks.
  On point or baying, breathing brackets and a paw pip mark what he found.
  Beside him down, USE's prompt is BLUE'S DOWN - HOLD <USE> (the bound
  key, Y on a pad, USE on a touch screen); holding it, GETTIN' BLUE UP and
  its bar (`hound_revive`, `hud_flow`) rise from the view's foot.

`tools/hound_check.gd` (HOUND CHECK OK, in check_all) holds it: heel, catch
up and the lost jump; none with it off, in County Run, a versus map, the
range, the Crossroads or a deathmatch; the bay at a secret door and at new
iron, the point at a hidden pickup; a hand held stunned and never killed by
him, kicks, finished by the player; a told SIC biting a whole hand down; no
boss; a fetch dropped and taken; down, held USE, a rind, getting up himself;
STAY, COME, the replay op and the controls' whistle; saves; co-op's two
hounds and their own whistles; two games in lockstep with him about, a
snapshot onto a fresh game running on the same; his art, the stand-in and
the badge; every state's pose a frame of his model (POSES); the badge's
words, the markers, the point's brackets, the revive bar and the prompt
(FEEDBACK). `tools/actor_check.gd` holds his model's motions (every frame
`HoundLooks` plays, each motion's keys in a row, played on the gait, a
one-shot ending on its last key, his own blend) and his texels. Pass 10's
ranging, stepping out of the sights, going round a hazard, backing off
hurt, a boss's aim as harm, the free seat and a partner taking it, the
sulk, the howl, the cower, the growl, the still, the pant, the shake and
the barks dealt at random (LEGS, MOODS, VOICE); pass 12: his gaits by `Dog.stride_v`, settling by a standing player (no ranging straight off, sitting, lying down, no scratch as he stops). `-- play=<level>` lets the
campaign bot play two minutes with him and prints what he did.

`tools/hound_walk_check.gd` (HOUND WALK OK, in check_all; pass 10) walks
every chapter's way through (route_map's stops, every door open, no hands)
and the hub and the range (he is set on there for it) with him along,
turning round at each stop, and fails when he is stuck over 2 s, further
than 10 cells over 8 s, seen jumping, or standing in a hazard; then a load
far off, a ride in each vehicle (the car, the airboat, the mower) and every
chapter's start. `-- verbose` names each moment, `-- trace=<from>-<to>`
prints him every quarter second. Measured at v3.7.0 and after pass 10 (the
same walks; seconds):

| | stuck, longest | far, longest | in the sights, all | in harm, all | 90th percentile apart |
| --- | --- | --- | --- | --- | --- |
| v3.7.0 | 12.0 (Hickston), 2.4 to 3.3 on five more | 12.6 (Hickston), 10.8 (the ridge) | 45.2 | 1.8 (burn barrels) | 3.3 to 17.3 cells |
| pass 10 | 1.6 | 2.2 | 30.0 | 0 | 3.6 to 6.5 cells |

(The walk turns a full circle at every stop, its sights sweeping over him;
most of what is left in the sights is a third of a second a turn.) The
rides: the airboat with him 35% of the ride and him not back at
heel 12 s after, now 100% (riding) and back at once; the mower 20% and not
back, now 100% (following) and back in 3.1 s; the car 64%, now 85%.

#### Calm and easy to look at (pass 12)

The owner: "he's a frickin speed demon and hard to even look at".
`tools/hound_pace.gd` (below) measured why, a row a tick. He ran 7.4 cells
a second (1.9 times his player's run, a racing greyhound at his size) back
to heel whenever he was over 3.4 off, and his heel spot followed where his
player looked, so a player turning on the spot sent him sprinting round
behind them; by a player standing he ranged out at 3.3 and back at 5.4 a
few seconds after every stop (33 cells in 24 s, 10 sprints a minute); he
stepped out of the sights at a run as a look swept past; he sped up and
slowed at 10 cells a second each second and stopped dead; he turned 10
radians a second at any pace (pivots at a run, sliding sideways along walls
facing into them, 46 degrees off his facing at the 90th percentile); his
legs went into the trot at 1.8 and the gallop at 5 by the tick's own speed,
so his gait flickered (22 pose pops a minute); and his feet skated: a
planted foot went back .14 of the ground he covered in the walk, .42 in the
trot, .14 in the gallop (and Godot's import dropped keys from his motions,
below). A cell is about 1.85 of his metres, so his player walks about
5 m/s; a real coonhound trots 3-4 m/s and seldom gallops, so at heel he
lopes with a walking player and gallops only to catch up.

- **Pace.** With his player: their own speed (where they truly went,
  `Dog.p_v`: running into a wall is standing), `heel_gain` a second more for
  each cell off his place, at most `heel_extra` quicker; well behind, the
  lope (`lope` 4.2); ranging out and circling back at their pace and
  `range_extra`; beside a running player he does not range. `run` (7.0)
  only with a reason: catching up from further than `catch_far` .7, after a
  hand, out of harm. To bay, point and fetch, and greeting: the lope.
  Asides at `aside_pace`, and only after `aside_after` in the sights (a look
  sweeping past no longer sends him off). Round a still at an amble.
- **Easing.** `accel` 3.5, `decel` 6 (cells a second each second). `head`
  brakes for its goal (no faster than he can stop in, plus his player's
  speed when the goal goes with them), for a sharp corner in his planned
  way ahead (down to a trot at it) and by his player's legs; `halt` coasts
  him to a stop.
- **Turning.** No quicker than `HoundLegs.turn_rate`: `turn_slow` (4.5
  radians a second) at a walk down to `turn_fast` (3.0) at a run, so he runs
  arcs; facing well off his way, or with his goal inside his turning circle,
  he slows to an amble to turn. He faces the way he truly went (along a
  wall too); shoved well wide of where he means to go he turns on round
  toward it (wedged, he went to and fro facing a wall). `TURNS` ends with
  straight back; pinned where every little step goes nowhere (the level's
  settling pushes him back), one `HoundLegs.STEP_LEAST` step gets him out.
- **Heel.** Behind the way his player goes, not where they look
  (`HoundLegs.heel_spot`). His player standing, anywhere `heel_near` to
  `heel_far` from them will do (`HoundLegs.home`: the nearest easy spot on
  his own side, not round behind them, unless he is right in front of their
  face) and he settles (`HoundMoods.settle`: he turns his head to them only
  when he faces well away); after `range_rest_still` he ranges round them
  again. A player walking into him: off their path and on ahead
  (`HoundMoods.make_way`); he goes round any player close in his way
  (`HoundLegs.round_players`). A kick shoves him over a few ticks
  (`Dog.knock`), not half a cell at once; a car coming, he bounds off facing
  where he goes. Ranging beside a player going on, only to a spot ahead of
  him (he wheeled round and ran back). His point or bay ends when his
  player has gone on past `catch_far` .7.
- **His legs** (`HoundLooks`). The gait by `Dog.stride_v`, held between
  thresholds (`gait_of`: into the trot over `TROT_FROM` 1.5, back under
  `TROT_TO` 1.0; into the lope over `LOPE_FROM` 2.6, back under `LOPE_TO`
  1.9; standing under `STAND_TO`), so it never flickers. Play's `Dog.gait`
  gains `beats_per_cell` a cell in the gait he is in, so the stride runs on
  across a change of gait: his feet hold `HOLD` (.9) of the ground, from
  `STRIDE` (how far a planted foot goes back a beat in each gait's keys,
  measured off the model), and go no more than `CADENCE` strides a second
  (past it, flat out, they slip a little rather than scurry). A pivot on the
  spot steps. By his player standing he sits after `SIT_AFTER` and lies down
  after `LIE_DOWN_AFTER`; his idle round's scratch and sniff come only once
  he has stood `IDLE_AFTER`; between bites he stays braced in the lunge's
  last key.
- **His model** (art.md): longer strides with the shoulder blade swinging,
  a new lope, his toes no longer flying between feet, every key kept.

`tools/hound_pace.gd` (HOUND PACE OK, in check_all with `check`) runs him
beside a scripted player, a row a tick at 120 ticks a second: walking and
running the chapter's way, standing, looking round (a flick about at
12 s), stop and go, turning back, a told SIC, a pickup to point at, a car
coming at him, co-op; and sums each scene: his speed against his player's,
the share of time he dashes past them (over their speed and 1.5 within 5
cells), sprints (over 5) a minute, acceleration, turn rate, darts (his way
reversed at a trot or quicker within .6 s, his player not turned about), off
where he faces, pose pops (back to the pose before within .4 s), his feet
against the ground in each gait, the nearest to the eye, how much of the
view and how long over the crosshair, his own speed across the view, and at
rest how far he wanders and how often his pose changes. `-- out=<dir>`
writes the rows; `draw` (a window, scratch APPDATA) draws every tick and adds
the drawn model's planted feet. The walker puts its player on a cell it is
caught short of; the next second and a half is left out of the sums. The
check holds each scene's turn rate, feet, view and rest, and over the calm
scenes the middle and the worst of the rest (`BUDGETS`, `WORST`). Measured
on hickston, fair, quarry and bayou (40 scenes; the middle of the calm
ones; in `docs/godot3d/blue12/` before and after: the sums, hickston's walk, look and still a row a tick, the drawn feet and the model sheets):

| | dashing past his player | sprints a minute | his 90th percentile speed | accel p99 | turn p95 | off his facing p90 | darts a minute | pose pops a minute | feet: walk / trot / lope |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| v3.9.0 | 32% | 18 | 5.4 | 37 | 573 | 46 | 10 | 22 | .14 / .42 / .14 |
| pass 12 | 4% | 0 | 3.7 | 6.1 | 248 | 0 | 2.5 | 0 | .88 / .87 / .84 |

Drawn in a window (`draw`, hickston), his drawn model's planted feet slid
.58 of his speed walking with his player and .84 turning back; now .19 and
.48 (the measure is rough at an amble and on a pivot: .58 before and .71
now looking round). By a standing player (still) he wandered 33 to 61 cells in 24 s and
sprinted 10 to 34 times a minute; now he stays where he settled, sits and
lies down. The worst scenes left: a dog wedged on a level's corner jitters
until his stall hops him on (a scene's worst facing-off, 81 degrees), a
player walking him into a wall comes within .73 of the eye now and then,
and his feet keep .64 of the ground flat out. hound_walk_check after pass
12: stuck at most .5 s (pass 10: 1.6), far at most about 7 s (pass 10: 2.2;
he catches up calmer), no hazard.

#### BLUE shows the way (pass 15)

The audit's bots never got lost (they follow the pin), but the owner's word
was that a player does. `src/hound_lead.gd` (`HoundLead`, numbers in
`hound.cfg [lead]`): his player calm (no hand awake within `lead_quiet`, 14;
his mood easy; on foot, on the ground, not in deep water) and no nearer the
objective by the pin's walk for `lead_after` (30 s, looked at every
`lead_look`, .5 s of the game's clock) and more than `lead_least` (6) steps
off it, BLUE takes the job LEAD: he lopes to a stop `lead_reach` (5) steps
down the way (short of a shut door on it, where he waits pointing at the
door; never in harm; fair for him and, as he picks it, out of every
player's sights), turns back to his player with a bark (`hound_bark`) and
stands on point down the way (the point pose; the badge says LEADIN'). As
they come within `lead_near` (2) he goes on another stretch, barking every
`lead_bark` at a stop. Getting `lead_gain` (20) steps nearer than they were
stuck at, or near the objective, ends it (back on the way); a hand awake
near, a mood, a seat in a vehicle, a partner's sights, his player off the
other way (past 4 cells and walking off, or further than `lead_far`), or
`lead_wait` (12 s) at a stop with nobody coming, and he gives it up till
`lead_again` (60 s) after. Mundell says a "lost" line once a stuck spell
(`barks.gd` "lost": BLUE KNOWS THE WAY. / FOLLER THE HOUND, DUMMY.), and the
first time NEW PLAYER TIPS says BLUE'LL SHOW YA. FOLLOW HIM. (`lead`).
With HOUND DOG off the objective pin jumps and blinks chalk-green brackets
for `pulse_for` (8 s) instead, and Mundell says a "lost_pin" line (TURNED
AROUND AGAIN. MIND THE ARROW. / I KNOW THESE PARTS. MOSTLY.): looks only,
this machine's, the hound feature's tick with him off (`HoundLead.alone`,
`hud.gd objective_pin`).

- **The walk.** Play never reads `Game.route` (a VIEW field the HUD walks
  over several frames), so the walk BLUE reads is his own: a field from the
  objective with doors as the pin takes them (and barred doors one way),
  walked in one go whenever what it was walked with changes (`HoundLead.sig`:
  where to, the stations, the keys, the doors only something opens, the
  walls, the floor's open cells), 3 to 6 ms on the desktop, once an
  objective or so; while any door swings the look waits (a leaf blocks the
  cells by it for a moment: the walk never depends on where one was). It is
  never carried: a snapshot copy walks it again from the same things and
  reads the same steps.
- **Carried.** The job and `Dog.lead_best`, `lead_at`, `lead_said` (the
  stuck spell) go with the Dog (SIM, no dice); the stop is `Dog.goal`, what
  he points at `Dog.look`, the stop's time `Dog.until` (the BAY/POINT
  fields, free while he follows). Co-op: each Dog leads his own player.
  `HoundLead.ON` false (tools that measure his legs: `hound_walk_check`, the
  stuck and barred-door checks, `flow_report -- lead=0`) and he never leads.
- **Calm to look at.** He lopes (`lope`), eases and turns as ever; it starts
  only after 30 s, so `hound_pace`'s scenes (30 s at most) never see it.

`hound_check` LEAD holds it (checks.md).

### Mundell's junk bench (content pass 8)

Scrap to pick up and a bench to spend it at on duct-tape mods for the main
guns, in the campaign's chapters and the Crossroads, alone or in co-op
(`BenchMods.on`: not the range, County Run, a player map, a boss rematch or
the versus modes; County Run's runs and daily board are balanced on its own
guns and offers, so it keeps them). JUNK BENCH (PLAY page, `bench`, on)
turns it off; a game reads `bench` from its options with 0 when missing, and
the front end sets it to 0 when a tool or view tour runs (`main.gd`), so
every older check, replay and picture is unchanged. Numbers in
`data/tuning/bench.cfg`; code `src/bench_mods.gd` (the mods),
`src/features/bench.gd` (a SIM feature: the benches, scrap, USE),
`src/bench_screen.gd` (the board).

- **Scrap** is a pickup (`item_scrap_bolts`, `_wire`, `_hubcap`: 1, 2, 3)
  taken as any pickup (`game_world.gd collect`), carried on the player's
  `Armory.scrap` (at most `most`). It drops (game.rng) from a hand killed
  (`enemy_chance`, the tougher kinds more), every piece of `boss` from a
  boss, a breakable broken (`props` by picture), a vehicle wrecked and a set
  piece come down (looked for every 15 ticks, each once, saved); `count`
  pieces are laid beside a chapter's own pickups as it starts (once, saved).
- **The benches**: the Crossroads' in the Road Department's yard against
  the depot (`hub_at`); a chapter's near its start, out of the way the
  start faces, its back to a wall where it can (`_spot`, the same on every
  machine). Its model is `town_junk_bench` (props_bench.py) drawn through a
  sprite; it has no box: a player walking into it is put back out (hands
  can walk through one). The Crossroads runs no hands and no features, so
  game.gd hands its controls to `bench.hub_tick`.
- **Buying**: USE at a bench (`game_use.gd`, before BLUE) sets
  `game.bench_asked` for this machine's player; the front end opens
  BenchScreen (`settle`, every frame; shut when its player walks `leave`
  off, or by USE again: asked while up, `settle` shuts it, since the press
  reaches the game as a use before `steer` sees it held; Space is USE's, not
  a buy). A pick goes out as `Controls.buy` (the place in bench.cfg's mods,
  `take_pending`), so a replay, every copy online and co-op partners buy
  alike; `bench.buy` takes it only at a bench, once, with the gun and the
  scrap (`BenchMods.why_not`), says MODNAME TAPED ON with a strip of tape
  torn off (`bench_tape`, a made cue) and Mundell's `bench_buy` line.
- **The mods** (`Armory.mods`, bench.cfg ids, name order) are numbers on the
  gun's own weapons.cfg keys: `Armory.firing(slot)` is the section with
  the mods' `set` and `times` on (`BenchMods.firing`, cached), and the
  Armory reads fire_time, reload_time, max_reserve, damage, shot_noise, the
  scope and the spread through it (`num`); `Armory.mods_on` (set each tick
  from `game.bench_live`) keeps them out of every other game. Their own
  keys: `bayonet` (`Armory._jab`: FIRE dry or loading drives it into the
  hand in front, one under its share of health finished; a lunge in
  `_hold`), `burns` and `blast_scale` (`BenchMods.blast_of`, put on the
  blast in `game_combat.gd explode`: a flaming bolt lights what it reaches,
  `_light_up`), `fuse` (the dynamite's). The ten: PAWN SHOP SCOPE (ALT FIRE
  zooms 2.1, dead on, reach 36), SPEED LOADER (reload halved), CORN KNIFE
  (38, 1.55 reach, finishes under 40 %), PIPE CHOKE (spread .6, reach 1.4),
  DRUM MAG (320 carried, heat .6), COFFEE CAN BRAKE (climb .35, heat
  spread .5, 30 % louder), FLAMING BOLTS, TRUCK SPRING (bolt 1.45 faster,
  half the lob, cocks in .75), LONG FUSE (4.4 s), 3-STICK BUNDLE (radius
  1.4, strength 1.5, hurts you as much more).
- **Looks**: each choice of a gun's mods has its own pictures
  (`gun_<gun>__<shorts>_<pose>`, `Armory.art_name`; [art.md](art.md#guns-in-first-person));
  the status bar shows the mods on the gun in hand as marks on a strip of
  tape under its rounds and the scrap by the keys (`hud.gd _draw_mods`).
- **Carried**: saves (version 10: the armory's `scrap` and `mods`,
  `save_restore.gd _restore_bench`, a mod no longer in bench.cfg dropped;
  the drum's rounds pass the save check), the chapter kit (`loadout`),
  Modes.carry (online co-op's chapters and hub), the Crossroads' buys back
  into the chapter it leads to (`main_flow.gd bench_carry`); snapshots carry
  the Armory's fields as ever.

`tools/bench_check.gd` (BENCH CHECK OK, in check_all) holds it;
`tools/bench_frames.gd` takes its pictures in a window.

### County events (content pass 8)

Now and then a campaign chapter gets something nobody planned, so no two
runs through it go alike: a twister, a hog stampede, a revenue raid or (in
the night chapters) a blackout. `features/county_events.gd` (`CountyEvents`,
id `events`, a SIM feature, saved) plans and runs them; each kind is a file
of static functions on it: `src/event_twister.gd`, `event_herd.gd`,
`event_raid.gd`, `event_dark.gd`. The sights and sounds are
`features/event_looks.gd` (looks) and the 3D view. Numbers in
`data/tuning/events.cfg`.

- **The plan.** COUNTY EVENTS (PLAY page, `events`: OFF, SOMETIMES, OFTEN;
  SOMETIMES by default; a net match takes the host's, it is in the lobby's
  sim options). A game reads `events` with 0 when it is missing, and the
  front end sets it to 0 for tools and view tours (`main.gd`), so every
  check, replay and picture made before them is the same; off, not one die
  is cast. On the first tick of a campaign chapter, alone or in co-op (not
  the hub, the range, the Mothership, a rematch, County Run or a versus
  map), game.rng says whether it gets one (`chance_often`,
  `chance_sometimes`), which (`weights`; a blackout only in `night`
  levels) and when (`start_after`, OFTEN sooner). At that time it starts if
  it can: no boss awake and standing, everyone up, a place for it found at
  run time from the level (nothing in the chapter plans: a new chapter gets
  them for free). Else it tries again every `retry`, eight times. At most
  one a chapter, never within `boss_clear` of a boss. A boss fight starting
  cuts one short (the twister lifts, the herd runs off, the power comes
  back). Nothing it does shuts a way: a barn it tears down falls by the set
  pieces' own rules.
- **The twister.** `start_far` out (13 cells at least from the player) it
  touches down after the siren and the scanner (`warn`), comes across at
  `speed`, swinging a little off its line, passing `pass_near`..`pass_far`
  beside a player or right through a standing barn or tower within
  `aim_set_piece` of them, and lifts past the far side (on past the map's
  edge sometimes: the ground there is read with `LevelData.elevation_near`,
  the nearest cell's). Within `reach`,
  under the open sky only (`roof_over`: seek cover), bodies are drawn round
  and in; in the `core` a player is knocked flat and hurt (`bite`), a hand
  stunned and hurt (`bite_enemy`, credited to the nearest player), the
  breakables smashed, a set piece's parts torn (`set_pieces.blast` every
  `rip_every`: a barn comes down in its pieces, a tower over), the dead
  shoved, and a loose thing near torn off its place and flung round
  (`carry.fling`; in flight it hurts whoever it strikes, as a hand's throw).
  Drawn by `view3d/twister.gdshader` (`world_view.gd _twister_at`): the
  funnel, a cone of cloud bent and swaying, bands spiralling up it, frayed
  at its edges, debris silhouettes whirled in it; a torn skirt of dirt at its
  foot; the wall cloud it hangs from; forming and lifting, the rope shows
  from the cloud down to where it reaches. event_looks whirls breakables'
  bits (`fx_brk_*`) and dust round its foot and plays `tornado_roar` on its
  own bed (`Sound.BED_EVENT`), muffled under a roof.
- **The stampede.** A run of open ground (`run_least`..`run_most`, one
  floor height) through a point within `pass_near` of a player, preferring a
  long one that starts out of their sight; `count` razorbacks bunched
  `spread` wide gallop down it at `pace`, scatter at its end and are gone
  once out of sight. Trampled: a player knocked flat and hurt (`trample`), a
  hand stunned and hurt, a low breakable bowled over; a blast kills the hogs
  it reaches. The hogs are rows in the feature (not enemies: nothing to
  count), moved like a hand (`LevelData.move`), drawn by their own model
  (`scripts/blender/actors_hog.py`, `scenes/actors/hog.tscn`: a razorback,
  its frames `0`, the gallop `r0..r4`, `down`) through a stand-in
  (`ModeBodies.stand_in`, `hog<i>`), the gallop on their gait. Dust behind
  them, squeals, `hog_stampede` hooves on the event bed.
- **The raid.** A still standing (`EventRaid.STILLS`) within `still_far` of
  a player, else the hand with most of the county's others near it, up or
  asleep (`gather_far` off; one alone will do; it counted only hands awake
  until polish pass 9, so it started on the hickston alone), the way in
  tried on two more rings if `come_from`'s are shut; the squad set down
  round its way in (it stood on one point before); the squad (`count`, `count_hard` on HARD and up) comes in out of every
  player's sight `come_from` away where the player's flow field reaches.
  The squad is the first of `kinds` the game has: a `revenuer` kind when one
  is made (the hook), else the yard and shield deputies. They join the
  enemies after the level's own (`features/posse.gd` saves them) and count
  as varmints. Every half second a raider picks a fight with the nearest of
  the county's hands it sees (`grudge` both ways, the hand woken):
  `Enemy.tick` asks `CountyEvents.feud` before a brawl, and a raider in
  sight of its foe shoots (`shot_every`, `hit`, `hurt`; event_looks draws the
  streak) while the hand comes at it with its fists (the old brawl). At the
  still they bust it. Over when the last of them is down, or after `most`.
- **The blackout.** The breaker first: a spot on a wall `breaker_far` from
  the player, on their floor, that their flow field reaches (the quest
  switch's model, `town_quest_switch_off`, a red lamp blinking). Then the
  power dies in stutters over `fade`: `darkness()` (`dark` of the light
  gone) goes to the view as `blackout` (`view_light.gdshaderinc`: every
  surface darkened before the lights add theirs, the fog with it; lit
  windows' and signs' glow out) and the lamp props, street lamps and
  floodlights give no light (`view_lights.gd`); fires and lanterns burn on.
  Every player has a flashlight, on: L (KEYS page `flashlight`; the word
  names the bound key, `game.torch_key`: R3 on a pad, which works it while
  there is one and runs otherwise, and the touch LIGHT button, shown while
  there is one, `TouchControls.offer`; online and
  for bots `Controls.item == Game.TORCH`, 97; replay op `torch`) switches
  it. Its battery (`battery` seconds) runs down while it shines, flickers
  under `flicker`, dies; off, it gets `rest` a second back. Its beam is a
  spot light: `EventDark.spot_flags` packs the way (yaw, pitch) and cone into
  the light's flags (bit 2), and the shader lights a stepped hot middle,
  ring and edge in the cone, carrying further than a lamp. `lanterns` of the
  hands carry one (a warm light, `event_lantern` in the fist). Play:
  `Enemy.tick` scales how far a calm hand notices a player by
  `CountyEvents.notice` (`dark_sight`; `lit_sight` with their light on; 1 for
  a lantern hand). USE by the breaker (THROW THE MAIN BREAKER,
  `game_use.gd`) or `back_after` brings the power back. The battery shows on
  the HUD over BLUE's badge.
- **The word on it.** The civil defence siren (`tornado_siren`), the
  revenue men's sirens (`raid_siren`), `power_down`, `power_up`; Mundell's
  lines (`event_twister`, `event_hogs`, `event_raid`, `event_dark`,
  `event_light`); the radio: the scanner's call (`scan_twister`,
  `scan_hogs`, `scan_raid`, `scan_outage`), Dub's bulletin over the music
  (`RadioStation.bulletin`, `dj_bulletin_twister`, `dj_bulletin_outage`) and
  his word at the next break (`dj_twister`, `dj_hogs`, `dj_raid`,
  `dj_outage`).
- **Play, the same everywhere.** Every variable of the feature is carried
  (plain values; its numbers and the hogs' body are `SnapCodec.SKIP_FIELDS`),
  game.rng only. Saved in the save's features block (no new save version);
  a save from before them gets the chapter's own plan.
- `tools/events_check.gd` (EVENTS CHECK OK, check_all) holds it;
  `tools/events_frames.gd -- out=<dir>` pictures each in a window;
  `bot_campaign.gd -- events` walks the campaign with one played out at the
  start of every chapter.

### Walls break too

`features/wall_breaks.gd`, breakables.cfg `[windows]` and `[fence.<tile>]`.

- A window face is one wall piece showing a `_win`/`_lit` tile (or
  `trailer_window`); shot in its glass or blasted it swaps in place to
  `<material>_brk` (`tools/art/wall_break_art.gd`; `_brk` is laid by height
  like `_win`, see `LevelTiles` in `src/level_tiles.gd`) and stays a wall.
- A fence cell (stockyard) shot down to `damaged` swaps its faces to
  `stockyard_hit`, and at 0 hp `LevelData.open_cell()` makes it floor: its own
  face pieces leave `walls`, each solid neighbour gets the face
  `implied_walls` would give it, `walls_version`/`solid_version` bump (the
  automap signature; the 3D view builds only the chunks listed in `reshaped`
  again, [view3d.md](view3d.md#keeping-the-frame-cheap-track-r-before-v330)), both flow fields reopen
  it, and `stockyard_gap` stands in it as two plane sprites.
- This stays exact because nothing is rebuilt until something breaks: window
  and stockyard tiles are not `LevelTiles.TILED`, so their pieces are never
  merged runs and a swap or a removal touches only that cell's own pieces
  (keep a breakable fence tile out of TILED). `index_cells` needs nothing (no
  fixture or door moves); `solid` answers `blocked()`/`visible()`.
- Only cells whose opening joins no two stretches of floor the level keeps
  apart (`regions()`: doors a key, station, trigger, secret or blast opens
  counted shut), off the map's edge, outdoors, level with their neighbours and
  with nothing on them may open; the rest get shot about but hold.
- `tools/wall_break_check.gd` holds it (every level's cells opened at once).
  The Crossroads breaks nothing.
- **Plank walls** (polish pass N): `[fence.wood]`, `[fence.barn]` and
  `[fence.bayou_shack]` make the sheds', barns' and shacks' board walls
  break, and `[fence.stockyard]` gains two rules. `sheds`: a cell straight
  through between a roofed floor and the open air may open under its roof
  (`src/plank_walls.gd open_shed`: the gap takes the inside's roof, ceiling,
  floor, light and area, so the ceiling runs on over it, and every piece on
  its edges standing wholly above that roof, a barn's gable, stays). Only
  where its faces up to the roof are its own boards, the spec's `inside`
  tiles or trim, with no window on it, no door, gate, pane or deck
  (geometry) beside it, the ground level both sides and a roof at least 1.9
  over the gap. `under_roof`: a pen's fence inside a barn opens with its own
  roof kept and its neighbours' faces only their own height
  (`LevelData.open_cell(..., low)`). `straight`: only a cell open on two
  opposite sides. `only_open`: a cell that may not open is left whole (no
  building corner shot about). The region rule still holds for all of them.
  Today: the fair 35 barn wall cells and 32 pen cells, the sawmill 35 shed
  cells, the bayou 49 shack cells, County Run's Hickston 16 and bayou 52
  (Hickston's chapter sheds sit behind its gates, so they hold).
- A repeating plank wall (`LevelTiles.TILED`: wood, barn) is merged into runs
  at load; `PlankWalls.split` cuts a run at the cell before it is shot about
  or opened (the run keeps its place as its first part, the rest go at the
  end, and the chunks they were and are in build again through `retiled`).
  Shot about, the cell's own boards and the boards of a plank wall on its
  other face (`inside` tiles with a `<tile>_hit`) show `<tile>_hit`
  (`tools/art/wall_break_art.gd`; a TILED wall's `_hit` repeats as the wall
  does, `level_mesh.gd`), never a gable above the roof. Near the eye the
  planks are knocked out of the wall for real where the rounds struck
  (`features/wall_looks.gd`, below); `_hit` is the far-off look (its gaps
  the far side's boards in shadow, never black). The stumps stand in the gap
  (`<tile>_gap`, `_gap_1`, `_gap_2`: picked by the cell, each broken at its
  own heights). Nothing new is saved or carried:
  the fence cells' hp and stage were already (a save without them restores
  whole, so no save version; no map changed, so no layout).
  `tools/plank_check.gd` (check_all, quick too) holds it; railings, stairs
  and decks (geometry pieces) do not break yet.
- **In layers** (content pass 8, remade in pass 11): content pass 8 meant a
  window's first round to crack it (`<material>_crk`), but those tiles were
  never in the game's tile list (`data/index.json`), so every window went at
  its first round, and play is kept so: the first round breaks it (its bits,
  its specks, heard at `heard`, `broken`). A round under `[windows]
  crack_most` only shows it held in its frame (`WindowFace.cracked`: its
  tile as it was, the crack web laid where it struck by `wall_looks.gd`);
  the next round, a blast or a body shoots the glass out (`_shoot_out`: its
  picture and its sound only, no dice spent, nobody hears more). A blast
  shoots a window out to `<material>_bst` (its frame torn out too, the wall
  round it sooted: `wall_break_art.gd _blasted`, laid by height like `_brk`,
  its material its wall's; `WindowFace.blasted`). Both are saved (the
  feature's `cracked` and `blasted` lists; a save without them puts the
  window back shot out, `_brk`), so no save version (a feature's block takes
  new keys). A breakable sign (`sign=true`) with
  a `<sign>_crk` picture (`build_break_art.gd`) that a round under
  `[all] crack_most` would break cracks first (`Piece.cracked`, carried; a
  client's picture put right in `sprites()`) and goes on the next.
- A swapped tile (`LevelData.set_wall_tile`: a window shot out, a fence shot
  about) adds the piece's start to `LevelData.retiled`; the 3D view builds
  only the chunks round it again (`LevelMesh.build_static(base, only)`, a few
  milliseconds; the whole level is 70 to 150). Before this the 3D view kept
  showing the whole window.

### How walls look taking a beating (destruction pass 11, WALLS)

`features/wall_looks.gd` (LOOKS_FEATURES: own dice, never carried or
saved). `wall_breaks.gd` tells it where and how each fence cell and window
was struck (`fence_struck`, `window_struck`: SHOT, BLAST, BODY) as it
happens; a client or a save put on only sees the fences' hp and makes the
knocks it did not see up from it (seeded by the cell). Nothing in play
reads it (`wall_looks_check`: the same hp, stage, walls and flow without it).

- **Planks.** Each fence cell keeps, for each of its eight planks (an
  eighth of the cell along the fence, in world terms so both faces agree),
  the stretch knocked out `[lo, hi)` in sixteenths of the cell's height. A
  round (a share p of the cell's hp) wears the plank it struck `5p`; past
  .8 a chunk `.05 + .3p` either side of where it struck goes; the next
  round there widens it, past six sixteenths the shorter end lets go,
  past eleven (or enough wear) all of it. A heavy round (p >= .4) wears the
  plank beside it too. So a revolver knocks a chunk out each round, a load
  of buckshot (each pellet light) tears ragged chunks across a few planks,
  a blast tears out the planks facing it round its height (the nearest
  whole, ragged), a body breaks them from the ground up.
- **What flies.** Every stretch knocked out flies as that piece of plank
  (its tile's column, `t:<tile>@1,1|planks:8,1` drawn stretched to its
  length: `Wreck.shape`) out the far side along the shot, turning, with
  splinters (weapon_fx) back toward the gun and `pierce_plank`. Gone
  through, what is left over the stumps bursts out along the shot (away from
  a blast, harder) in whole lengths (none over `BOARD_LONGEST`),
  `pieces_most` (10) of them as boards, and a stockyard's rails go in
  halves. Its own chips are left out (`burst(..., keep = false)`: the dice
  spent as ever) and its `bits` are 4, so the boards read, not a cloud of
  specks.
- **Drawn.** `view_rows()` hands the 3D view the 32 cells nearest the eye
  (rows 9 to 12 of `view_data`); the world shader cuts their planks out of
  the faces along the fence (`world_body.gdshaderinc plank_damage`, kind
  `KIND_PLANKS` for `LevelMesh.PLANK_TILES` and their `_hit`): what is
  behind shows (the yard, the room, the far rail), the ends broken in teeth
  with a pale splintered edge, a plank's side by a gap shadowed, the
  stockyard's posts and rails kept. A hole on a stretch knocked out goes
  with it. No retiling: only the rows change.
- **Windows.** A window held cracked shows its crack web (`fx_glass_web_N`,
  as big as the glass round that spot allows) as a wall mark where the round
  struck (a made-up spot where nobody saw it). Shot out,
  the pane is cut fresh round where it was struck (`cut_pane`: 7 to 10 rays
  from the hole, two wobbling rings, no piece over `SHARD_MOST`): the
  pieces in the inner ring and any past `[windows] shards_most` (14, 6 on a
  phone) are thrown as glints (`glints`), the rest as shards (one template
  triangle of `fx_shard_glass`, half its texels clear, drawn through a shape
  to each triangle) flying from the hole by the round's force (a blast's
  harder, all over the pane). A shard landing hard breaks again: a big one
  in two, a small one into glints lying where it fell (`shatter`,
  `glass_settle`). A blast throws the frame's sticks too.
- `tools/wall_looks_check.gd` (check_all, quick too) holds it;
  `tools/walls_frames.gd` pictures it (before and after:
  `docs/godot3d/destruction/WALLS/`).

### In real pieces of themselves

`features/wreckage.gd` (looks only: LOOKS_FEATURES, own dice, never carried,
saved or in anyone's way), `src/wreck_cuts.gd`, `src/wreck_physics.gd`,
`view3d/wreck_layer.gd`. Broken scenery comes apart in real 3D pieces of
itself on the chapters, the County Run maps and the hub (none on the 5v5
and 2v2 maps: breakables.cfg `[pieces] never`):

- **What comes apart how** is each breakable's `pieces` (breakables.cfg),
  cut by `src/wreck_fracture.gd` (destruction pass 11): `boards:n` (crates,
  coolers, the TNT and ammo crates, the alien crate, the outhouse: each side
  in n boards, a little uneven, each snapped across at one or two slanting
  breaks, more near where it was struck), `staves:n` (the mash barrel and,
  stood up from its picture, the yard's `prop_barrel`: curved staves round
  its axis, some snapped on a slant, its heads split by chords into disc
  pieces, its two hoops as real iron rings sprung open at a gap or broken
  into two or three bent arcs, what stands in it or off it in chunks),
  `table:n` (the picnic table's top in planks, its legs and benches in
  splinters), `shatter:n` (jugs, jars, the cow tube, the nitro rack, the
  flamingo, balloons: n shards, small and many near the hit), `tear:n` (tin:
  propane, the hazard drum, gas cans, mailboxes: torn sheets curled out from
  the inside and dented), `burst:n` (hay, the prize bear: solid clumps, a
  bale's in flakes across its length), `splinter:n` (the pallet stack along
  its grain; a painted sign's face in n splinters, its back raw wood),
  `chunk:n` (camp chairs). `prop_crate` is a crate stood up from its picture
  (`boards:3`). A cell of a fracture is a seed's: the nearest seed, distances
  stretched along wood's grain (splinters come out long) or across hay's
  length (flakes come out thin); a triangle whose corners, middle and edges'
  middles share one seed lies in its cell whole, the rest are cut by the few
  seeds they touch only (`_cells`), so a model of thousands of triangles cuts
  in tens of milliseconds. Each piece's box is fitted to it (`fit`: its
  spread's longest way along x, its thinnest through y), so a shard lies on
  its face. Windows and fence cells are cut fresh each break by
  `features/wall_looks.gd` (above; `[windows] pieces` and a fence's
  `fence:n,v...` are only what wreckage.gd would throw without it).
- **The pieces are the thing's own look.** `WreckCuts.parts(key)` cuts a
  prop's baked model (assets3d/props, its first mesh), or a barrel or crate
  stood up from its picture, with real clipping and keeps its UVs, so a
  piece is drawn with the prop's own baked texture; a tile becomes boxes
  with that part of it on their faces. A key and each of its variants is cut
  once and kept for the process. A level's breakables are not cut while it
  loads: `attach` lists their keys (`WreckCuts.prepare`) and
  `WreckCuts.pump`, each tick, cuts the next, a model's (or a stood-up
  picture's) on a `WorkerThreadPool` task (its triangles made on the main
  thread first; the worker only reads them), a sign's or a tile's at once
  (a millisecond or two). The mash barrel, about 2,900 triangles, is the
  slowest at about 100 to 160 ms a variant (its model read included); a
  level's kinds each have one within its first second or two and all their
  variants within a few more. A key asked for before its turn (something
  broke at once) is cut there and then, or waited for if the worker has it;
  a break otherwise uses only variants already cut. Looks only: the pieces
  are the same whichever thread cuts them (`load_check`).
- **Never the same twice.** A fractured key is cut in up to
  `WreckCuts.VARIANTS` (6; a model of more than `HEAVY` triangles 3)
  variants, "<key>^k", each with its own dice and its own fracture origin
  (`WreckFracture.origin`: round its sides at heights that change with k).
  Only each kind's own is cut in the level's first frames (as before, on the
  worker; a painted board's splinters too). A kind that breaks asks for its
  next two (`WreckCuts.more`), cut on the worker only while no piece flies
  (`pump(quiet)`), so only what breaks gets more of itself and nothing is
  cut in a fight's thick or in a quiet level (pass 11's first cut of every
  variant at the start cost every frame of a level's first seconds up to
  half again: a worker running GDScript slows the main thread). A level's
  start drops what an earlier level asked for. A break takes one of the two
  or three cut variants whose origin is nearest where it was struck, never
  the one that kind broke as last; a barrel's is turned about its axis to
  face the hit (`WreckCuts.round_about`). Without threads (the lite browser
  build) each break of a kind cuts its next variant there and then, up to
  `LITE` (2; heavy models keep one). Tin, glass and rubber pieces are their
  skin alone (`SHEER`: drawn both sides, no inside face or rims).
- **Thrown by the hit** (`wreckage.gd _break_piece`, `_burst_apart`): the
  hits that broke it (`_hits_for`: each pellet where it struck, or the blast
  gone off near it in the last `BLAST_TIME`) both pick the variant
  (`_impact_of`: where, which way, how hard: their strengths together over
  `BREAK_PUSH`, about .4 a revolver round, 1.3 buckshot at arm's length) and
  knock the pieces through the one impact model (`WreckPhysics.impact`,
  wreck.cfg `[impact.*]`: harder near the hit, spun by an off-centre push);
  with no hit known (a thrown thing, a car, a swing, a client's mirror) its
  side facing this machine's player, .7. A revolver round chips it open,
  buckshot blows it apart. Each piece is `WreckPhysics.add`ed with the
  thing's stuff (a hoop iron) and its cut's form. One break throws at most
  `per_break` pieces (18, `per_break_phone` 10, `per_break_county` 10 on the
  County Run maps, one long fight; the biggest), none that would
  start with three corners in a wall (`_walled`). A shot that does not break
  a thing knocks chips off where it struck (`prop_struck`, `wreck_burst.gd
  chips`; its hp untouched).
- **Cut faces are raw** (wreck.gdshader): a piece's skin keeps the model's
  UVs; its inside face (set in by its stuff's `THICK`; hay and stuffing as
  solid lumps) and the rims joining it to the skin carry vertex colours
  (alpha 0, red its stuff, green 1 a rim) and draw one texel of the piece's
  own texture worked toward the stuff: fresh pale wood with fine grain on a
  rim and its weathered back inside, a bright raw tin edge, clay's
  terracotta body, a glass glint, straw, a cooler's white foam, iron with
  rust specks, in hard 64ths of a cell. Nothing is smeared across a face.
- **Fine debris** (`src/wreck_debris.gd`, `features/wreck_burst.gd`): with
  the real pieces each break throws splinters, shards and glints, slivers,
  straw and crumbs by its stuff (counts and sizes `BITS`, the thing's own
  colours and the stuff's): points with a spin that fall, bounce off the
  floor under them (asked when they have gone half a cell), stop at walls,
  slide and lie, and shrink away after their life; never the solver. At
  most `fine_most` (80, `fine_most_phone` 32); drawn as one MultiMesh by
  the wreck layer (the sprite "~~fine", its `who` the debris), written again
  only while some move. A dust puff (`features/dust.gd`) goes up off wood,
  hay, clay and plastic, and a second sound by stuff and force plays under
  the break's own cue (`LAYER`: `break_splinter`, `shard_rain`, `tin_tear`,
  `straw_burst`, ElevenLabs pass 11). Landing clinks are by stuff too.
- **Remains** (`scripts/blender/props_broken.py`): the yard barrel and the
  mash barrel leave a low ragged stump of snapped staves in their bottom
  hoop (`_stubs`), the jugs their feet in teeth, the crate a low ragged
  back, the hay bale its slumped bottom flakes; their staged lying pieces
  are mostly gone (the real pieces lie there now). Remains are play's
  broken picture: the same every time.
- **New breakables**: `town_picnic_table`, `town_camp_chairs` and
  `town_outhouse` break (`gone`: no broken picture, nothing stands where it
  was, its base opens the way as a crate's does; `never` on the versus maps).
  This is play (they stop shots, take hp and free their cells, the same on
  every machine); the pieces are not.
- **Physics** (`WreckPhysics`, on the shared core: see "The shared physics
  core" below): each piece a `PhysCore.Box` with a quaternion, slide and
  spin, mass and moments from its size; contacts are its corners (and points
  along a long stick) against the floor under it (`Tumble.floor_at`, so
  decks, stairs, ramps and furniture tops), roofs, walls, furniture sides
  and steps higher than `LEDGE` (`solid()`, pushed out along the shortest of
  x or y), other pieces (the axis two boxes overlap least, so a plank on a
  plank is pushed up; the middles of its edges when no corner is in the
  other, so two flat boards turned face to face stack) and the balls of
  ragdolls lying about (`Ragdoll.others`, held still). The core's fast
  solver (`PASSES` at most, stopping once a pass changes nothing), speculative
  contacts (`MARGIN` plus its speed) so a fall never passes through a deck,
  penetration pushed out after (pieces from one another first, then from
  the level by the deepest contact each way, so a pile never squeezes one
  into the floor). Pieces of one break pass through each other for `APART`.
- **What it asks the level**: a piece looks round once while it stays
  within `REASK` (`_look_round`: plain ground under all of it, a wall near,
  the highest floor under it, a roof near); one whose lowest point is
  `AIR_GAP` over every floor under it with no wall or roof near asks nothing
  more; else each point's floor, roof and "in something" are kept while the
  point stays put (`PhysCore.Floors`), and with no wall near a point higher
  than every floor under it is skipped. More than `GRID_FROM` pieces find
  their neighbours by the core's grid. A tick takes one step, not `steps`,
  while every awake piece is slower than `SLOW_V`/`SLOW_W`.
- **Sleep**: a piece sleeps when it has been slow `SLEEP_AFTER`, has gone
  nowhere for `HELD_AFTER` (even wedged a little way into something once
  awake `WEDGED_AFTER`), has crept on the floor slower than `CREEP_V` for
  `CREEP_AFTER`, or has been awake and slow `LONGEST`; going to sleep it is
  lifted out of any floor and wall it is a little way into. Asleep it costs
  nothing and remembers what it lies on (`Body.under`): when that wakes or
  is taken away (`remove()`), it wakes at once. One resting piece a tick is
  still asked whether it lies on something (a floor, a wall, a piece, a
  body; once until it is knocked again), blasts (`blast_shoved`) throw what
  lies about and this machine's player kicks pieces walking through.
- **How it is found**: the feature watches breakables' pieces, the windows
  and the fence cells (by their `net_version`) for ones newly broken, so a
  client's mirror throws pieces too; what is broken at the start, from a save
  or a snapshot put on (`restore`) throws nothing. A break throws away from a
  blast that went off near it in the last `BLAST_TIME`, else along the line
  from this machine's player (looks only).
- **Cost**: `[pieces] most` (48, `most_phone` 20) lie about at most; past it
  the oldest shrink away in `fade` and stop moving. More than `CROWD` (20)
  awake takes one physics step a tick instead of `steps` (2). On the shared
  core (engine pass 6) the hickston fight's `wreckage._tick` is about a third
  of what it was (tick_profile, headless, back to back on a busy desktop:
  0.76 to 0.25 ms; fair 0.60 to 0.17), and 48 pieces thrown at once 2.15 to
  1.28 ms a tick, worst tick 9.2 to 5.7 ms, all asleep in 4 s instead of 6. Idle (all
  asleep) a tick costs about 15 us; breaking everything on hickston at once
  (48 pieces in the air) peaked near 9 ms a tick headless on a busy desktop,
  a single crate about 1 to 2 ms for a second. A phone or the LOW physics
  tier (`Quality.level()`) takes `most_phone`; below HIGH a tick takes one
  step fewer.
- **Cost of the pass 11 breaks** (window, back to back with v3.8.0 on a busy
  desktop, medians of three): stress_bench wreck48 frame median 6.07 to
  6.35 ms, p99 12.1 to 15.3 ms, max 20.4 to 25.3 ms (the cut faces' inside
  faces and rims are about three times a piece's triangles, and the fine
  debris; at most `per_break` pieces a break and `fine_most` bits keep it
  near); hitch_bench's first wreck with a cold shader cache 23.2 to 27.5 ms
  (67 ms before the warm-up drew the cut-face and debris shaders). A level's
  variants are cut on the worker (about a second of worker time on
  hickston). A break makes at most `MESHES_FRAME` (8) new piece meshes a
  frame; the debris MultiMesh is written only while bits move.
- **Drawn** by `WreckLayer3D`: a sprite with `solid` "~<key>#<piece>" is that
  piece's mesh (made once from the cut), a MeshInstance3D a piece shown
  (kept for the next piece after), `wreck.gdshader` (prop.gdshader's light
  with the source's texture; a picture's clear texels discarded), lit in its
  cell as a prop is.
- `tools/wreck_check.gd` (check_all, quick too; CI) breaks every kind with
  `pieces`, a few windows and fence cells on seven levels and checks pieces
  fly, all come to rest within 15 s on a floor within .03 and never inside
  anything, nothing on the versus maps, the cap, a save throws nothing and
  the idle cost; and (pass 11, BREAKS DIFFER) two breaks of a barrel, a
  crate, a propane tank and a hay bale struck the same way come apart
  differently, pieces go away from the side struck and the fracture starts
  on it, buckshot throws harder than a revolver round, every piece names
  its stuff and shape and has raw cut faces, a break throws fine debris
  under its cap and a shot that does not break chips. `tools/break_frames.gd`
  (a window) pictures each kind shot the way play shoots it
  (`docs/godot3d/destruction/BREAKS/`, before and after);
  `tools/physics_frames.gd -- only=break` the barrel, window, fence, picnic
  table and hazard drums (`docs/godot3d/features/C/`).

### How the pieces move (pass 11)

`src/wreck_physics.gd`, `src/wreck_stuff.gd` (the stuff and form table and
the knocks' push), `data/tuning/wreck.cfg`, `src/features/wreckage.gd`
(looks only: own dice, never carried or saved; play's tumble.gd, corpses,
carry and the bowling pins' exact solver are untouched).

- **The API the breaks call** (BREAKS, WALLS, BLASTS; RAGDOLL uses
  `push_for`): `add(at, q, size, stuff, form, group)` puts a piece in, made
  of `stuff` (breakables.cfg's names: wood, tin, steel/iron, glass, clay,
  straw, stuffing, cloth, plastic, rubber, goo, char...; unknown is wood) in
  `form` ("board", "stave", "ring", "disc", "can", "shard", "chunk",
  "sheet", "clump"; "" a plain box), still until knocked.
  `impact(at, way, strength, kind, group, dice)` knocks pieces from a hit:
  each piece (of `group`, or all) is pushed at its own point nearest the
  hit, so an off-centre hit spins it, by how near that point is (half at
  the kind's `reach`), along the hit, out from it and up by the kind's
  shares (`[impact.shot|break|blast|kick|ram]`); a shot's strength is an
  impulse (light pieces fly, heavy ones nudge), the others a speed (heavy
  pieces somewhat less); a blast behind cover pushes `hidden` as hard.
  `push_for(kind, at, way, strength, point, middle, seen, dice)` is that
  push for any point (a ragdoll's ball as well). `burst(group, mid, speed,
  dice)` parts a break's pieces from its middle by the stuff's `burst`.
  `ray(from, to)` finds the piece a shot enters. After each step `cracked`
  lists pieces knocked harder than their stuff's `crack` (for the breaks to
  split), each body's `hit` its hardest knock. `WreckCuts.Part.form` names
  today's cuts' forms (staves, lids as discs, hoops as rings, boards,
  shards); a barrel's hoops are iron.
- **A break comes apart from its hit**: wreckage keeps the shots of the last
  `SHOT_TIME` (`traced`: from the shooter's eye to where each pellet ended)
  and a break throws its pieces apart (`burst`) and then knocks them from
  each pellet that struck it (`_hits_for`; many pellets are many smaller
  knocks), else from the blast just gone off near it, else from its near
  side along the old knock. Struck on its left it flies right; the same
  break twice from the same hit is alike (the feature's dice).
- **Material and form**: the stuff gives weight, bounce, grip, the spin and
  slide lost a second on the floor; the form scales those (wreck.cfg).
  Discs, rings and cans are round: their touching points are the lowest,
  highest and two side points of each rim, worked out each step
  (`Body.rims`), so they roll on their edge; their spin keeps its momentum
  as they turn (`_turn_round`: a coin leaning over curves and wobbles); a
  round one rolling slower than `ROLL_UP` is leaned `WOBBLE` every
  `TIP_EVERY` and goes over like a spun coin; moments are a disc's, a
  ring's or a cylinder's. A sheet in the air is held back across its face
  (`drag`, `_flutter`): it falls slower and rocks. Shards grip and stop
  short, hay hardly bounces. Corners sweep: a spinning piece's contact
  margin counts its spin, a corner swept deep under a floor its middle is
  over is still that floor (`DEEP_FLOOR`), and a point in a wall cell is
  never let under that cell's ground. A piece going to sleep still in
  something at both ends (a board across a gap narrower than it) is turned
  about upright (`TURNS`) or laid flat until it fits; where nothing fits it
  is `stuck` and wreckage shrinks it away.
- **Knocks**: a shot (any player's hitscan, `traced`) passing into a lying
  piece knocks it at the entry point by the gun's damage (`[knock]
  shot_push`); a blast (`blast_shoved`) knocks from where it went off by
  distance, less behind cover; players, the county's hands, BLUE and the
  vehicles walking or driving through pieces kick them at their edge along
  their way, harder the faster (`_kick`: walkers near the pieces only, their
  speed from where they stood last tick). Fence boards shot off are knocked
  back toward the shot (not through the fence) and a broken-through cell's
  boards out across the fence's line. The county's hands kick only within `KICK_SEEN` (14 cells) of this
  machine's player and each piece once in `KICK_AGAIN` (1 s): a County Run
  horde walking through a yard of pieces kept them all awake (wreckage's
  tick 0.76 ms to 0.29 there).
- **Sounds**: the two hardest knocks a step are heard by the stuff's `cue`
  (`cue_hard` past half its `loud`), louder the harder, higher for small
  pieces, at most `sounds_most` a second and one a piece in `gap`; a metal
  hoop or lid wobbling down rings (`spin_cue`). The cues are `wreck_*`
  (audio_spec.py, pass 11; wood and tin have other takes, `alts`).
- **Cost** (`tools/wreck_bench.gd`, which also counts the work, the same
  on a busy machine): against v3.8.0 hickston's wreck48 takes about the same
  awake piece-steps (5,500 to 5,570 over 5 s) and about 13 % more contacts
  (19,000 to 16,800: the throws are flatter, more pieces slide), all asleep
  in 4.9 s (4.3); breaking every breakable on hickston at once the same.
  Timed back to back on a busy desktop the means were within the noise
  (wreck48 1.9 to 2.0 ms, every 1.6 to 1.4 ms a tick, medians of three);
  the throw tick costs more (the knocks and parting: a few ms for a hundred
  pieces). The impacts' numbers are read once (`WreckStuff.kind_of`), a
  break's knocks walk only its own pieces (newest first), and a piece
  leaning in a pile on chunks that merely stand (`SLENDER`) is held, so piles
  do not keep jiggling.
  Pass 13 (HEAVY) took a fifth off the tick, exactly (the pairs both ways
  from one set of dots in `src/wreck_pairs.gd`, each piece's corners turned
  once a step, `way_out` asking no table twice for one cell's furniture):
  [view3d.md](view3d.md#keeping-the-frame-cheap-track-r-before-v330).
- `tools/wreck_motion_check.gd` (check_all, quick) holds all of it;
  `tools/wreck_motion_frames.gd` pictures it (`bare` leaves out what stays
  standing where a thing broke); `docs/godot3d/destruction/PHYSICS/`.

### The big breaks (content pass 8)

`features/set_pieces.gd` (SIM_FEATURES and FACT_FEATURES, saved),
`src/set_piece_shape.gd` (what each is made of), `src/set_piece_flow.gd` (the
gas and the flood), `src/set_piece_mesh.gd` (their pieces as wreck-layer
cuts); numbers in `data/tuning/set_pieces.cfg`; a level lists its own in
`"set_pieces"` ([levels.md](levels.md#the-big-breaks)). Three kinds, none on
the versus maps or the hub (`[all] never`):

- **A barn or hay shed** (`barn`): posts down both long sides, top plates, a
  ridge, tin sheets on two slopes and plank walls on the sides its spec
  names (the front stays open). Each post and wall panel is a part with hp;
  standing, the posts and walls are LevelData volumes (in the way of bodies,
  sight and shots; the paths shut round them, `FlowField.close`). Two posts
  out (`posts_out`), or the frame (`frame` hp) spent by blasts
  (`blast_frame`), rams (`ram_frame`) or fire in its footprint
  (`burn_frame`, `burn_part`), and it creaks (`warn`): dust sifts, the call
  goes up (`call`), the county's hands round it run (`flee`, their
  `retreat`, without `responded`: a save holds such a retreat since polish
  pass 9, where Python's save check refused it). Then it comes down in its own pieces: the tin drops and slides
  the way it leans, the walls go over on their bottom edges, posts and
  plates fall, each a little apart in time (game.rng). A wall panel shot
  about shows its tile's `_hit` boards; shot through it goes over on its
  own and the way through it opens (its volume dropped, the paths
  reopened). A shed falls only the square ways its spec's `falls` allows,
  the nearest to its lean.
- **A water tower** (`tower`): four legs braced both ways, a deck, a stave
  tank with iron hoops and a tin cap. Two legs out on one side (or three, or
  the frame gone) and it goes over that way about its feet
  (`topple_time`); the tank, hoops, cap and deck burst where the tank meets
  the ground (the frame comes apart and its legs and braces drop flat,
  scattered) and the water floods the street (`set_piece_flow.gd`).
- **A fuel line** (`fuel`): a pipe along the ground through its `points` and
  hit boxes at its `pumps` (the level's own pump props). A pump or a length
  of pipe holed leaks: gas runs along the line both ways from the hole
  (`leak_speed`) and lies `gas_life`. Fire touching any gas cell (fire.gd's
  burning cells, a blast near) lights it and the fire runs along the line a
  cell every `run_step`, each cell `fire.ignite()`d for `gas_burn` and
  flaring `flare` into whatever breakable stands on it (a propane tank at
  the end goes up, and its blast lights the rest).
- **Debris matters.** Each piece that lands hurts whoever is under it by
  what it is (`crush_*`: players pinned `pin` seconds as a hog's charge
  knocks them, `Player.knocked`; hands held `pin_enemy` and hurt
  `enemy_crush` times as much, credited to the nearest player, so a hand
  lured under a shed dies) and breaks the breakables under it (hay bales; a
  propane tank goes up). What lies higher than `low` over its floor (and
  not overhead) is cover: a volume in the way, never laid over anybody and
  never shutting anyone in.
- **The flood**: the cells round where the tank struck, by a walk that
  favours the way it fell and keeps to the ground's level (no walls, rubble,
  steps or water), `flood` at most, cheapest first; its front rolls out at
  `flood_speed`, puts out fire (`fire.douse`), washes the gas away and
  shoves whoever it meets ahead of it (`wash`; a player knocked
  `wash_knock`, a hand floundering `wash_stun`), stands `flood_life` and
  drains in `drain` (water marks, `mark_flood_*`).
- **Play, exactly the same everywhere.** Every falling piece has a move
  (`HINGE` about a line, or `DROP` by gravity to its rest) worked out once
  when it goes; where it is is a sum of its move and game.clock
  (`pose()`), so nothing steps a body. The state is plain values (the
  pieces' hp, states, moves; the volumes added and dropped; the floods),
  carried (`NET_GUARDED` by `net_version`) and saved; restore() puts the
  volumes right on a load or a client (save version 9). The shapes, the
  trails and the looks are made from the level on every machine
  (`SnapCodec.SKIP_FIELDS`).
- **Hits**: `game_combat.gd` asks `ray()` in `hitscan` (a nearer breakable
  wins), `touch()` for a shot in flight and `blast()` in `_blast_shoves`;
  `vehicles.gd _bump` rams (`touch`/`strike` at the bump).
- **Drawn** by the wreck layer: each part's key
  (`t:<tile>@0,0|spbox:...`, `sptank`, `sphoops`, `spcone`) is cut by
  `SetPieceMesh` with the level's own tile by the metre; what stands (and,
  once nothing moves, what lies) is merged into one mesh a tile
  (`WreckCuts.put`: a few nodes, each holding its shader slots), what moves
  is drawn piece by piece; set piece parts are drawn out to `WreckLayer3D.FAR`.
  Once a part creaks, falls or bursts it is drawn in its own pieces instead
  (below, "Coming apart"); a tank burst throws its staves (those not torn out
  in the fall), cap and painted name as real pieces (`wreckage.gd`), and a
  breakable broken inside a barn come down (`rubble_at`) throws no real
  pieces: pieces wedged among the rubble's volumes cost the wreck physics 15
  to 25 ms a tick.
- **Sounds**: `collapse_creak`, `collapse_crash`, `tower_groan`,
  `tower_burst`, `gas_leak`, `gas_whoosh`, `plank_crack` (ElevenLabs, pass 8);
  `timber_snap`, `collapse_tin`, `collapse_rumble`, `hoop_ring`, `pipe_burst`
  (pass 11, played by the looks below).
- **Cost**: asleep (no tick) while nothing moves, leaks, floods or burns;
  awake its tick walks only its own few pieces. Measured in pass 8: see
  [checks.md](checks.md#benchmarks).
- `tools/set_piece_check.gd` (SET PIECE CHECK OK, check_all) holds it;
  `tools/set_piece_frames.gd -- out=<dir>` pictures each one standing,
  going and down in a window (`bench` times the frames instead).

#### Coming apart (destruction pass 11)

`src/set_piece_wreck.gd` (`SetPieceWreck`, owned by `wreckage.gd`: looks
only, its own dice, never carried or saved), with `src/set_piece_bits.gd`
(its pure parts, which a worker runs) and `src/set_piece_fx.gd` (the dust,
water, flares, splinters, shake and sounds). Play still moves each part whole
(the HINGE and DROP above; its volumes, crush and cover are exact as before);
the looks draw each part in its own pieces that ride its pose and then break
away, so a barn no longer swings down in whole flat walls and roof slopes:

- **The pieces** are `SetPieceMesh` `spsplit` cuts of the part's box (each
  piece shows the very part of the tile it showed in the whole box, so they
  read as the part until they part): a wall in runs of one to three boards,
  each snapped once or twice on a jagged line (a splinter point or a notch);
  the tin in separate sheets torn across; a post, a plate, the ridge, a leg, a
  brace, a pipe snapped along its length on splintered ends; the deck in
  planks. A hickston barn is about 100 pieces (`detail`; a phone or LOW
  `detail_low`); a post always snaps.
- **When each goes**: a share of its part's move (`early`, more where it was
  weak) breaks away in the fall: a post's top snaps off, the ridge and plates
  break and fold, sheets of tin tumble off, boards peel off a wall going over,
  a tower's legs on the leaning side snap (at most `flying` of a set piece
  in the air on their own at once: more ride their part down). The rest
  come apart where the part lands: most shake loose into their own place in
  the part as it lies, knocked askew and onto whatever came down there first
  (so the pile keeps play's layers, and its cover is where its pieces are),
  merged at once into a mesh with the rest of that landing's; `scatter` of
  them are thrown off onto the pile, `propped` of those left leaning on it.
  A post's foot stays standing, snapped. Every flight is worked out once when
  the piece goes (ballistic to the pile's height, a hop and a slide to rest;
  the tin skates further, the way it fell). The pile is a height map of what
  came down before (`CELL`), so later pieces lie on earlier ones. Nothing is
  stepped, nothing asks the level but the ground's height, and no piece ever
  meets the rubble volumes.
- **The creak**: the frame sways more and more toward its fall (`sway`: play's
  standing mesh turned, `sway_turn`), dust and chaff sift off the eaves,
  boards pop off the walls. Meanwhile every part's pieces are cut, with
  their schedule (`SetPieceBits.schedule`) and their riding group's mesh, on
  a worker (a barn is tens of milliseconds of GDScript); a part is drawn
  whole until its cut is in, and nothing of a set piece breaks away while
  any of its cuts is out, so the pile builds in the same order however quick
  the worker was. Without threads (the lite browser build) it cuts at once.
- **Landing**: each part throws splinters, hay (embers if it burned) and low
  billows of dust (`fx_barndust`, hard edged) that roll out along the ground;
  everything down throws a ring of them round the footprint. The view shakes
  by how near this machine's player is (`shake_reach`; play no longer shakes
  it).
- **A tower**: its legs snap, its tank tears open in the fall (the staves
  facing the ground burst out with a gush), its hoops spring off in bent bands
  (`sphooparc`) that land on the ground, its deck splinters, and the burst
  throws a fan of water (`fx_gush`). The flood's front breaks as it rolls
  (`Flow.looks`: `fx_gush` along the cells it has just reached).
- **A fuel line**: gas spurts from each hole while it leaks (`fx_gasjet`); a
  flare runs along the line with the fire (`fx_boom` where a cell has just
  lit), and each length of pipe bursts into pieces where the fire reaches it.
- **Never the same twice**: the dice are seeded by play's own record of how
  it came down (when it creaked, each part's hp left: which posts were shot
  out and how hard the walls were shot, the lean), so a client and a save see
  the same pile and the same fall lies the same, piece for piece. What
  brought it down weakens the parts near it (`_weakness`: hp spent, a post or
  leg out near it, a blast near, fire): more pieces there, breaking away
  sooner and harder, thrown away from the blast.
- **A save or a snapshot** put on (`sync()`): what is down lies in its pieces
  at once, nothing thrown. A snapshot reaches it through `set_pieces.gd
  restore()` (only when its facts changed, `game.net_facts`) calling
  `wreckage.gd sync_sets()`: until pass 12 a late joiner online (or a copy
  put back) saw every part of a fallen barn land again, dust and rumble and
  all, and lie whole (`set_piece_check`, `net_soak_all.gd`'s late join).
- **Drawn**: the pieces of a part that ride it to the ground together are one
  mesh (`spgroup`) until the first of them goes; the rest are each a sprite
  (`~<spsplit key>#<n>`); pieces at rest are merged on a worker into a mesh a
  tile (`sprest`), `MERGE_AT` at a time, and once a ruin holds `MERGED_MOST`
  merges (or all of it lies still) all of it is merged again whole, a mesh a
  tile (every mesh is a draw of its own). Dust and gushes are pooled sprites blended as a blast's smoke (hard
  edged), flares glowing (at most `puffs`, fewer on a phone); splinters and
  hay are looks specks (at most `specks`).
- **Cost**: see the pass 11 numbers in [checks.md](checks.md#benchmarks).
- `set_piece_check` holds it: the barn in more than three pieces a part and
  within its budget, every post snapped, every piece on the ground or the
  pile, merged once still, the same fall twice the same; brought down by the
  other posts, by a blast or at another time it lies otherwise; a save put
  back shows the pile; a tower's legs snapped, tank torn, hoops in bands on
  the ground, deck splintered. `set_piece_frames.gd` pictures it; v3.8.0 against
  pass 11 side by side in `docs/godot3d/destruction/COLLAPSE/`.

### The shared physics core (engine pass 6)

`src/phys_core.gd` (`PhysCore`) is what the loose things' solvers share:
the wreck pieces (`wreck_physics.gd`, looks), the bowling pins and the
midway's bottles (`range_pin_physics.gd`, play) and the ragdolls
(`ragdoll.gd`, looks). Pure GDScript, no dice, no threads, no native
physics, so play's users stay the same on every machine.

- **Bodies and contacts**: `Body` (middle, quaternion, slide, spin, weight;
  each solver's own body extends it with its inertia), `Box` (a box's
  moments, corners, edge middles, `extent`, `ball_out`), `Contact`, `Pool`
  (contacts handed out again each step).
- **Two solvers**: `prepare`/`solve` is the exact one, the pins' arithmetic
  to the last bit (bowling is play: bowl_lab rolls give the same pins, and
  `physics_core.gd` holds the old formulas against it); `prepare_fast`/
  `solve_fast` works each contact's turning terms out once a step (the
  body's inverse inertia in world axes, `Box.turned()`), uses two fixed ways
  across the normal for friction and stops when a pass changes nothing
  (`SETTLED`): looks only.
- **Grid**: a hash of map cells (`GRID`) for finding near bodies.
- **The level's questions**: `plain`, `plain_under`, `plain_rect`,
  `level_ground`, `in_wall`, `solid`, `way_out`, `ball_solid`, `rail_at`, and
  `Floors` (a point's floor, roof and "in something" kept while it moves
  less than `REASK`), for wreck pieces and ragdolls alike.
- **Space** (`PhysCore.space(world)`, kept on the LevelData): the wreck
  pieces about (`boxes`) and how many are awake (`stirring`). A ragdoll's
  balls are pushed out of the pieces (`Ragdoll._on_boxes`: a body lies on a
  plank; striking one at rest wakes and shoves it), and a body asleep wakes
  when a piece near it stirs (`_pieces_stir`). The pieces meet the ragdolls
  in `Ragdoll.others` (those on their level, `Ragdoll.level`): a board
  dropped on a body lies across it. All looks; a headless server has no
  ragdolls, so its pieces meet none.
- **Resting on**: `Body.under` is what a sleeping body lies on;
  `wake_resting_on` wakes every body on one that woke or went.
- **Not on it**: `tumble.gd` stays play's own point-body stepper (gibs, bits,
  bodies, rolling shots: SIM, arithmetic every machine must match), though
  every solver here asks its `floor_at`.
- Checks: `physics_check`'s part `tools/physics_core.gd` (the exact solver
  against the old formulas, the grid against asking everyone, `ball_out`,
  a box dropped, three stacked and knocked from under, the same throw twice,
  a body on a piece and a board on a body).

### Materials and penetration

- **What a bullet strikes is a material** (`src/materials.gd`: a level's tile
  names map to wood, timber, tin, steel, mesh, brick, stone, dirt, brush,
  glass, rubber, water; `_lit`/`_win` variants are their base). Hitscan sets
  `impact_kind` before `traced`, picks the speck and sound by it, and gives a
  hole its picture (`fx_hole_<kind>`); `traced`'s "wall:<surface>" stays the
  old four. The game's `burst()` spends the game's `rng`, so a strike still
  bursts the same count it always did. The material of a wall hit comes from
  `WallHits.wall_mark`.
- **Penetration is play** (`src/penetration.gd`): a gun with `penetrate` in
  weapons.cfg goes through that much wall (planks 1.0 a cell, tin .75, wire
  .25, brush .6; anything else stops it) and hurts the first hand behind for
  `penetrate_damage`, by the game's own tests, no dice (`pierced` announces
  it; `tools/feel_check.gd`, run by check_fixes, holds it).
- `features/impacts.gd` throws the chips and keeps the marks: holes, floor
  pocks, wall scorches, blood running down from `gore.walls`, each to a cap
  and a life from effects.cfg `[debris]`, the oldest fading first
  (`Assets.faded_art`, alpha-scaled copies). Each new hole takes one of its
  material's own pictures and size (`HOLE_LOOKS`, pass 11,
  `tools/art/wall_mark_art.gd`, drawn to read from four to six cells off): a
  dark hole with a pale torn rim and splinters sticking out in planks (.24
  across), a chipped crater with a chunk out and a pale dust ring in brick
  (.28), a punched hole with bright bent petals in tin (.2), a pale pock in
  stone (.2), each with its dust puff (tin's too now), under the same cap. A
  blast against a wall knocks two to four big holes (.34 to .48) of the
  wall's material out of its scorch's upper half (`_chunks`). Features add wall marks through
  `wall_marks()`. It also keeps the latest marking shots and blasts in
  `thing_hits` (looks only) for the 3D view to hole, scorch and char props,
  vehicles and wreck pieces ([view3d.md](view3d.md#marks-on-modelled-things)).
- `features/dust.gd` is gun smoke, boot dust, race-car and derby dust and
  embers off fires (`dust_cap`), drifting on `[debris] wind_<level>`.
- `features/feel.gd` puts the gun on springs (sway, each gun's kick from
  recoil/retreat/view_rise/settle/spring_damp, landing, blows) into
  `player.weapon_lag` and the view's kick into `view_kick` (game_view.gd adds
  it to the eye like the shake, never to the aim); VIEW BOB scales sway and
  landing, SCREEN SHAKE the blows, off means none. Sounds it wants are in
  `docs/feel_audio.md`.
- **The switch** (polish pass 9, `weapons.gd Armory.shown_gun`, looks only):
  a switch takes `SWITCH_TIME` (.23 s) as ever; for its first
  `switch_lower` (weapons.cfg `[all]`, .09) the gun put away goes down out
  of the view (eased in), then the new one comes up (fast out of the
  bottom, eased home). `Armory.drawn`/`leaving` are worked out as it draws,
  never carried (snap_codec `SKIP_FIELDS`); raising the gun from the
  holster has nothing going down.

## Vehicles

`features/vehicles.gd` (the feature), `src/vehicle_drive.gd` (the driving
sums, the `Spec` and `Ride` classes), `src/vehicle_cab.gd` (the seat view
and how the seat feels), `src/vehicle_hud.gd` (the driving plate),
`src/vehicle_looks.gd` (the car's painted dash, without a window),
`src/vehicle_finder.gd` (finding one), `features/vehicle_runs.gd` (the set
pieces built round them), numbers in `data/tuning/vehicles.cfg`. A level's
`"vehicles"`
list places them (`[kind, x, y, heading]`, level_builder from the plan's
`meta`): the airboat moored by Gator Bayou's dock walk, a stock car on the
speedway's pit row, a riding mower (the tractor model at half size) on the
chapel path at Hickston. Only the campaign and co-op have them
(`active()`); County Run's maps strip them (`county_kit.gd STORY_META`).

- **In and out**: USE beside a hull (within `reach`, roughly facing it; or
  `reach_wide` when nothing else is at hand to USE, a station or a door)
  takes the driver's seat, or the next seat (the airboat and the car seat
  two: a co-op partner rides along behind the airboat's driver, `ride_back`,
  or beside the car's, `ride_side`, and shoots); the prompt says DRIVE THE
  <NAME> / RIDE ALONG / BURNT OUT, and GET OUT while it stands. USE while seated gets out
  beside it (left, right, behind, front, a little further each way), never
  into deep water, a wall or another hull ("NOWHERE TO STEP OFF HERE").
  Hooks: `game_use.gd` interact/use_prompt, `game.gd _step_body` (a seated
  player is driven, not walked) and `_step_hands` (`hands_busy`: the car's
  hands are on the wheel unless a one-handed gun is out of its window,
  below), `damage()` (the vehicle soaks its
  `soak` share of what hurts the people in it), `net_predict.gd` (a seated
  client predicts only its aim).
- **Driving** (`VehicleDrive.throttle`/`move`): FORWARD/BACK throttle, brake
  and reverse; it steers toward where the driver looks (mouse, pad, touch:
  the same on every control set) or straight from STRAFE (the eye then turns
  with it); not toward the look while firing, so a shot to the side holds
  the course; JUMP is the handbrake (the car slides). Grip wears away the
  slide across its heading (the airboat slides most; its prop turns it on the
  throttle standing still; since the engine pass after 3.3.0 a little less:
  `grip` 1.1 to 1.6 and `coast` 1.1 to 1.5, so it floats less). `Ride.gas` is
  the driver's throttle this tick (plain number, carried; the cab's tach and
  the plate read it). The hull is three circles along it tested with
  `geo.blocked_body` (walls, furniture, closed doors, decks) and `floor_at`:
  a step taller than its `step` stops it (the car climbs the banked turns'
  .12 steps, never a stair); `floors` lists the only floors it runs on (the
  airboat: bayou water, deep water, marsh, mud), `slow_floors` slow it
  (the car off the asphalt and track). A blocked step slides along the wall
  and bounces back (`BOUNCE`); harder than `bump_from` it dents, and a
  fence or window in the way takes the knock a thrown body gives it
  (`wall_breaks.crash`). A ride wedged already may drive out.
- **Bodies**: a hand inside its hull at `ram_from` or more is run down for
  `ram` x speed, `how` "roadkill" (corpses.gd throws it as a blast throws a
  body, from behind it along the way it went: `Enemy.blast_at`); a boss takes
  a third and stops it dead. The mower's `blade` cuts what it runs over every
  `BLADE_EVERY` ("mower"). Anything else in the hull is put out of it, and
  players on foot too. Hands ahead of a vehicle faster than `dodge_from` step
  aside, one in `dodge_skip` (by uid) holds and shoots (the squads already aim
  at its driver). The breakables in front are struck (`breakables.touch` /
  `strike`): the mower cuts flamingos and crates.
- **Hurt and wrecked**: bumps, run-overs, its soak share and every blast near
  it (`blast_reach`, `blast_damage`, from `events.exploded`) take its `hp`; it
  smokes under half, burns under a quarter; at 0 everyone in it is thrown out
  (`eject_damage`, "WRECK") and it blows (`wreck_blast`, a shots.cfg blast)
  and burns `burn` seconds, then stays a burnt-out wreck.
- **How it looks hurt and wrecked** (destruction pass 11,
  `src/vehicle_wreck_looks.gd`, looks only, gun_fx's dice): under half its
  engine smokes (`smoke_at` in vehicles.cfg: the share of the way from its
  middle to its nose; the airboat's is behind), under a quarter black with
  sparks; a round whose line passes through its hull throws sparks where it
  went in (and pings now and then). Wrecked, parts come off by where the
  last blast near it was and how hard (`blasted()`): the near side's door,
  wheels and the end toward the blast most, the hood or top more often than
  not, thrown away from the blast; its glass bursts (glints) and
  `wreck_crash` plays. The parts are its own model cut in a grid
  (`CUTS`: the car's hood, doors, four wheels, trunk lid; the airboat's fan
  cage, rails and seat; the mower's hood, wheels and seat) with WreckCuts'
  clipping, put as `m:<model>|vw`, and thrown by `wreckage.throw_cut` (real
  pieces, scorched by `PART_CHAR`). The hulk is the rest of the model
  (`m:<model>|vh<mask>`, one wreck-layer piece, `vehicles.gd sprites()`
  shows it instead of the model): kicked up by its blast and dropped onto
  its rims, sagging where a wheel went, charring from `CHAR_FROM` to
  `CHAR_TO` as it burns (`View.Sprite.hurt`, `wreck_layer.gd`). While it
  burns: flames over it, a column of soot, embers, secondary pops (a small
  fuel ball, sparks, `wreck_pop`) every second or two; then it smoulders
  `SMOULDER` seconds. With LIGHTS AND GLOW off the old smoke and flames
  (`_smoke`) stay. A wreck already wrecked when seen (a save, a snapshot)
  shows its hulk whole and throws nothing. Each wreck rolls its own dice
  (from where and when), so which parts go differs; a thrown part striking
  the ground throws sparks and a puff of dirt (twice at most). Cost: each
  kind on the level is cut on a worker as the level starts (`CutJob`, about
  60 to 140 ms for the stock car on this busy desktop, `cut_ms`); the hulk
  is built on a worker as it is wrecked (`HulkJob`; its model shows under
  the fireball meanwhile), so the wreck's tick is about 10 ms headless
  (blast_check prints both). The lite build without threads cuts there and
  then.
- **The speedway's lap timer**: the car on the lap cars' racing line counts
  the turn round its middle; a whole turn is a lap (LAP n, the time, the
  best); off the line by `LINE_REACH` it starts again. The time and best are
  on screen with the speed (MPH) and the rig's health.
- **Play and looks**: each Ride is plain numbers, no dice, carried by
  snapshots (`snap_codec.gd` knows `VehicleDrive.Ride`) and saved in the
  features block (place, heading, health, wreck, seats; restore gets {} from
  older saves, so no save version, and adding a level's list changed no map,
  so no layout). Skid marks, the mown stripe and the clippings are `_looks`
  (skipped by snapshots); smoke and flames come from the clock; the driver's
  own model is left out of their view (the seat view instead, below; with no
  window, the car's painted dash and wheel, `VehicleLooks`). The models are
  stood on their heading by `nose` (the airboat's and car's were posed 20
  and 18 degrees round for their sprites and drove crabwise before).
  Sounds reuse cues: `airboat_wake`, `lap_car_pass`, `saw_motor`, `crunch`,
  `lap_car_hit`, `tire_roll`, `mower`.
- **How it looks on the move** (polish pass N; `src/vehicle_feel.gd`, looks
  only): each ride's body is on springs (`spring`, `damp` in vehicles.cfg),
  worked out every tick from how the ride itself moved (its speed along it,
  its turn, its floor's height, `bumps`) with the feature's own `_dice`
  (snapshots skip it and `_looks`): it squats back on the throttle and dives
  braking (`squat`), leans out of a turn (`lean`), takes a kerb or step on
  its springs, lands with a dip off a ledge, jars on a wall, jolts over
  rough floors (`rough` everywhere, `rough_off` more on its slow floors and
  grass: the mower bounces all the time), and the airboat rocks on the water
  (`rock`). A parked, settled ride costs nothing. The 3D view gets its model
  as a prop on the move (`View.Sprite.track` "ride<n>", `turn` the heading,
  pitch and roll, `z` with the bob; `PropView.relight` lights it in the cell
  it is in) and the seat's eye takes a little of the bob and pitch
  (`sway_eye`, from `game_view.gd`; EASY ON THE EYES: 70 %, 30 %, none; no
  roll of the camera); the car's dash rides a pixel or two. The car leaves
  two tyre streaks off its back wheels sliding or braking hard
  (`brake_skid`; black rubber `SKID_MARK` a tyre wide, `SKID_WIDE`: the pale
  thin wear decal before 3.3.0 read as nothing at 320 wide) and throws a
  spray of sparks where it strikes a wall (`sparks`; 6 to 14, a third of a
  cell, over half a second); the
  airboat throws spray off its bow (more in a turn) and leaves a wake of
  rings behind it (`spray`, the water feature's `ring`); the mower spits
  clippings out of its side chute. The engine's cue plays at a pitch from
  `ENGINE_LOW` standing to `ENGINE_HIGH` flat out (`game.sound_at(...,
  rate)` -> `GameSound.play_at_rate`). PHOTO MODE sees the car from outside
  (its model shown, no dash).
- **From the seat** (the engine pass after 3.3.0; `src/vehicle_cab.gd`,
  `view3d/cab_layer.gd`, looks only): the driver sees their own vehicle in
  the 3D view, a model of what a driver sees of it (`cab` in vehicles.cfg:
  the airboat's deck, green rails, bow lamp, cooler and a tach on a bracket
  off the left rail, the fan cage behind with its varnished prop, which
  fades into a stippled spinning disc as the engine works (`fade`); the car's hood with its scoop and
  stripes, A-pillars, windscreen bars, header, mirror and fuzzy dice, the
  dash with two gauges, window net, cage; the mower's red hood, grille,
  lamps, exhaust stack, the cutting deck out in front, fenders and a beer)
  with Mundell's hands on the controls (the airboat's stick, the mower's
  wheel at ten: the other hand holds the gun; the car's wheel at ten and
  two), the same weathered skin and flannel cuff as the photographed hand
  the guns are held in. `sway_eye` (from game_view.gd) hands the frame's eye a `cab`: its
  model, its turn (the body on its springs, `VehicleFeel.turn`, so the hood
  squats, dives, leans and bucks against the view, which takes only
  SCENERY MOTION's share of it), how much lower the eye sits in it
  (`cab_drop`) and how far it tips its nose up (`cab_tilt`), so the front
  shows in the old view's narrow height with the road still showing over
  it; and the moving parts' turns: the wheel (`cab_lock`, clockwise for a
  right turn) with the hands riding it, the airboat's stick, the needles
  (speed, the car's tach by its gear, the airboat's tach by `rpm`), the
  airboat's prop (turned in `_looks` while someone is at the stick) and the
  mower's blade lever (forward while the blade bites). Not for a rider, not
  in PHOTO MODE, not without a window or the cab's art.
- **How the seat feels** (`VehicleCab.dress`): the engine buzzes in the view
  (`buzz`, `buzz_hz`, more on the throttle; the hood buzzes a hair against
  it), the mower thumps (`chug`), the eye dips or rises at speed
  (`seat_dip`), and a driver's view is wider (83 degrees across when FIELD
  OF VIEW is narrower: `DRIVE_FOCAL`) and widens by up to `KICK` more at top
  speed (the eye's `wide`: world_view.gd widens the camera about the view's
  middle, so the crosshair still aims true). SCREEN SHAKE scales the buzz
  and thump; SCENERY MOTION scales them and the sway, the dip and the kick
  (STILL: none). The airboat's hull slaps the water at speed (`slap`, kicks
  on the springs with the looks' dice) and its bow rides up as it gets going
  (`trim`); spray flies back over its bow into the driver's view (`drops`
  in `_looks`, in the cab's own axes, drawn on the view as a pixel or two of
  white water where the cab puts them: `VehicleCab.draw_spray`). The car
  squats and dives more than before (`squat` .009, `lean` .007).
- **The driving plate** (`src/vehicle_hud.gd`, from `draw_view`): a tin plate
  in the view's top left (4, 36), under the objective pin's arrow and clear
  of the hands on the controls and the touch move stick, in the status
  bar's colours: the speed in the
  big rust numerals (STATUS PANEL: on a little dial), the rig's health as a
  row of ten lamps with SMOKIN' (under half), ON FIRE (a quarter, flashing)
  or BURNT OUT, the throttle up its right edge (reverse red, down), and the
  kind's line: the car's GEAR (R, N, 1 to 4 by its speed) with a tach, the
  airboat's FAN tach, the mower's BLADE ON/OFF lamp. HUD MINIMAL keeps two
  lines of text (MPH and RIG or its state) in the same corner. The touch
  stick and buttons drive as before (throttle and steering are
  FORWARD and STRAFE, the right-side drag the look it steers to).
- **Out of the window** (feature pass 7; the car's `window`): the car's
  driver holds a one-handed gun out of it (`[all] window_guns`: the .38,
  the sawed-off, the pistols, a stick of dynamite; getting in with a long
  gun takes up the first one owned) while the other hand stays on the
  wheel, so it steers at `one_hand_turn` of its lock; a long gun stays
  down. A shot strays `window_spread` times more (`Modes.shot_tuning` asks
  `aim_scale`; a rider's `rider_spread`; on foot and at the airboat's stick
  or the mower's wheel 1, as before) and goes only out of the front and the
  sides (`window_arc` from the nose, the driver's and the passenger's: never
  back through the cage, where the gun drops). The seat view hides the cab's
  right hand while the gun is out (its `fade`, `hand_r`) and both with
  nobody at the wheel.
- **Riding shotgun**: the car's passenger sits `ride_side` to the right of
  the wheel and sees the cab from there (`VehicleCab.dress` offsets the
  cab's `lift`; the car's shell is left out of their view too), with the
  driver's hands on the wheel. Co-op only: online play outside COUNTY RUN
  has no co-op yet, and County Run's maps have no vehicles.
- **Finding one** (feature pass 7; `src/vehicle_finder.gd`, looks and
  sound only): a ready vehicle (nobody at its wheel, not burnt out) keeps
  its `lamps` on (`effects.cfg [light.vehicle_lamp]`, a pool on the ground
  ahead of each, through `view_lights.gd`, and an `fx_flare` glow on the
  lamp) and its `radio` playing (the jukebox's loop through the radio
  channel, `radio_volume`, within `radio_reach`; the jukebox wins; KPSM's
  DJ and scanner come from it when near, and taking it tunes it in: see
  [audio.md](audio.md#the-county-radio-content-pass-8));
  the automap draws a little picture of it in the key's yellow
  (`VehicleFinder.ICONS`, and RIG, KEYS IN IT in the key); USE's prompt
  names it looked at from `spot_reach` ("AIRBOAT  /  KEYS IN IT"), only
  when nothing else is at hand; its `spotted` line is said once a chapter
  the first time a player is within `spot_told` of it in sight (remembered
  in `_looks`). Each map with one hangs a hand-painted KEYS IN IT sign by
  it (`vehicle_sign_<kind>`, `tools/art/build_vehicle_signs.gd`).
- **Set pieces** (feature pass 7; `features/vehicle_runs.gd`, a simulation
  feature): a level's `"vehicle_runs"` (from its plan's meta) are runs
  against the clock through gates in order, started by driving the right
  vehicle through `start` (the way `way` points, when given) and lost on the
  clock, a wreck or nobody at the wheel (then started again once the vehicle
  has left the start). The hands a run sets on the player are held back by
  a level trigger with `"when": {"run": id}` (`src/triggers.gd`); made in
  time, everyone in the vehicle `collect`s its `reward` and the tally shows
  the time. At the wheel the objective names the run's start and then each
  gate (`GameObjective` asks `goal`/`objective`; the pin points there), a
  flare burns on it (`[light.run_flare]`, `run_start`) and a plate across
  from the driving plate shows the title, the time left, the gate or lap
  and its name. Gator Bayou's CHANNEL RUN: out of the dock, down the south
  fork, up the north fork to the swing bridge and into the king's lagoon in
  45 s, the king's boys (four gators, two chummers, a coot, a billy) woken
  as it starts, the king's stash ('shine, sticks, shells, cartridges) the
  reward. Buzzard Bend's HEAT RACE: three laps of the oval in the stock car
  from the start line, east as the lap cars run, through a gate at each turn
  and the back stretch, in the lap cars' own time for three laps
  (`pace`; 80 s once they have run dry), the pit crew coming out of the
  infield; the purse in the glovebox. Saved (a run in the middle starts
  over); no save version (an older save restores none).
- **The Moonshine Run** (content pass 8): Granny's stock car in her barn,
  its own line (`Level.vehicle_lines`); the MOONSHINE RUN through two
  roadblocks of barricades it rams (breakables struck at `ram_from` or more);
  the county blacktop's patrol cruisers are `race_laps` with a cruiser model,
  light bars (`lights()`, effects.cfg `[light.cruiser]` `blink`/`blink_color`)
  and no lap timer (`lap_cars.laps` false). `tools/moonshine_check.gd` drives it.
- **Checks**: `tools/vehicle_set_check.gd` (VEHICLE SET OK: finding each
  one, both runs driven to the end and run out of time, the window's guns,
  riding shotgun); `tools/vehicle_set_frames.gd` takes its window pictures.
  `tools/vehicle_check.gd` (in check_all, quick too; its FEEL part
  is `tools/vehicle_feel_check.gd`: squat, dive, lean the right way, skid
  marks, sparks, landing and settling, rocking, spray and wake, the mower's
  bounce and clippings, other dice the same drive);
  `tools/vehicle_cab_check.gd` (VEHICLE CAB OK: the seat view, its parts and
  their turns, the settings, the plate, driving the same with it drawn);
  `tools/vehicle_frames.gd` takes window pictures (`docs/godot3d/features/D/`;
  from the seat looking down and back too)
  and `tools/feel_frames.gd` the feel's and the plank walls'
  (`docs/godot3d/polish/N/`).

## Gore

- **More gore** (dev.43, `src/gore_extras.gd`, called from `gore.gd`; looks
  only, gore.gd's own dice): a pool spreads under a body once it settles
  (`features/corpses.gd _settle` -> `Gore.settled`; not on water); a hit of
  `LIMB_HIT` or more to the arms, legs or head of a body that falls whole
  throws that piece and the stump spurts (`spurts`); `HitZones.METAL` kinds
  burst into scrap (`gib_m_*`) and oil (`mark_oil_*`), a blast's kill into
  half charred chunks (`gib_c_*`) with soot; big hits lay a streak
  (`mark_streak_*`) along the shot; rolling chunks smear, chunks hitting a
  wall splat on it; the local player walks bloody boot prints
  (`mark_print_*`) out of a pool. Caps: 80 chunks, 140 floor marks, 48 wall
  splats. The new pictures are `tools/art/build_gore_art.gd`'s (it rewrites
  the older gore pictures slightly differently: put those back after a run).
- **Headless bodies and wet blades** (dev.45): a head taken off
  (`GoreExtras.limb`) marks the body in `gore.headless` and game_view shows
  `<kind>_down_headless` once it is down (`GoreExtras.headless_cel`); those
  cels are Blender's (`build_enemy_actors.gd -- kinds=... frames=headless`:
  the head collapsed, a stump drawn; render to a scratch raw= and out= and
  copy only the new files). The 3D actors leave off lost limbs
  (`Gore.lost`, see [view3d.md](view3d.md)). `src/melee_blood.gd` wets the
  crowbar and sling blade after close hits (stages by gun rack, dried over
  `LASTS`), drawn as its own cached copy of the graded cel in weapons.gd.

## Mood, weather and sound

- **A level's mood** is `effects.cfg` `[level.<id>]`: fog colour and distance,
  grade, cloud drift, lightning, rain (`rain`, `showers` for spells),
  `fog_banks`, `heat` spots, crows, fireflies; `[anim.<tile>]` makes a sign
  buzz or pulse. All of it is drawn by the 3D view's shaders
  (`view_light.gdshaderinc`), behind LIGHTS AND GLOW.
- **Weather you can feel** (after v3.1.0, track H): `features/climate.gd`,
  a simulation feature (carried; its own seeded dice), keeps the rain and the
  wet (the showers' spells, once weather.gd's), the puddles' water `pool`
  (gathers while it rains, `pool_grow`; dries slowly), the mud (`muddy()`) and
  the wind (the level's `[debris] wind_<id>`, stronger in rain and in gusts).
  Each tick it sets `game.mud` and `game.wind` (SIM_FIELDS), scaled by the
  WEATHER setting (`game.weather_feel`: FULL 1, LIGHT .5, OFF 0). `Mud.pace`
  (`src/mud.gd`, effects.cfg `[mud]` floors, `mud_slow`) slows the player
  (`_step_body`) and every hand and animal (`Enemy.advance`); a thrown thing
  with gravity drifts on `game.wind` (`move_shot`, and a stick of dynamite in
  the air in `_roll`). weather.gd (looks) mirrors the climate for the view,
  lays boot, hoof, claw and tyre prints in the mud (`mark_<kind>_mud`,
  `tools/art/build_weather_art.gd`; `track()` for anything with wheels) and
  hands the wind to the dust and the 3D view; with WEATHER OFF the looks stay.
  The numbers are effects.cfg `[climate]`. County Run's storm front adds its
  own rain and wind (`climate.storm`).
- **Weather, water, relief and shimmer** (3D view shaders only, behind LIGHTS
  AND GLOW, `effects_on`): `features/weather.gd` keeps `rain` and `wet`
  (puddles on `[puddles]` floors, a sheen on walls under the sky, streaks over
  the view) and the lightning's `flash_dir`; `features/water.gd` keeps the
  rings bodies leave wading on `[water]` floors (the shaders take the nearest
  16). What each tile is to them (`[water]`, signed `[relief]`, `[puddles]`)
  is one row of tile info (`ViewTiles`). Lights come from `view_lights.gd`:
  `[light.*]` takes `pool`, `hot` (the shimmer's width; strength 0 only
  shimmers) and `props` (every prop with that picture carries it). Heat
  shimmer goes to the display shader through `HeatHaze`. Rain never on the
  Mothership; `tools/weather_check.gd` (in check_fixes) holds where it falls.
  A view tour viewpoint may hold the weather: `rain`, `wet`, `lightning`.
- **World loops** (`features/soundscape.gd`, `Sound.set_bed`): four voices of
  their own keep the rain (`rain_loop`, muffled under a roof, and `rain_roof`
  overhead, both following `weather.rain`), the nearest burn barrel, grill,
  still, generator or the Mothership's core within 9 cells (`SOURCES`, by
  picture) and the swamp king's wake. `pause_world()` stops them. The sounds
  for breaking, strikes, the gun's feel, weather and water were made in
  dev.32 (`docs/*_audio.md` say where each plays); breakables.cfg's `chip` is
  the knock of a shot that does not break a thing yet.
- **Placed sounds, takes and the per-play pitch** are in
  [audio.md](audio.md) (`hearing.gd`, `Sound.VARIANTS`).
- **Doppler on fast movers** (pass 14): a vehicle's engine, a lap car, a
  shot's or a thrown thing's flight loop and a saucer's hum bend up as they
  come and down as they go, from where they are drawn each frame
  (`mover_sounds.gd`, `doppler.gd`, `data/tuning/doppler.cfg`); sound only.
  A new sound that should bend is played with `game.sound_from(key, ...)`
  (`Doppler.RIDE`, `LAP`, `FOE` keys) or gets a `[fly]` row:
  [audio.md](audio.md#doppler-pass-14).
- **Sound effects are QOA** (`sfx.bin`, about a fifth of 16-bit samples), and
  the tiles and skies are deflated whole (`Assets.pack_whole`). An
  `AudioStreamWAV`'s `data` is then not samples: count frames with
  `get_length() * mix_rate`.

## Rumble and haptics (pass 14)

A pad's motors and a phone's buzz, looks only, like the screen shake and the
sound. Numbers in `data/tuning/rumble.cfg` (its comments say each key).

- **What feels it:** `features/rumble.gd` (a LOOKS feature, last in
  `Features.ALL`: a host leaves it off; no dice, no save, nothing carried).
  It listens to `shot_fired` (each gun's `[guns]` line; both barrels times
  `pair`; the rip saw's grind its `grind` buzz), `traced` (a melee swing
  landing, the grind's `bite`), `player_hurt`, `exploded` and the boss
  events, and each tick reads the game: the dynamite's match and throw (the
  armory's fuse and shot age), brawl's boot landing (on a man, the air, a
  door) and finisher blows, a fall's drop (`game.feel_landed`, the highest
  the feet were while falling), the seat (`vehicles.seat_of`: the engine's
  hum held in `bed` by the speed, the mower's cylinder, the airboat's chop,
  rough ground; `bumps` going up at the last tick's speed, a kerb, a ledge,
  the tank going up), and the screen's shake: a rise nothing above made (a
  boss's slam, a barn coming down, a level's script) is a quake. Only the
  local player's own doings and hurts count (`game.acting_local()`); a blast
  by its distance to the local player. An online client's own shot shown
  ahead (`own_shot`, `own_trace`; its blasts through `net_own_shots.gd`) is
  felt then and not again (`own_quiet`, `blast_quiet`). No split screen: the
  one local player has the first pad.
- **A pulse** is [weak, strong, seconds]: weak the small fast motor (a pad's
  right grip), strong the big slow one (left); full for its first `hold`,
  then fading. A hurt leans to the side it came from (from the right: more
  weak, less strong, by `lean`). Pulses add up to `cap_weak`/`cap_strong`;
  a quake goes by the bigger instead. They age by the frames (`mix(dt)`,
  from the front end), not the tick.
- **The motors:** `src/rumble_out.gd` (`RumbleOut`, `main.rumble`), each
  frame from `main.gd`. Live only in play with nothing over it
  (`live_of`: not a menu or pause, the focus, PHOTO MODE, an opener, the
  KILL CAM, a replay, the demo, the console, the tally, the down screen);
  otherwise the pad is stopped and the pulses dropped (`hush`). It also
  stops as the window or the app loses the focus (main_input.gd) and as the
  program goes (main_state.gd `_exit_tree`). The pad is the first one, as
  `read_pad` reads, while it is played with (the last device, or a stick
  or trigger moved within `pad_idle` seconds: a pad on the desk stays still);
  it is told again only when a motor moves `send_step` or every `refresh`,
  each telling lasting `refresh` + `linger`, so a stalled frame never leaves
  it running. Played by touch, the phone buzzes once for the strongest pulse
  just begun (`Input.vibrate_handheld` with its strength on Android; in a
  browser `navigator.vibrate` through `JavaScriptBridge`, shorter for weaker,
  and nothing where there is none: an iPhone's), never under `[phone]
  floor` nor sooner than `gap`. The Android export asks for VIBRATE
  (`export_presets.cfg`).
- **Settings:** RUMBLE (INPUT page, under GAMEPAD; FULL) and PHONE RUMBLE
  (TOUCH page; LOW), each OFF / LOW / FULL, LOW times `low`. Two, not one:
  a phone held in the hand with a Bluetooth pad may want one and not the
  other, and a phone's one buzzer for every round of a tommy gun is a lot
  (and the battery's), so it starts lower; a pad starts FULL as pads do.
  Changing either gives a taste of the level picked (`RumbleOut.taste`), or
  says SAVED, BUT NO PAD IS HOOKED UP / THIS ONE CANNOT BUZZ.
- **Cost:** the tick's `rumble._tick` is 8 microseconds of 0.84 ms
  (`tick_profile`, timers and all); `plain` with and without it, three pairs
  back to back, medians 0.753 and 0.751 ms.
- Check: `tools/rumble_check.gd` (RUMBLE CHECK OK, quick) with a recorder in
  place of Input's calls.

## The browser packs

**Chapter music and chapter enemies are a separate download in the browser.**
`tools/pack_assets.gd` writes `music_<chapter>.bin` and, for the enemies only
one chapter has (`Assets.CHAPTER_KINDS`), `art_<chapter>.bin`; the web presets
leave them out, CI turns each chapter's pair into a pack (`tools/make_packs.gd`)
and `pack_loader.gd` fetches them after start. `main_flow.gd play()` holds a
chapter until its pictures are there. A new enemy kind used in more than one
level must not be in `CHAPTER_KINDS` (`verify_assets.gd` checks). The wreck
pieces only chapters' levels cut (`bake_cuts_<stem>.bin`,
[levels.md](levels.md#the-bakes-pass-14)) come in those chapters' packs too;
before a pack is in, such a key is cut as before. A browser
cannot rename files in its storage and HTTPRequest's `download_file` does not
write there: keep writing packs from memory.

## A new player's first minutes (pass 12, ONBOARD)

The owner: "the first 10 minutes for new players. After eleven updates
there's a lot to learn". `tools/onboard_walk.gd` plays a fresh profile from
NEW GAME into Hickston with the PLAY page's defaults (BLUE, the bench, the
events, the tips), as `tools/newbie_pilot.gd`: the balance bot at ROOKIE (or
`skill=-1`, GREENHORN: slower, wilder, eats later) that only does what the
game has shown it (it follows the objective pin, which points along
`Game.route`; it opens a door only when OPEN DOOR shows; it eats, boots or
finishes only once a tip has said how). It writes down every notice, tip
and prompt, each objective and its time, where it got lost (no nearer the
objective for 20 s with nothing to fight), its deaths (retried as the death
screen does), damage by half minute and by whom; with a window and
`out=<dir>` it takes a picture at each (`docs/godot3d/onboard/`).

What the audit of v3.9.0 found (ROOKIE and GREENHORN at NORMAL, seeds 1-12,
and ROOKIE at HARD):

- **The first hand comes in 3.4 s** (the gas station's coot) and lands a hit
  at 4.6 s, but the fire lesson came at 12-26 s: the old lessons waited for
  any notice to clear, and the opening objective, then five pickups'
  notices, held it back. The walk lesson came at 3.3 s, the arrow at 50 s.
- **Never explained**: USE kicks and finishes (BLUE's FINISH HIM! with no
  word of how), picking things up and throwing them (the prompt shows only
  with the crosshair on one), the vehicles, the junk bench and what scrap is
  for (ten pieces picked up by the sheriff), BLUE's whistle and his badge,
  the dynamite's fuse, the mouse wheel. The CONTROLS page named fixed keys
  whatever the KEYS page said, and "1-9 0 - =  WEAPONS / WHEEL / R LOAD".
- **Nobody got lost**: the arrow leads well; the brass key took 53-81 s, the
  steel key 78-112, Bessie's pasture 52-78; the sheriff was in sight at
  194-236 s.
- **The deaths** were all at the sheriff (RODEO GROUNDS): see [boss_retry]
  below. On the way there nothing killed a ROOKIE at NORMAL in 11 runs.

**The tips** (`src/lessons.gd`, a LOOKS feature, `lessons_feature.gd`): one
short tip the first time something comes up, once a profile
(`user://lessons.json`, never in a save), in its own banner under the
notice (`game.tip`, `tip_until`, VIEW fields; `game_view.gd _lay_hud`,
chalk green `Lessons.INK`; it outranks a place's name). Each names the key
as bound, the pad button or the touch button for the device last used
(`game.input_device`, set by main.gd each frame; `Lessons.glyph`). The
moments: a hand after you (fire), the start (walk; the arrow seven seconds
in), one reeling in reach (finish), one in boot reach (kick), a locked door,
health under 55 with food (heal), the mower or a rig to drive (ride), the
crosshair on loose junk (carry), the junk bench, the dynamite in hand, BLUE
(14 s in), three guns, food in the pockets, scrap, BLUE hurt, his badge,
gut, drink. `ORDER` is who goes first; `URGENT` (fire, finish, kick) shows
at once, over a notice, cutting any other tip short after a second; `QUIET`
ones wait out a fight; `CALM` ones keep `CALM_GAP` (9 s) clear after the
last tip; the rest wait for a notice to clear. Five say a line of
Mundell's (`tip_*` in barks.gd and mundell_lines.json). Off in tools,
tours, benches, demos (`game.lessons`), in the Crossroads and with NEW
PLAYER TIPS off (PLAY page, `tips`). `Lessons.reset()` forgets them all.
The touch and pad words differ where the buttons do (the pad's D-pad eats,
the touch WHISTLE is BLUE's badge).

`tools/onboard_check.gd` (ONBOARD CHECK OK, check_all): every tip at its
moment set up on Hickston, once, not again (also after the file is read
again), nothing before its moment; none with the setting off or in a
tool's game; the keys, pad and touch words, a key moved on the KEYS page;
the CONTROLS rows fit and name the bound keys; play the same with tips on,
off and in a tool's game (`Replay.state_hash` after a minute of the bot);
and the new player's first minutes: the fire tip within a second and a half
of the first fight, no tip twice, the sheriff reached within 300 s on
NORMAL with at most one death.

## Trail markers (pass 15)

The pass 15 audit: a death outside a boss fight started the chapter over
from its kit. The ROOKIE bot threw away 107 to 140 s a death, 468 s in one
Fair, and each of those deaths ended one unbroken fight that began 3 s into
the chapter: a marker that waits for an objective or a quiet moment would
have saved nothing.

`features/trail_marker.gd` (a LOOKS feature: it only reads the game) takes
a **trail marker**, a whole save that `src/chapter_marks.gd` writes to
`marker-<chapter>[-replay|-party].json` beside the boss checkpoint (put
together on the tick, about 2 ms of a chapter on the desktop, turned into
text and written on a worker thread; whatever reads it waits for it):

- on an objective (a station done, a key or task item taken, a vehicle run
  over, a boss down) and on first standing in a district, once `gap_least`
  (20 s) has gone since the last;
- on the clock, `gap_most` (45 s) after the last, fight or no fight;
- only when it is safe enough (`_safe`): every player up, on the ground
  (not on a ladder, in deep water or a seat), no lit stick, nobody hurt
  for `calm_for` (1 s), no awake hand within `clear_reach` (3 cells) and no
  hostile shot within `shot_reach` (5), no fire at their feet, no boss
  awake near or in its arena (nor its checkpoint taken: RETRY THE FIGHT is
  the way back then), no barn creaking or coming down and no flood running,
  no vehicle run on, and no feature's `marker_ready()` saying no. An
  objective's or a district's waits `settle_most` (10 s), then leaves it to
  the clock; a clock's that has waited `press_after` (10 s) is taken on the
  looser test (`_safe(true)`: nobody hurt for `press_calm`, .5 s, hands near
  or not). The Fair's grinder had a crawler within a step and a half for
  its whole last minute: the first cut's marker, waiting for the full test,
  was 81 s old when the ROOKIE died there.

Numbers in `modes.cfg [marker]`. The death screen ([ui.md](ui.md#the-death-screen))
offers BACK TO THE MARKER while the file is the one this run took (a token
in the feature's save, as the boss checkpoint's). `MainFlow.retry_death` is
its ENTER: RETRY THE FIGHT while a boss checkpoint is offered, else BACK TO
THE MARKER, else the chapter's start; the balance and onboard bots retry
through it. Back at a marker (`at_marker`) each player gets `[marker]
health` (50) and `rounds` for each gun carried (the ROOKIE took 376 to 437
damage in those fights), `grace` (1.5 s) of `spawn_grace`, and every
feature's `marker_back()`. Dead again within `bad_within` (30 s) of coming
back, the marker before it (`marker-before-<chapter>`, kept as each new
one is written) is used instead ("THAT SPOT WAS A DEATH TRAP"): nobody is
stuck dying at a bad spot. A win clears the chapter's files, a chapter's
start the other chapters'.

What a marker holds is what a save holds, every feature's `save()` with
it, so a new feature's state (the director's beats) comes back by itself;
`GameFeature.marker_ready()` holds a marker back (a peak under way) and
`marker_back()` runs on the game just loaded from one. CHECKPOINTS (PLAY
page, `checkpoints`; `game.trail_markers`, a VIEW field) is TRAIL MARKERS
by default, BOSSES ONLY takes none and leaves the death screen as it was;
a game configured without the option (a tool's) takes none. Off in the
hub, the range, a revisit, a rematch, County Run and the versus modes;
co-op takes the party's (`-party`, the host's game only) and the host
picks. The quicksave and the save slots are untouched. Taking one changes
nothing in play (`marker_check`: a bot's 100 s the same either way).

What a death costs, the ROOKIE bot at NORMAL through the whole campaign
(the audit's `flow.gd` run, a death retried as the death screen does;
deaths outside a boss fight, seconds of play thrown away):

| runs | deaths | thrown away | median a death | worst |
| --- | --- | --- | --- | --- |
| v3.12.1, seeds 1-3 (the audit's 1-2; 3 on BOSSES ONLY) | 10 | 1,034 s | 107 s | 144 s |
| trail markers, seeds 1-3 | 6 | 220 s | 33 s | 76 s |
| trail markers, seeds 1-5 | 7 | 249 s | 29 s | 76 s |

The worst is a marker died at again 20 s after coming back (the bayou
cannery), so the one before it. With markers the ROOKIE cleared the Fair
after one death (seed 1; three before) and after two (seed 3; it gave up
after six before). The REGULAR and SHARP runs (seeds 1-2) do not die and
play exactly as before.

**The pin's way after a load (1.11).** After RETRY THE FIGHT on Jerry at
HARD (REGULAR bot, seed 1) the bot stood 880 s by the rodeo grandstand.
Not the bot and not the level: `Game.route` (the pin's way, which the bots
follow) was walked from Bessie in the slow motion of Jerry's fall, while
his gate was still swinging open, and a swinging leaf blocks the cell
beside its doorway; `objective_route` walks again only when its sig
changes, and the sig counts doors *opened*, which flips as the swing
starts. The way stopped at the gate for good (in every other run the walk
came after the swing). Now a way that does not reach the player is walked
again, `REWALK_GAP` (1 s) after the last walk began, until it does (a sig
counting doors at rest was tried first: it re-walked at every swing's end,
moved every bot run and left the SHARP bot shut in the Fair's raffle door,
a door that waits while someone stands in its swing). And after every load
the route walked with the key ring the game was made with (`save_restore`
hands the players a new one): every key door was shut to the pin until the
next chapter; `objective_route` now takes the game's own. Play never reads
`Game.route`: these change the pin and the bots, not the rules.

## Stuck spots the bots found (pass 15)

- **Caught in furniture.** A ROOKIE bot stood 660 s on the bayou's lagoon
  bank by a dock piling after the swamp king fell (seed 3), the pin's way
  reaching it (16 steps): it stood inside the square the piling blocks
  (`LevelData.blocked` tests a body's square, radius each way), put or
  shoved there, and every first small step out was refused and the velocity
  died. A person would stand there too. `LevelData._walks_out`: a player
  caught in a piece of furniture where they stand may take a step that goes
  less deep into it and into nothing else (tested a hair narrower than that
  depth); asked only when a step was refused, so play that never gets caught
  is unchanged.
- **Walled in after a boss.** The bots T2 saw shut in after the foreman,
  the derby champ and the swamp king had the pin's way walked in the boss's
  fall while the arena's gates swung open (the 1.11 mechanism, trail markers
  above): `REWALK_GAP` walks it again. `tools/stuck_check.gd` plays every
  chapter through and holds the way reaching the player after each boss.

## Between chapters (pass 15)

Before pass 15 a won chapter's card led to the Crossroads, the player at
its spawn 32 to 51 cells (8 to 13 s running) from the next gate, then a
load each way: 25 to 35 s of not playing at each of the seven boundaries.

- **BETWEEN CHAPTERS** (PLAY page, `between`; it replaced CLASSIC LEVEL
  FLOW, whose `classic` key is no longer read): STRAIGHT ON (the default)
  or THE CROSSROADS says what the card's one tap does; the other is a plate
  of its own. `BetweenChapters.choices` gives the card's ways on, each with
  its slot (`GO`, `OTHER`, `AGAIN`) and key word; `main_flow.gd take_road`
  does what a slot's plate says.
- **Straight on** (`continue_campaign()`): `_next_chapter` starts the next
  chapter with the kit and history carried, the won chapter kept in
  `retained` for a revisit, its gate unlocked and saved; the campaign entry
  is written there too, so skipping the Crossroads loses nothing.
- **The Crossroads** (`continue_campaign(true)`): `open_hub(made, message,
  following)` writes the entry as before and stands player one in front of
  the next chapter's gate, facing it, `GATE_STEP` (1.8) out
  (`BetweenChapters.stand_at_gate`; USE takes it: CONTINUE into the chapter
  under way). Every gate has room in front of it (`road_check`).
- **TRY TO BEAT IT** (`try_to_beat_it`): the chapter again as the hub's
  REPLAY gate starts it (the gate's kit, `NetCoop.chapter_kit`); from the
  campaign's own card the campaign goes on first, unseen (the next chapter
  made, its gate opened, the entry written). A won replay's card offers HIT
  THE ROAD (into the campaign's chapter under way), THE CROSSROADS (at its
  gate) and TRY TO BEAT IT again (`back_on_the_road`); before pass 15 it
  went to the title.
- **The openers** play once a chapter (OPENERS: FIRST TIME) and one key,
  button, click or tap skips all of one (unchanged; `road_check` holds it on
  the straight road).
- **The bests** (`src/chapter_bests.gd`): `chapter_bests.json` beside the
  boss rematch bests (`BossRematch.folder()`: the profile, or the cache
  folder in a tool run), never a save. For each chapter and difficulty the
  best time, most varmints and most secrets, each its own best. Kept once
  per won card (`BetweenChapters.settle`, from `main_flow.gd watch_tally`
  each frame and `take_road`) for a campaign chapter played alone by a
  person: not co-op or online, a rematch, a recorded replay, a tour, bench
  or demo, or with cheats. Replays count. A first run sets them with no
  NEW BEST.
- **Par** (`modes.cfg [par]`): seconds of the chapter clock, the same at
  every difficulty, from the SHARP bot's pass 15 audit times times 1.5 (the
  file says which). The ribbon gives `pace_share` (.2) to keeping to par:
  full at par, none at `slack` (2) times par. The balance step re-sets par
  when play moves.
- **Online co-op**: the host picks, as before (`online_input.gd`): ENTER
  does what the host's BETWEEN CHAPTERS says, the MAP key the other
  (`NetCoop.next(main, crossroads)`); at the Crossroads player one stands at
  the gate, the partners gathered beside them.

Measured (headless, this PC): ENTER to the next chapter playable 75 to 195
ms straight on; by the Crossroads the hub's load as well, then the walk.
Not playing at a boundary, a player who watches the card to its ribbon
(seven or eight rows): before 3.0 to 3.4 s of card + 8.4 to 13.2 s running
to the gate + two loads; after 2.1 to 2.3 s (0.6 s with a tap) + one load,
the opener (first time only, skippable) either way. Over the seven
boundaries about 80 to 120 s before, 5 to 17 s after.

## Reading danger (pass 15)

The audit found 19 to 57 % of the damage taken came from outside the middle
of the view (half in the quarry and the Mothership), told only in words
(`STRIKE LEFT`, `WINDUP LEFT`), and no bot ever used a hazard. Now danger is
drawn where it comes from, and a hazard kill pays. Numbers in hits.cfg
`[danger]` and `[hazard]`.

- **Damage arrows** (`src/danger_marks.gd`, looks; DANGER ARROWS on DISPLAY,
  on by default). `damage()` keeps each blow with a source in
  `game.danger_blows` (a VIEW field: [heading, landed, until, amount], the
  local player's only, at most `arrows_most`). Each draws a red chevron at
  the view's edge its way: the edge is picked by the bearing (a quarter turn
  round is a corner; the chevron points out of the edge it sits on, up,
  right, down or left, a pixel pattern three pixels thick, never a turned
  line), white for `FRESH` (.06 s), then fading over `arrow_for` (.8 s); a
  blow of `heavy` (20) or more is a double chevron. They go where the hurt
  arc went (before the notice and the tip, so banners stay on top) and slide
  in toward the middle off any HUD piece or touch button
  (`HudLayout.taken`, where each is drawn, ASPECT WIDE's edge pieces moved
  out); one with no clear spot is not drawn. The hurt banner then names
  only what hit (the side is the arrow's). Off: the hurt arc, `<CAUSE>
  LEFT` and the WINDUP panel exactly as before. Unlike the arc, the steam
  (a boilerback's blast, a jet) and the chalk or gas clouds get an arrow
  (toward the cloud's middle); the player's own blasts (`OWN`) and a source
  on top of him (`ON_TOP`) get none. In the audit's quarry runs these were
  about half the unseen blows.
- **Wind-ups.** A regular hand's model washes amber over the last
  `tell_share` (.6) of his wind-up (`EnemyLooks.tell`: .2 to .38 toward
  amber as it runs out, flickering at 12 a second; the actor shader's `tell`,
  a sprite's packed wash; a hit's wash comes first; bosses keep their own
  pulse). Off the view (DANGER ARROWS on) an amber chevron points at each
  hand winding up within `windup_reach` (14), the nearest `windups_most` (2),
  blinking hot in his last share; in the view his model tells it. A wind-up
  of `big_windup` (.6 s) or more (chain hand, boilerback, bottle tosser, yard
  deputy, millhand, ...) marks the floor at his `aim_mark` (where the player
  stood as it began) the bosses' way, `ring_dots` warning marks closing from
  `ring_wide` to `ring_tight` round a filling slam mark
  (`features/danger_looks.gd`, a LOOKS feature); a ranged hand's raised gun
  hand glints over the same share.
- **Hazards readable.** The awake hand nearest the sights (within
  `sights_reach`, the aim on his body, in sight) lights faint red brackets,
  breathing, round each hazard prop within `show_reach` (3.5) of him, as tall
  as the prop's board. When USE would boot a man (brawl.gd `target`, not one
  to be finished, not a boss) and his slide along the aim (the boot's speed
  run down by its drag, stopped by a wall) meets a hazard prop's reach, deep
  or running water or ends among the hogs, a little bone skull shows under
  the crosshair (`DangerMarks.skull`). Looks only, always on.
- **The bonus** (play, brawl.gd `_bonus`, the same on every machine): for
  whoever booted him, COUNTY JUSTICE! across the screen (callouts.gd
  `JUSTICE`) and the hazard's name with the pay in the notice, Mundell's
  `hazard` line as before, `bonus_scrap` (3) scrap in his coffee can with the
  bench live (up to bench.cfg `most`), a drop at the body nudged toward him
  (`_bonus_pick`: his kind's own enemies.cfg `drop`, else one of
  `bonus_drops` by `game.rng`; none with NO DROPS; the PACE track may point
  this one line at its drop by need), and `game.events.hazard_killed(enemy,
  kind, slot)`; the RAMPAGE meter adds `bonus_rampage` for it ([RAMPAGE](#rampage-pass-15)).
  Bosses (who only take their share) get none.
- Carried online within PROTOCOL 5: nothing new is carried. The arrows, the
  tell, the rings, the glint, the brackets and the skull read what already
  is (an enemy's windup and aim_mark, the local damage); the bonus is brawl
  play, its scrap on the carried armory and its drop a pickup. County Run:
  the same rules (no scrap: no bench there).
- `tools/danger_check.gd` holds it; `tools/danger_frames.gd` (a window)
  pictures it; `brawl_check` holds the bonus.

## RAMPAGE (pass 15)

Kills landed the same way every time and a chain of them meant nothing but a
callout. Now kill chains fill a meter, and a full one turns Mundell loose.
`features/rampage.gd` (a simulation feature, last in `Features.ALL` and
`SIM_FEATURES`), numbers in hits.cfg `[rampage]`.

- **The meter** (0 to 1, per player by slot). A kill of his own (the hit
  that killed was his: `hit_landed` with `killed`, then `enemy_killed`; a
  hand killed by another hand fills nothing) adds `kill` (.11), more for a
  head (`head` .06), an overkill that takes the body apart (`overkill` .06:
  `Enemy.explosive`), a brawl finisher landing (`finisher` .12: brawl's
  `last_moves` a wind-up ago), a boss (`boss` .5) and a hazard kill
  (`hazard_killed`: [hazard] `bonus_rampage` .35); a kill within `chain_for`
  (2.5 s) of the one before adds `chain` (.03) for every link, up to
  `chain_most` (4). It holds `hold` (3.5 s) after a kill, then drains
  `drain` (.08) a second. A burst of four or five kills fills it; the steady
  kill a minute of a walk does not.
- **RAMPAGE**, when it is full: `rampage_for` (8 s), each kill in it adding
  `extend` (.5 s) up to `rampage_most` (14 s) in all. He moves `speed` (1.12)
  times as fast (one factor in `game.gd _walk`, `Rampage.pace`) and his hits
  do `damage` (1.2) times as much (one line in `Enemy.hurt` after the hit's
  zone, `Rampage.might`, his own hits only). The meter is empty after.
- **Looks** (this machine's player): the lamps under the health and RAMPAGE
  on the health box ([ui.md](ui.md#the-huds-layout)), the view's edge
  burning (`src/rampage_looks.gd`), a made sting (`rampage_sting`) and
  Mundell's holler (barks `rampage`, forced) as it begins, the music at its
  PEAK ([audio.md](audio.md#the-fight-music-in-four-levels-pass-15)). The
  sting and holler come from `draw_view` once per RAMPAGE (`_said`, this
  machine's, in `SnapCodec.SKIP_FIELDS`), so an online copy hears its own.
  The callouts (TWOFER .. RAMPAGE!) stay as they were: words for a quick
  streak.
- **Where**: the campaign, co-op (each player his own) and County Run (its
  cards stack on top); never deathmatch, team deathmatch, the 5v5, the hub
  or the range.
- **Online and saves**: every variable but `_said` is carried (no dice; the
  host decides, a client's prediction reads the same `pace`), PROTOCOL stays
  5 (a feature block an older build does not know is skipped); its block in
  the save holds the meters, the holds, the RAMPAGES under way and the
  chain, read back as floats (an older save: an empty meter). No save version.
- `tools/rampage_check.gd` holds it; `tools/rampage_frames.gd` pictures it.

The balance bot (`flow_report.gd`, REGULAR, SHARP and ROOKIE at NORMAL, seeds
1 and 2; before is this pass's PACE, READ, MARKERS and ROAD tracks merged):

| chapter | seconds (median) | kills a minute | whole fight loop % of the chapter | CALM / BUILD / FIGHT / PEAK % after | RAMPAGES an attempt | on one, s an attempt |
| --- | --- | --- | --- | --- | --- | --- |
| hickston | 258 -> 259 | 9.7 -> 10.1 | 82 -> 46 | 25 / 32 / 33 / 16 | 1.67 | 15.5 |
| fair | 292 -> 273 | 10.1 -> 10.3 | 80 -> 49 | 26 / 27 / 21 / 24 | 1.71 | 14.6 |
| sawmill | 203 -> 209 | 11.4 -> 11.4 | 84 -> 40 | 23 / 42 / 22 / 16 | 1.50 | 15.3 |
| quarry | 211 -> 207 | 10.8 -> 10.9 | 81 -> 51 | 27 / 24 / 29 / 23 | 1.33 | 13.6 |
| bayou | 201 -> 211 | 12.9 -> 11.4 | 83 -> 59 | 25 / 17 / 32 / 24 | 1.63 | 13.0 |
| speedway | 186 -> 170 | 10.6 -> 11.5 | 82 -> 43 | 26 / 38 / 24 / 20 | 1.14 | 11.5 |
| moonshine | 150 -> 159 | 11.8 -> 12.5 | 82 -> 66 | 15 / 23 / 34 / 28 | 1.29 | 13.3 |
| mothership | 214 -> 213 | 12.5 -> 12.5 | 92 -> 65 | 16 / 22 / 53 / 12 | 0.86 | 6.2 |

(Medians of the attempts; the level shares do not sum to 100, each being a
median.) Over all the play the whole fight loop went from 83 % to 52 % of
the time; the Moonshine Run and the Mothership, fought the most (46 and
59 % of their time hot, crowds of three or more 44 and 24 % of it), still
hear it about two thirds of theirs. RAMPAGES: 1.39 a chapter (ROOKIE 1.58,
REGULAR 1.26, SHARP 1.31), about 6 % of the time on one. The chapters'
median seconds summed: ROOKIE 1581 -> 1639, REGULAR 1715 -> 1645 (-4 %),
SHARP 1690 -> 1644 (-3 %). Deaths a run: ROOKIE 2.5 -> 1.5, REGULAR 0 ->
1.5 (at the derby champ, the revenue man and a crawfish boil fire, two of
them in attempts with no RAMPAGE in them: play goes otherwise from the first
change, one seed of each), SHARP 0 -> 0. The music is looks only: with every
music change since, the same seeds played to the same chapters, seconds and
kills (checked attempt by attempt). Speed: `tick_spikes.gd` on Hickston, three
alternate runs back to back, the tick's median 1.202 -> 1.225 ms (+1.9 %; the
bot's game is a different one with the boost).

## Moves (pass 15)

The walk was quick already (63 % of the speed in 43 ms), but it stopped soft,
steered little in the air and had nothing to do on the run; swaps took a
quarter second, a reload could not be stopped, and the boot and the dynamite
hid behind USE and a gun slot. `src/moves.gd` (`Moves`), numbers in modes.cfg
`[move]` and weapons.cfg `[all]`.

- **The walk's numbers** moved from `game.gd _walk` to `[move]` first with
  their exact values (the same bots played the same ticks: hickston, the
  sawmill and the bayou, ROOKIE and SHARP, 7,200 ticks each, every state hash
  the same), then: `run` 3.85 -> 4.1, `ease_stop` 30 -> 40, `ease_air` 7 ->
  10. `game.gd _walk` works out the speed (keys, gut, drink, mud, a RAMPAGE,
  water) and `Moves.body` does the rest (the crouch, the slide, the ease,
  walls and bodies, the jump, the fall); an online client's
  `NetPredict.step` ends in the same `Moves.body`, so its picture walks the
  host's sums, slide and all (it gained the RAMPAGE's pace on the way).
  Ladders, ledges, vehicles and the water's own rules are untouched.
- **The slide.** CROUCH taken (a fresh crouch: `Player.crouched` was false)
  on the ground going at least `slide_from` (3.4: running, not walking)
  starts one along the way the player is going, at `slide_speed` (5.0, less
  in mud or water, more if a sprint had him faster), easing (slow, then
  quicker) to the crouch walk over `slide_for` (.55 s), turning toward the
  keys at most `slide_steer` (1.6 radians a second). It ends on letting go
  of CROUCH, a jump (the jump is allowed with CROUCH held while sliding: a
  hop that keeps the speed), a wall or a body head on (less than
  `slide_wall` of its step made), a knock-down, the air, or its end; another
  waits `slide_rest` (.8 s). The eye is the crouch's. Landing with CROUCH
  held going fast is a slide too. Sound: `slide_scuff` (free, a gravel step
  smeared, `audio_build.py` scuff); the gun dips and leans (`feel.gd
  _slide_dip`, looks). `Player.slide`, `slide_dir`, `slide_top`,
  `slide_rest` are carried like the player's other fields and never saved
  (a load stands).
- **KICK** (K, the mouse's back side button, R3, the KICK button):
  `Game.quick_kick` -> `brawl.gd boot`: what USE's boot does (a finisher on
  a man open to one, a man booted, a door run at kicked in) and nothing else
  USE does (no door opened, nothing toted, no switch); with nobody in reach
  the boot all the same, into the air (`can_kick`). Where the boot is off
  (deathmatch, the 5v5, the hub) it does nothing.
- **THROW** (N, the mouse's front side button, LB, the THROW button):
  `Game.quick_throw` -> `Armory.quick_throw`: with the dynamite carried and a
  stick (`reserve[CROSSBOW]`), the stick lit and thrown at once with a full
  fuse from whatever gun is up; the dynamite hand shows the throw and the
  gun comes back up `throw_back` (.32 s) later (`throw_from`, its rise only);
  a stick already lit goes now. Not with the hands full (a boot or a
  finisher, something toted, a wheel, the gallery's gun).
- **Swaps and reloads**: `switch_time` .23 -> .16 (`switch_lower` .09 ->
  .065, the same share going down); FIRE pulled (a fresh pull:
  `Armory.trigger_held`) with rounds still in the gun stops a reload and
  shoots what is loaded; a reload from empty goes on (a bayonet jabs) and so
  does one started with the trigger held.
- **Controls**: `Game.Controls.kick` and `throw` (fresh presses). The
  campaign's front end does them between ticks as actions (`act(["kick"])`,
  `["throw"]`, kept in its replay); online, the round modes and a bot send
  them as controls (`TacticalScreens.pending_kick`, `pending_throw`).
  Replays are format 2 (the buttons as a varint), format 1 still plays; the
  net codec's controls are 15 bytes and PROTOCOL is 6
  ([multiplayer.md](multiplayer.md#the-transport)).
- **County Run** walks, slides and kicks the same (THROW needs the dynamite,
  as anywhere).
- `tools/move_check.gd` holds it ([checks.md](checks.md)); `-- numbers`
  prints the feel.

How it feels, by numbers (`move_check.gd -- numbers`, a range lane, 60 Hz
keys; before is v3.12's walk worked out by the same sums):

| | before | now |
| --- | --- | --- |
| run | 3.85 cells/s | 4.1 |
| 90 % of the run from standing | 117 ms | 117 ms |
| a stop from the run | 150 ms over .13 cells | 117 ms over .07 cells |
| the air: side speed .25 s after a jump with a strafe held | 3.2 cells/s | 3.8 |
| a swap | 230 ms | 167 ms (ten ticks at 60) |
| a slide | none | 5.0 cells/s, 2.3 cells in .57 s (a crouch-walk: 1.3) |

The balance bot (`flow_report.gd`, REGULAR, SHARP and ROOKIE at NORMAL,
seeds 1 and 2; before is this pass's tracks to RAMPAGE AND MUSIC merged; the
bots run and boot with KICK, never slide or throw):

| chapter | seconds (median) | kills a minute | fight % |
| --- | --- | --- | --- |
| hickston | 259 -> 255 | 10.1 -> 10.9 | 46 -> 48 |
| fair | 273 -> 258 | 10.3 -> 10.5 | 46 -> 47 |
| sawmill | 209 -> 204 | 11.4 -> 11.2 | 53 -> 54 |
| quarry | 207 -> 196 | 10.9 -> 11.7 | 51 -> 52 |
| bayou | 211 -> 211 | 11.4 -> 12.4 | 50 -> 51 |
| speedway | 170 -> 175 | 11.5 -> 11.0 | 43 -> 48 |
| moonshine | 159 -> 168 | 12.5 -> 13.1 | 46 -> 50 |
| mothership | 213 -> 195 | 12.5 -> 12.8 | 59 -> 58 |

The chapters' median seconds summed: ROOKIE 1639 -> 1667, REGULAR 1645 ->
1644, SHARP 1644 -> 1612 (-2 %); deaths a run ROOKIE 1.5 -> 1.0, REGULAR
1.5 -> 0, SHARP 0 -> 0 (play goes otherwise from the first changed tick:
one seed of each, so these are a sign, not a measure). The run is 6.5 %
quicker but the bot walks the pin and fights at the same pace, so a chapter
is a few seconds shorter at most.

## Difficulty and pacing as numbers (polish pass 9)

`tools/balance.gd` plays the campaign for real and writes down what
happened; `tools/balance_pilot.gd` is the player it plays as: the campaign
bot (`tools/bot_pilot.gd`) with a skill (ROOKIE, REGULAR, SHARP: how long it
takes to fire on a new foe, how far off it aims, how fast it turns, whether
it strafes, boots a hand up close and finishes one open to it, when it eats)
that also steps off the way for a pickup it can use in sight (rounds for a
gun it has short, food, scrap, a gun), fights on with the blade or the
crowbar when every gun is dry, and hops and turns when the way has not got
shorter for a while. Its dice are its own; `game.rng` is reseeded per
attempt by the tool, so a run is the same every time.

- **run**: one campaign, god mode off, the PLAY page's defaults (the hound,
  the bench, events SOMETIMES; ADAPTIVE as a player has it), each chapter
  carried into the next as `continue_campaign` does; a death retries as the
  death screen does (`MainFlow.retry_death`: RETRY THE FIGHT in a boss
  fight, else BACK TO THE MARKER since pass 15, else the chapter from its
  kit; the row says where it went back to and the seconds thrown away,
  `back_to` and `lost`), six deaths or 900 s and it walks the chapter in god mode to go
  on. At each chapter's start it buys what the bench's prices allow,
  cheapest first. A line of JSON an attempt: how it ended, where (district,
  or the boss), what was near, the cause, the time, health and the share of
  rounds left, seconds dry, kills by gun, shots by gun, food eaten, scrap
  found and carried, mods, finishers, boots, hazard kills, the hound's
  bites and pins, seconds in a vehicle, and each boss's fight timed from the
  first hit it took to its fall.
- **county**: COUNTY RUN to death (or `cap`) by `tools/county_bot.gd`:
  survival, the level, kills and health a minute, the cards offered and
  picked.
- **report**: the tables from many runs' lines (`balance_report.gd`):
  chapters by difficulty, deaths by skill, where the deaths cluster, the
  bosses, the guns, the bench, COUNTY RUN. `tools/balance_runs.sh <dir>`
  runs the long report (4 difficulties x 3 skills x 3 seeds, a third of
  the runs without the hound, plus COUNTY RUN, each Godot process with its
  own APPDATA and LOCALAPPDATA; about 400 MB each, so mind `jobs`).
- **check** (`balance_1`..`_5` in check_all, BALANCE OK): RETRY THE FIGHT's
  floor; each boss in its rematch by the REGULAR bot at NORMAL inside
  `BOSS_BANDS`; each chapter from its chapter kit by the SHARP bot at NORMAL
  cleared within `CHAPTER_DEATHS` and inside `CHAPTER_BANDS`. A play change
  that moves one is deliberate or a regression: run the long report, then
  set the band again and say why in its comment.

The bot is a yardstick, not a player: it never dodges a telegraph, takes
only pickups near the way and never drives. Its deaths say where a chapter
is hard next to the others, not how hard it is for a person.

What the first long report (before pass 9's tuning; 36 campaigns, 425
attempts) found, and what changed:

- **Hickston, the first chapter, was the hardest** at every difficulty
  (deaths a run, all skills: NORMAL .44 where chapters 3 to 8 had none, HARD
  3.33 where none of the next five had any, HOG WILD 5.67), and the bot came
  out of it with 2 to 7 % of its rounds. The deaths were in the sheriff's and
  Jerry's fights: two bosses each calling the whole backup, entered dry, and
  RETRY THE FIGHT put the player back at the door with the same empty guns
  and low health, to die again in under ten seconds, six times running.
  Changed: `[boss_retry]` (a retry brings 60 health and 24 revolver and 12
  shotgun rounds at least), `[boss_fight] backup_share` (the two Hickston
  bosses call half each), the sheriff 1300 to 1050 health and Jerry 1150 to
  950, and the yard deputies (Hickston's backup) drop shells (.5) and the
  aliens .38 rounds (.35) (enemies.cfg).
- **The middle bosses fell in 12 to 19 s** at NORMAL and killed nobody below
  HOG WILD: the foreman 1000 to 1200, the baron 1300 to 1550, Boggs 1250 to
  1500 (BOSS REMATCH's `par` for the foreman and the baron moved to 14 and
  16 with the bot's new times).
- **Rounds piled up late**: the speedway and the Moonshine Run ended with
  52 to 60 % of everything carried at EASY and NORMAL: the tire rollers'
  drops .6 to .5, the pit mechanics' .55 to .45, the revenooers' .6 to .5.
- **The bench was trivially cheap**: every mod the guns in hand could take
  was bought by the quarry, and 72 scrap went unspent into the Mothership.
  Every price half again (57 to 83 in all): the mods now come over the
  first five chapters, 55 scrap left at the end. The crossbow's two mods
  were never bought (the crossbow comes late and the bot seldom has it).

Deaths a run by chapter (36 campaigns each, all three skills), before and
after:

| | hickston | fair | sawmill | quarry | bayou | speedway | moonshine | mothership |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| EASY | .22 / 0 | .44 / .22 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |
| NORMAL | .44 / .22 | .38 / .33 | 0 / 0 | 0 / 0 | 0 / .22 | 0 / .22 | 0 / .25 | 0 / 0 |
| HARD | 3.33 / 1.56 | 0 / 1.00 | 0 / .13 | 0 / 0 | 0 / .63 | 0 / 0 | .38 / 1.00 | .38 / 1.50 |
| HOG WILD | 5.67 / 3.78 | 1.22 / 1.11 | .11 / 1.13 | .89 / 1.50 | 2.56 / 2.75 | .29 / 1.25 | 1.43 / 1.75 | 4.86 / 5.57 |

Left as found: Hickston is still the deadliest chapter at HOG WILD and the
Mothership's Maw the deadliest fight (ROLLIN' PIN and STOMP); the swamp
king kills at HOG WILD only; the fair's crawlers are where a ROOKIE dies on
EASY. COUNTY RUN (its bot survives 1.5 to 7 minutes, the quarry map the
shortest at every difficulty, NORMAL and HARD hardly apart) was measured,
not changed: its runs and daily board are balanced on its own cards, and its
bot is too weak a yardstick to tune them by. (The aliens' and deputies'
new drops fall in its hordes too, as every hand's drop always has.)

## Fight rhythm (pass 15)

Pass 15's audit (`tools/flow_report.gd`, below) found the fights a flat
trickle: one alerted hand within 14 cells for half of all the fighting, a
small fight every 8 to 12 s all chapter with no build-up, peak or breather,
and a ROOKIE swinging the crowbar for 29 % of its pulls while 20 to 50 ammo
pickups lay about. Three changes, all play, all deterministic:

**The director** (`features/director.gd`, its choices in
`src/director_beats.gd`, numbers in `data/tuning/director.cfg` read by
`DirectorData`). A simulation feature, last in `Features.ALL` and
`SIM_FEATURES`.

- On a chapter's first tick it holds back `hold_share` of each district's
  hands (`world.area`; picked with `game.rng`, out of every player's sight
  (a hand past `DirectorBeats.SIGHT_FAR`, 36 cells, counts as unseen: a
  speck at 320 wide, and a sight line across the map was most of the first
  tick's cost),
  more than `start_clear` from the start and `boss_clear` from a boss or the
  last boss, never in a boss's district) and adds `extra_share` more of the
  district's kinds beside them, all dormant. Extras join `game.enemies` after
  everything else and are saved by `posse` with the rest that joined later;
  `total_kills` counts them.
- **Never held** (`DirectorBeats.named`): a hand a trigger wakes or waits on
  (`wake`, `down`), a partner pair, the station's wave, a patrol, a hand
  whose id anything else in the level uses (an exchange, a door), the bosses,
  the rescue's cast, the tough guy, critters, swimmers and lurkers, a hand by
  an exchange. A trigger's `alert` wakes the held hands in its reach too
  (`_answer_alerts`), so a set piece's hands all come.
- **The beats**: `calm` (no hand on the party) and `build` (the level's own
  hands as placed); `peak` when the party does a station, takes a key, walks
  into a district not seen before (`district_settle` s later) or `build_for`
  s have gone, not before `first_peak` s, not within `build_least` of the
  last breather, a walk-in or the timer only after `peak_quiet` s with no
  hand on the party, never in a long fight or within `boss_quiet` cells of
  a boss still up (awake or waiting: a crowd at the boss's door would still
  be there at RETRY THE FIGHT): the held
  hands within `peak_reach` cells (nearest first; the chapter's first peak
  `peak_first` at most, one more each peak after, up to `peak_group_most`:
  the crowds grow through a chapter) are moved to spots `peak_spot` cells out (out of every player's sight, on
  their floor, reachable within `peak_steps`, never in or by a doorway) and
  wake hunting (`peak_hunt`), with a "help" bark and a HUD line
  (`peak_lines`). The peak is over when its hands are down (the last kill
  leaves what the player is short of, below), none has been on the party
  for `peak_cold` s, or after `peak_most`. Then `breather` for
  `breather_for` s: no hand sent. A boss's fight beginning (`boss_intro`:
  the peak's hands and the stragglers out of sight go back to the held ones)
  and a boss's fall (`boss_down`) bring a breather too: the boss fight is
  the boss's, with its own backup, and no crowd falls on a player who has
  just finished one.
- **The guard**: in a breather, and in a fight that has gone `long_fight` s
  without a `quiet_gap`, a hand farther than `guard_near` that hears a shot
  does not come to look (its `Mind.investigate` is cleared right after the
  squad's hearing), and the level's own hands between `guard_near` and
  `hush_reach`, out of sight and after nobody, keep still (dormant,
  `hushed`); after, each is back where it stood once no player can see the
  spot (no pop-in). A finished peak's hands that give up the hunt go back to
  the held ones as soon as no player can see them (`strays`): a hand left
  standing where its hunt ran out, in a one-cell gap or a doorway, never
  keeps the way shut (two bot runs were walled in so). In a long fight every `relief_every`-th kill also leaves
  what the player is short of (below): the supply where the fight is.
- **A held hand thinks afresh** when it comes back (`lod_since` reset): a
  dormant hand does not tick, and its level of detail's owed time would
  otherwise move it the whole way it could have walked while held, in one
  step (found while building this: peak hands crossed half of Hickston).
- **Where it runs**: the eight chapters (`Campaign.ORDER`, less
  `off_chapters`), campaign and co-op; off in County Run (its spawner is its
  director), deathmatch, team deathmatch, the 5v5 rounds, the hub, the
  range, a rematch, a chapter revisited, player maps, and when a tool sets
  `DirectorData.ON = false` (`flow_report.gd -- run director=0`). Co-op: the
  beats follow the party (each player's sight and flow field; a peak comes
  for the first player up by slot) and the local player is left acting.
- **Online and saves**: every variable is carried (the host decides; the
  enemies' `dormant` already was); its block in the save holds the held,
  hushed and peak hands by index (the list only grows in the modes it runs
  in), the phase and the timers. A save with no block (older, or one it did
  not run in) holds nothing held, unless it was made before the chapter's
  first tick (then the chapter starts as new). Its `restore` also brings a
  lighter sponge saved with more health than its kind now has down to it.
  Mixed versions at PROTOCOL 5 still mirror (an unknown feature block is
  skipped), but the MOVES track's protocol bump separates them.

**The intensity signal** for the music, the RAMPAGE meter, the slow-motion
rule and BLUE: `Director.intensity_of(game)` (0..1) and
`Director.phase_of(game)` ("calm", "build", "peak", "breather"; "calm" and 0
where the director does not run), and `game.events.pace_changed(phase,
intensity)` when the phase moves. Intensity is 0 calm, .2 to .7 in a build-up
by the hands on the party (`crowd_full` of them is a full crowd), .7 to 1 in
a peak, and fading from .25 over a breather (.35 times the crowd if hands
are still on the party). Updated every `scan` (.25 s) on the tick, so it is
the same on every machine.

**Drops lean to need** (`src/drop_need.gd`, `game_world.gd enemy_down`):
when a kind's drop comes up it stays the kind's own while that is any use to
the player who downed it (rounds for a gun of theirs under `need_full` of
what it holds and carries, food while under `need_health`); otherwise, on
`need_share` of the drops, it is `need_food` for a hurt player or the
rounds of their gun with the least left. The roll is the drop's own (the same
count of `game.rng` rolls; an always-drop's comes from the hand's uid). NO
DROPS still drops nothing it did not; County Run and the versus modes drop as
before. The peak's last kill leaves `DropNeed.wanted()` too.

**Lighter sponges**: the tin guard 185 -> 130, big billy 150 -> 120, the
noodler and the tire roller 118 -> 100, the tough guys about 15 % (Big Earl
270 -> 230 ... Zorgo 300 -> 255); "more of them" is the director's extras.

Found on the way and fixed: a level's exchange (hands talking at a spot,
`game_combat.gd tick_exchanges`) waits for a line still playing instead of
starting over it (presentation only), and a revenue raid's squad tries round
its rings when every first turn is walled (`event_raid.gd start`; the old
places first, so a squad that found room before stands where it did). Tools
that walk `game.enemies` beside `game.enemy_ids` must stop at the ids (the
extras have none, as a bigger posse's partners never had);
`hound_check.gd` plays with the director off (its own moves on hands it
places).

`tools/director_check.gd` holds it (checks.md). `tools/flow_report.gd`
measures it: the balance bot plays the campaign as `balance.gd -- run` does
(keep its `_play_chapter` in step with balance.gd's) and `-- report` prints
the tables. Pass 15 before (v3.12.1) and after, REGULAR, SHARP and ROOKIE at
NORMAL, seeds 1 and 2, every chapter:

Against pass 15's targets (all attempts; seeds 1-2, and seeds 1-4 after
the slash):

| | 3+ alerted within 14 (% of fighting) | melee kills % | melee pulls % | longest fight, no boss in it, s | deaths a run | the chapters' median seconds, summed |
| --- | --- | --- | --- | --- | --- | --- |
| target | 40 or more | ROOKIE under 3 | | ROOKIE 65 at most | pass 9's table | SHARP within 20 % |
| ROOKIE before | 21 / 21 | 9.4 / 8.6 | 29.3 / 28.1 | 137 / 143 | 2.50 / 3.25 | 1774 / 1889 |
| ROOKIE after | 36 / 37 | 1.1 / 1.5 | 9.2 / 6.4 | 79 / 92 | 3.50 / 3.00 | 1671 / 1614 |
| REGULAR before | 27 / 26 | 0.7 / 1.9 | 1.4 / 1.8 | 88 / 97 | 0 / 0 | 1802 / 1846 |
| REGULAR after | 37 / 37 | 0 / 0 | 0 / 0 | 87 / 87 | 0 / 0 | 1715 / 1743 |
| SHARP before | 30 / 29 | 0.1 / 0.1 | 0.4 / 0.2 | 118 / 118 | 0 / 0 | 1704 / 1710 |
| SHARP after | 37 / 36 | 0 / 0 | 0 / 0 | 58 / 86 | 0 / 0 | 1690 / 1698 |

Alerted hands within 14 while fighting, all runs (seeds 1-2), before and
after: 1 at a time 53 -> 44 %, 2: 22 -> 20, 3: 10 -> 13, 4: 7 -> 9, 5: 4 -> 7,
6+: 5 -> 7. By chapter, the 3+ share and the fights (seeds 1-2):

| chapter | 3+ % | fights an attempt | median fight s | longest fight s | median quiet gap s | gaps of 12 s+ | longest calm s | deaths a run (seeds 1-4) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| hickston | 25 -> 34 | 7.6 -> 7.6 | 14.1 -> 15.3 | 67 -> 65 | 8.3 -> 9.4 | 1.0 -> 2.1 | 13 -> 27 | .17 -> .17 |
| fair | 13 -> 28 | 5.3 -> 5.9 | 17.1 -> 15.6 | 137 -> 68 | 11.2 -> 11.5 | 2.1 -> 2.3 | 25 -> 23 | .75 -> .25 |
| sawmill | 25 -> 34 | 5.0 -> 6.2 | 33.9 -> 18.2 | 137 -> 87 | 8.5 -> 8.9 | 0.2 -> 1.0 | 11 -> 17 | 0 -> 0 |
| quarry | 24 -> 39 | 5.5 -> 6.8 | 11.0 -> 7.8 | 103 -> 70 | 10.1 -> 11.7 | 2.0 -> 2.8 | 18 -> 23 | 0 -> .08 |
| bayou | 31 -> 46 | 6.3 -> 5.9 | 16.1 -> 20.4 | 103 -> 85 | 11.4 -> 13.7 | 2.6 -> 2.9 | 31 -> 23 | .17 -> .33 |
| speedway | 24 -> 37 | 6.5 -> 6.3 | 16.7 -> 14.5 | 44 -> 48 | 8.0 -> 8.2 | 1.0 -> 1.5 | 17 -> 19 | 0 -> 0 |
| moonshine | 37 -> 52 | 4.8 -> 3.9 | 19.7 -> 18.9 | 78 -> 74 | 13.2 -> 14.8 | 2.0 -> 2.0 | 18 -> 19 | 0 -> .17 |
| mothership | 27 -> 26 | 4.8 -> 3.5 | 42.8 -> 43.4 | 77 -> 125 | 7.8 -> 11.1 | 0.5 -> 1.2 | 13 -> 18 | 0 -> 0 |

(The longest fights past 65 s after are mostly a boss's: Maw's, the baron's,
the swamp king's, the foreman's with the run up to them.) Supply: the ROOKIE
was dry 35.5 s an attempt in Hickston before, 1.5 after; melee kills in
Hickston 16.2 -> 1.9 %, the Fair 9.9 -> 1.0 %. Time to kill (seeds 1-4, s from
the first hit / from first targeted): the tin guard 5.8 / 6.9 -> 3.9 / 5.9,
big billy 3.0 / 4.5 -> 1.9 / 2.8, the noodler 2.1 / 4.5 -> 2.0 / 4.0, the tire
roller 2.0 / 3.0 -> 2.1 / 3.4, the tough guys 2.1 to 7.9 -> 1.7 to 7.7. The
fight loop still plays 80 to 90 % of a chapter (the music track, T5, reads
the intensity). Deaths: 13 in the 12 campaigns before, 12 after; the
ROOKIE's are now mostly at bosses (Jerry, the revenue man, the swamp king)
and the Fair's opening crawlers, before the first peak. A bot can still be
walled in after a boss falls (the objective's route no longer reaches the
player, `world.blocked` true where they stand: seen three times in about 70
campaigns while tuning, two of them with settings since changed; in none of
the 12 final campaigns nor of the base's 12). Not found yet; a person may
see the same.

Speed (hickston, `tick_spikes.gd` and `net_bench.gd`, back to back with
v3.12.1, medians): the tick 1.31 -> 1.27 ms (the bot's game is a different
game now: bigger fights, more wreckage, p95 2.4-2.8 -> 3.1-3.3); the
director's first tick, when it picks the hands, 1.7 ms; net_bench's tick
1.52/1.59 -> 1.48/1.53 ms (1 player), 1.70 -> 1.46-1.56 (2), 2.33-2.37 ->
2.19-2.36 (4); a snapshot carries 14 more hands in Hickston (116 for 102):
capture 8.3 -> 8.9-9.5 ms, 28.9 -> 29.7 KB packed, the host's delta 2.26 ->
2.21 KB.

## Drawn between ticks (pass 14)

The tick is 1/120 s (`MainState.SIM_STEP`; `main.gd advance` runs as many
as the frame's time holds, the rest waits in `accumulator`). With FRAME
LIMIT at 120, 144 or 240 single player is drawn part way between its last
two ticks (`SoloBlend`, `src/solo_blend.gd`: the players, the guns' timers,
the clock, the hands near the view, the shots, the wreck pieces, the gibs,
casings, vehicles and the hound), a tick behind play, and put back exactly
after the frame; the view turns every frame by the mouse not yet played, so
the crosshair is where the next tick fires. Nothing a tick does changes: the
same `game.tick` calls, dice, snapshots and replays (`frame_smooth` plays
the same frames both ways to the same hash). A draw-time cache kept in a
feature must be taken by the tick's clock, not the drawn one (the variants'
`look_for_doors`). The whole story is in
[view3d.md](view3d.md#drawn-between-ticks-single-player-pass-14).

## Speed of the tick

- **Line of sight is the tick's big cost** (`LevelData.visible()`, nine
  `blocked()` steps a cell, from every enemy's look and many effects).
  `index_cells` marks the cells either index lists anything under (furniture,
  doors), so a step over open floor with no panes or locked gates in the level
  is answered from the solid grid alone; the answers are the same, about 2.6
  times faster. Keep it exact: a new collision source must be in
  `near_fixtures`/`near_doors` (built by `_build_indexes`) or `blocked()` loses it.
- **Sight's quick tests** (engine pass 6, `level_sight.gd`): a step in a
  `box_cells` cell (open, off the map's edge, no door or geometry listed
  under it; furniture may be) is not tested one by one: the stretch of the
  line inside the cell is tested once against the solid cells round it
  (`_walls_clear`: its box kept blocked()'s .023 from each solid side and
  corner) and against the fixtures' boxes listed there (`_boxes_met`,
  clipped, at the line's heights), and if it meets none every step in the
  cell is clear. At heights on a level with geometry, a step in a cell the
  geometry alone lists is clear when its height and the step before lie
  outside every one of the cell's `LevelGeometry.sight_bands` (each slab and
  sight-stopping segment near the cell from its lowest bottom to its highest
  top, merged). These only ever say "clear" where the step by step test
  would, and read the live grid and lists (a wall opened, a cell walled up,
  furniture broken out); anything else falls through to the old steps. A
  sight line costs less than half what it did (random lines, hickston 74 ->
  34 us at heights, 51 -> 27 flat; the other chapters alike); `ai_check`
  compares 9,000 lines a map both ways on nine maps.
- **The flow field's walk** writes passable() out for open and wall cells
  (the function call was most of it): the same cells in the same order,
  2.5 times faster (hickston about 1 ms -> 0.4 ms a walk).
- **Spikes** (`tools/tick_spikes.gd`: net_bench's bot game played three
  times, each tick at its least, with every feature and listener timed
  apart). Before engine pass 6 the worst ticks of 7,200 on hickston were:
  a hand ducking for cover (`HandTactics.cover`: up to 60 spots, two sight
  lines each, 3 to 11 ms in the tick a shot hurt it), the chapter's first
  tick (the tough guy's whole-level walk in `variants_feature` 4 to 10 ms,
  the squad's activities 3 to 4 ms), a wake spreading to friends near
  (1.7 to 3 ms with their barks), the player's flow field walk (1 to 2 ms
  every quarter second on the move: the p95), a big hit's blood spray
  (`gore.spray`, 1.6 ms) and the wreck pieces (1 ms). Now: cover a few spots
  a tick (`cover_search.gd`), the tough guy's walk made while the level loads
  and kept per level (`Variants.start_walk`), the activities looked up by
  cell (`IdleLife.grid`), the walk and the sight lines above.
- **Cover a few spots a tick** (`src/cover_search.gd`): `Enemy.take_cover`
  hands the search to CoverSearch; all the hands together test at most
  enemies.cfg `cover_budget` (8) spots a tick, a search that runs out goes
  on from where it stopped on the hand's next ticks (`Enemy.cover_hunt`,
  carried) and the hand ducks when it ends (a reload's cover too: down till
  `Mind.reload_until`). The whole search at once (`CoverSearch.whole`,
  `Enemy.find_cover`, `HandTactics.cover`) finds the spot it always did; a
  spot that could no longer change the answer is passed before its sight
  lines.
- **The enemies' level of detail** (`src/enemy_lod.gd`, `game.enemy_lod`, a
  VIEW field): an enemy far from every player who is up (enemies.cfg
  `lod_far`, 20 cells: past the 14 it sees) and with nothing going on (not
  alerted; no shot heard, investigation, search, regroup, flush or kick; not
  hit for `lod_hurt` s; no wind-up, volley, stun, recovery, flinch, milk,
  cover or cover search, retreat, brawl, fetch, ladder, fall, hop or held
  cel; no boss or derby champ) and not out in front of a player within
  `lod_view_far` cells and `lod_view_angle` degrees ticks only every
  `lod_step` (.05) s times .6 to 1 (by its uid and pose, so the turns never
  fall together), with all the time since its last tick (`Enemy.lod_since`,
  carried: the clock of that tick, -1 when not calm; it changes only on the
  ticks it takes, so a waiting enemy adds nothing to a snapshot's delta): its
  timers, walks and dice keep their pace in fewer, longer steps. The tick anything engages it, it ticks that tick with
  what it saved and every tick after. While it waits only what others can
  change is asked again each tick (where the players are, an alarm, a shot
  heard, a hit, a critter's scare, the squad's calls); the rest, which only
  changes on its own ticks, on the tick after each of them. Game.tick asks `enemy_lod.step()` for
  each enemy's step (0: it waits; with several players it is not focused
  either). It changes play (where a far patrol is when you get there) but
  only from play's own state, so it is the same on every machine and in a
  replay; `lod=false` turns it off. On hickston about two thirds of the
  enemies wait on a given tick at the start.
- **Pass 10 (PERFCPU).** A member read through another object
  (`e.alerted` from EnemyLod) costs about twice one read in the object's own
  method, so the level of detail is worked out on the enemy
  (`Enemy.lod_step`, `Enemy.lod_calm`; `EnemyLod.look` takes the players once
  a tick and `Game.tick` calls the enemy's own step), climbing's plain case
  (on its feet: note the floor) is written into `Enemy.tick`, and the walking
  test (`LevelGeometry.can_walk`, `blocked_body`) reads the level's tables
  into locals once and skips both index lookups on a cell `index_cells`
  marks empty. The several-player body buckets are keyed by one number, not
  a Vector2i; `use_target`, the loose things' target, the gun glints and
  lights and the lamps' pickup lights pass over what is out of reach before
  any lookup. Every one answers as before: `cpu_check` holds the level of
  detail's asks, and the bot game played on the old and new builds gave the
  same state hash every 20 ticks on seven chapter, player and hound/event
  mixes.
- **What was tried for the tick and dropped:** cosmetic features stepped at
  60 Hz would move choppier on a display over 60 Hz. (Far enemies ticking
  less often was dropped once for not being exact; it is now the level of
  detail above, a deliberate change of play.)
