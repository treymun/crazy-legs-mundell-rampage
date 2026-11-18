## How a vehicle looks hurt and wrecked (features/gun_fx.gd owns one;
## destruction pass 11). Badly hurt, its engine smokes (grey, then black with
## flames) and a round striking it throws sparks. Wrecked, parts come off it:
## the hood, a door, a wheel, the trunk lid or the airboat's fan cage, which
## and how far by where the killing blast came from and how hard (the near
## side's parts more, thrown away from it); its glass bursts. They fly as real
## pieces of its model (features/wreckage.gd throws them: cut here from the
## model with WreckCuts' clipping, so a hood is the hood's own triangles and
## paint). The hulk left is the model without them, charring as it burns,
## kicked up by the blast and dropped onto its rims, sagging where a wheel
## went; it burns `burn` seconds (vehicles.cfg) under a column of black smoke
## with secondary pops, then smoulders.
##
## Looks only: gun_fx's own dice, never saved or carried. A vehicle that was
## a wreck already when seen (a save, a snapshot put on) shows its hulk whole
## and throws nothing.
class_name VehicleWreckLooks
extends RefCounted

const Bit := preload("res://src/fx_bit.gd")
## How each kind's model comes apart: splits of its box in its own frame
## (x rear to front, y right to left, z up, each 0 to 1), and the parts that
## may come off as cells [x, y, z] of that grid, with which side they are on
## (r, l: its right and left; top, front, back).
const CUTS := {
	"car":
	{
		"x": [0.0, .27, .62, 1.0],
		"y": [0.0, .2, .8, 1.0],
		"z": [0.0, .3, .62, 1.0],
		"parts":
		{
			"hood": ["top", [[2, 1, 1], [2, 1, 2]]],
			"door_r": ["r", [[1, 0, 1]]],
			"door_l": ["l", [[1, 2, 1]]],
			"wheel_fr": ["r", [[2, 0, 0]]],
			"wheel_fl": ["l", [[2, 2, 0]]],
			"wheel_rr": ["r", [[0, 0, 0]]],
			"wheel_rl": ["l", [[0, 2, 0]]],
			"trunk": ["back", [[0, 1, 1]]],
		},
	},
	"airboat":
	{
		"x": [0.0, .24, .6, 1.0],
		"y": [0.0, .25, .75, 1.0],
		"z": [0.0, .32, 1.0],
		"parts":
		{
			"cage": ["back", [[0, 0, 1], [0, 1, 1], [0, 2, 1]]],
			"rail_r": ["r", [[1, 0, 1], [2, 0, 1]]],
			"rail_l": ["l", [[1, 2, 1], [2, 2, 1]]],
			"seat": ["top", [[1, 1, 1]]],
		},
	},
	"mower":
	{
		"x": [0.0, .4, .7, 1.0],
		"y": [0.0, .22, .78, 1.0],
		"z": [0.0, .45, 1.0],
		"parts":
		{
			"hood": ["top", [[2, 1, 1]]],
			"wheel_rr": ["r", [[0, 0, 0], [0, 0, 1]]],
			"wheel_rl": ["l", [[0, 2, 0], [0, 2, 1]]],
			"wheel_fr": ["r", [[2, 0, 0]]],
			"wheel_fl": ["l", [[2, 2, 0]]],
			"seat": ["back", [[1, 1, 1]]],
		},
	},
}
## Seconds the blast's kick takes to land the hulk, how high it goes, how far
## it sinks onto its rims (cells, at the model's size) and how far it sags
## where a wheel went (radians).
const KICK_TIME := .55
const KICK_UP := .28
const RIMS := .07
const SAG := .09
## Char as it is wrecked and once burnt out (thing_marks.gdshaderinc char_k).
const CHAR_FROM := .65
const CHAR_TO := .95
## The share of its burn by which it is charred through.
const CHAR_BY := .4
## How scorched a part blown off it comes (view3d/wreck_layer.gd).
const PART_CHAR := .62
## Seconds a burnt-out wreck smoulders after its fire.
const SMOULDER := 40.0

## Each kind's cut cells, made once: kind -> [Soup a cell, or null].
static var _cells := {}

