# Map authoring

How to make maps for Crazy Legs Mundell Rampage from a text file and one
command, by hand or as an AI agent (OpenAI Codex, Claude, anything that can
edit JSON and run a shell). This is the single entry point. The full key by
key reference of the format is [docs/map_notes/t7.md](docs/map_notes/t7.md);
the deep notes on each part of the engine are in `docs/map_notes/` (t1
terrain and raked walls, t2 the review, t4 doors, panes and vias, t5 the
building kit, t6 looks and water, t7 the format).

Contents: the quick start, the rules, the format, building blocks (kit,
land, looks, logic, versus, prefabs, low-level pieces), making a multiplayer
map that ships, the commands, the codes, the hard rules, the limits.

Players also make maps inside the game (CUSTOM MAPS, the MAP SHED): a small
grid format of their own, checked hard because strangers share them
([docs/dev/levels.md](docs/dev/levels.md#player-maps)). These tools do not
read those.

## Quick start

```bash
GODOT="C:/Users/treym/OneDrive/Desktop/Tools/Godot_v4.7.2-stable_win64_console.exe"   # or your Godot 4.7.2 console
map() { "$GODOT" --headless --path godot --script res://tools/map.gd -- "$@"; }

map new crossing size=48x40        # writes godot/maps/crossing.map.json (version 2)
# edit godot/maps/crossing.map.json (the format is below)
map check crossing quick           # ~8 s: validate, build in memory, review, walk the routes, plans
map check crossing                 # + 3D pictures (and a bot run on a one-player map), 15-30 s
```

Then read `godot/maps/.check/crossing/report.md` and look at
`godot/maps/.check/crossing/sheet.png`. Every finding says where (x, y, z),
what is wrong and how to fix it. Fix every MUST FIX, then the SHOULD items,
and run it again until the verdict is PASS (nothing but NICE ideas). WORK
means it plays but could play better; FAIL means it is broken.

Copy from the two worked examples, both PASS:

- `godot/maps/feud.map.json` (52 x 40, 57 lines): a crossroads for
  deathmatch, team deathmatch, search and destroy and hostage rescue.
  Review and pictures: `docs/map_examples/feud/`.
- `godot/maps/shiloh.map.json` (64 x 48, 50 lines): a farm for one player
  and co-op (buildings, road, creek, pond, hill, woods, a kill gate, a
  switch, a wake zone, a key). Review and pictures: `docs/map_examples/shiloh/`.

The map tools never touch the player's profile: `map check`, `pictures`
and `shot` start themselves again under a scratch profile
(`TEMP/clmr-map-tools`) when none is set. For any other Godot run, set
`APPDATA` and `LOCALAPPDATA` to a scratch folder first (see the hard rules).

## The rules of the format

- 1 map unit = 1 cell. x runs east, y south, z up. The eye is .95 over a
  floor, a door 1.85 high, a step at most .245 (higher takes a jump of about
  .6), a body .2 round and 1.12 tall (.86 crouched). A real door (2.1 m) is
  1.85 units: the world is stylised.
- **Every rect is `[x0, y0, x1, y1]`, x1 and y1 exclusive** (cells x0..x1-1,
  y0..y1-1). Types that change cells want whole numbers.
- **A building's `at` is the north-west corner of its footprint** (whole
  cells). A thing's `at` (a hand, a pickup, a start) is a place: .5 is a
  cell's middle.
- Angles are degrees, 0 east, 90 south, -90 north. `turn` is quarter turns
  clockwise (0 front south, 1 west, 2 north, 3 east), `face` the same in
  words (s, w, n, e). Heights (`z`, `top`, `z0`...) are absolute.
- Ids are `^[a-z][a-z0-9_]*$` and unique. Parts a piece makes are named
  `<id>_<part>`, so every finding names something you wrote.
- Objects are laid in order; terrain, logic, the versus plan and the looks
  are worked out over the whole map at the end.
- Words on screen are UPPER CASE, short, in the county's voice.
- Version 1 sources (the low-level pieces only) still read, build and save
  exactly as before; anything below that is marked v2 makes a source
  `"version": 2` (the tools write it for you).

## The file

```json
{
  "schema": "clmr-map",
  "version": 2,
  "id": "crossing",
  "size": [48, 40],
  "border": "hedgerow",
  "meta": {"title": "THE CROSSING", "intro": "TWO FAMILIES. ONE ROAD.", "sky": "sky", "layout": 1},
  "mood": "farm_dusk",
  "modes": ["deathmatch", "team_deathmatch", "bomb"],
  "districts": [{"id": "yard", "name": "THE CROSSING"}, {"id": "barn", "name": "THE BARN", "rect": [30, 26, 38, 36], "mood": "barn_dark"}],
  "prefabs": {},
  "spawn": {"at": [4.5, 20.5], "angle": 0},
  "objects": [
    {"id": "ground", "type": "yard", "rect": [1, 1, 47, 39], "floor": "grass", "district": "yard"}
  ]
}
```

| key | what |
| --- | --- |
| `size` | `[w, h]`, 4 to 256 (keep a versus map near 40 x 30 to 64 x 54) |
| `border` | the tile of the solid ring round the map |
| `meta` | `title`, `intro`, `sky`, `score`, `ambience`, `layout` (bump when a built map changes), `kit` (the review's start kit) |
| `mood` (v2) | the map's light and air: `farm_dusk`, `barn_dark`, `church_still`, `holler_fog`, `bayou_night`, `store_fluorescent`, `mothership_glow` |
| `modes` (v2) | what it is made for: `solo`, `coop`, `deathmatch`, `team_deathmatch`, `bomb`, `hostage`, `county`. `map check` reviews each and says what is missing |
| `districts` | named places (the HUD and automap say the name). v2: `rect` paints one over cells, `mood` gives it its own mood |
| `prefabs` (v2) | groups of objects placed by `prefab` objects |
| `seed` (v2) | the looks dice (house variants, where plants fall); the id's hash when left out |
| `spawn` | the one-player start `{at, angle, z}` |
| `base` | `{"plan": "<level id>"}`: lay objects over an existing level's plan |
| `playtest` | the source's own playtest routes |

The JSON Schema is `docs/map_schema.json` (`map schema`); every type with
a copyable example, every tile, prop, enemy and pickup with a thumbnail is
in `docs/map_catalog/catalog.md` (`map catalog`).

## Building blocks

### Whole buildings and bits: the kit (v2)

```json
{"id": "home", "type": "farmhouse", "at": [8, 8]}
{"id": "barn", "type": "barn", "at": [30, 26], "w": 8, "d": 10, "face": "n", "side_door": false}
{"id": "station", "type": "gas_station", "at": [30, 2], "w": 10, "d": 9}
{"id": "rail", "type": "kit", "piece": "fence", "at": [4, 20], "w": 12, "kind": "stock", "gate": 6}
```

A three-line object is a whole, good-looking building: walls, windows with
glass, a hung front door, floors, inside stairs, a roof you can walk on
where it makes sense, furniture to hide behind. Every option has a default.

| piece | default size (range) | what |
| --- | --- | --- |
| `house` | 8 x 6 (5-16 x 5-14) | plain house, `storeys` 1-3, any `roof`, inside stairs |
| `farmhouse` | 9 x 9 (7-14 x 8-14) | two storeys, porch, balcony, chimney, ladder to the roof |
| `shack` | 5 x 4 | one plank room, lean-to roof |
| `trailer` | 9 x 5 | single-wide on blocks, steps, awning |
| `outhouse` | 2 x 2 | a plank box |
| `barn` | 10 x 14 (8-16 x 10-24) | big sliding doors front and back, hayloft up a ladder, bales |
| `pole_barn` | 8 x 10 | tin roof on posts, open sides, bales |
| `silo`, `grain_bin`, `water_tower` | 6 x 4, 5 x 5, 6 x 6 | round; a platform, a climbable cone, a railed tank (`water_tower` can fall) |
| `store` | 8 x 10 | boardwalk, awning, false front, counter and shelves, roof ladder |
| `gas_station` | 12 x 11 (10-16 x 9-14) | cinder box, canopy over pumps, flat roof to walk on |
| `church` | 7 x 14 | pews, coloured glass, a bell tower with a belfry |
| `porch`, `ladder`, `arch`, `curved_wall`, `chimney`, `dock`, `catwalk`, `tower`, `roof` | | bits: a porch against a wall, a ladder, a wall with an arch, a wall round an arc, a dock (waist-high cover), a catwalk, a hunting stand, a roof alone |
| `kit` + `piece` | | any piece, and the only way to write `stairs`, `ramp`, `fence` (rail, wire, picket, stock), `bridge` (plank, covered) and `wall` (doors and windows on every storey) |

- Keys every piece takes: `at` (needed), `w`, `d`, `face` or `turn`,
  `mirror`, `style` (`barn_red`, `whitewash`, `grey`, `plank`, `tin`,
  `brick`, `cinder`, `trailer`, `staves`), `variant` (0 picks by the seed),
  `district`. Each piece's own options (`storeys`, `roof`, `porch`,
  `bales`, `pews`, `hung`, `glass`...) with their ranges: the catalog's "Kit
  pieces' own keys" table and [t5.md](docs/map_notes/t5.md).
- A piece facing west or east takes `d` x `w` cells. Buildings may not
  overlap; bits may touch buildings. Everything stays a cell inside the
  border.
- A building's front door (a barn's two big doors) hangs a door leaf, id
  `<piece id>_<side>_hung<n>` (`barn_s_hung1`); logic may name the piece's
  id alone (`"opens": ["barn"]`) for all its hung doors. Back, side and
  upper doorways are open ways; windows have glass a shot breaks.
