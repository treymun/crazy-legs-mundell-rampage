## The midway's skee-ball cabinet (src/range_layout.gd says where; its shape
## is range_games_shape.gd's, which the 3D view draws it from): nine wooden
## balls a game rolled up a rising maple lane, off the rubber hump, through
## the air and onto the ring board. Where a ball lands on the board is the
## ring it drops into: 50 in the middle, 40, 30, 20 round it, 10 for the
## rest of the board and the gutter under it, 100 in the two top corner
## cups; a ball that dies on the lane rolls back for nothing. How hard it is
## rolled is where the thrower looks (down the lane soft, up hard), which way
## is where they face. Part of the range's play: plain numbers, no dice.
extends RefCounted

const L := preload("res://src/range_layout.gd")
const S := preload("res://src/range_games_shape.gd")
const GRAVITY := 10.7
## Steps a tick (the ball is quick off the hump).
const STEPS := 4

static var BALLS: int = RangeTuning.get_value("skeeball", "balls", 9)
## Cells a second the ball leaves the hand at: looking down the lane, and up.
static var SLOW: float = RangeTuning.get_value("skeeball", "slow", 3.6)
static var FAST: float = RangeTuning.get_value("skeeball", "fast", 7.2)
## The lane's drag on a rolling ball (cells a second, a second), what the
## rails and the back give back of a knock, and seconds down a ring's drain.
static var DRAG: float = RangeTuning.get_value("skeeball", "drag", .35)
static var RAIL: float = RangeTuning.get_value("skeeball", "rail", .5)
static var BACK: float = RangeTuning.get_value("skeeball", "back", .3)
static var DROP: float = RangeTuning.get_value("skeeball", "drop", .45)
## Each roll a little off, by the game's dice: speed (a share), way (radians).
static var WOBBLE: float = RangeTuning.get_value("skeeball", "wobble", .025)
static var AIM_WOBBLE: float = RangeTuning.get_value("skeeball", "aim_wobble", .02)

## The ball rolling now ({} none): s along the lane, u across, z up from the
## floor, its speeds, its phase ("lane", "back", "air", "drop"), the ring it
## is dropping into and where it landed on the board, the drop's clock.
var ball := {}
var balls_left := BALLS
var score := 0
var rolls: Array = []
var last := ""
var best := 0
var games := 0
var fifties := 0
## Games finished since the range last looked ([game, score]).
var finished: Array = []


static func bed(s: float) -> float:
	return S.SKEE_FOOT + S.SKEE_RISE * s


## The lane's point in the map (and z above the floor).
static func to_map(s: float, u: float) -> Vector2:
	return Vector2(L.SKEE_FOOT.x + u, L.SKEE_FOOT.y + s)


## The points of a ball landing on the board `a` up it, `u` across.
static func points_at(a: float, u: float) -> int:
	var cup: Array = S.SKEE_HUNDRED
	var cup_up: float = cup[0]
	var cup_across: float = cup[1]
	var cup_r: float = cup[2]
	for side: float in [-1.0, 1.0]:
		if Vector2(a - cup_up, u - side * cup_across).length() < cup_r:
			return 100
	var r := Vector2(a - S.SKEE_RING_AT, u).length()
	for row: Array in S.SKEE_RINGS:
		var outer: float = row[0]
		if r < outer:
			var points: int = row[1]
			return points
	return 10


## Where on the board a ring's ball drains (up it, across).
static func drain(points: int, a: float, u: float) -> Vector2:
	if points == 100:
		var cup: Array = S.SKEE_HUNDRED
		var cup_up: float = cup[0]
		var cup_across: float = cup[1]
		return Vector2(cup_up, cup_across * signf(u))
	if points == 10:
		return Vector2(.06, 0.0) if a > .0 else Vector2(-.12, 0.0)
	var inner := 0.0
	for row: Array in S.SKEE_RINGS:
		var outer: float = row[0]
		var ring_points: int = row[1]
		if ring_points == points:
			if inner == 0.0:
				return Vector2(S.SKEE_RING_AT, 0.0)
			return Vector2(S.SKEE_RING_AT - (inner + outer) * .5, 0.0)
		inner = outer
	return Vector2(S.SKEE_RING_AT, 0.0)


