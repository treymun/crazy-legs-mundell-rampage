## How a blast looks in the gun and blast layer (features/gun_fx.gd owns one,
## destruction pass 11): which look it has (data/tuning/blast_looks.cfg: by
## its shots.cfg kind and by what blew, a propane tank, a hazard drum, a
## vehicle), where it went off (in water, on a deck, against a wall) and
## everything it throws: the fireball and the lobes bursting beside it, the
## soot column rolling up into a mushroom, scraps arcing out trailing smoke,
## clods, a ring of dirt puffs rolling out along the ground, sparks, embers,
## burning drops, a column of water, and the crater it leaves.
##
## Looks only: gun_fx's own dice (every blast rolls its own shape, turn,
## lobes, lean, scraps and crater, so no two look alike), never saved or in
## anyone's way. Fewer bits on a phone or QUALITY LOW (`most_bits_low`), and
## each blast of a chain throws fewer bits but keeps its whole fireball.
class_name BlastLooks
extends RefCounted

const Bit := preload("res://src/fx_bit.gd")
const PATH := "res://data/tuning/blast_looks.cfg"
## Fireball frames (fx_boom_<fire><shape>_N) and shapes.
const FRAMES := 12
const SHAPES := 3
## Craters kept at most (the oldest fade first) and how long one stays.
const CRATERS := 16
const CRATERS_LOW := 8
const CRATER_LIFE := 600.0
## A wall nearer than this to a blast throws its fire off it.
const WALL_NEAR := .8

var game: Game
var dice: RandomNumberGenerator
var bits: Array
## [x, y, z, born, scale, side lobe, fire, shape, life, flip, flash, glow]
var booms: Array
## [x, y, z, born, size]
var geysers: Array
## [x, y, z, turn, size, shape, born, View.GroundMark]
var craters: Array = []
var most_bits := 240
var most_craters := CRATERS
var _cfg: ConfigFile
var _looks := {}
var _own := RandomNumberGenerator.new()


func _init(
	g: Game, d: RandomNumberGenerator, bit_list: Array, boom_list: Array, geyser_list: Array
) -> void:
	game = g
	dice = d
	bits = bit_list
	booms = boom_list
	geysers = geyser_list
	_cfg = Tuning.file(PATH)
	var phone := (
		OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	)
	var few := phone or Quality.level() == Quality.LOW
	most_bits = _cfg.get_value("all", "most_bits_low" if few else "most_bits", 240)
	most_craters = CRATERS_LOW if few else CRATERS


## A look's numbers (blast_looks.cfg [look.<name>], over [look.blast]).
func look(name: String) -> Dictionary:
	var known: Variant = _looks.get(name)
	if known != null:
		var kept: Dictionary = known
		return kept
	var out := {}
	for section: String in ["look.blast", "look." + name]:
		if not _cfg.has_section(section):
			continue
		for key: String in _cfg.get_section_keys(section):
			out[key] = _cfg.get_value(section, key)
	out["name"] = name
	_looks[name] = out
	return out


func setting(key: String, fallback: Variant) -> Variant:
	return _cfg.get_value("all", key, fallback)


## Which look a blast of `kind` at (x, y) has: what blew there if it was a
## breakable or a vehicle ([from]), else its kind's ([kinds]).
func look_of(kind: String, x: float, y: float) -> Dictionary:
	var name := str(_cfg.get_value("kinds", kind, "blast"))
	var pieces: Object = game.features.get("breakables")
	if pieces != null:
		var list: Array = pieces.get("pieces")
		for item: Variant in list:
			var p: Object = item
			var broken: bool = p.get("broken")
			if not broken:
				continue
			var px: float = p.get("x")
			var py: float = p.get("y")
			if absf(px - x) < .02 and absf(py - y) < .02:
				name = str(_cfg.get_value("from", str(p.get("image")), name))
				break
	var rides: Object = game.features.get("vehicles")
	if rides != null:
		var list: Array = rides.get("rides")
		for item: Variant in list:
			var v: VehicleDrive.Ride = item
			if v.wreck == game.clock and absf(v.x - x) < .05 and absf(v.y - y) < .05:
				name = str(_cfg.get_value("from", "vehicle", name))
	return look(name)


