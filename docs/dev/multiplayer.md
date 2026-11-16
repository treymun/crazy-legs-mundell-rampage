# Multiplayer: the foundation, the tests and the transport

`docs/multiplayer.md` is the plan (model, rates, transports per platform,
what a networking pass still needs); `docs/online.md` is the how-to for
playing and serving online. This file is how the code does it. The rules each
mode plays by (co-op, deathmatch, the 5v5 rounds) are in
[modes.md](modes.md); County Run co-op in [county_run.md](county_run.md).

## The foundation

This is what co-op or deathmatch rules and the transport build on.
`src/players.gd`, `src/player_voice.gd`, `src/game_snapshot.gd`,
`src/snap_codec.gd`, the authoritative host (`src/game_host.gd`,
`src/net_track.gd`, `src/quiet_sound.gd`, `src/server_loop.gd`), the client's
`src/game_mirror.gd`, `tools/net_check.gd` and `tools/net_bench.gd` hold it.
One player plays exactly as before (checked tick by tick against the old
build: state hashes of bot runs in every chapter at NORMAL and HOG WILD,
`first_minutes.gd -- whole`, the rematch times, the duels).

### Players are a list

`game.players: Array[Player]` by slot (index 0 is player one; `Player.slot` is
never reused and is how a snapshot names a player). `game.local_player` is the
one this machine shows and hears. `Players.join(game, x, y, angle)` adds one
(Game._init joins player one), `Players.set_local(game, p)` changes whose view
this is.

### `game.player` is the ACTING player

`game.focus(p, own)`: the local player outside the tick; during the tick each
player in turn while their controls play (`own` true: their sounds come from
where they stand, their notices are not shown here), an enemy's hunted player
while that enemy ticks, a shot's thrower while it flies (`Shot.slot`).
`game.armory`, `flow`, `inventory`, `keys`, `task_items`, `inventory_slot`,
`sprint`, `step_number` and `next_belch` are the acting player's
(`armory`/`flow` are swapped in by focus, the rest are properties over
`game.player`).

- Code that acts for "the player" (damage, pickups, use, the guns, an enemy's
  sight, aim, blows and flow field) keeps reading `game.player` and acts on
  the right one.
- Code about the world goes over `game.players`: blasts, enemy shots
  (`_shot_finds_player`), hazards, doors held open (`LevelData.update(dt,
  players, enemies)`), triggers (`Triggers._met_any`: the first player who
  meets it is left acting), arena fire, rollers, the log carriage, steam jets,
  slicks, core pulses, race cars.
- A new hazard loops over `game.players` and calls `game.damage(amount,
  source, cause, who)`; a knock-back focuses the player first (`move_actor`
  tests the acting player). `game.reopen_paths()` opens a broken piece's cells
  in every player's flow field and the route.
- After focusing someone else, focus back: `game.focus(game.local_player)`.

### Controls per player

`game.tick(dt, controls)`: one `Game.Controls` is the local player's (anyone
else stands idle, the single-player path), or a Dictionary slot -> Controls (a
slot left out stands idle). Controls also carry `use` (a fresh press),
`weapon` (a slot), `item` (a pocket) and `cycle` (+1/-1 gun) for a player who
is not the local front end; the local front end still calls `interact()`,
`Armory.select()`, `use_item()` between ticks. The tick plays every live
player's body (`_step_body`), then rooms that open (`_discover`), the doors
once, every player's hands (`_step_hands`: controls' actions, pickups, gun,
the tin rooster booth for the player who opened it), then each player's flow
field, the enemies, the shots, the hazards. The world stops when nobody is
alive; a dead player's steps are skipped (respawning is the co-op rules' to
write).

### Per player vs shared

This is `Players.SHARED` and nowhere else: `keys` and `task_items` (the PA
patch lead) are one object the party shares, `inventory` (rinds, beer...) each
player's own; flip one there. Always each player's own: place, health, gut,
drunk, guns and rounds (`Player.armory`), sprint, footsteps, flow field.
Always the world's: stations, doors, the pickups lying about (whoever touches
one takes it), kills and secrets, clock, rng, enemies, scenery, triggers,
`cheats.god`. With more than one player there is no world-stopping hitstop or
boss entrance hold, and no ADAPTIVE DIFFICULTY (each is one machine's game
feel).

### Enemies pick a player

