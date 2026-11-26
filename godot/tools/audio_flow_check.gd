## Mundell's voice and the player's own sounds through a run of chapters, on
## the real Sound (bark_check hears the talk through a stand-in that never
## runs out of voices; this one is the mixer the player hears). Headless.
##
## 3.13.0 bug ("audio is buggy after the third level: Mundell stops talking
## and you don't hear the player's sounds"): Sound's loops (the fuse's hiss,
## the ripsaw's motor, a burn barrel's crackle) set looping on the cached
## stream that the one-shots of the same cue share (a tosser's fuse, the
## mower's engine notes and the Foreman's saw, a fire's crackle). From then on
## every one-shot of that cue looped for good on its effect voice, and nothing
## ever stopped it (pause_world left the effects alone), level after level,
## until all EFFECT_VOICES were held: no free voice for Mundell's lines (they
## are effects) or the player's steps, pickups, swaps and reloads.
##
## The checks: every cue Sound loops still plays once as an effect; and over
## CHAPTERS in turn, with the bot playing each a stretch and the game's own
## loop-and-one-shot pairs heard on the way (a lit fuse beside a tosser's, the
## ripsaw beside the mower and the Foreman's saw, a burn barrel beside a
## fire), every effect voice is free once the takes have played out, at every
## chapter's end and after the level-end hush; Mundell's line and the
## player's step and pickup still get a voice in every chapter. The headless
## mixer does not keep the game's time (the game runs far faster than real
## time here), so Mixer plays it: a take ends when its length has gone by on
## the game clock, a looping one never.
##
##   godot --headless --path godot --script res://tools/audio_flow_check.gd
##       [-- chapters=hickston,fair,sawmill,quarry] [seconds=45]
extends SceneTree

const ScratchProfile := preload("res://tools/scratch_profile.gd")
const Pilot := preload("res://tools/balance_pilot.gd")
const STEP := 1.0 / 60.0
const CHAPTERS := ["hickston", "fair", "sawmill", "quarry"]
## The cues Sound loops on a voice of their own (set_fuse, set_tool, set_bed)
## that the game also plays as one-shots (boggs.gd, swamp_king.gd and
## squad_feature.gd the fuse; foreman.gd and the mower's engine the saw;
## fire.gd the crackle).
const SHARED := ["fuse_hiss", "saw_motor", "fire_crackle"]

var main
var failures: Array = []
var seconds := 45.0
## `-- natural`: the bot alone, none of the pairs played on purpose.
var natural := false


## The mixer's clock kept on the game's: a one-shot voice stops when its take
## has played out, a looping one plays on (as it would, for good).
class Mixer:
	extends RefCounted
	var voices: Array = []
	## Instance id of each voice's player -> [stream, started on the clock].
	var started := {}
	## How many takes started of each cue.
	var heard := {}

	func _init(s: Sound) -> void:
		voices = s._one_shots()

	func step(clock: float) -> void:
		for v: Sound.Voice in voices:
			var id := v.player.get_instance_id()
			if not v.player.playing:
				started.erase(id)
				continue
			var row: Variant = started.get(id)
			if row == null or row[0] != v.player.stream:
				started[id] = [v.player.stream, clock]
				heard[v.cue] = int(heard.get(v.cue, 0)) + 1
				continue
			var stream: AudioStream = row[0]
			if Assets.loops(stream):
				continue
			var length := stream.get_length() / maxf(.1, v.player.pitch_scale)
			if clock - float(row[1]) >= length:
				v.player.stop()
				started.erase(id)

	## Every one-shot started by `clock` played out `wait` seconds after: the
	## cues still playing then.
	func settle(clock: float, wait := 12.0) -> Array:
		step(clock)
		step(clock + wait)
		var held: Array = []
		for v: Sound.Voice in voices:
			if v.player.playing:
				held.append(v.cue)
		return held

	func count(part: String) -> int:
		var n := 0
		for cue: String in heard:
			if cue.contains(part):
				n += int(heard[cue])
		return n


func _init() -> void:
	if ScratchProfile.refuse(self, "AUDIO FLOW CHECK"):
		return
	_run.call_deferred()


func _run() -> void:
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	var chapters: Array = CHAPTERS.duplicate()
	for arg in OS.get_cmdline_user_args():
		var a := String(arg)
		if a.begins_with("chapters="):
			chapters = Array(a.substr(9).split(",", false))
		elif a == "natural":
			natural = true
		elif a.begins_with("seconds="):
			seconds = float(a.substr(8))
	var s: Sound = main.sound
	print("AUDIO FLOW (the real Sound, %d s a chapter)" % int(seconds))
	_loops_apart(s)
	var mixer := Mixer.new(s)
	for chapter: String in chapters:
		_chapter(s, mixer, str(chapter))
	print("")
	print(
		(
			"AUDIO FLOW OK"
			if failures.is_empty()
			else "%d AUDIO FLOW CHECK(S) FAILED" % failures.size()
		)
	)
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


