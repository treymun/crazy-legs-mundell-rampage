## Gore: chunks thrown by an overkill, blood leaving a wound, and the pools and
## splats it leaves on floors and walls (more of it in gore_extras.gd: pools
## that spread, limbs off, robot scrap, charred chunks, streaks, boot prints).
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
	## How far it has rolled along the ground (it turns over as it goes).
	var roll := 0.0
	## Scrap off a robot: no blood where it lands or rolls.
	var metal := false
	## How far it has turned over (View.Sprite.spin) and how fast it turns in
	## the air (radians a second); on the ground it turns as it rolls.
	var spin := 0.0
	var spin_rate := 0.0
	## Come down in water: it sinks under its face (SINK_RATE, SINK_TIME).
	var sinking := false


## Dust or sparks where a bullet struck.
class Puff:
	var x := 0.0
	var y := 0.0
	var z := 0.0
	var age := 0.0
	var kind := "puff"


## Gore keeps fixed-size rings: the oldest chunk, pool or splat is reused, so a
## long fight never grows these lists or stalls on freeing them.
const GIB_CAP := 80
## A chunk come down in water sinks this fast (units a second) for this long.
const SINK_RATE := .3
const SINK_TIME := 1.2
const Water := preload("res://src/features/water.gd")
const PUFF_CAP := 20
const BLOOD_CAP := 140
const SPLAT_CAP := 48
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
## gore_extras.gd's: pools spreading [mark, size], stumps spurting [enemy,
## until, next, green, height], and the boot prints the player has left in them.
var pools: Array = []
var spurts: Array = []
## Bodies whose head was taken off (GoreExtras.limb): game_view.gd shows
## their `<kind>_down_headless` cel once they are down.
var headless := {}
## Bodies that lost a limb (GoreExtras.limb): enemy -> [piece, side], the
## piece "head", "arm", "hand" or "boot", the side "r" or "l". The 3D view
## leaves that limb off the body's model (view3d/actor_layer.gd).
var lost := {}
var bloody := 0
var bloody_green := false
var walked := 0.0
var last_at := Vector2.INF
var foot := false
## How each size of chunk moves (tumble.gd), made once.
var _feels := {}
## The resting chunk _wake_one() looks at next.
var _wake_at := 0
var game: Game


func _init(owner: Game) -> void:
	game = owner
	# A fixed seed: a new RandomNumberGenerator starts from a random one, and the
	# same fight should splash the same way every time it is replayed or tested.
	dice.seed = 1997
	# Gore listens first (before any feature): the same moment the old direct
	# calls had, so nothing about play or the dice moves.
	owner.events.blood_sprayed.connect(spray)
	owner.events.enemy_gibbed.connect(burst)
	owner.events.enemy_bled_out.connect(bleed_out)
	owner.events.wall_struck.connect(impact)
	owner.events.blast_shoved.connect(shove)


