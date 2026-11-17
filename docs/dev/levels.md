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
| `moonshine_plan.gd` (+ `moonshine_cast.gd`) | chapter 7, the Moonshine Run: Copperhead Ridge by night (below) |
| `mothership_plan.gd` (+ `mothership_cast.gd`) | chapter 8, all indoors, the last |
| `range_plan.gd` | the firing range, not a chapter (layout 5: the games row south of the armory) |
| `hub_plan.gd` | the Crossroads (`data/hub.json`; layout 4: Mundell's trophy shack behind the Road Department; layout 5: the ridge road's gate to the Moonshine Run, south off the county line road's west end, a revenue cruiser pulled off by it) |
| `grainyard_plan.gd`, `holler_plan.gd`, `salvage_plan.gd` | the 5v5 maps ([modes.md](modes.md#the-maps)) |
| `pumpngo_plan.gd`, `pineacres_plan.gd`, `landing_plan.gd` | the 2v2 maps |
| `county_hickston_plan.gd`, `county_quarry_plan.gd`, `county_bayou_plan.gd` (+ `county_kit.gd`) | the County Run maps ([county_run.md](county_run.md#the-maps)) |

The county's hazards (content pass 8,
[gameplay.md](gameplay.md#dirty-fighting-content-pass-8)) stand in the open
where hands fight, each plan's `hazards()` (Hickston's in `hickston_cast.gd`):
Hickston a well, a bug zapper, a cattle guard, a hot wire (and the hog pen,
the creek); the fair two zappers, a burn barrel, a hot wire; the sawmill two
wood chippers and a burn barrel (and its saws); the quarry a hot wire, a burn
barrel, a cattle guard (and its crushers and saw); the bayou two zappers and a
burn barrel (and the deep water); the speedway has its burn barrels and car
crusher, the Mothership its beam emitters and hogs. A hot wire's run is a
`volume()` its model shows. Layouts went up one for the five changed chapters.

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

### The big breaks

A plan's meta `"set_pieces"` lists its barns, water towers and fuel lines
(features/set_pieces.gd; level_builder writes it only when there are any):
`{"kind": "barn"|"tower"|"fuel", "id", "x", "y", "turn" (quarter turns),
"falls" (the square ways it may go over: 0 east, 1 south, 2 west, 3
north)}` and a kind's own (`w`, `d`, `eave`, `wall_tile`, `roof_tile`;
a fuel line's `points` and `pumps`). `tools/levels/set_piece_kit.gd` adds
them (`barn()`, `tower()`, `fuel()`) and each chapter's are its
`hickston()`, `fair()`, `sawmill()`, `speedway()`, called at the end of the
plan's build(). Content pass 8 put in: Hickston's water tower (moved from
the creek's corner to the county road at Main Street), the orchard's hay
shed (the orchard's two south rows of trees made way) and the GAS-N-GUT's
fuel line to a propane tank by the side door (layout 7); the fair's hay
shed in the parking field (layout 6); the sawmill's lumber shed in the
yard (layout 7); the speedway truck stop's water tower and its fuel
island's line to the gas cans by the big tank (layout 5). Each stands off
the only way to anything the chapter needs and falls only away from walls,
hedges and parked things; `tools/set_piece_check.gd` brings them all down
every way they may fall and walks to every station, key and exit again.
The chapter the CHAPTER track builds puts its own through the same kit.

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

### The Moonshine Run (content pass 8)

`moonshine_plan.gd` (+ `moonshine_cast.gd`), 128x96, layout 1, between the
speedway and the Mothership in `Campaign.ORDER`. Copperhead Ridge by night:
the woods (`ridge_pines`) stand everywhere nobody cleared, the bluffs and the
still cave are `ridge_rock` over `cave_floor` (`tools/art/build_moonshine_art.gd`,
with the moonlit sky and the signs). Granny Hooten's farm (the start, the
tobacco barn with the stock car in it, the smokehouse stash), Mule Creek a step
down (a man wades it, the car does not climb out), the low water bridge, Little
Bethel church and its graveyard, the county blacktop (a loop the revenue
cruisers patrol: `lap_cars` with `model` `town_cruiser`, `siren`, `laps` false so
no lap timer, `dry` their line, stopped by the radio station), Buzzard Knob and
the radio mast, the deer camp, Snake Holler (Skeeter's trailer with Granny's
brass barn key, the busted still, the sinkhole), the county line checkpoint,
the log gate, the switchbacks (a step of .12 a cell, the car's), the revenue
camp and the still cave.

- Stations: `trunk` (in the barn; opens its four doors), `radio` (stops the
  cruisers; while it talks an agent may radio the player in,
  `src/moonshine_hands.gd`), `bell` (Little Bethel's rope; opens the log gate),
  then `cave` (Granny's dinner iron by the cave door; needs the three) wakes the
  Revenue Man. The exit is the last jar by the camp.
- The MOONSHINE RUN (`vehicle_runs`): the stock car from the barn doors over the
  bridge, round the church curve, along the blacktop among the cruisers and
  up through the checkpoint in 45 s, the agents at both roadblocks woken as it
  starts. Each roadblock is a cruiser (a `volume` under its model, `parked()`)
  across half the road and two `town_sawhorse` barricades across the rest:
  breakables (`breakables.cfg`) the car rams through (`vehicles.gd _cut`), with a
  gap a man gets by at (so they never part the floor). The checkpoint's shoulder
  is a step up the car cannot take. `vehicle_lines` gives the car its own line in
  the barn (`Level.vehicle_lines`, over vehicles.cfg `spotted`).
- Keys and secrets: the brass key in Skeeter's trailer opens the barn's tack
  room; the smokehouse, the pulpit and the sinkhole hide stashes.
- The other pass-8 systems: set pieces (`set_piece_kit.gd` via the plan's
  `set_pieces()`): Granny's tobacco curing shed south of the barn (falls east
  or west, off the barn's door), the revenue camp's water tank by the cave
  (south or west across the camp) and the camp's fuel line from the drums to
  a propane tank under the lights (`set_piece_check` WANT); hazards for a brawl
  (`hazards()`): Granny's well, a burn barrel at the camp and the farm's, a bug
  zapper on the church's porch; the radio: Dub's line on the Revenue Man's fall
  (`dj.boss_revenue_man`) and the scanner's place (`scanner.place_moonshine`) in
  `radio_lines.json`; the hound: a line at Blue's old doghouse by Granny's porch;
  the county events' revenue raid (`events.cfg [raid] kinds`) sends the
  revenooers, so that kind's pictures and model are in the base pack, not
  the chapter's (`Assets.CHAPTER_KINDS`).
- Saves: save version 10 is the Moonshine Run's step (after the set pieces'
  9): a version 9 campaign save at the Mothership gets the run in its history.
- `tools/moonshine_check.gd` (MOONSHINE CHECK OK, in check_all) holds it.

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
map waiting for the lobby, where DEATHMATCH, TEAM DEATHMATCH and CAMPAIGN
CO-OP (one map, back to the lobby when won) take it too
([multiplayer.md](multiplayer.md#player-maps-in-a-lobby)).

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
client getting it (hash checked, registered, kept), a 5v5 match on the same
level on both, a deathmatch with someone dropping in (the map first), team
deathmatch, CAMPAIGN CO-OP on the map (a retry, no party save, the win back
to the lobby with nothing opened), MODE stepping past what a map can't
host, the always-open servers refusing player maps, the map changed in the
lobby, and hostile MAP packets refused. `menu_touch_check` taps through CUSTOM MAPS and the shed.
