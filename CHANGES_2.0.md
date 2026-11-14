# 2.0.0-dev.41 changes

## COUNTY RUN
- **COUNTY RUN**, a new solo endless survival mode on the title: pick a map, roam free while the county's hands keep coming, and see how long you last. Survival time is the score; death ends the run with your time, the map's personal best, highest level, kills and final build, then RETRY, MAPS or TITLE. Records are kept on their own, apart from campaign saves.
- **Three big maps**, each a campaign chapter's ground reworked for survival with every door open: **HICKSTON** (the town: Main Street's storefronts, alleys, backyards, the saloon and feed store; the creek, the stockyard, the rodeo and the trailer court now loop into each other; a footbridge over Main Street), **THE QUARRY** (haul roads, terraced pits and sheds; the weigh station opens into the lower cut, a new ramp comes down from the cut yard, and a steel catwalk crosses the flooded pit), **GATOR BAYOU** (plank causeways across the deep water and out to the lagoon island, two raised boardwalks over the shallows, shacks on stilts and open water to circle in). All three open from the start.
- **Three weapon slots**: start with the .38 and the crowbar; earn more from the roster as level-up rewards. 1-3 pick a slot, the wheel and the next-gun keys cycle; the HUD shows your slots, the gun in hand and its ammo. With all three full, a new gun asks which one to swap out and shows the upgrades you would lose; CANCEL goes back to the cards. Switching keeps a gun's ammo and upgrades; swapping drops only that gun's upgrades.
- **XP you collect**: kills drop spinning bottle caps (copper, silver, gold), more from tougher varmints, on ground you can reach. Walk close and they float in, never through a wall or from another floor. The HUD shows your level, XP and clock.
- **Level ups** stop the clock and the world and offer three cards: always an upgrade for the gun in hand, plus upgrades for your other guns, new weapons and perks. Each card says which gun, what changes and by how much, the tradeoff and how long it lasts. Two to three paths per gun: the shotgun's EXTRA BUCK, TIGHT CHOKE and SLAM LOAD; the .38's QUICK HANDS, DEADEYE and HEAVY HAND; the rifle's STEADY STOCK, FIELD MAGAZINE and CALLED SHOT; the crowbar's WIDE SWING, LONG REACH and CROWD CONTROL; the explosives' PACKED CHARGE, SHAPED CHARGE and BLAST PADDING; perks DEEP POCKETS, GOOD BOOTS, XP MAGNET, THICK HIDE, PATCH UP and SUPPLY GRAB. B shows your whole build.
- **Every tenth level is a milestone**: three major picks in their own colours: BUCKSHOT BREAKER, SIX-SHOOTER SHOWDOWN, CHAIN REACTION, LAST STAND, SECOND WIND, GRIT ARMOR, MUDSLIDE (a slide on USE) and BREAKAWAY. A big XP pickup that crosses several levels offers every choice in turn.
- **The pressure keeps building**: enemies spawn continuously out of sight and far enough off to react, more and tougher with the minutes, with elites now and then and a short lull to reload and grab XP.
- Works by keyboard, mouse and touch (Android and the browser): the map picker, the cards, the swap, the build screen and the end of a run.

# 2.0.0-dev.40 changes

## Online
- **COUNTY SERVERS**: two always-open lobbies on the county's own server, listed live in the game (mode, map, players, lobby or match, ping). Pick one and press ENTER: no host, no join code, no router setup.
- Nobody hosts an always-open lobby: the first one in runs it (mode, map, rules, start, kick), the next in line when they leave; bots fill the teams; after a match everyone is back in the lobby on their own; an empty lobby goes back to its own settings.
- Each lobby switches between SEARCH AND DESTROY, HOSTAGE RESCUE and TAG TEAM 2V2 (the map and team size follow).
- Online play is lighter on the host: snapshots now come from the game's change tracker (about a sixth of the work), so a full 5v5 takes 15-20% of a small server core.

