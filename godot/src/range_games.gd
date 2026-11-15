## The firing range's midway games, on the games row south of the armory
## (src/range_layout.gd says where; their shapes are range_games_shape.gd's,
## which the 3D view draws them from):
##
## - HORSESHOES: ten shoes a game pitched at the stake from the box. A shoe
##   flies as it was pitched (where the pitcher faces, how high they look),
##   spinning; it lands dead in the pit and slides a little; the stake knocks
##   it off when its bar meets it and holds it when it drops round it. Resting
##   round the stake is a ringer (3), against it a leaner (2), within a
##   shoe's width a point.
## - THE DUNK TANK: a county hand on the plank over the water and a bullseye
##   hanging off the tank's arm. Any shot on the bullseye drops the plank and
##   him in with a splash; he climbs back up jawing. The lever starts a round:
##   the bullseye swings and the dunks are counted.
## - SKEE-BALL (range_skeeball.gd).
## - KNOCK 'EM DOWN: ten milk bottles racked on a table and three softballs
##   thrown at them. The bottles are rigid bodies like the bowling pins
##   (range_pin_physics.gd, a bottle's own shape) and the softball a free
##   ball in the same solve; a bottle down on the table is a point, off it
##   two, the table cleared ten more.
##
## Played by the range feature (features/firing_range.gd), which hands it its
## stations, the shots and the ticks. Part of the range's play (carried in
## snapshots): plain numbers in arrays and dictionaries, no dice at all.
extends RefCounted

const L := preload("res://src/range_layout.gd")
const S := preload("res://src/range_games_shape.gd")
const P := preload("res://src/range_pin_physics.gd")
const Targets := preload("res://src/range_targets.gd")
const Skee := preload("res://src/range_skeeball.gd")
const GRAVITY := 10.7
## A bottle's numbers kept between ticks (as a bowling pin's).
const KEYS := ["x", "y", "z", "qx", "qy", "qz", "qw", "vx", "vy", "vz", "wx", "wy", "wz", "rest"]

static var SHOES: int = RangeTuning.get_value("horseshoes", "shoes", 10)
static var SHOE_SPEED: float = RangeTuning.get_value("horseshoes", "speed", 10.4)
static var SHOE_LOFT: float = RangeTuning.get_value("horseshoes", "loft", .466)
static var SHOE_SPIN: float = RangeTuning.get_value("horseshoes", "spin", 7.0)
static var SHOE_KEEP: float = RangeTuning.get_value("horseshoes", "keep", .45)
static var SHOE_DRAG: float = RangeTuning.get_value("horseshoes", "drag", 14.0)
static var SHOE_KNOCK: float = RangeTuning.get_value("horseshoes", "knock", .3)
static var SHOE_POINT: float = RangeTuning.get_value("horseshoes", "point", .17)
static var SHOE_WOBBLE: float = RangeTuning.get_value("horseshoes", "wobble", .03)
static var SHOE_AIM_WOBBLE: float = RangeTuning.get_value("horseshoes", "aim_wobble", .015)
static var BALL_WOBBLE: float = RangeTuning.get_value("bottles", "wobble", .03)
static var BALL_AIM_WOBBLE: float = RangeTuning.get_value("bottles", "aim_wobble", .015)
static var DUNK_ROUND: float = RangeTuning.get_value("dunk", "round", 30.0)
static var DUNK_SWING: float = RangeTuning.get_value("dunk", "swing", .5)
static var DUNK_RATE: float = RangeTuning.get_value("dunk", "rate", 1.7)
static var DUNK_UNDER: float = RangeTuning.get_value("dunk", "under", 2.2)
static var DUNK_CLIMB: float = RangeTuning.get_value("dunk", "climb", 1.0)
static var BOTTLE_BALLS: int = RangeTuning.get_value("bottles", "balls", 3)
static var BALL_SPEED: float = RangeTuning.get_value("bottles", "speed", 10.5)
static var BALL_LOFT: float = RangeTuning.get_value("bottles", "loft", .1)
static var BALL_MASS: float = RangeTuning.get_value("bottles", "ball_mass", .8)
static var BOTTLE_STEPS: int = RangeTuning.get_value("bottles", "steps", 6)
static var BOTTLE_LONGEST: float = RangeTuning.get_value("bottles", "longest", 6.0)

