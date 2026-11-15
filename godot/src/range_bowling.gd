## The Bowl-O-Rama's lane (src/range_layout.gd says where): ten pins that are
## real bodies, a pinsetter and a ten-frame score sheet. Played by the firing
## range's targets (range_targets.gd), which hand it the ball, the shots and
## the blasts; part of the range's play (carried in snapshots), so its own dice
## only, never the game's.
##
## Each pin is a rigid body in three dimensions (range_pin_physics.gd): its
## shape a chain of spheres up a real pin's profile on the ring of its foot,
## its weight, its turn and its spin. Struck, it is thrown and turned by where
## it was hit; it rocks back on its foot if it was only nudged and goes over
## if its centre of mass passes the edge of its foot; down, it rolls on its
## belly, slides, spins and knocks the next one, off the kickbacks, into the
## gutters (real channels) and over the edge of the deck into the pit. The
## ball is the game's own rolling shot, a heavy sphere in the same solve while
## it is among the pins: a pin takes its share of the ball's momentum and the
## ball goes on slower and deflected; on the lane it hooks the way the thrower
## turned as they let go, once past the oil, and off the lane it runs down a
## gutter. After the first ball of a frame the sweep clears the deadwood and
## stands the rest up where they stood; after a strike or the frame's last
## ball, a fresh rack. Strikes and spares score as bowling does, ten a game.
extends RefCounted

const L := preload("res://src/range_layout.gd")
const P := preload("res://src/range_pin_physics.gd")

## The ball's radius and mass (a sixteen-pounder against a pin's 1).
const BALL_R := P.BALL_R
const BALL_MASS := P.BALL_MASS
## The lane: its bed, the gutters each side (channels GUTTER deep), the
## kickbacks (walls) outside them, where the deck ends and the pit (PIT deep)
## begins, the cushion at its back, the foul line and how far the oil runs.
const BED := [45.0, 48.0]
const GUTTER := -.06
const KICKBACK := [44.04, 48.96]
const DECK_END := 36.0
const PIT := -.22
const PIT_Y := 36.25
const CUSHION_Y := 33.4
const FOUL_Y := 49.4
const OIL := 6.5
## The ball is solved with the pins from this far before the head pin.
const AMONG := 1.4
## A pin counts as down leaning past this (radians), or off the bed; in the
## pit it is gone (and no longer moved) below FELL.
const COUNTS := .62
const FELL := -.18
## Steps a tick for the pins (their knocks are quick), at HIGH physics detail.
const STEPS := 6
## Seconds: the pins must lie still this long to be counted; the longest a ball
## is waited on; from the count to the sweep or a fresh rack.
const STILL := .45
const LONGEST := 6.5
const SWEEP_AFTER := 1.4
## Deadwood slower than this (cells a second) can be counted round.
const DEADWOOD := .45
## The hook: radians a second of the thrower's turn as they let go, to cells a
## second squared sideways once past the oil (it bends the way they turned),
## and the most it takes.
const HOOK_GAIN := .55
const HOOK_MOST := 3.2
## Which pins touch which in a rack (numbers 1..10), for calling a split.
const NEIGHBOURS := {
	1: [2, 3, 5],
	2: [1, 3, 4, 5, 8],
	3: [1, 2, 5, 6, 9],
	4: [2, 7, 8, 5],
	5: [1, 2, 3, 4, 6, 8, 9],
	6: [3, 9, 10, 5],
	7: [4, 8],
	8: [4, 5, 7, 9, 2],
	9: [5, 6, 8, 10, 3],
	10: [6, 9],
}
## A pin's numbers kept between ticks (snapshots carry them).
const KEYS := ["x", "y", "z", "qx", "qy", "qz", "qw", "vx", "vy", "vz", "wx", "wy", "wz", "rest"]

var dice := RandomNumberGenerator.new()
## Each pin: {n (1..10), x, y, z (its centre of mass; z above the deck), qx,
## qy, qz, qw (its turn), vx, vy, vz (its slide), wx, wy, wz (its spin), rest
## (seconds it has been still), awake (1 or 0), gone ("" on the deck, "pit",
## "swept")}.
var pins: Array = []
## The ball (a shot's uid) rolling now, its hook, whether it is in a gutter,
## whether it met a pin.
var ball_uid := -1
var hook := 0.0
var in_gutter := false
var touched := false
## The roll: when it began (-1 none), since when everything has been still.
var roll_started := -1.0
var still_since := -1.0
## When the sweep or a fresh rack comes (-1 none), and which.
var sweep_at := -1.0
var sweep_full := false
## The score sheet: every ball's pins, by frame; the frame and ball now.
var frames: Array = []
var frame := 0
var ball := 0
var standing_before := 10
var games := 0
var best_game := 0
var last_roll := ""
var strikes := 0
var spares := 0
## The pins' knocks heard this tick (a clatter, not forty clicks).
var clacks := 0
var clack_at := Vector2.ZERO


