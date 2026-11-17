## Pictures of the big breaks (features/set_pieces.gd) in a real window (the
## graphics-card view players see): each chapter's barn, water tower and fuel
## line standing, coming down (or leaking and burning) and down. Each is
## <level>_<id>_<n>.png in out=<dir>; only=<id,id> picks some.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/set_piece_frames.gd -- out=<dir> [only=a,b]
##
## Point APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

const SetPieces := preload("res://src/features/set_pieces.gd")
const Shape := preload("res://src/set_piece_shape.gd")
const Flow := preload("res://src/set_piece_flow.gd")
const LEVELS := ["hickston", "fair", "sawmill", "speedway"]
## Where to look from, by set piece: [eye x, y, at x, y, z] (else a spot
## worked out round it).
const VIEWS := {
	"orchard-shed": [12.6, 21.2, 18.5, 15.6, 1.3],
	"town-tower": [51.0, 63.6, 60.5, 71.5, 3.6],
	"gas-line": [24.5, 63.8, 30.5, 57.0, .1],
}

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
	for level_id: String in LEVELS:
		var g := _level(level_id)
		var sp: SetPieces = g.features.get("set_pieces")
		if sp == null:
			continue
		var n := sp.pieces.size()
		for i in n:
			var spec: Dictionary = sp.spec_of(i)
			var id := str(spec.get("id", "piece%d" % i))
			if not only.is_empty() and not only.has(id):
				continue
			g = _level(level_id)
			sp = g.features.get("set_pieces")
			match str(spec["kind"]):
				"barn":
					await _barn(g, sp, i, level_id + "_" + id)
				"tower":
					await _tower(g, sp, i, level_id + "_" + id)
				"fuel":
					await _fuel(g, sp, i, level_id + "_" + id)
	print("set piece frames written to ", out)
	main.queue_free()
	await process_frame
	quit()


func _snap(name: String) -> void:
	if main.game != null:
		main.game.message_until = 0.0
		main.game.barks.until = 0.0
	main.render()
	await RenderingServer.frame_post_draw
	main.render()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))


func _level(level_id: String) -> Game:
	main.start(level_id)
	var g: Game = main.game
	g.cheats.god = true
	g.lessons = false
	g.barks.enabled = false
	for e: Enemy in g.enemies:
		e.dormant = true
	g.message_until = 0.0
	g.district_until = 0.0
	return g


## Stand at the set piece's own view if it has one: true.
func _view(g: Game, id: String) -> bool:
	if not VIEWS.has(id):
		return false
	var v: Array = VIEWS[id]
	_stand(g, v[0], v[1], v[2], v[3], g.world.elevation(v[2], v[3]) + float(v[4]))
	return true


func _stand(g: Game, x: float, y: float, tx: float, ty: float, tz: float) -> void:
	var p := g.player
	p.x = x
	p.y = y
	p.angle = atan2(ty - y, tx - x)
	p.floor_z = g.world.elevation(x, y)
	p.air = 0.0
	p.eye = .95 + p.floor_z
	var d := Vector2(tx - x, ty - y).length()
	p.pitch = clampf((tz - p.eye) / maxf(d, .1) * View.base_focal, -50.0, 50.0)
	p.vx = 0.0
	p.vy = 0.0


func _ticks(g: Game, seconds: float) -> void:
	for i in int(seconds * 60.0):
		g.tick(1.0 / 60.0, Game.Controls.new())


## A spot `d` off the middle of piece i, on open ground that sees it, from
## the way `from` (radians) first.
func _spot(g: Game, at: Vector2, d: float, from: float) -> Vector2:
	for reach: float in [d, d * .85, d * .7, d * 1.2, d * .55]:
		for k in 24:
			var a := from + (k / 2) * (TAU / 24.0) * (1 if k % 2 == 0 else -1)
			var s := at + Vector2(cos(a), sin(a)) * reach
			if s.x < 1 or s.y < 1 or s.x > g.world.width - 1 or s.y > g.world.height - 1:
				continue
			if g.world.blocked(s.x, s.y, .3):
				continue
			var z := g.world.elevation(s.x, s.y)
			if g.world.visible(s.x, s.y, at.x, at.y, z + .95, z + 1.0):
				return s
	return at + Vector2(d, 0)


func _codes(sp: SetPieces, i: int, role: String) -> Array:
	var out_codes: Array = []
	var made: Array = sp.shapes[i]
	for k in made.size():
		var part: Shape.Part = made[k]
		if part.role == role:
			out_codes.append(i * 1000 + k)
	return out_codes


