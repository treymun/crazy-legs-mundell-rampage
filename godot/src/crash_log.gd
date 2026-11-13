## The crash and error log: every script error, engine error and warning the
## running game meets, with what was going on (version, screen, level, tick,
## mode, players, the last controls), written to user://logs/session.log as
## it happens and a summary at a clean exit. Godot's own Logger hook
## (OS.add_logger) hands it each error, from any thread.
##
## A lock file (user://logs/session.lock) says a session is running; a clean
## exit removes it. When the next launch finds it (a crash, a kill, a power
## cut), the last session's log is kept aside as crash-<stamp>.log and one
## line goes to the console. Earlier clean logs rotate as session-<stamp>.log
## (KEEP of each). A session that went to the background on a phone and was
## closed there by the system is not counted as a crash.
##
## Nothing runs per frame: the hook is called only when the engine reports
## something, the context is read then (on the main thread; an error on a
## worker thread notes the thread), and the same error at the same place is
## written out only REPEATS times, then counted. Tools (a SceneTree script)
## and the browser build do not write a log (main.gd starts it only for a real
## launch); `tally()` gives tools a counter of errors without a file
## (tools/multi_bots.gd fails a run on any).
##
## Script backtraces come with every error in a debug build and the editor;
## an exported release build has them only with
## debug/settings/gdscript/always_track_call_stacks, which costs every call
## and is left off.
class_name CrashLog
extends Logger

const DIR := "user://logs"
const LOG := "user://logs/session.log"
const LOCK := "user://logs/session.lock"
## Clean session logs and crash logs kept, each.
const KEEP := 5
## The same error at the same place written out at most this many times.
const REPEATS := 5
## A session log stops growing here (the summary still goes on the end).
const MAX_BYTES := 2 * 1024 * 1024
## Lines of plain output kept for an error's context.
const RECENT := 12
const KINDS := ["ERROR", "WARNING", "SCRIPT ERROR", "SHADER ERROR"]

## The log of this session (null: none started, or a tool's tally).
static var current: CrashLog = null

var errors := 0
var warnings := 0
## The first few errors as one line each (a tool's report).
var first_errors: PackedStringArray = []
## A note left at the last launch about the session before (or "").
var last_session := ""
var _file: FileAccess = null
var _main: WeakRef = null
var _mutex := Mutex.new()
var _busy := false
var _by_place := {}
var _recent: PackedStringArray = []
var _notes: PackedStringArray = []
var _started_unix := 0.0
var _started_text := ""
var _written := 0
var _dir := DIR
var _path := LOG
var _lock_path := LOCK


## Starts the session's log for the real game (`main` is the front end, read
## for context when something goes wrong). Prints a line when the last
## session ended without a clean exit. Returns the logger (also `current`).
static func start(main, dir := DIR) -> CrashLog:
	var logger := CrashLog.new()
	logger._main = weakref(main)
	logger._started_unix = Time.get_unix_time_from_system()
	logger._started_text = Time.get_datetime_string_from_system(false, true)
	logger._dir = dir
	logger._path = dir.path_join("session.log")
	logger._lock_path = dir.path_join("session.lock")
	DirAccess.make_dir_recursive_absolute(dir)
	logger._open()
	OS.add_logger(logger)
	current = logger
	return logger


## A counter of errors and warnings with no file (tools): stop() when done.
static func tally() -> CrashLog:
	var logger := CrashLog.new()
	OS.add_logger(logger)
	return logger


## Leaves a line in the log (a level started, a save): what led up to an error.
static func note(text: String) -> void:
	if current != null:
		current._note(text)


func _note(text: String) -> void:
	_mutex.lock()
	var line := "%s  %s" % [_clock(), text]
	_notes.append(line)
	if _notes.size() > 40:
		_notes.remove_at(0)
	_write(line)
	_mutex.unlock()


## Stops listening (a tool's tally, or before close()).
func stop() -> void:
	OS.remove_logger(self)
	if current == self:
		current = null


## A clean exit: the summary, then the lock goes.
func close() -> void:
	stop()
	_mutex.lock()
	if _file != null:
		_write_raw(_summary())
		_file.close()
		_file = null
		DirAccess.remove_absolute(_lock_path)
	_mutex.unlock()


## Gone to the background (a phone): the system may close it there, which is
## not a crash. Back in front, a session again.
func backgrounded(away: bool) -> void:
	if _file != null:
		_write_lock("background" if away else "running")


# ------------------------------------------------------------------ the hook


