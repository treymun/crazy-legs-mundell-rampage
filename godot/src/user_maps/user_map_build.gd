## A player map (UserMap) compiled into a level dictionary the game loads
## like any other (LevelData.from_dict, through LevelData.preview). Only the
## palette's cells and things come out, so whatever a file says, the level is
## one the game's own levels could be: one cell of hedgerow round the map,
## walls the grids imply (LevelEdit.implied_walls) with a foundation and eave
## band on a building's outside, doors hung in their wall lines with a lintel
## up to the wall's top, lamp light on the grid, props stood up at their own
## size, the lever and the getaway truck as the chapters' quest props.
##
## `versus` builds the copy the versus modes and COUNTY RUN play on: no hands,
## no lever, no truck (its level id ends in UserMap.VERSUS_TAIL).
class_name UserMapBuild
extends RefCounted

const BORDER := "hedgerow"
const BORDER_TOP := 2.0
const DOOR_TOP := 1.85
const FASCIA_TOP := DOOR_TOP + .35
const OUTSIDE_LIGHT := .97
const INSIDE_LIGHT := .74
const LIGHT_MOST := 1.45
const BANDED := ["barn", "tin", "brick", "plaster", "cinder"]
const FOUNDATION := .2
const EAVE := .15
const GLOW_REACH := 4.2
## Where the 5v5 spawns stand round a start mark, and how many.
const TEAM_SPOTS := 5


