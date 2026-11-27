# AGENTS.md: making maps for Crazy Legs Mundell Rampage

For OpenAI Codex and any other coding agent working in this repository.

## The project

Crazy Legs Mundell Rampage is a 1997-style first-person shooter in the
spirit of Redneck Rampage (all art, sound and maps original), made in
Godot 4.7.2. The game is the Godot project in `godot/`. `CLAUDE.md` and
`docs/dev/` describe the code; you do not need them to make maps.

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