## Where a blast went off: {floor, water, deck, wall (the way off the nearest
## wall, or zero)}.
func place(x: float, y: float, z: float) -> Dictionary:
	var world := game.world
	var floor_z := Tumble.floor_at(world, x, y, z)
	# Standing water only (a water floor, effects.cfg [water]): a puddle in
	# the rain throws no column.
	var wet := false
	if z - floor_z < .6 and x >= 0.0 and y >= 0.0 and x < world.width and y < world.height:
		var tile := int(world.floor_tile[int(y) * world.width + int(x)])
		if tile >= 0 and tile < world.tile_names.size():
			wet = Effects.WATER.has(String(world.tile_names[tile]))
		wet = wet and absf(floor_z - world.elevation(x, y)) < .05
	var deck := absf(floor_z - world.elevation(x, y)) > .05
	var off := Vector2.ZERO
	var nearest := WALL_NEAR
	for k in 8:
		var dir := Vector2.from_angle(k * TAU / 8.0)
		var d := .15
		while d < nearest:
			if world.blocked(x + dir.x * d, y + dir.y * d, .02, z):
				nearest = d
				off = -dir * (1.0 - d / WALL_NEAR)
				break
			d += .1
	return {"floor": floor_z, "water": wet, "deck": deck, "wall": off}


func _bit(kind: String, at: Vector3, v: Vector3, life: float, size: float, fall := 0.0) -> Bit:
	var bit := Bit.make(kind, at, v, life, size, fall)
	bits.append(bit)
	return bit


## How many of `key` this blast throws: the look's, by `share`, give or take.
func _count(l: Dictionary, key: String, share: float) -> int:
	var base: float = l.get(key, 0.0)
	return maxi(0, roundi(base * share * dice.randf_range(.7, 1.3)))


## A way out along the ground, kept off a wall: within 100 degrees of `off`
## when there is one.
func _way(off: Vector2) -> Vector2:
	var a := dice.randf_range(0, TAU)
	if off != Vector2.ZERO:
		a = off.angle() + dice.randf_range(-1.75, 1.75)
	return Vector2.from_angle(a)


## Everything a blast at (x, y, z) throws, as `look` says, where it is;
## `share` of the bits (a chain throws fewer).
func burst(x: float, y: float, z: float, l: Dictionary, where: Dictionary, share: float) -> void:
	# Its own dice, from where and when it went (and the layer's dice): the
	# same blast in a replay looks the same, no two blasts alike.
	var layer := dice
	dice = _own
	dice.seed = hash(
		[snappedf(x, .001), snappedf(y, .001), snappedf(game.clock, .001), layer.randi()]
	)
	_burst(x, y, z, l, where, share)
	dice = layer


