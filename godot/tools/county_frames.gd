## Pictures of COUNTY RUN (src/modes/county_*.gd) in a real window (the
## graphics-card view players see): the title with COUNTY RUN picked, the map
## picker, then on each map a look round a minute in with the bot playing
## (the HUD: XP bar, level, clock, slots, abilities), XP lying about, the
## reward cards, a milestone's cards, the swap with every slot full, the
## build screen and the end of a run. <name>.png in out=<dir>.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/county_frames.gd -- out=<dir> [maps=county_hickston]
##
## Point APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

const Bot := preload("res://tools/county_bot.gd")

var main
var out := ""


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var maps: Array = CountyData.MAP_IDS.duplicate()
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
	CountyRecords.folder_override = out.path_join("records")
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.touring = true
	Effects.enabled = true
	main.state = "title"
	main.selection = main.entries().find("COUNTY RUN")
	await _shot("title")
	main.state = "county"
	CountyScreens.map_row = 1
	await _shot("picker")
	for map: String in maps:
		await _map(map)
	print("county frames written to ", out)
	main.queue_free()
	await process_frame
	quit()


func _shot(name: String) -> void:
	main.render()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))


func _map(id: String) -> void:
	var g: Game = main.make_game(id)
	main.game = g
	main.state = "play"
	g.configure(SessionStore.defaults())
	Modes.setup(g, Modes.COUNTY, 1)
	g.barks.enabled = false
	g.cheats.god = true
	CountyScreens.reset()
	var f = g.features["county"]
	var bot = Bot.new()
	# A minute in, picking as the bot likes (the first card shown is kept).
	var cards_shot := false
	while f.run_time < 60.0:
		if f.on and not f.pending.is_empty():
			if not cards_shot and f.run_time > 8.0:
				cards_shot = true
				g.message_until = 0.0
				await _shot(id + "_cards")
			CountyMode.choose(g, Bot.pick(g, f), 0)
			continue
		g.tick(1.0 / 60.0, bot.steer(g))
		bot.moved(g)
	g.message_until = 0.0
	g.callout_until = 0.0
	await _shot(id + "_hud")
	# XP on the floor ahead.
	var p: Player = g.player
	for k in 7:
		var a := p.angle + (k - 3) * .12
		CountyOrbs._lay(
			f,
			p.x + cos(a) * (2.0 + k * .4),
			p.y + sin(a) * (2.0 + k * .4),
			g.world.stand(p),
			[1, 2, 5, 9, 14, 3, 1][k],
			"xp"
		)
	await _shot(id + "_xp")
	# Every slot full, a weapon offered: the swap.
	for slot in f.slots.size():
		if int(f.slots[slot]) < 0:
			CountyBuild.put_weapon(
				g,
				f,
				(
					Weapons.SHOTGUN
					if not CountyBuild.carried(f).has(Weapons.SHOTGUN)
					else Weapons.RIFLE
				),
				slot
			)
	f.ranks[CountyBuild.key(int(f.slots[0]), String(CountyData.upgrades_for(int(f.slots[0]))[0]))] = 2
	f.pending = [[f.level + 1, false, g.armory.active]]
	var spare := CountyBuild.unowned_weapons(f)
	f.offer = [
		CountyBuild.card("weapon", "", int(spare[0])),
		CountyBuild.card("perk", "good_boots"),
		CountyBuild.card(
			"upgrade", String(CountyData.upgrades_for(int(f.slots[0]))[0]), int(f.slots[0])
		),
	]
	await _shot(id + "_offer")
	CountyScreens.swapping = 0
	CountyScreens.swap_slot = 0
	await _shot(id + "_swap")
	CountyScreens.swapping = -1
	CountyScreens.swap_slot = -1
	# A milestone's cards.
	f.pending = [[10, true, g.armory.active]]
	f.offer = CountyBuild.milestone_offers(g, f)
	await _shot(id + "_milestone")
	f.pending = []
	f.offer = []
	CountyScreens.build_open = true
	await _shot(id + "_build")
	CountyScreens.build_open = false
	# The end.
	g.cheats.god = false
	g.damage(500.0, null, "TEST")
	await _shot(id + "_end")
	main.game = null
