## The moonshine stills: a copper still, a copper vat or a shine tank is a
## breakable (data/tuning/breakables.cfg) with something in it. Shot and not
## broken yet, the pipe the shot holed sprays burning shine back toward the
## shooter, an arc of fire `jet_reach` cells long for `jet_life` seconds
## (fire.cfg [stills]): it sets alight what it lands on (fire.gd) and burns
## whoever stands in it. Shot enough it breaks, and it goes up as a `still`
## blast (shots.cfg), its copper thrown about in pieces (the breakables'
## bits) and its shine spilled burning round it (fire.gd [spills]).
##
## Play (game.rng for which way a holed pipe points), carried in snapshots;
## the spray is drawn from that.
extends GameFeature

const Fire := preload("res://src/features/fire.gd")
const Breakables := preload("res://src/features/breakables.gd")
const PATH := "res://data/tuning/fire.cfg"
## A jet's row in `jets`.
const AT_X := 0
const AT_Y := 1
const AT_Z := 2
const DIR_X := 3
const DIR_Y := 4
const UNTIL := 5
const NEXT := 6
## Drops of fire drawn along a spray.
const DROPS := 8

## Each spraying pipe: [x, y, z of the hole, way x, way y, until, next drop].
var jets: Array = []
var _cfg: ConfigFile
var _images := {}


func id() -> String:
	return "stills"


func attach() -> void:
	_cfg = Tuning.file(PATH)
	for image: Variant in _cfg.get_value("stills", "images", []):
		_images[str(image)] = true
	game.events.prop_struck.connect(_struck)
	game.events.prop_broken.connect(_broken)
	game.events.ticked.connect(_tick)


func num(key: String) -> float:
	var v: float = _cfg.get_value("stills", key, 0.0)
	return v


func _fire() -> Fire:
	var fire: Fire = game.features.get("fire")
	return fire if fire != null and fire.allowed() else null


## A still was shot: the holed pipe sprays back the way the shot came, a
## little to one side (one jet a still; another hit keeps it going).
func _struck(image: String, x: float, y: float, z: float, ax: float, ay: float) -> void:
	if not _images.has(image) or _fire() == null:
		return
	var back := Vector2(-ax, -ay)
	if back.length() < .01:
		back = Vector2.from_angle(game.rng.uniform(0.0, TAU))
	back = back.normalized().rotated(game.rng.uniform(-.7, .7))
	for jet: Array in jets:
		var jx: float = jet[AT_X]
		var jy: float = jet[AT_Y]
		if absf(jx - x) < .8 and absf(jy - y) < .8:
			jet[UNTIL] = game.clock + num("jet_life")
			return
	var floor_z := game.world.elevation(x, y)
	var hole := clampf(z, floor_z + .35, floor_z + 1.3)
	jets.append([x, y, hole, back.x, back.y, game.clock + num("jet_life"), game.clock])
	game.sound_at("pressure_vent", x, y, .9)
	game.sound_at("molotov_burst", x, y, .5)


## A still broke: no more spray from it; its copper flies (it goes up as a
## blast of its own a moment later: breakables.cfg `blast`).
func _broken(image: String, x: float, y: float, z: float) -> void:
	if not _images.has(image):
		return
	var kept: Array = []
	for jet: Array in jets:
		var jx: float = jet[AT_X]
		var jy: float = jet[AT_Y]
		if absf(jx - x) > .8 or absf(jy - y) > .8:
			kept.append(jet)
	jets = kept
	var bk: Breakables = game.features.get("breakables")
	if bk != null:
		var count := int(num("pieces"))
		bk.scatter(x, y, z, "orange", count, 0.0, 0.0)
		bk.scatter(x, y, z + .3, "tin", count / 2, 0.0, 0.0)
	game.sound_at("arm_vent", x, y, .9)


func _tick(_dt: float) -> void:
	if jets.is_empty():
		return
	var fire := _fire()
	var kept: Array = []
	for jet: Array in jets:
		var until: float = jet[UNTIL]
		if game.clock >= until or fire == null:
			continue
		kept.append(jet)
		var next: float = jet[NEXT]
		if game.clock < next:
			continue
		jet[NEXT] = game.clock + num("jet_every")
		_spray(jet, fire)
	jets = kept


## One beat of a spray: where it lands now (it sways in and out), set alight,
## and whoever is in its path burned.
func _spray(jet: Array, fire: Fire) -> void:
	var x: float = jet[AT_X]
	var y: float = jet[AT_Y]
	var z: float = jet[AT_Z]
	var way := _way(jet)
	var reach := num("jet_reach") * (.65 + .35 * sin(game.clock * 5.0))
	var w := game.world
	var land := Vector2(x, y) + way * .45
	for k in range(1, int(reach / .3) + 1):
		var at := Vector2(x, y) + way * (.45 + k * .3)
		if w.blocked(at.x, at.y, .08, z - k * .1):
			break
		land = at
	var floor_z := w.floor_under(land.x, land.y, z)
	fire.fresh()
	if not fire.ignite(land.x, land.y, floor_z, num("jet_life") * .6):
		fire.spill(land.x, land.y, floor_z)
	var bite := num("jet_bite") * num("jet_every") / .5
	for p: Player in game.players:
		if p.health > 0 and _in_path(p.x, p.y, x, y, land):
			game.damage(bite, [x, y], "FIRE", p)
	for e: Enemy in game.enemies:
		if e.alive and e.brain != "bessie" and _in_path(e.x, e.y, x, y, land):
			e.hurt(bite, game, false, false, null, "fire")


func _in_path(px: float, py: float, x: float, y: float, land: Vector2) -> bool:
	var a := Vector2(x, y)
	var run := land - a
	var length := run.length()
	if length < .01:
		return false
	var t := clampf((Vector2(px, py) - a).dot(run) / (length * length), 0.0, 1.0)
	return (a + run * t).distance_to(Vector2(px, py)) < .4


func sprites() -> Array:
	var out: Array = []
	if jets.is_empty():
		return out
	var frame := int(game.clock * 14.0)
	for jet: Array in jets:
		var x: float = jet[AT_X]
		var y: float = jet[AT_Y]
		if not game.in_view(x, y, 3.0):
			continue
		var z: float = jet[AT_Z]
		var way := _way(jet)
		var reach := num("jet_reach") * (.65 + .35 * sin(game.clock * 5.0))
		var floor_z := game.world.elevation(x, y)
		for k in DROPS:
			var t := (k + .5) / DROPS
			var at := Vector2(x, y) + way * (.35 + reach * t)
			# An arc: up out of the hole, falling to the floor where it lands.
			var h := z + (z - floor_z) * (.25 * t - t * t * 1.0) + .1 * t
			var s: View.Sprite = game.pooled(
				at.x, at.y, "fx_flame_%d" % ((frame + k) % 4), .18 + .3 * t, maxf(floor_z, h - .1)
			)
			s.glow = true
			out.append(s)
	return out


func _way(jet: Array) -> Vector2:
	var dx: float = jet[DIR_X]
	var dy: float = jet[DIR_Y]
	return Vector2(dx, dy)