## What the hand on the plank says, in turn: as a round starts, and as he
## climbs back up.
const JAW := [
	"YOU COULDN'T HIT A BARN FROM THE INSIDE!",
	"MY MAW THROWS BETTER AND SHE'S DEAD!",
	"THAT ALL YOU GOT, CITY BOY?",
	"WATER'S WARM. COME ON IN!",
	"I SEEN SCARECROWS SHOOT STRAIGHTER!",
	"LUCKY. PURE DUMB LUCK.",
]

var skee := Skee.new()
## Horseshoes: the shoes on the court ({x, y, z (above the court), vx, vy,
## vz, yaw (the heel's way), wy (its spin), state "fly"/"slide"/"rest",
## ringed, lean (radians it leans on the stake), knocked}), the game.
var shoes: Array = []
var shoes_left := SHOES
var shoe_score := 0
var ringers := 0
var shoe_last := ""
var shoe_best := 0
## The dunk tank: the round, the hand ("up", "falling", "under", "climbing")
## and since when, the bullseye's swing.
var dunk_on := false
var dunk_clock := 0.0
var dunks := 0
var dunk_hits := 0
var dunk_best := 0
var dunk_last := ""
var dunk_state := "up"
var dunk_since := 0.0
var dunk_splashed := false
var swing := 0.0
var jaw_next := 0
## Knock 'em down: the bottles (a bowling pin's numbers each, and gone: ""
## on the table, "off" below it), the softball ({} none; x, y, z above the
## floor, its speeds and since when), the round.
var bottles: Array = []
var ball := {}
var balls_left := BOTTLE_BALLS
var bottle_score := 0
var bottle_last := ""
var bottle_best := 0
var bottle_settle := -1.0
var bottle_shot := false
## Games finished since the range last looked ([game, score]).
var finished: Array = []


func _init() -> void:
	rack_bottles()


func tick(game: Game, dt: float) -> void:
	_tick_shoes(game, dt)
	_tick_dunk(game, dt)
	skee.tick(game, dt)
	_tick_bottles(game, dt)
	if not skee.finished.is_empty():
		finished.append_array(skee.finished)
		skee.finished.clear()


## Where a throw leaves `p`'s hand and how: [x, y, z above `ground`, the
## way (radians), how far up (radians)].
static func _release(p: Player, ground: float, loft: float, ahead := .3, drop := .25) -> Array:
	var a := p.view_angle()
	var up := atan(p.pitch / View.base_focal + loft)
	return [p.x + cos(a) * ahead, p.y + sin(a) * ahead, p.eye - ground - drop, a, up]


# ------------------------------------------------------------------ horseshoes


func _court(game: Game) -> float:
	return game.world.elevation(L.STAKE.x, L.STAKE.y)


## Pitch a shoe from where `p` stands. Returns what to tell them.
func pitch(game: Game, p: Player) -> String:
	for shoe: Dictionary in shoes:
		if str(shoe["state"]) != "rest":
			return "WAIT FOR IT TO LAND."
	if shoes_left <= 0:
		shoes_left = SHOES
		shoe_score = 0
		ringers = 0
		shoes.clear()
	if (SHOES - shoes_left) % 2 == 0:
		# A new inning: the last two shoes are picked up.
		shoes.clear()
	var out := _release(p, _court(game), SHOE_LOFT)
	# No hand is a machine: the pitch is a little off, by the game's dice.
	var a: float = out[3]
	a += game.rng.uniform(-SHOE_AIM_WOBBLE, SHOE_AIM_WOBBLE)
	var up: float = out[4]
	var speed := SHOE_SPEED * (1.0 + game.rng.uniform(-SHOE_WOBBLE, SHOE_WOBBLE))
	(
		shoes
		. append(
			{
				"x": out[0],
				"y": out[1],
				"z": out[2],
				"vx": cos(a) * cos(up) * speed,
				"vy": sin(a) * cos(up) * speed,
				"vz": sin(up) * speed,
				"yaw": a + PI,
				"wy": SHOE_SPIN * (1.0 + game.rng.uniform(-.2, .2)),
				"state": "fly",
				"ringed": false,
				"lean": 0.0,
				"knocked": false,
			}
		)
	)
	shoes_left -= 1
	game.sound.play("football_throw", .6)
	return ""


func _tick_shoes(game: Game, dt: float) -> void:
	var h := dt / 4.0
	for shoe: Dictionary in shoes:
		if str(shoe["state"]) == "rest":
			continue
		for _k in 4:
			_shoe_step(game, shoe, h)
			if str(shoe["state"]) == "rest":
				_call(game, shoe)
				break


