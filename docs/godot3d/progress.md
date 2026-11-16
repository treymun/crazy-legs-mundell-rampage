# Godot 3D rewrite: progress log

Branch `godot-3d`, cut from `main` at `v2.0.0-dev.45` (f8f5eb7, the newest
GitHub release when the work started, 2026-11-14). Plan: `plan.md`.
Test builds: `C:\Users\treym\Downloads\CrazyLegs-3D-Test\` (TESTING.md there).

## Where things stand

| Stage | State |
| --- | --- |
| 1 Survey and plan | done |
| 2 World in 3D | done |
| 3 Animated 3D enemies | done; final model pass in progress |
| 4 Gore and effects in 3D | done as billboards and decals (gibs, blood, marks), limbs off the models |
| 5 Every map and mode, then the switch | done: software renderer retired |
| 6 Menus and HUD on Godot UI | menus done (screen objects); HUD still canvas-drawn |
| 7 Content as data | done except the bosses' inline literals |
| 8 Docs | done (CLAUDE.md core + docs/dev/) |

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

### 2026-11-14 (evening)
- The switch: software renderer, palette.gdshader, scene_layers and the
  picture tools retired; `View` replaces `Renderer` for play; display.gdshader
  is the picture. CI's window job tours the 3D view (compare_3d against
  tools/pictures_3d). Full check_all: ALL CHECKS OK (426 s).
- DRAW DISTANCE (AUTO/FAR/NEAR; AUTO is NEAR 64 cells on phones); the
  browser keeps its detail without threads. Headless server runs with no
  GPU (`--server`, net_server_check OK).
- Menus: every state is a UiScreen (buttons with focus for title, replays,
  rematch, controls, credits; tap zones through a Control for online, 5v5
  picker, County Run; setup and slots keep their key rules). UiTheme.
- Props and actors as scenes (scenes/props, scenes/actors: PropView,
  ActorView). Billboard prop heights and bot buying styles into data.
- Docs: CLAUDE.md 138 lines; docs/dev/ (14 files incl. how_to_add.md).
- Boards are one-sided as in the old renderer (a sign's back no longer
  hides its front).
- Actor looks: baked four ways round with each texel weighted by how it
  faced the camera (back and side views now match the cels); missed bake
  texels (a fifth of each texture: inner arms, thighs, undersides) rebaked
  with longer rays, then from the body itself (no more black patches on
  fallen bodies); fallen bodies lit like their cels. Baking on the GPU
  (about 1 minute a kind).
- Static typing: six parallel batches (10.9k errors); modes and features
  merged; view3d, ui, core typed by hand.
- Compare sheets: docs/godot3d/compare/<level>.png, actors/actors_NN.png.

### 2026-11-15 (night): finishing and the v3.0.0 remaster
- Actors re-baked (all 38, GPU, four turns, weighted); committed with their
  scenes. A third of each texture was pure-black missed texels (black specks
  on faces); build_actor_meshes now fills them from their neighbours.
- 3D picture references for CI (tools/pictures_3d, 72 pictures).
- Remaster, five tracks merged (pictures in docs/godot3d/remaster/):
  pickups as 3D pixel slabs; maps (stair/deck/ramp sides, car boxes hidden,
  lamps on raised walks, moods for ten maps); physics on the real floors
  (tumble.gd, physics_check.gd); audio (hearing through walls and floors,
  more takes, loudness outliers 68 -> 43; no ElevenLabs spend: no key in the
  session); modes (3D bodies in 5v5, team colours, race cars).
- check_all lint: every check OK after a hearing fix (sounds off the map).
- Bench (RTX 5070 Ti laptop): 3.6 ms a frame on average (277 fps).
- Known: Big Billy's fall specks, crawler legs thin, derby champ large, big
  bosses busy up close (512 texture), co-op partners still flat cels, HUD
  not on Controls.

### 2026-11-16: polish and optimization pass (v3.3.0)
- Boss arenas lock you in (boss_lock.gd): the fight starts only well inside,
  every way in shuts and holds until the boss falls (the early starts were a
  14-cell radius through walls, gaps by the sheriff's chute, any damage
  starting it, bosses walking out).
- 5v5 and DM bots aim like people (bot_aim.gd, BOT SKILL EASY..HOG WILD,
  MIXED), personas, trades, team radio, belly aim (headshots ~38%).
- Physics: loose things settle, ragdolls on the floor (<1 cm), staves tip,
  water splashes and drift, no tunnelling; vehicle feel (squat, lean, spray,
  skids, sparks, engine pitch); plank walls of sheds and barns break.
- Looks: the County Run storm wall, chunky dynamic shadows (SHADOWS), marks on
  props/vehicles/wreck pieces; six bosses re-baked on the tight unwrap; the
  shop lamp and the cow as models; ducks turn on their sticks.
- Optimization (track R; numbers in docs/godot3d/optimize/R/results.md): view
  bench HIGH/MEDIUM/LOW 7.20/7.17/6.03 -> 6.93/6.26/5.44 ms, a wall broken
  59 -> 3.4 ms, repeat level loads 4.6 -> 1.5 s; checks no longer hang after
  OK (sound level churn); CI in six parallel shards (~4 min).

### 2026-11-15: feature pass (v3.2.0)
- Ten tracks merged (pictures in docs/godot3d/features/): ragdolls and
  slow-mo finishers; picking up and throwing props, spreading fire, the
  moonshine stills; breakable scenery in 3D pieces; drivable vehicles
  (airboat, stock car, mower); smarter hands and climbing in every chapter;
  bosses wrecking their arenas and gear shot off; range games, the range
  board, the fair gallery 2.0, the hub trophy shack; weather (puddles, mud,
  wind), the County Run storm, critters with physics; photo mode, kill cam,
  quality tiers, the HUD on Controls; multiplayer lag (net_lag.gd numbers in
  multiplayer.md), 5v5 boarded cover, round MVP.
- Merge notes: level.gd's sight test moved to level_sight.gd, game_view's
  look rows to game_state.gd (file limit); arena_wreck's save is empty when
  nothing is wrecked (a 5v5 round start); the bowling meshes' winding fixed;
  hickston layout 6 (ladders, mower, cows), older hickston saves load with
  the three animals counted. Settings: 69.
- check_all lint: all OK but net_server_check once under load (OK 4 of 4
  alone).

### 2026-11-15: second polish pass (v3.1.0)
- Bowling lane: the pins are 3D rigid bodies (range_pin_physics.gd: a real
  pin's profile as spheres on its foot ring, sequential impulses, sleep),
  the ball solved with them; pins and ball drawn as 3D meshes (SolidLayer3D);
  the gutters and pit sunk (range layout 4). bowl_lab.gd tunes it.
- Slabs (SlabLayer3D, was PickupLayer3D): loose things (brass, gibs, bits,
  hats, dropped guns) tumble and lie flat; range targets swing and spin.
- Every prop 3D: 33 new models for the last 59 prop pictures, quest
  stations one model with their off and on looks, facing their use point.
- Mundell as a 3D model for every other player (co-op, DM, team DM, County
  Run co-op, online, the mirror).
- Floating parts after kills (almost every kind): actor animations imported
  at 30 fps resampled their 24 fps keys; fixed for every kind and checked
  (view3d_check). death_frames.gd pictures deaths close up.
- QA sweep: county_net_check's flake (bark_next and specks' dice; the check
  now lists every mismatch), the restroom's GENTS tiles, the fair's tent
  sign, the soda fountain, a pickup in the footbridge stairs, the sky's top
  row; tours keep drawing when another window takes focus.
- Pictures: docs/godot3d/remaster2/ (bowling, slabs, props, mundell, qa,
  actors). check_all lint ALL CHECKS OK.

#### Actor leftovers (detail)
- Big Billy's fall specks: actors imported at 30 fps resampled their 24 fps
  keys (a part shrunk away came back half-grown in mid-air); now 24 fps,
  LINEAR keys, near-print matching (parts no longer vanish for a fall or a
  walk beat), gone parts shrink in place. Every kind re-rigged (rig-only,
  unwrap carried over), the baron re-baked.
- Unwrap packed by shape (the baron's islands covered 3% of his texture,
  now about half) and the baron at 1024.
- fit.json: per-kind light (models were 5-30% darker than their cels),
  derby champ .85, crawler legs at least about a pixel; bodies at rest drawn
  half height. Pictures: docs/godot3d/remaster2/actors/.

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
