# Godot 3D rewrite: the plan

What the owner asked for, in order: the whole game on Godot's real 3D
(Node3D, meshes, cameras, animated 3D enemies) with the 1997 look kept
exactly (320x200 picture, palette, art, dusk mood), and the code rebuilt
into small self-contained systems that are easy to extend. Findings behind
this plan: `survey.md`. Running log: `progress.md`.

## 1. The new structure

```
godot/src/
  core/        GameEvents (the signal hub), Typed helpers
  sim/         the simulation systems, each owning its own data:
               players, enemies, pickups, doors, shots, hazards, objectives,
               stations ... (moved out of the game_state..game chain)
  view3d/      the 3D view: WorldView3D, LevelMesh, SpriteLayer3D,
               MarkLayer3D, ActorLayer3D, PropLayer3D, view shaders
  ui/          screens (one object per menu), the HUD, the theme
  features/    GameFeatures, now listening to GameEvents
  modes/       game modes, unchanged in idea
godot/scenes/  enemies/, bosses/, props/, pickups/, weapons/, effects/
               (.tscn: a model + a small script with the numbers)
godot/data/    levels (JSON, as now), tuning (cfg/json), content Resources
```

### The seam between play and picture

The simulation never draws and never asks the view anything. Each frame the
view reads the game's state:

- the camera (`Player.as_render_player()` plus shake and kick),
- the level (walls, floors, roofs, caps, slopes, doors, panes, gates, light,
  tints) for the static mesh, rebuilt only when `walls_version`,
  `light_version` or a door's progress says so,
- the frame's sprites (`game.sprites()`, as now) for everything that is still
  a picture: effects, gore chunks, pickups, signs, items,
- enemies by their own state (kind, pose, phase, facing, hurt, limbs) for the
  3D actors (Stage 3), instead of their sprite,
- wall marks and ground marks for decals,
- the lights (`ViewLights`) and the level's mood (`Effects.mood`).

Two old couplings go first: hitscan's material lookup (`renderer.wall_mark`,
pure geometry) moves into `LevelData`, and the art sizes breakables use come
from `Assets` directly. Then a host or a tool needs no view object at all.

### How the look is kept

The 3D view renders into a SubViewport the size of the old view (320x156,
HD 640x312). Every surface uses our own unshaded spatial shaders that carry
the old renderer's formulas per pixel: the distance shading
`round32(max(.19, L / (1 + .102 d)))` with the area tint, the same tile
mapping (repeating materials at 1.28 units, windows between 1.0 and 1.68),
nearest-neighbour texels with no mipmaps, the same sky panorama, and (with
LIGHTS AND GLOW) the same lights, fog, grade, rain sheen and lightning as
`palette.gdshader`'s `surface_light`. The camera uses an off-axis frustum so
looking up and down is the old horizon shift, not a rotation: aim, crosshair
and every screen overlay (`to_canvas`) stay exactly true.

The display shader keeps everything after the view: the weapon/HUD/menu
layer, hurt flash, drunk warp, grain, dither, vignette, tone table and the
RGB555 -> VGA palette lookup. So the palette colours are kept by
construction, on every platform.

One renderer everywhere: `gl_compatibility` (desktop, Android, browser).
Because the look is in our shaders, nothing depends on Forward+.

### Scenes for content

- Props: glTF meshes exported from the existing Blender scripts (same
  shapes and materials, baked to the palette), wrapped in
  `scenes/props/<name>.tscn`. A prop without a model yet stays a billboard.
- Enemies and bosses (Stage 3): armatures added to the Blender actor scripts
  (rigid parts parented to bones: the segmented low-poly look suits 1997),
  glTF with animations, `scenes/enemies/<kind>.tscn` with an `EnemyLook`
  script (animation names, hit zones, gore points, phase looks).
- Pickups, weapons' world models, effects: scenes the same way.

Adding an enemy becomes: copy a scene, swap the model, edit its numbers
(enemies.cfg keeps the behaviour numbers).

### The event hub

`GameEvents` (one per game, `game.events`) carries every signal the game
announces now (enemy_killed, player_hurt, pickup_taken, shot_fired, traced,
exploded, level_won ...) plus level_started/ended. The old `game.<signal>`
names stay as forwards while features move over, then go. County Run XP,
barks, gore, stats and the 3D view's effects listen there, so new features
never edit combat code.

### Breaking up the layer chains

