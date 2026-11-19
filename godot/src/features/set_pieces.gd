## The big breaks (data/tuning/set_pieces.cfg; shapes in src/set_piece_shape.gd,
## the flood and the fuel trail in src/set_piece_flow.gd): a level's barns and
## hay sheds, water towers and fuel lines (its "set_pieces" list).
##
## - A barn stands on its posts. A post shot, blasted or rammed through goes
##   and takes its share of the frame; past `posts_out` posts (or a frame
##   blasted, rammed or burned to nothing) it creaks, the hands round it run,
##   and it comes down in its own big pieces: the tin sheets drop and slide
##   the way it leans, the plank walls go over on their bottom edges, the
##   posts and plates fall, each lying where it lands. A wall panel shot
##   about shows its boards knocked out and then goes over on its own.
## - A water tower stands on four braced legs: two out on one side (or the
##   frame gone) and the whole of it goes over that way about its feet; the
##   tank bursts where it strikes the ground and floods the street.
## - A fuel line's pumps or pipe holed leak gas along it; fire reaching the
##   gas runs along it to whatever waits at the end.
## What lands on somebody hurts them (players pinned a moment, hands held)
## and what lies higher than `low` is cover in the way of bodies and shots
## (LevelData volumes, the paths shut round it); nothing is laid over a body.
##
## Play: game.rng and the game's own arithmetic; a falling piece's place is
## worked out from its move and game.clock. Carried (SIM_FEATURES), saved
## (what came down stays down), and a fact (FACT_FEATURES: restore() puts the
## level's volumes right on a client or a load). Drawn through the wreck
## layer (each part's key cut by src/set_piece_mesh.gd); wreckage.gd throws
## the splinters and the tank's staves.
class_name SetPiecesFeature
extends GameFeature

const Flow := preload("res://src/set_piece_flow.gd")
const Shape := preload("res://src/set_piece_shape.gd")

const STANDING := 0
const WARN := 1
const FALLING := 2
const DOWN := 3
## A part: standing, moving, lying, gone (a tank burst).
const UP := 0
const MOVING := 1
const LYING := 2
const GONE := 3
## A move: [kind, t0, seconds, ...]. HINGE: about a line through `pivot`
## along `axis` by `angle`, then `dz` up by the end. DROP: to (x, y, z) and the
## turn (qx, qy, qz, qw), falling by gravity.
const HINGE := 1.0
const DROP := 2.0

## Each set piece's state (plain values): "kind", "stage", "t0", "frame",
## "lean" [x, y], "hp" (each part's), "out" (UP, MOVING...), "moves" (each
## part's move, [] none), "hit" (bodies struck: key -> clock), and a tower's
## "burst" (when its tank bursts, -1), a fuel line's "holes" ([cell index,
## clock] each) and "lit" (each trail cell's clock lit, -1; -2 washed away).
var pieces: Array = []
## Volumes it put in the way and took out of it (rows as the level's own).
var added: Array = []
var dropped: Array = []
## Floods running (set_piece_flow.gd).
var floods: Array = []
var net_version := 0
const NET_GUARDED := ["pieces", "added", "dropped", "floods"]

## The level's specs, their parts (Shape.Part) and floors, the trails' cells:
## made the same on every machine from the level, never carried.
var _specs: Array = []
var shapes: Array = []
var _ground: Array = []
var trails: Array = []
var _boxes: Array = []
var _tile := 0.0
## Looks: the sprites shown (by piece and part), the gas and water marks.
var _sprites := {}
## How each piece in view is drawn (_plan), made again when it changes.
var _draw_plan := {}
var _drawn_version := -1
var mark_cache := {}
var _hiss_at := 0.0
## Rubble laid this fall, its paths to shut once nothing moves.
var _to_shut: Array = []
## The last ray(): how far, and which part (piece * 1000 + part).
var ray_d := 0.0
var ray_hit := -1


func id() -> String:
	return "set_pieces"


func attach() -> void:
	var never: Array = Shape.cfg().get_value("all", "never", [])
	if never.has(game.level.id):
		return
	_tile = Shape.f(maxi(0, game.world.tile_id("barn")))
	for item: Variant in game.level.set_pieces:
		if not (item is Dictionary):
			continue
		var spec: Dictionary = item
		if not Shape.KINDS.has(str(spec.get("kind", ""))):
			continue
		_specs.append(spec)
	if _specs.is_empty():
		return
	for spec: Dictionary in _specs:
		var x: float = spec.get("x", 0.0)
		var y: float = spec.get("y", 0.0)
		var ground := game.world.elevation(x, y)
		var made: Array[Shape.Part] = Shape.parts(spec, ground)
		shapes.append(made)
		_ground.append(ground)
		trails.append(Shape.trail(spec) if str(spec["kind"]) == "fuel" else [])
		_boxes.append(Shape.footprint(spec).grow(.3))
		pieces.append(_fresh(spec, made))
	_stand_all()
	tick_with(_tick)
	game.events.exploded.connect(_exploded)


## A piece as the level stands it.
func _fresh(spec: Dictionary, made: Array[Shape.Part]) -> Dictionary:
	var kind := str(spec["kind"])
	var hp: Array = []
	var out: Array = []
	var moves: Array = []
	for part: Shape.Part in made:
		hp.append(part.hp)
		out.append(UP)
		moves.append([])
	var state := {
		"kind": kind,
		"stage": STANDING,
		"t0": 0.0,
		"frame": Shape.num(kind, "frame", 100.0),
		"lean": [0.0, 0.0],
		"hp": hp,
		"out": out,
		"moves": moves,
		"hit": {},
		"burst": -1.0,
	}
	if kind == "fuel":
		var lit: Array = []
		lit.resize(Shape.trail(spec).size())
		lit.fill(-1.0)
		state["holes"] = []
		state["lit"] = lit
	return state


## Every standing part that is in the way puts its volume in the level (the
## same on every machine at the start; the paths shut round them).
func _stand_all() -> void:
	for i in _specs.size():
		var made: Array = shapes[i]
		for k in made.size():
			var part: Shape.Part = made[k]
			if part.solid:
				var v := Shape.volume_of(part, _tile)
				if not game.world.collision_volumes.has(v):
					ArenaWreckFeature.add_volume(game.world, v)
		var box: Rect2 = _boxes[i]
		_shut(box.position.x, box.position.y, box.end.x, box.end.y)


# ------------------------------------------------------------------ saves


