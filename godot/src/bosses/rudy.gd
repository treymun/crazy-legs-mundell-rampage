## RUDY RACKET, the fair's last boss: the ringmaster of the big top, a bass
## drum on his belly and two brass horns over his shoulders, raking the ring
## with horn blasts (enemies.cfg [rudy], enemies.gd special_attack).
##
##   weak spot   the bass drum, hit from in front low on his belly (DRUM); the
##               horns themselves while he winds up and blows (HORNS), high.
##   horn stacks once he is fightin' mad the PA horn stacks round the ring
##               fire down their lanes at the player in turn (a lane on the
##               ground warns): every STACK_MAD seconds, STACK_DESPERATE in
##               phase three. A lane that catches Rudy knocks him about too.
##   phase 3     the grand finale: a ring of horn blasts every way at once, the
##               spokes on the ground showing the gaps, a second ring after it
##               turned half a step. The spotlights sweep the ring.
##   HOG WILD    balloon bombs: every BALLOONS_EVERY blasts (fightin' mad) he
##               lets two bunches go that drift after the player and burst;
##               shoot them down.
extends "res://src/bosses/arena_moves.gd"

const DRUM := 1.75
const HORNS := 2.25
const STACK_MAD := 7.0
const STACK_DESPERATE := 3.6
const FINALE_EVERY := 6.5
const FINALE_WARN := 1.1
const FINALE_SHOTS := 16
const BALLOONS_EVERY := 3


func fight_start(e: Enemy, _game) -> void:
	e.set_meta("balloons_after", e.attacks + BALLOONS_EVERY)


func phase_changed(e: Enemy, game, phase: int) -> void:
	if phase == 2:
		e.set_meta("stack_at", game.clock + 2.0)
	elif phase == 3:
		e.set_meta("finale_at", game.clock + .9)
		e.set_meta("stack_at", game.clock + 2.5)
		game.message("THE GRAND FINALE! THE SPOTLIGHTS ARE ON YOU!", 2.6)
		game.sound.play("crowd_cheer", .8)


func tick(e: Enemy, dt: float, game) -> bool:
	if not fighting(e, game):
		return false
	var f = arena(game)
	if f != null and e.boss_phase >= 2:
		_stacks(e, game, f)
		if e.boss_phase >= 3:
			_spotlights(f, game)
	if due(e, game, "wave2_at"):
		e.remove_meta("wave2_at")
		_ring(e, game, .5)
	if run_own(e, game, dt):
		return true
	if not ready(e) or e.volley > 0:
		return false
	if e.boss_phase >= 3 and due(e, game, "finale_at"):
		e.set_meta("finale_at", game.clock + FINALE_EVERY * (.8 if hog_wild(game) else 1.0))
		begin_own(e, game, "finale", FINALE_WARN)
		# The gap opens on the far side from the player: it must be run for.
		e.set_meta("finale_gap", FINALE_SHOTS / 2 - 1)
		game.sound_at("rudy_warn", e.x, e.y, 1.0)
		say_once(e, game, "finale_told", "HE'S BLOWIN' EVERY WHICH WAY! FIND THE GAP!")
		return true
	if (
		hog_wild(game)
		and e.boss_phase >= 2
		and e.attacks >= int(e.get_meta("balloons_after", 1 << 30))
	):
		e.set_meta("balloons_after", e.attacks + BALLOONS_EVERY)
		begin_own(e, game, "balloons", .5)
		return true
	return false


func act(e: Enemy, game, name: String) -> void:
	if name == "finale":
		_ring(e, game, 0.0)
		e.set_meta("wave2_at", game.clock + .5)
		e.recovery = .9
		e.cooldown = maxf(e.cooldown, 1.4)
	elif name == "balloons":
		var f = arena(game)
		if f != null:
			var floor_z: float = game.world.elevation(e.x, e.y)
			for side: float in [-1.0, 1.0]:
				var a := e.angle + side * 1.2
				f.balloon(
					e.x + cos(a) * .7,
					e.y + sin(a) * .7,
					floor_z + 1.4,
					"balloon_bomb",
					"town_balloons",
					7.0
				)
		game.sound_at("rudy_horn", e.x, e.y, .6)
		say_once(e, game, "balloon_told", "BALLOON BOMBS! SHOOT 'EM DOWN!")
		e.recovery = .4


