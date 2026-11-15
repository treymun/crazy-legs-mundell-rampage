# How to add things

Short recipes. Each names the files to touch. After any of them, run
`check_all -- quick` and, at the end of the work, `check_all -- lint`
([checks.md](checks.md)). Paths are under `godot/` unless they start with
`scripts/` or `assets/`. A new `class_name` script needs `godot --headless
--path godot --import` before other scripts can see it.

## A gun

1. Add a section at the END of `data/tuning/weapons.cfg` (the guns are its
   sections in order: saves and number keys keep the old order). Give it how
   it fires (hitscan, pellets, projectile, melee), damage, rate, reload, how
   it sits in view, `flash_art`/`flash_size`, and `penetrate`, `scope` or
   `thrown` if it needs them. `Weapons.NAMES` comes from the sections; add a
   constant in `src/weapons.gd` (like `Weapons.HUNTER`) only if code must
   name it.
2. Model it in `scripts/blender/weapon_views.py` on a plate's rig (revolver,
   shotgun, or crowbar for throwables) and cut it with
   `tools/art/build_weapon_views.gd`. If it has no pickup picture, add its
   wall picture with `tools/art/build_item_art.gd`.
3. Give it a flash style in `tools/art/build_gun_fx_art.gd` STYLES and a
   muzzle light `[light.muzzle_<gun>]` in `data/tuning/effects.cfg`.
4. Add its sounds in `scripts/audio_spec.py` (a report, room twin, dry, equip,
   reloads). Check `audio_generator.py status` before spending ElevenLabs
   credits; never two generation processes at once.
5. If it is sold in the 5v5 store, add `[item.<gun>]` and `[hit.<gun>]` to
   `data/tuning/store.cfg`.
6. Run `tools/pack_assets.gd`, `tools/ttk.gd` for its time to kill, and
   `tools/gun_frames.gd` for pictures.

## An enemy kind

1. Add a section to `data/tuning/enemies.cfg`. To reuse a brain, set
   `brain=<kind>` (it acts as that kind); `art=<kind>` draws it with that
   kind's pictures until its own are in.
