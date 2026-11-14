# County Run

COUNTY RUN is Crazy Legs Mundell Rampage's solo endless survival mode (new in
2.0.0-dev.41). Pick one of three big maps, roam freely while the county's
hands keep coming, pick up the XP they drop, level up, build your guns. Survival
time is the score; death ends the run. This file is the guide to running it,
testing it and adding to it. The code's own notes are in `CLAUDE.md`
("County Run"); test results are in `docs/county_run/test_results.md`.

## Launch it

- **Released game**: the EXE, installer, APK or the browser build. On the
  title pick **COUNTY RUN**, then a map (HICKSTON, THE QUARRY, GATOR BAYOU).
- **From this project folder** (Godot 4.7.2; on this PC
  `C:\Users\treym\OneDrive\Desktop\Tools\Godot_v4.7.2-stable_win64_console.exe`):

  ```
  godot --path godot                                   # the game; title -> COUNTY RUN
  godot --headless --path godot --script res://tools/pack_assets.gd    # after changing art
  ```

  In the Godot editor, open `godot/project.godot` and press Play.

## How it plays

- You start at level 1 with the **.38** and the **crowbar** in two of three
  weapon slots. Kills drop **XP** (spinning bottle caps: copper, silver,
  gold for bigger piles); walk near it and it floats in. It must be on your
  floor and in view: not through a wall, not from a deck above or below.
- Each **level up** stops the clock and the world and offers three cards.
  One is always an upgrade for the gun you had in hand when you levelled; a
  weapon card shows while a slot is free. **Every tenth level** (10, 20, 30...)
  offers three big **milestones** instead: a weapon change, a way to stay
  alive, a move. One pickup worth several levels offers each choice in turn.
- With three guns carried, a weapon card asks which to **swap out** and shows
  the upgrades that gun would lose. CANCEL goes back to the same three cards.
  General perks and milestones always stay.
- The county keeps coming: more and tougher with the minutes, an elite now and
  then, a short lull every minute and a half. Ammo and food drop sometimes.
- Elites wear a gold ELITE tag and a health bar; the HUD counts down a lull
  and warns when an elite is coming. Tips show on the cards in your first
  three runs (county.json `tips`).
- When you die: survival time, the map's personal best, highest level,
  kills, elites, XP, damage taken, best streak and your final build; RETRY,
  MAPS or TITLE.

**Controls** (as in the campaign): **1-3** pick a slot, the **wheel** or
`;` `'` (and the NEXT button on a phone) cycle carried guns, **R** reload,
**B** the build screen (the world waits), **E / SPACE / USE** is MUDSLIDE once
you have it. On the cards: **1-3**, arrows and ENTER, a click or a tap.

## The maps

Each County Run map is a plan built over a campaign chapter's ground
(`godot/tools/levels/county_<chapter>_plan.gd` with `county_kit.gd`): the
chapter builds, its story comes off (hands, pickups, stations, triggers, the
exit, the road back to the Crossroads, the boss arenas), every door is
unlocked and left open, then the plan cuts its new ways through, lays its
raised routes and names its landmarks.

| map | what changed for survival |
| --- | --- |
| HICKSTON (`county_hickston`) | the dry creek's south fence down (a loop instead of a dead end); the stockyard into the rodeo, the rodeo into the trailer court, the court into the motel strip; a footbridge over Main Street |
| THE QUARRY (`county_quarry`) | the weigh station opens into the lower cut's floor; a ramp from the cut yard down into the weigh station; the cut yard straight into the condenser yard; a steel catwalk over the flooded pit |
| GATOR BAYOU (`county_bayou`) | plank causeways over the deep channel west of the lagoon and out to the island from both shores; two raised boardwalks over the open shallows |

## Adding a survival map

1. Write `godot/tools/levels/county_<name>_plan.gd` like the three there:
   `make()` builds the base plan's builder, `build()` runs the base plan,
   then `Kit.strip(b, "county_<name>", "TITLE", "intro line")`, your changes,
   and returns the start `[x, y, angle]` (somewhere central with room).
   A map from scratch works too: any plan written with the level builder.
