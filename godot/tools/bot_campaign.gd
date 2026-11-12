## End-to-end campaign walkthrough through the real front end: new game ->
## every chapter -> Crossroads -> unlock -> revisit -> ending, plus a save
## round-trip at every transition. Objectives are driven through the same calls
## the game makes (hit_scenery, interact, continue_campaign, travel), not by
## poking `won`, so a broken trigger shows up here.
extends SceneTree

var failures: Array = []


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, text: String) -> void:
	if condition:
		print("  ok   ", text)
	else:
		print("  FAIL ", text)
		failures.append(text)


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"

	print("NEW GAME")
	main.start("hickston")
	check(main.state == "play", "state is play")
	check(main.game.level.id == "hickston", "level is hickston")
	check(main.campaign_run == main.game, "campaign_run tracks the run")
	check(not main.game.won, "not won at spawn")

	for chapter: String in Campaign.ORDER:
		print("\n=== CHAPTER ", chapter)
		if main.game == null or main.game.level.id != chapter:
			check(main.state == "play" and main.game.in_hub, "at Crossroads before " + chapter)
			main.travel(chapter)
			check(main.game.level.id == chapter, "travelled to " + chapter)
		clear_chapter(main, chapter)
		verify_chapter_won(main, chapter)
		save_round_trip(main, chapter)
		advance_campaign(main, chapter)

	print("\nEND OF CAMPAIGN")
	var last: String = Campaign.ORDER.back()
	check(main.campaign_run.level.id == last, "campaign still on " + last)
	check(main.game.in_hub, "finale returns to Crossroads")
	check(
		main.game.hub_milestone == mini(Campaign.ORDER.size(), GameState.HUB_DISPATCH.size() - 1),
		"hub milestone reached the finale"
	)

	print("\nREVISITS")
	for chapter: String in Campaign.ORDER:
		main.travel(chapter)
		var g: Game = main.game
		check(g.level.id == chapter, "revisit opened " + chapter)
		check(g.revisiting, chapter + " is marked revisiting")
		check(g.won, chapter + " stays won")
		check(not g.showing_tally, chapter + " revisit has no tally")
		draw_once(g, "revisit " + chapter)
		main.open_hub(main.campaign_run)

	print("\nCAMPAIGN SAVE / LOAD")
	var campaign_path := "user://probe-campaign.json"
	check(main.write_campaign(main.campaign_run, campaign_path), "campaign save written")
	var loaded: Game = SessionStore.read(campaign_path, Callable(main, "make_game"), false)
	check(loaded != null, "campaign save reloads")
	if loaded != null:
		main.play(loaded)
		loaded.configure(main.options)
		check(
			loaded.history.size() == Campaign.ORDER.size() - 1,
			"history has every chapter before the last finished"
		)
		check(
			loaded.loadout()["active"] == main.campaign_run.loadout()["active"],
			"loadout survived the round trip"
		)
		check(
			absf(loaded.player.x - main.campaign_run.player.x) < 0.001,
			"position survived the round trip"
		)
		check(
			loaded.retained.size() == main.campaign_run.retained.size(),
			"retained chapters survived"
		)
		main.campaign_run = loaded
		main.open_hub(loaded)
		for chapter: String in Campaign.ORDER:
			check(main.unlocked.has(chapter), "gate unlocked: " + chapter)

	# A live, non-revisiting run with the finished chapters in its history, so
	# retry and quicksave exercise the same code a real mid-campaign player uses.
	print("\nDEATH / RETRY")
	var history := [["hickston", 0, 0, 0, 0, 0], ["fair", 0, 0, 0, 0, 0]]
	main.start("sawmill", null, history, false, null)
	check(main.game.level.id == "sawmill" and not main.game.won, "live run started")
	main.game.player.health = 0
	main.key(KEY_ENTER)
	check(main.game.level.id == "sawmill", "retry restarts the same chapter")
	check(not main.game.won, "retry is a fresh run")
	check(not main.game.revisiting, "retry is not a revisit")
	check(main.game.history.size() == 2, "retry keeps the finished history")

	print("\nQUICKSAVE / QUICKLOAD")
	var before: Game = main.game
	var spot := Vector2(float(before.level.spawn[0]), float(before.level.spawn[1]))
	before.player.x = spot.x
	before.player.y = spot.y
	before.player.eye = before.world.elevation(spot.x, spot.y) + .95
	before.kills = 3
	var saved_x := before.player.x
	var saved_y := before.player.y
	main.save_game()
	check(FileAccess.file_exists(main._save_path()), "quicksave file written")
	before.player.x = 0.0
	before.player.y = 0.0
	before.kills = 0
	main.load_game()
	check(main.game.level.id == "sawmill", "quickload restored the chapter")
	check(absf(main.game.player.x - saved_x) < 0.001, "quickload restored the position")
	check(absf(main.game.player.y - saved_y) < 0.001, "quickload restored the second axis")
	check(main.game.kills == 3, "quickload restored the kill count")

	var path_clean := [
		"user://probe-campaign.json",
		"user://probe-hickston.json",
		"user://probe-fair.json",
		"user://probe-sawmill.json",
		"user://probe-quarry.json",
		"user://probe-bayou.json",
		"user://probe-speedway.json",
	]
	for p in path_clean:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

	if failures.is_empty():
		print("\nCAMPAIGN WALKTHROUGH OK")
	else:
		print("\nCAMPAIGN WALKTHROUGH FAILURES: ", failures.size())
		for f in failures:
			print("   - ", f)
	quit(0 if failures.is_empty() else 1)