2. Model it in the Blender actor scripts (`scripts/blender/enemy_actors.py` or
   a chapter's `actors_<chapter>.py`; variants in `actors_variants.py`) and
   render its cels with `tools/art/build_enemy_actors.gd -- kinds=<kind>`
   (every cel the regular has, the wind-up and hurt cels).
3. The 3D model: `scripts/blender/export_actors.py`, then
   `tools/art/build_actor_meshes.gd -- kinds=<kind>`, `pack_assets`,
   `--import`, then `tools/art/build_actor_scenes.gd -- kinds=<kind>`. Check
   that the face, hands and colours match the cels.
4. If only one chapter uses it, it may go in `Assets.CHAPTER_KINDS` (a
   browser chapter pack); used in more than one level, it must not.
5. Run `pack_assets`, `view3d_check` and `verify_assets`.

## A prop

1. Model it in the Blender props scripts (`scripts/blender/town_props.py`,
   `props_more.py`, or the chapter's `props_<chapter>.py`; a broken copy in
   `props_broken.py` if it breaks).
2. Render the sprite: `tools/art/build_town_props.gd -- names=<name>` (its
   size lands in `assets/art/town_props.json`).
3. The 3D model: `tools/art/build_prop_meshes.gd -- names=<name>`,
   `pack_assets`, `--import`, `tools/art/build_prop_scenes.gd --
   names=<name>`.
4. Place it by hand in a level plan with `town(...)` (never to fill ground),
   then rebuild the level ([levels.md](levels.md)).
5. If it breaks, add it to `data/tuning/breakables.cfg`. If it carries a
   light, add `props` to the `[light.*]` in effects.cfg.
6. Run `view3d_check`, and `tools/art/prop_sheet.gd -- names=<name>
   out=<png>` (a window) to hold the model against its picture.

A quest station is modelled in `scripts/blender/quest_props.py` (STATIONS,
its SCALE); `build_quest_art.gd` renders its two pictures and the same
`build_prop_meshes.gd -- names=quest_<name>` makes its one model with both
looks (art.md#props).

## A level

1. Write a plan in `tools/levels/` (`<id>_plan.gd`) with the level builder's
   kit ([levels.md](levels.md)); give it a `layout` number.
2. Build it: `tools/levels/build_level.gd -- <id> map=<png>`. Fix what it
   reports.
3. Add it where it is reached (the campaign order in `campaign.gd`, a hub
   gate in `hub_plan.gd`, a mode's map list) and its mood in effects.cfg
   `[level.<id>]`.
4. Run `quest_reach`, `view3d_check`, `first_minutes.gd -- <id> whole`.
5. Changing an existing level's map: bump its `layout`, run
   `save_fixtures.gd -- make` and fix `tools/saves/expected.json`.

## A feature

1. Create `src/features/<name>.gd` extending `GameFeature`: `id()`,
   `attach()` connecting to `game.events.<signal>.connect(...)`, `save()` and
   `restore()` (gets {} from older saves, so no new save version), optional
   `tally_rows()` and `draw_view(c)`.
2. List it in `src/features/features.gd` (`Features.ALL`; also
   `Features.LOOKS` if it only looks).
3. Put its id in `SIM_FEATURES` or `LOOKS_FEATURES` in
   `src/game_snapshot.gd` (`net_check` fails otherwise). Looks-only features
   use their own dice, never `game.rng`.
4. Numbers go in a tuning file, not the script.
5. Run `check_fixes` and `net_check`.

## A setting

1. Add a row to `src/setup_pages.gd`: label, key, default, choices, hint.
2. Bump the settings count in `tools/check_fixes.gd` (64 now).
3. Settings are not part of a save: no save version.

## A menu screen

1. Write a `UiScreen` subclass in `src/ui/screens/` (buttons via
   `add_button`; a `ZonedScreen` or `KeyedScreen` if keys are its rules).
2. Add its state to `UiRoot.SCREENS` in `src/ui/ui_root.gd`.
3. Set `main.state` to that state to show it.
4. `--import`, then `tools/menu_touch_check.gd`. See [ui.md](ui.md).

## A tuning number

1. Add the key to the right `data/tuning/*.cfg` with a comment.
2. Read it into a static var where the old constant was, keeping its name,
   e.g. `static var MAD_AT: float = BossData.get_value("boss_kit",
   "mad_at")`, or `ModeData.get_value(section, key, fallback)`,
   `HitData.value(...)`, `Difficulty.at(...)`. See [data.md](data.md).

## A game event

1. Add a `signal` with a comment to `src/core/game_events.gd`.
2. Emit it from the play code with `game.events.<signal>.emit(...)` at the
   moment it happens.
3. Listeners connect in their `attach()`. Signals are synchronous: keep
   listeners that change play in a fixed connect order.

## A boss

1. Give the kind a `title` in `data/tuning/enemies.cfg`.
2. Write a `BossMoves` subclass in `src/bosses/<name>.gd` (`fight_start`,
   `phase_changed`, `tick`, `weak_spot`, `telegraph`, `looks`, `dying`,
   `stagger_hit`/`stagger_rest`, `hog_wild`) and add it to `BossKit.MOVES` in
   `src/boss_kit.gd`. Keep fight state on the enemy or in a feature's save,
   not on the shared moves object.
3. Put its numbers in `data/tuning/bosses.cfg` under its own section.
4. Give its plan a `boss_arena` meta (box, lights, hazards).
5. Art: phase cels (`_p2_`, `_p3_`, `_wind`) and the 3D model's looks.
6. Run `boss_check`, `arena_check`, and `boss_rematch_check.gd -- bot` to set
   its PAR. See [bosses.md](bosses.md).

## A mode

1. Write a `GameMode` subclass in `src/modes/<name>_mode.gd` (stateless; state
   on the players and in the mode feature).
2. Register it in `Modes.rules_for` in `src/modes/modes.gd` (a name constant
   and a `match` arm).
3. Numbers in `data/tuning/modes.cfg` (`ModeData.get_value`).
4. For online play, add it to the mode row in `data/tuning/lobby.cfg` and
   `NetPlay.play_mode()`.
5. Run `mode_check`. See [modes.md](modes.md).

## A County Run card

1. Add it to `data/tuning/county.json` (numbers and every word on the card,
   its `short` words).
2. If it acts in a fight, add its effect in `src/modes/county_moves.gd`.
3. Run `county_check`. [COUNTY_RUN.md](../../COUNTY_RUN.md) is the full
   how-to for maps, weapons, upgrades and milestone abilities.
