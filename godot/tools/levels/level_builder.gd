## Builds a level file (data/<id>.json) from a plan written as code: yards,
## rooms, buildings, fences, doors, fixtures, signs and the people and things
## in them. A plan (tools/levels/<id>_plan.gd) calls these; finish() works out
## the walls the grids imply (src/level_edit.gd, so the editors can patch the
## result), skins the inside of rooms, bands building walls with a foundation
## and an eave, adds the free pieces (signs, cables, awnings) and writes.
##
## Cells are whole map squares; a rectangle is (x0, y0, x1, y1), both corners
## inside it. Heights are in map units: the player's eye is .95 up, a door
## 1.85 tall, a step up at most .245.
extends RefCounted

## Building materials that get a foundation band and an eave band.
const BANDED := ["barn", "tin", "brick", "plaster", "cinder", "office_wall"]
const FOUNDATION := .2
const EAVE := .15
const DOOR_TOP := 1.85

var id := ""
var w := 0
var h := 0
var tile: Dictionary
var solid: Array = []
var floor_tile: Array = []
var ceiling: Array = []
var ground: Array = []
var roof: Array = []
var wall_height: Array = []
var light: Array = []
var area: Array = []
## Per open cell: the tile the walls around it show on this side (-1: their own).
var skin: Array = []
## Per solid cell: false keeps its walls unbanded (fences, hedges, rock).
var banded: Array = []

var doors: Array = []
var fixtures: Array = []
var caps := {}
var extra_walls: Array = []
var pane_tiles: Array = []
var enemies: Array = []
var patrols := {}
var pickups: Array = []
var props: Array = []
var billboards: Array = []
var scenery: Array = []
var stations: Array = []
var notes: Array = []
var interiors: Array = []
var dress_marks: Array = []
var triggers: Array = []
var exchanges: Array = []
var hidden_rooms: Array = []
var discovery_rooms := {}
var map_labels: Array = []
var distant_cues: Array = []
var fuel_drums: Array = []
var partners: Array = []
var controlled_doors: Array = []
var access_doors := {}
var crouch_doors: Array = []
var ruptures := {}
var tints: Array = []
var districts: Array = []
var meta := {}
var rng := RandomNumberGenerator.new()
var _ids := {}
var _town_sizes := {}
## Floor tile -> the tile the step up onto it shows (rock for a quarry bench).
var riser_tiles := {}
## A floor nobody walks on (Gator Bayou's deep water, LevelData.deep_at): the
## checks treat it as blocked. -1: none.
var deep_floor := -1


func _init(level_id: String, width: int, height: int, border := "hedgerow") -> void:
	id = level_id
	w = width
	h = height
	rng.seed = hash(level_id)
	tile = Assets.new().tile_index
	var n := w * h
	for i in n:
		solid.append(t(border))
		floor_tile.append(t("dirt"))
		ceiling.append(t("ceiling"))
		ground.append(0.0)
		roof.append(0.0)
		wall_height.append(2.0)
		light.append(.97)
		area.append(0)
		skin.append(-1)
		banded.append(false)


## A tile's index; a plan naming a tile that does not exist is an error.
func t(name: String) -> int:
	assert(tile.has(name), "no tile " + name)
	return int(tile.get(name, 0))


func at(x: int, y: int) -> int:
	return y * w + x