func _shoe_step(game: Game, shoe: Dictionary, h: float) -> void:
	var state := str(shoe["state"])
	var x: float = shoe["x"]
	var y: float = shoe["y"]
	var z: float = shoe["z"]
	var vx: float = shoe["vx"]
	var vy: float = shoe["vy"]
	var vz: float = shoe["vz"]
	var yaw: float = shoe["yaw"]
	var wy: float = shoe["wy"]
	var rest_z := S.SHOE_BAR * .65
	if state == "fly":
		vz -= GRAVITY * h
		x += vx * h
		y += vy * h
		z += vz * h
		yaw += wy * h
		if z <= rest_z:
			# Dead in the pit: the clay takes its fall and most of its run.
			z = rest_z
			vz = 0.0
			vx *= SHOE_KEEP
			vy *= SHOE_KEEP
			state = "slide"
			game.sound_at("impact_dirt", x, y, .45)
			game.burst(x, y, _court(game) + .02, "dust", 4, .6)
	elif state == "slide":
		var speed := Vector2(vx, vy).length()
		var slow := SHOE_DRAG * h
		if speed <= slow:
			vx = 0.0
			vy = 0.0
			state = "rest"
		else:
			vx *= (speed - slow) / speed
			vy *= (speed - slow) / speed
		x += vx * h
		y += vy * h
		yaw += wy * h
		wy *= exp(-6.0 * h)
	# The backboard behind the pit.
	if y > L.SHOE_BACK - S.SHOE_R:
		y = L.SHOE_BACK - S.SHOE_R
		vy = -absf(vy) * .3
		game.sound_at("impact_wood", x, y, .4)
	var v := Vector2(vx, vy)
	var c := Vector2(x, y)
	if z <= S.STAKE_TOP + S.SHOE_BAR:
		var hit := _stake(shoe, c, v, yaw)
		c = hit[0]
		v = hit[1]
		var struck: float = hit[2]
		if struck > .6:
			game.sound_at("tailgate_clang", L.STAKE.x, L.STAKE.y, minf(1.0, .3 + struck * .12))
			wy += struck * 2.0
	shoe["x"] = c.x
	shoe["y"] = c.y
	shoe["z"] = z
	shoe["vx"] = v.x
	shoe["vy"] = v.y
	shoe["vz"] = vz
	shoe["yaw"] = yaw
	shoe["wy"] = wy
	shoe["state"] = state


## The stake against a shoe at `c` going `v`, heel along `yaw`: [where it is
## after, its way after, how hard it struck (cells a second, 0 none)]. Inside
## the ring the stake holds it (ringed); against the bar it knocks it off;
## through the mouth it lets it by.
func _stake(shoe: Dictionary, c: Vector2, v: Vector2, yaw: float) -> Array:
	var d := L.STAKE - c
	var dist := d.length()
	var reach := S.SHOE_R + S.SHOE_BAR + S.STAKE_R
	if dist > reach:
		return [c, v, 0.0]
	var inner := S.SHOE_R - S.SHOE_BAR - S.STAKE_R
	var n := -d / maxf(dist, 1e-4)
	var ringed: bool = shoe["ringed"]
	if ringed or dist < inner:
		shoe["ringed"] = true
		if dist <= inner:
			return [c, v, 0.0]
		# Held round the stake: it rattles against the inside of the bar.
		c = L.STAKE - d / dist * inner
		var away := v.dot(n)
		if away > 0.0:
			v -= n * away * 1.2
		return [c, v, maxf(0.0, away)]
	var off := wrapf(atan2(d.y, d.x) - yaw, -PI, PI)
	if absf(off) > S.SHOE_ARC or dist < S.SHOE_R:
		return [c, v, 0.0]
	# The bar meets the stake from outside: knocked off it.
	shoe["knocked"] = true
	c = L.STAKE + n * reach
	var closing := v.dot(n)
	if closing >= 0.0:
		return [c, v, 0.0]
	v -= n * closing * (1.0 + SHOE_KNOCK)
	v *= .8
	return [c, v, -closing]