static func level(map: Dictionary, versus := false) -> Dictionary:
	var tiles := UserMap.tile_index()
	var w := UserMap.width(map) + 2
	var h := UserMap.height(map) + 2
	var n := w * h
	var border: int = tiles.get(BORDER, 0)
	var solid: Array = []
	var floor_tile: Array = []
	var ceiling: Array = []
	var ground: Array = []
	var roof: Array = []
	var wall_height: Array = []
	var light: Array = []
	var area: Array = []
	var dirt: int = tiles.get("dirt", 0)
	var ceiling_tile: int = tiles.get("ceiling", 0)
	for i in n:
		solid.append(border)
		floor_tile.append(dirt)
		ceiling.append(ceiling_tile)
		ground.append(0.0)
		roof.append(0.0)
		wall_height.append(BORDER_TOP)
		light.append(OUTSIDE_LIGHT)
		area.append(0)
	var doors: Array = []
	var lintels: Array = []
	for y in UserMap.height(map):
		for x in UserMap.width(map):
			var key := UserMap.at(map, x, y)
			var spec := UserMap.cell(key)
			var i := (y + 1) * w + x + 1
			var group := str(spec["group"])
			var tile: int = tiles.get(str(spec["tile"]), 0)
			if group == "wall":
				solid[i] = tile
				var top: float = spec.get("top", 2.9)
				wall_height[i] = top
				continue
			if group == "door":
				var way := UserMap.door_way(map, x, y)
				if way < 0:
					# Not in a wall line: it stands as the wall it sits in.
					solid[i] = tiles.get("barn", 0)
					wall_height[i] = 2.9
					continue
				doors.append(_door(x + 1, y + 1, way == 1, tiles, versus))
				lintels.append([x, y, way])
				continue
			solid[i] = -1
			floor_tile[i] = tile
			var lift: float = spec.get("ground", 0.0)
			ground[i] = lift
			var over: float = spec.get("roof", 0.0)
			roof[i] = over
			light[i] = INSIDE_LIGHT if over > 0.0 else OUTSIDE_LIGHT
	# A door cell takes the floor, roof and light of an open side.
	for d: Array in lintels:
		var x: int = d[0]
		var y: int = d[1]
		var i := (y + 1) * w + x + 1
		var side := Vector2i(1, 0) if d[2] == 1 else Vector2i(0, 1)
		var j := (y + 1 + side.y) * w + x + 1 + side.x
		var k := (y + 1 - side.y) * w + x + 1 - side.x
		var roof_j: float = roof[j]
		var inner := j if roof_j > 0.0 else k
		solid[i] = -1
		floor_tile[i] = floor_tile[inner]
		ceiling[i] = ceiling[inner]
		light[i] = light[inner]
		ground[i] = 0.0
		roof[i] = DOOR_TOP
	var level_dict := {
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
	}
	var fixtures: Array = []
	var billboards: Array = []
	var props: Array = []
	var enemies: Array = []
	var pickups: Array = []
	var stations: Array = []
	var extraction: Variant = null
	var spawn := [w * .5, h * .5, 0.0]
	var start: Variant = UserMap.mark(map, "start")
	var lamps: Array = []
	for v: Variant in map["things"]:
		var t: Array = v
		var kind := str(t[0])
		var name := str(t[1])
		var cx: int = t[2]
		var cy: int = t[3]
		var facing: int = t[4]
		var x := cx + 1.5
		var y := cy + 1.5
		var spec := UserMap.thing(kind, name)
		match kind:
			"hand":
				if not versus:
					enemies.append(
						{"kind": name, "x": x, "y": y, "id": "%s-%d" % [name, enemies.size()]}
					)
			"loot":
				pickups.append([name, x, y])
			"prop":
				var solid_r: float = spec.get("solid", 0.0)
				if solid_r > 0.0:
					fixtures.append(
						[x - solid_r, y - solid_r, x + solid_r, y + solid_r, .05, "dirt", "dirt", 0]
					)
				var old: bool = spec.get("old", false)
				if old:
					props.append([name, x, y])
				else:
					var tall: float = spec.get("height", 1.0)
					billboards.append(_board("town_" + name, x, y, tall, ""))
				var glow: float = spec.get("glow", 0.0)
				if glow > 0.0:
					lamps.append([x, y, glow])
			"mark":
				match name:
					"start":
						spawn = [x, y, _angle(facing)]
					"lever":
						if not versus:
							stations.append(_lever(x, y))
							billboards.append(
								_board("town_quest_switch", x, y, _num(spec, "height"), "lever")
							)
					"goal":
						if not versus:
							extraction = {
								"x": x, "y": y, "label": "HIT THE ROAD", "shutdown": "lever"
							}
							billboards.append(
								_board("town_quest_exit", x, y, _num(spec, "height"), "exit")
							)
	if start == null:
		var first: Variant = UserMap.mark(map, "attack")
		if first == null:
			first = _first_open(map)
		var at: Vector2i = first
		spawn = [at.x + 1.5, at.y + 1.5, 0.0]
	for lamp: Array in lamps:
		var lx: float = lamp[0]
		var ly: float = lamp[1]
		var amount: float = lamp[2]
		_glow(level_dict, lx, ly, amount)
	var walls := _walls(level_dict, tiles)
	walls.append_array(_lintel_walls(map, level_dict, lintels, tiles))
	var mood := UserMap.mood(str(map.get("mood", "dusk")))
	var title := str(map["name"])
	var by := str(map.get("author", ""))
	var note := str(map.get("note", ""))
	var out := {
		"id": UserMap.level_id(map, versus),
		"title": title,
		"heading": ["A COUNTY MAP", title],
		"intro":
		note if note != "" else ("MADE BY %s." % by if by != "" else "A MAP FROM THE MAP SHED."),
		"ending": "",
		"score": str(mood["score"]),
		"ambience": str(mood["ambience"]),
		"rescue": false,
		"layout": 1,
		"spawn": spawn,
		"districts": [title],
		"map_labels": [],
		"width": w,
		"height": h,
		"sky": str(mood["sky"]),
		"control_name": "",
		"mirror": null,
		"solid": solid,
		"floor": floor_tile,
		"ceiling": ceiling,
		"ground": ground,
		"roof": roof,
		"wall_height": wall_height,
		"light": light,
		"area": area,
		"tints": [[1.0, 1.0, 1.0]],
		"ground_heights": [],
		"roof_heights": [],
		"walls": walls,
		"doors": doors,
		"fixtures": fixtures,
		"collision_volumes": fixtures.duplicate(true),
		"caps": {},
		"enemies": enemies,
		"pickups": pickups,
		"props": props,
		"billboards": billboards,
		"stations": stations,
		"extraction": extraction,
		"tactical": _tactical(map),
	}
	LevelEdit.refresh_heights(out)
	var roofs := {}
	for v: float in roof:
		if v > 0.0:
			roofs[snappedf(v, .0001)] = true
	var sorted := roofs.keys()
	sorted.sort()
	out["roof_heights"] = sorted
	return out


static func _num(spec: Dictionary, key: String) -> float:
	var value: float = spec.get(key, 1.0)
	return value


## A swing door; in the versus copy it stands open (the bots path through
## doorways, and a round has no time for doors).
static func _door(x: int, y: int, vertical: bool, tiles: Dictionary, open := false) -> Dictionary:
	return {
		"x": x,
		"y": y,
		"style": "hinge",
		"vertical": vertical,
		"key": "",
		"secret": false,
		"blast_only": false,
		"progress": 1 if open else 0,
		"opened": open,
		"discovered": false,
		"texture": "",
		"material": tiles.get("door", 0),
		"id": "",
	}


static func _board(
	image: String, x: float, y: float, tall: float, signal_name: String
) -> Dictionary:
	return {
		"x": x,
		"y": y,
		"image": image,
		"height": tall,
		"z": 0.0,
		"signal": signal_name,
		"glow": false,
		"plane": null,
		"back": "",
	}