func _init() -> void:
	dice.seed = 1958
	new_game()


func new_game() -> void:
	frames = []
	for k in 10:
		frames.append([])
	frame = 0
	ball = 0
	rack()


## A fresh rack: all ten on their spots, still and upright.
func rack() -> void:
	pins.clear()
	var spots: Array = L.pins()
	for i in spots.size():
		var spot: Vector2 = spots[i]
		var pin := {"n": i + 1, "gone": "", "awake": 0.0}
		for key: String in KEYS:
			pin[key] = 0.0
		_stand(pin, spot)
		pins.append(pin)
	standing_before = 10
	roll_started = -1.0
	sweep_at = -1.0


## Stand `pin` up still on its foot at `spot`.
static func _stand(pin: Dictionary, spot: Vector2) -> void:
	for key: String in KEYS:
		pin[key] = 0.0
	pin["x"] = spot.x
	pin["y"] = spot.y
	pin["z"] = P.COM
	pin["qw"] = 1.0
	pin["awake"] = 0.0


## How far a pin leans from upright (radians).
static func lean(pin: Dictionary) -> float:
	var qx := _float(pin["qx"])
	var qy := _float(pin["qy"])
	return acos(clampf(1.0 - 2.0 * (qx * qx + qy * qy), -1.0, 1.0))


## Down: in the pit or swept, leaning past COUNTS, or off the bed.
static func is_down(pin: Dictionary) -> bool:
	if str(pin["gone"]) != "" or lean(pin) > COUNTS:
		return true
	var x := _float(pin["x"])
	return x < BED[0] or x > BED[1] or _float(pin["y"]) < DECK_END


func standing() -> int:
	var n := 0
	for pin: Dictionary in pins:
		if not is_down(pin):
			n += 1
	return n


func pins_down() -> int:
	return 10 - standing()


## The deck's floor under (x, y), from the deck's top: the bed, a gutter's
## channel, the pit (the level is built so: range_plan.gd's bowling()).
static func floor_at(x: float, y: float) -> float:
	if y < DECK_END:
		return PIT
	if x < BED[0] or x > BED[1]:
		return GUTTER
	return 0.0


# ------------------------------------------------------------------ bodies


static func _body(pin: Dictionary) -> P.Body:
	var b := P.Body.new()
	b.p = Vector3(_float(pin["x"]), _float(pin["y"]), _float(pin["z"]))
	b.q = Quaternion(_float(pin["qx"]), _float(pin["qy"]), _float(pin["qz"]), _float(pin["qw"]))
	b.v = Vector3(_float(pin["vx"]), _float(pin["vy"]), _float(pin["vz"]))
	b.w = Vector3(_float(pin["wx"]), _float(pin["wy"]), _float(pin["wz"]))
	b.rest = _float(pin["rest"])
	b.awake = _float(pin["awake"]) > 0.0
	return b


static func _store(b: P.Body, pin: Dictionary) -> void:
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
		pin[KEYS[i]] = values[i]
	pin["awake"] = 1.0 if b.awake else 0.0


## A knock `j` on a pin, `up` along its axis from its foot, the pin woken.
func _knock(pin: Dictionary, j: Vector3, up: float) -> void:
	var b := _body(pin)
	b.awake = true
	b.rest = 0.0
	b.push(j, b.axis() * (up - P.COM))
	_store(b, pin)


# ------------------------------------------------------------------ the ball


## A ball has been thrown (the range heard it): its hook from how fast the
## thrower was turning, radians a second.
func thrown(shot: GameState.Shot, turn: float) -> void:
	ball_uid = shot.uid
	hook = clampf(turn * HOOK_GAIN, -HOOK_MOST, HOOK_MOST)
	in_gutter = false
	touched = false


static func _on_lane(x: float, y: float) -> bool:
	return x > KICKBACK[0] - .5 and x < KICKBACK[1] + .5 and y > CUSHION_Y - .5 and y < FOUL_Y + 1.2


