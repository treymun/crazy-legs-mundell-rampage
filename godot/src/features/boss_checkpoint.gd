## The checkpoint at the boss door (boss_door.gd keeps the file). While no
## boss fight is on it notes where the player last stood on the ground, every
## SCAN seconds for the last minute. When a fight begins (the boss awake and
## the player in its arena: BossFight.on) the door is the last of those spots
## clear of the arena (BossFight.clear_of: out of it and ARENA from the boss,
## so Hickston's is the pen's gate, not its middle), and a beat later, once
## the player is on the ground with no lit stick, the game is saved to the
## checkpoint: health, guns and rounds
## as they are at the fight's start, the boss still whole. Retrying puts the
## player back at the door facing the boss, so the fight is walked into again
## rather than started mid-swing. One checkpoint a boss: Hickston's sheriff
## and then Jerry each take theirs.
##
## Campaign chapters and replays only: never the hub, the range, a finished
## chapter revisited or a rematch. Saved in the features block: which boss's
## checkpoint was taken (with a token the file must match) and the door.
extends GameFeature

const SCAN := .25
## Spots kept (a minute of SCAN).
const KEEP := 240
## Longest wait for the player to land before the checkpoint is taken anyway.
const SETTLE := 3.0

var samples: Array = []
var scan_left := 0.0
## The boss whose fight was last begun, and the door for it: [x, y, angle].
var fight_kind := ""
var door: Array = []
## Boss kind -> the token of the checkpoint taken for its fight.
var taken := {}
var pending_since := -1.0
## The death screen's answer, worked out once a death (-1 not yet).
var offer := -1


func id() -> String:
	return "boss_checkpoint"


func attach() -> void:
	game.ticked.connect(_tick)
	game.level_won.connect(_won)


func save() -> Dictionary:
	if taken.is_empty():
		return {}
	return {"taken": taken.duplicate(), "door": door.duplicate(), "kind": fight_kind}


func restore(state: Dictionary) -> void:
	var kept = state.get("taken", {})
	taken = {}
	if kept is Dictionary:
		for key in kept:
			taken[String(key)] = String(kept[key])
	var spot = state.get("door", [])
	door = []
	if spot is Array and spot.size() >= 3:
		for value in spot.slice(0, 3):
			door.append(float(value))
	fight_kind = String(state.get("kind", ""))


func eligible() -> bool:
	return (
		not game.in_hub
		and not game.revisiting
		and Campaign.ORDER.has(game.level.id)
		and not BossRematch.active(game)
	)


func _tick(dt: float) -> void:
	scan_left -= dt
	if scan_left > 0.0 or not eligible():
		return
	scan_left = SCAN
	var p = game.player
	if p.health <= 0:
		pending_since = -1.0
		return
	if pending_since >= 0.0:
		_settle()
		return
	var foe := BossFight.on(game)
	if foe != null and not taken.has(foe.kind):
		fight_began(foe)
		return
	if p.air == 0.0 and p.vertical_speed == 0.0:
		samples.append([p.x, p.y, p.angle])
		if samples.size() > KEEP:
			samples.pop_front()


## The fight with `foe` has begun: this is the one place it is noticed, so the
## boss framework's intro signal can call it instead of the polling above.
func fight_began(foe: Enemy) -> void:
	if not eligible() or taken.has(foe.kind) or pending_since >= 0.0:
		return
	fight_kind = foe.kind
	var p = game.player
	var spot: Array = []
	for i in range(samples.size() - 1, -1, -1):
		var sample: Array = samples[i]
		if BossFight.clear_of(game, foe, float(sample[0]), float(sample[1])):
			spot = sample
			break
	if not spot.is_empty():
		door = [float(spot[0]), float(spot[1]), float(spot[2])]
	elif door.is_empty():
		# Woken with the player already inside (a station beside the boss): the
		# door is where they stood then.
		door = [p.x, p.y, p.angle]
	pending_since = game.clock
	_settle()


## A beat after the fight began, once nothing of the player's is in the air.
func _settle() -> void:
	var p = game.player
	var calm: bool = p.air == 0.0 and p.vertical_speed == 0.0
	if game.armory.fuse > 0.0 or (not calm and game.clock - pending_since < SETTLE):
		return
	pending_since = -1.0
	taken[fight_kind] = "%s-%s-%d" % [game.level.id, fight_kind, Time.get_ticks_usec()]
	if not BossDoor.write(game):
		taken.erase(fight_kind)


func _won() -> void:
	if eligible():
		BossDoor.clear(game.level.id, game.replay)


## RETRY THE FIGHT is on offer: a fight was begun, its boss still stands, and
## the checkpoint on file is the one this run took.
func offered() -> bool:
	if game.player.health > 0:
		offer = -1
		return false
	if offer < 0:
		var boss := BossFight.of_kind(game, fight_kind)
		var yes := (
			eligible()
			and taken.has(fight_kind)
			and boss != null
			and (
				BossDoor.token_on_file(game.level.id, game.replay, fight_kind)
				== String(taken[fight_kind])
			)
		)
		offer = 1 if yes else 0
	return offer == 1


## The death screen's lines when the fight can be retried ([] otherwise), in
## the words of the device last used (game.use_key says which).
func death_lines() -> Array:
	if not offered():
		return []
	if game.use_key == "Y":
		return ["A  RETRY THE FIGHT", "X  CHAPTER START  /  B  TITLE"]
	if game.use_key == "USE":
		return ["TAP  RETRY THE FIGHT", "TAP HERE  CHAPTER START"]
	return [
		"ENTER  RETRY THE FIGHT",
		"%s  CHAPTER START  /  F9 LOAD  /  ESC TITLE" % reload_key(),
	]


## The key RELOAD is on (play keys arrive as their default, KEY_R).
static func reload_key() -> String:
	for code in KeyBindings._translate:
		if int(KeyBindings._translate[code]) == KEY_R:
			return KeyBindings.key_name(int(code))
	return "R"
