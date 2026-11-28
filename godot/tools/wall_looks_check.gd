## How walls look taking a beating (features/wall_looks.gd; tools/check_all.gd
## runs it, quick too):
##
##   godot --headless --path godot --script res://tools/wall_looks_check.gd
##
## Plank walls: a round knocks out the plank it struck round the height it
## struck (a light pellet only wears it), the next round there breaks it
## further, each bit knocked out flies as a piece of that plank out the far
## side along the shot; two cells struck in different places come apart
## differently; buckshot tears more planks than one round, a blast tears out
## the planks facing it whole; a hole on a plank knocked out goes with it; the
## view gets the cells nearest the eye with their planks; a client (a
## snapshot put on) makes the knocks up from the hp; the fence's own play
## (hp, stage, walls, flow) is the same with or without the looks; broken
## through, what is left bursts out along the shot.
## Windows: the first round lays its crack web where it struck, within the
## glass; shot out, its pane is cut fresh round where it was struck (small
## pieces near the hole, two windows struck in different places throw
## different shards) and the shards break again where they land; a blast
## shows its frame torn out (<material>_bst) and throws the frame's sticks.
## Holes: each material's hole gets its own picture and size.
extends SceneTree

const DT := 1.0 / 60.0
const WallBreaksScript := preload("res://src/features/wall_breaks.gd")
const WallLooksScript := preload("res://src/features/wall_looks.gd")

var failures: Array = []
var passes := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var started := Time.get_ticks_msec()
	print("\nPLANKS (fair)")
	_planks(main)
	print("\nWINDOWS (hickston)")
	_windows(main)
	print("\nCUTTING A PANE")
	_cutting()
	print("\nHOLES")
	_holes(main)
	print("")
	print(
		(
			"%d checks in %.1f s"
			% [passes + failures.size(), (Time.get_ticks_msec() - started) / 1000.0]
		)
	)
	print(
		(
			"WALL LOOKS CHECK OK"
			if failures.is_empty()
			else "%d WALL LOOKS CHECK(S) FAILED" % failures.size()
		)
	)
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	if ok:
		passes += 1
		print("  ok   ", text)
	else:
		print("  FAIL ", text)
		failures.append(text)


func _game(main: Control, id: String) -> Game:
	var g: Game = main.make_game(id)
	g.configure({})
	g.cheats.god = true
	for e: Enemy in g.enemies:
		e.dormant = true
	return g


func _ticks(g: Game, n: int) -> void:
	var held := Game.Controls.new()
	for i in n:
		g.tick(DT, held)


## Opening fence cells along x (not a shed's wall), in order.
func _fences(g: Game) -> Array:
	var wb = g.features["wall_breaks"]
	var out: Array = []
	var keys: Array = wb.fences.keys()
	keys.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool: return a.y * 1000 + a.x < b.y * 1000 + b.x
	)
	for key: Vector2i in keys:
		var f = wb.fences[key]
		if f.opens and f.inside < 0 and f.along_x:
			out.append(f)
	return out


## A round into fence cell f at `along` (0..1 across it) and `up` (a share of
## its height), from the south side going north, `amount` of its hp.
func _shoot(g: Game, f, along: float, up: float, amount: float) -> void:
	var wb = g.features["wall_breaks"]
	var ground := g.world.ground[f.cell.y * g.world.width + f.cell.x]
	var at := Vector3(f.cell.x + along, f.cell.y + .99, ground + f.top * up)
	wb.strike(at.x, at.y, at.z, 0.0, -1.0, amount)


static func _bands(pl) -> Array:
	var out: Array = []
	for j in WallLooksScript.SLOTS:
		out.append([pl.lo[j], pl.hi[j]] if pl.gone(j) else [])
	return out


static func _knocked(pl) -> int:
	var n := 0
	for j in WallLooksScript.SLOTS:
		if pl.gone(j):
			n += 1
	return n


