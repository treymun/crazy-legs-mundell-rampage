## The checkpoint at the boss door: a save (SessionStore's own format, no new
## version) of the moment a chapter's boss fight began, in a file of its own
## beside the quicksave, boss-checkpoint-<chapter>.json (-replay for a replay
## run). features/boss_checkpoint.gd takes it; the death screen offers RETRY
## THE FIGHT while it matches the run (main_flow.gd retry_fight), which loads it
## with the boss at full health and the player back at the arena's door.
## Cleared when the chapter is won, and a chapter's start clears every other
## chapter's. Tool scripts keep theirs under the cache folder, never in the
## player's profile.
class_name BossDoor
extends RefCounted


static func folder() -> String:
	var loop := Engine.get_main_loop()
	if loop != null and loop.get_script() != null:
		return OS.get_cache_dir().path_join("clmr-boss-door")
	return SessionStore.data_directory()


static func path(level_id: String, replay: bool) -> String:
	return folder().path_join("boss-checkpoint-%s%s.json" % [level_id, "-replay" if replay else ""])


static func write(game) -> bool:
	return SessionStore.save(game, path(game.level.id, game.replay))


static func clear(level_id: String, replay: bool) -> void:
	var file := path(level_id, replay)
	if FileAccess.file_exists(file):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file))


## A chapter starts: the other chapters' checkpoints (of the same kind of run) go.
static func clear_others(level_id: String, replay: bool) -> void:
	for other: String in Campaign.ORDER:
		if other != level_id:
			clear(other, replay)


static func clear_all() -> void:
	for level_id: String in Campaign.ORDER:
		clear(level_id, false)
		clear(level_id, true)


## The token the checkpoint on file was taken with for `kind` ("" for none).
static func token_on_file(level_id: String, replay: bool, kind: String) -> String:
	var file := path(level_id, replay)
	if not FileAccess.file_exists(file):
		return ""
	var doc = JSON.parse_string(FileAccess.get_file_as_string(file))
	if not (doc is Dictionary) or String(doc.get("level", "")) != level_id:
		return ""
	var state = doc.get("features", {}).get("boss_checkpoint", {})
	if not (state is Dictionary) or not (state.get("taken", {}) is Dictionary):
		return ""
	return String(state["taken"].get(kind, ""))


## The fight again: the checkpoint loaded, the player at the door, the boss
## whole, nothing in the air. Null when the file is gone or no longer loads.
static func restore(make_game: Callable, current) -> Game:
	var loaded := SessionStore.read(
		path(current.level.id, current.replay), make_game, current.replay, current.level.id
	)
	if loaded == null:
		return null
	var feature = loaded.features.get("boss_checkpoint")
	if feature == null or feature.door.size() < 3:
		return null
	var p := loaded.player
	p.x = float(feature.door[0])
	p.y = float(feature.door[1])
	p.vx = 0.0
	p.vy = 0.0
	p.air = 0.0
	p.vertical_speed = 0.0
	p.pitch = 0.0
	p.crouched = false
	p.eye = loaded.world.elevation(p.x, p.y) + .95
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
		p.angle = float(feature.door[2])
	loaded.shots.clear()
	loaded.hazards.clear()
	loaded.blasts.clear()
	loaded.armory.fuse = 0.0
	loaded.armory.tnt_latched = false
	loaded.spawn_grace = maxf(loaded.spawn_grace, 1.5)
	loaded.district = int(loaded.world.area[loaded.world.cell(p.x, p.y)])
	loaded.message("BACK AT THE DOOR. SAME GUNS, SAME BOSS. GIT 'EM.", 3.5)
	return loaded
