# Map check: feud

**PASS: nothing to fix. The NICE items are ideas.**

> THAT'LL DO. THAT'LL DO JUST FINE.

0 MUST FIX, 0 SHOULD, 2 NICE. The check took 11.3 s after Godot started.

How to read this: each item says where (map x, y and z: x east, y south, z up), what is wrong and how to fix it. Fix every MUST FIX (the map is broken without it), then the SHOULD items (it plays worse without them). NICE items are ideas. Then run the check again.

## MUST FIX (0)

Nothing.

## SHOULD (0)

Nothing.

## NICE (2)

1. **way** at (5.5, 20.5): The map has no objective and no exit: it was checked as a versus arena.
   - Fix: For a one-player map add a station (an objective) and an exit with shutdown naming it.
   - "NO JOB TO DO AND NO ROAD OUT. MUST BE A FIGHTIN' PIT."
2. **secrets** at (5.5, 20.5): The map has no secrets: no secret door and no stash off the way.
   - Fix: Hide a stash: a door with secret true into a small room with rounds or food, or a pickup tucked 8 or more steps off the way.
   - "NO SECRETS. HIDE A STASH SOMEWHERE A FELLA WOULDN'T LOOK."

## The numbers

| measure | value |
| --- | --- |
| arena heals | 3 |
| arena rounds | 4 |
| bare share | 0.04 |
| dead ends | 0 |
| dm spawns | 8 |
| hands | 0 |
| longest look | 19.4 |
| modes | deathmatch, team_deathmatch, bomb, hostage |
| nav ms | 53.4 |
| nodes | 2378 |
| nodes up | 298 |
| pickups | 8 |
| pieces | 236 |
| secret doors | 0 |
| site A attack steps | 42 |
| site A defend steps | 23 |
| site B attack steps | 43 |
| site B defend steps | 26 |
| sites uneven | 1.02 |
| stashes | 0 |
| stations | 0 |
| teams apart steps | 47 |
| wall rows | 923 |

## Routes walked (a player's body, every door open)

| route | result | seconds | walked |
| --- | --- | --- | --- |
| spawn_to_shells_w | reached | 2.13 | 8.6 |
| spawn_to_shells_e | reached | 9.18 | 37.42 |
| spawn_to_bullets_n | reached | 6.25 | 25.41 |
| spawn_to_bullets_s | reached | 5.87 | 23.81 |
| spawn_to_rinds_n | reached | 4.0 | 16.2 |
| spawn_to_rinds_s | reached | 4.13 | 16.73 |
| spawn_to_beer_mid | reached | 6.63 | 27.0 |
| spawn_to_rifle_mid | reached | 5.37 | 21.64 |

## Pictures

Everything on one sheet: `sheet.png`

- plan from above: `feud_plan.png`
- plan from above: `feud_floor0_z0_0.png`
- plan from above: `feud_floor1_z2_6.png`
- plan from above: `feud_floor2_z7_9.png`
- feud_start: `feud_start_fx.png` (the start, looking along the way)
- feud_high_1: `feud_high_1_fx.png` (from one of the highest places to stand)
- feud_high_2: `feud_high_2_fx.png` (from one of the highest places to stand)
- feud_deck_barn_loft: `feud_deck_barn_loft_fx.png` (on the deck barn_loft)
- feud_deck_store_roof_b: `feud_deck_store_roof_b_fx.png` (on the deck store_roof_b)
- feud_deck_store_roof_a: `feud_deck_store_roof_a_fx.png` (on the deck store_roof_a)
- feud_place_the_crossing: `feud_place_the_crossing_fx.png` (the middle of THE CROSSING)
- feud_place_site_a__gas_station: `feud_place_site_a__gas_station_fx.png` (the middle of SITE A  GAS STATION)
- feud_place_site_b__the_barn: `feud_place_site_b__the_barn_fx.png` (the middle of SITE B  THE BARN)
