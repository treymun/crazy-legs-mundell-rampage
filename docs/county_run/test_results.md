# 2.0.0-dev.45 test results

Run on the owner's PC (Windows 11, Godot 4.7.2), headless unless noted, on
branch `polish-20`. Nobody on the agent side could listen to the sound, play
by hand or try a phone; every "played" result is a bot or a scripted check.

- **All checks** (`check_all.gd -- lint`, a scratch profile): every row passed (check_shader, verify_assets,
  check_fixes, save_fixtures, level_edit_check, quest_reach, bot_campaign,
  picture_check, net_showdown_check, net_server_check, menu_touch_check,
  county_check, gdformat) but two, both since fixed and re-run on their own:
  gdlint (three unused arguments) and county_net_check (a bar on how far the
  bots got by themselves; it now hands the party two levels halfway). The
  window tour matched the graphics-card references exactly (36 views).
  The full `net_check.gd` found two places a server's game and a player's
  copy part: a floating body's ring clock (since dev.43 at least, kept only
  where the looks-only water feature runs) and the bowling ball's hit list
  (keyed by object ids); both fixed and re-checked.
- **County Run co-op online** (`tools/county_net_check.gd`, new, in CI): a
  lobby server on Hickston, ALICE over ENet, BOB over the WebSocket side;
  40 s of play with the County bot steering each player in their own copy:
  level 3, 14 kills, 2 cards picked by the leader through her controls, both
  copies at the party's level and carrying the party's guns, 41 checks each
  with no parting (one on BOB's side from the test switching god mode on in
  the server's game only), back in the lobby once both were down.
- **Party rules** (`county_check.gd` `_party`): one kit for both, the party's
  XP, a partner's card ignored, the leader's card in both armories, a partner
  down is not the end, holding USE beside them stands them up, both down ends
  the run. Local party of two bots for 40 s: level 4, 25 kills (solo: level
  3, 18).
- **Daily run** (`_daily`): two runs of Hickston on the same day spawn alike
  (8 hands in 12 s), another day differs; the board keeps a name's best, best
  first, refuses another version and an old day; a post over the lobby's
  WebSocket comes back on the board (`net_server_check.gd`).
- **Walking prediction** (`net_loopback.gd -- seconds=30 lag=60 loss=0.03`):
  the player was drawn 6 ticks behind the host's path without it, 6 ticks
  ahead (0.03 cells apart) with it: about 200 ms less delay at 60 ms lag.
- **Browser online** (`net_server_check.gd`): BOB plays the whole match over
  the WebSocket side (plain ws on 127.0.0.1); wss on the real server was
  checked from the browser build after the release.
- **Deep water steering** (`county_play.gd`, Gator Bayou, 4 minutes, god
  mode): 107 kills and 121 hands spawned, hands reaching the player in 13 s
  (before: 75, 90, 16 s).
- **Melee blood** (`_melee_blood`): a crowbar hit wets the crowbar, never a
  pistol; the wet cel has 396 red pixels against 0.
- **Exit hang** (item 13): `county_play.gd` exited cleanly in three short runs
  and a 155 s run of all three maps; not reproduced.

# County Run test results (2.0.0-dev.41)

Run on the owner's PC (Windows 11, Godot 4.7.2), headless unless noted, on
branch `county-run` before it was merged into `combat-overhaul`. Nobody on the
agent side could listen to the sound, play by hand or try a phone: every
"played" result below is the bot (`tools/county_bot.gd`) or a scripted check.

## Rules and maps: `tools/county_check.gd` (in CI)

`COUNTY CHECK OK`. What it holds, each set up exactly:

- A run starts under COUNTY RUN at level 1, no XP, the crowbar and the .38 in
  two of three slots, the .38 loaded with spare rounds; the level's own drops
  off; every door open; COUNTY RUN is on the title.
- **Filling the third slot**: a weapon card with a slot open is taken and
  fills it, loaded.
- **Switching in a fight**: 1 and 3 pick slots, the next-gun key goes round
  the carried guns; switching keeps each gun's rounds and its upgrades.
- **Replacing at capacity**: a weapon card with all slots full asks which to
  swap and shows the upgrades it would lose; **CANCEL** goes back to the same
  three cards with nothing swapped; CONFIRM swaps the picked slot, drops that
  gun's upgrades and **keeps the perks and milestones**; forty swaps later no
  more than **three guns** are ever carried.
- **Offers**: no card twice, never a gun already carried, an upgrade for the
  gun in hand in every set while it has any left (60 of 60), a weapon from the
  first level up while a slot is free, fallback to other guns and perks once
  the gun in hand is maxed, no PATCH UP at full health; cards name their gun,
  rank and how long they last; weapon cards say how they play and what ammo
  comes with them.
- **One pickup across level 10**: worth three levels from level 8, it queues
  9, 10 and 11 in order, level 10 the milestone with all major cards; the
  world holds until all three are taken, then play goes on.
- **Milestones at 10 and 20**: 20 is a milestone too and leaves out what 10
  gave; a set mixes a way to stay alive and a move.
- **Two builds for one gun** (12 shots each at tough targets):

  | shotgun build | a line of four 6-8 steps off | a crowd of six 2 steps off |
  | --- | --- | --- |
  | TIGHT CHOKE 3 + BUCKSHOT BREAKER | **1969** | 1937 |
  | EXTRA BUCK 3 + BUCKSHOT BREAKER | 1101 | **2876** |

- **XP across walls and floors**: not taken two steps off behind a wall (XP
  MAGNET 3), not taken from a deck overhead, taken in view on the same floor
  (it floats in, pops +5); every drop lies on reachable floor (40 of 40);
  90 piles merge to fewer and keep their XP.
- **Timer pause**: while the cards are up the clock and the world stop and
  nothing spawns; the build screen holds them too; the clock runs again after.
- **Abilities**: SECOND WIND saves one fatal hit (health 50), only once; GRIT
  ARMOR turns 15 XP into 15 armor that takes a hit first; MUDSLIDE slides more
  than 3 steps on USE, then waits; GOOD BOOTS 3 walks 21% further; QUICK HANDS
  3 reloads in 27 ticks against 53; LAST STAND starts on a melee kill and
  halves what lands; CHAIN REACTION sets off follow-up blasts, at most 3 a
  shot; BREAKAWAY starts after breaking out of a crowd of five and speeds the
  feet and the reload.
- **Fair spawns**, each map, 40 tries: none nearer than 11 steps or in sight,
  every one on ground that walks to the start.
- **Enemy routes**: 14 hands spawned round a player who stands still and never
  shoots: Hickston 14 of 14 reached the player (median 11 s), the Quarry 14 of
  14 (14 s), Gator Bayou 13 of 14 in a minute (14 s; the last was still wading
  round the deep water).
- **Records**: kept per map in `county-records.json` (a check's under the
  cache folder), never in a campaign save.
- **Campaign untouched**: a campaign game is no run, the hooks hand back what
  they are given, the run saves nothing.
- **Each map through a death and a retry** (45 s of bot play, then death):
  death ends the run with its numbers, the map's best and the build; RETRY
  starts the same map at level 1 with the starting kit.

## By touch and mouse: `tools/menu_touch_check.gd` (in CI)

`MENU TOUCH OK`: the title's COUNTY RUN opens the map picker, BACK returns, a
tap on GATOR BAYOU starts a run there; a tap on a weapon card with all slots
full asks which to swap, a tap picks the slot, CANCEL gives back the same
cards; BUILD opens the build screen (world held), CLOSE shuts it; a tap takes
a perk card; the cards free the mouse pointer and a click takes a card; the
end shows RETRY, MAPS and TITLE; RETRY starts the map again, MAPS goes back to
the picker. Real touch events through the game's input; no script errors.

## Played: `tools/county_play.gd` (the bot at NORMAL)

Survival time to death, then a retry (2 minutes), then a long run in god mode
timing every 120 Hz tick (budget 8.3 ms). "Reached you": the share of spawned
hands that got within 4 steps of the bot (it shoots most of them first).

| map | run | survived | level | kills | most up | tick median | p99 | levels at |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Hickston | to death | 4:31 | 13 | 186 | 20 | 1.23 ms | 3.90 ms | 10 at 2:55 |
| Hickston | long, god | 15:00 | 27 | 908 | 39 | 1.62 ms | 4.31 ms | 10 at 3:15, 20 at 9:38 |
| The Quarry | to death | 2:49 | 9 | 92 | 14 | 0.73 ms | 2.52 ms | |
| The Quarry | long, god | 15:00 | 27 | 950 | 39 | 1.59 ms | 4.20 ms | 10 at 2:41, 20 at 8:45 |
| Gator Bayou | to death | 2:29 | 7 | 66 | 11 | 0.70 ms | 2.58 ms | |
| Gator Bayou | long, god | 10:00 | 17 | 312 | 27 | 1.59 ms | 3.69 ms | 10 at 4:16 |

- The live-enemy cap holds (38, plus an elite: 39 at most) on a 15-minute run.
- The worst single tick is the first of a run on a map not yet visited
  (about 50 ms: the spawn spots worked out once per map); the game now works
  them out while the map loads, before play. After it, the worst tick on a
  15-minute run was 9-31 ms (most runs under 10).
- Gator Bayou is the hardest map: its shallows slow you to 69% and the hands
  wade round the deep water to reach you. It runs at 80% of the other maps'
  spawn pressure (county.json `pressure`), and the start was moved from the
  lagoon island to the mud flat after the bot died there at level 1 in a
  minute.
- Tuning from these runs: a gentler opening (8 up at once, one every 2.8 s at
  the start) and a slower XP curve (level 10 had come at 1:53).

## Maps: `tools/map.gd validate`

Each map through a throwaway source (`map new zz_x base=county_<chapter>`):
0 errors, 0 warnings on all three after fixing what it found (a bridge's rails
across its own stairs; stairs whose foot started above the floor beside it:
the quarry's east bench is at 0, the bayou's shallows at -0.24). Pictures of
the footbridge, the catwalk, the boardwalk and the causeway in the
graphics-card view are in this folder.

## Regression

`tools/check_all.gd -- lint`: **ALL CHECKS OK** (gdformat, gdlint,
check_shader, verify_assets, check_fixes with every quick part (net, multi
bots, loopback, modes, geometry, maps, County Run), save_fixtures,
level_edit_check, quest_reach, bot_campaign (the campaign walkthrough),
picture_check, net_showdown_check, net_server_check, menu_touch_check,
county_check). `tools/tactical_check.gd -- rounds=3`: **TACTICAL CHECK OK**
(the 5v5 and 2v2 maps and modes with ten bots). `tools/mode_check.gd`: **MODE
CHECK OK** (co-op, deathmatch, team deathmatch).

Screenshots from a real window (`tools/county_frames.gd`, the tour above) are
in this folder: `title.png`, `map_picker.png`, `hud_hickston.png`,
`xp_quarry.png`, `cards.png`, `milestone.png`, `swap.png`, `build.png`,
`run_over.png`, `hickston_footbridge.png`, `quarry_catwalk.png`,
`bayou_boardwalk.png`, `bayou_causeway.png`.

## Not checked

- Sound: the collect chime, level-up stings and every other cue are reused
  game sounds; nobody listened to them in a run.
- Playing by hand: all play above is the bot's or scripted. Feel, readability
  in a real fight, and whether the difficulty suits a person are not known.
- A phone: the touch flow is checked with real touch events headless, not on
  an Android device.
