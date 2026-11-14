# Map authoring

How to make and change maps for Crazy Legs Mundell Rampage from structured
files and commands, by hand or as an AI agent (Claude, Codex, anything that
can edit JSON and run a shell). Everything here is implemented and checked by
`tools/geometry_check.gd` and `tools/map_check.gd` (both run in
`tools/check_fixes.gd`, so in CI).

Contents: the model, the files, the workflow, commands, the source format,
components, validation codes, playtests, pictures, the editor, glTF import,
existing levels, limitations.

## The model (what geometry the game has)

The game draws and plays a 2.5D world (as the 1997 engines did), extended in
level **format 2**:

| piece | what it is | collision | sight and shots | rendering |
| --- | --- | --- | --- | --- |
| cells | the grid: solid cells (walls, hedges, rock) and open cells with a ground height and a roof height | full height | full height | walls of the solid cells, floors, ceilings |
| decks (slabs with a thickness) | a floor walked on **and under**: lofts, landings, catwalks, balconies, bridges | 3D: a body climbs onto one at most .245 above its feet, falls off its edge, passes under it with headroom | the slab stops looks and shots; a shot can land on it | top, underside and edges |
| blocks, stairs, ramps (slabs solid to the ground) | plinths, docks, stair treads, sloped ramps | 3D | stop looks and shots | top (flat or sloped) and sides |
| walls (segments) | free walls at any angle, any thickness >= .08, with their own bottom and top; openings cut to size | 3D (a rail stops a body, not a bullet over it) | per wall (`sight`, `shots`) | faces (and a top when low and thick) |
| ceilings | a surface overhead with no floor on it | headroom | — | seen from below |

A level without geometry (format 1) plays exactly as it always did.

Bots, enemies, the objective pin and the 5v5 bots path on a **nav graph**:
each cell's own floor is a node, and every deck over a cell is another node
at its height, so a bot on a loft and one under it are on different nodes;
stairs and ramps join them. A wall opening only joins the graph where a cell's
middle line passes through it (validate warns otherwise).

## Units and axes

- 1 map unit = 1 cell. x runs east, y south, z up from the ground.
- The eye is .95 over a floor; a door 1.85 high; a step at most .245 (higher
  takes a jump, about .6); a body is .2 round and 1.12 tall (.86 crouched).
- Every `rect` is `[x0, y0, x1, y1]` in map units with x1, y1 exclusive. Types
  that change cells ("grid" in the table below) want whole numbers and cover
  cells x0..x1-1, y0..y1-1.
- Angles are degrees: 0 east, 90 south.
- Heights: `top`, `z`, `z0`, `z1`, `from`, `to` are absolute (over the
  ground's zero), not over the floor below.
- Real-world models: a real door (2.1 m) is 1.85 units and a real eye (1.6 m)
  is .95, so the game's world is stylised; `scale=0.6` on import puts a
  metre-built model near the game's proportions. Check doors with validate.

## The files

| file | what it is | edit it? |
| --- | --- | --- |
| `godot/maps/<id>.map.json` | **the map's source**: the one authoritative file for maps made this way | yes (by hand, with `tools/map.gd`, or in the editor's Maps screen) |
| `godot/data/<id>.json` | the built level the game loads | no: `map.gd -- build` writes it and refuses to write over hand changes |
| `godot/maps/built.json` | the hash of each level as last built (how a hand change is noticed) | no |
| `godot/maps/.history/<id>/` | a copy of the source (or level) before every edit and build; `undo` uses it (not committed) | no |
| `docs/map_schema.json` | JSON Schema of a source | generated: `map.gd -- schema` |
| `docs/map_catalog/` | catalog of components, tiles, props, enemies, pickups with thumbnails | generated: `map.gd -- catalog` |
| `docs/map_examples/` | the demo map's build script and viewpoints | example |
| `godot/tools/levels/<id>_plan.gd` | the older levels' sources, written as code; a map source may build on one (`base`) | yes, for those levels |

## The workflow

