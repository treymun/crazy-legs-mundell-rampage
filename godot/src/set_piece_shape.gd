## What each set piece is made of (features/set_pieces.gd plays them; the 3D
## view draws their parts through the wreck layer): a level's "set_pieces"
## entry and data/tuning/set_pieces.cfg made into parts, each a box with a
## role, a place and a turn standing, the same on every machine.
##
## Kinds: "barn" (posts, top plates, ridge, tin sheets, plank walls), "tower"
## (four legs braced, a deck, a stave tank with hoops and a tin cap) and
## "fuel" (a pipe run along the ground from the pumps; the pumps are the
## level's own props, here only their hit boxes). A piece's frame: its middle
## (x, y) on the floor at `ground`, turned by `turn` quarter turns (so its
## standing parts stay square to the map: their volumes are boxes).
class_name SetPieceShape
extends RefCounted

const PATH := "res://data/tuning/set_pieces.cfg"
const KINDS := ["barn", "tower", "fuel"]

static var _cfg: ConfigFile = null


## One part: a box `half` each way about `p` turned by `q` (map axes, z up).
class Part:
	var role := ""
	## What the wreck layer draws ("" nothing: a pump's hit box).
	var key := ""
	var p := Vector3.ZERO
	var q := Quaternion.IDENTITY
	var half := Vector3(.1, .1, .1)
	## Its own hp (0: never struck on its own: it goes with the whole).
	var hp := 0.0
	## In the way of bodies and shots while it stands (a volume).
	var solid := false
	## Which way it faces out from the middle (a wall's outside, a post's or a
	## leg's corner), on the map.
	var side := Vector2.ZERO
	## The tile it is drawn with (a wall's cracked look swaps it for _hit).
	var tile := ""
	## The tank, its hoops and its cap go together (they burst).
	var tank := false


## A number read untyped (a level's JSON, a carried row) as a float.
static func f(v: Variant) -> float:
	var x: float = v
	return x


static func cfg() -> ConfigFile:
	if _cfg == null:
		_cfg = Tuning.file(PATH)
	return _cfg


static func num(section: String, key: String, fallback := 0.0) -> float:
	var v: float = cfg().get_value(section, key, fallback)
	return v


static func text(section: String, key: String, fallback := "") -> String:
	return str(cfg().get_value(section, key, fallback))


## A spec's own number, else its kind's.
static func own(spec: Dictionary, key: String, fallback := 0.0) -> float:
	var kind := str(spec.get("kind", ""))
	var v: float = spec.get(key, num(kind, key, fallback))
	return v


## The key the wreck layer draws a box of `tile` with.
static func box_key(tile: String, size: Vector3) -> String:
	return "t:%s@0,0|spbox:%.3f,%.3f,%.3f" % [tile, size.x, size.y, size.z]


## Every part of `spec` standing, its floor at `ground`.
static func parts(spec: Dictionary, ground: float) -> Array[Part]:
	var out: Array[Part] = []
	match str(spec.get("kind", "")):
		"barn":
			_barn(spec, ground, out)
		"tower":
			_tower(spec, ground, out)
		"fuel":
			_fuel(spec, ground, out)
	return out


## The piece's frame: map point of local (x, y, z) and the turn.
static func turn_of(spec: Dictionary) -> Basis:
	var quarters := roundi(f(spec.get("turn", 0)))
	return Basis(Vector3(0, 0, 1), quarters * PI * .5)


static func _at(spec: Dictionary, ground: float, local: Vector3) -> Vector3:
	var x: float = spec.get("x", 0.0)
	var y: float = spec.get("y", 0.0)
	var r := turn_of(spec) * local
	return Vector3(x + snappedf(r.x, .0001), y + snappedf(r.y, .0001), ground + local.z)


static func _part(
	spec: Dictionary,
	ground: float,
	role: String,
	local: Vector3,
	b: Basis,
	size: Vector3,
	tile: String
) -> Part:
	var part := Part.new()
	part.role = role
	part.p = _at(spec, ground, local)
	part.q = Quaternion((turn_of(spec) * b).orthonormalized())
	part.half = size * .5
	part.tile = tile
	part.key = box_key(tile, size) if tile != "" else ""
	return part


static func _side(spec: Dictionary, local: Vector2) -> Vector2:
	var r := turn_of(spec) * Vector3(local.x, local.y, 0.0)
	return Vector2(snappedf(r.x, .0001), snappedf(r.y, .0001))


