# Crazy Legs Mundell Rampage
## The Hickston Incident · Campaign 2.0.0-dev.6

A standalone Windows FPS in the style of Xatrix Entertainment's 1997 Redneck Rampage. The campaign runs from Hickston through Possum County Fair and Blackwater Timber to Stillwater Cut. County Crossroads sits inside Hickston and has four road gates. The four reference photos supply the 12-frame mugshot and full-body player in the title, the intermission, the GENTS mirror, and Hickston County wanted posters.

The 1.4.1 detail pass dresses 40 locations across the four chapters and County Crossroads. Look for garage tools, concession hardware, mill machinery, still gauges, and roadside gear. The Alien Sheriff wears a patched county coat, and the Ranch Rifle has a lower idle pose and visible ejection port.

The 1.4.2 combat pass gives the regulars distinct silhouettes and turning sprites. Billy leans into his scattergun, the Coot hunches over his pistol, and the larger bosses visibly settle after an attack. All twelve weapon sets have revised finishes and timing for their actions. The player's patched overalls and work cap appear in the title, posters, and eight-way bathroom reflection.

The 1.4.3 armory pass gives the Bottle Rocket Launcher, Mill Riveter, and Copperhead their own shapes and reloads. The dynamite crossbow has a visible draw cycle, the Rip Saw shows its cutting wheel, and the Alien Arm Gun has an asymmetric shell and claws. A bottle rocket now cracks out of the pipe, whistles in flight, and lands with a smaller firecracker burst.

This development pass adds the optional Tin Rooster gallery, a dry boardwalk around the mill pond, and changing notices at County Dispatch. Look for short paper clues across the four chapters. Glass and loud machinery can draw a nearby enemy's attention. A shuddering pipe gives you time to step clear. Setup's **Next Run Supplies** offers Standard, Scarce and No Drops. Scarce cuts ammo from boxes. No Drops removes ordinary enemy ammo drops and preserves chapter supplies. The selection takes effect when you start a new run. Saved runs retain their original rule.

### Downloads and builds

| Target | File | Notes |
| --- | --- | --- |
| Windows portable | `CrazyLegsMundellRampage.exe` | Single-file EXE, no install |
| Windows installer | `CrazyLegsMundellRampage_Setup.exe` | Start-menu shortcuts and uninstaller |
| Android | `CrazyLegsMundellRampage.apk` | Android 7.0+, arm64 |
| Browser | <https://treymun.github.io/crazy-legs-mundell-rampage/> | Pygbag WebAssembly build |

The landing page's download buttons always point at the newest GitHub release. Rebuild locally with `build_windows.bat` (PyInstaller + Inno Setup), `buildozer -v android debug` after `python scripts/make_ogg.py`, or `python -m pygbag --build .`. Pushing a `v*` tag runs `.github/workflows/release.yml`, which builds all three packages, publishes the release, and deploys Pages.

### Play

Double-click **CrazyLegsMundellRampage-2.0.0-dev.6.exe** on Windows x64 and press **Enter** at the title. The EXE contains the game, runtime, audio, and art. The first launch opens in a resizable 4:3 window. This build is a local development checkpoint.

| Input | Action |
| --- | --- |
| WASD or Up/Down | Walk and strafe |
| Mouse or Left/Right | Aim or turn; hold Alt with the arrows to strafe |
| Left mouse or Left Ctrl | Fire; with dynamite, hold to light and release to throw |
| Right mouse | Fire both shotgun barrels, grind with the Rip Saw, or fire a two-rivet burst |
| Shift / Caps Lock | Run / toggle always-run |
| J / Z | Jump / crouch |
| 1–8 | Crowbar, .38 revolver, sawed-off shotgun, dynamite crossbow, Ranch Rifle, Rip Saw, Alien Arm Gun, handheld dynamite |
| 9 / 0 / - | Sling Blade / Bottle Rocket Launcher / Mill Riveter |
| = | Copperhead Pressure Gun |
| Mouse wheel or ; / ' | Cycle owned weapons |
| R | Reload |
| H or Scroll Lock | Lower or raise the weapon |
| E, Space, or middle mouse | Use doors, road gates and props or rescue Bessie |
| Q or [ ] | Select inventory item |
| F or Enter | Use selected item |
| C, B, M | Use pork rinds, beer, or moonshine |
| Tab | Toggle the automap and current objective |
| Home / Backspace | Center vertical aim / turn 180° |
| Y | Holler |
| F4 | Toggle music |
| F5 | Open the four named save slots |
| F6 / F9 | Quicksave / quickload (F2 and F3 also work) |
| F11 | Toggle between windowed mode and your last fullscreen mode |
| F12 | Save a screenshot |
| Esc | Pause and return to the title menu |

