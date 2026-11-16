## Finding the guns (feature pass 7: src/gun_finder.gd, features/new_iron.gd,
## the plans' new_iron(); tools/check_all.gd runs it):
##
##   godot --headless --path godot --script res://tools/gun_find_check.gd [-- audit] [map=<dir>]
##
## ROUTE, in each chapter (tools/gun_routes.gd): every gun new to a player
## arriving in campaign order has a copy no secret stands in front of within
## NEAR steps of the way through; one more than SIGNED steps off it and out of
## sight of it has a gun sign by the place the way is left for it; a gun found
## only behind a secret has its rounds lying near the way; GunFinder's table of
## each chapter's guns is the levels'. CUES, for every gun lying out in every
## chapter while the player ain't got it: it shines and is lit, USE names it
## looked at from further off, seen it goes on the automap (NEW IRON in the
## key), Mundell smells it once from close by; once had, none of it. Secrets:
## a gun behind a secret not yet found neither shines, is lit nor goes on the
## map. TALLY: the chapter tally's GUNS row counts the chapter's guns had. HUB:
## the trophy shack's shadow board hangs each gun had and the card counts them.
## OFF: County Run, the versus maps and the range have none of it, and the
## County Run maps none of the gun signs.
##
## `audit` prints the table of every gun pickup (off the way, in sight, behind a
## secret, new) and map=<dir> writes guns_<chapter>.png (the way yellow, new
## guns red, others blue, secret doors purple).
extends SceneTree

const Routes := preload("res://tools/gun_routes.gd")
const NewIron := preload("res://src/features/new_iron.gd")
const STEP := 1.0 / 60.0
## A new gun's copy lies within this many steps of the way through; one more
## than SIGNED off it and out of its sight has a sign within SIGN_NEAR of
## where the way is left for it.
const NEAR := 24
const SIGNED := 8
const SIGN_NEAR := 6.0
const COUNTY := ["county_hickston", "county_quarry", "county_bayou"]

var failures: Array = []
var passes := 0


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if ok:
		passes += 1
	else:
		failures.append(text)


