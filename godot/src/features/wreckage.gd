## Broken scenery in real pieces of itself: a crate shot apart throws its
## boards snapped on a slant, a barrel its curved staves, split heads and
## sprung hoops, a picnic table its top's planks and its legs, the outhouse
## its walls and roof, a jug or a jar its shards, tin its torn sheets, hay its
## clumps, a sign its splinters; a window's glass comes out in panes and a
## stockyard fence's boards and rails fly. Each piece is cut from the thing's
## own look (wreck_cuts.gd, wreck_fracture.gd: its model's triangles with its
## baked texture, or its picture; its cut faces drawn raw by what it is made
## of), flies as a rigid box (wreck_physics.gd, on the shared core
## phys_core.gd), bounces, slides, piles on the others and on bodies lying
## about (ragdolls, which lie on the pieces in turn) and stays where it comes
## to rest. Fine debris flies with them (splinters, straw, shards, slivers:
## wreck_debris.gd, cheap points, never the solver) and dust puffs up. A
## blast throws what lies about, and a boot kicks it.
##
## No two breaks alike: each kind is cut in several variants (each its own
## fracture, smallest about its own origin), and a break takes the one whose
## origin is nearest where it was struck (a barrel's turned to face the
## hit), thrown by the hit itself: from where it struck, along the shot,
## harder near it, spun by how far off its middle it struck, as hard as the
## hit was (a revolver round chips it open, a load of buckshot at arm's
## length blows it apart, a blast throws it all away from itself). A shot
## that does not break it knocks chips off where it struck.
##
## Looks only: it watches what breakables.gd and wall_breaks.gd broke (their
## pieces, windows and fence cells, as every machine has them) and where the
## shots went (traced, prop_struck, exploded), throws with its own dice, and
## is never carried, saved or in anyone's way. What broke before a save or a
## level's start throws nothing. breakables.cfg [pieces] says how many lie
## about at most (the oldest shrink away first; fewer on a phone) and on
## which maps none fly; each breakable's `pieces` says how it comes apart.
## Pieces asleep cost nothing; the 3D view draws them (view3d/wreck_layer.gd)
## from the sprites this hands it (View.Sprite.solid "~<key>#<piece>", and
## "~~fine" for the debris).
extends GameFeature

const Breakables := preload("res://src/features/breakables.gd")
const WallBreaks := preload("res://src/features/wall_breaks.gd")
const PATH := "res://data/tuning/breakables.cfg"
## How long after a blast a break nearby counts as the blast's (thrown hard,
## away from it), and how near.
const BLAST_TIME := .5
const BLAST_NEAR := 4.5
## A piece gone to sleep this far into a wall shrinks away (_came_to_rest).
const STUCK := .03
## How long after a shot struck near a thing its break counts as that shot's.
const SHOT_TIME := .15
## More awake than this: one physics step a tick.
const CROWD := 20
## What goes under in water (breakables.cfg `stuff`; glass and clay too, by
## their clink); how fast it sinks, how deep before it shrinks away, and how
## fast a floating piece turns as it drifts (radians a second at most).
const SINKS := ["tin", "redtin", "grey", "clay", "glass"]
const SINK_RATE := .25
const SINK_DEEP := .3
const DRIFT_TURN := .25
const Water := preload("res://src/features/water.gd")
const BreakDebris := preload("res://src/features/wreck_burst.gd")
## How a break throws its pieces, when breakables.cfg [launch] does not say.
const LAUNCH := {
	"near": .45,
	"push_far": .8,
	"push_near": 6.0,
	"out_far": .8,
	"out_near": 2.4,
	"up_far": .8,
	"up_near": 2.4,
	"blast_far": 3.0,
	"blast_near": 4.0,
	"blast_up": 2.4,
	"lever": .35,
	"tumble": 4.5,
	"spin_most": 26.0,
	"speed_most": 6.5,
}


## One piece lying about or flying.
class Wreck:
	var body: WreckPhysics.Body
	## The cut it is from (WreckCuts) and which piece of it; drawn this many
	## times its cut size.
	var key := ""
	var index := 0
	var size := 1.0
	## What it is made of and its shape (WreckCuts.Part: the physics keys
	## its bounce, friction and rolling on them).
	var material := "wood"
	var form := "chunk"
	## The sound it makes landing.
	var clink := ""
	var sprite: View.Sprite
	## When it began to shrink away (below 0: it has not).
	var fading := -1.0
	## Woken once for nothing under it since it was last knocked.
	var wedged := false
	## What it is made of goes under in water (glass, clay, tin, stone), and
	## how it lies there: -1 not asked since it came to rest, 0 not on water,
	## 1 floating, 2 sinking.
	var sinks := false
	var floats := -1
	## Asleep when last looked at, and whether it was nudged off its end.
	var asleep := false
	var nudged := false


