## What a level's tiles are made of, for what a bullet does when it strikes
## one: the chips it throws, the sound, the hole it leaves (features/impacts.gd)
## and whether a strong enough round goes on through (penetration.gd).
##
## Kinds: wood (planks, boards, doors), timber (logs and trunks: too thick to
## shoot through), tin (sheet iron, trailers, garage doors), steel (plate,
## pipe, the ship), mesh (wire fence), brick, stone (plaster, concrete, cinder
## block, rock), dirt (ground), brush (corn, hedge, reeds), glass, rubber
## (tyre walls), water. Anything not listed is wood, as the game always had it.
class_name Materials
extends RefCounted

const GLASS := ["window", "glazing", "hub_screen", "ship_screen", "mirror"]
const TIN := [
	"tin",
	"bayou_tin",
	"mill_tin",
	"trailer",
	"trailer_window",
	"garage_door",
	"ship_tin",
	"powder_panel",
	"kiln_patches",
	"rain_sheets",
	"shed_repair",
]
const STEEL := [
	"ship",
	"diner_steel",
	"fair_iron",
	"fair_gate",
	"gate",
	"mill_pump",
	"quarry_iron",
	"quarry_copper",
	"copper_seams",
	"hub_tank_shell",
	"junk_stack",
	"service",
]
const MESH := ["steel_mesh", "bayou_pen"]
const BRICK := ["brick", "garage_courses", "trim_foundation"]
const STONE := [
	"plaster",
	"cinder",
	"tile",
	"floor_tile",
	"concrete",
	"office_wall",
	"quarry_face",
	"chalk_cut",
	"crash_wall",
	"bayou_cannery",
	"diner_checker",
	"hub_service_wall",
	"tavern",
	"bar_wainscot",
	"grandstand_riser",
	"checker_band",
	"counter_top",
]
const TIMBER := ["mill_log", "bayou_cypress", "bayou_stilts"]
const BRUSH := ["corn", "hedgerow", "bayou_reeds"]
const WATER := ["creek", "mill_water", "bayou_water", "bayou_deep", "hub_runoff"]
const RUBBER := ["tire_wall"]
const DIRT := [
	"dirt",
	"grass",
	"orchard",
	"tracks",
	"shoulder",
	"gravel",
	"quarry_dust",
	"mill_grit",
	"fair_gravel",
	"asphalt",
	"road",
	"oil_asphalt",
	"bayou_mud",
	"bayou_marsh",
	"bayou_bank",
	"track_dirt",
	"track_chalk",
	"derby_mud",
	"junk_ground",
	"hub_patch",
	"mill_oil",
]
## Floors a boot or a wheel raises dust off.
const DUSTY := [
	"dirt",
	"tracks",
	"shoulder",
	"gravel",
	"quarry_dust",
	"mill_grit",
	"fair_gravel",
	"track_dirt",
	"track_chalk",
	"junk_ground",
	"hub_patch",
	"road",
]
## How hard each kind is to shoot through, per cell of it the round crosses
## (a gun's `penetrate` in weapons.cfg is how much it can spend). A kind not
## here stops every round.
const RESIST := {"wood": 1.0, "tin": .75, "mesh": .25, "brush": .6}
## The hole each kind keeps (empty: none; mesh lets it by, brush closes up).
const HOLES := {
	"wood": "fx_hole_wood",
	"timber": "fx_hole_wood",
	"tin": "fx_hole_tin",
	"steel": "fx_hole_metal",
	"brick": "fx_hole_brick",
	"stone": "fx_hole_stone",
	"dirt": "fx_hole_stone",
	"glass": "fx_hole_glass",
}
## The game's own speck each kind throws (game_combat.gd burst: the same
## count as ever, so the game's dice are spent the same way).
const SPECKS := {
	"wood": "chips",
	"timber": "chips",
	"tin": "spark",
	"steel": "spark",
	"mesh": "spark",
	"brick": "chips",
	"stone": "powder",
	"glass": "glass",
	"dirt": "soil",
	"brush": "soil",
	"rubber": "soil",
	"water": "splash",
}
const CUES := {
	"wood": "impact_wood",
	"timber": "impact_wood",
	"tin": "ricochet_tin",
	"steel": "ricochet_whine",
	"mesh": "impact_mesh",
	"brick": "impact_brick",
	"stone": "impact_plaster",
	"glass": "impact_glass",
	"dirt": "impact_dirt",
	"brush": "impact_brush",
	"rubber": "impact_rubber",
	"water": "impact_dirt",
}

static var _kinds := {}
## Each fixture's side tile, found once (collision volumes keep no names).
static var _sides := {}
static var _sides_of: Object = null


