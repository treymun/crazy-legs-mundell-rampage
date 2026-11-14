# Godot 3D rewrite: progress log

Branch `godot-3d`, cut from `main` at `v2.0.0-dev.45` (f8f5eb7, the newest
GitHub release when the work started, 2026-11-14). Plan: `plan.md`.
Test builds: `C:\Users\treym\Downloads\CrazyLegs-3D-Test\` (TESTING.md there).

## Where things stand

| Stage | State |
| --- | --- |
| 1 Survey and plan | done |
| 2 World in 3D | mostly done (see below) |
| 3 Animated 3D enemies | not started |
| 4 Gore and effects in 3D | not started |
| 5 Every map and mode, then the switch | not started |
| 6 Menus and HUD on Godot UI | not started |
| 7 Content as data | not started |
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

## Next

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