func inside(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h


## A district: its name on the HUD and the map, and the tint its light takes.
func district(name: String, tint := Color(1, 1, 1)) -> int:
	districts.append(name)
	tints.append([snappedf(tint.r, .01), snappedf(tint.g, .01), snappedf(tint.b, .01)])
	return districts.size() - 1


# ------------------------------------------------------------------ the grids


## Open ground under the sky.
func yard(
	x0: int, y0: int, x1: int, y1: int, floor_name: String, district_id: int, o := {}
) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var i := at(x, y)
			solid[i] = -1
			floor_tile[i] = t(floor_name)
			roof[i] = 0.0
			ground[i] = float(o.get("ground", 0.0))
			light[i] = float(o.get("light", .97))
			area[i] = district_id
			skin[i] = -1


## Open floor under a roof `top` high.
func room(
	x0: int, y0: int, x1: int, y1: int, floor_name: String, district_id: int, o := {}
) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var i := at(x, y)
			solid[i] = -1
			floor_tile[i] = t(floor_name)
			ceiling[i] = t(String(o.get("ceiling", "ceiling")))
			roof[i] = float(o.get("roof", 2.2))
			ground[i] = float(o.get("ground", 0.0))
			light[i] = float(o.get("light", .78))
			area[i] = district_id
			skin[i] = t(String(o["skin"])) if o.has("skin") else -1


## Solid cells: a wall `top` high of `tile_name` (fences, hedges, rock).
func wall(x0: int, y0: int, x1: int, y1: int, tile_name: String, top := 2.0, band := false) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var i := at(x, y)
			solid[i] = t(tile_name)
			wall_height[i] = top
			banded[i] = band


## A building: a ring of `wall` cells (windows every `windows` cells, some
## lit) around a room. Returns nothing; doors are cut with door().
func building(x0: int, y0: int, x1: int, y1: int, district_id: int, o: Dictionary) -> void:
	var top := float(o.get("roof", 2.2))
	var material := String(o.get("wall", "brick"))
	var every := int(o.get("windows", 0))
	var lit := float(o.get("lit", .3))
	var k := 0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if x != x0 and x != x1 and y != y0 and y != y1:
				continue
			var name := material
			var corner := (x == x0 or x == x1) and (y == y0 or y == y1)
			if every > 0 and not corner and (x + y) % every == 0:
				name = material + ("_lit" if rng.randf() < lit else "_win")
				if not tile.has(name):
					name = material
			wall(x, y, x, y, name, top + float(o.get("parapet", .28)), material in BANDED)
			k += 1
	room(
		x0 + 1,
		y0 + 1,
		x1 - 1,
		y1 - 1,
		String(o.get("floor", "wood")),
		district_id,
		{
			"roof": top,
			"ceiling": o.get("ceiling", "ceiling"),
			"light": o.get("light", .74),
			"skin": o.get("skin", material),
		}
	)


## Solid cells' walls built up to `top`: a false front, a tower.
func wall_top(x0: int, y0: int, x1: int, y1: int, top: float) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if int(solid[at(x, y)]) >= 0:
				wall_height[at(x, y)] = top


## Floor tiles over part of the ground (paths, rugs, mud, the road's lines).
func paint(x0: int, y0: int, x1: int, y1: int, floor_name: String) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			floor_tile[at(x, y)] = t(floor_name)


func raise(x0: int, y0: int, x1: int, y1: int, top: float) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			ground[at(x, y)] = top


func lighten(x0: int, y0: int, x1: int, y1: int, value: float) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			light[at(x, y)] = value


## A pool of lamp light on the grid around (x, y), fading out by `reach`.
func glow(x: float, y: float, reach: float, amount: float) -> void:
	for yy in range(int(y - reach), int(y + reach) + 1):
		for xx in range(int(x - reach), int(x + reach) + 1):
			if not inside(xx, yy):
				continue
			var d := Vector2(xx + .5 - x, yy + .5 - y).length()
			if d < reach:
				var i := at(xx, yy)
				light[i] = snappedf(light[i] + amount * (1.0 - d / reach), .0001)


func set_skin(x0: int, y0: int, x1: int, y1: int, tile_name: String) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			skin[at(x, y)] = t(tile_name)


## A door in the wall cell (x, y): the cell opens with a lintel over the door,
## its floor and district from the side named `room_side` (n, s, e or w).
func door(x: int, y: int, vertical: bool, o := {}) -> Dictionary:
	var i := at(x, y)
	var side := String(o.get("from", "w" if vertical else "n"))
	var dx := {"e": 1, "w": -1}.get(side, 0) as int
	var dy := {"s": 1, "n": -1}.get(side, 0) as int
	var j := at(x + dx, y + dy)
	solid[i] = -1
	floor_tile[i] = floor_tile[j]
	ceiling[i] = ceiling[j]
	area[i] = area[j]
	light[i] = light[j]
	ground[i] = 0.0
	roof[i] = float(o.get("roof", DOOR_TOP))
	skin[i] = -1
	var d := {
		"x": x,
		"y": y,
		"style": String(o.get("style", "hinge")),
		"vertical": vertical,
		"key": String(o.get("key", "")),
		"secret": bool(o.get("secret", false)),
		"blast_only": bool(o.get("blast_only", false)),
		"progress": 0,
		"opened": bool(o.get("opened", false)),
		"discovered": false,
		"texture": "",
		"material": t(String(o.get("tile", "door"))),
		"id": String(o.get("id", "")),
	}
	if d["opened"]:
		d["progress"] = 1
	doors.append(d)
	return d


## A gap with no door (an archway, a gate left open).
func gap(x: int, y: int, side: String) -> void:
	door(x, y, side == "e" or side == "w", {"from": side})
	doors.pop_back()


## A hidden room behind a secret door: kept off the map until found.
func secret(x: int, y: int, vertical: bool, room_rect: Array, o := {}) -> void:
	var opts := o.duplicate()
	opts["secret"] = true
	opts["style"] = "slide"
	door(x, y, vertical, opts)
	hidden_rooms.append([[x, y], room_rect])


func window_pane(x: int, y: int) -> void:
	pane_tiles.append([x, y])


# ---------------------------------------------------------------- the pieces


## A box standing on the floor: counters, crates, tables, stalls, car bodies.
## `cap` is the tile on top (seen from above when it is below the eye).
func fixture(
	x0: float,
	y0: float,
	x1: float,
	y1: float,
	top: float,
	side: String,
	cap := "counter_top",
	bottom := 0.0
) -> void:
	var f := [
		snappedf(x0, .01),
		snappedf(y0, .01),
		snappedf(x1, .01),
		snappedf(y1, .01),
		snappedf(top, .01),
		side,
		cap,
		bottom
	]
	fixtures.append(f)
	# Tops worth seeing get a cap; a base a few centimetres high does not (each
	# cap height is a floor plane the renderer draws).
	if top < 1.5 and top >= .15:
		var key := str(snappedf(top, .01))
		if not caps.has(key):
			caps[key] = []
		caps[key].append([f[0], f[1], f[2], f[3], cap])


## A free piece of wall from (ax, ay) to (bx, by), from z0 up to z1: a sign
## board on a front, an awning's edge, a rail. Not part of the grid.
func panel(
	ax: float, ay: float, bx: float, by: float, tile_name: String, z0: float, z1: float, lit := 1.0
) -> void:
	var cx := clampi(int((ax + bx) * .5), 0, w - 1)
	var cy := clampi(int((ay + by) * .5), 0, h - 1)
	extra_walls.append(
		[
			snappedf(ax, .001),
			snappedf(ay, .001),
			snappedf(bx, .001),
			snappedf(by, .001),
			t(tile_name),
			snappedf(lit, .0001),
			snappedf(z0, .001),
			snappedf(z1, .001),
			area[at(cx, cy)]
		]
	)


## A power line between two poles: two thin strands sagging between them.
func cable(ax: float, ay: float, bx: float, by: float, z := 3.3) -> void:
	var mid := Vector2((ax + bx) * .5, (ay + by) * .5)
	for k: float in [-.1, .1]:
		var off := Vector2(by - ay, ax - bx).normalized() * k
		panel(ax + off.x, ay + off.y, mid.x + off.x, mid.y + off.y, "cable", z, z + .03, .88)
		panel(mid.x + off.x, mid.y + off.y, bx + off.x, by + off.y, "cable", z, z + .03, .88)


func prop(name: String, x: float, y: float) -> void:
	assert(GameState.PROP_HEIGHTS.has(name), "no prop " + name)
	props.append([name, snappedf(x, .01), snappedf(y, .01)])


## A picture standing in the world: facing the player (plane NAN) or flat on
## a plane at that angle (a sign nailed to a wall, a notice).
func board(image: String, x: float, y: float, height: float, o := {}) -> void:
	var b := {
		"x": snappedf(x, .01),
		"y": snappedf(y, .01),
		"image": image,
		"height": height,
		"z": float(o.get("z", 0.0)),
		"signal": String(o.get("signal", "")),
		"glow": bool(o.get("glow", false)),
		"plane": o.get("plane"),
		"back": String(o.get("back", "")),
	}
	if o.get("hung", false):
		# Hung on something of its own (a fingerpost's arm): mount_signs()
		# leaves it as it is.
		b["hung"] = true
	billboards.append(b)


## One of the town's modelled props (tools/art/build_town_props.gd), stood
## up at its own size: o.scale, o.z, o.plane (flat on a plane, as a sign) and
## o.glow as board() has them. o.solid gives it a base that blocks the way,
## that wide; a solid prop stands in the middle of its cell.
func town(name: String, x: float, y: float, o := {}) -> void:
	if _town_sizes.is_empty():
		var path := ProjectSettings.globalize_path("res://").path_join(
			"../assets/art/town_props.json"
		)
		_town_sizes = JSON.parse_string(FileAccess.get_file_as_string(path.simplify_path()))
	assert(_town_sizes.has(name), "no town prop " + name)
	var size: Array = _town_sizes[name]
	var px := x
	var py := y
	if o.has("solid"):
		px = floorf(x) + .5
		py = floorf(y) + .5
		var r := float(o["solid"])
		fixture(px - r, py - r, px + r, py + r, .05, String(o.get("base", "dirt")), "dirt")
	var options := o.duplicate()
	options.erase("solid")
	options.erase("scale")
	options.erase("base")
	board("town_" + name, px, py, float(size[1]) * float(o.get("scale", 1.0)), options)


## A quest prop (tools/art/build_quest_art.gd): a modelled station, exit or
## gate bolt standing free on the floor, facing whoever looks at it, as
## town_<name>_off until `signal_name` (a station id, or "exit") is done, then
## town_<name>_on. o.scale, o.z and o.solid as town() has them. It needs no
## plank backing and no posts (mount_signs() leaves it alone).
func quest(name: String, x: float, y: float, signal_name: String, o := {}) -> void:
	var options := o.duplicate()
	options["signal"] = signal_name
	options.erase("plane")
	town(name + "_off", x, y, options)
	billboards[billboards.size() - 1]["image"] = "town_" + name


## A block of four free walls standing up off a roof: a chimney, a gable's
## step, a spire's stage. Walls only, so it is in nobody's way (a fixture
## would block whatever cell it stands over, a doorway included).
func tower(
	x0: float,
	y0: float,
	x1: float,
	y1: float,
	bottom: float,
	top: float,
	tile_name: String,
	lit := .95
) -> void:
	panel(x0, y0, x1, y0, tile_name, bottom, top, lit)
	panel(x1, y0, x1, y1, tile_name, bottom, top, lit * .84)
	panel(x1, y1, x0, y1, tile_name, bottom, top, lit)
	panel(x0, y1, x0, y0, tile_name, bottom, top, lit * .84)


func enemy(kind: String, x: float, y: float, name := "", route := []) -> void:
	var enemy_id := name if name != "" else "%s-%d" % [kind, enemies.size()]
	assert(not _ids.has(enemy_id), "two enemies called " + enemy_id)
	_ids[enemy_id] = true
	enemies.append({"kind": kind, "x": snappedf(x, .01), "y": snappedf(y, .01), "id": enemy_id})
	if not route.is_empty():
		patrols[str(enemies.size() - 1)] = route


func pickup(name: String, x: float, y: float) -> void:
	pickups.append([name, snappedf(x, .01), snappedf(y, .01)])


## Something that reacts when shot or kicked (cans, a TV, a toilet, a window).
func react(kind: String, x: float, y: float, height: float, o := {}) -> void:
	(
		scenery
		. append(
			{
				"id": String(o.get("id", "%s-%d" % [kind, scenery.size()])),
				"kind": kind,
				"x": snappedf(x, .01),
				"y": snappedf(y, .01),
				"height": height,
				"z": float(o.get("z", 0.0)),
				"radius": float(o.get("radius", .25)),
				"opens": o.get("opens", []),
				"station": String(o.get("station", "")),
			}
		)
	)


## A decal on the ground: oil, grain, tyre wear.
func mark(image: String, x: float, y: float, angle: float, reach: float, width: float) -> void:
	dress_marks.append(
		[snappedf(x, .01), snappedf(y, .01), .003, snappedf(angle, .01), reach, width, image]
	)


func label(text: String, x: int, y: int) -> void:
	map_labels.append([text, x, y])


# ---------------------------------------------------------------- the kit
# Pieces every level uses, so a plan says what is there, not how it is made.


func fence(x0: int, y0: int, x1: int, y1: int, top := 1.24, tile_name := "stockyard") -> void:
	wall(x0, y0, x1, y1, tile_name, top)


func hedge(x0: int, y0: int, x1: int, y1: int, top := 1.48) -> void:
	wall(x0, y0, x1, y1, "hedgerow", top)


## A post-and-beam gate over a way through, a sign between the posts. The
## sign shows on the side the gate is walked up to (the side of the hub gate
## or road gate meta names at this spot), the back boards on the other.
func arch(cx: float, y: float, width: float, face: String, back := "stockyard") -> void:
	var l := cx - width * .5
	var r := cx + width * .5
	fixture(l - .17, y - .17, l + .17, y + .17, 2.37, "stockyard", "counter_top")
	fixture(r - .17, y - .17, r + .17, y + .17, 2.37, "stockyard", "counter_top")
	var gates: Array = meta.get("hub_gates", []).duplicate()
	if meta.get("return_gate") != null:
		gates.append(meta["return_gate"])
	var side := -1
	for g: Dictionary in gates:
		if absf(float(g["x"]) - cx) < .5 and absf(float(g["y"]) - y) < .5:
			side = int(g.get("side", 1))
	if side < 0:
		panel(l + .17, y, r - .17, y, face, 1.83, 2.34, 1.29)
		panel(r - .17, y + .035, l + .17, y + .035, back, 1.83, 2.34, .86)
	else:
		panel(l + .17, y, r - .17, y, back, 1.83, 2.34, .86)
		panel(r - .17, y + .035, l + .17, y + .035, face, 1.83, 2.34, 1.29)
	panel(l + .17, y, r - .17, y, "stockyard", 2.34, 2.53, 1.08)


## A fingerpost: a square timber `top` high with an arm for each place, nailed
## on at its height and pointing at it. arms: [picture, the way it points (an
## angle, as the player's), the arm's bottom, its height]; the picture has the
## point on its right and a <picture>_back seen from behind.
func fingerpost(x: float, y: float, arms: Array, top := 2.85) -> void:
	fixture(x - .07, y - .07, x + .07, y + .07, top, "wood", "counter_top")
	for spec: Array in arms:
		var image := String(spec[0])
		var angle := float(spec[1])
		var tall := float(spec[3])
		var span: float = tall * float(_art_shape(image)[0])
		var c := Vector2(x, y) + Vector2(cos(angle), sin(angle)) * (span * .5 + .08)
		board(
			image,
			c.x,
			c.y,
			tall,
			{
				"z": float(spec[2]),
				"plane": snappedf(angle, .0001),
				"back": image + "_back",
				"hung": true
			}
		)


## A lit lamp head on a post and the pool of light under it.
func streetlamp(x: float, y: float, reach := 4.2) -> void:
	board("hub_lamp", x, y, 2.52, {"glow": true})
	glow(x, y, reach, .3)


## Utility poles at the points with the wires strung between them.
func poles(points: Array, z := 3.3) -> void:
	for i in points.size():
		var p: Vector2 = points[i]
		prop("utilitypole", p.x, p.y)
		if i > 0:
			var q: Vector2 = points[i - 1]
			cable(q.x, q.y, p.x, p.y, z)


## An old car: the modelled wreck (a sedan or a pickup; in a derby, a derby
## car) over a low chassis that is in the way and takes the shots.
func car(x: float, y: float, along_x: bool, side := "mill_tin") -> void:
	var lx := 1.7 if along_x else .9
	var ly := .9 if along_x else 1.7
	fixture(x - lx * .5, y - ly * .5, x + lx * .5, y + ly * .5, .3, side, "tin")
	var cx := clampi(int(x), 0, w - 1)
	var cy := clampi(int(y), 0, h - 1)
	var model := "wreck_sedan" if side == "mill_tin" else "wreck_pickup"
	if districts[area[at(cx, cy)]] == "DEMOLITION DERBY":
		model = "derby_car"
	town(model, x, y)


func table(x0: float, y0: float, x1: float, y1: float, top := .62) -> void:
	fixture(x0, y0, x1, y1, top, "wood", "counter_top")


func trough(x0: float, y0: float, x1: float, y1: float) -> void:
	fixture(x0, y0, x1, y1, .45, "tin", "creek")


## A bale standing in the middle of its cell.
func bale(x: float, y: float) -> void:
	var c := Vector2(floorf(x) + .5, floorf(y) + .5)
	fixture(c.x - .42, c.y - .3, c.x + .42, c.y + .3, .62, "feed", "counter_top")


## A crate or a stack of them, in the middle of the cell, `high` tall.
func crate_stack(x: float, y: float, high := .75) -> void:
	var c := Vector2(floorf(x) + .5, floorf(y) + .5)
	fixture(c.x - .36, c.y - .36, c.x + .36, c.y + .36, high, "crate_side", "counter_top")


func scatter(name: String, spots: Array) -> void:
	for p: Vector2 in spots:
		prop(name, p.x, p.y)


## A station: something the objective needs done at (x, y).
func station(
	station_id: String, x: float, y: float, label_text: String, message: String, o := {}
) -> void:
	(
		stations
		. append(
			{
				"id": station_id,
				"x": snappedf(x, .01),
				"y": snappedf(y, .01),
				"label": label_text,
				"message": message,
				"requires": o.get("requires", []),
				"opens": o.get("opens", []),
				"sectors": o.get("sectors", []),
				"cue": String(o.get("cue", "lever_clunk")),
				"reveals_secret": bool(o.get("reveals_secret", false)),
				"hidden": bool(o.get("hidden", false)),
				"action": String(o.get("action", "use")),
				"held": String(o.get("held", "")),
			}
		)
	)


## A door a station opens (no key, no handle of its own).
func controlled(x: int, y: int, vertical: bool, o := {}) -> void:
	door(x, y, vertical, o)
	controlled_doors.append([x, y])


## How far each open cell is from anything (a wall, a piece of furniture, a
## prop, a board, an enemy, a pickup): the empty ground a pass should fill.
func emptiness() -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(w * h)
	dist.fill(99)
	var todo: Array = []
	var seed_cell := func(x: int, y: int) -> void:
		if inside(x, y) and dist[at(x, y)] != 0:
			dist[at(x, y)] = 0
			todo.append(Vector2i(x, y))
	for y in h:
		for x in w:
			if int(solid[at(x, y)]) >= 0:
				seed_cell.call(x, y)
	for f: Array in fixtures:
		for y in range(int(f[1]), int(f[3]) + 1):
			for x in range(int(f[0]), int(f[2]) + 1):
				seed_cell.call(x, y)
	for list in [pickups, props]:
		for p: Array in list:
			seed_cell.call(int(p[1]), int(p[2]))
	for e: Dictionary in enemies:
		seed_cell.call(int(e["x"]), int(e["y"]))
	for bd: Dictionary in billboards:
		seed_cell.call(int(bd["x"]), int(bd["y"]))
	for s: Dictionary in scenery:
		seed_cell.call(int(s["x"]), int(s["y"]))
	for s: Dictionary in stations:
		seed_cell.call(int(s["x"]), int(s["y"]))
	var head := 0
	while head < todo.size():
		var c: Vector2i = todo[head]
		head += 1
		var d := dist[at(c.x, c.y)] + 1
		for k in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + k
			if inside(n.x, n.y) and dist[at(n.x, n.y)] > d:
				dist[at(n.x, n.y)] = d
				todo.append(n)
	return dist


var _art_shapes := {}


## A picture's [width / height, how much of it is solid (0 to 1)].
func _art_shape(image: String) -> Array:
	if not _art_shapes.has(image):
		var folder := ProjectSettings.globalize_path("res://").path_join("../assets/art")
		var path := folder.path_join("%s.png" % image).simplify_path()
		if not FileAccess.file_exists(path):
			# A board that lights up (signal) has _on and _off pictures.
			path = folder.path_join("%s_off.png" % image).simplify_path()
		var pic := Image.load_from_file(path)
		var solid_px := 0
		for y in pic.get_height():
			for x in pic.get_width():
				if pic.get_pixel(x, y).a > .5:
					solid_px += 1
		_art_shapes[image] = [
			float(pic.get_width()) / pic.get_height(),
			float(solid_px) / (pic.get_width() * pic.get_height())
		]
	return _art_shapes[image]


## How far from a flat picture at `c` (`span` wide along `along`, from `z0` to
## `z1` up) the first wall, door, piece of furniture or panel stands, going `way`.
func _clear_along(
	c: Vector2, along: Vector2, span: float, way: Vector2, z0: float, z1: float, reach := .7
) -> float:
	var door_cells := {}
	for d: Dictionary in doors:
		door_cells[Vector2i(int(d["x"]), int(d["y"]))] = true
	var nearest := 9.0
	for t: float in [-.38, 0.0, .38]:
		var base := c + along * span * t
		var step := .04
		while step < minf(nearest, reach):
			var q := base + way * step
			var cell := Vector2i(int(floorf(q.x)), int(floorf(q.y)))
			var hit := not inside(cell.x, cell.y) or int(solid[at(cell.x, cell.y)]) >= 0
			hit = hit or door_cells.has(cell)
			if not hit:
				for f: Array in fixtures:
					if (
						float(f[0]) <= q.x
						and q.x <= float(f[2])
						and float(f[1]) <= q.y
						and q.y <= float(f[3])
						and float(f[4]) > z0 + .1
						and float(f[7]) < z1
					):
						hit = true
						break
			if not hit:
				for wl: Array in extra_walls:
					var p0 := Vector2(float(wl[0]), float(wl[1]))
					var p1 := Vector2(float(wl[2]), float(wl[3]))
					var on := Geometry2D.get_closest_point_to_segment(q, p0, p1)
					if on.distance_to(q) < .04 and float(wl[7]) > z0 and float(wl[6]) < z1:
						hit = true
						break
			if hit:
				nearest = minf(nearest, step)
				break
			step += .04 if step < .7 else .2
	return nearest


## Every flat sign gets something to hang on (build_level.gd runs this after
## the plan). One whose face looks into a wall while its back is open is turned
## round. A sign or piece of equipment with nothing behind it gets a plank
## backing a little bigger than it (a cut-out picture, a stake or a line of
## washing, gets none), its faces a hair either side; ground decals are not
## pictures and are left alone; one up off the ground with nothing under it gets two posts
## down to the ground.
func mount_signs() -> void:
	for bd: Dictionary in billboards.duplicate():
		if bd.has("hung"):
			bd.erase("hung")
			continue
		# Quest props are modelled whole and stand on their own feet.
		if bd["plane"] == null or String(bd["image"]).begins_with("town_quest_"):
			continue
		var image := String(bd["image"])
		var shape := _art_shape(image)
		var tall := float(bd["height"])
		var span: float = tall * float(shape[0])
		var z := float(bd["z"])
		var plane := float(bd["plane"])
		var c := Vector2(float(bd["x"]), float(bd["y"]))
		var along := Vector2(cos(plane), sin(plane))
		var face := Vector2(-sin(plane), cos(plane))
		var two_sided := String(bd["back"]) != ""
		var ahead := _clear_along(c, along, span, face, z, z + tall)
		var behind := _clear_along(c, along, span, -face, z, z + tall)
		var open_ahead := _clear_along(c, along, span, face, z, z + tall, 4.0)
		var open_behind := _clear_along(c, along, span, -face, z, z + tall, 4.0)
		var into_wall := ahead < .3 and behind >= .3
		var to_corner := open_ahead < 1.5 and open_behind > open_ahead + 1.0
		if not two_sided and (into_wall or to_corner):
			# Painted facing the wall it hangs on, or a fence a step away, with the
			# way people come from behind it: nobody would see it.
			plane = fposmod(plane + PI, TAU)
			bd["plane"] = snappedf(plane, .0001)
			along = -along
			face = -face
			var swap := ahead
			ahead = behind
			behind = swap
		if behind <= .26:
			continue
		# A painted board or a piece of equipment (detail_*) hangs on planks; a
		# cut-out (a stake, an arrow, washing on a line) on its posts alone.
		var board_like := float(shape[1]) > .82 or image.begins_with("detail_")
		if board_like:
			var m := .05
			var p0 := c - along * (span * .5 + m)
			var p1 := c + along * (span * .5 + m)
			panel(p0.x, p0.y, p1.x, p1.y, "wood", z - m, z + tall + m, .82)
			var front := c + face * .02
			bd["x"] = snappedf(front.x, .01)
			bd["y"] = snappedf(front.y, .01)
			if two_sided:
				var rear := c - face * .02
				board(bd["back"], rear.x, rear.y, tall, {"z": z, "plane": fposmod(plane + PI, TAU)})
				bd["back"] = ""
		# Posts only for a sign within reach of the ground: one up on a roof or a
		# water tank belongs to that, not to poles from the dirt.
		if z < .12 or z + tall > 2.6:
			continue
		var seated := false
		for f: Array in fixtures:
			var mid := Vector2((float(f[0]) + float(f[2])) * .5, (float(f[1]) + float(f[3])) * .5)
			if (
				absf(float(f[4]) - z) < .2
				and absf((mid - c).dot(along)) < span * .5 + .3
				and absf((mid - c).dot(face)) < .5
			):
				seated = true
				break
		if seated:
			continue
		# Posts are free walls (tower), not furniture: slim, in nobody's way.
		var post_top := z + tall * (.6 if board_like else .95)
		for side: float in [-1.0, 1.0]:
			var q := c + along * side * maxf(span * .5 - .04, .05) - face * .03
			tower(q.x - .035, q.y - .035, q.x + .035, q.y + .035, 0.0, post_top, "wood", .8)


func _taken_cells() -> Dictionary:
	var taken := {}
	for d: Dictionary in doors:
		taken[Vector2i(int(d["x"]), int(d["y"]))] = true
		for k in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			taken[Vector2i(int(d["x"]), int(d["y"])) + k] = true
	# Round what stands about, a cell's margin: it may stand on a cell's edge.
	var spots: Array = []
	for list in [pickups, props]:
		for p: Array in list:
			spots.append(Vector2(float(p[1]), float(p[2])))
	for e: Dictionary in enemies:
		spots.append(Vector2(float(e["x"]), float(e["y"])))
	for s: Dictionary in stations:
		spots.append(Vector2(float(s["x"]), float(s["y"])))
	for p: Vector2 in spots:
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				taken[Vector2i(int(p.x) + dx, int(p.y) + dy)] = true
	for bd: Dictionary in billboards:
		if bd["plane"] == null:
			taken[Vector2i(int(bd["x"]), int(bd["y"]))] = true
	for s: Dictionary in scenery:
		taken[Vector2i(int(s["x"]), int(s["y"]))] = true
	return taken


func _roomy(x: int, y: int, _taken: Dictionary) -> bool:
	if not inside(x, y) or _cell_blocked(x, y):
		return false
	var g := float(ground[at(x, y)])
	for d in [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1),
		Vector2i(1, 1),
		Vector2i(-1, -1),
		Vector2i(1, -1),
		Vector2i(-1, 1)
	]:
		var n: Vector2i = Vector2i(x, y) + d
		if (
			not inside(n.x, n.y)
			or _cell_blocked(n.x, n.y)
			or absf(float(ground[at(n.x, n.y)]) - g) > .01
		):
			return false
	return true


