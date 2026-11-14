## The arenas of the sheriff, Jerry, Rudy and the foreman: hazards that fight
## both ways (src/bosses/sheriff.gd, jerry.gd, rudy.gd and foreman.gd start
## them; the level says where things stand, `boss_arena` in its JSON, from
## its plan). Here:
##   fire        burning ground where a fuel tank, gas can or drum went up in
##               an arena (and round the saucer, along the bleachers, through
##               the sawdust once a boss is plum desperate): it scorches the
##               player and any hand or boss standing in it.
##   strikes     a ring closing on a spot, then a blast there (shots.cfg kind):
##               the sheriff's saucer strike; it hurts whoever stands in it.
##   lobs        a thing thrown high that bursts where it lands (Jerry's
##               flaming pigskin, Rudy's balloon bombs).
##   rollers     loose things rolling over the floor (tumble.gd): tyres off a
##               drill stack, a fuel drum kicked down the saw floor; each
##               knocks down whoever it meets, boss or player.
##   the carriage  the mill's log carriage running its track on a bell
##               (foreman.gd says when): anyone on the track is hit.
##   horn lanes  the big top's horn stacks firing down their lanes (rudy.gd).
##   lights      an arena's floodlights cut once its boss is plum desperate
##               (back on when it falls), and the lights its hazards give.
## A boss's shot that meets something breakable in its arena breaks it (cover
## that goes both ways: the player's shots break it too). Nothing here is
## saved: what burns or rolls is over in seconds, and what a phase changed
## follows the boss's health. Gameplay numbers come from the level and the
## game's rng; looks use `dice`.
extends GameFeature

const KINDS := ["boss", "jerry", "rudy", "foreman"]
## Fire: how often it bites, how hard (player, a hand or boss), the most patches.
const FIRE_BITE := .5
const FIRE_PLAYER := 6.0
const FIRE_FOE := 16.0
const FIRES_MAX := 26
## A boss's shot meeting something breakable: how hard it strikes it.
const SHOT_BREAK := 30.0
const BOSS_SHOTS := ["plasma", "football", "rudy_horn", "foreman_cut"]
## The carriage: how fast it runs, how wide it is, what it does.
const CARRIAGE_SPEED := 7.5
const CARRIAGE_WARN := 1.4
const CARRIAGE_HALF := .75
const CARRIAGE_PLAYER := 28.0
const CARRIAGE_FOE := 110.0
const ROLL_FEEL_TIRE := [.32, .55, .3, .55]
## A floodlight's pool: how far out in front of its tower, how high, how wide,
## its colour and strength, and how near the player it must stand to count.
const FLOOD_OUT := 3.0
const FLOOD_HIGH := 3.2
const FLOOD_REACH := 8.0
const FLOOD_COLOUR := Color(1, .93, .78)
const FLOOD_STRENGTH := .85
const FLOOD_SEEN := 20.0


class Fire:
	var x := 0.0
	var y := 0.0
	var r := .7
	var born := 0.0
	var until := 0.0
	var spread_at := INF


class Strike:
	var x := 0.0
	var y := 0.0
	var at := 0.0
	var warn := 1.0
	var kind := ""


class Lob:
	var x := 0.0
	var y := 0.0
	var z := 0.0
	var vx := 0.0
	var vy := 0.0
	var vz := 0.0
	var kind := ""
	var image := ""
	var size := .2
	var gravity := 6.0
	var until := 0.0
	## Drifting balloons home in on the player instead of falling.
	var drift := false


class Roller:
	extends Tumble.Body
	var image := ""
	var size := .6
	var feel: Tumble.Feel
	var damage := 0.0
	var foe_damage := 0.0
	var until := 0.0
	## A kicked fuel drum goes up as this blast when it meets someone or stops.
	var blast := ""
	var hit := {}
	var spin := 0.0


## A lane firing from a horn stack: from (x, y) along `angle`, `length` long.
class Lane:
	var x := 0.0
	var y := 0.0
	var angle := 0.0
	var length := 6.0
	var at := 0.0
	var warn := 1.0


var bosses: Array = []
var arena := {}
var fires: Array = []
var strikes: Array = []
var lobs: Array = []
var rollers: Array = []
var lanes: Array = []
## The carriage: where it stands on its track, which way it runs next, when
## its bell rang and when it runs (INF: parked), what it has hit this run.
var carriage_x := 0.0
var carriage_dir := -1.0
var carriage_bell := -INF
var carriage_run := INF
var carriage_hit := {}
var dice := RandomNumberGenerator.new()
## Kinds whose phase three has put the arena's floodlights out.
var dark := {}
## When fire may next bite each player (by slot).
var _burn_next := {}
var _lights: Array = []
var _light_used := 0
## The tyre stacks that have been knocked over (by index in the arena's list).
var _tyres_out := {}
## -1 then the indexes of the breakables in an arena (empty: not looked yet).
var _cover: Array = []


