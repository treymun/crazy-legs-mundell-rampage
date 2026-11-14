# Godot 3D rewrite: progress log

Branch `godot-3d`, cut from `main` at `v2.0.0-dev.45` (f8f5eb7, the newest
GitHub release when the work started, 2026-11-14). Plan: `plan.md`.
Test builds: `C:\Users\treym\Downloads\CrazyLegs-3D-Test\` (TESTING.md there).

## Where things stand

| Stage | State |
| --- | --- |
| 1 Survey and plan | in progress |
| 2 World in 3D | not started |
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

## Decisions

- Keep `gl_compatibility` as the one renderer on every platform. The look is
  made by our own unshaded spatial shaders (the old renderer's light, shade
  and fog formulas, ported per pixel), so Godot's light model and the renderer
  choice don't change the picture; the browser and phones get the same image.
- The 3D view replaces only the view part of the display shader: the weapon,
  HUD and menus layer, the look pass (grain, dither, vignette, tone) and the
  RGB555 -> palette lookup stay as they are, so the palette colours are kept
  by construction.

## Known problems

(none yet)