## How a thing was struck when it broke: where (map), which way the push
## goes, how hard (about .4 a revolver round, 1.3 buckshot at arm's length,
## up to 1.8 a blast near), and the blast's middle when a blast did it.
## `kind` is "shot", "blast" or "knock" (a thrown thing, a car, a swing).
class Impact:
	var at := Vector3.ZERO
	var way := Vector3(1, 0, 0)
	var force := .7
	var kind := "knock"
	var blast := false
	var from := Vector3.ZERO


var physics: WreckPhysics
var wrecks: Array = []
var dice := RandomNumberGenerator.new()
var on := false
## Pieces lying about at most (the oldest shrink away when more come), at
## most one break throws, the small steps a tick, how long one takes to
## shrink away, how heavy a piece is.
var most := 48
var per_break := 28
var steps := 2
var fade := .5
var dense := 500.0
## How a break throws its pieces (breakables.cfg [launch]).
var launch := {}
## The fine debris (wreck_debris.gd) and what makes it (wreck_burst.gd).
var debris := WreckDebris.new()
var burst: BreakDebris
## The impact of the last break thrown (tools/wreck_check.gd reads it).
var last_impact: Impact = null
var last_variant := ""
var last_turn := 0.0
## What has been seen broken: breakables' pieces by index, windows by index,
## each fence cell's stage.
var _seen_pieces := {}
var _seen_windows := {}
var _fence_stage := {}
var _version := -1
var _wall_version := -1
## The set pieces' parts as last seen (features/set_pieces.gd): "<i>:<k>" ->
## its state, so a tank burst throws its staves and a piece landing splinters.
var _set_out := {}
var _set_version := -1
## Blasts lately: [x, y, z, clock]; shots lately that struck a thing:
## [where, from, clock].
var _blasts: Array = []
var _shots: Array = []
var _groups := 0
var _clink_next := 0.0
var _splash_next := 0.0
## The pieces being thrown now are of something that sinks (SINKS).
var _sinking := false
var _wake_at := 0
var _models: PropModels
## The variant each kind broke as last (never twice running).
var _last_variant := {}
var _fine_sprite := View.Sprite.new(-999.0, -999.0, "", 1.0, -999.0)


func id() -> String:
	return "wreckage"


func attach() -> void:
	dice.seed = 1997
	var cfg := Tuning.file(PATH)
	var never: Array = cfg.get_value("pieces", "never", [])
	on = cfg.get_value("pieces", "on", true) and not never.has(game.world.id)
	if not on:
		# None lie about here (a level kept from an earlier game holds none).
		PhysCore.space(game.world).boxes = []
		return
	# A phone, or the LOW physics tier (src/core/quality.gd), takes
	# `most_phone`; below HIGH a tick takes one step fewer (_tick).
	var phone := (
		OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	)
	var few := phone or Quality.level() == Quality.LOW
	most = cfg.get_value("pieces", "most_phone" if few else "most", 48)
	per_break = cfg.get_value("pieces", "per_break_phone" if few else "per_break", 28)
	debris.most = cfg.get_value("pieces", "fine_most_phone" if few else "fine_most", 120)
	steps = cfg.get_value("pieces", "steps", 2)
	fade = cfg.get_value("pieces", "fade", .5)
	dense = cfg.get_value("pieces", "dense", 500.0)
	for key: String in LAUNCH:
		var value: float = cfg.get_value("launch", key, LAUNCH[key])
		launch[key] = value
	physics = WreckPhysics.new(game.world)
	_models = PropModels.new(game.art)
	burst = BreakDebris.new(game, debris, dice)
	_fine_sprite.solid = WreckLayer3D.FINE
	_fine_sprite.who = debris
	_sync()
	# What the level can break is cut in its first frames (WreckCuts.pump,
	# a model's on a worker), not while it loads nor in a fight (a big model
	# takes tens of milliseconds; kept for the next level).
	var pieces: Breakables = game.features.get("breakables")
	if pieces != null:
		var keys: Array = []
		for p: Breakables.Piece in pieces.pieces:
			var src := _source(p)
			if not src.is_empty():
				keys.append(str(src["key"]))
		WreckCuts.prepare(keys)
	tick_with(_tick)
	game.events.exploded.connect(_exploded)
	game.events.blast_shoved.connect(_shoved)
	game.events.traced.connect(_traced)
	game.events.prop_struck.connect(_struck)


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
	_set_out.clear()
	var sets: SetPiecesFeature = game.features.get("set_pieces")
	if sets != null:
		_set_version = sets.net_version
		for i in sets.pieces.size():
			var st: Dictionary = sets.pieces[i]
			var outs: Array = st["out"]
			for k in outs.size():
				_set_out["%d:%d" % [i, k]] = outs[k]


