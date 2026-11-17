## The boss arenas come apart as the fights go on (bosses.cfg [arena_wreck]):
## each boss has steps that fire as its health falls past their `at` (a share
## of its whole: the phase lines .5 and .2 among them), some again every few
## of its attacks after (`every`). A step is one of:
##   topple   a standing prop (a searchlight, a pylon, the scoreboard, a
##            copper vat, a lantern post, a pod, the floodlight tower) shakes
##            with its lane painted on the ground, then goes over along it:
##            whoever is in the lane is hurt (the boss and his hands too), and
##            it lies there after as cover (furniture in the way of bodies and
##            shots, LevelData.add_volume)
##   fall     a hanging lamp lets go: a ring closes on the spot under it, it
##            drops, hurts whoever is under it and lies there as cover
##   scatter  the props near the boss (the derby bowl's crushed stacks and
##            wrecks) are flung away from him, tumble and land somewhere else,
##            hurting what they strike; their old bases leave the way and they
##            lie where they land as cover
##   wave     the boss throws a wave across the water: a ring rolls out from
##            him that shoves whoever it meets out of the way and hurts a little
##   blowout  the windows round a spot blow out (features/wall_breaks.gd)
## The props are the level's own (a billboard the step names by picture and
## place, hidden while this draws it moving and lying: LevelData.Billboard
## .hidden; a lamp is a game.props sprite taken away), drawn as their 3D
## models turned by View.Sprite.turn (track).
##
## Play: the arithmetic is the game's own (no dice), the state is carried
## (SIM_FEATURES) and what it did to the level is a fact (FACT_FEATURES:
## restore() puts the volumes, the hidden boards and the lamps taken right on
## a client or a load). The boss checkpoint's retry calls reset(): the arena
## as the level made it. BOSS ARENAS WRECK off (game.boss_wrecks): nothing.
class_name ArenaWreckFeature
extends GameFeature

const WallBreaks := preload("res://src/features/wall_breaks.gd")

static var ARENAS: Dictionary = BossData.get_value("arena_wreck", "arenas")
## How long a topple takes to go over once it goes, and a fall's gravity.
static var TOPPLE_TIME: float = BossData.get_value("arena_wreck", "topple_time")
static var GRAVITY: float = BossData.get_value("arena_wreck", "gravity")
## How wide a toppled piece's lane is (half), and how high it lies as cover.
static var LANE: float = BossData.get_value("arena_wreck", "lane")
static var LYING: float = BossData.get_value("arena_wreck", "lying")
## A wave: how fast it rolls, how far, how thick its front is.
static var WAVE_SPEED: float = BossData.get_value("arena_wreck", "wave_speed")
static var WAVE_REACH: float = BossData.get_value("arena_wreck", "wave_reach")
static var WAVE_FRONT: float = BossData.get_value("arena_wreck", "wave_front")

## How far a fallen lamp lies tipped over (radians; looks only).
const LAMP_LIE := 1.15
const WARN := 0
const GOING := 1
const DOWN := 2

## Every step of the bosses in the level whose arenas wreck (none: the
## feature sleeps; Hickston has two), and the boss of each.
var steps: Array = []
var foes: Array = []
## Per step: -1 not yet; else the boss's attack count when it last fired.
var fired: Array = []
## Each piece moving or lying: {"step", "kind" (topple, fall, fly), "image",
## "x", "y", "z" (its foot), "dir", "length", "height", "stage", "t0",
## "board" (its place in world.billboards, -1 none), "lamp" ([x, y] of the
## game.props lamp taken, [] none), "vx", "vy", "vz", "turn", "hurt",
## "radius", "struck" (the boss struck already)}.
var pieces: Array = []
## Waves rolling out: [x, y, born, struck players (slots)].
var waves: Array = []
## What it did to the level: volumes put in the way and the level's own
## volumes taken out of it (as plain arrays).
var added: Array = []
var dropped: Array = []
## Looks: the lamps taken (to put back on reset), the next water ring.
var _taken: Array = []
var _ring_next := 0.0
var _fly_feel: Tumble.Feel


func id() -> String:
	return "arena_wreck"