## A shoe come to rest: what it scores.
func _call(game: Game, shoe: Dictionary) -> void:
	var c := Vector2(_f(shoe, "x"), _f(shoe, "y"))
	var yaw: float = shoe["yaw"]
	var d := L.STAKE - c
	var dist := d.length()
	var off := wrapf(atan2(d.y, d.x) - yaw, -PI, PI)
	var points := 0
	var ringed: bool = shoe["ringed"]
	if ringed and dist < S.SHOE_R:
		points = 3
		ringers += 1
		shoe_last = "RINGER!"
		game.callout = "RINGER!"
		game.callout_until = game.clock + 1.4
		game.sound_at("tailgate_clang", L.STAKE.x, L.STAKE.y, .9)
	elif absf(off) <= S.SHOE_ARC and absf(dist - S.SHOE_R) < S.SHOE_BAR + S.STAKE_R + .03:
		points = 2
		shoe["lean"] = .85
		shoe_last = "LEANER! 2"
		game.callout = "LEANER!"
		game.callout_until = game.clock + 1.2
	elif dist - S.SHOE_R < SHOE_POINT:
		points = 1
		shoe_last = "CLOSE ONE: A POINT"
	else:
		var along := (L.STAKE - L.SHOE_BOX).normalized().dot(c - L.STAKE)
		shoe_last = "SHORT" if along < -.3 else "LONG" if along > .3 else "WIDE"
	shoe_score += points
	if shoes_left <= 0:
		shoe_best = maxi(shoe_best, shoe_score)
		finished.append(["horseshoes", shoe_score])
		shoe_last = "GAME: %d, %d RINGERS. BEST %d" % [shoe_score, ringers, shoe_best]
		game.message("HORSESHOES: %d POINTS, %d RINGERS." % [shoe_score, ringers], 3.0)


## How far a pitch now would carry, in cells along the ground (the card's
## guide: where the pitcher looks).
static func carry(p: Player, ground: float) -> float:
	var out := _release(p, ground, SHOE_LOFT)
	var z0: float = out[2]
	var up: float = out[4]
	var vz := sin(up) * SHOE_SPEED
	var t := (vz + sqrt(vz * vz + 2.0 * GRAVITY * maxf(0.0, z0))) / GRAVITY
	return cos(up) * SHOE_SPEED * t


# ------------------------------------------------------------------ dunk tank


func start_dunk(game: Game) -> void:
	dunk_on = true
	dunk_clock = 0.0
	dunks = 0
	dunk_hits = 0
	dunk_last = ""
	_jaw(game)
	game.sound.play("menu_accept")


func _jaw(game: Game) -> void:
	game.message('THE HAND ON THE PLANK: "%s"' % JAW[jaw_next % JAW.size()], 2.6)
	jaw_next += 1


## The bullseye's middle now (z above the floor).
func target(game: Game) -> Vector3:
	var pivot := Vector3(
		L.TANK_AT.x + S.TARGET_AT.x, L.TANK_AT.y + S.TARGET_AT.y, S.TARGET_AT.z + .3
	)
	var floor_z := game.world.elevation(L.TANK_AT.x, L.TANK_AT.y)
	return pivot + Vector3(sin(swing) * .3, 0.0, floor_z - cos(swing) * .3)


func _tick_dunk(game: Game, dt: float) -> void:
	if dunk_on:
		dunk_clock += dt
		swing = DUNK_SWING * sin(dunk_clock * DUNK_RATE) * minf(1.0, dunk_clock)
		if dunk_clock >= DUNK_ROUND:
			dunk_on = false
			dunk_best = maxi(dunk_best, dunks)
			finished.append(["dunk", dunks])
			var aim := roundi(dunks * 100.0 / maxf(1.0, dunk_hits)) if dunk_hits > 0 else 0
			dunk_last = "%d DUNKS. BEST %d" % [dunks, dunk_best]
			game.message("TIME! %d DUNKS (%d%% OF HITS)." % [dunks, aim], 3.0)
			game.sound.play("range_gallery_buzzer")
	else:
		swing *= exp(-dt * 1.5)
	var since := game.clock - dunk_since
	if dunk_state == "falling":
		if not dunk_splashed and since > .32:
			dunk_splashed = true
			var floor_z := game.world.elevation(L.TANK_AT.x, L.TANK_AT.y)
			var at := hand_at()
			game.burst(at.x, at.y, floor_z + S.WATER + .05, "splash", 18, 1.8)
			game.sound_at("wade_splash", at.x, at.y, 1.0)
		if since > .6:
			dunk_state = "under"
			dunk_since = game.clock
	elif dunk_state == "under" and since > DUNK_UNDER:
		dunk_state = "climbing"
		dunk_since = game.clock
		game.sound_at("step_water_0", L.TANK_AT.x, L.TANK_AT.y, .6)
	elif dunk_state == "climbing" and since > DUNK_CLIMB:
		dunk_state = "up"
		dunk_since = game.clock
		if game.clock > 1.0:
			_jaw(game)