func save() -> Dictionary:
	var any := not (added.is_empty() and dropped.is_empty() and floods.is_empty())
	for st: Dictionary in pieces:
		var stage: int = st["stage"]
		any = any or stage != STANDING or _touched(st)
	if not any:
		return {}
	return {
		"pieces": pieces.duplicate(true),
		"added": added.duplicate(true),
		"dropped": dropped.duplicate(true),
		"floods": floods.duplicate(true),
	}


static func _touched(st: Dictionary) -> bool:
	for o: Variant in st["out"]:
		var was: int = o
		if was != UP:
			return true
	if st.has("holes"):
		var holes: Array = st["holes"]
		if not holes.is_empty():
			return true
	return false


## Back from a save, or a host's facts on a client: the pieces as they were
## and the level as they left it (only what is not so already).
func restore(state: Dictionary) -> void:
	if _specs.is_empty() or state.is_empty():
		return
	var kept: Array = state.get("pieces", [])
	if kept.size() == pieces.size():
		for i in kept.size():
			var row: Dictionary = kept[i]
			var mine: Dictionary = pieces[i]
			var outs: Array = row.get("out", [])
			var mine_out: Array = mine["out"]
			if str(row.get("kind", "")) == str(mine["kind"]) and outs.size() == mine_out.size():
				pieces[i] = _ints(row.duplicate(true))
	for row: Array in state.get("dropped", []):
		var v := PackedFloat32Array(row)
		if game.world.collision_volumes.has(v):
			game.world.drop_volume(v)
			game.reopen_paths(v[0], v[1], v[2], v[3])
		if not _has(dropped, row):
			dropped.append(row)
	for row: Array in state.get("added", []):
		var v := PackedFloat32Array(row)
		if not game.world.collision_volumes.has(v):
			ArenaWreckFeature.add_volume(game.world, v)
			_shut(v[0], v[1], v[2], v[3])
		if not _has(added, row):
			added.append(row)
	var running: Array = state.get("floods", [])
	floods = running.duplicate(true)
	net_version += 1
	_sprites.clear()
	wake()
	# A snapshot put on (a late joiner, a copy put back: _apply_facts notes
	# it in game.net_facts first): the looks lay what is down in its pieces at
	# once, as a load does (wreckage.gd sync_sets). Until pass 12 a late
	# joiner saw every part land again, dust, rumble and all, and lie whole.
	if game.net_facts.has(id()):
		var wk: GameFeature = game.features.get("wreckage")
		if wk != null and wk.has_method("sync_sets"):
			wk.call("sync_sets")


## A piece's state read back (a save's numbers are all floats): its stage
## and its parts' states whole numbers again.
static func _ints(row: Dictionary) -> Dictionary:
	row["stage"] = roundi(Shape.f(row.get("stage", STANDING)))
	var outs: Array = row.get("out", [])
	for k in outs.size():
		outs[k] = roundi(Shape.f(outs[k]))
	return row


static func _has(rows: Array, row: Array) -> bool:
	for r: Array in rows:
		if r == row:
			return true
	return false


# ------------------------------------------------------------------ hits


## The nearest standing part along a hitscan shot from (px, py) at eye
## height, nearer than `near`: true, with ray_d and ray_hit set.
func ray(px: float, py: float, eye: float, ax: float, ay: float, slope: float, near: float) -> bool:
	ray_hit = -1
	ray_d = near
	if _specs.is_empty():
		return false
	var o := Vector3(px, py, eye)
	var dir := Vector3(ax, ay, slope)
	for i in _specs.size():
		var box: Rect2 = _boxes[i]
		if not _ray_rect(px, py, ax, ay, box, ray_d):
			continue
		var st: Dictionary = pieces[i]
		var outs: Array = st["out"]
		var made: Array = shapes[i]
		for k in made.size():
			var was: int = outs[k]
			if was != UP:
				continue
			var part: Shape.Part = made[k]
			var dx := part.p.x - px
			var dy := part.p.y - py
			var reach := part.half.length() + .05
			if absf(dx * ay - dy * ax) > reach or dx * ax + dy * ay < -reach:
				continue
			var t := _ray_box(o, dir, part.p, part.q, part.half)
			if t <= 0.0 or t >= ray_d:
				continue
			var back := maxf(0.0, t - .12)
			if game.world.visible(px, py, px + ax * back, py + ay * back, eye, eye + slope * back):
				ray_d = t
				ray_hit = i * 1000 + k
	return ray_hit >= 0


## Whether a shot along (ax, ay) from (px, py) crosses `box` within `far`.
static func _ray_rect(px: float, py: float, ax: float, ay: float, box: Rect2, far: float) -> bool:
	var t0 := 0.0
	var t1 := far
	for axis in 2:
		var o := px if axis == 0 else py
		var d := ax if axis == 0 else ay
		var lo := box.position.x if axis == 0 else box.position.y
		var hi := box.end.x if axis == 0 else box.end.y
		if absf(d) < 1e-6:
			if o < lo or o > hi:
				return false
			continue
		var a := (lo - o) / d
		var b := (hi - o) / d
		t0 = maxf(t0, minf(a, b))
		t1 = minf(t1, maxf(a, b))
		if t0 > t1:
			return false
	return true


## Where a ray from o along dir enters the box `half` about p turned by q
## (dir's own length a unit of t), or -1.
static func _ray_box(o: Vector3, dir: Vector3, p: Vector3, q: Quaternion, half: Vector3) -> float:
	var inv := q.inverse()
	var lo := inv * (o - p)
	var ld := inv * dir
	var t0 := 0.0
	var t1 := INF
	for a in 3:
		var oa := lo[a]
		var da := ld[a]
		var h := half[a] + .02
		if absf(da) < 1e-7:
			if absf(oa) > h:
				return -1.0
			continue
		var u := (-h - oa) / da
		var v := (h - oa) / da
		t0 = maxf(t0, minf(u, v))
		t1 = minf(t1, maxf(u, v))
		if t0 > t1:
			return -1.0
	return t0


## The standing part a thing at (x, y, z) is in (a shot flying, a vehicle's
## nose `reach` wide), or -1 (piece * 1000 + part).
func touch(x: float, y: float, z: float, reach: float) -> int:
	for i in _specs.size():
		var box: Rect2 = _boxes[i]
		if not box.grow(reach).has_point(Vector2(x, y)):
			continue
		var st: Dictionary = pieces[i]
		var outs: Array = st["out"]
		var made: Array = shapes[i]
		for k in made.size():
			var was: int = outs[k]
			var part: Shape.Part = made[k]
			if was != UP or part.hp <= 0.0:
				continue
			var local := part.q.inverse() * (Vector3(x, y, z) - part.p)
			if (
				absf(local.x) < part.half.x + reach
				and absf(local.y) < part.half.y + reach
				and absf(local.z) < part.half.z + .05
			):
				return i * 1000 + k
	return -1


