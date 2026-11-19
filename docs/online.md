# Playing online

The 5v5 and 2v2 modes, COUNTY RUN co-op, the CAMPAIGN in co-op, DEATHMATCH
and TEAM DEATHMATCH can be played with friends on other networks: one person
hosts a lobby, the others join it (in the 5v5 modes the empty places fill
with bots). Everyone needs the same version of the game.

Nobody has to touch their router. A hosted lobby rings **THE PARTY LINE**, a
relay on the game's own server: the host gets a short code like `HKP-427`,
friends type it in, and their game reaches the host's through the server.
It works behind CGNAT, on a phone and in the browser. When the host's own
port does answer (the router opened it), a desktop friend goes straight to
the host instead, which is a little quicker.

## Hosting

1. Title, **MULTIPLAYER**, **HOST A GAME**.
2. Fill in your name, the lobby's name and a password (leave it empty for an
   open lobby). The port is 47197 unless you change it. Leave **ASK THE
   ROUTER** on.
3. **OPEN THE LOBBY**. The lines under the lobby's name say how friends get
   in:
   - `PARTY LINE CODE HKP-427   C COPIES`: press **C** (or tap the line) to
     copy the code and send it to your friends. That is all they need.
   - The next line is your router: `ROUTER OPENED UDP 47197: FRIENDS COME
     STRAIGHT IN`, or `ROUTER WON'T OPEN UDP 47197: FRIENDS COME BY THE PARTY
     LINE` (fine either way).
   - `RINGING THE PARTY LINE...` for a moment, then the code. If it says
     `THE PARTY LINE AIN'T ANSWERING` the server is down or out of reach: the
     lobby still opens the old way (the join code from your router, your home
     addresses for the same house or a VPN; see "When the router won't open
     the port" below).
   - A lobby with **no password** is listed on everyone's COUNTY SERVERS list
     (PLAY ONLINE) too; one with a password is only reached by its code.
4. Set the match with the arrow keys: mode, map, rounds to win, team size
   (1v1 to 5v5), bots on or off, bot skill, friendly fire, round time, buy
   time, freeze time, starting cash; and the lobby: how many people it has
   room for, late joining, and whether players pick their own team or you
   balance them. Everyone sees the settings as you change them. Picking a
   2V2 map (Pump & Go, Pine Acres, Catfish Landing) switches to TAG TEAM 2V2:
   search and destroy two a side, first to 9, 1:30 rounds.
5. When everyone shows READY, go to **START!** and press ENTER. If START
   says why not (someone not ready, too many on one team for the team size,
   a team with nobody and bots off), fix that first.
6. After the match, ENTER on the results takes everyone back to the lobby for
   another. ESC (then ENTER) closes the lobby for everyone.

**KICK** in the lobby: pick the player with LEFT and RIGHT, ENTER twice.

The match settings include **RULES**: ANY GUNS, SHOTGUNS ONLY (at least
$2000 each round), PISTOL PARTY, SNIPER DUEL (at least $6000), ECO WAR
(nothing over $1500) and BIG MONEY ($16000 every round). The store, and the
bots, sell and buy only what the rules allow. MULTIPLAYER's PLAY VS BOTS has
the same RULES row.

## Joining

1. Title, **MULTIPLAYER**, **JOIN WITH A CODE**.
2. Your name, then the host's **party line code** (`HKP-427`; small letters
   and no dash work too). The old ways still work on the desktop: a **join
   code** (`ABCDE-12345`) or an **address** (`203.0.113.7`,
   `203.0.113.7:47197`, a VPN address like `100.101.102.103`, or a name).
   CTRL+V pastes. Then the password if the lobby has one.
3. **JOIN**. With a code it says `RINGING THE PARTY LINE...` (and for up to
   three seconds `TRYING THE HOST'S OWN LINE...` when the host's port may
   answer). The lobby's top line says how you got there: `ON THE PARTY LINE`
   or `STRAIGHT TO THE HOST`. A wrong code says `NOBODY'S ON THE PARTY LINE
   BY THAT CODE`. In the lobby, LEFT/RIGHT picks your team (ANY lets the host
   balance), ENTER says READY.
