# Playing 5v5 online

The 5v5 and 2v2 modes can be played with friends on other networks: one person
hosts a lobby, the others join it, and the empty places fill with bots.
Everyone needs the same version of the game.

## Hosting

1. Title, **MULTIPLAYER**, **HOST A GAME**.
2. Fill in your name, the lobby's name and a password (leave it empty for an
   open lobby). The port is 47197 unless you change it. Leave **ASK THE
   ROUTER** on.
3. **OPEN THE LOBBY**. The second line of the lobby says how friends get in:
   - `JOIN CODE ABCDE-12345 (203.0.113.7)  C COPIES`: the router opened
     the port. Press **C** to copy the code and send it to your friends.
   - `ROUTER WON'T OPEN UDP 47197`: your router said no to UPnP or has it
     off. See "When the router won't open the port" below.
   - `YOUR PROVIDER SHARES ONE ADDRESS (CGNAT)`: your internet provider puts
     many homes behind one address, so nobody outside can reach you. Use a VPN
     (below), or have a friend whose router works host.
   - The third line lists your addresses on your own network (and on a VPN):
     friends in the same house, or on the same VPN, join with those.
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
2. Your name, then the host's **join code** or **address**: `203.0.113.7`,
   `203.0.113.7:47197`, a VPN address like `100.101.102.103`, or a name.
   CTRL+V pastes. Then the password if the lobby has one.
3. **JOIN**. In the lobby, LEFT/RIGHT picks your team (ANY lets the host
   balance), ENTER says READY.
4. In the match the top right shows your ping. ESC (then ENTER) leaves; a bot
   takes your place for the rest of the match.

With LATE JOIN on, someone who joins during a match takes over a bot on the
team with fewer people, straight away.

## County servers (no code needed)

Title, **MULTIPLAYER**, **PLAY ONLINE**: the always-open lobbies listed live
(mode, map, how many are in, in the lobby or a match on, ping). Type your
name once at the top, pick one, press ENTER: you are in its lobby. R asks
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
  matches across the server; a START past that is told to wait. One 5v5 with nine bots is about 15-20% of a
  one-core VPS.
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

## When the router won't open the port

The host needs **UDP port 47197** reachable from outside. Three ways:

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

## What is checked and what is not

`tools/net_server_check.gd` (in check_all and CI) holds the always-open
lobby: the first player in runs it, a player who doesn't cannot change
anything, the admin cannot change the password, START waits on readiness
and on a busy server, a match with bots kept in step with the server, back
to the lobby on its own, the next admin when one leaves, a kick, an empty
lobby ending its match and getting its settings back, closing tells
everyone.

`tools/net_showdown_check.gd` plays a whole online session in one process
over the network stack (a host and three clients on 127.0.0.1, with test lag
and packet loss): joining by code, a wrong password turned away, not ready,
the host's settings, teams, names, buys over the wire, rounds, a player
leaving (a bot takes over), a late joiner, back to the lobby, closing it. Two
real game windows on one PC were also run against each other (a host and a
client, each played by a bot). **Not checked:** play between two real homes
over the internet, a real router's UPnP answering (the test PC's router did
not), CGNAT, phones and the browser build (the browser cannot host or join
yet: it would need WebRTC or a WebSocket relay).

## How it works

`src/net/net_play.gd` is the lobby and the match around it; `net_sync.gd`
the match itself; `net_wire.gd` every packet; `net_session.gd` the ENet
connection; `net_upnp.gd` the router; `lobby_screens.gd` the screens.

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