func attach() -> void:
	_fly_feel = Tumble.Feel.new(.4, .3, .25, 4.0)
	_fly_feel.hard = 2.0
	_fly_feel.climb = .15
	for e: Enemy in game.enemies:
		if ARENAS.has(e.kind) and not foes.has(e):
			var own: Array = ARENAS[e.kind]
			for step: Dictionary in own:
				steps.append(step)
				foes.append(e)
				fired.append(-1)
	if steps.is_empty():
		return
	tick_with(_tick)


func save() -> Dictionary:
	# Nothing wrecked (or no arena here): nothing to put back, so a round's
	# start (modes/round_cover.gd) and saves see a level as built.
	var any := not (pieces.is_empty() and added.is_empty() and dropped.is_empty())
	for at: Variant in fired:
		var step: int = at
		any = any or step != -1
	if not any:
		return {}
	return {
		"fired": fired.duplicate(),
		"pieces": pieces.duplicate(true),
		"added": added.duplicate(true),
		"dropped": dropped.duplicate(true),
	}


## Back from a save, or a host's facts on a client: the pieces as they were,
## and the level as they left it (only what is not so already).
func restore(state: Dictionary) -> void:
	if steps.is_empty() or state.is_empty():
		return
	var was: Array = state.get("fired", [])
	if was.size() == fired.size():
		fired = was.duplicate()
	var kept: Array = state.get("pieces", [])
	pieces = kept.duplicate(true)
	for p: Dictionary in pieces:
		_take(p)
	var gone: Array = state.get("dropped", [])
	for row: Array in gone:
		var v := PackedFloat32Array(row)
		if game.world.collision_volumes.has(v):
			game.world.drop_volume(v)
		if not _has(dropped, row):
			dropped.append(row)
	var put: Array = state.get("added", [])
	for row: Array in put:
		var v := PackedFloat32Array(row)
		if not game.world.collision_volumes.has(v):
			add_volume(game.world, v)
		if not _has(added, row):
			added.append(row)


## The arena as the level made it (the boss checkpoint's retry).
func reset() -> void:
	for p: Dictionary in pieces:
		var board := _board(p)
		if board != null and board.hidden:
			board.hidden = false
			game.world.boards_version += 1
	for row: Array in added:
		game.world.drop_volume(PackedFloat32Array(row))
	for row: Array in dropped:
		var v := PackedFloat32Array(row)
		if not game.world.collision_volumes.has(v):
			add_volume(game.world, v)
	for s: View.Sprite in _taken:
		if not game.props.has(s):
			game.props.append(s)
	_taken.clear()
	pieces.clear()
	waves.clear()
	added.clear()
	dropped.clear()
	for i in fired.size():
		fired[i] = -1


static func _num(d: Dictionary, key: String, default: float) -> float:
	var v: float = d.get(key, default)
	return v


static func _i(p: Dictionary, key: String) -> int:
	var v: int = p[key]
	return v


static func _f(p: Dictionary, key: String) -> float:
	var v: float = p[key]
	return v


func _has(rows: Array, row: Array) -> bool:
	for r: Array in rows:
		if r == row:
			return true
	return false


func _tick(dt: float) -> void:
	if steps.is_empty():
		return
	if game.boss_wrecks:
		for i in steps.size():
			var boss: Enemy = foes[i]
			if boss == null or not boss.alive or boss.max_hp <= 0.0:
				continue
			var step: Dictionary = steps[i]
			var at: float = step["at"]
			if boss.hp / boss.max_hp > at:
				continue
			var last: int = fired[i]
			var every: int = step.get("every", 0)
			if last < 0 or (every > 0 and boss.attacks - last >= every):
				fired[i] = boss.attacks
				_fire(i, step)
	for p: Dictionary in pieces:
		_move(p, dt)
	if not waves.is_empty():
		_waves()


# ------------------------------------------------------------------ steps


func _fire(i: int, step: Dictionary) -> void:
	var what := str(step["do"])
	var call := str(step.get("call", ""))
	if call != "":
		game.message(call, 2.4)
	match what:
		"topple", "fall":
			for spot: Array in step["spots"]:
				_start(i, step, spot)
		"scatter":
			_scatter(i, step)
		"wave":
			var boss: Enemy = foes[i]
			waves.append([boss.x, boss.y, game.clock, []])
			game.sound_at("wade_splash", boss.x, boss.y, 1.0)
			game.burst(boss.x, boss.y, game.world.elevation(boss.x, boss.y) + .1, "splash", 18, 2.6)
		"blowout":
			_blowout(step)