func _planks(main: Control) -> void:
	var g := _game(main, "fair")
	var looks = g.features.get("wall_looks")
	var wreck = g.features["wreckage"]
	var cells := _fences(g)
	_check(
		looks != null and cells.size() >= 6, "fair: wall_looks and %d fence cells" % cells.size()
	)
	if looks == null or cells.size() < 6:
		return
	var f = cells[0]
	var most: float = f.most
	var before: int = wreck.wrecks.size()
	_shoot(g, f, .3, .7, most * .3)
	var pl = looks.planks.get(f.cell)
	_check(pl != null and pl.gone(2), "a round knocks out the plank it struck (slot 2)")
	if pl == null:
		return
	var h := .7 * WallLooksScript.TALL
	_check(
		pl.lo[2] < h and pl.hi[2] > h and pl.hi[2] - pl.lo[2] <= 9,
		"round the height it struck (%d to %d sixteenths, struck at %.1f)" % [pl.lo[2], pl.hi[2], h]
	)
	_check(_knocked(pl) <= 2, "and little else (%d planks)" % _knocked(pl))
	var thrown: int = wreck.wrecks.size() - before
	var piece = wreck.wrecks.back() if thrown > 0 else null
	_check(
		thrown >= 1 and piece.key.begins_with("t:") and piece.body.v.y < 0.0,
		(
			"the bit flies as a piece of plank along the shot (%d, going %s)"
			% [thrown, piece.body.v if piece else Vector3.ZERO]
		)
	)
	var long_was: int = pl.hi[2] - pl.lo[2]
	_shoot(g, f, .31, .62, most * .25)
	_check(
		pl.hi[2] - pl.lo[2] > long_was,
		"a second round there breaks it further (%d to %d)" % [pl.lo[2], pl.hi[2]]
	)
	# A light pellet only wears a plank.
	var g2 := _game(main, "fair")
	var f2 = _fences(g2)[0]
	_shoot(g2, f2, .8, .5, most * .08)
	var pl2 = g2.features["wall_looks"].planks.get(f2.cell)
	_check(pl2 != null and _knocked(pl2) == 0, "a light pellet only wears the plank")
	_shoot(g2, f2, .81, .52, most * .08)
	_shoot(g2, f2, .79, .48, most * .08)
	_check(_knocked(pl2) >= 1, "a few more there knock it out")
	# Two cells struck in different places come apart differently.
	var a = cells[1]
	var b = cells[2]
	_shoot(g, a, .15, .3, most * .3)
	_shoot(g, b, .7, .8, most * .3)
	var pa = looks.planks.get(a.cell)
	var pb = looks.planks.get(b.cell)
	_check(
		pa != null and pb != null and str(_bands(pa)) != str(_bands(pb)),
		"two struck in different places differ (%s / %s)" % [_bands(pa), _bands(pb)]
	)
	# Buckshot tears more planks than a round; a blast tears the planks
	# facing it out whole.
	var c = cells[3]
	var dice := RandomNumberGenerator.new()
	dice.seed = 5
	for k in 9:
		_shoot(g, c, .5 + dice.randf_range(-.3, .3), .55 + dice.randf_range(-.2, .2), most * .09)
	var pc = looks.planks.get(c.cell)
	_check(
		pc != null and _knocked(pc) >= 2,
		"buckshot tears several planks (%d)" % (_knocked(pc) if pc else 0)
	)
	var d = cells[4]
	var wb = g.features["wall_breaks"]
	var ground := g.world.ground[d.cell.y * g.world.width + d.cell.x]
	wb._knock(
		d, most * .5, 0.0, -1.0, Vector3(d.cell.x + .5, d.cell.y + 1.6, ground + .3), wb.BLAST
	)
	var pd = looks.planks.get(d.cell)
	var whole := 0
	if pd != null:
		for j in WallLooksScript.SLOTS:
			if pd.gone(j) and pd.hi[j] - pd.lo[j] >= 10:
				whole += 1
	_check(
		pd != null and _knocked(pd) >= 4 and whole >= 1,
		(
			"a blast tears out the planks facing it (%d, %d nearly whole)"
			% [_knocked(pd) if pd else 0, whole]
		)
	)
	# A hole on a plank knocked out goes with it.
	var mark := View.WallMark.new()
	mark.x = f.cell.x + .3
	mark.y = f.cell.y + 1.0
	mark.z = pl.z0 + (pl.lo[2] + pl.hi[2]) * .5 / WallLooksScript.TALL * pl.span
	mark.image = "fx_hole_wood_0"
	g.wall_marks.append(mark)
	looks._dirty[f.cell] = true
	_ticks(g, 1)
	_check(not g.wall_marks.has(mark), "a hole on a plank knocked out goes with it")
	# The view's rows: the cells nearest the eye, their planks as words.
	var rows: Array = looks.view_rows(f.cell.x + .5, f.cell.y + 3.0)
	var first: Vector4 = rows[0][0]
	var words: Vector4 = rows[1][0]
	var want: Vector3 = pl.words()
	_check(
		Vector2i(int(first.x), int(first.y)) == f.cell and first.w > 0.0,
		"the view gets the nearest cell first (%s)" % first
	)
	_check(
		Vector3(words.x, words.y, words.z) == want,
		"with its planks (%s)" % Vector3(words.x, words.y, words.z)
	)
	# The words decode as the shader reads them.
	var ok := true
	for j in WallLooksScript.SLOTS:
		var word: float = [words.x, words.y, words.z][j / 3]
		var byte := (int(word) >> ((j % 3) * 8)) & 255
		var lo := byte & 15
		var hi := (byte >> 4) + 1
		if pl.gone(j) != (hi > lo) or (pl.gone(j) and (lo != pl.lo[j] or hi != pl.hi[j])):
			ok = false
	_check(ok, "each plank reads back as the shader reads it")
	# A client makes the knocks up from the hp.
	var snap := GameSnapshot.capture(g)
	var copy := _game(main, "fair")
	GameSnapshot.apply(copy, snap)
	_ticks(copy, 1)
	var cl = copy.features["wall_looks"].planks.get(f.cell)
	_check(cl != null and cl.any(), "a client makes the knocks up from the hp")
	# The play is the same without the looks.
	var bare := _game(main, "fair")
	# Not told of any round (it still ticks, kept here, making up knocks).
	var kept = bare.features["wall_looks"]
	bare.features.erase("wall_looks")
	var full := _game(main, "fair")
	for game: Game in [bare, full]:
		var cs := _fences(game)
		for k in 4:
			_shoot(game, cs[0], .2 + k * .2, .5, most * .3)
		_shoot(game, cs[1], .5, .5, most * 2.0)
		_ticks(game, 5)
	var fb = _fences(bare)
	var ff = _fences(full)
	_check(
		(
			fb[0].hp == ff[0].hp
			and fb[0].stage == ff[0].stage
			and bare.world.wall_count == full.world.wall_count
			and bare.world.solid == full.world.solid
			and bare.flow.open == full.flow.open
		),
		"play is the same with or without the looks (hp %.1f, stage %d)" % [ff[0].hp, ff[0].stage]
	)
	_check(kept != null, "(the looks left out kept ticking)")
	# Broken through: what is left bursts out along the shot.
	var e = cells[5]
	before = wreck.wrecks.size()
	_shoot(g, e, .5, .5, most * 3.0)
	_ticks(g, 2)
	var out := 0
	var along := 0.0
	for k in range(before, wreck.wrecks.size()):
		out += 1
		along += -wreck.wrecks[k].body.v.y
	_check(
		e.stage == 2 and out >= 4 and along > 0.0,
		"gone through, its boards burst out along the shot (%d)" % out
	)
	_check(not looks.planks.has(e.cell), "and its planks are forgotten")


