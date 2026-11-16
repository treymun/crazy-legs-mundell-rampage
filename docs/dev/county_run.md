# County Run

COUNTY RUN (dev.41) is the solo endless survival mode: the title's COUNTY RUN
(state "county", `CountyScreens.draw_maps`, `CountyInput.key_maps`; on screen
through `CountyMapsScreen`, see [ui.md](ui.md)) picks one of three big maps,
enemies never stop coming, survival time is the score and death ends the run.
[COUNTY_RUN.md](../../COUNTY_RUN.md) at the repo root is the how-to for adding
maps, weapons, upgrades and milestone abilities. The mode framework is in
[modes.md](modes.md).

## The mode

`Modes.COUNTY` ("county"; `src/modes/county_mode.gd`, `CountyMode`, one
player, `main_flow.gd start_county`/`open_county`). Its state is one
simulation feature, `features/county_run.gd` (id `county`, just before
`mode`; plain values; a run is never saved: F5/F6 refuse it and
`slot_source()` gives no game). The rest is static helpers in `src/modes/`:

- `county_data.gd` (`data/tuning/county.json`: every number and every word on
  a card; the moves, orbs and spawner numbers also have sections in
  `data/tuning/modes.cfg`);
- `county_build.gd` (slots, ranks, ammo caps, offers, taking a card, card
  text, the build summary);
- `county_spawner.gd`;
- `county_orbs.gd` (XP and supplies);
- `county_moves.gd` (upgrades and milestone abilities in a fight);
- `county_screens.gd` and `county_input.gd` (every screen, keys, taps,
  clicks);
- `county_records.gd` (`county-records.json` beside the unlocks; tools under
  the cache folder or `CountyRecords.folder_override`).

`CountyMode.run(game)` is the feature in a run (null otherwise),
`CountyMode.active(game)` the mode test.

## Hooks in the engine

All `GameMode` virtuals that hand back what they are given in every other
mode, reached through `Modes.holds`, `move_scale`, `incoming`, `hit_reach`,
`hit_amount`, `hit_after`, `blast_tuning`, which return at once in the
campaign:

- `game.gd tick` holds the world (`Modes.holds`: a choice on screen or the
  build screen; the clock stops);
- `_step_body` scales walking speed;
- `game_world.gd damage()` lets the mode take a hit first (armor, SECOND
  WIND);
- `game_combat.gd hitscan` asks for a swing's reach, the hit's damage and what
  happens after it (streaks, pierce, wide swing, shoves), `explode()` for the
  player's blasts' radius, strength and middle/edge shares;
- `Modes.shot_tuning` also asks the rules in a run (spread).

Fire rate, reload speed, extra pellets and projectile damage act from the
feature's own `shot_fired` and `ticked` handlers (`CountyMoves.fired`/`tick`:
a reload is sped by taking extra time off, never to 0, so the armory finishes
it itself). weapons.gd is untouched.

## Weapons

- Three slots (`f.slots`, weapon indices in the armory's own order, empty
  last: `sort_slots`, so 1-2-3, the wheel and the next-gun key agree). The kit
  is county.json `start` (crowbar and .38).
