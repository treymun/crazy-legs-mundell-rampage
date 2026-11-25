# Tuning data

The game's numbers live in `godot/data/tuning/`. Edit these, not the scripts.
A running game from the project folder reads a saved `.cfg` again within a
second and puts it to use where it can (the dev console's watch,
`dev_tune.gd`; values are Godot ConfigFile text, so 6 and 6.0 differ):
weapons, enemies (those in play too), shots and effects through their
loaders, and the `static var`s the scripts read from the files, worked out
again from their own lines; the console says each change and where it took.
The console's `tune get/set/save/reload` tweak them in play (see
[gameplay.md](gameplay.md), the developer console); never online. What a
script keeps another way shows at the next level or start (store.cfg's
header says a match started after the change uses it; `county.json` has its
own stamp check in `county_data.gd`). Each `.cfg` file's own comments say
what every key means.

Scripts keep their old constant names as `static var`s loaded from these
files, so code reads `MAD_AT` or `TAGTEAM_PLAYERS` as before (for example
`static var MAD_AT: float = BossData.get_value("boss_kit", "mad_at")`).

## The files

| File | What it holds | Read by |
| --- | --- | --- |
| `weapons.cfg` | fire rates, damage, reloads, how each gun fires (hitscan, pellets, projectile, melee), sits in view and sounds; `flash_art`/`flash_size`, `penetrate`/`penetrate_damage`, `scope`/`scope_spread`, `thrown` | `weapons.gd` |
| `enemies.cfg` | enemy health, speed, reach, voice, boss `title` and drops; variants (`brain=`, `art=`, `height`, `tint`); in `[all]` the level of detail (`lod`, `lod_far`, `lod_step`, `lod_view_far`, `lod_view_angle`, `lod_hurt`) and `cover_budget`; the drops by need (`need_share`, `need_health`, `need_full`, `need_food`, pass 15) | `enemies.gd`, `variants.gd`, `enemy_lod.gd`, `drop_need.gd` |
| `shots.cfg` | each shot's fall, size, glow and blast; `rolls` | the shots, breakables |
| `effects.cfg` | lights and glows (`[light.*]`: the vehicles' lamps `vehicle_lamp`, a run's flares `run_flare` and `run_start`, a gun not had yet `new_iron` too), finding the guns (`[new_iron]`: see_reach, smell_reach, prompt_reach, prompt_facing, the glint's shine_size and shine_lift; `src/gun_finder.gd`), a level's mood (`[level.<id>]`), `[anim.<tile>]`, `[debris]`, `[water]`, `[relief]`, `[puddles]`, `[mud]`, `[sway]`, `[climate]` (the weather that changes play); pass 15's looks, read by `Effects.num(section, key, fallback)`: `[rim]` (the awake hands' and critters' rim), `[pickup_glint]` (the glint and the bob), `[hurt_looks]` (the vignette, the drain, the heart), `[enemy_muzzle]` with `[light.enemy_muzzle]` and `_scatter`, `[gun_smoke]` (the muzzle wisp), `[casings]` (each gun's shells) | `Effects`, `view_lights.gd`, the 3D view, `ActorRim`, `PickupLooks`, `HurtLooks`, `MuzzleLooks`, `features/debris.gd` |
| `breakables.cfg` | what breaks, its broken picture, hp, bits, cues, blast; `[windows]`, `[fence.<tile>]`, `never` | `features/breakables.gd`, `wall_breaks.gd` |
| `carry.cfg` | what a hand can take up and throw (`[thing.<picture>]`: weight, label, cue), a throw's speed, hit and shove, a hard landing, the brutes who throw things back (`[brutes]`) | `features/carry.gd` |
| `fire.cfg` | fire that spreads: the cap and budget, how often it spreads and bites, rain, the blasts that light things, puddles of shine, the floors and props that burn (`[floors]`, `[props]`: seconds, catch), what spills shine (`[spills]`), the stills' spray (`[stills]`) | `features/fire.gd`, `features/stills.gd` |
| `bench.cfg` | Mundell's junk bench: what scrap is worth and the most carried (`[scrap]`), what drops it (`[drops]`: hands by kind, bosses, breakables by picture, wrecked vehicles, set pieces), the pieces laid out a chapter (`[placed]`), where the benches stand and USE's reach (`[bench]`), and each mod (`[mod.<id>]`: gun, short, label, line, price, and the weapons.cfg keys it `set`s or `times`; its own `bayonet`, `burns`, `blast_scale`, `fuse`) | `BenchMods` (`src/bench_mods.gd`), `features/bench.gd` |
| `events.cfg` | the county events: how often and when, where never, the kinds and their weights, the night levels; the twister (warning, path, speed, core, reach, pull, hurt, what it breaks and flings), the stampede (herd, run, pace, trample), the raid (squad kinds, count, where from, shots, the still), the blackout (dark, the power coming back, the breaker, the flashlight's battery and beam, sight in the dark, lanterns) | `features/county_events.gd`, `src/event_*.gd` |
| `hound.cfg` | BLUE the hound: his health, mending and getting up, revives (USE held, a rind), his walk, run and heel, catching up when lost, his nose (bay and point reaches, how long each lasts and rests), fighting (sic, bite, pin, kicks, blasts, how brave), fetching (told, on his own), the whistle's aim; pass 10's getting about (trot, lope, easing; pass 12: the amble, decel, heel_gain and heel_extra, range_extra, heel_near and heel_far, turn_slow and turn_fast, aside_after and aside_pace, range_rest_still), ranging, stepping aside, pathing and the lost jump, hazards, backing off hurt, moods (sulk, howl, cower, growl, still, greet) and boarding a vehicle | `HoundNose.tuned`, `features/hound.gd` (read once per game) |
| `blast_looks.cfg` | how each blast looks (destruction pass 11, looks only): `[all]` the bits' caps, a chain's share, the view's kick, the debris sound; `[kinds]` shots.cfg kind to look; `[from]` what blew (a breakable's picture, a vehicle) to look; `[look.<name>]` fire, ball, life, lobes, column, rise, cap, smoke, scraps and their kind, fling, clods, puffs, sparks, embers, fire_rain, crater, flash, glow, kick, layer | `src/blast_looks.gd`, `features/gun_fx.gd` |
| `set_pieces.cfg` | the big breaks: `[all]` (never, gravity, hinge time, the warning and how far hands run, the crush by kind, pins, `low` cover, blasts', rams' and fire's share of the frame), `[barn]` (size, posts, sheets, walls, tiles, frame, post and panel hp, strain, posts out, crack, call), `[tower]` (spread, legs, tank, cap, staves, tiles, frame, leg hp, topple time, the flood and its wash), `[fuel]` (pipe and pump hp, leak speed, gas life, run step, burn, flare) | `features/set_pieces.gd`, `set_piece_shape.gd`, `set_piece_flow.gd` |
| `set_pieces.cfg` | the big breaks: `[all]` (never, gravity, hinge time, the warning and how far hands run, the crush by kind, pins, `low` cover, blasts', rams' and fire's share of the frame), `[barn]` (size, posts, sheets, walls, tiles, frame, post and panel hp, strain, posts out, crack, call), `[tower]` (spread, legs, tank, cap, staves, tiles, frame, leg hp, topple time, the flood and its wash), `[fuel]` (pipe and pump hp, leak speed, gas life, run step, burn, flare), `[looks]` (how they come apart, looks only: detail, early, kick, scatter, propped, sway, dust and splinters at most, shake reach) | `features/set_pieces.gd`, `set_piece_shape.gd`, `set_piece_flow.gd`, `set_piece_wreck.gd` |
| `vehicles.cfg` | each vehicle kind: its model, hull, speeds, grip, step, floors, health, soak, seats, eye, ram and blade, and how it looks on the move (springs, lean, squat, rough, rock, spray, sparks, brake skids, the airboat's slap and trim); the seat view (cab, cab_drop, cab_tilt, cab_lock) and how the seat feels (buzz, buzz_hz, chug, seat_dip); finding it and riding it (spotted, lamps, radio, window, ride_side, ride_back); `[all]` bumps, wrecks, dodging, blasts, the reaches (reach, reach_wide, spot_reach, spot_told), the radio, the window's guns and limits (window_guns, window_arc, window_spread, rider_spread, one_hand_turn) | `vehicle_drive.gd`, `features/vehicles.gd`, `vehicle_cab.gd`, `vehicle_finder.gd` |
| `effects.cfg` | lights and glows (`[light.*]`), a level's mood (`[level.<id>]`), `[anim.<tile>]`, `[debris]`, `[water]`, `[relief]`, `[puddles]` | `Effects`, `view_lights.gd`, the 3D view |
| `breakables.cfg` | what breaks, its broken picture, hp, bits, cues, blast, `pieces` (how it comes apart), `gone`, `never`; `[pieces]` (how many pieces lie about); `[windows]`, `[fence.<tile>]` (plank walls: `sheds`, `under_roof`, `straight`, `only_open`, `inside`) | `features/breakables.gd`, `wall_breaks.gd`, `wreckage.gd`, `plank_walls.gd` |
| `wreck.cfg` | how broken things' pieces move (looks): `[stuff.<name>]` (each breakables.cfg `stuff`: weight, bounce, grip, rolling and sliding losses, knock sounds, crack, burst, sinks; `like` another), `[form.<name>]` (board, stave, ring, disc, can, shard, chunk, sheet, clump: shares of those, a sheet's drag), `[impact.<kind>]` (shot, break, blast, kick, ram: reach, along, out, lift, spread, spin, most, hidden), `[knock]` (shot push, walkers' kicks, the knock sounds' cap) | `wreck_stuff.gd`, `wreck_physics.gd`, `features/wreckage.gd` |
| `store.cfg` | the 5v5 store, economy and pvp: `[economy]`, `[item.*]`, `[rules.*]`, `[hit.*]`, `[hit]`, `[blast]`, `[spread]` | `src/modes/tactical_shop.gd` |
| `difficulty.cfg` | every number that changes with DIFFICULTY, one array each in the order EASY, NORMAL, HARD, HOG WILD: `[player]`, `[hands]`, `[bosses]` (the 5v5 bots' aim is modes.cfg `[bot_aim]`, by BOT SKILL) | `Difficulty` (`src/core/difficulty.gd`) |
| `director.cfg` | the fight-rhythm director (pass 15): `[all]` `on`, `off_chapters`, `scan`, `near`, `crowd_full`, the hands never held near the start or a boss (`start_clear`, `boss_clear`), a peak's least, its spots (`peak_spot`, `peak_steps`), `peak_hunt`, when it is over (`peak_cold`, `peak_most`), `first_peak`, `build_least`, `peak_quiet`, `district_settle`, `quiet_gap`, the breather's guard (`guard_near`, `hush_reach`) and the HUD lines (`peak_lines`); `[pace]` by difficulty like difficulty.cfg: `hold_share`, `extra_share`, `peak_reach`, `peak_group_most`, `build_for`, `breather_for`, `long_fight` | `DirectorData` (`src/core/director_data.gd`), `features/director.gd`, `director_beats.gd` |
| `hits.cfg` | how hits land: `[head]`, `[zones]`, `[reaction]`, `[reaction.store]`, `[ammo]`; keys are what `hurt()` is told did it; dirty fighting `[kick]`, `[finish]`, `[finish.<move>]`, `[hazard]`, `[hazard.<kind>]`; the RAMPAGE meter `[rampage]` (pass 15: what each kill fills, the hold and drain, the boost) | `HitData` (`src/core/hit_data.gd`), `hit_zones.gd`, `enemies.gd`, `features/brawl.gd`, `brawl_hazards.gd`, `features/rampage.gd` |
| `modes.cfg` | the modes' rules: `[versus]`, `[coop]` (with the scaling table), `[deathmatch]`, `[tactical]`, `[bomb]`, `[hostage]`, `[tagteam]`, County Run (`[county_cards]`, `[county_coop]`, `[county_moves]`, `[county_orbs]`, `[county_spawner]`), `[tactical_utility]` (throwables), `[squad]`, `[squad_feature]`, `[idle_life]`, `[climbing]` (ladders, pull-ups, hands falling), `[hand_tactics]` (reload, peek, kick), `[hit_zones]`, `[tactical_bot]`, `[marker]` (the trail markers: when one is taken, when it is safe, the floor back at one) | `ModeData` (`src/core/mode_data.gd`) |
| `bosses.cfg` | the boss scripts' numbers, one section per script (`[boss_kit]`, ...; `[boss_lock]` each arena's room, doors, gates and spot; `[boss_retry]` the least health and rounds RETRY THE FIGHT brings; `[boss_fight] backup_share` each boss's share of the backup) | `BossData` (`src/core/boss_data.gd`) |
| `rumble.cfg` | controller rumble and phone buzz (looks only): `[all]` the LOW level, caps, the fade, how often a pad is told, an idle pad, the setting's taste; `[guns]` a pulse each gun (by weapons.cfg name), `[melee]`, `[dynamite]`, `[hurt]` (with its lean), `[boot]`, `[blast]` (reach, falloff, size), `[land]`, `[quake]`, `[boss]`, `[vehicle]` and `[vehicle.<kind>]` (hum, chug, chop, bumps, crashes, kerbs, ledges, wreck), `[phone]` | `RumbleData` (`src/core/rumble_data.gd`), `features/rumble.gd`, `src/rumble_out.gd` |
| `doppler.cfg` | Doppler on fast movers (sound only, pass 14): `[all]` on, the speed of sound (cells a second), the clamp (semitones), ease, slew, how speeds follow the drawn places (track, snap, fastest), the shortest cue that bends, forget; `[loops]` the flight loops' slots, reach, the hum's reach, fades, how often they are placed, a whoosh's quiet and loud speeds; `[family.<name>]` on and scale (car, airboat, mower, race, rocket, bolt, ball, cow, thrown, carried, saucer); `[fly]` a shot kind's loop [cue, level, pitch, family, whoosh]; `[carried]`, `[saucer]` theirs | `Doppler` (`src/doppler.gd`), `MoverSounds` (`src/mover_sounds.gd`) |
| `voice.cfg` | online voice chat: the radius and falloff, voices one player is sent at once, a talker's frames a second, the jitter buffer, the open mic's gate and hangover, the level, the radio's band, CLEAR 16K's (allowed, its top, voices a listener gets CLEAR, the lobby's and a home host's budget, a line's trouble and rest) | `src/net/net_voice.gd`, `src/net/voice_chat.gd` |
| `lobby.cfg` | the online lobby's rows and defaults: each row is [key, label, values, names]; a new online mode goes in the mode row (and `NetPlay.play_mode()`) | `src/net/net_play.gd` |
| `county.json` | County Run: every number and every word on a card, `start`, `tips`, `short`, the storm front (`storm`), a player map's horde (`custom_map`) | `county_data.gd` |
| `user_maps.json` | player maps: their limits, what a mode needs, the moods, every cell and thing the MAP SHED offers (a new one at the end of its list) | `UserMap` (`src/user_maps/user_map.gd`) |
| `cuss_lines.json` | the cuss pack (the voice tools read it too) | `src/cuss_lines.gd` |
| `mundell_lines.json` | Mundell's wisecracks | `Barks` |
| `radio_lines.json` | the county radio's words: Dub's lines by group, his crude ones, the scanner's pieces (the voice tools read it too) | `RadioStation` |
| `camera.cfg` | PHOTO MODE's camera and pictures `[photo]`, the KILL CAM's sampling, replay and camera `[kill_cam]`, the boss ending's timing and shot `[boss_end]`, QUALITY AUTO's measurement `[quality]` | `PhotoMode`, `KillCam`, `Quality` (static vars, read at start) |
| `servers.json` | the county servers the browser lists (`wss` for the browser build) | `NetBrowser` |
| `range_games.cfg` | the midway games: `[horseshoes]`, `[skeeball]`, `[dunk]`, `[bottles]` (the range's games row), `[fair_gallery]`, `[range_board]` | `RangeTuning` (`src/core/range_tuning.gd`) |

## Loaders

In `godot/src/core/`:

- `ModeData.get_value(section, key, fallback)`.
- `BossData.get_value(section, key)`.
- `HitData.section(name, except)`, `HitData.value(name, key, fallback)`,
  `HitData.ammo()`.
- `Difficulty.table(section, key)`, `Difficulty.at(section, key,
  difficulty)`.
- `RumbleData.pulse(section, key)` (a Vector3: weak, strong, seconds),
  `RumbleData.gun(i)`, `RumbleData.num(section, key, fallback)`,
  `RumbleData.level_scale(level)`.

## Rules for the big files

- **The guns are weapons.cfg's sections in order.** A new one goes at the end
  (section plus art), so saves and number keys keep the old order.
  `Weapons.HUNTER..MARKSMAN` are 16..25, the throwables 26..29.
- **A new enemy can be a section with `brain=<kind>`** (it acts as that kind)
  plus its art. `art="billy"` draws it with another kind's pictures until its
  own are in.
- **A new gun's rumble** is a line in rumble.cfg `[guns]` named as its
  weapons.cfg section; `rumble_check` fails a gun without one.
- **Lights**: `[light.*]` takes `pool`, `hot` (the shimmer's width; strength 0
  only shimmers) and `props` (every prop with that picture carries it); each
  gun has its own muzzle light, `[light.muzzle_<gun>]`.
- **A level's mood** is `[level.<id>]`: fog colour and distance, grade, cloud
  drift, lightning, rain (`rain`, `showers` for spells), `fog_banks`, `heat`
  spots, crows, fireflies. `[debris] wind_<level>` drifts the dust;
  `current_<level>` is the water's current (floating bodies and boards).
- **Breakables**: 5v5 maps' fences are `never`; keep a breakable fence tile
  out of `LevelTiles.TILED`.

To add a number, see [how_to_add.md](how_to_add.md#a-tuning-number).