## A shot, a swing, a ram or a fire took `amount` off part `code` (piece *
## 1000 + part), going along (ax, ay).
func strike(code: int, amount: float, ax: float, ay: float) -> void:
	var i := code / 1000
	var k := code % 1000
	if i < 0 or i >= pieces.size():
		return
	var st: Dictionary = pieces[i]
	var made: Array = shapes[i]
	var part: Shape.Part = made[k]
	var outs: Array = st["out"]
	var was: int = outs[k]
	if was != UP:
		return
	var kind := str(st["kind"])
	if part.hp <= 0.0:
		# A plate or the tin: a knock to the whole, no more.
		_strain(i, amount * .25, ax, ay)
		_chip(part, kind)
		return
	var hp: Array = st["hp"]
	var left: float = hp[k]
	var cracked := left < part.hp * Shape.num(kind, "crack", .55)
	left -= amount
	hp[k] = left
	net_version += 1
	wake()
	if left > 0.0:
		_chip(part, kind)
		if part.role == "wall" and not cracked and left < part.hp * Shape.num(kind, "crack", .55):
			_sprites.clear()
			game.sound_at("plank_crack", part.p.x, part.p.y, .9)
			game.burst(part.p.x, part.p.y, part.p.z, "chips", 8, 1.6)
		return
	match part.role:
		"post", "leg":
			_knock_out(i, k, ax, ay)
			var side := part.side
			var lean: Array = st["lean"]
			lean[0] = Shape.f(lean[0]) + side.x + ax * .5
			lean[1] = Shape.f(lean[1]) + side.y + ay * .5
			st["frame"] = Shape.f(st["frame"]) - Shape.num(kind, "strain", 30.0)
			_judge(i)
		"wall":
			_knock_out(i, k, ax, ay)
		"pipe", "pump":
			# Holed: it leaks from there on (a pipe still lies there, drawn).
			Flow.hole(self, i, part, game.clock)
			outs[k] = LYING if part.role == "pipe" else GONE
			game.sound_at("gas_leak", part.p.x, part.p.y, 1.0)
			game.burst(part.p.x, part.p.y, part.p.z, "spark", 6, 1.4)


func _chip(part: Shape.Part, kind: String) -> void:
	var stuff := "spark" if part.role in ["pipe", "pump", "hoop", "cap", "roof"] else "wood"
	game.burst(part.p.x, part.p.y, part.p.z, stuff, 3, .8)
	if game.clock >= _hiss_at:
		_hiss_at = game.clock + .08
		var cue := "ricochet" if stuff == "spark" else "impact_wood"
		game.sound_at(cue, part.p.x, part.p.y, .35 if kind != "fuel" else .5)


## A knock to the whole frame (a blast, a ram, a fire): its frame hp, and the
## way it leans.
func _strain(i: int, amount: float, ax: float, ay: float) -> void:
	var st: Dictionary = pieces[i]
	var stage: int = st["stage"]
	if stage != STANDING or str(st["kind"]) == "fuel":
		return
	st["frame"] = Shape.f(st["frame"]) - amount
	var lean: Array = st["lean"]
	lean[0] = Shape.f(lean[0]) + ax * amount * .02
	lean[1] = Shape.f(lean[1]) + ay * amount * .02
	net_version += 1
	_judge(i)


## Whether piece i goes now: its frame spent, or too many posts or legs out.
func _judge(i: int) -> void:
	var st: Dictionary = pieces[i]
	var stage: int = st["stage"]
	if stage != STANDING:
		return
	var kind := str(st["kind"])
	var made: Array = shapes[i]
	var outs: Array = st["out"]
	var gone := 0
	var sides: Array[Vector2] = []
	for k in made.size():
		var part: Shape.Part = made[k]
		var was: int = outs[k]
		if (part.role == "post" or part.role == "leg") and was != UP:
			gone += 1
			sides.append(part.side)
	var falls := Shape.f(st["frame"]) <= 0.0
	if kind == "barn":
		falls = falls or gone >= int(Shape.num("barn", "posts_out", 2.0))
	elif kind == "tower":
		# Two legs out on one side: those two share a side of the square.
		for a in sides.size():
			for b in range(a + 1, sides.size()):
				if sides[a].dot(sides[b]) > -.5:
					falls = true
		falls = falls or gone >= 3
	if not falls:
		return
	st["stage"] = WARN
	st["t0"] = game.clock
	net_version += 1
	wake()
	_warn(i)


## The creak before it goes: dust sifts down, the hands run from it, and a
## player near hears the call.
func _warn(i: int) -> void:
	var spec: Dictionary = _specs[i]
	var kind := str(spec["kind"])
	var box: Rect2 = _boxes[i]
	var mid := box.get_center()
	var heard := Shape.num(kind, "heard", 12.0)
	game.sound_at("tower_groan" if kind == "tower" else "collapse_creak", mid.x, mid.y, 1.0)
	var top: float = _ground[i] + Shape.num(kind, "eave", Shape.num(kind, "legs", 3.0))
	for n in 4:
		var x := box.position.x + box.size.x * (n + .5) / 4.0
		game.burst(x, mid.y, top, "dust", 5, .6)
	var flee := Shape.num("all", "flee", 2.2)
	var reach := box.grow(flee)
	for e: Enemy in game.enemies:
		if e.alive and e.hostile and not Enemy.BOSS_TITLES.has(e.kind):
			if reach.has_point(Vector2(e.x, e.y)):
				e.retreat = [mid.x, mid.y, game.clock + Shape.num("all", "warn", .95) + 1.2]
	for p: Player in game.players:
		if Vector2(p.x - mid.x, p.y - mid.y).length() < heard:
			game.message(Shape.text(kind, "call", "LOOK OUT!"), 1.6)
			break
	game.disturb(mid.x, mid.y, heard, top)


## Whether (x, y) is in the footprint of a barn or shed coming or come down.
func rubble_at(x: float, y: float) -> bool:
	for i in pieces.size():
		var st: Dictionary = pieces[i]
		var stage: int = st["stage"]
		var box: Rect2 = _boxes[i]
		if stage >= FALLING and str(st["kind"]) == "barn" and box.has_point(Vector2(x, y)):
			return true
	return false