func _burst(x: float, y: float, z: float, l: Dictionary, where: Dictionary, share: float) -> void:
	var floor_z: float = where["floor"]
	var wet: bool = where["water"]
	var deck: bool = where["deck"]
	var off: Vector2 = where["wall"]
	var at := Vector3(x, y, z) + Vector3(off.x, off.y, 0.0) * .35
	var ball: float = l["ball"] * dice.randf_range(.85, 1.15)
	var life: float = l["life"] * dice.randf_range(.9, 1.12)
	var fire := str(l["fire"])
	if wet:
		ball *= .6
		life *= .7
	var born := game.clock
	var low := z - floor_z < 1.2
	booms.append(
		[
			at.x,
			at.y,
			at.z,
			born,
			ball,
			false,
			fire,
			dice.randi_range(0, SHAPES - 1),
			life,
			dice.randf() < .5,
			l["flash"],
			l["glow"]
		]
	)
	# Lobes bursting beside it a moment after, each its own shape and size.
	var most_lobes: int = l["lobes"]
	var lobes := dice.randi_range(1, maxi(1, most_lobes))
	var turn := dice.randf_range(0, TAU)
	for k in lobes:
		var a := turn + k * TAU / lobes + dice.randf_range(-.6, .6)
		var dir := Vector2.from_angle(a)
		if off != Vector2.ZERO and dir.dot(off) < -.2:
			dir = dir.reflect(off.normalized())
		var far := ball * dice.randf_range(.3, .6)
		booms.append(
			[
				at.x + dir.x * far,
				at.y + dir.y * far,
				at.z + dice.randf_range(-.05, .45) * ball,
				born + dice.randf_range(.03, .16),
				ball * dice.randf_range(.42, .68),
				true,
				fire,
				dice.randi_range(0, SHAPES - 1),
				life * dice.randf_range(.7, .95),
				dice.randf() < .5,
				0.0,
				0.0
			]
		)
	if wet:
		geysers.append([x, y, floor_z, born, dice.randf_range(.85, 1.2) * l["ball"]])
	_column(at, l, _count(l, "column", share), _count(l, "cap", share), wet)
	# Scraps arcing out trailing smoke.
	var fling: float = l["fling"]
	for _k in _count(l, "scraps", share):
		var dir := _way(off)
		var v := Vector3(dir.x, dir.y, 0.0) * dice.randf_range(1.2, 4.4) * fling
		v.z = dice.randf_range(2.2, 6.2) * fling
		var scrap := _bit("chunk", at + Vector3(0, 0, .1), v, dice.randf_range(1.4, 2.4), .1, 9.0)
		scrap.look = str(l["scrap"])
		scrap.size = dice.randf_range(.07, .14)
		scrap.trail = dice.randf_range(0.0, .05) if scrap.look != "meat" else 99.0
	# What the ground throws up: clods out of the crater, splinters off a deck.
	if low and not wet:
		for _k in _count(l, "clods", share):
			var dir := _way(off)
			var v := Vector3(dir.x, dir.y, 0.0) * dice.randf_range(.4, 2.2)
			v.z = dice.randf_range(2.8, 5.6)
			var kind := "splinter" if deck else "clod"
			_bit(kind, Vector3(x, y, floor_z + .05), v, dice.randf_range(1.2, 2.0), .05, 9.0)
	# The dust ring: dirt puffs rolling out along the floor (spray on water).
	if low:
		var puffs := _count(l, "puffs", share)
		var start := dice.randf_range(0, TAU)
		for k in puffs:
			var dir := Vector2.from_angle(
				start + k * TAU / maxf(1.0, puffs) + dice.randf_range(-.3, .3)
			)
			var v := Vector3(dir.x, dir.y, 0.0) * dice.randf_range(2.4, 3.6)
			v.z = dice.randf_range(.05, .3)
			var puff := _bit("dust", Vector3(x, y, floor_z + .1), v, dice.randf_range(.9, 1.4), .22)
			puff.look = "smoke" if wet else "dirtpuff"
			puff.grow = .3
			puff.age = -dice.randf_range(0.0, .06)
	for _k in _count(l, "sparks", share):
		var dir := Vector2.from_angle(dice.randf_range(0, TAU))
		var v := Vector3(dir.x, dir.y, 0.0) * dice.randf_range(3.0, 8.0)
		v.z = dice.randf_range(1.0, 6.0)
		_bit("spark", at, v, dice.randf_range(.25, .6), .03, 6.0)
	for _k in _count(l, "embers", share):
		var dir := Vector2.from_angle(dice.randf_range(0, TAU))
		var ember := _bit(
			"ember",
			at,
			Vector3(dir.x, dir.y, 0.0) * dice.randf_range(.3, 1.4) + Vector3(0, 0, 1.0),
			dice.randf_range(1.2, 2.4),
			.035,
			-.3
		)
		ember.vz = dice.randf_range(.6, 1.6)
	if not wet:
		for _k in _count(l, "fire_rain", share):
			var dir := _way(off)
			var v := Vector3(dir.x, dir.y, 0.0) * dice.randf_range(.8, 2.8)
			v.z = dice.randf_range(2.6, 5.0)
			_bit("burning", at, v, dice.randf_range(2.6, 4.0), .05, 7.0)
	else:
		for _k in 10:
			var dir := Vector2.from_angle(dice.randf_range(0, TAU))
			var v := Vector3(dir.x, dir.y, 0.0) * dice.randf_range(.4, 1.6)
			v.z = dice.randf_range(3.0, 5.5)
			_bit("drop", Vector3(x, y, floor_z + .1), v, 1.2, .035, 9.0)
	var crater: float = l["crater"]
	if low and not wet and crater > 0.0:
		_crater(x, y, z, floor_z, crater * dice.randf_range(.8, 1.2), deck)
	_cap()


