## The front end's replays (src/replay.gd): every local game played is
## recorded from its first tick (REPLAYS on, not online, not a tool, a tour or
## a bench), each action between ticks a key makes goes through act(), and the
## run is written to user://replays/ when its player dies or it ends, and to
## user://logs/session.replay every FLUSH_TICKS so a crash leaves one beside
## its crash log (src/crash_log.gd keeps it as crash-<stamp>.replay). The dev
## console's `replay save` writes the run now; `--replay=<file>` plays one in
## the game's own view (play_file).
##
## Writing happens on a worker thread (the bytes are put together on the main
## thread, the packing and the file on the worker), so a save costs a frame
## nothing much; nothing is written while the last write is still going.
class_name ReplayKeeper
extends RefCounted

const DIR := "user://replays"
## Replays kept in DIR (the newest).
const KEEP := 12
## The run so far goes to the session's file this often (30 s at 120 Hz).
const FLUSH_TICKS := 3600

## REPLAYS on and this kind of run recorded (main_state.gd apply_options).
var enabled := false
## The run being recorded (null: none).
var rec: Replay = null
## Its death or end was written already.
var saved := false
var last_path := ""
var _flushed_at := 0
var _task := -1
## The session's file beside the crash log (CrashLog.replay_path; "": none).
var session_path := ""


## The tick about to be played on `g` (main.gd advance): the recording starts
## on a game's first tick, so everything set up before it is in its keyframe.
## `first`: the frame's first tick (the keys and the rest ran before it).
func before(
	g: Game, options: Dictionary, mode_options: Dictionary, dt: float, c: Variant, first := true
) -> void:
	if not enabled:
		rec = null
		return
	if rec == null or rec.game != g:
		var setup := {
			"mode": Modes.mode_of(g),
			"count": g.players.size(),
			"options": mode_options.duplicate(true),
		}
		rec = Replay.record(g, options, setup)
		saved = false
		_flushed_at = 0
	rec.tick(dt, c, first)


## The tick was played: a death or the end writes the run; now and then the
## session's file is brought up to date.
## `last`: the frame's last tick (the front end runs after it).
func after(g: Game, last := true) -> void:
	if rec == null or rec.game != g:
		return
	rec.ticked(last or g.portal_request != "")
	if not saved and (g.defeated() or g.won or g.showing_tally):
		saved = true
		save("death" if g.defeated() else "end")
	elif session_path != "" and rec.ticks - _flushed_at >= FLUSH_TICKS:
		_flushed_at = rec.ticks
		_write(session_path, rec, "crash")


## An action of this machine's player between ticks: kept when `g` is the
## game being recorded, and done.
func act(g: Game, op: Array) -> Variant:
	if rec != null and rec.game == g:
		return rec.act(op)
	return Replay.apply_op(g, op)


## The settings changed under `g` mid-run (main_state.gd apply_options).
func options_changed(g: Game, options: Dictionary) -> void:
	if rec != null and rec.game == g:
		rec.set_options(options)


## Something changed `g` outside the tick and the actions (the dev console):
## a keyframe now.
func touched(g: Game) -> void:
	if rec != null and rec.game == g:
		rec.touch()


## Writes the run being recorded to DIR (`why`: death, end, asked). Returns
## the file's path ("" when nothing is recorded).
func save(why: String) -> String:
	if rec == null or rec.ticks == 0:
		return ""
	DirAccess.make_dir_recursive_absolute(DIR)
	var stamp := Time.get_datetime_string_from_system(false, false).replace(":", "").replace(
		"T", "-"
	)
	var path := DIR.path_join("%s-%s-%s.replay" % [stamp, rec.game.level.id, why])
	var n := 1
	while FileAccess.file_exists(path):
		n += 1
		path = DIR.path_join("%s-%s-%s-%d.replay" % [stamp, rec.game.level.id, why, n])
	_write(path, rec, why)
	last_path = path
	return path


## Waits for a write still going (the program closing).
func settle() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _write(path: String, r: Replay, why: String) -> void:
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	r.reason = why
	var data := r.pack()
	var prune := path.get_base_dir() == DIR
	var job := func() -> void:
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_buffer(Replay.bytes_of(data))
			f.close()
		if prune:
			ReplayKeeper._prune()
	if OS.has_feature("web"):
		job.call()
	else:
		_task = WorkerThreadPool.add_task(job, false, "replay write")


## Keeps the KEEP newest replays in DIR.
static func _prune() -> void:
	var names: Array = []
	for name in DirAccess.get_files_at(DIR):
		if name.ends_with(".replay"):
			names.append(name)
	names.sort()
	while names.size() > KEEP:
		DirAccess.remove_absolute(DIR.path_join(str(names.pop_front())))


## The file `--replay=` names: a path, or a name in DIR.
static func find(name: String) -> String:
	if FileAccess.file_exists(name):
		return name
	for path: String in [DIR.path_join(name), DIR.path_join(name + ".replay")]:
		if FileAccess.file_exists(path):
			return path
	return ""


## Plays the replay at `path` in the game's own view (`--replay=`): the
## keys do nothing to it, Esc leaves. False when there is none to play.
static func play_file(main: MainFlow, path: String) -> bool:
	var found := find(path)
	var rep := Replay.load_file(found) if found != "" else null
	if rep == null:
		main.notice("NO REPLAY AT %s" % path.to_upper(), 4.0)
		return false
	var pb := Replay.Playback.new(rep)
	var g := pb.start(Callable(main, "make_game"))
	main.replays.enabled = false
	main.replay_play = pb
	main.mode_name = ""
	main.game = g
	g.tone = main.tone_table
	main.state = "play"
	main.sound.pause_world()
	main.play_music()
	main.grab(true)
	var line := "REPLAY: %s, %d TICKS" % [str(rep.header["level"]).to_upper(), rep.last_tick()]
	if pb.note != "":
		line += " (%s)" % pb.note.to_upper()
	main.notice(line, 4.0)
	print("replay: playing %s (%s)" % [ProjectSettings.globalize_path(found), rep.covers()])
	return true


## One frame of a replay playing (main.gd advance): its ticks at the game's
## pace; at the end (or the first hash that differs) it says so once.
static func advance(main: MainState, elapsed: float) -> void:
	var pb := main.replay_play
	main.accumulator = minf(.1, main.accumulator + elapsed)
	var steps := int((main.accumulator + 1e-9) / MainState.SIM_STEP)
	main.accumulator = maxf(0.0, main.accumulator - steps * MainState.SIM_STEP)
	var parted := pb.diverged >= 0
	for _i in steps:
		if not pb.step():
			break
	if not parted and pb.diverged >= 0:
		main.notice("THE REPLAY PARTED FROM PLAY AT TICK %d" % pb.diverged, 5.0)
		print("replay: parted at tick %d (last match %d)" % [pb.diverged, pb.last_good])
	if pb.done and pb.note != "over":
		pb.note = "over"
		var ok := pb.diverged < 0 and pb.end_matches()
		main.notice("REPLAY OVER%s. ESC FOR THE TITLE" % ("" if ok else " (IT PARTED)"), 6.0)
		print("replay: over at tick %d, %s" % [pb.tick, "exact" if ok else "parted"])