# ------------------------------------------------------------------ blasts


## A blast at (x, y, z) (game_combat.gd _blast_shoves): the parts it reaches
## take its damage by how near, the frames round it are shaken, a fuel line's
## pipe holed.
func blast(x: float, y: float, z: float, radius: float, strength: float, energy: bool) -> void:
	if _specs.is_empty():
		return
	var at := Vector3(x, y, z)
	var k := .5 if energy else 1.0
	for i in _specs.size():
		var box: Rect2 = _boxes[i]
		if not box.grow(radius).has_point(Vector2(x, y)):
			continue
		var st: Dictionary = pieces[i]
		var stage: int = st["stage"]
		if stage != STANDING:
			continue
		var made: Array = shapes[i]
		var outs: Array = st["out"]
		for j in made.size():
			var part: Shape.Part = made[j]
			var was: int = outs[j]
			if was != UP or part.hp <= 0.0:
				continue
			var local := part.q.inverse() * (at - part.p)
			var near := Vector3(
				clampf(local.x, -part.half.x, part.half.x),
				clampf(local.y, -part.half.y, part.half.y),
				clampf(local.z, -part.half.z, part.half.z)
			)
			var d := (local - near).length()
			if d >= radius:
				continue
			var away := Vector2(part.p.x - x, part.p.y - y).normalized()
			strike(i * 1000 + j, strength * k * (1.0 - d / (radius + .3)), away.x, away.y)
		var mid := box.get_center()
		var d0 := maxf(0.0, Vector2(x, y).distance_to(mid) - box.size.length() * .3)
		if d0 < radius:
			var push := (mid - Vector2(x, y)).normalized()
			_strain(
				i,
				strength * k * Shape.num("all", "blast_frame", .9) * (1.0 - d0 / (radius + 1.0)),
				push.x,
				push.y
			)


func _exploded(x: float, y: float, z: float, energy: bool) -> void:
	if not energy:
		Flow.blast_lights(self, x, y, z)


# ------------------------------------------------------------------ the tick


func _tick(dt: float) -> void:
	if _specs.is_empty():
		sleep()
		return
	var busy := false
	for i in pieces.size():
		var st: Dictionary = pieces[i]
		var stage: int = st["stage"]
		if stage == WARN:
			busy = true
			if game.clock >= Shape.f(st["t0"]) + Shape.num("all", "warn", .95):
				_collapse(i)
		elif stage == FALLING:
			busy = true
			_falling(i)
		elif _any_moving(st):
			busy = true
			_falling(i)
		if str(st["kind"]) == "fuel" and Flow.trail_busy(self, i):
			busy = true
			Flow.trail_tick(self, i)
	if not floods.is_empty():
		busy = true
		Flow.flood_tick(self, dt)
	if not _to_shut.is_empty() and not _falling_any():
		for v: PackedFloat32Array in _to_shut:
			_shut(v[0], v[1], v[2], v[3])
		_to_shut.clear()
	# Every `burn_every` of the clock (no state of its own: a copy woken at
	# another tick burns on the same ticks).
	var every := Shape.num("all", "burn_every", .5)
	if floori(game.clock / every) != floori((game.clock - dt) / every):
		_burn()
	if not busy and not _fire_burning():
		# Nothing moving, leaking or burning: no tick until something strikes,
		# blasts or a fire starts (wake()).
		sleep()


func _falling_any() -> bool:
	for st: Dictionary in pieces:
		if _any_moving(st):
			return true
	return false


func _any_moving(st: Dictionary) -> bool:
	for o: Variant in st["out"]:
		var was: int = o
		if was == MOVING:
			return true
	return false


func _fire_burning() -> bool:
	var fire: GameFeature = game.features.get("fire")
	if fire == null:
		return false
	var burning: Array = fire.get("burning")
	return not burning.is_empty()


## Fire in a wooden piece's footprint eats its frame, and a post, leg or wall
## standing in a burning cell.
func _burn() -> void:
	var fire: GameFeature = game.features.get("fire")
	if fire == null or not _fire_burning():
		return
	var every := Shape.num("all", "burn_every", .5)
	for i in pieces.size():
		var st: Dictionary = pieces[i]
		var stage: int = st["stage"]
		var kind := str(st["kind"])
		if stage != STANDING or kind == "fuel":
			continue
		var box: Rect2 = _boxes[i]
		var cells := 0
		for cy in range(floori(box.position.y), ceili(box.end.y)):
			for cx in range(floori(box.position.x), ceili(box.end.x)):
				if fire.call("burning_at", cx + .5, cy + .5):
					cells += 1
		if cells == 0:
			continue
		var made: Array = shapes[i]
		var outs: Array = st["out"]
		for k in made.size():
			var part: Shape.Part = made[k]
			var was: int = outs[k]
			if was == UP and part.hp > 0.0 and fire.call("burning_at", part.p.x, part.p.y):
				strike(i * 1000 + k, Shape.num("all", "burn_part", 9.0) * every, 0.0, 0.0)
		_strain(i, Shape.num("all", "burn_frame", 6.0) * cells * every, 0.0, 0.0)


# --------------------------------------------------------------- falling


## A post, leg or wall panel gone on its own: it falls along the knock.
func _knock_out(i: int, k: int, ax: float, ay: float) -> void:
	var st: Dictionary = pieces[i]
	var made: Array = shapes[i]
	var part: Shape.Part = made[k]
	var ground: float = _ground[i]
	var way := Vector2(ax, ay)
	if way.length() < .1:
		way = part.side
	way = way.normalized()
	var moves: Array = st["moves"]
	var outs: Array = st["out"]
	if part.role == "wall":
		var out_side := part.side if way.dot(part.side) >= 0.0 else -part.side
		moves[k] = _hinge_move(
			part, ground, out_side, game.clock, Shape.num("all", "hinge_time", 1.15)
		)
	else:
		moves[k] = _lie_move(part, ground, way, game.clock, ground)
	outs[k] = MOVING
	_drop_standing(part)
	game.sound_at("plank_crack", part.p.x, part.p.y, 1.0)
	game.burst(part.p.x, part.p.y, part.p.z, "chips", 10, 1.8)
	net_version += 1
	wake()


## Its standing volume out of the way (the paths open through it).
func _drop_standing(part: Shape.Part) -> void:
	if not part.solid:
		return
	var v := Shape.volume_of(part, _tile)
	if game.world.collision_volumes.has(v):
		game.world.drop_volume(v)
		game.reopen_paths(v[0], v[1], v[2], v[3])
		game.route_sig = []
	var row := Array(v)
	if not _has(dropped, row):
		dropped.append(row)