var game: Game
var dice: RandomNumberGenerator
var bits: Array
var booms: Array
var _models: PropModels
## By ride: {mask, key, born, tilt, burn_next, pop_next, seen}.
var _state := {}
## The last blast near each ride: index -> [x, y, force, clock].
var _hits := {}
var _engine_next := {}


func _init(g: Game, d: RandomNumberGenerator, bit_list: Array, boom_list: Array) -> void:
	game = g
	dice = d
	bits = bit_list
	booms = boom_list
	_models = PropModels.new(g.art)


func _rides() -> Array:
	var rides: Object = game.features.get("vehicles")
	if rides == null:
		return []
	var list: Array = rides.get("rides")
	return list


func _bit(kind: String, at: Vector3, v: Vector3, life: float, size: float, fall := 0.0) -> Bit:
	var bit := Bit.make(kind, at, v, life, size, fall)
	bits.append(bit)
	return bit


## A blast went off: each ride near it remembers it (the wreck's parts fly
## away from the one that wrecked it).
func blasted(x: float, y: float) -> void:
	var rides := _rides()
	var reach := VehicleDrive.shared("blast_reach") if not rides.is_empty() else 3.0
	for i in rides.size():
		var v: VehicleDrive.Ride = rides[i]
		var d := Vector2(v.x - x, v.y - y).length()
		if d < reach + 2.0:
			_hits[i] = [x, y, clampf(1.2 - d / (reach + 1.0), .2, 1.0), game.clock]


## A round's line from `from` to `end`: through a vehicle's hull it throws
## sparks where it went in (and a ricochet's ping now and then).
func struck(from: Vector3, end: Vector3) -> void:
	for item: Variant in _rides():
		var v: VehicleDrive.Ride = item
		var s := VehicleDrive.spec(v.kind)
		var a := Vector2(from.x, from.y)
		var b := Vector2(end.x, end.y)
		var near := Geometry2D.get_closest_point_to_segment(Vector2(v.x, v.y), a, b)
		if near.distance_to(Vector2(v.x, v.y)) > s.length * .6:
			continue
		var length := a.distance_to(b)
		var steps := ceili(length / .2)
		for k in steps:
			var t := float(k) / maxf(1.0, steps)
			var p := from.lerp(end, t)
			if p.z < v.z + .1 or p.z > v.z + s.tall:
				continue
			if VehicleDrive.gap(s, v, p.x, p.y) > .02:
				continue
			var out := (from - p).normalized()
			var hurt := v.hp < s.hp * .5 or v.wreck >= 0.0
			for _k in 7 if hurt else 4:
				var dir := Vector3(
					dice.randf_range(-1, 1), dice.randf_range(-1, 1), dice.randf_range(0, 1)
				)
				_bit("spark", p, out * 2.0 + dir * 3.0, dice.randf_range(.18, .4), .03, 7.0)
			if hurt:
				var puff := _bit("soot", p, out * .3 + Vector3(0, 0, .3), 1.0, .14)
				puff.grow = .35
				puff.look = "soot"
			if dice.randf() < .3:
				game.sound_at("ricochet_tin", p.x, p.y, .45)
			break


## Every tick: wrecks newly seen come apart; the burning ones smoke and pop;
## the hurt ones smoke from the engine.
func tick() -> void:
	var rides := _rides()
	for i in rides.size():
		var v: VehicleDrive.Ride = rides[i]
		var s := VehicleDrive.spec(v.kind)
		var st: Dictionary = _state.get(i, {})
		if v.wreck < 0.0:
			if not st.is_empty():
				_state.erase(i)
			_engine(i, v, s)
			continue
		if st.is_empty():
			st = _wrecked(i, v, s, game.clock - v.wreck < .5)
			_state[i] = st
		_burning(i, v, s, st)


## The engine's place: `smoke_at` of the way from its middle to its nose
## (vehicles.cfg; behind for the airboat's), near its top.
func _engine_at(v: VehicleDrive.Ride, s: VehicleDrive.Spec) -> Vector3:
	var at: float = Tuning.file(VehicleDrive.FILE).get_value(v.kind, "smoke_at", -.3)
	var along := s.length * .5 * at
	return Vector3(v.x + cos(v.h) * along, v.y + sin(v.h) * along, v.z + s.tall * .85)


