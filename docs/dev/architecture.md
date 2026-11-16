# Architecture

The game is GDScript in `godot/src/`. It is a 320x200 game: play runs a fixed
tick, the world is drawn by a 3D view into a small viewport, and the HUD,
menus and gun are drawn on a 320x200 canvas laid over it, then the whole
picture goes through the VGA palette.

## Two chains of layers

Each file extends the one before. A function may call functions of its own
layer or the layers below it; calling up is a parse error. New fields go in
the bottom layer (`main_state.gd`, `game_state.gd`). Files stay under 1,500
lines (gdlint).

**The front end:** `main_state` -> `main_flow` -> `main_input` -> `main`.

- `main_state.gd`: the front end's fields, options (`persist_options`, which
  returns when a tool script runs the main loop), launch flags, the frame
  (`_frame_3d()` hands the view frame to the 3D view), `_exit_tree`.
- `main_flow.gd`: starting games, chapters, modes and matches (`play()`,
  `start_county`, `net_match_game`, `retry_fight`, `_take_mode`), settings
  feedback.
- `main_input.gd`: keys, the pad (`read_pad` -> `_pad_menu` -> `key()`), touch,
  controls (`_controls`), the keyed menus. The online screens' keys are
  `OnlineInput` (`net/online_input.gd`, `key_online`, asked first by `key()`).
- `main.gd`: `_ready` (the crash log), the per-frame drive (`advance()`,
  `_net_frame`, `_net_aim`, `_auto_detail`, `--launch-check`).

**Play:** `game_state` -> `game_world` -> `game_combat` -> `game_view` ->
`game`.

- `game_state.gd`: the game's fields, `game.events`, the sprite pool
  (`pooled()`), uids, `to_canvas`.
- `game_world.gd`: the world: `configure()` (difficulty), `damage()`,
  `use_target`, pickups.
- `game_combat.gd`: `hitscan`, `_hits`, `explode`, `_blast_shoves`.
- `game_view.gd`: what is drawn: `sprites()`, the automap, the down screen,
  and `game.view_frame` for the 3D view.
- `game.gd`: the tick (`tick(dt, controls)`, `_step_body`, `_step_hands`,
  slow motion, rewind).

A layer stays under the line limit by handing self-contained pieces to
helpers outside the chain: classes of static functions taking the game
(`g: Game`; a layer below `Game` passes `var me: Game = self as Object`),
or a small object the game holds in a field of its own (listed in
`VIEW_FIELDS`), or a feature. The layer keeps a one-line function of the old
name where other code calls it. Play's helpers so far:

- `game_use.gd` (`GameUse`): what USE acts on (`use_target`, the device aim
  points), its prompt, `interact()`, the Crossroads gates and clues.
- `game_objective.gd` (`GameObjective`): the objective's text, pin and route,
  the quest lamps.
