## THE SPLINTER FOREMAN, the sawmill's last boss: a blade in each fist and a
## saw rig strapped on his back, cutting the floor of the saw shed into lanes
## (enemies.cfg [foreman], enemies.gd special_attack and saw_lanes).
##
##   weak spot   the saw rig's motor on his back: from behind RIG, from the
##               side and high SIDE_RIG.
##   the carriage  the mill's log carriage runs its track on a bell
##               (features/boss_arena.gd): every CARRIAGE[phase] seconds once
##               the fight is on. It hits whoever is on the track, him too.
##   phase 3     the big cut: he flings a fan of saw blades that bounce off
##               the walls (lanes on the floor show the throw); the saw speeds
##               up: the carriage runs on a shorter bell, the head saw throws
##               sparks and the sawdust burns when a drum goes up by it.
##   HOG WILD    he kicks a fuel drum rolling down the floor at the player:
##               it goes up when it meets someone or a wall (shoot it first).
extends "res://src/bosses/arena_moves.gd"

const RIG := 2.0
const SIDE_RIG := 1.4
const CARRIAGE := [9.0, 9.0, 6.5, 4.0]
const CUT_EVERY := 5.0
const CUT_WARN := .95
const CUT_FAN := [-.42, -.21, 0.0, .21, .42]
const CUT_BOUNCES := 2
const DRUM_EVERY := 3
const DRUM_SPEED := 5.8


func fight_start(e: Enemy, game) -> void:
	e.set_meta("carriage_at", game.clock + 4.0)
	e.set_meta("drum_after", e.attacks + DRUM_EVERY)


func phase_changed(e: Enemy, game, phase: int) -> void:
	if phase != 3:
		return
	e.set_meta("cut_at", game.clock + .9)
	e.set_meta("carriage_at", minf(float(e.get_meta("carriage_at", INF)), game.clock + 2.0))
	game.message("THE SAW'S SPEEDIN' UP! MIND THE TRACK!", 2.6)
	game.sound_at("saw_motor", e.x, e.y, 1.0)


func tick(e: Enemy, dt: float, game) -> bool:
	if not fighting(e, game):
		return false
	var f = arena(game)
	if f != null and due(e, game, "carriage_at"):
		var every: float = CARRIAGE[clampi(e.boss_phase, 1, 3)] * (.8 if hog_wild(game) else 1.0)
		e.set_meta("carriage_at", game.clock + every)
		if f.ring_carriage():
			say_once(e, game, "carriage_told", "THE CARRIAGE BELL! GET OFF THE TRACK!")
	if f != null and e.boss_phase >= 3:
		_head_saw(f, game)
	if run_own(e, game, dt):
		return true
	if not ready(e):
		return false
	if e.boss_phase >= 3 and due(e, game, "cut_at") and sees_player(e, game):
		e.set_meta("cut_at", game.clock + CUT_EVERY * (.8 if hog_wild(game) else 1.0))
		begin_own(e, game, "cut", CUT_WARN)
		game.sound_at("foreman_warn", e.x, e.y, 1.0)
		say_once(e, game, "cut_told", "THE BIG CUT! THEM BLADES BOUNCE!")
		return true
	if (
		hog_wild(game)
		and e.boss_phase >= 2
		and e.attacks >= int(e.get_meta("drum_after", 1 << 30))
		and sees_player(e, game)
	):
		e.set_meta("drum_after", e.attacks + DRUM_EVERY)
		begin_own(e, game, "drum", .55)
		return true
	return false


func act(e: Enemy, game, name: String) -> void:
	if name == "cut":
		var floor_z: float = game.world.elevation(e.x, e.y)
		for off: float in CUT_FAN:
			var a: float = e.angle + off
			var sx := e.x + cos(a) * (e.radius + .15)
			var sy := e.y + sin(a) * (e.radius + .15)
			if game.world.blocked(sx, sy, .05):
				continue
			var shot := GameState.Shot.new(
				sx,
				sy,
				floor_z + .62,
				cos(a) * 7.0,
				sin(a) * 7.0,
				0.0,
				"foreman_cut",
				2.6,
				true,
				12,
				CUT_BOUNCES
			)
			shot.owner = e.get_instance_id()
			game.shots.append(shot)
		game.sound_at("foreman_cut", e.x, e.y, 1.0)
		e.recovery = .7
		e.cooldown = maxf(e.cooldown, 1.2)
	elif name == "drum":
		var f = arena(game)
		if f != null:
			var a := e.angle
			var sx2 := e.x + cos(a) * (e.radius + .5)
			var sy2 := e.y + sin(a) * (e.radius + .5)
			if not game.world.blocked(sx2, sy2, .4):
				f.roll(
					"prop_fuel",
					sx2,
					sy2,
					cos(a) * DRUM_SPEED,
					sin(a) * DRUM_SPEED,
					1.0,
					[.36, .4, .2, .7],
					0.0,
					0.0,
					"fuel"
				)
		game.sound_at("can_kick", e.x, e.y, 1.0)
		game.sound_at("tire_roll", e.x, e.y, .8)
		say_once(e, game, "drum_told", "HE KICKED A DRUM AT YOU! SHOOT IT!")
		e.recovery = .5


## The head saw at the end of the track throwing sparks, faster now.
func _head_saw(f, game) -> void:
	var saw = f.spec("foreman").get("head_saw")
	if not (saw is Array):
		return
	var x := float(saw[0])
	var y := float(saw[1])
	var beat := .6 + .4 * sin(game.clock * 31.0)
	f.light(x, y, game.world.elevation(x, y) + 1.0, 3.0, Color(1, .7, .35), beat)
	if fmod(game.clock, .25) < .02:
		game.burst(x, y, game.world.elevation(x, y) + .9, "spark", 3, 1.8)


func weak_spot(e: Enemy, game, hit: Vector3, from: Vector2, how: String) -> float:
	if how == "blast" or how == "energy" or how == "fire":
		return 1.0
	var off := off_facing(e, from)
	if off > 1.95:
		return RIG
	if off > 1.35 and body_height(e, game, hit) > .5:
		return SIDE_RIG
	return guarded(e, 1.0)


func telegraph(e: Enemy, game) -> Array:
	if own(e) != "cut":
		return []
	var out: Array = []
	for off: float in CUT_FAN:
		out.append_array(lane_marks(game, e.x, e.y, e.angle + off, 6.0, .2))
	return out


func looks(e: Enemy, game) -> Array:
	if e.boss_phase < 3:
		return []
	# The rig on his back smoking and spitting sparks.
	var floor_z: float = game.world.elevation(e.x, e.y)
	var spark := Renderer.Sprite.new(
		e.x - cos(e.angle) * e.radius * .7,
		e.y - sin(e.angle) * e.radius * .7,
		"fx_sparks_%d" % (int(game.clock * 13.0) % 3),
		.4,
		floor_z + e.height * .7
	)
	spark.glow = true
	return [spark]


func dying(e: Enemy, game) -> void:
	game.burst(e.x, e.y, game.world.elevation(e.x, e.y) + 1.3, "spark", 18, 2.4)
	game.sound_at("saw_bounce", e.x, e.y, 1.0)
