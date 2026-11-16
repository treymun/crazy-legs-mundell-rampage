## Replays play back exactly (src/replay.gd; check_all runs it):
##
##   Godot --headless --path <project> --script res://tools/replay_check.gd [-- quick] [front]
##
## (front: only the front end's part, the last below.)
##
## Bots play recorded runs: the first chapter from a fresh game and its seed,
## a later chapter recorded from the middle (a snapshot) with its USE, gun
## picks and wheel as actions between ticks and two touches outside them (a
## cheat, a wound), a boss fight, COUNTY RUN with its card picks, and co-op
## with two players. Each recording goes to bytes and back and plays onto a
## fresh game: every hash on the way and the end state (the whole snapshot)
## must match. A recording past its cap keeps the run's start and its last
## segments and plays across the gap; a game nudged during playback is caught
## within a hash of the nudge; the front end's own recorder (main.advance,
## main.act) gives a replay that plays back exactly too. Prints what the
## recording costs a tick and how big a minute of it is.
extends SceneTree

const Pilot := preload("res://tools/bot_pilot.gd")
const CountyBot := preload("res://tools/county_bot.gd")
const BossCheck := preload("res://tools/boss_check.gd")
const STEP := 1.0 / 60.0

var failures: Array = []
var main: Control
var quick := false
## Recording cost over every run: microseconds and ticks.
var cost_us := 0
var cost_ticks := 0


func _init() -> void:
	_run.call_deferred()


func check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