## Where the hand stands on the plank (the map).
static func hand_at() -> Vector2:
	return L.TANK_AT + Vector2(0.0, S.TANK.y - .1 - S.SEAT_DEEP * .5)


## How high his boots are above the floor, and the plank's drop (radians).
func hand_pose(game: Game) -> Vector2:
	var since := game.clock - dunk_since
	var up := S.SEAT_Z + .03
	var under := S.WATER - .72
	match dunk_state:
		"falling":
			var t := minf(since, .6)
			return Vector2(maxf(under, up - .5 * GRAVITY * t * t), minf(1.45, since * 12.0))
		"under":
			return Vector2(under + sin(since * 3.0) * .02, 1.45)
		"climbing":
			var k := clampf(since / DUNK_CLIMB, 0.0, 1.0)
			return Vector2(lerpf(under, up, k * k * (3.0 - 2.0 * k)), 1.45 * (1.0 - k))
	return Vector2(up, 0.0)


## A shot from s to e: on the bullseye it dunks him. True when it struck.
func dunk_shot(game: Game, s: Vector3, e: Vector3) -> bool:
	var t := target(game)
	var hit := Targets.crossing(s, e, t.x, t.y, t.z, S.TARGET_R, S.TARGET_R)
	if hit.x < 0.0:
		return false
	_bullseye(game)
	return true


func _bullseye(game: Game) -> void:
	var t := target(game)
	if dunk_on:
		dunk_hits += 1
	if dunk_state != "up":
		game.sound_at("ricochet_tin", t.x, t.y, .5)
		return
	game.sound_at("range_gallery_ding", t.x, t.y, .8)
	game.sound_at("tailgate_clang", L.TANK_AT.x, L.TANK_AT.y, .6)
	dunk_state = "falling"
	dunk_since = game.clock
	dunk_splashed = false
	if dunk_on:
		dunks += 1
		dunk_last = "DUNKED! %d" % dunks
	else:
		dunk_last = "DUNKED HIM. PULL THE LEVER FOR A ROUND."
	game.callout = "DUNKED!"
	game.callout_until = game.clock + 1.0


# ------------------------------------------------------------------ bottles


## Ten bottles racked on the table, head bottle toward the thrower.
func rack_bottles() -> void:
	bottles.clear()
	var gap := .105
	var head := L.TABLE_AT + Vector2(0.0, -.14)
	var n := 0
	for row in 4:
		for k in row + 1:
			var spot := head + Vector2((k - row * .5) * gap, row * gap * .87)
			n += 1
			var bottle := {"n": n, "gone": "", "awake": 0.0}
			for key: String in KEYS:
				bottle[key] = 0.0
			bottle["x"] = spot.x
			bottle["y"] = spot.y
			bottle["z"] = S.TABLE_TOP + S.BOTTLE_COM
			bottle["qw"] = 1.0
			bottles.append(bottle)
	balls_left = BOTTLE_BALLS
	bottle_score = 0
	bottle_settle = -1.0
	bottle_shot = false


## Throw a softball from where `p` stands. Returns what to tell them.
func throw_ball(game: Game, p: Player) -> String:
	if not ball.is_empty():
		return "WAIT FOR THE BALL."
	if balls_left <= 0:
		rack_bottles()
		return "RACKED UP. THREE BALLS."
	var out := _release(p, game.world.elevation(L.TABLE_AT.x, L.TABLE_AT.y), BALL_LOFT, .3, .12)
	var a: float = out[3]
	a += game.rng.uniform(-BALL_AIM_WOBBLE, BALL_AIM_WOBBLE)
	var up: float = out[4]
	var speed := BALL_SPEED * (1.0 + game.rng.uniform(-BALL_WOBBLE, BALL_WOBBLE))
	ball = {
		"x": out[0],
		"y": out[1],
		"z": out[2],
		"vx": cos(a) * cos(up) * speed,
		"vy": sin(a) * cos(up) * speed,
		"vz": sin(up) * speed,
		"t": 0.0,
	}
	balls_left -= 1
	bottle_settle = -1.0
	game.sound.play("football_throw", .6)
	return ""


