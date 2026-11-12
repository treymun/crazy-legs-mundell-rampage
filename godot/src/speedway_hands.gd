## The speedway's own hands that do something the county's others do not
## (enemies.gd hands them their attack and their fall):
##   nitro_huffer   runs in close and goes up in a nitrous blast, and goes up
##                  the same way when he is shot down, taking whoever is near
##                  with him (his own side too, which starts a brawl or two)
##   flagman        waves the green flag to call every hand within earshot in
##                  on the player, round walls included, then keeps his
##                  distance and fires flares
## The pit mechanic and the tyre roller need nothing here: they are a bottle
## tosser and a valve rat throwing their own shot (enemies.cfg `shot`).
class_name SpeedwayHands
extends RefCounted

## How close the player must be when a huffer's lunge lands for him to blow.
const HUFF_REACH := 2.0
## How far the flagman's flag carries.
const FLAG_REACH := 16.0


## The attack of a kind handled here; false for every other kind.
static func attack(e: Enemy, game, direction: float, distance: float, eye: float, aim_z) -> bool:
	if e.brain == "nitro_huffer":
		var p = game.player
		if sqrt(pow(p.x - e.x, 2) + pow(p.y - e.y, 2)) < HUFF_REACH:
			e.hurt(e.hp + 1.0, game, true, false, e, "nitro")
		else:
			e.cooldown = 1.2
		return true
	if e.brain == "flagman":
		if e.attacks % 3 == 1 and _wave_in(e, game):
			e.cooldown = 2.4
			return true
		var p = game.player
		var target: float = p.eye if aim_z == null else float(aim_z)
		var sx := e.x + cos(direction) * .34
		var sy := e.y + sin(direction) * .34
		if not game.world.blocked(sx, sy, .045, eye):
			var t := maxf(.2, distance / 6.4)
			game.launch(
				sx,
				sy,
				eye,
				direction,
				6.4,
				"flare",
				(target - eye) / t,
				true,
				10,
				-1.0,
				e.get_instance_id()
			)
		game.sound_at("rocket_pop", e.x, e.y, .8)
		e.cooldown = 1.75 if e.attacks % 2 else 2.1
		return true
	return false


## The green flag: every hand in reach that has not seen the fight comes for
## the player. False when there was nobody left to call.
static func _wave_in(e: Enemy, game) -> bool:
	var p = game.player
	var called := 0
	for other: Enemy in game.enemies:
		if other == e or not other.alive or not other.hostile or other.alerted:
			continue
		if Enemy.BOSS_TITLES.has(other.kind):
			continue
		if sqrt(pow(other.x - e.x, 2) + pow(other.y - e.y, 2)) > FLAG_REACH:
			continue
		other.wake(game, p.x, p.y)
		other.hunt_until = maxf(other.hunt_until, game.clock + 12.0)
		called += 1
	if called == 0:
		return false
	game.sound_at("whistle", e.x, e.y, 1.0)
	game.message("THE FLAGMAN'S WAVIN' 'EM IN! (%d)" % called, 2.4)
	return true


## A huffer down, however it happened: the bottle on his back goes.
static func huffer_down(e: Enemy, game) -> void:
	var z: float = game.world.elevation(e.x, e.y) + .7
	game.explode(GameState.Shot.new(e.x, e.y, z, 0.0, 0.0, 0.0, "nitro", 0.0, true, 0))