Start at Stanky's and find the brass key in the dispatch office. It opens the barn's front gate and its loading entrance off the trailer lot. The barn holds the shotgun, crossbow, and Rip Saw. Follow the service road east to the Stock Registry for the steel pasture key. It also opens a shortcut back across the county yard. Runs started in older releases can still find an uncollected key at the original barn feed scale. Pick up the Alien Arm Gun in the pasture. Defeat the Alien Sheriff and the fictional Jerry Jones boss, then approach Bessie and use E. The trailer lot's powder store needs a blast to open. Use E on other cracked panels. Red fuel drums explode when shot and can set each other off.

After each intermission, press **Enter** to return to the crossroads. Approach the next gate and press **E**, **Space**, or the middle mouse button to continue with your current health, weapons, ammo, and consumables. Gate signs identify the destination. Close prompts explain locked roads, continuing, revisiting, and resuming a replay. The fair, sawmill, and quarry gates open in campaign order. Use each level's return gate to suspend progress, or choose **County Hub** on the title.

Use a completed chapter's gate to revisit its current world. Its enemies, pickups, doors, controls and secrets retain their state. A revisit has its own local supplies, and changes there stay separate from the active chapter's inventory. To start over with a fixed kit, choose **Replay Level** from the title. Hickston's kit includes the crowbar, revolver and one bag of rinds. The other kits also include a loaded sawed-off and Ranch Rifle, spare ammunition, two bags of rinds, and that chapter's weapon. The crossroads has three optional road notes that mark their locations on your map when found. Each chapter has three counted secrets plus optional approaches.

At the fair, collect the patch lead from the Raffle Office and carry it to the backstage PA booth. Patch the booth and set the concession breaker in either order. Ring the show bell to open the pavilion, then cut its broadcast. Rudy Racket sweeps in alternating directions with a charged horn. Use the prize stalls for cover and attack during his recovery. The midway barker raises a small horn before a three-way spread. Watch the landing mark when a bottle tosser winds up.

At Blackwater Timber, isolate the west feed and strike the belt release at the east dry kiln. Release the log carriage brake and shut down the pump house relay. The dry banks flank the shallow pond. Give a chain hand space when he raises both arms. The Splinter Foreman alternates between two and three marked cutting lanes. Step off the marks and use the log stacks for cover.

At Stillwater Cut, isolate the cutting feed and turn the copper condenser three times. Follow the recovery gate and haul lanes back to the bottling works, vent the relay, and clear the loading court. Watch the Boilerback's gauge before it vents in a cone. Move after a Chalk Spitter marks your last position, and step or jump clear of a valve guard's low shot. The Copper Baron alternates bursts from marked pipe outlets with a forward vent. Optional relief valves reduce the pressure and lengthen his recovery. Use the load ticket after the court is clear to finish the campaign.

Fire the Ranch Rifle in bursts to keep it on target. The Rip Saw's blades rebound off walls and can come back at you. Use the right mouse button to grind without spending a blade. The Arm Gun's plasma splashes nearby targets. Collect a box of sticks to unlock handheld dynamite in slot 8. It shares the crossbow's spare ammo. You can cook the fuse for a shorter throw delay, but it will go off in your hand if you wait too long. The Hickston Sling Blade has a slower swing and longer reach than the crowbar. The fair's Bottle Rocket Launcher deals splash damage, including at close range to the player. The Mill Riveter can fire one rivet or a pair. The Copperhead fires a short-range pressure slug that interrupts an ordinary enemy's windup. The interruption has a per-enemy cooldown. Bosses still take damage and keep their attack telegraph.

Listen for the attack cues and move after an enemy takes aim. Billy Ray closes in with a scattergun, Old Coot backs off to shoot, and skeeters dive toward your last position. Saucers fire paired bolts. The Sheriff's plasma cannon has an audible siren and switches to a wider volley at low health. Listen for Jerry's whistle before he throws; he throws three footballs per volley at low health.

Pork rinds and beer restore health and build the GUT and DRUNK meters. Excess beer makes aiming and movement drift. Moonshine lowers both meters and briefly boosts speed and crowbar damage. At Stanky's you can shoot out the front pane and jump through the sill, play the jukebox, or use the restroom sink.

