# Menus and the HUD

The menu screens are Godot Controls in `godot/src/ui/`, and so is the play
HUD's status bar and objective pin (`src/ui/hud/`, below). The notices,
prompts, callouts, boss bars, the range card, the 5v5 store and COUNTY RUN's
cards still draw with the Canvas helpers on the Godot 2D canvas, over the
HUD's Controls; see [gameplay.md](gameplay.md#the-automap-canvas-and-sprites)
for the two canvases.

## The HUD on Controls

`HudLayer` (`src/ui/hud/hud_layer.gd`) is a 320x200 Control in the overlay
viewport, the overlay's first child: under the canvas's own drawing (the
`Node2D` painter) and under `UiRoot`. `main_state.gd _start_overlay` makes it
and sets `hud.controls`; a headless run (no overlay) has none and `HUD.draw`
draws the bar on the software canvas as before.

- **StatusBar** at (0, 156), 320x44: a `Plate` TextureRect (the bare plate of
  the mode, `HUD.plate_texture`: campaign, 5v5 or COUNTY RUN headings) under
  one TextureRect per part (`HudLayer.BOXES`: `rail`, `rail_end`, `health`,
  `ammo`, `third` (keys or vest), `face`, `gauges` (the gut and drunk
  meters, the 5v5 side and gear, COUNTY RUN's gun slots; the bar's whole
  height), `pocket`). Each box is an `AtlasTexture` of its rectangle of
  `HUD.bar_texture()`, which `_draw_bar` draws in software only when what the
  bar shows changes (`_bar_state`), so the bar is the old picture pixel for
  pixel.
- **ObjectivePin** (`HudPin`, a `Painted`, repainted every frame) draws
  `HUD.objective_pin` at `game.pin_top`.