func _run() -> void:
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	quick = OS.get_cmdline_user_args().has("quick")
	var scale := 1 if quick else 2
	print("REPLAYS")
	if OS.get_cmdline_user_args().has("front"):
		_front_end("hickston", 1200)
		quit(1 if not failures.is_empty() else 0)
		return
	_campaign_fresh("hickston", 2400 * scale)
	_campaign_middle("sawmill", 900, 2400 * scale)
	_boss("quarry", 1800 * scale)
	_county("hickston", 2400 * scale)
	_coop("fair", 1800 * scale)
	_rolling("bayou")
	_nudged()
	_front_end("hickston", 1200)
	print(
		(
			"    recording costs %.1f us a tick (%d ticks, every run)"
			% [float(cost_us) / maxi(1, cost_ticks), cost_ticks]
		)
	)
	print("")
	print("REPLAY CHECK OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


## A game as the tools make one: difficulty normal, the chapters before it
## in its history.
func _made(id: String) -> Game:
	var g: Game = main.make_game(id)
	g.configure({"difficulty": 1})
	for done: String in Campaign.ORDER.slice(0, maxi(0, Campaign.ORDER.find(id))):
		g.history.append([done, 1, 2, 0, 1, 60])
	return g


## Plays `rec` back from its bytes onto a fresh game; checks every hash and
## the end against `g` (the recorded game). Returns the playback.
func _replayed(name: String, rec: Replay, g: Game, step := STEP) -> Replay.Playback:
	cost_us += rec.spent_us
	cost_ticks += rec.ticks
	var bytes := rec.to_bytes()
	var back := Replay.from_bytes(bytes)
	check(back != null, "%s: the replay comes back from its bytes" % name)
	if back == null:
		return null
	var pb := Replay.Playback.new(back)
	pb.start(Callable(main, "make_game"))
	var t0 := Time.get_ticks_msec()
	pb.run()
	var ms := Time.get_ticks_msec() - t0
	var same := GameSnapshot.same(GameSnapshot.capture(g), GameSnapshot.capture(pb.game))
	var where := (
		""
		if same
		else GameSnapshot.first_difference(GameSnapshot.capture(g), GameSnapshot.capture(pb.game))
	)
	var minutes := rec.ticks * step / 60.0
	var stream := 0
	for seg: Dictionary in rec.pack()["segments"]:
		stream += (seg["data"] as PackedByteArray).size()
	check(
		pb.diverged < 0 and pb.hashes > 0 and pb.end_matches() and same,
		(
			(
				"%s: %d ticks play back exactly (%d hashes%s, %d keyframes put on; "
				+ "file %d bytes, controls %.1f KB a minute raw; played in %d ms)%s"
			)
			% [
				name,
				pb.tick,
				pb.hashes,
				"" if pb.diverged < 0 else ", parted at tick %d" % pb.diverged,
				pb.jumps,
				bytes.size(),
				stream / 1024.0 / maxf(minutes, .01),
				ms,
				"" if same else ": " + where
			]
		)
	)
	print(
		(
			"    %s: recording %.1f us a tick, keyframes %.1f ms in all"
			% [name, float(rec.spent_us) / maxi(1, rec.ticks), rec.keyframe_us / 1000.0]
		)
	)
	return pb


## The bot's controls for `g`; its USE, gun pick and wheel go through
## rec.act (as the front end's keys do) when `as_actions`.
func _bot_step(g: Game, rec: Replay, pilot, as_actions := false) -> void:
	var c: Game.Controls = pilot.steer(g)
	if as_actions:
		if c.use:
			c.use = false
			rec.act(["use"])
		if c.weapon >= 0:
			rec.act(["select", c.weapon])
			c.weapon = -1
		if c.cycle != 0:
			rec.act(["cycle", c.cycle])
			c.cycle = 0
	rec.tick(STEP, c)
	g.tick(STEP, c)
	rec.ticked()
	pilot.moved(g)


## Chapter one from a fresh game: the replay keeps only the seed.
func _campaign_fresh(id: String, ticks: int) -> void:
	var g := _made(id)
	g.cheats.god = true
	var rec := Replay.record(g, {"difficulty": 1}, {}, true)
	var pilot := Pilot.new()
	pilot.as_controls = true
	for t in ticks:
		_bot_step(g, rec, pilot)
	check(
		rec.segments.size() == 1 and (rec.segments[0]["snap"] as PackedByteArray).is_empty(),
		"%s: a fresh recording keeps no snapshot" % id
	)
	_replayed("%s from the start" % id, rec, g)


## A later chapter recorded from the middle, its actions between ticks, a
## cheat and a wound outside them.
func _campaign_middle(id: String, before: int, ticks: int) -> void:
	var g := _made(id)
	g.cheats.god = true
	var pilot := Pilot.new()
	pilot.as_controls = true
	for t in before:
		g.tick(STEP, pilot.steer(g))
		pilot.moved(g)
	var rec := Replay.record(g, {"difficulty": 1})
	for t in ticks:
		if t == ticks / 3:
			g.cheats.apply("hickguns", g)
		if t == ticks / 2:
			g.cheats.god = false
			g.player.health = maxi(1, g.player.health - 7)
		if t == ticks / 2 + 60:
			g.cheats.god = true
		_bot_step(g, rec, pilot, true)
	check(
		rec.touches >= 2,
		"%s: touches outside the tick are caught (%d keyframes)" % [id, rec.touches]
	)
	_replayed("%s from the middle" % id, rec, g)


func _boss(id: String, ticks: int) -> void:
	var g: Game = BossCheck._fight(main, id)
	g.cheats.god = true
	var rec := Replay.record(g, {"difficulty": 1})
	var pilot := Pilot.new()
	pilot.as_controls = true
	var boss: Enemy = BossCheck.boss_of(g)
	var hp0 := boss.hp if boss != null else 0.0
	for t in ticks:
		_bot_step(g, rec, pilot)
	check(
		boss != null and boss.hp < hp0,
		"%s: the boss was fought (%.0f of %.0f)" % [id, boss.hp if boss != null else 0.0, hp0]
	)
	_replayed("%s boss fight" % id, rec, g)


func _county(id: String, ticks: int) -> void:
	var g: Game = main.make_game(id)
	g.configure({"difficulty": 1})
	Modes.setup(g, Modes.COUNTY, 1)
	g.rng.set_state(CountyBoard.seed_for("2026-11-16", id))
	var rec := Replay.record(
		g, {"difficulty": 1}, {"mode": Modes.COUNTY, "count": 1, "options": {}}, true
	)
	var f = g.features["county"]
	var bot = CountyBot.new()
	var picks := 0
	var t := 0
	while t < ticks and not g.defeated():
		if f.on and not f.pending.is_empty():
			rec.act(["county", CountyBot.pick(g, f), 0])
			picks += 1
			continue
		var c: Game.Controls = bot.steer(g)
		rec.tick(STEP, c)
		g.tick(STEP, c)
		rec.ticked()
		bot.moved(g)
		t += 1
	check(picks > 0, "county run: cards were picked (%d)" % picks)
	_replayed("county run on %s" % id, rec, g)


func _coop(id: String, ticks: int) -> void:
	var g := _made(id)
	Modes.setup(g, Modes.COOP, 2)
	for p: Player in g.players:
		p.health = 100
	g.cheats.god = true
	var rec := Replay.record(g, {"difficulty": 1}, {"mode": Modes.COOP, "count": 2, "options": {}})
	var pilots: Array = []
	for i in g.players.size():
		var pilot := Pilot.new()
		pilot.as_controls = true
		pilots.append(pilot)
	for t in ticks:
		var given := {}
		for p: Player in g.players:
			if p.health > 0:
				g.focus(p)
				given[p.slot] = pilots[p.slot].steer(g)
		g.focus(g.local_player)
		rec.tick(STEP, given)
		g.tick(STEP, given)
		rec.ticked()
		for p: Player in g.players:
			g.focus(p)
			pilots[p.slot].moved(g)
		g.focus(g.local_player)
	check(g.players.size() == 2, "co-op: two players")
	_replayed("co-op on %s" % id, rec, g)


## Past the cap: the start and the newest segments are kept, and play goes
## across the gap from the next keyframe.
func _rolling(id: String) -> void:
	var g := _made(id)
	g.cheats.god = true
	var rec := Replay.record(g, {"difficulty": 1})
	rec.cap_ticks = 900
	rec.roll_ticks = 300
	rec.keep_roll = 2
	var pilot := Pilot.new()
	pilot.as_controls = true
	for t in 3000:
		_bot_step(g, rec, pilot)
	var firsts: Array = []
	for seg: Dictionary in rec.segments:
		firsts.append(int(seg["first"]))
	check(
		firsts == [0, 2400, 2700],
		"%s: past the cap the start and the newest two minutes stay (%s)" % [id, rec.covers()]
	)
	var pb := _replayed("%s across a gap" % id, rec, g)
	check(pb != null and pb.jumps == 1, "%s: the gap was crossed from its keyframe" % id)


## A game changed under the playback is caught within a hash.
func _nudged() -> void:
	var g := _made("hickston")
	g.cheats.god = true
	var rec := Replay.record(g, {"difficulty": 1})
	var pilot := Pilot.new()
	pilot.as_controls = true
	for t in 1200:
		_bot_step(g, rec, pilot)
	var pb := Replay.Playback.new(Replay.from_bytes(rec.to_bytes()))
	pb.start(Callable(main, "make_game"))
	pb.run(500)
	pb.game.player.x += .001
	pb.run()
	check(
		pb.diverged > 500 and pb.diverged <= 500 + Replay.HASH_EVERY and pb.last_good <= 500,
		(
			"a game nudged at tick 500 parts by tick %d (the last match %d)"
			% [pb.diverged, pb.last_good]
		)
	)


## The front end's own recorder: main.advance and main.act, as a player's
## keys and mouse drive them, at the game's 120 Hz.
func _front_end(id: String, frames: int) -> void:
	main.start(id)
	var g: Game = main.game
	g.cheats.god = true
	main.replays.enabled = true
	var pilot := Pilot.new()
	pilot.as_controls = true
	var opts: Dictionary = main.options.duplicate()
	for t in frames:
		var c: Game.Controls = pilot.steer(g)
		if c.use:
			c.use = false
			main.act(g, ["use"])
		if c.cycle != 0:
			main.act(g, ["cycle", c.cycle])
			c.cycle = 0
		# The keys' other actions, and a setting that changes play (FOV aims
		# the shots) changed mid-run.
		match t:
			100:
				main.act(g, ["pocket", 1])
				main.act(g, ["item", -1])
			200:
				main.act(g, ["holster"])
			230:
				main.act(g, ["holster"])
				main.act(g, ["select", 0])
			300:
				main.act(g, ["turn_back"])
				opts["fov"] = 3
				g.configure(opts)
				main.replays.options_changed(g, opts)
			400:
				main.act(g, ["pitch0"])
				main.act(g, ["reload"])
		main.advance(STEP, c)
		pilot.moved(g)
	var rec: Replay = main.replays.rec
	check(
		rec != null and rec.game == g and rec.ticks >= frames * 2 - 2,
		"the front end recorded its game (%d ticks)" % (rec.ticks if rec != null else 0)
	)
	if rec != null:
		_replayed("the front end on %s" % id, rec, g, MainState.SIM_STEP)
		# The dev console's `replay save`: a file in user://replays that plays
		# back to the same end.
		var said: String = main.console.run("replay save") if main.console != null else ""
		main.replays.settle()
		var saved := Replay.load_file(main.replays.last_path)
		var pb: Replay.Playback = null
		if saved != null:
			pb = Replay.Playback.new(saved)
			pb.start(Callable(main, "make_game"))
			pb.run()
		check(
			pb != null and pb.diverged < 0 and pb.end_matches() and saved.reason == "asked",
			(
				"`replay save` writes the run to %s, and it plays back (%s)"
				% [main.replays.last_path, said]
			)
		)
		# A death writes the run by itself.
		g.cheats.god = false
		g.damage(9999.0, null, "TEST")
		main.advance(STEP, Game.Controls.new())
		main.replays.settle()
		check(
			main.replays.saved and main.replays.last_path.ends_with("-death.replay"),
			"a death writes the run (%s)" % main.replays.last_path.get_file()
		)
	main.replays.enabled = false
	main.return_to_title()
	_crash_kept()


## The session's replay beside the crash log: kept as crash-<stamp>.replay
## when the session never closed, gone after a clean exit.
func _crash_kept() -> void:
	var dir := OS.get_cache_dir().path_join("clmr_replay_check_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(dir)
	for name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(name))
	var first := CrashLog.start(main, dir)
	var path := first.replay_path()
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("replay")
	f.close()
	first.stop()  # a crash: the lock stays
	var second := CrashLog.start(main, dir)
	var kept := Array(DirAccess.get_files_at(dir)).filter(
		func(n: String) -> bool: return n.begins_with("crash-") and n.ends_with(".replay")
	)
	check(
		(
			path.get_file() == "session.replay"
			and kept.size() == 1
			and not FileAccess.file_exists(path)
		),
		"a crashed session's replay is kept beside its crash log (%s)" % ", ".join(kept)
	)
	f = FileAccess.open(second.replay_path(), FileAccess.WRITE)
	f.store_string("replay")
	f.close()
	second.close()
	check(
		not FileAccess.file_exists(second.replay_path()), "a clean exit drops the session's replay"
	)
	for name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(name))
	DirAccess.remove_absolute(dir)
