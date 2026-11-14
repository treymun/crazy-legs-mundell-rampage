#!/usr/bin/env bash
# The demonstration map, Mundell Feed & Seed, made only with tools/map.gd
# commands (MAP_AUTHORING.md walks through it). Run from the repo root:
#   GODOT=/path/to/godot bash docs/map_examples/feedstore_build.sh
# It writes godot/maps/feedstore.map.json (refusing if it exists: remove that
# first to start over), validates it and builds data/feedstore.json.
set -e
GODOT="${GODOT:-godot}"
map() { "$GODOT" --headless --path godot --script res://tools/map.gd -- "$@"; }

map new feedstore size=28x22
map set feedstore ground floor='"dirt"'
# The source's own keys: districts, the title and story, where the player starts.
map top feedstore districts='[{"id": "outside", "name": "FEED YARD"}, {"id": "store", "name": "FEED STORE", "tint": [1.0, 0.94, 0.84]}, {"id": "office", "name": "OFFICE", "tint": [0.92, 0.96, 1.0]}]'
map top feedstore meta='{"title": "MUNDELL FEED & SEED", "sky": "sky", "layout": 1, "intro": "BILLY PARKED HIS TRUCK UNDER THE GRAIN CHUTE. HELP HIM OUT."}'
map top feedstore spawn='{"at": [3.5, 18.5], "angle": -40}'

# The yard: a gravel path from the road to the store.
map add feedstore '{"id": "path", "type": "paint", "rect": [3, 12, 10, 20], "floor": "gravel"}'

# The store: a barn-walled building, two floors tall, a door south and east.
map add feedstore '{"id": "store", "type": "building", "rect": [4, 3, 16, 12], "wall": "barn", "roof": 3.4, "floor": "wood", "windows": 3, "district": "store"}'
map add feedstore '{"id": "store_door", "type": "door", "cell": [9, 11], "from": "n"}'
map add feedstore '{"id": "side_door", "type": "door", "cell": [15, 9], "vertical": true, "from": "w"}'

# Stairs up the north wall to the loft (a landing at their foot, by the west wall), the loft railed on its open sides
# (a gap where the stairs arrive); the stock room under it.
map add feedstore '{"id": "loft_stairs", "type": "stairs", "rect": [6, 4, 10, 5.2], "from": 0, "to": 1.7, "toward": "e", "tile": "porch", "edge": "barn", "district": "store"}'
map add feedstore '{"id": "loft", "type": "balcony", "rect": [10, 4, 15, 8], "top": 1.7, "open": "ws", "gaps": [["w", 0, 1.3]], "tile": "porch", "under": "joists", "district": "store"}'

# A thin plaster partition under the loft's edge: a doorway and a window cut
# to size.
map add feedstore '{"id": "partition", "type": "wall", "a": [10, 5.4], "b": [10, 11], "z0": 0, "z1": 1.55, "thick": 0.12, "tile": "plaster", "openings": [{"id": "stock_door", "at": 2.1, "width": 1.0}, {"id": "stock_window", "at": 4.6, "width": 1.0, "sill": 0.9, "head": 1.45}], "district": "store"}'

# The office: an angled room east of the store.
map add feedstore '{"id": "office", "type": "room_poly", "points": [[18, 2], [24, 2], [26, 6], [18, 6]], "floor": "floor_tile", "roof": 2.4, "wall": "plaster", "openings": [[3, {"id": "office_door", "at": 1.5, "width": 1.0}]], "district": "office"}'

# The loading dock, its ramp, and crates for cover on it and in the yard.
map add feedstore '{"id": "dock", "type": "block", "rect": [17, 8, 22, 12], "top": 0.9, "tile": "porch", "edge": "barn"}'
map add feedstore '{"id": "dock_ramp", "type": "ramp", "rect": [17.5, 12, 19.5, 15], "from": 0, "to": 0.9, "toward": "n", "tile": "porch", "edge": "barn"}'
map add feedstore '{"id": "dock_crates", "type": "cover", "a": [19.5, 9.2], "b": [21.5, 9.2], "z": 0.9, "height": 0.8, "thick": 0.4, "tile": "crate_side"}'
map add feedstore '{"id": "yard_crates", "type": "cover", "a": [6, 15], "b": [9, 15], "height": 1.0, "thick": 0.35, "tile": "crate_side"}'
map add feedstore '{"id": "yard_crates_east", "type": "cover", "a": [20, 17], "b": [20, 19.5], "height": 1.0, "thick": 0.35, "tile": "crate_side"}'

# What lives here.
map add feedstore '{"id": "chute_lever", "type": "station", "at": [14.3, 5.0], "z": 1.7, "label": "THROW THE GRAIN CHUTE", "message": "FEED ALL OVER BILLY'"'"'S TRUCK", "prop": "quest_switch"}'
map add feedstore '{"id": "road_exit", "type": "exit", "at": [25.5, 12.5], "label": "HIT THE ROAD", "shutdown": "chute_lever"}'
map add feedstore '{"id": "loft_billy", "type": "enemy", "kind": "billy", "at": [13.5, 6.8], "z": 1.7}'
map add feedstore '{"id": "stock_billy", "type": "enemy", "kind": "billy", "at": [12.5, 6.0]}'
map add feedstore '{"id": "dock_billy", "type": "enemy", "kind": "billy", "at": [21, 11], "z": 0.9}'
map add feedstore '{"id": "yard_billy", "type": "enemy", "kind": "billy", "at": [22.5, 15.5]}'
map add feedstore '{"id": "loft_shells", "type": "pickup", "name": "shells", "at": [11, 7.3], "z": 1.7}'
map add feedstore '{"id": "office_beer", "type": "pickup", "name": "beer", "at": [20, 4.5]}'
map add feedstore '{"id": "stock_pallets", "type": "prop", "name": "pallet_stack", "at": [13.5, 9.8]}'
map add feedstore '{"id": "yard_cans", "type": "prop", "name": "gas_cans", "at": [26, 19.5]}'
map add feedstore '{"id": "shop_lamp", "type": "light", "at": [8, 7.5], "reach": 5, "amount": 0.18}'
map add feedstore '{"id": "sp_yard", "type": "spawn_point", "at": [24.5, 18.5]}'
map add feedstore '{"id": "sp_dock", "type": "spawn_point", "at": [20.5, 10.5], "z": 0.9}'
map add feedstore '{"id": "sp_loft", "type": "spawn_point", "at": [12.5, 6.5], "z": 1.7}'

map validate feedstore
map build feedstore