func restore(_state: Dictionary) -> void:
	if not on:
		return
	for w: Wreck in wrecks:
		physics.remove(w.body)
	wrecks.clear()
	debris.bits.clear()
	_sync()


# ------------------------------------------------------------------ watching


func _tick(dt: float) -> void:
	WreckCuts.pump(game.art)
	_watch()
	# Many in the air at once: one step a tick, not `steps` (the cost caps
	# itself; they settle a little rougher).
	var flying := 0
	for b: WreckPhysics.Body in physics.bodies:
		flying += 1 if b.awake else 0
	var n := steps if Quality.level() == Quality.HIGH else maxi(1, steps - 1)
	physics.step(dt, n if flying <= CROWD else 1)
	if physics.knock_hard > 2.0 and game.clock >= _clink_next:
		_clink_next = game.clock + .2
		var w := _nearest(physics.knock_at)
		if w != null and w.clink != "":
			game.sound_at(w.clink, physics.knock_at.x, physics.knock_at.y, .25)
	if physics.knock_hard > 1.2 and game.clock >= _splash_next:
		var at := physics.knock_at
		if Water.splash_if(game, at.x, at.y, at.z, clampf(physics.knock_hard * .25, .5, 1.4)):
			_splash_next = game.clock + .15
	_came_to_rest()
	if not debris.bits.is_empty():
		debris.step(game.world, dt)
	_in_water(dt)
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
	var sets: SetPiecesFeature = game.features.get("set_pieces")
	if sets != null and sets.net_version != _set_version:
		_set_version = sets.net_version
		_watch_sets(sets)


## Pieces that have just gone to sleep: one left with a corner in a wall
## (wedged there in a pile, a thin sheet that skipped) shrinks away rather
## than stay half in it; a thin one left standing on its end with nothing
## leaning it is nudged over once.
func _came_to_rest() -> void:
	for w: Wreck in wrecks:
		var b := w.body
		if b.awake:
			w.asleep = false
			continue
		if w.asleep or w.fading >= 0.0:
			continue
		w.asleep = true
		if physics.inside(b) > STUCK:
			w.fading = game.clock
			continue
		b.turn = Basis(b.q)
		if not w.nudged and not b.propped and WreckPhysics.standing(b):
			w.nudged = true
			var up := 0
			for a in 3:
				if absf(b.turn[a].z) > absf(b.turn[up].z):
					up = a
			var foot := (
				(up + 1) % 3 if b.half[(up + 1) % 3] < b.half[(up + 2) % 3] else (up + 2) % 3
			)
			var over := b.turn[foot]
			over.z = 0.0
			over = over.normalized() * (1.0 if dice.randf() < .5 else -1.0)
			var spin := Vector3(0, 0, 1).cross(over) * 5.0
			WreckPhysics.knock(b, over * .9 + Vector3(0, 0, .6), spin)


## A set piece's tank burst throws its staves, hoops, cap, deck and name
## (the barns' pieces throw only chips: game.burst, cheap; real splinters
## wedged among their rubble cost the wreck physics milliseconds a tick).
func _watch_sets(sets: SetPiecesFeature) -> void:
	for i in sets.pieces.size():
		var st: Dictionary = sets.pieces[i]
		var outs: Array = st["out"]
		var made: Array = sets.shapes[i]
		var lean_row: Array = st["lean"]
		var lean := Vector2(SetPieceShape.f(lean_row[0]), SetPieceShape.f(lean_row[1]))
		for k in outs.size():
			var tag := "%d:%d" % [i, k]
			var now: int = outs[k]
			var was: int = _set_out.get(tag, SetPiecesFeature.UP)
			if now == was:
				continue
			_set_out[tag] = now
			var part: SetPieceShape.Part = made[k]
			var at: Array = sets.pose(i, k, game.clock)
			var c: Vector3 = at[0]
			var q: Quaternion = at[1]
			if now == SetPiecesFeature.GONE and part.tank:
				var src := {"key": part.key, "origin": c, "basis": Basis(q), "size": 1.0}
				_throw(src, Vector3(lean.x, lean.y, 2.2), 1.0, 99, "debris_settle", [])