4. In the match the top right shows your ping (through the party line: your
   trip to the server and the host's, added). ESC (then ENTER) leaves; a bot
   takes your place for the rest of the match. If the host's game goes away
   the party line tells you `THE HOST HUNG UP`.

With LATE JOIN on, someone who joins during a match takes over a bot on the
team with fewer people, straight away (co-op and deathmatch: they pull up a
chair beside the party, or at a spawn point with the starting guns).

## Co-op through the campaign

MODE **CAMPAIGN CO-OP** in a lobby you host (two to four of you; not on the
always-open servers): MAP is the chapter to start (one the host has reached
in their own campaign; past Hickston everyone gets the guns a gate on the
crossroads gives) or **THE PARTY SAVE**.

- Everyone plays their own guns and pockets; keys and the PA lead are the
  party's. A partner down is stood up by someone holding USE beside them,
  or comes back beside a partner after 20 seconds; while you're down the
  view goes to a partner (SPACE for the next one).
- The host's ENTER on a won chapter's tally takes everyone on: to the
  COUNTY CROSSROADS, where any of you walks through a gate for the party
  (the chapter you left is picked up where you left it). With CLASSIC on
  it goes straight into the next chapter.
- Everyone down: the host's ENTER tries the boss fight again from the
  party's own checkpoint, everyone at the door together; R starts the
  chapter over.
- Only the host saves: F5 writes THE PARTY SAVE (never the host's own
  campaign or quicksave). Next time pick MAP THE PARTY SAVE; whoever is in
  the lobby takes its places in order.
- Someone who leaves lies out of play until someone joins and takes their
  place. The kill feed down the left says who went down and who hauled whom
  up.

## Deathmatch and team deathmatch

MODE **DEATHMATCH** or **TEAM DEATHMATCH** (two to four): MAP is the arena
(the rodeo grounds, the Hogs' field, Rudy's big top, the saw floor, the
crossroads, the range or a 5v5 or 2v2 map), FRAG LIMIT and TIME LIMIT end
it. In team deathmatch you pick RED or BLUE with TEAM. After the results
the host's ENTER takes everyone back to the lobby.

## Custom maps

A map made in the MAP SHED (title, **CUSTOM MAPS**) can be played online:

1. **CUSTOM MAPS**, pick the map, **HOST ONLINE** (CHECK in the shed says
   which modes the map can host and what it still needs for the rest).
2. The host form opens as for HOST A GAME; **OPEN THE LOBBY**. The lobby's
   MAP shows your map's name and MODE is one the map can host: SEARCH AND
   DESTROY and HOSTAGE RESCUE (5v5 marks), COUNTY RUN CO-OP (room enough),
   DEATHMATCH and TEAM DEATHMATCH, CAMPAIGN CO-OP (a start, the lever and the
   truck: one map, the win takes everyone back to the lobby, no party save).
   Stepping MODE onto one the map can't host steps past it and says why.
3. Everyone who joins gets a copy of the map on the way in, before anything
   can start (a few KB). Their game checks it: its hash must match what the
   host said, and it must be a map the shed would load. A map that does not
   check out sends the joiner back with `THE HOST'S MAP WAS NO GOOD` and why.
   A copy is kept in their own maps folder (`maps/shared`, the 32 newest),
   listed under CUSTOM MAPS as FROM A LOBBY.
4. MAP's < > goes back to the game's own maps; to put a custom map on again,
   HOST ONLINE it again.

The always-open county servers do not take custom maps (yet).

## County servers (no code needed)

Title, **MULTIPLAYER**, **PLAY ONLINE**: the always-open lobbies listed live
(mode, map, how many are in, in the lobby or a match on, ping), and below
them every player's own lobby on the party line that has no password
(`PARTY LINE HKP-427` on its second line; the list scrolls past three).
Type your name once at the top, pick one, press ENTER: you are in its lobby. R asks
again; a server that is down shows NOT ANSWERING, one on another version says
so. The list is `godot/data/tuning/servers.json` (name, address, port); the
game asks each server with an INFO knock on its own port (`NetWire.INFO`,
`NetPlay.summary`, `src/net/net_browser.gd`), so no other port needs opening.

## Always-open lobbies (a server)

A small Linux server can keep lobbies open all the time, so nobody hosts
and nobody's router needs a port opened. Join one like any lobby, by its
address and port (or join code) and its password if it has one.

- The first person in **runs the lobby** (ADMIN by their name): the same
  settings, START and kick a host has. Everyone else readies up as usual.
  When the admin leaves, the next person in line runs it.
- Bots fill the teams. When a match ends everyone is back in the lobby on
  their own after 12 seconds (the admin's ENTER on the results does it at
  once); when every person has left a match it ends.
- An empty lobby goes back to its own settings. The lobby's name and
  password are the server's: the admin cannot change them.
- Two lobbies (COUNTY LOBBY 1 on UDP 47197, 2 on 47198), each a match at a
  time; whoever runs one switches its MODE between SEARCH AND DESTROY,
  HOSTAGE RESCUE and TAG TEAM 2V2 (which moves it to a map and format that
  fit), and an empty lobby goes back to its own. `most_matches` (2) caps
  matches across the server; a START past that is told to wait. One 5v5 with
  four people and six bots measured about a fifth of a core on the owner's PC
  (`tools/net_lag.gd`); both lobbies in a match on one core of it with most
  of that core taken by something else, about a fifth of what was left
  (`tools/net_pace.gd`, pass 12). Before 3.2 the bots' route cache was
  shared by every game in the process and cleared itself whenever two took
  turns: 6 to 9 ms a tick for the bots then, about 1 now.
- Fewer lobbies is only `server/lobbies.json`: the game's list asks each
  server which lobbies it runs and leaves out the rest. `"snap_every": 1`
  there sends 60 snapshots a second instead of 30 (others shown a tick
  sooner, about half as much again of the server's work and twice the
  bandwidth; for a server of one lobby). The status line in the log has
  each lobby's tick cost and how evenly its snapshots go out (`snaps 33.3 ms
  apart (p99 ..., worst ..., N bunched)`: p99 near 33 and nothing bunched is
  right).
- Players need the same version as the server: update the server with each
  release.

**Running one** (`server/`): `lobbies.json` lists the lobbies (port plus any
of `NetPlay.DEFAULTS`: `lobby_name`, `password`, `mode`, `map`, `team_size`,
`rounds`, ...) and `most_matches`. `server/deploy.sh root@<address>` (Git Bash
on the owner's PC, with the server's SSH key in `~/.ssh/clmr_oracle`) exports
the "Linux Server" preset, copies it with the config and runs `setup.sh` on
the server: a `clmr` user, `/opt/clmr`, the `clmr-lobbies` systemd service
(restarts on a crash, starts at boot, its log in `journalctl -u
clmr-lobbies`), the firewall (SSH and UDP 47197-47198) and SSH by key only.
Run the same command to update it. Locally:

```
godot --headless --path godot -- --lobby-server=../server/lobbies.json
```

The server's address is kept out of this public repository.

## The party line on the server

The relay is part of the lobby server: `server/lobbies.json`'s `"relay"`
turns it on (rooms at once, players a room, bytes a second a room, minutes an
empty room stays open; `src/net/net_relay.gd`). It answers on the lobbies'
own ports (UDP 47197 and 47198, and the browser's wss on 443 and 8443), so it
needs no new port or firewall rule; it comes with the next `deploy.sh`.
`godot/data/tuning/servers.json` marks the servers the game calls for it
(`"relay": true`). The log has a line for each room opened and closed (how
long, how many joined, the bytes each way) and the status line counts rooms,
players and bytes a second. A 5v5 player through it costs about 3 KB/s up and
27 KB/s down; a full room of nine about 250 KB/s.

To time it against a server by hand:
`godot --headless --path godot --script res://tools/relay_check.gd -- ping=<address>:47197`
(it opens a room and joins it from the same PC, and prints the round trip
through the line against the trip to the server).

## The browser build online (wss)

A page on https may only open secure WebSockets, so each lobby in
`server/lobbies.json` with a `ws_port` also listens there with TLS, and
`godot/data/tuning/servers.json` gives the browser each lobby's `wss://`
address (the server's hostname: the certificate is for it, not the IP).
The ports are 443 and 8443 because IONOS's own firewall passes those and
not the 47xxx TCP ports.

Once on a new server (it accepts Let's Encrypt's terms, so it is a person's
call): `apt-get install certbot`, then
`certbot certonly --standalone -n --agree-tos --register-unsafely-without-email -d <hostname>`.
`server/setup.sh` (run by deploy.sh) opens 80, 443 and 8443, installs the
renewal hook that copies the certificate to `/etc/clmr/tls/` for the
`clmr` user and restarts the lobbies, and the service may bind 443
(`AmbientCapabilities=CAP_NET_BIND_SERVICE`). Without a certificate the
WebSocket side runs plain (fine for tests on 127.0.0.1, refused by a page
on https). `tools/net_server_check.gd` plays a whole match with one player
on the WebSocket side; `tools/county_net_check.gd` a County Run party.

The browser build hosts (HOST A GAME) and joins by a party line code through
the same wss: it cannot listen or open UDP itself, so everyone comes by the
party line (the lobby says `HOSTED IN A BROWSER`). It cannot use a 10-letter
join code or an address.

## When the router won't open the port

With the party line answering this is not needed. Without it (the server
down, or another server list), the host needs **UDP port 47197** reachable
from outside. Three ways:

1. **Forward the port by hand.** In your router's settings (usually
   `192.168.0.1` or `192.168.1.1` in a browser), find "port forwarding" and
   forward **UDP 47197** to the host PC's address (the lobby's third line
   shows it). Friends then join with your public address (search "what is my
   IP" on the host PC) or a join code made from it. Allow the game through
   Windows Firewall if it asks.
2. **A VPN everyone joins** (free for a few people): Tailscale or ZeroTier.
   Everyone installs it and joins the same network; the host's VPN address
   shows on the lobby's third line (Tailscale's start with 100.). Friends join
   with that address. No router settings needed, and it works behind CGNAT.