func id() -> String:
	return "boss_arena"


func attach() -> void:
	dice.seed = 7311
	arena = game.level.boss_arena
	for e: Enemy in game.enemies:
		if KINDS.has(e.brain) and BossKit.is_boss(e):
			bosses.append(e)
	if bosses.is_empty() or arena.is_empty():
		return
	var track = spec("foreman").get("track")
	if track is Array:
		# Parked at the east end of its track, by the conveyor.
		carriage_x = float(track[1])
	game.ticked.connect(_tick)
	game.exploded.connect(_exploded)
	game.traced.connect(_shot_traced)


## The level's notes on a kind's arena ({} when it has none).
func spec(kind: String) -> Dictionary:
	var out = arena.get(kind, {})
	return out if out is Dictionary else {}


## Whether (x, y) is inside a kind's arena box (false without one).
func in_box(kind: String, x: float, y: float) -> bool:
	var box = spec(kind).get("box")
	if not (box is Array) or box.size() < 4:
		return false
	return (
		float(box[0]) <= x
		and x <= float(box[2]) + 1.0
		and float(box[1]) <= y
		and y <= float(box[3]) + 1.0
	)


## The kind of the arena (x, y) is in, "" for none.
func arena_at(x: float, y: float) -> String:
	for kind: String in KINDS:
		if in_box(kind, x, y):
			return kind
	return ""


func boss_of(kind: String) -> Enemy:
	for e: Enemy in bosses:
		if e.brain == kind:
			return e
	return null


## A boss of ours whose fight is on: alive, awake, not held back.
func fighting(e: Enemy) -> bool:
	return e != null and e.alive and e.alerted and not e.dormant


# ------------------------------------------------------------------ makers


## Burning ground at (x, y), `r` wide, for `secs`; spreading on its own when
## `spread` (a desperate boss's arena). Too many: the oldest goes.
func fire(x: float, y: float, r: float, secs: float, spread := false) -> void:
	if game.world.blocked(x, y, .1) or game.world.deep_at(x, y):
		return
	for f: Fire in fires:
		if absf(f.x - x) < .35 and absf(f.y - y) < .35:
			f.until = maxf(f.until, game.clock + secs)
			return
	var f := Fire.new()
	f.x = x
	f.y = y
	f.r = r
	f.born = game.clock
	f.until = game.clock + secs
	if spread:
		f.spread_at = game.clock + 1.6
	fires.append(f)
	if fires.size() > FIRES_MAX:
		fires.pop_front()


func strike(x: float, y: float, delay: float, kind: String) -> void:
	var s := Strike.new()
	s.x = x
	s.y = y
	s.at = game.clock + delay
	s.warn = delay
	s.kind = kind
	strikes.append(s)


## Something thrown from (x, y, z) to land at (tx, ty) after `flight` seconds.
func lob(
	x: float,
	y: float,
	z: float,
	tx: float,
	ty: float,
	flight: float,
	kind: String,
	image: String,
	size := .22
) -> void:
	var l := Lob.new()
	l.x = x
	l.y = y
	l.z = z
	l.kind = kind
	l.image = image
	l.size = size
	l.vx = (tx - x) / flight
	l.vy = (ty - y) / flight
	var land: float = game.world.elevation(tx, ty)
	l.vz = (land - z) / flight + .5 * l.gravity * flight
	l.until = game.clock + flight + 2.0
	lobs.append(l)


## A balloon that drifts after the player and bursts on them (or when shot at
## by its own clock running out).
func balloon(x: float, y: float, z: float, kind: String, image: String, secs: float) -> void:
	var l := Lob.new()
	l.x = x
	l.y = y
	l.z = z
	l.kind = kind
	l.image = image
	l.size = .55
	l.drift = true
	l.until = game.clock + secs
	lobs.append(l)


## A thing set rolling from (x, y) at (vx, vy): `feel` [radius, wall, bounce,
## drag]; `blast` makes it go up when it meets someone or stops.
func roll(
	image: String,
	x: float,
	y: float,
	vx: float,
	vy: float,
	size: float,
	feel: Array,
	damage: float,
	foe_damage: float,
	blast := ""
) -> void:
	var r := Roller.new()
	r.image = image
	r.x = x
	r.y = y
	r.z = game.world.elevation(x, y) + float(feel[0])
	r.vx = vx
	r.vy = vy
	r.size = size
	r.feel = Tumble.Feel.new(float(feel[0]), float(feel[1]), float(feel[2]), float(feel[3]))
	r.feel.lift = float(feel[0])
	r.feel.climb = .14
	r.damage = damage
	r.foe_damage = foe_damage
	r.blast = blast
	r.until = game.clock + 6.0
	rollers.append(r)


