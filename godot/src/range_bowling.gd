## The Bowl-O-Rama's lane (src/range_layout.gd says where): ten pins that are
## bodies, a pinsetter and a ten-frame score sheet. Played by the firing
## range's targets (range_targets.gd), which hand it the ball, the shots and
## the blasts; part of the range's play (carried in snapshots), so its own dice
## only, never the game's.
##
## A pin is a disc at its base and a tilt: a 2D vector, which way its head
## leans and how far, with a rate of change. Knocked, it leans; past TIP its
## own weight takes it down (it falls quicker the further it goes), short of
## TIP it rocks back and settles (a wobbler). Leaning or down it is a capsule
## from its base to where its head lies over the deck, so a falling pin sweeps
## into the next one and takes it with it, and lying pins are kicked about and
## spin. Pins bounce off the kickbacks, drop into the pit behind the deck or
## into a gutter. The ball is the game's own rolling shot: a pin it meets takes
## its share of the ball's momentum and the ball goes on a little slower and
## deflected; on the lane it hooks the way the thrower turned as they let go,
## once it is past the oil, and a ball off the lane runs down the gutter.
## After the first ball of a frame the sweep clears the deadwood and stands the
## rest up where they stood; after a strike or the frame's last ball, a fresh
## rack. Strikes and spares score as bowling does, ten frames a game.
extends RefCounted

const L := preload("res://src/range_layout.gd")

## Sizes in cells (a cell is about a yard): a pin's belly and length, the ball.
const PIN_R := .066
const PIN_LEN := .42
const BALL_R := .118
## Masses: a pin 1, the ball a sixteen-pounder against three and a half.
const BALL_MASS := 4.6
## The lane: its bed, the gutters each side, the kickbacks (walls) outside
## them, where the pin deck ends and the pit begins, the cushion at its back,
## the foul line and how far the oil runs from it.
const BED := [45.0, 48.0]
const KICKBACK := [44.04, 48.96]
const PIT_Y := 36.25
const CUSHION_Y := 34.1
const FOUL_Y := 49.4
const OIL := 6.5
## A pin's lean: past TIP (radians) it falls; G_T is its weight's pull on the
## lean (a radian a second squared at a radian); the rocking settles at DAMP.
## An impulse (mass times cells a second) at the belly leans it TIP_GAIN
## radians a second. Down is LYING; it counts as down past COUNTS.
const TIP := .17
const G_T := 38.0
const DAMP := 2.6
const TIP_GAIN := 3.0
const LYING := PI / 2.0
const COUNTS := .62
## Sliding on the deck (cells a second squared): upright, lying; a hop's fall.
const SLIDE := 3.0
const SLIDE_DOWN := 2.2
const GRAVITY := 10.7
## How bouncy: ball on pin, pin on pin, pin on a kickback.
const E_BALL := .72
const E_PIN := .64
const E_WALL := .45
## The pins' pictures' heights (cells) by how far they lean (upright, then
## range_pin_t1..t3), and how much more leaning away than toward the viewer.
const TALL := [.5, .48, .37, .18]
const TALL_YAW := [0.0, .01, .04, 0.0]
## Steps a tick for the pins (their knocks are quick).
const STEPS := 4
## Seconds: the pins must lie still this long to be counted; the longest a ball
## is waited on; from the count to the sweep or a fresh rack.
const STILL := .45
const LONGEST := 5.5
const SWEEP_AFTER := 1.4
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

var dice := RandomNumberGenerator.new()
## Each pin: {n (1..10), x, y (its base), vx, vy, tx, ty (the lean), wx, wy
## (its rate), spin (a lying pin's turn, radians a second), z, vz (a hop),
## gone ("" on the deck, "pit", "gutter", "swept")}.
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
## Where everything on the deck was at the last look (for _settled()).
var last_pose := PackedFloat32Array()
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
		(
			pins
			. append(
				{
					"n": i + 1,
					"x": spot.x,
					"y": spot.y,
					"vx": 0.0,
					"vy": 0.0,
					"tx": 0.0,
					"ty": 0.0,
					"wx": 0.0,
					"wy": 0.0,
					"spin": 0.0,
					"z": 0.0,
					"vz": 0.0,
					"gone": "",
				}
			)
		)
	standing_before = 10
	roll_started = -1.0
	sweep_at = -1.0