3. **Someone else hosts**: a friend whose router does UPnP.

The server also keeps the firing range's board (`range-board.json` in the
server's user folder, beside `county-board.json`): every game's top scores
by name, posted by players' games when they finish one online.

## What is checked and what is not

`tools/net_server_check.gd` (in check_all and CI) holds the always-open
lobby: the first player in runs it, a player who doesn't cannot change
anything, the admin cannot change the password, START waits on readiness
and on a busy server, a match with bots kept in step with the server, back
to the lobby on its own, the next admin when one leaves, a kick, an empty
lobby ending its match and getting its settings back, closing tells
everyone.

`tools/games_check.gd` knocks on a lobby server in the same process for the
firing range's board: a best comes back, a name's best counts, a score past
what a game allows and another version's are refused.

`tools/relay_check.gd` (in check_all and CI) holds the party line: a lobby
server with it on its ports, a full line turning a room away, a room over its
bytes a second keeping only what must arrive, an empty room closing; a hosted
5v5 with one player in over ENet (after trying the host's address that does
not answer) and one over the WebSocket, the server's own lobby busy on the
same port meanwhile, the room on the servers list, a match with every copy
kept with the host, a late joiner going straight to the host, a kick and the
closing heard through the line; a County Run party of three through it, and
the host's game going with no goodbye.

