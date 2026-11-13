# 5V5 Showdown

Five a side, round by round, with a buy menu and money. Pick **5V5 SHOWDOWN**
on the title screen, choose the mode, the map and the match length, and go.
You and four bots against five bots. The bots follow the game's DIFFICULTY.

From the command line (the project folder or the EXE):

```
--mode=bomb --arena=grainyard --rounds=7
--mode=hostage --arena=holler
```

## Online

Play it with friends on other networks: docs/online.md.

## The modes

**Search & Destroy.** The OUTLAWS carry the shine bomb (a crate of moonshine
and dynamite) to site A or B and plant it: stand on the site and hold USE for
2.6 seconds. It blows 35 seconds later and takes anyone near with it. The
DEPUTIES cut the fuse: hold USE beside it for 7 seconds, or 3.5 with wire
snips. Outlaws win when it blows or every deputy is down; deputies win when
the fuse is cut, when every outlaw is down before a plant, or when the clock
runs out with nothing planted. A dropped bomb is picked up by walking over it.

**Hostage Rescue.** Two hostages are held on the sites by the OUTLAWS. The
DEPUTIES come in from the far end, press USE beside a hostage to take them
(USE again sets them down) and run them to a rescue point: the box at their
own spawn, and on the Distillery and the Salvage yard two nearer points on the
lanes back from the sites (each shows RESCUE over it). One hostage out wins it for the deputies, as
does downing every outlaw; the outlaws win by downing every deputy or by
running out the clock.

## A round

1. **Freeze** (6 s): everyone stands at their spawn. Press **B** to shop.
2. **Live**: 1:45 for search and destroy, 1:55 for hostage rescue. You can
   still buy for 20 seconds near your spawn.
3. **After** (5 s): who took it and why, then the next round.

The county fair's barker calls the round over the PA: the start, the bomb
planted, the fuse cut, a hostage out, who took the round and the match, half
time, and when you are the last of your posse standing. The planted bomb beeps,
faster as its fuse runs down.

The status bar shows what matters in a round: health, ammo, your vest (and
+HAT with a hard hat), your side and its goal, the bomb or snips if you carry
them, and how many throwables you have. TAB held is the scoreboard, M the map
with the sites. At the end the results show both teams' kills and deaths,
the match's MVP and every round as it went. The outlaws look like the
county's hillbillies, the deputies like its yard deputies; the title's
CONTROLS screen has a 5V5 page with every key.

Nobody comes back inside a round. If you go down, the view follows a
teammate who's still up. If you survive, you keep your guns (topped up) and
your vest. If you don't, you start the next round with the crowbar and the
.38. Teams swap sides at half time and the money starts over. First to 7
rounds wins (or first to 4 for a short match); 6 to 6 is a draw.

## The store

Each side shops at its own counter. Both start every round with the crowbar
and their side's pistol: the outlaws a **.38 Special**, the deputies a
**County .45** automatic.

| Class | Outlaws | Deputies |
| --- | --- | --- |
| Pistol | Hogleg .44, an old brass-framed single-action: one to the head drops anyone, hard hat or not (700) | Star .357, a stainless magnum: quicker to fire and reload, two to a hard hat (700) |
| Shotgun | Sawed-off, two barrels (1100) | Riot Pump, six shells, pump-action (1300) |
| SMG | Grease Gun, stamped steel, 30 rounds (1200) | Squad Tommy, a 50-round drum (1500) |
| Sprayers | Mill Riveter (1350), Teat Gun (1050) | |
| Rifle | Ranch Rifle (2700), Alien Arm Gun (2500: slower, but its bolt does not fall off with distance) | the same |
| Sniper | Hog Hunter .30-06, bolt-action: one to the body drops anyone (4750) | County Marksman, semi-auto: two to the body, fast (5000) |
| Machine gun | Corn Mower, a 100-round belt (5200) | Patrol BAR, a 60-round box (5000) |
| Heavy | Bottle Rockets (4200) | the same |
| Gear | Tin Vest (650), Vest + Hard Hat (1000) | the same, and Wire Snips (400) in search and destroy |

The kit pistols differ too: the .38 takes three to the body and drops anyone
without a hard hat with one to the head; the .45 takes four but holds eight
and fires faster.

**Aim like you mean it.** Every gun is most accurate standing still, a bit
better crouched, worse walking, much worse running and worst in the air; the
four ticks round the crosshair show how far shots can stray right now. Rifles,
machine guns and sniper rifles suffer most on the move (a scoped rifle is for
standing still), SMGs and shotguns least. Damage falls off with distance for
pistols, SMGs, shotguns, rifles and machine guns (full out to a gun's own
range, then down to about half to three quarters at its reach); sniper rifles
hit as hard at any distance. `tools/gun_sheet.gd` prints every gun's numbers.

The store has two pages, **GUNS** and **GEAR + THROWN**: LEFT and RIGHT switch
between them. The number keys buy a row (1 to 9, 0, -, =, then the comma and
full stop keys, shown as < and >); UP, DOWN and ENTER work too.

## Throwables

