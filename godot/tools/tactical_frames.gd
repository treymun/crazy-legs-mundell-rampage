## Pictures of the 5v5 round modes (src/modes/tactical_mode.gd) in a real
## window (the graphics-card view players see): the title's 5V5 SHOWDOWN
## picker; on each map the freeze with the buy menu open, a look down a lane
## a few seconds into the round with the bots playing, each site, the
## automap; a planted shine bomb, a hostage, the scoreboard of a player who is
## out and the match's results. <name>.png in out=<dir>.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/tactical_frames.gd -- out=<dir> [maps=holler]
##
## Point APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

var main
var out := ""
var pilots := {}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var maps: Array = Modes.SHOWDOWN_MAPS.duplicate()
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
		elif String(arg).begins_with("maps="):
			maps = Array(String(arg).substr(5).split(","))
	if out == "":
		push_error("out=<dir> is needed")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.touring = true
	Effects.enabled = true
	main.state = "title"
	main.selection = main.entries().find("MULTIPLAYER")
	main.render()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("title.png"))
	main.state = "showdown"
	main.showdown_row = 1
	main.render()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("picker.png"))
	for map: String in maps:
		await _map(map)
	if not Modes.TAGTEAM_MAPS.has(String(maps[0])):
		await _hostage(String(maps[0]))  # the 2v2 maps hold no hostages
	else:
		await _tag_results(String(maps[0]))
	print("tactical frames written to ", out)
	main.queue_free()
	await process_frame
	quit()


func _game(level_id: String, mode: String) -> Game:
	var g: Game = main.make_game(level_id)
	main.game = g
	main.state = "play"
	g.configure(SessionStore.defaults())
	var options := {"arena": level_id}
	var count := 10
	if Modes.TAGTEAM_MAPS.has(level_id):
		options.merge(Modes.TAGTEAM_OPTIONS)
		count = Modes.TAGTEAM_PLAYERS
	Modes.setup(g, mode, count, options)
	g.barks.enabled = false
	TacticalScreens.reset()
	TacticalScreens.human = 0
	pilots = {}
	for p: Player in g.players:
		pilots[p.slot] = TacticalBot.new(p.slot)
	return g


## `n` ticks with every player, this one too, played by its bot.
func _play(g: Game, n: int, skip_local := false) -> void:
	for i in n:
		var given := {}
		for p: Player in g.players:
			if p.health > 0 and not (skip_local and p == g.local_player):
				g.focus(p)
				given[p.slot] = pilots[p.slot].steer(g)
		g.focus(g.local_player)
		g.tick(1.0 / 120.0, given)


func _snap(name: String) -> void:
	var g: Game = main.game
	g.barks.until = 0.0
	g.callout_until = 0.0
	g.district_until = 0.0
	main.render()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))


## Stands this machine's player at (x, y) looking at (tx, ty), out of harm.
func _stand(g: Game, x: float, y: float, tx: float, ty: float) -> void:
	var me: Player = g.local_player
	Modes.place(g, me, x, y, atan2(ty - y, tx - x))
	me.health = 100