## The ball on the lane this tick (it has just rolled, game_combat.gd): the
## gutter, the hook, the pit. True when it is among the pins (solved with
## them this tick).
func roll_ball(game: Game, shot: GameState.Shot, dt: float) -> bool:
	var deck := _deck(game)
	if not _on_lane(shot.x, shot.y) or shot.z - deck > .45:
		return false
	if roll_started < 0.0 and shot.y < FOUL_Y:
		roll_started = game.clock
		still_since = -1.0
	var speed := Vector2(shot.vx, shot.vy).length()
	if in_gutter or shot.x < BED[0] or shot.x > BED[1]:
		# In the channel: it runs straight down it, past the pins.
		if not in_gutter and shot.y < FOUL_Y:
			game.sound_at("bowling_thud", shot.x, shot.y, .5)
		in_gutter = true
		var channel := (BED[0] + KICKBACK[0]) * .5 if shot.x < 46.5 else (BED[1] + KICKBACK[1]) * .5
		shot.x = lerpf(shot.x, channel, minf(1.0, dt * 12.0))
		shot.vx = 0.0
		shot.vy = -maxf(absf(shot.vy), speed * .9)
	elif shot.y < FOUL_Y - OIL and absf(hook) > .01 and speed > .5:
		# Off the oil the spin bites: the line bends, the speed stays.
		var v := Vector2(shot.vx, shot.vy).rotated(hook * dt / speed)
		shot.vx = v.x
		shot.vy = v.y
	if shot.y < DECK_END - .3:
		# Over the edge into the pit: the roll is done with.
		ball_uid = -1
		return false
	return not in_gutter and shot.y < L.PIN_HEAD.y + AMONG


# ------------------------------------------------------------------ the pins


## The deck's height in the level (the pins' z is from it).
static func _deck(game: Game) -> float:
	return game.world.elevation(L.PIN_HEAD.x, L.PIN_HEAD.y)


func _live_ball(game: Game) -> GameState.Shot:
	if ball_uid < 0:
		return null
	for shot: GameState.Shot in game.shots:
		if shot.uid == ball_uid:
			return shot
	ball_uid = -1
	return null


func tick(game: Game, dt: float) -> void:
	clacks = 0
	var shot := _live_ball(game)
	var among := false
	if shot != null:
		among = roll_ball(game, shot, dt)
	var bodies: Array = []
	var held: Array = []
	var moving := among
	for pin: Dictionary in pins:
		if str(pin["gone"]) != "":
			continue
		var b := _body(pin)
		bodies.append(b)
		held.append(pin)
		moving = moving or b.awake
	if moving:
		_solve(game, bodies, held, shot if among else null, dt)
	_score(game)


func _solve(game: Game, bodies: Array, held: Array, shot: GameState.Shot, dt: float) -> void:
	var sim := P.new()
	sim.floor_at = floor_at
	sim.kick = Vector2(KICKBACK[0], KICKBACK[1])
	sim.cushion = CUSHION_Y
	sim.foul = FOUL_Y
	var ball_body: P.Body = null
	if shot != null:
		# The ball's roll this tick is solved again here, with the pins, from
		# where it was before it.
		ball_body = P.Body.new()
		ball_body.ball = true
		ball_body.inv_m = 1.0 / BALL_MASS
		ball_body.p = Vector3(shot.x - shot.vx * dt, shot.y - shot.vy * dt, BALL_R)
		ball_body.v = Vector3(shot.vx, shot.vy, 0.0)
	# Fewer steps at a lower physics detail (QUALITY, core/quality.gd).
	var steps := Quality.steps(STEPS)
	var h := dt / steps
	for _k in steps:
		sim.step(bodies, ball_body, h)
	for i in bodies.size():
		var b: P.Body = bodies[i]
		var pin: Dictionary = held[i]
		_store(b, pin)
		if b.p.z < FELL and b.p.y < DECK_END:
			pin["gone"] = "pit"
	if ball_body != null:
		shot.x = ball_body.p.x
		shot.y = ball_body.p.y
		shot.vx = ball_body.v.x
		shot.vy = ball_body.v.y
		if sim.first_hit and not touched:
			touched = true
			game.sound_at("bowling_hit", shot.x, shot.y, .8)
	clacks = sim.knocks
	clack_at = sim.knock_at
	if clacks > 0:
		game.sound_at("pin_clack", clack_at.x, clack_at.y, minf(1.0, .35 + clacks * .08))
		if clacks >= 6:
			game.sound_at("range_pin_scatter", clack_at.x, clack_at.y, .5)


# ------------------------------------------------------------------ scoring