## A piece of step `step` at `spot` ([x, y] and, toppling, its way over).
func _start(i: int, step: Dictionary, spot: Array) -> void:
	var what := str(step["do"])
	var image := str(step["image"])
	var x: float = spot[0]
	var y: float = spot[1]
	var p := {
		"step": i,
		"kind": what,
		"image": image,
		"x": x,
		"y": y,
		"z": game.world.elevation(x, y),
		"dir": 0.0,
		"length": 1.0,
		"height": 1.0,
		"stage": WARN,
		"t0": game.clock,
		"board": -1,
		"lamp": [],
		"vx": 0.0,
		"vy": 0.0,
		"vz": 0.0,
		"turn": 0.0,
		"hurt": _num(step, "hurt", 15.0),
		"radius": _num(step, "radius", .9),
		"struck": false,
	}
	if what == "topple":
		var dir: float = spot[2]
		p["dir"] = dir
		var board := _find_board(image, x, y)
		if board == null:
			return
		p["board"] = game.world.billboards.find(board)
		p["height"] = board.height
		p["length"] = board.height * _num(step, "reach", .95)
		p["z"] = game.world.elevation(board.x, board.y) + board.z
		p["x"] = board.x
		p["y"] = board.y
	else:
		var lamp := _find_lamp(image, x, y)
		if lamp == null:
			return
		p["lamp"] = [lamp.x, lamp.y]
		p["height"] = lamp.height
		p["z"] = lamp.z
		p["x"] = lamp.x
		p["y"] = lamp.y
	_take(p)
	pieces.append(p)


## The level lets go of what piece `p` now draws (a board hidden, a lamp taken
## away, its base out of the way): only what is not so already.
func _take(p: Dictionary) -> void:
	var board := _board(p)
	if board != null and not board.hidden:
		board.hidden = true
		if board.glow:
			board.glow = false
			if "lamp_boards" in game:
				game.lamp_boards.erase(board)
		game.world.boards_version += 1
		var base := base_at(game.world, board.x, board.y)
		if not base.is_empty():
			var row := Array(base)
			game.world.drop_volume(base)
			if not _has(dropped, row):
				dropped.append(row)
	var lamp: Array = p["lamp"]
	if lamp.size() == 2:
		var lx: float = lamp[0]
		var ly: float = lamp[1]
		for s: View.Sprite in game.props:
			if s.image == str(p["image"]) and absf(s.x - lx) < .05 and absf(s.y - ly) < .05:
				game.props.erase(s)
				_taken.append(s)
				break


## The boss whose step set piece `p` going.
func _foe(p: Dictionary) -> Enemy:
	var i := _i(p, "step")
	var e: Enemy = foes[i] if i >= 0 and i < foes.size() else null
	return e


func _board(p: Dictionary) -> LevelData.Billboard:
	var i: int = p["board"]
	if i < 0 or i >= game.world.billboards.size():
		return null
	var board: LevelData.Billboard = game.world.billboards[i]
	return board


func _find_board(image: String, x: float, y: float) -> LevelData.Billboard:
	for board: LevelData.Billboard in game.world.billboards:
		if board.image == image and absf(board.x - x) < .6 and absf(board.y - y) < .6:
			return board
	return null


func _find_lamp(image: String, x: float, y: float) -> View.Sprite:
	for s: View.Sprite in game.props:
		if s.image == image and absf(s.x - x) < .6 and absf(s.y - y) < .6:
			return s
	return null


## The base a prop stands on (the box under it the level put in the way, no
## more than a few cells across), taken out of the way when it goes over.
static func base_at(world: LevelData, x: float, y: float) -> PackedFloat32Array:
	for fixture: Variant in world.near_fixtures.get(Vector2i(int(x), int(y)), []):
		var f: PackedFloat32Array = fixture
		if (
			f[0] <= x + .05
			and x - .05 <= f[2]
			and f[1] <= y + .05
			and y - .05 <= f[3]
			and maxf(f[2] - f[0], f[3] - f[1]) <= 3.0
		):
			return f
	return PackedFloat32Array()