- Budget: 1,200 pieces of geometry from the kit a map (a farmhouse is about
  110, a barn 91, a church 170, a shack 22).

### Land (v2)

```json
{"id": "hill", "type": "terrain", "rect": [44, 33, 62, 47], "brush": "hill", "height": 2.5}
{"id": "bank", "type": "terrain", "rect": [10, 2, 20, 8], "brush": "plateau", "height": 1.2}
{"id": "pike", "type": "road", "points": [[19, 1], [19, 39]], "width": 3}
{"id": "creek", "type": "creek", "points": [[1, 30], [16, 31.5], [62, 30]], "width": 1.8}
{"id": "pond", "type": "pond", "at": [9.5, 23.5], "radius": 3}
```

- **terrain** brushes add up: `hill`, `ditch`, `plateau` (`falloff` cells of
  slope), `ramp` (`toward`), `flat` (set; 0 levels a spot), `noise`
  (`seed`, `scale`), `smooth`, `heights` (every corner given). The ground
  is a smooth surface you walk up and down (up to 1 in 1); steeper is a
  cliff that blocks. A hill's crest hides what is behind it. Things are
  lifted onto it. Keep brushes off buildings' footprints. Engine detail:
  [t1.md](docs/map_notes/t1.md).
- **road**: `width` (3), `surface` blacktop (gravel shoulders), gravel,
  dirt, concrete, oil; `ditch`. Plants keep off it; a creek under it gets a
  bridge.
