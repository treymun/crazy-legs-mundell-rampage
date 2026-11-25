## The checkpoint at the boss door: a save (SessionStore's own format, no new
## version) of the moment a chapter's boss fight began, in a file of its own
## beside the quicksave, boss-checkpoint-<chapter>.json (-replay for a replay
## run, -party in co-op): chapter_marks.gd keeps the files, the trail markers'
## beside them. features/boss_checkpoint.gd takes it; the death screen offers
## RETRY THE FIGHT while it matches the run (main_flow.gd retry_fight), which
## loads it with the boss at full health and the player back at the arena's
## door. Cleared when the chapter is won, and a chapter's start clears every
## other chapter's.
class_name BossDoor
extends RefCounted

const BossCheckpointFeature := preload("res://src/features/boss_checkpoint.gd")
const BossLockFeature := preload("res://src/features/boss_lock.gd")


static func folder() -> String:
	return ChapterMarks.folder()


static func path(level_id: String, replay: bool) -> String:
	return ChapterMarks.path(ChapterMarks.BOSS, level_id, replay)


## A co-op game's checkpoint is a file of its own (-party), so a party's
## fight never takes the place of the host's own chapter's.
static func path_of(game: Game) -> String:
	return ChapterMarks.path_of(ChapterMarks.BOSS, game)


static func write(game: Game) -> bool:
	return ChapterMarks.write(ChapterMarks.BOSS, game)


static func clear(level_id: String, replay: bool) -> void:
	ChapterMarks.clear(ChapterMarks.BOSS, level_id, replay)


## A chapter starts: the other chapters' checkpoints and markers (of the same
## kind of run) go.
static func clear_others(level_id: String, replay: bool) -> void:
	ChapterMarks.clear_others(level_id, replay)


static func clear_all() -> void:
	ChapterMarks.clear_all()


## The token the checkpoint on file was taken with for `kind` ("" for none).
static func token_on_file(level_id: String, replay: bool, kind: String, file := "") -> String:
	if file == "":
		file = path(level_id, replay)
	var box := ChapterMarks.state_on_file(file, level_id, "boss_checkpoint")
	if not (box.get("taken", {}) is Dictionary):
		return ""
	var taken: Dictionary = box["taken"]
	return str(taken.get(kind, ""))


## The fight again: the checkpoint loaded, the player at the door, the boss
## whole, nothing in the air. Null when the file is gone or no longer loads.
static func restore(make_game: Callable, current: Game) -> Game:
	var loaded := ChapterMarks.read(ChapterMarks.BOSS, make_game, current)
	if loaded == null:
		return null
	return at_door(loaded)


## A checkpoint's game, just loaded, made ready to retry: the boss whole, its
## arena as the level made it, the player at the door. Null when it has no door.
static func at_door(loaded: Game) -> Game:
	var feature: BossCheckpointFeature = loaded.features.get("boss_checkpoint")
	if feature == null or feature.door.size() < 3:
		return null
	var p := loaded.player
	var door_x: float = feature.door[0]
	var door_y: float = feature.door[1]
	p.x = door_x
	p.y = door_y
	p.vx = 0.0
	p.vy = 0.0
	p.air = 0.0
	p.vertical_speed = 0.0
	p.pitch = 0.0
	p.crouched = false
	p.eye = loaded.world.stand(p) + .95
	var boss := BossFight.of_kind(loaded, String(feature.fight_kind))
	if boss != null:
		boss.hp = boss.max_hp
		boss.windup = 0.0
		boss.recovery = 0.0
		boss.aim_mark = null
		boss.stun = 0.0
		boss.cooldown = maxf(boss.cooldown, 1.2)
		boss.target = [p.x, p.y]
		p.angle = atan2(boss.y - p.y, boss.x - p.x)
	else:
		var door_angle: float = feature.door[2]
		p.angle = door_angle
	# The arena as the level made it, and every piece of the boss's gear on.
	var wreck: ArenaWreckFeature = loaded.features.get("arena_wreck")
	if wreck != null:
		wreck.reset()
	var gear: BossGearFeature = loaded.features.get("boss_gear")
	if gear != null:
		gear.reset()
	# Its doors as they stood before the fight shut them, the gates gone: it
	# shuts again as the player walks in (features/boss_lock.gd).
	var lock: BossLockFeature = loaded.features.get("boss_lock")
	if lock != null:
		lock.reset()
	loaded.shots.clear()
	loaded.hazards.clear()
	loaded.blasts.clear()
	loaded.armory.fuse = 0.0
	loaded.armory.tnt_latched = false
	loaded.spawn_grace = maxf(loaded.spawn_grace, 1.5)
	loaded.district = int(loaded.world.area[loaded.world.cell(p.x, p.y)])
	retry_floor(loaded)
	loaded.message("BACK AT THE DOOR. SAME GUNS, SAME BOSS. GIT 'EM.", 3.5)
	return loaded


## A fight retried with its guns run dry is lost before it starts (polish
## pass 9: the campaign bot died again within ten seconds of every Hickston
## retry at HARD): each player's guns carried come back with at least
## bosses.cfg [boss_retry] `rounds` in reserve, and at least its `health`
## (the checkpoint keeps the health a player came in with, and at 40 the
## bot died again within seconds every time). Play, the same on every machine.
static func retry_floor(loaded: Game) -> void:
	var least_of: Dictionary = BossData.get_value("boss_retry", "rounds")
	var health: int = BossData.get_value("boss_retry", "health")
	for pl: Player in loaded.players:
		pl.health = maxi(pl.health, health)
		for gun: String in least_of:
			var slot := Weapons.NAMES.find(gun)
			if slot < 0 or not pl.armory.owned[slot]:
				continue
			var least: int = least_of[gun]
			pl.armory.reserve[slot] = maxi(pl.armory.reserve[slot], least)
