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
  source, cause, who)`; a knock-back may move any player with `move_actor`
  (it took any player but the acting one for a hand until polish pass 9: a
  script error in co-op for the twister, the hogs and the bayou arena's
  waves). `game.reopen_paths()` opens a broken piece's cells
  in every player's flow field and the route.
- After focusing someone else, focus back: `game.focus(game.local_player)`.
- Outside a player's own step the tick leaves the LOCAL player acting, who
  is another on every machine. A hurt no player's hand dealt (fire, a
  still's jet, a blast nobody threw) is blamed on `Players.blamed` (the
  nearest player alive; `Players.world_hurt`), never on whoever is acting
  then: `hurt()` turns the enemy on the acting player (county_check
  `_party_twin` holds it).

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
Play kept on an object goes in a field (an enemy's `notes` for a boss's
moves and the like), never in its metas, which no snapshot carries (pass 12,
net_check scans for them). `game.bark_next` decides whether a hand's own
`Mind.bark_next` is set, so it is a SIM field; a simulation feature's looks keep their own dice that the
snapshot skips (`SnapCodec.SKIP_FIELDS`: the specks of `hit_reads` and
`critters`, whose count hangs on the specks already about), and what follows
this machine's callouts (`hit_reads._call_at`, after the BARKS setting and
`callout_until`) is skipped too. With more than one player `burst()` spends
`game.rng` whatever this machine's specks or GORE setting (it leaves the
specks out instead), and an object a snapshot carries by value is never
shared by two carried fields (a corpse names its feel, `Body.how`): putting a
snapshot on fills such an object in place, so a shared one took another's
numbers ([county_run.md](county_run.md#copies-that-parted-after-a-card-pick-online-fixed)).

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

`src/game_snapshot.gd`, version 3. `GameSnapshot.capture(game)` is a
Dictionary of plain values that never changes as play goes on (packed arrays
are shared by reference in Godot 4: encode and decode copy them):

- "game" (SIM_FIELDS);
- "world" (each door's progress, opened and discovered by its place in the
  level's list; the panes broken, in breaking order);
- "facts" (`FACT_FEATURES`' own save(), or its `net_facts()` where it has
  one, `GameSnapshot.fact_of`: what breakables and wall breaks broke, which
  changes the level's walls and floor; the arena wreck; the boss arena shut,
  `boss_lock`, whose restore lays its solid cells and gates on a copy; the
  breakables' leaves out the bits and fuses, pass 12);
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

A flow field travels as the cells its last walk reached, in runs of
neighbours in cell order, and their steps (`@flow`, pass 12: a County Run
player's field was 6 KB of a 9 KB delta packed, under 2 KB now; a row of
every cell, as before, still reads); a level's windows, fences, breakable pieces and boards carry only
what can change (`SnapCodec.ONLY_FIELDS`), a feature's tuning and lookups not
at all (`SKIP_FIELDS`). `to_bytes`/`from_bytes` (var_to_bytes, zstd),
`delta(base, now)` (dictionaries walked, each value compared once, bit for
bit; a changed dictionary is `{"@new": value}`, anything else travels as it
is; gone keys under "@gone", a new key order under "@order"), `patch`,
`patch_into` (into the caller's own copy), `merge(older, newer)` (two deltas
as one; null only for "@order": until pass 12 a value gone to null, an
enemy's `aim_mark`, came back as that null too, and the host sent every
client a whole snapshot), `same(a, b)` (bit for bit, key order too), `first_difference`
(each dictionary compared whole first, walked only where it differs: a
client's check every second took 100 to 180 ms walking it all).

A feature's NET_GUARDED lists (wall breaks' windows and fences, breakables'
pieces, carry's things) travel as one table each (`SnapCodec.guarded`,
`table`: `{"@T": [class, names, keys, columns]}`, a packed column a field
where its type allows), kept on the feature (a meta, never a script
variable) until its `net_version` moves: a capture costs nothing for them
while nothing broke. `apply` leaves a list the game already holds as it is
(`guarded_same`) and notes what each now holds (`guarded_now`,
`guarded_moved`), so a copy put back costs nothing for them either. The same
rule as NetTrack's: anything that changes one of those objects bumps
`net_version`; net_check holds the kept tables against fresh ones
(`SnapCodec.keep_tables` off). Enemies' and players' fields are read into a
row and written back in one call each (scripts made per class: `_rower`,
`_putter`; `put_fields`).

Inner classes are named by their feature's file (`wall_breaks.Fence`), all
roots first (`_register_all`). Before version 3 a feature reached first
through another's preload named its inner classes by that path
(`boss_fight.Corpses.WallBreaks.Fence`), so ONLY_FIELDS and SKIP_FIELDS never
applied to them: every fence carried its tuning (a Hickston snapshot was
892 KB before packing, 392 KB now; 32 KB packed, 26 KB now), the breakable
bits' `landed` and `spin0` (this machine's view) were carried, and a feature
reached so was carried by value instead of named.

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
`join_near(game)` seats one more player. `close()` disposes the host's own
game (not an adopted one; [architecture.md](architecture.md#letting-a-game-go)).

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
breakables' pieces, carry's things) compares each as its table
(`SnapCodec.guarded`, the snapshot's own form) only when its `net_version`
moved, and sends it whole when it changed: anything that changes a window,
fence or piece must bump it. The changes per
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

Pass 6 (snapshot version 3: tables, inner classes named by their file, rows
read and written in one call, `first_difference` comparing whole first), on
this PC loaded by other work, `net_bench -- levels=hickston players=1,4`,
medians of three runs old and new back to back (a quieter set of three
before it in brackets): a whole capture 28 -> 5.6 ms (18 -> 5.2), 892 KB raw
-> 392 KB, 35.0 -> 28.8 KB packed, packing 10 -> 3.1 ms; onto a fresh game
54 -> 15 ms (47 -> 11); a client's check every second (capture and compare)
226 -> 17 ms (192 -> 9.4); a copy put back on a snapshot 52 -> 10 ms (49 ->
5.9); the host's whole snapshot 46 -> 13 ms (26 -> 8.1), a mirror taking it
65 -> 18 ms (43 -> 11). The host's delta (NetTrack, 2 KB) and a mirror
putting one on are as they were (3 to 5 ms, 1 to 2 ms); the generic capture
and diff (`GameSnapshot.delta`, only the old untracked way) 27 + 47 -> 7.9 +
21 ms (17 + 32 -> 4.4 + 12). What is left of a capture is mostly the
enemies (each one's row, 2 to 3 ms for 100).

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
and with 2 and 4 players, and the host's snapshot with its guarded tables
kept is the one encoded afresh; deltas merge; a copy put back on a snapshot
keeps its dice and its thrown bodies' slide (`_put_back`). The bot (`bot_pilot.gd as_controls`)
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
- The run's replay goes beside the log (`session.replay`, below): kept as
  `crash-<stamp>.replay` with a crash log, dropped at a clean exit.

### Replays

`src/replay.gd` (`Replay`), the front end's part in `src/replay_keeper.gd`.
Play is deterministic, so a run is its start and each tick's controls:

- **What a replay holds.** A header (build, level, layout, the mode's setup
  {mode, count, options}, the rng seed, god, history, the physics tier
  `Quality.physics`, which steps some play) and segments. Each segment starts
  from a keyframe (`GameSnapshot.to_bytes`, or nothing for a fresh game made
  as the tools make one, then seeded) with the options it was configured with
  (FOV aims the shots, so all of them), then a byte stream: a tick's controls
  as the fields that changed by slot (floats 0/1/-1 in the tag, else float32
  when exact, else float64; the buttons as one byte; ints zigzag), a run of
  ticks unchanged, an action between ticks, a hash every `HASH_EVERY` (120)
  ticks, a snapshot when the game was touched, the end. The file is MAGIC, the
  size and the values zstd'd.
- **Actions between ticks.** The front end's keys that change play outside
  `game.tick` (USE, a gun slot, the wheel, reload, holster, turn back, level
  the view, a pocket, an item, a County Run card, the build screen's hold)
  go through `main.act(game, op)`, which records the op and does it
  (`Replay.apply_op`, the same code playback runs). A setting changed mid-run
  is an "options" op. New front-end code that changes play must use act() (or
  add an op).
- **Touches.** `Replay.probe` (each player's place, view, speed, health, gun,
  pockets; the dice, the enemy and shot counts, god, touch aim) is taken after
  every tick and before the next; a difference means something else changed
  the game (a cheat on the title, the dev console, the revisit respawn), and a
  snapshot of the game then goes in the stream. The console's commands take
  one always, and so does a tuning change (`tune set`/`reload`, a tuning file
  read again when saved). The tuning itself is not in the replay: a replay
  played with other numbers than it was made with parts at the first tick
  they matter.
- **Recording only reads.** A keyframe's capture would name new things
  (`name_new`); `capture_quiet` takes those uids back. Nothing in the tick
  changes; the tick profile is the same with and without (`tick_profile.gd
  replay`).
- **How much is kept.** The whole run up to `CAP_TICKS` (30 min), then
  segments of a minute, the newest five; a saved replay is the run's start and
  its last minutes, played across the gap from the next keyframe.
- **When it is written.** `ReplayKeeper` records a local game from its first
  tick (so a County Run's seed, a kit, a loaded save are in the keyframe):
  REPLAYS on (PLAY page), not online, not a tool, tour, bench, smoke run or
  demo. A death or the end writes `user://replays/<stamp>-<level>-<why>.replay`
  (the newest 12 kept), every 30 s the session's file is brought up to date,
  and the console's `replay save` writes it now. Files are packed and written
  on a worker thread.
