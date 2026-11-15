## Broken scenery in real pieces of itself: a crate shot apart throws its
## boards, a barrel its staves, lids and hoops, a picnic table its top's planks
## and its legs, the outhouse its walls and roof, a jug its shards, a sign a
## splinter or two of its paint; a window's glass comes out in panes and a
## stockyard fence's boards and rails fly. Each piece is cut from the thing's
## own look (wreck_cuts.gd: its model's triangles with its baked texture, or
## its picture), flies as a rigid box (wreck_physics.gd), bounces, slides,
## piles on the others and stays where it comes to rest. A blast throws what
## lies about, and a boot kicks it.
##
## Looks only: it watches what breakables.gd and wall_breaks.gd broke (their
## pieces, windows and fence cells, as every machine has them), throws with its
## own dice, and is never carried, saved or in anyone's way. What broke before
## a save or a level's start throws nothing. breakables.cfg [pieces] says how
## many lie about at most (the oldest shrink away first; fewer on a phone) and
## on which maps none fly; each breakable's `pieces` says how it comes apart.
## Pieces asleep cost nothing; the 3D view draws them (view3d/wreck_layer.gd)
## from the sprites this hands it (View.Sprite.solid "~<key>#<piece>").
extends GameFeature

const Breakables := preload("res://src/features/breakables.gd")
const WallBreaks := preload("res://src/features/wall_breaks.gd")
const PATH := "res://data/tuning/breakables.cfg"
## How long after a blast a break nearby counts as the blast's (thrown hard,
## away from it), and how near.
const BLAST_TIME := .5
const BLAST_NEAR := 4.5
## More awake than this: one physics step a tick.
const CROWD := 20


## One piece lying about or flying.
class Wreck:
	var body: WreckPhysics.Body
	## The cut it is from (WreckCuts) and which piece of it; drawn this many
	## times its cut size.
	var key := ""
	var index := 0
	var size := 1.0
	## The sound it makes landing.
	var clink := ""
	var sprite: View.Sprite
	## When it began to shrink away (below 0: it has not).
	var fading := -1.0
	## Woken once for nothing under it since it was last knocked.
	var wedged := false


var physics: WreckPhysics
var wrecks: Array = []
var dice := RandomNumberGenerator.new()
var on := false
## Pieces lying about at most (the oldest shrink away when more come), the
## small steps a tick, how long one takes to shrink away, how heavy a piece is.
var most := 48
var steps := 2
var fade := .5
var dense := 500.0
## What has been seen broken: breakables' pieces by index, windows by index,
## each fence cell's stage.
var _seen_pieces := {}
var _seen_windows := {}
var _fence_stage := {}
var _version := -1
var _wall_version := -1
## Blasts lately: [x, y, z, clock].
var _blasts: Array = []
var _groups := 0
var _clink_next := 0.0
var _wake_at := 0
var _models: PropModels


func id() -> String:
	return "wreckage"


func attach() -> void:
	dice.seed = 1997
	var cfg := Tuning.file(PATH)
	var never: Array = cfg.get_value("pieces", "never", [])
	on = cfg.get_value("pieces", "on", true) and not never.has(game.world.id)
	if not on:
		return
	# TODO(track I): Quality.physics / Quality.steps(n) (src/core/quality.gd)
	# once the phone tiers land; until then a phone takes `most_phone`.
	var phone := (
		OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	)
	most = cfg.get_value("pieces", "most_phone" if phone else "most", 48)
	steps = cfg.get_value("pieces", "steps", 2)
	fade = cfg.get_value("pieces", "fade", .5)
	dense = cfg.get_value("pieces", "dense", 500.0)
	physics = WreckPhysics.new(game.world)
	_models = PropModels.new(game.art)
	_sync()
	# What the level can break is cut now, while it loads, not in a fight
	# (a big model takes tens of milliseconds; kept for the next level).
	var pieces: Breakables = game.features.get("breakables")
	if pieces != null:
		for p: Breakables.Piece in pieces.pieces:
			var src := _source(p)
			if not src.is_empty():
				WreckCuts.parts(game.art, str(src["key"]))
	game.events.ticked.connect(_tick)
	game.events.exploded.connect(_exploded)
	game.events.blast_shoved.connect(_shoved)


