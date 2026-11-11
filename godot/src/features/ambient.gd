## Life at the edges of a level: crows crossing the evening sky now and then
## (cawing), and fireflies blinking about the dark yards. A level's mood says
## which it has (effects.cfg crows, fireflies). Outdoors only, looks only (its
## own dice, never saved), none with SCENERY MOTION on STATIC and half as many
## on REDUCED.
extends GameFeature


## A crow on its way across, or a firefly about its business.
class Mote:
	var x := 0.0
	var y := 0.0
	var z := 0.0
	var vx := 0.0
	var vy := 0.0
	var age := 0.0
	var life := 10.0
	var phase := 0.0
	var crow := false


var dice := RandomNumberGenerator.new()
var motes: Array = []
var next_flock := 0.0


func id() -> String:
	return "ambient"


func attach() -> void:
	dice.seed = hash(game.level.id) + 7
	next_flock = dice.randf_range(4.0, 12.0)
	game.ticked.connect(_tick)


func _motion() -> int:
	return int(game.renderer.world_motion)


func _tick(dt: float) -> void:
	var id_: String = game.level.id
	var p = game.player
	var outdoors: bool = game.world.roof[game.world.cell(p.x, p.y)] == 0.0
	var kept: Array = []
	for m: Mote in motes:
		m.age += dt
		m.x += m.vx * dt
		m.y += m.vy * dt
		if not m.crow:
			# A firefly wanders and bobs.
			m.vx += dice.randf_range(-.6, .6) * dt
			m.vy += dice.randf_range(-.6, .6) * dt
			m.vx = clampf(m.vx, -.35, .35)
			m.vy = clampf(m.vy, -.35, .35)
			m.z += sin(m.age * 1.7 + m.phase) * .08 * dt
		var far := Vector2(m.x - p.x, m.y - p.y).length()
		if m.age < m.life and far < 24.0:
			kept.append(m)
	motes = kept
	if _motion() == 2 or game.in_hub or not outdoors:
		return
	var thin := 2 if _motion() == 1 else 1
	if bool(Effects.mood(id_, "crows", false)) and game.clock >= next_flock:
		next_flock = game.clock + dice.randf_range(14.0, 30.0) * thin
		_flock(p)
	if bool(Effects.mood(id_, "fireflies", false)):
		var lights := 0
		for m: Mote in motes:
			if not m.crow:
				lights += 1
		while lights < 10 / thin:
			_firefly(p)
			lights += 1


func _flock(p) -> void:
	var heading := dice.randf_range(0, TAU)
	var side := Vector2(cos(heading + PI / 2), sin(heading + PI / 2))
	var start := (
		Vector2(p.x, p.y)
		- Vector2(cos(heading), sin(heading)) * 14.0
		+ side * dice.randf_range(-6.0, 6.0)
	)
	for k in dice.randi_range(2, 4):
		var crow := Mote.new()
		crow.crow = true
		crow.x = start.x + dice.randf_range(-1.2, 1.2)
		crow.y = start.y + dice.randf_range(-1.2, 1.2)
		crow.z = game.world.elevation(p.x, p.y) + dice.randf_range(3.2, 4.6)
		var speed := dice.randf_range(2.6, 3.4)
		crow.vx = cos(heading) * speed
		crow.vy = sin(heading) * speed
		crow.life = 30.0 / speed
		crow.phase = dice.randf_range(0, TAU)
		motes.append(crow)
	game.sound_at("distant_crow", start.x, start.y, .35)


func _firefly(p) -> void:
	var fly := Mote.new()
	var a := dice.randf_range(0, TAU)
	var d := dice.randf_range(2.0, 7.0)
	fly.x = p.x + cos(a) * d
	fly.y = p.y + sin(a) * d
	if game.world.blocked(fly.x, fly.y, .05):
		fly.x = p.x
		fly.y = p.y
	fly.z = game.world.elevation(fly.x, fly.y) + dice.randf_range(.25, 1.3)
	fly.life = dice.randf_range(6.0, 14.0)
	fly.phase = dice.randf_range(0, TAU)
	motes.append(fly)


func sprites() -> Array:
	var out: Array = []
	for m: Mote in motes:
		if m.crow:
			var crow := Renderer.Sprite.new(
				m.x, m.y, "fx_crow_%d" % (int(m.age * 5.0 + m.phase) % 2), .32, m.z
			)
			crow.flip = m.vx < 0.0
			out.append(crow)
		else:
			# Lit a moment, dark a while.
			var lit := fmod(m.age * .9 + m.phase, 2.4) < .7
			var fly := Renderer.Sprite.new(m.x, m.y, "fx_firefly_%d" % (0 if lit else 1), .035, m.z)
			fly.glow = lit
			out.append(fly)
	return out
