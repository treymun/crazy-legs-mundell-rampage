## Every level load lets go of the last one, headless (Game.dispose(),
## src/game_pool.gd; tools/check_fixes.gd runs it, it also runs on its own):
##
##   Godot --headless --path <project> --script res://tools/leak_check.gd [-- rounds=N]
##
## A game holds its features and they hold it (the gore, the players' voices,
## the listeners of its events the same), a cycle reference counting never
## frees: before 3.3.x every load kept the last game's 1,300-odd objects for
## good. This plays, round after round, games made directly and let go with
## dispose() (the campaign, co-op, deathmatch, COUNTY RUN, the range, the
## Crossroads, a server's host game), then the front end's own flow
## (main_flow.gd: a chapter, the Crossroads, the range and back, a COUNTY
## RUN, co-op, a deathmatch, back to the title), and holds the object count
## after each round against the one before: the first round fills the caches
## (art, sheets, tuning), every later one must come back to the same level.
## Each game let go must be freed, too (a weak reference to it comes back
## empty). Fails on any script or engine error.
extends SceneTree

## Objects a round may leave over the last one (caches keyed per play, the
## odd pooled sprite): nothing like the 1,300 of one leaked game.
const SLACK := 40
const STEP := 1.0 / 60.0

var failures: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var rounds := 4
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("rounds="):
			rounds = maxi(3, int(arg.substr(7)))
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var tally := CrashLog.tally()
	await run(main, _check, rounds)
	tally.stop()
	_check.call(
		tally.errors == 0,
		(
			"no script or engine errors"
			+ ("" if tally.errors == 0 else " (%d: %s)" % [tally.errors, tally.first_errors[0]])
		)
	)
	print("")
	print("LEAK CHECK OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)
		if OS.get_environment("GITHUB_ACTIONS") != "":
			print("::error title=leak_check.gd::%s" % text)


## The checks; `check` is check_fixes' (condition, text). Awaited: each
## round ends at a frame's end (what is freed there, sounds done, is gone).
static func run(main, check: Callable, rounds := 3) -> void:
	await _direct(main, check, rounds)
	await _front_end(main, check, rounds)


static func _frame_end(main) -> void:
	var tree: SceneTree = main.get_tree()
	await tree.process_frame
	await tree.process_frame


static func _objects() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_COUNT))


## Each round's object count after it: none may grow past SLACK from the
## second on (the first fills the caches).
static func _steady(check: Callable, what: String, counts: Array) -> void:
	var grew := 0
	for k in range(2, counts.size()):
		grew = maxi(grew, int(counts[k]) - int(counts[k - 1]))
	var total := int(counts[-1]) - int(counts[1])
	check.call(
		grew <= SLACK and total <= SLACK,
		(
			"%s: the object count holds round to round (%s; most a round grew %d)"
			% [what, ", ".join(counts.map(func(c: int) -> String: return str(c))), grew]
		)
	)


## `frames` ticks with the trigger held and a slow turn: shots, bodies, gore.
static func _play(g: Game, frames: int) -> void:
	var c := Game.Controls.new()
	c.fire = true
	c.turn = .02
	for i in frames:
		g.tick(STEP, c)


# ------------------------------------------------------------------ direct


static func _direct(main, check: Callable, rounds: int) -> void:
	print("GAMES MADE AND LET GO (dispose)")
	var options := SessionStore.settings(OS.get_cache_dir().path_join("clmr_leak_none.json"))
	var plays := [
		["hickston", "", 1],
		["fair", "", 1],
		["sawmill", Modes.COOP, 2],
		["fair", Modes.DEATHMATCH, 2],
		["county_hickston", Modes.COUNTY, 1],
		["range", "", 1],
		["hub", "", 1],
	]
	var counts: Array = []
	var freed := true
	for r in rounds:
		for play: Array in plays:
			var g := Game.new(main.art, main.hud, main.sound, str(play[0]))
			g.configure(options)
			if str(play[1]) != "":
				Modes.setup(g, str(play[1]), int(play[2]), {})
			_play(g, 90)
			var ref := weakref(g)
			g.dispose()
			g = null
			freed = freed and ref.get_ref() == null
		var host := GameHost.new("bayou", 2, {"difficulty": 1})
		for i in 60:
			host.step({})
		var host_ref := weakref(host.game)
		host.close()
		host = null
		freed = freed and host_ref.get_ref() == null
		await _frame_end(main)
		counts.append(_objects())
	check.call(freed, "every game let go is freed (its weak reference comes back empty)")
	_steady(check, "campaign, co-op, deathmatch, COUNTY RUN, range, Crossroads, host", counts)


# ------------------------------------------------------------------ front end


## The front end's flow; release_games() is what the frame's end runs.
static func _front_end(main, check: Callable, rounds: int) -> void:
	print("THE FRONT END'S FLOW (main_flow.gd, GamePool)")
	var counts: Array = []
	var most_kept := 0
	var weak: Array = []
	for r in rounds:
		# A chapter, on to the Crossroads, and back to the title.
		main.mode_name = ""
		main.start("hickston")
		weak.append(weakref(main.game))
		_play(main.game, 60)
		main.open_hub(main.game)
		_play(main.game, 20)
		main.return_to_title(true)
		main.release_games()
		most_kept = maxi(most_kept, main.games.size())
		# The range from the title and back.
		main.open_range()
		weak.append(weakref(main.game))
		_play(main.game, 60)
		main.leave_range()
		main.release_games()
		# A COUNTY RUN, let go from its end.
		main.start_county("county_hickston")
		weak.append(weakref(main.game))
		_play(main.game, 90)
		main.open_county(true)
		main.release_games()
		# Co-op, then a deathmatch in the range.
		main.mode_name = Modes.COOP
		main.mode_players = 2
		main.mode_options = {}
		main.start("sawmill")
		_play(main.game, 60)
		main.return_to_title(true)
		main.release_games()
		main.mode_name = Modes.DEATHMATCH
		main.mode_players = 2
		main.mode_options = {"arena": "range"}
		main.start_match()
		weak.append(weakref(main.game))
		_play(main.game, 60)
		main.mode_name = ""
		main.return_to_title(true)
		main.release_games()
		most_kept = maxi(most_kept, main.games.size())
		await _frame_end(main)
		# (Less the weak references held here, objects themselves.)
		counts.append(_objects() - weak.size())
	# Kept at the title: the campaign's co-op chapter (CONTINUE) and the
	# chapter the Crossroads was opened from.
	check.call(
		most_kept <= 3,
		"the front end keeps only the games it can go back to (%d at most)" % most_kept
	)
	# The last round's chapter is still the campaign run; every other went.
	weak.remove_at(weak.size() - 4)
	var alive := weak.filter(func(w: WeakRef) -> bool: return w.get_ref() != null)
	check.call(alive.is_empty(), "the games the front end let go are freed (%d not)" % alive.size())
	_steady(check, "chapter, Crossroads, range, COUNTY RUN, co-op, deathmatch", counts)
