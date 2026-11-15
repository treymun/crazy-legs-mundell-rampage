# Godot 3D rewrite: progress log

Branch `godot-3d`, cut from `main` at `v2.0.0-dev.45` (f8f5eb7, the newest
GitHub release when the work started, 2026-11-14). Plan: `plan.md`.
Test builds: `C:\Users\treym\Downloads\CrazyLegs-3D-Test\` (TESTING.md there).

## Where things stand

| Stage | State |
| --- | --- |
| 1 Survey and plan | done |
| 2 World in 3D | mostly done (see below) |
| 3 Animated 3D enemies | in progress |
| 4 Gore and effects in 3D | not started |
| 5 Every map and mode, then the switch | not started |
| 6 Menus and HUD on Godot UI | not started |
| 7 Content as data | mostly done |
| 8 Docs | not started |

## Log

### 2026-11-14
- Cloned, branched, packed assets, made the clone's own `.venv` (gdtoolkit).
- Baseline: `check_all -- lint` on the untouched clone: ALL CHECKS OK in 395 s
  (check_fixes is the long one, 395 s; everything else under 90 s).
- Survey written (`survey.md`), plan written (`plan.md`).
- Stage 2: `src/view3d/` draws the game in Godot 3D (on by default with a
  window; `--view2d` keeps the old renderer). Level meshes (walls, floors,
  roofs, caps, slopes, doors, panes, gates) in 16-cell chunks; sky; sprites
  as MultiMesh billboards/boards; wall and ground marks as decals; mirror by
  a second camera; rain layers; water, puddles, rings, relief, Crossroads
  runoff and tower shadow; lights/fog/grade ported from palette.gdshader.
- Props: `scripts/blender/export_meshes.py` + `tools/art/build_prop_meshes.gd`
  bake 194 props to glTF + palette textures (`godot/assets3d/props`,
  `assets/art/mesh_*.png`); `PropLayer3D` stands them where the billboards
  stood, facing the most open side.
- Play untied from the renderer: `WallHits.wall_mark`, `LevelTiles.TILED`/
  window band, breakables read art from Assets.
- Checks: `tools/view3d_check.gd` (CI, check_all), `check_all -- quick`
  (72 s). Full check_all passed after the 3D view landed.
- Bench (desktop, same frames back to back, `--view-bench=200`): 3D view vs
  old shader view: hickston 276 vs 229 fps, fair 492 vs 388, sawmill 507 vs
  309, quarry 468 vs 384, bayou 339 vs 261, speedway 452 vs 324.
- Test build: Windows EXE exported to Downloads\CrazyLegs-3D-Test (own
  profile folder, `Crazy Legs Mundell Rampage 3D`). APK: no Android SDK/JDK
  on this PC; the branch's CI now builds it as an artifact.

- Stage 3 started: `scripts/blender/export_actors.py` rigs every actor from
  enemy_actors.py's own per-frame build (parts recorded in `place()`, matched
  across frames by shape, moved rigidly; parts moving together become one
  bone; round joint balls merge into the limb that carries them), keys each
  frame (idle, walk w0-w3 + w4 loop key, aim, wind, fire, pain, recover,
  extras, die_0-4, down; hurt limping frames), labels bones head/arms/legs,
  decimates to ~8k faces, bakes plain/hurt/boss-phase albedo onto one
  unwrap. `tools/art/build_actor_meshes.gd` commits textures to the palette.
  `ActorLayer3D` draws each enemy as its model in the pose its sprite would
  show (walk and fall interpolated), facing its heading, scaled by height /
  canvas; `actor.gdshader` lights it with the cels' dusk stage relative to
  the camera, a dark rim, then the old sprite light formula.
- Gore: `Gore.lost` records a thrown limb (side from the enemy uid, no dice);
  the model leaves that limb off.
- Event hub: `src/core/game_events.gd` (`game.events`) carries every game
  signal (19, plus level_started); 58 files moved onto it.
- Tour viewpoints take `actors` (kind, ahead, side, turn, state) for
  side-by-side pictures of the 3D actors.

- Stage 7: content numbers moved into data/tuning: store.cfg (5v5 store,
  economy, pvp hits, spread), difficulty.cfg (every per-difficulty array),
  hits.cfg (head/limb multipliers, reactions, ammo pickups), modes.cfg (co-op,
  deathmatch, 5v5 rounds, bomb, hostage, tag team, County Run cards/co-op/
  moves/orbs/spawner, throwables, squads, idle life, hit zones), bosses.cfg
  (169 boss-script numbers), lobby.cfg (lobby rows and defaults). Values
  checked equal to the old constants; scripts keep their names as static
  vars. Loaders: Difficulty, HitData, ModeData, BossData (src/core/).
  Survey of what's left: `content_survey.md` (inline literals in boss
  scripts, PROP_HEIGHTS, bots' STYLES).
- Typing census (warnings as errors in a scratch copy): ~10.9k in src/
  (3.7k constructor args from Variants, 2.2k unsafe method calls, 1.5k+
  argument types, 1.1k untyped params, 0.7k untyped vars, 0.35k loop vars).

## Next

- **Owner's standing request (2026-11-14): the 3D models must look damn good
  and match the old cels** (faces, hands, colours, patterns). Before the
  project is called done: a side-by-side pass of every actor kind in every
  pose and look (tour `actors`, `--view2d` for the old), tuned until each
  matches; sheets in docs/godot3d/compare/actors/.

- Stage 2 leftovers: heat shimmer (haze boxes) in 3D; quest stations and
  `prop_*` pictures as meshes; mesh decimation for phones.
- Stage 3: armatures and animated glTF actors.

## Decisions

- Keep `gl_compatibility` as the one renderer on every platform. The look is
  made by our own unshaded spatial shaders (the old renderer's light, shade
  and fog formulas, ported per pixel), so Godot's light model and the renderer
  choice don't change the picture; the browser and phones get the same image.
- The 3D view replaces only the view part of the display shader: the weapon,
  HUD and menus layer, the look pass (grain, dither, vignette, tone) and the
  RGB555 -> palette lookup stay as they are, so the palette colours are kept
  by construction.

- Guns in hand stay 2D cels drawn over the 3D view (the 1997 look; their
  muzzle flashes and tracers are the existing overlays).
- The CI window job keeps comparing the old shader view (`--view2d`) to its
  references until the switch; a second step runs the tour on the 3D view
  under Mesa and fails on any shader or script error.
- The branch builds its EXE/APK as CI artifacts (no release, no site).
- The 3D build uses its own user folder so test builds never touch the
  released game's saves.

## Known problems

- Heat shimmer not drawn in 3D yet.
- Modelled props can look a little darker/flatter than their sprites; facing
  is guessed (levels never stored a facing for billboards).
