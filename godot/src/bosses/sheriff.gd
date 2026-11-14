## THE ALIEN SHERIFF, Hickston's first boss: a grey in a tin star who holds
## the rodeo pen the saucer came down in, at the top of town, and spits
## plasma (enemies.cfg [boss]).
##
##   weak spot   the ray gun's power pack on his back: a hit from behind counts
##               PACK, from the side high on the shoulder SHOULDER.
##   the vent    once he is fightin' mad, every VENT_EVERY shots the pack
##               overheats and he turns his back to vent it for VENT seconds:
##               the moment to get behind him.
##   phase 3     the saucer strike: he calls the wreck's guns down on the
##               player, rings closing on STRIKES spots then bolts from the sky
##               (shots.cfg saucer_strike; they burn him as well), and vents
##               after each call. The reactor goes critical: the floodlights
##               cut, fire rings the wreck, the pen glows red.
##   HOG WILD    the plasma ring: every RING_EVERY shots (fightin' mad) a ring
##               of bolts every way at once, a gap to slip through.
extends "res://src/bosses/arena_moves.gd"

const BACK := 1.95
const PACK := 2.0
const SHOULDER := 1.5
const VENT := 1.4
const VENT_EVERY := 3
const STRIKE_EVERY := 5.2
const STRIKE_CALL := .55
const STRIKE_WARN := 1.15
const STRIKES := 5
const RING_EVERY := 4
const RING_SHOTS := 14


func fight_start(e: Enemy, _game) -> void:
	e.set_meta("vent_after", e.attacks + VENT_EVERY + 1)
	e.set_meta("ring_after", e.attacks + RING_EVERY)


func phase_changed(e: Enemy, game, phase: int) -> void:
	if phase == 2:
		e.set_meta("vent_after", e.attacks + 1)
	if phase != 3:
		return
	e.set_meta("strike_at", game.clock + 1.4)
	game.message("THE SAUCER'S REACTOR IS GOIN' CRITICAL!", 2.6)
	game.sound_at("saucer_charge", e.x, e.y, 1.0)
	var f = arena(game)
	var wreck = f.spec("boss").get("wreck") if f != null else null
	if wreck is Array:
		var wx := float(wreck[0])
		var wy := float(wreck[1])
		for k in 9:
			var a := k * TAU / 9.0
			f.fire(wx + cos(a) * 2.7, wy + sin(a) * 2.3, .75, 60.0)
		game.burst(wx, wy, game.world.elevation(wx, wy) + 1.2, "plasma", 24, 2.6)


func tick(e: Enemy, dt: float, game) -> bool:
	if not fighting(e, game):
		return false
	var f = arena(game)
	if f != null and e.boss_phase >= 3:
		_reactor(f, game)
	if game.clock < float(e.get_meta("vent_until", -1.0)):
		# Venting: back turned, the pack hissing.
		var p = game.player
		e.angle = atan2(e.y - p.y, e.x - p.x)
		e.windup = 0.0
		e.aim_mark = null
		if f != null:
			var pack := _pack(e, game)
			f.light(pack.x, pack.y, pack.z, 2.4, Color(.5, 1, .55), .9)
		return true
	if run_own(e, game, dt):
		return true
	if not ready(e):
		return false
	if e.boss_phase >= 3 and due(e, game, "strike_at") and sees_player(e, game):
		var hog := hog_wild(game)
		e.set_meta("strike_at", game.clock + STRIKE_EVERY * (.75 if hog else 1.0))
		begin_own(e, game, "strike", STRIKE_CALL)
		game.sound_at("saucer_charge", e.x, e.y, .9)
		return true
	if e.boss_phase >= 2 and e.attacks >= int(e.get_meta("vent_after", 1 << 30)):
		_vent(e, game)
		return true
	if hog_wild(game) and e.boss_phase >= 2 and e.attacks >= int(e.get_meta("ring_after", 1 << 30)):
		e.set_meta("ring_after", e.attacks + RING_EVERY)
		begin_own(e, game, "ring", .8, [e.x, e.y, 1.0])
		game.sound_at("sheriff_siren", e.x, e.y, 1.0)
		return true
	return false


func act(e: Enemy, game, name: String) -> void:
	if name == "strike":
		_call_strike(e, game)
		# The call overheats the pack: he vents right after.
		e.set_meta("vent_after", e.attacks)
		e.recovery = .3
	elif name == "ring":
		_ring(e, game)
		e.recovery = .5
		e.cooldown = maxf(e.cooldown, 1.0)


## The pack overheats: back turned for VENT seconds.
func _vent(e: Enemy, game) -> void:
	e.set_meta("vent_until", game.clock + VENT)
	e.set_meta("vent_after", e.attacks + VENT_EVERY)
	e.cooldown = maxf(e.cooldown, VENT + .4)
	game.sound_at("arm_vent", e.x, e.y, 1.0)
	game.sound_at("pressure_vent", e.x, e.y, .7)
	say_once(e, game, "vent_told", "HIS PACK'S VENTIN'! GIT BEHIND HIM!")