# ------------------------------------------------------------------- barn


static func _barn(spec: Dictionary, ground: float, out: Array[Part]) -> void:
	var w := own(spec, "w", 8.0)
	var d := own(spec, "d", 5.0)
	var eave := own(spec, "eave", 2.9)
	var rise := own(spec, "rise", 1.1)
	var n := maxi(2, roundi(own(spec, "posts", 4.0)))
	var sheets := maxi(1, roundi(own(spec, "sheets", 4.0)))
	var post_tile := text("barn", "post_tile", "wood")
	var beam_tile := text("barn", "beam_tile", "wood")
	var wall_tile := str(spec.get("wall_tile", text("barn", "wall_tile", "barn")))
	var roof_tile := str(spec.get("roof_tile", text("barn", "roof_tile", "tin")))
	var walls: Array = spec.get("walls", cfg().get_value("barn", "walls", []))
	var post := .24
	var xs: Array[float] = []
	for i in n:
		xs.append(-w * .5 + w * i / (n - 1))
	# The posts, both long sides.
	for sy: float in [-1.0, 1.0]:
		for x: float in xs:
			var part := _part(
				spec,
				ground,
				"post",
				Vector3(x, sy * d * .5, eave * .5),
				Basis.IDENTITY,
				Vector3(post, post, eave),
				post_tile
			)
			part.hp = num("barn", "post_hp", 60.0)
			part.solid = true
			part.side = _side(spec, Vector2(x, sy * d * .5)).normalized()
			out.append(part)
	# The top plates and the ridge.
	for sy: float in [-1.0, 1.0]:
		out.append(
			_part(
				spec,
				ground,
				"beam",
				Vector3(0.0, sy * d * .5, eave + .1),
				Basis.IDENTITY,
				Vector3(w + .3, .2, .2),
				beam_tile
			)
		)
	out.append(
		_part(
			spec,
			ground,
			"beam",
			Vector3(0.0, 0.0, eave + rise + .08),
			Basis.IDENTITY,
			Vector3(w + .3, .2, .2),
			beam_tile
		)
	)
	# The plank walls (before the roof: the roof lies over them when it comes).
	var panel_hp := num("barn", "panel_hp", 55.0)
	for name: Variant in walls:
		match str(name):
			"back", "front":
				var sy := 1.0 if str(name) == "back" else -1.0
				for i in n - 1:
					var x0: float = xs[i]
					var x1: float = xs[i + 1]
					var part := _part(
						spec,
						ground,
						"wall",
						Vector3((x0 + x1) * .5, sy * d * .5, eave * .5),
						Basis.IDENTITY,
						Vector3(x1 - x0 - post, .1, eave),
						wall_tile
					)
					part.hp = panel_hp
					part.solid = true
					part.side = _side(spec, Vector2(0.0, sy))
					out.append(part)
			"left", "right":
				var sx := -1.0 if str(name) == "left" else 1.0
				var halves := 2
				for i in halves:
					var y0 := -d * .5 + d * i / halves
					var y1 := -d * .5 + d * (i + 1) / halves
					var part := _part(
						spec,
						ground,
						"wall",
						Vector3(sx * w * .5, (y0 + y1) * .5, eave * .5),
						Basis(Vector3(0, 0, 1), PI * .5),
						Vector3(y1 - y0 - post, .1, eave),
						wall_tile
					)
					part.hp = panel_hp
					part.solid = true
					part.side = _side(spec, Vector2(sx, 0.0))
					out.append(part)
	# The tin: each slope from the ridge out past the eave, in sheets.
	var over := .35
	var run := d * .5 + over
	var drop := rise * over / (d * .5)
	var slope := Vector2(run, rise + drop).length()
	var tilt := atan2(rise + drop, run)
	for sy: float in [-1.0, 1.0]:
		for i in sheets:
			var x := -w * .5 - .15 + (w + .3) * (i + .5) / sheets
			var y := sy * run * .5
			var z := eave + rise + .2 - (rise + drop) * .5
			out.append(
				_part(
					spec,
					ground,
					"roof",
					Vector3(x, y, z),
					Basis(Vector3(1, 0, 0), -sy * tilt),
					Vector3((w + .3) / sheets + .04, slope, .05),
					roof_tile
				)
			)