The chains (`main_state..main`, `game_state..game`, `render_state..renderer`)
go one area at a time, each step checked:

1. The renderer chain is deleted at the switch (Stage 5).
2. Play: systems move out of the chain into `sim/` classes that own their
   data (pickups, doors, objectives/stations, shots and hazards, automap,
   look/grade, barks), with `game.<field>` kept as a property for one release
   so saves, snapshots and features keep working; the chain then collapses
   into one small `Game` that owns and ticks the systems.
3. Front end: one screen object per menu (Stage 6) replaces the text states,
   so `main_state..main` shrinks to the app shell (window, loop, input
   routing).

Snapshots and saves name fields by their place in `Game`; a field that
moves keeps its saved name through `GameSnapshot`/`SessionStore` mapping, so
no save version changes unless the content does.

### Static typing

New code is fully typed. `untyped_declaration`, `unsafe_property_access`,
`unsafe_method_access` and `unsafe_call_argument` become errors in
`project.godot` once the old code passes; the files are cleaned in batches
with a checker that lists each file's warnings.

## 2. What is rebuilt, what is kept

Kept as it is: the simulation (movement, collision on the grid, flow fields,
`blocked()`, enemies' brains, combat numbers, modes, net code, saves), the
level builder and level JSON, the tuning files, the art pipeline's pictures
(tiles, signs, items, effects, the gun cels), the sound, the display
shader's look pass and palette.

Rebuilt: the view (software renderer, its shader composer, SceneLayers),
props as meshes, enemies as animated models, gore as decals/particles/meshes,
the menus and HUD as Control nodes, content numbers as data files, the docs.

Retired at the switch: `render_state/surfaces/sprites/renderer.gd`,
`scene_layers.gd`, the view half of `palette.gdshader`, the start-up view
check, `picture_check` (software pictures), `compare_views` (shader vs
software), the HD/LOW detail plumbing that only the raycaster needed.

## 3. Order of work

1. Survey, plan, quick checks (this).
2. The 3D view beside the old one (`--view3d`, then a setting): level mesh,
   sky, sprites, marks, camera; then lights, fog, weather, water; props as
   meshes. Compare screenshots old/new at the tour's viewpoints.
3. Untie play from the renderer (wall_mark, art sizes, TILED table).
4. GameEvents hub, features moved onto it.
5. Animated 3D enemies and bosses.
6. Gore and effects in 3D.
7. Every map and mode checked in 3D; headless server with no view; browser
   and phone settings; the switch (old view deleted); new 3D picture
   references in the window CI job.
8. Break up the play chain into systems; typing warnings as errors.
9. Menus and HUD on Control nodes.
10. Content as data.
11. Docs.

Test builds (Windows EXE, Android APK) go to
`Downloads\CrazyLegs-3D-Test` at the end of every stage.

## 4. Risks

- **Exact play.** The simulation must not change: determinism (net), saves,
  bots' walkthroughs. Mitigation: the view only reads; every stage runs the
  full check set (net_check, multi_bots, save_fixtures, bot_campaign).
- **Look drift.** 3D interpolation and float precision differ from the
  raycaster in single pixels (texel edges, row rounding). Mitigation: same
  formulas, nearest texels; side-by-side pictures every chapter; tuning
  where a difference reads as "less like the original".
- **Phones and the browser.** Compatibility renderer limits (texture units,
  no compute). Mitigation: tiny render target (320x156), one MultiMesh for
  sprites, a texture array for tiles and art, static level mesh in chunks,
  draw-distance culling; a phone quality setting (no lights, shorter draw).
- **Animated enemies are the biggest art job** (about 40 kinds and 8 bosses,
  procedural per-frame meshes today). Mitigation: a generic rig built from
  the same `skeleton()` joints, parts parented rigidly to bones, actions
  baked from the existing pose code; kinds without a model keep their cels
  until done.
- **Headless.** The lobby server and tools must never create the view.
  Mitigation: the view is created only by the front end with a window.
- **Size of the restructure.** 67k lines of game code. Mitigation: move one
  system at a time behind the old names; never mix a move with a behaviour
  change; checks after each.

## 5. Checks

- Quick set (about two minutes): `tools/quick_check.gd` - boot, assets,
  check_fixes, the 3D mesh build of every level headless, gdformat/gdlint.
- Full set at the end of each stage: `check_all -- lint` plus the window
  tour pictures.