`Players.hunted(game, e)`, only with more than one: it keeps its pick
`RETARGET` (.5 s), then a player who hurt it within `SPITE` (`Enemy.spite`,
set in `hurt()`), else the nearest it can see (14 cells), else the one nearest
where it last heard something, else the nearest alive; ties to the lower slot,
no dice. `Enemy.hunted` is the pick; the enemy ticks with that player acting,
so its sight, flow field (each player has one), aim marks, flanks and blows
are about them. Squads form per hunted player (`squad_feature.gd
_step(only)`); Maw follows hers (her wind-up, curlers and crew calls too). A
hostile body keeps out of every player's way; in co-op and versus players who
are up block each other (`move_actor`, `GameMode.bodies_block`; the campaign's
two-player runs pass through, as the foundation's checks expect).

### Presentation follows the local player

The HUD, view, automap, objective pin, camera shake (a blast's by distance to
the local player), the face (`set_face`), barks, messages, the crosshair's hit
mark, the hurt flash, item feedback, captions, the room's sound, the place
names, the walked map, the gun's kick (`feel`), tracers and muzzle smoke
(`weapon_fx`, `gun_fx`), chapter stats, kill callouts, fight music and boss
taunts are the local player's (`game.acting_local()`). Sound is placed for the
local player's ears (`sound_position`, `sound_at` through `game.speaker`);
while another player acts by their own hand `game.sound` is their
`PlayerVoice`, which places their gun, pickups and grunts where they stand and
ignores the local-only calls (fuse, room, music, stings). A message during
another player's own step is not shown here (one said while an enemy is after
them is).

### Simulation vs presentation

This is written down in `GameSnapshot`: every field of Game is in
`SIM_FIELDS`, `PLAYER_FIELDS` or `VIEW_FIELDS`, every feature in
`SIM_FEATURES` or `LOOKS_FEATURES`; `net_check.gd` fails on a field or feature
in none, so put a new one in one. Simulation is everything that can change
play and comes from `game.rng` or the features' own state; presentation uses
its own dice and is never carried (specks and blast flashes are looks, though
a save keeps them). `game.events`, `game.view` and `game.view_frame` are VIEW fields. Known mixes
kept for exact single-player play: the HIT FEEDBACK setting decides the
hitstop, footstep splashes spend `game.rng`, `cheats.god` is the game's.

A carried field must never be decided by one that is not: a client's copy
that is put back on a snapshot keeps its own presentation, so anything
carried that read it parts the copies again (county_net_check found three).
`game.bark_next` decides whether a hand's own `Mind.bark_next` is set, so it
is a SIM field; a simulation feature's looks keep their own dice that the
snapshot skips (`SnapCodec.SKIP_FIELDS`: the specks of `hit_reads` and
`critters`, whose count hangs on the specks already about), and what follows
this machine's callouts (`hit_reads._call_at`, after the BARKS setting and
`callout_until`) is skipped too.

### Stable ids

Players by slot; enemies, shots and pickups by a uid from `game.take_uid()` in
the order they come into being (`Enemy.uid`, `Shot.uid`, a pickup's fourth
element; enemies and shots that joined during a tick are named at its end,
`game.name_new()`), so two machines running the same ticks agree. Doors,
stations and scenery by their place in the level's lists; breakables and wall
breaks by their place in their feature's lists. A save keeps pickups as
`[name, x, y]` (no new version); their ids are handed out again on load. An
enemy's instance id in carried state (a shot's thrower, a dictionary keyed by
enemy) travels as its uid.

### Snapshots

`src/game_snapshot.gd`, version 2. `GameSnapshot.capture(game)` is a
Dictionary of plain values that never changes as play goes on (packed arrays
are shared by reference in Godot 4: encode and decode copy them):

