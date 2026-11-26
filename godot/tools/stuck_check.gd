## The stuck spots the pass 15 bots found, held so they cannot come back
## (docs/dev/checks.md; tools/check_all.gd runs it):
##
##   godot --headless --path godot --script res://tools/stuck_check.gd
##
## CAUGHT: a player standing inside the square a piece of furniture blocks
## (LevelData.blocked's test: put or shoved there) walks out of it. Before,
## every first small step out was refused and the velocity died: the ROOKIE
## bot stood 660 s on the bayou's lagoon bank by a dock piling after the swamp
## king fell. That spot, and a player put against a corner of the furniture
## of every chapter, walks off; the bot from the lagoon bank reaches the exit.
## AFTER A BOSS: every boss of the campaign struck down in its chapter (its
## gates swinging open in the fall's slow motion), the objective's way
## reaches the player within REACH_WITHIN s and the SHARP bot clears the
## chapter (god mode; the bots were walled in after the foreman,
## the derby champ and the swamp king: a way walked while a gate swung stayed
## shut, Game.route's REWALK_GAP since T1).
extends SceneTree

const ScratchProfile := preload("res://tools/scratch_profile.gd")
const STEP := 1.0 / 60.0
const Pilot := preload("res://tools/balance_pilot.gd")
## Seconds after a boss's fall the way must reach the player in; seconds the
## bot has to clear a chapter.
const REACH_WITHIN := 3.0
const CHAPTER_FOR := 900.0
## The bayou's lagoon bank by a dock piling (pass 15's ROOKIE, seed 3).
const BANK := Vector2(101.2, 24.0)

var failures: Array = []
var passes := 0
var main


func _init() -> void:
	if ScratchProfile.refuse(self, "STUCK CHECK"):
		return
	_run.call_deferred()


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if ok:
		passes += 1
	else:
		failures.append(text)