## Rules and chatter
- **RULES** for 5v5 and 2v2 (online and against bots): ANY GUNS, SHOTGUNS ONLY, PISTOL PARTY, SNIPER DUEL, ECO WAR, BIG MONEY. The bots buy by them too.
- **CHATTER** setting (CUSSIN', CLEAN, OFF): the county's hands cuss you out in their own voices, the 5v5 bots crow over kills, plants and wins, and Mundell talks: every one of his wisecracks is voiced now, plus lines for boss fights, stations, keys, headshots and chapter starts. CLEAN puts a duck call or a horn over the cussing. A lobby can hold everyone to CLEAN or OFF.

## Menus
- MULTIPLAYER on the title: PLAY ONLINE, PLAY VS BOTS, HOST A GAME, JOIN WITH A CODE.
- Every multiplayer screen works by touch and mouse (Android and the browser included), with BACK buttons and the phone's keyboard for names and codes. A setting changes with one click; its < > step either way.
- The 5v5 store is one big panel (guns and gear side by side) you buy from with a click; the gun never fires while it is open. On a phone a BUY button opens it.
- Easier-to-read text on the menus.

## Levels and the engine
- The level engine has walkable upper floors (rooms over rooms, passages underneath), sloped ramps, stairs, thin and angled walls with openings cut to size, rails and low cover; shots, sight, grenades, bots and both renderers agree on them. Old saves load (save version 8).
- Remastered: Hickston's feed barn has a real hay loft; the fair's derby bleachers are stepped rows; a plank footbridge crosses the sawmill's log pond; the quarry's benches are joined by sloped haul ramps; the bayou's preacher's shack stands high on stilts up a gangway; the Mothership's tractor bay has a grating ramp. A chapter whose map changed starts over from a save made in it (guns and health kept).
- The firing range: all 30 guns racked, all eight bosses in the corral, every hand in the bullpen, a deer stand, and a bowling lane with real pin physics and ten-frame scoring.
- A new demonstration map, Mundell Feed & Seed, and map authoring tools for AI agents (`MAP_AUTHORING.md`).

# 2.0.0-dev.8 changes

## Browser build
- The opening street is now a safe start: nobody opens fire while the player is still standing at the level entrance with no enemy roused. Stepping out (or firing) starts the ambush as before, so a new browser player can read the controls instead of dying to the road sentry within the first half minute.
- A short spawn grace keeps enemies from spotting the player during the first seconds of any level.
- Browser sound effects now decode on first use instead of all at boot, cutting the long load stall and memory peak on the web build.
- The browser mixer uses a bigger buffer so heavy frames are less likely to crackle or drop out the soundtrack.

# 2.0.0-dev.7 changes

## Browser build
- pygbag converts the WAV masters to OGG for the web archive, so the game now loads effects and one-shot music streams from `.ogg`/`.opus` as well as `.wav`. This fixes the missing `title.wav` crash at boot and restores all sound effects in browsers.
- `main.py` imports numpy before pygame so pygbag sees the dependency during its boot scan instead of pausing mid-import.
- A browser that refuses pointer lock (for example an embedded or unfocused view) no longer interrupts the event loop.
- Raised the darkest ambient shade slightly so unlit corners stay readable on dim displays.

# 2.0.0-dev.6 changes

## Distribution
- Windows builds now go through `CrazyLegsMundellRampage.spec` (`build_windows.bat`) and can produce an Inno Setup installer (`installer.iss`).
- Added an Android target (`buildozer.spec` plus the `p4a-recipes/pygame-ce` recipe) with an on-screen thumbstick, drag-look, and FIRE/USE/ALT/NEXT/MENU buttons; desktop keyboard and mouse behavior is unchanged.
- Added a pygbag WebAssembly target and a GitHub Pages landing page. A tagged push builds the EXE, installer, APK, and browser build, then publishes the release and site.
- Resources resolve from `sys._MEIPASS`, the Android private directory, or the source tree; saves always stay in the per-user data directory.
- The game loop is asynchronous so browser builds yield each frame. Mobile and web builds prefer OGG soundtrack files, with the Opus and WAV masters retained for desktop.

## Weapons look and feel
- In-game weapon sprites are smooth-scaled with per-weapon framing, a warm rim light and a slightly raised hold, so larger guns read at 320x200.
- Weapon cutouts now sit flush on the status-bar line with no added arms, matching the Redneck Rampage bottom-of-screen hold. A small sink plus a hold clamp keeps the grip behind the HUD and stops bobbing or recoil from opening a blank sliver under the gun.
- The Teat Gun is redrawn as a galvanized milking can with gauge, hose, udder pump and spray nozzle (all-new 7-frame action).

## Combat balance
- Central DAMAGE/MELEE/GRIND tables replace inline numbers; boss HP raised (Sheriff 620, Jerry 720, Rudy 360, Foreman 420, Baron 480) so finale fights last.
- Capacity, reload and fire timing retuned for shotgun, rifle, arm gun and teat gun. Key-item replay kits read capacity instead of hard-coded counts.

## Levels
- Added about 24 reachable props per chapter (fair 36, sawmill 38, quarry 37 total), vetted with a floor BFS and spacing rules.

## Look
- Added a cached vignette and animated film grain to the DOS look pass (about 0.5 ms/frame); four distinct skies and light pools retained.

## Enemies
- Hits now flash the target white-hot and same-kind crowds vary slightly in height per spawn; pain/impact particles and death cues retained.

## Audio
- Reworked five thin interactable cues (bowling pins, kicked can, toilet flush, TV pop, vending clunk) with layered transients, body and tails.
- Restored high-end presence to all twelve tracks and gave the upbeat honky-tonk numbers (135+ BPM) a hotter lead and snappier kit.
- New reverb zones: loud world cues (explosions, enemy shots, gates, glass, machinery) layer a baked multi-tap room tail whenever the player is under a roof (`room_zones.py`); outdoor gunplay stays dry.
- Crossbow report gained body and about 2.5 dB more level; the enemy pump-action windup is deeper and easier to read. The whole gun set went back through the low-thump/shelf mastering chain.
- Existing occlusion muffle, room gun tails, radios and barks retained.

## HUD
- Low-health pulse and a RELOAD prompt when a magazine empties.
- New objective compass pin with distance that hides during banners and the automap.

## Verification
- smoke_test, save_check (v1-v4), weapon_check (0 flags), radio_check (0 problems), render_check, look_check and a 40 s/level combat bot soak all pass. No crashes.

## Still open
- All-new honky-tonk compositions, photo-sourced enemies, mugshot re-cut.

# 2.0.0-dev.3 changes

## Audio mastering (audio_master.py, audio_audit.py, audio_compare.py)
Measured against the reference soundtrack, SFX and voice files you supplied (analysis only, nothing copied).
Before -> after (median / mean):
- Guns: low-end share 0.09 -> 0.12, RMS -15.7 -> -14.8 dB (added a short synthesized low thump per shot)
- Explosions: low-end share 0.22 -> 0.49, RMS -18.3 -> -15.0 dB
- Ambience: RMS -32.4 -> -22.4 dB, peak -17.4 -> -8.0 dB
- Music (12 tracks, re-encoded to Opus): low share 0.27 -> 0.15, high share 0.18 -> 0.30, centroid 1608 -> 2238 Hz (reference is about 3400 Hz)
- No clipping anywhere. Originals backed up before processing; rerun is idempotent.
Not verified by ear.

## Weapons (16 total)
New: Bowling Ball [-] (rolls and hits everything in its path), Powder Keg [=] (lobbed, big blast), Cow Launcher [\] (launches a cow, blast plus moo), Teat Gun [`] (30-round rapid fire).
Riveter and Copperhead are no longer given or placed: their old pickups and chapter rewards turn into Bowling Ball and Cow Launcher.
New items: Whiskey [V], Cow Pie [X]. Old saves load and are padded to the new slot counts.

## Interactables
About 8 new per chapter (TV, toilet, vending machine, window, kickable can, jukebox), placed automatically on reachable floor. Shoot or blast them: new sprite, sound and particles.

## Look
DOS dither plus per-chapter color wash and indoor lamp flicker (SETUP > VIEW, both toggles). About 1 ms per frame.

## Tools
nav_bot.py (BFS path bot; still gets stuck in places, so its kill counts are not balance data).

## NOT done
Photo-sourced enemy roster, new HUD layout, mugshot re-cut (needs your photos), vehicles and raised floors, hand-authored set pieces,
new honky-tonk compositions, reverb zones, in-world radio, wall texture upgrade, game.py split, full DPS rebalance.