- The armory owns only what the slots hold; ammo goes through
  `CountyBuild.give_ammo` (DEEP POCKETS and the rifle's FIELD MAGAZINE raise
  the cap past weapons.cfg's).
- Number keys pick slots (`CountyInput.key_play`, before `_key_play`'s own),
  the campaign's other gun keys and pocket keys do nothing in a run.
- A weapon card fills an open slot; with all three full it asks which to swap
  (`CountyScreens.swapping`, CONFIRM / CANCEL back to the same cards); a swap
  drops that gun's upgrades (`"<gun>/<upgrade>"` ranks), perks (`perk/`) and
  milestones (`m/`) stay.
- The level's and the hands' drops are cleared every tick (`supply_rule` 2 and
  `game.pickups.clear()`); the run's own supplies are in the orbs.

## XP

`county_orbs.gd`: a kill drops `max_hp / per_hp` XP (elites times
`elite_times`, in piles) on a spot the player can stand on: not in a wall, not
deep water, on ground that walks to the start (`CountySpawner.reached`). Taken
within `reach` (XP MAGNET adds), on the same floor (`SAME_FLOOR`) and seen from
the eye; within `pull` it floats in. Piles merge past `merge_over`, keeping
their XP. A pickup worth several levels queues each (`f.pending`: [level,
milestone, gun in hand]) and they are offered in turn; every tenth is a
milestone. Art: `county_xp_<tier>_<n>` (copper, silver, gold bottle caps) from
`tools/art/build_county_art.gd`.

## Offers

`CountyBuild.offers`: one upgrade for the gun in hand when the level came
(else another carried gun's, else a perk that helps), a weapon while a slot is
open, the rest weighted (`WEIGHTS`, `SWAP_CHANCE`); never a gun already
carried, never two of a card, supplies only when they would help. Milestones
(`milestone_offers`): a weapon change for a gun carried, a way to stay alive,
a move, then the rest, then the spares (`again`).

## The spawner

`county_spawner.gd`: independent of kills and levels; a ring `near`..`far`
round the player sampled for a spot that is reached, dry, open, out of sight
and within `steps_most` flow-field steps; the cap and the rate grow with the
minutes, the pool's kinds come in by minute, health grows after
`health_from_minute`; a lull every `lull_every`; an elite every
`elite_every`. Hands far off or stuck unseen are moved to a fresh spot; bodies
past `corpses_kept` go (oldest first). The spawn spots and reached cells are
worked out once per level (by id: a broken window must not redo a whole-map
walk mid-fight; that was a 40 ms tick).

## The storm front

After v3.1.0 (track H), `src/modes/county_storm.gd`: a storm sweeps across the
map as the run goes on. Its state is the county feature's `storm_*` (plain
values and its own dice, seeded at the start from the run's rng state and
the map: a DAILY RUN's storm is everyone's, a party's the same on every
machine). The safe ground starts as the whole map (round the middle of the
spawner's reached spots); the first stage closes at county.json `storm.first`
seconds, later ones `every` after the last held, each called `warn` seconds
ahead on the HUD ("STORM FRONT 0:25"), closing over `close` seconds to
`radii[stage]` of the whole radius (never below `least`), the new ring's
middle a reached spot inside the last. Outside it a player takes
`hurt[stage]` a second and the wind shoves them round the wall and a little
back in; near the wall it throws boards, tin and hay (`storm_bits`, the break
bits' pictures) that hurt (`bit_damage`). It builds the climate's rain and
wind (`climate.storm`). Shown: the HUD line and a small ring map in the top
right (`CountyStorm.draw_hud`), the ring on the automap (`draw_map`) and a towering
wall of storm in the 3D view: two curtains with lightning and flying debris in them, the ground soaked and churned along it, the world past it dimmed and veiled ([view3d.md](view3d.md#county-runs-storm-front)).
COUNTY STORM (setting, `game.storm_on`, a sim option carried online) leaves
it out; a DAILY RUN always has it. `tools/climate_check.gd` checks the stages,
the hurt and the push, the setting and the daily storm; the cards, XP and
spawner are untouched.

## The maps

Plans over the chapters (`tools/levels/county_hickston_plan.gd`,
`county_quarry_plan.gd`, `county_bayou_plan.gd`, with `county_kit.gd`):

1. The chapter's plan builds.
2. `Kit.strip` takes the story off (hands, pickups, stations, notes, triggers,
   waves, exit, the road back, boss arenas, Bessie) and opens and unlocks
   every door.
3. Each plan cuts its shortcuts (`open_cells` like a neighbouring cell,
   `clear_fixtures`, `clear_things`), lays its raised routes (Geo decks,
   stairs, bridges; a flight starts from the floor at its foot: the bayou's
   shallows lie at -.24) and labels its landmarks.

Nobody steps off a deck into deep water (`can_walk`'s deep rule), so a
crossing over deep water is planks on the water. Build one with
`build_level.gd -- county_quarry` (county_hickston, county_quarry,
county_bayou). Validate one with a throwaway source: `map.gd -- new zz_x
base=county_quarry`, `validate zz_x`, then delete `godot/maps/zz_x.map.json`.
The browser fetches the chapter's pack for a county map
(`CountyData.base_of`, `Assets.CHAPTER_ART`).

## Checks

- `tools/county_check.gd` (CI, check_all; its quick part in check_fixes) holds
  the rules and plays each map through a death and a retry.
- `tools/menu_touch_check.gd` taps through the picker, cards, swap, build
  screen and end.
- `tools/county_play.gd -- md=<file>` (not CI) plays to death and long
  god-mode runs and tables time, levels, kills, horde and tick times.
- `tools/county_frames.gd -- out=<dir>` (a window) takes pictures of every
  screen.
- `tools/county_probe.gd` is a quick look; `tools/county_bot.gd` is the bot
  they share.
- `tools/county_net_check.gd` (check_all, CI) plays a party of two over ENet
  and WebSocket against a lobby server.

## Co-op

dev.45, `src/modes/county_coop.gd`: two to four players, one party build (the
same slots, ranks and perks; each player's own rounds and health; `share()`
puts a card's guns and rounds in every armory), the party's XP, the first
player up picks (`leader`), downs revived by a partner holding USE or back
after `RESPAWN_AFTER`, the run over when everyone is down; the horde scales
(`CAP_PER`, `TOUGH_PER`).

- Everything in a party's tick reads players by slot, never the local one:
  `CountyCoop.step` focuses each player in turn for the orbs and
  `CountyMoves.hands` (split from `streaks` and `world`, in the same order, so
  a solo run plays as before), the spawner rings a player a tick and each hand
  chases its hunted player.
- Online it is a lobby mode ("county", the county maps in MAP_ROWS: a county
  map makes the mode); the leader's card rides Controls.buy
  (`CountyCoop.encode`, applied in `CountyMode.hold_controls` before the held
  world returns), number keys, R and USE ride TacticalScreens' pending inputs,
  nobody takes a leaver's place, the lobby goes back when the run is over, and
  the host's `seed` gives each match fresh dice.
- Facts the run keeps on enemies and shots (`Enemy.county_elite`,
  `county_watch`, `Shot.county_scaled`) are fields, never keyed by instance id
  (a client's copy has other ids).

## DAILY RUN

dev.45, `src/modes/county_board.gd`: T on the picker; the day's (UTC) dice for
the map (`seed_for`), `f.daily`. Its end posts to the first server in
servers.json and the picker asks for each map's board: a BOARD knock
(NetWire.BOARD) on the lobby's port, answered by `answer()` from
`county-board.json` on the server (the last 7 days; a name's best counts; a
wrong version or an old day is refused). Posting happens in the front end
(`CountyScreens.board_frame`), never from a tool.

## HUD, cards and polish

- **dev.45 HUD and cards**: the status bar is the run's own (`hud.gd
  _draw_county_bar`, `plate_county`: VEST, slots, LEVEL with XP); the cards
  are `county.json`'s `short` words (`CountyBuild.describe` badge, pips, big,
  small_trade, detail).
- **dev.43 polish**: elites wear an ELITE tag and a health bar
  (`CountyScreens._elite_tags`), the HUD counts a lull and warns of an elite,
  the cards' heading drops in, tips (county.json `tips`) show for a player's
  first three runs (`f.tips`), the end adds elites, XP, damage and the best
  streak (`f.elites_down`, `f.hurt`, `f.best_streak`), supplies glow, and the
  maps have lamps at the new gates and crossings and burn barrels.