## The whole of piece i goes now.
func _collapse(i: int) -> void:
	var st: Dictionary = pieces[i]
	var spec: Dictionary = _specs[i]
	st["stage"] = FALLING
	st["t0"] = game.clock
	var lean_row: Array = st["lean"]
	var lean := Vector2(Shape.f(lean_row[0]), Shape.f(lean_row[1]))
	lean = _way(spec, lean)
	st["lean"] = [lean.x, lean.y]
	var box: Rect2 = _boxes[i]
	var mid := box.get_center()
	game.sound_at("collapse_crash", mid.x, mid.y, 1.0)
	if str(spec["kind"]) == "tower":
		_topple(i, lean)
	else:
		_cave_in(i, lean)
	net_version += 1


func spec_of(i: int) -> Dictionary:
	var spec: Dictionary = _specs[i]
	return spec


## The way a piece goes over: the square way nearest its lean among those its
## spec allows ("falls": 0 east, 1 south, 2 west, 3 north; all when none), a
## die's when it does not lean.
func _way(spec: Dictionary, lean: Vector2) -> Vector2:
	var allowed: Array = spec.get("falls", [0, 1, 2, 3])
	if allowed.is_empty():
		allowed = [0, 1, 2, 3]
	if lean.length() < .05:
		var pick: int = roundi(
			Shape.f(allowed[int(game.rng.random() * allowed.size()) % allowed.size()])
		)
		return Vector2.from_angle(pick * PI * .5).round()
	var best := Vector2.ZERO
	var most := -INF
	for item: Variant in allowed:
		var dir := Vector2.from_angle(roundi(Shape.f(item)) * PI * .5).round()
		var score := dir.dot(lean.normalized())
		if score > most:
			most = score
			best = dir
	return best


## A barn's pieces: each its own way down, a little apart in time.
func _cave_in(i: int, lean: Vector2) -> void:
	var st: Dictionary = pieces[i]
	var made: Array = shapes[i]
	var outs: Array = st["out"]
	var moves: Array = st["moves"]
	var ground: float = _ground[i]
	var hinge := Shape.num("all", "hinge_time", 1.15)
	var layer := 0
	for k in made.size():
		var part: Shape.Part = made[k]
		var was: int = outs[k]
		if was != UP:
			continue
		var delay := game.rng.random() * .25
		var t0 := game.clock + delay
		match part.role:
			"post":
				moves[k] = _lie_move(part, ground, lean, t0, ground)
			"wall":
				var side := part.side if part.side.dot(lean) > -.3 else -part.side
				moves[k] = _hinge_move(
					part, ground, side, t0, hinge * (.9 + .3 * game.rng.random())
				)
			"beam":
				moves[k] = _lie_move(part, ground, lean, t0 + .15, ground + .02)
			"roof":
				layer += 1
				var slide := (.4 + .8 * game.rng.random()) * lean
				var lift := ground + .16 + .055 * (layer % 4)
				var tilt := (game.rng.random() - .5) * .9
				var yaw := (game.rng.random() - .5) * .7
				var q1 := (
					Quaternion(Shape.turn_of(spec_of(i)))
					* Quaternion(Vector3(0, 0, 1), yaw)
					* Quaternion(Vector3(1, 0, 0), tilt)
				)
				var reach := absf(sin(tilt)) * part.half.y
				var to := Vector3(part.p.x + slide.x, part.p.y + slide.y, lift + reach)
				moves[k] = _drop_move(part, to, q1, t0 + .1)
			_:
				moves[k] = _lie_move(part, ground, lean, t0, ground)
		outs[k] = MOVING
		_drop_standing(part)


## A tower over about its feet on the leaning side, the tank bursting where
## it strikes.
func _topple(i: int, lean: Vector2) -> void:
	var st: Dictionary = pieces[i]
	var spec: Dictionary = _specs[i]
	var made: Array = shapes[i]
	var outs: Array = st["out"]
	var moves: Array = st["moves"]
	var ground: float = _ground[i]
	var x: float = spec["x"]
	var y: float = spec["y"]
	var s := Shape.own(spec, "spread", 1.15)
	var pivot := Vector3(x + lean.x * s, y + lean.y * s, ground)
	var axis := Vector3(0, 0, 1).cross(Vector3(lean.x, lean.y, 0.0)).normalized()
	var time := Shape.num("tower", "topple_time", 2.1)
	# When the tank first meets the ground.
	var hit := PI * .5
	for part: Shape.Part in made:
		if part.role != "tank":
			continue
		for n in 90:
			var a := PI * .5 * n / 89.0
			var r := Basis(axis, a)
			var c := pivot + r * (part.p - pivot)
			if c.z - part.half.x <= ground + .05:
				hit = a
				break
	st["burst"] = game.clock + time * sqrt(hit / (PI * .5))
	st["burst_angle"] = hit
	# The frame lies whole on its side: lifted as one so none of it is under
	# the floor (the far legs up over the near ones, the side braces between).
	var dz := -INF
	for k in made.size():
		var part: Shape.Part = made[k]
		var was: int = outs[k]
		if was == UP and not part.tank:
			dz = maxf(dz, _settle(part, pivot, axis, PI * .5, ground))
	for k in made.size():
		var part: Shape.Part = made[k]
		var was: int = outs[k]
		if was != UP:
			continue
		moves[k] = [
			HINGE, game.clock, time, pivot.x, pivot.y, pivot.z, axis.x, axis.y, axis.z, PI * .5, dz
		]
		outs[k] = MOVING
		_drop_standing(part)


## How far up a part turned by `angle` about the line must come to lie on
## the floor (down when it ends over it).
func _settle(part: Shape.Part, pivot: Vector3, axis: Vector3, angle: float, ground: float) -> float:
	var r := Basis(axis, angle)
	var c := pivot + r * (part.p - pivot)
	var b := r * Basis(part.q)
	var low := INF
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var corner := c + b * Vector3(part.half.x * sx, part.half.y * sy, part.half.z * sz)
				low = minf(low, corner.z)
	var floor_z := game.world.floor_under(c.x, c.y, maxf(c.z, ground) + .5)
	return floor_z + .01 - low


