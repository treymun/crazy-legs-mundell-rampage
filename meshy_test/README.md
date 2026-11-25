# Meshy test: three models for Crazy Legs Mundell Rampage

A one-off experiment, run entirely in a cloud session on 2026-11-25. Nothing
in the game was changed: this folder is the only addition, on a temporary
branch, and it is not wired into the project. The in-game pictures were made
in a scratch copy of the game that was thrown away afterwards.

**Credits: 162 of the 250 allowed** (balance 3,100 → 2,938; no purchases).

## The three models

| | Enemy: hillbilly shotgun thug | Monster: mutated hog | Prop: rusted tractor (Grainyard) |
| --- | --- | --- | --- |
| Closest existing asset | `billy` actor | `hog` actor (the herd) | `tractor` prop |
| Existing: triangles / texture | 23,742 / 512² | 7,770 / 256² | 1,012 / 256² |
| Meshy source: triangles / texture | 31,020 / 2048² | 28,451 / 2048² | 40,695 / 2048² |
| Game-ready: triangles / texture | 9,993 / 512² | 5,996 / 512² | 7,954 / 512² |
| Game-ready GLB size | 508 KB | 336 KB | 520 KB |
| Credits | 9 concept + 30 model = **39** (+40 for the rig test below) | 9 + 30 + 5 remesh = **44** | 9 + 30 = **39** |

Height and orientation match the asset each one would replace: the
hillbilly is Billy's 1.643 m, the hog is 0.93 m (the herd hogs stand 0.9),
and the tractor is 1.9 m tall with its grille facing the way the old
tractor's does.

### Files

- `models/*_meshy_source.glb` / `.usdz`: Meshy's full-quality output. On an
  iPhone, open the **.usdz** (Quick Look shows it in 3D and AR); iOS has no
  built-in GLB viewer.
- `models/*_game_ready.glb`: the Blender-reduced model with its baked
  texture, for viewing.
- `models/pipeline/`: what the game's prop pipeline would take: the mesh
  alone (`meshy_<name>.glb`) and its texture after the game's own grading
  (`mesh_meshy_<name>.png`, run through `Paint.photo_grade` and
  `Paint.digitize` exactly as `build_prop_meshes.gd` does).
- `models/enemy_rigged_walk.glb`, `enemy_rigged_run.glb`: the A-pose
  hillbilly, auto-rigged by Meshy (24 bones) with its walk and run.
- `previews/`: concepts, turnarounds, comparisons, the rig test, and
  `ingame/` (the game's display at 1280x800) and `ingame_native/` (the
  320x156 world view as the game renders it, before scaling).
- `credit_ledger.json`: every paid call, with the balance read before and
  after it.
- `tools/`: the scripts used (Meshy client with the credit cap, the Blender
  steps, the renderer, the in-game set-up), so the test can be repeated.

## How they were made

1. **Concept, on-model.** Meshy image-to-image (`nano-banana-pro`, 9 credits)
   with the game's own sprite as the reference (`billy_0`, `hog_0`,
   `town_tractor`, enlarged). This kept Billy's design (grey-green cap, dark
   beard, red plaid, blue overalls, belly, shotgun) while adding a face,
   cloth and grime. The hog became a mutant from the alien chapters: a third
   eye, tumours, staples and a rusty implant with a green tube. The tractor
   is a 1950s row-crop tractor gone to rust, with a flat front tyre.
   Nothing references Redneck Rampage art; the prompts ask for an original
   1990s Southern comedy-horror look.
2. **3D.** Meshy image-to-3D (30 credits each), textured, triangles, remeshed
   to 30–40k. `meshy-7.5` is listed by the API but was refused for
   generation on this key, so the request used `latest`. The task record
   does not say which model that resolved to.
