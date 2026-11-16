# Levels

A level is `godot/data/<id>.json`. The campaign chapters, the Crossroads, the
range, the 5v5/2v2 maps and the County Run maps are built from a plan in
`godot/tools/levels/`; change the plan and rebuild, because an edit to its
JSON is lost at the next build. [MAP_AUTHORING.md](../../MAP_AUTHORING.md) at
the repo root is the guide to map sources (`godot/maps/*.map.json`) and
`tools/map.gd` (new, inspect, validate, build, render), checked by
`tools/geometry_check.gd` and `tools/map_check.gd`. Play rules that touch
levels (paths, ledges, using things, the hub) are in
[gameplay.md](gameplay.md#levels-in-play).

## The level builder

`godot/tools/levels/level_builder.gd` lays out yards, rooms, buildings,
fences, doors, fixtures, signs and actors; it works out the walls, skins
rooms, bands building fronts and checks the plan. Its kit has gates, lamps,
poles, fingerposts, booths, trailers, stations, `town()` props and rock risers
per floor (`geo_kit.gd` for decks, stairs and bridges).

### The plans

| Plan | Level |
| --- | --- |
| `hickston_plan.gd` (+ `hickston_cast.gd`, `hickston_loft.gd`) | Hickston, chapter 1 |
| `fair_plan.gd` | the fair |
| `sawmill_plan.gd` | the sawmill |
| `quarry_plan.gd` | the quarry |
| `bayou_plan.gd` (+ `bayou_cast.gd`) | chapter 5 |
| `speedway_plan.gd` | chapter 6 |
| `mothership_plan.gd` (+ `mothership_cast.gd`) | chapter 7, all indoors, the last |
| `range_plan.gd` | the firing range, not a chapter (layout 5: the games row south of the armory) |
| `hub_plan.gd` | the Crossroads (`data/hub.json`; layout 4: Mundell's trophy shack behind the Road Department) |
| `grainyard_plan.gd`, `holler_plan.gd`, `salvage_plan.gd` | the 5v5 maps ([modes.md](modes.md#the-maps)) |
| `pumpngo_plan.gd`, `pineacres_plan.gd`, `landing_plan.gd` | the 2v2 maps |
| `county_hickston_plan.gd`, `county_quarry_plan.gd`, `county_bayou_plan.gd` (+ `county_kit.gd`) | the County Run maps ([county_run.md](county_run.md#the-maps)) |

### Placing things

- **Every prop is placed by hand**: nothing scatters things to fill ground
  (the owner: "don't fill a spot just to fill it"). A yard that reads
  unfinished gets a set piece, a few things that belong together against a
  wall.
- After the plan, `mount_signs()` turns any flat sign or piece of equipment
  whose face looks into a wall, puts a plank backing behind one with nothing
  behind it, and posts under one up off the ground (cut-outs get posts only;
  ground decals are left alone).
- Quest props (`quest()`: a station's or the exit's modelled prop,
  `town_quest_<name>`, lit by its signal) stand free on the floor and get
  neither: stand one in a cell's middle or half a cell off a wall face, near
  its station (within 3.5).
- A prop is placed with `town(<name>, ...)`, sized from
  `assets/art/town_props.json`; in the 3D view it shows as its modelled prop
  ([view3d.md](view3d.md#props)). On a raised or sunken floor use the plan's
  own base (the Mothership's `stand()`).
- Stand small pieces in a cell's middle and posts on its corners, so nothing
  thin cuts the line between two open cells (the flow field).
- A box a model or picture already shows (a car's chassis, a parked truck's)
  is a `volume()`: a fixture that blocks and is stood on like any other, but
  is written to `collision_volumes` only, with no walls and no cap. `car()`
  uses one and lays its wreck model along it (`plane`, `hung`).
- On the 5v5/2v2 maps, cover that shoots through is `b.fence(x0, y0, x1, y1,
  top, "cover_boards")` ([modes.md](modes.md#breakable-cover)): outdoors only
  (a cell under a roof or beside a step never opens), nothing standing on it,
  clear of the bots' route lines and of a hold's look (`map_timing.gd --
  strict` says when a hold watches nothing). A new tile goes at the END of
  `data/index.json` ("tiles" and "tile") and `assets_gen/tiles_index.json`:
  levels number tiles by that list.
- A board's `z` counts up from its cell's ground (`game_view.gd`), not from a
  deck over it: a lamp on a walk over water or a pit takes the walk's top
  minus that ground.

### Vehicles and their set pieces

A plan's meta places its vehicles (`"vehicles"`, [gameplay.md](gameplay.md#vehicles))
and the set pieces run in them (`"vehicle_runs"`: the start, the gates in
order, laps, time, reward and lines; level_builder writes both only when
the plan has them). The hands a run sets on the player are ordinary
`b.enemy` rows held back by a trigger whose `"when"` is `{"run": id}` and
whose `"do"` wakes them. Each vehicle has its KEYS IN IT sign beside it
(`vehicle_sign_<kind>`): Hickston's is hung on the chapel wall that was
there (`"hung"`, nothing built, so no new layout), the bayou's stands on
the dock walk, the speedway's hangs on pit row's garage wall. County Run's
maps drop the vehicles, their runs and their signs (`county_kit.gd`).
Feature pass 7 put them in: `bayou_plan.gd channel_run()` (layout 5: the
sign, the king's boys, the CHANNEL RUN) and `speedway_plan.gd heat_race()`
(layout 4: the sign, the pit crew, the HEAT RACE; and the team's hauler in
`speedway_cast.gd` moved off turn 2's banking into the gravel behind it, so
the oval can be driven all the way round). A run's gates must lie on what
its vehicle runs on and be reachable in order; `tools/vehicle_set_check.gd`
drives each one to the end.

### The guns along the way

Feature pass 7 (`src/gun_finder.gd` makes a gun not had yet shine, go on
the map and be named; [gameplay.md](gameplay.md#finding-the-guns-feature-pass-7)).
Each chapter with a first-time gun well off its way has a `new_iron()` in
its plan: a second copy of the gun by the way (the first left where it was,
its rounds still worth the walk) under a hand-painted sign
(`gun_sign_<name>`, `tools/art/build_gun_signs.gd`), hung (`"hung"`) on a
wall or counter that was there. Pickups and hung signs only: nothing built,
so no new layout (a save keeps its own pickups and holds no boards; an old
save goes on with the pickups it had):

- Hickston: Bait & Ammo is shut, so a few are left out front on the county
  road under GUNS (a rifle painted by it) / HONOR SYSTEM (the sling blade,
  rifle, teat gun and rip saw); a GUNS THIS WAY arrow on GAS-N-GUT's south
  wall round to its crossbow; a hobo's chalk gun and X on the trailer by
  the alien arm gun's secret closet (it stays secret: its cells lie out on
  the registry floor by the way).
- The fair: the bottle rocket launcher as a prize at the midway's east
  booth across from the shotgun's, its counter painted WIN A GUN / NO
  REFUNDS (the powder
  keg already lies on the way).
- The sawmill: the bowling ball (a level's `riveter` pickup is the bowling
  ball in the campaign, `game_state.gd ALIAS`) by the sorting yard's north
  wall in sight of the e-stop, under MILL LEAGUE / BOWLING NITE.
- The quarry: the cow launcher (the `pressure_gun` pickup) at the foot of
  the cliff by the weigh station, under DANGER / COW LAUNCHER / NOT YOU
  MUNDELL.
- The bayou, the speedway and the ship lay out no gun new in campaign order
  (a gun missed earlier still shines there); the hub lays out none.

Every word on a gun sign is painted at least twice its size and the signs
hang about two thirds of a cell tall, so each line reads at 320x200 from a
few cells off: few words, big, the joke in the big words.

County Run's maps drop the gun signs with the vehicles' (`county_kit.gd`),
and their pickups as before. A new sign must hang on something facing out,
and a new first-time gun lie within `NEAR` steps of the way, signed if it is
further than `SIGNED` and out of sight: `tools/gun_find_check.gd`.

### Places to climb

Since v3.2.0 every chapter has height to climb (`climbs.gd`, one function a
chapter, called at the end of its plan's build(); the County Run maps built
on a chapter get them too). `climb_kit.gd` builds them on geo_kit: `block()`
(solid to the ground, walked on top: a shed's flat roof, a stack, a
container, a rig's box trailer), `shed()` (a block with a ladder, rails on
the sides named), `tower()` (a deck on corner posts, railed but at its
ladder, an optional tin roof: deer stands, lookouts, a water tower's walk),
`catwalk()` (a railed walk along a wall with a ladder at one end) and
`ladder_on()`; `Geo.ladder()` is the ladder itself (`x, y` on the face it
leans on, `dir` the way it is climbed, `z0` to `z1`). Rules: put a ladder's
face on a cell line, so its foot and its top are in different cells (the nav
graph joins those; `climb_check` fails on one that joins nothing); keep a
block a chest-high pull-up (at most 1.15) or give it a ladder; same-height
blocks a jump apart want a gap of 1.6 at most; stand none in a way through,
a quest prop's reach, the fair's gallery or midway, the hub's shack, the
speedway's track or the multiplayer maps. A pickup or an enemy up top takes
the floor's height (`b.pickup(..., z)`, the enemy's `z`: `climbs.gd
_lift`).

### Building one

`build_level.gd -- <id> map=<png>` writes `data/<id>.json` and a top-down
picture, and stops on problems: a thing in a wall or furniture, furniture
cutting a path, a picture missing, anything the start cannot walk to. It
prints how much open ground has nothing near it (red on its map picture):
information, not a target.

```
godot --headless --path godot --script res://tools/levels/build_level.gd -- fair map=<png>   # hickston, fair, sawmill, quarry, ...
godot --headless --path godot --script res://tools/levels/build_level.gd -- grainyard        # 5v5: grainyard, holler, salvage; 2v2: pumpngo, pineacres, landing
godot --headless --path godot --script res://tools/levels/build_level.gd -- county_quarry    # county_hickston, county_quarry, county_bayou
godot --headless --path godot --script res://tools/first_minutes.gd -- hickston whole        # bot plays it to the end (god mode)
godot --headless --path godot --script res://tools/route_map.gd -- <dir>                     # each level's objective route, long detours flagged, PNGs
```

After a rebuild, run `tools/quest_reach.gd` (if a station or its board moved)
and `tools/view3d_check.gd` (the level's 3D mesh builds).

## Layouts and saves

**Levels have a `layout` number.** Bump the plan's "layout" when the map
changes so old saves of it start the chapter over. A save records it (save
version 7); a save of an older layout of its level loads at that chapter's
start with its guns, rounds, health and pockets (`save_restore.gd _restart`),
and a finished chapter of an older layout stays finished. Rebuilding a level's
map means:

1. Bump its plan's `layout`.
2. Run `save_fixtures.gd -- make`.
3. Fix the old fixtures' expected positions in `tools/saves/expected.json`.

A save whose doors or enemies no longer match its level (changed without a new
layout) restarts the chapter too, rather than failing to load. A rebuild that
only changes how things look (a wall's or fixture's texture, where a board
hangs) keeps the layout: a save holds none of it, and a new layout would send
every player of that chapter back to its start for nothing. The hub is never
saved, so a new hub layout needs no save fixtures.

## Editing a level by hand

`godot/data/<id>.json` is the source for a level not built from a plan. Change
one:

- in the Godot editor's Levels screen (`addons/clmr_levels`: paint walls,
  floors, enemies, pickups and trigger areas, with undo, then Save; Play from
  here);
- in the game (F2 when running from the project folder);
- or from the command line:

```
godot --headless --path godot --script res://tools/level_edit.gd -- fair enemy billy 30.5 25.5
godot --headless --path godot --script res://tools/level_edit.gd -- hickston trigger '<json>'   # src/triggers.gd
```

Every way the wall list is patched (`src/level_edit.gd`) and a running game
reloads the level. `tools/level_edit_check.gd` (LEVEL EDIT OK) holds it.

Wall files keep a piece per cell for the editors; straight runs of one
repeating material merge into one piece when a level loads
(`LevelData._merge_runs`).
