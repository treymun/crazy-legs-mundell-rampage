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
	var drip := 0.0


## Dust or sparks where a bullet struck.
class Puff:
	var x := 0.0
	var y := 0.0
	var z := 0.0
	var age := 0.0
	var kind := "puff"


## Gore keeps fixed-size rings: the oldest chunk, pool or splat is reused, so a
## long fight never grows these lists or stalls on freeing them.
const GIB_CAP := 64
const PUFF_CAP := 20
const BLOOD_CAP := 96
const SPLAT_CAP := 32
const GIB_PARTS := [
	"head",
	"arm",
	"arm",
	"hand",
	"boot",
	"boot",
	"rib",
	"gut",
	"eye",
	"eye",
	"meat",
	"meat",
	"meat",
	"chunk",
	"chunk",
	"organ"
]
const GIB_SIZES := {
	"eye": .09,
	"meat": .15,
	"chunk": .19,
	"organ": .18,
	"rib": .30,
	"arm": .34,
	"boot": .30,
	"head": .26,
	"hand": .13,
	"gut": .24
}
var gibs: Array = []
var puffs: Array = []
## Blood thrown onto the lens by a close overkill: [x, y, radius, age, green].
var lens: Array = []
var blood_marks: Array = []
var walls: Array = []
var dice := RandomNumberGenerator.new()
var _splat_clock := -1.0
var game: Game


func _init(owner: Game) -> void:
	game = owner
	# A fixed seed: a new RandomNumberGenerator starts from a random one, and the
	# same fight should splash the same way every time it is replayed or tested.
	dice.seed = 1997


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
	var green := Enemy.GREEN_GIBS.has(enemy.kind)
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
	# Close enough and some of it reaches the lens.
	var near := sqrt(
		(
			(enemy.x - game.player.x) * (enemy.x - game.player.x)
			+ (enemy.y - game.player.y) * (enemy.y - game.player.y)
		)
	)
	if near < 2.4:
		for _i in 5 + dice.randi() % 5:
			var lx := dice.randf_range(14.0, 306.0)
			var ly := dice.randf_range(10.0, 132.0)
			if absf(lx - 160.0) < 34.0 and absf(ly - 78.0) < 26.0:
				continue
			lens.append([lx, ly, dice.randf_range(1.5, 4.5), 0.0, green])
		while lens.size() > 18:
			lens.pop_front()


## A body that fell whole still bleeds where it lies.
func bleed_out(enemy: Enemy, green: bool) -> void:
	if not game.gore:
		return
	_stain(enemy.x, enemy.y, dice.randf_range(.26, .36), green)
	for _i in 2:
		var a := dice.randf() * TAU
		_stain(enemy.x + cos(a) * .3, enemy.y + sin(a) * .3, dice.randf_range(.10, .18), green)


## Dust or sparks where a bullet lands.
func impact(x: float, y: float, z: float, surface: String) -> void:
	var puff := Puff.new()
	puff.x = x
	puff.y = y
	puff.z = z
	puff.kind = "sparks" if surface == "metal" else "puff"
	puffs.append(puff)
	if puffs.size() > PUFF_CAP:
		puffs.pop_front()


## Blood on the lens runs down and thins out.
func draw_lens(c: Canvas) -> void:
	for drop: Array in lens:
		var age: float = drop[3]
		var radius := int(float(drop[2]) * (1.0 - age / 2.8))
		if radius < 1:
			continue
		var color := Canvas.rgb(70, 150, 50) if drop[4] else Canvas.rgb(132, 16, 16)
		var x := int(drop[0])
		var y := int(float(drop[1]) + age * age * 9.0)
		if y < Renderer.VIEW - radius - 1:
			c.circle(x, y, radius, color, true)
			if radius > 2:
				c.fill_rect(x - 1, y - radius - int(age * 8.0), 2, int(age * 8.0), color)


func tick(dt: float) -> void:
	for puff: Puff in puffs:
		puff.age += dt
	while not puffs.is_empty() and puffs[0].age > .34:
		puffs.pop_front()
	for drop: Array in lens:
		drop[3] = float(drop[3]) + dt
	while not lens.is_empty() and float(lens[0][3]) > 2.8:
		lens.pop_front()
	for g: Gib in gibs:
		if g.rest:
			g.age += dt
			continue
		g.vz -= 9.4 * dt
		# A chunk in the air leaves a line of drops behind it.
		g.drip -= dt
		if g.drip <= 0.0 and game.specks.size() < 170:
			g.drip = .09
			game.specks.append(
				Game.Speck.new(
					g.x,
					g.y,
					g.z,
					0.0,
					0.0,
					-.2,
					dice.randf_range(.18, .34),
					"plasma" if g.green else "gore"
				)
			)
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
