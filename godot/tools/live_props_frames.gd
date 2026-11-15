## Pictures of the things a hand picks up and throws, the fire that spreads
## and the moonshine stills, in a real window (the graphics-card view players
## see): a rocking chair, a propane tank and jugs held up before the eye, the
## chair thrown and tumbling and at rest where it stopped; a billy with a
## propane tank over his head; hickston's
## hay set alight, spreading, and the char it leaves; a still shot and
## spraying burning shine, and going up. Each is <name>.png in out=<dir>.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/live_props_frames.gd -- out=<dir>
##
## Point APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

const Carry := preload("res://src/features/carry.gd")
const Fire := preload("res://src/features/fire.gd")
const Breakables := preload("res://src/features/breakables.gd")

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
	await _chair()
	await _held("town_propane_tank", "carry_5_held_tank")
	await _held("town_jug_stack", "carry_6_held_jugs", "quarry")
	await _brute()
	await _hay()
	await _still()
	print("live props frames written to ", out)
	main.queue_free()
	await process_frame
	quit()


func _snap(name: String) -> void:
	if main.game != null:
		main.game.message_until = 0.0
		main.game.barks.until = 0.0
	# Twice: the first sets the view the sprites are culled by.
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


func _stand(g: Game, x: float, y: float, tx: float, ty: float, tz: float, floor_z := NAN) -> void:
	var p := g.player
	p.x = x
	p.y = y
	p.angle = atan2(ty - y, tx - x)
	p.floor_z = g.world.elevation(x, y) if is_nan(floor_z) else floor_z
	p.air = 0.0
	p.vertical_speed = 0.0
	p.eye = .95 + p.floor_z
	var d := Vector2(tx - x, ty - y).length()
	p.pitch = clampf((tz - p.eye) / maxf(d, .1) * View.base_focal, -50.0, 50.0)
	p.vx = 0.0
	p.vy = 0.0


func _ticks(g: Game, n: int, fire := false, alt := false) -> void:
	var held := Game.Controls.new()
	for i in n:
		held.fire = fire and i == 0
		held.alt_fire = alt and i == 0
		g.tick(1.0 / 60.0, held)


func _thing(carry: Carry, image: String) -> int:
	for i in carry.things.size():
		var t: Carry.Thing = carry.things[i]
		if t.image == image and carry.takeable(t):
			return i
	return -1


## A spot `d` off (x, y), on its floor, that sees it.
func _spot(g: Game, x: float, y: float, d: float, first := 0) -> Vector2:
	for reach in [d, d * .8, d * .6, d * .4]:
		for k in 16:
			var a := (k + first) * TAU / 16.0
			var at := Vector2(x + cos(a) * reach, y + sin(a) * reach)
			if g.world.blocked(at.x, at.y, .3):
				continue
			if absf(g.world.elevation(at.x, at.y) - g.world.elevation(x, y)) > .2:
				continue
			if g.world.roof_over(at.x, at.y, g.world.elevation(at.x, at.y) + .5) > 0.0:
				if g.world.roof_over(x, y, g.world.elevation(x, y) + .5) == 0.0:
					continue
			var z := g.world.elevation(at.x, at.y)
			if g.world.visible(at.x, at.y, x, y, z + .9, z + .4):
				return at
	return Vector2(x + d, y)


func _chair() -> void:
	var g := _level("hickston")
	var carry: Carry = g.features["carry"]
	var i := _thing(carry, "town_rocker")
	var t: Carry.Thing = carry.things[i]
	var at := carry.place_of(t)
	var near := _spot(g, at.x, at.y, .9)
	_stand(g, near.x, near.y, at.x, at.y, at.z + .4)
	_ticks(g, 2)
	await _snap("carry_0_aimed")
	carry.use()
	_ticks(g, 30)
	g.player.pitch = 0.0
	await _snap("carry_1_held")
	_ticks(g, 1, true)
	_ticks(g, 9)
	# Seen from the side as it flies.
	var p := g.player
	var side := Vector2(t.x, t.y) + Vector2(-sin(p.angle), cos(p.angle)) * 2.2
	var keep := Vector2(p.x, p.y)
	var keep_angle := p.angle
	_stand(g, side.x, side.y, t.x, t.y, t.z)
	main.render()
	await _snap("carry_2_thrown")
	p.x = keep.x
	p.y = keep.y
	p.angle = keep_angle
	for _k in 200:
		_ticks(g, 1)
		if t.state == Carry.STAND:
			break
	var view := _spot(g, t.x, t.y, 1.8)
	_stand(g, view.x, view.y, t.x, t.y, t.foot + .4)
	_ticks(g, 2)
	await _snap("carry_3_landed")


