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

### QUALITY: the tiers

QUALITY (VIEW page, `quality`: AUTO, LOW, MEDIUM, HIGH; `src/core/quality.gd`)
picks VIEW DETAIL, DRAW DISTANCE, LIGHTS AND GLOW, SHADOWS and the physics
detail at once:

| Tier | VIEW DETAIL | DRAW DISTANCE | LIGHTS AND GLOW | SHADOWS | physics |
| --- | --- | --- | --- | --- | --- |
| LOW | LOW | NEAR | off | off | LOW (half the steps) |
| MEDIUM | AUTO | NEAR | on | on | MEDIUM (two thirds) |
| HIGH | AUTO | FAR | on | on | HIGH (all; the old defaults) |

- A tier picked in setup sets the three settings (`main_flow.gd
  _quality_picked`); each can still be changed afterwards.
- AUTO measures once, in a real window only (never tools, tours, benches or
  smoke runs): `Quality.Meter` takes the frame's own work plus however late
  the frame came, for `measure` seconds after `settle` seconds of play
  (`camera.cfg [quality]`), and picks HIGH under `high_ms`, MEDIUM under
  `medium_ms`, else LOW; a phone or tablet never above `phone_top` (MEDIUM).
  The tier is kept in `user://quality.json` (`Quality.save_measured`, which a
  tool never writes); on a first run (no settings saved before) it also sets
  the three settings and says so. Picking AUTO again measures again.
- **`Quality.physics`** (0 LOW, 1 MEDIUM, 2 HIGH) is the one number other
  systems read; `Quality.steps(full)` cuts a solver's steps to it (the bowling
  pins' `STEPS`, `range_bowling.gd`). `Quality.level()` is HIGH whenever
  `Quality.shared` (more than one player, or online; main.gd sets it each
  frame), so every copy of a networked game steps alike; a host or a tool
  that never sets it is HIGH.
- FRAME COUNTER (DISPLAY, `show_fps`) shows the frames per second.

## PHOTO MODE and the KILL CAM

Both draw the 3D view from a camera of their own while the front end does
not tick the game, so nothing of play moves (`tools/camera_check.gd` holds
the game's snapshot, clock and view frame the same).

**PHOTO MODE** (`src/photo_mode.gd`; P in play, Y on a pad's pause screen,
PHOTO on a touch screen; single player): the camera starts at the player's
eye and flies by `main_input.gd _controls()` (keys and mouse, the pad's
sticks, the touch stick and a drag; jump and crouch up and down, run
faster), sliding along walls, off floors and ceilings and within `reach` of
the player (`camera.cfg [photo]`). `game.eye_override` (a VIEW field) is the
eye `game_view.gd _draw` uses: no shake, the sprites culled to it, the player
added as Mundell (`ModeBodies.player_sprite`; in a vehicle he sits down into
an open seat by vehicles.cfg `sit`, `ModeBodies.feet_of`; on the riding mower
(vehicles.cfg `pose="sit"`) his model shows its own `sit` key, hips on the
seat and boots out front, where before pass 9 he stood sunk to the chest in it; and the car's
shell hides its driver, `hidden_in_vehicle`: he stood up through its roof
before 3.3.0; a partner and the mirror the same), and no gun, sights, prompts or
HUD. The strip in the status bar's rows names the filter and the buttons
(H, a pad's Y or USE hides it). Filters: PLAIN, FILM (the film look's pass),
and the display shader's `photo_filter` TINTYPE, DUSK, MOONLIGHT (view rows
only, before the palette, so every picture stays in the 256 colours). ENTER,
F12, a click, RT or FIRE saves: the display shader draws the view rows again
into a SubViewport `scale` times 320x156 (filter and all), written to
Pictures/Crazy Legs Mundell Rampage on a computer, else `user://photos`; the
browser build downloads it (`JavaScriptBridge.download_buffer`); headless it
is the software canvas's view rows. ESC, P or MENU leaves.