# --------------------------------------------------------------------- finish


func level_dict() -> Dictionary:
	var level := {
		"id": id,
		"width": w,
		"height": h,
		"solid": solid,
		"floor": floor_tile,
		"ceiling": ceiling,
		"ground": ground,
		"roof": roof,
		"wall_height": wall_height,
		"light": light,
		"area": area,
		"fixtures": fixtures,
	}
	return level


## The walls: those the grids imply, each wall facing a skinned cell showing
## the skin, building walls banded, then the free pieces.
func build_walls() -> Array:
	var level := level_dict()
	var implied: Array = LevelEdit.implied_walls(level, tile)
	var out: Array = []
	for wall_row: Array in implied:
		var ax := float(wall_row[0])
		var ay := float(wall_row[1])
		var bx := float(wall_row[2])
		var by := float(wall_row[3])
		var on_grid := (
			ax == floorf(ax) and ay == floorf(ay) and bx == floorf(bx) and by == floorf(by)
		)
		if not on_grid or float(wall_row[6]) < 0.0 or float(wall_row[7]) - float(wall_row[6]) < 1.0:
			out.append(_riser_at(wall_row))
			continue
		# The two cells either side of the edge: one open, one solid.
		var mid := Vector2((ax + bx) * .5, (ay + by) * .5)
		var normal := Vector2(by - ay, ax - bx).normalized() * .5
		var c1 := Vector2i(floori(mid.x + normal.x), floori(mid.y + normal.y))
		var c2 := Vector2i(floori(mid.x - normal.x), floori(mid.y - normal.y))
		if not inside(c1.x, c1.y) or not inside(c2.x, c2.y):
			out.append(wall_row)
			continue
		var open_cell := c1 if int(solid[at(c1.x, c1.y)]) < 0 else c2
		var wall_cell := c2 if open_cell == c1 else c1
		var oi := at(open_cell.x, open_cell.y)
		var wi := at(wall_cell.x, wall_cell.y)
		if int(solid[wi]) < 0:
			out.append(_riser(wall_row, at(c1.x, c1.y), at(c2.x, c2.y)))
			continue
		var row := wall_row.duplicate()
		if int(skin[oi]) >= 0:
			row[4] = skin[oi]
		var material := String(_name_of(int(row[4]))).trim_suffix("_win").trim_suffix("_lit")
		# Bands on the outside of a building only: the trims are pieces of
		# their own, and indoors nobody looks at the skirting.
		if not banded[wi] or not (material in BANDED) or float(roof[oi]) > 0.0:
			out.append(row)
			continue
		var bottom := float(row[6])
		var top := float(row[7])
		var foot := row.duplicate()
		foot[4] = t("trim_foundation")
		foot[7] = snappedf(bottom + FOUNDATION, .001)
		var body := row.duplicate()
		body[6] = foot[7]
		body[7] = snappedf(top - EAVE, .001)
		var cap := row.duplicate()
		cap[4] = t("trim_eave")
		cap[6] = body[7]
		cap[5] = snappedf(float(row[5]) * .92, .0001)
		out.append(foot)
		out.append(body)
		out.append(cap)
	for wall_row: Array in out:
		wall_row[5] = snappedf(float(wall_row[5]), .0001)
	out.append_array(extra_walls)
	return out


