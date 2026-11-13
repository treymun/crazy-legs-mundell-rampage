## The 5v5 round modes played out by ten bots (src/modes/tactical_mode.gd,
## tactical_bot.gd), headless:
##
##   Godot --headless --path <project> --script res://tools/tactical_check.gd
##       [-- maps=grainyard,holler,salvage] [modes=bomb,hostage] [rounds=3]
##       [minutes=<cap of play per match>] [verbose]
##
## Every match on every map and mode is played by TacticalBot in all ten
## slots, as a real game ticks (120 a second), to its end or the cap. Each
## round prints who took it, how and when. It fails on a script or engine
## error, a player whose place is not a number, a match that does not finish,
## a round that outlasts its clock by more than a few seconds, or a map/mode
## where every round ran out of time (bots that never meet). The economy is
## checked too: nobody's cash ever outside 0..16000, and a round's payout
## matching the rules.
extends SceneTree

const STEP := 1.0 / 120.0

var failures: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var maps: Array = Modes.SHOWDOWN_MAPS.duplicate()
	var modes: Array = Modes.TACTICAL.duplicate()
	var rounds := 3
	var minutes := 30.0
	var verbose := false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("maps="):
			maps = Array(arg.substr(5).split(","))
		elif arg.begins_with("modes="):
			modes = Array(arg.substr(6).split(","))
		elif arg.begins_with("rounds="):
			rounds = int(arg.substr(7))
		elif arg.begins_with("minutes="):
			minutes = float(arg.substr(8))
		elif arg == "verbose":
			verbose = true
	var errors := CrashLog.tally()
	for map: String in maps:
		for mode: String in modes:
			_match(main, map, mode, rounds, minutes, verbose)
	errors.stop()
	_check(
		errors.errors == 0,
		(
			"no script or engine errors"
			+ ("" if errors.errors == 0 else " (%d: %s)" % [errors.errors, errors.first_errors[0]])
		)
	)
	print("")
	print("TACTICAL CHECK OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


func _match(main, map: String, mode: String, rounds: int, minutes: float, verbose: bool) -> void:
	print("== %s  %s  first to %d" % [map, mode, rounds])
	var g: Game = main.make_game(map)
	g.configure({"difficulty": 1})
	Modes.setup(g, mode, 10, {"arena": map, "rounds": rounds})
	TacticalScreens.human = -1
	var pilots := {}
	for p: Player in g.players:
		pilots[p.slot] = TacticalBot.new(p.slot)
	var st = Modes.feature(g)
	var seen := 0
	var round_began := 0.0
	var worst_over := 0.0
	var timeouts := 0
	var reasons := {}
	var bad_place := false
	var cash_ok := true
	var ticks := int(minutes * 60.0 / STEP)
	var t0 := Time.get_ticks_msec()
	var before: Array = []
	var events: Array = []
	var shots := {}
	g.shot_fired.connect(
		func(_gun: int) -> void: shots[g.player.slot] = int(shots.get(g.player.slot, 0)) + 1
	)
	var last_objective := ""
	var first_blood := -1.0
	var alive_was := {}
	var used := {"smoke": 0, "fire": 0, "flashed": 0}
	var was_counts := [0, 0, 0]
	for i in ticks:
		var given := {}
		for p: Player in g.players:
			if p.health > 0:
				g.focus(p)
				given[p.slot] = pilots[p.slot].steer(g)
		g.focus(g.local_player)
		if String(st.phase) == "live" and before.is_empty():
			pass
		var phase_was := String(st.phase)
		if phase_was == "live":
			before = st.money.duplicate()
		g.tick(STEP, given)
		for p: Player in g.players:
			if is_nan(p.x) or is_nan(p.y):
				bad_place = true
		for cash in st.money:
			if int(cash) < 0 or int(cash) > TacticalShop.MAX_MONEY:
				cash_ok = false
		if st.clouds.size() > int(was_counts[0]):
			used["smoke"] += 1
		if st.fires.size() > int(was_counts[1]):
			used["fire"] += 1
		if st.blind.size() > int(was_counts[2]):
			used["flashed"] += st.blind.size() - int(was_counts[2])
		was_counts = [st.clouds.size(), st.fires.size(), st.blind.size()]
		if phase_was == "freeze" and String(st.phase) == "live":
			round_began = g.clock
			events = []
		var now := _objective(st)
		if now != last_objective:
			last_objective = now
			if now != "" and String(st.phase) in ["live", "post"]:
				events.append("%s@%.0f" % [now, g.clock - round_began])
		var dead := 0
		for p: Player in g.players:
			dead += 1 if p.health <= 0 else 0
			if verbose and p.health <= 0 and alive_was.get(p.slot, false):
				var by := p.downed_by
				var k: Player = g.players[by] if by >= 0 and by < g.players.size() else null
				print(
					(
						"           %.1fs %s (%s %s cash %d) at %.0f,%.0f facing %.1f  by %s at %s"
						% [
							g.clock - round_began,
							Modes.tag(p),
							TacticalMode.side_name(st, p),
							Weapons.NAMES[p.armory.active],
							int(st.money[p.slot]),
							p.x,
							p.y,
							p.angle,
							Modes.tag(k) if k != null else "-",
							(
								"%.0f,%.0f %s" % [k.x, k.y, Weapons.NAMES[k.armory.active]]
								if k != null
								else ""
							),
						]
					)
				)
			alive_was[p.slot] = p.health > 0
		if dead > 0 and first_blood < 0.0 and String(st.phase) == "live":
			first_blood = g.clock - round_began
			events.append("blood@%.0f" % first_blood)
		if String(st.phase) == "freeze":
			first_blood = -1.0
		if st.history.size() > seen:
			seen = st.history.size()
			var row: Array = st.history[seen - 1]
			var took := g.clock - round_began
			var limit: float = (Modes.rules(g) as TacticalMode).round_time()
			if mode == Modes.BOMB:
				limit += BombMode.BOMB_TIMER
			worst_over = maxf(worst_over, took - limit)
			var how := String(row[1])
			reasons[how] = int(reasons.get(how, 0)) + 1
			if how == "TIME":
				timeouts += 1
			var side := "OUTLAWS" if int(row[0]) == int(st.outlaws) else "DEPUTIES"
			print(
				(
					"  round %2d  %s (%s) by %-7s  %5.1fs  %s %d - %d %s  kills %s"
					% [
						int(st.round_no),
						TacticalMode.team_name(int(row[0])),
						side,
						how,
						took,
						TacticalMode.TEAM_NAMES[0],
						int(st.wins[0]),
						int(st.wins[1]),
						TacticalMode.TEAM_NAMES[1],
						_kills(g),
					]
				)
			)
			print("           ", " ".join(events))
			if verbose:
				print("           cash ", st.money)
		if bool(st.match_over):
			break
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	if verbose:
		for p: Player in g.players:
			print(
				(
					"  %s team %d  frags %d deaths %d  shots %d  gun %s  armor %.0f"
					% [
						Modes.tag(p),
						p.team,
						p.frags,
						p.deaths,
						int(shots.get(p.slot, 0)),
						Weapons.NAMES[p.armory.active],
						float(st.armor[p.slot])
					]
				)
			)
	print(
		(
			"  %d rounds in %.0fs of play (%.1fs to run), %s, winner %s"
			% [seen, g.clock, secs, str(reasons), Modes.rules(g).winner(g)]
		)
	)
	print(
		(
			"  throwables: %d smokes, %d fires, %d flashed"
			% [used["smoke"], used["fire"], used["flashed"]]
		)
	)
	var tag := "%s %s" % [map, mode]
	_check(bool(st.match_over), tag + ": the match finishes")
	_check(not bad_place, tag + ": every place is a number")
	_check(cash_ok, tag + ": cash stays within 0..16000")
	_check(worst_over < 3.0, tag + ": no round outlasts its clock (worst %+.1fs)" % worst_over)
	_check(seen == 0 or timeouts < seen, tag + ": not every round runs out of time")


## The objective's state in a word (the bomb's, or hostages carried/out).
func _objective(st) -> String:
	if String(st.mode) == Modes.BOMB:
		var state := String(st.bomb.get("state", ""))
		if state == "planted":
			return "planted-" + String(st.bomb["site"])
		return state if state in ["dropped", "defused", "blown"] else ""
	var carried := 0
	for h: Array in st.hostages:
		carried += 1 if String(h[2]) == "carried" else 0
	if int(st.rescued) > 0:
		return "rescued"
	return "carried%d" % carried if carried > 0 else ""


func _kills(g: Game) -> String:
	var parts: Array = []
	for team in 2:
		var n := 0
		for p: Player in g.players:
			if p.team == team:
				n += p.frags
		parts.append(str(n))
	return "/".join(parts)