func _engine(i: int, v: VehicleDrive.Ride, s: VehicleDrive.Spec) -> void:
	var share := v.hp / maxf(1.0, s.hp)
	if share > .5:
		return
	var next: float = _engine_next.get(i, 0.0)
	if game.clock < next:
		return
	var bad := share < .25
	_engine_next[i] = game.clock + (.16 if bad else .32) * dice.randf_range(.8, 1.2)
	var at := _engine_at(v, s)
	var puff := _bit(
		"soot",
		at + Vector3(dice.randf_range(-.15, .15), dice.randf_range(-.15, .15), 0.0),
		Vector3(v.vx * .5, v.vy * .5, dice.randf_range(.5, .9)),
		dice.randf_range(1.6, 2.4),
		.22 if bad else .16
	)
	puff.grow = .5
	puff.look = "soot" if bad else "smoke"
	if bad and dice.randf() < .25:
		var spark_v := Vector3(dice.randf_range(-1, 1), dice.randf_range(-1, 1), 2.0)
		_bit("spark", at, spark_v, .3, .03, 6.0)


## Its parts come off (`fresh`: just now, by the blast; else a wreck already
## when seen: whole, nothing thrown).
func _wrecked(i: int, v: VehicleDrive.Ride, s: VehicleDrive.Spec, fresh: bool) -> Dictionary:
	var st := {"mask": 0, "born": v.wreck, "tilt": Basis.IDENTITY, "seen": game.clock}
	st["burn_next"] = game.clock
	st["pop_next"] = v.wreck + dice.randf_range(1.2, 2.4)
	var cut: Dictionary = CUTS.get(v.kind, {})
	var name := _models.name_of(s.picture)
	if cut.is_empty() or name == "":
		return st
	var cells := _cut(v.kind, name, s.nose)
	if cells.is_empty():
		return st
	if not fresh:
		st["key"] = _hulk_key(v.kind, name, s.nose, 0)
		return st
	var hit: Array = _hits.get(i, [v.x - cos(v.h + PI / 2.0), v.y - sin(v.h + PI / 2.0), .7, 0.0])
	var hx: float = hit[0]
	var hy: float = hit[1]
	var force: float = hit[2]
	# Where the blast was, in its own frame: which side is near.
	var dx := hx - v.x
	var dy := hy - v.y
	var fwd := dx * cos(v.h) + dy * sin(v.h)
	var left := -dx * sin(v.h) + dy * cos(v.h)
	var near_side := "l" if left > 0.0 else "r"
	var near_end := "front" if fwd > 0.0 else "back"
	var parts: Dictionary = cut["parts"]
	var names: Array = parts.keys()
	var mask := 0
	var off: Array = []
	for k in names.size():
		var row: Array = parts[names[k]]
		var side := str(row[0])
		var chance := .2 * force
		if side == "top":
			chance = .5 + .45 * force
		elif side == near_side:
			chance = .3 + .6 * force
		elif side == near_end:
			chance = .35 + .4 * force
		if str(names[k]).begins_with("wheel") and side == near_side:
			chance *= .7
		if dice.randf() < chance:
			mask |= 1 << k
			off.append(k)
	st["mask"] = mask
	st["key"] = _hulk_key(v.kind, name, s.nose, mask)
	# Sag where a wheel went: down toward the missing corners.
	var roll := 0.0
	var pitch := 0.0
	for k: int in off:
		var label := str(names[k])
		if label.begins_with("wheel"):
			roll += SAG * (1.0 if label.ends_with("r") else -1.0) * dice.randf_range(.7, 1.2)
			pitch += SAG * .6 * (1.0 if label.contains("_f") else -1.0)
	st["tilt"] = Basis(Vector3(1, 0, 0), roll) * Basis(Vector3(0, 1, 0), pitch)
	_throw(v, s, name, off, Vector2(hx, hy), force)
	_glass(v, s)
	game.sound_at("wreck_crash", v.x, v.y, .82)
	return st


## The model's map frame (its foot's middle at the origin): turned to its
## heading, the model's own pose (`nose`) undone, at the model's size.
func _frame(v: VehicleDrive.Ride, s: VehicleDrive.Spec, name: String) -> Basis:
	var size := _models.scale_of(name, s.height)
	return (
		Basis(Vector3(0, 0, 1), v.h)
		* Basis(Vector3(0, 0, 1), s.nose)
		* Basis.from_scale(Vector3.ONE * size)
	)