## Each cue Sound loops (and the bed cues that are also one-shots) still
## plays once as an effect while its loop goes on.
func _loops_apart(s: Sound) -> void:
	s.set_fuse(true)
	s.set_tool(true)
	s.set_bed(Sound.BED_NEAR, "fire_crackle", .5)
	var looping := (
		Assets.loops(s._fuse.player.stream)
		and Assets.loops(s._tool.player.stream)
		and Assets.loops(s._beds[Sound.BED_NEAR].player.stream)
	)
	_check(looping, "the fuse, the ripsaw's motor and a burn barrel's bed loop")
	var once: Array = []
	for cue: String in SHARED:
		if Assets.loops(s.assets.cue(cue)):
			once.append(cue)
	_check(once.is_empty(), "their cues still play once as effects (looping: %s)" % [once])
	s.set_fuse(false)
	s.set_tool(false)
	s.set_bed(Sound.BED_NEAR, "", 0.0)
	# And a one-shot voice that loops all the same (none should) is let go
	# when play stops (pause_world: the level's end, a menu, the next level).
	var stuck: Sound.Voice = s._effects[0]
	stuck.cue = "fuse_hiss"
	stuck.player.stream = s.assets.looped("fuse_hiss")
	stuck.player.play()
	s.pause_world()
	_check(not stuck.player.playing, "a looping take on an effect voice stops when play stops")


## The chapter from its kit, the bot playing it `seconds` with talk on, the
## game's loop-and-one-shot pairs heard every few seconds; then the checks.
func _chapter(s: Sound, mixer: Mixer, chapter: String) -> void:
	main.start(chapter, null, [], false, null)
	var g: Game = main.game
	NetCoop.chapter_kit(g, chapter)
	g.configure({"difficulty": 1})
	g.rng = GameState.Rng.new(1009)
	g.chatter = CussLines.CUSSIN
	g.barks.enabled = true
	g.cheats.god = true
	var pilot := Pilot.new(2, 1)
	mixer.heard.clear()
	var next_pair := 2.0
	var end := g.clock + seconds
	while g.clock < end and not g.won:
		if g.clock >= next_pair and not natural:
			next_pair = g.clock + 4.0
			_pairs(g, s)
		g.tick(STEP, pilot.steer(g))
		pilot.moved(g)
		mixer.step(g.clock)
	var said := mixer.count("mundell_")
	var steps := mixer.count("step_")
	var free_now := 0
	for v: Sound.Voice in s._effects:
		free_now += 0 if v.player.playing else 1
	print(
		(
			"  %-9s %.0f s: Mundell said %d, steps %d, effect voices free %d of %d"
			% [chapter, g.clock, said, steps, free_now, s._effects.size()]
		)
	)
	_check(said > 0, "%s: Mundell says his lines aloud as it is played (%d)" % [chapter, said])
	_check(steps > 0, "%s: the player's steps are heard as it is played (%d)" % [chapter, steps])
	var held := mixer.settle(g.clock)
	_check(held.is_empty(), "%s: every effect voice comes free (held: %s)" % [chapter, held])
	# Mundell's line, forced past his gaps, and the player's own sounds.
	g.barks.next_any = 0.0
	g.barks.say(g, "kill", true)
	_check(_on_voice(s, "mundell_"), "%s: Mundell's line gets a voice" % chapter)
	g.sound.play("step_gravel_0")
	g.sound.play("pickup")
	_check(_on_voice(s, "step_gravel"), "%s: the player's step gets a voice" % chapter)
	# The level ends the way the game ends it (finish_level: pause_world),
	# and nothing it played is left playing for the next.
	g.finish_level("gate")
	held = mixer.settle(g.clock, 20.0)
	_check(
		held.is_empty(), "%s: nothing is left playing after the level ends (%s)" % [chapter, held]
	)


## What the game plays in the same few seconds now and then: the player's lit
## fuse and a tosser's, the ripsaw's motor and the mower's engine (the
## Foreman's saw), a burn barrel's bed and a fire's crackle nearby.
func _pairs(g: Game, s: Sound) -> void:
	var p := g.local_player
	s.set_fuse(true)
	s.set_tool(true)
	s.set_bed(Sound.BED_NEAR, "fire_crackle", .4)
	for cue: String in SHARED:
		g.sound_at(cue, p.x + 1.5, p.y, .8)


func _on_voice(s: Sound, part: String) -> bool:
	for v: Sound.Voice in s._effects:
		if v.player.playing and v.cue.contains(part):
			return true
	return s._priority.player.playing and s._priority.cue.contains(part)
