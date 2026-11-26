## Fight music in four levels (pass 15; src/score_layers.gd plays them):
## CALM the chapter's track; BUILD the fight loop's drums alone, in the
## track's place; FIGHT the whole loop; PEAK the loop with its top riff over
## it. sound.gd ScorePlayer crossfades the track and the fight player (in
## over 1 s, out over 3 s); ScoreLayers moves the layers under the one stream.
## Looks only: it reads the enemies, the director's beat and the game's
## events, never changes play, and saves nothing (a loaded game works the
## level out again within a tick).
##
## An enemy is on the player when it is alive, hostile and alerted and it
## sees them, hunts them close by on the flow field, or is in the middle of an
## attack near them. BUILD while one is on the player or an alerted hand
## hunts within NEAR (held BUILD_HOLD s). FIGHT while CROWD are on him, or one
## is and has hurt him within HURT_HOT s, or the director's intensity is
## FIGHT_HEAT or more; held HOLD s after the last of these, so losing sight of
## someone for a moment never lets the music drop, but held only QUIET_HOLD s
## once no hand about is awake and after him, and dropped within BREATHER_DROP s
## once the director calls a breather and nobody is on him.
## PEAK while a director's peak has hands on him or he is on a RAMPAGE (held
## PEAK_HOLD s). Before pass 15 any hand on the player was the fight loop, held
## 7 s: with a fight every 8 to 12 s it played 80 to 97 % of every chapter.
##
## A chapter's boss fight goes further: its boss loop (Sound.BOSSES) takes over
## from the track and the fight loop while the boss is alive, awake and the
## player is in its arena (where the boss bar shows: within BOSS_RANGE of a
## chapter's last boss, the pen at Hickston's top), until BOSS_HOLD seconds
## after the player last was, and hands back the moment the boss falls.
extends GameFeature

## The numbers (data/tuning/fight_music.cfg [all]): seconds the whole loop
## holds after the last of what keeps it (and how soon it drops in a
## director's breather, and with nobody about); BUILD's and PEAK's holds.
const DATA := "res://data/tuning/fight_music.cfg"
static var HOLD: float = Tuning.value(DATA, "hold")
static var BREATHER_DROP: float = Tuning.value(DATA, "breather_drop")
static var QUIET_HOLD: float = Tuning.value(DATA, "quiet_hold")
static var BUILD_HOLD: float = Tuning.value(DATA, "build_hold")
static var PEAK_HOLD: float = Tuning.value(DATA, "peak_hold")
## FIGHT: this many on the player, or one and a blow within HURT_HOT s, or the
## director's intensity this high.
static var CROWD: int = Tuning.value(DATA, "crowd")
static var HURT_HOT: float = Tuning.value(DATA, "hurt_hot")
static var FIGHT_HEAT: float = Tuning.value(DATA, "fight_heat")
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
## How high the boss loop plays once its boss is plum desperate (phase 3).
const LIFT := 1.06

## The whole fight loop is playing (FIGHT or PEAK; tools read it), and the
## level (ScoreLayers.CALM .. PEAK).
var fighting := false
var level := ScoreLayers.CALM
## When BUILD and PEAK were last called for, and the last blow in a fight.
var build_heat := -100.0
var peak_heat := -100.0
var struck_at := -100.0
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
	tick_with(_tick)
	# The local player's fight (another player's blows set no music here).
	game.events.player_hurt.connect(
		func(_amount: float, _cause: String) -> void: _struck_here(true)
	)
	game.events.hit_landed.connect(func(_amount: float, _killed: bool) -> void: _struck_here(false))


func _struck_here(taken: bool) -> void:
	if game.acting_local():
		_struck(taken)


func _tick(dt: float) -> void:
	scan_left -= dt
	if scan_left <= 0.0:
		scan_left = SCAN
		engaged = _engaged()
		_heat()
		_boss_scan()
	level = _level()
	fighting = level >= ScoreLayers.FIGHT
	if game.sound != null and game.sound.has_method("set_fight"):
		var node := game.sound.node()
		var fight_track := str(Sound.FIGHTS.get(String(game.level.score), ""))
		var layered := node != null and ScoreLayers.layered(node.assets, fight_track)
		game.sound.set_fight(level >= (ScoreLayers.BUILD if layered else ScoreLayers.FIGHT))
		if node != null:
			ScoreLayers.step(dt, level, node.fight_mix())
		_boss_music()
		# The boss loop lifts a touch in its boss's last phase (sound.gd tick_score
		# eases it there; only a boss loop is ever lifted).
		var foe := boss()
		game.sound.score_lift = LIFT if foe != null and foe.boss_phase >= 3 else 1.0