## A horn stack's lane: warned for `warn` seconds, then it fires.
func lane(x: float, y: float, angle: float, length: float, warn: float) -> void:
	var l := Lane.new()
	l.x = x
	l.y = y
	l.angle = angle
	l.length = length
	l.at = game.clock + warn
	l.warn = warn
	lanes.append(l)


## The carriage's bell: it runs CARRIAGE_WARN seconds later. False when it is
## already on its way.
func ring_carriage() -> bool:
	if carriage_run < INF or not (spec("foreman").get("track") is Array):
		return false
	carriage_bell = game.clock
	carriage_run = game.clock + CARRIAGE_WARN
	carriage_hit = {}
	var track: Array = spec("foreman")["track"]
	game.sound_at("fair_bell", carriage_x, float(track[2]), .9)
	game.sound_at("brake_ratchet", carriage_x, float(track[2]), .8)
	return true


func carriage_moving() -> bool:
	return carriage_run <= game.clock


## Tyres off the drill stack nearest (x, y) within `reach`, rolling away from
## (x, y); each stack goes once.
func knock_tyres(x: float, y: float, reach: float) -> bool:
	var stacks = spec("jerry").get("tires", [])
	for i in stacks.size():
		var s: Array = stacks[i]
		var sx := float(s[0])
		var sy := float(s[1])
		if _tyres_out.has(i) or Vector2(sx - x, sy - y).length() > reach:
			continue
		_tyres_out[i] = true
		var away := atan2(sy - y, sx - x) if Vector2(sx - x, sy - y).length() > .05 else 0.0
		for k in 3:
			var a := away + (k - 1) * .55
			roll(
				"prop_tire",
				sx + cos(a) * .5,
				sy + sin(a) * .5,
				cos(a) * 5.2,
				sin(a) * 5.2,
				.62,
				ROLL_FEEL_TIRE,
				10.0,
				26.0
			)
		game.sound_at("bowling_thud", sx, sy, .9)
		game.burst(sx, sy, game.world.elevation(sx, sy) + .4, "dust", 10, 1.4)
		return true
	return false


# ------------------------------------------------------------------ the tick


func _tick(dt: float) -> void:
	_light_used = 0
	_tick_fires(dt)
	_tick_strikes()
	_tick_lobs(dt)
	_tick_rollers(dt)
	_tick_lanes()
	_tick_carriage(dt)
	_tick_shots()
	_tick_lights()
	for i in range(_light_used, _lights.size()):
		_lights[i][6] = -1.0


func _tick_fires(_dt: float) -> void:
	if fires.is_empty():
		return
	var kept: Array = []
	var born: Array = []
	for f: Fire in fires:
		if game.clock >= f.until:
			continue
		kept.append(f)
		for p: Player in game.players:
			var d := Vector2(p.x - f.x, p.y - f.y).length()
			if d < f.r and p.air < .3 and game.clock >= float(_burn_next.get(p.slot, 0.0)):
				_burn_next[p.slot] = game.clock + FIRE_BITE
				game.damage(FIRE_PLAYER, [f.x, f.y], "FIRE", p)
		for e: Enemy in game.enemies:
			if not e.alive or not e.hostile or e.brain == "bessie":
				continue
			if absf(e.x - f.x) > f.r + e.radius or absf(e.y - f.y) > f.r + e.radius:
				continue
			if Vector2(e.x - f.x, e.y - f.y).length() < f.r + e.radius * .5:
				if game.clock >= float(e.get_meta("burn_next", 0.0)):
					e.set_meta("burn_next", game.clock + FIRE_BITE)
					# Its own: no weak spot, no hit mark on the crosshair.
					e.hurt(FIRE_FOE, game, false, false, e, "fire")
		if game.clock >= f.spread_at and fires.size() + born.size() < FIRES_MAX:
			f.spread_at = game.clock + 2.2
			# The way it spreads follows its place, not dice: the same every time.
			var a := fmod(f.x * 2.7 + f.y * 1.9 + game.clock * .7, TAU)
			born.append([f.x + cos(a) * 1.2, f.y + sin(a) * 1.2, f.until])
	fires = kept
	for row: Array in born:
		fire(float(row[0]), float(row[1]), .7, maxf(3.0, float(row[2]) - game.clock), true)


