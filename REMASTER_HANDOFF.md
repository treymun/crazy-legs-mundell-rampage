# Geometry upgrade, map authoring and remaster: handoff

Branch **`geometry-remaster`** (from `17f1edc`, 2.0.0-dev.39), pushed to
`origin`. Not merged, not tagged, not released: the session on
`combat-overhaul` merges both branches, re-runs the checks and publishes one
release (the owner: "only publish once both are finished and together").

Read with: `MAP_AUTHORING.md` (the workflow and every command),
`docs/remaster_progress.md` (the running notes), `docs/map_schema.json`,
`docs/map_catalog/catalog.md`.

## In short

**Done and verified**
- **Engine**: level format 2 with walkable decks (rooms over rooms, passages
  under), sloped ramps, stairs, thin and angled walls with openings cut to
  size, rails, low cover, ceilings. Movement, collision, headroom, shots,
  sight, grenades and debris, both renderers, the nav graph (bots tell floors
  apart), snapshots and saves (version 8) all agree. Every old level is
  unchanged in play.
- **Authoring for agents**: JSON map sources with stable ids and a schema;
  `tools/map.gd` (create, inspect, validate, build, render, screenshot,
  playtest, targeted edits with dry runs, kept copies and undo, catalog,
  schema, glTF import); a Maps screen in the Godot editor;
  `MAP_AUTHORING.md`.
- **Demo map** Mundell Feed & Seed, made and revised only through the
  commands, validated, rendered, playtested (bots and hands up and down the
  floors), round-tripped through the editor.
- **Remaster**: Hickston (hay loft), the fair (bleachers), the sawmill (pond
  bridge), the quarry (haul ramps), the bayou (stilt house and gangway), the
  Mothership (gantry ramp), the range (deer stand); every other map reviewed
  and kept, with reasons. Each changed chapter plays through to the end with
  the bot; the versus maps play out identically to dev.39.