Set `GODOT` to the Godot console executable (on this machine
`C:\Users\treym\OneDrive\Desktop\Tools\Godot_v4.7.2-stable_win64_console.exe`)
and run from the repo root:

```bash
map() { "$GODOT" --headless --path godot --script res://tools/map.gd -- "$@"; }
```

1. `map new <id> size=32x24` (or `base=<plan>` to build on an existing plan).
2. Add and change objects: `map add`, `map top`, `map move`, ... or edit the
   JSON directly. Every edit command takes `dry` and prints what it changed.
3. `map validate <id>` until there are no errors. Each problem names the
   object, gives a location `[x, y, z]` and a hint.
4. `map render <id> overlay=nav,unreachable,collision` and look at the plans
   (one per floor).
5. `map shot <id> views=<file>` for the game's own view from places.
6. `map playtest <id> perf enemies` (bots walk to every objective and floor).
7. `map build <id>`, then play it: `"$GODOT" --path godot -- --play-at=<id>:x,y,angle,z`.
8. Commit the source **and** `data/<id>.json` and `maps/built.json`.

Every command prints readable lines, then one line `MAP-RESULT {json}` for a
program to parse (`json` prints only that line). Exit codes: **0** done, **1**
the map has errors or a playtest failed, **2** bad arguments, **3** a file
could not be read or written, **4** refused (the level was changed by hand
since its last build; `force` keeps a copy and builds over it).

## Commands

```bash
map help
map new feedstore size=28x22                 # a blank source with a yard
map new hickston_extra base=hickston        # objects over an existing plan
map inspect feedstore                        # objects, floors, nav counts
map validate feedstore                       # exit 1 on errors
map build feedstore [dry] [force]            # validate, then write data/feedstore.json
map render feedstore out=renders overlay=nav,unreachable,collision,spawns,objects [floor=1.7] [scale=16]
map shot feedstore out=shots at=12.5,6.5,1.7 angle=160 pitch=-15
map shot feedstore out=shots views=docs/map_examples/feedstore_views.json
map playtest feedstore [scenario=routes.json] [perf] [enemies] [seconds=20]

map add feedstore '{"id": "crates2", "type": "cover", "a": [3, 9], "b": [5, 9]}' [after=store]
map move feedstore partition by=0,1          # or to=x,y; by=dx,dy,dz lifts too
map resize feedstore office rect=18,2,25,6
map resize feedstore partition opening=stock_door width=1.4 [at=2.5]
map set feedstore dock top=1.0 tile='"tin"'  # values are JSON
map material feedstore plaster brick in=office
map remove feedstore yard_cans
map rename feedstore partition stock_wall    # references follow
map top feedstore spawn='{"at": [3.5, 18.5], "angle": -40}'   # spawn, districts, meta (merged), border, size, playtest
map undo feedstore
map history feedstore

map catalog                                  # docs/map_catalog/
map schema                                   # docs/map_schema.json
map import feedstore shed.glb materials=mats.json scale=0.6 origin=4,4,0 prefix=shed [skip_unsupported] [dry]
```

## The source format

```json
{
  "schema": "clmr-map",
  "version": 1,
  "id": "tiny",
  "size": [16, 12],
  "border": "hedgerow",
  "meta": {"title": "TINY", "sky": "sky", "layout": 1},
  "districts": [{"id": "yard", "name": "THE YARD"}],
  "spawn": {"at": [2.5, 6.5], "angle": 0, "z": 0},
  "objects": [
    {"id": "ground", "type": "yard", "rect": [1, 1, 15, 11], "floor": "dirt", "district": "yard"},
    {"id": "shed", "type": "building", "rect": [8, 3, 14, 9], "wall": "barn", "roof": 3.4},
    {"id": "shed_door", "type": "door", "cell": [8, 6], "vertical": true, "from": "e"},
    {"id": "loft", "type": "balcony", "rect": [11, 4, 13, 8], "top": 1.7, "open": "w"},
    {"id": "loft_stairs", "type": "stairs", "rect": [9, 4, 11, 5.2], "from": 0, "to": 1.7, "toward": "e"},
    {"id": "lever", "type": "station", "at": [12.5, 6.5], "z": 1.7, "label": "PULL IT", "prop": "quest_switch"}
  ]
}
```