func _tick_strikes() -> void:
	if strikes.is_empty():
		return
	var kept: Array = []
	for s: Strike in strikes:
		if game.clock < s.at:
			kept.append(s)
			continue
		var z: float = game.world.elevation(s.x, s.y) + .1
		game.explode(GameState.Shot.new(s.x, s.y, z, 0.0, 0.0, 0.0, s.kind, 0.0, true, 0))
		_rubble(s.x, s.y)
	strikes = kept


func _tick_lobs(dt: float) -> void:
	if lobs.is_empty():
		return
	var kept: Array = []
	for l: Lob in lobs:
		if l.drift:
			# A balloon bomb drifts on the nearest player.
			var p: Player = game.player
			if game.players.size() > 1:
				p = Players.nearest(game, l.x, l.y)
				if p == null:
					p = game.local_player
			var to := Vector2(p.x - l.x, p.y - l.y)
			var d := to.length()
			var pace := 1.5 if d > 1.0 else 2.2
			if d > .05:
				var nx := l.x + to.x / d * pace * dt
				var ny := l.y + to.y / d * pace * dt
				if not game.world.blocked(nx, ny, .1):
					l.x = nx
					l.y = ny
			l.z += (game.world.elevation(l.x, l.y) + 1.1 + .12 * sin(game.clock * 3.0) - l.z) * dt
			if d < .55 or game.clock >= l.until:
				_burst_lob(l)
				continue
			kept.append(l)
			continue
		var nx2 := l.x + l.vx * dt
		var ny2 := l.y + l.vy * dt
		l.vz -= l.gravity * dt
		var nz := l.z + l.vz * dt
		var ground: float = game.world.elevation(nx2, ny2)
		if (
			game.world.blocked(nx2, ny2, .06, nz)
			or nz <= ground + .05
			or game.clock >= l.until
			or _lob_strikes(nx2, ny2, nz)
		):
			l.z = maxf(nz, ground + .1)
			_burst_lob(l)
			continue
		l.x = nx2
		l.y = ny2
		l.z = nz
		kept.append(l)
	lobs = kept


func _burst_lob(l: Lob) -> void:
	game.explode(GameState.Shot.new(l.x, l.y, maxf(.1, l.z), 0.0, 0.0, 0.0, l.kind, 0.0, true, 0))
	if l.kind == "pigskin_bomb":
		fire(l.x, l.y, .6, 3.5)


## Whether a lob at (x, y, z) has come down on a player.
func _lob_strikes(x: float, y: float, z: float) -> bool:
	for p: Player in game.players:
		if Vector2(p.x - x, p.y - y).length() < .35 and absf(z - p.eye) < .6:
			return true
	return false


func _tick_rollers(dt: float) -> void:
	if rollers.is_empty():
		return
	var kept: Array = []
	for r: Roller in rollers:
		var hit := Tumble.step(game.world, r, r.feel, dt)
		var speed := Vector2(r.vx, r.vy).length()
		r.spin += speed * dt * 3.0
		var done: bool = (hit & Tumble.RESTED) != 0 or game.clock >= r.until or speed < .25
		if hit & Tumble.WALL:
			game.sound_at("bowling_thud", r.x, r.y, .6)
			if r.blast != "":
				done = true
		for p: Player in game.players:
			# A player's key in `hit` is their slot (an enemy's its instance id).
			if speed <= 1.0 or r.hit.has(p.slot):
				continue
			var d := Vector2(p.x - r.x, p.y - r.y).length()
			if d < r.feel.radius + .3 and p.air < .45:
				r.hit[p.slot] = true
				game.focus(p)
				game.damage(r.damage, [r.x, r.y], "RUN DOWN")
				game.move_actor(p, r.vx * .12, r.vy * .12, GameState.PLAYER_RADIUS)
				game.focus(game.local_player)
				if r.blast != "":
					done = true
		if speed > 1.0:
			for e: Enemy in game.enemies:
				if not e.alive or not e.hostile or r.hit.has(e.get_instance_id()):
					continue
				if Vector2(e.x - r.x, e.y - r.y).length() < r.feel.radius + e.radius:
					r.hit[e.get_instance_id()] = true
					game.move_actor(e, r.vx * .1, r.vy * .1, e.radius)
					e.stun = maxf(e.stun, .5)
					e.hurt(r.foe_damage, game, false, false, e, "rolled")
					game.sound_at("body_thud", e.x, e.y, .9)
					if r.blast != "":
						done = true
		if done:
			if r.blast != "":
				game.explode(
					GameState.Shot.new(r.x, r.y, r.z + .3, 0.0, 0.0, 0.0, r.blast, 0.0, true, 0)
				)
				fire(r.x, r.y, .9, 6.0)
			continue
		kept.append(r)
	rollers = kept


