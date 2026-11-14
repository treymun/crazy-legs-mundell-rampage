# Map catalog

Made by `godot --headless --path godot --script res://tools/map.gd -- catalog`; do not edit by hand. 1 map unit = 1 cell; eye .95 over a floor; door 1.85; step .245; body radius .2, height 1.12.

## Components (object types)

| type | cells | required | what it is |
| --- | --- | --- | --- |
| `yard` | yes | rect, floor | Open ground under the sky over whole cells. |
| `room` | yes | rect, floor | Open floor under a roof `roof` high (cells); walls come from solid cells round it. |
| `building` | yes | rect | A ring of wall cells round a room; cut doors with `door`. |
| `solid` | yes | rect, tile | Solid cells: a wall, hedge, rock or fence `top` high. |
| `fence` | yes | rect | A fence of solid cells (breakable where breakables.cfg says). |
| `paint` | yes | rect, floor | A floor tile over cells (a path, a rug, mud). |
| `raise` | yes | rect, ground | Cells' ground raised (or sunk) to `ground` (a step up needs <= .245). |
| `light` | yes | at | A pool of lamp light on the cells round `at`. |
| `door` | yes | cell | A door in a wall cell (a grid door: 1 cell wide, 1.85 high). |
| `gap` | yes | cell, from | An open doorway in a wall cell, no door. |
| `pane` | yes | cell | A breakable glass pane across a cell. |
| `deck` | no | rect, top | A floor walked on and under (a loft, a landing, a catwalk), `thick` thick. |
| `block` | no | rect, top | A solid block standing on the ground (a plinth, a dock, a stage), walked on. |
| `ramp` | no | rect, from, to, toward | A slope from z `from` up to `to` toward n/e/s/w (solid to the ground unless `thick`). |
| `stairs` | no | rect, from, to, toward | Stairs from `from` up to `to` toward n/e/s/w, treads `rise` high at most. |
| `wall` | no | a, b | A free wall a to b; `openings` [{id, at, width, sill, head}] cut doors and windows. |
| `rail` | no | a, b | A rail standing on z: stops bodies, not looks or shots. |
| `cover` | no | a, b | Low solid cover a to b: stops bodies, looks and shots under its top. |
| `balcony` | no | rect, top, open | A deck railed on the `open` sides (n, e, s, w); `gaps` [[side, from, to]]. |
| `bridge` | no | rect, top | A deck across a gap at `top`, railed along its long sides; walk under it. |
| `ceiling` | no | rect, z | A flat surface overhead (an overhang, a porch roof, an upper room's ceiling). |
| `room_poly` | yes | points, floor | A room of any outline, a wall on each edge; `openings` [[edge, {at, width}]]. |
| `corridor` | yes | points, floor | A roofed passage `width` cells wide along a path of cell centres (straight legs, n/s/e/w). |
| `fixture` | no | rect, top | A box of furniture (a counter, a crate stack): stops bodies; not walked on. |
| `prop` | no | name, at | A modelled prop (town_props.json names) standing at `at`. |
| `sign` | no | image, at, height | A flat picture standing at `at` (a sign, a board). |
| `enemy` | no | kind, at | A hand of `kind` (enemies.cfg) standing at `at`, on the floor at or under z. |
| `pickup` | no | name, at | A pickup lying at `at`. |
| `station` | no | at, label | An objective: a quest station used at `at`; `opens` door cells; `prop` a town_quest_<name>. |
| `exit` | no | at, label | The level's exit (extraction) at `at`, open once `shutdown` is done. |
| `spawn_point` | no | at | A named place a player or bot can start a playtest from (and a versus spawn). |
| `label` | no | text, at | A name on the automap. |
| `allow_overlap` | no | objects, reason | Says two or more objects overlap on purpose (validate stops calling it an error). |

## Tiles (materials)

| | id | notes |
| --- | --- | --- |
| ![](thumbs/tile_wood.png) | `wood` | strikes as wood, footstep gravel, variants wood |
| ![](thumbs/tile_barn.png) | `barn` | strikes as wood, footstep gravel, variants barn, barn_win, barn_lit, barn_brk |
| ![](thumbs/tile_tin.png) | `tin` | strikes as tin, footstep gravel, variants tin, tin_win, tin_lit, tin_brk |
| ![](thumbs/tile_brick.png) | `brick` | strikes as brick, footstep gravel, variants brick, brick_win, brick_lit, brick_brk |
| ![](thumbs/tile_plaster.png) | `plaster` | strikes as stone, footstep gravel, variants plaster, plaster_win, plaster_lit, plaster_brk |
| ![](thumbs/tile_tile.png) | `tile` | strikes as stone, footstep gravel, variants tile |
| ![](thumbs/tile_mirror.png) | `mirror` | strikes as glass, footstep gravel, variants mirror |
| ![](thumbs/tile_floor_tile.png) | `floor_tile` | strikes as stone, footstep tile, variants floor_tile |
| ![](thumbs/tile_concrete.png) | `concrete` | strikes as stone, footstep tile, variants concrete |
| ![](thumbs/tile_dirt.png) | `dirt` | strikes as dirt, footstep mud, variants dirt |
| ![](thumbs/tile_tracks.png) | `tracks` | strikes as dirt, footstep mud, variants tracks |
| ![](thumbs/tile_grass.png) | `grass` | strikes as dirt, footstep grass, variants grass |
| ![](thumbs/tile_asphalt.png) | `asphalt` | strikes as dirt, footstep gravel, variants asphalt |
| ![](thumbs/tile_road.png) | `road` | strikes as dirt, footstep gravel, variants road |
| ![](thumbs/tile_door.png) | `door` | strikes as wood, footstep gravel, variants door |
| ![](thumbs/tile_gate.png) | `gate` | strikes as steel, footstep gravel, variants gate |
| ![](thumbs/tile_liquor.png) | `liquor` | strikes as wood, footstep gravel, variants liquor |
| ![](thumbs/tile_eat.png) | `eat` | strikes as wood, footstep gravel, variants eat |
| ![](thumbs/tile_restroom.png) | `restroom` | strikes as wood, footstep gravel, variants restroom |
| ![](thumbs/tile_barnsign.png) | `barnsign` | strikes as wood, footstep gravel, variants barnsign |
| ![](thumbs/tile_warning.png) | `warning` | strikes as wood, footstep gravel, variants warning |
| ![](thumbs/tile_wanted.png) | `wanted` | strikes as wood, footstep gravel, variants wanted |
| ![](thumbs/tile_crack.png) | `crack` | strikes as wood, footstep gravel, variants crack |
| ![](thumbs/tile_ship.png) | `ship` | strikes as steel, footstep gravel, variants ship |
| ![](thumbs/tile_ceiling.png) | `ceiling` | strikes as wood, footstep gravel, variants ceiling |
| ![](thumbs/tile_joists.png) | `joists` | strikes as wood, footstep gravel, variants joists |
| ![](thumbs/tile_tavern.png) | `tavern` | strikes as stone, footstep gravel, variants tavern |
| ![](thumbs/tile_shelves.png) | `shelves` | strikes as wood, footstep gravel, variants shelves |
| ![](thumbs/tile_fascia.png) | `fascia` | strikes as wood, footstep gravel, variants fascia |
| ![](thumbs/tile_window.png) | `window` | strikes as glass, footstep gravel, variants window |
| ![](thumbs/tile_cinder.png) | `cinder` | strikes as stone, footstep gravel, variants cinder, cinder_win, cinder_lit, cinder_brk |
| ![](thumbs/tile_porch.png) | `porch` | strikes as wood, footstep wood, variants porch |
| ![](thumbs/tile_counter.png) | `counter` | strikes as wood, footstep gravel, variants counter |
| ![](thumbs/tile_counter_top.png) | `counter_top` | strikes as stone, footstep gravel, variants counter_top |
| ![](thumbs/tile_crate_side.png) | `crate_side` | strikes as wood, footstep gravel, variants crate_side |
| ![](thumbs/tile_steel_mesh.png) | `steel_mesh` | strikes as mesh, footstep gravel, variants steel_mesh |
| ![](thumbs/tile_shoulder.png) | `shoulder` | strikes as dirt, footstep mud, variants shoulder |
| ![](thumbs/tile_gravel.png) | `gravel` | strikes as dirt, footstep gravel, variants gravel |
| ![](thumbs/tile_stockyard.png) | `stockyard` | strikes as wood, footstep gravel, variants stockyard |
| ![](thumbs/tile_trailer.png) | `trailer` | strikes as tin, footstep gravel, variants trailer, trailer_brk |
| ![](thumbs/tile_trailer_window.png) | `trailer_window` | strikes as tin, footstep gravel, variants trailer_window |
| ![](thumbs/tile_service.png) | `service` | strikes as steel, footstep gravel, variants service |
| ![](thumbs/tile_dispatch.png) | `dispatch` | strikes as wood, footstep gravel, variants dispatch |
| ![](thumbs/tile_feed.png) | `feed` | strikes as wood, footstep gravel, variants feed |
| ![](thumbs/tile_orchard.png) | `orchard` | strikes as dirt, footstep grass, variants orchard |
| ![](thumbs/tile_bleachers.png) | `bleachers` | strikes as wood, footstep gravel, variants bleachers |
| ![](thumbs/tile_creek.png) | `creek` | strikes as water, footstep water, variants creek |
| ![](thumbs/tile_office_wall.png) | `office_wall` | strikes as stone, footstep gravel, variants office_wall, office_wall_win, office_wall_lit, office_wall_brk |
| ![](thumbs/tile_glazing.png) | `glazing` | strikes as glass, footstep gravel, variants glazing |
| ![](thumbs/tile_powder_panel.png) | `powder_panel` | strikes as tin, footstep gravel, variants powder_panel |
| ![](thumbs/tile_stanky_marquee.png) | `stanky_marquee` | strikes as wood, footstep gravel, variants stanky_marquee |
| ![](thumbs/tile_feed_marquee.png) | `feed_marquee` | strikes as wood, footstep gravel, variants feed_marquee |
| ![](thumbs/tile_cable.png) | `cable` | strikes as wood, footstep gravel, variants cable |
| ![](thumbs/tile_oil_asphalt.png) | `oil_asphalt` | strikes as dirt, footstep gravel, variants oil_asphalt |
| ![](thumbs/tile_hedgerow.png) | `hedgerow` | strikes as brush, footstep gravel, variants hedgerow |
| ![](thumbs/tile_fair_booth.png) | `fair_booth` | strikes as wood, footstep gravel, variants fair_booth, fair_booth_win, fair_booth_lit, fair_booth_brk |
| ![](thumbs/tile_fair_iron.png) | `fair_iron` | strikes as steel, footstep gravel, variants fair_iron, fair_iron_win, fair_iron_lit, fair_iron_brk |
| ![](thumbs/tile_fair_gravel.png) | `fair_gravel` | strikes as dirt, footstep gravel, variants fair_gravel |
| ![](thumbs/tile_fair_gate.png) | `fair_gate` | strikes as steel, footstep gravel, variants fair_gate |
| ![](thumbs/tile_fair_prize.png) | `fair_prize` | strikes as wood, footstep gravel, variants fair_prize |
| ![](thumbs/tile_mill_tin.png) | `mill_tin` | strikes as tin, footstep gravel, variants mill_tin, mill_tin_win, mill_tin_lit, mill_tin_brk |
| ![](thumbs/tile_mill_water.png) | `mill_water` | strikes as water, footstep water, variants mill_water |
| ![](thumbs/tile_mill_log.png) | `mill_log` | strikes as timber, footstep gravel, variants mill_log |
| ![](thumbs/tile_mill_oil.png) | `mill_oil` | strikes as dirt, footstep gravel, variants mill_oil |
| ![](thumbs/tile_mill_pump.png) | `mill_pump` | strikes as steel, footstep gravel, variants mill_pump |
| ![](thumbs/tile_mill_grit.png) | `mill_grit` | strikes as dirt, footstep gravel, variants mill_grit |
| ![](thumbs/tile_route_hickston.png) | `route_hickston` | strikes as dirt, footstep gravel, variants route_hickston |
| ![](thumbs/tile_route_fair.png) | `route_fair` | strikes as dirt, footstep gravel, variants route_fair |
| ![](thumbs/tile_route_sawmill.png) | `route_sawmill` | strikes as dirt, footstep gravel, variants route_sawmill |
| ![](thumbs/tile_route_quarry.png) | `route_quarry` | strikes as dirt, footstep gravel, variants route_quarry |
| ![](thumbs/tile_route_hub.png) | `route_hub` | strikes as dirt, footstep gravel, variants route_hub |
| ![](thumbs/tile_route_closed.png) | `route_closed` | strikes as dirt, footstep gravel, variants route_closed |
| ![](thumbs/tile_quarry_face.png) | `quarry_face` | strikes as stone, footstep gravel, variants quarry_face |
| ![](thumbs/tile_quarry_dust.png) | `quarry_dust` | strikes as dirt, footstep gravel, variants quarry_dust |
| ![](thumbs/tile_quarry_iron.png) | `quarry_iron` | strikes as steel, footstep gravel, variants quarry_iron, quarry_iron_win, quarry_iron_lit, quarry_iron_brk |
| ![](thumbs/tile_quarry_copper.png) | `quarry_copper` | strikes as steel, footstep gravel, variants quarry_copper |
| ![](thumbs/tile_quarry_shed.png) | `quarry_shed` | strikes as wood, footstep gravel, variants quarry_shed, quarry_shed_win, quarry_shed_lit, quarry_shed_brk |
| ![](thumbs/tile_feed_wash.png) | `feed_wash` | strikes as wood, footstep gravel, variants feed_wash |
| ![](thumbs/tile_fair_marquee.png) | `fair_marquee` | strikes as wood, footstep gravel, variants fair_marquee |
| ![](thumbs/tile_route_threshold.png) | `route_threshold` | strikes as dirt, footstep gravel, variants route_threshold |
| ![](thumbs/tile_hub_patch.png) | `hub_patch` | strikes as dirt, footstep gravel, variants hub_patch |
| ![](thumbs/tile_hub_service_wall.png) | `hub_service_wall` | strikes as stone, footstep gravel, variants hub_service_wall, hub_service_wall_win, hub_service_wall_lit |
| ![](thumbs/tile_hub_runoff.png) | `hub_runoff` | strikes as water, footstep gravel, variants hub_runoff |
| ![](thumbs/tile_hub_screen.png) | `hub_screen` | strikes as glass, footstep gravel, variants hub_screen |
| ![](thumbs/tile_hub_tank_shell.png) | `hub_tank_shell` | strikes as steel, footstep gravel, variants hub_tank_shell |
| ![](thumbs/tile_detail_wall_bar_wainscot.png) | `detail_wall_bar_wainscot` | strikes as stone, footstep gravel, variants detail_wall_bar_wainscot |
| ![](thumbs/tile_detail_wall_garage_courses.png) | `detail_wall_garage_courses` | strikes as brick, footstep gravel, variants detail_wall_garage_courses |
| ![](thumbs/tile_detail_wall_feed_pen_boards.png) | `detail_wall_feed_pen_boards` | strikes as wood, footstep gravel, variants detail_wall_feed_pen_boards |
| ![](thumbs/tile_detail_wall_raffle_stripes.png) | `detail_wall_raffle_stripes` | strikes as wood, footstep gravel, variants detail_wall_raffle_stripes |
| ![](thumbs/tile_detail_wall_prize_skirting.png) | `detail_wall_prize_skirting` | strikes as wood, footstep gravel, variants detail_wall_prize_skirting |
| ![](thumbs/tile_detail_wall_kiln_patches.png) | `detail_wall_kiln_patches` | strikes as tin, footstep gravel, variants detail_wall_kiln_patches |
| ![](thumbs/tile_detail_wall_rain_sheets.png) | `detail_wall_rain_sheets` | strikes as tin, footstep gravel, variants detail_wall_rain_sheets |
| ![](thumbs/tile_detail_wall_chalk_cut.png) | `detail_wall_chalk_cut` | strikes as stone, footstep gravel, variants detail_wall_chalk_cut |
| ![](thumbs/tile_detail_wall_copper_seams.png) | `detail_wall_copper_seams` | strikes as steel, footstep gravel, variants detail_wall_copper_seams |
| ![](thumbs/tile_detail_wall_shed_repair.png) | `detail_wall_shed_repair` | strikes as tin, footstep gravel, variants detail_wall_shed_repair |
| ![](thumbs/tile_detail_wall_approach_fence.png) | `detail_wall_approach_fence` | strikes as wood, footstep gravel, variants detail_wall_approach_fence |
| ![](thumbs/tile_barn_win.png) | `barn_win` | strikes as wood, footstep gravel, variants barn, barn_win, barn_lit, barn_brk |
| ![](thumbs/tile_barn_lit.png) | `barn_lit` | strikes as wood, footstep gravel, variants barn, barn_win, barn_lit, barn_brk |
| ![](thumbs/tile_tin_win.png) | `tin_win` | strikes as tin, footstep gravel, variants tin, tin_win, tin_lit, tin_brk |
| ![](thumbs/tile_tin_lit.png) | `tin_lit` | strikes as tin, footstep gravel, variants tin, tin_win, tin_lit, tin_brk |
| ![](thumbs/tile_brick_win.png) | `brick_win` | strikes as brick, footstep gravel, variants brick, brick_win, brick_lit, brick_brk |
| ![](thumbs/tile_brick_lit.png) | `brick_lit` | strikes as brick, footstep gravel, variants brick, brick_win, brick_lit, brick_brk |
| ![](thumbs/tile_plaster_win.png) | `plaster_win` | strikes as stone, footstep gravel, variants plaster, plaster_win, plaster_lit, plaster_brk |
| ![](thumbs/tile_plaster_lit.png) | `plaster_lit` | strikes as stone, footstep gravel, variants plaster, plaster_win, plaster_lit, plaster_brk |
| ![](thumbs/tile_cinder_win.png) | `cinder_win` | strikes as stone, footstep gravel, variants cinder, cinder_win, cinder_lit, cinder_brk |
| ![](thumbs/tile_cinder_lit.png) | `cinder_lit` | strikes as stone, footstep gravel, variants cinder, cinder_win, cinder_lit, cinder_brk |
| ![](thumbs/tile_office_wall_win.png) | `office_wall_win` | strikes as stone, footstep gravel, variants office_wall, office_wall_win, office_wall_lit, office_wall_brk |
| ![](thumbs/tile_office_wall_lit.png) | `office_wall_lit` | strikes as stone, footstep gravel, variants office_wall, office_wall_win, office_wall_lit, office_wall_brk |
| ![](thumbs/tile_fair_booth_win.png) | `fair_booth_win` | strikes as wood, footstep gravel, variants fair_booth, fair_booth_win, fair_booth_lit, fair_booth_brk |
| ![](thumbs/tile_fair_booth_lit.png) | `fair_booth_lit` | strikes as wood, footstep gravel, variants fair_booth, fair_booth_win, fair_booth_lit, fair_booth_brk |
| ![](thumbs/tile_fair_iron_win.png) | `fair_iron_win` | strikes as steel, footstep gravel, variants fair_iron, fair_iron_win, fair_iron_lit, fair_iron_brk |
| ![](thumbs/tile_fair_iron_lit.png) | `fair_iron_lit` | strikes as steel, footstep gravel, variants fair_iron, fair_iron_win, fair_iron_lit, fair_iron_brk |
| ![](thumbs/tile_mill_tin_win.png) | `mill_tin_win` | strikes as tin, footstep gravel, variants mill_tin, mill_tin_win, mill_tin_lit, mill_tin_brk |
| ![](thumbs/tile_mill_tin_lit.png) | `mill_tin_lit` | strikes as tin, footstep gravel, variants mill_tin, mill_tin_win, mill_tin_lit, mill_tin_brk |
| ![](thumbs/tile_quarry_iron_win.png) | `quarry_iron_win` | strikes as steel, footstep gravel, variants quarry_iron, quarry_iron_win, quarry_iron_lit, quarry_iron_brk |
| ![](thumbs/tile_quarry_iron_lit.png) | `quarry_iron_lit` | strikes as steel, footstep gravel, variants quarry_iron, quarry_iron_win, quarry_iron_lit, quarry_iron_brk |
| ![](thumbs/tile_quarry_shed_win.png) | `quarry_shed_win` | strikes as wood, footstep gravel, variants quarry_shed, quarry_shed_win, quarry_shed_lit, quarry_shed_brk |
| ![](thumbs/tile_quarry_shed_lit.png) | `quarry_shed_lit` | strikes as wood, footstep gravel, variants quarry_shed, quarry_shed_win, quarry_shed_lit, quarry_shed_brk |
| ![](thumbs/tile_hub_service_wall_win.png) | `hub_service_wall_win` | strikes as stone, footstep gravel, variants hub_service_wall, hub_service_wall_win, hub_service_wall_lit |
| ![](thumbs/tile_hub_service_wall_lit.png) | `hub_service_wall_lit` | strikes as stone, footstep gravel, variants hub_service_wall, hub_service_wall_win, hub_service_wall_lit |
| ![](thumbs/tile_trim_foundation.png) | `trim_foundation` | strikes as brick, footstep gravel, variants trim_foundation |
| ![](thumbs/tile_trim_eave.png) | `trim_eave` | strikes as wood, footstep gravel, variants trim_eave |
| ![](thumbs/tile_corn.png) | `corn` | strikes as brush, footstep gravel, variants corn |
| ![](thumbs/tile_track_dirt.png) | `track_dirt` | strikes as dirt, footstep mud, variants track_dirt |
| ![](thumbs/tile_track_chalk.png) | `track_chalk` | strikes as dirt, footstep mud, variants track_chalk |
| ![](thumbs/tile_derby_mud.png) | `derby_mud` | strikes as dirt, footstep mud, variants derby_mud |
| ![](thumbs/tile_junk_ground.png) | `junk_ground` | strikes as dirt, footstep gravel, variants junk_ground |
| ![](thumbs/tile_diner_checker.png) | `diner_checker` | strikes as stone, footstep tile, variants diner_checker |
| ![](thumbs/tile_crash_wall.png) | `crash_wall` | strikes as stone, footstep gravel, variants crash_wall |
| ![](thumbs/tile_tire_wall.png) | `tire_wall` | strikes as rubber, footstep gravel, variants tire_wall |
| ![](thumbs/tile_junk_stack.png) | `junk_stack` | strikes as steel, footstep gravel, variants junk_stack |
| ![](thumbs/tile_garage_door.png) | `garage_door` | strikes as tin, footstep gravel, variants garage_door |
| ![](thumbs/tile_grandstand_riser.png) | `grandstand_riser` | strikes as stone, footstep gravel, variants grandstand_riser |
| ![](thumbs/tile_speedway_marquee.png) | `speedway_marquee` | strikes as wood, footstep gravel, variants speedway_marquee |
| ![](thumbs/tile_diner_steel.png) | `diner_steel` | strikes as steel, footstep gravel, variants diner_steel, diner_steel_win, diner_steel_lit, diner_steel_brk |
| ![](thumbs/tile_diner_steel_win.png) | `diner_steel_win` | strikes as steel, footstep gravel, variants diner_steel, diner_steel_win, diner_steel_lit, diner_steel_brk |
| ![](thumbs/tile_diner_steel_lit.png) | `diner_steel_lit` | strikes as steel, footstep gravel, variants diner_steel, diner_steel_win, diner_steel_lit, diner_steel_brk |
| ![](thumbs/tile_checker_band.png) | `checker_band` | strikes as stone, footstep gravel, variants checker_band |
| ![](thumbs/tile_bayou_water.png) | `bayou_water` | strikes as water, footstep water, variants bayou_water |
| ![](thumbs/tile_bayou_deep.png) | `bayou_deep` | strikes as water, footstep water, variants bayou_deep |
| ![](thumbs/tile_bayou_planks.png) | `bayou_planks` | strikes as wood, footstep wood, variants bayou_planks |
| ![](thumbs/tile_bayou_mud.png) | `bayou_mud` | strikes as dirt, footstep mud, variants bayou_mud |
| ![](thumbs/tile_bayou_marsh.png) | `bayou_marsh` | strikes as dirt, footstep grass, variants bayou_marsh |
| ![](thumbs/tile_bayou_stilts.png) | `bayou_stilts` | strikes as timber, footstep gravel, variants bayou_stilts |
| ![](thumbs/tile_bayou_bank.png) | `bayou_bank` | strikes as dirt, footstep gravel, variants bayou_bank |
| ![](thumbs/tile_bayou_cypress.png) | `bayou_cypress` | strikes as timber, footstep gravel, variants bayou_cypress |
| ![](thumbs/tile_bayou_tin.png) | `bayou_tin` | strikes as tin, footstep gravel, variants bayou_tin, bayou_tin_win, bayou_tin_lit, bayou_tin_brk |
| ![](thumbs/tile_bayou_shack.png) | `bayou_shack` | strikes as wood, footstep gravel, variants bayou_shack, bayou_shack_win, bayou_shack_lit, bayou_shack_brk |
| ![](thumbs/tile_bayou_cannery.png) | `bayou_cannery` | strikes as stone, footstep gravel, variants bayou_cannery, bayou_cannery_win, bayou_cannery_lit, bayou_cannery_brk |
| ![](thumbs/tile_bayou_juke.png) | `bayou_juke` | strikes as wood, footstep gravel, variants bayou_juke |
| ![](thumbs/tile_bayou_pen.png) | `bayou_pen` | strikes as mesh, footstep gravel, variants bayou_pen |
| ![](thumbs/tile_bayou_reeds.png) | `bayou_reeds` | strikes as brush, footstep gravel, variants bayou_reeds |
| ![](thumbs/tile_bayou_bridge.png) | `bayou_bridge` | strikes as wood, footstep gravel, variants bayou_bridge |
| ![](thumbs/tile_bayou_juke_marquee.png) | `bayou_juke_marquee` | strikes as wood, footstep gravel, variants bayou_juke_marquee |
| ![](thumbs/tile_bayou_bait_neon.png) | `bayou_bait_neon` | strikes as wood, footstep gravel, variants bayou_bait_neon |
| ![](thumbs/tile_bayou_tin_win.png) | `bayou_tin_win` | strikes as tin, footstep gravel, variants bayou_tin, bayou_tin_win, bayou_tin_lit, bayou_tin_brk |
| ![](thumbs/tile_bayou_tin_lit.png) | `bayou_tin_lit` | strikes as tin, footstep gravel, variants bayou_tin, bayou_tin_win, bayou_tin_lit, bayou_tin_brk |
| ![](thumbs/tile_bayou_shack_win.png) | `bayou_shack_win` | strikes as wood, footstep gravel, variants bayou_shack, bayou_shack_win, bayou_shack_lit, bayou_shack_brk |
| ![](thumbs/tile_bayou_shack_lit.png) | `bayou_shack_lit` | strikes as wood, footstep gravel, variants bayou_shack, bayou_shack_win, bayou_shack_lit, bayou_shack_brk |
| ![](thumbs/tile_bayou_cannery_win.png) | `bayou_cannery_win` | strikes as stone, footstep gravel, variants bayou_cannery, bayou_cannery_win, bayou_cannery_lit, bayou_cannery_brk |
| ![](thumbs/tile_bayou_cannery_lit.png) | `bayou_cannery_lit` | strikes as stone, footstep gravel, variants bayou_cannery, bayou_cannery_win, bayou_cannery_lit, bayou_cannery_brk |
| ![](thumbs/tile_ship_hull.png) | `ship_hull` | strikes as steel, footstep gravel, variants ship_hull |
| ![](thumbs/tile_ship_tin.png) | `ship_tin` | strikes as tin, footstep gravel, variants ship_tin |
| ![](thumbs/tile_ship_rib.png) | `ship_rib` | strikes as steel, footstep gravel, variants ship_rib |
| ![](thumbs/tile_ship_panel.png) | `ship_panel` | strikes as steel, footstep gravel, variants ship_panel |
| ![](thumbs/tile_ship_core.png) | `ship_core` | strikes as steel, footstep gravel, variants ship_core |
| ![](thumbs/tile_ship_screen.png) | `ship_screen` | strikes as glass, footstep gravel, variants ship_screen |
| ![](thumbs/tile_ship_deck.png) | `ship_deck` | strikes as steel, footstep tile, variants ship_deck |
| ![](thumbs/tile_ship_grate.png) | `ship_grate` | strikes as steel, footstep tile, variants ship_grate |
| ![](thumbs/tile_ship_ceiling.png) | `ship_ceiling` | strikes as steel, footstep gravel, variants ship_ceiling |
| ![](thumbs/tile_ship_door.png) | `ship_door` | strikes as steel, footstep gravel, variants ship_door |
| ![](thumbs/tile_ship_beam.png) | `ship_beam` | strikes as steel, footstep gravel, variants ship_beam |
| ![](thumbs/tile_ship_edge.png) | `ship_edge` | strikes as steel, footstep gravel, variants ship_edge |
| ![](thumbs/tile_ship_pod.png) | `ship_pod` | strikes as steel, footstep gravel, variants ship_pod |
| ![](thumbs/tile_ship_vat.png) | `ship_vat` | strikes as steel, footstep gravel, variants ship_vat |
| ![](thumbs/tile_ship_lino.png) | `ship_lino` | strikes as steel, footstep tile, variants ship_lino |
| ![](thumbs/tile_route_bayou.png) | `route_bayou` | strikes as dirt, footstep gravel, variants route_bayou |
| ![](thumbs/tile_route_speedway.png) | `route_speedway` | strikes as dirt, footstep gravel, variants route_speedway |
| ![](thumbs/tile_route_mothership.png) | `route_mothership` | strikes as dirt, footstep gravel, variants route_mothership |
| ![](thumbs/tile_barn_brk.png) | `barn_brk` | strikes as wood, footstep gravel, variants barn, barn_win, barn_lit, barn_brk |
| ![](thumbs/tile_tin_brk.png) | `tin_brk` | strikes as tin, footstep gravel, variants tin, tin_win, tin_lit, tin_brk |
| ![](thumbs/tile_brick_brk.png) | `brick_brk` | strikes as brick, footstep gravel, variants brick, brick_win, brick_lit, brick_brk |
| ![](thumbs/tile_plaster_brk.png) | `plaster_brk` | strikes as stone, footstep gravel, variants plaster, plaster_win, plaster_lit, plaster_brk |
| ![](thumbs/tile_cinder_brk.png) | `cinder_brk` | strikes as stone, footstep gravel, variants cinder, cinder_win, cinder_lit, cinder_brk |
| ![](thumbs/tile_office_wall_brk.png) | `office_wall_brk` | strikes as stone, footstep gravel, variants office_wall, office_wall_win, office_wall_lit, office_wall_brk |
| ![](thumbs/tile_fair_booth_brk.png) | `fair_booth_brk` | strikes as wood, footstep gravel, variants fair_booth, fair_booth_win, fair_booth_lit, fair_booth_brk |
| ![](thumbs/tile_fair_iron_brk.png) | `fair_iron_brk` | strikes as steel, footstep gravel, variants fair_iron, fair_iron_win, fair_iron_lit, fair_iron_brk |
| ![](thumbs/tile_mill_tin_brk.png) | `mill_tin_brk` | strikes as tin, footstep gravel, variants mill_tin, mill_tin_win, mill_tin_lit, mill_tin_brk |
| ![](thumbs/tile_quarry_iron_brk.png) | `quarry_iron_brk` | strikes as steel, footstep gravel, variants quarry_iron, quarry_iron_win, quarry_iron_lit, quarry_iron_brk |
| ![](thumbs/tile_quarry_shed_brk.png) | `quarry_shed_brk` | strikes as wood, footstep gravel, variants quarry_shed, quarry_shed_win, quarry_shed_lit, quarry_shed_brk |
| ![](thumbs/tile_bayou_tin_brk.png) | `bayou_tin_brk` | strikes as tin, footstep gravel, variants bayou_tin, bayou_tin_win, bayou_tin_lit, bayou_tin_brk |
| ![](thumbs/tile_bayou_shack_brk.png) | `bayou_shack_brk` | strikes as wood, footstep gravel, variants bayou_shack, bayou_shack_win, bayou_shack_lit, bayou_shack_brk |
| ![](thumbs/tile_bayou_cannery_brk.png) | `bayou_cannery_brk` | strikes as stone, footstep gravel, variants bayou_cannery, bayou_cannery_win, bayou_cannery_lit, bayou_cannery_brk |
| ![](thumbs/tile_diner_steel_brk.png) | `diner_steel_brk` | strikes as steel, footstep gravel, variants diner_steel, diner_steel_win, diner_steel_lit, diner_steel_brk |
| ![](thumbs/tile_trailer_brk.png) | `trailer_brk` | strikes as tin, footstep gravel, variants trailer, trailer_brk |
| ![](thumbs/tile_stockyard_hit.png) | `stockyard_hit` | strikes as wood, footstep gravel, variants stockyard_hit |

## Props

| | id | notes |
| --- | --- | --- |
| ![](thumbs/prop_airboat.png) | `airboat` | prop, 2.11 high, 3.21 wide |
| ![](thumbs/prop_alien_console.png) | `alien_console` | prop, 1.53 high, 1.35 wide |
| ![](thumbs/prop_alien_crate.png) | `alien_crate` | prop, 0.85 high, 1.23 wide |
| ![](thumbs/prop_alien_crate_broken.png) | `alien_crate_broken` | prop, 0.85 high, 1.8 wide |
| ![](thumbs/prop_axe_stump.png) | `axe_stump` | prop, 1.18 high, 0.72 wide |
| ![](thumbs/prop_bait_cooler_rack.png) | `bait_cooler_rack` | prop, 2.05 high, 1.25 wide |
| ![](thumbs/prop_bait_tank.png) | `bait_tank` | prop, 1.93 high, 1.95 wide |
| ![](thumbs/prop_balloons.png) | `balloons` | prop, 1.99 high, 1.1 wide |
| ![](thumbs/prop_balloons_broken.png) | `balloons_broken` | prop, 1.95 high, 0.75 wide |
| ![](thumbs/prop_barrel_broken.png) | `barrel_broken` | prop, 0.67 high, 1.62 wide |
| ![](thumbs/prop_bathtub.png) | `bathtub` | prop, 0.78 high, 1.44 wide |
| ![](thumbs/prop_beam_emitter.png) | `beam_emitter` | prop, 0.88 high, 1.8 wide |
| ![](thumbs/prop_belt_conveyor.png) | `belt_conveyor` | prop, 1.74 high, 3.54 wide |
| ![](thumbs/prop_boil_pot.png) | `boil_pot` | prop, 1.85 high, 1.45 wide |
| ![](thumbs/prop_boil_table.png) | `boil_table` | prop, 1.15 high, 2.09 wide |
| ![](thumbs/prop_boulder_a.png) | `boulder_a` | prop, 1.18 high, 1.67 wide |
| ![](thumbs/prop_boulder_b.png) | `boulder_b` | prop, 1.18 high, 1.0 wide |
| ![](thumbs/prop_bunk.png) | `bunk` | prop, 1.9 high, 1.98 wide |
| ![](thumbs/prop_burn_barrel.png) | `burn_barrel` | prop, 1.4 high, 0.62 wide |
| ![](thumbs/prop_cable_spool.png) | `cable_spool` | prop, 1.24 high, 1.23 wide |
| ![](thumbs/prop_camp_chairs.png) | `camp_chairs` | prop, 1.05 high, 1.54 wide |
| ![](thumbs/prop_canned_ham.png) | `canned_ham` | prop, 1.58 high, 3.29 wide |
| ![](thumbs/prop_captain_chair.png) | `captain_chair` | prop, 1.58 high, 1.49 wide |
| ![](thumbs/prop_car_crusher.png) | `car_crusher` | prop, 3.01 high, 3.63 wide |
| ![](thumbs/prop_carousel_horse.png) | `carousel_horse` | prop, 2.19 high, 1.05 wide |
| ![](thumbs/prop_chicken_coop.png) | `chicken_coop` | prop, 1.6 high, 1.73 wide |
| ![](thumbs/prop_cooler.png) | `cooler` | prop, 0.63 high, 0.85 wide |
| ![](thumbs/prop_cooler_broken.png) | `cooler_broken` | prop, 0.62 high, 1.27 wide |
| ![](thumbs/prop_copper_vat.png) | `copper_vat` | prop, 2.25 high, 1.74 wide |
| ![](thumbs/prop_corn_tray.png) | `corn_tray` | prop, 2.2 high, 1.48 wide |
| ![](thumbs/prop_cotton_candy.png) | `cotton_candy` | prop, 1.93 high, 1.3 wide |
| ![](thumbs/prop_cow_tube.png) | `cow_tube` | prop, 2.74 high, 1.32 wide |
| ![](thumbs/prop_cow_tube_broken.png) | `cow_tube_broken` | prop, 2.82 high, 2.0 wide |
| ![](thumbs/prop_crane_hook.png) | `crane_hook` | prop, 3.49 high, 4.06 wide |
| ![](thumbs/prop_crate_broken.png) | `crate_broken` | prop, 0.76 high, 1.72 wide |
| ![](thumbs/prop_crawfish_traps.png) | `crawfish_traps` | prop, 1.12 high, 1.28 wide |
| ![](thumbs/prop_crushed_stack.png) | `crushed_stack` | prop, 1.39 high, 2.4 wide |
| ![](thumbs/prop_crusher.png) | `crusher` | prop, 2.63 high, 2.29 wide |
| ![](thumbs/prop_cypress.png) | `cypress` | prop, 4.78 high, 2.31 wide |
| ![](thumbs/prop_cypress_b.png) | `cypress_b` | prop, 3.63 high, 1.76 wide |
| ![](thumbs/prop_cypress_knees.png) | `cypress_knees` | prop, 0.82 high, 1.08 wide |
| ![](thumbs/prop_dead_snag.png) | `dead_snag` | prop, 3.15 high, 1.49 wide |
| ![](thumbs/prop_deer_target.png) | `deer_target` | prop, 1.42 high, 1.15 wide |
| ![](thumbs/prop_derby_car.png) | `derby_car` | prop, 1.28 high, 2.41 wide |
| ![](thumbs/prop_dish.png) | `dish` | prop, 1.47 high, 1.13 wide |
| ![](thumbs/prop_doghouse.png) | `doghouse` | prop, 1.1 high, 1.54 wide |
| ![](thumbs/prop_drill_rig.png) | `drill_rig` | prop, 3.28 high, 1.89 wide |
| ![](thumbs/prop_dump_truck.png) | `dump_truck` | prop, 2.03 high, 2.49 wide |
| ![](thumbs/prop_engine_hoist.png) | `engine_hoist` | prop, 2.3 high, 1.81 wide |
| ![](thumbs/prop_engine_stand.png) | `engine_stand` | prop, 1.2 high, 0.99 wide |
| ![](thumbs/prop_escape_outhouse.png) | `escape_outhouse` | prop, 2.99 high, 1.65 wide |
| ![](thumbs/prop_ferris_wheel.png) | `ferris_wheel` | prop, 5.83 high, 4.25 wide |
| ![](thumbs/prop_flag_stand.png) | `flag_stand` | prop, 3.47 high, 2.04 wide |
| ![](thumbs/prop_flamingo.png) | `flamingo` | prop, 1.02 high, 0.51 wide |
| ![](thumbs/prop_flamingo_broken.png) | `flamingo_broken` | prop, 0.28 high, 1.01 wide |
| ![](thumbs/prop_floodlight_tower.png) | `floodlight_tower` | prop, 7.31 high, 1.47 wide |
| ![](thumbs/prop_forklift.png) | `forklift` | prop, 1.88 high, 2.19 wide |
| ![](thumbs/prop_fridge.png) | `fridge` | prop, 1.64 high, 1.0 wide |
| ![](thumbs/prop_fuel_drum_burst.png) | `fuel_drum_burst` | prop, 0.92 high, 1.31 wide |
| ![](thumbs/prop_fuel_pump.png) | `fuel_pump` | prop, 2.0 high, 0.83 wide |
| ![](thumbs/prop_fuel_tank.png) | `fuel_tank` | prop, 2.36 high, 2.5 wide |
| ![](thumbs/prop_gas_cans.png) | `gas_cans` | prop, 0.5 high, 0.68 wide |
| ![](thumbs/prop_gas_cans_broken.png) | `gas_cans_broken` | prop, 0.48 high, 1.0 wide |
| ![](thumbs/prop_gator_hide.png) | `gator_hide` | prop, 1.8 high, 2.23 wide |
| ![](thumbs/prop_generator.png) | `generator` | prop, 1.48 high, 1.75 wide |
| ![](thumbs/prop_giant_gator.png) | `giant_gator` | prop, 1.32 high, 4.8 wide |
| ![](thumbs/prop_giant_hog.png) | `giant_hog` | prop, 2.42 high, 2.99 wide |
| ![](thumbs/prop_grill.png) | `grill` | prop, 1.42 high, 1.09 wide |
| ![](thumbs/prop_hay_wagon.png) | `hay_wagon` | prop, 1.43 high, 2.05 wide |
| ![](thumbs/prop_headrig.png) | `headrig` | prop, 2.14 high, 3.95 wide |
| ![](thumbs/prop_heron.png) | `heron` | prop, 1.32 high, 0.85 wide |
| ![](thumbs/prop_high_striker.png) | `high_striker` | prop, 3.28 high, 0.8 wide |
| ![](thumbs/prop_hubcap_board.png) | `hubcap_board` | prop, 1.0 high, 1.84 wide |
| ![](thumbs/prop_hung_pickup.png) | `hung_pickup` | prop, 1.85 high, 2.43 wide |
| ![](thumbs/prop_ice_chest.png) | `ice_chest` | prop, 0.67 high, 0.94 wide |
| ![](thumbs/prop_ice_chest_broken.png) | `ice_chest_broken` | prop, 0.64 high, 1.38 wide |
| ![](thumbs/prop_jug_stack.png) | `jug_stack` | prop, 0.73 high, 1.08 wide |
| ![](thumbs/prop_jug_stack_broken.png) | `jug_stack_broken` | prop, 0.64 high, 1.11 wide |
| ![](thumbs/prop_jukebox_rig.png) | `jukebox_rig` | prop, 2.05 high, 1.7 wide |
| ![](thumbs/prop_lantern_post.png) | `lantern_post` | prop, 1.6 high, 0.45 wide |
| ![](thumbs/prop_laundry.png) | `laundry` | prop, 0.93 high, 2.6 wide |
| ![](thumbs/prop_log_loader.png) | `log_loader` | prop, 2.58 high, 3.7 wide |
| ![](thumbs/prop_log_pile.png) | `log_pile` | prop, 1.49 high, 2.75 wide |
| ![](thumbs/prop_lumber_cart.png) | `lumber_cart` | prop, 1.21 high, 1.94 wide |
| ![](thumbs/prop_lumber_stack.png) | `lumber_stack` | prop, 1.07 high, 2.48 wide |
| ![](thumbs/prop_magnet_crane.png) | `magnet_crane` | prop, 5.33 high, 4.53 wide |
| ![](thumbs/prop_mailbox_row.png) | `mailbox_row` | prop, 1.19 high, 1.13 wide |
| ![](thumbs/prop_mailbox_row_broken.png) | `mailbox_row_broken` | prop, 1.2 high, 1.42 wide |
| ![](thumbs/prop_marina_pump.png) | `marina_pump` | prop, 1.87 high, 0.71 wide |
| ![](thumbs/prop_mash_barrel.png) | `mash_barrel` | prop, 1.63 high, 1.63 wide |
| ![](thumbs/prop_mash_barrel_broken.png) | `mash_barrel_broken` | prop, 1.02 high, 2.0 wide |
| ![](thumbs/prop_mine_cart.png) | `mine_cart` | prop, 1.14 high, 2.43 wide |
| ![](thumbs/prop_monster_truck.png) | `monster_truck` | prop, 2.71 high, 3.13 wide |
| ![](thumbs/prop_net_rack.png) | `net_rack` | prop, 2.12 high, 1.79 wide |
| ![](thumbs/prop_nitro_rack.png) | `nitro_rack` | prop, 1.29 high, 0.93 wide |
| ![](thumbs/prop_nitro_rack_broken.png) | `nitro_rack_broken` | prop, 1.37 high, 1.06 wide |
| ![](thumbs/prop_outboard_stand.png) | `outboard_stand` | prop, 1.21 high, 1.05 wide |
| ![](thumbs/prop_outhouse.png) | `outhouse` | prop, 2.4 high, 1.51 wide |
| ![](thumbs/prop_pa_horns.png) | `pa_horns` | prop, 3.29 high, 1.25 wide |
| ![](thumbs/prop_pallet_stack.png) | `pallet_stack` | prop, 0.85 high, 1.42 wide |
| ![](thumbs/prop_pallet_stack_broken.png) | `pallet_stack_broken` | prop, 0.52 high, 1.97 wide |
| ![](thumbs/prop_picnic_table.png) | `picnic_table` | prop, 1.0 high, 1.96 wide |
| ![](thumbs/prop_pirogue.png) | `pirogue` | prop, 0.4 high, 2.21 wide |
| ![](thumbs/prop_pod.png) | `pod` | prop, 2.15 high, 1.35 wide |
| ![](thumbs/prop_porch_couch.png) | `porch_couch` | prop, 1.08 high, 1.78 wide |
| ![](thumbs/prop_port_a_john.png) | `port_a_john` | prop, 2.38 high, 1.35 wide |
| ![](thumbs/prop_powder_shelf.png) | `powder_shelf` | prop, 2.25 high, 1.78 wide |
| ![](thumbs/prop_prize_bear.png) | `prize_bear` | prop, 1.44 high, 1.0 wide |
| ![](thumbs/prop_prize_bear_broken.png) | `prize_bear_broken` | prop, 0.93 high, 1.64 wide |
| ![](thumbs/prop_probe_rack.png) | `probe_rack` | prop, 1.1 high, 1.7 wide |
| ![](thumbs/prop_probe_table.png) | `probe_table` | prop, 2.06 high, 1.98 wide |
| ![](thumbs/prop_propane_tank.png) | `propane_tank` | prop, 1.21 high, 1.79 wide |
| ![](thumbs/prop_propane_tank_broken.png) | `propane_tank_broken` | prop, 1.27 high, 1.78 wide |
| ![](thumbs/prop_pylon.png) | `pylon` | prop, 1.55 high, 0.44 wide |
| ![](thumbs/prop_quest_bell_off.png) | `quest_bell_off` | prop, 1.49 high, 1.02 wide |
| ![](thumbs/prop_quest_bell_on.png) | `quest_bell_on` | prop, 1.49 high, 1.02 wide |
| ![](thumbs/prop_quest_bolt_off.png) | `quest_bolt_off` | prop, 1.34 high, 0.84 wide |
| ![](thumbs/prop_quest_bolt_on.png) | `quest_bolt_on` | prop, 1.34 high, 0.84 wide |
| ![](thumbs/prop_quest_brake_off.png) | `quest_brake_off` | prop, 1.33 high, 1.16 wide |
| ![](thumbs/prop_quest_brake_on.png) | `quest_brake_on` | prop, 1.33 high, 1.16 wide |
| ![](thumbs/prop_quest_condenser_off.png) | `quest_condenser_off` | prop, 1.34 high, 0.72 wide |
| ![](thumbs/prop_quest_condenser_on.png) | `quest_condenser_on` | prop, 1.34 high, 0.72 wide |
| ![](thumbs/prop_quest_estop_off.png) | `quest_estop_off` | prop, 1.35 high, 0.57 wide |
| ![](thumbs/prop_quest_estop_on.png) | `quest_estop_on` | prop, 1.35 high, 0.57 wide |
| ![](thumbs/prop_quest_exit_fair_off.png) | `quest_exit_fair_off` | prop, 1.68 high, 1.13 wide |
| ![](thumbs/prop_quest_exit_fair_on.png) | `quest_exit_fair_on` | prop, 1.68 high, 1.13 wide |
| ![](thumbs/prop_quest_exit_flag_off.png) | `quest_exit_flag_off` | prop, 1.7 high, 0.84 wide |
| ![](thumbs/prop_quest_exit_flag_on.png) | `quest_exit_flag_on` | prop, 1.7 high, 0.84 wide |
| ![](thumbs/prop_quest_exit_off.png) | `quest_exit_off` | prop, 1.68 high, 1.13 wide |
| ![](thumbs/prop_quest_exit_on.png) | `quest_exit_on` | prop, 1.68 high, 1.13 wide |
| ![](thumbs/prop_quest_flag_off.png) | `quest_flag_off` | prop, 1.39 high, 0.69 wide |
| ![](thumbs/prop_quest_flag_on.png) | `quest_flag_on` | prop, 1.39 high, 0.69 wide |
| ![](thumbs/prop_quest_fuel_drum_off.png) | `quest_fuel_drum_off` | prop, 1.12 high, 1.12 wide |
| ![](thumbs/prop_quest_fuel_drum_on.png) | `quest_fuel_drum_on` | prop, 1.12 high, 1.12 wide |
| ![](thumbs/prop_quest_fuel_dump_off.png) | `quest_fuel_dump_off` | prop, 1.35 high, 0.69 wide |
| ![](thumbs/prop_quest_fuel_dump_on.png) | `quest_fuel_dump_on` | prop, 1.35 high, 0.69 wide |
| ![](thumbs/prop_quest_generator_off.png) | `quest_generator_off` | prop, 1.39 high, 1.16 wide |
| ![](thumbs/prop_quest_generator_on.png) | `quest_generator_on` | prop, 1.39 high, 1.16 wide |
| ![](thumbs/prop_quest_ignition_off.png) | `quest_ignition_off` | prop, 1.29 high, 0.45 wide |
| ![](thumbs/prop_quest_ignition_on.png) | `quest_ignition_on` | prop, 1.29 high, 0.45 wide |
| ![](thumbs/prop_quest_latch_off.png) | `quest_latch_off` | prop, 1.17 high, 1.32 wide |
| ![](thumbs/prop_quest_latch_on.png) | `quest_latch_on` | prop, 1.17 high, 1.32 wide |
| ![](thumbs/prop_quest_pa_rig_off.png) | `quest_pa_rig_off` | prop, 1.53 high, 0.86 wide |
| ![](thumbs/prop_quest_pa_rig_on.png) | `quest_pa_rig_on` | prop, 1.53 high, 0.86 wide |
| ![](thumbs/prop_quest_patchbay_off.png) | `quest_patchbay_off` | prop, 1.34 high, 0.67 wide |
| ![](thumbs/prop_quest_patchbay_on.png) | `quest_patchbay_on` | prop, 1.34 high, 0.67 wide |
| ![](thumbs/prop_quest_relay_off.png) | `quest_relay_off` | prop, 1.34 high, 0.77 wide |
| ![](thumbs/prop_quest_relay_on.png) | `quest_relay_on` | prop, 1.34 high, 0.77 wide |
| ![](thumbs/prop_quest_ship_drain_off.png) | `quest_ship_drain_off` | prop, 1.36 high, 0.57 wide |
| ![](thumbs/prop_quest_ship_drain_on.png) | `quest_ship_drain_on` | prop, 1.36 high, 0.57 wide |
| ![](thumbs/prop_quest_ship_drive_off.png) | `quest_ship_drive_off` | prop, 1.37 high, 0.78 wide |
| ![](thumbs/prop_quest_ship_drive_on.png) | `quest_ship_drive_on` | prop, 1.37 high, 0.78 wide |
| ![](thumbs/prop_quest_ship_iris_off.png) | `quest_ship_iris_off` | prop, 1.15 high, 0.72 wide |
| ![](thumbs/prop_quest_ship_iris_on.png) | `quest_ship_iris_on` | prop, 1.15 high, 0.72 wide |
| ![](thumbs/prop_quest_ship_launch_off.png) | `quest_ship_launch_off` | prop, 1.33 high, 0.66 wide |
| ![](thumbs/prop_quest_ship_launch_on.png) | `quest_ship_launch_on` | prop, 1.33 high, 0.66 wide |
| ![](thumbs/prop_quest_switch_bayou_off.png) | `quest_switch_bayou_off` | prop, 1.36 high, 0.61 wide |
| ![](thumbs/prop_quest_switch_bayou_on.png) | `quest_switch_bayou_on` | prop, 1.36 high, 0.61 wide |
| ![](thumbs/prop_quest_switch_fair_off.png) | `quest_switch_fair_off` | prop, 1.34 high, 0.63 wide |
| ![](thumbs/prop_quest_switch_fair_on.png) | `quest_switch_fair_on` | prop, 1.34 high, 0.63 wide |
| ![](thumbs/prop_quest_switch_off.png) | `quest_switch_off` | prop, 1.35 high, 0.63 wide |
| ![](thumbs/prop_quest_switch_on.png) | `quest_switch_on` | prop, 1.35 high, 0.63 wide |
| ![](thumbs/prop_quest_switch_speedway_off.png) | `quest_switch_speedway_off` | prop, 1.34 high, 0.63 wide |
| ![](thumbs/prop_quest_switch_speedway_on.png) | `quest_switch_speedway_on` | prop, 1.34 high, 0.63 wide |
| ![](thumbs/prop_quest_valve_off.png) | `quest_valve_off` | prop, 1.22 high, 0.7 wide |
| ![](thumbs/prop_quest_valve_on.png) | `quest_valve_on` | prop, 1.22 high, 0.7 wide |
| ![](thumbs/prop_race_car_0.png) | `race_car_0` | prop, 1.09 high, 1.21 wide |
| ![](thumbs/prop_race_car_1.png) | `race_car_1` | prop, 1.12 high, 2.47 wide |
| ![](thumbs/prop_race_car_2.png) | `race_car_2` | prop, 1.02 high, 2.59 wide |
| ![](thumbs/prop_race_car_3.png) | `race_car_3` | prop, 1.05 high, 2.47 wide |
| ![](thumbs/prop_race_car_4.png) | `race_car_4` | prop, 1.0 high, 1.21 wide |
| ![](thumbs/prop_race_car_5.png) | `race_car_5` | prop, 1.05 high, 2.47 wide |
| ![](thumbs/prop_race_car_6.png) | `race_car_6` | prop, 1.02 high, 2.59 wide |
| ![](thumbs/prop_race_car_7.png) | `race_car_7` | prop, 1.12 high, 2.47 wide |
| ![](thumbs/prop_range_ammo_crate.png) | `range_ammo_crate` | prop, 0.81 high, 1.02 wide |
| ![](thumbs/prop_range_ammo_crate_broken.png) | `range_ammo_crate_broken` | prop, 0.51 high, 1.79 wide |
| ![](thumbs/prop_range_bench.png) | `range_bench` | prop, 1.05 high, 1.52 wide |
| ![](thumbs/prop_range_cow_target.png) | `range_cow_target` | prop, 1.3 high, 1.64 wide |
| ![](thumbs/prop_range_duck.png) | `range_duck` | prop, 0.56 high, 0.72 wide |
| ![](thumbs/prop_range_dummy.png) | `range_dummy` | prop, 1.72 high, 1.28 wide |
| ![](thumbs/prop_range_floodlight.png) | `range_floodlight` | prop, 4.39 high, 1.2 wide |
| ![](thumbs/prop_range_gong.png) | `range_gong` | prop, 1.53 high, 1.38 wide |
| ![](thumbs/prop_range_gun_rack.png) | `range_gun_rack` | prop, 1.68 high, 1.56 wide |
| ![](thumbs/prop_range_hay_bale.png) | `range_hay_bale` | prop, 1.0 high, 1.13 wide |
| ![](thumbs/prop_range_hay_bale_broken.png) | `range_hay_bale_broken` | prop, 0.64 high, 1.5 wide |
| ![](thumbs/prop_range_lever.png) | `range_lever` | prop, 1.41 high, 0.43 wide |
| ![](thumbs/prop_range_loudspeaker.png) | `range_loudspeaker` | prop, 4.07 high, 1.01 wide |
| ![](thumbs/prop_range_pin.png) | `range_pin` | prop, 0.35 high, 0.13 wide |
| ![](thumbs/prop_range_pin_down.png) | `range_pin_down` | prop, 0.14 high, 0.36 wide |
| ![](thumbs/prop_range_sandbags.png) | `range_sandbags` | prop, 0.71 high, 1.58 wide |
| ![](thumbs/prop_range_scoreboard.png) | `range_scoreboard` | prop, 2.4 high, 1.9 wide |
| ![](thumbs/prop_range_target.png) | `range_target` | prop, 1.34 high, 1.04 wide |
| ![](thumbs/prop_rock_chute.png) | `rock_chute` | prop, 2.91 high, 3.06 wide |
| ![](thumbs/prop_rocker.png) | `rocker` | prop, 1.19 high, 1.02 wide |
| ![](thumbs/prop_safe_open.png) | `safe_open` | prop, 0.93 high, 1.12 wide |
| ![](thumbs/prop_saucer_wreck.png) | `saucer_wreck` | prop, 1.79 high, 4.25 wide |
| ![](thumbs/prop_saw_blade.png) | `saw_blade` | prop, 2.34 high, 1.98 wide |
| ![](thumbs/prop_sawdust_pile.png) | `sawdust_pile` | prop, 0.95 high, 2.0 wide |
| ![](thumbs/prop_scarecrow.png) | `scarecrow` | prop, 2.1 high, 1.5 wide |
| ![](thumbs/prop_school_bus.png) | `school_bus` | prop, 2.09 high, 5.97 wide |
| ![](thumbs/prop_searchlight.png) | `searchlight` | prop, 1.33 high, 0.95 wide |
| ![](thumbs/prop_semi_tractor.png) | `semi_tractor` | prop, 3.05 high, 3.29 wide |
| ![](thumbs/prop_shine_tank.png) | `shine_tank` | prop, 1.81 high, 1.93 wide |
| ![](thumbs/prop_ship_engine.png) | `ship_engine` | prop, 2.7 high, 1.95 wide |
| ![](thumbs/prop_skiff.png) | `skiff` | prop, 0.93 high, 3.49 wide |
| ![](thumbs/prop_skull_post.png) | `skull_post` | prop, 1.37 high, 0.68 wide |
| ![](thumbs/prop_sorting_table.png) | `sorting_table` | prop, 1.23 high, 2.75 wide |
| ![](thumbs/prop_specimen_jar.png) | `specimen_jar` | prop, 1.35 high, 0.54 wide |
| ![](thumbs/prop_specimen_jar_broken.png) | `specimen_jar_broken` | prop, 1.16 high, 0.99 wide |
| ![](thumbs/prop_still.png) | `still` | prop, 1.3 high, 1.49 wide |
| ![](thumbs/prop_stock_car.png) | `stock_car` | prop, 1.05 high, 2.71 wide |
| ![](thumbs/prop_stock_car_b.png) | `stock_car_b` | prop, 1.14 high, 2.49 wide |
| ![](thumbs/prop_stone_blocks.png) | `stone_blocks` | prop, 1.88 high, 2.51 wide |
| ![](thumbs/prop_stone_sledge.png) | `stone_sledge` | prop, 1.33 high, 2.75 wide |
| ![](thumbs/prop_strongbox.png) | `strongbox` | prop, 0.61 high, 0.72 wide |
| ![](thumbs/prop_tire_pile.png) | `tire_pile` | prop, 1.23 high, 1.92 wide |
| ![](thumbs/prop_tire_stack.png) | `tire_stack` | prop, 0.89 high, 0.75 wide |
| ![](thumbs/prop_tnt_crate.png) | `tnt_crate` | prop, 0.9 high, 0.99 wide |
| ![](thumbs/prop_tnt_crate_broken.png) | `tnt_crate_broken` | prop, 0.53 high, 1.54 wide |
| ![](thumbs/prop_tombstone_a.png) | `tombstone_a` | prop, 0.77 high, 0.54 wide |
| ![](thumbs/prop_tombstone_b.png) | `tombstone_b` | prop, 0.85 high, 0.52 wide |
| ![](thumbs/prop_tombstone_c.png) | `tombstone_c` | prop, 0.65 high, 0.61 wide |
| ![](thumbs/prop_tool_chest.png) | `tool_chest` | prop, 1.33 high, 0.98 wide |
| ![](thumbs/prop_tow_truck.png) | `tow_truck` | prop, 1.9 high, 3.19 wide |
| ![](thumbs/prop_tractor.png) | `tractor` | prop, 2.08 high, 2.09 wide |
| ![](thumbs/prop_trophy.png) | `trophy` | prop, 1.46 high, 0.81 wide |
| ![](thumbs/prop_trophy_gnome.png) | `trophy_gnome` | prop, 1.6 high, 0.89 wide |
| ![](thumbs/prop_truck_blocks.png) | `truck_blocks` | prop, 1.49 high, 2.13 wide |
| ![](thumbs/prop_warning_barrel.png) | `warning_barrel` | prop, 0.98 high, 0.61 wide |
| ![](thumbs/prop_warning_barrel_broken.png) | `warning_barrel_broken` | prop, 0.66 high, 1.29 wide |
| ![](thumbs/prop_washer.png) | `washer` | prop, 1.16 high, 0.95 wide |
| ![](thumbs/prop_wheelbarrow.png) | `wheelbarrow` | prop, 0.74 high, 1.14 wide |
| ![](thumbs/prop_wreck_pickup.png) | `wreck_pickup` | prop, 1.39 high, 2.08 wide |
| ![](thumbs/prop_wreck_sedan.png) | `wreck_sedan` | prop, 1.28 high, 2.13 wide |
| ![](thumbs/prop_wrecked_derby.png) | `wrecked_derby` | prop, 1.43 high, 2.2 wide |
| ![](thumbs/flat_barrel.png) | `barrel` | flat prop, 1.04 high |
| ![](thumbs/flat_hay.png) | `hay` | flat prop, 0.91 high |
| ![](thumbs/flat_pump.png) | `pump` | flat prop, 1.43 high |
| ![](thumbs/flat_pump_b.png) | `pump_b` | flat prop, 1.43 high |
| ![](thumbs/flat_sink.png) | `sink` | flat prop, 0.89 high |
| ![](thumbs/flat_crate.png) | `crate` | flat prop, 0.75 high |
| ![](thumbs/flat_jukebox.png) | `jukebox` | flat prop, 1.45 high |
| ![](thumbs/flat_lamp.png) | `lamp` | flat prop, 0.24 high |
| ![](thumbs/flat_tree.png) | `tree` | flat prop, 3.65 high |
| ![](thumbs/flat_tree_b.png) | `tree_b` | flat prop, 3.65 high |
| ![](thumbs/flat_utilitypole.png) | `utilitypole` | flat prop, 3.85 high |
| ![](thumbs/flat_pickup_truck.png) | `pickup_truck` | flat prop, 1.31 high |
| ![](thumbs/flat_pickup_truck_b.png) | `pickup_truck_b` | flat prop, 1.2 high |
| ![](thumbs/flat_roadsign.png) | `roadsign` | flat prop, 1.67 high |
| ![](thumbs/flat_bleacher_sign.png) | `bleacher_sign` | flat prop, 1.58 high |
| ![](thumbs/flat_mailbox.png) | `mailbox` | flat prop, 1.18 high |
| ![](thumbs/flat_tire.png) | `tire` | flat prop, 0.4 high |
| ![](thumbs/flat_windmill.png) | `windmill` | flat prop, 4.65 high |
| ![](thumbs/flat_silo.png) | `silo` | flat prop, 3.78 high |
| ![](thumbs/flat_reeds.png) | `reeds` | flat prop, 0.58 high |
| ![](thumbs/flat_water_tower.png) | `water_tower` | flat prop, 5.1 high |

## Enemies

| | id | notes |
| --- | --- | --- |
| ![](thumbs/enemy_clone.png) | `clone` | brain clone, health 60 |
| ![](thumbs/enemy_billy.png) | `billy` | brain billy, health 70 |
| ![](thumbs/enemy_coot.png) | `coot` | brain coot, health 53 |
| ![](thumbs/enemy_skeeter.png) | `skeeter` | brain skeeter, health 36 |
| ![](thumbs/enemy_alien.png) | `alien` | brain alien, health 91 |
| ![](thumbs/enemy_saucer.png) | `saucer` | brain saucer, health 75 |
| ![](thumbs/enemy_boss.png) | `boss` | brain boss, health 1300, boss |
| ![](thumbs/enemy_jerry.png) | `jerry` | brain jerry, health 1150, boss |
| ![](thumbs/enemy_barker.png) | `barker` | brain barker, health 80 |
| ![](thumbs/enemy_crawler.png) | `crawler` | brain crawler, health 34 |
| ![](thumbs/enemy_millhand.png) | `millhand` | brain millhand, health 98 |
| ![](thumbs/enemy_lantern.png) | `lantern` | brain lantern, health 69 |
| ![](thumbs/enemy_boilerback.png) | `boilerback` | brain boilerback, health 99 |
| ![](thumbs/enemy_chalk_spitter.png) | `chalk_spitter` | brain chalk_spitter, health 52 |
| ![](thumbs/enemy_yard_deputy.png) | `yard_deputy` | brain yard_deputy, health 64 |
| ![](thumbs/enemy_bottle_tosser.png) | `bottle_tosser` | brain bottle_tosser, health 51 |
| ![](thumbs/enemy_chain_hand.png) | `chain_hand` | brain chain_hand, health 78 |
| ![](thumbs/enemy_valve_rat.png) | `valve_rat` | brain valve_rat, health 63 |
| ![](thumbs/enemy_rudy.png) | `rudy` | brain rudy, health 1250, boss |
| ![](thumbs/enemy_foreman.png) | `foreman` | brain foreman, health 1000, boss |
| ![](thumbs/enemy_baron.png) | `baron` | brain baron, health 1300, boss |
| ![](thumbs/enemy_drone.png) | `drone` | brain millhand, health 46 |
| ![](thumbs/enemy_tin_guard.png) | `tin_guard` | brain alien, health 185 |
| ![](thumbs/enemy_probe.png) | `probe` | brain saucer, health 58 |
| ![](thumbs/enemy_maw.png) | `maw` | brain maw, health 2400, boss |
| ![](thumbs/enemy_chicken.png) | `chicken` | brain chicken, health 11 |
| ![](thumbs/enemy_pig.png) | `pig` | brain pig, health 22 |
| ![](thumbs/enemy_bessie.png) | `bessie` | brain bessie, health 100 |
| ![](thumbs/enemy_noodler.png) | `noodler` | brain millhand, health 118 |
| ![](thumbs/enemy_chum_tosser.png) | `chum_tosser` | brain bottle_tosser, health 58 |
| ![](thumbs/enemy_gator.png) | `gator` | brain crawler, health 82 |
| ![](thumbs/enemy_swamp_king.png) | `swamp_king` | brain swamp_king, health 1900, boss |
| ![](thumbs/enemy_pit_mechanic.png) | `pit_mechanic` | brain bottle_tosser, health 62 |
| ![](thumbs/enemy_tire_roller.png) | `tire_roller` | brain valve_rat, health 118 |
| ![](thumbs/enemy_nitro_huffer.png) | `nitro_huffer` | brain nitro_huffer, health 40 |
| ![](thumbs/enemy_flagman.png) | `flagman` | brain flagman, health 56 |
| ![](thumbs/enemy_derby_champ.png) | `derby_champ` | brain derby_champ, health 1250, boss |
| ![](thumbs/enemy_big_billy.png) | `big_billy` | brain billy, health 150 |
| ![](thumbs/enemy_drunk_coot.png) | `drunk_coot` | brain coot, health 82 |
| ![](thumbs/enemy_shield_deputy.png) | `shield_deputy` | brain yard_deputy, health 70 |
| ![](thumbs/enemy_tough_earl.png) | `tough_earl` | brain billy, health 270 |
| ![](thumbs/enemy_tough_clem.png) | `tough_clem` | brain barker, health 230 |
| ![](thumbs/enemy_tough_tom.png) | `tough_tom` | brain millhand, health 280 |
| ![](thumbs/enemy_tough_bubba.png) | `tough_bubba` | brain boilerback, health 290 |
| ![](thumbs/enemy_tough_chuck.png) | `tough_chuck` | brain bottle_tosser, health 190 |
| ![](thumbs/enemy_tough_pete.png) | `tough_pete` | brain bottle_tosser, health 200 |
| ![](thumbs/enemy_tough_zorgo.png) | `tough_zorgo` | brain alien, health 300 |

## Pickups

| | id | notes |
| --- | --- | --- |
| ![](thumbs/pickup_arm_ammo.png) | `arm_ammo` |  |
| ![](thumbs/pickup_armgun.png) | `armgun` |  |
| ![](thumbs/pickup_beer.png) | `beer` |  |
| ![](thumbs/pickup_bottle_launcher.png) | `bottle_launcher` |  |
| ![](thumbs/pickup_bowling_ammo.png) | `bowling_ammo` |  |
| ![](thumbs/pickup_bowling_ball.png) | `bowling_ball` |  |
| ![](thumbs/pickup_bullets.png) | `bullets` |  |
| ![](thumbs/pickup_cow_ammo.png) | `cow_ammo` |  |
| ![](thumbs/pickup_cow_launcher.png) | `cow_launcher` |  |
| ![](thumbs/pickup_cowpie.png) | `cowpie` |  |
| ![](thumbs/pickup_crossbow.png) | `crossbow` |  |
| ![](thumbs/pickup_crowbar.png) | `crowbar` |  |
| ![](thumbs/pickup_dynamite.png) | `dynamite` |  |
| ![](thumbs/pickup_keg_ammo.png) | `keg_ammo` |  |
| ![](thumbs/pickup_key_brass.png) | `key_brass` |  |
| ![](thumbs/pickup_key_steel.png) | `key_steel` |  |
| ![](thumbs/pickup_milk_ammo.png) | `milk_ammo` |  |
| ![](thumbs/pickup_moonshine.png) | `moonshine` |  |
| ![](thumbs/pickup_pa_patch.png) | `pa_patch` |  |
| ![](thumbs/pickup_powder_keg.png) | `powder_keg` |  |
| ![](thumbs/pickup_pressure_ammo.png) | `pressure_ammo` |  |
| ![](thumbs/pickup_pressure_gun.png) | `pressure_gun` |  |
| ![](thumbs/pickup_revolver.png) | `revolver` |  |
| ![](thumbs/pickup_rifle.png) | `rifle` |  |
| ![](thumbs/pickup_rifle_ammo.png) | `rifle_ammo` |  |
| ![](thumbs/pickup_rinds.png) | `rinds` |  |
| ![](thumbs/pickup_ripsaw.png) | `ripsaw` |  |
| ![](thumbs/pickup_rivet_ammo.png) | `rivet_ammo` |  |
| ![](thumbs/pickup_riveter.png) | `riveter` |  |
| ![](thumbs/pickup_rocket_ammo.png) | `rocket_ammo` |  |
| ![](thumbs/pickup_saw_ammo.png) | `saw_ammo` |  |
| ![](thumbs/pickup_shells.png) | `shells` |  |
| ![](thumbs/pickup_shotgun.png) | `shotgun` |  |
| ![](thumbs/pickup_slingblade.png) | `slingblade` |  |
| ![](thumbs/pickup_teat_gun.png) | `teat_gun` |  |
| ![](thumbs/pickup_tnt.png) | `tnt` |  |
| ![](thumbs/pickup_whiskey.png) | `whiskey` |  |

