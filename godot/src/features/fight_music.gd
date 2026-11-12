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
##
## A chapter's boss fight goes further: its boss loop (Sound.BOSSES) takes over
## from the track and the fight loop while the boss is alive, awake and the
## player is in its arena (where the boss bar shows: within BOSS_RANGE of a
## chapter's last boss, the pen at Hickston's top), until BOSS_HOLD seconds
## after the player last was, and hands back the moment the boss falls.
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
## The boss arena: as far as the boss bar shows (game_view.gd), and how long
## the boss loop holds once the player steps out of it.
const BOSS_RANGE := 14.0
const BOSS_HOLD := 10.0
## Bosses whose own feature plays their loop (features/mothership.gd).
const OWN_MUSIC := ["maw"]

var fighting := false
## The boss loop is wanted (tools read it), and when the player was last in
## an awake boss's arena.
var boss_fight := false
var boss_heat := -100.0
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
		_boss_scan()
	fighting = not game.in_hub and game.clock - last_heat < HOLD
	if game.sound != null and game.sound.has_method("set_fight"):
		game.sound.set_fight(fighting)
		_boss_music()


## The boss whose fight it is: the chapter's last boss, or Hickston's sheriff
## and then Jerry; null when none is awake.
func boss() -> Enemy:
	for foe in [game.finale, game.boss, game.jerry]:
		if foe != null and foe.alive and foe.alerted and not foe.dormant:
			return foe
	return null


func _boss_scan() -> void:
	var foe := boss()
	if foe == null or game.in_hub or OWN_MUSIC.has(foe.kind):
		boss_fight = false
		return
	var p = game.player
	var near: bool = (
		Vector2(foe.x - p.x, foe.y - p.y).length() < BOSS_RANGE
		if foe == game.finale
		else p.y < 10.0
	)
	if near:
		boss_heat = game.clock
	boss_fight = game.clock - boss_heat < BOSS_HOLD


## Swap the chapter's score for its boss loop and back. Only ever between
## those two: the menus, the tally and Maw's own track are left alone.
func _boss_music() -> void:
	var score := String(game.level.score)
	var track := String(Sound.BOSSES.get(score, ""))
	if track == "" or (game.finale != null and OWN_MUSIC.has(game.finale.kind)):
		return
	var now := String(game.sound.score)
	if boss_fight and now == score:
		game.sound.set_score(track)
	elif not boss_fight and now == track:
		game.sound.set_score(score)


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
