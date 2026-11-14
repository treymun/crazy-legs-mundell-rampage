# Stage 1 survey (dev.45 code, before the rewrite)

Paths are under `godot/src/`. Line numbers are dev.45's.

## The layer chains

Front end (all fields in main_state; upper layers add no fields):
- `main_state.gd` (1376, extends Control): settings, window/letterbox, save-slot
  lists, pad bindings, the plain menus (replays, controls, credits, setup,
  slots), the shader overlay (`_start_overlay`), `render()` (the state
  dispatcher), the start-up view check.
- `main_flow.gd` (1074): level flow (start, play, `_take_mode`), showdown /
  match / county starts, hub travel, campaign continue, title actions
  (`menu_action`), save/load, settings pages, fullscreen, level reload, the
  network lifecycle.
- `main_input.gd` (1398): the key router `key()` and one handler per state,
  `_input`, menu wheel/touch/drag/hover/click, gamepad `read_pad`/`_pad_menu`,
  touch buttons, `_controls()` (builds Game.Controls), online keys.
- `main.gd` (957): `_ready` (nodes, shader, headless server or lobby
  branches), tool modes (tours, benches, launch check), `_process`, `advance`
  (fixed 1/120 s steps), net frame / host tick / aim.

Play (all fields in game_state; upper layers add none):
- `game_state.gd` (1283, RefCounted): tables (PROP_HEIGHTS, PICKUP_NAMES, AMMO,
  REACTIONS), inner classes Rng, Shot, Speck, Blast, Hazard, Barks, Cheats,
  Gallery, Controls; every field; `focus`, `defeated`, `take_uid`, `pooled`.
- `game_world.gd` (1410): loadout/configure, message and sound placement,
  damage, pickups (add_pickup, collect), use_item, move_actor, enemy_down,
  face, use_target/interact, stations, exit/finish_level, hub gates,
  toggle_door, burst, objective text and route.
- `game_combat.gd` (1112): launch, dynamite, hitscan, wall strikes, aim
  assist, explode, blast shoves, shots (move, roll, hits, update), hazards,
  ground_marks, exchanges (dialogue).
- `game_view.gd` (1464): mirror, fixed-sprite culling, `sprites()`,
  `to_canvas`, feedback, `draw/_draw`, lights, hurt arc/use mark/hit mark,
  look pass/grade, automap.
- `game.gd` (633): `_init` (level, enemies, pickups, flow fields, features),
  `tick`, `_step_body`, `_surroundings`, `_discover`, `_step_hands`.

Save/load is SessionStore (not in the chain). There is no `_physics_process`.

## Front-end states

title, setup, slots, replays, controls, credits, rematch, rematch_done,
showdown, multi, nethost, netjoin, servers, lobby, lobbyset, county, play.
Drawn in `main_state.render()`; keys through `main_input.key()`; online states
through `_key_online` and `OnlineInput.SCREENS`; taps through hand-placed
zones (`LobbyScreens.zones`, `OnlineInput.tap`, `CountyInput.tap`,
`TacticalScreens.tap`). Tally, death and finale are not states: they draw
through `hud.intermission`.

## Main loop

`main.gd _process` -> touch, pad, `_controls()` -> `advance()` (accumulator,
1/120 s steps of `game.tick`) -> `render()`. In play `render()` calls
`game.draw(canvas)` -> `_draw`: `renderer.frame_begin(eye)`, ground and wall
marks, `sprites()`, `renderer.frame_sprites`, features' `draw_view`, the
weapon, flashes, crosshair, banners, HUD; then `scene_hook` (SceneLayers.early)
and `render_end`; then `layers.frame()` hands the shader its parts.

The screen: Main (Control) -> backdrop, `view` TextureRect with
`palette.gdshader`, the iris fade, TouchControls. With a window the HUD, menus
and gun are drawn with Godot 2D into a 320x200 SubViewport (`post_tex`).

## Signals (declared in game_state.gd)

