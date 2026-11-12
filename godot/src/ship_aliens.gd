## The mothership's crew (chapter 7): what they do that the kinds they borrow
## their brains from (enemies.cfg `brain`) do not. The grey drone zaps with a
## cattle prod and skitters back out of reach; the tin guard soaks shots from
## the front on a pickup's tailgate, which it swings aside only to fire its bug
## zapper; the floating probe reels the player in on a beam. Maw Glorb's looks
## follow her health here; her attacks are the mothership feature's
## (features/mothership.gd), which runs her whole fight. enemies.gd hands over
## to these from three small hooks (attack, hurt, sprite).
class_name ShipAliens
extends RefCounted

## Hits a tailgate does not stop: blasts, swings, rolled and thrown things.
const SHIELD_PASSES := [
	"crowbar", "slingblade", "bowling", "pressure_gun", "blade", "ripsaw", "keg", "cow", "tnt"
]
## How much of a hit gets past the tailgate, and how far round from its front
## (radians either side) a shot has to come from to meet it.
const SHIELD_SOAK := .3
const SHIELD_ARC := 1.1
## Maw's second look: the housecoat gone, a third of her health left.
const BARE_AT := 1.0 / 3.0


## The attack of a kind drawn here (true), or false for every other kind.
static func attack(
	enemy: Enemy, game, direction: float, distance: float, eye: float, aim_z
) -> bool:
	match enemy.kind:
		"drone":
			_prod(enemy, game, eye)
		"tin_guard":
			_zap(enemy, game, direction, distance, eye, aim_z)
		"probe":
			_tug(enemy, game, direction, distance, eye)
		"maw":
			var fight = game.features.get("mothership")
			if fight != null:
				fight.maw_attack(enemy, direction)
			else:
				enemy.cooldown = 2.0
		_:
			return false
	return true


## A hit on the tin guard's tailgate: most of it stopped, sparks off the tin.
static func soak(
	enemy: Enemy, amount: float, game, how: String, explosive: bool, pressure: bool, by
) -> float:
	if enemy.kind != "tin_guard" or enemy.windup > 0.0 or explosive or pressure or by != null:
		return amount
	if SHIELD_PASSES.has(how):
		return amount
	var p = game.player
	var toward := atan2(p.y - enemy.y, p.x - enemy.x)
	if absf(Enemy.angle_delta(toward, enemy.angle)) > SHIELD_ARC:
		return amount
	if game.clock - enemy.struck_at > .14:
		game.sound_at(cue(game, "tailgate_clang", "ricochet"), enemy.x, enemy.y, .7)
	var floor_z: float = game.world.elevation(enemy.x, enemy.y)
	game.burst(
		enemy.x + cos(toward) * .4, enemy.y + sin(toward) * .4, floor_z + 1.0, "spark", 3, 1.1
	)
	return amount * SHIELD_SOAK


## The picture set a kind wears now: Maw out of her housecoat, or the usual.
static func skin(enemy: Enemy) -> String:
	if enemy.kind == "maw" and enemy.hp <= enemy.max_hp * BARE_AT:
		return "_bare"
	return ""


## The boss bar's tell for Maw: the attack she is winding up.
static func tell(game, boss: Enemy, fallback: String) -> String:
	var fight = game.features.get("mothership") if boss.kind == "maw" else null
	return fight.tell_of() if fight != null else fallback


## The boss bar's line under the tell: Maw's phase as it changes.
static func phase_text(game, boss: Enemy, fallback: String) -> String:
	var fight = game.features.get("mothership") if boss.kind == "maw" else null
	return fight.phase_line(fallback) if fight != null else fallback


## The chapter's own sound once it is made (docs/new_chapters/mothership_audio.md),
## an existing one till then.
static func cue(game, wanted: String, fallback: String) -> String:
	return wanted if game.art != null and game.art.has_cue(wanted) else fallback


## The drone's prod: a zap that jolts the aim, then off out of reach.
static func _prod(enemy: Enemy, game, eye: float) -> void:
	var lunge: Array = Enemy.LUNGES[enemy.kind]
	enemy.cooldown = float(lunge[5])
	var p = game.player
	var gap := Vector2(p.x - enemy.x, p.y - enemy.y).length()
	if gap < float(lunge[2]) and game.world.visible(enemy.x, enemy.y, p.x, p.y, eye, p.eye):
		game.damage(int(lunge[3]), [enemy.x, enemy.y], "ZAP")
		game.sound_at(cue(game, "drone_zap", String(lunge[4])), enemy.x, enemy.y)
		game.shake = minf(1.0, game.shake + .25)
		p.angle = fposmod(p.angle + (.06 if enemy.attacks % 2 else -.06), TAU)
		game.burst(p.x, p.y, p.eye - .3, "spark", 6, 1.2)
	enemy.retreat_from(game, p.x, p.y)


## The tin guard's bug zapper: three bolts in a fan, the tailgate swung aside.
static func _zap(enemy: Enemy, game, direction: float, distance: float, eye: float, aim_z) -> void:
	enemy.cooldown = 1.95 if enemy.attacks % 2 else 1.45
	var target: float = game.player.eye if aim_z == null else float(aim_z)
	var flight := maxf(.12, distance / 5.4)
	for i in 3:
		var theta := direction + (i - 1) * .14
		game.launch(
			enemy.x + cos(theta) * (enemy.radius + .08),
			enemy.y + sin(theta) * (enemy.radius + .08),
			eye - .1,
			theta,
			5.4,
			"barker_bolt",
			(target - eye + .1) / flight,
			true,
			9,
			-1.0,
			enemy.get_instance_id()
		)
	game.sound_at(cue(game, "guard_zapper", "barker_blast"), enemy.x, enemy.y)


## The probe's beam: the player reeled a step or so toward it and zapped, or,
## out of reach of the beam, a plain bolt.
static func _tug(enemy: Enemy, game, direction: float, distance: float, eye: float) -> void:
	enemy.cooldown = 2.4
	var p = game.player
	var seen: bool = game.world.visible(enemy.x, enemy.y, p.x, p.y, eye, p.eye)
	if seen and distance < float(Enemy.REACH[enemy.kind]) + .6:
		var pull := clampf(distance - 1.2, 0.0, 1.5)
		var toward := atan2(enemy.y - p.y, enemy.x - p.x)
		for _k in 6:
			game.move_actor(
				p, cos(toward) * pull / 6.0, sin(toward) * pull / 6.0, GameState.PLAYER_RADIUS
			)
		game.damage(6, [enemy.x, enemy.y], "BEAM")
		game.shake = minf(1.0, game.shake + .3)
		game.burst(p.x, p.y, p.eye - .2, "plasma", 8, 1.0)
		game.sound_at(cue(game, "probe_tug", "saucer_shot"), enemy.x, enemy.y)
		return
	var flight := maxf(.12, distance / 4.2)
	game.launch(
		enemy.x + cos(direction) * .3,
		enemy.y + sin(direction) * .3,
		eye,
		direction,
		4.2,
		"plasma",
		(p.eye - eye) / flight,
		true,
		8,
		-1.0,
		enemy.get_instance_id()
	)
	game.sound_at("saucer_shot", enemy.x, enemy.y)