## The board's point `a` up it, `lift` off its face, as (s, z) of the lane.
static func on_board(a: float, lift: float) -> Vector2:
	var t := S.SKEE_TILT
	return Vector2(
		S.SKEE_BOARD_S + a * cos(t) - lift * sin(t), S.SKEE_BOARD_Z + a * sin(t) + lift * cos(t)
	)


func new_game() -> void:
	balls_left = BALLS
	score = 0
	rolls = []
	last = ""


## How hard a ball rolled now would go, 0 to 1 (where the thrower looks).
static func power(p: Player) -> float:
	return clampf((p.pitch / View.base_focal + .23) / .46, 0.0, 1.0)


## Roll a ball from where `p` stands: how hard by their look, which way by
## their facing, each a little off by `dice` (the game's). Returns what to
## tell them ("" when it rolled).
func roll(p: Player, dice: GameState.Rng) -> String:
	if not ball.is_empty():
		return "WAIT FOR THE BALL TO DROP."
	if balls_left <= 0:
		new_game()
	var a := p.view_angle() + dice.uniform(-AIM_WOBBLE, AIM_WOBBLE)
	var speed := lerpf(SLOW, FAST, power(p)) * (1.0 + dice.uniform(-WOBBLE, WOBBLE))
	var u := clampf(p.x - L.SKEE_FOOT.x, -S.SKEE_W * .5 + .1, S.SKEE_W * .5 - .1)
	ball = {
		"s": .05,
		"u": u,
		"z": bed(.05) + S.SKEE_BALL_R,
		"vs": maxf(.5, sin(a) * speed),
		"vu": cos(a) * speed,
		"vz": 0.0,
		"phase": "lane",
		"points": 0,
		"a": 0.0,
		"au": 0.0,
		"t": 0.0,
	}
	balls_left -= 1
	return ""


func tick(game: Game, dt: float) -> void:
	if ball.is_empty():
		return
	var h := dt / STEPS
	for _k in STEPS:
		if ball.is_empty():
			return
		_step(game, h)


func _step(game: Game, h: float) -> void:
	var phase := str(ball["phase"])
	var s: float = ball["s"]
	var u: float = ball["u"]
	var z: float = ball["z"]
	var vs: float = ball["vs"]
	var vu: float = ball["vu"]
	var vz: float = ball["vz"]
	var r := S.SKEE_BALL_R
	var room := S.SKEE_W * .5 - r
	if phase == "drop":
		var t: float = ball["t"]
		ball["t"] = t + h
		if t + h >= DROP:
			var points: int = ball["points"]
			_scored(game, points)
		return
	if phase == "lane" or phase == "back":
		vs -= (GRAVITY * S.SKEE_RISE / sqrt(1.0 + S.SKEE_RISE * S.SKEE_RISE)) * h
		vs -= DRAG * h * signf(vs)
		s += vs * h
		u += vu * h
		z = bed(s) + r
		if phase == "lane" and vs <= 0.0:
			phase = "back"
		if phase == "back" and s <= 0.0:
			ball = {}
			_scored(game, 0, "SHORT: IT ROLLED BACK. NOTHING.")
			return
		if phase == "lane" and s >= S.SKEE_LANE:
			# Off the hump and into the air.
			s = S.SKEE_LANE + S.SKEE_HUMP
			z = bed(S.SKEE_LANE) + S.SKEE_HUMP_UP + r
			vz = vs * sin(S.SKEE_KICK)
			vs = vs * cos(S.SKEE_KICK)
			phase = "air"
			game.sound_at("football_bounce", to_map(s, u).x, to_map(s, u).y, .35)
	elif phase == "air":
		vz -= GRAVITY * h
		s += vs * h
		u += vu * h
		z += vz * h
		if s > S.SKEE_BACK_S - r:
			s = S.SKEE_BACK_S - r
			vs = -absf(vs) * BACK
			game.sound_at("impact_wood", to_map(s, u).x, to_map(s, u).y, .4)
		var t := S.SKEE_TILT
		var across := (s - S.SKEE_BOARD_S) * cos(t) + (z - S.SKEE_BOARD_Z) * sin(t)
		var above := -(s - S.SKEE_BOARD_S) * sin(t) + (z - S.SKEE_BOARD_Z) * cos(t)
		if across >= 0.0 and above <= r:
			_land(game, across, u)
			return
		if z < S.SKEE_BOARD_Z - .16 + r:
			# Into the gutter under the board's foot: the 10.
			_land(game, -.1, u)
			return
	if absf(u) > room:
		u = clampf(u, -room, room)
		vu = -vu * RAIL
	ball["phase"] = phase
	ball["s"] = s
	ball["u"] = u
	ball["z"] = z
	ball["vs"] = vs
	ball["vu"] = vu
	ball["vz"] = vz


