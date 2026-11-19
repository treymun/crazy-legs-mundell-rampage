# Modes

`src/modes/` holds the rules a game plays by; `features/mode_feature.gd` (id
`mode`, a simulation feature, last in `Features.ALL`) holds what they remember
and runs their hooks. Their numbers are in `data/tuning/modes.cfg` (co-op,
deathmatch, 5v5 rounds, bomb, hostage, tag team, throwables, ...; read with
`ModeData.get_value(section, key, fallback)`) and `data/tuning/store.cfg` (the
5v5 store, economy and pvp hits). The **campaign** is the default and nothing
in either runs for it: its feature saves nothing (old saves, fixtures and
every single-player check are as before).

The multiplayer foundation (players, snapshots, the host) is in
[multiplayer.md](multiplayer.md); County Run in [county_run.md](county_run.md).
To add a mode, see [how_to_add.md](how_to_add.md#a-mode).

## Framework

`GameMode` (`game_mode.gd`) is one shared, stateless object per mode
(`Modes.rules_for(name)`):

- `start` (first tick, after the posse), `joined`/`left`, `tick`,
  `downed(p, by)` (health reached 0; `by` the slot whose hit landed, from
  `st.blame`, -1 the world or an enemy), `respawn`, `defeated` (the death
  screen: `game.defeated()`, which the front end asks instead of
  `player.health <= 0`), `over` (versus results), `pickup`,
  `hurt_scale(attacker, victim, blast)` (friendly fire), `won`, `scores`.
- State lives on the players (`Player.down_at`, `revive`, `holding`, `frags`,
  `deaths`, `team`, `downed_by`) and in the feature (plain values: `mode`,
  `scaled_upto`, limits, arena, spawns, pickups coming back).
- A save keeps the mode and every player past the first (place, health, guns,
  pockets; frags for all) in the features block (no new save version), so a
  co-op save loads as co-op with its partners.
- `Modes.setup(game, name, count, options)` before the first tick;
  `Modes.rules(game)`, `Modes.mode_of(game)`, `Modes.is_versus(game)`.
- A player's hit on another goes through `Modes.player_in_line`/`player_hit`
  (hitscan), `shot_strikes` (`_hits`) and `blast_hit` (explode), which blame
  the shooter; `Controls.hold` is USE held down (the front end sets it from
  the bound key).

## Co-op

`coop_mode.gd`. Keys and the PA lead shared (`Players.SHARED`), guns, health,
rounds and pockets each player's own.

- A gun or ammo pickup goes to EVERY player up (each gets the toucher's
  amount); pocket items to the toucher.
- At 0 a player is DOWN: a partner holding USE within 1.3 for 3 s stands them
  up with 35 (`REVIVE_*`; letting go eases the progress back); left 20 s they
  come back beside the nearest partner with 50, guns kept. Lost only when
  everyone is down at once.
- A partner's bullets pass through you, their blasts bite at half, your own
  in full.
- A boss fight begins when ANY player up walks into its arena
  (`BossKit.party_in_arena`); the bar, boss loop and checkpoint follow the
  local player; a retried fight, a loaded save or a rematch brings the
  partners to player one's side (`Modes.gather`, main_flow `_take_mode`); the
  entrance hold and hitstop are single-player only (as before).
- The exit ends the chapter for the whole party (anyone down comes along with
  35) and each partner carries their own kit into the next game
  (`Modes.carry`).
- Every area attack hits everyone in it: steam and chalk (`update_hazards`),
  burning slicks (per-player bites: `s[3]` player one, `s[4+slot]` the rest),
  race cars (`car[2]`, `car[3+slot]`; the shake and the hit sound only on a
  hit now), Maw's rolling pin, stomp rings (`ring[3]` player one, bits of
  `ring[4]` the rest) and loose beam (`beam_hurt`), arena fire, rollers, the
  log carriage, steam jets and core pulses (already per player).