# ------------------------------------------------------------------ tower


static func _tower(spec: Dictionary, ground: float, out: Array[Part]) -> void:
	var s := own(spec, "spread", 1.15)
	var legs := own(spec, "legs", 4.6)
	var r := own(spec, "tank_r", 1.55)
	var th := own(spec, "tank_h", 2.3)
	var rise := own(spec, "cap_rise", .9)
	var staves := roundi(own(spec, "staves", 18.0))
	var leg_tile := text("tower", "leg_tile", "wood")
	for sy: float in [-1.0, 1.0]:
		for sx: float in [-1.0, 1.0]:
			var leg := _part(
				spec,
				ground,
				"leg",
				Vector3(sx * s, sy * s, legs * .5),
				Basis.IDENTITY,
				Vector3(.26, .26, legs),
				leg_tile
			)
			leg.hp = num("tower", "leg_hp", 70.0)
			leg.solid = true
			leg.side = _side(spec, Vector2(sx, sy)).normalized()
			out.append(leg)
	# Each side: a girt across the middle and an X in each bay.
	var mid := legs * .47
	var bays := [[.35, mid], [mid, legs - .25]]
	for k in 4:
		var a := k * PI * .5
		var normal := Vector3(cos(a), sin(a), 0.0)
		var across := Vector3(-sin(a), cos(a), 0.0)
		var face := normal * (s + .15)
		out.append(
			_part(
				spec,
				ground,
				"brace",
				face + Vector3(0, 0, mid),
				Basis(across, -normal, Vector3(0, 0, 1)),
				Vector3(s * 2.0 + .3, .07, .16),
				leg_tile
			)
		)
		for bay: Array in bays:
			var z0: float = bay[0]
			var z1: float = bay[1]
			for dir: float in [-1.0, 1.0]:
				var from := face + across * (-s * dir) + Vector3(0, 0, z0)
				var to := face + across * (s * dir) + Vector3(0, 0, z1)
				out.append(
					_part(
						spec,
						ground,
						"brace",
						(from + to) * .5 + normal * .04 * dir,
						SetPieceMesh.frame(to - from, normal.cross(to - from)),
						Vector3((to - from).length(), .06, .13),
						leg_tile
					)
				)
	out.append(
		_part(
			spec,
			ground,
			"deck",
			Vector3(0, 0, legs + .08),
			Basis.IDENTITY,
			Vector3(s * 2.0 + .9, s * 2.0 + .9, .16),
			text("tower", "deck_tile", "porch")
		)
	)
	# The deck goes to pieces with the tank.
	out[out.size() - 1].tank = true
	var tank_z := legs + .16 + th * .5
	var tank := Part.new()
	tank.role = "tank"
	tank.tank = true
	tank.p = _at(spec, ground, Vector3(0, 0, tank_z))
	tank.q = Quaternion(turn_of(spec))
	tank.half = Vector3(r, r, th * .5)
	tank.tile = text("tower", "tank_tile", "wood")
	tank.key = "t:%s@0,0|sptank:%.3f,%.3f,%d" % [tank.tile, r, th, staves]
	out.append(tank)
	var hoops := Part.new()
	hoops.role = "hoop"
	hoops.tank = true
	hoops.p = tank.p
	hoops.q = tank.q
	hoops.half = tank.half
	hoops.tile = text("tower", "hoop_tile", "mill_tin")
	hoops.key = "t:%s@0,0|sphoops:%.3f,%.3f,%d,3" % [hoops.tile, r + .05, th * .9, staves]
	out.append(hoops)
	var cap := Part.new()
	cap.role = "cap"
	cap.tank = true
	cap.p = _at(spec, ground, Vector3(0, 0, tank_z + th * .5 + rise * .5))
	cap.q = tank.q
	cap.half = Vector3(r + .15, r + .15, rise * .5)
	cap.tile = text("tower", "cap_tile", "tin")
	cap.key = "t:%s@0,0|spcone:%.3f,%.3f,%d" % [cap.tile, r + .15, rise, staves]
	out.append(cap)
	# Its name painted round the tank (a picture: "sign", facing "sign_face"
	# quarter turns from north).
	var sign := str(spec.get("sign", ""))
	if sign != "":
		var name := Part.new()
		name.role = "name"
		name.tank = true
		name.p = tank.p
		var face := roundi(f(spec.get("sign_face", 0)))
		name.q = Quaternion(Basis(Vector3(0, 0, 1), face * PI * .5) * turn_of(spec))
		name.half = tank.half
		name.key = "p:%s|sparc:%.3f,%.3f,%.3f,10" % [sign, r + .06, r * 2.1, th * .3]
		out.append(name)


