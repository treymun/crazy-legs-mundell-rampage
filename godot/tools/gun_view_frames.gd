## Pictures of every gun in first person in a real window (src/weapons.gd's
## Armory.draw over the 3D view): each gun at rest, through a shot (every pose
## it passes through, the flash in the first), through a reload (every pose),
## going down as it is put away and halfway up as it is drawn, and every
## choice of its junk bench mods at rest.
## <gun>_<what>.png in out=<dir>; only=<gun,...> takes some guns.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/gun_view_frames.gd -- out=<dir> [only=revolver,shotgun]
##
## Point APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

const STEP := 1.0 / 60.0
## The bench's mods by gun (BenchMods' table), each choice drawn at rest.
const MODDED := {
	"revolver": [["scope"], ["loader"], ["loader", "scope"]],
	"shotgun": [["bayonet"], ["choke"], ["bayonet", "choke"]],
	"rifle": [["brake"], ["drum"], ["brake", "drum"]],
	"crossbow": [["flame"], ["spring"], ["flame", "spring"]],
	"tnt": [["bundle"], ["fuse"], ["bundle", "fuse"]],
}

var main
var out := ""
var only: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		var text := String(arg)
		if text.begins_with("out="):
			out = text.substr(4)
		elif text.begins_with("only="):
			only = Array(text.substr(5).split(","))
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
	main.options["bench"] = 1
	main.start("hickston")
	var g: Game = main.game
	g.cheats.god = true
	g.lessons = false
	g.barks.enabled = false
	for e: Enemy in g.enemies:
		if e.hostile:
			e.dormant = true
	g.spawn_grace = 99.0
	_ticks(g, 3)
	g.player.pitch = 4.0
	for slot in Weapons.COUNT:
		var gun: String = Weapons.NAMES[slot]
		if not only.is_empty() and not only.has(gun):
			continue
		await _gun(g, slot)
	print("gun view frames written to ", out)
	main.queue_free()
	await process_frame
	quit()


func _arm(g: Game, slot: int, mods: Array) -> void:
	var a := g.armory
	var typed: Array[String] = []
	for m: String in mods:
		typed.append(m)
	a.mods = typed
	a.owned[slot] = true
	a.reserve[slot] = 20
	a.reserve[Weapons.CROSSBOW] = 20
	a.loaded[slot] = Weapons.CAPACITY[slot]
	if a.active != slot:
		a.select(slot, g)
	a.reload = 0.0
	a.cooldown = 0.0
	a.fuse = 0.0
	a.switch = 0.0
	a.shot_age = 1.0
	a.flash = 0.0
	g.player.weapon_lag = Vector2.ZERO


func _gun(g: Game, slot: int) -> void:
	var gun: String = Weapons.NAMES[slot]
	var a := g.armory
	_arm(g, slot, [])
	_ticks(g, 30)
	await _snap("%s_idle" % gun)
	# Put away (going down), then another drawn halfway up.
	var other := Weapons.CROWBAR if slot != Weapons.CROWBAR else Weapons.REVOLVER
	a.select(other, g)
	_ticks(g, 3)
	await _snap("%s_lower" % gun)
	_ticks(g, 20)
	a.select(slot, g)
	_ticks(g, 9)
	await _snap("%s_raise" % gun)
	# A shot: every pose it passes through.
	_arm(g, slot, [])
	_ticks(g, 30)
	a.fire(g)
	if slot == Weapons.DYNAMITE or slot in Weapons.THROWN_GUNS:
		_ticks(g, 20)
		await _snap("%s_lit" % gun)
		a.release_dynamite(g)
	var seen := {"idle": true}
	var k := 0
	for t in 90:
		_ticks(g, 1)
		var pose := a.pose()
		if not seen.has(pose):
			seen[pose] = true
			await _snap("%s_fire%d_%s" % [gun, k, pose])
			k += 1
	# A reload, if it has one.
	if Weapons.CAPACITY[slot] > 0:
		_arm(g, slot, [])
		a.loaded[slot] = 0
		_ticks(g, 2)
		a.start_reload(g)
		var poses := {}
		for t in 240:
			_ticks(g, 1)
			if a.reload <= 0.0:
				break
			var pose2 := a.pose()
			if not poses.has(pose2):
				poses[pose2] = true
				_ticks(g, 2)
				await _snap("%s_reload_%s" % [gun, pose2])
	for mods: Array in MODDED.get(gun, []):
		_arm(g, slot, mods)
		_ticks(g, 4)
		await _snap("%s_mod_%s" % [gun, "_".join(mods)])
	_arm(g, slot, [])


func _snap(name: String) -> void:
	var g: Game = main.game
	g.message_until = 0.0
	g.callout_until = 0.0
	g.district_until = 0.0
	g.barks.until = 0.0
	main.render()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))


func _ticks(g: Game, n: int) -> void:
	for i in n:
		g.tick(STEP, Game.Controls.new())