func _exploded(x: float, y: float, z: float, _energy: bool) -> void:
	_blasts.append([x, y, z, game.clock])
	while _blasts.size() > 8:
		_blasts.pop_front()


## A hitscan shot struck a thing (a breakable, a set piece's part, a prop):
## where, and from where it was fired (the acting player's eye).
func _traced(end: Vector3, struck: String) -> void:
	if struck != "thing":
		return
	var p := game.player
	var from := Vector3(p.x, p.y, p.eye) if p != null else end
	_shots.append([end, from, game.clock])
	while _shots.size() > 24:
		_shots.pop_front()


## A shot that did not break a thing knocks chips off where it struck.
func _struck(image: String, x: float, y: float, _z: float, ax: float, ay: float) -> void:
	var pieces: Breakables = game.features.get("breakables")
	if pieces == null or burst == null:
		return
	for p: Breakables.Piece in pieces.pieces:
		if p.image != image or absf(p.x - x) > .001 or absf(p.y - y) > .001:
			continue
		var hit := _impact(p, Vector3(ax, ay, 0.0))
		burst.chips(p, hit, _material(p))
		return


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


## How a breakable was struck: by a blast just gone off near it (from its
## side facing the blast, away from it, harder the nearer), by the shots that
## struck it this moment (where they struck, along them, harder for more
## pellets and from nearer), else by a knock from this machine's player's
## side (a thrown thing, a car, a swing). `along`: the way the play said it
## went, when known.
func _impact(p: Breakables.Piece, along := Vector3.ZERO) -> Impact:
	var hit := Impact.new()
	var foot: float = game.world.stand(p) + p.z
	var mid := Vector3(p.x, p.y, foot + p.height * .5)
	var blast := _blast_near(p.x, p.y)
	if not blast.is_empty():
		var bx: float = blast[0]
		var by: float = blast[1]
		var bz: float = blast[2]
		var b := Vector3(bx, by, bz)
		var away := mid - b
		away.z = maxf(away.z, .15)
		var d := Vector2(away.x, away.y).length()
		var flat := Vector3(away.x, away.y, 0.0).normalized()
		hit.blast = true
		hit.kind = "blast"
		hit.from = b
		hit.way = away.normalized()
		hit.at = mid - flat * p.radius * .8
		hit.at.z = clampf(b.z, foot + p.height * .15, foot + p.height * .85)
		hit.force = 1.8 * clampf(1.15 - d / BLAST_NEAR, .45, 1.0)
		return hit
	var ends := Vector3.ZERO
	var count := 0
	var from := Vector3.ZERO
	for k in range(_shots.size() - 1, -1, -1):
		var s: Array = _shots[k]
		var when: float = s[2]
		if game.clock - when > SHOT_TIME:
			break
		var end: Vector3 = s[0]
		if Vector2(end.x - p.x, end.y - p.y).length() > p.radius + .35:
			continue
		if end.z < foot - .1 or end.z > foot + p.height + .1:
			continue
		ends += end
		from = s[1]
		count += 1
	if count > 0:
		hit.at = ends / count
		hit.kind = "shot"
		hit.from = from
		var way := hit.at - from
		var far := Vector2(way.x, way.y).length()
		hit.way = way.normalized()
		var pellets := .36 + .16 * (count - 1) + (.15 if count > 1 else 0.0)
		hit.force = clampf(pellets * clampf(1.35 - far / 9.0, .7, 1.35), .3, 1.55)
		return hit
	var eye := game.local_player if game.local_player != null else game.player
	var toward := Vector3(along.x, along.y, 0.0)
	if toward.length() < .01 and eye != null:
		toward = Vector3(p.x - eye.x, p.y - eye.y, 0.0)
	if toward.length() < .01:
		toward = Vector3(1, 0, 0)
	toward = toward.normalized()
	hit.way = toward
	hit.at = mid - toward * p.radius * .8
	hit.force = .7
	return hit


