# Geometry remaster: progress notes

Branch `geometry-remaster` (from dev.39). Not to be merged, tagged or released
from this branch: the session on `combat-overhaul` merges both and publishes.

## Decision: extend the 2.5D engine (not a Godot 3D path)

The look is the custom renderer (software view + `palette.gdshader`), and
collision, sight, hitscan, flow fields, 5v5 bots, saves and the netcode's
tick-for-tick determinism all go through `LevelData`. The engine already had
per-pixel depth, wall pieces with their own bottom/top, floor caps at any
height and 3D collision boxes, so the new geometry is an extension of it:

- `src/level_geometry.gd` (`LevelGeometry`): a level's `geometry` block
  (level `format` 2): **slabs** (walkable decks with a thickness, or solid
  wedges/treads down to the ground; rectangle cut by lines; flat or sloped
  top), **segments** (thin/angled walls with z range, rails, cover) and
  **ceilings**. Queries: `floor_at`, `ceiling_at`, `blocks`, `solid_point`,
  `crosses`; bodies: `can_walk`, `settle`; render parts; nav graph.
- `LevelData`: `geo`, `stand(body)`, `floor_under(x,y,z)`, `roof_over(x,y,z)`,
  `crosses()`; blocked()/visible() ask the geometry in its cells.
- Bodies: `Player.floor_z`, `Enemy.floor_z` (only read when `geo` exists).
  Actor height lookups go through `world.stand(body)` (= `elevation()` on old
  levels, so old levels are exact).
- Renderers: caps may carry cut lines; `roof_caps` (undersides seen from
  below); `slopes` (software `_slope_layer`, shader `plane_at` wrapper). The
  plane table grew rows (light map now from row 12); no new texture.
- `FlowField.graph`: on format 2 levels the field walks `LevelGeometry.NavGraph`
  (node < w*h = the cell's own floor, the rest decks). heading/distance/
  waypoint/update take an optional z.

## Status

- [x] Audit
- [x] Geometry core, LevelData hooks, bodies, shots, tumble, renderers, flow graph (written)
- [ ] Verify: regression checks on old levels unchanged
- [ ] Saves: floor_z (SessionStore version bump + fixtures)
- [ ] Authoring: map source JSON + schema, `tools/map.gd` CLI, components, catalog, validation, renders, playtest
- [ ] Editor support
- [ ] glTF import
- [ ] Demo map
- [ ] Remaster maps
- [ ] MAP_AUTHORING.md, REMASTER_HANDOFF.md