## Still: every pin still up has come to rest, and the deadwood is down to a
## crawl (a pin sliding fast may yet take one with it).
func _settled() -> bool:
	for pin: Dictionary in pins:
		if str(pin["gone"]) != "" or _float(pin["awake"]) <= 0.0:
			continue
		if not is_down(pin):
			return false
		if Vector3(_float(pin["vx"]), _float(pin["vy"]), _float(pin["vz"])).length() > DEADWOOD:
			return false
	return true


func _ball_live(game: Game) -> bool:
	return _live_ball(game) != null


func _score(game: Game) -> void:
	if sweep_at > 0.0 and game.clock >= sweep_at:
		_sweep(game)
		return
	if roll_started < 0.0:
		return
	if _ball_live(game) and game.clock - roll_started < LONGEST:
		return
	if not _settled() and game.clock - roll_started < LONGEST:
		still_since = -1.0
		return
	if still_since < 0.0:
		still_since = game.clock
		return
	if game.clock - still_since < STILL:
		return
	roll_started = -1.0
	still_since = -1.0
	_count(game)


func _count(game: Game) -> void:
	var up := standing()
	var got := standing_before - up
	if frame >= 10:
		new_game()
		up = standing()
	var sheet: Array = frames[frame]
	sheet.append(got)
	var last := frame == 9
	var callout := ""
	if ball == 0 and got == 10:
		strikes += 1
		last_roll = "STRIKE! ALL TEN"
		callout = "STRIKE!"
		game.sound.play("range_strike", .8)
	elif ball == 1 and standing_before < 10 and up == 0 and not (last and sheet[0] == 10):
		spares += 1
		last_roll = "SPARE! %d ON THE SECOND BALL" % got
		callout = "SPARE!"
	elif got == 0:
		last_roll = "GUTTER BALL" if in_gutter else "NOTHING. NOT A PIN"
	else:
		last_roll = "%d PIN%s DOWN" % [got, "" if got == 1 else "S"]
		var split := split_name()
		if ball == 0 and split != "":
			last_roll = split + " SPLIT!"
			callout = "SPLIT!"
	if callout != "":
		game.callout = callout
		game.callout_until = game.clock + 1.5
	ball += 1
	var done := _frame_done(sheet, last)
	if done:
		frame += 1
		ball = 0
		if frame >= 10:
			var total := score()
			games += 1
			best_game = maxi(best_game, total)
			last_roll = "GAME OVER: %d. BEST %d" % [total, best_game]
			game.callout = "GAME! %d" % total
			game.callout_until = game.clock + 2.2
	# A strike or a spare in the tenth racks them all for its bonus ball.
	sweep_full = done or up == 0
	sweep_at = game.clock + SWEEP_AFTER
	standing_before = up if not sweep_full else 10


static func _frame_done(sheet: Array, last: bool) -> bool:
	if not last:
		return sheet.size() >= 2 or (sheet.size() == 1 and _int(sheet[0]) == 10)
	if sheet.size() >= 3:
		return true
	if sheet.size() == 2:
		return _int(sheet[0]) + _int(sheet[1]) < 10
	return false


## The pinsetter: deadwood out and the standing pins stood up where they are,
## or a fresh rack.
func _sweep(game: Game) -> void:
	sweep_at = -1.0
	game.sound_at("range_pen_gate", L.PIN_HEAD.x, L.PIN_HEAD.y - .8, .45)
	if sweep_full:
		rack()
		return
	for pin: Dictionary in pins:
		if is_down(pin):
			pin["gone"] = "swept"
		else:
			_stand(pin, Vector2(_float(pin["x"]), _float(pin["y"])))
	standing_before = standing()


## A split after the first ball: the head pin down and the pins left standing
## in two or more bunches that touch nothing of each other ("7-10").
func split_name() -> String:
	var up: Array = []
	for pin: Dictionary in pins:
		if not is_down(pin):
			up.append(_int(pin["n"]))
	if up.size() < 2 or 1 in up:
		return ""
	var seen := {up[0]: true}
	var todo: Array = [up[0]]
	while not todo.is_empty():
		var n: int = todo.pop_back()
		for m: int in NEIGHBOURS[n]:
			if m in up and not seen.has(m):
				seen[m] = true
				todo.append(m)
	if seen.size() == up.size():
		return ""
	up.sort()
	var words: PackedStringArray = []
	for n: int in up:
		words.append(str(n))
	return "-".join(words)