func _run() -> void:
	var audit := false
	var out_dir := ""
	for a: String in OS.get_cmdline_user_args():
		if a == "audit":
			audit = true
		elif a.begins_with("map="):
			out_dir = a.substr(4)
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var started := Time.get_ticks_msec()
	var art: Assets = main.art
	var by := Routes.guns_by_chapter(art)
	for id: String in Routes.CHAPTERS:
		print("\nROUTE %s" % id.to_upper())
		var level := LevelData.load_level(id, art)
		var route := Routes.route_cells(level)
		var fresh := Routes.new_guns(id, by)
		var rows := Routes.audit(level, route, fresh)
		if audit:
			_print_rows(fresh, rows)
		if out_dir != "":
			_picture(level, route, rows, out_dir)
		_route(level, rows, fresh)
		print("CUES %s" % id.to_upper())
		_cues(main, id, rows)
	print("\nTALLY")
	_tally(main)
	print("\nHUB")
	_hub(main)
	print("\nOFF")
	_off(main)
	print("")
	print(
		(
			"%d checks in %.1f s"
			% [passes + failures.size(), (Time.get_ticks_msec() - started) / 1000.0]
		)
	)
	print("GUN FIND OK" if failures.is_empty() else "%d GUN FIND CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


# ------------------------------------------------------------------ the way


func _route(level: LevelData, rows: Array, fresh: Array) -> void:
	var laid: Array = []
	for row: Dictionary in rows:
		if not laid.has(row.gun):
			laid.append(row.gun)
	var table: Array = GunFinder.CHAPTER_GUNS.get(level.id, [])
	_check(laid == table, "GunFinder's table holds its guns %s" % [laid])
	for board: LevelData.Billboard in level.billboards:
		if board.image.begins_with("gun_sign_"):
			# Hung flat on a wall or a counter that is there (nothing built for it).
			var face := Vector2(-sin(board.plane), cos(board.plane))
			var behind := Vector2(board.x, board.y) - face * .12
			var ahead := Vector2(board.x, board.y) + face * .3
			_check(
				(
					not is_nan(board.plane)
					and (_solid(level, behind) or level.blocked(behind.x, behind.y))
					and not _solid(level, ahead)
				),
				(
					"%s at (%.2f, %.2f) hangs on something, facing out"
					% [board.image, board.x, board.y]
				)
			)
	for gun: String in fresh:
		var best: Dictionary = {}
		var hidden_only := true
		for row: Dictionary in rows:
			if not Routes.gun_names(str(row.gun)).has(gun):
				continue
			if row.secret:
				continue
			hidden_only = false
			if best.is_empty() or int(row.off) < int(best.off):
				best = row
		if hidden_only:
			_check(
				_teased(level, gun, rows),
				"%s only behind a secret: its rounds lie near the way" % gun
			)
			continue
		_check(
			int(best.off) <= NEAR,
			"%s lies %d steps off the way (%.1f, %.1f)" % [gun, best.off, best.x, best.y]
		)
		if int(best.off) > SIGNED and not best.seen:
			var branch: Vector2i = best.branch
			_check(
				_signed(level, branch),
				(
					"%s (%d off): a gun sign by where the way is left for it (%d, %d)"
					% [gun, best.off, branch.x, branch.y]
				)
			)


static func _solid(level: LevelData, at: Vector2) -> bool:
	return level.solid[int(at.y) * level.width + int(at.x)] >= 0


## Whether a gun sign hangs within SIGN_NEAR of `branch`, in sight of it.
func _signed(level: LevelData, branch: Vector2i) -> bool:
	var at := Vector2(branch.x + .5, branch.y + .5)
	for board: LevelData.Billboard in level.billboards:
		if not board.image.begins_with("gun_sign_"):
			continue
		var b := Vector2(board.x, board.y)
		if b.distance_to(at) <= SIGN_NEAR and level.visible(at.x, at.y, b.x, b.y):
			return true
	return false


## Whether rounds for `gun` lie near the way (a secret's gun teased).
func _teased(level: LevelData, gun: String, rows: Array) -> bool:
	var slot := Weapons.NAMES.find(gun)
	var route := Routes.route_cells(level)
	var field := FlowField.new(level)
	field.reach = 100000
	field.doors_open = true
	field.every_door = true
	for row: Variant in level.pickups:
		var item := str(row[0])
		if not GameState.AMMO.has(item):
			continue
		var entry: Array = GameState.AMMO[item]
		if int(entry[0]) != slot:
			continue
		field.origin = Vector2i(-1, -1)
		field.next_at = 0.0
		field.update(float(row[1]), float(row[2]), 0.0)
		for cell: Vector2i in route:
			if field.distance(cell.x + .5, cell.y + .5) <= NEAR:
				return true
	return rows.is_empty()


# ------------------------------------------------------------------ the cues


func _game(main: Control, id: String) -> Game:
	var g: Game = main.make_game(id)
	g.configure({"difficulty": 1})
	g.cheats.god = true
	g.barks.enabled = false
	g.enemies.clear()
	g.enemy_ids.clear()
	return g


func _tick(g: Game, n: int) -> void:
	for t in n:
		g.tick(STEP, Game.Controls.new())


## Stands the player about `far` from (x, y) (or nearer, down to 1.5, where
## there is no room), on its floor, looking at it (or away), where it can be
## seen from; whether such a place was found.
static func _stand(g: Game, x: float, y: float, far: float, away := false, sight := true) -> bool:
	var reach := far
	while reach >= 1.5:
		if _stand_at(g, x, y, reach, away, sight):
			return true
		reach -= .75
	return false


static func _stand_at(g: Game, x: float, y: float, far: float, away: bool, sight: bool) -> bool:
	for k in 24:
		var a := k * TAU / 24.0
		var at := Vector2(x, y) + Vector2(cos(a), sin(a)) * far
		if at.x < 1 or at.y < 1 or at.x > g.world.width - 1 or at.y > g.world.height - 1:
			continue
		if g.world.blocked(at.x, at.y, .3) or g.world.deep_at(at.x, at.y):
			continue
		var floor_z := g.world.elevation(at.x, at.y)
		if absf(floor_z - g.world.elevation(x, y)) > .5:
			continue
		if (
			sight
			and not g.world.visible(at.x, at.y, x, y, floor_z + .95, g.world.elevation(x, y) + .2)
		):
			continue
		var p := g.player
		p.x = at.x
		p.y = at.y
		p.floor_z = floor_z
		p.eye = floor_z + .95
		p.air = 0.0
		p.pitch = 0.0
		p.angle = atan2(y - at.y, x - at.x) + (PI if away else 0.0)
		return true
	return false


static func _iron(g: Game) -> NewIron:
	return g.features.get("new_iron")


## The red of the map's gun mark round (x, y) on the automap (zoomed in; the
## guns' marks drawn on a canvas of their own over the map as it was just
## drawn, so the player's mark or the key over the corner hide none of it).
static func _inked(g: Game, x: float, y: float) -> int:
	g.map_zoom = 3
	g.map_view.draw(g, Canvas.new())
	var c := Canvas.new()
	_iron(g).draw_map(c, g.map_view)
	var at := g.map_view.point(x, y)
	var inked := 0
	for dy in range(-3, 4):
		for dx in range(-5, 6):
			var o := ((int(at.y) + dy) * Canvas.WIDTH + int(at.x) + dx) * 3
			if o >= 0 and o + 2 < c.pixels.size():
				var px := Color8(c.pixels[o], c.pixels[o + 1], c.pixels[o + 2])
				if px.is_equal_approx(GunFinder.MAP_INK):
					inked += 1
	return inked


static func _shines_at(g: Game, x: float, y: float) -> bool:
	var out: Array = []
	GunFinder.shines(g, out)
	for s: View.Sprite in out:
		if absf(s.x - x) < .01 and absf(s.y - y) < .01 and s.image.begins_with("fx_gun_shine_"):
			return true
	return false


static func _lit_at(g: Game, x: float, y: float) -> bool:
	for l: Array in _iron(g).lights(g.player):
		if absf(float(l[0]) - x) < .01 and absf(float(l[1]) - y) < .01:
			return true
	return false


func _cues(main: Control, id: String, rows: Array) -> void:
	var keyed := false
	for row: Dictionary in rows:
		var g := _game(main, id)
		_check(GunFinder.on(g), "%s: the guns are found here" % id)
		var x: float = row.x
		var y: float = row.y
		var name := "%s (%.1f, %.1f)" % [row.gun, x, y]
		if row.secret:
			_secret(g, name, x, y)
			continue
		_check(_shines_at(g, x, y), "%s shines" % name)
		_stand(g, x, y, 4.0)
		_check(_lit_at(g, x, y), "%s is lit" % name)
		_check(_inked(g, x, y) == 0, "%s is not on the map before it is seen" % name)
		var reach := GunFinder.tuned("prompt_reach")
		_check(_stand(g, x, y, reach - 2.0), "%s: a place to look at it from" % name)
		# Named looked at (the one looked at: a gun lying beside it may be nearer).
		var said := GunFinder.far_prompt(g)
		var i := GunFinder.looked_at(g, g.player, reach, GunFinder.tuned("prompt_facing"))
		var at_i := _at(g, i)
		_check(
			(
				at_i.distance_to(Vector2(x, y)) < 2.0
				and said == GunFinder.label(str(g.pickups[i][0])) + "  /  NEW IRON"
			),
			"%s looked at from off: '%s'" % [name, said]
		)
		_tick(g, 20)
		_check(_iron(g).seen.has(GunFinder.spot(x, y)), "%s seen" % name)
		_check(_inked(g, x, y) >= 4, "%s goes on the automap" % name)
		if not keyed:
			# The map's key gets its NEW IRON row (its little gun in the corner).
			keyed = true
			var c := Canvas.new()
			g.map_view.draw(g, c)
			var red := 0
			var top := GameAutomap.MAP_Y + GameAutomap.MAP_H - 70
			for yy in range(top, GameAutomap.MAP_Y + GameAutomap.MAP_H):
				for xx in range(GameAutomap.MAP_X + 1, GameAutomap.MAP_X + 20):
					var o := (yy * Canvas.WIDTH + xx) * 3
					if Color8(c.pixels[o], c.pixels[o + 1], c.pixels[o + 2]).is_equal_approx(
						GunFinder.MAP_INK
					):
						red += 1
			_check(red >= 8, "%s: NEW IRON in the map's key (%d)" % [id, red])
		var turned := _stand(g, x, y, reach - 2.0, true)
		i = GunFinder.looked_at(g, g.player, reach, GunFinder.tuned("prompt_facing"))
		_check(turned and _at(g, i) != Vector2(x, y), "%s looked away from: not named" % name)
		# Mundell smells it from close by, once.
		var g2 := _game(main, id)
		_stand(g2, x, y, GunFinder.tuned("smell_reach") - 1.5, false, false)
		g2.notice = ""
		g2.message_until = 0.0
		var smelled := 0
		for t in 60 * 3:
			g2.tick(STEP, Game.Controls.new())
			if NewIron.SMELLS.has(g2.notice):
				smelled += 1
				g2.notice = ""
				g2.message_until = 0.0
		# Once for it (and the guns lying with it), no more.
		var iron := _iron(g2)
		_check(
			iron.told.has(GunFinder.spot(x, y)) and smelled >= 1 and smelled == iron.said,
			"%s: Mundell smells it once (%d said)" % [name, smelled]
		)
		# Had: none of it (its own shine and light; the map and the prompt once
		# every gun is had, a gun lying beside it being another's).
		var armory := g.local_player.armory
		for gun: String in GunFinder.guns_of(str(row.gun)):
			armory.owned[Weapons.NAMES.find(gun)] = true
		_stand(g, x, y, reach - 2.0)
		_check(not _shines_at(g, x, y) and not _lit_at(g, x, y), "%s had: no shine or light" % name)
		for k in armory.owned.size():
			armory.owned[k] = true
		_check(
			_inked(g, x, y) == 0 and GunFinder.far_prompt(g) == "",
			"%s had with the rest: no mark or prompt" % name
		)


## Where pickup `i` lies (Vector2.INF for none).
static func _at(g: Game, i: int) -> Vector2:
	if i < 0:
		return Vector2.INF
	var entry: Array = g.pickups[i]
	return Vector2(entry[1], entry[2])


## A gun behind a secret not yet found: no shine, light or mark, even stood by.
func _secret(g: Game, name: String, x: float, y: float) -> void:
	_check(GunFinder.in_secret(g, x, y), "%s is behind a secret not found yet" % name)
	_stand(g, x, y, 2.5, false, false)
	_tick(g, 30)
	_check(
		not _shines_at(g, x, y) and not _lit_at(g, x, y) and _inked(g, x, y) == 0,
		"%s: no shine, light or mark gives the secret away" % name
	)


# ------------------------------------------------------------------ the rest


func _tally(main: Control) -> void:
	var g := _game(main, "sawmill")
	var row := GunFinder.tally(g)
	_check(
		row == ["GUNS", "00 / 03"], "the sawmill's tally, with the guns a new game has: %s" % [row]
	)
	var armory := g.local_player.armory
	armory.owned[Weapons.NAMES.find("shotgun")] = true
	armory.owned[Weapons.NAMES.find("bowling_ball")] = true
	row = GunFinder.tally(g)
	_check(row == ["GUNS", "02 / 03"], "two of its three had: %s" % [row])
	var c := Canvas.new()
	g.won = true
	main.hud.intermission(c, g)
	_check(true, "the tally draws with its GUNS row")


func _hub(main: Control) -> void:
	var g := _game(main, "hub")
	var shack: GameFeature = g.features.get("trophy_shack")
	_check(not GunFinder.on(g), "the Crossroads lays out no guns to find")
	var armory := g.local_player.armory
	for gun: String in ["shotgun", "rifle", "crossbow"]:
		armory.owned[Weapons.NAMES.find(gun)] = true
	var lines: Array = shack.call("lines")
	_check(lines.has("GUN BOARD 5 OF 14"), "the card counts the guns had: %s" % [lines])
	var sprites: Array = shack.sprites()
	var board := 0
	var hung := 0
	for s: View.Sprite in sprites:
		if s.image == "gun_board":
			board += 1
		elif s.image.begins_with("item_") and not is_nan(s.plane):
			hung += 1
	_check(board == 1 and g.art.has_art("gun_board"), "the shadow board hangs in the shack")
	_check(hung == 5, "each gun had hangs on it (%d)" % hung)
	# The card keeps clear of the board, looked at from the middle of the shack
	# and from the door's side and the back.
	var size := Vector2i(170, 14 + lines.size() * 7)
	for eye: Vector2 in [Vector2(66.2, 49.5), Vector2(68.6, 50.8), Vector2(64.6, 51.9)]:
		var angle := atan2(48.5 - eye.y, 63.0 - eye.x)
		g.view_eye = {
			"x": eye.x,
			"y": eye.y,
			"view_angle": angle,
			"pitch": 0.0,
			"bob": 0.0,
			"sway": 0.0,
			"eye": g.world.elevation(eye.x, eye.y) + .95,
		}
		var seen: Rect2 = shack.call("board_rect")
		var at: Vector2i = shack.call("card_at", size, 18)
		var fits := size
		if at.x < 0:
			fits = Vector2i(170, 21)  # folded to its count
			at = shack.call("card_at", fits, 18)
		_check(
			(
				seen.size.x > 20.0
				and at.x >= 0
				and not Rect2(Vector2(at), Vector2(fits)).intersects(seen)
			),
			(
				"looked at from (%.1f, %.1f): the card (%s) clear of the board (%s)"
				% [eye.x, eye.y, at, seen]
			)
		)


func _off(main: Control) -> void:
	for id: String in COUNTY:
		var g := _game(main, id)
		_check(not GunFinder.on(g), "%s: no campaign gun cues" % id)
		var signs := 0
		for board: LevelData.Billboard in g.world.billboards:
			if board.image.begins_with("gun_sign_"):
				signs += 1
		_check(signs == 0, "%s: none of the chapter's gun signs" % id)
	for id: String in ["range", "grainyard"]:
		var g := _game(main, id)
		_check(not GunFinder.on(g), "%s: no gun cues" % id)
	var art: Assets = main.art
	for name: String in [
		"gun_sign_way_r",
		"gun_sign_honor",
		"gun_sign_fair",
		"gun_sign_mill",
		"gun_sign_quarry",
		"gun_sign_chalk",
		"fx_gun_shine_0",
		"fx_gun_shine_1",
		"fx_gun_shine_2",
	]:
		_check(art.has_art(name), "%s is packed" % name)


# ------------------------------------------------------------------ the audit


func _print_rows(fresh: Array, rows: Array) -> void:
	print("  new to a player arriving: %s" % [fresh])
	for row: Dictionary in rows:
		print(
			(
				"  %-16s (%5.1f, %5.1f) off %4d  seen %-5s  secret %-5s  new %s"
				% [row.gun, row.x, row.y, row.off, row.seen, row.secret, row.new]
			)
		)


func _picture(level: LevelData, route: Dictionary, rows: Array, out_dir: String) -> void:
	var scale := 6
	var image := Image.create_empty(
		level.width * scale, level.height * scale, false, Image.FORMAT_RGB8
	)
	for cy in level.height:
		for cx in level.width:
			var cell := cy * level.width + cx
			var color := Color(.09, .07, .06) if level.solid[cell] >= 0 else Color(.32, .29, .25)
			if route.has(Vector2i(cx, cy)):
				color = Color(.9, .8, .2)
			image.fill_rect(Rect2i(cx * scale, cy * scale, scale, scale), color)
	for door: LevelData.Door in level.doors:
		if door.secret:
			image.fill_rect(Rect2i(door.x * scale, door.y * scale, scale, scale), Color(.8, .2, .9))
	for row: Dictionary in rows:
		var c := Color(1, .15, .1) if row.new else Color(.3, .6, 1)
		image.fill_rect(Rect2i(int(row.x * scale) - 5, int(row.y * scale) - 5, 11, 11), c)
	var s := Vector2i(int(level.spawn[0]), int(level.spawn[1]))
	image.fill_rect(Rect2i(s.x * scale - 4, s.y * scale - 4, 9, 9), Color(.2, .9, .3))
	image.save_png("%s/guns_%s.png" % [out_dir, level.id])