## Rings close on the player's spot (and where they are headed) and round it,
## then the bolts come down.
func _call_strike(e: Enemy, game) -> void:
	var f = arena(game)
	if f == null:
		return
	var p = game.player
	var lead := Vector2(p.x + p.vx * .55, p.y + p.vy * .55)
	var spots: Array = [Vector2(p.x, p.y)]
	if lead.distance_to(Vector2(p.x, p.y)) > .6:
		spots.append(lead)
	var turn: float = game.rng.random() * TAU
	var count := STRIKES + (3 if hog_wild(game) else 0)
	var k := 0
	while spots.size() < count:
		var ring := 2.4 if k < 4 else 4.0
		var a := turn + k * TAU / 4.0 + (.4 if k >= 4 else 0.0)
		spots.append(Vector2(p.x + cos(a) * ring, p.y + sin(a) * ring))
		k += 1
	for i in spots.size():
		var at: Vector2 = spots[i]
		if not game.world.blocked(at.x, at.y, .2):
			f.strike(at.x, at.y, STRIKE_WARN + i * .1, "saucer_strike")
	game.sound_at("sheriff_siren", e.x, e.y, 1.0)
	say_once(e, game, "strike_told", "HE'S CALLIN' DOWN THE SAUCER! MOVE!")


## HOG WILD: bolts every way at once, a gap left on one side.
func _ring(e: Enemy, game) -> void:
	var eye: float = game.world.stand(e) + e.height * .55
	var gap := int(game.rng.random() * RING_SHOTS)
	for k in RING_SHOTS:
		if k == gap or k == (gap + 1) % RING_SHOTS:
			continue
		var a := e.angle + k * TAU / RING_SHOTS
		game.launch(
			e.x + cos(a) * (e.radius + .1),
			e.y + sin(a) * (e.radius + .1),
			eye,
			a,
			4.6,
			"plasma",
			0.0,
			true,
			11,
			-1.0,
			e.get_instance_id()
		)
	game.sound_at("sheriff_shot", e.x, e.y, 1.0)


## The wreck's reactor in phase three: a red pulse over the pen.
func _reactor(f, game) -> void:
	var wreck = f.spec("boss").get("wreck")
	if not (wreck is Array):
		return
	var wx := float(wreck[0])
	var wy := float(wreck[1])
	var beat := .5 + .5 * sin(game.clock * 5.0)
	f.light(wx, wy, game.world.elevation(wx, wy) + 1.4, 7.5, Color(1, .25, .18), .6 + 1.0 * beat)


## Where the pack is: on his back, high.
func _pack(e: Enemy, game) -> Vector3:
	var floor_z: float = game.world.stand(e)
	return Vector3(
		e.x - cos(e.angle) * (e.radius * .6),
		e.y - sin(e.angle) * (e.radius * .6),
		floor_z + e.height * .62
	)


func weak_spot(e: Enemy, game, hit: Vector3, from: Vector2, how: String) -> float:
	if how == "blast" or how == "energy" or how == "fire":
		return 1.0
	var off := off_facing(e, from)
	if off > BACK:
		return PACK
	if off > 1.35 and body_height(e, game, hit) > .55:
		return SHOULDER
	return guarded(e, 1.0)


func telegraph(e: Enemy, game) -> Array:
	if own(e) == "strike":
		# Arms up to the sky: a column of light over him.
		var col := Renderer.Sprite.new(
			e.x, e.y, "fx_beam_column", 3.0, game.world.stand(e) + e.height * .8
		)
		col.glow = true
		col.translucent = true
		return [col]
	return []


func looks(e: Enemy, game) -> Array:
	var out: Array = []
	var venting: bool = game.clock < float(e.get_meta("vent_until", -1.0))
	if not venting and e.boss_phase < 3:
		return out
	var pack := _pack(e, game)
	if venting:
		for k in 3:
			var age := fposmod(game.clock * 1.6 + k / 3.0, 1.0)
			var puff := Renderer.Sprite.new(
				pack.x - cos(e.angle) * age * .3,
				pack.y - sin(e.angle) * age * .3,
				"fx_steam_%d" % mini(3, int(age * 4.0)),
				.5 + age * .6,
				pack.z + age * .9
			)
			puff.translucent = true
			out.append(puff)
	if e.boss_phase >= 3:
		var spark := Renderer.Sprite.new(
			pack.x, pack.y, "fx_sparks_%d" % (int(game.clock * 15.0) % 3), .45, pack.z
		)
		spark.glow = true
		out.append(spark)
	return out


func dying(e: Enemy, game) -> void:
	# The pack goes with him: a green flash, sparks, smoke.
	var pack := _pack(e, game)
	game.burst(pack.x, pack.y, pack.z, "plasma", 20, 2.4)
	game.blast_flash = maxf(game.blast_flash, .3)
	game.sound_at("arm_impact", e.x, e.y, 1.0)