## A brick window of Hickston's whose glass faces open ground.
func _window(g: Game, skip: int):
	var wb = g.features["wall_breaks"]
	for face in wb.windows:
		if not String(g.world.tile_names[face.whole]).begins_with("brick"):
			continue
		var n: Vector2 = face.normal()
		var mid: Vector2 = face.middle()
		var at := mid + n * 2.0
		if g.world.blocked(at.x, at.y, .3):
			continue
		if skip > 0:
			skip -= 1
			continue
		return face
	return null


## Stand two cells out from the window and shoot its glass at `u` (along
## its face from the middle) and height z.
func _shoot_glass(g: Game, face, u: float, z: float, amount: float) -> void:
	var wb = g.features["wall_breaks"]
	var n: Vector2 = face.normal()
	var along: Vector2 = Vector2(face.edge.z - face.edge.x, face.edge.w - face.edge.y).normalized()
	var mid: Vector2 = face.middle()
	var target := mid + along * u
	var p := g.player
	p.x = target.x + n.x * 2.0
	p.y = target.y + n.y * 2.0
	var hit := target - n * .02
	wb.strike(hit.x, hit.y, z, -n.x, -n.y, amount)


func _windows(main: Control) -> void:
	var g := _game(main, "county_hickston")
	if g.features["wall_breaks"].windows.is_empty():
		g = _game(main, "hickston")
	var looks = g.features.get("wall_looks")
	var wreck = g.features["wreckage"]
	var face = _window(g, 0)
	_check(face != null, "a brick window facing open ground")
	if face == null:
		return
	var u := -.12
	var z: float = face.low + (face.high - face.low) * .3
	_shoot_glass(g, face, u, z, 20.0)
	_ticks(g, 1)
	var web = looks.webs.get(face)
	var along: Vector2 = Vector2(face.edge.z - face.edge.x, face.edge.w - face.edge.y).normalized()
	var mid: Vector2 = face.middle()
	_check(
		face.broken and face.cracked and web != null,
		"the first round breaks it (play as ever) but holds its glass cracked: its web"
	)
	if web != null:
		var at := mid + along * u
		_check(
			Vector2(web.x, web.y).distance_to(at) < .03 and absf(web.z - z) < .03,
			"where it struck (%.2f off)" % Vector2(web.x, web.y).distance_to(at)
		)
		_check(looks.wall_marks().has(web), "and shows it")
	var windows: WallBreaksScript = g.features["wall_breaks"]
	var cracked := windows.save()
	var before: int = wreck.wrecks.size()
	g.net_facts["wall_breaks"] = var_to_bytes(cracked)
	_shoot_glass(g, face, .1, face.low + (face.high - face.low) * .7, 20.0)
	_ticks(g, 1)
	var shards: Array = []
	for k in range(before, wreck.wrecks.size()):
		shards.append(wreck.wrecks[k])
	_check(
		face.broken and not face.cracked and shards.size() >= 6,
		"the next shoots the glass out: %d shards" % shards.size()
	)
	_check(not looks.wall_marks().has(web), "its web goes with the glass")
	_check(
		not g.net_facts.has("wall_breaks"), "window changes invalidate the incoming snapshot memo"
	)
	var shattered := windows.save()
	windows.restore(cracked)
	_check(face.cracked, "a snapshot can put the cracked pane back in its frame")
	windows.restore(shattered)
	_check(face.broken and not face.cracked, "a snapshot clears glass shot out of a cracked pane")
	windows.restore({})
	_check(not face.broken and not face.cracked, "an earlier snapshot restores the whole pane")
	windows.restore(shattered)
	var tris := ""
	for s in shards:
		tris += str(s.tri)
	# Another window struck elsewhere throws different shards.
	var g2 := _game(main, g.world.id)
	var face2 = _window(g2, 0)
	var w2 = g2.features["wreckage"]
	var b2: int = w2.wrecks.size()
	_shoot_glass(g2, face2, -.2, face2.low + .05, 80.0)
	_ticks(g2, 1)
	var tris2 := ""
	for k in range(b2, w2.wrecks.size()):
		tris2 += str(w2.wrecks[k].tri)
	_check(
		face2.broken and tris2 != "" and tris2 != tris,
		"struck elsewhere, the pane comes apart differently"
	)
	# The shards break again where they land.
	var waited := 0
	while waited < 600:
		_ticks(g, 10)
		waited += 10
		var left := 0
		for s in wreck.wrecks:
			if s.tri.size() > 0 and s.breaks == 0:
				left += 1
		if left == 0:
			break
	var fx = g.features["weapon_fx"]
	var glints := 0
	for bit in fx.bits:
		if bit.kind == "glint":
			glints += 1
	_check(waited < 600, "every shard breaks again landing (%.1f s)" % (waited * DT))
	_check(glints > 0, "into glints lying about (%d)" % glints)
	# A blast tears the frame out too.
	g = _game(main, g.world.id)
	wreck = g.features["wreckage"]
	var face3 = _window(g, 0)
	if face3 != null:
		var n3: Vector2 = face3.normal()
		var m3: Vector2 = face3.middle()
		var b3: int = wreck.wrecks.size()
		g.features["wall_breaks"].blast(m3.x + n3.x * .8, m3.y + n3.y * .8, 1.0, 2.0, 100.0, false)
		_ticks(g, 1)
		var tile := ""
		for i in g.world.walls_on(face3.edge.x, face3.edge.y, face3.edge.z, face3.edge.w):
			var name := String(
				g.world.tile_names[int(g.world.walls[i * LevelData.WALL_STRIDE + 4])]
			)
			if name.ends_with("_bst") or tile == "":
				tile = name
		var sticks := 0
		for k in range(b3, wreck.wrecks.size()):
			if wreck.wrecks[k].key == WallLooksScript.STICK:
				sticks += 1
		_check(
			face3.blasted and tile.ends_with("_bst"),
			(
				"a blast shows its frame torn out (%s; broken %s blasted %s blast %d)"
				% [tile, face3.broken, face3.blasted, face3.blast]
			)
		)
		_check(sticks >= 2, "and throws the frame's sticks (%d)" % sticks)
		# Its material is still the wall's (play: what a round strikes there).
		_check(
			Materials.of_name(tile) == Materials.of_name(tile.trim_suffix("_bst") + "_brk"),
			"a torn-out window is its wall's material"
		)