## The finale wave (meta "wave": enemy names), as the indexes the game wants.
func _wave_indexes() -> Array:
	var out: Array = meta.get("reinforcements", []).duplicate()
	for name in meta.get("wave", []):
		for i in enemies.size():
			if String(enemies[i]["id"]) == String(name):
				out.append(i)
	return out


## A trailer home, 8 by 4 cells, a door on its long side facing `door_side`.
func trailer(x0: int, y0: int, door_side: String, district_id: int) -> void:
	building(
		x0,
		y0,
		x0 + 7,
		y0 + 3,
		district_id,
		{"wall": "trailer", "roof": 2.0, "parapet": .12, "floor": "floor_tile", "light": .66}
	)
	for x in [x0 + 2, x0 + 5]:
		wall(x, y0, x, y0, "trailer_window", 2.12)
		wall(x, y0 + 3, x, y0 + 3, "trailer_window", 2.12)
	var dy := y0 + 3 if door_side == "s" else y0
	door(x0 + 3, dy, false, {"from": "n" if door_side == "s" else "s", "style": "slide"})
	prop("lamp", x0 + 4.5, y0 + 1.5)


## A booth with an open front: a counter across it, an awning over it, its
## goods (a sign board) on the back wall. front: n, s, e or w.
func booth(x0: int, y0: int, x1: int, y1: int, district_id: int, front: String, o := {}) -> void:
	building(
		x0,
		y0,
		x1,
		y1,
		district_id,
		{
			"wall": String(o.get("wall", "fair_booth")),
			"roof": float(o.get("roof", 2.3)),
			"floor": String(o.get("floor", "porch")),
			"light": float(o.get("light", .9)),
			"skin": String(o.get("skin", "fair_prize")),
			"windows": int(o.get("windows", 0)),
		}
	)
	# Open the front wall (corners kept) under an awning and set the counter in it.
	var cells: Array = []
	if front == "s" or front == "n":
		var y := y1 if front == "s" else y0
		for x in range(x0 + 1, x1):
			cells.append(Vector2i(x, y))
	else:
		var x := x1 if front == "e" else x0
		for y in range(y0 + 1, y1):
			cells.append(Vector2i(x, y))
	for c: Vector2i in cells:
		room(
			c.x,
			c.y,
			c.x,
			c.y,
			String(o.get("floor", "porch")),
			district_id,
			{"roof": 2.05, "light": 1.0}
		)
	var a: Vector2i = cells[0]
	var b: Vector2i = cells[cells.size() - 1]
	if front == "s" or front == "n":
		fixture(a.x, a.y + .3, b.x + 1, a.y + .7, .95, "counter", "counter_top")
	else:
		fixture(a.x + .3, a.y, a.x + .7, b.y + 1, .95, "counter", "counter_top")
	if o.has("sign"):
		var mid := (Vector2(a) + Vector2(b)) * .5 + Vector2(.5, .5)
		var plane := {"s": 0.0, "n": PI, "e": -PI / 2, "w": PI / 2}[front] as float
		var out := (
			{
				"s": Vector2(0, .62),
				"n": Vector2(0, -.62),
				"e": Vector2(.62, 0),
				"w": Vector2(-.62, 0)
			}[front]
			as Vector2
		)
		board(String(o["sign"]), mid.x + out.x, mid.y + out.y, .7, {"z": 1.75, "plane": plane})
	prop("lamp", (x0 + x1 + 1) * .5, (y0 + y1 + 1) * .5)