static func _on_table(x: float, y: float) -> bool:
	var d := Vector2(x, y) - L.TABLE_AT
	return absf(d.x) <= S.TABLE_HALF.x and absf(d.y) <= S.TABLE_HALF.y


static func _table_floor(x: float, y: float) -> float:
	return S.TABLE_TOP if _on_table(x, y) else 0.0


static func _ground_floor(_x: float, _y: float) -> float:
	return 0.0


## A number of a dictionary, typed.
static func _f(d: Dictionary, key: String) -> float:
	var v: float = d[key]
	return v


static func _v3(d: Dictionary, a: String, b: String, c: String) -> Vector3:
	return Vector3(_f(d, a), _f(d, b), _f(d, c))


static func _body(bottle: Dictionary) -> P.Body:
	var b := P.Body.new()
	b.shape = S.BOTTLE
	b.com = S.BOTTLE_COM
	b.foot_r = S.BOTTLE_FOOT
	var inertia: Array = S.BOTTLE_I
	b.i_across = inertia[0]
	b.i_along = inertia[1]
	b.p = _v3(bottle, "x", "y", "z")
	b.q = Quaternion(_f(bottle, "qx"), _f(bottle, "qy"), _f(bottle, "qz"), _f(bottle, "qw"))
	b.v = _v3(bottle, "vx", "vy", "vz")
	b.w = _v3(bottle, "wx", "wy", "wz")
	b.rest = bottle["rest"]
	var awake: float = bottle["awake"]
	b.awake = awake > 0.0
	return b


static func _store(b: P.Body, bottle: Dictionary) -> void:
	var values := [
		b.p.x,
		b.p.y,
		b.p.z,
		b.q.x,
		b.q.y,
		b.q.z,
		b.q.w,
		b.v.x,
		b.v.y,
		b.v.z,
		b.w.x,
		b.w.y,
		b.w.z,
		b.rest
	]
	for i in KEYS.size():
		bottle[KEYS[i]] = values[i]
	bottle["awake"] = 1.0 if b.awake else 0.0


static func bottle_down(bottle: Dictionary) -> bool:
	if str(bottle["gone"]) != "":
		return true
	var qx: float = bottle["qx"]
	var qy: float = bottle["qy"]
	return acos(clampf(1.0 - 2.0 * (qx * qx + qy * qy), -1.0, 1.0)) > .62


func _tick_bottles(game: Game, dt: float) -> void:
	var moving := not ball.is_empty()
	for bottle: Dictionary in bottles:
		var awake: float = bottle["awake"]
		moving = moving or awake > 0.0
	if not moving:
		_score_bottles(game)
		return
	var high: Array = []
	var high_of: Array = []
	var low: Array = []
	var low_of: Array = []
	for bottle: Dictionary in bottles:
		var b := _body(bottle)
		if str(bottle["gone"]) == "":
			high.append(b)
			high_of.append(bottle)
		else:
			low.append(b)
			low_of.append(bottle)
	var thrown: P.Body = null
	if not ball.is_empty():
		thrown = P.Body.new()
		thrown.ball = true
		thrown.free = true
		thrown.radius = S.SOFTBALL_R
		thrown.inv_m = 1.0 / BALL_MASS
		thrown.p = _v3(ball, "x", "y", "z")
		thrown.v = _v3(ball, "vx", "vy", "vz")
	var ball_high := thrown != null and thrown.p.z > S.TABLE_TOP - .1
	var top := _solver(_table_floor)
	var bottom := _solver(_ground_floor)
	var h := dt / BOTTLE_STEPS
	for _k in BOTTLE_STEPS:
		top.step(high, thrown if ball_high else null, h)
		bottom.step(low, thrown if not ball_high else null, h)
	for i in high.size():
		var b: P.Body = high[i]
		var bottle: Dictionary = high_of[i]
		_store(b, bottle)
		if b.p.z < S.TABLE_TOP - .1:
			# Off the edge: below the table it falls among the ground's.
			bottle["gone"] = "off"
			game.sound_at("glass_settle", b.p.x, b.p.y, .45)
	for i in low.size():
		var lying: P.Body = low[i]
		var lying_of: Dictionary = low_of[i]
		_store(lying, lying_of)
	var knocks := top.knocks + bottom.knocks
	if knocks > 0:
		var at := top.knock_at if top.knocks > 0 else bottom.knock_at
		game.sound_at("pin_clack", at.x, at.y, minf(1.0, .3 + knocks * .08))
	if thrown != null:
		_ball_moved(game, thrown, dt)
	_score_bottles(game)