- **creek**, **pond** (`at` + `radius`, `rect` or `polygon`): water in a
  carved bed with a shore; a pond's middle is deep water nobody wades.
  **trough**: a stock trough. Detail: [t6.md](docs/map_notes/t6.md).

### Looks (v2)

```json
"mood": "farm_dusk",
{"id": "woods", "type": "foliage", "kind": "pine", "rect": [1, 33, 26, 47], "density": 0.8, "seed": 2}
{"id": "corn", "type": "foliage", "kind": "corn", "rect": [18, 18, 27, 27], "rows": true}
{"id": "junk", "type": "dress", "rect": [34, 2, 62, 28], "theme": "farm", "count": 2}
{"id": "logs", "type": "vignette", "name": "wood_pile", "at": [10, 15], "wall": "n"}
{"id": "tank", "type": "set_piece", "kind": "tower", "at": [57.5, 13.5], "falls": [1, 3]}
```

- Moods by area: the map's `mood`, a district's `mood`; the view eases from
  one to the next as you cross.
- **foliage** (grass, weeds, scrub, tree, pine, cypress, snag, corn, reeds)
  only on natural ground, in the open, clear of roads, the way through,
  doors, objectives and starts; 360 plants a map at most. Trees' trunks
  block; the rest are walked through.
- **dress** / **vignette**: hand-made groups (a porch sittin' corner, a
  junk pile, a wood pile, a church yard...) set against walls, out of the
  way. Nothing is ever scattered to fill ground.