## A step between two open cells, in the upper cell's riser tile if it has one.
func _riser(row: Array, a: int, b: int) -> Array:
	if riser_tiles.is_empty() or int(solid[a]) >= 0 or int(solid[b]) >= 0:
		return row
	var upper := a if float(ground[a]) > float(ground[b]) else b
	var name := _name_of(int(floor_tile[upper]))
	if not riser_tiles.has(name):
		return row
	var out := row.duplicate()
	out[4] = t(String(riser_tiles[name]))
	return out


func _riser_at(row: Array) -> Array:
	if riser_tiles.is_empty():
		return row
	var ax := float(row[0])
	var ay := float(row[1])
	var bx := float(row[2])
	var by := float(row[3])
	if not (ax == floorf(ax) and ay == floorf(ay) and bx == floorf(bx) and by == floorf(by)):
		return row
	var mid := Vector2((ax + bx) * .5, (ay + by) * .5)
	var normal := Vector2(by - ay, ax - bx).normalized() * .5
	var c1 := Vector2i(floori(mid.x + normal.x), floori(mid.y + normal.y))
	var c2 := Vector2i(floori(mid.x - normal.x), floori(mid.y - normal.y))
	if not inside(c1.x, c1.y) or not inside(c2.x, c2.y):
		return row
	return _riser(row, at(c1.x, c1.y), at(c2.x, c2.y))