static func _lever(x: float, y: float) -> Dictionary:
	return {
		"id": "lever",
		"x": x,
		"y": y,
		"label": "THROW THE BIG LEVER",
		"message": "LEVER'S THROWN. GET TO THE TRUCK.",
		"requires": [],
		"opens": [],
		"sectors": [],
		"cue": "lever_clunk",
		"reveals_secret": false,
		"hidden": false,
		"action": "use",
		"held": "",
	}


## Facing 0..7 (east, then clockwise in eighths) as an angle.
static func _angle(facing: int) -> float:
	return snappedf(facing * PI / 4.0, .0001)


static func _first_open(map: Dictionary) -> Vector2i:
	for y in UserMap.height(map):
		for x in UserMap.width(map):
			if UserMap.is_open(UserMap.at(map, x, y)):
				return Vector2i(x, y)
	return Vector2i(1, 1)


static func _glow(lv: Dictionary, x: float, y: float, amount: float) -> void:
	var w: int = lv["width"]
	var h: int = lv["height"]
	var light: Array = lv["light"]
	for yy in range(int(y - GLOW_REACH), int(y + GLOW_REACH) + 1):
		for xx in range(int(x - GLOW_REACH), int(x + GLOW_REACH) + 1):
			if xx < 0 or yy < 0 or xx >= w or yy >= h:
				continue
			var d := Vector2(xx + .5 - x, yy + .5 - y).length()
			if d < GLOW_REACH:
				var i := yy * w + xx
				var was: float = light[i]
				light[i] = snappedf(minf(LIGHT_MOST, was + amount * (1.0 - d / GLOW_REACH)), .0001)


## The walls the grids imply, a building's outside banded with a foundation
## and an eave (level_builder.gd does the same for the chapters).
static func _walls(lv: Dictionary, tiles: Dictionary) -> Array:
	var implied: Array = LevelEdit.implied_walls(lv, tiles)
	var out: Array = []
	var w: int = lv["width"]
	var solid: Array = lv["solid"]
	var roof: Array = lv["roof"]
	var names := {}
	for key: Variant in tiles:
		names[tiles[key]] = str(key)
	var foundation: int = tiles.get("trim_foundation", 0)
	var eave: int = tiles.get("trim_eave", 0)
	for v: Variant in implied:
		var row: Array = v
		var ax: float = row[0]
		var ay: float = row[1]
		var bx: float = row[2]
		var by: float = row[3]
		var bottom: float = row[6]
		var top: float = row[7]
		var lit: float = row[5]
		row[5] = snappedf(lit, .0001)
		var on_grid := (
			ax == floorf(ax) and ay == floorf(ay) and bx == floorf(bx) and by == floorf(by)
		)
		if not on_grid or bottom < 0.0 or top - bottom < 1.0:
			out.append(row)
			continue
		var mid := Vector2((ax + bx) * .5, (ay + by) * .5)
		var normal := Vector2(by - ay, ax - bx).normalized() * .5
		var c1 := Vector2i(floori(mid.x + normal.x), floori(mid.y + normal.y))
		var c2 := Vector2i(floori(mid.x - normal.x), floori(mid.y - normal.y))
		var i1 := c1.y * w + c1.x
		var i2 := c2.y * w + c2.x
		if i1 < 0 or i2 < 0 or i1 >= solid.size() or i2 >= solid.size():
			out.append(row)
			continue
		var s1: int = solid[i1]
		var open_i := i1 if s1 < 0 else i2
		var wall_i := i2 if open_i == i1 else i1
		var wall_tile: int = solid[wall_i]
		var face: int = row[4]
		var material := str(names.get(face, "")).trim_suffix("_win").trim_suffix("_lit")
		var outside: float = roof[open_i]
		if wall_tile < 0 or not material in BANDED or outside > 0.0:
			out.append(row)
			continue
		var foot := row.duplicate()
		foot[4] = foundation
		foot[7] = snappedf(bottom + FOUNDATION, .001)
		var body := row.duplicate()
		body[6] = foot[7]
		body[7] = snappedf(top - EAVE, .001)
		var cap := row.duplicate()
		cap[4] = eave
		cap[6] = body[7]
		cap[5] = snappedf(lit * .92, .0001)
		out.append(foot)
		out.append(body)
		out.append(cap)
	return out


