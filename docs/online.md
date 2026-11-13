# Playing 5v5 online

The 5V5 SHOWDOWN can be played with friends on other networks: one person
hosts a lobby, the others join it, and the empty places fill with bots.
Everyone needs the same version of the game.

## Hosting

1. Title, **5V5 SHOWDOWN**, **ONLINE: HOST A LOBBY**.
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

## Joining

1. Title, **5V5 SHOWDOWN**, **ONLINE: JOIN A LOBBY**.
2. Your name, then the host's **join code** or **address**: `203.0.113.7`,
   `203.0.113.7:47197`, a VPN address like `100.101.102.103`, or a name.
   CTRL+V pastes. Then the password if the lobby has one.
3. **JOIN**. In the lobby, LEFT/RIGHT picks your team (ANY lets the host
   balance), ENTER says READY.
4. In the match the top right shows your ping. ESC (then ENTER) leaves; a bot
   takes your place for the rest of the match.

With LATE JOIN on, someone who joins during a match takes over a bot on the
team with fewer people, straight away.

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