Up to four at once, any mix. Press **4** to go round the ones you carry, then
fire to throw (look up to throw further).

| Throwable | Cost | What it does |
| --- | --- | --- |
| Dynamite (HE) | 300 | the grenade: hold fire to light it, let go to throw; it blows |
| Flash Jar | 200 (carry 2) | a mason jar of flash powder: whites out everyone who sees it, longer the nearer and the more square on (look away!) |
| Smudge Pot | 300 | a paint can of smoke: a thick cloud for 15 seconds that nobody sees through |
| Shine Cocktail | 400 | a lit bottle of moonshine: a patch of fire for 7 seconds that burns anyone in it (thrown into smoke it only fizzles) |
| Firecracker Can | 50 | a decoy: rattles off like your own gun for 10 seconds |

The bots use them too: attackers smoke off a site's defenders and flash in
before they push, defenders firebomb a push.

One long gun at a time: buying one swaps out the one you had. The crowbar and
your side's pistol are always yours.

In a round the number keys work like a round shooter's: **1** your long gun,
**2** your sidearm (again to swap to the other one), **3** the crowbar,
**4** dynamite.

Both snipers are wild from the hip. Right-click puts the scope up (the view
closes in, four times on the Hog Hunter and three and a half on the Marksman,
and the shot goes where the cross-hair is) and right-click again takes it
down. Reloading or switching guns takes it down too. The machine guns have
long reloads, so pick your moment.

## The money

- Everyone starts a half with **800**, and nobody can hold more than **16,000**.
- Winning a round pays the whole team **3,250**, or **3,500** when it was the
  bomb going up, the fuse being cut or a hostage getting out.
- Losing pays **1,400**, then 500 more for each loss in a row, up to **3,400**.
  A win takes one off that run.
- Outlaws who plant and still lose get **800** each on top.
- Planting pays the planter **300**, cutting the fuse **300**, taking a hostage
  **150** and getting one out **1,000**.
- A kill pays by the gun: crowbar **1,500**, shotguns **900**, SMGs and sprayers
  **600**, the Hog Hunter **100**, the rest **300**.

## The maps

**Puckett Grain Co-op**: attackers in the truck lot to the west, defenders
in the co-op lot to the east. North: the feed road and the belt house's two
narrow doors onto A, the dump pit (grain bins, a hay wagon, a tractor). Mid: the
rail yard with its boxcars and grain bin, a short way up to A, the scale office
through to B, and the long co-op row to the defenders. South: the feed tunnel
into B, the seed warehouse (pallets, shelves, a forklift).

**Holler Distillery**: attackers on the logging road to the south,
defenders on the fire road to the north. A creek runs the width of the map and
slows anyone wading it; the footbridge in the middle is the only dry way
across. West through the pines to A, the still house (copper, mash barrels, four
ways in). East past the hay barn and the hog pens to B, the bottling yard (jugs,
crates, the shine tank). The woodshed yard in the middle reaches both.

**Mundell's Salvage**: attackers in the tow lot to the east, defenders at
the scale shack to the west. Tight and full of corners. North along hubcap
alley and through the crane gap onto A, the crusher pit. Mid through wreck
canyon's zig-zag of junk walls. South past the dead school bus to B, the tire
barn.

## Tag Team 2v2

Search and destroy two a side on its own small maps, one bomb site each (the
title's 5V5 SHOWDOWN, MODE: TAG TEAM 2V2; online, pick a 2V2 map in the
lobby and the format follows; `--mode=tagteam [--arena=pineacres]` from the
command line). First to 9 of 16 rounds (sides swap after 8; a short match is
first to 5), 1:30 rounds, 15 seconds to buy, the same store, money, guns and
throwables as the 5v5. You and a bot partner against two, or a friend online.
The defenders reach the site four or five seconds before the attackers can.

**Pump & Go**: a highway gas station. Outlaws on the highway shoulder to the
west, deputies in the garage lot to the south-east. Long: truck parking along
the top fence and in through the fence gap onto the pumps. Short: in the
corner store's side door, through the aisles, out the loading dock and up the
service alley onto the pumps from below. The frontage road along the bottom
flanks round to the garage lot. The deputies come up the alley or through the
garage bay. The site: the pump island, a car at the pumps, the fuel tank.

**Pine Acres**: a trailer park. Outlaws at the park entrance to the south,
deputies in their lane to the north-east. Long: the back row, a dirt lane
behind the trailers, in at the carport's west end. Middle: the common green
round a trailer parked across it and through the board fence's gap. East: the
woodpile and through the double-wide to the deputies' lane (the flank). The
site: the carport yard (a pickup, the wash line, a washer, a grill).

**Catfish Landing**: a bait shop on the river. Outlaws in the gravel lot to
the north-west, deputies at the marina office to the east. Long: the bank
path down the west side and along the water onto the dock. Short: through the
bait shop and its tanks, out past the cleaning shed and down onto the dock.
Ice house row along the top flanks round to the office. The site: the dock
(an airboat, bait tanks, the net rack); the water off its end slows anyone
wading.