# ------------------------------------------------------------------ moving


func _move(p: Dictionary, dt: float) -> void:
	var stage: int = p["stage"]
	if stage == DOWN:
		return
	var step: Dictionary = steps[_i(p, "step")]
	var warn: float = step.get("warn", 1.2)
	var t0: float = p["t0"]
	var age := game.clock - t0
	var kind := str(p["kind"])
	if stage == WARN:
		if age >= warn:
			p["stage"] = GOING
			p["t0"] = game.clock
			var x: float = p["x"]
			var y: float = p["y"]
			game.sound_at("scenery_scrap", x, y, 1.0)
		return
	match kind:
		"topple":
			if age >= TOPPLE_TIME:
				_landed(p)
		"fall":
			var x: float = p["x"]
			var y: float = p["y"]
			var z0: float = p["z"]
			var fallen := .5 * GRAVITY * age * age
			var floor_z := game.world.floor_under(x, y, z0)
			if z0 - fallen <= floor_z:
				p["z"] = floor_z
				_landed(p)
		"fly":
			var hit := Tumble.step(game.world, p, _fly_feel, dt)
			var struck: bool = p["struck"]
			if not struck:
				_strike_near(p, .8)
			if hit & Tumble.RESTED or age > 4.0:
				var x: float = p["x"]
				var y: float = p["y"]
				var z: float = p["z"]
				p["z"] = Tumble.floor_at(game.world, x, y, z, _fly_feel.radius)
				_landed(p)


## It came down: the hurt, the noise and dust, and it lies there as cover.
func _landed(p: Dictionary) -> void:
	p["stage"] = DOWN
	var kind := str(p["kind"])
	var x: float = p["x"]
	var y: float = p["y"]
	var z: float = p["z"]
	var dir: float = p["dir"]
	var length: float = p["length"]
	var cue := "metal_down"
	if kind == "topple":
		_strike_lane(p)
		var along := 0.0
		while along < length - .2:
			_burst_dust(x + cos(dir) * (along + .3), y + sin(dir) * (along + .3), z, 4)
			along += 1.2
		game.shake = minf(1.0, game.shake + clampf(length * .06, .15, .5))
		_cover_lane(p)
	elif kind == "fall":
		_strike_near(p, _f(p, "radius"))
		_burst_dust(x, y, z, 10)
		game.burst(x, y, z + .2, "glass", 8, 2.0)
		game.shake = minf(1.0, game.shake + .2)
		cue = "glass_break"
		_cover_box(x, y, z, .35, .35)
	else:
		_burst_dust(x, y, z, 6)
		_cover_box(x, y, z, .45, _f(p, "height") * .6)
	game.sound_at(cue, x, y, 1.0)


## Whoever is in a toppled piece's lane.
func _strike_lane(p: Dictionary) -> void:
	var x: float = p["x"]
	var y: float = p["y"]
	var dir: float = p["dir"]
	var length: float = p["length"]
	var hurt: float = p["hurt"]
	for q: Player in game.players:
		if q.health > 0 and _in_lane(q.x, q.y, x, y, dir, length, LANE + .2):
			game.damage(
				hurt, [x + cos(dir) * length * .5, y + sin(dir) * length * .5], "FLATTENED", q
			)
	for e: Enemy in game.enemies:
		if e.alive and e.hostile and _in_lane(e.x, e.y, x, y, dir, length, LANE + e.radius):
			_hurt_enemy(e, hurt, _foe(p))


func _in_lane(
	px: float, py: float, x: float, y: float, dir: float, length: float, width: float
) -> bool:
	var dx := px - x
	var dy := py - y
	var along := dx * cos(dir) + dy * sin(dir)
	return along > .2 and along < length + .2 and absf(-dx * sin(dir) + dy * cos(dir)) < width


