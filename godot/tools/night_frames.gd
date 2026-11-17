## How well the enemies read against the world, in a real window: each
## chapter's own hands stood where the level puts them, seen from a few cells
## off, and the same view drawn again with the one enemy taken away. The
## pixels that differ are the enemy; the line printed for each says how
## light it is against what it hides in the finished frame (mean CIE L*,
## night_contrast.gd) and how much each of its pixels differs from the ground
## behind it (mean |dL*|), the number a player's eye reads a figure by.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/night_frames.gd -- out=<dir> [only=moonshine,dark] [per=4]
##
## Writes <dir>/<tag>.png (the frame), <tag>_3d.png and <tag>_bare_3d.png
## (the 3D view with and without the enemy). Point APPDATA at a scratch
## folder: it runs the game with the profile there.
extends SceneTree

const STEP := 1.0 / 60.0
const Contrast := preload("res://tools/night_contrast.gd")
const LEVELS := [
	"hickston", "fair", "sawmill", "quarry", "bayou", "speedway", "moonshine", "mothership"
]

var main
var out := ""
var only: Array = []
var per := 4
var rows: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		var text := String(arg)
		if text.begins_with("out="):
			out = text.substr(4)
		elif text.begins_with("only="):
			only = text.substr(5).split(",")
		elif text.begins_with("per="):
			per = int(text.substr(4))
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
	for level_id: String in LEVELS:
		if only.is_empty() or only.has(level_id):
			await _level_foes(level_id)
	if only.is_empty() or only.has("dark"):
		await _blackout()
	print("NIGHT FRAMES: %d views to %s" % [rows.size(), out])
	main.queue_free()
	await process_frame
	quit()


func _start(level_id: String) -> Game:
	main.options["events"] = 0
	main.start(level_id)
	var g: Game = main.game
	g.cheats.god = true
	g.lessons = false
	g.barks.enabled = false
	g.spawn_grace = 99.0
	for i in 4:
		g.tick(STEP, Game.Controls.new())
	return g


func _place(g: Game, at: Vector2, look: Vector3) -> void:
	var p := g.player
	p.x = at.x
	p.y = at.y
	p.floor_z = g.world.elevation(at.x, at.y)
	p.eye = .95 + g.world.stand(p)
	p.angle = atan2(look.y - at.y, look.x - at.x)
	var drop := (p.floor_z + p.eye) - (look.z + .7)
	p.pitch = clampf(-drop / maxf(at.distance_to(Vector2(look.x, look.y)), 1.0) * 230.0, -30, 30)
	p.drunk = 0.0
	p.sway = 0.0
	g.armory.holstered = true
	g.armory.lower = 1.0


## A spot about `far` from `spot` on open ground that sees it up to `top`.
func _vantage(g: Game, spot: Vector2, facing: float, far: float, top := 1.4) -> Vector2:
	var ground := g.world.elevation(spot.x, spot.y)
	for ring: float in [far, far * .8, far * 1.25]:
		for k in 24:
			var q := spot + Vector2.from_angle(facing + k * TAU / 24.0) * ring
			if q.x < 2 or q.y < 2 or q.x > g.world.width - 2 or q.y > g.world.height - 2:
				continue
			if g.world.blocked(q.x, q.y, .35):
				continue
			var z := g.world.elevation(q.x, q.y)
			if absf(z - ground) > 1.5:
				continue
			if (
				g.world.visible(q.x, q.y, spot.x, spot.y, z + .95, ground + .15)
				and g.world.visible(q.x, q.y, spot.x, spot.y, z + .95, ground + top)
			):
				return q
	return Vector2.INF


func _level_foes(level_id: String) -> void:
	var g := _start(level_id)
	var picks: Array[Enemy] = []
	var hostile: Array[Enemy] = []
	for e: Enemy in g.enemies:
		if e.alive and e.hostile and not Enemy.BOSS_TITLES.has(e.kind):
			hostile.append(e)
	if hostile.is_empty():
		return
	var stride := maxi(1, hostile.size() / per)
	for i in range(0, hostile.size(), stride):
		if picks.size() < per:
			picks.append(hostile[i])
	for k in picks.size():
		var e := picks[k]
		for far: float in [4.0, 9.0]:
			var at := _vantage(g, Vector2(e.x, e.y), e.angle, far)
			if at == Vector2.INF:
				continue
			_place(g, at, Vector3(e.x, e.y, g.world.elevation(e.x, e.y)))
			e.angle = atan2(at.y - e.y, at.x - e.x)
			await _measure(g, e, "%s_%s_%d_%d" % [level_id, e.kind, k, int(far)])
	await _level_pickups(g, level_id)


