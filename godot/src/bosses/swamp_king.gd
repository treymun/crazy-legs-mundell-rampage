## THE SWAMP KING, Gator Bayou's boss: an airboat that circles its lagoon,
## fires its punt gun and makes airboat runs down a marked lane
## (bayou_brains.gd, enemies.cfg [swamp_king]).
##
## Kind `swamp_king`. His fight on the lagoon (bayou_plan.gd lagoon()):
##   the lagoon   a run that ends on the bank, a piling or a cypress beaches the
##                boat (bayou_brains.gd); beached by a fuel drum or anything that
##                goes up, it goes up on him (and on whoever stands there).
##   phase 3      DYNAMITE: every third attack he sits and lobs three lit sticks
##                onto marked spots round the player; his holed tank leaves
##                burning slicks on the water behind him (features/boss_arenas.gd).
##   weak spot    the engine in its cage at the stern: a hit from behind the
##                boat, cage high, counts double.
##   HOG WILD     BROADSIDE: a run he finishes on the water ends with the punt
##                gun turned on the player straight off, no wind-up.
extends BossMoves

const DYNAMITE_WINDUP := 1.05
const DYNAMITE_RADIUS := 1.6
## How far off his heading a shot must come from to strike the engine cage.
const BEHIND := 2.0
const WEAK := 2.0
const PACE := [1.3, 1.0, .92, .84]


func stagger_hit(_e: Enemy) -> float:
	return 170.0


func stagger_rest(_e: Enemy) -> float:
	return 6.0


func phase_changed(e: Enemy, game, phase: int) -> void:
	if phase == 3:
		var arenas = game.features.get("boss_arenas")
		if arenas != null:
			arenas.turn(e)


func tick(e: Enemy, dt: float, game) -> bool:
	var running := e.has_meta("run")
	if bool(e.get_meta("was_running", false)) and not running:
		_run_over(e, game)
	e.set_meta("was_running", running)
	if e.has_meta("dynamite"):
		e.windup = maxf(0.0, e.windup - dt)
		e.angle = atan2(game.player.y - e.y, game.player.x - e.x)
		if e.windup <= 0.0 or e.stun > .3:
			_thrown(e, game)
		return true
	if _dynamite_ready(e, dt, game):
		_dynamite(e, game)
		return true
	return false


## A run just ended: beached against something that goes up, it goes up; on
## HOG WILD, one finished on the water ends in a broadside.
func _run_over(e: Enemy, game) -> void:
	var bow := Vector2(e.x + cos(e.angle) * (e.radius + .4), e.y + sin(e.angle) * (e.radius + .4))
	if e.stun > .5:
		var z: float = game.world.elevation(bow.x, bow.y)
		for point in game.drums.keys():
			var vec: Vector2 = point
			if vec.distance_to(bow) < 1.6:
				game.drum_hit(vec, 40)
		var pieces = game.features.get("breakables")
		if pieces != null:
			pieces.blast(bow.x, bow.y, z + .4, 1.3, 40.0, false)
		return
	if not hog_wild(game) or not e.alive:
		return
	var p = game.player
	var toward := atan2(p.y - e.y, p.x - e.x)
	var gap := Vector2(p.x - e.x, p.y - e.y).length()
	if gap > 11.0 or not game.world.visible(e.x, e.y, p.x, p.y):
		return
	var eye: float = game.world.stand(e) + 1.2
	for k in 5:
		var bearing := toward + (k - 2) * .13
		var sx := e.x + cos(bearing) * (e.radius + .3)
		var sy := e.y + sin(bearing) * (e.radius + .3)
		if not game.world.blocked(sx, sy, .045, eye):
			var slope: float = (p.eye - eye) * 7.6 / maxf(gap, 1.0)
			game.launch(sx, sy, eye, bearing, 7.6, "deputy_slug", slope, true, 8, 2.0)
	game.sound_at("king_puntgun", e.x, e.y, 1.0)
	game.burst(e.x + cos(toward) * 1.1, e.y + sin(toward) * 1.1, eye, "spark", 8, 1.6)
	game.message("BROADSIDE!", 1.2)