## A drop of blood landing at (x, y) from height `from_z`: on the floor under
## it there (a deck, a stair, a ramp tilted with it, the ground).
func _stain(x: float, y: float, radius: float, green: bool, from_z: float) -> void:
	if game.world.blocked(x, y):
		return
	var image := "mark_%s_%d" % ["acid" if green else "blood", dice.randi() % 3]
	blood_marks.append(
		Tumble.lay(
			game.world,
			View.GroundMark.new(x, y, 0.0, dice.randf() * TAU, radius, radius, image),
			from_z
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
	var hand := game.player
	if (
		hand != null
		and game.acting_local()
		and hand.armory.shot_age < .5
		and Vector2(hand.x - x, hand.y - y).length() < 2.6
	):
		MeleeBlood.bloody(hand.armory, hand.armory.active, amount, green)
	# A big hit throws more, and lays a long streak along the shot.
	if amount >= 28.0:
		GoreExtras.streak(self, x, y, ax, ay, amount, green, z)
	for _i in clampi(int(amount / 9.0), 2, 7 if amount < 40.0 else 11):
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
		_stain(x + ax * reach, y + ay * reach, radius, green, z)
	var d := .25
	while d < 1.9:
		if game.world.blocked(x + ax * d, y + ay * d, .02, z):
			var mark: Variant = WallHits.wall_mark(game.world, x, y, z, ax, ay, 0.0, d)
			if mark != null:
				mark.image = "fx_%s_%d" % ["acid" if green else "blood", dice.randi() % 4]
				mark.radius = dice.randf_range(.17, .30)
				# Up the wall from the floor it stands on (a loft, a deck), not
				# from the ground under it.
				var floor_z: float = game.world.floor_under(x, y, z)
				mark.z = clampf(z + dice.randf_range(-.25, .15), floor_z + .25, floor_z + 1.7)
				walls.append(mark)
				if walls.size() > SPLAT_CAP:
					walls.pop_front()
			break
		d += .12


## An overkill: the body comes apart instead of falling over.
func burst(enemy: Enemy) -> void:
	if GoreExtras.metal(enemy):
		GoreExtras.scrap(self, enemy)
		return
	var green := Enemy.GREEN_GIBS.has(enemy.kind)
	var floor_z: float = game.world.stand(enemy)
	var away := atan2(enemy.y - game.player.y, enemy.x - game.player.x)
	var prefix := "gib_a_" if green else "gib_"
	# A blast chars half of what it throws and leaves soot with the blood.
	var charred := enemy.killed_by == "blast" and not green
	if charred:
		var soot := View.GroundMark.new(
			enemy.x,
			enemy.y,
			floor_z + .003,
			dice.randf() * TAU,
			.6,
			.6,
			"mark_scorch_%d" % (dice.randi() % 3)
		)
		blood_marks.append(Tumble.lay(game.world, soot, floor_z + .2, .003))
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
		if charred and dice.randf() < .5:
			g.image = "gib_c_" + part
		g.size = GIB_SIZES[part]
		g.flip = dice.randf() < .5
		g.green = green
		g.spin_rate = spin_rate(g.size)
		gibs.append(g)
	while gibs.size() > GIB_CAP:
		gibs.pop_front()
	_stain(enemy.x, enemy.y, .42, green, floor_z + .3)
	for _i in 5:
		var a := dice.randf() * TAU
		var r := dice.randf_range(.3, 1.1)
		_stain(
			enemy.x + cos(a) * r,
			enemy.y + sin(a) * r,
			dice.randf_range(.12, .26),
			green,
			floor_z + .3
		)
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
	# The pool spreads where the body comes to rest (settled()); here the
	# drops as it falls, and a limb or the head a heavy hit took off.
	GoreExtras.limb(self, enemy)
	var from_z: float = game.world.stand(enemy) + .3
	for _i in 2:
		var a := dice.randf() * TAU
		_stain(
			enemy.x + cos(a) * .3, enemy.y + sin(a) * .3, dice.randf_range(.10, .18), green, from_z
		)


## A body came to rest (features/corpses.gd): its pool spreads there.
func settled(enemy: Enemy) -> void:
	GoreExtras.pool(self, enemy)


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
		var drop_size: float = drop[2]
		var radius := int(drop_size * (1.0 - age / 2.8))
		if radius < 1:
			continue
		var color := Canvas.rgb(70, 150, 50) if drop[4] else Canvas.rgb(132, 16, 16)
		var x: int = drop[0]
		var drop_y: float = drop[1]
		var y := int(drop_y + age * age * 9.0)
		if y < View.VIEW - radius - 1:
			c.circle(x, y, radius, color, true)
			if radius > 2:
				c.fill_rect(x - 1, y - radius - int(age * 8.0), 2, int(age * 8.0), color)


func tick(dt: float) -> void:
	GoreExtras.grow(self, dt)
	GoreExtras.spurt(self)
	GoreExtras.prints(self)
	for puff: Puff in puffs:
		puff.age += dt
	while not puffs.is_empty() and puffs[0].age > .34:
		puffs.pop_front()
	for drop: Array in lens:
		var drop_age: float = drop[3]
		drop[3] = drop_age + dt
	while not lens.is_empty() and lens[0][3] > 2.8:
		lens.pop_front()
	_wake_one()
	for g: Gib in gibs:
		if g.rest:
			g.age += dt
			if g.sinking and g.age < SINK_TIME:
				# Gone into the water: down under its face.
				g.z -= SINK_RATE * dt
			continue
		# A chunk in the air leaves a line of drops behind it.
		g.drip -= dt
		if g.vz != 0.0 and g.drip <= 0.0 and game.specks.size() < 170 and not g.metal:
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
		# Off walls, floors and furniture, down slopes, rolling to a stop
		# (tumble.gd): never left inside a wall.
		var ox := g.x
		var oy := g.y
		var hit := Tumble.step(game.world, g, _feel(g.size), dt)
		if hit & (Tumble.FLOOR | Tumble.RESTED) and Water.splash_if(game, g.x, g.y, g.z, g.size * 2.0):
			# Into the water: a splash, and it sinks.
			g.rest = true
			g.sinking = true
			g.age = 0.0
			continue
		if hit & Tumble.RESTED:
			# It comes to lie on one face or the other: the 3D view eases it
			# over from the turn it stopped at (kept), by its age at rest.
			g.rest = true
			g.age = 0.0
		if hit & Tumble.FLOOR:
			# Each bounce takes the most of its spin.
			g.spin_rate *= -.45
			if not g.metal:
				_stain(g.x, g.y, dice.randf_range(.09, .18), g.green, g.z + .05)
			if game.clock - _splat_clock > .11:
				_splat_clock = game.clock
				game.sound_at("metal_down" if g.metal else "gib_splat", g.x, g.y, .45)
		elif hit & Tumble.WALL:
			GoreExtras.wall_splat(self, g)
			g.spin_rate *= -.6
			if game.clock - _splat_clock > .11:
				_splat_clock = game.clock
				game.sound_at("metal_down" if g.metal else "gib_splat", g.x, g.y, .35)
		if g.rest:
			continue
		if g.vz == 0.0:
			# On the ground it turns over as it rolls (by its run, not the air's spin).
			var run := Vector2(g.x - ox, g.y - oy).length()
			var was := int(g.roll / .22)
			g.roll += run
			g.spin += run / maxf(.05, g.size * .5) * signf(g.spin_rate + .001)
			if int(g.roll / .22) != was:
				# A chunk rolling smears a trail behind it.
				if not g.metal and g.roll < 2.0:
					_stain(g.x, g.y, dice.randf_range(.05, .08), g.green, g.z + .05)
		else:
			g.spin += g.spin_rate * dt
	if not gibs.is_empty() and gibs[0].rest and gibs[0].age > 45.0:
		gibs.pop_front()


## One resting chunk a tick is asked whether it still has something under it
## (the crate it lay on shot away): if not, it falls again.
func _wake_one() -> void:
	if gibs.is_empty():
		return
	_wake_at = (_wake_at + 1) % gibs.size()
	var g: Gib = gibs[_wake_at]
	if g.rest and Tumble.unsupported(game.world, g, _feel(g.size)):
		g.rest = false
		g.age = 0.0


## How fast a chunk thrown off turns over in the air: small ones fastest,
## either way round (radians a second).
func spin_rate(size: float) -> float:
	var rate := (6.0 + 1.2 / maxf(.05, size)) * dice.randf_range(.75, 1.25)
	return rate if dice.randf() < .5 else -rate


## How a chunk its size moves: small ones bounce more and roll further.
func _feel(size: float) -> Tumble.Feel:
	var key := snappedf(size, .05)
	var feel: Tumble.Feel = _feels.get(key)
	if feel == null:
		feel = Tumble.Feel.new(clampf(size * .3, .03, .1), .45, .36, 1.6 + size * 4.0)
		feel.grip = .55
		feel.hard = 1.5
		feel.pull = .9
		_feels[key] = feel
	return feel


## A blast throws the chunks lying near it (game_combat.gd explode()).
func shove(x: float, y: float, reach: float, power: float) -> void:
	for g: Gib in gibs:
		if absf(g.x - x) > reach or absf(g.y - y) > reach:
			continue
		var push := Tumble.shove(x, y, reach, power, g.x, g.y)
		if push == Vector3.ZERO or not game.world.visible(x, y, g.x, g.y):
			continue
		g.vx += push.x * dice.randf_range(.8, 1.2)
		g.vy += push.y * dice.randf_range(.8, 1.2)
		g.vz += push.z
		g.rest = false
		g.age = 0.0
