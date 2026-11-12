## What hangs in the air of a fight and a dusk yard: gun smoke that lingers
## off the muzzle and drifts on the level's wind, boot dust off dirt roads
## (the player's and the county's), dust rolling up behind the speedway's race
## cars and the derby boss, and embers lifting off burn barrels, stills and
## grills, with their smoke. Looks only: its own dice, never saved, at most
## effects.cfg [debris] dust_cap of it at once (the oldest goes first).
extends GameFeature

## Fires and what rises off them: picture -> [embers from (part of its
## height), seconds between embers, smoke from (part of its height), seconds
## between wisps (0: none)].
const FIRES := {
	"town_burn_barrel": [.72, .16, .95, .45],
	"town_still": [.2, .7, .97, 1.1],
	"town_grill": [.5, 1.4, .98, .6],
}
## How near a fire, a car or a boot must be for its dust or embers to be made.
const NEAR := 12.0


## One puff, wisp or ember.
class Mote:
	var x := 0.0
	var y := 0.0
	var z := 0.0
	var vx := 0.0
	var vy := 0.0
	var vz := 0.0
	var age := 0.0
	var life := 1.0
	var size := .1
	var grow := 0.0
	var kind := "dust"


var dice := RandomNumberGenerator.new()
var motes: Array = []
var wind := Vector2.ZERO
## [x, y, ground z, height, picture's row of FIRES, next ember, next wisp]
var _fires: Array = []
## Enemy instance -> [x, y, next puff]
var _strides := {}
var _step := 0
var _smoke_next := 0.0
var _trail_next := 0.0


func id() -> String:
	return "dust"


func attach() -> void:
	dice.seed = 1953
	wind = Effects.DEBRIS.get("wind_" + game.level.id, Vector2.ZERO)
	for board: LevelData.Billboard in game.world.billboards:
		if FIRES.has(board.image):
			_fires.append(
				[
					board.x,
					board.y,
					game.world.elevation(board.x, board.y) + board.z,
					board.height,
					FIRES[board.image],
					0.0,
					0.0
				]
			)
	game.shot_fired.connect(_fired)
	game.ticked.connect(_tick)


func _add(kind: String, at: Vector3, v: Vector3, life: float, size: float, grow: float) -> void:
	var m := Mote.new()
	m.kind = kind
	m.x = at.x
	m.y = at.y
	m.z = at.z
	m.vx = v.x
	m.vy = v.y
	m.vz = v.z
	m.life = life
	m.size = size
	m.grow = grow
	motes.append(m)
	var cap := int(Effects.DEBRIS.get("dust_cap", 56))
	if motes.size() > cap:
		motes = motes.slice(motes.size() - cap)


## Gun smoke off the muzzle, out ahead a little and hanging.
func _fired(gun: int) -> void:
	if not gun in Weapons.MUZZLE_GUNS or gun == Weapons.ARMGUN or game.clock < _smoke_next:
		return
	# A gun that fires fast lays one thicker cloud, not a wall of them.
	_smoke_next = game.clock + .14
	var p = game.player
	var a: float = p.view_angle()
	var count := 2 if gun == Weapons.SHOTGUN else 1
	for k in count:
		var ahead := dice.randf_range(.75, 1.1)
		var at := Vector3(
			p.x + cos(a) * ahead - sin(a) * .1,
			p.y + sin(a) * ahead + cos(a) * .1,
			p.eye - .14 + dice.randf_range(-.03, .03)
		)
		var push := dice.randf_range(.3, .7)
		var v := Vector3(
			cos(a) * push + dice.randf_range(-.08, .08),
			sin(a) * push + dice.randf_range(-.08, .08),
			dice.randf_range(.05, .16)
		)
		_add("smoke", at, v, dice.randf_range(2.2, 3.4), .06 + k * .015, .17)


func _tick(dt: float) -> void:
	_boots()
	_race_dust()
	_embers()
	var world: LevelData = game.world
	var solid := world.solid
	var width := world.width
	var height := world.height
	var kept: Array = []
	for m: Mote in motes:
		m.age += dt
		if m.age >= m.life:
			continue
		kept.append(m)
		m.size += m.grow * dt
		var pull := minf(1.0, dt * (1.2 if m.kind == "ember" else 1.8))
		m.vx += (wind.x - m.vx) * pull
		m.vy += (wind.y - m.vy) * pull
		if m.kind == "ember":
			# Lifting on the heat, wavering, slowing as it cools.
			m.vz = maxf(.12, m.vz - .35 * dt)
			m.vx += sin(m.age * 9.0 + m.size * 300.0) * .6 * dt
		elif m.kind == "dust":
			m.vz *= 1.0 - minf(1.0, dt * 2.5)
		var nx := m.x + m.vx * dt
		var ny := m.y + m.vy * dt
		# Held by wall cells only (a cheap look, not the game's whole test).
		var ix := int(nx)
		var iy := int(ny)
		if ix >= 0 and iy >= 0 and ix < width and iy < height and solid[iy * width + ix] < 0:
			m.x = nx
			m.y = ny
		m.z += m.vz * dt
	motes = kept