func _map(id: String) -> void:
	var g := _game(id, Modes.BOMB)
	var st = Modes.feature(g)
	_play(g, 2)
	g.message_until = 0.0
	TacticalScreens.open = true
	TacticalScreens.cursor = 5
	await _snap(id + "_buy")
	# The deputies' counter: the same player, the sides turned round a moment.
	st.outlaws = 1
	st.money[g.local_player.slot] = 6000
	TacticalScreens.cursor = 2
	await _snap(id + "_buy_deputies")
	st.outlaws = 0
	st.money[g.local_player.slot] = TacticalShop.START_MONEY
	TacticalScreens.open = false
	# A few seconds into the round, the view of a bot on the attack.
	_play(g, int(TacticalMode.FREEZE * 120.0) + 120 * 7)
	g.message_until = 0.0
	await _snap(id + "_lane")
	g.cheats.god = true
	var plan: Dictionary = g.world.tactical
	for site: String in plan["sites"]:
		var box: Array = plan["sites"][site]
		var centre := TacticalMode.box_centre(box)
		var holds: Array = plan["holds"][site]
		var from := Vector2(float(holds[0][0]), float(holds[0][1]))
		# Back from the site's middle toward the hold, looking across it.
		var at := centre + (from - centre).normalized() * 4.0
		if g.world.blocked(at.x, at.y, .3):
			at = from
		_stand(g, at.x, at.y, centre.x, centre.y)
		g.message_until = 0.0
		_play(g, 1, true)
		await _snap("%s_site_%s" % [id, site.to_lower()])
	g.map = true
	g.map_zoom = 0
	await _snap(id + "_map")
	g.map = false
	# The Hog Hunter's scope up, looking down the defenders' long lane.
	var me: Player = g.local_player
	TacticalShop.give(st, me, TacticalShop.item("hunter"))
	me.armory.switch = 0.0
	var mid: Array = plan["holds"].get("mid", plan["holds"]["A"])[0]
	var sites: Dictionary = plan["sites"]
	var aim_at := TacticalMode.box_centre(sites["A"])
	_stand(g, float(mid[0]), float(mid[1]), aim_at.x, aim_at.y)
	me.angle = float(mid[2])
	me.scoped = true
	_play(g, 1, true)
	g.message_until = 0.0
	await _snap(id + "_scoped")
	me.scoped = false
	TacticalShop.give(st, me, TacticalShop.item("mower"))
	me.armory.switch = 0.0
	_play(g, 1, true)
	await _snap(id + "_mower")
	# The throwables: smoke and a fire out ahead, a flash jar in hand, a flash.
	me.scoped = false
	TacticalShop.give(st, me, TacticalShop.item("flash_jar"))
	me.armory.select(Weapons.FLASH_JAR, g)
	me.armory.switch = 0.0
	var ahead := Vector2(me.x + cos(me.angle) * 7.0, me.y + sin(me.angle) * 7.0)
	var near := Vector2(me.x + cos(me.angle) * 3.5, me.y + sin(me.angle) * 3.5)
	st.clouds.append([ahead.x, ahead.y, g.clock + 15.0, g.clock - 3.0])
	st.fires.append([near.x, near.y, g.clock + 6.0, g.clock + 9.0, 1])
	_play(g, 1, true)
	g.message_until = 0.0
	await _snap(id + "_utility")
	st.clouds.clear()
	st.fires.clear()
	st.blind[me.slot] = [g.clock + 3.0, 1.0]
	await _snap(id + "_flashed")
	st.blind.clear()
	var held := {
		"smudge_pot": Weapons.SMUDGE_POT,
		"shine_cocktail": Weapons.SHINE_COCKTAIL,
		"firecracker_can": Weapons.FIRECRACKER_CAN
	}
	for name: String in held:
		TacticalShop.give(st, me, TacticalShop.item(name))
		me.armory.select(int(held[name]), g)
		me.armory.switch = 0.0
		_play(g, 1, true)
		await _snap(id + "_held_" + name)
	# The bomb planted on A, seen from beside it.
	var a_box: Array = plan["sites"]["A"]
	var a := TacticalMode.box_centre(a_box)
	st.bomb["state"] = "planted"
	st.bomb["x"] = a.x
	st.bomb["y"] = a.y
	st.bomb["site"] = "A"
	st.bomb["planted_at"] = g.clock
	st.phase = "live"
	var spot := a + Vector2(2.5, 1.5)
	if g.world.blocked(spot.x, spot.y, .3):
		spot = a + Vector2(-2.5, 1.5)
	_stand(g, spot.x, spot.y, a.x, a.y)
	_play(g, 1, true)
	g.message_until = 0.0
	await _snap(id + "_planted")
	g.cheats.god = false
	main.game = null


## A TAG TEAM match's end: a few rounds played out by the bots, then over.
func _tag_results(id: String) -> void:
	var g := _game(id, Modes.BOMB)
	var st = Modes.feature(g)
	_play(g, 120 * 60, true)
	st.wins = [9, 6]
	st.match_over = true
	st.over_clock = g.clock
	g.won = true
	g.showing_tally = true
	await _snap(id + "_results")
	main.game = null


func _hostage(id: String) -> void:
	var g := _game(id, Modes.HOSTAGE)
	var st = Modes.feature(g)
	_play(g, int(TacticalMode.FREEZE * 120.0) + 60)
	g.cheats.god = true
	var h: Array = st.hostages[0]
	var at := Vector2(float(h[0]), float(h[1]))
	var spot := at
	for k in 8:
		var a := k * TAU / 8.0
		var try := at + Vector2(cos(a), sin(a)) * 2.2
		if not g.world.blocked(try.x, try.y, .35) and g.world.visible(try.x, try.y, at.x, at.y):
			spot = try
			break
	_stand(g, spot.x, spot.y, at.x, at.y)
	_play(g, 1, true)
	g.message_until = 0.0
	await _snap(id + "_hostage")
	# Out: the scoreboard.
	g.cheats.god = false
	g.damage(500.0, null, "TEST", g.local_player)
	for p: Player in g.players:
		if p.team == g.local_player.team:
			p.health = 0
	_play(g, 2, true)
	g.message_until = 0.0
	await _snap(id + "_out")
	# The results: the match over.
	st.wins = [7, 5]
	st.match_over = true
	st.over_clock = g.clock
	g.won = true
	g.showing_tally = true
	await _snap(id + "_results")
	main.game = null
