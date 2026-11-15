# Gameplay: things that are easy to get wrong

The play code is the chain `game_state` -> `game_world` -> `game_combat` ->
`game_view` -> `game` in `godot/src/` (see [architecture.md](architecture.md)).
Bosses are in [bosses.md](bosses.md), modes in [modes.md](modes.md), the
level builder in [levels.md](levels.md).

## Rules that hold everywhere

- **Gameplay randomness** comes from the game's `rng`. Cosmetic effects use
  their own seeded generator (`gore_fx.dice`), so they never change play.
- **Saves are versioned.** Changing what a save holds means bumping
  `SessionStore.VERSION`, adding the step from the old version in
  `src/save_upgrade.gd`, and running `tools/save_fixtures.gd -- make` to add
  saves of the new version to `godot/tools/saves/`. Never delete the old ones:
  they are how CI knows players' saves still load.
- **Tool scripts never write the player's settings** (`main_state.gd
  persist_options` returns when a script runs the main loop), and tests write
  saves under `OS.get_cache_dir()`. The gun pictures warm on a thread that
  `Weapons.Armory.settle()` waits for when the program closes.
- **Settings** are listed in `src/setup_pages.gd` (one row each: label, key,
  default, choices, hint); `tools/check_fixes.gd` counts them (59 now; DRAW
  DISTANCE is the newest, under VIEW). Settings are not part of a save, so a
  new one needs no save version. Changing a setting shows what it did and that
  it was saved where the hint goes (`main_flow.gd`).
- **Keep the Redneck Rampage feel** in new polish: dusk and dirt, brass and
  red hulls, crows, county-fair words and ribbons, cartoon wipes; original art
  and sound only (new small sounds can be made in `assets.gd` MADE_CUES).

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
`wall_struck` and `blast_shoved`. `game.events` is a VIEW field in
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
(`compare_3d.gd`'s `_gpu` pictures hold that): `features/gun_fx.gd` (blasts:
a white star, a fireball rolling up into soot with two smaller beside it, a
smoke column, charred scraps trailing smoke, a dust ring on the ground,
lights `blast_flash` and `boom_glow`; strikes by material, `fx_hit_<kind>`,
with more chips; wadding, smoke and sparks off the muzzle; fuse and rocket
sparks; all capped, a chain of blasts throwing less each, its own dice, made
whatever the view), `gun_flash.gd` (each gun's muzzle flash: weapons.cfg
`flash_art`/`flash_size`, over the old flash as a glow), weapon_fx's fatter
tracers with a glowing head, and each gun's own muzzle light
(`[light.muzzle_<gun>]`). game_view.gd leaves the old `fx_blast` fireball out
then. The pictures are in [art.md](art.md#gun-effects-art).

## The automap, canvas and sprites

- **The automap** (`game_view.gd`) follows the player at a readable zoom
  (PGUP/PGDN, keypad +/-, the mouse wheel; zoom 0 fits the level), from an
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
  scripts.

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
- **Using things is forgiving, and checked** (`game_world.gd use_target`): a
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
- **Wall runs merge when a level loads** (`LevelData._merge_runs`, level.gd):
  straight runs of one repeating material become one piece. Files keep a
  piece per cell for the editors.
- **Deep water and steering** (dev.45, `src/deep_steer.gd`): a hand that
  cannot swim and sees the player across deep water (no deck) follows the
  flow field; `LevelData.over_deep` is a deck over the water.

## Enemies

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
- **The county's hands fight smart** (`enemies.gd`): a hurt hand may duck
  behind cover the player cannot see (`find_cover`), a badly hurt one runs to
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
  retakes and his voice.

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
- Breakables save in the features block. Sounds wanted for them:
  `docs/physics_audio.md`. `tools/break_check.gd` (in check_fixes) and
  `tools/physics_frames.gd` (window pictures of each effect) cover it.

### Walls break too

`features/wall_breaks.gd`, breakables.cfg `[windows]` and `[fence.<tile>]`.

- A window face is one wall piece showing a `_win`/`_lit` tile (or
  `trailer_window`); shot in its glass or blasted it swaps in place to
  `<material>_brk` (`tools/art/wall_break_art.gd`; `_brk` is laid by height
  like `_win`, see `LevelTiles` in `src/level_tiles.gd`) and stays a wall.
- A fence cell (stockyard) shot down to `damaged` swaps its faces to
  `stockyard_hit`, and at 0 hp `LevelData.open_cell()` makes it floor: its own
  face pieces leave `walls`, each solid neighbour gets the face
  `implied_walls` would give it, `walls_version`/`solid_version` bump (the 3D
  view's level mesh key and the automap signature), both flow fields reopen
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
  (`Assets.faded_art`, alpha-scaled copies). Features add wall marks through
  `wall_marks()`.
- `features/dust.gd` is gun smoke, boot dust, race-car and derby dust and
  embers off fires (`dust_cap`), drifting on `[debris] wind_<level>`.
- `features/feel.gd` puts the gun on springs (sway, each gun's kick from
  recoil/retreat/view_rise/settle/spring_damp, landing, blows) into
  `player.weapon_lag` and the view's kick into `view_kick` (game_view.gd adds
  it to the eye like the shake, never to the aim); VIEW BOB scales sway and
  landing, SCREEN SHAKE the blows, off means none. Sounds it wants are in
  `docs/feel_audio.md`.

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
- **Sound effects are QOA** (`sfx.bin`, about a fifth of 16-bit samples), and
  the tiles and skies are deflated whole (`Assets.pack_whole`). An
  `AudioStreamWAV`'s `data` is then not samples: count frames with
  `get_length() * mix_rate`.

## The browser packs

**Chapter music and chapter enemies are a separate download in the browser.**
`tools/pack_assets.gd` writes `music_<chapter>.bin` and, for the enemies only
one chapter has (`Assets.CHAPTER_KINDS`), `art_<chapter>.bin`; the web presets
leave them out, CI turns each chapter's pair into a pack (`tools/make_packs.gd`)
and `pack_loader.gd` fetches them after start. `main_flow.gd play()` holds a
chapter until its pictures are there. A new enemy kind used in more than one
level must not be in `CHAPTER_KINDS` (`verify_assets.gd` checks). A browser
cannot rename files in its storage and HTTPRequest's `download_file` does not
write there: keep writing packs from memory.

## Speed of the tick

- **Line of sight is the tick's big cost** (`LevelData.visible()`, nine
  `blocked()` steps a cell, from every enemy's look and many effects).
  `index_cells` marks the cells either index lists anything under (furniture,
  doors), so a step over open floor with no panes or locked gates in the level
  is answered from the solid grid alone; the answers are the same, about 2.6
  times faster. Keep it exact: a new collision source must be in
  `near_fixtures`/`near_doors` (built by `_build_indexes`) or `blocked()` loses it.
- **What was tried for the tick and dropped:** enemies far away (past the 32
  cells the old renderer drew) ticking at 30 Hz with the time saved up kept
  the dice the same but stepped far patrols coarser, so where a hand stood
  when the player got there could differ from before (not exact, so not
  kept); cosmetic features stepped at 60 Hz would move choppier on a display
  over 60 Hz. Keep tick changes exact (same state, same dice).