func _throw(
	v: VehicleDrive.Ride, s: VehicleDrive.Spec, name: String, off: Array, hit: Vector2, force: float
) -> void:
	var wreck: Object = game.features.get("wreckage")
	if wreck == null or off.is_empty():
		return
	var on: bool = wreck.get("on")
	if not on:
		return
	var size := _models.scale_of(name, s.height)
	var src := {
		"key": "m:%s|vw" % name,
		"origin": Vector3(v.x, v.y, v.z),
		"basis": Basis(Vector3(0, 0, 1), v.h) * Basis(Vector3(0, 0, 1), s.nose),
		"size": size,
	}
	var parts := WreckCuts.parts(game.art, str(src["key"]))
	for k: int in off:
		if k >= parts.size():
			continue
		var part: WreckCuts.Part = parts[k]
		var basis: Basis = src["basis"]
		var at: Vector3 = Vector3(v.x, v.y, v.z) + basis * (part.centre * size)
		var away := Vector2(at.x - hit.x, at.y - hit.y)
		if away.length() < .05:
			away = Vector2.from_angle(dice.randf_range(0, TAU))
		away = away.normalized()
		var up := .9 + force * .5
		wreck.call("throw_cut", src, Vector3(away.x, away.y, up), .5 + force * .45, [k])


## Its glass bursting out: glints flung from its middle at the cab's height.
func _glass(v: VehicleDrive.Ride, s: VehicleDrive.Spec) -> void:
	var at := Vector3(v.x, v.y, v.z + s.tall * .75)
	for _k in 14:
		var dir := Vector2.from_angle(dice.randf_range(0, TAU))
		var vel := Vector3(dir.x, dir.y, 0.0) * dice.randf_range(1.0, 3.2)
		vel.z = dice.randf_range(1.2, 3.4)
		_bit("glint", at, vel, dice.randf_range(1.6, 3.0), .028, 9.0)


## While it burns: a column of black smoke off its fire, secondary pops (a
## small fireball, sparks, a pop), then thin smoke as it smoulders.
func _burning(_i: int, v: VehicleDrive.Ride, s: VehicleDrive.Spec, st: Dictionary) -> void:
	var age := game.clock - v.wreck
	var burn := VehicleDrive.shared("burn")
	var next: float = st["burn_next"]
	if game.clock < next or age > burn + SMOULDER:
		return
	var burning := age < burn
	var gap := .1 if burning else lerpf(.6, 2.4, (age - burn) / SMOULDER)
	st["burn_next"] = game.clock + gap * dice.randf_range(.8, 1.25)
	var at := Vector3(
		v.x + dice.randf_range(-.35, .35) * s.length * .5,
		v.y + dice.randf_range(-.3, .3) * s.width * .5,
		v.z + s.tall * .7
	)
	var puff := _bit(
		"soot",
		at,
		Vector3(0, 0, dice.randf_range(.8, 1.3) if burning else .5),
		dice.randf_range(3.0, 4.2) if burning else 2.4,
		dice.randf_range(.32, .5) if burning else .2
	)
	puff.grow = .6 if burning else .35
	puff.look = "soothot" if burning and dice.randf() < .4 else ("soot" if burning else "smoke")
	if burning and dice.randf() < .3:
		var ember := _bit(
			"ember",
			at,
			Vector3(dice.randf_range(-.5, .5), dice.randf_range(-.5, .5), 1.2),
			1.6,
			.035,
			-.3
		)
		ember.vz = dice.randf_range(.8, 1.5)
	var pop: float = st["pop_next"]
	if burning and game.clock >= pop:
		st["pop_next"] = game.clock + dice.randf_range(.9, 2.6)
		var p := Vector3(at.x, at.y, v.z + s.tall * .5)
		booms.append(
			[
				p.x,
				p.y,
				p.z,
				game.clock,
				dice.randf_range(.38, .55),
				true,
				"f",
				dice.randi_range(0, 2),
				.7,
				dice.randf() < .5,
				.35,
				.6
			]
		)
		for _k in 6:
			var dir := Vector2.from_angle(dice.randf_range(0, TAU))
			var vel := Vector3(dir.x, dir.y, 0.0) * dice.randf_range(1.5, 4.0)
			vel.z = dice.randf_range(1.5, 4.0)
			_bit("spark", p, vel, dice.randf_range(.25, .5), .03, 6.0)
		game.sound_at("wreck_pop", p.x, p.y, .7)