# ------------------------------------------------------------------ breaking


## What a breakable's pieces are made of (breakables.cfg `stuff`).
func _material(p: Breakables.Piece) -> String:
	return WreckFracture.material_of(str(p.spec.get("stuff", "wood")))


## Where a breakable's pieces come from and how they stand: {key, origin,
## basis (turn), size}, or {} when it has no `pieces`.
func _source(p: Breakables.Piece) -> Dictionary:
	var recipe := str(p.spec.get("pieces", ""))
	if recipe == "":
		return {}
	var stuff := str(p.spec.get("stuff", "wood"))
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
			"key": "m:%s|%s~%s" % [name, recipe, stuff],
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
		"key": "p:%s|%s~%s" % [p.image, recipe, stuff],
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
	var sets: SetPiecesFeature = game.features.get("set_pieces")
	if sets != null and sets.rubble_at(p.x, p.y):
		# Broken in a barn come down (set_pieces.gd): flattened under its tin,
		# no real pieces wedged in the rubble (they cost the physics
		# milliseconds a tick there); its bits and chips fly as ever.
		return
	var hit := _impact(p)
	last_impact = hit
	var material := _material(p)
	var is_sign: bool = p.spec.get("sign", false)
	var count: int = p.spec.get("pieces_most", 4 if is_sign else per_break)
	var stuff := str(p.spec.get("stuff", "wood"))
	var clink := _clink_of(material)
	_sinking = SINKS.has(stuff)
	_burst_apart(src, hit, mini(count, per_break), clink, .7 if is_sign else 1.0)
	_sinking = false
	burst.broke(p, hit, material)


## The sound a piece of `material` makes landing.
static func _clink_of(material: String) -> String:
	match material:
		"glass", "clay":
			return "glass_settle"
		"tin", "iron":
			return "can_kick"
		"straw", "stuffing":
			return ""
	return "debris_settle"


## The variant of `key` a hit at `local` (in its source's frame) breaks as,
## and how far it is turned about its upright (a round thing turns its
## origin to the hit): [variant key, turn]. Variants not cut yet are passed
## over while any is (a key is cut there and then only when none is).
func _variant(key: String, local: Vector3) -> Array:
	var count := WreckCuts.variants(key)
	var ready: Array[int] = []
	for v in count:
		var named := key if v == 0 else "%s^%d" % [key, v]
		if WreckCuts.has(named):
			ready.append(v)
	if ready.is_empty():
		ready.append(0)
	elif ready.size() < count and not OS.has_feature("threads"):
		# No worker (the lite browser build): each break of a kind cuts the
		# next variant there and then, till it has them all (WreckCuts.LITE).
		ready.append(ready.size())
	var round := WreckCuts.round_about(key)
	var scored: Array = []
	for v: int in ready:
		var named := key if v == 0 else "%s^%d" % [key, v]
		WreckCuts.parts(game.art, named)
		var o := WreckCuts.origin(named)
		var d := o.distance_to(local)
		if round:
			d = absf(o.z - local.z) + dice.randf() * .2
		scored.append([d, v, named, o])
	scored.sort_custom(_nearer)
	# The nearest two or three, never the one this kind broke as last time
	# (two barrels shot alike still come apart differently).
	var near := scored.slice(0, 3)
	var last: int = _last_variant.get(key, -1)
	if near.size() > 1:
		for k in near.size():
			var row: Array = near[k]
			var v: int = row[1]
			if v == last:
				near.remove_at(k)
				break
	var pick: Array = near[0]
	if near.size() > 1 and dice.randf() < .4:
		pick = near[1]
	_last_variant[key] = pick[1]
	var turn := 0.0
	if round:
		var o: Vector3 = pick[3]
		turn = atan2(local.y, local.x) - atan2(o.y, o.x)
	return [pick[2], turn]


static func _nearer(a: Array, b: Array) -> bool:
	var da: float = a[0]
	var db: float = b[0]
	return da < db