- "game" (SIM_FIELDS);
- "world" (each door's progress, opened and discovered by its place in the
  level's list; the panes broken, in breaking order);
- "facts" (`FACT_FEATURES`' own save(): what breakables and wall breaks broke,
  which changes the level's walls and floor; the arena wreck; the boss arena
  shut, `boss_lock`, whose restore lays its solid cells and gates on a copy);
- "players" (every carried field by slot, each player's own, whoever is
  acting);
- "enemies" (by uid) with "order";
- "features" (each simulation feature's variables);
- "statics" (play in static variables: `DerbyChamp.state`; new play belongs on
  the enemy or in a feature).

No save and no presentation inside it. `GameSnapshot.apply(game, data)` puts
it onto a Game of that level, just made OR already running: the players it
lacks join, the doors and panes are set, each fact feature's restore() breaks
what is not broken yet (only when its facts differ from what the game was last
given, `game.net_facts`), enemies are matched by uid (new ones made), every
carried field is set, and a finished station's lights follow `stations_done`
(`game.lit_stations`, kept by `set_station_lights`). `apply_delta(game, d,
full)` puts on only what a delta touches, each field from `full` (its patched
snapshot).

A flow field travels as the cells its last walk reached and their steps
(`@flow`); a level's windows, fences, breakable pieces and boards carry only
what can change (`SnapCodec.ONLY_FIELDS`), a feature's tuning and lookups not
at all (`SKIP_FIELDS`). `to_bytes`/`from_bytes` (var_to_bytes, zstd),
`delta(base, now)` (dictionaries walked, each value compared once, bit for
bit; a changed dictionary is `{"@new": value}`, anything else travels as it
is; gone keys under "@gone", a new key order under "@order"), `patch`,
`patch_into` (into the caller's own copy), `merge(older, newer)` (two deltas
as one), `same(a, b)` (bit for bit, key order too), `first_difference`.

`snap_codec.gd` turns objects into plain values by reflection (script
variables, read in one call through a script made per class, `packer()`); a
class it cannot name is listed in "unknown" and fails the check; decoding
fills what is there in place, so what a snapshot does not carry (a sprite)
stays.

### The host

`src/game_host.gd`: `GameHost.new(level_id, slots, options)` makes a host Game
(`game.host`: no looks-only features, `Features.LOOKS`; a `QuietSound` for
`sound` and `speaker`; no voices, no talk, no room sound or place names,
`sound_at` returns at once; nothing is ever drawn) and runs it `step({slot:
controls})` one fixed 120 Hz tick at a time (`tick` counts them). `snapshot()`
is bytes of `{"tick", "full"}`; `delta_since(acked)` is bytes of `{"tick",
"base": acked, "d"}`, or a whole snapshot when the base is older than
`HISTORY` ticks (or -1). `adopt(game)` wraps a game already made;
`join_near(game)` seats one more player.

Presentation that play still leans on stays on a host: specks and gore (their
count gates `burst()` and its rng), the View object (hitscan's material comes
from `WallHits.wall_mark`), and so on; a host game and an ordinary one fed the
same controls stay identical (net_check).

`main.gd --server=<level>` (`--server-players=N`, `--server-ticks=N` to time
flat out and quit, `--server-report=S`, `--server-difficulty=D`; run it
`--headless`) runs a host in `ServerLoop` with no window, picture, sound or
menu work and prints the tick's and the deltas' cost; players stand idle until
a transport hands their controls to `ServerLoop.controls`.

### How the host finds a delta

`src/net_track.gd`: `NetTrack` keeps every carried field's last value (plain
values as they are, arrays and dictionaries as bytes, packed arrays copied,
objects by identity with a watch over each object carried by value: a mind, a
gun rack, a shot, a flow field). Each look (once a tick at most, when a
snapshot or delta is asked for) compares the `HOT` fields one by one and the
rest of an object and everything inside it as ONE var_to_bytes, so a field is
only looked at alone when its part changed; floats to the sign of zero. A
feature with `NET_GUARDED` lists (wall breaks' windows and fences,
breakables' pieces) is looked through only when its `net_version` moved:
anything that changes a window, fence or piece must bump it. The changes per
look are logged; `delta_since` merges the log since the base
(`GameSnapshot.merge`). Never "@order": enemies that change places send the
enemies whole.

### The mirror

`src/game_mirror.gd`: `GameMirror.new(client_game)`, `take(bytes)` puts a
whole snapshot on (`apply`, onto its running game too) or a delta made against
the tick it holds (`acked`, the tick to acknowledge) by patching its copy of
the snapshot and `apply_delta`. It does not tick its game; prediction is not
here. `NetSync` (the transport) still diffs whole captures; switching it to
`GameHost.delta_since` / `GameMirror` is the transport's to do, and
`NetSync.APPLY_RUNNING` can go on.

### Several players cost little more than one

One player's tick is the same code as before: an enemy's pick stands
`RETARGET` and is tested in the enemy loop before any call; a new pick draws
sight lines to the players in reach nearest first and stops at the first seen
(none with one alive); each player's flow field is walked when something first
needs it in a tick (`Player.flow_due`, `focus()`; any left are walked after
the enemies, so every field is current after the tick for a bot or the next
tick), and a walk from a cell another player's field was walked from this tick
copies it (`flow_walks`, `FlowField.adopt`: a copy, packed arrays being shared
by reference); players' bodies look only at the enemies in the cells round
them (`body_cells`). New per-player work should be on demand like these, never
a loop over every enemy for every player each tick.

### Costs

Headless, this PC loaded by other work, so only roughly; see
`tools/net_bench.gd`, which times old and new alike, run side by side: a whole
capture 3 to 8 ms (was 10 to 30), 15 to 24 KB packed (was 23 to 38); the
host's delta for 4 ticks 1.2 to 2.6 ms with bots playing (was a capture and a
diff, 20 to 57 ms), 0.6 to 2 KB (was 1.3 to 3.5 KB), put on by a mirror in 0.3
to 0.9 ms; up to 4 ms in Hickston with all 99 hands alive (`--server`, idle
players). A whole snapshot onto a fresh game 8 to 18 ms. The enemies are most
of a delta (every field of every one is read each look: about 10 to 20 us an
enemy). One player's tick is unchanged; four bots cost 1.2 to 1.9 times one
(Hickston .62 -> .88 ms).

### The determinism check

`tools/net_check.gd`; its quick part runs in `check_fixes.gd`. Two games fed
the bot's recorded controls stay identical, snapshot for snapshot; capture,
apply to a fresh game, capture is the same; bytes and a delta round-trip; the
fresh game then runs on beside the first and stays identical (the snapshot
carries all the play there is); with two players both are hunted, player two
is hurt by a hand and by a blast, takes shells and a beer for themselves and a
key for the party, opens a door with USE; two two-player games stay identical
and round-trip; a snapshot kept from tick 600 has not changed by the end. The
host: its game has the simulation's features and no looks-only ones and no
sound; it and an ordinary game fed the same controls stay identical; a mirror
over a fresh client game, kept up by deltas alone every 4 ticks and once by a
whole snapshot onto its running game, matches the host each time it is
compared (the patched snapshot and a capture of its game), in every chapter
and with 2 and 4 players; deltas merge. The bot (`bot_pilot.gd as_controls`)
asks for USE and the next gun through its controls so a lockstep game gets
them too.

### Not done yet (foundation)

Per-player stats, messages and kill feed; player bodies blocking each other;
respawn; Maw's area attacks hit only the player she is after; a slick or a
race car bites one player at a time; the objective pin, boss bar, boss
checkpoint and rematch think of one player; client prediction; the transport
using GameHost/GameMirror. The steam scald is marked on the hazard now
(`Hazard.scalded`, `boss_arenas.scald_count`). Several of these were since
done by the modes (bodies blocking, respawn, area attacks on every player:
see [modes.md](modes.md)).

## Tests, the crash log and the transport

### Presentation must never change play, whoever is local

Play that reads `game.player` outside an enemy's or a player's own step (in a
`ticked` handler, say) reads the LOCAL player, so two machines would play it
differently. `multi_bots.gd` holds this: its twin game is seen from the last
player's machine (`Players.set_local`), and the two must stay identical. It
found three (the chickens spooked by the local player's run only, floating
bodies bobbing near the local player only, a race car's kill blamed on the
local player): now any player, the nearest player. Single-player play is
unchanged by them.

### `tools/multi_bots.gd`

1 to 4 players in one game, each its own `bot_pilot` (`as_controls`) through
`game.tick(dt, {slot: controls})`, every chapter for `seconds=` or to the end
(`whole`), god mode unless `mortal` (the harness fills a dry gun in both runs
alike, never the pilot's own `whole`, which touches one game). Per player:
kills (credited to the acting player when an enemy dies), damage taken,
deaths, stuck time (still, with no foe in sight) and the share of the enemies'
hunting; the tick's median, p99 and max. Fails on any script or engine error
(a `CrashLog.tally()` round the run), a position that is not a number, a
player's middle inside a solid cell for half a second, or the twin parting
(snapshots compared every 600 ticks and at the end). Its quick part (`run()`:
Hickston with four for 12 s, the bayou with two for 6 s) is in check_fixes.
Two bots on Hickston idle about 30 s at (45.5, 57.7) in a minute: a bot or
route matter, not looked into.

### The crash and error log

`src/crash_log.gd`, a Godot `Logger` added with `OS.add_logger` in `main.gd
_ready`, closed in `main_state.gd _exit_tree`. A real launch (not a tool, not
the browser) writes every error and warning to `user://logs/session.log` with
the version, screen, level, tick, mode, each player's place, health and gun,
the last controls (`main.last_controls`, set in `advance()`), the last lines
of output and the script backtrace (debug builds; a release export has none
unless `always_track_call_stacks`, which costs every call, is on).

- The same error at one place is written REPEATS times, then counted; the
  file stops at 2 MB.
- `CrashLog.note(text)` leaves a line (each level started); a clean exit
  appends a summary (counts, the busiest places, the last notes) and removes
  `session.lock`.
- A launch that finds the lock keeps the old log as `crash-<stamp>.log` and
  prints one `CRASH LOG:` line; a phone sent to the background marks the lock
  so a system kill there is not a crash; another copy running on the profile
  gets `live-<pid>.log`. KEEP (5) of each kind.
- Nothing runs per frame. check_fixes's CRASH LOG block holds it in a cache
  folder (`CrashLog.start(main, dir)`).

### The transport

`src/net/`: `NetSession` wraps ENet or WebSocket (`MultiplayerPeer`, packets
only), with test latency, jitter and loss on what it sends (on the clock
handed to `poll`; loss only unreliable). `NetWire` is every packet's layout
(protocol 3: controls in 14 bytes, buys, reloads and the host's rewind among
them; inputs sent redundantly with the tick the client shows; snapshots with
their base, tick, input ack and the inputs played since the base; the lobby's
messages).

- `NetSync.Host` plays the authoritative game and sends deltas from each
  client's acknowledged snapshot (whole while it has none).
- `NetSync.Client` rebuilds them and steps a copy of the game with the inputs
  the host played (`play_out`: a few ticks behind the newest, smoothly), and
  puts a snapshot onto the copy (`REBUILD_RUNNING`: the running game, no
  hitch) when it cannot step or a check finds it parted.
- Both can be fed by whoever polls the session (`take`, `play`,
  `add_remote`): the online lobby does.
- **Shots are judged where the shooter saw them**: the host sets
  `Controls.rewind` (ticks back, from the tick the client said it shows, at
  most `NetSync.MAX_REWIND`) and `game.gd _rewound_hands` stands everyone else
  where `game.place_log` (60 ticks a second, never carried, every copy keeps
  its own) had them for that player's hands. The rewind travels in the echoed
  inputs, so every copy plays it the same.
- Two things about snapshots the tests found, both fixed in snapshot version
  2: a capture shared the game's packed arrays (it copies them now;
  `NetSync.capture`'s deep copy is no longer needed), and the save part
  followed the acting player and carried presentation (there is no save part
  now; `NetSync.comparable` passes a version 2 snapshot through as it is).
- **NetSync.Host's snapshots come from NetTrack** (`tracked`, `track`,
  `_change_since`: each snapshot's changes logged in `history`, merged from a
  client's base; a whole capture only for a client with none): about a sixth
  of a capture and diff for a 5v5, which took a full match on the one-core
  VPS from 40% to about 15-20%.

### `tools/net_loopback.gd`

One process, a host and a client peer on 127.0.0.1 (a port from the process
id, so parallel checks do not meet), two games, the game's own clock. The
host's bot plays player one, the client's bot (steered from its copy) player
two. Checks every snapshot the client rebuilt against the host's game as it
stood (`GameSnapshot.same`, `wholes`, not what the host sent), the copy
against the snapshots once a second, that the client's inputs move player two,
and no errors; prints bandwidth each way, snapshot and input sizes, lag and
the host's costs. Its quick part (ENet 6 s with 40 ms, jitter and 5% loss;
WebSocket 2 s) is in check_fixes. It also prints how many ticks off the host's
path the drawn player is with and without client prediction
([modes.md](modes.md#client-prediction)).

## Lag: what a player feels (`tools/net_lag.gd`)

`net_lag.gd` runs an always-open lobby server (`LobbyServer`, as on the VPS)
with a full 5v5 and `people` clients over 127.0.0.1 ENet with latency, jitter
and loss on both sides, each client a `TacticalBot` steering from its own
copy led by the prediction (what a person's screen shows). Per link it prints:
how far the drawn player leads the server and the round trip to confirmation;
the prediction's corrections and the jumps the player actually sees; frames
where everyone else stood still or skipped; copies put back and mismatches;
every client hitscan or pellet shot's centre line tested where that screen
showed everyone and where the server judged it (with the rewind, and without
for comparison); bandwidth per client, delta sizes, and the server's cost per
tick split into the game, the snapshots and the bots, as a share of one core.
`old` turns every fix below off (statics on NetSync, NetPredict.Smoother,
NetSession, Modes and TacticalNav), so before and after run on one build;
`quick` (check_all) is one 120 ms link for 30 s with limits. The numbers are
in [the 3.2 measurements](#the-32-lag-measurements) below.

What it found and what changed:

- **ENet threw inputs away.** Its packet throttle drops unreliable packets
  while the round trip grows and climbs back slowly: with a wandering round
  trip a third to over half of the client's input packets never arrived, so
  the host held and merged inputs (the rubber band) and small snapshots went
  missing. `NetSession._patient` sets every peer's throttle to come back whole
  at the next steady answer (`THROTTLE_INTERVAL`, `THROTTLE_BACK`).
- **Prediction from the echoed rows.** `Client.unplayed_inputs` walks on with
  what the host actually played for us on each tick past the copy's (a late
  input held again, inputs merged after a stall), then our inputs it has not
  played; the old guess at the input the copy's tick had was a tick or more
  out whenever the host held or merged one.
- **Corrections eased.** `NetPredict.Smoother` (main_state `net_smooth`, drawn
  in `main.gd _net_aim`) keeps a correction as an offset on the picture that
  fades over 90 ms instead of jumping; looks only, put back after the frame.
- **Everyone else paced by the clock.** `Client.playout` shows the host's tick
  now (judged from the quickest arrivals) less `playout_depth` (the
  snapshots' gap plus their arrivals' 95th-percentile spread, up at once, down
  after 3 s): a tick a frame however the snapshots bunch. It used to stand two
  ticks behind the newest snapshot, so every late snapshot froze everyone for
  a frame and the catch-up hurried them. The echo is taken from stale
  snapshots too (big ones go reliable and can pass small ones).
- **Smaller snapshots.** Each snapshot carried every input row since the
  client's acknowledged base, a round trip of rows; now the rows since the
  last snapshot sent it plus `ECHO_AGAIN` snapshots' worth (`Remote.echo_sent`).
  The 5v5 rounds walk no player flow fields (nothing hunts a player there;
  `game.gd`, `Modes.flows_in_rounds` for the old way), which were half a
  delta; the hearing walks the listener's own (`hearing.gd _own`, never
  carried).
- **Cheaper on the server.** `Host._carry_since` merges the newest change onto
  each base a client may still acknowledge, once each, where each client used
  to merge every snapshot since its own base. `TacticalNav` keeps its fields
  per world (up to 8, the one used longest ago going first; a solid floor
  change walks them again): one cache for every game cleared itself whenever
  two matches (or a server and copies) took turns, and the bots walked
  whole-map fields every tick. `TacticalBot.calls` and `staged` are per game
  for the same reason.
- **Shots rewound from the tick that shot saw.** The host keeps the shown tick
  each input packet reported for its newest input (`Remote.views`,
  `_view_of`, worked out a tick an input from the nearest when a packet was
  lost); it used the newest tick reported by anything before the input was
  played, so a buffered shot was judged too late. `MAX_REWIND` is 64 ticks
  (under `REWIND_KEEP`, 72).
- `game.place_log` is still not carried: a copy put back on a snapshot keeps
  its own log, so a rewound shot in the next half second can play otherwise
  and part it (put back at the next check). With the inputs arriving, copies
  are put back for lost inputs about never (0 in the runs below), so it was
  left.

### The 3.2 lag measurements

`net_lag.gd -- seconds=90` (`old` for before), grainyard search and destroy,
four people and six bots, 2% loss, jitter a fifth of the latency, on this PC
loaded by other work (the server's milliseconds are only a guide; old and new
ran side by side). The 250 ms column after is the run after `NetPredict.MOST`
and the rewind keep were raised (below).

| | 50 ms before | after | 120 ms before | after | 250 ms before | after |
| --- | --- | --- | --- | --- | --- | --- |
| rubber band seen, jumps a minute (p95) | 0.2 (.064) | 0 | 0 | 0 | 1009 (.49) | 1 (.04) |
| everyone else frozen a frame | 0.7% | 0.2% | 8.4% | 0% | 16.3% | 0.1% |
| copies put back for lost inputs | 13 | 0 | 9 | 0 | 20 | 0 |
| looked a hit, judged a miss (no rewind) | 9% of 22 (27%) | 19% of 31 (42%) | 11% of 18 (39%) | 6% of 17 (35%) | 42% of 33 (73%) | 23% of 13 (69%) |
| down per client | 125 KB/s | 54 | 178 | 57 | 280 | 60 |
| delta median / p95 | 2431 / 7240 B | 687 / 1531 | 2951 / 8698 | 713 / 1832 | 5257 / 9681 | 828 / 1902 |
| whole snapshots in 90 s | 7 | 0 | 13 | 0 | 41 | 0 |
| server a tick (bots) | 12.6 ms (9.0) | 3.6 (1.1) | 9.4 (6.2) | 4.1 (1.1) | 14.0 (9.2) | 3.6 (0.8) |

The drawn player leads the server by the one-way trip (6, 11, 20 ticks: the
input shows at once), against 6 to 20 ticks behind without the prediction;
the round trip to confirmation is the link's own (200, 333, 633 ms). The hit
samples are small (a bot match): the rewind halves the misses at every
latency, and what is left is mostly the centre line grazing a body's edge.
At 250 ms the prediction stopped at 40 unplayed inputs (`NetPredict.MOST`, now
90) and shots past 38 ticks were judged unrewound (`MAX_REWIND` now 64,
`GameState.REWIND_KEEP` 72): that was the 1009 jumps a minute. The server's
match tick includes the bots' steering of the six bot slots; with one match
of a full 5v5 it is about a fifth of a core here (the VPS's core is slower
than this PC's, so allow more). County Run co-op keeps the old playout
(`Client.by_clock` off): its copies parted from the host while the party's
card picks held the world.

## Online 5v5

`src/net/net_play.gd`, `lobby_screens.gd`, `net_upnp.gd`; `docs/online.md` is
the how-to. The 5v5 rules themselves are in
[modes.md](modes.md#the-5v5-round-modes).

- `NetPlay.host_lobby` / `join_lobby`; the front end polls it every frame
  (`main.gd _net_frame`) and acts on `take_changes()` (a match began, back to
  the lobby, a bot or a person took a slot).
- HELLO carries name, password and version (refused: wrong password, another
  version, full, a match on without LATE JOIN).
- The host's settings are `NetPlay.LOBBY_ROWS` and `MATCH_ROWS` (rows and
  defaults in `data/tuning/lobby.cfg`); the match ones reach the mode through
  `Modes.HOST_SETTINGS` (freeze, buy and round seconds, start cash, friendly
  fire, bot skill, bots, `teams` and `names` by slot: the host is slot 0, then
  the people, then bots to the team size).
- A match is made by `main_flow.gd net_match_game` on every machine alike (the
  host's play settings, START's "sim", over each machine's own), then played:
  the host ticks at `NetSync.STEP` with its own player and the bots
  (`_net_host_tick`); a client sends controls and plays its copy out
  (`_net_advance`), and draws its own aim with the turns the host has not
  played yet (`_net_aim`).
- Someone leaving mid-match: a bot plays on in their slot; LATE JOIN: a
  newcomer takes the bot's slot on the team with fewer people. ESC asks
  before leaving; nobody pauses or saves.
- The router is asked for the port by UPnP on a thread; the join code is the
  outside IPv4 and port in ten characters (`NetPlay.to_code`). ENet peers wait
  `NetSession.PATIENCE_MS` of silence before giving up (a machine loading a
  map stalls).
- Play that reads `game.local_player` must not change anything carried: the
  5v5's "last one standing" call used to, and the online check found it.
- `tools/net_showdown_check.gd` holds it all (host plus three clients in one
  process, lag and loss as asked; in check_all and CI).

### Always-open lobbies

`NetPlay.serve_lobby`, `src/net/lobby_server.gd`, `--lobby-server=<json>`,
`server/` (deploy: `bash server/deploy.sh root@<server address>`,
`docs/online.md`).

- No host player; the first person in is the admin (`admin_id`, `is_admin()`,
  `admin_of()`; the admin's `set_setting`/`start_match`/`kick`/`back_to_lobby`
  go as ASK `set`/`start`/`kick`/`back`, checked by `allowed_value`, never
  `SERVER_ONLY` keys), the next in line when they leave.
- Results go back to the lobby after `BACK_AFTER` (`tally_at`, `back_in()`);
  an emptied lobby ends its match and takes `base_settings` back.
- MODE includes TAG TEAM 2V2 (`tagteam`, `play_mode()` makes it search and
  destroy; picking it or a 2v2 map moves the lobby to the other's map and
  format, `_mode_fits_map`), and a new online mode goes on that row.
- `server/lobbies.json` has two lobbies; server lines reach every lobby screen
  with the next LOBBY (`_tell`).
- One process runs every lobby with TacticalBot pilots on host games
  (`Game.new(..., true)`, which client copies match exactly), at most
  `most_matches` at once (`may_start`).
- `tools/net_server_check.gd` holds it.
- The firing range's board rides COUNTY RUN's BOARD knock: a knock with
  `range` in it is answered by `RangeBoard.answer` from
  `user://range-board.json` ([gameplay.md](gameplay.md#the-ranges-records-and-board));
  `tools/games_check.gd` knocks on a lobby server for it over ENet.

### The multiplayer menus

These are UiScreens now (`OnlineScreen`, a `ZonedScreen`; see
[ui.md](ui.md)), drawing with `LobbyScreens`.

- The title's MULTIPLAYER (state "multi", `LobbyScreens.draw_hub`,
  `OnlineInput.key_hub`) has four big choices: PLAY ONLINE (the server list),
  PLAY VS BOTS (the picker, state "showdown"), HOST A GAME, JOIN WITH A CODE;
  the lobby shows its main settings (`LOBBY_KEYS`) and ALL SETTINGS is its own
  page (state "lobbyset", `ALL_KEYS`, `OnlineInput.key_all`).
- **Every one of them works by touch and mouse**: each draw notes where a tap
  lands (`LobbyScreens.zones`, `zone`/`button`, cleared each `render()`) and
  `OnlineInput.tap` turns a tap into the key it stands for (`main.key`), so
  the keys stay the rules; a tap on a text field raises the phone's keyboard
  (`OnlineInput.keyboard`, `settle`). A setting changes with one click: its
  value is the next one, its < > step either way (the lobby's main settings,
  ALL SETTINGS, PLAY VS BOTS).
- **The 5v5 store** (`TacticalScreens.draw_shop`) is one big panel, guns left
  and gear and throwables right, drawn by main_state.gd over the gun and HUD;
  open on a desktop it lets the pointer go (`main.gd _shop_pointer`,
  `TacticalScreens.mouse_free`, `hover`) so an item is bought with a click,
  the gun never fires while it is open (main_input `_controls`), and it shuts
  itself when the buy time ends (`settle`). On a touch screen a BUY plate
  shows in the buy time (`TacticalScreens.touch_on`, `BUY_PLATE`); taps buy
  (`TacticalScreens.tap`, from `_touch_actions`), as an online match's YES /
  NO and results take taps.
- `tools/menu_touch_check.gd` (check_all, CI) taps through them all as touch
  events.
- Menu text: the readable 7-pixel font where it fits, `SOFT` for second lines,
  `Menu.FADED` a little brighter.
- **COUNTY SERVERS** (PLAY ONLINE; state "servers", `main.browser`,
  `LobbyScreens.draw_servers`): `NetBrowser` lists `data/tuning/servers.json`
  and asks each every `ASK_EVERY` seconds with an INFO knock (connect,
  `NetWire.INFO`, `NetPlay.summary()` back, hang up; `_info` never seats
  anyone; a served lobby has 6 spare ENet peers for them); ENTER joins through
  `net_join` like the JOIN form.

### Still open

(The start of this note was lost in an earlier edit of CLAUDE.md.) ... breaks
or the posse; per-player stats (chapter stats and the tally are the local
player's) and a kill feed; the steam scald list is keyed by hazard instance id
(not carried). Respawn, bodies blocking, area attacks on every player and the
group's boss fight are the modes' ([modes.md](modes.md)).