func _dynamite_ready(e: Enemy, dt: float, game) -> bool:
	if e.boss_phase < 3 or not e.alerted or e.windup > 0.0 or e.stun > 0.0:
		return false
	if e.has_meta("run") or e.recovery > .17 or e.attacks % 3 != 2:
		return false
	if e.cooldown > dt * float(game.sharpness):
		return false
	var p = game.player
	var gap := Vector2(p.x - e.x, p.y - e.y).length()
	return gap <= float(Enemy.REACH[e.kind]) + 2.0 and game.world.visible(e.x, e.y, p.x, p.y)


## DYNAMITE: he sits the boat and lobs three lit sticks round the player.
func _dynamite(e: Enemy, game) -> void:
	var p = game.player
	e.windup = DYNAMITE_WINDUP * float(PACE[clampi(game.difficulty, 0, 3)])
	e.aim_mark = null
	e.set_meta("dynamite", true)
	e.set_meta("tell", "DYNAMITE!")
	var arenas = game.features.get("boss_arenas")
	var toward := atan2(p.y - e.y, p.x - e.x)
	var side := Vector2(-sin(toward), cos(toward))
	var spots: Array = [
		Vector2(p.x, p.y), Vector2(p.x, p.y) + side * 2.1, Vector2(p.x, p.y) - side * 2.1
	]
	var k := 0
	for at: Vector2 in spots:
		if arenas == null or game.world.blocked(at.x, at.y, .2):
			continue
		arenas.drop("tnt", at.x, at.y, e.windup + .35 + k * .18, DYNAMITE_RADIUS, 0, "DYNAMITE")
		k += 1
	game.sound_at("king_holler", e.x, e.y, 1.0)
	game.sound_at("fuse_hiss", e.x, e.y, .9)


func _thrown(e: Enemy, game) -> void:
	e.remove_meta("dynamite")
	e.remove_meta("tell")
	e.windup = 0.0
	e.attacks += 1
	e.cooldown = 1.2 * float(PACE[clampi(game.difficulty, 0, 3)])
	e.recovery = .5


## The engine in its cage at the stern: hit from behind the boat, cage high.
func weak_spot(e: Enemy, game, hit: Vector3, from: Vector2, how: String) -> float:
	if how == "blast" or how == "energy" or how == "fire" or how == "steam":
		return 1.0
	var toward_shooter := atan2(from.y - e.y, from.x - e.x)
	if absf(Enemy.angle_delta(toward_shooter, e.angle)) < BEHIND:
		return 1.0
	var up: float = (hit.z - game.world.stand(e)) / maxf(.5, e.height)
	return WEAK if up > .3 else 1.0


## Fuel burning off his stern once the tank is holed; a sputter before that.
func looks(e: Enemy, game) -> Array:
	var out: Array = []
	if e.boss_phase < 3:
		return out
	var floor_z: float = game.world.stand(e)
	var frame := int(game.clock * 10.0)
	for k in 2:
		var back := Vector2(
			e.x - cos(e.angle) * (.55 + k * .35) + sin(e.angle) * (k - .5) * .4,
			e.y - sin(e.angle) * (.55 + k * .35) - cos(e.angle) * (k - .5) * .4
		)
		var fire := Renderer.Sprite.new(
			back.x, back.y, "fx_fire_%d" % ((frame + k * 2) % 4), .8 - k * .2, floor_z + .35
		)
		fire.glow = true
		out.append(fire)
	return out


## His crate of dynamite goes with the boat: blasts strung across the water.
func dying(e: Enemy, game) -> void:
	var z: float = game.world.stand(e)
	for k in 3:
		var a := e.angle + k * 2.1
		game.blasts.append(
			GameState.Blast.new(e.x + cos(a) * .9, e.y + sin(a) * .9, z + .5 + k * .3, "fire")
		)
	game.sound_at("king_ram", e.x, e.y, 1.0)
	var fight = game.features.get("boss_fight")
	if fight != null:
		fight.sparks(e.x, e.y, z + .4, "splash", 30, 3.2)