static func lean(pin: Dictionary) -> float:
	return Vector2(pin["tx"], pin["ty"]).length()


## Down: off the deck, or leaning past COUNTS.
static func is_down(pin: Dictionary) -> bool:
	return String(pin["gone"]) != "" or lean(pin) > COUNTS


func standing() -> int:
	var n := 0
	for pin: Dictionary in pins:
		if not is_down(pin):
			n += 1
	return n


func pins_down() -> int:
	return 10 - standing()


## Where a pin's head lies over the deck, and its lean's heading.
static func head(pin: Dictionary) -> Vector2:
	var t := Vector2(pin["tx"], pin["ty"])
	var a := t.length()
	if a < .0001:
		return Vector2(pin["x"], pin["y"])
	return Vector2(pin["x"], pin["y"]) + t / a * PIN_LEN * sin(minf(a, LYING))


# ------------------------------------------------------------------ the ball


## A ball has been thrown (the range heard it): its hook from how fast the
## thrower was turning, radians a second.
func thrown(shot, turn: float) -> void:
	ball_uid = shot.uid
	hook = clampf(turn * HOOK_GAIN, -HOOK_MOST, HOOK_MOST)
	in_gutter = false
	touched = false


static func _on_lane(x: float, y: float) -> bool:
	return x > KICKBACK[0] - .5 and x < KICKBACK[1] + .5 and y > CUSHION_Y - .5 and y < FOUL_Y + 1.2


## The ball on the lane this tick: hook, gutter, pit, and what it meets.
func roll_ball(game, shot, dt: float) -> void:
	if not _on_lane(shot.x, shot.y) or shot.z - game.world.elevation(shot.x, shot.y) > .35:
		return
	if roll_started < 0.0 and shot.y < FOUL_Y:
		roll_started = game.clock
		still_since = -1.0
	var speed := Vector2(shot.vx, shot.vy).length()
	if in_gutter or shot.x < BED[0] or shot.x > BED[1]:
		# In the channel: it runs straight down it, past the pins.
		if not in_gutter and shot.y < FOUL_Y:
			in_gutter = true
			game.sound_at("bowling_thud", shot.x, shot.y, .5)
		in_gutter = true
		var channel := (BED[0] + KICKBACK[0]) * .5 if shot.x < 46.5 else (BED[1] + KICKBACK[1]) * .5
		shot.x = lerpf(shot.x, channel, minf(1.0, dt * 12.0))
		shot.vx = 0.0
		shot.vy = -maxf(absf(shot.vy), speed * .9)
	elif shot.y < FOUL_Y - OIL and absf(hook) > .01 and speed > .5:
		# Off the oil the spin bites: the line bends, the speed stays.
		var turn := hook * dt / speed
		var v := Vector2(shot.vx, shot.vy).rotated(turn)
		shot.vx = v.x
		shot.vy = v.y
	if shot.y < PIT_Y:
		# Into the pit: gone from the deck.
		shot.vx = 0.0
		shot.vy = 0.0
		ball_uid = -1
		return
	if in_gutter:
		return
	var at := Vector2(shot.x, shot.y)
	var v_ball := Vector2(shot.vx, shot.vy)
	for pin: Dictionary in pins:
		if String(pin["gone"]) != "":
			continue
		var near := _closest_on(pin, at)
		var gap := at - near
		var reach := BALL_R + PIN_R
		var d := gap.length()
		if d >= reach or d < .00001:
			continue
		var n := gap / d
		var v_pin := _velocity_at(pin, near)
		var closing := (v_ball - v_pin).dot(n)
		# Push them apart, then trade momentum if they are closing.
		at += n * (reach - d) * (1.0 / BALL_MASS) / (1.0 + 1.0 / BALL_MASS)
		if closing < 0.0:
			var j := -(1.0 + E_BALL) * closing / (1.0 / BALL_MASS + 1.0)
			v_ball += n * j / BALL_MASS
			_impulse(pin, near, -n * j, .14)
			if not touched:
				touched = true
				game.sound_at("bowling_hit", pin["x"], pin["y"], .8)
			_clack(near)
	shot.x = at.x
	shot.y = at.y
	shot.vx = v_ball.x
	shot.vy = v_ball.y