## Whoever is within `reach` of a piece coming down or flying (once).
func _strike_near(p: Dictionary, reach: float) -> void:
	var x: float = p["x"]
	var y: float = p["y"]
	var z: float = p["z"]
	var hurt: float = p["hurt"]
	var flying := str(p["kind"]) == "fly"
	for q: Player in game.players:
		if q.health <= 0 or Vector2(q.x - x, q.y - y).length() > reach + .2:
			continue
		if flying and absf(z - (game.world.stand(q) + .5)) > 1.0:
			continue
		game.damage(hurt, [x, y], "FLATTENED", q)
		p["struck"] = true
	for e: Enemy in game.enemies:
		if e.alive and e.hostile and Vector2(e.x - x, e.y - y).length() < reach + e.radius:
			if flying and e == _foe(p):
				continue
			_hurt_enemy(e, hurt, _foe(p))
			if flying:
				p["struck"] = true


## The boss and his hands are flattened too (the boss by twice the hurt: a
## lure under a falling tower pays).
func _hurt_enemy(e: Enemy, hurt: float, boss: Enemy) -> void:
	var by := boss if boss != null else e
	e.hurt(hurt * (2.0 if e == boss else 1.5), game, false, false, by, "wreck")
	if e == boss and e.alive:
		e.stun = maxf(e.stun, .5)


func _burst_dust(x: float, y: float, z: float, count: int) -> void:
	game.burst(x, y, z + .1, "dust", count, 1.6)


## A toppled piece lies along its lane: a row of low boxes in the way.
func _cover_lane(p: Dictionary) -> void:
	var x: float = p["x"]
	var y: float = p["y"]
	var dir: float = p["dir"]
	var length: float = p["length"]
	var step: Dictionary = steps[_i(p, "step")]
	var tall: float = step.get("lying", LYING)
	var foot: float = p["z"]
	var along := .45
	while along < length:
		var bx := x + cos(dir) * along
		var by := y + sin(dir) * along
		_cover_box(bx, by, game.world.floor_under(bx, by, foot + .4), .3, tall)
		along += .55


## A box of cover `half` each way and `tall` over the floor at `floor_z`;
## none where a wall is, nor over anybody standing there (it would shut them
## in).
func _cover_box(x: float, y: float, floor_z: float, half: float, tall: float) -> void:
	if game.world.blocked(x, y, .05, floor_z + .3):
		return
	for q: Player in game.players:
		if _overlaps(q.x, q.y, GameState.PLAYER_RADIUS + .02, x, y, half):
			return
	for e: Enemy in game.enemies:
		if e.alive and _overlaps(e.x, e.y, e.radius + .02, x, y, half):
			return
	var tile := float(maxi(0, game.world.tile_id("tin")))
	var row: Array = [
		snappedf(x - half, .01),
		snappedf(y - half, .01),
		snappedf(x + half, .01),
		snappedf(y + half, .01),
		snappedf(floor_z + tall, .01),
		tile,
		tile,
		snappedf(floor_z, .01),
	]
	# The level's own floats (a volume read from a save matches it).
	row = Array(PackedFloat32Array(row))
	if _has(added, row):
		return
	added.append(row)
	add_volume(game.world, PackedFloat32Array(row))


## Put a piece of furniture in the way of `world` as the level's own are
## ([x0, y0, x1, y1, top, face tile, top tile, bottom]; LevelData.drop_volume
## takes one away): listed, indexed by the cells round it.
static func add_volume(world: LevelData, volume: PackedFloat32Array) -> void:
	world.collision_volumes.append(volume)
	var r := world.index_radius
	var w := world.width
	var h := world.height
	for yy in range(floori(volume[1] - r), floori(volume[3] + r) + 1):
		for xx in range(floori(volume[0] - r), floori(volume[2] + r) + 1):
			var key := Vector2i(xx, yy)
			if not world.near_fixtures.has(key):
				world.near_fixtures[key] = []
			var near: Array = world.near_fixtures[key]
			near.append(volume)
			if xx >= 0 and yy >= 0 and xx < w and yy < h:
				if world.index_cells.size() == w * h:
					world.index_cells[yy * w + xx] = 1
				if world.clear_cells.size() == w * h:
					world.clear_cells[yy * w + xx] = 0


## Whether a body of radius r at (bx, by) overlaps the box `half` each way
## round (x, y).
static func _overlaps(bx: float, by: float, r: float, x: float, y: float, half: float) -> bool:
	var nx := clampf(bx, x - half, x + half)
	var ny := clampf(by, y - half, y + half)
	return Vector2(bx - nx, by - ny).length() < r