## The game's score so far, as bowling counts it.
func score() -> int:
	var balls: Array = []
	for sheet: Array in frames:
		balls.append_array(sheet)
	var total := 0
	var i := 0
	for f in 10:
		var sheet: Array = frames[f]
		if sheet.is_empty():
			break
		if _int(sheet[0]) == 10 and f < 9:
			total += 10 + _ball(balls, i + 1) + _ball(balls, i + 2)
			i += 1
		elif sheet.size() >= 2 and _int(sheet[0]) + _int(sheet[1]) >= 10 and f < 9:
			total += 10 + _ball(balls, i + 2)
			i += 2
		else:
			for b: int in sheet:
				total += b
			i += sheet.size()
	return total


static func _ball(balls: Array, i: int) -> int:
	return _int(balls[i]) if i < balls.size() else 0


## The sheet as a bowler writes it: X a strike, / a spare, - a miss.
func sheet_text(last := 5) -> String:
	var marks: PackedStringArray = []
	for f in 10:
		var sheet: Array = frames[f]
		if sheet.is_empty():
			break
		var text := ""
		for k in sheet.size():
			var b := _int(sheet[k])
			var spare: bool = (
				k > 0
				and _int(sheet[k - 1]) != 10
				and _int(sheet[k - 1]) + b == 10
				and not (k == 2 and _int(sheet[0]) + _int(sheet[1]) != 10 and _int(sheet[1]) != 10)
			)
			if b == 10 and not spare:
				text += "X"
			elif spare:
				text += "/"
			elif b == 0:
				text += "-"
			else:
				text += str(b)
		marks.append(text)
	var from := maxi(0, marks.size() - last)
	return " ".join(marks.slice(from))


# ------------------------------------------------------------------ knocks


## A shot along s..e struck the first pin it met: the pin, or {}.
func shot_at(s: Vector3, e: Vector3, crossing: Callable) -> Dictionary:
	var best := {}
	var best_t := 9.0
	for pin: Dictionary in pins:
		if str(pin["gone"]) != "" or lean(pin) > COUNTS:
			continue
		var hit: Vector2 = crossing.call(s, e, pin["x"], pin["y"], .2, .2, .08)
		if hit.x >= 0.0 and hit.x < best_t:
			best_t = hit.x
			best = pin
	return {} if best.is_empty() else {"pin": best, "t": best_t}


## A round struck a pin: a hard knock high up, the way it flew.
func shot_knock(game: Game, pin: Dictionary, direction: Vector2, damage: float) -> void:
	var d := direction.normalized() * clampf(damage / 18.0, .8, 4.0) * .55
	var off := dice.randf_range(-.02, .02)
	_knock(pin, Vector3(d.x, d.y, .15), .3 + off)
	clacks += 1
	clack_at = Vector2(_float(pin["x"]), _float(pin["y"]))
	if roll_started < 0.0:
		roll_started = game.clock
		still_since = -1.0


## A blast at (x, y): pins within reach are thrown up and off it, spinning.
func blast(game: Game, x: float, y: float) -> void:
	var any := false
	for pin: Dictionary in pins:
		if str(pin["gone"]) != "":
			continue
		var away := Vector2(_float(pin["x"]) - x, _float(pin["y"]) - y)
		var d := away.length()
		if d > 3.2:
			continue
		var power := (3.2 - d) * 1.1
		var dir := (away / maxf(d, .05)).rotated(dice.randf_range(-.4, .4)) * power
		_knock(pin, Vector3(dir.x, dir.y, power * .7), dice.randf_range(.2, .36))
		any = true
	if any and roll_started < 0.0:
		roll_started = game.clock
		still_since = -1.0


# ------------------------------------------------------------------ looks


## The pins as 3D bodies for the view (View.Sprite.solid "pin": the mesh
## stands on its foot, turned by `turn`), each where its foot is.
func sprites(game: Game, _eye: Vector2) -> Array:
	var out: Array = []
	var deck := _deck(game)
	for pin: Dictionary in pins:
		if str(pin["gone"]) in ["pit", "swept"]:
			continue
		var b := _body(pin)
		var at := P.foot(b)
		if not game.in_view(at.x, at.y, .6):
			continue
		var sprite := View.Sprite.new(at.x, at.y, "town_range_pin", .5, deck + at.z)
		sprite.solid = "pin"
		sprite.turn = Basis(b.q)
		out.append(sprite)
	return out


## int() and float() of a value read from data or a dictionary, typed (the
## same result for a number, a bool or a number written as text).
static func _int(v: Variant) -> int:
	return str(v).to_int() if v is String else v


static func _float(v: Variant) -> float:
	return str(v).to_float() if v is String else v