2. Cut ways through with `Kit.open_cells(b, x0, y0, x1, y1, Vector2i(like_x,
   like_y))` (the cells copy a neighbour's floor, ground and roof), then
   `Kit.clear_fixtures` and `Kit.clear_things` over them. Raised routes with
   `Geo.bridge`/`Geo.balcony` (gaps in the rails where stairs arrive) and
   `Geo.stairs` from the floor height at the stair's foot. Label landmarks with
   `b.label("NAME", x, y)`.
3. Build: `godot --headless --path godot --script res://tools/levels/build_level.gd -- county_<name> map=<png>`.
   To find exact cells, read `godot/data/county_<name>.json` (`solid`, `floor`,
   `ground`, `roof`, `width`).
4. Validate with the map tools through a throwaway source:
   `godot --headless --path godot --script res://tools/map.gd -- new zz_x base=county_<name>`,
   then `-- validate zz_x` (no errors), `-- render zz_x out=<dir> overlay=nav,unreachable`,
   and delete `godot/maps/zz_x.map.json` afterwards.
5. Add it to `data/tuning/county.json` `maps` (id, title, tag, blurb, the
   enemy `pool` as `[kind, from minute, weight]` and `elites`) and to
   `CountyData.MAP_IDS`. A chapter's own enemies need its art pack in the
   browser: add `"county_<name>": "art_<chapter>.bin"` to `Assets.CHAPTER_ART`
   (`CountyData.base_of` maps the id to the chapter's music).
6. Run `tools/county_check.gd` (it plays every map) and commit the plan,
   `data/county_<name>.json` and the json change.

## Adding a weapon

Any gun in `data/tuning/weapons.cfg` can be offered. In `county.json`
`weapons`, add an entry under its weapons.cfg name:

```json
"riot_pump": {"short": "RIOT PUMP", "plays": "SIX SHELLS, PUMP ACTION.", "kind": "shotgun",
              "reserve": 24, "upgrades": ["extra_buck", "tight_choke", "slam_load", "hot_loads"]}
```

`kind` is one of `pistol`, `shotgun`, `rifle`, `melee`, `explosive`, `auto`,
`launcher` (milestones and upgrades with `kinds` read it); `reserve` is the
spare ammo it comes with; `short` the HUD slot name; `plays` the card's line.

## Adding an upgrade or a perk

In `county.json` `upgrades` (on a weapon) or `perks` (the whole run):

```json
"hollow_point": {"name": "HOLLOW POINT", "ranks": 3, "per": 0.1,
                 "text": "+{v}% DAMAGE TO A VARMINT UNDER HALF HEALTH.", "trade": ""}
```

`ranks` is the cap, `per` what one rank adds; in `text` `{v}` is the value at
the rank offered (a share below 1 shows as a percentage; `"unit": "dec"` shows
one decimal), `{gun}` the weapon. Add its id to the weapons' `upgrades`
lists. Then make it do something in `godot/src/modes/county_moves.gd`
(`hit_amount` for damage on a hit, `hit_after` for what happens after one,
`fired` for each shot, `tick` for anything over time, `blast_tuning` for
blasts) or `county_build.gd` (`damage_scale`, `reload_scale`, `fire_scale`,
`spread_scale`, `reserve_cap` for plain number changes). Read its rank with
`CountyBuild.rank(f, gun, "hollow_point")` or `CountyBuild.perk_rank(f, id)`.
Existing values can be changed in the json alone.

## Adding a milestone ability

In `county.json` `milestones`:

```json
"hog_call": {"name": "HOG CALL", "kind": "move", "cooldown": 20.0,
             "text": "USE: EVERY VARMINT NEAR FREEZES FOR 2S. EVERY 20S.", "trade": ""}
```

`kind` decides its place in a milestone set: `weapon` (needs `"needs"`: a gun
name or a weapon kind carried), `survive`, `move`, or `spare` (offered when
the others run out; `"again": true` can be taken again). Write what it does
in `county_moves.gd`, reading `CountyBuild.has(f, "hog_call")`, and keep its
timers on the county feature (`godot/src/features/county_run.gd`, plain
values). The HUD's ability line is `CountyScreens.draw_hud`.

## Tuning

Everything on the cards and every number of the spawner and XP is in
`godot/data/tuning/county.json`: the XP curve (`xp`), the live-enemy cap,
spawn rate, lulls, elites, health growth (`spawn`), the starting kit
(`start`). A run started from the project folder reads the file again when it
changes.

## Tests

```
godot --headless --path godot --script res://tools/county_check.gd             # COUNTY CHECK OK (in CI)
godot --headless --path godot --script res://tools/menu_touch_check.gd         # MENU TOUCH OK (in CI)
godot --headless --path godot --script res://tools/county_play.gd -- md=out.md # long play tests
godot --path godot --audio-driver Dummy --resolution 1280x800 --script res://tools/county_frames.gd -- out=<dir>
godot --headless --path godot --script res://tools/check_all.gd -- lint        # everything
```

Nobody on the agent side could listen to the sound, play by hand or try a
phone; see the test results for what was checked and how.