func _name_of(index: int) -> String:
	for name: String in tile:
		if int(tile[name]) == index:
			return name
	return ""


func finish(spawn: Array) -> Dictionary:
	var level := level_dict()
	level["walls"] = build_walls()
	var out := {
		"id": id,
		"title": String(meta.get("title", id.to_upper())),
		"heading": meta.get("heading", []),
		"intro": String(meta.get("intro", "")),
		"ending": String(meta.get("ending", "")),
		"score": String(meta.get("score", "music")),
		"ambience": String(meta.get("ambience", "")),
		"rescue": bool(meta.get("rescue", false)),
		"layout": int(meta.get("layout", 1)),
		"spawn": spawn,
		"districts": districts,
		"map_labels": map_labels,
		"hidden_rooms": hidden_rooms,
		"width": w,
		"height": h,
		"sky": String(meta.get("sky", "sky")),
		"control_name": String(meta.get("control_name", "")),
		"mirror": meta.get("mirror"),
		"solid": solid,
		"floor": floor_tile,
		"ceiling": ceiling,
		"ground": ground,
		"roof": roof,
		"wall_height": wall_height,
		"light": light,
		"area": area,
		"tints": tints,
		"ground_heights": [],
		"roof_heights": [],
		"walls": level["walls"],
		"doors": doors,
		"fixtures": fixtures,
		"collision_volumes": fixtures.duplicate(true),
		"caps": caps,
		"pane_tiles": pane_tiles,
		"enemies": enemies,
		"patrols": patrols,
		"pickups": pickups,
		"props": props,
		"fuel_drums": fuel_drums,
		"billboards": billboards,
		"scenery": scenery,
		"stations": stations,
		"extraction": meta.get("extraction"),
		"reinforcements": _wave_indexes(),
		"controlled_doors": controlled_doors,
		"access_doors": access_doors,
		"objective_side_tasks": meta.get("objective_side_tasks", []),
		"crouch_doors": crouch_doors,
		"discovery_rooms": discovery_rooms,
		"dress_marks": dress_marks,
		"distant_cues": distant_cues,
		"return_gate": meta.get("return_gate"),
		"hub_gates": meta.get("hub_gates", []),
		"hub_clues": meta.get("hub_clues", []),
		"hub_board": meta.get("hub_board"),
		"map_window": meta.get("map_window", []),
		"notes": notes,
		"interiors": interiors,
		"partners": partners,
		"ruptures": ruptures,
		"recovery_room": meta.get("recovery_room"),
		"exchanges": exchanges,
		"triggers": triggers,
		"devices": meta.get("devices", []),
		"area_sounds": meta.get("area_sounds", {}),
		"area_cues": meta.get("area_cues", {}),
		"gallery": meta.get("gallery"),
		"pressure_ports": meta.get("pressure_ports", []),
		"boss_decoys": meta.get("boss_decoys", []),
		"lap_cars": meta.get("lap_cars", {}),
	}
	if meta.has("boss_arena"):
		# Where a boss arena's hazards stand (features/boss_arena.gd).
		out["boss_arena"] = meta["boss_arena"]
	LevelEdit.refresh_heights(out)
	var roofs := {}
	for v in roof:
		if float(v) > 0.0:
			roofs[snappedf(float(v), .0001)] = true
	var sorted := roofs.keys()
	sorted.sort()
	out["roof_heights"] = sorted
	return out