## The column: soot (or powder, or steam over water) rolling up off the
## fire, leaning on its own and with the wind; `cap` more go higher and
## spread out at its top, a mushroom.
func _column(at: Vector3, l: Dictionary, count: int, cap: int, wet: bool) -> void:
	var rise: float = l["rise"]
	var smoke := "powder" if wet else str(l["smoke"])
	var lean := Vector2.from_angle(dice.randf_range(0, TAU)) * dice.randf_range(.05, .25)
	var ball: float = l["ball"]
	for k in count:
		var puff := _bit(
			"soot",
			(
				at
				+ (
					Vector3(dice.randf_range(-.3, .3), dice.randf_range(-.3, .3), .15 + k * .12)
					* ball
				)
			),
			Vector3(lean.x, lean.y, dice.randf_range(.6, 1.1) * rise * (1.0 + k * .08)),
			dice.randf_range(3.2, 4.8),
			(.6 + k * .06) * ball
		)
		puff.age = -.25 - k * .07
		puff.grow = .55
		puff.look = smoke if smoke == "powder" else "soothot"
	for k in cap:
		var dir := Vector2.from_angle(k * TAU / maxf(1.0, cap) + dice.randf_range(-.4, .4))
		var puff := _bit(
			"soot",
			at + Vector3(0, 0, .3 * ball),
			Vector3(lean.x, lean.y, dice.randf_range(1.5, 1.95) * rise),
			dice.randf_range(3.6, 5.2),
			.8 * ball
		)
		puff.age = -.35 - dice.randf_range(0.0, .15)
		puff.grow = .7
		puff.look = smoke if smoke == "powder" else "soothot"
		puff.spread = dir * dice.randf_range(.45, .8) * ball


## A crater with soot streaks thrown out (a scorch only off a deck: the
## planks do not crater, debris.gd's scorch is there).
func _crater(x: float, y: float, z: float, floor_z: float, size: float, deck: bool) -> void:
	if deck:
		return
	var turn := dice.randf_range(0, TAU)
	var shape := dice.randi_range(0, 3)
	var mark := View.GroundMark.new(
		x, y, floor_z, turn, size, size * dice.randf_range(.85, 1.0), "mark_crater_%d" % shape
	)
	Tumble.lay(game.world, mark, z)
	mark.z += .004
	craters.append([x, y, mark.z, turn, size, shape, game.clock, mark])
	while craters.size() > most_craters:
		craters.pop_front()


func _cap() -> void:
	if bits.size() > most_bits:
		var over := bits.size() - most_bits
		for _k in over:
			bits.pop_front()


## The craters as ground marks near the player, the oldest fading past their
## life.
func crater_marks(out: Array) -> void:
	var p := game.player
	var k := 0
	while k < craters.size():
		var c: Array = craters[k]
		var born: float = c[6]
		var age := game.clock - born
		if age > CRATER_LIFE + 2.0:
			craters.remove_at(k)
			continue
		k += 1
		var cx: float = c[0]
		var cy: float = c[1]
		if (cx - p.x) * (cx - p.x) + (cy - p.y) * (cy - p.y) > 400.0:
			continue
		var mark: View.GroundMark = c[7]
		var shape: int = c[5]
		var picture := "mark_crater_%d" % shape
		if age > CRATER_LIFE:
			picture = game.art.faded_art(picture, 1.0 - (age - CRATER_LIFE) / 2.0)
		mark.image = picture
		out.append(mark)
