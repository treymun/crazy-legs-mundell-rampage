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
| Browser | <https://treymun.github.io/crazy-legs-mundell-rampage/> | Godot WebAssembly build, playable on the landing page |

The landing page's download buttons always point at the newest GitHub release. From 2.0.0-dev.9 the release is built from the Godot project in `godot/`; the original Python/pygame game it was ported from is kept at the git tag `python-original`.

### The Godot build

`godot/` is a Godot 4.7 project, and it is the game: releases, the site and all new work come from it. It started as a port of a Python/pygame game (kept at the git tag `python-original`). Its maps are `godot/data/*.json`, and its art, sound and palette are packed from `assets/` and `audio_src/`. Its own reference images (`godot/tools/pictures/`, checked by `tools/picture_check.gd`) guard its look from one change to the next.

Build it from a clone:

```
godot --headless --path godot --script res://tools/pack_assets.gd
godot --headless --path godot --import
godot --headless --path godot --export-release "Windows Desktop" build/windows/CrazyLegsMundellRampage.exe
godot --headless --path godot --export-release "Web" build/web/index.html
godot --headless --path godot --export-release "Android" build/android/CrazyLegsMundellRampage.apk
ISCC installer.iss
```

`tools/pack_assets.gd` writes the asset packs (`godot/assets_gen/*.bin`, about 70 MB, not committed) from `assets/`, `audio_src/` and `godot/assets/music` in a few seconds; it needs no Python. The exports need Godot 4.7.2 with its export templates, and the Android one also needs a JDK 17, the Android SDK and a keystore. The Windows export is a single EXE with its data inside; `installer.iss` wraps that one file.

Checks, all headless:

```
godot --headless --path godot --script res://tools/check_fixes.gd    # porting regressions
godot --headless --path godot --script res://tools/bot_campaign.gd   # the whole campaign
gdformat --check godot/src godot/tools && (cd godot && gdlint src tools)
```

Both scripts save into the game's own profile. Point `APPDATA` at a scratch folder first if yours matters.

`.github/workflows/release.yml` runs those checks and the three exports on every push to `main`, and deploys the landing page with the browser build under `play/`. A `v*` tag stamps its version into the build and also publishes the EXE, the installer and the APK as a release. Set the `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_USER` and `ANDROID_KEYSTORE_PASSWORD` repository secrets to sign the APK with a lasting key; without them each run signs with a throwaway one, and a phone has to uninstall the old copy before it takes a new one.

The Godot build's sound is produced from `audio_src/`: stored ElevenLabs recordings, the supplied menu theme, and `scripts/audio_build.py`, which finishes them into the effect bank's cues and the Ogg music. `audio_src/README.md` explains the layout, how to change a sound, and the credit ledger; nothing in a normal build contacts ElevenLabs.

The landing page lives in `site/` (plain HTML, CSS and JavaScript). `python scripts/build_site_assets.py --audio` rebuilds its pictures and sound previews from the game's assets.


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

### How the game is put together

The game is the Godot 4.7 project in `godot/`; `CLAUDE.md` lists the commands, the checks and the rules for working on it.

- `godot/src/` holds the game in GDScript. Three big parts are chains of layers, each file extending the one before: the front end (`main_state` → `main_flow` → `main_input` → `main`), play (`game_state` → `game_world` → `game_combat` → `game_view` → `game`) and the software view (`render_state` → `render_surfaces` → `render_sprites` → `renderer`).
- With a window, `palette.gdshader` draws the view on the graphics card: sky, floors, ceilings, walls and sprites, then the weapon and HUD layer (drawn with Godot 2D) and the 256-colour grade. Without one (tools, CI) the software view draws the same picture.
- `godot/data/` holds the four maps (`*.json`, the source of every level) and `godot/data/tuning/` the weapon and enemy numbers.
- `assets/` and `audio_src/` hold the art and sound; `tools/pack_assets.gd` packs them for the game. The Python scripts in `scripts/` make that art and sound (Blender renders, digitizing, ElevenLabs, mastering); the game and its build need no Python.

The original Python/pygame game this was ported from is kept at the git tag `python-original`.
