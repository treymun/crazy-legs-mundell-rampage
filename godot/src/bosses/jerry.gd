## JERRY JONES, Hickston's second boss: the county's old linebacker, out of
## the corn once the sheriff falls, throwing footballs from his own field
## (enemies.cfg [jerry]).
##
##   weak spot   his bad knees: a hit low on his legs counts KNEES (a blast at
##               his feet BLAST_KNEES); his helmet takes a hit at HELMET.
##   phase 3     the blitz: he digs in (a lane on the ground shows his line),
##               then charges it at BLITZ_SPEED; caught, the player takes a hit
##               and a shove; if he meets a goalpost, the bleachers or a wall
##               he rings his own bell (BELL seconds stunned, stars round his
##               helmet). Tyre stacks he runs through roll their tyres. The
##               scoreboard shorts out: the floodlights cut and the bleachers
##               burn.
##   HOG WILD    the onside kick: once he is fightin' mad, every KICK_EVERY
##               throws he punts a flaming pigskin that bursts where it lands.
extends "res://src/bosses/arena_moves.gd"

const KNEE_LINE := .3
const KNEES := 2.0
const BLAST_KNEES := 1.5
const HELMET_LINE := .82
const HELMET := .6
const BLITZ_EVERY := 5.5
const BLITZ_WARN := .9
const BLITZ_SPEED := 7.2
const BLITZ_REACH := 10.0
const BLITZ_HIT := 20.0
const BELL := 1.7
const KICK_EVERY := 3


func fight_start(e: Enemy, _game) -> void:
	e.set_meta("kick_after", e.attacks + KICK_EVERY)


func phase_changed(e: Enemy, game, phase: int) -> void:
	if phase != 3:
		return
	e.set_meta("blitz_at", game.clock + .8)
	var f = arena(game)
	if f == null:
		return
	var board = f.spec("jerry").get("scoreboard")
	if board is Array:
		var bx := float(board[0])
		var by := float(board[1])
		game.burst(bx, by, game.world.elevation(bx, by) + 2.4, "spark", 30, 2.8)
		game.sound_at("arm_impact", bx, by, 1.0)
		game.sound_at("metal_down", bx, by, .8)
	for row in f.spec("jerry").get("bleachers", []):
		var x := float(row[0])
		while x <= float(row[2]):
			f.fire(x, float(row[1]), .7, 45.0)
			x += 1.6
	game.message("THE SCOREBOARD SHORTED OUT! THE BLEACHERS ARE BURNIN'!", 2.8)


func tick(e: Enemy, dt: float, game) -> bool:
	if not fighting(e, game):
		return false
	if e.has_meta("blitz"):
		if e.stun > 0.0:
			# Staggered out of it.
			_end_charge(e, 0.0)
			return false
		_charge(e, game, dt)
		return true
	if run_own(e, game, dt):
		return true
	if not ready(e):
		return false
	var p = game.player
	var gap := Vector2(p.x - e.x, p.y - e.y).length()
	if (
		e.boss_phase >= 3
		and due(e, game, "blitz_at")
		and gap > 2.2
		and gap < BLITZ_REACH + 1.0
		and sees_player(e, game)
	):
		e.set_meta("blitz_at", game.clock + BLITZ_EVERY * (.75 if hog_wild(game) else 1.0))
		begin_own(e, game, "blitz", BLITZ_WARN)
		e.set_meta("blitz_line", e.angle)
		game.sound_at("whistle", e.x, e.y, 1.0)
		say_once(e, game, "blitz_told", "HE'S FIXIN' TO BLITZ! SIDESTEP HIM!")
		return true
	if (
		hog_wild(game)
		and e.boss_phase >= 2
		and e.attacks >= int(e.get_meta("kick_after", 1 << 30))
		and sees_player(e, game)
	):
		e.set_meta("kick_after", e.attacks + KICK_EVERY)
		var mark: Array = [p.x + p.vx * .8, p.y + p.vy * .8, p.eye]
		begin_own(e, game, "kick", .65, mark)
		return true
	return false


func act(e: Enemy, game, name: String) -> void:
	if name == "blitz":
		var line := float(e.get_meta("blitz_line", e.angle))
		e.angle = line
		e.set_meta("blitz", BLITZ_REACH)
		game.sound_at("jerry_rage", e.x, e.y, .8)
	elif name == "kick":
		var f = arena(game)
		var p = game.player
		if f != null:
			var eye: float = game.world.elevation(e.x, e.y) + .5
			f.lob(
				e.x + cos(e.angle) * .6,
				e.y + sin(e.angle) * .6,
				eye,
				p.x + p.vx * .8,
				p.y + p.vy * .8,
				1.15,
				"pigskin_bomb",
				"fx_football",
				.32
			)
		game.sound_at("football_throw", e.x, e.y, 1.0)
		say_once(e, game, "kick_told", "ONSIDE KICK! THAT BALL'S ON FIRE!")
		e.recovery = .45
		e.cooldown = maxf(e.cooldown, .9)