| Signal | Emitted at | Listeners |
| --- | --- | --- |
| enemy_killed | game_world enemy_down | bayou_feature, boss_fight, boss_rematch, callouts, chapter_stats, county_run, firing_range, mothership, squad_feature |
| player_hurt | game_world damage | boss_voices, chapter_stats, feel, fight_music, firing_range, mode_feature |
| pickup_taken | game_world collect | mode_feature |
| station_done | game_world | firing_range, mothership, race_laps |
| shot_fired | weapons.gd | chapter_stats, county_run, critters, debris, dust, firing_range, gun_fx, impacts, squad_feature, weapon_fx |
| hit_landed | game_world struck | chapter_stats, fight_music |
| level_won | game_world finish_level | boss_checkpoint, boss_rematch, mode_feature, tally |
| ticked | game.gd tick | ~30 features |
| exploded | game_combat explode, mothership, bomb_mode | boss_arena, critters, debris, firing_range, gun_fx, impacts, water, weapon_fx |
| gun_reloading | weapons.gd | debris |
| traced | game_combat hitscan | boss_arena, firing_range, gun_fx, impacts, weapon_fx |
| pierced | penetration.gd | impacts |
| enemy_bark | squad.gd | enemy_barks |
| boss_enraged | enemies.gd, mothership | bayou_feature |
| boss_intro / boss_phase / boss_staggered / boss_weak_hit / boss_down | boss_fight, boss_kit | boss_voices, enemy_barks, boss_checkpoint, boss_rematch |

boss_voices and enemy_barks connect by signal name (`game.connect(...)`).

## What extracts cleanly, what is tangled

Clean: automap; look pass/grade; Barks/Cheats/Gallery (already classes);
`_surroundings` (presentation); pickups (plain arrays + collect); doors (data
and update already in LevelData); objective text/route (partly in
game_objective.gd); stations.

Tangled: combat (hitscan/explode/_hits reach into breakables, wall_breaks,
corpses, Modes, HitZones, penetration, Enemy.hurt); enemies (`Enemy.tick(dt,
game)` takes the whole game; enemy_down mixes kills, barks, drops, boss story);
the tick and the acting player (`focus()` swaps armory, flow, proxy
properties); damage(); interact/use_target; `message()` (39 files) and
`stations_done` (13 files).

## The old renderer's contract (what the 3D view must reproduce)

- Camera (`Player.as_render_player()`): x, y, eye (height), view_angle, pitch,
  bob, sway. Horizon = VIEW/2 + pitch + bob + sway (screen rows; Build-style
  y-shear, not a rotation). Screen x = vw/2 + lateral/ahead * focal, y =
  horizon - (z - eye)/ahead * focal. FOCAL 230 at 320 wide (FOV ~69.6 deg);
  FOCAL_FOR = [230, 190.7, 160, 134.3]; HD doubles vw, vh and focal.
- Light: `light_at(d, L) = round32(max(.19, L / (1 + .102 d)))`, d = forward
  (perpendicular) distance. Colour = trunc(texel * step/32 * tint[area]).
  Floors light `L*.94 + flash`, ceilings `L*.77 + flash`. Glow signs max(.9),
  the liquor tube flickers .9*.73. Bodies at least .58 - .021 d; glowing
  sprites 1.1.
- Walls: `level.active_walls()` rows of 9 floats [ax, ay, bx, by, tile,
  light, bottom, top, area]. Double sided; seen from behind u is mirrored
  back (tex_u = 1-u). Mode 0 (stretched): u 0..128 across, v over the height.
  Mode 1 (TILED materials): u = along * 128 px per unit, v = (1.96 - z) * 100
  wrapped to 128. Mode 2 (`_win`/`_lit`/`_brk` of a tiled material): the
  window tile between z 1.0 and 1.68, the plain tile elsewhere.
- Floors/ceilings: per cell `ground` / `roof` (0 = open sky), `floor_tile` /
  `ceiling_tile`; `caps` / `roof_caps` (height -> rects [x0,y0,x1,y1,tile,
  cut lines...]); `slopes`; world-space UV, 128 px per unit; `moving_floors`
  scroll v.
- Sprites (`Renderer.Sprite`): x, y, z (bottom), height, image, glow, flip,
  translucent, body (sunk by its image's empty bottom rows), plane (NaN =
  faces the camera; an angle = a flat board), hurt (red wash). Width = height
  * w/h. Drawn to 32 cells (51 for sprites over 2.7 tall).
- Wall marks (decals on walls, radius), ground marks (rectangles on floors:
  angle, reach, width).
- Sky: a 512x116 panorama, drawn where nothing else is.

## Where game code touches the renderer (seam map)