func _cutting() -> void:
	var rect := Rect2(-.3, 1.0, .6, .68)
	var dice := RandomNumberGenerator.new()
	dice.seed = 7
	var near_hit := WallLooksScript.cut_pane(rect, Vector2(-.15, 1.2), false, dice)
	var inner: Array = near_hit[0]
	var rest: Array = near_hit[1]
	var area := 0.0
	var inner_area := 0.0
	for t: PackedVector2Array in rest:
		area += WallLooksScript._area(t)
	for t: PackedVector2Array in inner:
		inner_area += WallLooksScript._area(t)
	_check(
		absf(area + inner_area - rect.get_area()) < .002,
		"the pieces cover the pane (%.4f of %.4f)" % [area + inner_area, rect.get_area()]
	)
	_check(
		inner_area / inner.size() < area / rest.size() * .25,
		"the pieces round the hole are the small ones"
	)
	var other := WallLooksScript.cut_pane(rect, Vector2(.2, 1.55), false, dice)
	_check(str(other[1]) != str(rest), "a pane struck elsewhere is cut differently")


func _holes(main: Control) -> void:
	var g := _game(main, "hickston")
	var impacts = g.features["impacts"]
	var sizes := {}
	for kind: String in ["wood", "brick", "tin", "stone"]:
		var mark := View.WallMark.new()
		mark.image = "fx_hole_" + kind
		mark.radius = .06
		impacts._look_of(mark)
		sizes[kind] = mark.radius
		_check(
			mark.image.begins_with("fx_hole_%s_" % kind) and g.art.has_art(mark.image),
			"%s: its own picture (%s), %.3f across" % [kind, mark.image, mark.radius * 2.0]
		)
	_check(sizes["brick"] > .08 and sizes["wood"] > .07, "holes read bigger than the old .06")