# ------------------------------------------------------------------ the pins


## The nearest point of a pin's body to `p`: its base, or along it to its head.
static func _closest_on(pin: Dictionary, p: Vector2) -> Vector2:
	var a := Vector2(pin["x"], pin["y"])
	var b := head(pin)
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 1e-8:
		return a
	return a + ab * clampf((p - a).dot(ab) / len2, 0.0, 1.0)


## The deck-level velocity of a pin's body at point `p` on it: sliding, its
## lean swinging over, a lying pin spinning.
static func _velocity_at(pin: Dictionary, p: Vector2) -> Vector2:
	var v := Vector2(pin["vx"], pin["vy"])
	var base := Vector2(pin["x"], pin["y"])
	var t := Vector2(pin["tx"], pin["ty"])
	var a := t.length()
	var s := (p - base).length()
	if a > .0001 and a < LYING:
		var w := Vector2(pin["wx"], pin["wy"])
		v += t / a * w.dot(t / a) * s * cos(a) * PIN_LEN / maxf(.05, PIN_LEN * sin(a))
	var spin := float(pin["spin"])
	if absf(spin) > .0001:
		var r := p - (base + head(pin)) * .5
		v += Vector2(-r.y, r.x) * spin
	return v


## A knock `j` (mass times cells a second) at point `p` on a pin, from `height`
## up: it slides, leans the way it was knocked (a standing or falling pin), or
## spins (a lying one); a hard one makes it hop.
func _impulse(pin: Dictionary, p: Vector2, j: Vector2, height: float) -> void:
	var a := lean(pin)
	var share := .55 if a < LYING else .85
	pin["vx"] = float(pin["vx"]) + j.x * share
	pin["vy"] = float(pin["vy"]) + j.y * share
	if a < LYING - .01:
		var gain := TIP_GAIN * (.6 + height * 3.0)
		pin["wx"] = float(pin["wx"]) + j.x * gain
		pin["wy"] = float(pin["wy"]) + j.y * gain
		if a < .02:
			# Upright: it starts its lean the way it was struck, a little off.
			var off := j.normalized().rotated(dice.randf_range(-.25, .25)) * .02
			pin["tx"] = float(pin["tx"]) + off.x
			pin["ty"] = float(pin["ty"]) + off.y
	else:
		var r := p - (Vector2(pin["x"], pin["y"]) + head(pin)) * .5
		pin["spin"] = float(pin["spin"]) + (r.x * j.y - r.y * j.x) * 14.0
	if j.length() > 2.6 and float(pin["z"]) <= 0.0:
		pin["vz"] = minf(1.6, (j.length() - 2.6) * .35)


func tick(game, dt: float) -> void:
	clacks = 0
	var h := dt / STEPS
	for _k in STEPS:
		for pin: Dictionary in pins:
			if String(pin["gone"]) == "":
				_step(pin, h)
		_knock_pins()
		for pin: Dictionary in pins:
			if String(pin["gone"]) == "":
				_bounds(pin)
	if clacks > 0:
		game.sound_at("pin_clack", clack_at.x, clack_at.y, minf(1.0, .35 + clacks * .12))
		if clacks >= 4:
			game.sound_at("range_pin_scatter", clack_at.x, clack_at.y, .5)
	_score(game)