- **Firing range brought up to date** (asked for by the owner during this
  work; section 11): all 30 guns racked (the 14 newer guns and throwables on a
  store wall with pictures rendered in Blender from their own models), all
  eight bosses in the corral (a pond for the Swamp King, Maw's own fight),
  every newer hand in the bullpen, and the bowling lane rebuilt with real pin
  physics and ten-frame scoring.
- **Checks**: `check_all` green; CI green; new `geometry_check.gd` and
  `map_check.gd` in check_fixes.

**Not verified**: playing by hand, sound, a phone, the browser and Android
builds (CI builds those only on main/tags), clicking the Maps screen in a
running editor. See section 10.

**Merge notes**: section 7 (save version 8, small edits to `main.gd`,
`main_state.gd`, `modes.gd`, `check_fixes.gd`, `project.godot`).

## 1. Architecture: extend the 2.5D engine, not a Godot 3D path

**Audit.** The look is the custom renderer: the software view
(`render_*.gd`, `renderer.gd`) and the graphics-card view
(`palette.gdshader` composed by `scene_layers.gd`). Collision, sight, hitscan,
grenades and debris, flow fields (enemies, the objective pin, the 5v5 bots),
saves, snapshots and the netcode's tick-for-tick determinism all go through
`LevelData`. The engine already had per-pixel depth (planes and walls are
depth-tested), wall pieces with their own bottom and top, floor "caps" at any
height, and 3D collision boxes (fixtures with a bottom and top). What it
lacked: anything walked on above another floor, slopes, collision for free
walls, ceilings that are not the cell's roof, and nav that knows heights.

**Choice.** A Godot 3D path would have replaced the renderer (and so the
look), the software fallback the headless checks and CI depend on, the
browser/Android limits work (nine textures), and all of the play code; and
Godot physics is not deterministic across machines (the netcode needs that).
The extension keeps every existing level byte-for-byte playable and gives
real multi-floor play, collision, sight, shots, nav and rendering that agree:

- **Level format 2** (`src/level_geometry.gd`, `LevelGeometry`): a level's
  `geometry` block: **slabs** (a footprint rectangle cut by up to two lines,
  a flat or sloped top; with a thickness they are decks walked on and under,
  without they are solid to the ground: blocks, ramps, stair treads),
  **segments** (free walls a to b with their own z range and thickness; `sight`
  and `shots` flags so a rail stops bodies but not bullets), **ceilings**.
  Queries: `floor_at`, `support` (a body stands on a ledge until its footprint
  is clear), `ceiling_at`, `blocks`, `solid_point`, `crosses` (a step through a
  thin deck), bodies' `can_walk`/`settle`, render parts, the nav graph.
- **LevelData** (`src/level.gd`): `geo`, `format`, `stand(body)`,
  `floor_under(x, y, z)`, `roof_over(x, y, z)`, `crosses()`, `apart(a, b)`,
  `goal_floor()`; `blocked()`, `visible()` and movement ask the geometry in the
  cells it touches. `LevelData.preview` lets tools load an unwritten level.
- **Bodies**: `Player.floor_z`, `Enemy.floor_z`. Every actor height lookup
  goes through `world.stand(body)` (which is `elevation()` on a level without
  geometry, so old levels are exact). A player who walks off an edge falls; a
  hand that sees the player on another floor walks the nav graph round to the
  stairs (`enemies.gd`).
- **Rendering**: caps may carry cut lines; `roof_caps` are surfaces seen from
  below; `slopes` are drawn per pixel in both views (`render_surfaces.gd
  _slope_layer`, `palette.gdshader plane_at`). The plane table grew rows
  (light map now from row 12); **no new texture** (still 8 of 9).
- **Shots and sight**: hitscan, projectiles (bounce off a deck's top or
  underside, not as a wall), sight lines (cannot step over a thin deck),
  tumbling debris and dynamite land on decks.
- **Nav** (`src/flow_field.gd`): on a format 2 level a FlowField walks
  `LevelGeometry.NavGraph`: node n < width*height is the cell's own floor (or
  the top of a solid slab on it), the rest are decks over it; edges are
  sub-step walked with the enemies' climbing rule. `heading/distance/waypoint/
  update` take an optional z; the reach is 44 there (26 elsewhere). The
  objective pin and the 5v5 bots' fields use it too.
- **Multiplayer**: `floor_z` travels in snapshots (players and enemies are
  carried by reflection); level geometry is static. `net_check`,
  `net_showdown_check`, `multi_bots` pass.
- **Saves**: version 8 (`floor_z` for the player and every enemy; a pickup on
  a deck keeps its floor); `save_upgrade.gd` step 7 -> 8; fixtures added.

Compatibility: a format 1 level (every level before this branch) loads and
plays exactly as before: all the checks that compare against references
(pictures, compare_views, determinism, saves) pass on the levels this branch
did not change.

## 2. Map authoring for agents

- **Source format**: `godot/maps/<id>.map.json` (`clmr-map` 1): stable object
  ids, 33 component types, explicit units and axes, kept keys a type does not
  know. A source can stand alone or build on a plan (`base`). Schema:
  `docs/map_schema.json` (generated).
- **Commands** (`tools/map.gd`): new, inspect, validate, build, render, shot,
  playtest, move/resize/set/material/add/remove/rename/top, undo, history,
  catalog, schema, import. Each prints readable lines and one `MAP-RESULT
  {json}`; exit codes 0/1/2/3/4. Every edit has `dry` and keeps a copy; a
  build refuses to write over a level changed by hand (`force` keeps a copy).
  Every plan-only level reads as a source over its plan, so validate, render,
  shot and playtest work on all of them.
- **Components** in `tools/levels/geo_kit.gd` (plans) and
  `tools/map/map_compile.gd` (sources): deck, block, ramp, stairs, wall with
  openings cut to size, rail, cover, balcony, bridge, ceiling, room_poly
  (angled rooms), corridor, and the grid ones.
- **Catalog**: `docs/map_catalog/` (components, 196 tiles, 256 props, 47
  enemies, 37 pickups, thumbnails).
- **Validation** (`tools/map/map_validate.gd`): the level built and loaded
  as the game would: overlaps (with `allow_overlap`), things inside solids,
  blocked doorways, low/narrow openings, openings off the nav grid, headroom,
  stairs that lead nowhere, unreachable things and floors, spawns seen.
- **Pictures** (`tools/map/map_render.gd`): labelled plans per floor with
  nav, collision, spawns, objects, unreachable overlays; `shot` for the
  game's own view (and `level=` for an older build).
- **Playtests** (`tools/map/map_playtest.gd`): bots walk routes with the
  player's body; enemies set on the player on each floor; frame and tick
  times.
- **Editor**: the Godot editor's **Maps** screen (`godot/addons/clmr_maps`).
- **glTF/GLB import** (`tools/map/map_import.gd`).
- **Checks**: `tools/geometry_check.gd`, `tools/map_check.gd` (both in
  `check_fixes.gd`).

## 3. The demonstration map: Mundell Feed & Seed

`godot/maps/feedstore.map.json`, made only with `tools/map.gd` commands
(`docs/map_examples/feedstore_build.sh`): a barn-walled feed store two
storeys tall (a loft on posts over the stock room: a walkable passage under
the upper floor), stairs up to the loft with a landing at their foot, a thin
plaster partition with a doorway and a window cut to size, an angled office
(room_poly), a loading dock with a sloped ramp, crates for cover, a lever up
on the loft (the objective), the road exit, four hands (one on the loft, one
under it, one on the dock, one in the yard), spawn points on each floor.
Built as `godot/data/feedstore.json`; play it with
`"$GODOT" --path godot -- --play-at=feedstore:3.5,18.5,-0.7`.

What was checked on it (and stays checked in `map_check.gd`): it validates
with no errors or warnings; a bot walks from the spawn to every objective,
pickup, spawn point and floor (up the stairs and the ramp); hands woken under
the loft, on the dock and in the yard all come up the stairs to a player on
the loft; both views draw it (software and graphics card, side by side in a
window tour); the editor's round trip; broken copies are caught.
Found and fixed while making it: the stairs' foot first stood against a wall
(validate's `stairs_foot` caught it), the office door was centred on a cell
edge (the nav graph did not pass it: now an `off_grid_opening` warning).

## 4. Map by map

Every playable environment was reviewed (its plan, a top-down picture, the
game's view). A change went in only where height or the new walls clearly
help; where a map already works, it is left alone and the reason given.
Before/after pictures of every changed spot (the game's software view, from
the same places): `docs/remaster/<map>/before_*.png` and `after_*.png`
(viewpoints in `docs/remaster/views/<map>.json`; remake them with
`map.gd -- shot <map> views=docs/remaster/views/<map>.json [level=<old json>]`).
Each changed level's `layout` was bumped (old saves of it start that chapter
over with their guns, rounds, health and pockets).

| map | layout | change | why | checked |
| --- | --- | --- | --- | --- |
| Hickston | 3 -> 4 | The feed barn's "platform two steps up" is now a real **hay loft** (`tools/levels/hickston_loft.gd`): a plank floor 1.55 up on posts over the back of the barn, stairs up its south side, railed along its open edges; the loft's alien, shells and rinds are up on it; feed stored under it in the shade (a passage under the upper floor). | A barn with a loft is the Redneck Rampage barn; the old half-step platform read as a stage. Gives the barn fight a height to hold and to clear. | validate clean; bot routes up the stairs, under the loft and along it; an enemy comes up to the player on it; pictures and GPU references rewritten (`hickston_05_0` looks at it) |
| Fair | 3 -> 4 | The derby ring's bleachers (three flat boxes .8 high) are **stepped rows** a step apart, climbed for a look over the wrecks. | Bleachers you can't climb were furniture; rows give the derby fight high ground without a new route. | validate clean; bot climbs both stands |
| Sawmill | 4 -> 5 | A **plank footbridge on log trestles** over the log pond, from the west yard to the main boardwalk, stairs at each end, plank rails; wade under it. | The pond was crossed only on the flat boardwalks; a bridge is what a mill pond has, and gives a high crossing to shoot down from. | validate clean; bot over it, onto it, wading under it; pictures rewritten (`sawmill_*` see it across the pond) |
| Quarry | 4 -> 5 | The half-step "ramp cells" between the chalk benches are **true sloped haul ramps**, three cells wide. | A quarry's benches are joined by haul roads; the cells read as odd steps. Same places, same routes. | validate clean; bot from the bottom bench to the top and back |
| Gator Bayou | 2 -> 3 | The preacher's shack stands **higher on its stilts** (1.2), reached by a **sloped plank gangway** over the water (wade under its high end), where three one-cell steps were. | The stilt row's whole idea is height over the water; the steps were a staircase. | validate clean; bot up the gangway and under it; picture rewritten (`bayou_stilt_row_0`) |
| Mothership | 2 -> 3 | The tractor bay gantry's six one-cell steps are a **sloped grating ramp**. | The rest of the ship is smooth hull and grating; the gantry stays as it was. | validate clean; bot up the ramp and along the gantry to the booth |
| Firing range | 1 -> 2 -> 3 | Layout 3 is the range update (section 11). Layout 2: a **deer stand** by the bullpen gate: a deck 1.8 up on posts, railed, stairs from the south. Shoot down at the locals; they come up after you or round under. Also: the plan racked all 30 guns, but only the first 16 have pictures (the shipped range had 16): it now racks the guns whose pictures exist, so the plan reproduces the shipped range (plus the stand) and the rest come with their art. | Somewhere to practise fighting across floors. The rack fix makes the range plan reproducible again (it was not at dev.39). | validate clean; bot up the stand, down to the pen, under it; quest reach (every rack) passes |
| Speedway | 2 (unchanged) | none | Already has the height the place needs: a banked oval, stands rising a step a row, the announcer's booth on top, the derby bowl. A crossover bridge would put players over the race cars' lane, whose hits are worked out flat. | covered by the checks (bot campaign, pictures) |
| The Crossroads (hub) | 3 (unchanged) | none | A hub of gates along one road, flat on purpose so every gate, sign and fingerpost reads from the four-way stop; height would hide them. | covered by the checks |
| Grainyard, Holler, Salvage (5v5) | 1 (unchanged) | none | Their routes, holds and timing are tuned (`map_timing.gd` strict) and the bots' routes and holds are flat x, y: a perch the bots do not know would play one-sided against them, and any height changes the timing tables. They run on the new engine as format 1 maps, unchanged. | tactical_check and map_timing (see results), net_showdown_check |
| Pump-n-Go, Pine Acres, Landing (2v2) | 1 (unchanged) | none | Small, tight two-a-side maps built round one site; height there would create spots one side cannot answer. | tactical_check (see results) |
| Mundell Feed & Seed (new) | 1 | the demonstration map (section 3) | | section 3 |

## 5. Launch, edit, rebuild, test

```bash
GODOT="C:/Users/treym/OneDrive/Desktop/Tools/Godot_v4.7.2-stable_win64_console.exe"
"$GODOT" --headless --path godot --import                   # once after checkout (new class_name scripts)
"$GODOT" --headless --path godot --script res://tools/pack_assets.gd
map() { "$GODOT" --headless --path godot --script res://tools/map.gd -- "$@"; }
```

- Play a map: `"$GODOT" --path godot -- --play-at=<id>:x,y,angle,z` (z: the
  floor to start on), or the campaign as usual.
- Edit a map source: `map add/move/resize/set/material/remove/rename/top`, or
  the Godot editor's **Maps** screen; a plan-built level: its plan
  (`godot/tools/levels/<id>_plan.gd`, with `geo_kit.gd`), or a map source
  over it (`map new <id> base=<id>`).
- Rebuild: `map build <id>` (a map source) or
  `"$GODOT" --headless --path godot --script res://tools/levels/build_level.gd -- <id>`
  (a plan, or a map source when there is one).
- Check a map: `map validate <id>`, `map render <id> overlay=nav,unreachable,collision`,
  `map shot <id> views=...`, `map playtest <id> perf enemies`.
- Whole project: `"$GODOT" --headless --path godot --script res://tools/check_all.gd -- lint`
  (this clone has no .venv: lint was run with the other clone's
  `.venv\Scripts\gdformat` / `gdlint` over `src tools addons`).
- After changing a map that a reference view sees: `picture_check.gd -- update`,
  and the graphics-card references from a window tour
  (`--view-tour=res://tools/picture_views.json --view-out=<dir>`, then copy the
  changed `<tag>_fx.png` to `tools/pictures_gpu/<tag>.png`, or
  `compare_views.gd -- <dir> update`).

## 6. Save compatibility

- Save **version 8** (was 7): adds `floor_z` for the player and each enemy;
  a pickup lying on a deck keeps its floor as a fourth number. `save_upgrade.gd`
  turns a version 7 save into 8 (every floor the ground: no level had
  geometry before), so every older save still loads (4 to 7 fixtures pass).
- Changed maps bumped their layout: hickston 4, fair 4, sawmill 5, quarry 5,
  bayou 3, mothership 3, range 3 (the range is never saved). A save of an older layout loads at that
  chapter's start with its kit (the existing mechanism); a finished chapter of
  an older layout stays finished.
- Fixtures: the v8 saves made before the remaster are kept as
  `tools/saves/v8_*_layoutN.json` (expected at the chapter start, like the v7
  ones of the old layouts); fresh v8 fixtures of the new layouts were made.
  `save_fixtures.gd`: OLD SAVES OK.
- Settings: none added. Snapshots: `floor_z` travels by reflection; no
  snapshot version change was needed (`net_check` passes).

## 7. Merging with `combat-overhaul`

Shared files this branch touched, all small:

| file | change |
| --- | --- |
| `godot/src/main.gd` | `--view-tour` and `--play-at` take a floor (z): two short additions |
| `godot/src/main_state.gd` | two `elevation(p.x, p.y)` -> `stand(p)` lines |
| `godot/src/modes/modes.gd` | two `elevation(q.x, q.y)` -> `stand(q)` lines |
| `godot/tools/check_fixes.gd` | two lines at the end: `geometry_check.gd` and `map_check.gd` |
| `godot/project.godot` | the Maps editor plugin added to `[editor_plugins] enabled` |
| `godot/src/session_store.gd`, `save_upgrade.gd` | save version 8 (field lists, the 7 -> 8 step) |
| `godot/tools/saves/*` | fixtures and expected.json |

Not touched: `src/net/*`, `main_input.gd`, `setup_pages.gd`,
`tactical_shop.gd`, `tools/check_all.gd`, `.github/workflows/release.yml`,
`export_presets.cfg`, audio.

Watch for:
- **Save version**: this branch is 8. If `combat-overhaul` also bumped
  `SessionStore.VERSION`, renumber one side's step (keep both steps in order),
  and re-run `save_fixtures.gd -- make` after the merge.
- **Many one-line `world.stand(...)` edits** across `src/` (every actor
  height lookup; about 130 lines across src/): a conflict there is
  resolved by keeping `stand(<body>)`; it equals `elevation()` on every level
  without geometry.
- `enemies.gd`, `game_world.gd`, `level.gd` are near the 1500-line limit
  (1500, 1497, 1462 lines here): new lines from the other side may need a split.
- The other branch's new Linux server and lobby code runs the same game
  code, so format 2 levels need nothing more there; a server and its players
  must run the same build (the lobby already refuses another version).
- After merging: `--import`, `pack_assets`, `check_all -- lint`, a window
  tour + `compare_views refs`, `tactical_check`, `net_server_check` (theirs).
- **Two clones running checks at once** share OS cache files (boss
  checkpoint and rematch files): a boss-rematch check can fail spuriously;
  it passes run alone.

## 8. Problems found and fixed on the way

Found by the tools while building and remastering, each fixed in the engine
or the tools (not worked round in a map):

- A roof value of 0 means the open sky, also over a sunken floor: the first
  geometry code read it as a ceiling at 0 and made the sawmill's pond (-.24)
  a crawlspace (found by the pond bridge's wade-under playtest).
- A body half off a ledge stood on the floor below and was then stuck in the
  ledge's side (enemies stepping off the demo's dock): bodies now stand on a
  ledge until their footprint is clear (`LevelGeometry.support`).
- A steep sight line could step over a deck thinner than one step: a hand
  under the loft "saw" the player on it and stood under them (`crosses` in
  `visible()`).
- A hand that sees the player on another floor walked straight at them;
  now it follows the nav graph round to the stairs (`LevelData.apart`).
- The flow field's reach (26 steps) was too short for routes up stairs; 44
  on levels with geometry.
- A diagonal nav step was allowed past a corner of deep water (the bayou bot
  stuck at the hoist bridge; first_minutes found it): both side cells must be
  reached, as the old grid rule had it.
- A diagonal nav step could cut a corner that a post stands on (the range's
  porch posts along the firing line): two deathmatch bots wedged there and
  never met (mode_check found it). The nav graph leaves out a diagonal past
  an occupied corner.
- A body moved without walking kept its old floor (`can_walk` now works the
  floor out again first).
- Sight lines given no heights (bots, cover finding, brawls) keep the old
  flat test (furniture in the way whatever its height); a first version gave
  them eye heights, which changed what bots saw and stalled the bayou bot
  at the end.
- The builder's grid reach check could not see decks or slopes: on levels
  with geometry the validator's nav check decides, and it now checks every
  hand, pickup, station and exit of the built level (not only a source's
  objects).
- `world.stand()` was first reached by a bulk edit on some variables that are
  points, not bodies; it now falls back to `elevation()` for anything that is
  not a player or an enemy.
- The range plan could not reproduce the shipped range (it racked 30 guns,
  14 without pictures); it now racks the guns with pictures.

## 9. Results

### Checks (this machine, final commit)

- `tools/check_all.gd` (shader, assets, check_fixes with geometry_check and
  map_check, save fixtures, level edit, quest reach, campaign walkthrough,
  pictures, online 5v5): **ALL CHECKS OK** (check_fixes 307 s, every check ok).
- Lint: `gdformat --check` and `gdlint` over `src tools addons`: clean.
- CI on GitHub (lint + headless checks + the shader view against its
  references in a Mesa window): green on every push after the fixtures and
  references were rewritten (see the Actions page for `geometry-remaster`).
- `tools/geometry_check.gd`: GEOMETRY CHECK OK (queries, walking, falling,
  rails, ramps, thin walls, doorway and window, crawlspace, shots past a
  deck's edge and stopped by it, nav floors apart and joined by stairs,
  both views drawn, a save on a deck).
- `tools/map_check.gd`: all pass (source diagnostics, the demo validates,
  broken copies caught, targeted edits touch only their object, undo exact,
  build guard, glTF import and refusal, the Maps screen round trip, a bot to
  the loft's lever, hands climbing to a player on the loft).

### Play, compared with dev.39 (the base, back to back on this machine)

| | dev.39 | this branch |
| --- | --- | --- |
| first_minutes whole (a god-mode bot plays the chapter to the end): hickston | 184 s | 178 s |
| fair | 207 s | 190 s |
| sawmill | 148 s | 153 s |
| quarry | 136 s | 139 s |
| bayou | 220 s | 159 s |
| mothership | 185 s | 184 s |
| `map_timing.gd` (6 versus maps: run times, holds, hostages) | | identical output |
| `tactical_check.gd -- rounds=2` (10 bots, every 5v5/2v2 map and mode) | | identical rounds, results and winners |
| `mode_check.gd` range deathmatch (90 s) | 1/1 deaths | 1/1 deaths |

### Performance

Old (dev.39, a worktree at 17f1edc) and new run back to back on this PC
(which runs other work too, so only the differences between neighbouring runs
mean anything).

`tools/bench.gd -- 150` (headless; tick and the CPU side of the draw), two
rounds each:

| run | tick mean / worst 1% | draw mean / worst 1% | fps mean |
| --- | --- | --- | --- |
| old 1 | 0.53 / 1.34 ms | 1.92 / 6.96 ms | 410 |
| new 1 | 0.61 / 1.50 ms | 1.99 / 7.20 ms | 384 |
| old 2 | 0.55 / 1.55 ms | 2.00 / 7.45 ms | 392 |
| new 2 | 0.62 / 1.50 ms | 1.97 / 6.92 ms | 387 |

Those bench rounds were before the last changes to the fast paths. With the
final code, the idle tick alone (900 ticks at 60 Hz, three alternating
rounds, ms):

| level | old | new |
| --- | --- | --- |
| hickston (hay loft) | 0.52 to 0.53 | 0.64 to 0.65 |
| bayou (stilt house) | 0.56 to 0.70 | 0.62 |
| mothership (gantry ramp) | 0.43 to 0.44 | 0.51 to 0.52 |
| speedway (format 1, unchanged) | 0.41 to 0.42 | 0.41 to 0.42 |

So a level with geometry ticks about 10 to 23% slower (0.06 to 0.12 ms a
tick, against a 16 ms frame), a format-1 level the same. What made it
cheaper than the first version (+25 to 40%): `stand()`/`floor_under()` read
the grid directly on a format-1 level; `LevelGeometry.cells` marks the cells
any slab or segment reaches (out to PAD), and the support, floor, ceiling,
sight-line crossing and walk queries skip the geometry in cells it does not
reach; enemies test "on another floor" only when the level has geometry. All
exact: the three geometry chapters' whole playthroughs come out the same to
the tick and the kill. A shortcut that walked with the grid's own test away
from the geometry was tried and dropped: it differs from the 3D test by
fixture heights (over the bayou's water) and changed play. The rest is the
nav graph (a whole flow walk 2.0 ms against 1.75 in Hickston) and calls.

Window `--view-bench=300` (1280x800, every chapter): shader view 2.82 ms
(355 fps) old, 2.96 ms (338 fps) new; the software fallback 38.4 vs 41.9 ms.
The shader view's extra is the cut caps, roof caps and slopes in the plane
table (format-1 levels send empty rows). Phones and the browser were not
timed.

### Pictures

- Before/after of every changed spot: `docs/remaster/<map>/before_*.png`,
  `after_*.png`; top-down plans: `plan_before.png`, `plan_after.png`.
- The demo map: `docs/map_examples/edit_demo/before|after/*.png` (labelled
  plans per floor with nav), software and graphics-card views checked in a
  window tour (`map shot`, `--view-tour`).
- Reference pictures that changed on purpose (rewritten and committed):
  `tools/pictures/` and `tools/pictures_gpu/` for hickston_05_0,
  hickston_fight_1_16, sawmill_01_2, sawmill_04_0, sawmill_mill_water_0,
  sawmill_fight_5_16, low_sawmill_mill_water_0, quarry_fight_1_26,
  bayou_stilt_row_0. The shader view matches the software view on all 36
  reference views (compare_views: VIEWS MATCH).

## 10. Not done, not checked, limitations

Not checked (nobody on the agent side can):
- Listening to anything; playing by hand with a mouse and keyboard; a phone
  or the browser build (CI builds the browser and Android only on `main`
  and tags, so those builds have not run for this branch: the merging
  session's release run will be their first).
- The Godot editor's Maps screen by hand: its logic runs headless in
  `map_check.gd` (open, save unchanged, add, move, apply, undo/redo, build),
  but nobody clicked it in a running editor.
- The browser build's frame time with the new shader branches (one more
  function call and a loop that is empty on every old level; two texture
  fetches per cap that a pixel falls in).

Not done:
- New sounds (none were needed; no ElevenLabs credits spent).
- Height on the speedway, the hub and the versus maps (reasons in section 4).
- glTF materials with textures: import maps material names to the game's
  tiles; it does not bring textures in (the game's art is its own palette).

Range update, not checked: how the bowling lane feels with a mouse (only the
physics in numbers and pictures); the new pin clack (a made cue, `assets.gd
MADE_CUES`) has not been listened to; the Swamp King, Maw and Boggs in the
corral were seen fighting in pictures and the range check, not played by hand.

Limitations of the geometry (also in MAP_AUTHORING.md): upright walls and
flat or planar sloped floors only (no slanted walls, arches, pitched roofs to
walk on); solid cells are full height; one roof height per cell; grid doors
one cell wide on the ground floor (openings of any size are door-less);
cut lines at most two per piece; rain treats a cell under any deck as roofed;
the automap draws every floor at once; things dropped in play land on the
floor under where they fall.

## 11. The firing range brought up to date (layout 3)

Asked for by the owner during this work: the range had not kept up with the
guns, bosses and hands added since it was made, and its bowling was a dice
roll. Every existing station is where it was.

- **Every gun on a rack.** The 14 guns and throwables of the 5v5 store hang
  on a **store wall** standing free down the armory's middle (a thin wall of
  the level's geometry, `range_layout.gd STORE_WALL`): the outlaws' guns on
  its north face, the deputies' on its south, each with its picture, plaque
  and take-station, a header board each side. The pictures are new:
  `scripts/blender/item_pictures.py` lays each gun's own first-person model
  (`weapon_views.py`) on its side and renders it square on (long guns get the
  wrist the hand normally hides), and `tools/art/build_item_art.gd` crops,
  shrinks and grades them into `assets/art/item_<gun>.png`. The plaques, lever
  plates and store headers are painted by `build_range_signs.gd` after
  everything else, so every existing sign comes out byte-identical. Each gun
  says what it is when taken (`firing_range.gd GUN_NOTES`).
- **All eight bosses in the corral.** New levers for THE SWAMP KING, BUMPER
  BOGGS and MAW GLORB. The corral has a pond along its south fence (shallow
  round a deep middle, `L.POND`): the King's airboat comes in on it and keeps
  to it; nobody else goes in the deep. Maw's fight (`features/mothership.gd`)
  now also runs on the range: it picks up a Maw let out into the corral, her
  pods are the corral's (`L.MAW_PODS`), and there is no ship to come apart
  after her. The Baron's outlets, Rudy's decoys and the boss gate moved north
  of the pond. The clear lever also takes away a boss's backup and Maw's
  younguns.
- **Every hand in the bullpen.** A second lever bank down the bullpen's west
  fence: noodler, chum tosser, gator, pit mechanic, tire roller, nitro huffer,
  flagman, drone, probe, tin guard, and two levers that turn out the next
  chapter's tough guy (Big Earl to Zorgo) and the next oddball (big Billy, the
  drunk coot, the deputy with a door) each pull. A chapter-only kind waits for
  its chapter's pictures in the browser, variants included.
- **The Bowl-O-Rama** (`src/range_bowling.gd`, new): the pins are bodies. Each
  has a base and a lean (a 2D vector with its rate): knocked, it leans; past
  ~10 degrees its own weight takes it down, short of that it rocks back (a
  wobbler). Leaning or down it is a capsule from base to head, so a falling
  pin sweeps into the next; lying pins slide and spin; they bounce off the
  kickbacks and drop into the pit or a gutter. The ball is the game's own
  rolling shot: it trades momentum with each pin it meets (a 16-pounder
  against 3.5) and goes on slower and deflected; past the oil it **hooks** the
  way the thrower was turning as they let go; off the lane it runs down the
  gutter. The pinsetter sweeps the deadwood after the first ball and stands
  the rest up where they stood; a fresh rack after a strike or a frame's last
  ball. **Ten-frame scoring** (strikes and spares count ahead, the tenth's
  bonus balls), splits called by their pins ("7-10 SPLIT!"), the sheet and
  best game on the lane's card. Pictures: the pin modelled in Blender tipped
  22 and 50 degrees and lying, at seven headings to the viewer
  (`props_range.py`, `town_range_pin_t<k>_<j>`), picked each frame by lean and
  heading. A knock clacks (a made cue, no credits spent). Part of the range's
  play (carried in snapshots), own dice. Bowling a range of lines: pocket hits
  strike, head-on hits leave splits, the edge clips a pin or two, a hook from
  the edge carries in.
- **Checks**: `tools/range_check.gd` (in check_fixes) now lets every boss out
  (the King on the water, Maw's fight picking her up), turns every pen kind
  out (the tough guys and oddballs in turn), takes every one of the 30 guns
  off its rack, rolls balls down the middle, the pocket, the edge, the gutter
  and with a hook, keeps every pin on the lane, and scores sheets (300, 150,
  90, 167) and a 7-10 split. `tools/range_frames.gd` takes window pictures of
  all of it (`docs/remaster/range/update/`).