## What is broken now is not thrown (a save, a snapshot put on, the start).
func _sync() -> void:
	_seen_pieces.clear()
	_seen_windows.clear()
	_fence_stage.clear()
	var pieces: Breakables = game.features.get("breakables")
	if pieces != null:
		_version = pieces.net_version
		for i in pieces.pieces.size():
			var p: Breakables.Piece = pieces.pieces[i]
			if p.broken:
				_seen_pieces[i] = true
	var walls: WallBreaks = game.features.get("wall_breaks")
	if walls != null:
		_wall_version = walls.net_version
		for i in walls.windows.size():
			var face: WallBreaks.WindowFace = walls.windows[i]
			if face.broken:
				_seen_windows[i] = true
		for cell: Vector2i in walls.fences:
			var f: WallBreaks.Fence = walls.fences[cell]
			_fence_stage[cell] = f.stage


func restore(_state: Dictionary) -> void:
	if not on:
		return
	for w: Wreck in wrecks:
		physics.bodies.erase(w.body)
	wrecks.clear()
	_sync()


# ------------------------------------------------------------------ watching


func _tick(dt: float) -> void:
	_watch()
	# Many in the air at once: one step a tick, not `steps` (the cost caps
	# itself; they settle a little rougher).
	var flying := 0
	for b: WreckPhysics.Body in physics.bodies:
		flying += 1 if b.awake else 0
	physics.step(dt, steps if flying <= CROWD else 1)
	if physics.knock_hard > 2.0 and game.clock >= _clink_next:
		_clink_next = game.clock + .2
		var w := _nearest(physics.knock_at)
		if w != null and w.clink != "":
			game.sound_at(w.clink, physics.knock_at.x, physics.knock_at.y, .25)
	_shrink(dt)
	_kick()
	if not wrecks.is_empty():
		# One piece at rest a tick is asked whether it still lies on something.
		_wake_at = (_wake_at + 1) % wrecks.size()
		var asked: Wreck = wrecks[_wake_at]
		if not asked.body.awake and not asked.wedged and physics.unsupported(asked.body):
			# Once until it is knocked again: one wedged against a wall stays.
			asked.wedged = true
			asked.body.wake()


func _watch() -> void:
	var pieces: Breakables = game.features.get("breakables")
	if pieces != null and pieces.net_version != _version:
		_version = pieces.net_version
		for i in pieces.pieces.size():
			var p: Breakables.Piece = pieces.pieces[i]
			if p.broken and not _seen_pieces.has(i):
				_seen_pieces[i] = true
				_break_piece(p)
	var walls: WallBreaks = game.features.get("wall_breaks")
	if walls != null and walls.net_version != _wall_version:
		_wall_version = walls.net_version
		for i in walls.windows.size():
			var face: WallBreaks.WindowFace = walls.windows[i]
			if face.broken and not _seen_windows.has(i):
				_seen_windows[i] = true
				_break_window(walls, face)
		for cell: Vector2i in walls.fences:
			var f: WallBreaks.Fence = walls.fences[cell]
			var was: int = _fence_stage.get(cell, 0)
			if f.stage > was:
				_fence_stage[cell] = f.stage
				_knock_fence(f, was)


func _exploded(x: float, y: float, z: float, _energy: bool) -> void:
	_blasts.append([x, y, z, game.clock])
	while _blasts.size() > 8:
		_blasts.pop_front()


## A recent blast near (x, y): [x, y, z, clock], or [].
func _blast_near(x: float, y: float) -> Array:
	for k in range(_blasts.size() - 1, -1, -1):
		var b: Array = _blasts[k]
		var bx: float = b[0]
		var by: float = b[1]
		var at: float = b[3]
		if game.clock - at <= BLAST_TIME and Vector2(bx - x, by - y).length() < BLAST_NEAR:
			return b
	return []