func _step(pin: Dictionary, h: float) -> void:
	var t := Vector2(pin["tx"], pin["ty"])
	var w := Vector2(pin["wx"], pin["wy"])
	var a := t.length()
	if a < LYING:
		# The lean: its weight pulls it back short of TIP and over past it.
		var dir := t / a if a > .0001 else Vector2.ZERO
		var pull := G_T * (sin(a) - sin(TIP)) if a > TIP else -G_T * 2.2 * a
		w += dir * pull * h
		if a < TIP:
			w *= exp(-DAMP * h)
		t += w * h
		var na := t.length()
		if na >= LYING:
			# Down: on its belly and head, a little bounce and the rest kept as
			# a slide and a spin.
			t = t / na * LYING
			var radial := w.dot(t / LYING)
			pin["vx"] = float(pin["vx"]) + t.x / LYING * radial * .05
			pin["vy"] = float(pin["vy"]) + t.y / LYING * radial * .05
			var across := w - t / LYING * radial
			pin["spin"] = float(pin["spin"]) + (t.x * across.y - t.y * across.x) * .4
			w = Vector2.ZERO
			_clack(head(pin))
		elif na < .002 and w.length() < .02:
			t = Vector2.ZERO
			w = Vector2.ZERO
	else:
		# Lying: it turns about its middle as it spins.
		var spin := float(pin["spin"])
		if absf(spin) > .001:
			var base := Vector2(pin["x"], pin["y"])
			var mid := (base + head(pin)) * .5
			var turn := spin * h
			var nb := mid + (base - mid).rotated(turn)
			pin["x"] = nb.x
			pin["y"] = nb.y
			t = t.rotated(turn)
			pin["spin"] = spin * exp(-2.4 * h)
	pin["tx"] = t.x
	pin["ty"] = t.y
	pin["wx"] = w.x
	pin["wy"] = w.y
	# Sliding, or a hop in the air.
	var v := Vector2(pin["vx"], pin["vy"])
	var z := float(pin["z"])
	if z > 0.0 or float(pin["vz"]) > 0.0:
		pin["vz"] = float(pin["vz"]) - GRAVITY * h
		z = maxf(0.0, z + float(pin["vz"]) * h)
		if z <= 0.0:
			pin["vz"] = 0.0
		pin["z"] = z
	else:
		var friction := (SLIDE if a < LYING else SLIDE_DOWN) * h
		var speed := v.length()
		v = Vector2.ZERO if speed <= friction else v * (1.0 - friction / speed)
	pin["x"] = float(pin["x"]) + v.x * h
	pin["y"] = float(pin["y"]) + v.y * h
	pin["vx"] = v.x
	pin["vy"] = v.y


## Pin on pin: each pair's bodies (discs or capsules) pushed apart, and if
## they are closing, the knock shared out.
func _knock_pins() -> void:
	for i in pins.size():
		var p: Dictionary = pins[i]
		if String(p["gone"]) != "":
			continue
		for k in range(i + 1, pins.size()):
			var q: Dictionary = pins[k]
			if String(q["gone"]) != "":
				continue
			var pair := _nearest_pair(p, q)
			var a: Vector2 = pair[0]
			var b: Vector2 = pair[1]
			var gap := b - a
			var d := gap.length()
			if d >= PIN_R * 2.0 or d < .00001:
				continue
			var n := gap / d
			var push := (PIN_R * 2.0 - d) * .5
			p["x"] = float(p["x"]) - n.x * push
			p["y"] = float(p["y"]) - n.y * push
			q["x"] = float(q["x"]) + n.x * push
			q["y"] = float(q["y"]) + n.y * push
			var closing := (_velocity_at(q, b) - _velocity_at(p, a)).dot(n)
			if closing < 0.0:
				var j := -(1.0 + E_PIN) * closing * .5
				_impulse(q, b, n * j, _height_at(p, a))
				_impulse(p, a, -n * j, _height_at(q, b))
				if j > .25:
					_clack((a + b) * .5)


## How high up a pin its body is at `p` (a falling pin's head comes down from
## above).
static func _height_at(pin: Dictionary, p: Vector2) -> float:
	var a := lean(pin)
	var s := (p - Vector2(pin["x"], pin["y"])).length()
	if a < .0001:
		return .14
	return clampf(s / maxf(.02, sin(a)) * cos(a), .05, .4)