func _tick_lanes() -> void:
	if lanes.is_empty():
		return
	var kept: Array = []
	for l: Lane in lanes:
		if game.clock < l.at:
			kept.append(l)
			continue
		var floor_z: float = game.world.elevation(l.x, l.y)
		for off: float in [-.06, .06]:
			game.launch(
				l.x + cos(l.angle) * .5,
				l.y + sin(l.angle) * .5,
				floor_z + 1.05,
				l.angle + off,
				8.0,
				"rudy_horn",
				0.0,
				true,
				9,
				l.length / 8.0
			)
		game.sound_at("rudy_horn", l.x, l.y, 1.0)
		# The blast down the lane knocks Rudy about as well as the player.
		var rudy := boss_of("rudy")
		if fighting(rudy) and _on_lane(rudy.x, rudy.y, l, rudy.radius + .35):
			rudy.stun = maxf(rudy.stun, .6)
			rudy.hurt(34.0, game, false, false, rudy, "horn")
			game.message("RUDY'S OWN HORNS GOT HIM!", 2.0)
	lanes = kept


func _on_lane(x: float, y: float, l: Lane, width: float) -> bool:
	var dx := x - l.x
	var dy := y - l.y
	var along := dx * cos(l.angle) + dy * sin(l.angle)
	return along > .3 and along < l.length and absf(-dx * sin(l.angle) + dy * cos(l.angle)) < width


func _tick_carriage(dt: float) -> void:
	var track = spec("foreman").get("track")
	if not (track is Array) or carriage_run > game.clock:
		return
	var x0 := float(track[0])
	var x1 := float(track[1])
	var y := float(track[2])
	carriage_x += carriage_dir * CARRIAGE_SPEED * dt
	var ended := carriage_x <= x0 or carriage_x >= x1
	carriage_x = clampf(carriage_x, x0, x1)
	for p: Player in game.players:
		if (
			not carriage_hit.has(p.slot)
			and absf(p.x - carriage_x) < CARRIAGE_HALF + .3
			and absf(p.y - y) < .95
			and p.air < .5
		):
			carriage_hit[p.slot] = true
			game.focus(p)
			game.damage(CARRIAGE_PLAYER, [carriage_x, y], "LOG CARRIAGE")
			var side := 1.0 if p.y >= y else -1.0
			game.move_actor(p, carriage_dir * .5, side * .9, GameState.PLAYER_RADIUS)
			if game.acting_local():
				game.shake = minf(1.0, game.shake + .5)
			game.focus(game.local_player)
	for e: Enemy in game.enemies:
		var key := e.get_instance_id()
		if not e.alive or not e.hostile or carriage_hit.has(key):
			continue
		if absf(e.x - carriage_x) < CARRIAGE_HALF + e.radius and absf(e.y - y) < .7 + e.radius:
			carriage_hit[key] = true
			var side2 := 1.0 if e.y >= y else -1.0
			game.move_actor(e, carriage_dir * .4, side2 * .8, e.radius)
			e.stun = maxf(e.stun, .9)
			e.hurt(CARRIAGE_FOE, game, false, false, e, "carriage")
			game.sound_at("body_thud", e.x, e.y, 1.0)
			game.burst(e.x, e.y, game.world.stand(e) + 1.0, "chips", 12, 2.0)
			if e.brain == "foreman":
				game.message("THE FOREMAN TOOK HIS OWN CARRIAGE!", 2.2)
	var pieces = game.features.get("breakables")
	if pieces != null:
		for dy: float in [-.45, 0.0, .45]:
			var i: int = pieces.touch(
				carriage_x, y + dy, game.world.elevation(carriage_x, y) + .4, .5
			)
			if i >= 0:
				pieces.strike(i, 200.0, carriage_dir, 0.0)
	if ended:
		carriage_run = INF
		carriage_dir = -carriage_dir
		game.sound_at("metal_down", carriage_x, y, .9)
		game.shake = minf(1.0, game.shake + .2)


## A boss's shot that meets something breakable in its arena breaks it.
func _tick_shots() -> void:
	var pieces = game.features.get("breakables")
	if pieces == null or game.shots.is_empty():
		return
	if _cover.is_empty():
		# The breakables standing in an arena, found once (indexes into pieces).
		_cover.append(-1)
		for i in pieces.pieces.size():
			if arena_at(pieces.pieces[i].x, pieces.pieces[i].y) != "":
				_cover.append(i)
	var spent: Array = []
	for shot in game.shots:
		if not shot.enemy or not BOSS_SHOTS.has(String(shot.kind)):
			continue
		var i := _cover_at(pieces, shot.x, shot.y, shot.z)
		if i >= 0:
			pieces.strike(i, maxf(SHOT_BREAK, float(shot.damage) * 2.0), shot.vx, shot.vy)
			spent.append(shot)
	for shot in spent:
		game.finish_shot(shot)
		game.shots.erase(shot)


