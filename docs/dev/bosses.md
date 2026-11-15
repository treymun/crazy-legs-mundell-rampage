# Bosses

The eight bosses: the sheriff (`boss`), Jerry, Rudy, the foreman, the Baron,
the Swamp King, Boggs (`derby_champ`) and Maw Glorb. Their numbers are in
`data/tuning/enemies.cfg` (health, speed, `title`, drops) and
`data/tuning/bosses.cfg` (the boss scripts' numbers, read through `BossData`).
To add one, see [how_to_add.md](how_to_add.md#a-boss).

## The framework

Boss fights share a framework: `src/boss_kit.gd`, `features/boss_fight.gd`,
`src/bosses/`.

- Each of the eight bosses (a `title` in enemies.cfg) has a `BossMoves` file
  (`bosses/boss_moves.gd`): `fight_start`, `phase_changed`, `tick` (true skips
  the brain), `weak_spot` (a damage multiplier, no dice), `telegraph`,
  `looks`, `dying`, `stagger_hit`/`stagger_rest`, `hog_wild(game)`.
- `BossKit.moves(kind)` hands back one instance shared by every game (from
  `BossKit.MOVES`, or the `brain=` kind's), so keep a fight's state on the
  enemy or in a feature's save.
- `Enemy.boss_phase` (2 under half, 3 under a fifth; Maw by her own lines) is
  worked out from health, never saved.
- A player's hit sets `game.hit_point`/`hit_from` before `hurt()`, which asks
  the weak spot and forgets the point.
- A big instant (`struck_sum` past `BossKit.STAGGER`) staggers.
- The entrance holds the world only when `game.lessons` (never in tools,
  tours, benches, bots) and once a save.
- Backup at phases 2 and 3 joins the enemies after the level's own (the posse
  feature saves them; `game.boss_backup` off for a rematch).
- A fall sets `game.slowmo` (game.gd steps the world at `SLOWMO_PACE`, the
  player and gun at full speed). SLOW-MO FINISHERS off drops it when alone;
  the last kill of an ordinary fight has its own, eased
  (`features/finishers.gd`, [gameplay.md](gameplay.md#ragdolls-and-finishing-shots-v320)).
- Signals for voices and the like (on `game.events`): `boss_intro`,
  `boss_phase`, `boss_staggered`, `boss_weak_hit`, `boss_down(e, seconds)`.
- `tools/boss_check.gd` (in check_fixes) holds it; `physics_frames.gd
  only=boss` takes its pictures.

## The arenas of the sheriff, Jerry, Rudy and the foreman

`features/boss_arena.gd`, `bosses/arena_moves.gd` under `sheriff.gd`,
`jerry.gd`, `rudy.gd`, `foreman.gd`.

Each plan gives `meta["boss_arena"]` (level JSON `boss_arena`,
`LevelData.boss_arena`): per kind its `box` (Hickston's two are
BossFight.in_arena_at's test: the bar, the music, the checkpoint), `floods`
(floodlight towers that cut at phase 3 and come back when it falls), `lights`,
`approach` (the picture tool's walk-in) and its hazards' places. The feature
keeps fire (a fuel tank, gas can or drum going up in an arena leaves the
ground burning, sawdust too; it bites the player and any boss or hand),
strikes, lobs, rollers (tumble.gd), the mill's carriage and the big top's horn
lanes; it saves nothing. A boss's shot breaks the cover it meets. All four: a
desperate boss shrugs off staggers longer and a gun's plain hit counts .7
(`guarded`).

- *Sheriff*: the rodeo grounds north of the corn (chute gate under STAMPEDE
  RODEO, the ring, grandstand, the saucer in its crater, Bessie's pen); stands
  before the wreck, seen through the gate; propane, alien fuel cells, bales;
  weak spot the power pack from behind (2x, shoulder 1.5x), and once mad he
  vents it with his back turned; phase 3 the saucer strike (rings, then bolts
  that burn him too), reactor red, fire round the wreck, lights out; HOG WILD
  a plasma ring.
- *Jerry*: the Hogs' field west of the rodeo behind a stock gate the sheriff's
  fall opens (trigger `field-gate`); midfield; tyre stacks that roll, the
  concession propane; weak spot the knees (2x, a blast at his feet 1.5x),
  helmet .6x; phase 3 the blitz down a marked lane (into a post or wall he
  rings his bell, stunned), the scoreboard shorts, bleachers burn, lights out;
  HOG WILD a flaming pigskin.
- *Rudy*: the pavilion is his big top (ring, bleachers, PA horn stacks at its
  corners, helium, balloons, bulbs, RUDY'S BIG TOP over the stage); in the
  ring, seen from the stage where the broadcast is cut; mad, the stacks fire
  lanes at the player (and hurt him); weak spot the drum low in front 1.75x,
  the horns while he blows 2.25x; phase 3 the grand finale rings with spokes
  showing the gaps, spotlights sweep; HOG WILD balloon bombs (shoot them). His
  horn volley now flies at chest height (it used to pass over the player).
- *Foreman*: the saw floor with its carriage track clear end to end (the
  carriage runs on a bell, every 9/6.5/4 s by phase, and hits him too), head
  saw, log decks, sawdust; across the track from the shed's south door; weak
  spot the saw rig from behind 2x; phase 3 the big cut (a fan of blades that
  bounce), the saw speeds up; HOG WILD a kicked fuel drum (shoot it).

`tools/arena_check.gd` (in check_fixes) holds it; `tools/arena_frames.gd`
takes window pictures of each arena (`docs/boss_arenas/`).

## The last four bosses' arenas

`features/boss_arenas.gd`, from each plan's `boss_arena` meta
(`LevelData.boss_arena`): hazards that hurt the boss as well as the player,
each third phase's arena change, `drop()` (a throw onto a marked spot whose
ring closes in: copper rain, dynamite, curlers), `burn()` (burning fuel or
oil), and the arena's own `lights` and valve `steam`. Nothing saved: the
change follows the boss's health. `tools/arena_frames_late.gd` (a window)
takes pictures of each: the way in, the reveal, the fight, phase 3.

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
their PAR. Maw's own fight is described in
[gameplay.md](gameplay.md#levels-in-play) (the Mothership).

## The arenas wreck and the gear comes off

BOSS ARENAS WRECK (setting, on by default, PLAY; `game.boss_wrecks`, carried
like DIFFICULTY): off, the fights are as before.

- **The arenas come apart** (`features/arena_wreck.gd`, bosses.cfg
  `[arena_wreck]`). Each boss has steps that fire as its health falls past
  their `at` (the phase lines .5 and .2 among them; Maw's two thirds), some
  again every few of its attacks (`every`). `topple`: a prop the level
  stands there shakes over its painted lane, goes over along it, flattens
  whoever is in the lane (the boss twice as hard, a stun: lure him) and lies
  as cover (a row of low boxes, `LevelData.add_volume`; bodies and shots
  stop at them); its own base leaves the way. `fall`: a hanging lamp lets go
  over a closing ring and lies where it lands. `scatter`: the props named
  near the boss are flung (Tumble) and land elsewhere as cover. `wave`: a
  ring rolls across the water from him, shoving and wetting whoever it meets.
  `blowout`: the windows round a spot blow out (`wall_breaks.blast`). By
  arena: the rodeo's searchlight, then the saucer's pylons; the Hogs'
  generator, grill, then the scoreboard; the big top's rigging lamps and
  searchlights; the saw floor's shop lamps, the engine hoist and the belt
  conveyor; the still house's lamps, windows and the two copper vats; the
  lagoon's lantern posts (the stilts going), the waves and the dead snag; the
  bowl's crushed stacks and wrecks (each few of his attacks) and the last
  floodlight tower; the core's pods. The props are drawn as their models on
  the move (`View.Sprite.track`); a board taken over is
  `LevelData.Billboard.hidden`, a lamp a `game.props` sprite taken away.
  Play: no dice, carried (SIM_FEATURES) and a fact (FACT_FEATURES: restore
  puts the cover, the hidden boards and the lamps right). The boss
  checkpoint's retry calls `reset()` (`BossDoor.at_door`); a rematch is a
  fresh game. `tools/wreck_lanes.gd` lists the open ways each prop can go
  over.
- **Gear shot off** (`features/boss_gear.gd`, bosses.cfg `[boss_gear]`): a
  hit where a piece sits (a band of the boss's height, front, back or any
  side) wears it by its damage (`BossKit.weak` asks `struck`); worn it soaks
  that hit by `armour`, worn out it flies off as a piece of the model,
  tumbles and lies on the floor, and a hit there counts `bare`. Some come off
  by themselves (`falls`: the derby truck sheds hood, trunk lid and ram as he
  is beaten). What changes: Jerry's helmet stops guarding (head 1.3x), Rudy's
  shoulder horns off end their weak spot and halve his finale ring, the
  foreman's hard hat and the King's bow shield soak until gone, Boggs's rams
  bite `ramless` (.6) once the ram is off; hats, the tin star, the monocle,
  the crown and Maw's curlers and glasses fly for the fun of it. Carried and
  saved; the checkpoint's retry puts every piece back.
- `tools/arena_wreck_check.gd` (in check_fixes) holds both for all eight;
  `tools/wreck_frames.gd` (a window) takes pictures of each step and of the
  gear coming off. In `docs/godot3d/features/F/` each sheet is a step read
  left to right, then down (before, its warning, going over, lying as
  cover: the Baron's vats, a saucer pylon, Jerry's scoreboard, a lagoon
  lantern post, a core pod, the derby wrecks flung) or the gear (on,
  flying, off, each piece lying: the sheriff's hat and star, Boggs's
  panels).

## The bosses' art wears the fight

`src/boss_looks.gd`, called from `Enemy.sprite()` for bosses only.
`build_enemy_actors.gd` renders the eight bosses on a dusk stage (warm key,
two rims, more samples; `enemy_actors.py light_for`, the graphics card when
Cycles has one) with less grain, plus a wind-up cel `<kind>_wind` (the first
half of a wind-up; then `_aim`) and a battle-damaged copy of every living cel
per phase: `<kind>_p2_<cel>` under half health, `<kind>_p3_<cel>` under a
fifth (Maw: `maw_p2_` from her fight's phase two, two thirds, housecoat on
fire; `maw_p3_bare_` out of it). The damage is `DAMAGE` in the Blender
scripts: every material scorched (`mat` `_battle_worn`) plus each boss's own
rags, smoke, flames and breakage; falls are drawn beaten. A cel without a
variant keeps its name. `pack_assets.gd` stores identical pictures once (the
old three-cel walk names).

In the 3D view the bosses are ActorView models baked from the same Blender
builds, with looks plain, hurt, p2 and p3 picked by health and phase (see
[view3d.md](view3d.md#actors)). `tools/boss_closeups.gd` (every boss in its
level in each state, drawn by the software view) was retired with the
software view; a tour viewpoint with `actors` shows the 3D models instead.

## The regular hands' art

The regular hands' art wears the fight too (`src/enemy_looks.gd`, called from
`Enemy.sprite()` for every non-boss hostile). They are drawn on the same dusk
stage with the cleaner grain, with a wind-up cel `<kind>_wind` (racking,
cocking, rearing, revving, charging; a glint on the business end) and a hurt
copy of every living cel, `<kind>_hurt_<cel>`, shown under half health: blood
soaked in (`actors_wounds.py _wounded`, green for `blood="plasma"` kinds, dents
and scratches on metal), a split brow, a gut wound the free hand clutches, a
limp in the walk (`skeleton()` while `WOUND`); creatures mark their own (torn
wing, cracked shell, smoke, sparks). A cel without a variant keeps its name.

The variants `big_billy`, `drunk_coot` and `shield_deputy` (behaviour in
enemies.cfg with `brain=`) are drawn in `scripts/blender/actors_variants.py`
with their base kind's cels (big_billy at 1.15x Billy's frame); they are in
art.bin, not a chapter pack. `tools/art/enemy_sheet.gd -- dirs=<old>,<new>`
lays cels side by side (`docs/enemy_art/`). The chicken, pig and Bessie are not
Blender actors. `tools/enemy_closeups.gd` (each kind in a level: whole,
walking, wind-up, aim, attack, hurt, limping, pain, down) was retired with the
software view; a tour viewpoint with `actors` shows the 3D models instead.

## Fight music

`features/fight_music.gd`, `sound.gd` crossfade, swaps a chapter's music for
its fight track (`assets/music/fight_*.ogg`, made by `audio_build.py
--fights`) while hands hunt or attack nearby. Each chapter also has a boss
loop (`boss_<chapter>`, `Sound.BOSSES`), faster and heavier, that takes over
while its last boss is alive, awake and the player is in its arena (as far as
the boss bar shows), holds `BOSS_HOLD` seconds after the player steps out and
hands back the moment the boss falls.

## The boss checkpoint and BOSS REMATCH

- **Checkpoint.** A beat after a boss fight begins (`BossFight.on`, the boss
  bar's test) `features/boss_checkpoint.gd` saves the game, in SessionStore's
  own format (no new version), to `boss-checkpoint-<chapter>[-replay].json`
  in the profile; the door is the last spot the player stood clear of the
  arena. On the death screen ENTER then retries the fight (`main_flow.gd
  retry_fight`, `boss_door.gd`: boss whole, player at the door, health and
  rounds as they were) and RELOAD's key starts the chapter over. A win clears
  it, another chapter's start clears it.
- **BOSS REMATCH.** The title's BOSS REMATCH (`boss_rematch.gd`,
  `features/boss_rematch.gd`) loads a beaten chapter with only that boss,
  every station done and door open, the `GUNS` table full and the player
  `DOOR_STEPS` flow-field steps from the boss; it is timed to the fall and
  ribboned by `PAR` (from `boss_rematch_check.gd -- bot`: run it again after
  changing a fight). Bests and beaten chapters live in `boss-rematch.json`,
  never in a save; nothing in a rematch saves or carries out.
  `--rematch-all` or the console's `rematch` opens every boss. Tool scripts
  keep both files under the cache folder.
- `fight_began(foe)` in both features is the one place a fight's start is
  noticed (the boss framework's intro signal can call it).
- `tools/boss_rematch_check.gd` holds both (its quick part runs in
  check_fixes).