## A wall panel over on its bottom edge toward `side`.
func _hinge_move(part: Shape.Part, ground: float, side: Vector2, t0: float, time: float) -> Array:
	var out := Vector3(side.x, side.y, 0.0).normalized()
	var pivot := Vector3(part.p.x, part.p.y, part.p.z - part.half.z) + out * part.half.y
	pivot.z = maxf(pivot.z, ground)
	var axis := Vector3(0, 0, 1).cross(out).normalized()
	var dz := _settle(part, pivot, axis, PI * .5, ground)
	return [HINGE, t0, time, pivot.x, pivot.y, pivot.z, axis.x, axis.y, axis.z, PI * .5, dz]


## A post, a leg or a beam down on its side along `way`, on the floor.
func _lie_move(
	part: Shape.Part, _ground_z: float, way: Vector2, t0: float, floor_z: float
) -> Array:
	var w := way.normalized() if way.length() > .01 else Vector2(1, 0)
	var b := Basis(part.q)
	var long := b.z if part.half.z >= part.half.x else b.x
	var length := maxf(part.half.z, part.half.x)
	var q1: Quaternion
	var to: Vector3
	if absf(long.z) > .7:
		# Standing: it goes over along the way, its foot where it stood.
		var axis := Vector3(0, 0, 1).cross(Vector3(w.x, w.y, 0.0)).normalized()
		q1 = Quaternion(axis, PI * .5) * part.q
		var thick := minf(part.half.x, part.half.y)
		to = Vector3(part.p.x + w.x * length * .9, part.p.y + w.y * length * .9, floor_z + thick)
	else:
		# Lying already (a plate): it drops flat, shoved along the way.
		q1 = part.q
		to = Vector3(
			part.p.x + w.x * .6, part.p.y + w.y * .6, floor_z + minf(part.half.y, part.half.z)
		)
	to.z = maxf(to.z, game.world.floor_under(to.x, to.y, part.p.z) + minf(part.half.x, part.half.y))
	return _drop_move(part, to, q1, t0)


func _drop_move(part: Shape.Part, to: Vector3, q1: Quaternion, t0: float) -> Array:
	var fall := maxf(.05, part.p.z - to.z)
	var time := sqrt(2.0 * fall / Shape.num("all", "gravity", 14.0)) + .12
	return [DROP, t0, time, to.x, to.y, to.z, q1.x, q1.y, q1.z, q1.w]


## Where part k of piece i is now: [middle, turn].
func pose(i: int, k: int, clock: float) -> Array:
	var st: Dictionary = pieces[i]
	var made: Array = shapes[i]
	var part: Shape.Part = made[k]
	var moves: Array = st["moves"]
	var m: Array = moves[k]
	if m.is_empty():
		return [part.p, part.q]
	var t0: float = m[1]
	var time: float = m[2]
	var s := clampf((clock - t0) / maxf(.01, time), 0.0, 1.0)
	var kind: float = m[0]
	if kind == HINGE:
		var pivot := Vector3(Shape.f(m[3]), Shape.f(m[4]), Shape.f(m[5]))
		var axis := Vector3(Shape.f(m[6]), Shape.f(m[7]), Shape.f(m[8]))
		var angle: float = m[9]
		var dz: float = m[10]
		var r := Basis(axis, angle * s * s)
		var c := pivot + r * (part.p - pivot)
		c.z += dz * s * s * s
		return [c, Quaternion(r) * part.q]
	var to := Vector3(Shape.f(m[3]), Shape.f(m[4]), Shape.f(m[5]))
	var q1 := Quaternion(Shape.f(m[6]), Shape.f(m[7]), Shape.f(m[8]), Shape.f(m[9]))
	var p0 := part.p
	var q0 := part.q
	if m.size() >= 17:
		# From where it was when it broke away (a tower's frame at the burst).
		p0 = Vector3(Shape.f(m[10]), Shape.f(m[11]), Shape.f(m[12]))
		q0 = Quaternion(Shape.f(m[13]), Shape.f(m[14]), Shape.f(m[15]), Shape.f(m[16]))
	var e := s * s
	var at := p0.lerp(to, e)
	var fallen := p0.z - .5 * Shape.num("all", "gravity", 14.0) * pow(maxf(0.0, clock - t0), 2.0)
	at.z = maxf(to.z, minf(fallen, p0.z))
	return [at, q0.slerp(q1, minf(1.0, s * 1.2))]


## A tower's frame at the burst: it comes apart, each leg and brace falling
## from where it is to lie flat on the ground, a little scattered.
func _break_up(i: int) -> void:
	var st: Dictionary = pieces[i]
	var made: Array = shapes[i]
	var outs: Array = st["out"]
	var moves: Array = st["moves"]
	var lean_row: Array = st["lean"]
	var lean := Vector2(Shape.f(lean_row[0]), Shape.f(lean_row[1]))
	var side := Vector2(-lean.y, lean.x)
	for k in made.size():
		var was: int = outs[k]
		var part: Shape.Part = made[k]
		if was != MOVING or part.tank:
			continue
		var at: Array = pose(i, k, game.clock)
		var c: Vector3 = at[0]
		var q: Quaternion = at[1]
		var b := Basis(q)
		# Its thinnest way up, turned about the up-axis a little.
		var thin := b.y if part.half.y <= part.half.x and part.half.y <= part.half.z else b.x
		if part.half.z < minf(part.half.x, part.half.y):
			thin = b.z
		var flat := Quaternion(thin.normalized(), Vector3(0, 0, 1) * signf(thin.z + .0001))
		var spin := Quaternion(Vector3(0, 0, 1), (game.rng.random() - .5) * .6)
		var q1 := (spin * flat * q).normalized()
		var thick := minf(part.half.x, minf(part.half.y, part.half.z))
		var spread := side * (game.rng.random() - .5) * 1.2 + lean * game.rng.random() * .8
		var ground: float = _ground[i]
		var floor_z := game.world.floor_under(
			c.x + spread.x, c.y + spread.y, maxf(c.z, ground) + .3
		)
		var to := Vector3(c.x + spread.x, c.y + spread.y, floor_z + thick + .01)
		var fall := maxf(.05, c.z - to.z)
		var time := sqrt(2.0 * fall / Shape.num("all", "gravity", 14.0)) + .15
		moves[k] = [
			DROP,
			game.clock,
			time,
			to.x,
			to.y,
			to.z,
			q1.x,
			q1.y,
			q1.z,
			q1.w,
			c.x,
			c.y,
			c.z,
			q.x,
			q.y,
			q.z,
			q.w
		]
	net_version += 1