## The whole piece of arena cover a shot at (x, y, z) is in, or -1 (the test
## breakables.gd touch() makes, over the arena's own pieces only).
func _cover_at(pieces, x: float, y: float, z: float) -> int:
	for k in range(1, _cover.size()):
		var i: int = _cover[k]
		var p = pieces.pieces[i]
		if p.broken or absf(p.x - x) > .14 + p.radius or absf(p.y - y) > .14 + p.radius:
			continue
		var foot: float = game.world.stand(p) + p.z
		if (
			Vector2(p.x - x, p.y - y).length() < .14 + p.radius * .7
			and z > foot - .05
			and z < foot + p.height + .05
		):
			return i
	return -1


## Something went up: a fuel tank, gas can or drum in an arena leaves the
## ground burning (and sets the sawdust off, and knocks the tyre stacks over).
func _exploded(x: float, y: float, _z: float, energy: bool) -> void:
	var kind := arena_at(x, y)
	if kind == "" or energy:
		return
	knock_tyres(x, y, 2.2)
	if not _fuel_at(x, y):
		return
	var e := boss_of(kind)
	var spread := e != null and e.alive and e.boss_phase >= 3
	fire(x, y, .95, 7.0, spread)
	for k in 3:
		var a := k * TAU / 3.0 + fmod(x * 1.7 + y * 2.3, TAU)
		fire(x + cos(a) * 1.0, y + sin(a) * 1.0, .65, 5.0, spread)
	for s in spec(kind).get("sawdust", []):
		var sx := float(s[0])
		var sy := float(s[1])
		if Vector2(sx - x, sy - y).length() < 3.0:
			fire(sx, sy, 1.25, 12.0, spread)
			game.message("THE SAWDUST WENT UP!", 2.0)


## A player's shot ended at `end`: a balloon bomb or a kicked drum on its way
## is shot down (burst where it is).
func _shot_traced(end: Vector3, _struck: String) -> void:
	if lobs.is_empty() and rollers.is_empty():
		return
	var p = game.player
	var from := Vector3(p.x, p.y, p.eye)
	for l: Lob in lobs.duplicate():
		if l.drift and _near_line(from, end, Vector3(l.x, l.y, l.z), .45):
			lobs.erase(l)
			_burst_lob(l)
	for r: Roller in rollers.duplicate():
		if r.blast != "" and _near_line(from, end, Vector3(r.x, r.y, r.z), .5):
			rollers.erase(r)
			r.until = 0.0
			game.explode(
				GameState.Shot.new(r.x, r.y, r.z + .3, 0.0, 0.0, 0.0, r.blast, 0.0, false, 0)
			)
			fire(r.x, r.y, .9, 6.0)


func _near_line(a: Vector3, b: Vector3, q: Vector3, reach: float) -> bool:
	var ab := b - a
	var t := clampf((q - a).dot(ab) / maxf(.0001, ab.length_squared()), 0.0, 1.0)
	return (a + ab * t).distance_to(q) < reach


## Whether a fuel drum, tank, barrel or gas can just went up at (x, y).
func _fuel_at(x: float, y: float) -> bool:
	var pieces = game.features.get("breakables")
	if pieces != null:
		for p in pieces.pieces:
			if (
				p.broken
				and absf(p.x - x) < .8
				and absf(p.y - y) < .8
				and ["fuel", "gas_can", "nitro", "tnt"].has(String(p.spec.get("blast", "")))
			):
				return true
	for point in game.level.fuel_drums:
		if absf(float(point[0]) - x) < .6 and absf(float(point[1]) - y) < .6:
			return true
	return false


func _rubble(x: float, y: float) -> void:
	var z: float = game.world.elevation(x, y)
	for _i in 6:
		var a := dice.randf() * TAU
		var v := dice.randf_range(.4, 1.8)
		game.specks.append(
			GameState.Speck.new(
				x, y, z + .1, cos(a) * v, sin(a) * v, dice.randf_range(1.0, 2.4), .5, "dust"
			)
		)


# ------------------------------------------------------------------ lights