func _solver(floor_fn: Callable) -> P:
	var sim := P.new()
	sim.floor_at = floor_fn
	sim.kick = L.BOTTLE_WALLS
	sim.cushion = -1e4
	sim.foul = L.BOTTLE_BACK
	return sim


func _ball_moved(game: Game, b: P.Body, dt: float) -> void:
	var t: float = ball["t"]
	ball["t"] = t + dt
	ball["x"] = b.p.x
	ball["y"] = b.p.y
	ball["z"] = b.p.z
	ball["vx"] = b.v.x
	ball["vy"] = b.v.y
	ball["vz"] = b.v.z
	var resting := b.v.length() < .25 and b.p.z < S.SOFTBALL_R + .02
	if resting or t > 4.0 or b.p.distance_to(Vector3(L.TABLE_AT.x, L.TABLE_AT.y, 0.0)) > 9.0:
		ball = {}
		bottle_settle = game.clock


func _score_bottles(game: Game) -> void:
	if not ball.is_empty() or bottle_settle < 0.0:
		return
	var all_off := true
	for bottle: Dictionary in bottles:
		all_off = all_off and str(bottle["gone"]) == "off"
	if balls_left > 0 and not all_off:
		return
	var still := true
	for bottle: Dictionary in bottles:
		var awake: float = bottle["awake"]
		still = still and awake <= 0.0
	if not still and game.clock - bottle_settle < BOTTLE_LONGEST:
		return
	if game.clock - bottle_settle < .5:
		return
	bottle_settle = -1.0
	var down := 0
	var off := 0
	for bottle: Dictionary in bottles:
		if str(bottle["gone"]) == "off":
			off += 1
		elif bottle_down(bottle):
			down += 1
	bottle_score = down + off * 2 + (10 if off == bottles.size() else 0)
	balls_left = 0
	if bottle_shot:
		bottle_last = "%d OFF, %d DOWN. SHOOTING THEM'S NO FAIR: NO SCORE." % [off, down]
		bottle_shot = false
		return
	bottle_best = maxi(bottle_best, bottle_score)
	finished.append(["bottles", bottle_score])
	if off == bottles.size():
		bottle_last = "CLEARED THE TABLE! %d" % bottle_score
		game.callout = "CLEARED!"
		game.callout_until = game.clock + 1.6
		game.sound.play("range_strike", .7)
	else:
		bottle_last = "%d OFF, %d DOWN: %d. BEST %d" % [off, down, bottle_score, bottle_best]


## A round struck a bottle standing on the table: it is knocked over the way
## the shot went (and the round scores nothing).
func bottle_shot_at(game: Game, s: Vector3, e: Vector3) -> bool:
	var floor_z := game.world.elevation(L.TABLE_AT.x, L.TABLE_AT.y)
	var best := {}
	var best_t := 9.0
	for bottle: Dictionary in bottles:
		if bottle_down(bottle):
			continue
		var x: float = bottle["x"]
		var y: float = bottle["y"]
		var hit := Targets.crossing(s, e, x, y, floor_z + S.TABLE_TOP + .13, .14, .05)
		if hit.x >= 0.0 and hit.x < best_t:
			best_t = hit.x
			best = bottle
	if best.is_empty():
		return false
	var b := _body(best)
	b.awake = true
	b.rest = 0.0
	var way := Vector2(e.x - s.x, e.y - s.y).normalized() * 1.4
	b.push(Vector3(way.x, way.y, .1), b.axis() * (.2 - S.BOTTLE_COM))
	_store(b, best)
	bottle_shot = true
	if bottle_settle < 0.0 and ball.is_empty():
		bottle_settle = game.clock
	game.sound_at("glass_settle", b.p.x, b.p.y, .6)
	return true


# ------------------------------------------------------------------ shots


## A bullet from s to e on the games row: the bullseye or a bottle.
func trace(game: Game, s: Vector3, e: Vector3) -> bool:
	if dunk_shot(game, s, e):
		return true
	return bottle_shot_at(game, s, e)