## Over each door, both faces of the wall line filled from the lintel to the
## top of the walls beside it (the roof edge draws the lintel's first band).
static func _lintel_walls(
	map: Dictionary, lv: Dictionary, lintels: Array, tiles: Dictionary
) -> Array:
	var out: Array = []
	var w: int = lv["width"]
	var roof: Array = lv["roof"]
	var light: Array = lv["light"]
	for d: Array in lintels:
		var x: int = d[0]
		var y: int = d[1]
		var way: int = d[2]
		var flank := UserMap.cell(
			UserMap.at(map, x, y - 1) if way == 1 else UserMap.at(map, x - 1, y)
		)
		var top: float = flank.get("top", 2.9)
		var face: int = tiles.get(str(flank.get("tile", "barn")), 0)
		var gx := x + 1
		var gy := y + 1
		# The two faces: the cell's open sides (west and east for a door
		# walked through east-west).
		var faces: Array = (
			[[gx, gy, gx, gy + 1, gx - 1, gy], [gx + 1, gy + 1, gx + 1, gy, gx + 1, gy]]
			if way == 1
			else [[gx + 1, gy, gx, gy, gx, gy - 1], [gx, gy + 1, gx + 1, gy + 1, gx, gy + 1]]
		)
		for f: Array in faces:
			var fx: int = f[4]
			var fy: int = f[5]
			var ni: int = fy * w + fx
			var beside: float = roof[ni]
			var bottom := FASCIA_TOP if beside <= 0.0 else DOOR_TOP
			if top <= bottom + .01:
				continue
			var lit: float = light[ni]
			out.append([f[0], f[1], f[2], f[3], face, lit, bottom, top, 0])
			out.append([f[2], f[3], f[0], f[1], face, lit, bottom, top, 0])
	return out


## The 5v5 plan (LevelData.tactical): five spawns round each start mark
## facing the other, a box round each bomb site, the hostages, the rescue
## ground round the attackers' start, a straight route and a hold for the
## bots at each site.
static func _tactical(map: Dictionary) -> Dictionary:
	var attack: Variant = UserMap.mark(map, "attack")
	var defend: Variant = UserMap.mark(map, "defend")
	if attack == null or defend == null:
		return {}
	var a: Vector2i = attack
	var d: Vector2i = defend
	var a_at := Vector2(a.x + 1.5, a.y + 1.5)
	var d_at := Vector2(d.x + 1.5, d.y + 1.5)
	var out := {
		"attack_spawns": _spots(map, a, (d_at - a_at).angle()),
		"defend_spawns": _spots(map, d, (a_at - d_at).angle()),
		"sites": {},
		"hostages": [],
		"rescue": [a.x - 1, a.y - 1, a.x + 4, a.y + 4],
		"routes": {},
		"holds": {},
	}
	var half := int(UserMap.rule("site_box"))
	for pair: Array in [["A", "site_a"], ["B", "site_b"]]:
		var site: Variant = UserMap.mark(map, str(pair[1]))
		if site == null:
			continue
		var s: Vector2i = site
		var gx := s.x + 1
		var gy := s.y + 1
		out["sites"][pair[0]] = [gx - half, gy - half, gx + half + 1, gy + half + 1]
		out["routes"][pair[0]] = [[[gx + .5, gy + .5]]]
		var look := (a_at - Vector2(gx + .5, gy + .5)).angle()
		out["holds"][pair[0]] = [[gx + .5, gy + .5, snappedf(look, .0001)]]
	var middle := (a_at + d_at) * .5
	out["holds"]["mid"] = [
		[snappedf(middle.x, .01), snappedf(middle.y, .01), snappedf((a_at - d_at).angle(), .0001)]
	]
	for h: Array in UserMap.marks(map, "mark", "hostage"):
		var hx: int = h[0]
		var hy: int = h[1]
		var held: Array = out["hostages"]
		held.append([hx + 1.5, hy + 1.5])
	return out


## Up to TEAM_SPOTS open cells round a start (the nearest first, on foot),
## each [x, y, facing].
static func _spots(map: Dictionary, from: Vector2i, facing: float) -> Array:
	var near := UserMap.reach(map, from)
	var cells: Array = near.keys()
	cells.sort_custom(
		func(p: Vector2i, q: Vector2i) -> bool:
			var dp := p.distance_squared_to(from)
			var dq := q.distance_squared_to(from)
			return dp < dq or (dp == dq and (p.y < q.y or (p.y == q.y and p.x < q.x)))
	)
	var taken := {}
	for v: Variant in map["things"]:
		var t: Array = v
		var tx: int = t[2]
		var ty: int = t[3]
		taken[Vector2i(tx, ty)] = str(t[0]) != "mark"
	var out: Array = []
	for c: Vector2i in cells:
		var busy: bool = taken.get(c, false)
		if busy or UserMap.at(map, c.x, c.y) == "D":
			continue
		out.append([c.x + 1.5, c.y + 1.5, snappedf(facing, .0001)])
		if out.size() >= TEAM_SPOTS:
			break
	return out
