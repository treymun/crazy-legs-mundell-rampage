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
  - [~] mothership (3): gantry ramp as a slope (plan edited, not built yet)
  - [ ] grainyard: a raised vantage (if balance holds)
  - [ ] holler, salvage, pumpngo, pineacres, landing: review; likely unchanged
  - [ ] speedway: likely unchanged (already banked oval, stepped stands, booth)
  - [ ] hub: likely unchanged (a hub of gates; flat on purpose)
- [ ] After each batch: check_all, save_fixtures make + expected.json,
      picture_check update (hickston_05_0 sees the barn), GPU refs (window tour)
- [ ] Performance (bench.gd, --view-bench) old vs new
- [ ] REMASTER_HANDOFF.md

## Known issues found (not caused here)

- range: the 5v5 guns' wall pictures (item_hunter.., range_plaque_16..29) do
  not exist in assets/art; the builder reports them (28 problems), the boards
  show nothing in game. Pre-existing since dev.38.
- Two clones running check_all at once share OS cache files: boss rematch
  checks can fail (passes alone).