Sprite sources: `game_view.sprites()` (draw order: fixed props/boards/drums/
notes, hub boards, gallery target, interiors and scenery, decoys, hazard mists,
enemies via `Enemy.sprite(...)`, pickups, shots, `Features.sprites`, specks,
puffs, gibs, blasts far to near). Persistent `Renderer.Sprite.new` in game.gd
(props), game_view (fixed), gallery, breakables, wall_breaks, variants_feature,
range_targets, range_bowling, race_laps, boss_arena(s), boss_fight, mothership,
bosses/*. Pooled (`game.pooled`) in ambient, debris, dust, gun_fx, hit_reads,
squad_feature, weapon_fx, breakables, county_orbs, mode_screens,
tactical_screens, tactical_utility. Culling: `game.in_view(x, y, reach)` (needs
`renderer.vw`, `renderer.focal`, `view_eye`).

Marks: `game.wall_marks` + `gore_fx.walls` + `Features.wall_marks` (impacts);
`renderer.wall_mark()` (find the wall face a hit lands on) called from
game_combat (hitscan material), impacts, gore, gore_extras. Ground marks from
`game_combat.ground_marks()` (dress marks, gore, Features.ground_marks,
hazards).

Screen-space overlays via `draw_view(c)` + `game.to_canvas()`: weapon_fx
(tracers, milk, steam), gun_fx, county_orbs, county_screens, mode_screens,
tactical_screens, use crosshair. `Effects.rich` gates the shader-only effects.

Lights: `ViewLights` gathers muzzle, blasts, gun_fx lights, shots, lamps,
glowing boards, airboat, quest pickups, `trigger_lights`. Rows
`[x, y, z, radius, Color, strength, flags, heat]`. Station lights rewrite
`world.light` and bump `light_version`. Weather/water features feed rain,
wet, flash_dir, rings. Fog/grade/sky from `Effects.mood(level.id)`.

Game logic that leans on the renderer (must move before the switch):
- Hitscan material: `renderer.wall_mark()` is pure geometry over
  `level.walls`; move it into LevelData.
- breakables.gd:186 collision radius from `renderer.sprite_art` sizes (use
  Assets directly); wall_breaks reads `renderer.tile_mode`,
  `RenderState.WINDOW_SILL/HEAD/TILED`; level `_merge_runs` reads
  `RenderState.TILED` (move the table to LevelTiles).
- Aim slope `(pitch + sway) / Renderer.base_focal` (weapons, game_combat,
  county_moves, tactical_bot, main_input, bot tools): keep `base_focal` as a
  plain number; the 3D camera reproduces the shear so the crosshair stays true.
- `Renderer.VIEW/WIDTH` used as 2D canvas constants all over the HUD.
- Host games keep a renderer object only for `wall_mark` and sprite sizes.

Tools on the old renderer: picture_check (headless software pictures,
tools/pictures), compare_views + view tour (tools/pictures_gpu), check_shader,
launch_check, bench, check_fixes renderer internals (screen_hole, hub shadow),
closeups, frame tools.

## Level data (for the mesh builder)

- Map axes x east, y south, z up; 1 cell = 1 unit. Godot: X=x, Y=z, Z=y.
  Angle 0 = +x, PI/2 = +y; screen right = (-sin a, cos a).
- Grids W*H: solid (-1 open), floor, ceiling (tile ids), ground, roof (0 =
  sky), wall_height, light, area. Hickston is 150x78.
- Wall rows face (dy, -dx); drawn two-sided. Light baked x.83 on E/W faces.
- Format 2 `geometry`: slabs (decks, ramps; `thick -1` = solid to the ground,
  gx/gy slope, cuts), segments (rails, thick walls). `render_parts` turns them
  into wall rows, caps, roof_caps, slopes `[z0, gx, gy, side, x0, y0, x1, y1,
  tile, light, area, cuts...]`.
- caps: height -> [x0, y0, x1, y1, tile(, cut lines nx, ny, c ...)].
- Doors: one zero-thickness wall 0..1.85 moved by `segment()`; door cells have
  roof 1.85. Panes: glazing wall .36..1.78 (5v5 maps). Gates: `barrier()`.
- Props: billboards `prop_<name>` (PROP_HEIGHTS), `town_<name>` billboards over
  a .05 base fixture (sizes in assets/art/town_props.json, 256 entries).
  Plane sprites: one-sided quad centred at (x, y), width along (cos p, sin p),
  seen from the side of (-sin p, cos p); `back` is a second one at p + PI.
- Blender scripts render PNGs only (no glTF yet). Props: ortho camera, model
  turned -28 deg, 8 deg pitch. Actors: per-frame procedural meshes from
  `skeleton(S, frame)` joint positions (no armature).
- Tiles: 196, 128x128 RGB, `assets_gen/tiles.bin`. Skies 512x116, 512 columns
  = 360 deg, row 93 the horizon. Palette: RGB555 -> `vga_rgb555.bin` LUT.
- Eye .95 (crouch .68), body 1.12, radius .19, step .245, jump ~.40, walk
  2.75, run 3.85. Door 1.85, wall 2.0, room roof 2.2.