Open **Setup → Display → Window Mode → Fullscreen (Fill)** to use the entire monitor. **Fullscreen (Aspect)** keeps the chosen proportions. Use the mouse or Tab/Page Up to switch setup pages. Display also includes brightness, frame limit, scaling, screen flashes, bob, crosshair, and status panel style. Input has separate turn and look speeds and hold/toggle crouch. Audio has separate music, effects, ambience, footsteps and voice volume, plus optional dialogue captions. **View** has scenery motion, lower or hidden weapons, and bullet marks. Play has difficulty, aim assist, automatic reload, weapon switching, blood particles, and optional hints.

On Windows saves, settings, and screenshots live under `%LOCALAPPDATA%\HickstonIncident`. **F5** opens named slots, four for the campaign and four per replay chapter. Enter a label and confirm separately to overwrite. Each slot shows the chapter, saved objective, and local timestamp. **F6/F9** use a separate quicksave. **Continue Campaign** opens the crossroads using the last recorded chapter entry or suspension, including completed worlds saved with 1.3.0. Retry after death restores the supplies you had when you entered the level. Supported V1–V3 saves are backed up before conversion to V4. Throw a lit stick before saving.

Menus, the HUD, and gameplay messages use native pixel lettering. Brightness changes the scene only, so the HUD and prompts stay readable even on the darkest setting.

### Build from source

Extract the complete ZIP. On Windows with Python 3.12 x64, double-click **Build_CrazyLegsMundellRampage.bat**. It makes a project-local virtual environment, installs the pinned dependencies, and builds the versioned EXE in **dist**. The prebuilt EXE in the ZIP runs independently.

From the project folder, run these commands for the same build.

    py -3.12 -m venv .venv
    .venv\Scripts\python.exe -m pip install -r requirements.txt
    .venv\Scripts\python.exe build_standalone.py

Run **main.py** with the same interpreter to play from source. The project includes pre-rendered art, WAV effects and streaming Opus music. **world_art.py** and **audio.py** regenerate the scenery, props, weapons, effects, VGA lookup, and music. For weapons only, run **weapon_art.py** followed by **expansion_weapons.py**. **face_pipeline.py** documents the four-photo workflow. The package includes derived sprites and the wardrobe plate. Keep your private photos separately.

### How the game is put together

- **engine.py** casts rays against walls at different heights with NumPy, draws porch steps and solid furniture, shades distance in steps, and renders the bathroom reflection through the visible part of the mirror.
- **period_palette.py** maps each 320×200 frame to the project's original 256-color VGA grade before scaling.
- **campaign.py**, **level_hickston.py**, **level_expansion.py**, and **level_quarry.py** define the four maps, gate destinations, routes, and completion conditions. **game.py** and **enemies.py** handle combat, patrols, secrets, and finales. **world_art.py**, **route_art.py**, **expansion_art.py**, and **quarry_art.py** bake scenery. **actor_models.py**, **expansion_enemies.py**, and **quarry_actors.py** bake the enemy animation frames.
- **county_detail.py** places the new hardware, wall finishes, and floor wear against existing map geometry. Run **county_detail_art.py** to regenerate those PNGs.
- **hud.py**, **weapons.py**, **weapon_art.py**, **weapon_models.py**, and **expansion_weapons.py** draw the status bar and twelve weapon sets. The rifle's magazine and bolt move independently. The sawed-off breaks open and shows one or both shells during reload.
- **session_store.py** handles quicksaves, level entry, chapter unlocks, save migration, and setup controls.
- **face_pipeline.py** aligns the photos, reshapes expression regions, and creates the digitized palette and sprite cutouts.
- **player_art.py** combines the baked portrait with work clothes and makes the directional mirror cels, wanted poster and title composition. It runs from the included art without the original photos.
- **audio.py**, **sound_production.py**, **expansion_audio.py**, and **soundtrack_production.py** assemble 16-bit PCM effects, area ambience, and original arrangements from recorded instruments. Nearby sounds pan and lose level behind walls. **score_player.py** runs the four shuffle playlists. See [the soundtrack manifest](MUSIC.md).
- **expression_sheet.png** shows all twelve expression sprites.

The 320×200 software presentation, distance shading, inventory meters, rural environments, and humor are period-inspired. The campaign, sprite artwork, audio, and engine are custom. The materials and title photograph are credited in **THIRD_PARTY_NOTICES.md**. Visual and gameplay references include [Interplay's game listing](https://store.steampowered.com/app/565550/Redneck_Rampage/), [the original manual](https://store.steampowered.com/manual/565550/), and [the 1997 demo](https://www.dosgamesarchive.com/file/redneck-rampage/redneckd).