- **Playing one.** `--replay=<file>` (a path, or a name in user://replays)
  plays it in the game's view: the keys do nothing to it, Esc leaves, the HUD
  says when it is over or the first hash that differed. `Replay.Playback`
  (`start(maker)`, `step()`, `run()`, `diverged`, `last_good`,
  `end_matches()`) is what tools use.
- **Costs** (measured on the owner's PC while other work ran, 2026-11-16): a
  tick's recording about 6-9 us alone and 13-20 us beside the real tick
  (about 1% of a 1.5 ms tick; the second tick of a frame skips the probe); a
  keyframe 6-13 ms (taken once at the start, then a minute apart only past
  the cap). The controls are 20-100 KB a minute raw for the bots (a turn every
  tick), about 25 KB a minute zstd'd.
- **Guard.** `tools/replay_check.gd` (check_all, `-- quick`) records bot runs
  (chapter one fresh, sawmill from the middle with actions and touches, the
  quarry boss, County Run, co-op), plays each from its bytes, and needs every
  hash and the whole end snapshot equal; a refactor that changes play by a
  hair fails it.
- **Not done.** A replay recorded on a phone (wreckage takes fewer pieces
  there by the device, not the tier) may part on a PC. Online games are not
  recorded. The kill cam still uses its own samples, not the recorded ticks.
  `-0.0` in a control is recorded as whichever zero came first.

### The transport

`src/net/`: `NetSession` wraps ENet or WebSocket (`MultiplayerPeer`, packets
only), with test latency, jitter and loss on what it sends (on the clock
handed to `poll`; a lost unreliable packet is dropped, a lost reliable one
comes a resend later and holds up its channel, `resend_lost`). `NetWire` is
every packet's layout (protocol 5, snapshot version 3: an older client is
refused at HELLO; controls in 14 bytes, buys, reloads and the host's rewind
among them; inputs sent redundantly with the tick the client shows;
snapshots with their base, tick, input ack and the inputs played since the
base, those rows zstd'd; a snapshot too big for a packet in unreliable
`SNAP_PART`s; the lobby's messages). See [pacing](#pacing-packets-and-the-one-core-server-pass-12).

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

One process, a host and a client peer on 127.0.0.1 (a free port from
`tools/net_ports.gd`, so parallel checks do not meet), two games, the game's own clock. The
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
for comparison); each client's own shots, button to flash shown at the press
and as the copy played it, and how many were withdrawn
([modes.md](modes.md#shots-reloads-and-pickups)); bandwidth per client, delta sizes, and the server's cost per
tick split into the game, the snapshots and the bots, as a share of one core.
`old` turns every fix below off (statics on NetSync, NetPredict.Smoother,
NetSession, Modes and TacticalNav), so before and after run on one build;
`oldserver` only pass 12's server side (the 3.9.0 server: its loop, rows
unpacked, a big snapshot reliable); `snaps=N` a snapshot every N ticks;
`quick` (check_all) is one 120 ms link for 30 s with limits. The numbers are
in [the 3.2 measurements](#the-32-lag-measurements) below. Until pass 12 the
test's loss never touched a reliable packet, so the stalls a reliable
snapshot stream has on a real network were invisible here (the 3.2 table's
"frozen" column is low for that reason); it also prints the snapshot
packets' sizes, how many were over the MTU and went in parts, and the
reliable packets the loss made late.

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
- `game.place_log` is not in a snapshot: a copy put back on one kept its
  own log, so a rewound shot in the next half second could play otherwise
  and part it. Since pass 12 each tick's row travels with the echoed inputs
  and a copy put back takes the ticks it skipped from them
  ([below](#soaking-every-mode-pass-12)).

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
than this PC's, so allow more). County Run co-op kept the old playout
(`Client.by_clock` off) until pass 12: its copies parted from the host while
the party's card picks held the world. The partings were found and fixed in
pass 9 ([county_run.md](county_run.md#copies-that-parted-after-a-card-pick-online-fixed));
pass 12 paces it by the clock like every other mode (`NetPlay.county_by_clock`;
county_net_check passed every run with it).

### Frame by frame (pass 12, `net_feel.gd`)

net_lag steps one frame a tick, so it could not see what a screen faster
than the tick shows. `tools/net_feel.gd` draws one client the way main.gd
does (its own `advance()`, `net_draw_begin()`, `net_draw_end()`) at a
screen's rate (`hz=144` or `60`, a quarter millisecond of wobble a frame),
the others bots on their own copies, over 127.0.0.1 ENet with latency,
jitter (a fifth of it) and 2% loss on both sides, in a 5v5 round, online
deathmatch, campaign co-op as a client (`coop`) and as the host's own view
(`host`, main.gd hosting), and County Run co-op; the same scene
single-player is the bar (SP: the game's own 120 ticks). Per frame it
records our eye, every other player and hand near us, the gun's flash, the
hit mark and the correction drawn; a moving thing's step is held against
its own pace over the 7 frames round it (frozen: under a quarter of it;
uneven: off by over 35%; jerk: the mean of how far off), the view's turn
against the mouse's that frame, key and mouse to screen (the bot is stopped
for a few frames now and then and let go), and how far behind the host's
tick now the others are drawn. `ways=old,new` runs v3.9.0's way and the new
one on one build; `quick` (check_all, ALONE) holds the 5v5 client and the
co-op host at 120 ms to `QUICK_LIMITS`.

What it found:

- **Online ticks at 60, single-player at 120, and neither drew between
  ticks.** On a 144 Hz screen a client's own player and everyone else held
  still for one or two frames and then stepped two ticks' worth: 55 to 58%
  of frames frozen and every frame off its pace (single-player: 17% frozen,
  a third uneven). The host's own view (online co-op, deathmatch) turned
  only at the tick (60% of turning frames held; the mouse took 7 to 14 ms
  to show).
- **Fixed, looks only, put back after the frame:** our player is carried
  into the next tick by the frame's share of it with the keys held now and
  turned by all of the mouse not sent (`NetPredict.ahead`; the host's own
  player too, `main.gd _host_aim`). Everyone else is drawn between the
  copy's last two ticks (`NetBlend`) at the fraction of a **render clock**
  (`NetSync.Client.view_at`, `_view_clock`): it runs with the frame's own
  time (`client_play(steps, elapsed)`) and eases toward the host's tick
  less the playout depth by at most 8% faster or 15% slower (it jumps only
  when 10 ticks off), so a quicker arrival, a late snapshot or a deeper
  playout bends its pace instead of freezing or hurrying everyone; the copy
  is played to the tick at or just past it (`_paced`). Our inputs report
  the tick shown, rounded (`shown_tick`), for the rewind. The front end's
  online clock is to the microsecond (`_net_frame`). The host blends its
  others a tick back by `net_accum`.
- **Co-op partners bumped.** The prediction walked us into the copy's
  partner, a round trip and the playout behind the host's: two co-op bots
  following each other were corrected 1,200 to 1,530 times a minute. The
  walk now meets the others who block where the host will have them
  (`NetPredict._mates`): 90 to 280 a minute (the rest is the partner
  turning), and the correction drawn is a fifth of what it was.
- **The walk missed mud and knock-downs, and walked through holds** (County
  Run's card picks, where the host plays nobody's input): `NetPredict.step`
  has both now, and while the copy holds the inputs the host echoed for
  those ticks are not walked (`held()`, lead's `echoed`); ours it has not
  played are, since they reach it after the pick (freezing them froze the
  view for a round trip after every pick).
- **County Run co-op** is paced by the clock like the rest
  (`NetPlay.county_by_clock`).
- **A thrown shot** showed a round trip late from behind us; now a ghost
  from the press, then the copy's own drawn on to our time
  (`NetOwnShots`, [modes.md](modes.md#shots-reloads-and-pickups)).

The pass 12 numbers, measured on the pass 12 server ([pacing, packets and
the one-core server](#pacing-packets-and-the-one-core-server-pass-12): 30
snapshots a second, big ones in unreliable parts): `net_feel.gd --
seconds=20 ways=old,new`, and `hz=60`; the tool's clock is its own, so runs
repeat nearly to the frame. Old is this track's fixes off on the same build
and server; v390 (one 120 ms run) is old with the server's side off too, as
3.9.0 played. At 144 Hz, old -> new; SP is single-player:

| 144 Hz | SP | v390 120 ms | 50 ms | 120 ms | 250 ms |
| --- | --- | --- | --- | --- | --- |
| 5v5: view frozen frames | 16.6% | 58.3 | 58.3 -> 0.1 | 58.3 -> 0.0 | 56.6 -> 0.0 |
| 5v5: view jerk | 35% | 114 | 114 -> 2.2 | 114 -> 2.3 | 110 -> 2.7 |
| 5v5: turn held against the mouse | 17% | 0 | 0 -> 0 | 0 -> 0 | 0 -> 0 |
| 5v5: others frozen | 16.5% | 57.7 | 58.2 -> 0.4 | 58.3 -> 0.0 | 58.3 -> 0.0 |
| 5v5: others jerk | 34% | 110 | 114 -> 1.4 | 114 -> 0.2 | 114 -> 0.2 |
| 5v5: others drawn behind the host | | 367 ms | 117 -> 112 | 267 -> 269 | 450 -> 432 |
| deathmatch: view frozen | 16.7% | 55.3 | 54.9 -> 0.5 | 54.3 -> 0.6 | 53.1 -> 0.7 |
| deathmatch: others frozen | 16.7% | 57.3 | 58.2 -> 1.4 | 58.3 -> 0.2 | 58.5 -> 6.0 |
| deathmatch: others jerk | 35% | 110 | 114 -> 5.0 | 114 -> 1.7 | 115 -> 12 |
| deathmatch: marks with the shot's frame | 100% | | 62 -> 71% | 23 -> 56 | 58 -> 86 |
| co-op client: view frozen | 17.5% | 7.3 | 16.7 -> 0.9 | 8.7 -> 1.3 | 33.2 -> 1.7 |
| co-op client: view jerk | 37% | 40 | 56 -> 7.5 | 34 -> 8.1 | 77 -> 7.4 |
| co-op client: corrections a minute | 0 | 1554 | 1269 -> 90 | 1530 -> 276 | 1203 -> 180 |
| co-op client: correction drawn (cells) | 0 | | .105 -> .007 | .136 -> .029 | .086 -> .014 |
| co-op client: others frozen | 17.9% | 57.6 | 58.2 -> 3.4 | 58.1 -> 1.9 | 59.2 -> 10.7 |
| co-op host's own view: frozen | | 58.4 | 58.3 -> 0.4 | 58.2 -> 1.1 | 58.3 -> 0.6 |
| co-op host: turn held against the mouse | | | 60.1 -> 0 | 59.9 -> 0 | 60.1 -> 0 |
| co-op host: key / mouse to screen | | | 0 / 6.6 -> 0 / 0 ms | 7.0 / 7.2 -> 0 / 0 | 6.6 / 13.7 -> 0 / 0 |
| co-op host: others frozen | | 58.8 | 58.7 -> 1.3 | 58.7 -> 1.2 | 58.4 -> 1.6 |
| County Run: view frozen | 17.1% | 56.8 | 54.1 -> 0.2 | 52.6 -> 0.9 | 52.0 -> 2.5 |
| County Run: others frozen | 17.4% | 61.3 | 59.4 -> 2.4 | 58.9 -> 1.9 | 60.2 -> 7.2 |
| County Run: others jerk | 36% | 125 | 139 -> 6.4 | 129 -> 5.2 | 128 -> 16 |
| County Run: others drawn behind the host | | 183 ms | 100 -> 118 | 183 -> 277 | 333 -> 450 |

At 60 Hz one tick a frame already, so old was close for the view (frozen 1
to 2% either way; single-player 0.5 to 1.8%), but the others stepped
unevenly: 5v5 frozen 2.7 to 3.0% -> 0.0 and jerk 8 to 10% -> 0.6; co-op 5.3,
6.0, 16.1% -> 3.2, 1.8, 12.4; County Run 12.8, 19.7, 26.5% -> 3.3, 3.5,
13.8; the host's turn held 0.5 to 1% -> 0. Key and mouse to screen are the
same frame everywhere online now (single-player's own is up to a tick), an
own shot's flash shows at the press, and the round trip to the host's word
is the link's (151, 313, 603 ms).

**Late input rows** (`Client._rows_late`, `ROWS_WAIT`): a missing row for
the next tick may still be coming in a snapshot that a newer one passed
(jitter reorders the unreliable ones); the copy waits for it while the
newest is under 12 ticks ahead instead of jumping to the newest at once.
At 250 ms: co-op put back 10 -> 5 times in 20 s, County Run 14 -> 6, the
others' jerk 28 -> 26% and 18 -> 15%.

What it does not fix, and why:

- **How far behind the others are drawn** is the one-way trip, the
  snapshot gap and the arrivals' jitter: 112, 269, 432 ms in the 5v5 (3.9.0:
  367 at 120 ms). County Run's are 20 to 120 ms more than its old playout's,
  which stood two ticks behind the newest snapshot whatever the jitter and
  froze them 13 to 27% of the frames at 60 Hz.
- **60 snapshots a second** (`snaps=1`): at 120 ms the others are drawn
  240 to 280 ms behind against 264 to 277 at 30, about a tick sooner, with
  no other gain in smoothness (frozen 0.0 to 1.6% either way); at 250 ms
  and 50 of jitter it breaks down: 43 copies put back in 20 s for input
  rows that never came, everyone else frozen 86% of frames (the host
  repeats only `ECHO_AGAIN` snapshots' worth of rows, 3 ticks at that
  rate). Not worth it as it stands.
- **Other people at 250 ms** (deathmatch, co-op, County Run: 6 to 11% of
  frames frozen, 12 to 22% jerk; the 5v5's server bots none): the host
  plays a person's late input held and then merges the pile, so they move
  unevenly on the host itself; a small input buffer per client on the host
  would even it out.
- **Hit marks**: a centre line well on the body is marked at the press
  (`NetShotPredict.SURE`); a grazing one when the host's word comes. The
  rewind judges at the shown tick rounded, at most half a tick (8 ms) off
  what the blend draws: net_lag's "looked a hit, judged a miss" (before
  the server's changes) was 0 / 4.8 / 21% at 50 / 120 / 250 ms with this,
  0 / 13.6 / 20% without.
(`Client.by_clock` off): its copies parted from the host while the party's
card picks held the world. Pass 12 found why (the check's own XP handed
between ticks, and whole snapshots every second or two from the merge of a
null; [county_run.md](county_run.md#copies-that-parted-after-a-card-pick-online-fixed)):
it can go by the clock like the rest.

## Online 5v5

`src/net/net_play.gd`, `lobby_screens.gd`, `net_upnp.gd`; `docs/online.md` is
the how-to. The 5v5 rules themselves are in
[modes.md](modes.md#the-5v5-round-modes).

- `NetPlay.host_lobby` / `join_lobby` (a party line code or an address); the
  front end hosts with the party line on; the front end polls it every frame
  (`main.gd _net_frame`) and acts on `take_changes()` (a match began, back to
  the lobby, a bot or a person took a slot).
- HELLO carries name, password and version (refused: wrong password, another
  version, full, a match on without LATE JOIN).
- The host's settings are `NetPlay.LOBBY_ROWS` and `MATCH_ROWS` (rows and
  defaults in `data/tuning/lobby.cfg`); the match ones reach the mode through
  `Modes.HOST_SETTINGS` (freeze, buy and round seconds, start cash, friendly
  fire, bot skill, bots, `teams` and `names` by slot: the host is slot 0, then
  the people, then bots to the team size). BOT SKILL is EASY, NORMAL, HARD,
  HOG WILD or MIXED (each bot its own skill by its place in its team; the
  bots' aim and play
  are in [modes.md](modes.md#the-bots)). The bots steer on the host only;
  their controls are carried like a person's, so a client never runs them
  and their dice are their own (never `game.rng`). The team radio is worked
  out on each machine from what it already holds (looks only).
- A match is made by `main_flow.gd net_match_game` on every machine alike (the
  host's play settings, START's "sim", over each machine's own), then played:
  the host ticks at `NetSync.STEP` with its own player and the bots
  (`_net_host_tick`); a client sends controls and plays its copy out
  (`_net_advance`), and draws its own aim with the turns the host has not
  played yet (`_net_aim`).
- CAMPAIGN CO-OP, DEATHMATCH and TEAM DEATHMATCH are on the same MODE row
  (people only, four at most; the co-op campaign moves the match from game
  to game with `NetPlay.switch_match`): see
  [modes.md](modes.md#online-co-op-and-deathmatch). The lobby shows their
  posse as one list (`LobbyScreens._posse`) and only their own settings
  (`lobby_keys`). The main settings' "<" stands past each column's longest
  label (a value too long for what is left takes the small letters); LATE
  JOIN shows there as DOORS OPEN / SHUT (`SHORT`).
- Someone leaving mid-match: a bot plays on in their slot; LATE JOIN: a
  newcomer takes the bot's slot on the team with fewer people. ESC asks
  before leaving; nobody pauses or saves.
- The router is asked for the port by UPnP on a thread; the join code is the
  outside IPv4 and port in ten characters (`NetPlay.to_code`). The lobby's
  first line is the party line's code when it has one (C or a tap copies it),
  the second how the router answered; a player sees whether they came by the
  line or straight in. ENet peers wait
  `NetSession.PATIENCE_MS` of silence before giving up (a machine loading a
  map stalls).
- Play that reads `game.local_player` must not change anything carried: the
  5v5's "last one standing" call used to, and the online check found it.
- `tools/net_showdown_check.gd` holds it all (host plus three clients in one
  process, lag and loss as asked; in check_all and CI).
- **When joining goes wrong** the client is told why: another version (both
  named) or protocol, WRONG PASSWORD, THE LOBBY IS FULL, A MATCH IS UNDER
  WAY, COULD NOT REACH THE HOST (`CONNECT_WAIT`), THE HOST NEVER ANSWERED
  (`ANSWER_WAIT` after the HELLO; pass 9, it used to wait on "hello" for
  ever), LOST THE HOST. Those in `NetPlay.RETRY` (the line or the host
  went quiet) take the front end back to the JOIN form as it was, the note
  `... ENTER TO TRY AGAIN.` and the cursor on JOIN (`main_flow.gd
  net_closed`): late join seats them again. A refusal or a host who closed
  the lobby goes to the title as before. `tools/net_errors_check.gd`.
- **The round trip** a client measures (`Client.lag_samples`, the dev
  overlay's) is stamped on the clock of every poll; until pass 9 only a
  poll with a snapshot moved it, so the first inputs were stamped 0 and
  their trips were the whole time since the program started (75 s in a
  soak). net_showdown_check holds the longest trip to the link's.

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
- `server/lobbies.json` has two lobbies (how many is only that file: the
  INFO answer's `ports` let COUNTY SERVERS drop a listed lobby the server
  does not run); server lines reach every lobby screen with the next LOBBY
  (`_tell`).
- One process runs every lobby with TacticalBot pilots on host games
  (`Game.new(..., true)`, which client copies match exactly), at most
  `most_matches` at once (`may_start`). A finished match's game is disposed
  once its lobby lets it go (the server's `GamePool`, swept each frame), so
  months of rounds do not pile up.
- `tools/net_server_check.gd` holds it.
- The firing range's board rides COUNTY RUN's BOARD knock: a knock with
  `range` in it is answered by `RangeBoard.answer` from
  `user://range-board.json` ([gameplay.md](gameplay.md#the-ranges-records-and-board));
  `tools/games_check.gd` knocks on a lobby server for it over ENet.

### The party line (the relay)

`src/net/net_relay.gd` (`NetRelay`, in the lobby server), `src/net/relay_link.gd`
(`RelayLink`, a `NetSession`, the far end); players' how-to in
`docs/online.md`. Anyone hosts from the menu with no port opened, behind
CGNAT, or in the browser: the host's game still plays the one real game, the
party line only passes bytes between it and its players.

- **Where it runs.** `server/lobbies.json`'s `"relay"` (any of
  `NetRelay.DEFAULTS`) turns it on in `LobbyServer`, on the lobbies' own ports:
  `relay.tap(session)` for each lobby's ENet and WebSocket session. A packet
  whose first byte is `NetWire.RELAY_FIRST` (0xF0) or more goes to the line
  (`NetSession.poll`); a peer that opens, joins or looks for a room is then the
  line's (`NetSession.claim`): the lobby never sees its packets, its leaving,
  its drop or its share of a broadcast. So no new port or firewall rule, and
  the browser reaches it over the wss it already has. Rooms are process-wide:
  a room opened on one port is joined from any of them, ENet or WebSocket.
  `NetRelay.listen(port)` gives it a port of its own (the check).
- **The game finds it** in `data/tuning/servers.json`: the first server marked
  `"relay": true` (its address and port, the browser its `wss`).
  `RelayLink.server` overrides it; a tool script never reaches the real one
  unless it sets that (`RelayLink.where`).
- **Packets** (the table is at the top of net_relay.gd): controls are
  `NetWire.message` dictionaries (OPEN, ROOM, LOOK, FOUND, JOIN, IN, PEER, KICK,
  NEWS, LIST, STAT, GONE). A player's game packets go as they are (the line
  knows their room) and reach the host as `FROM` + id (u32) + the bytes; the
  host's go as `TO` + channel + id (0 everyone) + the bytes and reach the
  player as the host sent them, on that channel. ENet's own channel and
  reliability are kept (a WebSocket's are all reliable). The line reads only
  the first byte of a game packet: a new game packet kind needs nothing here,
  only that its first byte stays under 0xF0.
- **Codes.** Three letters with no vowels (no words) and three digits,
  `HKP-427` (`NetRelay.clean_code` reads `hkp427` too); a 10-character join
  code is still the host's own address, not the line.
- **The API for a mode** (online co-op and deathmatch are built on it,
  [modes.md](modes.md#online-co-op-and-deathmatch)): host
  with `NetPlay.host_lobby(port, name, lobby, router, bind, true)` (the last
  `party_line`): the desktop's own ENet session gets the room as its `also`
  (the line's players are ids past `ALSO_IDS`, beside direct ones); the
  browser's session is the room itself. Join with `NetPlay.join_lobby(code,
  ...)`. Below NetPlay: `RelayLink.open_room(info)` (`state` "open", `code`),
  `RelayLink.join_room(code, may_look)`, `RelayLink.ask_rooms()` (`rooms`),
  then the ordinary NetSession calls (`send`, `poll`, `take_events`, `drop`,
  `connected`, `refusal()` for why it was turned away or lost, `extra_ms()` the
  host's own trip for the ping, `via()` "line" or "direct"). `news(info)`
  tells the line the lobby changed (NetPlay does it in `send_lobby` and when
  the router answers). Nothing in the line knows a mode, a map or a snapshot.
- **Straight to the host when it can.** A desktop player asks the line where
  the host is first (LOOK): the host's home addresses when both come from one
  outside address, else its outside address when its router opened the port
  (`NetPlay.room_info`: `port`, `open`, `lan`). It tries those for
  `RelayLink.DIRECT_WAIT` (3 s), keeps the first that answers (`state`
  "direct": a plain line to the host, the line hung up) and otherwise joins
  through the line. The browser (WebSocket) joins through the line at once.
- **Limits** (`NetRelay.DEFAULTS`, all in lobbies.json): 24 rooms, 4 from one
  outside address, 15 players a room, 1,000,000 bytes a second a room both ways (over it only reliable
  packets pass and the line logs it once; ten seconds over twice it shuts the
  room), a room nobody is in closes after 30 minutes, packets over 256 KB are
  dropped, someone who only looked is let go after 10 s, 64 ENet peers each
  port for the line. The host leaving or timing out (ENet, 15 s of silence)
  closes the room and tells its players (GONE "THE HOST HUNG UP"). The log
  has each room's opening and closing (minutes, joins, bytes each way,
  dropped) and a status part (rooms, players, bytes and packets a second).
  While a room has players the server wakes every `RELAY_POLL_MS` (4 ms;
  it was a 120 a second frame until pass 12), and the line flushes every
  session after it (`NetSession.flush`), so a packet waits that long at
  most once each way (not measured again since).
- **Costs**, measured on the owner's PC (`tools/relay_check.gd`, others' work
  running): the line in process, polled flat out, adds about 0.07 ms to a
  round trip; at 120 frames a second it adds 9 to 11 ms median (13 to 14 p95),
  half a frame each way on average, on top of the trip to the server and
  back. A 3v3 with two players through it: up 3.0 KB/s and down 21 to 24 KB/s
  a player (payload; the line's header is 5 bytes a packet up, 6 down); a
  5v5 on Grain Co-op with three people and seven bots (`relay_check --
  team=5 map=grainyard seconds=60`) up 3.0 and down 27 KB/s a player, about
  85 packets a second each, so a full room of nine is about 250 KB/s
  through the server. One forwarded packet is a dictionary lookup and a
  slice.
- **Not checked:** two real homes through the VPS, CGNAT, a phone, the browser
  build hosting in a real page, the VPS's CPU with full rooms.

### Soaking a server (`tools/net_soak.gd`)

Probes (2 to 4) join one always-open lobby on the real clock, the first
starts a match, TacticalBots play each from its copy, and the match is put
through a hang (a probe polls nothing for `stall` seconds), a leave and
join again, and the admin leaving (the lobby passes on) and coming back;
it prints drops, partings, put-backs, round trips, bandwidth and memory.
Against a real server (`server=<address:port>`, never written into the
repo) it knocks first and joins only an empty lobby of its own version.
The pass 9 runs are in [the pass 9 soak](#the-pass-9-soak).

### The pass 9 soak

Against the VPS (v3.6.0, Linux) from this PC (Windows) with this build,
2026-11-17, about eight minutes in all: the party line's echo 64 ms median
(78 p95); three probes on the tag team lobby, then four on the 5v5 one.
Nobody was dropped by a 4 to 6 s hang, a leave and join again, or the admin
leaving; the round trip to the confirmation of an input was 62 ms median,
78 to 112 p95; down 23 KB/s a probe in tag team, 41 in the 5v5, up 1 to 2.
The copies parted from the server 3 to 6 times in two minutes on floats a
last bit apart (`vy`, `bob`, `wind`: printed alike, the bits not): Linux and
Windows round sin, cos and their kin differently, which no check on one
machine can see. Each parting put the copy back on a snapshot. With
`NetSync.Client.NEAR` for a host on another system the next runs parted 0
times. Under heavy load on this PC (ten checks at once) a probe's copy was
put back about every 6 s for inputs whose rows never came (the process
starved, not the line). Memory: the process grew from about 290 to 360 MB
over three minutes as the games' capped pools (bullet holes, specks,
debris) filled, and much more slowly after; nothing found growing without
a cap (`grew=1`).

### Pacing, packets and the one-core server (pass 12)

The owner found online play jittery. On the server's side three things
made it so, found with `tools/net_pace.gd` against a lobby server in its
own process pinned to one core of this PC with a busy process taking 60% of
that core (standing for the VPS's one slower vCore), both lobbies in a
match and the party line on, and probes on the other cores:

- **Nearly every 5v5 snapshot went reliable.** A snapshot carries the inputs
  every player played since the client's acknowledged base (with a real
  round trip about 8 ticks of 10 players, 1.2 KB) and the delta (0.7 to
  1.5 KB): about 2 KB, and `NetSession.send` turns anything over `MTU_SAFE`
  (1200) on an unreliable channel reliable. So 97% of a 5v5's snapshots
  went on ENet's reliable channel, where one lost packet holds up every one
  after it until it is resent (a round trip and more). Clients got
  snapshots in bunches with gaps of 125 ms, and their playout depth
  (`NetSync.Client.playout_depth`) grew to 8 or 9 ticks to cover it:
  everyone else shown about 140 ms late, and still jerky. None of the checks
  saw it: their test loss dropped only unreliable packets.
- **The loop.** `Engine.max_fps` 120 frames, each room's ticks from the
  frame's delta: a snapshot left at the first frame after its tick, so its
  time against its tick wandered by up to a frame (8 ms) and Godot's own
  frame timing (p99 18 ms over the quickest); a late frame sent the snapshots
  it owed back to back; a stall past 8 ticks lost the time for good (the
  clients' reckoning of the server's tick then ran ahead for seconds).
- The status line's memory always said 0 MB (a /proc file read whole is
  empty).

What changed:

- **The rows packed** (`NetWire.snap`, zstd): a 5v5's 1.2 KB of rows are
  about 200 bytes (`NetWire.pack_rows` off: as they were).
- **A snapshot over `NetWire.PART_MOST` goes in `SNAP_PART`s**, unreliable
  (`NetWire.split`, `NetSync.Client._joined`; `Host.split_big` off: the old
  reliable way). A lost part loses that snapshot only; the next one is a
  delta from a base the client has. Parts leave room for the party line's
  header, so none turns reliable on the way. Only a whole snapshot (a
  joiner's first) is still reliable, and it goes after everyone's delta of
  that tick has been flushed (`_deltas_first`). A player's own lobby (the
  front end hosting) sends its snapshots the same way.
- **A paced loop** (`LobbyServer.paced`; the config's `"old": true` for the
  3.9.0 server on this build): one schedule for every match, a tick every
  `NetSync.STEP` from when the first began, and the loop sleeps itself to the
  next tick (`_rest`: no frame cap, no headless frame sleep). A late wake
  plays the ticks it owes (`MOST_STEPS` at most, the rest at once after) and
  only the last sends snapshots (`Host.hold`: a stall never sends a burst);
  behind by more than `SLIP_MS` it lets the time go and says so (`SLIPS` in
  the status). Each tick's packets are flushed at once; the bots steer for
  the next tick after that (the same controls as before: the state they
  read is the same), off the snapshots' way. Two matches send their
  snapshots on alternate ticks (`Host.snap_phase`). While the party line
  has players the loop also wakes every `RELAY_POLL_MS` (4) to pass their
  packets on (it was a frame, 8 ms).
- The status line has each room's snapshot gaps (median, p99, worst,
  bunched) and its ticks' p99, and the memory again.
- **The test loss hits reliable packets** (`NetSession.resend_lost`): one
  lost comes a round trip, twice the jitter and `RESEND_MS` later and holds
  its channel up, as ENet's resend does.
- Protocol 5 (an older client is told the server runs another version).
- The service runs at `Nice=-10`, so nothing else on the one core (a daily
  apt run) holds up a tick.

The numbers. `net_pace` against the pinned server (lobby 1 a 5v5 with four
people and six bots, lobby 2 a 2v2 with three people; 30 ms, up to 6 ms of
jitter and 2% loss each way; two 60 s runs of each, old and new back to
back; this PC also ran other tracks' checks):

| lobby 1 (5v5) | 3.9.0 server | pass 12 |
| --- | --- | --- |
| gaps between snapshots, p99 | 125 to 131 ms | 67 to 70 ms |
| snapshots bunched / missing a minute | 218 to 245 / 126 to 135 | 11 to 24 / 45 to 59 |
| arrivals' wander over the quickest, p95 (p99) | 27 to 37 ms (60 to 91) | 12 to 17 ms (13 to 20) |
| a playing client's playout depth | 8 to 9 ticks | 3 to 4 ticks |
| frames everyone else stood still | 0.1 to 8.8% | 0.0 to 0.7% |
| snapshot packet median, over the MTU | 1.8 KB, 97% (reliable) | 0.8 to 1.0 KB, 0% (parts) |
| down a client | 51 to 53 KB/s | 28 to 31 KB/s |

Lobby 2 (2v2): wander p95 15 to 18 -> 12 to 13 ms, depth 4 to 5 -> 3, down
25 -> 17 KB/s. `net_lag -- lags=120 seconds=40` (`oldserver` for before; 120
ms, 24 jitter, 2% loss, a 5v5 in one process): everyone else stood still in
17.6% of frames -> 0.1%; down 66 -> 34 KB/s a client; snapshot packets 2.3
-> 1.1 KB median; the server's snapshot work 1.79 -> 1.31 ms a tick, 20.5 ->
16.8% of a core.

On a clean link (127.0.0.1, no loss; three pairs of 45 s runs) old and new
time their snapshots alike: gaps p99 37 to 40 ms, wander p95 4.5 to 8 ms
either way. The new loop's part shows in a stall: it is caught up with one
snapshot a room and the server keeps its time (net_pace's check), which a
clean minute rarely has.

**The snapshot rate** stays 30 a second. `net_lag -- lags=50 seconds=30`, twice
each: at 30 a second 34 KB/s down a client and 18 to 19% of a core on this
PC (the snapshots 1.25 to 1.40 ms a tick), everyone else still in 1.3% of
frames; at 60 a second (`snaps=1`) 63 KB/s, 28 to 29% (2.9 to 3.0 ms), 0%,
and the others shown a tick (17 ms) sooner. With two lobbies on one slow
core that is too much; the config's `"snap_every": 1` turns it on (a server
of one lobby could afford it). The clients take either rate as it comes.

**One lobby or two.** Two, at 30 snapshots a second. The jitter was the
packets and the loop, not the core: with both lobbies in a match lobby 1's
snapshots came no worse than with it alone (the same runs with lobby 2
empty: wander p95 17 ms, depth 4 ticks, against 12 to 16 and 3 to 4), and
the two matches together took about 3.3 ms of each 16.7 ms tick on the
shared core (the 5v5 2.1 ms, p99 4.5; the 2v2 1.1). The VPS's core is
slower (its 3.6.0 log: a 5v5 with four people 4.9 ms a tick), so two busy
matches there are still well under half of it, and its log shows two
matches at once only rarely. One lobby is a config change: take it out of
`server/lobbies.json`; the game's COUNTY SERVERS hides a listed lobby its
server does not run (the INFO answer names the server's ports,
`NetBrowser._drop_unserved`), so `servers.json` may keep both. One lobby
with `"snap_every": 1` is the choice if the last tick of delay matters more
than a second lobby.

`tools/net_pace.gd` measures it again: `-- server=127.0.0.1:47197 watch=1
people=3 start_when=4 [lag= jitter= loss=]` against a server run with
`--lobby-server=<config>` (a config with `"status_every"`, `"old"` and
`"test_link": {"lag_ms", "jitter_ms", "loss"}` for the server's own side);
pin it to one core (`Start-Process ... -PassThru`, `.ProcessorAffinity`)
beside a busy process to stand for the VPS. Without `server` it is the check
(check_all, run alone): on a made-up clock a stall's ticks are caught up
with one snapshot a room and a 2 s stall is let go; then two lobbies, each a
match of bots with 1.5 ms of extra work a tick, on the real clock: no
snapshot bunched, the gaps' p99 under 45 ms at the server and 50 at a probe,
the arrivals' wander p95 under 20 ms and no snapshot packet over the MTU.

**The second round** (after NETFEEL's `net_feel.gd` found three more on
the host's side; `r1` there and net_lag's `oldserver` turn these off):

- **Rows by ticks, not snapshots.** A snapshot repeats `Host.ECHO_TICKS` (9)
  ticks of rows past the last sent, whatever the snapshot rate
  (`echo_by_ticks`); at 60 a second the old three snapshots' worth was
  three ticks.
- **Co-op and County Run lost rows** because their deltas (a world of
  hands, 8 to 14 KB) went in 7 to 12 parts: with 2% loss one in six or so
  never came whole, the client's base fell behind until it left the host's
  history, and the whole snapshot it then got carried **no rows at all**, so
  the copy was put back on it. A whole snapshot now carries the rows since
  the last it was sent (`rows_in_wholes`), and a split snapshot's first part
  alone gives its rows (they come before the payload: `rows_from_parts`), so
  a lost later part loses the state, not the inputs. 5v5 and deathmatch
  deltas are one or two parts, which is why only those two modes showed it.
- **An input buffer on the host** (`buffer_inputs`): a person's inputs are
  played 0 to `BUFFER_MOST` (2) ticks behind their arrival, by how much
  their arrivals wander (`Remote.arrivals`, their spread over the quickest
  less a tick), and after running dry it fills again before they play on.
  It used to play each as soon as it came: a late one was held (the person
  stopped turning), then the pile merged (a lurch). The rewind follows (the
  tick they showed against the tick it is played).

`net_feel.gd -- scenes=coop,county lags=250` (50 ms of jitter, 2% loss),
seeds 7, 11 and 23, `r1` against new: copies put back in 20 s 4, 7, 6 ->
2, 2, 2 in co-op and 7, 9, 10 -> 1, 3, 2 in County Run; everyone else
frozen 12.9, 13.1, 13.6 -> 13.0, 11.3, 9.8% in co-op and 11.1, 7.5, 7.9 ->
7.6, 8.4, 6.5% in County Run (single-player's own bar at 144 Hz is 17%).
The input buffer alone (`nobuffer` against new) is within the noise there
(20% jitter: the buffer is a tick and the host held as many inputs either
way) and costs 10 to 25 ms on the input's round trip; at 100 ms of jitter
(`net_lag -- lags=250 jitter=0.4`, `nobuffer` against new) the host held a
person's late input 12.9 -> 2.4 times a second and merged a pile 12.0 ->
1.4 times, for 33 ms more on the round trip (650 -> 683 ms).

At 60 snapshots a second (`snaps=1`, 250 ms) the rows by ticks took the
copies put back from 43 to 1 in 20 s (5v5 and co-op), but the others
still showed frozen in 86% of frames with or without them (the same
number in both: the client's drawing at that rate, not the rows), so 60
a second is not worth it yet; 30 stays.
### Soaking every mode (pass 12)

`tools/net_soak_all.gd` soaks every online mode in one process on its own
clock: a lobby server of this build on 127.0.0.1 with latency, jitter and
loss on every session (`lags=`, `jitter=` a share of it, `loss=`), two to
four players (`people=`) each steered by a bot from its own copy and drawn
as main.gd draws it (led by the prediction, own shots shown), the last of
them over the lobby's WebSocket side. CAMPAIGN CO-OP is hosted by the real
front end through the party line (the host's player one a bot too, one
partner straight in, the last through the line over WebSocket). A match
that ends starts again.

- **Destruction on purpose** (`wreck`, `every`): a director on every game
  alike, the server's and each copy (`Wrecker`, hooked to `ticked`, acting on
  the game's clock and carried state only), sets off a chain of blasts
  nobody threw every 4 s of game clock: through the breakables, at the
  barns, the water tower and the fuel line until they come down, at the
  vehicles, the fences and windows, among the hands. It is play, so every
  copy must keep with the server through it.
- **Late join** (`late`): half way the last player leaves and joins again
  into what is broken; its copy must keep for 10 s, and its wreckage must
  show every fallen set piece in its pieces.
- **Put backs** (`putback=S`): every S seconds each copy is put back on the
  newest snapshot, as a lost input row does, and must keep after it. This is
  what found most of what follows: play a snapshot does not carry shows up
  as a parting soon after a put back.
- It fails on a parting (beyond the two put backs a leave and a join make in
  the party modes, below), a drop, a script or engine error, a late joiner
  wrong, a save of the broken co-op chapter that reads back otherwise, and
  (runs of 3 minutes or more) objects or any game's list growing over the
  second half past `grow`. It prints, per run: partings and where, put
  backs, round trips, bandwidth down a player (the 95th percentile of a
  second while things break and while not), the client's frame (its copy
  played out, snapshots taken, the frame drawn led) median / p99 / worst,
  quiet, breaking, at a check and at a put back, its parts, the server's
  whole snapshots and delta sizes, memory and objects. `why=1` says why each
  whole snapshot went and what a delta carries after each blast. `quick`
  (check_all): County Run co-op and campaign co-op for 30 s at 120 ms, put
  back every 5 s.

What it found and fixed:

- **Whole snapshots every second or two in County Run and co-op.**
  `GameSnapshot.merge` takes null for "can't merge" (an "@order"), and a
  value gone to null in the newer delta (an enemy's `aim_mark` let go) came
  back as that null: the host sent every client a whole snapshot (12 to
  27 KB) with no input rows, and every copy was put back on it (12 to 50 ms
  each). County Run at 120 ms: 76 whole snapshots in 42 s and 35 copies put
  back "for lost inputs", 1 and 0 after; 296 KB/s down a player before, 152
  after with the two below.
- **Play kept in an enemy's metas** (the bosses' move plans, the bayou
  gators' homes and runs, the arena fire's next bite on each hand) was never
  carried: a copy put back in a boss fight, or a late joiner's, parted at
  every check after (each check put it back, which never brought the metas
  back). Now `Enemy.notes` (`get_note`, `set_note`...), carried; net_check
  fails on a `set_meta` in play code.
- **A flood washing a body** set the flood's `hit` without moving
  `set_pieces.net_version`, so snapshots never sent it: a copy put back
  parted at every check while the flood ran.
- **A late joiner saw a fallen barn land again** whole, dust and rumble and
  all: a snapshot's set pieces now sync the wreckage's ruin
  ([gameplay.md](gameplay.md#coming-apart-destruction-pass-11)).
- **What a delta carried while things broke**: the breakables' flying bits
  (play never reads them) twice over, in the feature and in its facts, and
  the fuses burning down in the facts: 5 to 40 KB raw a delta (1.6 to 7.5 KB
  packed) in a 5v5 while barrels went up, 1.2 to 1.3 KB now; the bits are
  looks now and the facts are `net_facts()`. A player's flow field travels
  as runs (County Run: 6 KB packed a field, under 2). 5v5 down a player
  while things broke (p95 of a second) 293 KB/s -> 79, deathmatch 383 ->
  106, County Run 222, campaign co-op 602 -> 265.
- **An engine error** when a packet for a WebSocket player that had just
  gone left the lag queue (`NetSession._ws_open`).
- **Past about a second of round trip** a client's acknowledged base fell
  out of the host's `KEEP` (32 snapshots, 1.07 s at 30 a second) and it got
  whole snapshots (7 to 30 KB, no input rows, a put back each) until the
  trip came down. With NETSERVER's `NetSession.resend_lost` (a lost packet
  holds a WebSocket up a round trip, as TCP does) the browser's player at
  250 ms was put back 76 to 83 times in 90 s in every 5v5 mode, the party
  line's at 120 ms 22 times in 30 s. `Host.KEEP` and `Client.KEEP` are 120
  (4 s); none since (net_check holds them together).
- **A copy's snapshots leaked**: `Client` let go only of the one exactly
  `KEEP` older than the newest, so one that came after a lost one stayed for
  ever (about one in fifty at 2% loss, each holding its game's whole
  snapshot): 260 kept after a minute; `KEEP` at most now.
- County Run's card picks: [county_run.md](county_run.md#copies-that-parted-after-a-card-pick-online-fixed).

Measured after all of it on the integrated transport (NETSERVER's), this PC
loaded by other work (the client's milliseconds are a guide only; headless:
the copy's ticks, its snapshots and its drawing led, no 3D), a minute each
of two players with the director on, 2% loss, jitter a fifth of the
latency (campaign co-op's round trip is through the party line, so about
twice the others'):

| 120 ms | partings (inputs lost) | trip p50/p95 | down KB/s (p95 quiet/breaking) | client frame quiet p50/p99 | breaking p50/p99/worst | checking (once a second) p50/worst |
| --- | --- | --- | --- | --- | --- | --- |
| County Run co-op | 0 (0) | 333/600 | 204 (107/227) | 6.7/22.6 | 9.9/35/129 | 23/55 |
| search and destroy | 0 (0) | 317/517 | 42 (12/55) | 2.6/5.9 | 2.9/8.4/18 | 6.9/15 |
| hostage | 0 (0) | 317/517 | 42 (12/53) | 2.5/6.2 | 3.0/8.0/15 | 6.8/14 |
| tag team | 0 (1) | 317/450 | 25 (10/29) | 2.0/3.5 | 2.4/4.5/8.9 | 5.0/7.4 |
| deathmatch | 2, the late join's (0) | 333/550 | 69 (41/113) | 5.1/15 | 8.0/25/159 | 14/65 |
| team deathmatch | 2, the late join's (0) | 333/550 | 64 (39/103) | 4.9/16 | 7.5/23/125 | 14/31 |
| campaign co-op | 0 (3) | 750/933 | 203 (45/261) | 8.5/44 | 11/51/116 | 40/87 |

At 250 ms (1.2 min each): search and destroy 0 partings (1 input lost),
deathmatch 2 (the put back after a lost row, below), County Run 0 (2),
campaign co-op 0 (6, its trip through the line 1.7 s). Four players at
120 ms: search and destroy 0 (0), County Run 0 (6), campaign co-op 4 (the
late join's, 6 allowed). The host's own frame in campaign co-op (its game
with the same scene, as one player's machine) 12.5 ms median, 41 p99, where
a partner's frame is 8.5 / 44 and a check of the copy 40 ms (NETFEEL's).

Round 2 (after NETFEEL's and NETSERVER's second rounds were merged):

- **The copies' "growth" over a long County Run was the soak's own.** Twelve
  minutes had taken the process from 460 MB and 13,500 objects to 1,280 MB
  and 77,500. Split by where it happened, it was the copies' ticks, and a
  County Run game made as the front end makes one grew 600 objects a
  minute with no network, one with `QuietSound` none, one with the sound's
  effects muted none: the sound's finished playbacks. The engine lets them
  go at a frame's end, and the soak (like every tool that runs one long
  loop) never let a frame run. A game that awaits a frame every few ticks
  stays flat (7,000 to 7,200 objects over two minutes); the soak now does
  (`await process_frame` every 4 ticks, no frame cap or sleep), and five
  minutes of County Run go 455 -> 497 MB, 11,800 -> 16,500 objects with the
  horde growing 21 -> 58. `quick` plays County Run two minutes and fails if
  the second minute's objects grow past 25% or memory past 40 MB a minute
  (before: +40% and +100 MB). A real client runs a frame each frame: it
  never had this. `NetSync.Client.lag_samples` grew without end (one float a
  confirmed input): the newest 8,192 now.
- **The place rows travel with the inputs** (`NetSync.Host._places_for`,
  `NetWire._put_places`): each tick's `game.place_log` row once, after the
  echoed rows in their packed block, each row's float bits xored with the
  one before. A copy put back on a snapshot ahead of it takes the ticks it
  skipped from them (`Client._put_places`), so a shot rewound into them
  plays as the host's did: a deathmatch put back every 4 s parted twice in
  90 s before, never after (44 put backs). Cost, down a player: search and
  destroy 39 -> 43 KB/s, County Run 167 -> 174 (`places=0` sends none). A
  reader that does not know them stops at the rows' end, so PROTOCOL stays
  5.
- **Rubble shut into the paths after a mid-fall put back**: a snapshot's
  facts of the set pieces now list the rubble still waiting
  (`net_facts()`, `to_shut`, carried); a copy put back on one shuts what the
  host has shut and waits with the rest (set_piece_check: a snapshot put on
  mid-fall plays on the same; it parted three ticks on before).

Known and left (each puts a copy back once or twice more, never for long):

- **A leave and a join in the party modes** (`Modes.went_away`,
  `join_late`) change the server's game between ticks: every other copy is
  put back once for each (a hitch of 10 to 130 ms on a busy co-op map).

### Player maps in a lobby

`src/net/net_maps.gd` (`NetMaps`); the maps themselves are
[levels.md](levels.md#player-maps).

- CUSTOM MAPS' HOST ONLINE opens the host form with the map in
  `NetMaps.pending`; when the lobby opens (`main_flow.gd net_open_lobby`)
  `host_map` puts it on: `settings["map"]` the map's versus level id,
  `settings["custom_map"]` its hash, name and author, MODE fitted to one the
  map can host (`fit_mode`, first in `_mode_fits_map`; `MODE_NEEDS` maps
  the lobby's modes to `UserMap.modes`): a MODE the map cannot host is
  stepped past the way the host stepped, and the host's lobby says why
  (`PUCKETT'S BACK FORTY CAN'T HOST SEARCH AND DESTROY: NEEDS AN ATTACK
  START.`); TAG TEAM 2V2 keeps to its own maps. MAP is the map's versus copy
  (no hands, lever or truck, doors open) for every mode but CAMPAIGN CO-OP,
  which plays the map itself.
- **DEATHMATCH, TEAM DEATHMATCH** on a player map: the versus copy, spawn
  points from the whole map (`Modes.spawn_points`), pickups coming back;
  someone dropping in gets the map before their START; the results go back
  to the lobby as on any map.
- **CAMPAIGN CO-OP** on a player map is one map: not held to the chapters
  the host has reached (`main_flow.gd` `may_start`), everyone starts with
  PLAY ALONE's kit (`NetCoop.chapter_kit`), downs and revives are co-op's,
  everyone down and R starts the map over for the party, F5 writes no PARTY
  SAVE (`NetCoop.save` says so), and the host's ENTER on the win takes
  everyone back to the lobby (`NetCoop.next`): never the Crossroads or a
  chapter, nothing opened on the host's profile.
- **MAP** (`NetWire.MAP`, 20), host to client, reliable: `{"hash", "data"}`,
  the map's canonical text as it is (a few KB at most, not packed: unpacking
  a stranger's bytes is one more way in). The host sends it to everyone when
  it picks a map and to each joiner straight after WELCOME (`_hello`), so on
  the reliable channel it always comes before a START, a late joiner's too.
- A client takes it only if it fits (`unpack`): at most `limits.bytes`, the
  hash the one said, a map `UserMap.check` passes, already canonical. Then it
  is registered (`LevelData.preview`) and kept under `user://maps/shared`;
  otherwise the client leaves with `THE HOST'S MAP WAS NO GOOD: <why>`.
  `net_match_game` makes no game of a player map that never came (THE MAP
  WOULD NOT LOAD), so nobody plays a different map.
- The lobby shows the map's name on MAP (`LobbyScreens.value_name`); the
  host's < > on MAP steps to the game's own maps (back to a player map is
  CUSTOM MAPS' HOST ONLINE again).
- Nothing in the party line changes: a MAP packet's first byte is under
  `RELAY_FIRST` and it is far under the line's 256 KB cap (the largest map's
  is about 5 KB).
- Always-open lobbies take no player maps (an admin's MAP is checked
  against lobby.cfg's row by `allowed_value`). Not done: a shared list of
  maps on the lobby server.
- `tools/user_map_check.gd` holds it (ENet in one process).

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
  `net_join` like the JOIN form. The party line's listed rooms (no password)
  follow the servers, asked with a LIST knock as often; the list shows three
  rows at a time and scrolls with the cursor.

### Still open

(The start of this note was lost in an earlier edit of CLAUDE.md.) ... breaks
or the posse; per-player stats (chapter stats and the tally are the local
player's; the kill feed is the modes', `features/kill_feed.gd`); the steam scald list is keyed by hazard instance id
(not carried). Respawn, bodies blocking, area attacks on every player and the
group's boss fight are the modes' ([modes.md](modes.md)).