## A few of the level's pickups, seen from 3 and 6 cells.
func _level_pickups(g: Game, level_id: String) -> void:
	var stride := maxi(1, g.pickups.size() / 3)
	for i in range(0, mini(g.pickups.size(), stride * 3), stride):
		var entry: Array = g.pickups[i]
		var spot := Vector2(entry[1], entry[2])
		for far: float in [3.0, 6.0]:
			var at := _vantage(g, spot, 0.0, far, .4)
			if at == Vector2.INF:
				continue
			_place(g, at, Vector3(spot.x, spot.y, g.world.elevation(spot.x, spot.y) - .5))
			await _measure(g, entry, "%s_item_%s_%d" % [level_id, str(entry[0]), int(far)])


func _blackout() -> void:
	main.options["events"] = 2
	main.start("hickston")
	var g: Game = main.game
	g.cheats.god = true
	g.lessons = false
	g.barks.enabled = false
	for i in 4:
		g.tick(STEP, Game.Controls.new())
	var ev: CountyEvents = g.features["events"]
	ev.begin("blackout")
	for i in int(ev.n("blackout", "fade") * 60.0) + 10:
		g.tick(STEP, Game.Controls.new())
	g.spawn_grace = 99.0
	var foe: Enemy = null
	for e: Enemy in g.enemies:
		if e.alive and e.hostile and not ev.lanterns.has(g.enemies.find(e)):
			if foe == null:
				foe = e
	var p := g.player
	for spot: Array in [[4.0, 0.0, "beam"], [7.0, .3, "edge"], [6.0, .48, "out"]]:
		var ahead: float = spot[0]
		var turn: float = spot[1]
		foe.x = p.x + cos(p.angle + turn) * ahead
		foe.y = p.y + sin(p.angle + turn) * ahead
		foe.angle = p.angle + PI
		p.pitch = -6.0
		for i in 2:
			g.tick(STEP, Game.Controls.new())
		await _measure(g, foe, "dark_hickston_%s_on" % spot[2])
		g.torch()
		g.tick(STEP, Game.Controls.new())
		await _measure(g, foe, "dark_hickston_%s_off" % spot[2])
		g.torch()


func _snap(g: Game) -> Image:
	g.message_until = 0.0
	g.callout_until = 0.0
	g.district_until = 0.0
	g.barks.until = 0.0
	g.caption_until = 0.0
	main.render()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return main.world_view.viewport.get_texture().get_image()


## `what`: an Enemy, or a pickup's entry (kind, x, y, ...), taken away
## for the bare picture and put back.
func _measure(g: Game, what: Variant, tag: String) -> void:
	var with := await _snap(g)
	var with_frame := root.get_texture().get_image()
	var keep: Vector2
	if what is Enemy:
		keep = Vector2(what.x, what.y)
		what.x = -500.0
	else:
		keep = Vector2(what[1], what[2])
		what[1] = -500.0
	var bare := await _snap(g)
	var bare_frame := root.get_texture().get_image()
	if what is Enemy:
		what.x = keep.x
	else:
		what[1] = keep.x
	with_frame.save_png(out.path_join(tag + ".png"))
	with.save_png(out.path_join(tag + "_3d.png"))
	bare.save_png(out.path_join(tag + "_bare_3d.png"))
	var r: Dictionary = Contrast.measure(with, bare, with_frame, bare_frame)
	rows.append([tag, r])
	print(
		(
			"NIGHT %-36s px %5d  foe L* %5.1f  behind L* %5.1f  mean|dL*| %5.1f  from %.1f %.1f %.2f"
			% [
				tag,
				r["px"],
				r["foe"],
				r["behind"],
				r["delta"],
				g.player.x,
				g.player.y,
				g.player.angle
			]
		)
	)