## What calls for each level, from the look just taken.
func _heat() -> void:
	var phase := Director.phase_of(game)
	var heat := Director.intensity_of(game)
	var awake := engaged > 0 or _awake_near()
	if awake:
		build_heat = game.clock
	if (
		engaged >= CROWD
		or (engaged > 0 and game.clock - struck_at < HURT_HOT)
		or (engaged > 0 and heat >= FIGHT_HEAT)
	):
		last_heat = game.clock
	if phase == Director.BREATHER and engaged == 0:
		# A breather: the whole loop gives way soon, the drums a while after.
		last_heat = minf(last_heat, game.clock - HOLD + BREATHER_DROP)
	elif not awake:
		# Nobody about at all: the whole loop holds only QUIET_HOLD.
		last_heat = minf(last_heat, game.clock - HOLD + QUIET_HOLD)
	if (phase == Director.PEAK and engaged > 0) or Rampage.raging(game, game.local_player):
		# (The PEAK alone: once it is over the level is what the hands make it.)
		peak_heat = game.clock


func _level() -> int:
	if game.in_hub:
		return ScoreLayers.CALM
	if game.clock - peak_heat < PEAK_HOLD:
		return ScoreLayers.PEAK
	if game.clock - last_heat < HOLD:
		return ScoreLayers.FIGHT
	if game.clock - build_heat < BUILD_HOLD:
		return ScoreLayers.BUILD
	return ScoreLayers.CALM


## An alerted hand within NEAR that sees the player or hunts him: the fight
## is coming.
func _awake_near() -> bool:
	var p := game.player
	for enemy: Enemy in game.enemies:
		if (
			enemy.alerted
			and enemy.alive
			and enemy.hostile
			and not enemy.dormant
			and (enemy.player_seen or game.clock < enemy.hunt_until)
			and absf(enemy.x - p.x) < NEAR
			and absf(enemy.y - p.y) < NEAR
		):
			return true
	return false


## The boss whose fight it is: the chapter's last boss, or Hickston's sheriff
## and then Jerry; null when none is awake.
func boss() -> Enemy:
	for foe: Enemy in [game.finale, game.boss, game.jerry]:
		if foe != null and foe.alive and foe.alerted and not foe.dormant:
			return foe
	return null


func _boss_scan() -> void:
	var foe := boss()
	if foe == null or game.in_hub or OWN_MUSIC.has(foe.kind):
		boss_fight = false
		return
	var p := game.player
	var near: bool = (
		Vector2(foe.x - p.x, foe.y - p.y).length() < BOSS_RANGE
		if foe == game.finale and BossFight.lock_of(game, foe.kind).is_empty()
		else BossFight.in_arena_at(game, foe, p.x, p.y)
	)
	if near:
		boss_heat = game.clock
	boss_fight = game.clock - boss_heat < BOSS_HOLD


## Swap the chapter's score for its boss loop and back. Only ever between
## those two: the menus, the tally and Maw's own track are left alone.
func _boss_music() -> void:
	var score := String(game.level.score)
	var track := str(Sound.BOSSES.get(score, ""))
	if track == "" or (game.finale != null and OWN_MUSIC.has(game.finale.kind)):
		return
	var now := game.sound.score
	if boss_fight and now == score:
		game.sound.set_score(track)
	elif not boss_fight and now == track:
		game.sound.set_score(score)


## A hit taken or landed counts only with an alerted enemy about: a hot coal
## or a shot pig is not a fight. One taken can make a FIGHT of one hand; one
## landed only keeps the BUILD.
func _struck(taken: bool) -> void:
	var p := game.player
	for enemy: Enemy in game.enemies:
		if (
			enemy.alerted
			and enemy.alive
			and enemy.hostile
			and absf(enemy.x - p.x) < NEAR
			and absf(enemy.y - p.y) < NEAR
		):
			if taken:
				struck_at = game.clock
			build_heat = game.clock
			return


func _engaged() -> int:
	var p := game.player
	var count := 0
	for enemy: Enemy in game.enemies:
		if not (enemy.alerted and enemy.alive and enemy.hostile):
			continue
		var distance := Vector2(enemy.x - p.x, enemy.y - p.y).length()
		if (
			enemy.player_seen
			or (distance < HUNT_RANGE and game.clock < enemy.hunt_until)
			or (distance < ATTACK_RANGE and (enemy.windup > 0.0 or enemy.recovery > 0.0))
		):
			count += 1
	return count