## The props named, near the boss, flung away from him.
func _scatter(i: int, step: Dictionary) -> void:
	var boss: Enemy = foes[i]
	var reach: float = step.get("reach", 6.0)
	var power: float = step.get("power", 4.0)
	var images: Array = step["images"]
	for k in game.world.billboards.size():
		var board: LevelData.Billboard = game.world.billboards[k]
		if board.hidden or not images.has(board.image):
			continue
		var dx := board.x - boss.x
		var dy := board.y - boss.y
		var d := sqrt(dx * dx + dy * dy)
		if d > reach:
			continue
		var away := atan2(dy, dx) if d > .05 else boss.angle
		var push := power * (1.0 - d / (reach + 1.0))
		var p := {
			"step": i,
			"kind": "fly",
			"image": board.image,
			"x": board.x,
			"y": board.y,
			"z": game.world.elevation(board.x, board.y) + board.z,
			"dir": away,
			"length": 1.0,
			"height": board.height,
			"stage": GOING,
			"t0": game.clock,
			"board": k,
			"lamp": [],
			"vx": cos(away) * push,
			"vy": sin(away) * push,
			"vz": push * .55,
			"turn": away,
			"hurt": _num(step, "hurt", 10.0),
			"radius": .7,
			"struck": false,
		}
		_take(p)
		pieces.append(p)


func _blowout(step: Dictionary) -> void:
	var breaks: WallBreaks = game.features.get("wall_breaks")
	if breaks == null:
		return
	var near: Array = step["near"]
	var nx: float = near[0]
	var ny: float = near[1]
	var reach: float = step.get("reach", 10.0)
	for face: WallBreaks.WindowFace in breaks.windows:
		if face.broken:
			continue
		var mid := face.middle()
		if mid.distance_to(Vector2(nx, ny)) > reach:
			continue
		var front := mid + face.normal() * .3
		breaks.blast(front.x, front.y, (face.low + face.high) * .5, .5, 100.0, false)


# ------------------------------------------------------------------ waves


func _waves() -> void:
	var kept: Array = []
	for w: Array in waves:
		var wx: float = w[0]
		var wy: float = w[1]
		var born: float = w[2]
		var r := (game.clock - born) * WAVE_SPEED
		if r > WAVE_REACH:
			continue
		kept.append(w)
		var struck: Array = w[3]
		var step := _wave_step()
		var push: float = step.get("push", 1.2)
		var hurt: float = step.get("hurt", 6.0)
		for q: Player in game.players:
			if q.health <= 0 or struck.has(q.slot) or q.air > .3:
				continue
			var dx := q.x - wx
			var dy := q.y - wy
			var d := sqrt(dx * dx + dy * dy)
			if absf(d - r) > WAVE_FRONT or d < .1:
				continue
			struck.append(q.slot)
			game.damage(hurt, [wx, wy], "SWAMPED", q)
			game.move_actor(q, dx / d * push, dy / d * push, GameState.PLAYER_RADIUS)
			game.sound_at("wade_splash", q.x, q.y, 1.0)
	waves = kept


func _wave_step() -> Dictionary:
	for step: Dictionary in steps:
		if str(step["do"]) == "wave":
			return step
	return {}


# ------------------------------------------------------------------ looks


func sprites() -> Array:
	var out: Array = []
	for k in pieces.size():
		var p: Dictionary = pieces[k]
		var x: float = p["x"]
		var y: float = p["y"]
		var length: float = p["length"]
		if not game.in_view(x, y, length + 2.0):
			continue
		var height: float = p["height"]
		var z: float = p["z"]
		if str(p["kind"]) == "fall" and _i(p, "stage") == GOING:
			# On its way down (play lowers it only once it lands).
			var t0: float = p["t0"]
			var age := game.clock - t0
			z = maxf(game.world.floor_under(x, y, z), z - .5 * GRAVITY * age * age)
		var s := View.Sprite.new(x, y, str(p["image"]), height, z)
		s.track = "wreck%d" % k
		var board := _board(p)
		if board != null:
			s.plane = board.plane
		s.turn = _turn_of(p)
		s.glow = str(p["image"]) == "prop_lamp" and _i(p, "stage") == WARN
		out.append(s)
	for w: Array in waves:
		out.append_array(_wave_looks(w))
	return out