## (Merging onto the shared solver: each piece goes in by WreckPhysics.add
## from _add, and the throw is WreckPhysics.impact(hit.at, hit.way, its
## strength from hit.force, hit.kind, the group, dice): _launch's numbers
## are breakables.cfg [launch].)
## A broken thing's pieces thrown by the hit: the variant whose fracture is
## nearest the hit (turned to it when round), up to `count` pieces (the
## biggest), each thrown from where the hit struck, along it, harder near it
## and spun by how far off its middle the push went.
func _burst_apart(src: Dictionary, hit: Impact, count: int, clink: String, power: float) -> void:
	var origin: Vector3 = src["origin"]
	var turn: Basis = src["basis"]
	var size: float = src["size"]
	var local := turn.transposed() * (hit.at - origin) / maxf(size, .01)
	var picked := _variant(str(src["key"]), local)
	var key: String = picked[0]
	last_variant = key
	var about: float = picked[1]
	last_turn = about
	var spin_about := Basis(Vector3(0, 0, 1), about)
	var parts := WreckCuts.parts(game.art, key)
	if parts.is_empty() or count <= 0:
		return
	var chosen: Array = range(parts.size())
	if chosen.size() > count:
		# The biggest go: the smallest are left to the fine debris.
		chosen.sort_custom(
			func(a: int, b: int) -> bool:
				var pa: WreckCuts.Part = parts[a]
				var pb: WreckCuts.Part = parts[b]
				return pa.half.x * pa.half.y * pa.half.z > pb.half.x * pb.half.y * pb.half.z
		)
		chosen = chosen.slice(0, count)
	var mid := Vector3.ZERO
	for i: int in chosen:
		var part: WreckCuts.Part = parts[i]
		mid += part.centre
	mid = origin + turn * (spin_about * (mid / maxf(1.0, chosen.size())) * size)
	_groups += 1
	var f := hit.force * power
	for i: int in chosen:
		var part: WreckCuts.Part = parts[i]
		var b := WreckPhysics.Body.new()
		b.q = Quaternion(turn * spin_about * part.basis)
		b.p = origin + turn * (spin_about * part.centre * size)
		b.shape(part.half * size, dense)
		if physics.solid(b.p) or _walled(b):
			continue
		_launch(b, hit, mid, f, size)
		b.group = _groups
		b.born = physics.clock
		_add(b, key, i, size, part, clink)
	_cap()


## A piece's throw by the hit (strength `f`): from where it struck, along it
## (a blast: away from its middle), harder the nearer (breakables.cfg
## [launch]: full within `near` of a thing's size, falling off past it), out
## from the break's middle `mid`, up, and spun by how far off the piece's
## middle the push went (a stave struck near its end cartwheels).
func _launch(b: WreckPhysics.Body, hit: Impact, mid: Vector3, f: float, size: float) -> void:
	var near_k: float = launch["near"]
	var r := b.p - hit.at
	var dist := r.length()
	var reach := near_k * maxf(size, .5)
	var near := 1.0 / (1.0 + (dist / reach) * (dist / reach))
	var out := b.p - mid
	out.z = 0.0
	if out.length() < .01:
		out = Vector3(dice.randf_range(-1.0, 1.0), dice.randf_range(-1.0, 1.0), 0.0)
	out = out.normalized()
	var push: Vector3
	if hit.blast:
		var far_k: float = launch["blast_far"]
		var close_k: float = launch["blast_near"]
		var up_k: float = launch["blast_up"]
		var away := (b.p - hit.from).normalized()
		push = away * f * (far_k + close_k * near) * dice.randf_range(.75, 1.2)
		push.z += f * up_k * dice.randf_range(.6, 1.3)
	else:
		var push_far: float = launch["push_far"]
		var push_near: float = launch["push_near"]
		var out_far: float = launch["out_far"]
		var out_near: float = launch["out_near"]
		var up_far: float = launch["up_far"]
		var up_near: float = launch["up_near"]
		# Little comes back at the shooter: out from the middle toward them
		# counts a third.
		if out.dot(Vector3(hit.way.x, hit.way.y, 0.0)) < 0.0:
			out *= .35
		push = (
			hit.way * f * (push_far + push_near * near) * dice.randf_range(.7, 1.2)
			+ out * f * (out_far + out_near * near) * dice.randf_range(.6, 1.3)
		)
		push.z = maxf(push.z, 0.0) + f * (up_far + up_near * near) * dice.randf_range(.5, 1.2)
	var fastest: float = launch["speed_most"]
	if push.length() > fastest:
		push = push.normalized() * fastest
	b.v = push
	var lever_k: float = launch["lever"]
	var tumble_k: float = launch["tumble"]
	var most: float = launch["spin_most"]
	var lever := r.cross(push) / maxf(dist * dist, .03) * lever_k
	var tumble := Vector3(
		dice.randf_range(-1.0, 1.0), dice.randf_range(-1.0, 1.0), dice.randf_range(-1.0, 1.0)
	)
	b.w = lever + tumble * tumble_k * dice.randf_range(.45, 1.5) * minf(f, 1.6)
	if b.w.length() > most:
		b.w = b.w.normalized() * most