## The kind a tile name is made of.
static func of_name(name: String) -> String:
	var cached = _kinds.get(name)
	if cached != null:
		return cached
	var base := name
	for tail: String in ["_win", "_lit", "_window"]:
		if base.ends_with(tail) and base != "trailer_window":
			base = base.substr(0, base.length() - tail.length())
	if base.begins_with("detail_wall_"):
		base = base.substr(12)
	var kind := "wood"
	if base in GLASS:
		kind = "glass"
	elif base in TIN:
		kind = "tin"
	elif base in MESH:
		kind = "mesh"
	elif base in STEEL or base.begins_with("ship_"):
		kind = "steel"
	elif base in BRICK:
		kind = "brick"
	elif base in STONE:
		kind = "stone"
	elif base in TIMBER:
		kind = "timber"
	elif base in BRUSH:
		kind = "brush"
	elif base in WATER:
		kind = "water"
	elif base in RUBBER:
		kind = "rubber"
	elif base in DIRT or base.begins_with("route_"):
		kind = "dirt"
	_kinds[name] = kind
	return kind


static func of_tile(level: LevelData, tile: int) -> String:
	if tile < 0 or tile >= level.tile_names.size():
		return "wood"
	return of_name(String(level.tile_names[tile]))


## The coarse surface the game always named ("wood", "metal", "plaster",
## "dirt": the `traced` event's "wall:<surface>").
static func coarse(kind: String) -> String:
	match kind:
		"tin", "steel", "mesh":
			return "metal"
		"brick", "stone", "glass":
			return "plaster"
		"dirt", "brush", "rubber", "water":
			return "dirt"
	return "wood"


static func resist(kind: String) -> float:
	return float(RESIST.get(kind, INF))


static func hole(kind: String) -> String:
	return String(HOLES.get(kind, ""))


static func dusty(level: LevelData, x: float, y: float) -> bool:
	var tile := int(level.floor_tile[level.cell(x, y)])
	if tile < 0 or tile >= level.tile_names.size():
		return false
	return String(level.tile_names[tile]) in DUSTY


## What the round met at (x, y, z), a point inside whatever stopped it:
## `surface_tile` is the floor's or roof's tile when that is what it struck.
static func struck(level: LevelData, x: float, y: float, z: float, surface_tile = null) -> String:
	if surface_tile != null:
		return of_tile(level, int(surface_tile))
	return of_tile(level, tile_at(level, x, y, z))


## The tile of the solid thing at (x, y, z): a wall cell, a door, a fixture's
## side, else the floor's.
static func tile_at(level: LevelData, x: float, y: float, z: float) -> int:
	var ix := clampi(int(x), 0, level.width - 1)
	var iy := clampi(int(y), 0, level.height - 1)
	var cell := iy * level.width + ix
	var tile := int(level.solid[cell])
	if tile >= 0:
		return tile
	if level.pane_at(x, y, z, .03) != null:
		return level.tile_id("window")
	for door: LevelData.Door in level.near_doors.get(Vector2i(ix, iy), []):
		if door.blocks(x, y, .03):
			return door.material
	for fixture in level.near_fixtures.get(Vector2i(ix, iy), []):
		var f: PackedFloat32Array = fixture
		if f[0] - .03 < x and x < f[2] + .03 and f[1] - .03 < y and y < f[3] + .03:
			return _side(level, f)
	# Just short of a wall cell (the game's tests reach a body's width round
	# a point): that cell's.
	for k in 4:
		var nx := clampi(int(x + (-.03 if k % 2 == 0 else .03)), 0, level.width - 1)
		var ny := clampi(int(y + (-.03 if k < 2 else .03)), 0, level.height - 1)
		var near := int(level.solid[ny * level.width + nx])
		if near >= 0:
			return near
	return int(level.floor_tile[cell])


## The tile on a fixture's sides: the drawn wall lying along its edge.
static func _side(level: LevelData, f: PackedFloat32Array) -> int:
	if _sides_of != level:
		_sides_of = level
		_sides = {}
	var key := Vector4(f[0], f[1], f[2], f[3])
	if _sides.has(key):
		return int(_sides[key])
	var found := level.tile_id("crate_side")
	var w := level.walls
	for i in level.wall_count:
		var o := i * LevelData.WALL_STRIDE
		var ax := w[o]
		var ay := w[o + 1]
		var bx := w[o + 2]
		var by := w[o + 3]
		var along_x := absf(ay - by) < .01 and (absf(ay - f[1]) < .02 or absf(ay - f[3]) < .02)
		var along_y := absf(ax - bx) < .01 and (absf(ax - f[0]) < .02 or absf(ax - f[2]) < .02)
		if along_x and minf(ax, bx) < f[2] and maxf(ax, bx) > f[0]:
			found = int(w[o + 4])
			break
		if along_y and minf(ay, by) < f[3] and maxf(ay, by) > f[1]:
			found = int(w[o + 4])
			break
	_sides[key] = found
	return found