- Objects are applied in order (a later one changes the cells an earlier one
  made). Ids are unique, `^[a-z][a-z0-9_]*$`, and never change unless you
  `rename`: edits, validation and the built level's pieces all use them (a
  wall `partition` with openings builds pieces `partition_0`, `partition_1`...;
  stairs `loft_stairs` build treads `loft_stairs_1`...).
- A key a type does not know is kept as it is and reported as a warning;
  start a note's key with `_` (`"_why": "..."`) to keep it quietly.
- `base: {"plan": "<id>"}` runs `tools/levels/<id>_plan.gd` first; then
  `size` and `districts` come from the plan (a district is named by its name in
  lower case with underscores), and `meta` keys you give override the plan's
  (bump `layout` when the map changes).
- `playtest: {"routes": [{"id", "from", "to", "seconds"}], "enemies": true, "perf": true}`
  gives the source its own playtest.

The full schema is `docs/map_schema.json`; the catalog
(`docs/map_catalog/catalog.md`) lists every component with an example, and
every tile, prop, enemy and pickup by id with a thumbnail.

## Components

| type | cells | what it makes |
| --- | --- | --- |
| `yard` | yes | open ground under the sky |
| `room` | yes | open floor under a roof `roof` high |
| `building` | yes | a ring of wall cells (windows every `windows`) round a room |
| `solid`, `fence` | yes | solid cells of a tile, `top` high |
| `paint`, `raise`, `light` | yes | floor tile, ground height, lamp light over cells |
| `door`, `gap`, `pane` | yes | a grid door (1 cell, 1.85 high), an open doorway, breakable glass |
| `room_poly` | yes | a room of any outline (angled walls), each edge a wall with `openings` |
| `corridor` | yes | a roofed passage along cell centres |
| `deck` | no | a floor walked on and under (`thick`, `tile`, `under`, `edge`, `cuts`) |
| `block` | no | a solid floor on the ground (a dock, a plinth); `walk: false` for scenery |
| `ramp` | no | a slope `from` up `to` toward n/e/s/w (at most 45 degrees) |
| `stairs` | no | treads `rise` (.2) high at most from `from` up `to` toward n/e/s/w |
| `wall` | no | a free wall a to b, `z0`..`z1`, `thick`, `openings` [{id, at, width, sill, head}] |
| `rail` | no | a rail on `z`, `height` high: stops bodies, not looks or shots |
| `cover` | no | low solid cover `height` high, `thick` thick |
| `balcony` | no | a deck railed on the `open` sides, `gaps` left in the rails |
| `bridge` | no | a deck railed along its long sides, walked under |
| `ceiling` | no | a surface overhead |
| `fixture` | no | furniture: a box that stops bodies |
| `prop`, `sign` | no | a modelled prop or a flat picture at `at`, on the floor at `z` |
| `enemy`, `pickup` | no | a hand or a pickup at `at`, on the floor at `z` |
| `station`, `exit` | no | an objective (with a quest `prop`), the level's exit |
| `spawn_point` | no | a named place for playtests (and versus spawns) |
| `label` | no | a name on the automap |
| `allow_overlap` | no | marks overlaps as intended (`objects`, `reason`) |

`cuts` are up to two lines `[nx, ny, c]` (inside where `nx*x + ny*y <= c`)
that cut a rectangle into a triangle, a trapezoid or an angled shape.

## Validation codes

Errors stop a build; warnings do not. Every problem has `object`, `at` (map
x, y, z) and usually a `hint`.