# ------------------------------------------------------------------ looks


func sprites(game: Game) -> Array:
	var out: Array = []
	_shoe_sprites(game, out)
	_dunk_sprites(game, out)
	out.append_array(skee.sprites(game))
	_bottle_sprites(game, out)
	return out


static func _solid(
	x: float, y: float, z: float, kind: String, turn := Basis.IDENTITY
) -> View.Sprite:
	var s := View.Sprite.new(x, y, "town_range_pin", .3, z)
	s.solid = kind
	s.turn = turn
	return s


func _shoe_sprites(game: Game, out: Array) -> void:
	if not game.in_view(L.STAKE.x, L.STAKE.y - 4.0, 6.0):
		return
	var court := _court(game)
	out.append(_solid(L.STAKE.x, L.STAKE.y, court, "stake"))
	for shoe: Dictionary in shoes:
		var x: float = shoe["x"]
		var y: float = shoe["y"]
		var z: float = shoe["z"]
		var yaw: float = shoe["yaw"]
		var lean: float = shoe["lean"]
		var turn := Basis(Vector3(0, 0, 1), yaw)
		if lean > 0.0:
			var t := (L.STAKE - Vector2(x, y)).normalized()
			turn = Basis(Vector3(t.y, -t.x, 0.0), lean) * turn
			z += S.SHOE_R * sin(lean) * .9
		elif str(shoe["state"]) == "fly":
			# A pitched shoe wobbles as it turns.
			turn = Basis(Vector3(cos(yaw), sin(yaw), 0.0), sin(yaw * 1.3) * .25) * turn
		out.append(_solid(x, y, court + z, "horseshoe", turn))


func _dunk_sprites(game: Game, out: Array) -> void:
	var at := L.TANK_AT
	if not game.in_view(at.x, at.y, 3.0):
		return
	var floor_z := game.world.elevation(at.x, at.y)
	out.append(_solid(at.x, at.y, floor_z, "dunk_tank"))
	var pose := hand_pose(game)
	var hinge := at + Vector2(0.0, S.TANK.y - .1)
	out.append(
		_solid(hinge.x, hinge.y, floor_z + S.SEAT_Z, "dunk_seat", Basis(Vector3(1, 0, 0), pose.y))
	)
	var pivot := Vector3(at.x + S.TARGET_AT.x, at.y + S.TARGET_AT.y, floor_z + S.TARGET_AT.z + .3)
	out.append(_solid(pivot.x, pivot.y, pivot.z, "dunk_target", Basis(Vector3(0, 1, 0), -swing)))
	var spot := hand_at()
	var image := "billy_0"
	var since := game.clock - dunk_since
	match dunk_state:
		"falling":
			image = "billy_pain"
		"under":
			image = "billy_hurt_0"
		"climbing":
			image = "billy_w%d" % (int(since * 6.0) % 4)
		_:
			if fmod(game.clock, 4.0) < 1.2:
				image = "billy_aim"
	var hand := View.Sprite.new(spot.x, spot.y, image, .95, floor_z + pose.x)
	hand.body = true
	var e := ModeBodies.stand_in(game, "range-dunk", "billy")
	e.x = spot.x
	e.y = spot.y
	e.angle = -PI / 2.0
	e.gait = since * 4.0
	hand.who = e
	out.append(hand)


func _bottle_sprites(game: Game, out: Array) -> void:
	var at := L.TABLE_AT
	if not game.in_view(at.x, at.y, 2.5):
		return
	var floor_z := game.world.elevation(at.x, at.y)
	for bottle: Dictionary in bottles:
		var b := _body(bottle)
		var foot := P.foot(b)
		out.append(_solid(foot.x, foot.y, floor_z + foot.z, "bottle", Basis(b.q)))
	if not ball.is_empty():
		var x: float = ball["x"]
		var y: float = ball["y"]
		var z: float = ball["z"]
		var t: float = ball["t"]
		out.append(_solid(x, y, floor_z + z, "softball", Basis(Vector3(1, 0, 0), t * 20.0)))
	else:
		# The balls left, on the counter at the line.
		for k in balls_left:
			out.append(
				_solid(
					L.BOTTLE_LINE.x + .75 + k * .14,
					L.BOTTLE_LINE.y + .25,
					floor_z + .8 + S.SOFTBALL_R,
					"softball",
					Basis(Vector3(0, 0, 1), k * 2.1)
				)
			)
