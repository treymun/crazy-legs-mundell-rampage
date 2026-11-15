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
- A board's `z` counts up from its cell's ground (`game_view.gd`), not from a
  deck over it: a lamp on a walk over water or a pit takes the walk's top
  minus that ground.

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
start with its guns, rounds, health and pockets (`session_store.gd _restart`),
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