## The bearings of the finale's ring, `turn` of a step round.
func _bearings(e: Enemy, turn: float) -> Array:
	var out: Array = []
	var gap := int(e.get_meta("finale_gap", 0))
	for k in FINALE_SHOTS:
		if k == gap or k == (gap + 1) % FINALE_SHOTS or k == (gap + 2) % FINALE_SHOTS:
			continue
		out.append(e.angle + (k + turn) * TAU / FINALE_SHOTS)
	return out


func _ring(e: Enemy, game, turn: float) -> void:
	var eye: float = game.world.elevation(e.x, e.y) + 1.05
	for a: float in _bearings(e, turn):
		game.launch(
			e.x + cos(a) * .45, e.y + sin(a) * .45, eye, a, 6.2, "rudy_horn", 0.0, true, 8, 1.5
		)
	game.sound_at("rudy_horn", e.x, e.y, 1.0)
	game.shake = minf(1.0, game.shake + .25)


## The horn stacks round the ring: the next in turn fires its lane at the player.
func _stacks(e: Enemy, game, f) -> void:
	if not due(e, game, "stack_at"):
		return
	var every := STACK_DESPERATE if e.boss_phase >= 3 else STACK_MAD
	e.set_meta("stack_at", game.clock + every * (.8 if hog_wild(game) else 1.0))
	var stacks: Array = f.spec("rudy").get("horns", [])
	if stacks.is_empty():
		return
	var p = game.player
	var turn := int(e.get_meta("stack_turn", 0))
	for tries in stacks.size():
		var s: Array = stacks[(turn + tries) % stacks.size()]
		var sx := float(s[0])
		var sy := float(s[1])
		var d := Vector2(p.x - sx, p.y - sy).length()
		if d > 15.0 or not game.world.visible(sx, sy, p.x, p.y):
			continue
		e.set_meta("stack_turn", turn + tries + 1)
		f.lane(sx, sy, atan2(p.y - sy, p.x - sx), d + 3.0, 1.0)
		game.sound_at("rudy_warn", sx, sy, .7)
		say_once(e, game, "stack_told", "THE HORN STACKS! STAY OFF THE LANES!")
		return


## Phase three: two spotlights sweeping the ring.
func _spotlights(f, game) -> void:
	var ring = f.spec("rudy").get("ring")
	if not (ring is Array):
		return
	var cx := float(ring[0])
	var cy := float(ring[1])
	for k in 2:
		var a: float = game.clock * (.9 if k == 0 else -.7) + k * PI
		var x := cx + cos(a) * 4.0
		var y := cy + sin(a) * 3.0
		var tint := Color(1, .95, .8) if k == 0 else Color(1, .3, .25)
		f.light(x, y, game.world.elevation(x, y) + 1.6, 3.4, tint, 1.3)


func weak_spot(e: Enemy, game, hit: Vector3, from: Vector2, how: String) -> float:
	if how == "blast" or how == "energy" or how == "fire":
		return 1.0
	var up := body_height(e, game, hit)
	var off := off_facing(e, from)
	if up > .68 and (e.windup > 0.0 or e.volley > 0):
		return HORNS
	if up > .2 and up < .48 and off < 1.3:
		return DRUM
	return guarded(e, 1.0)


func telegraph(e: Enemy, game) -> Array:
	if own(e) != "finale":
		return []
	var out: Array = []
	for a: float in _bearings(e, 0.0):
		out.append_array(lane_marks(game, e.x, e.y, a, 4.5, .16))
	return out


func looks(e: Enemy, game) -> Array:
	if e.boss_phase < 3 and own(e) != "finale":
		return []
	# The horns glowing hot.
	var top: float = game.world.elevation(e.x, e.y) + e.height * .86
	var out: Array = []
	for side: float in [-1.0, 1.0]:
		var a := e.angle + side * PI / 2.0
		var glint := Renderer.Sprite.new(
			e.x + cos(a) * .3,
			e.y + sin(a) * .3,
			"fx_glint_%d" % (int(game.clock * 8.0) % 2),
			.2,
			top
		)
		glint.glow = true
		out.append(glint)
	return out


func dying(e: Enemy, game) -> void:
	e.remove_meta("wave2_at")
	game.burst(e.x, e.y, game.world.elevation(e.x, e.y) + 1.2, "spark", 16, 2.2)