- **ASPECT WIDE** (pass 14, [view3d.md](view3d.md#aspect-wide-pass-14)):
  `HudLayer.fit()` makes the layer the picture's width (`View.cols`). The
  bar's parts left of `SPLIT` (171: the rail, health, ammo, keys or vest, the
  face) keep the left edge, the rest (the gauges, the pocket, the rail's end)
  move to the right edge, and the plate's wood between is `Planks`, its
  columns `FILL` (183 to 228: plain planks under one of the rail's sections)
  laid end to end; the plate's two parts are AtlasTextures of it. The pin is
  centred (`View.shift`). At 320 everything is where it was (`wide_check`).
- Each frame `render()` clears `hud.shown_game`; `HUD.draw` (reached at the
  end of `game_view.gd _draw`) only notes the game and guns when
  `hud.controls` is set; `hud_layer.show_frame()` then shows that frame's HUD
  or hides it (menus, the tally, PHOTO MODE and the KILL CAM draw none).
- **HUD MINIMAL** (DISPLAY, `hud_mode`; `hud.minimal`): the rail, the face and
  the campaign's meters are left off (their boxes hidden, the plate showing
  through; the software bar skips drawing them), and the pin; the 5v5 side
  and COUNTY RUN's gun slots stay.
- **The driving plate** (`src/vehicle_hud.gd`, drawn on the canvas by
  `features/vehicles.gd draw_view` while riding): speed, the rig's health
  and state, the throttle and the kind's line, in the plate's colours and
  lettering; MINIMAL keeps two lines, STATUS PANEL shows the speed on a
  dial; it hangs in the view's top left under the pin, clear of the hands
  on the controls and the touch stick
  ([gameplay.md](gameplay.md#vehicles)). A vehicle set piece's plate
  (`features/vehicle_runs.gd draw_view`) hangs across from it in the top
  right in the same tin: the run's name, LAP n/3 or GATE n/N, the time
  left in the big lettering (flashing red in the last ten seconds) and the
  next gate's name; MINIMAL keeps one line.
- **The automap's key** (`map_key.gd`) adds a last row, RIG, KEYS IN IT,
  with the little picture the map marks a ready vehicle with
  (`src/vehicle_finder.gd`), on a map that has one; and NEW IRON with the
  little red gun a gun not had yet is marked with once seen
  (`src/gun_finder.gd`).
- **The chapter tally** (`hud.gd intermission`) has a GUNS row under the
  secrets in a campaign chapter (its guns had, `GunFinder.tally`); with
  seven rows they close up to 10 pixels apart.
- **Scaling:** the overlay is the 320x200 picture (WIDE: as many columns as
  the screen's shape asks), scaled to the window by the display shader with
  crisp pixels (INTEGER 8:5 keeps every pixel the same size) inside the
  phone's safe area, so the HUD scales with the picture on a phone and on a
  big screen.
- `tools/camera_check.gd` composes the bar from the boxes over the plate
  (`HudLayer.composed()`) and holds it to `HUD.draw`'s software rows for the
  campaign, a 5v5 round and COUNTY RUN, full and MINIMAL.

## The HUD's layout

`HudLayout` (`src/ui/hud/hud_layout.gd`, `hud.layout`) owns the view's
edges: every piece drawn over the view takes a rect from it each frame and
no two overlap, however crowded the moment. Margins: 4 pixels from the
sides and top, nothing below row 153; pieces keep a pixel apart. A rect is
all the piece inks (outline and drop shadow too: `text_rect`, `panel_rect`).

`game_view.gd _lay_hud` lays the frame out before anything is drawn, in
this order (first come keeps its place):

1. `pinned`: what the front end draws after play (FPS, the online ping).
2. `GameFeature.hud_fixed`: pieces that never move (BLUE's badge in the
   bottom left, the 5v5 strip, cash and kill list, versus's frags line,
   COUNTY RUN's clock, XP bar and storm ring).
3. The top stack: the notice or place name (`banner`, narrowed round what is
   beside it, or moved down rather than grow more than a line), a new
   player's tip under it (`tip`, chalk green, lessons.gd; a place's name
   waits while one is up), the boss bar, the objective pin's row (the whole
   width, it swings).
4. `GameFeature.hud_flow`: pieces that hang under the top or stack on the
   corners (the driving and run plates, the lap timer, station and gallery
   cards, the flashlight over the badge, the revive line, the watching
   lines), then a picked-up item.
5. The prompt and the caption (or a bark) rising from the foot, narrowed
   clear of the badge; then a streak's call under the pin.
6. `GameFeature.hud_late`: the kill feed, oldest lines left off when short
   of room.

With the touch buttons showing, each button over the view is pinned first
(`main_state.gd _pin_hud`, `TouchControls.shown_buttons`), so the notice
and the rest keep off them; the move stick is the thumb's and is not. LIGHT
and WHISTLE sit in the top row and show only when they do something (a
flashlight, BLUE along: `TouchControls.offer`, main.gd each frame);
`hud_crowd.gd`'s touch moment shows both.

Pieces placed while drawing: partner tags at the view's edge (they wait
when there is no room), the windup and hurt marks. Marks drawn straight on
the view (the hurt arc round its edge, USE's corner brackets) go down before
the notice and the tip, so a banner is never struck through (pass 12: a hit
from in front ran the arc across the top banners). A feature draws its piece
where `layout.find(name)` says, inside `HudLayout.begin(c, name)` /
`end(c)`, which measure its real ink when `HudLayout.measuring` is on.
The boss's entrance ribbon is a moment of its own and is not laid out.

`tools/hud_layout_check.gd` (HUD LAYOUT OK) sets up crowded moments
(`tools/hud_crowd.gd`: campaign, SMALL TEXT, MINIMAL, driving, the
speedway's lap, co-op watching and reviving, a boss, versus, the fair,
COUNTY RUN, 5v5) headless and fails when any two pieces' ink touches, one
inks past the margins, or an expected piece is missing; `png=<dir>` writes
each moment's canvas with the rects outlined. `tools/hud_frames.gd` pictures
every menu and the same moments in a window.

A new HUD piece: take its rect in `hud_fixed`/`hud_flow`/`hud_late` (or in
`_lay_hud` for play's own), draw it at `find(name)` between `begin`/`end`,
and add it to a moment in `hud_crowd.gd`.

**ASPECT WIDE keeps the edges** (pass 14). The layout is worked out at 320
as ever; `begin(c, name)` then moves a piece that hugs an edge out to the
picture's edge (`HudLayout.side_of` its rect: starting within `HUG` 16 of
the left side and ending left of the middle, or the same on the right;
`Canvas.anchor(±View.shift)`, a transform on the canvas items until `end`).
Pieces only move apart, so the layout's promise holds. The touch buttons are
pinned where the pieces of their half see them (`_pin_hud`), and a tap on
BLUE's badge is read where the left edge's pieces are
(`picture_point(at, -1)`). Something drawn at an edge outside `begin`/`end`
calls `c.anchor()` itself (PHOTO MODE's strip, the cinematics' skip line).

## The parts

- **UiRoot** (`ui_root.gd`) is a Control the size of the canvas (320x200),
  centred on a WIDE picture (`View.shift`; what is behind, the title's scene
  or the game, shows at the sides; a pointer is mapped to the overlay's
  columns, `_to_canvas`). It lives in the overlay SubViewport the display
  shader lays over the 3D view,
  or in a viewport of its own in a headless run, so the checks drive the same
  screens. It maps each front-end state to a UiScreen (`SCREENS`), shows the
  screen of the current state and hands it every input event (`take()`):
  touch becomes the pointer, the window's coordinates become the canvas's,
  keys and pads go as they are. `UiTheme` is set on it.
- **UiScreen** (`ui_screen.gd`) is one menu screen, a Control:
  - `open(main)`: the screen is shown (build or refresh what it shows);
  - `back()`: BACK (ESC, a pad's B), true when the screen dealt with it;
  - `draw_back(c)`: paints what is behind the buttons on its `Painted` layer,
    every frame while shown;
  - `render(c)`: draws on the front end's canvas every frame, for screens
    whose drawing notes tap zones (that must happen headless too);
  - `picked()`: the button the front end's selection names; keys go to it, so
    the focus follows the selection whoever moved it;
  - `add_button(rect, id, look, pressed_do)`;
  - flags `keys_own` (keys and a pad go to Godot's focus here) and
    `pointer_own` (the pointer and touch go to the screen's controls).
- **PixelButton** (a BaseButton): focus, hover picks, a `look` Callable that
  paints it, a `step` Callable for left/right.
- **Painted**: a Control that draws with the game's Canvas helpers.
- **PixelFont**: the pixel letters as a FontFile.
- **UiTheme** (`ui_theme.gd`): the pixel font, no Godot focus boxes.

## The screens

In `src/ui/screens/`:

| Screen | States | How it takes input |
| --- | --- | --- |
| `TitleScreen`, `ReplaysScreen`, `RematchScreen`, `RematchDoneScreen`, `ControlsScreen`, `CreditsScreen` | title, replays, rematch, rematch_done, controls, credits | buttons; Godot focus |
| `OnlineScreen` (a `ZonedScreen`) | multi, showdown, servers, nethost, netjoin, lobby, lobbyset | drawn with `LobbyScreens` zones; pointer via the Control, keys via the front end's handlers |
| `CountyMapsScreen` (a `ZonedScreen`) | county | likewise, with `CountyScreens` |
| `CustomMapsScreen`, `MapEditorScreen` | maps, mapedit | their own: focus on the screen, keys, the mouse and touch in `_gui_input` ([levels.md](levels.md#player-maps)) |
| `KeyedScreen` | setup, slots | drawing only; keys and pointer stay with `main_input.gd` (a finger: `_touch_menu`, below) |

`ZonedScreen` is the base for screens drawn with zones (each draw notes where
a tap lands, and a tap becomes the key it stands for). The multiplayer menus'
rules are in [multiplayer.md](multiplayer.md#the-multiplayer-menus).

## Input

- Touch becomes the pointer in `UiRoot.take`.
- A pad drives menus through `read_pad` -> `_pad_menu` -> `key()`.
- The keys stay the rules on zoned and keyed screens; buttons on button
  screens.
- `tools/menu_touch_check.gd` (MENU TOUCH OK; check_all, CI) taps through the
  menus as touch events, and in play the junk bench's board, the USE button
  held and a tap over a chapter's opener.

### How a finger reaches a menu (pass 14)

The owner's phone browser took no finger on SETTINGS. A finger comes as
`InputEventScreenTouch`/`ScreenDrag` (mouse emulation is off in
project.godot, so it is never also a click) and takes one of two roads in
`main_input.gd _input`:

- **A screen that takes the pointer** (buttons, zoned screens, CUSTOM MAPS,
  the MAP SHED): `_to_screen` -> `UiRoot.take`, which turns the finger into
  the pointer in the screen's own viewport (a move, then the click).
- **A keyed screen** (SETTINGS, LOAD / SAVE: `KeyedScreen`, `pointer_own`
  off) and the states without a screen: `_touch_menu` and `_touch_drag`. On
  SETTINGS a tap counts when the finger lifts without moving; a finger that
  lands on the picked row's bar or the groove slides it; any other drag
  scrolls the list.

Two rules hold for both, and every new control must keep them:

- **Any finger number.** Godot's web build passes the browser's
  `Touch.identifier` on as the index, and a phone browser numbers fingers as
  it likes (an iPhone's are big numbers). The first finger down drives the
  menus until it lifts, whatever its number (`_menu_finger`); others are
  ignored. Never test `index == 0`: before pass 14 the keyed screens did, and
  took no finger at all in such a browser.
- **The browser's echo.** Godot's web build reads the page's `pointermove`
  as the mouse, and a moving finger is a pointer, so every drag also comes
  as an `InputEventMouseMotion` with no button held. `_finger_echo` drops a
  mouse motion while a finger is down (`fingers_down`); before pass 14 the
  echo ended a bar's drag at its first touch and lit rows under a scrolling
  finger.

What a finger is told: the hints and footers say TAP where the keys say
ENTER or ESC (`input_device == "touch"`; `Menu.touch_words`,
`LobbyScreens.footer(c, keys, by_finger)`); CONTROLS opens on its TOUCH page;
a KEYS row tapped waits for a key and says a tap keeps the old one (the
footer: KEYBOARD ONLY), since only a plugged-in keyboard can bind; LOAD /
SAVE's name and overwrite questions show their two answers as plates.

**Typing on a phone.** Android's soft keyboard types as keys. In the browser
Godot's own keyboard is off (experimental, it hands text only to a
LineEdit, and an iPhone opens no keyboard from a frame's code), so a tap on
a field (a save's name, the host and join forms, the server list's name,
the MAP SHED's lines) asks the browser for the text, the phone's keyboard
included (`WebTyping.ask`, a `prompt()`), and types the answer in as keys,
so each field keeps its rules. A mouse click on a field keeps the keyboard.

**A new control:** take the pointer through a `UiScreen` (buttons or zones)
where you can, so `UiRoot.take` brings the finger; if it reads fingers
itself, gate them with `_menu_finger` and never read a finger number; give
it a place to tap for every key it answers to (a BACK plate, not ESC alone),
and TAP words for a finger. A new setting needs nothing more:
`touch_settings_check` covers every row of the settings list.

`tools/touch_settings_check.gd` (TOUCH SETTINGS OK, quick) drives every page
and setting of `SessionStore.setup_pages()` by touch events only, the way
the engine delivers them, with a browser's finger numbers and echo and with
Android's; `tools/touch_screens_check.gd` (TOUCH SCREENS OK, quick) the
title's screens and their BACK, the MAP SHED, LOAD / SAVE and every play
button ([checks.md](checks.md)).

Tried in pass 14 in both browser builds in Edge with real touch events, a
390x844 phone upright and an 844x390 one on its side, Android's and an
iPhone's browser named, fingers numbered 0 and in the thousands: before the
fix SETTINGS took no tap at all from a big finger number and a bar would not
slide; after it every page, row, bar, the groove, KEYS, RESET, KEEP / UNDO,
MOVE THEM, LOAD / SAVE (a name typed in the browser's box), JOIN WITH A
CODE's field and the MAP SHED (its plate, painting, MAP NAME) worked. Not on
a real phone.

### Touch in play (polish pass 9)

What each v3.6.0 screen and feature takes from a finger (`src/touch_controls.gd`,
`main_input.gd _touch_actions`):

| What | By touch |
| --- | --- |
| The junk bench's board | USE at the bench opens it; a tag tapped buys it, a tap off it (or USE, or MENU) shuts it; the stick picks and FIRE buys, as the keys do |
| Finishers, the boot, a door kicked in | the USE button (USE's own) |
| Holding USE: a partner's revive, BLUE got up, a 5v5 plant or defuse | the USE button held down (`state()["hold"]` -> `Controls.hold`; before pass 9 a finger could not hold USE at all) |
| The county radio | nothing to press: it plays and captions by itself |
| BLUE's commands | a tap on his badge whistles (SIC 'EM, FETCH, STAY, COME by what the sights are on) |
| County events | USE throws a blackout's main breaker; the twister, the hogs and a raid ask for nothing but moving |
| A chapter's opener, the KILL CAM | a tap anywhere skips it |
| The 5v5 store, County Run's cards and end | their own taps (`TacticalScreens.tap`, `CountyInput.tap`; County Run's take the only finger down, any number) |

The buttons: the top row stands 9% of the width apart, so on a phone held
upright (a browser) its rings shrink to fit (`TouchControls.layout`, pass
14: they overlapped). MOVE THEM keeps the places in `user://touch-layout.json`,
never written by a tool.

Not checked by hand: none of it has been tried on a real phone.

## Voice chat's pieces (pass 13)

Online voice chat ([multiplayer.md](multiplayer.md#voice-chat-pass-13)) adds:

- **Settings**, AUDIO page under VOICE CHAT ONLINE: VOICE CHAT (on), MICROPHONE
  (off), TALK (PUSH TO TALK or OPEN MIC), MIC SENSITIVITY (open mic's gate),
  VOICE QUALITY (CB 8K or CLEAR 16K, the default; pass 14), VOICE CHAT
  VOLUME (80); the KEYS page's PUSH TO TALK (T). A pad talks with
  its share, touchpad or first paddle button held (pads are not bound).
- **Touch:** a TALK button (`TouchControls` role `talk`, held, at the left
  edge above the move stick, for the left thumb) offered in play while the
  mic is on PUSH TO TALK.
- **In play:** `VoiceChat.pins` takes the rows down the left from row 22 in
  `main_state.gd _pin_hud`, so the layout keeps clear; `VoiceChat.draw`
  draws ON THE AIR or the mic's trouble and who is talking there, and the
  talking mark (a 7x5 mouth with sound off both sides) over a talker this
  player can see. The 5v5 scoreboard shows the mark beside a name.
- **The lobby:** the mark left of whoever talks, MUTED after a muted name,
  our own row's MIC OFF, NO MIC, ALLOW MIC, MIC REFUSED or VOICE OFF; a click
  or tap on someone's name mutes or unmutes them (zone `mute`,
  `OnlineInput._tap_lobby`); the footer says so.
- `tools/voice_frames.gd` pictures them in a window.

## The update notice (pass 14)

So nobody has to uninstall and reinstall to keep up (a friend's ask, phones
above all), the Windows and Android builds look for a newer version once at
start (`src/update_notice.gd`, `UpdateNotice`):

- **When:** `main.gd _ready` calls `start_update_check()` (main_state.gd),
  which makes the notice only when `UpdateNotice.wanted`: not the browser
  (the page updates itself), not headless, not a tool (a script main loop),
  not a tour, bench, smoke run, launch check, `--dev` run or either server,
  CHECK FOR UPDATES on (PLAY page, on by default), and a platform with a
  download (Android or Windows). Turning the setting on later starts it then.
- **What:** one `HTTPRequest` GET of the site's `version.txt` (written by
  release.yml's Pages step from `tools/version.gd`), an 8 s timeout, at most
  256 bytes, two redirects; nothing sent but Godot's own User-Agent, nothing
  else fetched, never retried. Only a clean 200 whose text is a version
  newer than this one (`UpdateNotice.newer`: numbers, so 3.10 beats 3.9; a
  release beats its own pre-releases) counts; offline, a timeout, an error
  page or garbage shows nothing.
- **The sign** (`src/ui/update_sign.gd`, `UpdateSign`): a tin sign strapped
  to the light pole in the title's top right, clear of the logo, the board and
  Mundell: NEW VERSION on its red band, `3.x.y OUT`, GIT IT, which lights on a
  plate with chasing bulbs and shells while picked. On Android its small
  print says to tap the download once it is down, that it goes over this
  one and the saves are kept. It is one more button on `TitleScreen`
  (`sign_button()`): up from the big plate or right from the office column
  with keys or a pad, down or left back to the plate; the mouse and a finger
  press it. CHECK FOR UPDATES off takes it down.
- **Picked:** `OS.shell_open` on the platform's download, the latest
  release's `CrazyLegsMundellRampage.apk` (Android) or
  `CrazyLegsMundellRampage_Setup.exe` (Windows); the title's note says
  DOWNLOADIN'. TAP IT (RUN IT) WHEN IT'S DONE.
- **Installing over the old copy** needs the same package name
  (`com.hickston.crazylegsmundell`), a version code that never goes down
  (`tools/version.gd`) and the same signing key; release.yml fails a `v*`
  tag's APK job without the `ANDROID_KEYSTORE_*` secrets, and its package
  step refuses another package name, a code under 3.11.0's or the throwaway
  key on a tag. The player's steps are in the README ("Updating").
- `tools/update_check.gd` (UPDATE CHECK OK, in check_all) holds all of it
  without the network; `tools/update_frames.gd -- out=<dir>` pictures the
  signs in a window (`docs/godot3d/update14/`).

Tried by hand once (2026-11-20): the real request from the engine (as 3.10.0
it found 3.11.0, as 3.11.0 nothing; one request each though asked twice) and
both download addresses (they lead to the latest release's files). Not
checked: an exported build, a real phone's download and install.

## HOW TO RAISE HELL (the CONTROLS page)

`ControlsScreen.rows_of(page)`: the keyboard page's rows name each key as
bound on the KEYS page (`{action}` in `MainState.CONTROL_ROWS`, filled by
`Lessons.key`); since pass 12 they say that USE also picks things up and
boots a hand, how to throw what you tote, the mouse wheel and the dynamite.
`onboard_check.gd` holds every row to its column (108 and 162 pixels).

## Menu text

The readable 7-pixel font where it fits, `SOFT` for second lines,
`Menu.FADED` a little brighter. Text draws with an outline
(`Canvas.OUTLINE`); SMALL TEXT draws the 5-pixel style in the 7-pixel letters
(`PixelType.clear_small`).

## A new menu screen

1. Write a `UiScreen` subclass in `src/ui/screens/` (buttons with
   `add_button`, or a `ZonedScreen`/`KeyedScreen` if its rules are keys).
2. Add its state to `UiRoot.SCREENS`.
3. Set `main.state` to that state to show it.
4. Run `--import` (a new `class_name`) and `tools/menu_touch_check.gd`.

See also [how_to_add.md](how_to_add.md#a-menu-screen).