## The pieces of piece i in the air that have come down this tick: their
## hurt, their dust and the cover they make.
func _falling(i: int) -> void:
	var st: Dictionary = pieces[i]
	var made: Array = shapes[i]
	var outs: Array = st["out"]
	var moves: Array = st["moves"]
	var kind := str(st["kind"])
	var burst_at: float = st.get("burst", -1.0)
	if kind == "tower" and burst_at > 0.0 and game.clock >= burst_at:
		st["burst"] = -2.0
		Flow.burst(self, i)
		_break_up(i)
	var moving := false
	for k in made.size():
		var was: int = outs[k]
		if was != MOVING:
			continue
		var part: Shape.Part = made[k]
		if part.tank and Shape.f(st["burst"]) == -2.0:
			outs[k] = GONE
			net_version += 1
			continue
		var m: Array = moves[k]
		var t0: float = m[1]
		var time: float = m[2]
		if game.clock < t0 + time:
			moving = true
			continue
		outs[k] = LYING
		net_version += 1
		_landed(i, k)
	var stage: int = st["stage"]
	if stage == FALLING and not moving:
		st["stage"] = DOWN
		net_version += 1


## Part k of piece i came down: whoever is under it, the noise, its cover.
func _landed(i: int, k: int) -> void:
	var st: Dictionary = pieces[i]
	var made: Array = shapes[i]
	var part: Shape.Part = made[k]
	var at: Array = pose(i, k, INF)
	var c: Vector3 = at[0]
	var q: Quaternion = at[1]
	var lying := Shape.Part.new()
	lying.p = c
	lying.q = q
	lying.half = part.half
	var v := Shape.volume_of(lying, _tile)
	var hurt := Shape.num("all", "crush_" + _crush_kind(part, str(st["kind"])), 25.0)
	crush(i, v, hurt)
	_crush_things(v, hurt)
	if part.role != "pipe":
		game.burst(c.x, c.y, v[7] + .1, "dust", 4 if part.half.length() < 1.0 else 9, 1.4)
		if part.half.length() > 1.0:
			game.sound_at("collapse_crash" if part.role == "roof" else "impact_wood", c.x, c.y, .7)
	var floor_z := game.world.floor_under(c.x, c.y, minf(c.z, v[7]) + .3)
	# Cover where it stands higher than a step; none overhead (a fallen
	# tower's far legs lie over the near ones).
	if v[4] - floor_z > Shape.num("all", "low", .24) and v[7] - floor_z < 1.0:
		_cover(v)


func _crush_kind(part: Shape.Part, kind: String) -> String:
	if kind == "tower":
		return "tower" if not part.tank else "tank"
	match part.role:
		"roof":
			return "roof"
		"wall":
			return "wall"
		"post":
			return "post"
	return "beam"


## Whoever stands where volume v comes down: hurt (once a piece a little
## while), pinned (a player knocked flat, a hand held).
func crush(i: int, v: PackedFloat32Array, amount: float) -> void:
	var st: Dictionary = pieces[i]
	var hit: Dictionary = st["hit"]
	var pin := Shape.num("all", "pin", 1.6)
	for p: Player in game.players:
		if p.health <= 0 or not _in(v, p.x, p.y, GameState.PLAYER_RADIUS):
			continue
		var key := "p%d" % p.slot
		if game.clock < Shape.f(hit.get(key, -9.0)) + .5:
			continue
		hit[key] = game.clock
		game.damage(amount, [(v[0] + v[2]) * .5, (v[1] + v[3]) * .5], "FLATTENED", p)
		p.knocked = maxf(p.knocked, pin)
	for e: Enemy in game.enemies:
		if not e.alive or not e.hostile or not _in(v, e.x, e.y, e.radius):
			continue
		var key := "e%d" % e.uid
		if game.clock < Shape.f(hit.get(key, -9.0)) + .5:
			continue
		hit[key] = game.clock
		e.stun = maxf(e.stun, Shape.num("all", "pin_enemy", 2.4))
		Players.world_hurt(game, e, amount * Shape.num("all", "enemy_crush", 1.6), false, "crushed")


## What breaks where volume v comes down (hay bales, a propane tank: it goes up).
func _crush_things(v: PackedFloat32Array, amount: float) -> void:
	var bk: GameFeature = game.features.get("breakables")
	if bk == null:
		return
	var list: Array = bk.get("pieces")
	for n in list.size():
		var piece: Object = list[n]
		var px: float = piece.get("x")
		var py: float = piece.get("y")
		var gone: bool = piece.get("broken")
		if not gone and _in(v, px, py, .1):
			bk.call("strike", n, amount * 1.5, 0.0, 0.0)


static func _in(v: PackedFloat32Array, x: float, y: float, r: float) -> bool:
	return v[0] - r < x and x < v[2] + r and v[1] - r < y and y < v[3] + r


## A lying piece in the way: none where a wall is or over anybody (it would
## shut them in).
func _cover(v: PackedFloat32Array) -> void:
	var row := Array(v)
	if _has(added, row) or game.world.collision_volumes.has(v):
		return
	for p: Player in game.players:
		if p.health > 0 and _in(v, p.x, p.y, GameState.PLAYER_RADIUS + .02):
			return
	for e: Enemy in game.enemies:
		if e.alive and _in(v, e.x, e.y, e.radius + .02):
			return
	added.append(row)
	ArenaWreckFeature.add_volume(game.world, v)
	# The paths shut round it once everything has come down (one walk of
	# the flow fields again, not one a piece landing: _tick).
	_to_shut.append(v)


## The paths shut where something now stands in the way.
func _shut(x0: float, y0: float, x1: float, y1: float) -> void:
	for p: Player in game.players:
		p.flow.close(x0, y0, x1, y1)
	game.route.close(x0, y0, x1, y1)
	game.route_sig = []


# ---------------------------------------------------------------- drawing


