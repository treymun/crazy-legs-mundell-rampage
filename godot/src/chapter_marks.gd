## The files a chapter is picked up from after a death (pass 15): saves in
## SessionStore's own format (no version of their own) beside the quicksave,
## one of each kind a chapter:
##   BOSS   boss-checkpoint-<chapter>.json, taken as a boss fight begins
##          (features/boss_checkpoint.gd; boss_door.gd retries it);
##   MARKER marker-<chapter>.json, a trail marker taken on the way
##          (features/trail_marker.gd; BACK TO THE MARKER), and the one
##          before it in BEFORE, marker-before-<chapter>.json (a marker
##          died at again straight after is given up for that one).
## A replay run's are -replay files, a co-op game's -party files (the party's
## fight or marker never takes the place of the host's own chapter's). Each
## feature keeps a token in its features block that the file must hold, so a
## file left by another run is never offered. A win clears the chapter's, a
## chapter's start clears every other chapter's. Tool scripts keep theirs
## under the cache folder, never in the player's profile.
class_name ChapterMarks
extends RefCounted

const BOSS := "boss-checkpoint"
const MARKER := "marker"
const BEFORE := "marker-before"
const KINDS: Array[String] = [BOSS, MARKER, BEFORE]

## A write going on a worker thread (-1 none), and whether settle() is hung
## on the scene tree's root leaving: the program closing waits for the write
## (a task never waited for crashed it on quit, pass 15).
static var _task := -1
static var _exit_hooked := false


static func folder() -> String:
	var loop := Engine.get_main_loop()
	if loop != null and loop.get_script() != null:
		return OS.get_cache_dir().path_join("clmr-boss-door")
	return SessionStore.data_directory()


static func path(kind: String, level_id: String, replay: bool) -> String:
	return folder().path_join("%s-%s%s.json" % [kind, level_id, "-replay" if replay else ""])


## A co-op game's file is a file of its own (-party).
static func path_of(kind: String, game: Game) -> String:
	if Modes.mode_of(game) == Modes.COOP:
		return folder().path_join("%s-%s-party.json" % [kind, game.level.id])
	return path(kind, game.level.id, game.replay)


static func write(kind: String, game: Game) -> bool:
	settle()
	return SessionStore.save(game, path_of(kind, game))


## Written without holding the tick up: the save put together here (a deep
## copy, so play may go on changing the game), turned into text and written
## on a worker thread (a few milliseconds a chapter on the desktop, more on a
## phone, once a minute or so). Whatever reads the file waits for it first.
## `keep`: the file there now is moved to that kind's first.
static func write_soon(kind: String, game: Game, keep := "") -> void:
	settle()
	var doc: Dictionary = SessionStore.document(game).duplicate(true)
	var file := path_of(kind, game)
	var kept := path_of(keep, game) if keep != "" else ""
	var job := func() -> void:
		var previous := SessionStore.readable_path(file)
		if kept != "" and FileAccess.file_exists(previous):
			SessionStore._write_atomic(kept, FileAccess.get_file_as_string(previous))
		SessionStore.write_document(file, doc)
	if OS.has_feature("web"):
		job.call()
	else:
		_hook_exit()
		_task = WorkerThreadPool.add_task(job, false, "chapter mark")


## settle() runs as the scene tree's root leaves (the program closing).
static func _hook_exit() -> void:
	if _exit_hooked:
		return
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var tree: SceneTree = loop
		tree.root.tree_exiting.connect(Callable(ChapterMarks, &"settle"))
		_exit_hooked = true


## `from`'s file put in place of `to`'s (a copy: `from`'s stays).
static func promote(from: String, to: String, game: Game) -> bool:
	settle()
	var source := SessionStore.readable_path(path_of(from, game))
	if not FileAccess.file_exists(source):
		return false
	return SessionStore._write_atomic(path_of(to, game), FileAccess.get_file_as_string(source))


## Waits for a write still going.
static func settle() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


static func clear(kind: String, level_id: String, replay: bool) -> void:
	settle()
	var file := ProjectSettings.globalize_path(path(kind, level_id, replay))
	for target: String in [file, file + SessionStore.BACKUP_SUFFIX]:
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(target)


## A chapter starts: the other chapters' files (of the same kind of run) go.
static func clear_others(level_id: String, replay: bool) -> void:
	for other: String in Campaign.ORDER:
		if other != level_id:
			for kind: String in KINDS:
				clear(kind, other, replay)


static func clear_all() -> void:
	for level_id: String in Campaign.ORDER:
		for kind: String in KINDS:
			clear(kind, level_id, false)
			clear(kind, level_id, true)


## The features block's `feature` state in the file at `file` when it is a
## save of `level_id` ({} for none).
static func state_on_file(file: String, level_id: String, feature: String) -> Dictionary:
	settle()
	file = SessionStore.readable_path(file)
	if not FileAccess.file_exists(file):
		return {}
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
	if not (doc is Dictionary):
		return {}
	var sheet: Dictionary = doc
	if str(sheet.get("level", "")) != level_id:
		return {}
	var features: Variant = sheet.get("features", {})
	if not (features is Dictionary):
		return {}
	var block: Dictionary = features
	var state: Variant = block.get(feature, {})
	if not (state is Dictionary):
		return {}
	var out: Dictionary = state
	return out


## The game in `kind`'s file for `current`'s chapter, just loaded (null when
## the file is gone or no longer loads).
static func read(kind: String, make_game: Callable, current: Game) -> Game:
	settle()
	return SessionStore.read(path_of(kind, current), make_game, current.replay, current.level.id)