## The charge: down his line until he meets the player, something solid or
## runs out of field.
func _charge(e: Enemy, game, dt: float) -> void:
	var left := float(e.get_meta("blitz"))
	var step := BLITZ_SPEED * dt
	var ox := e.x
	var oy := e.y
	game.move_actor(e, cos(e.angle) * step, sin(e.angle) * step, e.radius)
	var moved := Vector2(e.x - ox, e.y - oy).length()
	e.gait += moved * 6.0
	e.last_stride = e.pose
	left -= moved
	var f = arena(game)
	if f != null:
		f.knock_tyres(e.x, e.y, 1.3)
	var pieces = game.features.get("breakables")
	if pieces != null:
		var i: int = pieces.touch(e.x, e.y, game.world.elevation(e.x, e.y) + .6, e.radius)
		if i >= 0:
			pieces.strike(i, 200.0, cos(e.angle), sin(e.angle))
	if int(e.pose * 8.0) % 2 == 0:
		game.burst(e.x, e.y, game.world.elevation(e.x, e.y) + .1, "dust", 2, .8)
	var p = game.player
	if Vector2(p.x - e.x, p.y - e.y).length() < e.radius + .42 and p.air < .5:
		game.damage(BLITZ_HIT, [e.x, e.y], "SACKED")
		game.move_actor(p, cos(e.angle) * 1.1, sin(e.angle) * 1.1, GameState.PLAYER_RADIUS)
		game.shake = minf(1.0, game.shake + .6)
		game.sound_at("body_thud", p.x, p.y, 1.0)
		_end_charge(e, .6)
		return
	if moved < step * .45:
		# Into something solid: he rings his own bell.
		_end_charge(e, 0.0)
		e.stun = BELL
		e.flinch = BELL
		e.set_meta("bell_until", game.clock + BELL)
		game.shake = minf(1.0, game.shake + .45)
		game.sound_at("body_thud", e.x, e.y, 1.0)
		game.sound_at("metal_down", e.x, e.y, .7)
		say_once(e, game, "bell_told", "JERRY RANG HIS OWN BELL! GO FOR THE KNEES!")
		return
	if left <= 0.0:
		_end_charge(e, .5)
		return
	e.set_meta("blitz", left)


func _end_charge(e: Enemy, rest: float) -> void:
	e.remove_meta("blitz")
	e.recovery = maxf(e.recovery, rest)
	e.cooldown = maxf(e.cooldown, .8)


func weak_spot(e: Enemy, game, hit: Vector3, _from: Vector2, how: String) -> float:
	var up := body_height(e, game, hit)
	if how == "blast":
		return BLAST_KNEES if up < .25 else 1.0
	if how == "energy" or how == "fire":
		return 1.0
	if up < KNEE_LINE:
		return KNEES
	if up > HELMET_LINE:
		return guarded(e, HELMET)
	return guarded(e, 1.0)


func telegraph(e: Enemy, game) -> Array:
	if own(e) != "blitz":
		return []
	var line := float(e.get_meta("blitz_line", e.angle))
	var out := lane_marks(game, e.x, e.y, line, BLITZ_REACH, .55)
	# Dust kicked up where he digs in.
	var dig := Renderer.Sprite.new(
		e.x - cos(line) * .4,
		e.y - sin(line) * .4,
		"fx_puff_%d" % (int(game.clock * 10.0) % 4),
		.5,
		game.world.elevation(e.x, e.y)
	)
	dig.translucent = true
	out.append(dig)
	return out


func looks(e: Enemy, game) -> Array:
	var out: Array = []
	if game.clock >= float(e.get_meta("bell_until", -1.0)):
		return out
	# Stars round his helmet.
	var top: float = game.world.elevation(e.x, e.y) + e.height * e.variant + .05
	for k in 3:
		var a: float = game.clock * 6.0 + k * TAU / 3.0
		var star := Renderer.Sprite.new(
			e.x + cos(a) * .32, e.y + sin(a) * .32, "fx_glint_%d" % (k % 2), .18, top
		)
		star.glow = true
		out.append(star)
	return out


func dying(e: Enemy, game) -> void:
	e.remove_meta("blitz")
	var f = arena(game)
	if f != null:
		f.knock_tyres(e.x, e.y, 3.0)
