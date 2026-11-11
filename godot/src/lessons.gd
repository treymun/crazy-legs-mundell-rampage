## Teaching by doing. The first time something comes up (the first step, the
## first enemy, the first bad wound, a third gun, a while without the map) one
## line says which key, as the player has bound it, or which touch button does
## what about it; then never again on this profile. Shown only in real play
## (main_flow.gd turns Game.lessons on) and with TOOLTIPS / OBJECTIVES on, and
## only when no other notice is up.
class_name Lessons
extends RefCounted

const FILE := "user://lessons.json"

static var taught := {}
static var _loaded := false


static func tick(game) -> void:
	if not game.lessons or not game.hints or game.in_hub or game.message_until > game.clock:
		return
	if not _loaded:
		_loaded = true
		var parsed = JSON.parse_string(
			FileAccess.get_file_as_string(FILE) if FileAccess.file_exists(FILE) else ""
		)
		taught = parsed if parsed is Dictionary else {}
	var p = game.player
	var touch: bool = game.touch_aim
	if not taught.has("move") and game.clock > 1.2:
		_teach(
			game,
			"move",
			(
				"LEFT THUMB WALKS, RIGHT THUMB AIMS."
				if touch
				else (
					"%s %s %s %s WALK, THE MOUSE AIMS, %s RUNS."
					% [
						key("forward"),
						key("strafe_left"),
						key("back"),
						key("strafe_right"),
						key("run")
					]
				)
			)
		)
		return
	if not taught.has("fire") and _threat_in_view(game):
		_teach(
			game,
			"fire",
			(
				"FIRE SHOOTS. STRAIGHT GUNS FIRE BY THEMSELVES AT A FOE IN THE SIGHTS."
				if touch
				else "LEFT CLICK SHOOTS, %s RELOADS. RIGHT CLICK IS THE OTHER FIRE." % key("reload")
			)
		)
		return
	if not taught.has("heal") and p.health < 55 and _has_food(game):
		_teach(
			game,
			"heal",
			(
				"RIND, BEER AND SHINE PATCH YOU UP."
				if touch
				else (
					"%s EATS OR DRINKS WHAT IS PICKED, %s PICKS ANOTHER."
					% [key("use_item"), key("next_item")]
				)
			)
		)
		return
	if not taught.has("guns") and _guns(game) >= 3:
		_teach(
			game,
			"guns",
			(
				"NEXT CHANGES GUNS."
				if touch
				else (
					"NUMBER KEYS, %s AND %s CHANGE GUNS." % [key("prev_weapon"), key("next_weapon")]
				)
			)
		)
		return
	if not taught.has("map") and game.clock > 50.0 and game.objective_target() != null:
		_teach(
			game,
			"map",
			(
				"THE ARROW UP TOP POINTS THE WAY, WITH THE STEPS LEFT."
				if touch
				else "%s SHOWS THE MAP. THE ARROW UP TOP POINTS THE WAY." % key("map")
			)
		)


## The key bound to a play action, by name.
static func key(action: String) -> String:
	if InputMap.has_action(action):
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				return KeyBindings.key_name((event as InputEventKey).keycode)
	return "?"


static func _teach(game, id: String, text: String) -> void:
	taught[id] = true
	game.message(text, 4.5)
	var file := FileAccess.open(FILE, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(taught))


static func _threat_in_view(game) -> bool:
	for e: Enemy in game.enemies:
		if e.alive and e.hostile and e.alerted and e.player_seen:
			return true
	return false


static func _has_food(game) -> bool:
	for name: String in HUD.ITEMS:
		if int(game.inventory.get(name, 0)) > 0:
			return true
	return false


static func _guns(game) -> int:
	var count := 0
	for owned: bool in game.armory.owned:
		if owned:
			count += 1
	return count