| code | severity | means |
| --- | --- | --- |
| `schema`, `version`, `bad_id`, `duplicate_id`, `unknown_type`, `missing`, `rect`, `grid_rect`, `outside`, `point`, `toward`, `rise`, `no_tile`, `no_prop`, `no_enemy`, `no_pickup`, `no_district`, `cuts` | error | the source's own shape |
| `unknown_key` | warning | a key the type does not know (kept) |
| `geometry` | error | a piece the game would refuse (no area, too steep) |
| `overlap` | error | two solids in each other (allow with `allow_overlap`) |
| `inside` | error | a spawn, hand, pickup or objective stands in something solid |
| `outside` | error | placed off the map |
| `blocked_doorway` | error | something solid stands in a grid door |
| `low_opening` | error | a doorway lower than a body (1.17) or narrower than .5 |
| `off_grid_opening` | warning | a doorway the nav graph does not pass through |
| `headroom` | warning | a spawn or hand under a ceiling lower than 1.12 |
| `stairs_foot`, `stairs_top` | error | stairs or a ramp whose foot is not reached or whose top meets no floor at its height |
| `unreachable` | error (warning for hands) | cannot be walked to from the spawn, every door opened |
| `floor_unreachable` | error | a deck nothing leads up to |
| `spawn_seen` | warning | a hand sees the spawn from closer than 8 |
| `builder` | error | the plan builder's own checks (things in walls, pictures missing...) |
| `corridor_leg`, `no_plan` | error | the compiler could not make the object |

## Playtests

`map playtest <id>` builds the source in memory (nothing is written, so an
edit can be tried before a build) and has a bot walk each route with the
player's own body and controls (god mode, doors opened): by default from the
spawn to every station, exit, pickup, spawn point and deck. A route reports
reached or not, seconds, distance walked, nav steps and every place it stuck.
`enemies` wakes the hands and stands the player at each route's end on that
floor to see who gets there; `perf` times the software view from the spawn
and route ends and the tick while walking. A failed route fails the
playtest (exit 1). For the existing game modes use their own tools
(`tools/tactical_check.gd`, `tools/first_minutes.gd`, `tools/multi_bots.gd`).

## Pictures

- `map render`: `<id>_plan.png` (every piece, labelled with its id) and
  `<id>_floor<k>_z<height>.png` for the ground and each deck height, with
  overlays `nav` (nodes, green reached from the spawn, red not; links between
  floors cyan), `collision` (where a body cannot stand on that floor),
  `spawns`, `objects` (hands red, pickups yellow, objectives white),
  `unreachable` (red). The same `out=` and options give the same pictures, so
  before and after an edit can be compared.
- `map shot`: the game's software view with its palette (as the tools draw
  it). The graphics-card view needs a window: build the map, then
  `"$GODOT" --path godot --audio-driver Dummy --resolution 1280x800 -- --view-tour=<tour.json> --view-out=<dir>`
  with tour entries `{"level", "tag", "x", "y", "z", "angle" (radians), "pitch"}`.

## The editor

The Godot editor has a **Maps** screen (`godot/addons/clmr_maps`) beside
Levels: pick a source, a floor and the nav overlay; click an object to pick it
(drag to move it), or pick it in the list and change its JSON (Apply); Add
puts a new object of a type where you last clicked; every change is one undo
step (Ctrl+Z); Save writes the source exactly as the tools do (opening and
saving without a change leaves the file byte for byte; unknown keys stay);
Validate lists problems (click one to go to it); Build writes the level;
Play from here starts the game at the click on the floor picked.

The **Levels** screen still edits `data/<id>.json` cell by cell; for a level
built from a map source it says so, and a hand change there makes the next
`map build` stop (exit 4) instead of losing it.

## glTF import

`map import <id> <file.glb>` turns geometry into the game's own pieces:
upward faces into decks or blocks (a downward face under one within 2 units
gives its thickness), faces sloping up at most 45 degrees into ramps,
downward faces nothing claims into ceilings, upright faces into walls
(grouped by plane and covered in rectangles, so holes come out as openings;
two faces back to back within .6 become one thick wall). Anything else (a
slanted wall, a slope over 45 degrees, a face leaning down) is an error unless
`skip_unsupported` (then a warning). Axes: map x = glTF X, map y = glTF Z,
map z = glTF Y, times `scale`, plus `origin=x,y,z`. Materials: `materials=<json>`
maps material names to tiles; `default_tile=` takes the rest; unmapped names
are an error. Objects come in as `<prefix>_floor1`, `<prefix>_wall3`, ...
marked `"_import": "<prefix>"`; importing the same prefix again replaces
exactly those. Tops too narrow to stand on (wall tops) are left to the walls.

