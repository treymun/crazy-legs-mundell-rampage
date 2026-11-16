# Levels

A level is `godot/data/<id>.json`. The campaign chapters, the Crossroads, the
range, the 5v5/2v2 maps and the County Run maps are built from a plan in
`godot/tools/levels/`; change the plan and rebuild, because an edit to its
JSON is lost at the next build. [MAP_AUTHORING.md](../../MAP_AUTHORING.md) at
the repo root is the guide to map sources (`godot/maps/*.map.json`) and
`tools/map.gd` (new, inspect, validate, build, render), checked by
`tools/geometry_check.gd` and `tools/map_check.gd`. Maps players make in the
game (CUSTOM MAPS, the MAP SHED) are their own small format:
[Player maps](#player-maps). Play rules that touch
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

## Player maps

Maps players make in the game itself: the title's **CUSTOM MAPS** list and
its editor, **THE MAP SHED** (`src/user_maps/`,
`src/ui/screens/custom_maps_screen.gd`, `map_editor_screen.gd`). They are a
different, much smaller thing than a plan or a map source: a grid of letters
and a list of things, every one of them from the palette in
`data/tuning/user_maps.json` (edit that, not the scripts; a new cell or
thing goes at the END of its list, since maps name them by letter and name).

### The file

```json
{"schema": "clmr-usermap", "version": 1,
 "name": "PUCKETT'S BACK FORTY", "author": "THE MAP SHED", "note": "...",
 "mood": "dusk", "size": [40, 30],
 "rows": ["HHHH...", "..."],
 "things": [["hand", "billy", 16, 8, 4], ["mark", "start", 2, 27, 0]]}
```

- `rows`: `size[1]` strings of `size[0]` letters, each a palette cell:
  ground (pasture, dirt, gravel, blacktop, road, slab, creek, mud), inside
  floors (plank, shop concrete, diner checker, kitchen tile: roofed at 2.6),
  steps (porch .24, deck .48, dock .72: a step up each), walls (barn, barn
  window, brick, brick window, tin, cinder, plaster, trailer, stock fence,
  hedgerow, rock, junk, tires; each its own height) and `D`, a swing door.
- `things`: `[kind, name, x, y, facing]` on a cell (facing in eighths from
  east): `hand` (enemy kinds whose art is in the base pack, so the browser
  fetches nothing), `loot` (pickups), `prop` (town props and the old flat
  props, each with a blocking radius and an optional lamp glow), `mark`
  (`start`, `lever`, `goal`, `attack`, `defend`, `site_a`, `site_b`,
  `hostage`; most one of a kind).
- `mood`: the sky, score and ambience (`moods` in the palette).
- Limits (`limits`): 32 KB, 12 to 64 cells a side, 256 things, 64 hands, a
  name of 24 letters, 64 maps in the player's folder, 32 kept from lobbies.

`UserMap` (`user_map.gd`) reads one: `parse_bytes`/`parse_text` hold it to
all of that and refuse anything else with one plain line, never an error
(brackets nested past six are refused before the parser sees them, numbers
must be whole and finite, letters must be the pixel font's), and give it in
canonical form. `to_text` writes the one canonical text; `hash_of` is its
SHA-256; `level_id` is `custom_` and twelve hex of it (the versus copy ends
in `v`). `modes(map)` says, per mode, `""` or why not (`solo`: a start, the
lever and the truck, all walked to; `deathmatch`: 60 open cells; `bomb`,
`hostage`: both starts walked between, 120 cells, site A (B optional) or a
hostage; `county`: 260 cells from the start; the numbers are `modes` in the
palette).

### Into a level

`UserMapBuild.level(map, versus)` (`user_map_build.gd`) compiles a map into
a level dictionary: one cell of hedgerow round it (things move one cell in),
the grids, the walls the grids imply (`LevelEdit.implied_walls`) with the
chapters' foundation and eave bands on a building's outside, doors hung in
their wall lines (a door not in one is built as wall) with the wall line
filled over the lintel, lamp glow on the light grid, props as boards (or the
old props) with a fixture base where they block, the lever as a station with
the chapters' switch, the truck as the extraction with the exit prop, and
`tactical` for the 5v5 (five spawns round each start facing the other, a box
round each site, the hostages, the rescue ground round the attackers, a
straight route and a hold at each site). The versus copy leaves out the
hands, the lever and the truck and stands its doors open (the bots path
through doorways). `UserMaps.register` puts it in `LevelData.preview` (one
map at a time), so `make_game(id)` and every mode take it like any level.

### Where they live and how they are played

`UserMaps` (`user_maps.gd`): `user://maps/<name>.json` (the player's),
`res://data/user_maps/` (the two examples), `user://maps/shared/<hash>.json`
(maps lobbies sent). Tools set `UserMaps.folder_override` (under
`OS.get_cache_dir()`). A file that does not pass shows on the list with its
reason and plays nothing.

`UserMapPlay` (`user_map_play.gd`) is the front end's side, its state static
so the front end's layers hold only small hooks (main_state `entries`,
`MENU_STATES`, `slot_source`; main_flow `menu_action`, `play` (never the
campaign), `continue_campaign` (back to the list), `return_to_title` (a test
run goes back to the shed), `save_game`/`load_game`, `open_county`,
`net_match_game`, `net_open_lobby`). PLAY ALONE is the campaign's rules on
the map; 5V5 VS BOTS and HOSTAGE VS BOTS are PLAY VS BOTS's match on its
versus copy; COUNTY RUN is `start_county` on it (`county.json` `custom_map`
is its horde, base-pack hands only); HOST ONLINE is the host form with the
map waiting for the lobby ([multiplayer.md](multiplayer.md#player-maps-in-a-lobby)).
Deathmatch is checked for (CHECK, `modes()`) and is for a lobby that has the
mode.

### Saves of a player map

F6 on a player map writes its own save, never the campaign's quicksave or
slots: `user://maps/saves/<source>_<file>.json`, SessionStore's snapshot (at
its VERSION, brought up by `SaveUpgrade` like any save) plus `custom_save`
(1) and `custom_map` (the map's hash, name, file and source). F9, or the
list's CONTINUE YOUR SAVE, loads it only onto the same map: a newer
`custom_save`, a map gone, or a map changed since (its hash) is refused with
a line saying so, and the file is kept. Campaign saves are untouched, so
there is no new save VERSION. (`save_restore.gd` counts no chapter history
before a level that is not a chapter.)

### The MAP SHED

`MapEditor` (`map_editor.gd`) is the working copy and every edit: tabs
GROUND, INSIDE, STEPS, WALLS, HANDS, LOOT, PROPS, MARKS and TEAR OUT (for a
finger or a pad, which have no right click); a box of cells (a wall box is a
building: walls round, the INSIDE tab's floor in); one-of-a-kind marks move
when placed again; a wall over a thing takes it; undo and redo (80 steps,
one a stroke); NAME, SKY, SIZE (24x18 to 64x48, keeping what fits);
`save()` (an example saves as the player's own copy).

`MapPicture` (`map_picture.gd`) draws the plan from above: each cell its
tile's own picture shrunk to the cell (floors flipped by cell so a field does
not read as stamps), walls lifted and edged, steps lighter with a lip where
they drop, inside floors dimmed, a wall's shadow on the ground south of it,
doors as a slab, things as small marks.

`MapEditorScreen` turns the mouse (click paints, right click tears out,
SHIFT-drag a box, middle drag slides the plan, the wheel zooms), keys (H
lists them), a pad (as keys) and touch into those calls. TEST plays the map
as it stands from your start (SHIFT+T from the cursor); ESC comes back to the
shed. Pictures: `--smoke-screen=mapedit:<n>[:<look>]` opens the list's n-th
map (look 1 its test run, 2..9 a test from the cursor turned (look - 2)
eighths, 100 CHECK, 101 the keys, 102 PROPS, 103 MARKS zoomed);
`--smoke-screen=maps:<row>` the list on a row.

### The examples

`tools/user_map_examples.gd` makes `data/user_maps/pucketts_back_forty.json`
(a farm at dusk: alone, deathmatch, County Run) and `the_sale_barn.json` (a
livestock auction on a fair night: every mode) with the shed's own calls,
the way a player's clicks make them. Change the script and run it again
rather than editing the files (they are kept with LF line ends,
`.gitattributes`, as the check compares them byte for byte).

### Checks

`tools/user_map_check.gd` (USER MAP CHECK OK; check_all quick and CI): the
examples load and round-trip byte for byte; forty-odd broken and hostile
files refused with a plain line (empty, junk, too big, nested ten thousand
deep, newer, silly sizes, odd letters, things off the map or in a wall, too
many) and a 4 MB file refused unread; the shed's calls; alone (lever, then
truck, won), a 5v5 round of ten bots, County Run's horde and deathmatch's
spawn points on the examples; a map save loaded, and refused for a changed,
gone or newer map or one that does not fit; a hosted lobby on a map, a
client getting it (hash checked, registered, kept), the match on the same
level on both, the map changed in the lobby, and hostile MAP packets
refused. `menu_touch_check` taps through CUSTOM MAPS and the shed.