func _barn(g: Game, sp: SetPieces, i: int, name: String) -> void:
	var box: Rect2 = sp._boxes[i]
	var mid := box.get_center()
	var spec: Dictionary = sp.spec_of(i)
	var face := Shape.turn_of(spec) * Vector3(0, -1, 0)
	var eye := _spot(g, mid, 9.0, atan2(face.y, face.x) + .5)
	_stand(g, eye.x, eye.y, mid.x, mid.y, g.world.elevation(mid.x, mid.y) + 1.6)
	_view(g, str(spec.get("id", "")))
	_ticks(g, .2)
	await _snap(name + "_0_standing")
	var walls := _codes(sp, i, "wall")
	if not walls.is_empty():
		sp.strike(walls[0], 40.0, 0.0, 0.0)
		_ticks(g, .1)
		await _snap(name + "_1_wall_shot")
	var posts := _codes(sp, i, "post")
	sp.strike(posts[0], 300.0, face.x, face.y)
	sp.strike(posts[1], 300.0, face.x, face.y)
	_ticks(g, .5)
	await _snap(name + "_2_creak")
	_ticks(g, .75)
	await _snap(name + "_3_falling")
	_ticks(g, .5)
	await _snap(name + "_4_landing")
	_ticks(g, 3.0)
	await _snap(name + "_5_down")
	var other := _spot(g, mid, 6.0, atan2(face.y, face.x) + PI * .75)
	_stand(g, other.x, other.y, mid.x, mid.y, g.world.elevation(mid.x, mid.y) + .3)
	_ticks(g, .05)
	await _snap(name + "_6_down_near")


func _tower(g: Game, sp: SetPieces, i: int, name: String) -> void:
	var spec: Dictionary = sp.spec_of(i)
	var at := Vector2(Shape.f(spec["x"]), Shape.f(spec["y"]))
	var falls: Array = spec.get("falls", [3])
	var way := Vector2.from_angle(roundi(Shape.f(falls[falls.size() - 1])) * PI * .5).round()
	var side := Vector2(-way.y, way.x)
	var eye := _spot(g, at + way * 5.0, 12.0, side.angle() + .2)
	_stand(
		g, eye.x, eye.y, at.x + way.x * 3.0, at.y + way.y * 3.0, g.world.elevation(at.x, at.y) + 3.0
	)
	_view(g, str(spec.get("id", "")))
	_ticks(g, .2)
	await _snap(name + "_0_standing")
	for code: int in _codes(sp, i, "leg"):
		var part: Shape.Part = sp.shapes[i][code % 1000]
		if part.side.dot(way) > 0.0:
			sp.strike(code, 400.0, way.x, way.y)
	_ticks(g, 1.2)
	await _snap(name + "_1_going")
	_ticks(g, .8)
	await _snap(name + "_2_falling")
	_ticks(g, .6)
	await _snap(name + "_3_burst")
	_ticks(g, 1.2)
	await _snap(name + "_4_flood")
	if not sp.floods.is_empty():
		var f: Dictionary = sp.floods[0]
		var fx: float = f["x"]
		var fy: float = f["y"]
		var back := Vector2(fx, fy) - way * 6.0 + side * 2.0
		_stand(g, back.x, back.y, fx, fy, g.world.elevation(fx, fy))
		_ticks(g, .02)
		await _snap(name + "_4b_water")
	_ticks(g, 3.0)
	await _snap(name + "_5_down")
	var near := _spot(g, at + way * 4.0, 4.5, side.angle() + PI)
	_stand(
		g,
		near.x,
		near.y,
		at.x + way.x * 4.0,
		at.y + way.y * 4.0,
		g.world.elevation(at.x, at.y) + .4
	)
	_ticks(g, .05)
	await _snap(name + "_6_down_near")


func _fuel(g: Game, sp: SetPieces, i: int, name: String) -> void:
	var cells: Array = sp.trails[i]
	var first: Vector2i = cells[0]
	var last: Vector2i = cells[cells.size() - 1]
	var mid := Vector2(first.x + last.x + 1.0, first.y + last.y + 1.0) * .5
	var eye := _spot(g, mid, 8.0, PI * .5)
	_stand(g, eye.x, eye.y, mid.x, mid.y, g.world.elevation(mid.x, mid.y) + .2)
	_view(g, str(sp.spec_of(i).get("id", "")))
	_ticks(g, .2)
	await _snap(name + "_0_standing")
	var pumps := _codes(sp, i, "pump")
	sp.strike(pumps[0], 100.0, 0.0, 1.0)
	_ticks(g, 4.0)
	await _snap(name + "_1_leaking")
	var fire = g.features["fire"]
	fire.fresh()
	fire.ignite(first.x + .5, first.y + .5, g.world.elevation(first.x + .5, first.y + .5), 3.0)
	_ticks(g, .7)
	await _snap(name + "_2_running")
	_ticks(g, 1.2)
	await _snap(name + "_3_end")
