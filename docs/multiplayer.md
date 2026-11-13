# Multiplayer: platforms, model and what is still to do

The game has the pieces a network game is built from, and tests that hold
them. The 5v5 modes play online with a lobby (docs/online.md); co-op and
deathmatch do not yet.
CLAUDE.md ("Multiplayer foundation", "Multiplayer tests and transport") lists
the code. This note is the plan around it.

## The model: one authoritative host

One machine runs the real game (`Game`, ticking at 60 Hz) and is the only one
whose dice count. Every other machine is a client:

1. **Client to host, every tick:** that tick's controls (12 bytes:
   `NetWire.pack_controls`), numbered. Each packet carries every input the
   host has not confirmed yet (up to `NetWire.REDUNDANT` = 12, 200 ms), so a
   lost packet costs nothing; the packet also says which snapshot the client
   has (the ack). Unreliable channel.
2. **Host, every tick:** plays its own players' controls and each client's
   next input. A late input: the last one again without its one-shot actions
   (USE, a gun, an item, a cycle). Inputs piling up after a stall: the host
   catches up, keeping any USE press it skips over.
3. **Host to client, 20 Hz** (every 3 ticks; 30 Hz is `snap_every` 2): a
   `GameSnapshot` delta from the newest snapshot that client acknowledged
   (32 kept, 1.6 s), or the whole snapshot (at most every half second) while
   it has none. The packet also carries the inputs every player played since
   that base, so the client can step its own copy in between, and the last
   input of the client's the host used (the client's measure of its lag).
   Small packets unreliable, big ones reliable (ENet would split a big
   unreliable packet and lose all of it with any piece).
4. **Client:** rebuilds each snapshot from its base and keeps a copy of the
   game stepped with the inputs the host played, starting again from a
   snapshot when inputs were lost past the redundancy. Today a snapshot can
   only be put onto a game just made (`GameSnapshot.apply`), so the copy is
   rebuilt as a fresh game every 10 s (and whenever it falls out of step);
   once apply works on a running game, `NetSync.APPLY_RUNNING` puts every
   snapshot onto the copy instead.

What the player sees comes from the copy: the local player's view, sound and
HUD. Presentation never travels (blood specks, smoke, the face, the walked
map): each machine makes its own with its own dice.

### Rates and sizes (measured by `tools/net_loopback.gd`)

| | |
| --- | --- |
Hickston, two players (the host's bot and the client's), 180 s of play, 50 ms
latency each way plus up to 15 ms jitter, 5% of unreliable packets lost:

| | |
| --- | --- |
| Tick | 60 Hz on the host; the client sends one input a tick |
| Snapshots | 20 Hz (30 Hz possible); whole 30.6 KB; a delta 3.7 KB median, 8.6 KB p95, 14.1 KB at most (zstd) |
| Up (client to host) | 8.9 KB/s of inputs (152-byte packets at 60 Hz with the redundancy), 11.5 KB/s with headers |
| Down (host to one client) | 95 KB/s (96 with headers) |
| Input to confirmation | 200 ms median (100 ms of latency, the snapshot interval, the host's input buffer) |
| Match | all 3,596 snapshots the client rebuilt were the host's bit for bit; the client's copy matched at all 180 checks (18 rebuilds from a snapshot) |
| Host cost | capture 34 ms and delta + compression 29 ms a snapshot, headless (this is why the test runs at half real time) |

The snapshot is far too big and too slow to take for a real game at 20 Hz:
the headless host work makes deltas fast and small (only what changed; the
save part, which carries everything again, out of the per-tick path).
Targets for a playable game: a delta under 1.2 KB (one packet) most of the
time, under 2 ms to take, 20 to 30 KB/s down per client.

## Transports by platform

All go through Godot's `MultiplayerPeer`, packets only (no RPCs, no scene
replication): `NetSession` hides which one.

| Platform | Transport | Notes |
| --- | --- | --- |
| Windows, Linux, macOS | ENet (UDP) | Channels: reliable (hello, welcome, big snapshots), inputs (unreliable), small snapshots (unreliable). A host listening on all addresses may meet the system firewall's prompt the first time. |
| Android | ENet (UDP) | The same build; needs the INTERNET permission in the export preset (not set yet). A phone on mobile data is behind carrier NAT: it can join, not host, without a relay. |
| Browser (full build) | WebSocket (TCP) now; WebRTC later | A browser cannot open a UDP socket or listen. WebSocket works today against a host on a desktop or a server (`websocket` in the loopback test), but TCP holds everything up behind a lost packet. WebRTC data channels (unreliable, unordered) are the real browser transport: `WebRTCMultiplayerPeer`, same API, but they need a signalling server to meet and STUN/TURN for NAT. |
| Browser (lite build) | WebSocket | The lite build has no threads (`variant/thread_support=false`): one core for the game, the view and the network. It can be a client; it should never host. |

