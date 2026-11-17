## Pictures of the boss arenas' lock (features/boss_lock.gd) in a real window:
## for each boss, from inside its room looking back at a way in, the way open
## as the player came in, then shut once the fight has begun. Each pair is one
## picture side by side, <kind>_lock.png in out=<dir> (each half at half the
## window's size).
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/lock_frames.gd -- out=<dir> [kinds=boss,rudy]
##
## Point APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

const KINDS := [
	"boss", "jerry", "rudy", "foreman", "baron", "swamp_king", "derby_champ", "revenue_man", "maw"
]
## Which way in each looks at (by its place in BossFight.entrances), and how
## far inside it stands.
const WAY := {"boss": 1, "baron": 1, "derby_champ": 1, "swamp_king": 13}
const BACK := 4.5

var main
var out := ""


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var kinds: Array = KINDS.duplicate()
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
		elif String(arg).begins_with("kinds="):
			kinds = Array(String(arg).substr(6).split(",", false))
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
	for kind: String in kinds:
		await _pair(kind)
	print("lock frames written to ", out)
	main.queue_free()
	await process_frame
	quit()


func _grab() -> Image:
	var g: Game = main.game
	g.message_until = 0.0
	g.barks.until = 0.0
	g.callout_until = 0.0
	main.render()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.resize(image.get_width() / 2, image.get_height() / 2, Image.INTERPOLATE_NEAREST)
	return image


func _ticks(g: Game, n: int, e: Enemy) -> void:
	for i in n:
		e.stun = 10.0
		e.cooldown = 10.0
		g.tick(1.0 / 60.0, Game.Controls.new())


func _look(g: Game, at: Vector2, to: Vector2) -> void:
	var p := g.player
	Modes.place(g, p, at.x, at.y, atan2(to.y - at.y, to.x - at.x))
	p.floor_z = g.world.elevation(at.x, at.y)
	var d := at.distance_to(to)
	p.pitch = clampf(
		(g.world.elevation(to.x, to.y) + 1.0 - p.eye) / d * View.base_focal, -30.0, 30.0
	)


func _pair(kind: String) -> void:
	var sheet: Dictionary = BossData.get_value("boss_lock", kind)
	var level_id := str(sheet["level"])
	var g: Game = main.make_game(level_id)
	main.game = g
	main.state = "play"
	g.configure(SessionStore.defaults())
	g.cheats.god = true
	g.barks.enabled = false
	g.weapon_view = 2
	var e := BossFight.of_kind(g, kind)
	e.dormant = false
	e.alerted = true
	for other: Enemy in g.enemies:
		if other != e:
			other.hp = 0.0
			other.alive = false
	for door: LevelData.Door in BossFight.lock_doors(g, kind):
		door.opened = true
		door.progress = 1.0
	var ways := BossFight.entrances(g, kind)
	var cell: Vector2i = ways[mini(int(WAY.get(kind, 0)), ways.size() - 1)]
	var middle := Vector2(cell.x + .5, cell.y + .5)
	# Inward: toward the neighbour in the room.
	var inward := Vector2.ZERO
	for d: Vector2i in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		if BossFight.in_room(g, kind, middle.x + d.x, middle.y + d.y):
			inward = Vector2(d)
	if inward == Vector2.ZERO:
		# A bridge far from the room: look at it from its near side.
		inward = Vector2(0, -1)
	var at := middle + inward * BACK
	for step in 12:
		if not g.world.blocked(at.x, at.y, .4):
			break
		at += Vector2(inward.y, -inward.x) * .5
	_ticks(g, 2, e)
	_look(g, at, middle)
	var before: Image = await _grab()
	# In to the spot: the fight begins and it shuts.
	var spot: Array = sheet["spot"]
	Modes.place(g, g.player, float(spot[0]), float(spot[1]), 0.0)
	var lock: GameFeature = g.features["boss_lock"]
	for i in 60:
		_ticks(g, 1, e)
		if str(lock.get("kind")) != "":
			break
	_ticks(g, 90, e)
	_look(g, at, middle)
	_ticks(g, 1, e)
	_look(g, at, middle)
	var during: Image = await _grab()
	var both := Image.create(
		before.get_width() * 2 + 4, before.get_height(), false, before.get_format()
	)
	both.fill(Color.BLACK)
	both.blit_rect(before, Rect2i(Vector2i.ZERO, before.get_size()), Vector2i.ZERO)
	both.blit_rect(
		during, Rect2i(Vector2i.ZERO, during.get_size()), Vector2i(before.get_width() + 4, 0)
	)
	both.save_png(out.path_join(kind + "_lock.png"))
	print(kind, ": shut ", str(lock.get("kind")) != "", " looking at ", cell, " from ", at)
