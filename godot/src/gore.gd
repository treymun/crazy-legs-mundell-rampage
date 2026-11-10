## Gore: chunks thrown by an overkill, blood leaving a wound, and the pools and
## splats it leaves on floors and walls.
##
## None of this draws from the game's own dice: the simulation stays in step
## with the reference whether gore is on or off.
class_name Gore
extends RefCounted


## A chunk thrown by an overkill: it flies, bounces and comes to rest.
class Gib:
	var x := 0.0
	var y := 0.0
	var z := 0.0
	var vx := 0.0
	var vy := 0.0
	var vz := 0.0
	var image := ""
	var size := .2
	var flip := false
	var rest := false
	var age := 0.0
	var green := false


## Gore keeps fixed-size rings: the oldest chunk, pool or splat is reused, so a
## long fight never grows these lists or stalls on freeing them.
const GIB_CAP := 40
const BLOOD_CAP := 96
const SPLAT_CAP := 32
const GIB_PARTS := ["arm", "arm", "boot", "boot", "rib", "eye", "meat", "meat", "chunk", "organ"]
const GIB_SIZES := {
	"eye": .09, "meat": .15, "chunk": .19, "organ": .18, "rib": .30, "arm": .34, "boot": .30
}
var gibs: Array = []
var blood_marks: Array = []
var walls: Array = []
var dice := RandomNumberGenerator.new()
var _splat_clock := -1.0
var game: Game


func _init(owner: Game) -> void:
	game = owner


func _stain(x: float, y: float, radius: float, green: bool) -> void:
	if game.world.blocked(x, y):
		return
	var image := "mark_%s_%d" % ["acid" if green else "blood", dice.randi() % 3]
	blood_marks.append(
		Renderer.GroundMark.new(
			x, y, game.world.elevation(x, y) + .004, dice.randf() * TAU, radius, radius, image
		)
	)
	if blood_marks.size() > BLOOD_CAP:
		blood_marks.pop_front()


## Blood leaving a wound along (ax, ay): drops in the air, drops on the floor
## beyond the body, and a splat on a wall close behind it.
func spray(x: float, y: float, z: float, ax: float, ay: float, amount: float, green: bool) -> void:
	if not game.gore:
		return
	var kind := "plasma" if green else "gore"
	for _i in clampi(int(amount / 9.0), 2, 7):
		if game.specks.size() >= 170:
			break
		var push := dice.randf_range(.7, 2.6)
		var side := dice.randf_range(-.7, .7)
		game.specks.append(
			Game.Speck.new(
				x,
				y,
				z,
				ax * push - ay * side,
				ay * push + ax * side,
				dice.randf_range(.2, 1.7),
				dice.randf_range(.22, .6),
				kind
			)
		)
	if amount >= 12.0:
		var reach := dice.randf_range(.25, .95)
		var radius := dice.randf_range(.10, .10 + minf(.2, amount * .004))
		_stain(x + ax * reach, y + ay * reach, radius, green)
	var d := .25
	while d < 1.9:
		if game.world.blocked(x + ax * d, y + ay * d, .02):
			var mark = game.renderer.wall_mark(x, y, z, ax, ay, 0.0, d)
			if mark != null:
				mark.image = "fx_%s_%d" % ["acid" if green else "blood", dice.randi() % 4]
				mark.radius = dice.randf_range(.17, .30)
				mark.z = clampf(z + dice.randf_range(-.25, .15), .25, 1.7)
				walls.append(mark)
				if walls.size() > SPLAT_CAP:
					walls.pop_front()
			break
		d += .12


## An overkill: the body comes apart instead of falling over.
func burst(enemy: Enemy) -> void:
	var green := enemy.kind in ["alien", "boss", "crawler", "lantern", "chalk_spitter"]
	var floor_z: float = game.world.elevation(enemy.x, enemy.y)
	var away := atan2(enemy.y - game.player.y, enemy.x - game.player.x)
	var prefix := "gib_a_" if green else "gib_"
	for part: String in GIB_PARTS:
		var g := Gib.new()
		var angle := away + dice.randf_range(-1.5, 1.5)
		var speed := dice.randf_range(1.0, 3.6)
		g.x = enemy.x
		g.y = enemy.y
		g.z = floor_z + enemy.height * dice.randf_range(.3, .8)
		g.vx = cos(angle) * speed
		g.vy = sin(angle) * speed
		g.vz = dice.randf_range(1.4, 3.6)
		g.image = prefix + part
		g.size = float(GIB_SIZES[part])
		g.flip = dice.randf() < .5
		g.green = green
		gibs.append(g)
	while gibs.size() > GIB_CAP:
		gibs.pop_front()
	_stain(enemy.x, enemy.y, .42, green)
	for _i in 5:
		var a := dice.randf() * TAU
		var r := dice.randf_range(.3, 1.1)
		_stain(enemy.x + cos(a) * r, enemy.y + sin(a) * r, dice.randf_range(.12, .26), green)
	for k in 4:
		var a := away + (k - 1.5) * .8
		spray(enemy.x, enemy.y, floor_z + enemy.height * .55, cos(a), sin(a), 40.0, green)
	game.sound_at("gib_burst", enemy.x, enemy.y, .95)


func tick(dt: float) -> void:
	for g: Gib in gibs:
		if g.rest:
			g.age += dt
			continue
		g.vz -= 9.4 * dt
		var nx := g.x + g.vx * dt
		var ny := g.y + g.vy * dt
		if game.world.blocked(nx, ny, .06):
			g.vx *= -.35
			g.vy *= -.35
		else:
			g.x = nx
			g.y = ny
		g.z += g.vz * dt
		var floor_z: float = game.world.elevation(g.x, g.y)
		if g.z <= floor_z:
			g.z = floor_z
			if g.vz < -1.5:
				g.vz *= -.36
				g.vx *= .55
				g.vy *= .55
				_stain(g.x, g.y, dice.randf_range(.09, .18), g.green)
				if game.clock - _splat_clock > .11:
					_splat_clock = game.clock
					game.sound_at("gib_splat", g.x, g.y, .55)
			else:
				g.rest = true
				g.vz = 0.0
	if not gibs.is_empty() and gibs[0].rest and gibs[0].age > 45.0:
		gibs.pop_front()
