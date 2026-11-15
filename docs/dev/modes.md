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
  health, the kit again. Pickups come back 20 s after they are taken.
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
seen on a site, plant, defuse, carry and chase, pick the gun for the
distance, and aim with a reaction time and a wobble by DIFFICULTY.

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
(`player_<heading>_<step>` cels, tinted by slot, squat when down; the 3D view
draws each as Mundell's model, below), each
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

## The browser online

dev.45: a lobby server's lobby with `ws_port` also takes WebSocket players
(`NetSession.also`, ids past `ALSO_IDS`), wss with the config's
`tls_cert`/`tls_key` (server/setup.sh copies Let's Encrypt's certificate to
/etc/clmr/tls on renewal; IONOS's own firewall passes 443 and 8443, not the
47xxx TCP ports). servers.json's `wss` is what the browser build knocks on and
joins (net_browser.gd, `NetPlay.join_lobby` with a `wss://` address); hosting
and join codes stay desktop only.

## Not done

- Online co-op and deathmatch outside COUNTY RUN.
- A relay or NAT punch-through for hosts whose router will not open the port
  (forward it, or a VPN).
- Client prediction of anything but walking and the aim (a shot, a pickup).
- A second local input set (split keyboard).
- A kill feed outside the 5v5 modes.
- A lying-down picture for a player who is down (the standing one, squat;
  the 3D view's model falls and lies down).
- Spawn points from the plans outside the 5v5 maps (only worked out).
- Versus pickups other than the level's own.
- The title's mode entries are MULTIPLAYER and COUNTY RUN (co-op and
  deathmatch command line only).
- A save or snapshot taken while player one is down does not load
  (SessionStore refuses a player at 0; the quicksave is refused then anyway).
- The co-op boss checkpoint's retry with partners is put together from the
  save round-trip and `gather`, with no check of its own; the boss PARs and
  the tuning are single-player numbers.