## Flames licking over a burning hulk (sprites, by the clock), drawn with
## gun_fx's sprites.
func flames(out: Array) -> void:
	var rides := _rides()
	var burn := VehicleDrive.shared("burn") if not rides.is_empty() else 0.0
	for item: Variant in rides:
		var v: VehicleDrive.Ride = item
		if v.wreck < 0.0:
			continue
		var age := game.clock - v.wreck
		if age > burn or not game.in_view(v.x, v.y, 3.0):
			continue
		var s := VehicleDrive.spec(v.kind)
		var dying := clampf((burn - age) / 2.5, 0.0, 1.0)
		for k in 5:
			var u := (k - 2) * .22 * s.length
			var w := (.25 if k % 2 else -.2) * s.width
			var fx := v.x + cos(v.h) * u - sin(v.h) * w
			var fy := v.y + sin(v.h) * u + cos(v.h) * w
			var flick := int(game.clock * 12.0 + k * 5) % 4
			var tall := (
				(.5 + .25 * sin(game.clock * 3.1 + k * 1.7)) * dying * (1.2 if k == 2 else 1.0)
			)
			if tall < .08:
				continue
			var flame := game.pooled(fx, fy, "fx_flame_%d" % flick, tall, v.z + s.tall * .45)
			flame.glow = true
			out.append(flame)


## A light over each burning wreck, flickering: [x, y, z, radius, Color, ...].
func lights(out: Array) -> void:
	var rides := _rides()
	var burn := VehicleDrive.shared("burn") if not rides.is_empty() else 0.0
	for item: Variant in rides:
		var v: VehicleDrive.Ride = item
		if v.wreck < 0.0 or game.clock - v.wreck > burn:
			continue
		var glow: Variant = Effects.light(
			"wreck_fire",
			v.x,
			v.y,
			v.z + 1.0,
			clampf((burn - (game.clock - v.wreck)) / 2.0, 0.0, 1.0),
			game.clock
		)
		if glow != null:
			out.append(glow)


## The hulk of ride `i` as a wreck piece sprite (null: show its model).
func hulk(i: int) -> View.Sprite:
	var st: Dictionary = _state.get(i, {})
	if st.is_empty() or not st.has("key"):
		return null
	var rides := _rides()
	if i >= rides.size():
		return null
	var v: VehicleDrive.Ride = rides[i]
	var s := VehicleDrive.spec(v.kind)
	var key := str(st["key"])
	var parts := WreckCuts.parts(game.art, key)
	if parts.is_empty():
		return null
	var part: WreckCuts.Part = parts[0]
	var name := _models.name_of(s.picture)
	var size := _models.scale_of(name, s.height)
	var born: float = st["born"]
	var seen: float = st["seen"]
	var age := game.clock - born
	var fresh := seen - born < .5
	# Kicked up by its own blast, down onto its rims, a bounce.
	var t := clampf(age / KICK_TIME, 0.0, 1.0) if fresh else 1.0
	var hop := KICK_UP * size * 4.0 * t * (1.0 - t) * (1.0 - t)
	var settle := smoothstep(0.0, 1.0, t)
	var tilt: Basis = st["tilt"]
	var turn := Basis(Vector3(0, 0, 1), v.h) * Basis.IDENTITY.slerp(tilt, settle)
	var frame := turn * Basis(Vector3(0, 0, 1), s.nose) * Basis.from_scale(Vector3.ONE * size)
	var foot := Vector3(v.x, v.y, v.z + hop - RIMS * size * settle)
	var at := foot + frame * part.centre
	var spr: View.Sprite = st.get("sprite")
	if spr == null:
		spr = View.Sprite.new(at.x, at.y, "", 1.0, at.z)
		spr.solid = "~%s#0" % key
		st["sprite"] = spr
	spr.x = at.x
	spr.y = at.y
	spr.z = at.z
	spr.turn = frame * part.basis
	var burn := VehicleDrive.shared("burn")
	spr.hurt = lerpf(CHAR_FROM, CHAR_TO, clampf(age / maxf(1.0, burn * CHAR_BY), 0.0, 1.0))
	return spr


