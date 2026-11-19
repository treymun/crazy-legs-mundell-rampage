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
- **Scaling:** the overlay is the 320x200 picture, scaled to the window by
  the display shader with whole, crisp pixels (INTEGER 8:5 keeps every pixel
  the same size) inside the phone's safe area, so the HUD scales with the
  picture on a phone and on a big screen.
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

## The parts

- **UiRoot** (`ui_root.gd`) is a Control the size of the canvas (320x200). It
  lives in the overlay SubViewport the display shader lays over the 3D view,
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
| `KeyedScreen` | setup, slots | drawing only; keys and pointer stay with `main_input.gd` |

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
| The 5v5 store, County Run's cards and end | their own taps (`TacticalScreens.tap`, `CountyInput.tap`) |

Not checked by hand: none of it has been tried on a real phone.

## Voice chat's pieces (pass 13)

Online voice chat ([multiplayer.md](multiplayer.md#voice-chat-pass-13)) adds:

- **Settings**, AUDIO page under VOICE CHAT ONLINE: VOICE CHAT (on), MICROPHONE
  (off), TALK (PUSH TO TALK or OPEN MIC), MIC SENSITIVITY (open mic's gate),
  VOICE CHAT VOLUME (80); the KEYS page's PUSH TO TALK (T). A pad talks with
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