func _run() -> void:
	DirectorData.ON = false
	HoundLead.ON = false
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	main.options["hound"] = 0
	var started := Time.get_ticks_msec()
	print("CAUGHT IN FURNITURE")
	_caught()
	print("\nAFTER A BOSS")
	for id: String in Campaign.ORDER:
		_after_bosses(id)
	print(
		(
			"\n%d checks in %.1f s"
			% [passes + failures.size(), (Time.get_ticks_msec() - started) / 1000.0]
		)
	)
	print("STUCK CHECK OK" if failures.is_empty() else "%d STUCK CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _game(id: String) -> Game:
	var g: Game = main.make_game(id)
	g.configure({"difficulty": 1, "hound": 0})
	g.cheats.god = true
	g.lessons = false
	return g


func _walk(g: Game, angle: float, secs: float) -> void:
	g.player.angle = angle
	for t in int(secs / STEP):
		var c := Game.Controls.new()
		c.forward = 1.0
		c.running = true
		g.tick(STEP, c)


# ------------------------------------------------------------------ caught


func _caught() -> void:
	var g := _game("bayou")
	g.tick(STEP, Game.Controls.new())
	var r := GameState.PLAYER_RADIUS
	_check(g.world.blocked(BANK.x, BANK.y, r), "the lagoon bank spot is inside the piling's square")
	for k in 4:
		var a := -.3 + k * .37
		Modes.place(g, g.player, BANK.x, BANK.y, a)
		var from := Vector2(g.player.x, g.player.y)
		_walk(g, a, 1.0)
		var went := from.distance_to(Vector2(g.player.x, g.player.y))
		_check(went > 1.5, "walks off it heading %.2f (%.1f cells in a second)" % [a, went])
	# The bot from there after the king, to the exit.
	var b := _game("bayou")
	b.tick(STEP, Game.Controls.new())
	for s: LevelData.Station in b.world.stations:
		b.stations_done[s.id] = true
	for e: Enemy in b.enemies:
		if e.kind == "swamp_king":
			e.hp = 0.0
		elif e.hostile:
			e.dormant = true
	Modes.place(b, b.player, BANK.x, BANK.y, .37)
	var pilot := Pilot.new(0, 3)
	var t0 := b.clock
	while b.clock - t0 < 60.0 and not b.won:
		var c := pilot.steer(b)
		b.tick(STEP, c)
		pilot.moved(b)
	_check(b.won, "the ROOKIE bot from the bank reaches the exit (%.1f s)" % (b.clock - t0))
	# A player put against a corner of each chapter's small furniture walks out.
	for id: String in Campaign.ORDER:
		var w := _game(id)
		w.tick(STEP, Game.Controls.new())
		var tried := 0
		var stuck := 0
		for v: PackedFloat32Array in w.world.collision_volumes:
			if tried >= 12:
				break
			var half := (v[2] - v[0]) * .5
			if half > .4 or v[4] < .6 or v[7] > w.world.elevation((v[0] + v[2]) * .5, v[1]) + .1:
				continue
			var at := Vector2(v[2] + r * .4, (v[1] + v[3]) * .5)
			if w.world.solid[w.world.cell(at.x + .6, at.y)] >= 0 or w.world.deep_at(at.x, at.y):
				continue
			Modes.place(w, w.player, at.x, at.y, 0.0)
			if not w.world.blocked(at.x, at.y, r):
				continue
			# Out, some way away from it (one way may be water or a wall).
			var out := false
			for a: float in [0.0, -.7, .7]:
				Modes.place(w, w.player, at.x, at.y, a)
				_walk(w, a, .5)
				if at.distance_to(Vector2(w.player.x, w.player.y)) >= .3:
					out = true
					break
			tried += 1
			if not out:
				stuck += 1
				print("    caught at %.2f, %.2f by %s" % [at.x, at.y, v])
		_check(
			tried > 0 and stuck == 0,
			"%s: put against furniture %d times, walked out each" % [id, tried]
		)


# ------------------------------------------------------------------ bosses


## Chapter `id` played through by the SHARP bot (god mode): after each boss
## falls the pin's way reaches the player within REACH_WITHIN s, and the
## chapter is cleared.
func _after_bosses(id: String) -> void:
	main.start(id)
	var g: Game = main.game
	g.cheats.god = true
	g.lessons = false
	var bosses: Array = []
	for e: Enemy in g.enemies:
		if Enemy.BOSS_TITLES.has(e.kind):
			bosses.append(e)
	var down := {}
	var fell := {}
	var reached := {}
	var pilot := Pilot.new(2, 1)
	var t0 := g.clock
	while g.clock - t0 < CHAPTER_FOR and not g.won:
		var c := pilot.steer(g)
		g.tick(STEP, c)
		pilot.moved(g)
		for boss: Enemy in bosses:
			if boss.hp <= 0.0 and not fell.has(boss.kind):
				fell[boss.kind] = g.clock
		for kind: String in fell:
			if not reached.has(kind) and _steps(g) >= 0:
				reached[kind] = g.clock - float(fell[kind])
	for boss: Enemy in bosses:
		var kind := boss.kind
		if not fell.has(kind):
			_check(g.won, "%s: %s fell (or the chapter was won without him)" % [id, kind])
			continue
		var took: float = reached.get(kind, -1.0)
		_check(
			took >= 0.0 and took <= REACH_WITHIN,
			"%s: %s down, the pin's way reaches the player %.1f s after" % [id, kind, took]
		)
	_check(
		g.won,
		(
			"%s: the bot clears it after its bosses (%.0f s, at %.1f, %.1f)"
			% [id, g.clock - t0, g.player.x, g.player.y]
		)
	)


## Steps from the player to the objective by the pin's way (-1 none), asked
## each tick as the HUD asks each frame.
func _steps(g: Game) -> int:
	var goal: Variant = g.objective_target()
	if goal == null:
		return 0
	var way: Array = g.objective_route(goal)
	return way[1]