## Whether a piece would start with more than two of its corners in a wall
## or furniture (a long bench by a fence): left out, never pushed out of it.
func _walled(b: WreckPhysics.Body) -> bool:
	var turn := Basis(b.q)
	var inside := 0
	for k in 8:
		var c := Vector3(
			b.half.x * (1.0 if k & 1 else -1.0),
			b.half.y * (1.0 if k & 2 else -1.0),
			b.half.z * (1.0 if k & 4 else -1.0)
		)
		if physics.solid(b.p + turn * c):
			inside += 1
			if inside > 2:
				return true
	return false


## A piece thrown: kept, its sprite made, its body handed to the physics
## with what it is made of and its shape (the physics' `stuff` and `form`,
## set by name: a solver that knows them keys its bounce, grip and rolling
## on them, one that does not treats the piece as a plain box).
func _add(
	b: WreckPhysics.Body, key: String, i: int, size: float, part: WreckCuts.Part, clink: String
) -> void:
	var w := Wreck.new()
	w.body = b
	w.key = key
	w.index = i
	w.size = size
	w.material = part.material
	w.form = part.form
	b.set("stuff", part.material)
	b.set("form", part.form)
	w.clink = clink
	w.sinks = _sinking or clink == "glass_settle"
	w.sprite = View.Sprite.new(b.p.x, b.p.y, "", 1.0, b.p.z)
	w.sprite.solid = "~%s#%d" % [key, i]
	wrecks.append(w)
	physics.bodies.append(b)


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
## the middle, along `knock` (x, y the way, z how hard), spinning. (Windows,
## fences and a set piece's tank: a break of a breakable is _burst_apart's.)
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
		_add(b, key, i, size, part, clink)
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
	physics.remove(w.body)
	wrecks.erase(w)


## Pieces lying still on water: wood (and anything light) floats, drifting
## on the level's current (Water.current) and turning slowly, never onto the
## bank or into a wall; glass, clay, tin and stone sink under the surface and
## shrink away. Asleep all the while (a drifting piece costs a cell's look).
func _in_water(dt: float) -> void:
	var flow := Water.current(game.level.id)
	var world := game.world
	for w: Wreck in wrecks:
		var b := w.body
		if b.awake:
			w.floats = -1
			continue
		if w.fading >= 0.0:
			continue
		if w.floats < 0:
			# Asked once each time it comes to rest: all of it on the water.
			w.floats = 2 if w.sinks else 1
			var lying := Basis(b.q)
			for k in 8:
				var c := b.p + lying * b.points[k]
				if not BayouBrains.wet_at(world, c.x, c.y):
					w.floats = 0
					break
		if w.floats == 2:
			b.p.z -= SINK_RATE * dt
			if world.floor_under(b.p.x, b.p.y, 99.0) - b.p.z > SINK_DEEP:
				w.fading = game.clock
			continue
		if w.floats != 1 or flow == Vector2.ZERO:
			continue
		var phase := float(w.index) * 1.7 + b.p.x * .3
		var way := flow * (1.0 + .4 * sin(game.clock * .41 + phase)) * dt
		var was := b.p
		var was_q := b.q
		b.p += Vector3(way.x, way.y, 0.0)
		b.q = (Quaternion(Vector3(0.0, 0.0, 1.0), DRIFT_TURN * dt * sin(phase)) * b.q).normalized()
		# Every corner still over the water, none in the bank or a wall.
		var turn := Basis(b.q)
		var clear := true
		for k in 8:
			var c := b.p + turn * b.points[k]
			if not BayouBrains.wet_at(world, c.x, c.y):
				clear = false
				break
		if not clear or physics.inside(b) > .005:
			b.p = was
			b.q = was_q


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
	if not debris.bits.is_empty():
		out.append(_fine_sprite)
	return out
