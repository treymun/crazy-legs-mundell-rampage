# Geometry remaster: progress notes

Branch `geometry-remaster` (from dev.39). Not to be merged, tagged or released
from this branch: the session on `combat-overhaul` merges both and publishes.
Resume from here if a session stops: read this, `REMASTER_HANDOFF.md` (when
written), `MAP_AUTHORING.md`.

## Decision: extend the 2.5D engine (not a Godot 3D path)

See REMASTER_HANDOFF.md "Architecture". In short: level format 2 adds a
`geometry` block (slabs walked on and under or solid to the ground, flat or
sloped; segments with their own z range; ceilings) to the cell grid; bodies
carry `floor_z`; FlowField walks a nav graph with a node per floor over a cell.

## Status

- [x] Audit, design
- [x] Engine: src/level_geometry.gd, LevelData hooks, bodies, shots, tumble,
      both renderers (cut caps, roof caps, slopes), nav graph, saves v8
- [x] Authoring: maps/<id>.map.json, tools/map.gd (new, inspect, validate,
      build, render, shot, playtest, edits, undo, catalog, schema, import),
      components, catalog, schema, validation codes, playtests
- [x] Editor: addons/clmr_maps Maps screen (headless-tested round trip)
- [x] glTF import (tested with a GLB made in the check)
- [x] Demo map feedstore (docs/map_examples/feedstore_build.sh)
- [x] Checks: tools/geometry_check.gd + tools/map_check.gd in check_fixes
- [x] MAP_AUTHORING.md
- Remaster (plans + layout bumps):
  - [x] range (layout 2): deer stand in the bullpen
  - [x] hickston (4): feed barn hay loft (hickston_loft.gd)
  - [x] fair (4): derby bleachers a step a row
  - [x] sawmill (5): log pond bridge on trestles
  - [x] quarry (5): sloped haul ramps between the benches
  - [x] bayou (3): preacher's stilt house + gangway
  - [x] mothership (3): gantry ramp as a slope
  - [x] grainyard, holler, salvage, pumpngo, pineacres, landing: reviewed, unchanged (reasons in the handoff); map_timing and tactical_check identical to dev.39
  - [x] speedway, hub: reviewed, unchanged (reasons in the handoff)
- [x] check_all, save fixtures (v8 + *_layoutN), picture and GPU references rewritten; CI green
- [x] first_minutes whole on every changed chapter (all finish; bayou needed two nav fixes)
- [x] Performance (bench.gd, --view-bench) old vs new: geometry levels tick 5-12% slower, shader view +5% (handoff "Performance")
- [x] REMASTER_HANDOFF.md

## Known issues found (not caused here)

- range: the 5v5 guns' and throwables' wall pictures (item_hunter..,
  range_plaque_16..29) do not exist in assets/art, and the shipped range.json
  predates their racks. The plan now racks only guns with pictures (the range
  as shipped, 16 racks); the other 14 racks appear when that art is made.
- Two clones running check_all at once share OS cache files: boss rematch
  checks can fail (passes alone).

## Range update (owner's request during the remaster)

- [x] 30 guns racked: store wall (geometry thin wall) with the 14 5v5 guns and
      throwables; pictures from Blender (scripts/blender/item_pictures.py,
      tools/art/build_item_art.gd); plaques and plates painted last
- [x] corral: all eight bosses, a pond for the Swamp King, Maw's fight on the
      range (features/mothership.gd on_range)
- [x] bullpen: west lever bank with every newer hand, tough guys and oddballs
- [x] bowling: src/range_bowling.gd (pin bodies, lean, capsules, hook, gutter,
      pit, pinsetter, ten-frame scoring), pin pictures tipped and lying
- [x] range_check extended; tools/range_frames.gd pictures in
      docs/remaster/range/update/
- Perf note: the walk test's grid shortcut was taken out again (it changed
  play on the bayou: fixture heights over water); the query early-outs stay.
