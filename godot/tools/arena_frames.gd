## Pictures of the four boss arenas of features/boss_arena.gd in a real window
## (the graphics-card view players see): the sheriff's rodeo, Jerry's football
## field, Rudy's big top and the foreman's saw floor. For each: walking in
## (from the rematch's door, BossRematch.entrance), the boss's reveal (its
## entrance), the fight with the arena's hazards going (phase two) and its
## phase three (the arena changed, its new attack winding up and landing).
## Each picture is <kind>_<moment>.png in out=<dir>.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/arena_frames.gd -- out=<dir> [kinds=boss,rudy]
##
## Point APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

const KINDS := ["boss", "jerry", "rudy", "foreman"]

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
	BossKit.tool_intros = true
	for kind: String in kinds:
		await _arena(kind)
	print("arena frames written to ", out)
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
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))


func _ticks(g: Game, n: int, fire := false) -> void:
	var held := Game.Controls.new()
	held.fire = fire
	for i in n:
		g.tick(1.0 / 60.0, held)


## Stand at (x, y) looking at (tx, ty) at height tz.
func _stand(g: Game, at: Vector2, tx: float, ty: float, tz: float) -> void:
	var p := g.player
	p.x = at.x
	p.y = at.y
	p.angle = atan2(ty - at.y, tx - at.x)
	p.eye = .95 + g.world.elevation(at.x, at.y)
	var d := Vector2(tx - at.x, ty - at.y).length()
	p.pitch = clampf((tz - p.eye) / maxf(d, .1) * Renderer.base_focal, -50.0, 50.0)
	p.vx = 0.0
	p.vy = 0.0


func _arena(kind: String) -> void:
	var g: Game = BossRematch.build(Callable(main, "make_game"), kind)
	main.game = g
	main.state = "play"
	g.configure(SessionStore.defaults())
	g.cheats.god = true
	g.barks.enabled = false
	var e := BossFight.of_kind(g, kind)
	if e == null:
		return
	var p := g.player
	var door := Vector2(p.x, p.y)
	var top: float = g.world.elevation(e.x, e.y) + e.height * .7
	# Walking in: from the door, the boss across the arena, not yet awake.
	e.alerted = false
	e.cooldown = 99.0
	# From the arena's approach (its notes), else a step back from the door.
	var back := door - Vector2(e.x - door.x, e.y - door.y).normalized() * 1.5
	var approach = g.features["boss_arena"].spec(kind).get("approach")
	if approach is Array:
		back = Vector2(float(approach[0]), float(approach[1]))
	elif g.world.blocked(back.x, back.y, .3):
		back = door
	_stand(g, back, e.x, e.y, top)
	_ticks(g, 2)
	await _snap(kind + "_walk_in")
	# The reveal: its entrance, the view coming round to it.
	_stand(g, door, e.x, e.y, top)
	g.player.angle += .5
	g.lessons = true
	e.alerted = true
	e.target = [door.x, door.y]
	_ticks(g, 30)
	await _snap(kind + "_reveal")
	_ticks(g, 120)
	g.lessons = false
	g.boss_hold = 0.0
	# The fight: fightin' mad, the arena's hazards set going.
	e.hp = e.max_hp * .45
	BossKit.phase_check(e, g)
	e.cooldown = 99.0
	_hazards(g, e, kind)
	_stand(g, door, e.x, e.y, top - .4)
	_ticks(g, 24)
	await _snap(kind + "_fight")
	_ticks(g, 30)
	await _snap(kind + "_fight_b")
	# Plum desperate: the arena changes and its new attack winds up.
	e.hp = e.max_hp * .15
	BossKit.phase_check(e, g)
	e.stun = 0.0
	e.recovery = 0.0
	e.windup = 0.0
	e.cooldown = 99.0
	_ticks(g, 50)
	_stand(g, door, e.x, e.y, top - .5)
	_third(g, e, kind)
	_ticks(g, 20)
	await _snap(kind + "_phase3")
	_ticks(g, 30)
	await _snap(kind + "_phase3_b")
	_ticks(g, 40)
	await _snap(kind + "_phase3_c")


## Set the arena's hazards going near the boss: the nearest explosive breaks
## (a chain and fire), the carriage's bell, a horn stack's lane, the tyres.
func _hazards(g: Game, e: Enemy, kind: String) -> void:
	var f = g.features["boss_arena"]
	var pieces = g.features["breakables"]
	var best := -1
	var near := 9.0
	for i in pieces.pieces.size():
		var piece = pieces.pieces[i]
		if piece.broken or String(piece.spec.get("blast", "")) == "":
			continue
		var d := Vector2(piece.x - e.x, piece.y - e.y).length()
		if d < near:
			near = d
			best = i
	if best >= 0:
		pieces.strike(best, 999.0, 1.0, 0.0)
	if kind == "foreman":
		f.ring_carriage()
		f.carriage_run = g.clock + .5
	elif kind == "jerry":
		var stacks: Array = f.spec("jerry").get("tires", [])
		if not stacks.is_empty():
			f.knock_tyres(float(stacks[0][0]) - .5, float(stacks[0][1]), 2.0)
	elif kind == "rudy":
		e.set_meta("stack_at", g.clock)


## Start its phase-three attack now.
func _third(g: Game, e: Enemy, kind: String) -> void:
	var moves := BossKit.moves(kind)
	match kind:
		"boss":
			e.set_meta("strike_at", g.clock)
		"jerry":
			e.set_meta("blitz_at", g.clock)
		"rudy":
			e.set_meta("finale_at", g.clock)
		"foreman":
			e.set_meta("cut_at", g.clock)
	moves.tick(e, 1.0 / 60.0, g)