## Which way a break at (x, y) throws and how hard: away from a blast just
## gone off near it, else along the shot (from this machine's player: looks).
func _knock(x: float, y: float) -> Vector3:
	var blast := _blast_near(x, y)
	if not blast.is_empty():
		var bx: float = blast[0]
		var by: float = blast[1]
		var away := Vector2(x - bx, y - by)
		var d := away.length()
		return Vector3(away.x / maxf(d, .01), away.y / maxf(d, .01), 1.6 if d > .05 else 1.3)
	var p := game.local_player if game.local_player != null else game.player
	if p != null:
		var along := Vector2(x - p.x, y - p.y)
		if along.length() > .05 and along.length() < 30.0:
			along = along.normalized()
			return Vector3(along.x, along.y, 1.0)
	return Vector3(0.0, 0.0, 1.0)


# ------------------------------------------------------------------ breaking


## Where a breakable's pieces come from and how they stand: {key, origin,
## basis (turn), size}, or {} when it has no `pieces`.
func _source(p: Breakables.Piece) -> Dictionary:
	var recipe := str(p.spec.get("pieces", ""))
	if recipe == "":
		return {}
	var foot := Vector3(p.x, p.y, game.world.stand(p) + p.z)
	var plane := NAN
	var face := NAN
	if p.board != null:
		plane = p.board.plane
	elif p.sprite != null:
		plane = p.sprite.plane
		face = p.sprite.face
	var name := _models.name_of(p.image)
	if name != "" and not recipe.begins_with("planks"):
		var turn := PropModels.facing(game.world, p.x, p.y, plane, face)
		return {
			"key": "m:%s|%s" % [name, recipe],
			"origin": foot,
			"basis": Basis(Vector3(0.0, 0.0, 1.0), -turn),
			"size": _models.scale_of(name, p.height),
		}
	# A picture: a board along its plane, else square to this machine's view.
	var axis := Vector3(cos(plane), sin(plane), 0.0)
	if is_nan(plane):
		var eye := game.local_player if game.local_player != null else game.player
		var a := eye.angle if eye != null else 0.0
		axis = Vector3(-sin(a), cos(a), 0.0)
	return {
		"key": "p:%s|%s" % [p.image, recipe],
		"origin": foot,
		"basis": _frame(axis),
		"size": p.height,
	}


## A frame running x along `axis`, z up (and y through, away from its front).
static func _frame(axis: Vector3) -> Basis:
	var up := Vector3(0.0, 0.0, 1.0)
	return Basis(axis, up.cross(axis), up)


func _break_piece(p: Breakables.Piece) -> void:
	var src := _source(p)
	if src.is_empty():
		return
	var knock := _knock(p.x, p.y)
	var is_sign: bool = p.spec.get("sign", false)
	var count: int = p.spec.get("pieces_most", 3 if is_sign else 99)
	var stuff := str(p.spec.get("stuff", "wood"))
	var clink := "glass_settle" if stuff == "glass" or stuff == "clay" else "debris_settle"
	_throw(src, knock, .6 if is_sign else 1.0, count, clink, [])


func _break_window(walls: WallBreaks, face: WallBreaks.WindowFace) -> void:
	var recipe := str(walls.win.get("pieces", ""))
	if recipe == "":
		return
	var a := Vector2(face.edge.x, face.edge.y)
	var b := Vector2(face.edge.z, face.edge.w)
	var along := (b - a).normalized()
	var n := face.normal()
	var mid := face.middle() + n * .03
	var tile := String(game.world.tile_names[face.whole])
	var key := (
		"t:%s@%.2f,1|%s,0.2,0.8,%.2f,%.2f" % [tile, (b - a).length(), recipe, face.low, face.high]
	)
	var src := {
		"key": key,
		"origin": Vector3(mid.x, mid.y, 0.0),
		"basis": _frame(Vector3(along.x, along.y, 0.0)),
		"size": 1.0,
	}
	var knock := _knock(mid.x, mid.y)
	# Glass mostly falls out of its frame toward whoever broke it, or away
	# from the blast.
	var out := n if Vector2(knock.x, knock.y).dot(n) <= 0.0 else -n
	var count: int = walls.win.get("pieces_most", 12)
	_throw(src, Vector3(out.x * .6, out.y * .6, .6), 1.0, count, "glass_settle", [])