# ------------------------------------------------------------------- fuel


## A pipe along the ground through "points" ([x, y] pairs), in lengths of at
## most two cells, and a hit box at each of "pumps".
static func _fuel(spec: Dictionary, ground: float, out: Array[Part]) -> void:
	var points: Array = spec.get("points", [])
	var tile := text("fuel", "pipe_tile", "mill_tin")
	for i in range(1, points.size()):
		var a := _xy(points[i - 1])
		var b := _xy(points[i])
		var length := a.distance_to(b)
		var pieces := maxi(1, ceili(length / 2.0))
		for k in pieces:
			var p0 := a.lerp(b, f(k) / pieces)
			var p1 := a.lerp(b, f(k + 1) / pieces)
			var part := Part.new()
			part.role = "pipe"
			part.p = Vector3((p0.x + p1.x) * .5, (p0.y + p1.y) * .5, ground + .08)
			part.q = Quaternion(Basis(Vector3(0, 0, 1), atan2(p1.y - p0.y, p1.x - p0.x)))
			var size := Vector3(p0.distance_to(p1) + .02, .14, .14)
			part.half = size * .5
			part.tile = tile
			part.key = box_key(tile, size)
			part.hp = num("fuel", "pipe_hp", 20.0)
			out.append(part)
	for item: Variant in spec.get("pumps", []):
		var at := _xy(item)
		var pump := Part.new()
		pump.role = "pump"
		pump.p = Vector3(at.x, at.y, ground + .6)
		pump.half = Vector3(.28, .22, .6)
		pump.hp = num("fuel", "pump_hp", 45.0)
		out.append(pump)


static func _xy(v: Variant) -> Vector2:
	var row: Array = v
	var x: float = row[0]
	var y: float = row[1]
	return Vector2(x, y)


## The cells a fuel line's gas runs along, in order from its first point.
static func trail(spec: Dictionary) -> Array:
	var points: Array = spec.get("points", [])
	var out: Array = []
	var seen := {}
	for i in range(1, points.size()):
		var a := _xy(points[i - 1])
		var b := _xy(points[i])
		var steps := maxi(1, ceili(a.distance_to(b) / .25))
		for k in steps + 1:
			var at := a.lerp(b, f(k) / steps)
			var cell := Vector2i(floori(at.x), floori(at.y))
			if not seen.has(cell):
				seen[cell] = true
				out.append(cell)
	return out


## The footprint of a piece on the map: [x0, y0, x1, y1].
static func footprint(spec: Dictionary) -> Rect2:
	var x: float = spec.get("x", 0.0)
	var y: float = spec.get("y", 0.0)
	var rect := Rect2(x, y, 0.0, 0.0)
	for part: Part in parts(spec, 0.0):
		if part.role == "pipe" or part.role == "pump":
			rect = rect.expand(Vector2(part.p.x, part.p.y))
			continue
		var b := Basis(part.q)
		for sx: float in [-1.0, 1.0]:
			for sy: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var c := (
						part.p + b * Vector3(part.half.x * sx, part.half.y * sy, part.half.z * sz)
					)
					rect = rect.expand(Vector2(c.x, c.y))
	return rect


## The volume a standing part puts in the way: [x0, y0, x1, y1, top, face
## tile, top tile, bottom] as the level's own, in its floats.
static func volume_of(part: Part, tile: float) -> PackedFloat32Array:
	var b := Basis(part.q)
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var c := part.p + b * Vector3(part.half.x * sx, part.half.y * sy, part.half.z * sz)
				lo = Vector3(minf(lo.x, c.x), minf(lo.y, c.y), minf(lo.z, c.z))
				hi = Vector3(maxf(hi.x, c.x), maxf(hi.y, c.y), maxf(hi.z, c.z))
	return PackedFloat32Array(
		[
			snappedf(lo.x, .01),
			snappedf(lo.y, .01),
			snappedf(hi.x, .01),
			snappedf(hi.y, .01),
			snappedf(hi.z, .01),
			tile,
			tile,
			snappedf(lo.z, .01),
		]
	)
