# Tuning data

The game's numbers live in `godot/data/tuning/`. Edit these, not the scripts.
A running game from the project folder reloads `weapons.cfg`, `enemies.cfg`,
`effects.cfg` and `shots.cfg` within a second (`Tuning.watch()`, `tuning.gd`;
values are Godot ConfigFile text, so 6 and 6.0 differ). The newer files are
mostly read into static vars when their scripts load, so a change to them
shows at the next start (store.cfg's header says a match started after the
change uses it; `county.json` has its own stamp check in `county_data.gd`).
Each `.cfg` file's own comments say what every key means.

Scripts keep their old constant names as `static var`s loaded from these
files, so code reads `MAD_AT` or `TAGTEAM_PLAYERS` as before (for example
`static var MAD_AT: float = BossData.get_value("boss_kit", "mad_at")`).

## The files

| File | What it holds | Read by |
| --- | --- | --- |
| `weapons.cfg` | fire rates, damage, reloads, how each gun fires (hitscan, pellets, projectile, melee), sits in view and sounds; `flash_art`/`flash_size`, `penetrate`/`penetrate_damage`, `scope`/`scope_spread`, `thrown` | `weapons.gd` |
| `enemies.cfg` | enemy health, speed, reach, voice, boss `title` and drops; variants (`brain=`, `art=`, `height`, `tint`) | `enemies.gd`, `variants.gd` |
| `shots.cfg` | each shot's fall, size, glow and blast; `rolls` | the shots, breakables |
| `effects.cfg` | lights and glows (`[light.*]`), a level's mood (`[level.<id>]`), `[anim.<tile>]`, `[debris]`, `[water]`, `[relief]`, `[puddles]`, `[mud]`, `[sway]`, `[climate]` (the weather that changes play) | `Effects`, `view_lights.gd`, the 3D view |
| `breakables.cfg` | what breaks, its broken picture, hp, bits, cues, blast; `[windows]`, `[fence.<tile>]`, `never` | `features/breakables.gd`, `wall_breaks.gd` |
| `carry.cfg` | what a hand can take up and throw (`[thing.<picture>]`: weight, label, cue), a throw's speed, hit and shove, a hard landing, the brutes who throw things back (`[brutes]`) | `features/carry.gd` |
| `fire.cfg` | fire that spreads: the cap and budget, how often it spreads and bites, rain, the blasts that light things, puddles of shine, the floors and props that burn (`[floors]`, `[props]`: seconds, catch), what spills shine (`[spills]`), the stills' spray (`[stills]`) | `features/fire.gd`, `features/stills.gd` |
| `vehicles.cfg` | each vehicle kind: its model, hull, speeds, grip, step, floors, health, soak, seats, eye, ram and blade; `[all]` bumps, wrecks, dodging, blasts | `vehicle_drive.gd`, `features/vehicles.gd` |
| `effects.cfg` | lights and glows (`[light.*]`), a level's mood (`[level.<id>]`), `[anim.<tile>]`, `[debris]`, `[water]`, `[relief]`, `[puddles]` | `Effects`, `view_lights.gd`, the 3D view |
| `breakables.cfg` | what breaks, its broken picture, hp, bits, cues, blast, `pieces` (how it comes apart), `gone`, `never`; `[pieces]` (how many pieces lie about); `[windows]`, `[fence.<tile>]` | `features/breakables.gd`, `wall_breaks.gd`, `wreckage.gd` |
| `store.cfg` | the 5v5 store, economy and pvp: `[economy]`, `[item.*]`, `[rules.*]`, `[hit.*]`, `[hit]`, `[blast]`, `[spread]` | `src/modes/tactical_shop.gd` |
| `difficulty.cfg` | every number that changes with DIFFICULTY, one array each in the order EASY, NORMAL, HARD, HOG WILD: `[player]`, `[hands]`, `[bosses]` (the 5v5 bots' aim is modes.cfg `[bot_aim]`, by BOT SKILL) | `Difficulty` (`src/core/difficulty.gd`) |
| `hits.cfg` | how hits land: `[head]`, `[zones]`, `[reaction]`, `[reaction.store]`, `[ammo]`; keys are what `hurt()` is told did it | `HitData` (`src/core/hit_data.gd`), `hit_zones.gd`, `enemies.gd` |
| `modes.cfg` | the modes' rules: `[versus]`, `[coop]` (with the scaling table), `[deathmatch]`, `[tactical]`, `[bomb]`, `[hostage]`, `[tagteam]`, County Run (`[county_cards]`, `[county_coop]`, `[county_moves]`, `[county_orbs]`, `[county_spawner]`), `[tactical_utility]` (throwables), `[squad]`, `[squad_feature]`, `[idle_life]`, `[climbing]` (ladders, pull-ups, hands falling), `[hand_tactics]` (reload, peek, kick), `[hit_zones]`, `[tactical_bot]` | `ModeData` (`src/core/mode_data.gd`) |
| `bosses.cfg` | the boss scripts' numbers, one section per script (`[boss_kit]`, ...) | `BossData` (`src/core/boss_data.gd`) |
| `lobby.cfg` | the online lobby's rows and defaults: each row is [key, label, values, names]; a new online mode goes in the mode row (and `NetPlay.play_mode()`) | `src/net/net_play.gd` |
| `county.json` | County Run: every number and every word on a card, `start`, `tips`, `short`, the storm front (`storm`) | `county_data.gd` |
| `cuss_lines.json` | the cuss pack (the voice tools read it too) | `src/cuss_lines.gd` |
| `mundell_lines.json` | Mundell's wisecracks | `Barks` |
| `camera.cfg` | PHOTO MODE's camera and pictures `[photo]`, the KILL CAM's sampling, replay and camera `[kill_cam]`, QUALITY AUTO's measurement `[quality]` | `PhotoMode`, `KillCam`, `Quality` (static vars, read at start) |
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

## Rules for the big files

- **The guns are weapons.cfg's sections in order.** A new one goes at the end
  (section plus art), so saves and number keys keep the old order.
  `Weapons.HUNTER..MARKSMAN` are 16..25, the throwables 26..29.
- **A new enemy can be a section with `brain=<kind>`** (it acts as that kind)
  plus its art. `art="billy"` draws it with another kind's pictures until its
  own are in.
- **Lights**: `[light.*]` takes `pool`, `hot` (the shimmer's width; strength 0
  only shimmers) and `props` (every prop with that picture carries it); each
  gun has its own muzzle light, `[light.muzzle_<gun>]`.
- **A level's mood** is `[level.<id>]`: fog colour and distance, grade, cloud
  drift, lightning, rain (`rain`, `showers` for spells), `fog_banks`, `heat`
  spots, crows, fireflies. `[debris] wind_<level>` drifts the dust.
- **Breakables**: 5v5 maps' fences are `never`; keep a breakable fence tile
  out of `LevelTiles.TILED`.

To add a number, see [how_to_add.md](how_to_add.md#a-tuning-number).