## Existing levels

The campaign, Crossroads, range and versus maps are built from plans
(`godot/tools/levels/<id>_plan.gd`) with
`"$GODOT" --headless --path godot --script res://tools/levels/build_level.gd -- <id>`.
Plans can use the same geometry (`tools/levels/geo_kit.gd`: `Geo.deck`,
`Geo.stairs`, `Geo.ramp`, `Geo.wall` with openings, `Geo.rail`, `Geo.balcony`,
`Geo.bridge`, `Geo.ceiling`, `Geo.room_poly`), and a map source with
`"base": {"plan": "<id>"}` lays objects over a plan, so the tools above work
on any level: `map new hickston base=hickston`, then add, validate, render,
playtest and build. When a level's map changes, bump its `layout` (old saves
then start that chapter over with their kit).

The COUNTY RUN survival maps (`county_hickston`, `county_quarry`,
`county_bayou`) are plans too, each over a chapter's plan
(`tools/levels/county_<chapter>_plan.gd`, `county_kit.gd`); `COUNTY_RUN.md`
says how to make one and validate it with a throwaway source
(`map new zz_x base=county_quarry`, `validate zz_x`).

## Worked example: Mundell Feed & Seed

`docs/map_examples/feedstore_build.sh` makes the demonstration map from
nothing with the commands above (new, top, add, validate, build), and
`docs/map_examples/feedstore_edit_demo.sh` does a targeted-edit round on it,
keeping each step's output in `docs/map_examples/edit_demo/`: a dry run, a
doorway moved along its wall (`resize ... opening=stock_door at=3.1`), a
material swapped in one object, validation, plans before and after,
a playtest, the history, then two undos that leave the source byte for byte
as it was. `docs/map_examples/feedstore_views.json` holds viewpoints for
`map shot`.

The first draft of it had two mistakes the tools caught, worth knowing:
the stairs' foot stood against the store's west wall (only the side of the
staircase could be reached, where the second tread is already too high:
`stairs_foot`), and the office doorway was centred on a cell's edge (the nav
graph passes cell middle to cell middle: `off_grid_opening`). Moving the
stairs one cell east and the doorway half a cell fixed both.

## Limitations

- Walls are upright and floors flat or a planar slope: no slanted walls,
  arches, curved surfaces or pitched roofs to walk on (import refuses them).
- Solid cells are full height; a wall on an upper floor only is a `wall`
  segment.
- The cell roof is one height per cell: give a two-storey building's cells
  its top roof and make the floor between storeys a deck.
- Grid doors (with hinges, keys, secrets) are one cell wide and on the ground
  floor; doorways on upper floors and openings of any width are `wall`
  openings (no door leaf).
- Rain and the open-sky effects treat a cell under any deck as roofed.
- A deck's or slope's cut lines: at most two per piece (the graphics-card
  view draws two).
- Bots path cell middle to cell middle, so a doorway must cross a cell's
  middle line to be used by them (validate warns).
- Pickups, props and signs placed with `z` stand on a deck; things dropped in
  play (a hand's weapon, gibs) land on the floor under where they fall.
- The automap draws decks' edges as walls, all floors at once.
- Enemies climb grid steps of any height (as they always did) but not slabs
  higher than a step.
- Sight lines asked without heights (some AI tests: cover, brawls, the bots'
  "can I see it") keep the old flat test: furniture blocks them whatever its
  height, a deck overhead does not, a stair or a wall does.
- Bots and enemies do not cut a corner a post stands on (the nav graph), and
  the flow field's reach is 44 steps on levels with geometry (26 elsewhere).