## How piece `p` is turned now (map axes, z up).
func _turn_of(p: Dictionary) -> Basis:
	var kind := str(p["kind"])
	var stage: int = p["stage"]
	var t0: float = p["t0"]
	var age := game.clock - t0
	var dir: float = p["dir"]
	var axis := Vector3(-sin(dir), cos(dir), 0.0)
	match kind:
		"topple":
			var over := 0.0
			if stage == WARN:
				var step: Dictionary = steps[_i(p, "step")]
				var warn: float = step.get("warn", 1.2)
				over = .05 * sin(game.clock * 31.0) * clampf(age / maxf(.1, warn), 0.0, 1.0)
			elif stage == GOING:
				var k := clampf(age / TOPPLE_TIME, 0.0, 1.0)
				over = PI * .5 * k * k
			else:
				over = PI * .5 - .04
			return Basis(axis, over)
		"fly":
			var heading: float = p["turn"]
			if stage == DOWN:
				return Basis(Vector3(0, 0, 1), heading + 1.1)
			return Basis(axis, age * 5.0) * Basis(Vector3(0, 0, 1), heading)
	if stage == WARN:
		return Basis(Vector3(1, 0, 0), .08 * sin(game.clock * 17.0))
	if kind == "fall":
		# A lamp swings over as it drops and lies tipped on its side, its tube
		# showing (the 3D view's shop lamp; a picture stands as it was).
		var k := 1.0 if stage == DOWN else clampf(age * 2.5, 0.0, 1.0)
		return Basis(Vector3(1, 0, 0), LAMP_LIE * k)
	return Basis.IDENTITY


func _wave_looks(w: Array) -> Array:
	var out: Array = []
	var wx: float = w[0]
	var wy: float = w[1]
	var born: float = w[2]
	var r := (game.clock - born) * WAVE_SPEED
	var water: GameFeature = game.features.get("water")
	var ring_now := game.clock >= _ring_next
	if ring_now:
		_ring_next = game.clock + .12
	var dots := int(clampf(r * 3.0, 8.0, 40.0))
	for k in dots:
		var a := k * TAU / dots
		var x := wx + cos(a) * r
		var y := wy + sin(a) * r
		if not game.in_view(x, y, .6):
			continue
		var crest := View.Sprite.new(x, y, "fx_splash", .4, game.world.elevation(x, y))
		crest.translucent = true
		out.append(crest)
		if ring_now and water != null and k % 3 == 0 and water.has_method("ring"):
			water.call("ring", x, y, .6)
	return out


func ground_marks() -> Array:
	var out: Array = []
	for p: Dictionary in pieces:
		if _i(p, "stage") != WARN:
			continue
		var x: float = p["x"]
		var y: float = p["y"]
		var reach: float = p["length"]
		if not game.in_view(x, y, reach + 2.0):
			continue
		var z: float = game.world.elevation(x, y) + .004
		match str(p["kind"]):
			"topple":
				var dir: float = p["dir"]
				var length: float = p["length"]
				out.append(
					View.GroundMark.new(
						x + cos(dir) * length * .5,
						y + sin(dir) * length * .5,
						z,
						dir,
						length * .5,
						LANE,
						"mark_lane"
					)
				)
			"fall":
				var step: Dictionary = steps[_i(p, "step")]
				var warn: float = step.get("warn", 1.2)
				var t0: float = p["t0"]
				var t := clampf((game.clock - t0) / maxf(.1, warn), 0.0, 1.0)
				var radius: float = p["radius"]
				var r := lerpf(radius + .7, radius * .6, t)
				for k in 10:
					var a := k * TAU / 10.0 + t * 1.3
					var mx := x + cos(a) * r
					var my := y + sin(a) * r
					out.append(View.GroundMark.new(mx, my, z, 0.0, .15, .15, "mark_warning"))
				out.append(
					View.GroundMark.new(
						x, y, z, 0.0, radius * .6 * t + .1, radius * .6 * t + .1, "mark_slam"
					)
				)
	return out