func sprites() -> Array:
	var out: Array = []
	if _specs.is_empty():
		return out
	# The parts wreckage.gd's SetPieceWreck draws in their own pieces (looks).
	var ruin := _ruin()
	var ruin_version := ruin.version if ruin != null else -1
	if _drawn_version != net_version or _draw_plan.get(-1, -1) != ruin_version:
		_drawn_version = net_version
		_draw_plan.clear()
		_draw_plan[-1] = ruin_version
	# One merged mesh made a frame at most (a few milliseconds each): the
	# rest are drawn a part at a time until their turn.
	var merges := 1
	for i in pieces.size():
		var box: Rect2 = _boxes[i]
		var mid := box.get_center()
		if not game.in_view(mid.x, mid.y, box.size.length() * .5 + 2.0):
			continue
		if not _draw_plan.has(i):
			_draw_plan[i] = _plan(i, ruin)
		var plan: Array = _draw_plan[i]
		var groups: Dictionary = plan[0]
		var moving: Array = plan[1]
		var floor_z: float = _ground[i]
		var st: Dictionary = pieces[i]
		for k: int in moving:
			var at: Array = pose(i, k, game.clock)
			var c: Vector3 = at[0]
			var q: Quaternion = at[1]
			_put_parts(out, i, k, _key_of(st, k), c, q)
		var n := 0
		for key: String in groups:
			n += 1
			var ks: Array = groups[key]
			if not WreckCuts.has(key):
				if merges <= 0:
					for k: int in ks:
						var at: Array = _rest_pose(i, k)
						var c: Vector3 = at[0]
						var q: Quaternion = at[1]
						_put_parts(out, i, k, _key_of(st, k), c, q)
					continue
				merges -= 1
				WreckCuts.put(key, [_merged(i, ks, Vector3(mid.x, mid.y, floor_z))])
			var tag := -1 - (i * 64 + n)
			var s: View.Sprite = _sprites.get(tag)
			if s == null:
				s = View.Sprite.new(mid.x, mid.y, "", 1.0, floor_z)
				_sprites[tag] = s
			s.solid = "~%s#0" % key
			# Its frame swaying in the creak (looks: SetPieceWreck).
			s.turn = ruin.sway_turn(i) if ruin != null else Basis.IDENTITY
			out.append(s)
	Flow.looks(self, out)
	return out


func _ruin() -> SetPieceWreck:
	var wk: GameFeature = game.features.get("wreckage")
	if wk == null:
		return null
	var ruin: SetPieceWreck = wk.get("ruin")
	return ruin


## How piece i is drawn while it stays as it is: [{merged key: its parts},
## the parts moving]. What stands (and, once nothing of it moves, what
## lies) is merged, a mesh a tile (a few nodes: each holds shader slots);
## what moves is drawn a part at a time.
func _plan(i: int, ruin: SetPieceWreck) -> Array:
	var st: Dictionary = pieces[i]
	var made: Array = shapes[i]
	var outs: Array = st["out"]
	var still := not _any_moving(st)
	var by_tile := {}
	var moving: Array = []
	for k in made.size():
		var was: int = outs[k]
		var part: Shape.Part = made[k]
		if was == GONE or part.key == "" or (ruin != null and ruin.taken.has(i * 1000 + k)):
			continue
		if was == UP or (was == LYING and still):
			var tile := _tile_of(st, k)
			if not by_tile.has(tile):
				by_tile[tile] = []
			var list: Array = by_tile[tile]
			list.append(k)
		else:
			moving.append(k)
	var groups := {}
	for tile: String in by_tile:
		var ks: Array = by_tile[tile]
		groups[_group_key(i, tile, ks, outs)] = ks
	return [groups, moving]


## Where part k of piece i stands or lies still.
func _rest_pose(i: int, k: int) -> Array:
	var st: Dictionary = pieces[i]
	var outs: Array = st["out"]
	var was: int = outs[k]
	if was == UP:
		var made: Array = shapes[i]
		var part: Shape.Part = made[k]
		return [part.p, part.q]
	return pose(i, k, INF)


## The tile part k shows now (a wall shot about shows its boards out).
func _tile_of(st: Dictionary, k: int) -> String:
	var i := pieces.find(st)
	var made: Array = shapes[i]
	var part: Shape.Part = made[k]
	if part.role == "wall":
		var hp: Array = st["hp"]
		var left: float = hp[k]
		var hit := part.tile + "_hit"
		if (
			left < part.hp * Shape.num(str(st["kind"]), "crack", .55)
			and game.art.tile_index.has(hit)
		):
			return hit
	return part.tile


func _key_of(st: Dictionary, k: int) -> String:
	var i := pieces.find(st)
	var made: Array = shapes[i]
	var part: Shape.Part = made[k]
	var tile := _tile_of(st, k)
	if tile == part.tile:
		return part.key
	return part.key.replace("t:%s@" % part.tile, "t:%s@" % tile)


## The key of piece i's parts `ks` of `tile` merged as they are now.
func _group_key(i: int, tile: String, ks: Array, outs: Array) -> String:
	var sig := ""
	for k: int in ks:
		var was: int = outs[k]
		sig += "%d%s" % [k, "u" if was == UP else "l"]
	return "t:%s@0,0|spmerged:%s:%d:%d" % [tile, game.level.id, i, sig.hash()]


## Piece i's parts `ks` as one, about `origin`.
func _merged(i: int, ks: Array, origin: Vector3) -> WreckCuts.Part:
	var st: Dictionary = pieces[i]
	var outs: Array = st["out"]
	var made: Array = shapes[i]
	var whole := WreckCuts.Part.new()
	for k: int in ks:
		var part: Shape.Part = made[k]
		var was: int = outs[k]
		var at: Array = [part.p, part.q] if was == UP else pose(i, k, INF)
		var c: Vector3 = at[0]
		var q: Quaternion = at[1]
		var b := Basis(q)
		for sub: WreckCuts.Part in WreckCuts.parts(game.art, _key_of(st, k)):
			var sb := b * sub.basis
			var sc := c + b * sub.centre - origin
			for n in sub.verts.size():
				whole.verts.append(sc + sb * sub.verts[n])
				whole.normals.append(sb * sub.normals[n])
			whole.uvs.append_array(sub.uvs)
	whole.half = Vector3(4, 4, 4)
	return whole


## The sprites of part k's pieces at `c` turned by `q`.
func _put_parts(out: Array, i: int, k: int, key: String, c: Vector3, q: Quaternion) -> void:
	var b := Basis(q)
	var subs := WreckCuts.parts(game.art, key)
	for n in subs.size():
		var sub: WreckCuts.Part = subs[n]
		var tag := (i * 1000 + k) * 64 + n
		var s: View.Sprite = _sprites.get(tag)
		if s == null:
			s = View.Sprite.new(0.0, 0.0, "", 1.0, 0.0)
			_sprites[tag] = s
		s.solid = "~%s#%d" % [key, n]
		var place := c + b * sub.centre
		s.x = place.x
		s.y = place.y
		s.z = place.z
		s.turn = b * sub.basis
		out.append(s)


func ground_marks() -> Array:
	return Flow.marks(self)