## Clear a chapter through its real objective chain.
func clear_chapter(main: Control, chapter: String) -> void:
	var g: Game = main.game
	g.cheats.god = true
	g.player.health = 100
	if chapter == "hickston":
		check(g.collect("key_brass"), "picked up the brass key")
		check(g.keys.has("key_brass"), "brass key registered")
		check(g.collect("key_steel"), "picked up the steel key")
		check(g.keys.has("key_steel"), "steel key registered")
		kill_all(g)
		check(g.boss != null and not g.boss.alive, "alien sheriff is down")
		check(g.jerry != null and not g.jerry.alive, "Jerry is down")
		stand_at(g, g.bessie.x, g.bessie.y)
		g.interact()
		check(g.won, "Bessie rescued")
		return
	var exit: LevelData.Extraction = g.world.extraction
	check(exit != null, chapter + " has an extraction")
	# Task items the station chain demands.
	for station: LevelData.Station in g.world.stations:
		if station.held != "" and not g.task_items.has(station.held):
			check(g.collect(station.held), chapter + " collected " + station.held)
	var guard := 0
	while guard < 24:
		guard += 1
		var progressed := false
		for station: LevelData.Station in g.world.stations:
			if g.stations_done.has(station.id):
				continue
			var ready := true
			for key in station.requires:
				if not g.stations_done.has(String(key)):
					ready = false
					break
			if not ready:
				continue
			if station.held != "" and not g.task_items.has(station.held):
				continue
			if station.action == "strike":
				# Real route: shoot the belt, which calls hit_scenery().
				var found := false
				for prop: LevelData.Scenery in g.world.scenery:
					if prop.station == station.id and not g.scenery_used(prop):
						g.hit_scenery(prop)
						found = true
						break
				if found and g.stations_done.has(station.id):
					progressed = true
				continue
			if station.action == "crank":
				# The condenser valve needs three turns spaced 0.20 s apart in
				# game time, so advance the clock between turns like a player.
				for turn in 4:
					stand_at(g, station.x, station.y)
					g.interact()
					if g.stations_done.has(station.id):
						break
					g.clock += 0.21
				if g.stations_done.has(station.id):
					progressed = true
				continue
			stand_at(g, station.x, station.y)
			g.interact()
			if g.stations_done.has(station.id):
				progressed = true
		if not progressed:
			break
	check(g.stations_done.has(exit.shutdown), chapter + " shutdown station done")
	check(g.finale != null, chapter + " has a finale boss")
	if g.finale != null:
		check(not g.finale.dormant, chapter + " finale woke on the shutdown")
	draw_once(g, chapter + " finale live")
	kill_all(g)
	check(not g._wave_alive(), chapter + " exit wave cleared")
	check(g.exit_ready(), chapter + " exit is ready")
	stand_at(g, exit.x, exit.y)
	g.interact()
	check(g.won, chapter + " finished at the exit")