- `game_automap.gd` (`GameAutomap`, the game's `map_view`): the automap.
- `screen_look.gd` (`ScreenLook`, `screen_look`): the software look pass
  (grit, grain, dither, the brightness grade folded in) and the drunk warp;
  its numbers also feed the GPU look.
- `barks.gd`, `cheats.gd`, `gallery.gd`: Mundell's one-liners, the HICK MODE
  codes, the tin rooster booth (preloaded as `GameState.Barks`, `Cheats`,
  `Gallery`).
- For an enemy: `enemy_attacks.gd` (`EnemyAttacks`: its attacks),
  `hand_tactics.gd` (`HandTactics`: cover, fetching help, brawls, swinging
  out), `enemy_looks.gd`, `enemy_tuning.gd`.

Keep hot paths direct: a function run for every enemy every frame (its
sprite) or for every cell in a loop stays where its fields are, or reads the
helper's object's fields into locals first; through `obj.field` each access
costs (a level's load was 13 % slower before its moved loops read through
locals).
- For the guns: `weapon_paint.gd` (`WeaponPaint`: the viewmodel's grading,
  rims, blits and lines).

`game.player` is the acting player, not always the local one: see
[multiplayer.md](multiplayer.md#gameplayer-is-the-acting-player).

## The 3D view

`src/view3d/`. `View` (`view.gd`) is what play knows of the view (size,
focal, detail, the Sprite/WallMark/GroundMark classes); `game.view` is it.
`game_view.gd` builds `game.view_frame` = {eye, horizon, flash, sprites,
marks, ground, reflection} each draw, `main_state.gd _frame_3d()` hands it to
`WorldView3D`, which renders the level mesh, props, actors, sprites, marks,
sky and rain into a SubViewport. `src/display.gdshader` lays the canvas over
it and does the look pass and the palette. Headless runs draw no world. Full
detail: [view3d.md](view3d.md).

## The canvas, HUD and menus

`canvas.gd` draws shapes and text; with a window the calls become Godot 2D
canvas commands (`Canvas.gpu`), headless they draw in software. `hud.gd`
draws the HUD with it; with a window its status bar and objective pin are
Controls (`HudLayer`, `src/ui/hud/`) under the canvas. The menu screens are
Controls under `UiRoot` (`src/ui/`). PHOTO MODE (`photo_mode.gd`) and the
KILL CAM (`kill_cam.gd`) are the front end's, drawing the view from cameras of
their own while the game holds still; QUALITY's tiers and the physics detail
are `Quality` (`src/core/quality.gd`). See [ui.md](ui.md),
[view3d.md](view3d.md#photo-mode-and-the-kill-cam) and
[gameplay.md](gameplay.md#the-automap-canvas-and-sprites).

## GameEvents

`src/core/game_events.gd`, `class_name GameEvents`, one per Game as
`game.events`. What happens in play is announced there (enemy_killed,
player_hurt, pickup_taken, station_done, shot_fired, hit_landed, level_won,
ticked, exploded, gun_reloading, traced, pierced, the boss signals,
level_started, blood_sprayed, enemy_gibbed, enemy_bled_out, wall_struck,
blast_shoved) for the features, the modes, the 3D view and the tools to
listen to. Signals are synchronous and keep the order listeners connected
in, so play that listens stays the same on every machine. Connect with
`game.events.<signal>.connect(...)`.

A feature's tick is not a `ticked` listener of its own: `tick_with(_tick)`
(GameFeature) adds it to the events' tick list, which one `ticked` listener
runs in the order the ticks were added (the features' order). A feature
with nothing to do calls `sleep()` and is skipped until something calls its
`wake()` (an event it listens to, another feature handing it work); a
snapshot or a save put on the game wakes every feature
(`GameEvents.wake_all()`). Sleep only when each skipped tick would have done
nothing at all, so play stays exact. Asleep now: the race cars once they
have run dry and stopped, the water on a level with no water floor while no
puddle holds water and no ring is left, the posse and the variants after
their one tick, a still with no pipe spraying, hit reads with nothing
knocked loose, the boss lock once its bosses are down, County Run with no
run and a rematch feature off a rematch.

## Letting a game go

A game holds its features and they hold it (`feature.game`), and so do its
gore, its players' voices and the lambdas listening to its events: a cycle
reference counting never frees, so a game dropped without more stays in
memory for good (before 3.3.x, 1,300-odd objects every level load).
`Game.dispose()` cuts every such link (each feature's `detach()`, the
event listeners and ticks, the gore, the voices); after it the game is
spent. Who makes games lets them go: the front end through its `GamePool`
(`main_state.gd` `games`: `make_game` tracks each, and whenever `game`
changes, at the frame's end, every game no longer kept is disposed: kept
are the game on screen, the campaign run and the hub's origin, replays, the
games waiting behind the range or a rematch or for their pictures, a
match's, and what the kill cam, PHOTO MODE and the HUD still show, each with
the chapters it retains), the lobby server its rooms' finished matches
(its own `GamePool`), `GameHost.close()` its game. A feature holding more
that points back at the game lets it go in `detach()`. Whatever is still
about as the process ends (a tool's games) is disposed as the scene tree's
root leaves (`Game.dispose_all()`), so tools end without leaked instances.
A tool that keeps a game from `main.make_game` past a frame's end in which
`main.game` changed holds it where `release_games()` looks, or makes it
with `Game.new` instead. `tools/leak_check.gd` holds it.

## Features

A piece of play or polish kept in a file of its own: `src/features/`, each a
`GameFeature` (`game_feature.gd`: `id()`, `attach()` to connect, `save()`,
`restore()`, `tally_rows()`, `draw_view(c)`, `tick_with()`, `sleep()` and
`wake()`, `detach()`), listed in `features.gd`
(`Features.ALL`; `Features.LOOKS` for looks-only ones a host leaves out).
Each is a simulation feature or a looks feature (`SIM_FEATURES`,
`LOOKS_FEATURES` in `game_snapshot.gd`). Triggers, lessons, chapter stats,
weather, debris, weapon effects, the posse, boss fights and arenas,
breakables, wall breaks, corpses, squads, variants, County Run and the mode
feature (last) are all features. See [gameplay.md](gameplay.md#features-listen-to-events).

## Modes

`src/modes/`: a `GameMode` per mode (`Modes.rules_for(name)`), state in
`features/mode_feature.gd`. The campaign runs none of it. See
[modes.md](modes.md) and [county_run.md](county_run.md).

## Bosses

`src/boss_kit.gd`, `features/boss_fight.gd`, a `BossMoves` file per boss in
`src/bosses/`. See [bosses.md](bosses.md).

## Networking

`src/players.gd`, `game_snapshot.gd`, `snap_codec.gd`, `game_host.gd`,
`net_track.gd`, `game_mirror.gd`, and the transport and lobbies in
`src/net/`. See [multiplayer.md](multiplayer.md).

## Data

- Levels: `godot/data/<id>.json`, built from plans in `godot/tools/levels/`
  ([levels.md](levels.md)); loaded into `LevelData` (`level.gd`; read and
  its tables built by `LevelLoad`, `level_load.gd`), with tiles in
  `level_tiles.gd` and geometry in `level_geometry.gd` (its nav graph built
  by `LevelNav`, `level_nav.gd`; the graph is `nav_graph.gd`).
- Tuning: `godot/data/tuning/*.cfg` and `*.json`, read by `tuning.gd`
  (weapons, enemies, effects, shots: reloaded live from the project folder)
  and the loaders in `src/core/` (`Difficulty`, `HitData`, `ModeData`,
  `BossData`). See [data.md](data.md).
- Art, sound and levels are packed into `godot/assets_gen/` by
  `tools/pack_assets.gd` (generated, not committed) and loaded by `assets.gd`;
  the 3D models are in `godot/assets3d/` and `godot/scenes/`
  ([art.md](art.md)).
- Saves: `session_store.gd` (`SessionStore.VERSION`, the writing side),
  loading in `save_restore.gd` (`SaveRestore`), upgrades in
  `save_upgrade.gd`, fixtures in `godot/tools/saves/`.

## Static typing

`project.godot` turns GDScript's `untyped_declaration`,
`unsafe_property_access`, `unsafe_method_access`, `unsafe_cast` and
`unsafe_call_argument` warnings into errors for everything outside
`res://tools` and `res://addons` (`directory_rules`). A script that breaks
one does not compile, so the game does not start: `tools/load_all.gd` and
every check catch it.

- An untyped value (a Dictionary entry, a JSON number, a save) goes into a
  typed variable: `var hp: int = d["hp"]`. That converts float and int the way
  `int()` did. `v as int` on an untyped value and `int(d["hp"])` are both
  flagged. Text from outside (a save, the network) that may be a String goes
  through `str()` or a small `_int()` helper (see `session_store.gd`).
- `String(v)` on an untyped value: write `str(v)`.
- A play layer below `Game` that hands itself to a helper taking `game: Game`
  writes `var me: Game = self as Object` (or `(self as Object) as Game`).
- Feature scripts without a `class_name` are typed through a preload constant
  (`const Breakables := preload("res://src/features/breakables.gd")`).
  `GameMode` declares `const ModeFeature := preload(...)`; its subclasses
  inherit it and must not declare their own.
- An override's typed parameters must match the parent's exactly.
- `game.sound` and `game.speaker` are a `GameSound` (`game_sound.gd`):
  `SoundLink` wraps this machine's `Sound` node, `PlayerVoice` places another
  player's sounds, `QuietSound` is a host's. Add a method there (and in
  `SoundLink`) before play calls it; `GameSound.node()` gives the Sound itself
  to code that needs the node (`soundscape.gd`).
- A few dynamic calls remain where a script cannot be named (tools' bots
  loaded at run time, the snapshot packer scripts made at run time, whose
  source turns the warnings off).

## Where the rest is

- Checks and CI: [checks.md](checks.md).
- Every command: [commands.md](commands.md).
- Step-by-step recipes: [how_to_add.md](how_to_add.md).