- **set_piece**: the chapters' big breaks (a barn that comes down, a water
  tower that falls and floods, a fuel line that burns).

### Logic (v2)

```json
{"id": "woods_gate", "type": "kill_gate", "rect": [2, 34, 26, 46], "opens": ["shed"], "message": "SOMEBODY UNLATCHED THE SHED."}
{"id": "barn_switch", "type": "switch", "at": [20.5, 39.5], "label": "THROW THE BARN SWITCH", "opens": ["barn"]}
{"id": "barn_wake", "type": "wake_zone", "rect": [42, 4, 52, 18], "trigger": [33, 19, 52, 25]}
{"id": "john_key", "type": "key", "at": [13.5, 12.5], "z": 0.2, "doors": ["john"]}
{"id": "truck", "type": "exit", "at": [47.5, 11.5], "label": "HIT THE ROAD", "shutdown": "barn_switch"}
```

`switch` (an objective; opens doors, `requires` other switches), `key`
(brass or steel; its doors need it), `kill_gate` (doors open when every hand
in a rect is down), `wake_zone` (hands sleep till a player walks in),
`message` (words when a player walks into a rect), `trigger` (a raw level
trigger: when area/key/station/kills/after/down, do
message/sound/open/close/lock/wake/alert/light/shake/pickup). Logic does not
run in versus modes, and doors there stand open.

### Versus: deathmatch, team deathmatch, the 5v5 rounds (v2)

```json
"modes": ["deathmatch", "team_deathmatch", "bomb", "hostage"],
{"id": "hogs", "type": "team_spawn", "team": "attack", "at": [4.5, 20.5]}
{"id": "gators", "type": "team_spawn", "team": "defend", "at": [47.5, 20.5]}
{"id": "site_a", "type": "bomb_site", "site": "A", "rect": [31, 7, 39, 11]}
{"id": "site_b", "type": "bomb_site", "site": "B", "rect": [31, 29, 37, 37]}
{"id": "held_a", "type": "hostage", "at": [36.5, 9.5]}
{"id": "dm1", "type": "dm_spawn", "at": [3.5, 3.5]}
```