## Checks a plan should pass before it is written: every enemy, pickup, prop
## and station on open floor, the spawn too, and every door in a wall line.
func problems(spawn: Array) -> Array:
	var out: Array = []
	var spots: Array = [["spawn", spawn[0], spawn[1]]]
	for e: Dictionary in enemies:
		# One that swims (enemies.cfg) may start out in deep water nobody can walk to.
		var swims := bool(Enemy.DEFS.get(String(e["kind"]), {}).get("swims", false))
		spots.append(["enemy " + String(e["id"]), e["x"], e["y"], swims])
	for p: Array in pickups:
		spots.append(["pickup " + String(p[0]), p[1], p[2]])
	for s: Dictionary in stations:
		spots.append(["station " + String(s["id"]), s["x"], s["y"]])
	# Every picture a board or a mark names must be in the art (a board with a
	# signal has an _on and an _off picture instead).
	var art: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://assets_gen/art_index.json")
	)
	for board: Dictionary in billboards:
		var image := String(board["image"])
		var names := [image] if String(board["signal"]) == "" else [image + "_on", image + "_off"]
		if board["back"] != "":
			names.append(String(board["back"]))
		for name: String in names:
			if not art.has(name):
				out.append("board at %.2f, %.2f: no picture %s" % [board["x"], board["y"], name])
	for m: Array in dress_marks:
		if not art.has(String(m[6])):
			out.append("mark at %.2f, %.2f: no picture %s" % [m[0], m[1], m[6]])
	# Paths are planned cell to cell (src/flow_field.gd: a cell is open when a
	# body fits at its middle). A thin piece across the line between two open
	# middles stops whoever walks it, the player's pin and the enemies alike.
	for f: Array in fixtures:
		var x0 := float(f[0]) - .2
		var y0 := float(f[1]) - .2
		var x1 := float(f[2]) + .2
		var y1 := float(f[3]) + .2
		for y in range(maxi(0, int(y0) - 1), mini(h - 1, int(y1) + 1) + 1):
			for x in range(maxi(0, int(x0) - 1), mini(w - 1, int(x1) + 1) + 1):
				for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
					var a := Vector2(x + .5, y + .5)
					var c := a + Vector2(d)
					if not inside(x + d.x, y + d.y):
						continue
					if _cell_blocked(x, y) or _cell_blocked(x + d.x, y + d.y):
						continue
					var cuts := (
						(d.x == 1 and y0 < a.y and a.y < y1 and x0 < c.x and a.x < x1)
						or (d.y == 1 and x0 < a.x and a.x < x1 and y0 < c.y and a.y < y1)
					)
					if cuts:
						out.append(
							(
								"fixture %.2f,%.2f-%.2f,%.2f cuts the way from cell %d,%d to %d,%d"
								% [f[0], f[1], f[2], f[3], x, y, x + d.x, y + d.y]
							)
						)
	# Everything that matters can be walked to from the start (doors open,
	# steps up of a step's height at most).
	var reached := _reach_from(int(spawn[0]), int(spawn[1]))
	for spot: Array in spots:
		var cell := Vector2i(int(spot[1]), int(spot[2]))
		if spot.size() > 3 and bool(spot[3]):
			continue
		if inside(cell.x, cell.y) and int(solid[at(cell.x, cell.y)]) < 0 and not reached.has(cell):
			var near := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				near = near or reached.has(cell + d)
			if not near:
				out.append(
					(
						"%s at %.2f, %.2f cannot be reached from the start"
						% [spot[0], spot[1], spot[2]]
					)
				)
	for spot: Array in spots:
		var x := int(spot[1])
		var y := int(spot[2])
		if not inside(x, y) or int(solid[at(x, y)]) >= 0:
			out.append("%s at %.2f, %.2f is in a wall" % [spot[0], spot[1], spot[2]])
			continue
		for f: Array in fixtures:
			if (
				float(f[0]) - .2 < float(spot[1])
				and float(spot[1]) < float(f[2]) + .2
				and float(f[1]) - .2 < float(spot[2])
				and float(spot[2]) < float(f[3]) + .2
				and String(spot[0]).begins_with("station") == false
			):
				out.append("%s at %.2f, %.2f is in a fixture" % [spot[0], spot[1], spot[2]])
	return out