## The arenas' lights this frame, in game.trigger_lights (kept and reused, so
## the list never grows): fire, the floodlights a desperate boss cut, the
## sweep and pulse a boss's phase three brings.
func _tick_lights() -> void:
	for e: Enemy in bosses:
		var kind := e.brain
		var want: bool = e.alive and e.boss_phase >= 3 and not e.dormant
		if want != dark.has(kind):
			_floods(kind, not want)
			if want:
				dark[kind] = true
			else:
				dark.erase(kind)
	var p = game.player
	_flood_lights(p)
	var near: Array = []
	for f: Fire in fires:
		var d := absf(f.x - p.x) + absf(f.y - p.y)
		if d < 16.0:
			near.append([d, f])
	near.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for i in mini(4, near.size()):
		var f: Fire = near[i][1]
		var flick := .85 + .15 * sin(game.clock * 17.0 + f.x * 3.1)
		_light(f.x, f.y, game.world.elevation(f.x, f.y) + .6, 3.2, Color(1, .55, .2), flick)
	for s: Strike in strikes:
		var t := clampf(1.0 - (s.at - game.clock) / maxf(.05, s.warn), 0.0, 1.0)
		_light(s.x, s.y, game.world.elevation(s.x, s.y) + 1.5, 2.6, Color(.45, 1, .5), .3 + t)


## The floodlights that are on throw their light down into the arena: a pool
## out in front of each tower (FLOOD_* numbers), the nearest ones only.
func _flood_lights(p) -> void:
	for kind: String in KINDS:
		# The arena's own lights (its notes' `lights`: x, y, height, reach,
		# colour, strength), on whatever the phase.
		for l in spec(kind).get("lights", []):
			if absf(float(l[0]) - p.x) < FLOOD_SEEN and absf(float(l[1]) - p.y) < FLOOD_SEEN:
				var tint: Array = l[4]
				_light(
					float(l[0]),
					float(l[1]),
					game.world.elevation(float(l[0]), float(l[1])) + float(l[2]),
					float(l[3]),
					Color(float(tint[0]), float(tint[1]), float(tint[2])),
					float(l[5])
				)
		if dark.has(kind):
			continue
		var notes := spec(kind)
		var box = notes.get("box")
		if not (box is Array) or notes.get("floods", []).is_empty():
			continue
		var mid := Vector2(
			(float(box[0]) + float(box[2]) + 1.0) * .5, (float(box[1]) + float(box[3]) + 1.0) * .5
		)
		for s in notes["floods"]:
			var at := Vector2(float(s[0]), float(s[1]))
			if absf(at.x - p.x) > FLOOD_SEEN or absf(at.y - p.y) > FLOOD_SEEN:
				continue
			var pool := at + (mid - at).normalized() * FLOOD_OUT
			_light(
				pool.x,
				pool.y,
				game.world.elevation(pool.x, pool.y) + FLOOD_HIGH,
				FLOOD_REACH,
				FLOOD_COLOUR,
				FLOOD_STRENGTH
			)


func _light(x: float, y: float, z: float, radius: float, color: Color, strength: float) -> void:
	var row: Array
	if _light_used < _lights.size():
		row = _lights[_light_used]
	else:
		row = [0.0, 0.0, 0.0, 1.0, color, 0.0, -1.0]
		_lights.append(row)
		game.trigger_lights.append(row)
	row[0] = x
	row[1] = y
	row[2] = z
	row[3] = radius
	row[4] = color
	row[5] = strength
	row[6] = game.clock + .25
	_light_used += 1


## Add a light for this frame from a boss's moves (a pulse, a sweep).
func light(x: float, y: float, z: float, radius: float, color: Color, strength: float) -> void:
	_light(x, y, z, radius, color, strength)


## Turn a kind's floodlights off or on: their glow, and the lamp list the
## view keeps (it lists again).
func _floods(kind: String, on: bool) -> void:
	var spots = spec(kind).get("floods", [])
	if spots.is_empty():
		return
	for board: LevelData.Billboard in game.world.billboards:
		if board.image != "town_floodlight_tower":
			continue
		for s in spots:
			if absf(board.x - float(s[0])) < .3 and absf(board.y - float(s[1])) < .3:
				board.glow = on
				for spr: Renderer.Sprite in game.fixed_sprites:
					if spr.image == board.image and absf(spr.x - board.x) < .01:
						if absf(spr.y - board.y) < .01:
							spr.glow = on
	game.lamps_of = Vector2i(-1, -1)
	if not on:
		game.sound_at("metal_down", game.player.x, game.player.y, .5)


# ------------------------------------------------------------------ the picture