## A fence cell shot about (a board or two off the side it was shot from) or
## broken through (its boards and rails out where it stood).
func _knock_fence(f: WallBreaks.Fence, was: int) -> void:
	var recipe := str(f.spec.get("pieces", ""))
	if recipe == "":
		return
	var world := game.world
	var centre := Vector2(f.cell.x + .5, f.cell.y + .5)
	var axis := Vector2(1.0, 0.0) if f.along_x else Vector2(0.0, 1.0)
	var n := Vector2(-axis.y, axis.x)
	var ground := world.ground[f.cell.y * world.width + f.cell.x]
	var tile := String(world.tile_names[f.tile])
	var key := "t:%s@1,%.2f|%s" % [tile, f.top, recipe]
	var knock := _knock(centre.x, centre.y)
	var side := -1.0 if Vector2(knock.x, knock.y).dot(n) > 0.0 else 1.0
	var parts := WreckCuts.parts(game.art, key)
	var all: Array = range(parts.size())
	_shuffle(all)
	var shot_off: int = f.spec.get("pieces_shot", 2)
	if was == 0:
		# Shot about: boards off the face toward whoever shot it.
		var face := centre + n * side * .56
		if physics.solid(Vector3(face.x, face.y, ground + f.top * .5)):
			face = centre - n * side * .56
		var src := {
			"key": key,
			"origin": Vector3(face.x, face.y, ground),
			"basis": _frame(Vector3(axis.x, axis.y, 0.0)),
			"size": 1.0,
		}
		_throw(src, knock, .8, shot_off, "debris_settle", all.slice(0, shot_off))
	if f.stage >= 2:
		var src := {
			"key": key,
			"origin": Vector3(centre.x, centre.y, ground),
			"basis": _frame(Vector3(axis.x, axis.y, 0.0)),
			"size": 1.0,
		}
		var count: int = f.spec.get("pieces_most", 9)
		_throw(src, knock, 1.0, count, "debris_settle", all.slice(shot_off))


func _shuffle(list: Array) -> void:
	for i in range(list.size() - 1, 0, -1):
		var k := dice.randi_range(0, i)
		var t: Variant = list[i]
		list[i] = list[k]
		list[k] = t


## Throw the pieces of `src` (up to `count`, of `only` when given): out from
## the middle, along `knock` (x, y the way, z how hard), spinning.
func _throw(
	src: Dictionary, knock: Vector3, power: float, count: int, clink: String, only: Array
) -> void:
	var key := str(src["key"])
	var parts := WreckCuts.parts(game.art, key)
	if parts.is_empty() or count <= 0:
		return
	var origin: Vector3 = src["origin"]
	var turn: Basis = src["basis"]
	var size: float = src["size"]
	var chosen: Array = only
	if chosen.is_empty():
		chosen = range(parts.size())
		_shuffle(chosen)
	chosen = chosen.slice(0, count)
	var mid := Vector3.ZERO
	for i: int in chosen:
		var part: WreckCuts.Part = parts[i]
		mid += part.centre
	mid = origin + turn * (mid / maxf(1.0, chosen.size()) * size)
	_groups += 1
	var k := power * knock.z
	for i: int in chosen:
		var part: WreckCuts.Part = parts[i]
		var b := WreckPhysics.Body.new()
		b.q = Quaternion(turn * part.basis)
		b.p = origin + turn * (part.centre * size)
		b.shape(part.half * size, dense)
		if physics.solid(b.p):
			continue
		var out := b.p - mid
		out.z = 0.0
		if out.length() < .01:
			out = Vector3(dice.randf_range(-1.0, 1.0), dice.randf_range(-1.0, 1.0), 0.0)
		out = out.normalized()
		b.v = (
			out * dice.randf_range(.4, 1.6) * k
			+ Vector3(knock.x, knock.y, 0.0) * dice.randf_range(.6, 2.0) * k
			+ Vector3(0.0, 0.0, dice.randf_range(.6, 2.2) * k)
		)
		b.w = (
			Vector3(
				dice.randf_range(-1.0, 1.0),
				dice.randf_range(-1.0, 1.0),
				dice.randf_range(-1.0, 1.0)
			)
			* dice.randf_range(3.0, 11.0)
			* minf(k, 1.6)
		)
		b.group = _groups
		b.born = physics.clock
		var w := Wreck.new()
		w.body = b
		w.key = key
		w.index = i
		w.size = size
		w.clink = clink
		w.sprite = View.Sprite.new(b.p.x, b.p.y, "", 1.0, b.p.z)
		w.sprite.solid = "~%s#%d" % [key, i]
		wrecks.append(w)
		physics.bodies.append(b)
	_cap()