| type | what |
| --- | --- |
| `dm_spawn` | a deathmatch start (6 or more, spread out, out of each other's sight); faces the map's middle unless `angle` |
| `team_spawn` | a 5v5 side's start, `team` attack (the outlaws: they plant the shine bomb or carry hostages out) or defend; `count` 5 places spread round `at` |
| `bomb_site` | search and destroy's site A or B |
| `hostage` | a hostage, near the defenders |
| `rescue_zone` | where hostages are carried (round the attackers' start when left out) |
| `bot_route`, `bot_hold` | where the 5v5 bots walk to a site and where defenders hold (straight to the site's middle, and one hold on each site and one midway, when left out) |

What each mode needs: `bomb` both team starts and a site (two for a 5v5),
`hostage` both team starts and a hostage, `deathmatch` nothing (it uses your
`dm_spawn`s, or picks its own), `solo` and `coop` an objective and an exit.

What `map check` measures on a versus map (numbers in
`godot/data/tuning/map_review.json`):

- every start, site and hostage walked to from the others (`spawn_cut`,
  `hostage_cut`: MUST FIX);
- the two sides' starts out of each other's sight (`team_spawn_seen`: MUST
  FIX within 40 cells, SHOULD beyond) and 30 or more steps apart
  (`teams_close`);
- balance: the defenders reach each site first, but the attackers' walk is
  1.1 to 2.6 times theirs (`site_rush`, `site_far`), and the attackers'
  walks to A and B within 1.8 times (`sites_uneven`). The game's own 5v5
  maps measure 1.6 to 2.4; the report's numbers table has every walk;
- deathmatch starts: 6 or more (`dm_spawns_few`), none two in sight under 8
  cells (`spawn_open`), none watched by most of the rest (`spawn_watched`);
- deathmatch loot: two heals and two rounds lying out at least
  (`arena_loot`).

A versus map gets no campaign bot run. Design tips: break the look between
the starts with a building or a bend; put the sites nearer the defenders but
on both sides' way; give every lane cover (`cover`, hay bales, docks,
`stock` fences, buildings' corners); lay heals and rounds down each lane,
both sides alike.

### Prefabs (v2)

```json
"prefabs": {"hay_fort": {"size": [3, 3], "objects": [
  {"id": "front", "type": "cover", "a": [0, 2.6], "b": [3, 2.6], "height": 1.1, "thick": 0.8, "tile": "kit_hay"}]}},
{"id": "fort_e", "type": "prefab", "name": "hay_fort", "at": [42, 13], "turn": 1, "mirror": true}
```

Defined in the source or in `godot/maps/prefabs/<name>.json` (`hog_pen` is
there). Its objects are written from (0, 0); placed, they turn, mirror and
move with it, and their ids become `<prefab id>_<id>`.

### The low-level pieces (v1, still everything they were)

| type | cells | what it makes |
| --- | --- | --- |
| `yard`, `room`, `building` | yes | open ground; a roofed floor; a ring of wall cells round a room |
| `solid`, `fence`, `paint`, `raise`, `light` | yes | solid cells; a fence; a floor tile; ground height; lamp light |
| `door`, `gap`, `pane` | yes | a grid door (v2: `z` up a storey, `span` 1-3, `style` barn, `bar`); an open doorway; glass |
| `room_poly`, `corridor` | yes | a room of any outline; a roofed passage |
| `deck`, `block`, `ramp`, `stairs` | no | floors walked on and under; solid floors; slopes (to 45 degrees walked, 76 not, `walk: false`); stairs |
| `wall` | no | a free wall a to b with `openings` (doors, windows, v2 `pane`), raked tops (`z1b`), v2 `curve` |
| `rail`, `cover`, `balcony`, `bridge`, `ceiling`, `fixture` | no | rails; low cover; railed decks; overhead surfaces; furniture |
| `prop`, `sign`, `enemy`, `pickup`, `station`, `exit`, `spawn_point`, `label`, `allow_overlap` | no | things, hands, loot, objectives, the exit, playtest places, automap names, intended overlaps |
| `via` (v2) | no | a nav point by hand |

Notes: a deck or slope may have up to 8 cut lines `[nx, ny, c]` (inside
where nx*x + ny*y <= c). A thin-wall doorway should cross a cell's middle
line (the nav graph walks middle to middle; v2 maps add a via in every
doorway, so off-grid doorways work there). Doors (t4): a door's leaf stands
on its cell's middle line; `span` 2 hinged is a pair, `span` 3 sliding a
barn door; an upper door needs the wall it stands in on that floor.

## Making a multiplayer map that ships in the game

1. **Write and check the source.** `godot/maps/<id>.map.json` with `modes`,
   team starts, sites, hostages and `dm_spawn`s. `map check <id>` must say
   PASS (no MUST FIX, no SHOULD). Keep the look original and 1997 (the
   kit, the catalog's tiles and props).
2. **Build it into a level.** `map build <id>` writes `godot/data/<id>.json`
   and records its hash in `godot/maps/built.json`. Commit the source, the
   level and `built.json` together. Never edit `data/<id>.json` by hand: a
   build refuses to write over hand changes (`force` keeps a copy).
3. **Try it.** Pack the assets once
   (`"$GODOT" --headless --path godot --script res://tools/pack_assets.gd`,
   then `--import`, then `pack_assets.gd -- bake`), then:
   - `"$GODOT" --path godot -- --mode=deathmatch --arena=<id>`
   - `"$GODOT" --path godot -- --mode=bomb --arena=<id> --rounds=3` (a built
     level with team starts plays even before it is listed)
   - `"$GODOT" --path godot -- --mode=hostage --arena=<id>`

   Always with a scratch `APPDATA` and `LOCALAPPDATA`, and
   `--audio-driver Dummy` if nobody listens.
4. **List it** (the small code and tuning edits that put it in the menus):
   - 5v5 search and destroy and hostage rescue: add the id to
     `Modes.SHOWDOWN_MAPS` in `godot/src/modes/modes.gd` (PLAY VS BOTS's
     picker), and two short upper-case lines for it to `MAP_LINES` in
     `godot/src/modes/tactical_screens.gd` (what it is; its sites). A two a
     side map with one site goes in `TAGTEAM_MAPS` instead.
   - Deathmatch and team deathmatch: add the id to `Modes.ARENAS` in the
     same file (mode_check and pacing_check play every arena).
   - Online lobbies: in `godot/data/tuning/lobby.cfg`, add the id to the MAP
     row of `match_rows` (the id in the values list and its upper-case
     name at the same place in the labels list) and to `mode_maps` under
     each mode it plays (`bomb`, `hostage`, `deathmatch`,
     `team_deathmatch`).
   - Everything in `godot/data/` is packed and its nav graph baked by
     `pack_assets.gd` and `-- bake`; nothing else to register.
5. **Run the checks** (each with a scratch profile; `check_all` only with
   `jobs=`):
   - `map check <id>` PASS;
   - `godot --headless --path godot --script res://tools/load_check.gd -- levels=<id>`,
     `prebake_check.gd` (after the bake), `geometry_check.gd`,
     `view3d_check.gd`, `looks_map_check.gd`;
   - `mode_check.gd` and `pacing_check.gd` once it is in `Modes.ARENAS`,
     `bot_check.gd` for a 5v5 map;
   - `check_all.gd -- quick jobs=4`, and before handing over
     `check_all.gd -- lint shard=K/4 jobs=4` for K = 1 to 4.
6. **Hand it over** on your own branch with the `map check` report and
   sheet: the owner decides what ships.

## Commands

Every command prints readable lines, then `MAP-RESULT {json}` (`json`
prints only that). Exit codes: 0 done, 1 the map has errors (or check says
FAIL), 2 bad arguments, 3 a file could not be read or written, 4 refused
(the level was changed by hand since its last build).

```bash
map help
map new <id> [size=WxH] [base=<plan>]       # a new source (version 2)
map check <id> [quick] [out=<dir>] [pictures=0]   # THE ONE COMMAND
map validate <id>                           # problems only (exit 1 on errors)
map build <id> [dry] [force]                # write data/<id>.json
map render <id> out=<dir> overlay=nav,unreachable,spawns,objects   # plans: one a storey, terrain contours,
                                            # plants, versus starts and sites
map pictures <id>                           # the auto tour's 3D pictures alone
map shot <id> at=x,y,z angle=<deg> pitch=<deg> [views=<json>]     # the 3D view from places
map flow <id> [seed=1] [skill=0,1,2]        # the campaign bot alone (one-player maps)
map playtest <id> [perf] [enemies]          # a body walks every route
map inspect <id>                            # objects, floors, nav counts

map add <id> '<object json>' [after=<object>]
map move <id> <object> by=dx,dy[,dz] | to=x,y
map turn <id> <object> [by=1]               # a kit piece, prefab or set piece
map mirror <id> <object>                    # a kit piece or prefab
map resize <id> <object> rect=x0,y0,x1,y1 | opening=<id> width=<w>
map set <id> <object> key=<json> [key=...]
map material <id> <from tile> <to tile> [in=<object>,...]
map remove <id> <object>
map rename <id> <object> <new id>           # references follow
map top <id> key=<json>                     # spawn, districts, meta, modes, mood...
map undo <id>                               # every edit is kept in maps/.history/<id>/
map history <id>

map catalog                                 # docs/map_catalog/
map schema                                  # docs/map_schema.json
map import <id> <file.glb> [scale=0.6] [materials=<json>] [prefix=<id>]   # glTF geometry
```

Every edit takes `dry` (show the change, write nothing).

## The report's codes

Validation (errors stop a build): the source's shape (`schema`, `version`,
`bad_id`, `duplicate_id`, `unknown_type`, `missing`, `rect`, `grid_rect`,
`outside`, `point`, `no_tile`, `no_prop`, `no_enemy`, `no_pickup`,
`no_district`), the geometry (`geometry`, `overlap`, `inside`,
`blocked_doorway`, `low_opening`, `off_grid_opening` warning, `headroom`
warning, `stairs_foot`, `stairs_top`, `unreachable`, `floor_unreachable`,
`spawn_seen` warning), and version 2's (`kit`, `kit_option`, `kit_size`,
`kit_outside`, `kit_overlap`, `kit_on_terrain`, `cost`, `terrain_brush`,
`road_blocked`, `logic_target`, `logic_loop`, `prefab_missing`,
`prefab_loop`, `mode_missing`, `versus_inside`, `mood_unknown`,
`foliage_kind`, `dress_theme`, `vignette`, and the looks layer's warnings).
Each has a hint; the full table is in [t7.md](docs/map_notes/t7.md).

The review (MUST FIX / SHOULD / NICE): `unreached`, `out_of_order`,
`route_failed`, `ammo_short`, `no_cover`, `spawn_seen`, `alley`, `dead_end`,
`no_secrets`, `quiet_stretch`, `first_fight_late`, `flat`, `no_districts`,
`empty_ground`, `dark_room`, `cost_should`, `cost_most`, `arena_loot`,
`no_way`, the bot's (`bot_stuck`, `bot_deaths`, `bot_calm`, `bot_lost`,
`bot_fight_share`), and the versus checks above. Table and samples:
[t2.md](docs/map_notes/t2.md).

## Hard rules

- **Original work only.** The game is a 1997 redneck shooter in the spirit
  of Redneck Rampage, but never its art, sounds, maps or layouts. No real
  people, brands or businesses in names, signs or maps. Use the kit, the
  catalog's tiles and props, and the game's own words style.
- **Keep the 1997 look.** No new shaders or high-detail models in a map; a
  map is built from the kit, tiles, props and foliage that exist.
- **Stay within the budgets** the review enforces: 1,200 kit pieces a map;
  1,200 geometry pieces (2,400 at most) and 20,000 wall rows (40,000 at
  most) a level; the first nav build under 300 ms (1,500 at most); 360
  plants a map. A heavy map must still run at 60 fps beside County Run's
  busiest scene.
- **Never touch the player's profile.** Every Godot run you start (headless
  or a window) runs with `APPDATA` and `LOCALAPPDATA` pointed at a scratch
  folder, for example
  `export APPDATA=$TMP/clmr-scratch LOCALAPPDATA=$TMP/clmr-scratch/Local`.
  The map tools do this themselves for check, pictures and shot.
- Online play must stay deterministic: no clock and no unseeded dice in a
  map (the format has none; keep `seed`s fixed).
- Chapters (the campaign's levels, built from `godot/tools/levels/*_plan.gd`)
  are not edited by map work.

## Limits (said plainly)

- A solid grid cell is full height; a building to stand on is geometry (the
  kit does this). The cell roof is one height.
- Kit buildings stand on flat ground; keep terrain off their footprints.
- Versus starts stand on the ground floor.
- Hands climb steps and ladders, not slabs higher than a step, nor cliffs.
- A look asked without heights (some AI tests) is the flat test.
- A door is 1.85 high, up to 3 cells wide, on a cell's middle line.
- Glass stops a look until it is broken.
- Foliage grows on the ground floor; vignettes on flat ground.
- `map check` runs no bots in versus modes: play them after a build.
- The Godot editor's Maps screen (`godot/addons/clmr_maps`) edits sources
  too (every type in Add, Validate, Build, Play from here); the Levels
  screen edits built levels cell by cell (a source's level should be
  changed through its source).