func _log_error(
	function: String,
	file: String,
	line: int,
	code: String,
	rationale: String,
	_editor_notify: bool,
	error_type: int,
	script_backtraces: Array[ScriptBacktrace]
) -> void:
	_mutex.lock()
	if _busy:
		# An error while writing one (the file itself): never recurse.
		_mutex.unlock()
		return
	_busy = true
	if error_type == ERROR_TYPE_WARNING:
		warnings += 1
	else:
		errors += 1
	var what := rationale if rationale != "" else code
	var kind: String = KINDS[clampi(error_type, 0, KINDS.size() - 1)]
	var place := "%s:%d" % [file, line]
	if error_type != ERROR_TYPE_WARNING and first_errors.size() < 8:
		first_errors.append("%s: %s (%s, %s)" % [kind, what, function, place])
	var key := "%d %s %s" % [error_type, place, code]
	var seen := int(_by_place.get(key, 0)) + 1
	_by_place[key] = seen
	if _file != null and seen <= REPEATS:
		var out := PackedStringArray()
		out.append("")
		out.append("%s  %s: %s" % [_clock(), kind, what])
		out.append("  at %s (%s)" % [function, place])
		if rationale != "" and code != "" and code != rationale:
			out.append("  code: %s" % code)
		for trace: ScriptBacktrace in script_backtraces:
			if trace != null and not trace.is_empty():
				for row in trace.format().split("\n", false):
					out.append("  " + row.strip_edges(false, true))
		out.append_array(_context())
		if seen == REPEATS:
			out.append("  (seen %d times here: from now on only counted)" % REPEATS)
		_write("\n".join(out))
	_busy = false
	_mutex.unlock()


func _log_message(message: String, error: bool) -> void:
	if _file == null:
		return
	_mutex.lock()
	_recent.append(("! " if error else "") + message.strip_edges())
	if _recent.size() > RECENT:
		_recent.remove_at(0)
	_mutex.unlock()


# ------------------------------------------------------------------ context


## What was going on: read only on the main thread (the game is not safe to
## read from another while it runs).
func _context() -> PackedStringArray:
	var out := PackedStringArray()
	out.append(
		(
			"  version %s, %s, %s"
			% [
				ProjectSettings.get_setting("application/config/version", "?"),
				OS.get_name(),
				"main thread" if _on_main() else "thread %d" % OS.get_thread_caller_id()
			]
		)
	)
	var main = _main.get_ref() if _main != null else null
	if main == null or not _on_main():
		return out
	var state := String(main.get("state"))
	var game = main.get("game")
	if game == null:
		out.append("  screen %s, no game" % state)
		return out
	var mode := "campaign"
	if game.in_hub:
		mode = "crossroads"
	elif game.replay:
		mode = "replay"
	elif game.revisiting:
		mode = "revisit"
	if "mode" in game:
		mode += " / " + str(game.get("mode"))
	out.append(
		(
			"  screen %s, level %s (layout %d), tick %d (%.2f s), mode %s, %d enemies"
			% [
				state,
				game.level.id,
				game.level.layout,
				roundi(game.clock * 60.0),
				game.clock,
				mode,
				game.enemies.size()
			]
		)
	)
	for p: Player in game.players:
		out.append(
			(
				"  player %d%s: (%.2f, %.2f) facing %.2f, health %d, gun %d%s"
				% [
					p.slot,
					" (here)" if p == game.local_player else "",
					p.x,
					p.y,
					p.angle,
					p.health,
					p.armory.active if p.armory != null else -1,
					"" if (is_finite(p.x) and is_finite(p.y)) else " NOT A NUMBER"
				]
			)
		)
	var c = main.get("last_controls")
	if c != null:
		out.append(
			(
				"  last controls: forward %.2f strafe %.2f turn %.3f look %.2f%s%s%s%s%s"
				% [
					c.forward,
					c.strafe,
					c.turn,
					c.look,
					" run" if c.running else "",
					" fire" if c.fire else "",
					" alt" if c.alt_fire else "",
					" jump" if c.jump else "",
					" crouch" if c.crouch else ""
				]
			)
		)
	if not _recent.is_empty():
		out.append("  output before it:")
		for row in _recent.slice(maxi(0, _recent.size() - 4)):
			out.append("    " + row.left(200))
	return out


func _on_main() -> bool:
	return OS.get_thread_caller_id() == OS.get_main_thread_id()


func _clock() -> String:
	return (
		"%7.1f s"
		% ((Time.get_unix_time_from_system() - _started_unix) if _started_unix > 0.0 else 0.0)
	)


# ------------------------------------------------------------------ files