## A cell nobody can stand in the middle of: solid, or a fixture there.
func _cell_blocked(x: int, y: int) -> bool:
	if int(solid[at(x, y)]) >= 0:
		return true
	if deep_floor >= 0 and int(floor_tile[at(x, y)]) == deep_floor:
		return true
	var cx := x + .5
	var cy := y + .5
	for f: Array in fixtures:
		if (
			float(f[0]) - .2 < cx
			and cx < float(f[2]) + .2
			and float(f[1]) - .2 < cy
			and cy < float(f[3]) + .2
		):
			return true
	return false


## The cells a player can walk to from (x, y): through doors, up steps no
## higher than a step (down anything), round anything standing in a cell.
func _reach_from(x: int, y: int) -> Dictionary:
	var seen := {Vector2i(x, y): true}
	var todo: Array = [Vector2i(x, y)]
	var door_cells := {}
	for d: Dictionary in doors:
		door_cells[Vector2i(int(d["x"]), int(d["y"]))] = true
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if seen.has(n) or not inside(n.x, n.y):
				continue
			if int(solid[at(n.x, n.y)]) >= 0 and not door_cells.has(n):
				continue
			if _cell_blocked(n.x, n.y) and not door_cells.has(n):
				continue
			if float(ground[at(n.x, n.y)]) - float(ground[at(c.x, c.y)]) > .25:
				continue
			seen[n] = true
			todo.append(n)
	return seen