- Vehicles (`features/vehicles.gd`, [gameplay.md](gameplay.md#vehicles)) are
  the campaign's and co-op's only: a partner rides along in the airboat's
  second seat, or beside the stock car's driver (riding shotgun, shooting
  out of the window, the cab seen from the passenger seat; no partner tag
  over someone in the same vehicle); a set piece's reward goes to everyone
  in it. Versus, the 5v5 and County Run have none, so nothing online
  drives (a seated client's prediction leads only its aim).

### Scaling

`CoopMode.SCALE` (modes.cfg `[coop] scale`), applied on the first tick and to
every enemy that joins later (`scale_new`):

| players | hands' health | bosses' health | extra hands at the start |
| --- | --- | --- | --- |
| 1 | x1 | x1 | none |
| 2 | x1.25 | x1.6 | a partner beside every 3rd hand about |
| 3 | x1.5 | x2.2 | every 2nd |
| 4 | x1.75 | x2.8 | every hand |

The extras join after the level's own (the posse feature saves them).

## Deathmatch

`deathmatch_mode.gd`. No enemies (cleared at the start: the level's own,
posse, critters).

- Spawn points worked out from the arena (`Modes.spawn_points`: open dry cells
  with nothing within .45, reachable from the middle, spread farthest-first,
  inside a boss kind's `box` when the arena names one); everyone starts with
  `Modes.give_kit` (crowbar, .38, shotgun).
- Every hit lands at `Modes.PVP_SCALE` (.5) of what it does to a hand, your own
  blast too. A kill is a frag, a fall to the world or your own blast takes one
  off; back 3 s later at the spawn point farthest from everyone up, full
  health, the kit again. Pickups come back 20 s after they are taken; the
  versus maps lay theirs out in their plans' `arena_loot()` (polish pass 9).
- The frag limit (10) or the time limit (300 s) ends the match: `game.won`
  (play stops) and the results screen in the tally's county-fair look
  (`ModeScreens.results`, from `hud.gd intermission`; ENTER another round, ESC
  the title). Never saved (F5 says so); never the death screen. On the range
  the medic, refills and station cards are off.
- Arenas (`Modes.ARENAS`): `range`, `hub`, `hickston:boss`, `hickston:jerry`,
  `fair:rudy`, `sawmill:foreman`.

## Team deathmatch

`team_deathmatch_mode.gd`: RED slots 0 and 2, BLUE 1 and 3; teammates'
bullets and blasts pass by; the frag limit is the team's score. The other
players' pictures and tags wear their team's colour (`ModeScreens.TEAM_TINTS`,
`TEAM_INKS`: RED warm, BLUE cold), not the slot colours of co-op and
deathmatch. Tags over several players step up out of each other's way.

## The 5v5 round modes

`tactical_mode.gd`, under it `bomb_mode.gd` search and destroy and
`hostage_mode.gd` hostage rescue; money and guns `tactical_shop.gd`, the HUD
and buy menu `tactical_screens.gd`, the bots `tactical_bot.gd` with
`tactical_nav.gd`'s whole-map step fields. Online play is in
[multiplayer.md](multiplayer.md#online-5v5).

### Rounds

- Ten players, teams by slot (HOGS the even slots, GATORS the odd); each half
  one plays the OUTLAWS (`st.outlaws`), sides and money swap after
  `rounds_to_win - 1` rounds, first to `rounds_to_win` (7, `--rounds=`) wins,
  a draw after twice that less two.
- A round: FREEZE (6 s, held still, the buy menu on B), live play (bomb 105 s,
  hostage 115 s), POST (5 s). Buying near your own spawn through the freeze
  and BUY_WINDOW (20 s) after. Survivors keep guns (topped up) and vest; the
  fallen get the crowbar and .38.
- The outlaws plant the shine bomb (hold USE 2.6 s on site A or B; 35 s fuse;
  deputies hold USE 7 s, 3.5 s with wire snips, to cut it; a blast of 420
  falling off over 10 cells); in hostage rescue the deputies attack, carry a
  hostage (USE, walking) into the rescue box, one out wins.
- Hits between players use TacticalShop's table (`GameMode.pvp_damage`/
  `blast_damage`: times what the gun does to a hand, a head multiplier above
  `HEAD_FROM`, the part a vest lets through), never a teammate's; teammates
  walk through each other.
- The economy is TacticalShop's numbers (store.cfg `[economy]`: 800 start,
  16000 cap, 3250/3500 a win, 1400 + 500 a loss in a row up to 3400, +800 each
  for a lost round with the bomb planted, kill rewards by gun).
- While this machine's player is out the view follows a teammate up (`main.gd
  _follow_view`; `TacticalScreens.human` is the slot the keys drive).
- In a 5v5 round the number keys are the round shooters' (1 long gun, 2
  sidearm, 3 crowbar, 4 dynamite; TacticalScreens). Never saved.
- In the 3D view the players are the campaign's own models (outlaws `billy`,
  deputies `yard_deputy`) and the hostages `coot` (tinted): each sprite names a
  `ModeBodies` stand-in (`src/modes/mode_bodies.gd`), an Enemy that is never in
  `game.enemies` and never ticks, posed each frame from the player (place,
  heading, gait, height, when they fell: the model falls over its five steps,
  then lies). A carried hostage is drawn, and tagged, at the carrier's heels
  (`TacticalScreens.hostage_place`); play keeps the hostage's own place. The
  freeze countdown sits at the top, clear of the tags.

### The bots

`TacticalBot` plays every slot but this machine's, in any build (main_flow
`_take_mode`); they buy a rifle or save, take the map's `routes` to the team's
site of the round (`plan_site`), hold the map's `holds` on defence, call foes
seen on a site, plant, defuse, carry and chase, and pick the gun for the
distance.

**Skill.** BOT SKILL (the lobby's row, PLAY VS BOTS' BOTS row, `bot_skill`
in `Modes.HOST_SETTINGS`): EASY, NORMAL (the default), HARD, HOG WILD, or
MIXED (each bot its own, modes.cfg `[tactical_bot] mixed` by place in its
team, both teams alike: one EASY, two NORMAL, two HARD);
`TacticalBot.skill_for`. Unset (-1) it follows the game's DIFFICULTY.

**Aim** (`src/modes/bot_aim.gd`, `BotAim`; numbers in modes.cfg `[bot_aim]`
by skill). Since 3.2 polish the bots no longer settle onto a foe in a few
tenths and hit nearly every shot:

- a foe coming into view is noticed after `reaction` (x0.8..1.35, more off
  the middle of the view and far away, a third for a foe seen within
  `memory` s: a re-peek); they notice only inside about 115 degrees in front
  (`VIEW_HALF`) unless within 2.5 cells;
- the crosshair is driven onto the foe by a damped spring (`spring`,
  `damping` under 1 so it overshoots, `turn_most`), the first fling landing
  off by `flick` of the turn;
- the hand's aim point strays (`noise`, re-picked every .12 to .3 s), more with
  the bot's own speed, the foe's sideways speed, range and a burst's length;
  a strafer is followed only by `track` of its motion (the rest is lag);
- it fires when its crosshair is inside `trigger` times the body's width of
  where it means to aim, so the stray is where misses come from; automatic
  guns go in bursts of `burst` at range and rest (`rest`), spraying inside 6
  cells (`spray_inside`), and a pistol past that taps `pistol_tap` s apart;
  the gun's climb is pulled down by the same spring and each shot's
  kick throws the hand by 1 - `recoil`;
- `head` is where up the body it aims (head hits come from the vertical
  stray): the belly, .28 EASY to .44 HOG WILD. Before 3.3.0 it was the chest
  (.52 to .62) and some 60% of NORMAL bots' pistol kills in a match were head
  shots (the 5v5 head multiplier makes the killing hit a head one far more
  often than the hits are); now some 30-40% of their pistol kills and 27% of
  their rifle kills (`tactical_check`, grainyard, salvage and holler), and
  `bot_check` holds every skill's head hits on a strafer to `MOST_HEADS`
  (15%) without its kill, hit-rate and first-hit bounds moving. Its dice are the bot's own (seeded by slot): bots play on the host
  only and their controls are what every copy plays, so `game.rng` is left
  alone.

**Play.** Each bot has a persona (modes.cfg `personas` by its place in its
team, both teams alike: aggressive,
careful, support). In a fight a rifle, machine gun, sniper or pistol user
stands to shoot once it has noticed the foe (firing only when nearly
stopped; the careful kneel past 9 cells), side-steps between bursts, and
under its persona's `fall_back` health (and the foe not nearly done) backs
off, gun up, to the nearest spot the foe cannot see (`BotTactics.cover_spot`,
at most 14 spots, looked for every .6 s), waits there 2..3.5 s with the gun
on where the foe was, then comes back on the angle (the re-peek's short
reaction); an attacker holds on to .6 of that line and nobody on the
attack hides with under 30 s left (`ATTACK_FALL_BACK`, `NO_HIDING`). A
teammate falling within `trade_reach` draws it to trade (gun on
where the killer stood) for `trade_for` s; a foe lost (not killed) keeps its
gun there 3 s, and the aggressive push there for `push_lost` s; gunfire that
hurts it with nobody in sight turns it to the nearest foe who just fired.
Nobody busy with the objective (carrying, planting, cutting the fuse,
carrying a hostage) falls back or trades. Route points are moved aside by
team place (`_spread_out`) so a team walks abreast, and after the gathering
they go in one after another (aggressive first, careful last). An attacker
whose next route point is 6 or more steps nearer through a whole boarded
cover cell in sight within 7 cells stands and shoots it open
(`BotTactics.board_for`, once a leg, not the careful). Everyone keeps out of
the round's fires (`keep_out_of_fire`). The team buys together: when its
middle cash is under 3000, a bot that could only just buy (under 4600, the
losses not yet run to two) saves with it (`_team_cash`). Far goals walk the
step field of their cell snapped to a 3-cell grid and route points their own
(`_nav_for`), near ones straight when in sight, so passing goals share the
whole-map fields. There are no ladders on the 5v5 maps.

**Team radio** (`src/modes/tactical_radio.gd`): short lines at the view's
left from this machine's teammates, worked out each frame from what every
copy already holds (looks only, nothing carried, nothing on the server):
foes a teammate has in front of them ("HOG 3: TWO ON B"), planting, planted,
the bomb dropped, a fuse being cut, a hostage carried out, a teammate hit
under 40. A speaker waits `radio_gap` between lines and the team
`team_radio_gap`. There are no radio voices (text only).

**Before and after** (`tools/bot_check.gd -- bench trials=12`, grainyard,
60 Hz, the outlaw rifle against a target in a vest, cap 6 s; median time to
the first hit / median time to kill / hit rate):

| skill, target | 4 cells | 8 cells | 14 cells | 22 cells |
| --- | --- | --- | --- | --- |
| EASY strafing, before | .53 / 1.20 / 98% | .75 / 1.70 / 58% | .90 / 2.57 / 25% | 1.02 / 2.47 / 20% |
| EASY strafing, after | .78 / 2.13 / 47% | 1.03 / 3.82 / 31% | 1.73 / 5.37 / 21% | 5.17 / 6+ / 8% |
| NORMAL strafing, before | .43 / .90 / 100% | .43 / 1.02 / 90% | .55 / 1.43 / 58% | .67 / 1.55 / 36% |
| NORMAL strafing, after | .62 / 2.00 / 48% | .90 / 2.42 / 48% | 1.33 / 3.18 / 31% | 1.80 / 4.05 / 22% |
| NORMAL standing, after | .65 / 1.17 / 80% | .73 / 1.40 / 74% | .88 / 1.85 / 47% | 1.33 / 3.75 / 21% |
| HARD strafing, before | .43 / .90 / 100% | .43 / .90 / 100% | .43 / 1.25 / 78% | .68 / 1.13 / 50% |
| HARD strafing, after | .47 / 1.28 / 75% | .68 / 1.70 / 54% | 1.10 / 2.52 / 38% | 1.07 / 2.27 / 32% |
| HOG WILD strafing, before | .43 / .90 / 100% | .43 / .90 / 100% | .43 / 1.02 / 86% | .55 / 1.25 / 52% |
| HOG WILD strafing, after | .38 / 1.08 / 77% | .65 / 1.35 / 73% | .68 / 1.43 / 62% | .93 / 1.90 / 37% |

(Before, NORMAL to HOG WILD hit a strafer 90..100% inside 8 cells and killed
it about as fast as the rifle fires, the first hit .4 s after it came into
view. A decent player lands a first hit in about .5 to .7 s and hits a
strafer maybe half the time up close: NORMAL is now about that, HARD a little
better, HOG WILD near the old bots at range but no longer perfect.)

### The maps

`tools/levels/grainyard_plan.gd` (Puckett Grain Co-op), `holler_plan.gd`
(Holler Distillery) and `salvage_plan.gd` (Mundell's Salvage), original
layouts each built for both modes; a plan's `meta["tactical"]` (level JSON
`tactical`, `LevelData.tactical`) holds `attack_spawns`, `defend_spawns`,
`sites`, `hostages`, `rescue`, the bots' `routes` and `holds`. The 2v2 maps
are pumpngo, pineacres and landing.

The title's MULTIPLAYER's PLAY VS BOTS (state "showdown") picks mode, map,
length and rules (`main_state.gd showdown_*`); the command line is
`--mode=bomb|hostage [--arena=holler] [--rounds=7]`.

### The guns

Ten guns were added for it, at the end of weapons.cfg (so saves and number
keys keep the old order), each side with its own pistol, shotgun, SMG, sniper
and machine gun (TacticalShop.ITEMS `who`; SIDE_PISTOL the kit's): `hunter`
(HOG HUNTER .30-06, scoped bolt-action) and `mower` (CORN MOWER, belt-fed) the
outlaws', with `hogleg` (HOGLEG .44) and `grease_gun`; the deputies'
`county45` (their kit pistol), `star357`, `riot_pump`, `tommy` (SQUAD TOMMY),
`patrol_bar` and `marksman` (COUNTY MARKSMAN, scoped semi-auto).
Weapons.HUNTER..MARKSMAN are 16..25.

- Each is modelled in `scripts/blender/weapon_views.py` (pistols on the
  revolver plate's rig, the grease gun too; the rest the shotgun plate's), cut
  by `build_weapon_views.gd`, has its own flash style (`build_gun_fx_art.gd`
  STYLES: hunter, mower, auto45, magnum, pump, smg, bar, marksman), muzzle
  light (`[light.muzzle_<gun>]`) and sounds in audio_spec (a report, room
  twin, dry, equip and reloads each; ElevenLabs, about 365 credits for all
  ten).
- The ten side guns' models wear their side (`weapon_views.py` `O_*` outlaw
  materials: bluing rubbed brown, rust, brass tacks, twine, snakeskin, XXX;
  `D_*` deputy ones: blue-black steel, black polymer, silver stars, brass
  county tags, a light on the riot pump); `pbr(edge=, cavity=)` rubs real
  edges and darkens creases, used only by those materials so the campaign
  guns render as before.
- **Scopes.** A gun with weapons.cfg `scope` puts the scope up and down on ALT
  FIRE (game.gd `_step_hands`, `Player.scoped`, carried in snapshots with the
  player), fires with `scope_spread` while it is up (weapons.gd), and
  `src/scope.gd` zooms the view (`View.base_focal` = `fov_focal` times the
  zoom; aiming slopes use the same focal, so the cross-hair stays true) and
  masks it to a glass; the mouse turns slower by the zoom.
- No campaign pickup gives them; the 5v5 store sells them and the range and
  console can hand them out.

### The throwables

Four more (Weapons.FLASH_JAR..FIRECRACKER_CAN, 26..29; weapons.cfg `thrown`:
dynamite-like poses, `shot_life` a fuse; shots.cfg `rolls`: they tumble as
thrown dynamite does; the cocktail bursts on impact), modelled on the
crowbar plate's rig, with their own flight pictures (`fx_<name>`, cut from the
raw render by `build_weapon_views.gd`). `game_combat.gd explode()` hands them
to `src/modes/tactical_utility.gd` (numbers in modes.cfg
`[tactical_utility]`): a flash blinds by distance and facing (`st.blind`, the
white-out over the view, bots blind too), smoke clouds (`st.clouds`,
`fx_smokecloud_*`; bots' sight held by `smoked()`), fire (`st.fires`,
`fx_flame_*`, bites blamed on the thrower; smoke puts it out) and decoys
(`st.decoys`, the thrower's gun in bursts). They tick in any mode (the range
has them). The store has two pages (guns, gear + thrown; four throwables at
most); the barker announces over the PA (`ann_*` voice cues) and the planted
bomb beeps faster.

### Store rules

`TacticalShop.RULES` (store.cfg `[rules.*]`), the mode feature's
`store_rules`, a `Modes.HOST_SETTINGS` key: ANY GUNS, SHOTGUNS ONLY, PISTOL
PARTY, SNIPER DUEL, ECO WAR (nothing over 1500), BIG MONEY (16000 every
round). A rule limits the kinds sold (`by_rules`, inside `allowed`, so the
store, the buy check and the bots all follow it), the dearest item, and the
cash a round starts with (`rule_cash`: `cash` exact, `least` a floor so the
rules' guns are in reach). Bots whose usual buy is not for sale take the
dearest gun that is (`rule_pick`). The lobby's RULES row, the picker's RULES
row, `--rules=`; `tactical_check.gd -- rules=<id>` checks nobody holds a gun
the rules do not sell and that the bots buy the ones they do.

### TAG TEAM 2V2

Search and destroy two a side (`Modes.TAGTEAM_MAPS`, `TAGTEAM_PLAYERS`,
`TAGTEAM_OPTIONS`, modes.cfg `[tagteam]`: first to 9, 1:30 rounds, 15 s buy;
`Modes.is_tag_team`), not a mode of its own: everything 5v5 applies. Its maps
have one site ("A") and holds "A" only (two defenders); the picker's third
MODE, `--mode=tagteam`, or a 2V2 map in the online lobby (which sets the
format). `tactical_check.gd` plays the 2v2 maps four players, bomb only;
`map_timing.gd` times them.

### 5v5 gun feel

`TacticalMode.shot_tuning`, `TacticalShop.MOVE_SPREAD`, `REACH`, `FALLOFF`
(store.cfg `[spread]`, `[hit.*]`): weapons.gd asks `Modes.shot_spread` for
every hitscan and pellet shot's spread and reach; outside the 5v5 modes it is
the gun's own, unchanged (the campaign never asks the rules).

- In them a gun strays more on the move by its kind, more in the air, less
  crouched and still, and some guns reach further with their damage falling
  off (`pvp_damage`); the spread is shown as ticks round the crosshair
  (`TacticalScreens._spread_marks`).
- The bots stand to shoot with the guns that need it, scope a sniper rifle
  past arm's length, and buy by a style per slot (`TacticalBot.STYLES`).
- The 5v5 maps' stock plank fences never break (`breakables.cfg` `never`); their
  boarded cover does, and stands again each round ("Breakable cover" above).
- The bots' attack gathers at the last route point no hold of the target site
  can see (`TacticalBot._stage_for`, `_released`, `STAGE_MOST`) and goes in
  together, guns on the site's holds (`_corner_to_check`).
- Hostage rescue has nearer rescue points (`tactical` `rescue_more`,
  `HostageMode.rescue_boxes`) and carriers run.
- The 5v5 HUD: `hud.gd _draw_team_bar` (VEST, side and goal, THROWN;
  `TacticalScreens.bar_state`), the results (`TacticalScreens.results`), the
  players drawn as `billy` (outlaws) and `yard_deputy` (deputies) cels at the
  hit box's height (`TacticalScreens.player_sprite`).
- Balance is read off `tactical_check.gd`'s summary (side wins per map and
  mode, kills by gun, plants, `deaths=` for where players fell); bot matches,
  so only a guide.

### Breakable cover

The 5v5 maps' boarded planks (`cover_boards`, a fresh pine X nailed over grey
boards so they read as what shoots through; tiles `cover_boards`,
`cover_boards_hit` and the gap picture `cover_boards_gap` by
`tools/art/wall_break_art.gd`) are `wall_breaks.gd` fence cells
(`breakables.cfg [fence.cover_boards]`, hp 150: about five rifle hits or a
stick of dynamite): shot about, then broken through into floor, sight and a
way for the bots' step fields. A plan places them with `b.fence(x0, y0, x1,
y1, top, "cover_boards")`; the stock plank fence (`stockyard`) still never
breaks on these maps. Placed: grainyard's A-side fence to the co-op lot,
boarded cover in the rail yard, A long and at the rail-yard end of co-op row
(clear of the mid hold's look); holler's pen fences and a boarded gap in the
hedge from the woodshed yard into the pens (7 steps round, 3 through);
salvage's boarded slot through the canyon's tyre wall (14 steps round, 4
through). Crates, barrels and the gas cans the maps stand break as before
(`breakables.gd`).

Every round's start puts it all back (`src/modes/round_cover.gd`,
`RoundCover`): `remember()` keeps each game's walls, floor and furniture as
built (from `Modes.setup`, before anything can break: a client's copy too),
`put_back()` (`TacticalMode.begin_round`) lays them down again when anything
broke, rebuilds the level's lookups, shuts the opened cells in the flow
fields and tells `wall_breaks` and `breakables` to `forget()`. Every copy does
it on the same tick; a copy that missed the round's start (put back on a later
snapshot) lays its level down first (`GameSnapshot._apply_facts`). Nothing new
is carried. `tools/cover_check.gd` (check_all quick) breaks a board and a prop
on each map, checks the floor, sight and the shorter way, the next round's
reset, and a copy kept up by snapshots alone.

### Round MVP and the bots' gathering

- At a round's end the kill feed shows `ROUND MVP  <name>  <n> KILLS` (the
  most kills that round, `TacticalMode.round_mvp`, from `st.killed_by`).
- An attack gathers before it goes in (`TacticalBot._released`): it waits for
  the bots on its team only (and counts a person standing at the point); it
  used to wait for every teammate, so with a person on the team (online, or
  PLAY VS BOTS) the bots stood `STAGE_MOST` (32 s) every round.

### 5v5 checks

`tools/tactical_check.gd` plays every map and mode out with ten bots (round by
round: who, how, when; `verbose` lists every death); `tools/tactical_frames.gd
-- out=<dir>` (a window) takes pictures of the picker, buy menu, sites,
automap, planted bomb, hostage, scoreboard and results. `tools/gun_sheet.gd`
puts the 5v5 guns' numbers side by side (md=<file>); `tools/map_timing.gd`
times run times to sites and checks the bots' routes and holds (strict).

## Presentation

`mode_screens.gd`, drawn only with more than one player: partners in the world
(`player_<heading>_<step>` cels, tinted by slot; the 3D view draws each as
Mundell's model, below), each
partner's tag and health over their head or at the view's edge with an arrow,
`E  HOLD TO REVIVE P2` where the use prompts go and the progress, the frags
and clock in versus, the down screen (`game_view.gd`: YOU'RE DOWN with the
respawn count, FRAGGED BY P2) instead of the death screen while play goes on,
and the results.

Outside the 5v5 rounds every other player (co-op and County Run partners,
deathmatch opponents, team deathmatch with its team tints, online too) is
drawn in the 3D view as Mundell's own model, `mundell`
(`scripts/blender/actors_mundell.py`, his front picture's face on its head),
through a `ModeBodies` stand-in like the 5v5 bodies; the picture keeps its
tint (`~r.g.b`), which tints the model. `ModeBodies.player_pose` picks the
model's frame (`View.Sprite.pose`): falling and down when out, firing (a shot
under .12 s old), flinching from a hit (`PAIN_TIME`, from `watch()` seeing
their health drop), aiming (scoped or a shot under .7 s old), walking on their
gait, standing; the hurt look under half health; crouched .8 as tall. The
player in Hickston's mirror is the same model on the reflection's render layer
(`ActorLayer3D.show_reflection`). Looks only: nothing carried changes.
`tools/mode_frames.gd -- only=mundell` lines partners up turned every way and
in each pose (`docs/godot3d/compare/actors/mundell_*.png`).

**Lying down.** Since pass 7 a player who is down has a flat picture of
their own: `player_down_side` (seen across, the head to the left; flipped
from behind), `player_down_head` and `player_down_feet` (from each end),
picked by where the viewer stands from the way they faced (the model falls
onto its side, its head to its right) and drawn `h / DOWN_ROWS` (122 rows a
map unit) tall (`ModeScreens.sprites`). They are the 3D model's own down
frame drawn by the game's own view (`tools/art/build_player_down.gd`, a
window: the view drawn with and without the body, the difference its matte,
no shadows, a dark rim as the old cels have), so the flat picture (a view
tour's cels, a missing model) lies as the model does. Before, the standing
picture squatted.

**The kill feed** (`features/kill_feed.gd`, a looks feature, never carried
or saved): co-op, deathmatch, team deathmatch and a COUNTY RUN party (the 5v5
rounds keep theirs) get five short lines down the view's left, `MOST` 5,
`SECONDS` 5, from y 78 (under the drive plate, and under the objective pin's
arrow and plate when the boss bar pushes it lower: fewer lines then, never
past y 106, above the revive line): `BUBBA  SAWED-OFF  BILLY` (a hand put down by a player's own
step or shot, `game.own_step`; bosses and tough guys by name, gold),
`CLETUS WENT DOWN` (`... THAT'S THE WHOLE POSSE` when nobody is left up),
`EARLENE HAULED CLETUS UP` (a revive), `... DUSTED OFF AND CAME BACK` (a
respawn), in versus `BUBBA  SAWED-OFF  CLETUS` and `CLETUS CASHED OUT`, and
online `BOB HEADED HOME` / `CARL ROLLED IN`. Each machine works it out from
what its own game holds (players' health, `away` and `downed_by` watched
tick to tick), so a client's copy put back on a snapshot may skip a line.

**Watching while down** (`main.gd _watch_partner`, looks only through
`Players.set_local`): outside the 5v5 rounds, two seconds after this
machine's player goes down (one in deathmatch) the view goes to a partner up
(team deathmatch: a teammate; deathmatch: whoever fragged them), SPACE or E
the next, `WATCHING BUBBA` and `YOU'RE DOWN. BACK IN 12  /  SPACE  NEXT` at
the top; back to their own the moment they are up. `TacticalScreens.human`
is the slot this machine's keys drive in every mode now (`_take_mode`), so
`_tick_party` and the host's tick keep feeding their own player.

## Online co-op and deathmatch

Since pass 7 CAMPAIGN CO-OP, DEATHMATCH and TEAM DEATHMATCH are on a hosted
lobby's MODE row (`lobby.cfg`'s mode row and `mode_maps`, `NetPlay.PARTY_MODES`;
the how-to is `docs/online.md`), hosted through the party line like the rest
(`NetPlay.host_lobby(..., party_line=true)`, `join_lobby(code)`). People only,
four at most (`most_players()`), no bots; MAP steps through the mode's own
maps (`NetPlay.maps()`; a map only one mode lists moves the lobby to it).
An always-open lobby has no host to lead a campaign: no CAMPAIGN CO-OP there
(`modes()`).

- **Deathmatch, team deathmatch**: the arenas of `Modes.ARENAS` (the rodeo
  grounds, the Hogs' field, Rudy's big top, the saw floor, the crossroads, the
  range, the 5v5 and 2v2 maps), START's level is the arena's
  (`Modes.arena_of`), FRAG LIMIT and TIME LIMIT (`frag_limit`, `time_limit`)
  go in the match options. Team deathmatch's teams are the lobby's picks
  (`TeamDeathmatchMode.joined`: `TacticalMode.team_of`). The results'
  ENTER (the host) takes everyone back to the lobby.
- **Co-op, chapter by chapter** (`src/net/net_coop.gd`, `NetCoop`): MAP is a
  chapter the host has reached (`may_start` says THE HOST AIN'T REACHED ...
  otherwise; past Hickston everyone starts with the gate's replay kit,
  `NetCoop.chapter_kit`, which main_flow's `start` now calls too) or THE
  PARTY SAVE. Whenever the party goes somewhere else the host makes the next
  game and moves the match onto it (`NetPlay.switch_match`: START again to
  everyone on their own slots; snapshot numbers run on past the old game's,
  `seq_from`, and a client's input numbers carry on, so a packet of the old
  game still on its way is never taken for the new one):
  - the chapter won: the host's ENTER on the tally (`ROLL ON, Y'ALL`; a
    client sees `THE HOST TAKES THE PARTY ON`) makes the next chapter with
    each player's own kit (`Modes.carry`) and history, opens its gate on the
    host's profile (as local co-op does) and takes the party to the COUNTY
    CROSSROADS (CLASSIC on: straight in). The hub's gates are the host's
    open ones, the chapter under way CONTINUE (`dress`: the clients make the
    same locked gates from START's `locked` and `gate_modes`);
  - any player's USE at a gate (`portal_request` on the host's game, seen in
    `main.gd _net_advance`): the hub's into a chapter (the one under way,
    `main.net_run`, is picked up where it was left; any other starts fresh
    with everyone's kit), a chapter's own gate back to the hub;
  - everyone down: the host's ENTER retries a boss fight from the party's
    boss checkpoint (`BossDoor.path_of`: `boss-checkpoint-<chapter>-party.json`,
    never the host's own), the partners at player one's side (`gather`); R
    (or no checkpoint) the chapter from its start, player one with the kit
    it was entered with. A client's death screen says THE HOST PICKS WHAT
    COMES NEXT; a copy never writes a checkpoint (`game.net_role` "copy").
  - Keys and the PA lead are the party's as offline; quest stations, doors
    and pickups are the host's game's like everything else.
- **Saves**: only the host saves online. F5 in a chapter writes THE PARTY
  SAVE (`NetCoop.save_path()`, beside the boss checkpoints; never the host's
  quicksave or campaign entry, and an online chapter is never the host's
  `campaign_run`); a client's F5 says THE HOST KEEPS THE SAVES. MAP THE PARTY
  SAVE starts from it: the people in the lobby take its slots in order, a
  slot nobody takes lies out of play, more people join beside player one;
  START says so when there is no save yet (`may_start`). A save now keeps
  each slot's name and `away` (no new version: the features block).
- **A save taken while player one is down** (a co-op checkpoint taken while
  the host was down and watching): `SessionStore.save` writes player one on
  their feet with `REVIVE_HEALTH`, as a partner down comes back
  (`Modes.gather`), and saves player one's own part whoever this machine
  shows or acts (it focuses `players[0]`). Before, it never loaded.
- **Late joining** (LATE JOIN on, the default): a newcomer takes a slot whose
  person left, else a new player (`Modes.join_late`: co-op beside a partner
  up with the lead's guns; versus at the spawn point farthest from everyone
  with the kit, team deathmatch on the side with fewer up), and gets START
  for it; the clients' copies get the new player from the next snapshot.
- **Leaving**: the slot lies out of play (`Player.away`, `Modes.went_away`:
  down, never stood up or respawned, not drawn, no tag) until someone takes
  it. Nobody leaving ends the match but the host.
- **Keys online** (`src/net/net_keys.gd`, host and clients alike): nothing a
  key does may change a game between ticks, so the gun keys, ; ', reload,
  USE, the pockets (Q [ ] pick one: `Controls.item` past `Game.POCKET_PICK`;
  F and C B M V X use one) go out with the next controls
  (`TacticalScreens.pending_*`), BACKSPACE turns round with the mouse's
  turn, HOME levels the view; holstering is offline only.
- `tools/net_party_check.gd` (check_all, about a minute) plays all of it
  from a lobby server's party line with the real front end as host: three
  in a co-op Hickston, a down and a revive and their feed lines, the host
  down watching a partner with the copies keeping, the sheriff's checkpoint
  and its retry, the chapter won, the hub's gates, the fair with the kits
  carried, a late join, a leave, THE PARTY SAVE and its start; a deathmatch
  played by bots on every copy with a late joiner and the results (the frag
  limit or the lobby's TIME LIMIT of a minute, which every copy ends on the
  host's tick; until pass 9 the check brought the host's frag limit down
  between ticks, which parted every copy once and failed a run in three on a
  busy PC); team deathmatch's picks.

## Running them locally

No networking: `--mode=coop --players=2 [--level=hickston]` (without
`--level` the title's NEW GAME), `--mode=deathmatch --players=2
[--arena=hickston:boss] [--frag-limit=5] [--time-limit=120]`,
`--mode=team_deathmatch --players=4`. Every player but this machine's is
played by `tools/mode_bot.gd` (bot_pilot plus reviving and following in
co-op, hunting in versus), from the project folder only
(`DevConsole.available()`); an exported build leaves them standing.
`tools/mode_check.gd` (its quick part in check_fixes; `-- seconds=90` plays
longer) holds the rules; `tools/mode_frames.gd -- out=<dir>` (a window) takes
pictures of the partner tags, the revive, the down screen, a deathmatch and
both results screens (`docs/modes/`).

## Client prediction

dev.45, `src/net/net_predict.gd`: a client draws its own player walked on
with the inputs the host has not played into its copy
(`NetSync.Client.unplayed_inputs`, the walking sums of `_step_body`), put back
after the frame (`main.gd _net_aim`); `net_loopback.gd` prints how many ticks
off the host's path the drawn player is with and without it. Since 3.2 the
walk starts from the inputs the host really played (the echoed rows) and a
correction fades over 90 ms (`NetPredict.Smoother`); `tools/net_lag.gd`
measures it (multiplayer.md, "Lag: what a player feels").

Pass 12 (`tools/net_feel.gd`, multiplayer.md
["Frame by frame"](multiplayer.md#frame-by-frame-pass-12-net_feelgd)):

- **Between ticks.** The game ticks 60 times a second online; the drawn
  player is carried into the next tick by the frame's share of it with the
  keys held now (`NetPredict.ahead`, from `main.net_accum`), turned by all
  of the mouse not sent yet, so it moves every frame on any screen. The
  host's own player gets the same (`main.gd _host_aim`; before, the host's
  view turned only at the tick). Everyone else is drawn between the copy's
  last two ticks (`NetBlend`, below).
- **The others who block us** (co-op, the versus modes) stand where the
  host will have them when each input is played, carried on by their speed
  (`NetPredict._mates`, at most `MATES_AHEAD` ticks), not where the copy has
  them a round trip back: two co-op bots following each other were
  corrected 1,200 to 1,530 times a minute, now 90 to 280.
- **The walk matches the host's**: mud (`Mud.pace`) and a knock-down
  (`Player.knocked`: no walk, the eye low) are in it, and while the world
  holds on the copy (COUNTY RUN's cards, the tally, a gate taken, everyone
  down: `NetPredict.held`) our inputs are not walked on, as the host plays
  none of them (the drawn player ran and turned through a card pick and was
  put back when it ended).
- Still walked as plain walking: a ladder or ledge (`Climbing.player_step`)
  and a drunk's wobble; both put right by the Smoother.

### Shots, reloads and pickups

Pass 7, `src/net/net_gun_lead.gd`, `net_shot_predict.gd`, `net_echo_sound.gd`,
`src/hands_watch.gd`. Before it a client's own shot flashed, banged and kicked
when its copy played it: a round trip and the play-out later (350 ms on a
100 ms link). Now, looks only, the host's game still the only truth:

- **The gun leads.** `NetGunLead.lead` steps our gun through the unplayed
  inputs with Weapons.Armory's sums (select, reload, the tick and its beats,
  fire with its refusals: holstered, cooling down, reloading, switching, dry,
  the 5v5 freeze through `hold_controls`), no dice and no hits. The flash, the
  kick pose, the rifle's climb and the HUD's rounds are drawn from it and put
  back after the frame, so a refused shot's round simply comes back. Not led:
  dynamite (the fuse), something carried, the wheel, the gallery booth.
- **What happened is shown once** (`NetShotPredict.frame`, from `_net_aim`):
  the bang (and its room ring), the cycle's and reload's beats, a dry click and
  its word, a gun's equip sound; for a shot the gun's kick (`feel.kick_now`),
  shake, and every looks-only feature's muzzle puff, shell and smoke
  (`GameFeature.own_shot`; `own_reload` for a reload's shells). A bullet or
  pellet gun's line is drawn where our screen shows the world (`probe`: the
  enemies and players the copy shows, which is what the host's rewind judges
  by, then the walls; pellets off our own dice inside the spread): its tracer
  and chips (`own_trace`), the wall's sound, and on someone well inside their
  edge (the centre line) the crosshair's mark, the tick and blood (specks on a
  player, the gore spray on a hand).
- **A pickup** our drawn player reaches and would take (`would_take`:
  collect's refusals) leaves the picture with its sound and word at once.
- **The copy does not show it again.** `game.hands_watch` (null on a single
  player game and a host) is called round the watched slot's `_step_hands`.
  While something shown is due (within `WINDOW` inputs of the one the copy
  plays) the step's looks-only calls are held (`game.own_quiet`:
  `HandsWatch.defer`, `held_burst` for burst()'s specks, whose dice go as
  ever) and its sounds written down (`NetEchoSound`). After it a shot the
  copy fired is matched with the oldest shown one: its held looks dropped, its
  shake taken back, the next kick skipped (`feel.skip_kick`), a mark it did
  not give withdrawn with its blood (the specks taken out), a kill it gave
  shown as it has it; a sound already heard is dropped, anything else (a kill's
  tick, a yelp, a shot nobody foresaw) plays then. Something shown and never
  played by `EXPIRE` inputs past is withdrawn quietly (a pickup comes back).
- **Dynamite, melee and USE** (pass 9). The lead steps a stick of dynamite
  too (`fuse` among the gun's kept fields): the match struck and the lit
  stick with its fuse bar at the press ("light", one a trigger hold:
  `_hold_start`, so a stick the host never lit is not struck again every
  few frames), the throw at the release ("throw": the sound, the hand, the
  face); the stick in flight is still the copy's. A melee swing (crowbar,
  sling, blades) already showed at the press; now its blow coming due
  ("blow", at `swing_at`) is looked along as the copy stands (`probe`,
  the swing's reach and width, a line well on the body): its hit sound,
  the mark and the blood, matched when the copy's own blow comes due
  (`swing_hit` going off in the watched step) and withdrawn if it missed.
  USE's boot (`_boot`, brawl.gd use()'s choice: rested, not busy, a man
  in reach not to be finished, or a plain door run at) shows at the first
  fresh press: the grunt, the boot drawn and the gun ducking, timed from
  our press (brawl's `kicked_at` and our `weapon_lag` set for the frame
  and put back; the copy's own boot is drawn at our press too, so it does
  not start again). A finisher is the copy's to show (its move is off the
  dice); so are the landing's jolt, doors and every other USE.
- **A thrown shot** (pass 12, `src/net/net_own_shots.gd`): a projectile
  gun's shot (the crossbow's bolt, the ripsaw's blade, the bottle rocket,
  the bowling ball...) came into the copy a round trip and the playout
  after the press, from where our player stood back then, behind the drawn
  one. Now a ghost of it flies from the press, from where our screen shows
  us, along our aim with the shot's speed, lift and fall (no bounce, no
  wind; it stops at a wall or the floor); once the copy fires its own the
  oldest ghost of that kind goes and the copy's shot is drawn as far on as
  our inputs lead the copy (`NetOwnShots.begin`'s `ahead`, the ticks not
  played), so it carries on where the ghost was (predict_check: one bolt
  in the picture every frame, its biggest step a frame its flight's). A
  ghost the host never matches goes after `WAIT`. Anything that rolls or
  rests (the bowling ball) stays the copy's.
- **Blasts, a stick in flight, a thrown thing's hit** (pass 12 round 2,
  `net_own_shots.gd`). Where the ghost (or the copy's shot drawn on) lands,
  a shot that blows up blows up at once (`_boom`: explode()'s looks only,
  its sounds, flash, shake and duck, the blast drawn, specks off our own
  dice, and the looks features' answers: debris's scorch and embers,
  weapon_fx's grit, gun_fx's fireball and wreck bits, impacts' marks,
  water's rings); a stick of dynamite's ghost leaves at the release with
  what is left of its fuse (the "throw" event's `fuse`), tumbles as the
  copy's does (`Tumble.step`, no wind) and goes up when the fuse is out, the
  copy's stick hidden meanwhile. When the copy's own blast comes,
  `explode()` asks `hands_watch.blast_shown(shot)` (same kind, within
  `BLAST_NEAR`): `game.blast_quiet` leaves out its sounds, flash, shake,
  the blast drawn, burst()'s specks (the dice go as ever) and the looks
  features' answers; its hurt, its breaks and everything the simulation's
  features do go as ever, a round trip later. A shot that blows up is not
  drawn after its blast. A ghost that meets a hand or another player shows
  the hit mark (its tick and blood are the copy's).
- **The scope** (`NetGunLead.scopes`): ALT FIRE on a scoped gun puts it up
  and down in the lead, game.gd's rule (a fresh press, not while
  reloading; a reload or another gun takes it down); `Player.scoped` and
  `alt_held` put back after the frame.
- **The hand flinches** (`net_hit_looks.gd`): a hit shown at the press draws
  the hand with Enemy.hurt's flash and flinch for the gun's damage from the
  press; when the copy's hurt lands its own flash and flinch are not drawn
  again for their length (`muted`); a hit withdrawn stops at once.
- **USE on a door or a note** (`net_use_looks.gd`): a fresh USE the boot
  did not take, on what interact() would open (no remote switch, the key
  held, not a powder store, the hatch crouched under), plays the door's
  sound and draws it swinging from the press at the copy's speed, ahead of
  the copy's until it catches up (a USE never played lets it go back after
  `WAIT`); a note's words show at once. The copy's door sound is dropped
  (net_echo_sound.gd).
- **Every online mode gets it** (County Run co-op, the 5v5 rounds, tag
  team, and any mode added online later): it reads only Game.Controls, the
  copy and `NetSync.Client`. Nothing carried is touched; `net_lag`,
  `county_net_check` (which draw the frame as main.gd does) find no parting.

`tools/predict_check.gd` (check_all) holds the cases: a shot played, refused,
dry, a hit judged a miss, a gun taken up and fired, a pickup played and
refused, a reload mid-burst (every cue, tracer and shell as often as a copy
without prediction), and nothing on a game nobody watches. `net_lag.gd` prints
button-to-flash shown and the copy's (the old way), and how often a shown shot
or hit was withdrawn (`noshots` turns it off).

Measured with `net_lag.gd -- lags=50,100,150` (one way each side, a fifth of
it jitter, 2% loss; grainyard search and destroy, four people and six bots;
the tool's clock is its own, so runs repeat nearly to the millisecond): three
60 s runs with it and three with `noshots`, then one of 240 s with it. Button
to the flash and bang, median (p95):

| | 50 ms | 100 ms | 150 ms |
| --- | --- | --- | --- |
| before: when the copy fired it | 200 ms (217) | 350 (383) | 500 (533) |
| now: shown | the same frame | the same frame | the same frame |
| shots shown, then withdrawn (240 s) | 1.2% of 166 | 3.3% of 209 | 2.6% of 155 |
| shots fired that were not foreseen | 0 | 0 | 0 |
| marks shown, then withdrawn (240 s) | 23% of 57 | 25% of 48 | 35% of 46 |
| (the tool's "looked a hit, judged a miss") | 21% | 18% | 30% |

A withdrawn shot is mostly one pressed just before the round ended or the
player went down on the host. A withdrawn mark is a centre line the host
judged a miss, as often as the bots' own aim is (a line grazing a body's edge
shows no mark at the press, `SURE`; the host's mark shows when it lands); on
hands in County Run co-op (no rewind for them) a fifth of the marks shown
were withdrawn in `county_net_check`. "The same frame": the input and its
shot are drawn by the frame that sent it.

## The browser online

dev.45: a lobby server's lobby with `ws_port` also takes WebSocket players
(`NetSession.also`, ids past `ALSO_IDS`), wss with the config's
`tls_cert`/`tls_key` (server/setup.sh copies Let's Encrypt's certificate to
/etc/clmr/tls on renewal; IONOS's own firewall passes 443 and 8443, not the
47xxx TCP ports). servers.json's `wss` is what the browser build knocks on and
joins (net_browser.gd, `NetPlay.join_lobby` with a `wss://` address). Since
pass 7 the browser also hosts and joins by a party line code, through the
relay in the lobby server ([multiplayer.md](multiplayer.md#the-party-line-the-relay));
a 10-character join code or an address stays desktop only.

## Not done

- UDP hole punching (the party line relays instead; a desktop player still
  goes straight to a host whose router opened the port).
- Client prediction of finishers (the move is game.rng's on the host's
  tick, which no copy knows ahead: a wrong move drawn could not be taken
  back), a break and its wreck pieces from our shots (a break changes the
  level's walls; drawn wrongly it would have to come back whole), a kill's
  fall and ragdoll (the hand's health on the host decides it; one drawn
  falling cannot get up again), the saw's grind, the boot's jolt, USE on
  anything but a door, a note or a boot (stations, the jukebox, gates),
  items, a thrown shot's blood and tick, and the blasts of things that
  roll (each still shows when the copy plays it).
- A second local input set (split keyboard).
- Spawn points from the plans outside the 5v5 maps (only worked out).
- Versus pickups other than the level's own.
- Co-op and deathmatch on the title with nobody else: there is no second
  local input set and the partner bots are tools only (`tools/mode_bot.gd`),
  so the title's MULTIPLAYER takes them online (HOST A GAME; a friend in the
  same house joins by the host's address or the code); `--mode=` still plays
  them against the tool bots from the project folder.
- Online co-op: a revisited (won) chapter, the range and BOSS REMATCH stay
  single-player; late joining does not scale the enemies already about
  (CoopMode scales on the first tick and for new ones); the boss PARs and the
  tuning are single-player numbers; the always-open servers carry no
  CAMPAIGN CO-OP.