`tools/net_party_check.gd` (in check_all and CI) hosts from the real front end
through a lobby server's party line: a co-op Hickston for three (one straight
to the host, one over the WebSocket by the line), a partner down and hauled
up, the host down watching a partner, the sheriff's checkpoint and its retry,
the chapter won and the crossroads, the fair through a gate with everyone's
guns, a late joiner, a leaver, THE PARTY SAVE written and started again; a
deathmatch fought by bots on every copy with a late joiner and the results;
team deathmatch's picks. **Not checked:** a real two-PC co-op chapter played
by people (try it: see the pass 7 report).

`tools/net_showdown_check.gd` plays a whole online session in one process
over the network stack (a host and three clients on 127.0.0.1, with test lag
and packet loss): joining by code, a wrong password turned away, not ready,
the host's settings, teams, names, buys over the wire, rounds, a player
leaving (a bot takes over), a late joiner, back to the lobby, closing it. Two
real game windows on one PC were also run against each other (a host and a
client, each played by a bot). **Not checked:** play between two real homes
over the internet (through the party line on the VPS or straight), a real
router's UPnP answering (the test PC's router did not), CGNAT, phones, and
the browser build hosting or joining by a code in a real page.

`tools/user_map_check.gd` hosts a lobby on a custom map in one process and
has a client join: the map arrives, its hash checked, the match starts on
the same level on both machines, a new map picked in the lobby reaches the
client, and broken or hostile map packets are refused.

## How it works

`src/net/net_play.gd` is the lobby and the match around it; `net_sync.gd`
the match itself; `net_wire.gd` every packet; `net_session.gd` the ENet
connection; `net_upnp.gd` the router; `net_relay.gd` the party line on the
server and `relay_link.gd` a game's end of it; `lobby_screens.gd` the screens.

- **The host plays the one real game.** It runs at 60 ticks a second with
  its own player, the bots and every client's controls (buys, reloads, gun
  picks and USE travel in the controls), and sends each client 30 snapshots
  a second: the change since the newest snapshot that client has, plus every
  player's controls since then.
- **Each client keeps a copy.** It steps the copy with the controls the host
  played, a couple of ticks behind the newest snapshot so the world moves
  smoothly, and checks it against the snapshots once a second; a copy that
  parts from the host is put back on the newest snapshot. Everything a copy
  shows (shots, blood, sounds) comes from stepping it, so it looks and sounds
  like a local game.
- **The aim answers at once.** A client draws its own view turned by the
  mouse moves the host has not played yet (main.gd `_net_aim`). Walking still
  waits a round trip.
- **Shots land where they were aimed.** The host judges a client's shots
  against the others where that client's screen showed them (up to half a
  second back: `Controls.rewind`, `game.gd _rewound_hands`); the rewind goes
  out with the controls, so every copy agrees.
- **Nobody can pause** an online match (the round goes on) **or save** it.
- **Settings that change play** (difficulty, gore, aim assist, hit feedback)
  are the host's on every copy.
