# Progress: audio, main-menu and settings overhaul

Branch `audio-menu-overhaul`. Read this, `git log`, `audio_src/manifest.json`
and `python scripts/audio_generator.py status` before continuing.

## State (updated as work lands)

| Step | State |
| --- | --- |
| Billing verified, ledger and 80,000-credit ceiling enforced in tooling | done |
| Cue inventory (301 active, 23 unused, 2 missing) | done — `audio_src/cue_inventory.json` |
| Reference measurements and creative targets | done — `audio_src/DIRECTION.md` |
| Calibration set and refinements | done |
| Effect sources generated | IN PROGRESS |
| Voices designed and lines generated | pending |
| Twelve chapter tracks, tally tune | 1 of 13 |
| Local finishing, manifest, validation | pipeline done; rerun when sources are complete |
| Godot: packer, title/tally as Ogg, menu-theme resume | done |
| Title screen and settings rebuilt | done; see "Front end" |
| Regression runs, screenshots, demo | pending |
| Handoff, push, CI | pending |

## Exact next action

See the bottom of this file ("Resume here").

## Decisions that are easy to get wrong

* **Credits come from the plan balance.** The Creator plan has overage switched
  off (`can_extend_character_limit` false), so no request can bill dollars.
  Measured cost: about 11 credits/s for effects, 13.8/s for music. The
  account's counter lags a request by up to a minute, so the ledger books the
  expected cost and `reconcile` trues it up against the account.
* **The Python game is untouched.** Its `assets/wav` and `assets/music` still
  feed the Python build. The Godot build now takes sound from
  `audio_src/final/sfx` and `godot/assets/music`.
* **The effect bank holds only cues the runtime plays** (manifest-driven). The
  old bank also packed 11 mono copies of the music and 12 dead effects: 38 MB.
* **Cue names, save keys, bookmarks and settings keys are unchanged.** New cue
  names: `menu_back`, `room_cow_launcher`, `room_teat_gun` (the last two were
  requested by the runtime and silently missing).
* **Cue lengths**: timing-critical families (reloads, wind-up warnings, equip,
  dry fire, footsteps) keep the length gameplay was tuned to; reports,
  explosions and deaths get a natural tail.
* **Levels**: each finished cue is matched to the loudness of the cue it
  replaces (within 6 dB of its family's level), so the existing mix balance,
  `REPORT_GAIN`, priorities and ducking still hold.
* **Menu theme**: `audio_src/supplied/menu_theme.mp3` is
  `Crazy_Legs_Mundell_Redneck_Rampage_Edition.mp3` from the author's Downloads
  folder — an assumption; two other candidates were there. Swap the file and
  run `python scripts/audio_build.py --music` to change it.
* **Menu music** now plays on every menu, including the pause menu, and keeps
  its place; the chapter track keeps its bookmark. (The Python original was
  silent while paused.)

## Front end

`godot/src/menu.gd` holds the layout of the title and settings screens as
rectangles in 320x200 space; drawing and pointer hit tests read the same data.
`godot/src/main.gd` keeps the state machine and every stored key. Supporting
art is drawn by `scripts/build_menu_art.py` into `assets/art/menu_*.png`.

## Resume here

1. `python scripts/audio_generator.py status --reconcile`
2. `python scripts/audio_produce.py --sfx` (skips what exists)
3. design voices (`audio_src/voices.json`), `--voices`, then `--music`
4. `python scripts/audio_build.py`, `--check`, `python scripts/build_godot_data.py`
5. Godot checks (README, "The Godot build"), screenshots, demo, push.