3. **Blender (headless, `bpy` 5.3).** Scaled and turned to match the old
   asset. Reduced to game budgets (collapse decimation; the hog's bristles
   are open sheets that Blender's collapse cannot reduce, so it used Meshy's
   remesh at 6,000, which cost 5 credits). Then the Meshy model was baked
   onto the reduced mesh under the game's own dusk stage (the key, fill and
   rim suns and sky of `town_props.py stage()`, a COMBINED bake as
   `export_meshes.py` does). The baked texture then went through the game's
   own grade and palette.
4. **In the game.** In a scratch copy, the three were registered as props
   (`meshy_*`) and placed in Grainyard beside the old tractor. Billy and a
   herd hog were stood next to them by the view tour. Then the game's own
   view tour rendered them: real `WorldView3D`, shaders, display shader,
   HUD, Mesa's software GL under Xvfb. In those pictures the new models are
   **static props**, not animated actors.

## Rigging test (the enemy)

The game's enemies are rigged and animated, so a still model is not enough.
Meshy's auto-rig (5 credits, about 15 s) on the first hillbilly gave a usable
skeleton and walk. But the shotgun is fused into his body and **bends like
rubber** with the arm (`previews/enemy_rig_gun_bends.png`). The fix: the
same concept regenerated with `pose_mode: a-pose` (30 credits). Meshy
re-posed him and dropped the gun. Rigged again (5 credits), he walks and
runs cleanly (`previews/enemy_apose_walk_run.png`). For real use, a
character would be made this way, with the gun as a separate model on a
hand bone (as the bosses' gear already is).

Not done: turning the Meshy rig into the game's own actor format (its
`poses` keys, bone labels, `actors.json`). That is real work: the game's
actors are cut from the same Blender builds as their sprites, with hurt
looks, deaths, gibs and ragdolls.

## Assessment

**Is it a worthwhile improvement over Blender alone? For characters and
creatures, clearly yes. For props, yes in quality, but it is the riskiest
for consistency.**

- **What Meshy brought** that our Blender builds cannot reasonably reach:
  sculpted faces with expression (the snarl, red nose, chaw and squint),
  real cloth folds, painted grime, and organic shapes (the hog's lumps,
  tusks and bristles). The existing actors are joined primitives (balls and
  hulls) with procedural cloth, and the old tractor is literal boxes and
  discs. Each Meshy model took a minute or two and about 40 credits. A
  comparable hand-sculpted asset is days of work.
- **What Blender still had to do**, and why the combination matters: scale,
  orientation, reduction to game budgets, the dusk-stage bake (which also
  restores detail lost in reduction), the game's grade and palette, the rig
  check, and fixing what Meshy got wrong (the hog's topology).
- **At the game's resolution** the models still read as late-90s pre-rendered
  sprites once the palette and 320x200 view are applied. They do look more
  detailed than the world around them. Put in one at a time, they would
  make the rest look cruder. If adopted, a set should be redone together
  (one chapter's cast and props), not single swaps.
- **Weak points:** the backs and undersides are Meshy's guesses (decent here);
  thin parts (the gun barrel, the tractor's levers) come out soft; Meshy's
  UVs are many small islands, so 512² textures use texels less efficiently
  than the game's packed unwraps; skin goes yellow-orange under the dusk
  grade (Billy's does too). Under the game's grade, the hog's pink patches
  turn brownish-yellow.

**Suggested next step, if continuing:** one chapter's enemy re-made the A-pose
way, with the gun as gear, converted to the game's actor format, then judged
in motion in the game before committing to more.

## What was not checked

- Nobody has looked at these on an iPhone, an Android phone or in a browser
  build. The USDZ files are Meshy's own and are untested on iOS.
- The in-game pictures came from Mesa's software renderer in the cloud, not
  a GPU. The game's picture comparison is not run against them.
- The models are shown in the game as static props. None runs as a real
  actor, and no gameplay, hit boxes, gibs, performance or load times were
  tested.
- `docs.meshy.ai` was outside the session's network, so the API was used
  from its own validation messages. Every cost above was measured from the
  balance before and after each call.