func _land(game: Game, a: float, u: float) -> void:
	var points := points_at(a, u) if a >= 0.0 else 10
	ball["phase"] = "drop"
	ball["points"] = points
	ball["a"] = a
	ball["au"] = u
	ball["t"] = 0.0
	var at := to_map(S.SKEE_BOARD_S, u)
	game.sound_at("range_gallery_ding" if points >= 40 else "impact_wood", at.x, at.y, .5)


func _scored(game: Game, points: int, words := "") -> void:
	ball = {}
	score += points
	rolls.append(points)
	if points >= 50:
		fifties += 1
	last = words if words != "" else "%d!" % points if points >= 50 else "%d" % points
	if points >= 100:
		game.callout = "100!"
		game.callout_until = game.clock + 1.4
	if balls_left <= 0:
		games += 1
		best = maxi(best, score)
		finished.append(["skeeball", score])
		last = "GAME OVER: %d. BEST %d" % [score, best]
		game.callout = "SKEE-BALL %d" % score
		game.callout_until = game.clock + 2.0
		game.sound.play("range_gallery_buzzer")


# ------------------------------------------------------------------ looks


## The cabinet, the ball in play and those waiting in the return.
func sprites(game: Game) -> Array:
	var out: Array = []
	var foot := L.SKEE_FOOT
	if not game.in_view(foot.x, foot.y + 2.3, 3.0):
		return out
	var ground := game.world.elevation(foot.x, foot.y - .5)
	var lane := View.Sprite.new(foot.x, foot.y, "town_range_pin", 2.4, ground)
	lane.solid = "skee_lane"
	out.append(lane)
	var waiting := mini(3, balls_left if balls_left > 0 or not ball.is_empty() else BALLS)
	for k in waiting:
		var w := View.Sprite.new(
			foot.x + (k - 1) * .17,
			foot.y - .26,
			"town_range_pin",
			.15,
			ground + S.SKEE_FOOT - .07 + S.SKEE_BALL_R
		)
		w.solid = "skee_ball"
		w.turn = Basis(Vector3(0, 0, 1), k * 1.7)
		out.append(w)
	if not ball.is_empty():
		var s: float = ball["s"]
		var u: float = ball["u"]
		var z: float = ball["z"]
		if str(ball["phase"]) == "drop":
			var clock: float = ball["t"]
			var t: float = clampf(clock / DROP, 0.0, 1.0)
			var points: int = ball["points"]
			var land_a: float = ball["a"]
			var land_u: float = ball["au"]
			var landed := Vector2(land_a, land_u)
			var hole := drain(points, landed.x, landed.y)
			var at := landed.lerp(hole, minf(1.0, t * 1.6))
			var sink := S.SKEE_BALL_R * (1.0 - maxf(0.0, t - .55) * 5.0)
			var sz := on_board(at.x, sink)
			s = sz.x
			z = sz.y
			u = at.y
		var spot := to_map(s, u)
		var b := View.Sprite.new(spot.x, spot.y, "town_range_pin", .15, ground + z)
		b.solid = "skee_ball"
		var turned := s / S.SKEE_BALL_R
		b.turn = Basis(Vector3(1, 0, 0), turned)
		out.append(b)
	return out