## A thing taken up and held, looking level.
func _held(image: String, name: String, level_id := "hickston") -> void:
	var g := _level(level_id)
	var carry: Carry = g.features["carry"]
	var i := _thing(carry, image)
	var t: Carry.Thing = carry.things[i]
	var at := carry.place_of(t)
	var near := _spot(g, at.x, at.y, .9)
	_stand(g, near.x, near.y, at.x, at.y, at.z + .4)
	_ticks(g, 2)
	carry.use()
	_ticks(g, 30)
	g.player.pitch = 0.0
	g.player.angle += 2.4
	await _snap(name)


func _brute() -> void:
	var g := _level("hickston")
	var carry: Carry = g.features["carry"]
	var e: Enemy = null
	for enemy: Enemy in g.enemies:
		if enemy.brain == "billy":
			e = enemy
			break
	# The billy a few steps ahead of where the chapter starts, holding up a
	# propane tank (the held picture is stood over his head wherever he is).
	var i := _thing(carry, "town_propane_tank")
	var at := carry.place_of(carry.things[i])
	var p := g.player
	var me := Vector2(p.x, p.y)
	var by := me + Vector2.from_angle(p.angle) * 4.4
	for k in 16:
		var try := me + Vector2.from_angle(p.angle + (k / 2) * .3 * (1 if k % 2 else -1)) * 4.4
		if not g.world.blocked(try.x, try.y, .4) and g.world.visible(me.x, me.y, try.x, try.y):
			by = try
			break
	var t: Carry.Thing = carry.things[i]
	e.x = by.x
	e.y = by.y
	e.floor_z = g.world.elevation(by.x, by.y)
	e.dormant = false
	_stand(g, me.x, me.y, e.x, e.y, g.world.elevation(e.x, e.y) + 1.8)
	e.angle = atan2(me.y - e.y, me.x - e.x)
	t.state = Carry.HELD
	t.by_enemy = true
	t.holder = e.uid
	t.timer = 9.0
	t.moved = true
	carry.active.append(i)
	carry._changed()
	g.armory.holstered = true
	g.armory.lower = 1.0
	_ticks(g, 3)
	print("brute at ", Vector2(e.x, e.y), " tank ", at, " me ", me)
	await _snap("carry_4_brute")


func _hay() -> void:
	var g := _level("hickston")
	var fire: Fire = g.features["fire"]
	var w := g.world
	# The hay with the most that burns round it.
	var best := -1
	var most := -1
	for c in fire._fuel.size():
		if fire._catch[c] < .9 or fire._fuel[c] <= 0.0:
			continue
		var n := 0
		for d: Vector2i in Fire.NEAR:
			var q := c + d.y * w.width + d.x
			n += 1 if q >= 0 and q < fire._fuel.size() and fire._fuel[q] > 0.0 else 0
		if n > most:
			most = n
			best = c
	var x := (best % w.width) + .5
	var y := float(best / w.width) + .5
	var z := fire._z[best]
	# A spot on the same floor (the loft), a few cells off, that sees it.
	var near := Vector2(x + 2.0, y)
	var found := false
	for reach: float in [3.4, 2.8, 2.2, 1.6]:
		for k in 16:
			var a := k * TAU / 16.0
			var at := Vector2(x + cos(a) * reach, y + sin(a) * reach)
			if at.x < 1.0 or at.y < 1.0 or w.blocked(at.x, at.y, .3, z + .5):
				continue
			if absf(w.floor_under(at.x, at.y, z + .3) - z) > .1:
				continue
			if w.visible(at.x, at.y, x, y, z + .9, z + .3):
				near = at
				found = true
				break
		if found:
			break
	_stand(g, near.x, near.y, x, y, z + .2, w.floor_under(near.x, near.y, z + .3))
	fire.fresh()
	var lit := fire.ignite(x, y, z)
	_ticks(g, 60)
	print("hay fire at ", x, ",", y, ",", z, " lit ", lit, " seen from ", near, " ", found)
	await _snap("fire_0_lit")
	_ticks(g, 360)
	await _snap("fire_1_spread")
	for _k in 120:
		_ticks(g, 30)
		if fire.burning.is_empty():
			break
	_ticks(g, 2)
	await _snap("fire_2_charred")


func _still() -> void:
	var g := _level("hickston")
	var bk: Breakables = g.features["breakables"]
	var at := -1
	for i in bk.pieces.size():
		var piece: Breakables.Piece = bk.pieces[i]
		if piece.image == "town_still":
			at = i
			break
	var piece: Breakables.Piece = bk.pieces[at]
	var near := _spot(g, piece.x, piece.y, 3.4, 5)
	_stand(g, near.x, near.y, piece.x, piece.y, g.world.elevation(piece.x, piece.y) + .6)
	var way := Vector2(piece.x - near.x, piece.y - near.y).normalized().rotated(.9)
	bk.strike(at, 5.0, way.x, way.y)
	_ticks(g, 40)
	await _snap("still_0_spray")
	bk.strike(at, 500.0, way.x, way.y)
	_ticks(g, 12)
	await _snap("still_1_blast")
	_ticks(g, 120)
	await _snap("still_2_after")
