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
