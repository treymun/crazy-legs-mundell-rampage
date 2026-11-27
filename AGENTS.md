# AGENTS.md: working on Crazy Legs Mundell Rampage

For OpenAI Codex and any other coding agent working in this repository.

## The project

Crazy Legs Mundell Rampage is a 1997-style first-person shooter in the
spirit of Redneck Rampage (all art, sound and maps original), made in
Godot 4.7.2. The game is the Godot project in `godot/`.

- **Making maps:** the section below and MAP_AUTHORING.md are all you need.
- **Any other work on the game:** read `CLAUDE.md` first. It is the full
  working guide (layout, commands, the rules every change follows); the
  detail is in `docs/dev/` (its index is at the end of CLAUDE.md). Then see
  "Working on the rest of the game" at the end of this file.

## Making maps

**The guide is [MAP_AUTHORING.md](MAP_AUTHORING.md).** Read it first. The
full format reference is [docs/map_notes/t7.md](docs/map_notes/t7.md).
Copy from the worked examples: `godot/maps/feud.map.json` (deathmatch,
team deathmatch, search and destroy, hostage rescue) and
`godot/maps/shiloh.map.json` (one player and co-op).

A map is one JSON file, `godot/maps/<id>.map.json`. The loop is one
command:

```bash
GODOT=<path to the Godot 4.7.2 console executable>
export APPDATA=$TMP/clmr-scratch LOCALAPPDATA=$TMP/clmr-scratch/Local   # a scratch profile, always
"$GODOT" --headless --path godot --script res://tools/map.gd -- check <id>
```

Read `godot/maps/.check/<id>/report.md` and look at `sheet.png` in the same
folder. Fix every MUST FIX, then every SHOULD, and run it again until it
says PASS. `check <id> quick` is the fast loop (about 8 s).

The first time in a fresh checkout, build the packed assets (not
committed):

```bash
"$GODOT" --headless --path godot --script res://tools/pack_assets.gd
"$GODOT" --headless --path godot --import
"$GODOT" --headless --path godot --script res://tools/pack_assets.gd -- bake
git checkout -- godot/assets3d godot/icons    # drop line-ending churn the import makes
```

## Rules

- **Work on your own branch.** Never commit to or push `combat-overhaul` or
  `main`, never tag, never run `tools/release.gd`, never publish or deploy.
  The owner reviews and merges.
- **Scratch profile, always.** Every Godot run (headless or a window) runs
  with `APPDATA` and `LOCALAPPDATA` pointed at a scratch folder. Never read,
  write or delete the player's real profile (`%APPDATA%\Crazy Legs Mundell
  Rampage 3D\`). The map tools set a scratch profile themselves for
  `check`, `pictures` and `shot`.
- Never open, print or copy `.env`. Never run `git clean` or delete files
  you did not make.
- Everything original: no Redneck Rampage (or any other game's) art, maps
  or layouts, no real people, brands or businesses. Words on screen are
  short, upper case, in the county's voice. Keep the 1997 look: build from
  the kit, the tiles, props and foliage in `docs/map_catalog/`.
- Do not edit the campaign's chapters (`godot/tools/levels/*_plan.gd`,
  their `godot/data/*.json`) for map work.
- Never edit a built level (`godot/data/<id>.json`) by hand: change the
  source and `map build` it.

## Before handing a map over

1. `map check <id>` says **PASS** (full, not quick), and the sheet looks
   right: buildings where you meant, sites and starts where you meant.
2. `map build <id>`; commit the source, `godot/data/<id>.json` and
   `godot/maps/built.json` together.
3. If you listed it in the menus (MAP_AUTHORING.md, "Making a multiplayer
   map that ships in the game"), these pass, each with the scratch profile:
   `load_check.gd -- levels=<id>`, `prebake_check.gd` (after `pack_assets.gd
   -- bake`), `geometry_check.gd`, `view3d_check.gd`, `looks_map_check.gd`,
   `mode_check.gd`, `pacing_check.gd`, and `bot_check.gd` for a 5v5 map.
4. `check_all.gd -- quick jobs=4`, then the lint run in four shards:
   `check_all.gd -- lint shard=1/4 jobs=4` ... `shard=4/4 jobs=4`, each
   ending ALL CHECKS OK. Never run `check_all` without `jobs=`.
5. In your hand-over, give the map's id, its modes, the verdict, the
   report's numbers table (site walks for both sides) and anything you
   could not check (a person playing it, online play between two machines).

## Working on the rest of the game

Everything in "Rules" above holds for all work, plus these (CLAUDE.md has
the reasons):

- **Never spend paid credits.** Do not run the ElevenLabs voice tools
  (`scripts/audio_generator.py`), the Meshy model tools (`meshy/`) or any
  other paid API. If a task needs new voice lines or new 3D models, stop and
  say so in your hand-over.
- **The game code is strictly typed GDScript**, layers only call down, and
  files stay under 1,500 lines (gdlint). Edit tuning (`godot/data/tuning/`),
  not scripts, where a number is all that changes.
- **Gameplay randomness comes from `game.rng`**; new Game fields go in the
  snapshot field lists; saves are versioned (CLAUDE.md "Never forget").
- **Keep what works working.** The chapters, old saves and player maps must
  load and play as before unless the task is to change them. Run the
  campaign checks the area touches (`docs/dev/checks.md` lists them all).
- **Benchmarks are noisy.** Compare against the base back to back, several
  rounds, before calling anything slower or faster.
- Say plainly what you could not check: nobody on the agent side can listen
  to the audio, play by hand, or try a phone.

Before handing any change over: the checks for the area, then
`check_all.gd -- quick jobs=4`, then the four lint shards
(`check_all.gd -- lint shard=K/4 jobs=4`, K = 1..4), all with the scratch
profile and all ending ALL CHECKS OK. If a change moves the 3D view, take the
picture tour and run `compare_3d.gd` (CLAUDE.md "Commands"); rewrite a
reference only when the change is meant, and say which.

### Open jobs (pick one; one branch each)

- **Bigger player maps (half done):** branch `p16-usermap` has player maps
  with storeys, kit buildings, logic and looks. Still to do: the 10,000-
  mutation fuzz, the two-process online lobby test, the cost cap, and the
  save check (`docs/map_notes/t8.md` in that branch). The branch is local to
  the owner's PC (not pushed), in the main checkout.
- **The new MAP SHED** (in-game editor): height, ramps and roofs, whole
  buildings, logic, copy/paste/mirror, a 3D preview and a CHECK button that
  calls `src/map_review/`. Needs the player-map work above first.
- **List new multiplayer maps in the menus:** MAP_AUTHORING.md "Making a
  multiplayer map that ships in the game" (`Modes.SHOWDOWN_MAPS` / `ARENAS`,
  `TacticalScreens.MAP_LINES`, `lobby.cfg` `match_rows` and `mode_maps`).
- **Shots aimed up at a loft:** on the feedstore demo the bot emptied every
  gun at a billy in the hayloft from below and never hurt him, while he hit
  back. Find whether upward shots stop at a rail or deck edge (it may affect
  players too) and fix it with a check.
- **`geometry_check` can print OK when its map check script fails to
  compile.** Make a failure to load fail the check.
- **County Run's Hickston** (`godot/data/county_hickston.json`) lacks the
  pass-15 rodeo shortcut gate the campaign's Hickston has.
- Small model leftovers (no new models needed): the still buster's chop
  holds the axe across his chest instead of swinging it down-forward (a
  hand-made fire pose); the flagman's flag could ripple on the held-tail
  path the chain hand's chain uses.
