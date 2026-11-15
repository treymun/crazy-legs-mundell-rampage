# Menus and the HUD

The menu screens are Godot Controls in `godot/src/ui/`. The HUD still draws
with the Canvas helpers on the Godot 2D canvas (not Controls); see
[gameplay.md](gameplay.md#the-automap-canvas-and-sprites) for the two
canvases.

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
  menus as touch events.

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