## The closest points of two pins' bodies (each a point or a segment).
static func _nearest_pair(p: Dictionary, q: Dictionary) -> Array:
	var a0 := Vector2(p["x"], p["y"])
	var a1 := head(p)
	var b0 := Vector2(q["x"], q["y"])
	var b1 := head(q)
	var d1 := a1 - a0
	var d2 := b1 - b0
	var r := a0 - b0
	var aa := d1.length_squared()
	var ee := d2.length_squared()
	var ff := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if aa < 1e-8 and ee < 1e-8:
		return [a0, b0]
	if aa < 1e-8:
		t = clampf(ff / ee, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if ee < 1e-8:
			s = clampf(-c / aa, 0.0, 1.0)
		else:
			var bb := d1.dot(d2)
			var denom := aa * ee - bb * bb
			s = clampf((bb * ff - c * ee) / denom, 0.0, 1.0) if denom > 1e-10 else 0.0
			t = (bb * s + ff) / ee
			if t < 0.0:
				t = 0.0
				s = clampf(-c / aa, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((bb - c) / aa, 0.0, 1.0)
	return [a0 + d1 * s, b0 + d2 * t]


func _bounds(pin: Dictionary) -> void:
	var base := Vector2(pin["x"], pin["y"])
	var tip := head(pin)
	# The kickbacks: whichever end is past one is pushed back, and the slide
	# comes off it.
	for end: Vector2 in [base, tip]:
		if end.x < KICKBACK[0] + PIN_R:
			var dx: float = KICKBACK[0] + PIN_R - end.x
			pin["x"] = float(pin["x"]) + dx
			if float(pin["vx"]) < 0.0:
				pin["vx"] = -float(pin["vx"]) * E_WALL
				_clack(end)
		elif end.x > KICKBACK[1] - PIN_R:
			var dx2: float = KICKBACK[1] - PIN_R - end.x
			pin["x"] = float(pin["x"]) + dx2
			if float(pin["vx"]) > 0.0:
				pin["vx"] = -float(pin["vx"]) * E_WALL
				_clack(end)
	base = Vector2(pin["x"], pin["y"])
	var mid := (base + head(pin)) * .5
	if mid.y < PIT_Y:
		pin["gone"] = "pit"
	elif mid.x < BED[0] - .02 or mid.x > BED[1] + .02:
		if lean(pin) > COUNTS or absf(float(pin["vx"])) + absf(float(pin["vy"])) > .1:
			pin["gone"] = "gutter"
	elif base.y > FOUL_Y:
		pin["y"] = FOUL_Y
		pin["vy"] = -absf(float(pin["vy"])) * E_WALL


func _clack(at: Vector2) -> void:
	clacks += 1
	clack_at = at


# ------------------------------------------------------------------ scoring


## Still: nothing on the deck moved since the last look (a pin may lie
## leaning on another; it counts as down past COUNTS).
func _settled() -> bool:
	var pose := PackedFloat32Array()
	for pin: Dictionary in pins:
		pose.append_array(
			[pin["x"], pin["y"], pin["tx"], pin["ty"], pin["z"], 1.0 if pin["gone"] == "" else 0.0]
		)
	var still := last_pose.size() == pose.size()
	if still:
		for i in pose.size():
			if absf(pose[i] - last_pose[i]) > .0025:
				still = false
				break
	last_pose = pose
	return still


func _ball_live(game) -> bool:
	if ball_uid < 0:
		return false
	for shot in game.shots:
		if shot.uid == ball_uid:
			return true
	ball_uid = -1
	return false


func _score(game) -> void:
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


func _count(game) -> void:
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
		return sheet.size() >= 2 or (sheet.size() == 1 and int(sheet[0]) == 10)
	if sheet.size() >= 3:
		return true
	if sheet.size() == 2:
		return int(sheet[0]) + int(sheet[1]) < 10
	return false


## The pinsetter: deadwood out and the standing pins stood up where they are,
## or a fresh rack.
func _sweep(game) -> void:
	sweep_at = -1.0
	game.sound_at("range_pen_gate", L.PIN_HEAD.x, L.PIN_HEAD.y - .8, .45)
	if sweep_full:
		rack()
		return
	for pin: Dictionary in pins:
		if is_down(pin):
			pin["gone"] = "swept"
		else:
			for key in ["vx", "vy", "tx", "ty", "wx", "wy", "spin", "z", "vz"]:
				pin[key] = 0.0
	standing_before = standing()


## A split after the first ball: the head pin down and the pins left standing
## in two or more bunches that touch nothing of each other ("7-10").
func split_name() -> String:
	var up: Array = []
	for pin: Dictionary in pins:
		if not is_down(pin):
			up.append(int(pin["n"]))
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
		if int(sheet[0]) == 10 and f < 9:
			total += 10 + _ball(balls, i + 1) + _ball(balls, i + 2)
			i += 1
		elif sheet.size() >= 2 and int(sheet[0]) + int(sheet[1]) >= 10 and f < 9:
			total += 10 + _ball(balls, i + 2)
			i += 2
		else:
			for b: int in sheet:
				total += b
			i += sheet.size()
	return total


static func _ball(balls: Array, i: int) -> int:
	return int(balls[i]) if i < balls.size() else 0


## The sheet as a bowler writes it: X a strike, / a spare, - a miss.
func sheet_text(last := 5) -> String:
	var marks: PackedStringArray = []
	for f in 10:
		var sheet: Array = frames[f]
		if sheet.is_empty():
			break
		var text := ""
		for k in sheet.size():
			var b := int(sheet[k])
			var spare: bool = (
				k > 0
				and int(sheet[k - 1]) != 10
				and int(sheet[k - 1]) + b == 10
				and not (k == 2 and int(sheet[0]) + int(sheet[1]) != 10 and int(sheet[1]) != 10)
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
		if String(pin["gone"]) != "" or lean(pin) > COUNTS:
			continue
		var hit: Vector2 = crossing.call(s, e, pin["x"], pin["y"], .2, .2, .08)
		if hit.x >= 0.0 and hit.x < best_t:
			best_t = hit.x
			best = pin
	return {} if best.is_empty() else {"pin": best, "t": best_t}


## A round struck a pin: a hard knock high up, the way it flew.
func shot_knock(game, pin: Dictionary, direction: Vector2, damage: float) -> void:
	var j := direction.normalized() * clampf(damage / 18.0, .8, 4.0)
	_impulse(pin, Vector2(pin["x"], pin["y"]), j, .3)
	_clack(Vector2(pin["x"], pin["y"]))
	if roll_started < 0.0:
		roll_started = game.clock
		still_since = -1.0


## A blast at (x, y): pins within reach are thrown off it, those near hop.
func blast(game, x: float, y: float) -> void:
	var any := false
	for pin: Dictionary in pins:
		if String(pin["gone"]) != "":
			continue
		var away := Vector2(pin["x"] - x, pin["y"] - y)
		var d := away.length()
		if d > 3.2:
			continue
		var power := (3.2 - d) * 2.2
		var j := (away / maxf(d, .05)).rotated(dice.randf_range(-.4, .4)) * power
		_impulse(pin, Vector2(pin["x"], pin["y"]), j, .25)
		pin["vz"] = maxf(float(pin["vz"]), power * .3)
		any = true
	if any and roll_started < 0.0:
		roll_started = game.clock
		still_since = -1.0


# ------------------------------------------------------------------ looks


## The pins' sprites, each picture picked by how far it leans and which way
## its head lies to the viewer at (vx, vy) (tools/art: range_pin_t<k>_<j>).
func sprites(game, eye: Vector2) -> Array:
	var out: Array = []
	for pin: Dictionary in pins:
		if String(pin["gone"]) in ["pit", "swept"]:
			continue
		var base := Vector2(pin["x"], pin["y"])
		if not game.in_view(base.x, base.y, .6):
			continue
		var a := lean(pin)
		var floor_z: float = game.world.elevation(base.x, base.y) + float(pin["z"])
		if String(pin["gone"]) == "gutter":
			floor_z -= .06
		if a < .2:
			out.append(Renderer.Sprite.new(base.x, base.y, "town_range_pin", .5, floor_z))
			continue
		var t := Vector2(pin["tx"], pin["ty"]) / a
		var k := 1 if a < .62 else 2 if a < 1.25 else 3
		# The view's right, and the head's heading measured from it toward
		# away from the viewer; heads to the left are a flip.
		var look := (base - eye).angle()
		var yaw := wrapf(look + PI / 2.0 - t.angle(), -PI, PI)
		var flip := false
		if absf(yaw) > PI / 2.0:
			flip = true
			yaw = wrapf(PI - yaw, -PI, PI)
		var j := clampi(roundi((rad_to_deg(yaw) + 90.0) / 30.0), 0, 6)
		var name := "town_range_pin_t%d_%d" % [k, j]
		# Its height on screen: the picture's, at the standing pin's scale (a
		# pin leaning away stands a little taller in its picture than one
		# leaning toward the viewer).
		var tall: float = float(TALL[k]) + float(TALL_YAW[k]) * sin(yaw)
		# The picture's middle sits over the middle of the pin's body.
		var mid := (base + head(pin)) * .5
		var sprite := Renderer.Sprite.new(mid.x, mid.y, name, tall, floor_z)
		sprite.flip = flip
		out.append(sprite)
	return out