## More than `most`: the oldest begin to shrink away; far more, they go now.
func _cap() -> void:
	var live := 0
	for w: Wreck in wrecks:
		if w.fading < 0.0:
			live += 1
	for w: Wreck in wrecks:
		if live <= most:
			break
		if w.fading < 0.0:
			# It shrinks away where it is, costing nothing more.
			w.fading = game.clock
			w.body.awake = false
			w.body.v = Vector3.ZERO
			w.body.w = Vector3.ZERO
			live -= 1
	while wrecks.size() > most + 24:
		var oldest: Wreck = wrecks[0]
		_drop(oldest)


func _drop(w: Wreck) -> void:
	physics.bodies.erase(w.body)
	wrecks.erase(w)


func _shrink(_dt: float) -> void:
	for k in range(wrecks.size() - 1, -1, -1):
		var w: Wreck = wrecks[k]
		if w.fading >= 0.0 and game.clock - w.fading >= fade:
			_drop(w)


func _nearest(at: Vector3) -> Wreck:
	var best: Wreck = null
	var near := 1.0
	for w: Wreck in wrecks:
		var d := w.body.p.distance_to(at)
		if d < near:
			near = d
			best = w
	return best


## A blast's shove (game_combat.gd blast_shoved) throws what lies about.
func _shoved(x: float, y: float, reach: float, power: float) -> void:
	for w: Wreck in wrecks:
		var b := w.body
		if absf(b.p.x - x) > reach or absf(b.p.y - y) > reach:
			continue
		var push := Tumble.shove(x, y, reach, power, b.p.x, b.p.y)
		if push == Vector3.ZERO or not game.world.visible(x, y, b.p.x, b.p.y):
			continue
		var spin := Vector3(
			dice.randf_range(-1.0, 1.0), dice.randf_range(-1.0, 1.0), dice.randf_range(-1.0, 1.0)
		)
		w.wedged = false
		WreckPhysics.knock(b, push * dice.randf_range(.5, 1.0), spin * dice.randf_range(3.0, 9.0))


## This machine's player walking through pieces kicks them along (looks only).
func _kick() -> void:
	var p := game.local_player
	if p == null or wrecks.is_empty():
		return
	var run := Vector2(p.vx, p.vy)
	if run.length() < .8:
		return
	var feet := game.world.stand(p)
	for w: Wreck in wrecks:
		var b := w.body
		if b.p.z > feet + .35 or absf(b.p.x - p.x) > .5 or absf(b.p.y - p.y) > .5:
			continue
		if Vector2(b.p.x - p.x, b.p.y - p.y).length() > .28 + minf(b.reach, .25):
			continue
		if Vector2(b.v.x, b.v.y).length() > run.length() * .5:
			continue
		# A splinter skips off a boot; a table's top hardly moves.
		var light := clampf(.15 / maxf(b.reach, .01), .25, 1.0)
		var spin := Vector3(dice.randf_range(-1.0, 1.0), dice.randf_range(-1.0, 1.0), 0.0)
		w.wedged = false
		WreckPhysics.knock(b, Vector3(run.x * .6, run.y * .6, .9) * light, spin * 4.0 * light)


# ------------------------------------------------------------------ drawing


func sprites() -> Array:
	var out: Array = []
	if not on:
		return out
	for w: Wreck in wrecks:
		var b := w.body
		if not game.in_view(b.p.x, b.p.y, b.reach + .3):
			continue
		var s := w.sprite
		s.x = b.p.x
		s.y = b.p.y
		s.z = b.p.z
		var k := w.size
		if w.fading >= 0.0:
			k *= clampf(1.0 - (game.clock - w.fading) / maxf(.01, fade), 0.0, 1.0)
		s.turn = Basis(b.q) * Basis.from_scale(Vector3.ONE * k)
		out.append(s)
	return out
