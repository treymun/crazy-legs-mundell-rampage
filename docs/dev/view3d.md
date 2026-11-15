# The 3D view

The world is drawn by a real 3D view in `godot/src/view3d/`. It replaced the
software renderer (`render_state.gd` .. `renderer.gd`, `scene_layers.gd` and
`palette.gdshader`), which is gone, along with its fallback, the start-up
driver check and the `--cpu-view`, `--view2d`, `--cpu-walls`, `--view-check`
and `--view-broken` flags. The planning notes for the move are in
`docs/godot3d/` (plan, progress, surveys).

## View: what play knows of the view

`View` (`src/view3d/view.gd`, `class_name View`) is what play needs; it draws
nothing. `game.view` is the View (there is no `game.renderer`).

- The canvas and projection: `WIDTH` 320, `VIEW` 156 (the view's rows),
  `HEIGHT` 200, `FOCAL` 230. Aiming, the crosshair and every screen overlay
  use this projection.
- FIELD OF VIEW: `FOCAL_FOR` (230, 190.7, 160, 134.3 for 70, 80, 90, 100
  degrees). `static base_focal` is the one in use; `static fov_focal` is the
  setting's, and `base_focal` is that times a scope's zoom while this
  machine's player has one up (`scope.gd`). Aiming works its slopes out with
  `base_focal` too.
- `static auto_low`: VIEW DETAIL AUTO has dropped to LOW (`main.gd
  _auto_detail`); kept for the session.
- Inner classes handed to the 3D view: `View.Sprite` (a picture in the world;
  `who` is the enemy it shows, drawn as its model when there is one),
  `View.WallMark`, `View.GroundMark`.
- `set_detail()`, `detail` (-1 HD, 0 HIGH, 1 LOW), `res_up`, `hd_wanted`,
  `world_motion`, `layered` (true with a window and a 3D view).
- DRAW DISTANCE: `View.draw_far_for(setting)`; `draw_far` is how far the view
  draws, in cells. AUTO is NEAR (64 cells, where a wall is a few pixels tall)
  on phones (mobile, web_android, web_ios) and FAR (160, the speedway seen
  across its oval) elsewhere.

### VIEW DETAIL and HD

VIEW DETAIL HD (setting value 3, off by default) is `view.set_detail(-1)`: the
view is drawn 640x312 at twice the focal length and the display shader shows it
at that size (`view_mul`), while the weapon, HUD and their effects stay
320x200. LOW draws 160x78. A frame drawn without the 3D view (headless) keeps
HIGH and the wish (`set_detail(0, true)`, `hd_wanted`), so the next frame
drawn with a window is HD again; never `set_detail(0)` for one frame. The film
look (grain, dither, vignette) works on the view's own grid, so HD keeps its
detail under it; HIGH is the 320 grid. (HD cost about 1.5x the frame in the old
shader view; not re-measured in the 3D view.)

## How a frame gets drawn

1. `game_view.gd` builds `game.view_frame` each draw: `{eye, horizon, flash,
   sprites, marks, ground, reflection}`.
2. `main_state.gd _frame_3d()` hands it to `WorldView3D`.
3. `WorldView3D` (`world_view.gd`) renders into a SubViewport at the view's
   size (320x156; LOW 160x78; HD 640x312) with an off-axis frustum camera
   that reproduces the old y-shear pitch: horizon = 78 + pitch + bob + sway,
   focal 230. Looking up and down shifts the horizon, as in the Build engine,
   so aim, crosshair and overlays stay true. It is read-only toward play.
4. `src/display.gdshader` (canvas_item) makes the picture players see: the 3D
   view's texture (`view3d_tex`) under the weapon/HUD/menus layer
   (`post_tex`), moonshine warp, heat haze, hurt flash, the look pass (grain,
   dither, vignette, tone table) and the VGA palette lookup (RGB555 ->
   palette).

Headless runs draw no world, only the canvas. The renderer is
`gl_compatibility` on every platform.

**Coordinates:** map (x, y, z) is Godot (x, z, y).

## The pieces

| Piece | File | What it does |
| --- | --- | --- |
| `WorldView3D` | `world_view.gd` | the SubViewport, camera, sky, layers; rebuilds the level mesh when `walls_version` or `light_version` moves |
| `LevelMesh` | `level_mesh.gd` | walls, floors, caps and slopes in 16x16 chunks; per-vertex CUSTOM0 tint + light, CUSTOM1 tile/kind |
| `ViewTiles` | `view_tiles.gd` | the tiles as a Texture2DArray, plus a row of tile info (water, relief, puddles) |
| world shaders | `world.gdshader`, `world_glass.gdshader`, `world_body.gdshaderinc` | solid vs see-through variants of one body via `#define` |
| light include | `view_light.gdshaderinc` | lights, fog, grade, rain, wet, water rings, relief, anim lights, mirror clip, `photo_grade`, `to_output` |
| sky | `sky.gdshader` | the sky behind the eye's camera |
| sprites | `sprite.gdshader`, `sprite_clear.gdshader`, `sprite_body.gdshaderinc`, `SpriteLayer3D` | camera-facing MultiMesh billboards |
| marks | `mark.gdshader` | wall and ground decals |
| rain | `rain.gdshader` | three camera-hung layers |
| slabs | `SlabLayer3D`, `SlabModels`, `slab.gdshader` | pickups, loose things (brass, gibs, bits) and range targets as pixel slabs (MultiMesh per mesh) |
| props | `PropLayer3D`, `PropView`, `prop_models.gd`, `prop.gdshader` | modelled props |
| actors | `ActorLayer3D`, `ActorView`, `actor_models.gd`, `actor.gdshader` | rigged enemies and bosses |
| heat | `HeatHaze` | heat shimmer boxes, handed to the display shader |
| mirror | second camera | draws the reflection on cull layer bit `1 << 19` (`LAYER_MIRROR`) |

All the view's shaders are unshaded custom shaders that port the old light
formulas, so a level looks as it did. Lights, glows, fog, grade, weather,
water, relief and shimmer are behind LIGHTS AND GLOW (`effects_on`, from
`data/tuning/effects.cfg`); see [gameplay.md](gameplay.md#mood-weather-and-sound)
for what feeds them.

### Things that are easy to get wrong

- **A shader that writes ALPHA anywhere becomes transparent** in Godot, and
  sorts and draws as such. That is why the world shader is split into
  `world.gdshader` (solid) and `world_glass.gdshader` (see-through) over one
  shared body with `#define`. Keep them split; do the same for any new
  shader that needs both.
- **Texture counts.** WebGL and many phones give a shader 16 texture units
  and Godot keeps several; past the limit the browser and Android builds draw
  nothing while a desktop looks fine. `display.gdshader` samples 4 textures
  now. `tools/check_shader.gd` (in CI) counts textures in `display.gdshader`
  (limit 9 including TEXTURE) and in every view3d shader with its includes
  (limit 10). Stack new data into an existing texture instead of adding one.
- **Nothing in the view changes play.** It reads the level, camera and sprite
  list and changes nothing; a host game draws nothing at all.
- **Guns in hand stay 2D cels** over the 3D view (`weapons.gd`), drawn on the
  canvas layer.
- **Slab edges repeat.** A stair's, deck's or ramp's side
  (`LevelGeometry.slab_edges`) in a stretched material is laid along by the
  metre from a point fixed on its line (`LevelMesh`), so each tread does not
  squeeze the whole tile into its own height; `EDGE_STRETCHED` keeps the
  ones drawn per piece (the grandstand riser).

## Props

Each prop placed with `town()` shows as a `PropView` scene
(`scenes/props/<name>.tscn`) over its baked glTF model. 194 props. The
pipeline that makes them is in [art.md](art.md#props). A light with `props` in
effects.cfg rides every prop with that picture.

A prop's facing is worked out once for where it stands (the most open way),
unless its sprite sets `plane`: then the model turns by `-plane`. A moving
prop (the speedway's lap cars, `race_laps.gd`) sets `plane` from its heading,
so it faces where it runs; it is stood again each frame it moves.

## Slabs: pickups, loose things, range targets

Some of the world's flat pictures are drawn by `SlabLayer3D` as slabs made
from their own picture (`SlabModels`): the picture's solid pixels (alpha
over 100, the solid sprite test) pushed out a few pixels thick. Front and
back show the picture; each edge pixel's side wall is one colour, the
pixel's, or past a drawn dark outline the first pixel inside it (so a can's
side is the can, not its black line). Sides are shaded .78, tops .9,
bottoms .62 of the front's light, like a 1997 voxel. Three families
(`SlabModels.family(image)`):

| Family | Pictures | Thickness |
| --- | --- | --- |
| PICKUP | `item_*` (guns, ammo, beer, rinds, keys, County Run supply piles; not boards or see-through sprites) | .6 of the art's breadth, 2 to 12 px |
| LOOSE | `fx_casing`, `fx_hull`, `gib_*` (meat, charred, scrap), `fx_brk_*` (breakables' bits), `fx_chips`, `fx_soil`, `fx_splinter_*`, `fx_grit_*`, `fx_hat_*`, `fx_drop_*` | .5 of the breadth, 2 to 8 px |
| TARGET | the firing range's `town_range_target`, `town_range_gong`, `town_range_cow_target`, `county_gallery_target`, `town_range_duck` | plywood: 1 px per 28 rows, at least 2 |

The breadth is the middle of the art's solid columns' and rows' counts (a
gun's barrel, a can's width). Blood, smoke, flames, muzzle flashes, embers,
glints and other glows stay sprites, as do see-through sprites and the
bowling pins and ball (`range_bowling.gd`, props).

- **No files.** The meshes are built from the art the first time a picture
  is seen and cached (150 pictures, about 190 triangles each); nothing is
  added to the export. A picture not here yet (a chapter pack still being
  fetched) stays a sprite.
- **Same size and place.** A mesh is in sprite units (one unit the
  picture's height, its empty bottom rows kept), scaled by the sprite's
  height and stood at its x, y, z, so from the front it is the billboard;
  x is centred on the art's solid columns.
- **Parts.** `SlabModels.PARTS` cuts a box of a picture into a mesh of its
  own (`<picture>#part`) that moves apart from the rest: the gong's plate
  and chains, hung from the box's top edge (`pivot()`); the picture's own
  mesh leaves those pixels out, and both are placed as the whole picture,
  so they fit.
- **Same light.** `slab.gdshader` is `sprite_body.gdshaderinc` with
  `MESH`: the sprites' art slots (`SpriteLayer3D.slot()`, so call
  `show_slabs` after `show_sprites`), stepped light, the area's tint, glow,
  then LIGHTS AND GLOW with the face's own normal, fog and grade. Solid only
  (no ALPHA), `cull_back`; no new texture. One MultiMesh per mesh.
- **Motion is looks only**, worked out each frame from the sprite (nothing
  kept, no dice of the game's):
  - A pickup turns at `TURN` (.9 rad/s) on `game.clock`, phase from its
    place; the bob is still the sprite's z (`game_view.gd`,
    `county_orbs.gd`). EASY ON THE EYES (`world_motion`) slows both to .4
    (REDUCED) and stops them (STILL), where each pickup faces the eye square
    to the view, as the sprite did.
  - A loose thing in the air tumbles in 3D: it turns about its face by the
    sprite's `spin` (the features' own: debris and gore keep a spin rate,
    breakables, weapon_fx and hit_reads work it out from where the bit is)
    and end over end by `PITCH` (.7) of it, heading where its place says
    (`HEADING`: it turns as it flies and slides and holds still at rest). On
    its floor (`View.Sprite.lying`: at rest, or rolling with no fall) it lies
    flat, propped `PROP` (.05 to .4 rad) off the floor by its place so it
    still reads from a standing eye, face up (face down, the picture
    mirrored, when flipped). Either way its lowest corner is on the sprite's
    z and its middle over its x, y, as the turned billboard's was.
  - A target stands on its foot along its `plane` (the lanes' boards, gongs
    and cows face the firing line, south), turned round when flipped (a
    gallery mover going the other way shows its back), and leans back about
    its foot by `View.Sprite.tilt`. `range_targets.gd` sets it: a board or a
    cow spins on its stand when hit (its `plane`, as before); a gong's plate
    swings from the bar (`GONG_SWING`, `GONG_REACH`; the frame stays put); a
    gallery mover wobbles on its stick as it rides (`MOVER_WOBBLE`, less with
    EASY ON THE EYES, none when STILL) and, knocked down, goes over flat
    backwards in `MOVER_FALL` and pops up when its `DOWN_TIME` is over (it
    used to vanish). The dummies are props (`range_dummy`): they rock by the
    same `tilt` (`ROCK_*`, `PropView.lean()`) instead of sliding sideways.
- Out to 32 cells ahead, as the sprite was; targets to 51 (a tall
  sprite's), so the rifle range's far gongs show from the firing line.

Pickups before (left), STILL (middle) and turning (right):
`docs/godot3d/remaster/pickups/*.png`. Loose things and targets before and
after: `docs/godot3d/remaster2/slabs/*.png`.

## Actors

Each enemy and boss with a model shows as an `ActorView` scene
(`scenes/actors/<kind>.tscn`); `View.Sprite.who` names the enemy.

- ActorView poses from the sprite name the game would have shown: walk
  interpolated on gait, falls on time since death.
- The look (plain, hurt, p2, p3) is picked by health and boss phase.
- Lost limbs are left off (`Gore.lost`).
- Bones are labelled head, arm_r, arm_l, leg_r, leg_l, body.
- A picture name's `~r.g.b` tint (`Assets.tinted_art`) tints the model too.
- Bodies that are not enemies can wear a model through a stand-in Enemy that
  only the view reads: the 5v5 players and hostages (`ModeBodies`,
  [modes.md](modes.md#rounds)). Co-op and deathmatch partners are still the
  player's cels: there is no model of the player.

The pipeline is in [art.md](art.md#actors).

## Checks

- `tools/view3d_check.gd` builds every level's mesh headless, loads every
  prop and actor scene and builds every slab (pickups, loose things, range
  targets; a gong with its plate), holding its front to the picture's size
  and place (VIEW3D CHECK OK; in check_all and CI).
- `tools/check_shader.gd` counts textures (SHADER OK).
- `tools/compare_3d.gd` holds a window tour's pictures against
  `tools/pictures_3d/` ([checks.md](checks.md#picture-references)).
- `tools/compare_sheet.gd` makes side-by-side sheets of two tours (the 3D
  rewrite's, old renderer left and 3D view right, are in
  `docs/godot3d/compare/`).

In a window:

```
godot --path godot --audio-driver Dummy --resolution 1280x800 -- --view-tour=res://tools/picture_views.json --view-out=<dir>
godot --path godot --audio-driver Dummy --resolution 1280x800 -- --view-bench=300
```

A tour viewpoint may set `map`/`map_zoom`, `gun`/`fire`/`ticks`, `rain`,
`wet`, `lightning`, `actors` (to show the 3D models) and `motion` (EASY ON
THE EYES: 0 full, the default, 1 reduced, 2 still).

## User folder

The 3D build uses its own user folder ("Crazy Legs Mundell Rampage 3D"), so it
never shares a profile with the published game.