## Dust off the boots on a dirt road: the player's at each step, the county's
## as they go.
func _boots() -> void:
	var p = game.player
	var world: LevelData = game.world
	var step := int(p.walk_phase / PI)
	if step != _step:
		_step = step
		if p.air <= 0.0 and p.motion > .35 and Materials.dusty(world, p.x, p.y):
			var a: float = p.angle
			var at := Vector3(p.x - cos(a) * .2, p.y - sin(a) * .2, world.elevation(p.x, p.y) + .05)
			_add("dust", at, Vector3(-cos(a) * .2, -sin(a) * .2, .25), .9, .08, .3)
	var seen := {}
	for e: Enemy in game.enemies:
		if not e.alive or e.z > .05 or absf(e.x - p.x) > NEAR or absf(e.y - p.y) > NEAR:
			continue
		var key := e.get_instance_id()
		seen[key] = true
		var was: Array = _strides.get(key, [e.x, e.y, game.clock + dice.randf_range(0, .3)])
		if game.clock >= float(was[2]):
			var moved := Vector2(e.x - float(was[0]), e.y - float(was[1])).length()
			# The derby boss's car churns up the arena whatever its floor.
			var big := e.brain == "derby_champ"
			var span := .06 if big else .28
			if moved > span * (1.6 if big else .8) and (big or Materials.dusty(world, e.x, e.y)):
				var away := Vector2(float(was[0]) - e.x, float(was[1]) - e.y).normalized()
				var at := Vector3(
					e.x + away.x * e.radius,
					e.y + away.y * e.radius,
					world.elevation(e.x, e.y) + (.15 if big else .05)
				)
				_add(
					"dust",
					at,
					Vector3(away.x * .3, away.y * .3, .3 if big else .2),
					1.6 if big else .9,
					.28 if big else .09,
					.8 if big else .3
				)
			was = [e.x, e.y, game.clock + span]
		_strides[key] = was
	if _strides.size() > seen.size() + 8:
		for key in _strides.keys():
			if not seen.has(key):
				_strides.erase(key)


## The race cars throw up a trail of dirt behind them as they go.
func _race_dust() -> void:
	if game.clock < _trail_next:
		return
	_trail_next = game.clock + .1
	var laps = game.features.get("race_laps")
	if laps == null or laps.cars.is_empty() or game.revisiting:
		return
	var p = game.player
	for car: Array in laps.cars:
		if float(car[1]) < 1.5:
			continue
		var where: Array = laps._at(float(car[0]) - .9)
		var at: Vector2 = where[0]
		if absf(at.x - p.x) > NEAR * 2.0 or absf(at.y - p.y) > NEAR * 2.0:
			continue
		var heading: float = where[1]
		var side := dice.randf_range(-.3, .3)
		var spot := Vector3(
			at.x - sin(heading) * side,
			at.y + cos(heading) * side,
			game.world.elevation(at.x, at.y) + .12
		)
		var v := Vector3(-cos(heading) * .8, -sin(heading) * .8, .35)
		_add("dust", spot, v, dice.randf_range(1.4, 2.0), .3, .9)


## Embers lifting off the fires near enough, and their smoke.
func _embers() -> void:
	var p = game.player
	for fire: Array in _fires:
		var fx: float = fire[0]
		var fy: float = fire[1]
		if absf(fx - p.x) > NEAR or absf(fy - p.y) > NEAR:
			continue
		var row: Array = fire[4]
		var base: float = fire[2]
		var height: float = fire[3]
		if game.clock >= float(fire[5]):
			fire[5] = game.clock + float(row[1]) * dice.randf_range(.6, 1.4)
			var at := Vector3(
				fx + dice.randf_range(-.1, .1),
				fy + dice.randf_range(-.1, .1),
				base + height * float(row[0])
			)
			var v := Vector3(dice.randf_range(-.15, .15), dice.randf_range(-.15, .15), .0)
			v.z = dice.randf_range(.45, .9)
			_add("ember", at, v, dice.randf_range(1.2, 2.2), .035, 0.0)
		if float(row[3]) > 0.0 and game.clock >= float(fire[6]):
			fire[6] = game.clock + float(row[3]) * dice.randf_range(.7, 1.3)
			var top := Vector3(fx, fy, base + height * float(row[2]))
			_add("smoke", top, Vector3(0, 0, .3), dice.randf_range(2.0, 3.0), .1, .22)


func sprites() -> Array:
	var out: Array = []
	var p = game.player
	for m: Mote in motes:
		if (m.x - p.x) * (m.x - p.x) + (m.y - p.y) * (m.y - p.y) < .25:
			continue
		if not game.in_view(m.x, m.y, m.size + .3):
			continue
		var step := mini(3, int(m.age / m.life * 4.0))
		var name := ""
		match m.kind:
			"smoke":
				name = "fx_smoke_%d" % step
			"dust":
				name = "fx_puff_%d" % step
			"ember":
				name = "fx_ember_%d" % (int(m.age * 9.0 + m.size * 400.0) % 2)
		var s := Renderer.Sprite.new(m.x, m.y, name, m.size, m.z)
		s.glow = m.kind == "ember"
		s.translucent = m.kind != "ember"
		out.append(s)
	return out