**KILL CAM** (`src/kill_cam.gd`; PLAY page `kill_cam`: OFF, BOSSES (the
default), BOSSES AND AREAS; never online or with more than one player). Since
pass 10 a boss's fall is not replayed: BOSSES and up show it live as the boss
ending ([bosses.md](bosses.md#the-boss-ending-pass-10)); the replay framed a
giant from a hand's distance (inside Maw, inside the King's fan cage), ran
time backwards and cut in and out hard.

- With BOSSES AND AREAS, while play runs it samples `game.view_frame` `rate`
  times a second of game clock, `keep` seconds of it: copies of the moving
  sprites (the level's fixed sprites are taken as they stand when it plays)
  and each body's pose (kind, heading, gait, height, when it died). It
  listens to `enemy_killed` and only notes a kill: the last of `fight` kills
  in `fight_time` seconds with no foe awake within `area` cells, never a
  boss.
- It starts once `game.slowmo`, `hitstop` and `boss_hold` are all over and
  `delay` more seconds have played: a finishing shot's slow motion that uses
  `game.slowmo` runs first, then the replay.
- The replay shows `before` seconds ahead of the kill to `after` past it at
  `pace`, from a camera `distance` from the body and `height` over its floor,
  swinging `swing` radians round it, placed off the player's line where its
  whole swing is clear of walls. Bodies are stand-in Enemies of its own
  (poses smoothed between samples, falls timed against the frozen clock);
  black bars carry KILL CAM and how to skip. Any key, click, tap or pad
  button skips it. Lost limbs are not shown in the replay.
- Cost (measured in a 1280x800 window while firing, 2026-11-15): one sample
  0.35 to 0.6 ms, taken every other frame at 60 fps (BOSSES AND AREAS only);
  the HUD's Controls 0.03 ms a frame over the old bar.

## The chapter openers (content pass 8)

`src/opener.gd` (`ChapterOpener`, the front end's `opener`) and
`src/opener_art.gd` (`OpenerArt`): before a campaign chapter's first tick a
short cinematic of 15 to 17.5 s, like a 1990s cutscene. PLAY page `openers`:
FIRST TIME (the default; the chapters seen are kept in
`user://openers_seen.json`, not the settings), ALWAYS, OFF.

- **When.** `main_flow.gd play()` offers each game; it is due only for a
  campaign chapter on this machine (the `chapter` test there: not the hub,
  the range, a rematch, a revisit, a player map, COUNTY RUN or online), in
  CAMPAIGN or local CO-OP, at game clock 0 (not a loaded save), not after
  the death screen's retry (`restart_chapter` sets `retrying`), never in a
  tour, bench, smoke run, demo or a tool (unless the tool asks). It starts on
  the next play frame if that game is still the one on screen (the hub that
  `continue_campaign` opens straight after `start()` drops it). Never online:
  the host's game cannot hold still for one machine, and a client joining a
  chapter under way has missed its start anyway.
- **How.** The front end does not tick the game while it plays (as PHOTO
  MODE and the KILL CAM); each frame `game.eye_override` is set to the
  opener's camera only for `game.draw` (no gun, sights or HUD; Mundell is
  left out of the flight and shown only as the camera comes down behind him),
  then cleared, and the variants' draw-time cache of who holds
  a car door (`CACHES`) is put back, so the game starts exactly as it would
  have (`opener_check` compares snapshots, and two seconds of play after it
  with play without one). Any key, click, tap or pad button skips it
  (`main_input.gd`); the click is blocked from firing; the iris opens on play
  after a skip, none after a landing (the picture is already the player's).
- **What.** Authored per chapter in `data/tuning/openers.json`: three shots
  (`secs`, `path` the camera's [x, y, z] keys, `look` the keys of what it
  watches; the older `from`/`to`, `look`/`look_to` pairs still read; `amb`,
  `spots` its sounds), the card style (`plank`,
  `swamp`, `tin`, `marquee`, `checker`, `saucer`: `OpenerArt.STYLES`) and
  tagline, the boss (`cel`, `light`: cone, glow, door, moon, headlights,
  flasher; its colour, growl, sting, line and caption) and the narrator's two
  lines. The title is `Campaign.title_of`, CHAPTER <N> from the campaign's
  order. Shots look best low (z 1 to 3.5) and a few cells from a sign or
  building, never right at it: from high up the levels read as a flat murky
  plane. The card covers the view's top half from 1.7 to 6.8 s: frame what
  the narrator names in the lower half then.
- **The camera** (pass 10, `src/opener_camera.gd`, `OpenerCamera`). Each
  shot's path and look are centripetal Catmull-Rom curves through their keys,
  flown at an even speed along their length (arc-length table) that eases from
  a share of the cruise at the ends (`ease`, default .55; the first shot
  starts from .2); the look runs a little ahead (`LEAD`); the camera leans
  into turns (`BANK`, at most `BANK_MAX` 2.3 degrees: `world_view.gd` rolls the
  camera by the eye's `roll`, 0 everywhere else) and is lifted smoothly over
  any ground or wall top it would skim. After the last shot it drifts to a
  stop (`DRIFT`) while the boss is shown; as the boss's line ends a dip cuts to
  the landing (`LAND` 1.5 s): from a clear spot a little behind and above the
  player (several tried, each flight checked) down into his eye, heading and
  horizon, the dark lifting and the bars drawing back, so play starts from
  the same picture. `clear_at` is the rule `opener_camera_check` holds every
  sample to: never in a wall, roof, deck, door, prop (a picture's reach is
  half its width: a tree's crown) or the ground, nor skimming them. Pass 10
  measured the v3.7.0 paths by the same rule: six of eight hit or skimmed
  walls, props, roofs or doors for 0.3 to 6 s, and every one jolted (a
  velocity change of 9 to 26 cells/s^2 as the boss part began); the
  frames showed the flights starting against Mundell's back, flying through
  a cornfield, a tent wall and a wooden barn, and ending pressed to a wall.
- **The frame.** Black bars (rows 0-13 and 142 on, "ANY KEY SKIPS"), a dip to
  black at each cut, the card dropped in on ropes with a bounce (the B-movie
  title rushes in from big instead), the tagline typed out under it, then
  the view darkens, the light fades in behind the boss's cel drawn as a
  near-black silhouette with a rim of the light, he looms nearer and the
  light flares as he growls; the line said is captioned in the bottom bar
  (VOICE CAPTIONS). Pictures are made once per opener as Images, from the
  game's own letters (three times the body font where the title fits, else
  twice) and cels; their dice are seeded by the chapter's name.
- **Sound** (pass 10, `src/opener_mix.gd`; [audio.md](audio.md#the-openers-sound-pass-10)).
  The chapter's own song from its top is the bed under the whole opener and
  goes on into play; the narrator's first line at 0.55 s on the voice
  channel, his second as the boss is shown, then the boss's growl and its
  boss sting, and its line .75 s after the growl; the schedule follows the
  lines' own lengths. Without the song (a browser pack still coming) the
  pass 8 sting plays and the score is held (`Sound.opener_music`).
- **Tools.** `--opener=<chapter>` plays the chapter with its opener whatever
  the setting (`--opener-data=<file>` from a draft of the file);
  `--opener-out=<dir>` also saves each key moment's window picture
  (`<chapter>_shot<k>.png`, `_card`, `_boss`, `_growl`, `_line`, `_land`) and
  quits; with `--opener-strip=<n>` it saves n frames evenly over the flight
  and three of the landing instead (`<chapter>_f<k>_<seconds>.png`).

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
| `LevelMesh` | `level_mesh.gd` | walls, floors, caps and slopes in 16x16 chunks; per-vertex CUSTOM0 tint + light, CUSTOM1 tile/kind; `build_static(base, only)` builds only some chunks (a wall piece retiled: `LevelData.retiled`) |
| `ViewTiles` | `view_tiles.gd` | the tiles as a Texture2DArray, plus a row of tile info (water, relief, puddles) |
| world shaders | `world.gdshader`, `world_glass.gdshader`, `world_body.gdshaderinc` | solid vs see-through variants of one body via `#define` |
| light include | `view_light.gdshaderinc` | lights, fog, grade, rain, wet, water rings, relief, anim lights, mirror clip, `photo_grade`, `to_output` |
| sky | `sky.gdshader` | the sky behind the eye's camera (`sky_at`: looking well up, past the panorama's top row, it fades into the top's mean colour, `ZENITH_FADE`, instead of smearing that row) |
| sprites | `sprite.gdshader`, `sprite_clear.gdshader`, `sprite_body.gdshaderinc`, `SpriteLayer3D` | camera-facing MultiMesh billboards |
| marks | `mark.gdshader` | wall and ground decals |
| rain | `rain.gdshader` | three camera-hung layers |
| slabs | `SlabLayer3D`, `SlabModels`, `slab.gdshader` | pickups, loose things (brass, gibs, bits) and range targets as pixel slabs (MultiMesh per mesh) |
| solids | `SolidLayer3D`, `solid.gdshader` | sprites with `solid` set (bowling pins, the bowling ball) as real meshes turned by their own `turn` |
| props | `PropLayer3D`, `PropView`, `prop_models.gd`, `prop.gdshader` | modelled props (`PropModels.facing`: which way one stands) |
| wrecks | `WreckLayer3D`, `wreck.gdshader` | broken scenery's real pieces (sprites with `solid` "~<key>#<piece>", cut by `src/wreck_cuts.gd`: [gameplay.md](gameplay.md#in-real-pieces-of-themselves)) |
| shadows | `ViewShadows` (`view_shadows.gd`), `view_light.gdshaderinc` | SHADOWS: what moves throws chunky shadows from the strong lights and a blob from the sky ([below](#shadows)) |
| thing marks | `ThingMarks` (`thing_marks.gd`), `thing_marks.gdshaderinc` | holes, scorch and char on props, vehicles and wreck pieces ([below](#marks-on-modelled-things)) |
| storm | `storm_wall.gdshader`, `world_view.gd _storm` | County Run's storm front: two curtains round the ring, the ground and the world outside it ([below](#county-runs-storm-front)) |
| actors | `ActorLayer3D`, `ActorView`, `actor_models.gd`, `actor.gdshader` | rigged enemies and bosses |
| seat view | `CabLayer3D` (`cab_layer.gd`), `cab.gdshader` | the driver's own vehicle from the seat ([below](#the-seat-view)) |
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
  (limit 10; the most now is actor.gdshader's 8, `view_data` among them).
  Stack new data into an existing texture instead of adding one.
- **A number the view sets each frame is a global uniform** (`global
  uniform` in the shader, in `project.godot [shader_globals]` with the same
  type, in `WorldView3D.GLOBALS`), a list a row of `view_data`; never a
  material's own uniform handed to every material each frame
  ([below](#keeping-the-frame-cheap-track-r-before-v330)).
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

Each prop placed with `town()` (and every quest station) shows as a
`PropView` scene (`scenes/props/<name>.tscn`) over its baked glTF model: 228
models, for 253 of the 257 `town_*` pictures and the shop lamp (the range's four targets stay
pictures). The pipeline that makes them is in [art.md](art.md#props). A light
with `props` in effects.cfg rides every prop with that picture.

A sprite shown taller or shorter than its picture was drawn (the level's
`height` against `town_props.json`, kept in meshes.json) stands its model
scaled to match (`PropModels.scale_of`), as the billboard was: the
speedway's booth PA rig is half size, Hickston's range scoreboard 1.5x.

A quest station's two pictures (`town_quest_<name>_off`, `_on`) are one
model with two looks (`look_off`, `look_on`); `PropView.show_look` shows the
one the picture names, so a station switches look where it stands.

A prop on the move (`View.Sprite.track`, a name it keeps: a boss arena's
wreck, `features/arena_wreck.gd`) is one model stood again each frame at the
sprite's place, turned the way it first stood and then by `turn` (map axes)
about its feet (`PropView.carry`): a floodlight tower going over, a vat on
its side, a wreck flung across the bowl.

A picture not named `town_*` may stand for a model too
(`PropModels.PICTURES`): the hanging shop lamp `prop_lamp` (game.gd hangs it
under a roof; a boss arena drops it) is the `shop_lamp` model, so it hangs,
falls and lies in 3D.

A prop's facing is worked out once for where it stands (the most open way),
unless its sprite sets `plane`: then the model turns by `-plane`. A quest
prop's sprite sets `face` (`game_combat.gd _station_face`): the way to its
station's (or the exit's) own point, where it is used from; the model turns
so that from there it shows the three-quarter view its picture had
(`PropLayer3D.PICTURE_TURN`). Where that point is the prop's own spot it
takes the most open way. Only looks: where the player aims and what USE
reaches are the same as before (`quest_reach`). A moving
prop (the speedway's lap cars, `race_laps.gd`) sets `plane` from its heading,
so it faces where it runs; it is stood again each frame it moves.

## The seat view

`CabLayer3D` draws what a driver sees of their own vehicle (the frame's
`eye["cab"]` from `src/vehicle_cab.gd`: model, turn in map axes, `lift` from
the eye at full size, each moving part's turn) from
`assets3d/cabs/<model>.glb` (meshes `look_<part>`, one baked texture
`mesh_<model>`) and `cabs.json` (each part's pivot and axis in Blender's
axes; a hand rides another part: it goes round with the wheel or stick and
its wrist takes only `turn` of it, so the forearm does not sweep the view).

- **Shrunk toward the eye**: the whole cab is drawn `SHRINK` (.1) of its
  size about the eye, so it looks the same size but sits nearer than any
  wall can come (a hull keeps walls .45 or more from the eye; the farthest
  part, the airboat's bow, is at .3) and further than the camera's near
  plane (.02): it never cuts into a wall or hides behind one, and whatever
  of the road it does not cover shows. `cab.gdshader` (a prop's light) works
  its distance and place at full size (`/ shrink`), so it is lit as the
  vehicle would be, by the cell the driver sits in (its light no nearer
  than `LIGHT_NEAR` and never over full, so pale paint does not burn
  white). A part with `fade` below 1 (the airboat's prop and its blur disc)
  leaves out an ordered 4x4 stipple of its pixels (`opacity`), the world
  showing through: a 1997 blur, no blending.
- **Its own layer** (`LAYER` 8): the eye's camera draws it, the mirror's
  camera does not.
- **The old view's height** is narrow (37 degrees at FIELD OF VIEW 70): a
  driver's view is widened (`eye["wide"]`, below) and each kind sits its eye
  lower in its cab (`cab_drop`) and tips it nose up a little (`cab_tilt`),
  so the hood, rails and controls show while the nose stays a few degrees
  under the horizon.
- **Widening** (`eye["wide"]`, below 1): `_place_camera` widens the frustum
  about the view's middle (the aim's way, `horizon` kept), and the shaders'
  `focal` and `horizon` follow, so the sky lines up; the crosshair still
  aims where it shoots. Overlays the canvas places from `View.focal` (the
  objective pin's arrow) are a few pixels off while it is wide.
- Hiding the driver's own model (`features/vehicles.gd sprites`) is play's
  job: the layer only draws the cab.
- **The car's passenger** (feature pass 7) sees the same cab from their
  seat: `VehicleCab.dress` moves its `lift` `ride_side` to the left (the
  eye sits right of the wheel), and the car's shell is left out of their
  view too. The car's hands are parts with a `fade` like the prop: the
  right one goes (0) while its driver's gun is out of the window, both with
  nobody at the wheel (a part's `fade` is set every frame: a part left out
  of it keeps the last one).

## Solid bodies

A `View.Sprite` with `solid` set ("pin", "ball") is drawn by
`SolidLayer3D` as a mesh standing at the sprite's (x, y, z), turned by its
`turn` (a `Basis` in map axes, z up; `godot_basis` swaps to Godot's y up).
The meshes are built in code at start: a pin turned on a lathe from a real
pin's profile with its two red neck stripes (drawn `CHUNK` 1.12 stouter, as
the old picture was), a ball with three finger holes and a swirl. Faces
carry their material in UV.x; `solid.gdshader` colours them from its
`PAINT` table, shades the round sides in three steps of a key light from
above and lights, fogs and palettes them as the sprites are. The range's
pins come from `range_bowling.gd`'s `sprites` (turn from each pin's
quaternion); a bowling ball shot anywhere is drawn so by `Shots.ball_look`
(rolled by its `travelled` about the line across its way).

The newer kinds are built by `SolidKit` (`view3d/solid_kit.gd`) the first
time one is seen, from the same numbers the play uses
(`src/range_games_shape.gd`): a horseshoe and its stake, the skee-ball
cabinet (maple lane, rubber hump, the ring board with its 10 to 50 rings and
100 cups, the red cabinet and its bulbs) and its balls, a milk bottle, a
softball, the dunk tank, its seat and its bullseye, and the fair's tin can,
gallery rail, prize shelf, straw hat, beer and start bell, and the trophy
shack's plinth and plaque. Their faces carry their own colour, not a PAINT
material: UV.x is -1 (matte) or -2 (shiny) and UV.y the colour packed as
r * 65536 + g * 256 + b (`solid.gdshader`). `SolidKit.tri` winds every face
clockwise seen from its front, Godot's front face. A sprite's `turn` may
scale (a rail or a shelf is one cell long, stretched by its turn).

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
    its floor (`View.Sprite.lying`) with a `settle` (seconds down, kept by
    its feature) it eases over from the turn it came down at onto its nearer
    face in `SETTLE`, rocks a little (`ROCK`, `ROCK_RATE`, `ROCK_DAMP`, over
    by `ROCK_TIME`), a round thing turned about its length by `roll`, and
    lies propped `PROP` (.1 to .45 rad, by a smooth sum of its place) so it
    still reads from a standing eye (`settled()`; `turn_of()` is the whole
    turn, the checks use it). With no settle (-1) it lies flat at once, as
    before. Either way its lowest corner is on the sprite's z and its middle
    over its x, y, as the turned billboard's was.
  - A target stands on its foot along its `plane` (the lanes' boards, gongs
    and cows face the firing line, south), turned round when flipped (a
    gallery mover going the other way shows its back), and leans back about
    its foot by `View.Sprite.tilt`. `range_targets.gd` sets it: a board or a
    cow spins on its stand when hit (its `plane`, as before); a gong's plate
    swings from the bar (`GONG_SWING`, `GONG_REACH`; the frame stays put); a
    gallery mover wobbles on its stick as it rides (`MOVER_WOBBLE`, less with
    EASY ON THE EYES, none when STILL), spins round on its stick when it
    turns at its rail's end (over its first `MOVER_TURN` cells back, edge on
    halfway, then its other face) and, knocked down, goes over flat
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
  (and any motion of five keys in a row, a letter and the beat,
  `ActorView.is_run`: the hound's gallop, trot, idle, shake and the rest)
  interpolated on gait (a body that plays one through once, the hound going
  down, is handed a gait short of its last key); a living
  body shown in a step of a fall it never took (`ActorView.held`: a hand
  the hound drags down) holds that step's key, falls on time since death.
- Looks-only motion over the keys (polish pass 9; none of it reads or
  spends `game.rng`, its dice are hashes of the body's uid and the moment):
  a jump between frames that are not neighbours in the action (idle to aim,
  aim to fire, pain, walking to standing, a hurt look's frames, the fall's
  start) blends every bone over `BLEND` (.13 s; `BLEND_SNAP` .06 into fire
  and pain; a kind's fit.json `blend`, the hound's .2, his poses being far
  apart) instead of snapping (`ActorView.group_of`: the walk's beats, a
  motion's and the fall's steps are one group each and never blend, the
  flapping bugs and saucers not at all). A hit rocks the living body about
  its feet for `FLINCH` (.34 s) by `Enemy.last_zone` and `last_side`: a head
  shot snaps it back, the body rocks and twists, an arm turns the shoulders,
  a leg buckles it forward and down, sized by `struck_sum`, a boss at .4.
  Standing idle (`0`) it breathes and sways a touch. A scripted fall (RAGDOLLS
  off, or a kind with no ragdoll) is mirrored for about half the deaths (not
  a boss's set piece, a tipping cow or a `down_cel` kind) and runs up to
  `FALL_QUICK` (18%) quicker. The Swamp King and Maw's bare model, kinds with
  their own frame lists, now have the walk's closing `w4` key too
  (export_actors.py `_frames`), so their walks run smoothly instead of
  snapping beat to beat. `tools/actor_check.gd` holds all of it.
- Thrown specks (`game.specks`: blood, sparks, grit) are `View.SPECK` (.095)
  tall but drawn between `SPECK_PX_MIN` (1.6) and `SPECK_PX_MAX` (6) of the
  view's pixels (`View.speck_size`): far off they winked out under a pixel,
  right in front one was a blot a tenth of the view across.
- The look (plain, hurt, p2, p3) is picked by health and boss phase.
- Lost limbs are left off (`Gore.lost`), and a boss's gear shot off
  (`features/boss_gear.gd`, the frame's `gear_lost`; `ActorView.lose_gear`
  shrinks the gear's bones, actors.json "gear"). The piece itself is a
  `View.Sprite` with `gear` (and `who` the boss): `ActorLayer3D.show_gear`
  draws it as a mesh cut from the model's rest frame
  (`ActorModels.gear_mesh`, the triangles bound to the gear's bones), at the
  boss's size, turned by `turn`, with the boss's look.
- Bones are labelled head, arm_r, arm_l, leg_r, leg_l, body.
- A picture name's `~r.g.b` tint (`Assets.tinted_art`) tints the model too.
- A dead body of a kind with a ragdoll rig (`RagdollRig`, not a boss, not
  fit.json `"ragdoll": false`, RAGDOLLS on) is posed from its ragdoll
  (`src/ragdoll.gd`): started from the pose it died in (or the model's own
  "down" when first seen long dead, settled at once), thrown by the kill,
  stepped as the view draws (`advance`, capped by effects.cfg `[ragdoll]
  budget` across all of them) and each part turned with its segment
  (`RagdollRig.pose`); the model is not flattened and its AnimationPlayer
  is not sought. `ActorLayer3D` keeps a body's ragdoll while it is out of
  sight (`KEEP_DOLLS`). See [gameplay.md](gameplay.md#ragdolls-and-finishing-shots-v320).
- Otherwise a body falling and at rest is drawn flatter, down to `FLAT` (.5)
  of its height at rest: its cel was a flat picture a quarter of the body's
  height, and the whole body lying belly and boots up read as a heap.
- `assets3d/actors/fit.json` (by hand; merged into actors.json's entries by
  `ActorModels`) fits a kind to its cels: `light` multiplies its looks (the
  models were 5 to 30% darker than their cels, measured old against new on a
  dry dusk tour; the bake's light and crease shade), `scale` sizes it (the
  derby champ .85: his truck's near end comes much closer to the eye than
  the billboard cel through its middle did), and `min_px` (the crawler, 1.5)
  pushes every surface out along its normal by half that many of the view's
  pixels at its distance (nothing up close), so thin legs keep about a pixel
  at range as the cel's lines did. `flat` sets how flat a dead body of the
  kind lies (FLAT otherwise; the cow 1: her legs stuck out). `tips` (the
  cow, .19: the hooves' half width) rolls a living body over sideways by the
  lean its `squash` holds (critters.gd: the lean's cosine) on the hooves of
  the side it lies on `down` (`ActorView.tipped`): a tipped cow goes over
  rigid, lies on her side with her stiff legs out, and gets up again.
  `down_cel` keeps the old cel for the body
  at rest where that is a build of its own the model's parts cannot make
  (the derby champ's burnt-out wreck, the swamp king's sunk boat, the Maw):
  `ActorLayer3D.takes()`.
- Bodies that are not enemies can wear a model through a stand-in Enemy that
  only the view reads: the 5v5 players and hostages (`ModeBodies`,
  [modes.md](modes.md#rounds)), and every other player outside the 5v5
  rounds and the player in the mirror as Mundell's model, `mundell`
  ([modes.md](modes.md#presentation)). A sprite's `pose` names the model's
  frame when it is not the picture's (the player pictures have no aim, fire
  or fall cels).

The pipeline is in [art.md](art.md#actors).

## Checks

- `tools/view3d_check.gd` builds every level's mesh headless, loads every
  prop and actor scene (a station's with both looks; every
  `town_quest_*` picture must have its model) and builds every slab
  (pickups, loose things, range targets; a gong with its plate), holding its
  front to the picture's size and place; it also holds the tiles' mip levels
  (a glow kept whole), the moon's rim to the night chapter and the blackout,
  and `night_contrast.gd`'s measure to a known figure (VIEW3D CHECK OK; in
  check_all and CI).
- `tools/check_shader.gd` counts textures (SHADER OK).
- `tools/view_perf_check.gd` holds the frame cheap (VIEW PERF CHECK OK): the
  global uniforms against `project.godot` and the shaders, no uniform
  arrays, no frame number handed to a material; turning round Hickston's
  spawn with its hands awake, the later turns make no prop or model again,
  nothing past where it shows gets one, the instance buffer stays in its
  room; and the view's `frame()` (headless, its lower quartile) under 1.2
  times a yardstick of plain GDScript timed beside it (0.4 to 0.7 here).
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

**Weather you can feel** (track H): `view_light.gdshaderinc` takes `pool`
(the puddles' water: more and bigger puddles, `world_body.gdshaderinc`, and
denser rain rings) and `wind_now` (the climate's wind, xy, and its gusting,
z). `rain.gdshader` slants the streaks with the wind across the view;
`prop.gdshader` sways the props effects.cfg `[sway]` names (`sway_k`, set per
model by `prop_layer.gd` with the model's height and width): trees, flags
and scarecrows bend from the ground, laundry, a hanging sign or a crane hook
swing from their top (the posts at the ends stay), stilled by SCENERY MOTION.

### County Run's storm front

(Track L, after v3.2.0.) `world_view.gd _storm` stands two open cylinders
round the safe ground ([county_run.md](county_run.md#the-storm-front)),
30 cells tall from just under the ground at the ring's middle: the front
curtain at the ring and a second `OUTER_STORM` (2.5) cells behind it, so the
wall has depth as the eye moves (drawn back to front: the order swaps when the
eye is out in the storm). `storm_wall.gdshader` (see-through, its own shader,
`layer_k` 0 or 1) draws each as a dark curtain in four dithered steps
(`dither_of`: within 5 to 11 units the steps break along streaks of rain a
fourteenth of a cell wide hung on the curtain itself, falling with the wind;
further, a soft grain of the 320-wide pixels; until 3.3.0 a 2x2 ordered
pattern of screen pixels, which read as a fine screen door up close and in
HD; `docs/godot3d/optimize/S/storm_*`): shafts
of rain hanging down it over great rolls of cloud, swaying and carried round
with the wind (`storm_k`, CountyStorm.strength), darkest at its foot where it
kicks up brown dirt, its crown lit pale where it thins into the sky; lightning
flickers inside it (a patch at a time on its own beat, lighting the billows
from within, a fork at the peaks) and boards, tin and hay fly round in the
front curtain as black silhouettes. `storm_ring` (the ring's middle, radius
and strength; 0 with no storm) goes to every shader: `surface_light` darkens
whatever stands out past the wall and veils each surface by how far the eye's
line runs through the storm (`storm_veil`, toward `STORM_FOG`); the floors
(`world_body.gdshaderinc storm_ground`) are soaked dark from four cells
inside the wall on out, with a ragged line of churned dirt clods where it
stands; out in the storm the sky turns to its dark roof (`sky.gdshader`).
EASY ON THE EYES slows it all (`motion`) and STILL freezes it, flickers and
debris included; `storm_rich` (LIGHTS AND GLOW on and VIEW DETAIL above LOW,
so off on QUALITY LOW) keeps one plain curtain otherwise, and the veil, the
dimming and the ground need LIGHTS AND GLOW. Pictures:
`docs/godot3d/polish/L/storm_*.png`.

### Shadows

SHADOWS (VIEW page, `shadows`, on; `View.shadows`, set in `main_state.gd
apply_options`; QUALITY LOW turns it off; needs LIGHTS AND GLOW). Each frame
`ViewShadows.collect` makes bodies of what is drawn, a segment with a radius:
the actors (enemies, other players, bosses; a dead body lies along its
heading), this machine's player (not in PHOTO MODE), props on the move
(thrown, carried, an arena's wreck flung), the vehicles drawn (along their
heading) and the four nearest wreck pieces; the `MOST_BODIES` (12) nearest
the eye within `REACH` (22) are kept. `pair()` matches them with this frame's
lights (Game.effect_lights(), in the order the shaders get them): a light of
strength times radius `STRONG` (.6) or more, the body within .9 of its reach
and not its own (closer than its radius plus `OWN_LIGHT`: the shooter's
muzzle flash, the fire it burns in); the `MOST_PAIRS` (16) that matter most go
to the floors, walls and marks only (`world_view.gd _share_shadows`: a body
would shadow itself). `lights_at` tests each floor and wall block (a grid of
`SHADOW_GRID` 10 blocks a cell, the soft edge dithered 2x2 on that grid: a
1997 low-res shadow map) against the pairs: in a body's shadow the light keeps
`SHADOW_LEFT` of its light and the surface's own light loses up to
`SHADOW_DIM` by the light's strength and nearness. Every body also lays a
blob on the floor under it from the sky (`blobs`, at most 12, smaller and
gone as it rises; `BLOB_DARK`). No Forward+ features: plain uniform arrays
in the gl_compatibility shaders, no new texture. Cost (`--view-bench=300`,
back to back on the noisy desktop, with the marks below): 6.51 ms before,
6.76 after (the whole 3D view, mean of two runs each). Pictures:
`docs/godot3d/polish/L/shadows_on.png`, `shadows_off.png`.

### Marks on modelled things

Bullet holes, scorch and char stay on props (PropView), vehicles (props too)
and wreck pieces as wall marks do on walls (`ThingMarks`, `thing_marks.gd`).
`features/impacts.gd` keeps the latest marking shots (the guns that hole
walls, BULLET MARKS on) and blasts in `thing_hits` ([serial, from, to]; a
blast's from and to are the same); each frame the view takes the new ones:
a shot's line from the gun to where it ended is met with the nearby parts'
own triangles (`TriangleMesh`, made once a mesh) and the first part hit gets a
hole there; a blast scorches the side facing it of up to eight parts within
`BLAST_REACH`. A mark is kept in the part's own space (`marks` meta, at most
six, the oldest going), so it moves with a carried, thrown or flung thing and
a driving car, and handed to `thing_marks.gdshaderinc` (`mark0`..`mark5`:
place and kind*10 + radius; drawn in chunky blocks: a black core, a dark rim,
flecks of the bare stuff; or soot). Char (`char_k`) comes from
`features/fire.gd`: what stands in a burning cell chars to `CHAR_BURNING`, in
a burnt-out one to `CHAR_BURNT`; a vehicle burning out `CHAR_WRECK`, one badly
hurt `CHAR_HURT`. `PropLayer3D` keeps the marks of props gone out of view
(`KEEP`, by key) and hands a gone prop's marks to one of its model made again
within `REMADE` cells (a car stood again at its next place, a thrown thing
landing, a breakable showing its struck picture); at most `MOST_MARKED` (64)
parts carry marks. Looks only. Pictures: `docs/godot3d/polish/L/marks_*.png`.

A tour viewpoint may set `map`/`map_zoom`, `gun`/`fire`/`ticks`, `rain`,
`wet`, `lightning`, `actors` (to show the 3D models), `cels` (true: enemies
drawn as their old cels instead, for old-against-new sheets), `motion`
(EASY ON THE EYES: 0 full, the default, 1 reduced, 2 still), `blackout`
(true: the county blackout begun and faded in, the flashlight on) and
`contrast` (a floor: the view is drawn again without its `actors` and
`compare_3d.gd` holds how well they read, [checks.md](checks.md#picture-references)). A tour or bench
keeps drawing when its window loses the focus.

## Night and surfaces (polish pass 9)

**Tile mip levels.** `ViewTiles` gives every tile its mip levels (64x64 down
to 1x1, a 2x2 box average; a glowing texel's glow goes down as the least
alpha of its four, so a lit window far off still lights itself). The world
shader reads them with `texelFetch` at the level `tile_lod` picks from the
screen derivatives of the texel coordinates (`world_body.gdshaderinc`: 0
until a view pixel spans two texels, one level more each time it spans twice
as many; the larger axis, so a road seen low settles too), as Quake's
software renderer stepped its mips. Up close nothing changes; far walls and
floors keep their colour instead of crawling. Measured on the tour's still
viewpoints (each drawn again a 0.06-cell step ahead, mean |dL*| of the whole
3D view, the frame-to-frame crawl): median 3.14 before, 1.90 after (mean 3.10
to 2.16); the worst, the speedway's figure 8 stands, 7.3 to 7.1, the
Crossroads hedge 7.1 to 4.2. The view's look (grain, dither, palette) is
unchanged. A chain-link wall's holes (`mesh_hole`) are still cut at full size.

**The moon's rim.** By night what stands in the dark catches the sky's light
along its edges: `moon_rim` (`view_light.gdshaderinc`, rgb a colour, a how
strong) is a level's own (effects.cfg `[level.moonshine] moon_rim`, the
night chapter) plus, in a county blackout, events.cfg `[blackout] moon_rim`
times how far the power has gone (`world_view.gd _moon_rim`). An actor
(`actor.gdshader`) adds it on its silhouette's edge (normals turned away
from the eye, most along the top, less on a body lying down) and a pickup's
slab (`SpriteLayer3D.ITEM`, `sprite_body.gdshaderinc`) on its picture's edge
texels at two thirds, and holds a body's floor of light; both in thirds
(`moon_rim_on`), thinned by the fog's share (`fog_share`, the same sum
`surface_light` fogs by) and the storm's veil, never darkened by the
blackout, only with LIGHTS AND GLOW. Elsewhere `moon_rim` is 0 and nothing
changes (the actors keep their cels' look). Measured with
`tools/night_frames.gd` (below), mean |dL*| of each enemy against what it
hides in the finished frame: Copperhead Ridge's gas man at 9 cells 5.9 to
8.2, a revenooer at 9 cells 4.0 to 6.7, a skeeter at 9 cells 3.0 to 4.6; the
blackout's hand just off the beam 2.3 to 4.4; the ridge's arm gun ammo at 3
cells 2.4 to 13.7. The night stays dark: the backgrounds keep L* 2 to 10.

**Audit pictures.** `tools/night_frames.gd` (a window, scratch APPDATA)
stands each chapter's own hands where the level puts them, seen from 4 and 9
cells, a few pickups from 3 and 6, and a blackout's hand in, at the edge of
and out of the flashlight's beam, each drawn with and without it; it prints
the mean L* of the figure, of what it hides and the mean |dL*| (CIE L*,
`tools/night_contrast.gd`) and where it stood. Before this pass the whole
game read 5 to 8 at 9 cells by day (the dusk palette) and 4 to 7 on the
ridge, its pickups 2 to 3.

## Keeping the frame cheap (track R, before v3.3.0)

What the view does each frame is GDScript on the main thread, so on a phone
or in the browser it is most of the frame. `WorldView3D.parts_us` times
`frame()` in parts (setup, shadows, props, wrecks, marks, actors, glue,
sprites, slabs, decals, uniforms); `--view-bench` and
`tools/stress_bench.gd` print them ([checks.md](checks.md#benchmarks)).
Rules that keep it cheap, none of which changes a picture:

- **No file checks per frame.** `ResourceLoader.exists` costs tens of
  microseconds; `PropModels.name_of` (asked for every sprite every frame) and
  `ActorModels.has` keep their answers (a picture's model name by its text,
  whether a scene exists by name; the art is still asked each time, as a
  chapter's pack may arrive later in the browser).
- **Models out of view are parked, not made again** (pass 10). A body
  leaving the view hides its `ActorView` under its own id
  (`ActorLayer3D._parked`, at most `PARK` 24); coming back it gets that model
  again, a new body the oldest parked one of its kind, and either is posed
  afresh (`ActorView.revive`, as a model just made). Props the same: a prop
  leaving the view is hidden under its key (`PropLayer3D._parked`, at most
  `PARK` 64) and shown again as it was, its marks on it, lit by its cell's
  light now (`PropView.light_again`); one let go of keeps its marks by key
  (`_kept`) as before. A hidden part still holds its block of the shader
  instance buffer (below), so both park only in the room left
  (`WorldView3D._park_room`: actors first, a model costing about ten times a
  prop to make). The view-bench's turn made 1.6 models and 7.5 props a frame
  before; `view_perf_check` holds a second turn round Hickston to none.
- **Nothing is made or posed past where it shows.** A model's parts end at
  its `visibility_range_end` (`ActorView.REACH` 32 cells; a prop 32, 51 when
  tall), but the game lists bodies to 54 cells ahead and sprites to 51: a
  living body past `REACH` and `ActorLayer3D.BEYOND` (5) is given no model
  and not posed, a prop past its reach and half its breadth and
  `PropLayer3D.BEYOND` (1) is not stood. The dead are posed as before (their
  ragdolls keep falling).
- **Posed only when the pose changes.** `ActorView` seeks its
  AnimationPlayer only when the action time changed (a seek is 25 to 70 us;
  idle bodies hold a frame), sets its four instance numbers only when they
  changed, keeps `pose_of`'s answers by picture and its frame's keys
  (`_keys`) until the frame changes.
- **Far bodies are posed every other frame**: past `ActorView.LOD_HIGH` (16
  cells, times the body's height, further in HD or a narrower FIELD OF
  VIEW: there a body is 14 of the view's pixels tall or less and its limbs
  move under half a pixel a frame), staggered by body; with VIEW DETAIL LOW
  (QUALITY LOW) past `LOD_NEAR` (10) every other frame and past `LOD_FAR`
  (20) every third. A change of action (aim, fire, pain, a fall) is posed at
  once; every body still moves every frame.
- **The frame's numbers are global uniforms** (pass 10). The eye, angle,
  horizon, clock, weather, fog, storm and the rest (`WorldView3D.GLOBALS`,
  declared `global uniform` in `view_light.gdshaderinc`, `world_body` and
  `storm_wall`, registered in `project.godot [shader_globals]`) are set once
  a frame with `RenderingServer.global_shader_parameter_set`; the frame's
  lists (the lights' places, colours and flags, the wading rings, the moving
  tiles, SHADOWS' pairs and blobs, the flowing floors) are rows of one small
  RGBA32F texture, `view_data` (`view_row()`; a light's flags as two 16-bit
  halves, as a float holds them exactly), uploaded once a frame when a row
  changed. So no material changes from frame to frame: before, `_share`
  handed seven or so changed numbers to each of the 80-odd materials drawn
  lately (`_track_live`, still used for the textures a material is given
  once), and the renderer rebuilt each one's uniforms: 0.5 to 0.9 ms a frame.
  SHADOWS' counts stay the floors', walls' and marks' own uniforms (a body
  would shadow itself). A new per-frame number goes in all three places
  (the shader, `project.godot`, `GLOBALS`); `view_perf_check` holds them
  together and fails on a uniform array in a view3d shader.
- **MultiMeshes are filled in one call.** The sprites', slabs' and solids'
  rows are written in place in the MultiMesh's own layout
  (`SpriteLayer3D.put`; the sprites' buffer sized once a frame,
  `put_at`) and handed over with `RenderingServer.multimesh_set_buffer`, not
  three calls an instance from a Packed array made per row.
- **A sprite's picture is sorted once.** Whether a picture is drawn as a
  prop's model, a slab (its family) or a picture is kept by picture
  (`WorldView3D._picture_kind`; a model whose art is still coming is asked
  again), and `SlabModels.family`, `ActorModels.has` and a picture's size
  keep their answers.
- **An opened cell rebuilds only its chunks.** `LevelData.open_cell` (a plank
  wall or fence broken through, a shed's wall opened) counts `reshapes` and
  lists the points it changed in `reshaped`; `WorldView3D._reshape` builds
  only those chunks again and patches the cell texture's pixels (3.4 ms a
  wall against 59 for the whole level, desktop). Anything else that changes
  the walls (the 5v5 cover standing again) still rebuilds all.
  `view3d_check` holds the chunks to what a whole build makes.
- **Shader instance numbers are a budget.** Every model part with instance
  uniforms (props, wreck pieces, actors, seat views), shown or hidden, holds
  a block of 16 vec4 slots of one global buffer whatever its shader uses
  (Godot's fixed block; measured in pass 10: 256 parts filled 4096 slots,
  with prop.gdshader's 8 numbers or cab.gdshader's 2), after the 44 global
  uniforms: 4096 slots on this desktop, room for
  `WorldView3D.INSTANCE_PARTS` 250 parts; 1024 where a uniform block holds
  16 KB (WebGL2's minimum, many phones), room for `INSTANCE_PARTS_SMALL` 60.
  Past it Godot prints "Too many instances using shader instance variables"
  and those parts draw black. Before pass 10 the slots were counted as the
  numbers used (8 a prop, 4 an actor), and the heavy stress scenes' 500 to
  800 "slots" were in fact 60 to 110 parts: over 60 on a small buffer (not
  checked on a phone or in the browser). `stress_bench` prints `instance
  parts` held; the parks above keep `INSTANCE_SPARE` (40) parts free. A next
  step would give unmarked parts no instance uniforms at all (the tone from
  the cell texture, marks only on the parts marked).

## The warm-up (polish pass 9)

gl_compatibility compiles a shader the first time something draws with it,
and a model's first instance and texture cost several milliseconds. On a
desktop or phone the compiled shaders are kept after the first run; the
browser keeps none, so it pays every time. What the view does about it at a
level's first frame (the frame that already builds the level, behind the
load or the chapter's opener):

- `_warm_models`: makes now what the level may show later: the props it
  stands (its billboards and props: each scene loaded and instanced once,
  its texture made, `PropLayer3D.warm`), the county events' hogs and raiders
  (`ActorLayer3D.warm`), its vehicles' seat views, hidden (`CabLayer3D.warm`).
- `warm_up`: for `WARM_FRAMES` (2) frames, everything hidden till something
  calls for it (the twister, County Run's storm wall, the rain, the seat
  views) is drawn as a speck 40 cells ahead (`SPECK_AWAY`), a ten-thousandth
  of its size (`SPECK`); `_unwarm` puts each back at the next frame's
  start. Nothing shows: the speck covers no pixel (a first try, a
  thousandth of the size just past the near plane, showed three pixels in
  the middle of the 320x156 view).

Measured with `tools/hitch_bench.gd` (desktop, cold shader cache, medians of
three runs, 2026-11-17; the PC busy, so the settled frames ran 11 to 18 ms):
a turn round at Hickston's spawn 106 -> 35 ms; getting in the mower
171 -> 48; the twister's first frame 44 -> 23 (619 in a first run); a barn
coming down 36 -> 21; the hogs 87 -> 67. Hickston's first frame costs about
0.37 s more the first time (the props), nothing the second.
`tools/warm_check.gd` holds it. Still to do: the hogs' first frame (about
40 ms outside the tick and the view's frame: the GPU side), getting in a
vehicle (the view's setup, 15 to 20 ms), a whole yard of props coming into
view at once for the first time (each a new instance; back in view they are
parked ones, above).

## Loading and the warm-up, pass 10 (PERFLOAD)

Measured with `--view-bench` (each chapter's `load` line: `start()` and the
first frame) and `tools/hitch_bench.gd`; the numbers are in
[checks.md](checks.md#measured-in-pass-10-perfload).

- **The title's warm-up** (`WorldView3D.warm_title`, driven by
  `main_state.gd` `warm_view` once a menu has been up `TITLE_WARM_AFTER`
  seconds before the first level): the 3D view is made (0.18 s the first
  level's load paid) and every view3d shader is drawn once, a piece a
  frame, into the viewport nobody sees yet: a quad with each shader's
  material, the sprites', slabs' and solids' in one-instance MultiMeshes as
  they draw; the sky draws itself. Then every pickup's slab mesh is built,
  eight a frame. In the browser (which keeps no compiled shaders) the first
  level's first frame was 10 s of compiling; it now happens under the
  title. A level started before it ends compiles the rest as before.
  `--view-bench` runs it first and prints it as `TITLE`.
- **Models load on the loader's threads**: at a level's first frame the
  view asks `ResourceLoader.load_threaded_request` for its props' and
  enemies' scenes (`PropModels.request`, `ActorModels.request`) before
  building the level's mesh, and `scene()` takes each (waiting if it must).
  Every one asked for is taken in that frame (`ActorLayer3D.prepare` takes
  every enemy kind's, a boss's too). Not with sub-threads: those left 220
  objects behind at exit. Not headless: the dummy renderer's meshes are not
  made safely from two threads at once.
- **Ragdoll rigs are baked** (`assets3d/actors/<kind>.rig`,
  `tools/art/bake_rigs.gd`): `RagdollRig.of` reads the points, radii, parts
  and hull back and makes the poses from the model (35 to 100 ms a kind
  found from the vertices, under 1 ms read). A file made from other
  actors.json labels or keys is not used. `RagdollRig.found` counts rigs
  found from vertices (a level's load finds none).
- **A hog and a raider are made and kept hidden** at the first frame
  (`ActorLayer3D.warm`; not parked, so it takes none of the parking's room but
  its own slot, `held()`, and the first body of its kind takes it) and drawn once by `warm_up`
  (`warm_roots`): the herd's first frame had paid the model's first draw
  (35 -> 19 ms). Every pickup the level holds has its slab mesh built then
  too (`SlabLayer3D.warm`): a turn at Hickston's spawn built eleven
  (10 -> 6 ms), getting in the mower eight (17 -> 10).
- **A model's looks are not kept twice**: its texture is made from
  `Assets.art_for_texture`, which keeps no copy of the pixels (128 of the
  516 MB held after the eight chapters), and a wrecked prop's pieces share
  the prop's own texture (`WreckLayer3D.prop_models`).

`tools/load_speed_check.gd` holds all of it. Still to do: a yard of props
coming into view at once (each a new instance; props are not pooled, see
"Keeping the frame cheap"), the script compiling at boot (4.5 s in the
project folder, about 1.5 s in the browser build: every script loads with
main.gd and Godot compiles them one at a time), the level's mesh built
again on a retry.

## User folder

The 3D build uses its own user folder ("Crazy Legs Mundell Rampage 3D"), so it
never shares a profile with the published game.