A browser page served over HTTPS may only open `wss://` (TLS) WebSockets, so a
host for browser players needs a certificate (a dedicated server does; a
player's desktop does not have one): another reason for a relay or server.

## Tests

```
# N bots in one game (each its own bot_pilot through its own controls), every
# chapter for a while or to the end; per player kills, damage, deaths, stuck
# time, the enemies' targets, tick cost; a twin run seen from another
# player's machine must stay identical (presentation never changes play)
godot --headless --path godot --script res://tools/multi_bots.gd -- players=4 seconds=60
godot --headless --path godot --script res://tools/multi_bots.gd -- players=1,2,4 whole
godot --headless --path godot --script res://tools/multi_bots.gd -- players=2 mortal diff=3

# A host and a client over localhost ENet (or `websocket`), with latency,
# jitter and loss; every snapshot rebuilt bit for bit, the client's copy
# checked against them; bandwidth and sizes
godot --headless --path godot --script res://tools/net_loopback.gd -- seconds=180 lag=50 jitter=15 loss=0.05

# The foundation: players, snapshots, determinism
godot --headless --path godot --script res://tools/net_check.gd
```

Their quick parts run in `tools/check_fixes.gd`.

The loopback test is one process with two network peers and two games, on
the game's own clock (it runs as fast as it can; the latency and loss are
added on that clock). Two processes on two machines, in real time, is the
next step for it.

## What a later networking pass still needs

Done for the 5v5 modes (docs/online.md): a lobby with host settings, joining
by code or address with a password, late joining, a bot taking a leaver's
slot, UPnP, shots judged where the shooter saw them, the aim drawn at once.

- **Lobby and joining (co-op, deathmatch):** a menu to host or join (address, or a code from a
  lobby service), a ready screen, the level chosen by the host, players
  joining mid-chapter (a whole snapshot, then deltas: the protocol already
  does this), leaving and timing out (the host keeps the slot; the co-op
  rules decide what happens to the body).
- **NAT and relay:** most players are behind NAT. Options: a relay server
  that forwards packets (simplest, always works, costs a server), UDP hole
  punching through a meeting server for ENet, or WebRTC with STUN and a TURN
  fallback (which is a relay). A dedicated server build (headless, the
  host work) avoids the problem for anyone who runs one.
- **Interpolation and prediction:** today the client's copy is the host's
  game some 100 to 200 ms ago. The local player should be predicted: play
  their own inputs on the copy at once, and when a snapshot arrives, put it
  on and play the inputs the host has not used yet again (the copy and the
  inputs are both there already). Everyone else is drawn between the last
  two snapshots (interpolation, 50 to 100 ms behind), enemies included.
  Hitscan shots need lag compensation on the host (rewind the enemies to
  where the shooter saw them) or players will miss what they hit.
- **Bandwidth:** deltas of only what changed, quantized positions and
  angles, enemies out of a player's reach sent less often (interest
  management), and the save part never per tick.
- **Cheating:** the host is authoritative, so a client can only send
  controls; the host must clamp them (turn and look rates, one USE a tick,
  a gun the player owns) and never take a position, a hit or a pickup from a
  client. A player hosting can cheat freely: ranked or public play wants a
  dedicated server. Snapshots tell a client where every enemy is (a wall
  hack); interest management helps.
- **Security:** a host must survive malformed packets (`NetWire.read_*`
  return {} on a short packet; a snapshot from the host is trusted, inputs
  from a client never are), limit packet rates and sizes per peer, and never
  `bytes_to_var` objects from the network (it does not: objects are off by
  default).
- **Per-machine presentation in the snapshot:** the save part carries a few
  presentation fields (the face's and messages' timers, the local player's
  walked map); `NetSync.comparable` leaves them out of a comparison, and the
  host work should leave them out of the snapshot.
- **Versions:** HELLO carries the protocol and the game version; a client of
  another version is turned away (protocol only today).

## Crash and error logging

`src/crash_log.gd` writes every error and warning of a real launch to
`user://logs/session.log` with what was going on (version, screen, level,
tick, mode, players, last controls, the script backtrace in a debug build),
a summary at a clean exit, and keeps a session that did not end cleanly as
`crash-<stamp>.log` (noted on the console at the next launch). A network
session should add its own lines (`CrashLog.note`: joined, left, a rebuild,
a desync) so a player's report carries them.
