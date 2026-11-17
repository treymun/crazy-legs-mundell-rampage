## Pictures of climbing in a real window (the graphics-card view players
## see): every chapter's ladders from the ground, the view from half way up a
## ladder and from the top of the lookout it climbs, a pull-up onto the
## salvage yard's stack, and a hand coming up the ladder after the player.
## <name>.png in out=<dir>.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/climb_frames.gd -- out=<dir>
##
## Point APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

const CHAPTERS := [
	"hickston", "fair", "sawmill", "quarry", "bayou", "speedway", "moonshine", "mothership"
]
const STEP := 1.0 / 60.0

var main
var out := ""


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
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
	await _ladders()
	await _climb()
	await _hand()
	print("climb frames written to ", out)
	main.queue_free()
	await process_frame
	quit()


func _game(level_id: String) -> Game:
	var g: Game = main.make_game(level_id)
	main.game = g
	main.state = "play"
	var options: Dictionary = SessionStore.defaults()
	options["difficulty"] = 2
	g.configure(options)
	g.cheats.god = true
	g.barks.enabled = false
	g.spawn_grace = 99.0
	# The first tick's features (the posse, the variants) before any are cleared.
	g.events.ticked.emit(STEP)
	return g


func _snap(name: String) -> void:
	var g: Game = main.game
	g.message_until = 0.0
	g.barks.until = 0.0
	g.callout_until = 0.0
	g.district_until = 0.0
	main.render()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))


## The player at `at` with feet on the floor at z, looking at (tx, ty, tz).
func _stand(g: Game, at: Vector2, z: float, tx: float, ty: float, tz: float) -> void:
	var p := g.player
	p.x = at.x
	p.y = at.y
	p.floor_z = z
	p.air = 0.0
	p.floor_z = g.world.stand(p)
	p.angle = atan2(ty - at.y, tx - at.x)
	p.eye = .95 + p.floor_z
	var d := Vector2(tx - at.x, ty - at.y).length()
	p.pitch = clampf((tz - p.eye) / maxf(d, .1) * View.base_focal, -50.0, 50.0)
	p.vx = 0.0
	p.vy = 0.0


## Each chapter's ladders from a few steps out, looking up them.
func _ladders() -> void:
	for level_id: String in CHAPTERS:
		var g := _game(level_id)
		g.enemies.clear()
		g.level.triggers = []
		var geo: LevelGeometry = g.world.geo
		if geo == null:
			continue
		for i in geo.ladders.size():
			var lad: LevelGeometry.Ladder = geo.ladders[i]
			var side := Vector2(-lad.dy, lad.dx)
			var back := Vector2(-lad.dx, -lad.dy)
			var at := Vector2(lad.x, lad.y) + back * 2.0
			var found := false
			for reach: float in [3.4, 2.8, 2.2, 1.6]:
				for off: float in [1.6, -1.6, .6, 0.0]:
					var q := Vector2(lad.x, lad.y) + back * reach + side * off
					if found or g.world.blocked(q.x, q.y, .3):
						continue
					if g.world.visible(q.x, q.y, lad.x - lad.dx * .2, lad.y - lad.dy * .2):
						at = q
						found = true
			_stand(g, at, lad.z0, lad.x, lad.y, (lad.z0 + lad.z1) * .5 + .3)
			await _snap("ladder_%s_%s" % [level_id, lad.id])


## Half way up the registry lookout's ladder, then the view from its top,
## then a pull-up onto the salvage yard's stack.
func _climb() -> void:
	var g := _game("hickston")
	g.enemies.clear()
	g.level.triggers = []
	var lad: LevelGeometry.Ladder = null
	for l: LevelGeometry.Ladder in g.world.geo.ladders:
		if l.id == "registry_lookout_ladder":
			lad = l
	var foot := lad.foot()
	_stand(g, foot - Vector2(lad.dx, lad.dy) * .5, lad.z0, lad.x + lad.dx, lad.y + lad.dy, 1.6)
	var c := Game.Controls.new()
	c.forward = 1.0
	for i in 70:
		g.tick(STEP, c)
	g.player.pitch = 18.0
	await _snap("on_ladder_half_way")
	for i in 180:
		g.tick(STEP, c)
		if g.player.ladder < 0 and g.player.climb_time == 0.0:
			break
	var p := g.player
	p.angle = atan2(lad.dy, lad.dx) + PI * .85
	p.pitch = -14.0
	for i in 20:
		g.tick(STEP, Game.Controls.new())
	await _snap("lookout_top_view")
	# A pull-up: from beside the low stack, jump and hold forward.
	_stand(g, Vector2(27.05, 42.3), 0.0, 24.6, 42.6, 1.6)
	var up := Game.Controls.new()
	up.forward = 1.0
	up.jump = true
	for i in 9:
		g.tick(STEP, up)
	await _snap("pull_up_onto_stack")
	for i in 60:
		g.tick(STEP, up)
	g.player.pitch = 6.0
	await _snap("on_the_stack")


## A hand coming up the lookout's ladder after the player on top.
func _hand() -> void:
	var g := _game("hickston")
	g.enemies.clear()
	g.level.triggers = []
	var lad: LevelGeometry.Ladder = null
	for l: LevelGeometry.Ladder in g.world.geo.ladders:
		if l.id == "registry_lookout_ladder":
			lad = l
	var top := lad.top()
	var e := Enemy.new("billy", lad.foot().x - lad.dx * 1.5, lad.foot().y - lad.dy * 1.5)
	e.mind = Squad.Mind.new()
	e.alerted = true
	e.hunting = true
	e.hunt_until = 1e9
	e.target = [top.x, top.y]
	g.enemies.append(e)
	var at := top + Vector2(lad.dx, lad.dy) * 1.0
	_stand(g, at, lad.z1, lad.x - lad.dx * 1.2, lad.y - lad.dy * 1.2, lad.z0 + 1.0)
	var still := Game.Controls.new()
	for i in 600:
		g.tick(STEP, still)
		if e.ladder >= 0 and e.climb_z > 1.0:
			break
	_stand(g, at, lad.z1, lad.x - lad.dx * 1.2, lad.y - lad.dy * 1.2, lad.z0 + 1.0)
	await _snap("hand_up_the_ladder")
	# From the yard: the hand on the ladder against the lookout.
	var g2 := _game("hickston")
	g2.enemies.clear()
	g2.level.triggers = []
	var e2 := Enemy.new("billy", e.x, e.y)
	e2.ladder = e.ladder
	e2.climb_up = true
	e2.climb_z = e.climb_z
	e2.floor_z = lad.z0
	e2.angle = e.angle
	g2.enemies.append(e2)
	var side := Vector2(-lad.dy, lad.dx)
	var from := Vector2(lad.x, lad.y) - Vector2(lad.dx, lad.dy) * 3.5 + side * 2.0
	_stand(g2, from, 0.0, lad.x, lad.y, 1.4)
	await _snap("hand_on_the_ladder_from_the_yard")