## The last session's log aside (as a crash when its lock is still there),
## old logs pruned, a new log and lock.
func _open() -> void:
	var lock := _read_lock()
	if not lock.is_empty() and _still_running(int(lock.get("pid", 0))):
		# Another copy of the game is running on this profile: a log of our own
		# (never rotated or pruned).
		_path = "%s/live-%d.log" % [_dir, OS.get_process_id()]
		_lock_path = "%s/live-%d.lock" % [_dir, OS.get_process_id()]
	elif FileAccess.file_exists(_dir.path_join("session.log")):
		var stamp := _stamp(FileAccess.get_modified_time(_dir.path_join("session.log")))
		var crashed := not lock.is_empty() and String(lock.get("state", "")) != "background"
		var kept := "%s/%s-%s.log" % [_dir, "crash" if crashed else "session", stamp]
		var n := 1
		while FileAccess.file_exists(kept):
			n += 1
			kept = "%s/%s-%s-%d.log" % [_dir, "crash" if crashed else "session", stamp, n]
		DirAccess.rename_absolute(_dir.path_join("session.log"), kept)
		if crashed:
			last_session = (
				"CRASH LOG: the last session (version %s, started %s) did not close cleanly; its log is %s"
				% [
					lock.get("version", "?"),
					lock.get("started", "?"),
					ProjectSettings.globalize_path(kept)
				]
			)
			print(last_session)
	_prune("session-")
	_prune("crash-")
	_file = FileAccess.open(_path, FileAccess.WRITE)
	if _file == null:
		return
	_write_lock("running")
	_write_raw(
		(
			"Crazy Legs Mundell Rampage %s, %s %s, started %s, %s"
			% [
				ProjectSettings.get_setting("application/config/version", "?"),
				OS.get_name(),
				OS.get_version(),
				Time.get_datetime_string_from_system(false, true),
				Engine.get_version_info().get("string", "")
			]
		)
	)
	if last_session != "":
		_write_raw(last_session)


func _write_lock(state: String) -> void:
	var f := FileAccess.open(_lock_path, FileAccess.WRITE)
	if f == null:
		return
	var lock := {
		"pid": OS.get_process_id(),
		"version": ProjectSettings.get_setting("application/config/version", "?"),
		"started": _started_text,
		"state": state,
	}
	f.store_string(JSON.stringify(lock))
	f.close()


func _read_lock() -> Dictionary:
	if not FileAccess.file_exists(_dir.path_join("session.lock")):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(_dir.path_join("session.lock")))
	return parsed if parsed is Dictionary else {"state": "unreadable"}


func _still_running(pid: int) -> bool:
	return pid > 0 and pid != OS.get_process_id() and OS.is_process_running(pid)


## Keeps the KEEP newest logs whose names start with `prefix`.
func _prune(prefix: String) -> void:
	var names: Array = []
	for name in DirAccess.get_files_at(_dir):
		if name.begins_with(prefix) and name.ends_with(".log"):
			names.append(name)
	names.sort()
	while names.size() > KEEP:
		DirAccess.remove_absolute(_dir.path_join(String(names.pop_front())))


func _stamp(unix: int) -> String:
	return Time.get_datetime_string_from_unix_time(unix).replace(":", "").replace("T", "-")


func _write(text: String) -> void:
	if _file == null or _written > MAX_BYTES:
		return
	_write_raw(text)
	if _written > MAX_BYTES:
		_write_raw("(the log is full: errors from here on are only counted)")


func _write_raw(text: String) -> void:
	# An error the file itself reports while writing is dropped (see _log_error).
	var was := _busy
	_busy = true
	_file.store_line(text)
	_file.flush()
	_written += text.length() + 1
	_busy = was


func _summary() -> String:
	var out := PackedStringArray()
	out.append("")
	out.append(
		(
			"SESSION SUMMARY: %.0f s, ended cleanly %s; %d error(s), %d warning(s)"
			% [
				Time.get_unix_time_from_system() - _started_unix,
				Time.get_datetime_string_from_system(false, true),
				errors,
				warnings
			]
		)
	)
	var places: Array = _by_place.keys()
	places.sort_custom(func(a, b): return int(_by_place[a]) > int(_by_place[b]))
	for key in places.slice(0, 10):
		var parts := String(key).split(" ", true, 2)
		out.append(
			(
				"  %5d x %s at %s%s"
				% [
					_by_place[key],
					KINDS[clampi(int(parts[0]), 0, 3)],
					parts[1],
					(" " + parts[2]) if parts.size() > 2 and parts[2] != "" else ""
				]
			)
		)
	if not _notes.is_empty():
		out.append("  last notes:")
		for row in _notes.slice(maxi(0, _notes.size() - 8)):
			out.append("    " + row)
	return "\n".join(out)
