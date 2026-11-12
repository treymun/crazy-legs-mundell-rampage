## Saves written by earlier builds must keep loading. tools/saves/ holds real
## saves of every save version (v<version>_<name>.json) and what each should
## load as (expected.json); this loads each one, checks it, saves it again and
## checks the copy too.
##
##   Godot --headless --path godot --script res://tools/save_fixtures.gd   # OLD SAVES OK
##   ... save_fixtures.gd -- make   # add saves of this version
##
## When the save format changes: bump SessionStore.VERSION, add the upgrade
## step (save_upgrade.gd _upgrade_step), run with -- make to add saves of the
## new version, and keep the old ones.
extends SceneTree

const FOLDER := "res://tools/saves"

var failures: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	if OS.get_cmdline_user_args().has("make"):
		_make(main)
	else:
		_check(main)
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


## What a loaded game should show, to compare against expected.json.
func _summary(game: Game) -> Dictionary:
	var reserve := 0
	for n in game.armory.reserve:
		reserve += int(n)
	var alive := 0
	for enemy: Enemy in game.enemies:
		if enemy.alive:
			alive += 1
	var retained: Array = game.retained.keys()
	retained.sort()
	return {
		"level": game.level.id,
		"replay": game.replay,
		"health": snappedf(game.player.health, .01),
		"x": snappedf(game.player.x, .001),
		"y": snappedf(game.player.y, .001),
		"kills": game.kills,
		"reserve": reserve,
		"alive": alive,
		"retained": retained,
	}


func _play(game: Game, frames: int) -> void:
	var held := Game.Controls.new()
	held.fire = true
	held.forward = .6
	held.turn = .01
	for i in frames:
		game.tick(1.0 / 60.0, held)


func _make(main) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	var expected_path := FOLDER.path_join("expected.json")
	var expected: Dictionary = {}
	if FileAccess.file_exists(expected_path):
		expected = JSON.parse_string(FileAccess.get_file_as_string(expected_path))
	var prefix := "v%d_" % SessionStore.VERSION
	var made := {}

	main.start("hickston")
	_play(main.game, 240)
	made["hickston_fight"] = main.game

	var finished: Game = main.make_game("hickston")
	finished.finish_level("")
	main.start("fair", null, [["hickston", 0, 0, 0, 0, 0]], false, null)
	main.game.retained = {"hickston": finished}
	_play(main.game, 120)
	made["fair_carrying_hickston"] = main.game

	main.start("quarry", null, [], true, null)
	_play(main.game, 90)
	made["quarry_replay"] = main.game

	main.start("speedway", null, [], true, null)
	_play(main.game, 90)
	made["speedway_replay"] = main.game

	for name: String in made:
		var path := FOLDER.path_join(prefix + name + ".json")
		if not SessionStore.save(made[name], ProjectSettings.globalize_path(path)):
			failures.append("could not write " + path)
		expected[prefix + name + ".json"] = _summary(made[name])

	main.start("sawmill", null, [["hickston", 0, 0, 0, 0, 0], ["fair", 0, 0, 0, 0, 0]], false, null)
	_play(main.game, 60)
	var slot := FOLDER.path_join(prefix + "sawmill_slot.json")
	var slot_global := ProjectSettings.globalize_path(slot)
	if FileAccess.file_exists(slot_global):
		DirAccess.remove_absolute(slot_global)
	if not SessionStore.save_named(main.game, slot_global, "OLD SLOT", null):
		failures.append("could not write " + slot)
	var row := _summary(main.game)
	row["label"] = "OLD SLOT"
	expected[prefix + "sawmill_slot.json"] = row

	var file := FileAccess.open(ProjectSettings.globalize_path(expected_path), FileAccess.WRITE)
	file.store_string(JSON.stringify(expected, "\t", true))
	file.close()
	print("WROTE %d SAVES OF VERSION %d" % [made.size() + 1, SessionStore.VERSION])


func _check(main) -> void:
	var expected: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(FOLDER.path_join("expected.json"))
	)
	var versions := {}
	for name: String in expected:
		var row: Dictionary = expected[name]
		var path := ProjectSettings.globalize_path(FOLDER.path_join(name))
		versions[int(name.substr(1, name.find("_") - 1))] = true
		var make := Callable(main, "make_game")
		var game: Game = SessionStore.read(path, make, bool(row["replay"]))
		if game == null:
			failures.append("%s does not load (%s)" % [name, SessionStore.last_error])
			continue
		_compare(name, row, _summary(game))
		if row.has("label"):
			var meta: Array = SessionStore.slot_metadata(path, "")
			if meta[1] == null or String(meta[1][0]) != String(row["label"]):
				failures.append("%s: its slot label does not read back" % name)
		# Saved again by this build and loaded once more: still the same game.
		var copy := ProjectSettings.globalize_path("user://fixture-copy.json")
		if not SessionStore.save(game, copy):
			failures.append("%s: cannot save it again" % name)
			continue
		var again: Game = SessionStore.read(copy, make, bool(row["replay"]))
		if again == null:
			failures.append("%s: the copy does not load (%s)" % [name, SessionStore.last_error])
		else:
			_compare(name + " (saved again)", row, _summary(again))
		DirAccess.remove_absolute(copy)
		print("  %s loads" % name)
	for v in range(SessionStore.OLDEST_VERSION, SessionStore.VERSION + 1):
		if not versions.has(v):
			failures.append("no saves of version %d in tools/saves (run with -- make)" % v)
	var newer := {"version": SessionStore.VERSION + 1, "level": "hickston"}
	var older := {"version": SessionStore.OLDEST_VERSION - 1, "level": "hickston"}
	if SaveUpgrade.upgrade(newer) != null or SaveUpgrade.upgrade(older) != null:
		failures.append("a save from a newer build or older than OLDEST_VERSION is accepted")
	for failure in failures:
		push_error(failure)
	print("OLD SAVES OK" if failures.is_empty() else "OLD SAVES FAILED")


func _compare(name: String, want: Dictionary, got: Dictionary) -> void:
	for key: String in got:
		var a = want.get(key)
		var b = got[key]
		var same := str(a) == str(b)
		if typeof(b) == TYPE_FLOAT or typeof(b) == TYPE_INT:
			same = absf(float(a) - float(b)) < .002
		if not same:
			failures.append("%s: %s is %s, expected %s" % [name, key, str(b), str(a)])