static func _hulk_key(kind: String, name: String, nose: float, mask: int) -> String:
	var key := "m:%s|vh%d" % [name, mask]
	if WreckCuts.has(key):
		return key
	var cells: Array = _cells.get(kind, [])
	var cut: Dictionary = CUTS[kind]
	var parts: Dictionary = cut["parts"]
	var off := {}
	var names: Array = parts.keys()
	for k in names.size():
		if mask & (1 << k):
			var row: Array = parts[names[k]]
			for c: Array in row[1]:
				off[_index(cut, c)] = true
	var soup := WreckCuts.Soup.new()
	for k in cells.size():
		if off.has(k) or cells[k] == null:
			continue
		var piece: WreckCuts.Soup = cells[k]
		for j in piece.size():
			soup.add(piece, j)
	var frame := Basis(Vector3(0, 0, 1), -nose)
	WreckCuts.put(key, [WreckCuts._part(soup, {"basis": frame}, true)] if soup.size() >= 3 else [])
	return key


static func _index(cut: Dictionary, c: Array) -> int:
	var ys: Array = cut["y"]
	var zs: Array = cut["z"]
	var ny := ys.size() - 1
	var nz := zs.size() - 1
	var cx: int = c[0]
	var cy: int = c[1]
	var cz: int = c[2]
	return (cx * ny + cy) * nz + cz


## The model of `kind` cut in its grid (cells in its own frame, turned by
## `nose` in the model's), once; and its loose parts put as "m:<name>|vw".
static func _cut(kind: String, name: String, nose: float) -> Array:
	var known: Variant = _cells.get(kind)
	if known != null:
		var kept: Array = known
		return kept
	var soup := WreckCuts._model(name)
	var cells: Array = []
	if soup.size() < 3:
		_cells[kind] = cells
		return cells
	var cut: Dictionary = CUTS[kind]
	# The model's box in its own frame (x along its heading).
	var own := Basis(Vector3(0, 0, 1), nose)
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for q: Vector3 in soup.p:
		var l := own * q
		lo = Vector3(minf(lo.x, l.x), minf(lo.y, l.y), minf(lo.z, l.z))
		hi = Vector3(maxf(hi.x, l.x), maxf(hi.y, l.y), maxf(hi.z, l.z))
	var back := own.transposed()
	var group := PackedInt32Array()
	group.resize(soup.size() / 3)
	var xs: Array = cut["x"]
	var ys: Array = cut["y"]
	var zs: Array = cut["z"]
	for ix in xs.size() - 1:
		for iy in ys.size() - 1:
			for iz in zs.size() - 1:
				var planes: Array = []
				var at := [ix, iy, iz]
				var splits := [xs, ys, zs]
				for axis in 3:
					var list: Array = splits[axis]
					var k: int = at[axis]
					var from: float = list[k]
					var to: float = list[k + 1]
					var a := lo[axis] + (hi[axis] - lo[axis]) * from
					var b := lo[axis] + (hi[axis] - lo[axis]) * to
					if k == 0:
						a -= 1.0
					if k == list.size() - 2:
						b += 1.0
					var n := Vector3.ZERO
					n[axis] = 1.0
					planes.append([back * n, b])
					planes.append([back * -n, -a])
				var piece := WreckCuts._clip_cell(soup, group, {"group": 0, "planes": planes})
				cells.append(piece if piece.size() >= 3 else null)
	_cells[kind] = cells
	# The loose parts, each its cells together, boxed in its own frame.
	var parts: Dictionary = cut["parts"]
	var loose: Array = []
	for label: String in parts:
		var row: Array = parts[label]
		var joined := WreckCuts.Soup.new()
		for c: Array in row[1]:
			var piece: Variant = cells[_index(cut, c)]
			if piece == null:
				continue
			var cell: WreckCuts.Soup = piece
			for j in cell.size():
				joined.add(cell, j)
		if joined.size() < 3:
			joined = WreckCuts.Soup.new()
			for j in 3:
				joined.p.append(Vector3(j * .01, 0, 0))
				joined.n.append(Vector3.UP)
				joined.uv.append(Vector2.ZERO)
		loose.append(WreckCuts._part(joined, {"basis": back}, true))
	WreckCuts.put("m:%s|vw" % name, loose)
	return cells