func draw_once(g: Game, label: String) -> void:
	var canvas := Canvas.new()
	g.tick(1.0 / 120.0, Game.Controls.new())
	g.draw(canvas, 1, true)
	var non_black := 0
	var pix := canvas.pixels
	for i in range(0, pix.size(), 3):
		if pix[i] != 0 or pix[i + 1] != 0 or pix[i + 2] != 0:
			non_black += 1
	if non_black < 1000:
		print("  FAIL ", label, " drew an empty frame (", non_black, " lit pixels)")
		failures.append(label + " empty frame")


func kill_all(g: Game) -> void:
	for enemy: Enemy in g.enemies:
		# Bessie is unkillable in the reference; `hurt` ignores her on purpose.
		if enemy.alive and enemy.kind != "bessie":
			enemy.wake(g, g.player.x, g.player.y)
			enemy.hurt(9999.0, g)
			enemy.hp = 0.0


## Stand a short step from (x, y) facing it, then settle the eye height.
func stand_at(g: Game, x: float, y: float) -> void:
	var p := g.player
	p.x = x + 0.9
	p.y = y
	p.angle = PI
	p.eye = g.world.elevation(p.x, p.y) + .95
	p.vx = 0.0
	p.vy = 0.0
	p.air = 0.0


func verify_chapter_won(main: Control, chapter: String) -> void:
	var g: Game = main.game
	check(g.won, chapter + " reports won")
	check(g.showing_tally, chapter + " shows the tally")
	check(not g.revisiting, chapter + " is not a revisit yet")
	draw_once(g, chapter + " tally")


func save_round_trip(main: Control, chapter: String) -> void:
	var path := "user://probe-%s.json" % chapter
	var g: Game = main.game
	check(main.write_campaign(g, path), chapter + " campaign save written")
	var back: Game = SessionStore.read(path, Callable(main, "make_game"), false)
	check(back != null, chapter + " campaign save reloads")
	if back != null:
		back.configure(main.options)
		check(back.level.id == chapter, chapter + " save keeps its chapter")
		check(back.won, chapter + " save keeps won")
		check(back.history.size() == g.history.size(), chapter + " save keeps history")
		check(back.stations_done.size() == g.stations_done.size(), chapter + " save keeps stations")
		check(back.kills == g.kills, chapter + " save keeps kills")
		check(back.secrets == g.secrets, chapter + " save keeps secrets")


func advance_campaign(main: Control, chapter: String) -> void:
	main.continue_campaign()
	var following := Campaign.next_level(chapter)
	if following == "":
		check(main.game.in_hub, "ending returns to the Crossroads")
		return
	check(main.game.in_hub, chapter + " close returns to the Crossroads")
	check(main.unlocked.has(following), "gate opened for " + following)
	var gated := false
	for gate: LevelData.Gate in main.game.world.hub_gates:
		gated = gated or gate.destination == following
	if gated:
		check(
			main.game.gate_modes.get(following, "") in ["REPLAY", "CONTINUE"],
			"gate mode set for " + following
		)
	else:
		# A new chapter before the Crossroads has its gate: travelled to directly.
		print("  note no Crossroads gate yet for ", following)
	check(main.game.gate_modes.get(chapter, "") == "REVISIT", "finished chapter offers REVISIT")