func sprites() -> Array:
	var out: Array = []
	for f: Fire in fires:
		if not game.in_view(f.x, f.y, f.r + .5):
			continue
		var floor_z: float = game.world.elevation(f.x, f.y)
		var fade := clampf((f.until - game.clock) / 1.2, .3, 1.0)
		var grow := clampf((game.clock - f.born) / .4, .4, 1.0)
		var tall := (f.r * 1.5 + .25) * fade * grow
		var n := 2 if f.r > .8 else 1
		for k in n:
			var a := k * PI + f.x
			var spr := Renderer.Sprite.new(
				f.x + cos(a) * f.r * .3 * (n - 1),
				f.y + sin(a) * f.r * .3 * (n - 1),
				"fx_fire_%d" % ((int(game.clock * 10.0) + k * 2 + int(f.x * 3.0)) % 4),
				tall,
				floor_z
			)
			spr.glow = true
			out.append(spr)
	for s: Strike in strikes:
		var left: float = s.at - game.clock
		if left < .3 and game.in_view(s.x, s.y, 1.0):
			# The bolt coming down.
			var floor2: float = game.world.elevation(s.x, s.y)
			var col := Renderer.Sprite.new(s.x, s.y, "fx_beam_column", 3.2, floor2 + left * 8.0)
			col.glow = true
			col.translucent = true
			out.append(col)
	for l: Lob in lobs:
		if game.in_view(l.x, l.y, .6):
			var spr2 := Renderer.Sprite.new(l.x, l.y, l.image, l.size, l.z - l.size * .5)
			spr2.glow = not l.drift
			out.append(spr2)
			if l.kind == "pigskin_bomb":
				var lit := Renderer.Sprite.new(
					l.x, l.y, "fx_fire_%d" % (int(game.clock * 12.0) % 4), .3, l.z
				)
				lit.glow = true
				out.append(lit)
	for r: Roller in rollers:
		if game.in_view(r.x, r.y, r.size):
			var spr3 := Renderer.Sprite.new(r.x, r.y, r.image, r.size, r.z - r.feel.radius)
			spr3.flip = int(r.spin) % 2 == 0
			out.append(spr3)
	out.append_array(_carriage_sprites())
	return out


func _carriage_sprites() -> Array:
	var track = spec("foreman").get("track")
	if not (track is Array):
		return []
	var y := float(track[2])
	if not game.in_view(carriage_x, y, 2.5):
		return []
	var out: Array = []
	var floor_z: float = game.world.elevation(carriage_x, y)
	var cart := Renderer.Sprite.new(carriage_x, y, "town_headrig", 1.6, floor_z)
	cart.flip = carriage_dir > 0.0
	out.append(cart)
	if carriage_moving():
		for k in 2:
			var spark := Renderer.Sprite.new(
				carriage_x - carriage_dir * (.9 + k * .3),
				y + (k - .5) * .5,
				"fx_sparks_%d" % ((int(game.clock * 14.0) + k) % 3),
				.4,
				floor_z + .15
			)
			spark.glow = true
			out.append(spark)
	return out


func ground_marks() -> Array:
	var out: Array = []
	var w: LevelData = game.world
	for f: Fire in fires:
		out.append(
			Renderer.GroundMark.new(
				f.x, f.y, w.elevation(f.x, f.y) + .004, f.x, f.r * 1.1, f.r * 1.1, "mark_scorch_0"
			)
		)
	for s: Strike in strikes:
		var t := clampf(1.0 - (s.at - game.clock) / maxf(.05, s.warn), 0.0, 1.0)
		var r := lerpf(1.9, 1.0, t)
		for k in 12:
			var a := k * TAU / 12.0 + t * 1.2
			var x := s.x + cos(a) * r
			var y := s.y + sin(a) * r
			if not w.blocked(x, y, .05):
				out.append(
					Renderer.GroundMark.new(
						x, y, w.elevation(x, y) + .005, a, .2, .2, "mark_warning"
					)
				)
		var fill := .2 + .9 * t
		out.append(
			Renderer.GroundMark.new(
				s.x, s.y, w.elevation(s.x, s.y) + .006, 0.0, fill, fill, "mark_slam"
			)
		)
	for l: Lane in lanes:
		var half := l.length * .5
		out.append(
			Renderer.GroundMark.new(
				l.x + cos(l.angle) * half,
				l.y + sin(l.angle) * half,
				w.elevation(l.x, l.y) + .004,
				l.angle,
				half,
				.45,
				"mark_lane"
			)
		)
	var track = spec("foreman").get("track")
	if track is Array and carriage_run < INF and game.clock < carriage_run:
		# The bell rang: the track it will run, lit up end to end.
		var x0 := float(track[0])
		var x1 := float(track[1])
		var y2 := float(track[2])
		if int(game.clock * 6.0) % 2 == 0:
			out.append(
				Renderer.GroundMark.new(
					(x0 + x1) * .5,
					y2,
					w.elevation(x0, y2) + .004,
					0.0,
					(x1 - x0) * .5,
					.9,
					"mark_lane"
				)
			)
	return out
