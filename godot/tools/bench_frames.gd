## Pictures of Mundell's junk bench (src/bench_mods.gd, features/bench.gd,
## src/bench_screen.gd) in a real window:
##   bench_hub         the Crossroads' bench on the Road Department's counter
##   bench_hub_near    walked up to it, USE's prompt
##   bench_screen      its board up, some scrap and mods had
##   bench_chapter     a chapter's own bench by where it starts
##   bench_scrap       the three pieces of scrap lying out
##   bench_gun_<view>  each gun with its mods on (and none), in hand, the HUD's marks
## Each lands in out=<dir> as <name>.png; only=<a,b> takes some of them.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/bench_frames.gd -- out=<dir> [only=hub,screen,guns]
##
## Point APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

const GUNS := [
	["revolver", []],
	["revolver", ["scope"]],
	["revolver", ["loader"]],
	["revolver", ["loader", "scope"]],
	["shotgun", []],
	["shotgun", ["bayonet"]],
	["shotgun", ["choke"]],
	["shotgun", ["bayonet", "choke"]],
	["rifle", []],
	["rifle", ["brake"]],
	["rifle", ["drum"]],
	["rifle", ["brake", "drum"]],
	["crossbow", ["flame"]],
	["crossbow", ["spring"]],
	["crossbow", ["flame", "spring"]],
	["tnt", ["bundle"]],
	["tnt", ["fuse"]],
	["tnt", ["bundle", "fuse"]],
]

var main
var out := ""
var only: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
		elif String(arg).begins_with("only="):
			only = String(arg).substr(5).split(",")
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
	if _wanted("hub") or _wanted("screen"):
		await _hub()
	if _wanted("chapter"):
		var g := _level("hickston")
		_ticks(g, 3)
		var bench = g.features["bench"]
		if not bench.benches.is_empty():
			var b: Array = bench.benches[0]
			var p := g.player
			var facing: float = b[2]
			p.x = float(b[0]) + sin(facing) * 2.4
			p.y = float(b[1]) + cos(facing) * 2.4
			p.angle = atan2(float(b[1]) - p.y, float(b[0]) - p.x)
			p.pitch = -8.0
			_ticks(g, 2)
			await _snap("bench_chapter")
		else:
			print("no chapter bench in hickston")
	if _wanted("scrap"):
		var g := _level("hickston")
		_ticks(g, 3)
		var p := g.player
		for k in 3:
			var a := p.angle + (k - 1) * .2
			g.add_pickup(
				["scrap_bolts", "scrap_wire", "scrap_hubcap"][k],
				p.x + cos(a) * 2.5,
				p.y + sin(a) * 2.5
			)
		p.pitch = -24.0
		g.armory.holstered = true
		g.armory.lower = 1.0
		_ticks(g, 2)
		await _snap("bench_scrap")
	if _wanted("guns"):
		var g := _level("hickston")
		_ticks(g, 3)
		g.player.pitch = 4.0
		for row: Array in GUNS:
			var gun: String = row[0]
			var mods: Array[String] = []
			for m: String in row[1]:
				mods.append(m)
			var slot := Weapons.NAMES.find(gun)
			g.armory.owned[slot] = true
			g.armory.reserve[slot] = 20
			g.armory.reserve[Weapons.CROSSBOW] = 20
			g.armory.loaded[slot] = Weapons.CAPACITY[slot]
			g.armory.active = slot
			g.armory.mods = mods
			g.armory.scrap = 9
			g.armory.switch = 0.0
			g.armory.shot_age = 1.0
			_ticks(g, 2)
			await _snap("bench_gun_%s" % g.armory.art_name(slot))
	print("bench frames written to ", out)
	main.queue_free()
	await process_frame
	quit()


func _hub() -> void:
	main.options["bench"] = 1
	main.start("hickston")
	var from: Game = main.game
	from.armory.scrap = 14
	from.armory.owned[Weapons.SHOTGUN] = true
	from.armory.owned[Weapons.RIFLE] = true
	from.armory.owned[Weapons.CROSSBOW] = true
	from.armory.owned[Weapons.DYNAMITE] = true
	var some: Array[String] = ["choke", "loader"]
	from.armory.mods = some
	main.open_hub(from)
	var g: Game = main.game
	g.lessons = false
	g.barks.enabled = false
	_ticks(g, 3)
	var p := g.player
	var at: Vector2 = BenchMods.value("bench", "hub_at", Vector2.ZERO)
	if _wanted("hub"):
		p.x = at.x + 1.2
		p.y = at.y + 4.2
		p.angle = atan2(at.y - p.y, at.x - p.x)
		p.pitch = -4.0
		_ticks(g, 2)
		await _snap("bench_hub")
		p.x = at.x
		p.y = at.y + 1.25
		p.angle = -PI * .5
		p.pitch = -14.0
		_ticks(g, 2)
		await _snap("bench_hub_near", false)
	if _wanted("screen"):
		p.x = at.x
		p.y = at.y + 1.25
		p.angle = -PI * .5
		p.pitch = -14.0
		_ticks(g, 2)
		BenchScreen.show(g)
		BenchScreen.row = 2
		BenchScreen.column = 1
		await _snap("bench_screen", false)
		BenchScreen.open = false


func _wanted(part: String) -> bool:
	return only.is_empty() or only.has(part)


func _snap(name: String, quiet := true) -> void:
	var g: Game = main.game
	if g != null and quiet:
		g.message_until = 0.0
		g.callout_until = 0.0
		g.district_until = 0.0
		g.barks.until = 0.0
	main.render()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))


func _level(level_id: String) -> Game:
	main.options["bench"] = 1
	main.start(level_id)
	var g: Game = main.game
	g.cheats.god = true
	g.lessons = false
	g.barks.enabled = false
	for e: Enemy in g.enemies:
		if e.hostile:
			e.dormant = true
	g.spawn_grace = 99.0
	return g


func _ticks(g: Game, n: int) -> void:
	for i in n:
		g.tick(1.0 / 60.0, Game.Controls.new())
