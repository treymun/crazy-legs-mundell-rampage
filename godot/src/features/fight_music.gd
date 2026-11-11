## Fight music: the chapter's fight loop swells in over its track when enemies
## are on the player and gives way again once the area has been quiet a while
## (sound.gd ScorePlayer does the crossfade: in over 1 s, out over 3 s). Looks
## only: it reads the enemies and the game's events, never changes play, and
## saves nothing (a loaded game works the fight out again within a tick).
##
## An enemy is on the player when it is alive, hostile and alerted and it
## sees them, hunts them close by on the flow field, or is in the middle of an
## attack near them. Damage taken or dealt counts too while an alerted enemy
## is within NEAR. The fight is over HOLD seconds after the last of these, so
## losing sight of someone for a moment never lets the music drop.
extends GameFeature

## Seconds of quiet before the fight loop gives way.
const HOLD := 7.0
## How close an enemy hunting the player out of sight must be, and one
## winding up or recovering from an attack (sight itself reaches 14).
const HUNT_RANGE := 9.0
const ATTACK_RANGE := 14.0
## Damage keeps the fight going while an alerted enemy is within this.
const NEAR := 20.0
## Seconds between looks over the enemies.
const SCAN := .1

var fighting := false
var last_heat := -100.0
var scan_left := 0.0
## Enemies on the player at the last look (tools read it).
var engaged := 0


func id() -> String:
	return "fight_music"


func attach() -> void:
	game.ticked.connect(_tick)
	game.player_hurt.connect(func(_amount: float, _cause: String) -> void: _struck())
	game.hit_landed.connect(func(_amount: float, _killed: bool) -> void: _struck())


func _tick(dt: float) -> void:
	scan_left -= dt
	if scan_left <= 0.0:
		scan_left = SCAN
		engaged = _engaged()
		if engaged > 0:
			last_heat = game.clock
	fighting = not game.in_hub and game.clock - last_heat < HOLD
	if game.sound != null and game.sound.has_method("set_fight"):
		game.sound.set_fight(fighting)


## A hit taken or landed counts only with an alerted enemy about: a hot coal
## or a shot pig is not a fight.
func _struck() -> void:
	var p = game.player
	for enemy: Enemy in game.enemies:
		if (
			enemy.alive
			and enemy.hostile
			and enemy.alerted
			and absf(enemy.x - p.x) < NEAR
			and absf(enemy.y - p.y) < NEAR
		):
			last_heat = game.clock
			return


func _engaged() -> int:
	var p = game.player
	var count := 0
	for enemy: Enemy in game.enemies:
		if not (enemy.alive and enemy.hostile and enemy.alerted):
			continue
		var distance := Vector2(enemy.x - p.x, enemy.y - p.y).length()
		if (
			enemy.player_seen
			or (distance < HUNT_RANGE and game.clock < enemy.hunt_until)
			or (distance < ATTACK_RANGE and (enemy.windup > 0.0 or enemy.recovery > 0.0))
		):
			count += 1
	return count
