## Pictures of the boss arenas coming apart and the bosses' gear shot off
## (features/arena_wreck.gd, features/boss_gear.gd) in a real window. For
## each boss, in its rematch's game: its arena before, each wreck step
## warning (its lane or ring on the ground), going over and lying after;
## then its gear on, a piece flying off and lying on the floor. Each picture
## is <kind>_<moment>.png in out=<dir>, at half the window's size.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/wreck_frames.gd -- out=<dir> [kinds=boss,baron]
##
## Point APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

const KINDS := ["boss", "jerry", "rudy", "foreman", "baron", "swamp_king", "derby_champ", "maw"]

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
		await _wreck(kind)
		await _gear(kind)
	print("wreck frames written to ", out)
	main.queue_free()
	await process_frame
	quit()


func _snap(name: String) -> void:
	if main.game != null:
		main.game.message_until = 0.0
		main.game.barks.until = 0.0
		main.game.callout_until = 0.0
	main.render()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.resize(image.get_width() / 2, image.get_height() / 2, Image.INTERPOLATE_NEAREST)
	image.save_png(out.path_join(name + ".png"))


func _ticks(g: Game, n: int, e: Enemy) -> void:
	for i in n:
		if e != null:
			e.stun = 10.0
			e.cooldown = 10.0
		g.tick(1.0 / 60.0, Game.Controls.new())


## Stand at (x, y) looking at (tx, ty) at height tz.
func _stand(g: Game, at: Vector2, tx: float, ty: float, tz: float) -> void:
	var p := g.player
	p.x = at.x
	p.y = at.y
	p.angle = atan2(ty - at.y, tx - at.x)
	p.eye = .95 + g.world.stand(p)
	var d := Vector2(tx - at.x, ty - at.y).length()
	p.pitch = clampf((tz - p.eye) / maxf(d, .1) * View.base_focal, -50.0, 50.0)
	p.vx = 0.0
	p.vy = 0.0


## An open spot `gap` from (x, y) that sees it, the nearest way to `prefer`.
func _spot(g: Game, x: float, y: float, gap: float, prefer: float) -> Vector2:
	var w := g.world
	for k in 32:
		var a := prefer + (k / 2) * TAU / 32.0 * (1.0 if k % 2 == 0 else -1.0)
		var at := Vector2(x + cos(a) * gap, y + sin(a) * gap)
		if (
			at.x > 1.0
			and at.y > 1.0
			and at.x < w.width - 1
			and at.y < w.height - 1
			and not w.blocked(at.x, at.y, .4)
			and w.visible(at.x, at.y, x, y, 1.2, 1.0)
		):
			return at
	return Vector2(x + cos(prefer) * gap, y + sin(prefer) * gap)


func _game(kind: String) -> Game:
	var g: Game = BossRematch.build(Callable(main, "make_game"), kind)
	main.game = g
	main.state = "play"
	g.configure(SessionStore.defaults())
	g.cheats.god = true
	g.barks.enabled = false
	g.weapon_view = 2
	return g


func _wreck(kind: String) -> void:
	var g := _game(kind)
	var e := BossFight.of_kind(g, kind)
	var f: ArenaWreckFeature = g.features["arena_wreck"]
	var shown := 0
	for i in f.steps.size():
		if f.foes[i] != e:
			continue
		var step: Dictionary = f.steps[i]
		var what := str(step["do"])
		if what == "blowout":
			continue
		# Where to look: the first spot (or the boss, for a wave or a scatter).
		var look := Vector2(e.x, e.y)
		var dir := 0.0
		var length := 2.0
		if step.has("spots"):
			var spot: Array = step["spots"][0]
			look = Vector2(spot[0], spot[1])
			if what == "topple":
				dir = spot[2]
				var board := f._find_board(str(step["image"]), look.x, look.y)
				length = board.height if board != null else 2.0
		var middle := look + Vector2(cos(dir), sin(dir)) * length * .45
		# From the boss's side of it, square to its way over where that is open.
		var toward := atan2(e.y - middle.y, e.x - middle.x)
		var side := dir + PI * .5
		if cos(side - toward) < 0.0:
			side += PI
		var gap := clampf(length * 1.3, 3.5, 9.0)
		var at := _spot(g, middle.x, middle.y, gap, toward + angle_difference(toward, side) * .5)
		var floor_z: float = g.world.elevation(middle.x, middle.y)
		_stand(g, at, middle.x, middle.y, floor_z + minf(length * .4, 1.6))
		_ticks(g, 2, e)
		await _snap("%s_%d_%s_before" % [kind, i, what])
		var at_hp: float = step["at"]
		if what == "scatter":
			var names: Array = step["images"]
			for board: LevelData.Billboard in g.world.billboards:
				if names.has(board.image) and not board.hidden:
					e.x = board.x - 2.0
					e.y = board.y
					break
			middle = Vector2(e.x, e.y)
			at = _spot(g, middle.x, middle.y, 7.0, 0.0)
			_stand(g, at, middle.x, middle.y, floor_z + .8)
		e.hp = e.max_hp * (at_hp - .01)
		BossKit.phase_check(e, g)
		var warn: float = step.get("warn", 1.2)
		_ticks(g, int(warn * 60.0 * .6), e)
		await _snap("%s_%d_%s_warn" % [kind, i, what])
		_ticks(g, int(warn * 60.0 * .4) + 26, e)
		await _snap("%s_%d_%s_going" % [kind, i, what])
		_ticks(g, 90, e)
		await _snap("%s_%d_%s_after" % [kind, i, what])
		shown += 1


func _gear(kind: String) -> void:
	var g := _game(kind)
	var e := BossFight.of_kind(g, kind)
	var f: BossGearFeature = g.features["boss_gear"]
	var table: Dictionary = BossGearFeature.GEAR.get(kind, {})
	var at := _spot(g, e.x, e.y, 3.2 + e.radius, e.angle)
	var top: float = g.world.stand(e) + e.height * e.variant * .65
	_stand(g, at, e.x, e.y, top)
	_ticks(g, 2, e)
	await _snap("%s_gear_on" % kind)
	for g_row: Dictionary in f.gear:
		if g_row["e"] == e:
			f.knock(g_row, Vector2(at.x, at.y))
	_ticks(g, 9, e)
	await _snap("%s_gear_flying" % kind)
	_ticks(g, 60 * 3, e)
	_stand(g, _spot(g, e.x, e.y, 4.5 + e.radius, e.angle + .6), e.x, e.y, top - .3)
	_ticks(g, 2, e)
	await _snap("%s_gear_off" % kind)
	# Each piece where it lies, close up, the boss behind it.
	var n := 0
	for piece: Dictionary in f.loose:
		var px: float = piece["x"]
		var py: float = piece["y"]
		var pz: float = piece["z"]
		var away := atan2(py - e.y, px - e.x)
		_stand(g, _spot(g, px, py, 2.2, away), px, py, pz)
		_ticks(g, 2, e)
		await _snap("%s_gear_lying%d" % [kind, n])
		n += 1
	if table.is_empty():
		return
