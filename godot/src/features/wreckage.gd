## Broken scenery in real pieces of itself: a crate shot apart throws its
## boards snapped on a slant, a barrel its curved staves, split heads and
## sprung hoops, a picnic table its top's planks and its legs, the outhouse
## its walls and roof, a jug or a jar its shards, tin its torn sheets, hay
## its flakes, a sign its splinters; a window's glass comes out in panes and a
## stockyard fence's boards and rails fly. Each piece is cut from the thing's
## own look (wreck_cuts.gd, wreck_fracture.gd: its model's triangles with its
## baked texture, or its picture; its cut faces drawn raw by what it is made
## of), each kind in several seeded variants: a break takes the one whose
## fracture is nearest where it was struck (a barrel's turned to face the
## hit), never the one that kind broke as last. Fine debris flies with them
## (wreck_debris.gd, features/wreck_burst.gd: splinters, shards, straw, never
## the solver), dust puffs up and a shot that does not break a thing chips
## it. Each piece flies as a rigid box (wreck_physics.gd, on the shared core
## phys_core.gd), bounces, slides, piles on the others and on bodies lying
## about (ragdolls, which lie on the pieces in turn) and stays where it comes
## to rest. How it flies comes from the hit that broke
## it (the shot's pellets where they struck, the blast where it went off:
## WreckPhysics.impact), so no two breaks come apart the same. A shot
## striking a piece lying about knocks it at the hit point; a blast throws
## what lies about by how near; players, the county's hands, BLUE the hound
## and the vehicles kick and shove pieces walking and driving through; each
## knock is heard by what the piece is made of (data/tuning/wreck.cfg).
##
## Looks only: it watches what breakables.gd and wall_breaks.gd broke (their
## pieces, windows and fence cells, as every machine has them), throws with its
## own dice, and is never carried, saved or in anyone's way. What broke before
## a save or a level's start throws nothing. breakables.cfg [pieces] says how
## many lie about at most (the oldest shrink away first; fewer on a phone) and
## on which maps none fly; each breakable's `pieces` says how it comes apart.
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
## More awake than this: one physics step a tick.
const CROWD := 20
## How fast a piece that sinks (wreck.cfg `sinks`) goes under, how deep
## before it shrinks away, and how fast a floating piece turns as it drifts
## (radians a second at most).
const SINK_RATE := .25
const SINK_DEEP := .3
const DRIFT_TURN := .25
const Water := preload("res://src/features/water.gd")
const Hound := preload("res://src/features/hound.gd")
## Shots this long ago or less count as the hit that broke a thing (their
## end points within the thing's reach plus SHOT_NEAR), and how hard a break
## with no shot or blast known is knocked (a speed: impact "break").
const SHOT_TIME := .15
const SHOT_NEAR := .35
const BREAK_PUSH := 2.4
const BLAST_PUSH := 7.0
## How fast a break's pieces part from its middle (times the stuff's burst).
const PART := 1.1
## A walker kicks a piece within its radius plus this, under its knees.
## Wakings where it lies before a restless piece is laid down (_restless).
const WAKES := 6
const KICK_REACH := .12
## Hands kick pieces only this near this machine's player (cells, across
## plus along), each piece at most once in KICK_AGAIN seconds.
const KICK_SEEN := 14.0
const KICK_AGAIN := 1.0
const KNEES := .45
## A breakable's fine debris, dust, second sound and chips.
const BreakDebris := preload("res://src/features/wreck_burst.gd")


## One piece lying about or flying.
class Wreck:
	var body: WreckPhysics.Body
	## The cut it is from (WreckCuts) and which piece of it; drawn this many
	## times its cut size.
	var key := ""
	var index := 0
	var size := 1.0
	var sprite: View.Sprite
	## When it began to shrink away (below 0: it has not).
	var fading := -1.0
	## Woken once for nothing under it since it was last knocked.
	var wedged := false
	## What it is made of goes under in water (wreck.cfg `sinks`), and how it
	## lies there: -1 not asked since it came to rest, 0 not on water,
	## 1 floating, 2 sinking.
	var sinks := false
	var floats := -1
	## Drawn through this shape about its middle (a shard cut fresh, a plank
	## broken to its length: features/wall_looks.gd), turned by its body.
	var shape := Basis.IDENTITY
	## Glass that breaks again where it lands (_glass_lands): its triangle
	## (three corners in its own x, z about its middle), how many times it has
	## broken, and how fast it was falling last tick.
	var tri := PackedVector2Array()
	var breaks := 0
	var fell := 0.0
	## The settle cue a wall piece was thrown with (wall_looks: a shard broken
	## again keeps its glass); sounds otherwise come from the body's stuff.
	var clink := ""
	## Asleep when last looked at, and how often it has woken since it was
	## thrown or last knocked (_restless).
	var asleep := false
	var wakes := 0
	## When a hand last kicked it (_walker).
	var kicked := -9.0


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
## Pieces lying about at most (the oldest shrink away when more come), the
## small steps a tick, how long one takes to shrink away, how heavy a piece is.
var most := 48
## Pieces one breakable's break throws at most (the biggest).
var per_break := 18
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
## The set pieces' parts as last seen (features/set_pieces.gd): "<i>:<k>" ->
## its state, so a tank burst throws its staves and a piece landing splinters.
var _set_out := {}
var _set_version := -1
## Blasts lately: [x, y, z, clock].
var _blasts: Array = []
var _groups := 0
var _splash_next := 0.0
## Knock sounds heard in the last second (clocks), for wreck.cfg's
## [knock] sounds_most.
var _heard := PackedFloat64Array()
## Recent hitscan shots: [from, to, clock, damage].
var _shots: Array = []
## Where walkers stood last tick (instance id -> Vector3), for their kicks.
var _walked := {}
var _wake_at := 0
var _models: PropModels
## The big breaks coming apart in their own pieces (src/set_piece_wreck.gd):
## null where the level has none.
var ruin: SetPieceWreck
## The fine debris (wreck_debris.gd) and what makes it (wreck_burst.gd).
var debris := WreckDebris.new()
var burst: BreakDebris
## The last breakable's break: how it was struck, the variant it broke as and
## how far that was turned (tools/wreck_check.gd reads them).
var last_impact: Impact = null
var last_variant := ""
var last_turn := 0.0
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
	per_break = cfg.get_value("pieces", "per_break_phone" if few else "per_break", 18)
	if game.world.id.begins_with("county_"):
		# County Run is one long fight: things break one on another.
		var busy: int = cfg.get_value("pieces", "per_break_county", 10)
		per_break = mini(per_break, busy)
	debris.most = cfg.get_value("pieces", "fine_most_phone" if few else "fine_most", 80)
	steps = cfg.get_value("pieces", "steps", 2)
	fade = cfg.get_value("pieces", "fade", .5)
	dense = cfg.get_value("pieces", "dense", 500.0)
	physics = WreckPhysics.new(game.world)
	_models = PropModels.new(game.art)
	burst = BreakDebris.new(game, debris, dice)
	_fine_sprite.solid = WreckLayer3D.FINE
	_fine_sprite.who = debris
	var sets: SetPiecesFeature = game.features.get("set_pieces")
	if sets != null and not sets.pieces.is_empty():
		ruin = SetPieceWreck.new(game)
		ruin.blasts = _blasts
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
	if ruin != null:
		ruin.sync()


## The set pieces put on from a snapshot (set_pieces.gd restore, for a late
## joiner's copy or one put back): what is down lies in its pieces at once
## and nothing lands or bursts again, as after a load; the rest stays.
func sync_sets() -> void:
	if not on:
		return
	var sets: SetPiecesFeature = game.features.get("set_pieces")
	if sets == null:
		return
	_set_version = sets.net_version
	for i in sets.pieces.size():
		var st: Dictionary = sets.pieces[i]
		var outs: Array = st["out"]
		for k in outs.size():
			_set_out["%d:%d" % [i, k]] = outs[k]
	if ruin != null:
		ruin.sync()


## Gone with its game: the set pieces' workers waited for, nothing pointing
## back at the game.
func detach() -> void:
	if ruin != null:
		ruin.close()
		ruin = null
	super()


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
	# A kind's further variants are cut only while nothing flies.
	WreckCuts.pump(game.art, not physics.moving())
	_watch()
	# Many in the air at once: one step a tick, not `steps` (the cost caps
	# itself; they settle a little rougher).
	var flying := 0
	for b: WreckPhysics.Body in physics.bodies:
		flying += 1 if b.awake else 0
	var n := steps if Quality.level() == Quality.HIGH else maxi(1, steps - 1)
	physics.step(dt, n if flying <= CROWD else 1)
	if flying > 0:
		_sounds()
	if physics.knock_hard > 1.2 and game.clock >= _splash_next:
		var at := physics.knock_at
		if Water.splash_if(game, at.x, at.y, at.z, clampf(physics.knock_hard * .25, .5, 1.4)):
			_splash_next = game.clock + .15
	if ruin != null and ruin.busy():
		ruin.tick(dt)
	if not debris.bits.is_empty():
		debris.step(game.world, dt)
	_restless()
	_in_water(dt)
	_glass_lands()
	_unstick()
	_shrink(dt)
	_kick(dt)
	if not wrecks.is_empty():
		# One piece at rest a tick is asked whether it still lies on something.
		_wake_at = (_wake_at + 1) % wrecks.size()
		var asked: Wreck = wrecks[_wake_at]
		if not asked.body.awake and not asked.wedged and physics.unsupported(asked.body):
			# Once until it is knocked again: one wedged against a wall stays.
			asked.wedged = true
			asked.body.wake()
		elif physics.topples(asked.body):
			# Left standing on its end when what it leaned on went: over it goes.
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
		if ruin != null:
			ruin.watch(sets)
		_watch_sets(sets)


## A set piece's tank burst throws its staves (those not torn out in the fall
## already), its cap and its name as real pieces; its hoops, its deck and the
## barns come apart in SetPieceWreck's own scripted pieces (real pieces
## wedged among the rubble's volumes cost the wreck physics milliseconds a
## tick).
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
				if ruin != null and part.role in ["hoop", "deck"]:
					continue
				var src := {"key": part.key, "origin": c, "basis": Basis(q), "size": 1.0}
				var only: Array = []
				if ruin != null and part.role == "tank":
					var gone := ruin.flown(i, k)
					for n in WreckCuts.parts(game.art, part.key).size():
						if not gone.has(n):
							only.append(n)
				# Burst where it struck the ground, along its fall.
				var way := Vector3(lean.x, lean.y, 0.0).normalized()
				var hit := [c - way * .4, (way + Vector3(0.0, 0.0, .5)).normalized(), 6.0, "break"]
				_throw(src, Vector3(lean.x, lean.y, 2.2), 1.0, 99, "", only, "wood", [hit])


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
	var knock := _knock(p.x, p.y)
	var is_sign: bool = p.spec.get("sign", false)
	var count: int = p.spec.get("pieces_most", 4 if is_sign else per_break)
	var foot: Vector3 = src["origin"]
	var hits := _hits_for(foot, p.radius, p.height, knock)
	var hit := _impact_of(p, hits)
	last_impact = hit
	src["stuff"] = str(p.spec.get("stuff", "wood"))
	# Many already in the air (a fight's breaks one on another): this one
	# throws half as many (the biggest still).
	var flying := 0
	for b: WreckPhysics.Body in physics.bodies:
		flying += 1 if b.awake else 0
	var most_now := per_break if flying < CROWD / 2 else maxi(4, per_break / 2)
	_burst_apart(src, hit, hits, mini(count, most_now), .7 if is_sign else 1.0)
	burst.broke(p, hit, _material(p))


## What a breakable's pieces are made of (breakables.cfg `stuff`, as the
## cut's raw faces name it).
func _material(p: Breakables.Piece) -> String:
	return WreckFracture.material_of(str(p.spec.get("stuff", "wood")))


## How a breakable was struck, from the hits that broke it (_hits_for): where
## (the pellets' mean, the side facing a blast), which way, how hard (their
## strengths together over BREAK_PUSH: about .4 a revolver round, 1.3 buckshot
## at arm's length, up to 1.8 a blast near), else (a thrown thing, a car, a
## swing, a client's mirror) its side facing this machine's player, .7.
## Picks the variant and throws the debris; the pieces themselves are
## knocked by `hits` (WreckPhysics.impact).
func _impact_of(p: Breakables.Piece, hits: Array, along := Vector3.ZERO) -> Impact:
	var hit := Impact.new()
	var foot: float = game.world.stand(p) + p.z
	var mid := Vector3(p.x, p.y, foot + p.height * .5)
	var first: Array = hits[0] if not hits.is_empty() else []
	if not first.is_empty() and str(first[3]) == "blast":
		var b: Vector3 = first[0]
		var away := mid - b
		away.z = maxf(away.z, .15)
		var flat := Vector3(away.x, away.y, 0.0).normalized()
		hit.blast = true
		hit.kind = "blast"
		hit.from = b
		hit.way = away.normalized()
		hit.at = mid - flat * p.radius * .8
		hit.at.z = clampf(b.z, foot + p.height * .15, foot + p.height * .85)
		hit.force = 1.8 * clampf(1.15 - Vector2(away.x, away.y).length() / BLAST_NEAR, .45, 1.0)
		return hit
	if not hits.is_empty():
		var at := Vector3.ZERO
		var way := Vector3.ZERO
		var total := 0.0
		for row: Array in hits:
			var a: Vector3 = row[0]
			var w: Vector3 = row[1]
			var strength: float = row[2]
			at += a
			way += w
			total += strength
		hit.at = at / hits.size()
		hit.way = way.normalized() if way.length() > .01 else Vector3(1, 0, 0)
		hit.kind = "shot"
		hit.force = clampf(total / BREAK_PUSH, .3, 1.6)
		return hit
	var eye := game.local_player if game.local_player != null else game.player
	var toward := Vector3(along.x, along.y, 0.0)
	if toward.length() < .01 and eye != null:
		toward = Vector3(p.x - eye.x, p.y - eye.y, 0.0)
	if toward.length() < .01:
		toward = Vector3(1, 0, 0)
	hit.way = toward.normalized()
	hit.at = mid - hit.way * p.radius * .8
	hit.force = .7
	return hit


## A shot that did not break a thing knocks chips off where it struck.
func _struck(image: String, x: float, y: float, _z: float, ax: float, ay: float) -> void:
	var pieces: Breakables = game.features.get("breakables")
	if pieces == null or burst == null:
		return
	for p: Breakables.Piece in pieces.pieces:
		if p.image != image or absf(p.x - x) > .001 or absf(p.y - y) > .001:
			continue
		var foot := Vector3(p.x, p.y, game.world.stand(p) + p.z)
		var along := Vector3(ax, ay, 0.0)
		var hit := _impact_of(p, _hits_for(foot, p.radius, p.height, along), along)
		burst.chips(p, hit, _material(p))
		return


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
		# Round its sides first, its height a third as much.
		var d := Vector2(o.x - local.x, o.y - local.y).length() + absf(o.z - local.z) * .35
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


## A broken thing's pieces: the variant whose fracture is nearest the hit
## (turned to it when round), up to `count` of them (the biggest), each a body
## of the physics made of the thing's stuff (a hoop iron) in its cut's form
## (_throw's way), parted from the middle and knocked by `hits` (the pellets
## that broke it, the blast: WreckPhysics.impact), or with none by `hit`.
func _burst_apart(src: Dictionary, hit: Impact, hits: Array, count: int, power: float) -> void:
	var origin: Vector3 = src["origin"]
	var turn: Basis = src["basis"]
	var size: float = src["size"]
	var stuff := str(src.get("stuff", "wood"))
	var local := turn.transposed() * (hit.at - origin) / maxf(size, .01)
	var picked := _variant(str(src["key"]), local)
	var key: String = picked[0]
	last_variant = key
	# Broken: two more of its variants to be cut in a quiet moment.
	WreckCuts.more(key)
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
	for i: int in chosen:
		var part: WreckCuts.Part = parts[i]
		var at := origin + turn * (spin_about * part.centre * size)
		var q := Quaternion((turn * spin_about * part.basis).orthonormalized())
		if physics.solid(at) or _walled(at, q, part.half * size):
			continue
		var made_of := part.material if part.material == "iron" else stuff
		var b := physics.add(at, q, part.half * size, made_of, part.form, _groups)
		var w := Wreck.new()
		w.body = b
		w.key = key
		w.index = i
		w.size = size
		w.sinks = WreckPhysics.stuff_of(made_of).sinks
		w.sprite = View.Sprite.new(b.p.x, b.p.y, "", 1.0, b.p.z)
		w.sprite.solid = "~%s#%d" % [key, i]
		wrecks.append(w)
	physics.burst(_groups, mid, PART * power, dice)
	var knocks := hits
	if knocks.is_empty():
		if hit.blast:
			knocks = [[hit.from, Vector3.ZERO, BLAST_PUSH * hit.force / 1.8, "blast"]]
		else:
			knocks = [[hit.at, hit.way, BREAK_PUSH * hit.force / .7, "break"]]
	for row: Array in knocks:
		var at: Vector3 = row[0]
		var way: Vector3 = row[1]
		var strength: float = row[2]
		physics.impact(at, way, strength * power, str(row[3]), _groups, dice)
	_cap()


## Whether a piece would start with more than two of its corners in a wall
## or furniture (a long bench by a fence): left out, never pushed out of it.
func _walled(at: Vector3, q: Quaternion, half: Vector3) -> bool:
	var turn := Basis(q)
	var inside := 0
	for k in 8:
		var c := Vector3(
			half.x * (1.0 if k & 1 else -1.0),
			half.y * (1.0 if k & 2 else -1.0),
			half.z * (1.0 if k & 4 else -1.0)
		)
		if physics.solid(at + turn * c):
			inside += 1
			if inside > 2:
				return true
	return false


func _break_window(walls: WallBreaks, face: WallBreaks.WindowFace) -> void:
	# Its glass cut fresh from where it was struck, when it leaves its frame
	# (features/wall_looks.gd watches the windows itself).
	if game.features.get("wall_looks") != null:
		return
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
	var glass := Vector3(mid.x, mid.y, (face.low + face.high) * .5)
	var hits := _hits_for(glass - Vector3(0.0, 0.0, .5), .6, 1.0, Vector3(-out.x, -out.y, .6))
	_throw(src, Vector3(out.x * .6, out.y * .6, .6), 1.0, count, "", [], "glass", hits)


## A fence cell shot about (a board or two off the side it was shot from) or
## broken through (its boards and rails out where it stood).
func _knock_fence(f: WallBreaks.Fence, was: int) -> void:
	# Its boards go as they were shot out, and burst out along the shot or
	# the blast when it goes through (features/wall_looks.gd).
	var looks: WallLooks = game.features.get("wall_looks")
	if looks != null:
		looks.fence_staged(f, was)
		return
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
		# Knocked off the face it was shot on, back toward the shot (not
		# through the fence that stands behind them).
		var at := Vector3(face.x, face.y, ground)
		var back := Vector3(-knock.x, -knock.y, knock.z)
		var hits := _hits_for(at, .5, f.top, back)
		for hit: Array in hits:
			var way: Vector3 = hit[1]
			hit[1] = Vector3(-way.x, -way.y, absf(way.z))
		_throw(src, back, .8, shot_off, "", all.slice(0, shot_off), "wood", hits)
	if f.stage >= 2:
		var src := {
			"key": key,
			"origin": Vector3(centre.x, centre.y, ground),
			"basis": _frame(Vector3(axis.x, axis.y, 0.0)),
			"size": 1.0,
		}
		var count: int = f.spec.get("pieces_most", 9)
		var at := Vector3(centre.x, centre.y, ground)
		# Out through the gap across the fence's line (its boards are longer
		# than the gap is wide: along the line they would wedge in the posts).
		var across := n * (1.0 if Vector2(knock.x, knock.y).dot(n) >= 0.0 else -1.0)
		var through := Vector3(across.x, across.y, knock.z)
		var hits := _hits_for(at, .6, f.top, through)
		for hit: Array in hits:
			var way: Vector3 = hit[1]
			var flat := Vector2(way.x, way.y).length()
			hit[1] = Vector3(across.x * flat, across.y * flat, way.z)
		_throw(src, through, 1.0, count, "", all.slice(shot_off), "wood", hits)


func _shuffle(list: Array) -> void:
	for i in range(list.size() - 1, 0, -1):
		var k := dice.randi_range(0, i)
		var t: Variant = list[i]
		list[i] = list[k]
		list[k] = t


## Throw the pieces of `src` (up to `count`, of `only` when given), made of
## `stuff`: each piece a body of the physics with its stuff and its cut's
## form, parted from the middle, then knocked by each of `hits` ([at, way,
## strength, kind]: the pellets that broke it, the blast; WreckPhysics.impact)
## or, with none, from its near side along `knock` (x, y the way, z how hard).
## (`_clink` is left from before: the stuff says how it sounds.)
func _throw(
	src: Dictionary,
	knock: Vector3,
	power: float,
	count: int,
	_clink: String,
	only: Array,
	stuff := "wood",
	hits: Array = []
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
	var made := WreckPhysics.stuff_of(stuff)
	var reach := 0.0
	for i: int in chosen:
		var part: WreckCuts.Part = parts[i]
		var at := origin + turn * (part.centre * size)
		if physics.solid(at):
			continue
		# A barrel's hoops are iron whatever its staves are.
		var made_of := "iron" if part.form == "ring" and stuff == "wood" else stuff
		var b := physics.add(
			at,
			Quaternion((turn * part.basis).orthonormalized()),
			part.half * size,
			made_of,
			part.form,
			_groups
		)
		reach = maxf(reach, at.distance_to(mid) + b.reach)
		var w := Wreck.new()
		w.body = b
		w.key = key
		w.index = i
		w.size = size
		w.sinks = made.sinks
		w.sprite = View.Sprite.new(b.p.x, b.p.y, "", 1.0, b.p.z)
		w.sprite.solid = "~%s#%d" % [key, i]
		wrecks.append(w)
	physics.burst(_groups, mid, PART * power, dice)
	if hits.is_empty():
		# No shot or blast known (a client's mirror, fire): struck on its near
		# side along the knock.
		var way := Vector3(knock.x, knock.y, 0.0)
		way = way.normalized() if way.length() > .01 else Vector3.ZERO
		var at := mid - way * reach * .6 + Vector3(0.0, 0.0, dice.randf_range(-.2, .2) * reach)
		hits = [[at, way, BREAK_PUSH * knock.z, "break"]]
	for hit: Array in hits:
		var at: Vector3 = hit[0]
		var way: Vector3 = hit[1]
		var strength: float = hit[2]
		physics.impact(at, way, strength * power, str(hit[3]), _groups, dice)
	_cap()


## One piece of `key` (its `index`th part) thrown on its own: at `at` turned
## `q`, drawn through `shape` (its part's faces about its middle; a template
## triangle or board stretched to what was cut this time), its box `half`,
## going `v`, spinning `w`. Glass (`tri` its corners) breaks again landing.
## A new break's pieces pass through one another a moment (new_group()).
func throw_shaped(
	key: String,
	index: int,
	at: Vector3,
	q: Quaternion,
	shape: Basis,
	half: Vector3,
	v: Vector3,
	w: Vector3,
	clink: String,
	tri := PackedVector2Array()
) -> Wreck:
	if not on or physics.solid(at):
		return null
	var glass := clink == "glass_settle"
	var b := physics.add(
		at, q, half, "glass" if glass else "wood", "shard" if glass else "board", _groups
	)
	b.v = v
	b.w = w
	var wreck := Wreck.new()
	wreck.body = b
	wreck.key = key
	wreck.index = index
	wreck.clink = clink
	wreck.shape = shape
	wreck.tri = tri
	wreck.sinks = clink == "glass_settle"
	wreck.fell = v.z
	wreck.sprite = View.Sprite.new(b.p.x, b.p.y, "", 1.0, b.p.z)
	wreck.sprite.solid = "~%s#%d" % [key, index]
	wrecks.append(wreck)
	_cap()
	return wreck


## The next pieces thrown are a break of their own.
func new_group() -> void:
	_groups += 1


## Shards of glass (Wreck.tri) that hit the floor or a wall hard break again:
## a big one in two or three, a small one (or one broken twice) into glints
## that lie where it fell (features/wall_looks.gd shatter()).
func _glass_lands() -> void:
	var landed: Array = []
	for w: Wreck in wrecks:
		if w.tri.is_empty() or w.fading >= 0.0:
			continue
		var vz := w.body.v.z
		var was := w.fell
		w.fell = vz
		if (was < -1.6 and vz > was * .35) or (not w.body.awake and w.breaks == 0):
			landed.append(w)
	if landed.is_empty():
		return
	var looks: WallLooks = game.features.get("wall_looks")
	for w: Wreck in landed:
		if looks != null and wrecks.has(w):
			_drop(w)
			# Whatever lay on it or against it is let go too.
			for o: Wreck in wrecks:
				if o.body.p.distance_to(w.body.p) < o.body.reach + w.body.reach + .1:
					o.wedged = false
					o.body.wake()
			looks.shatter(w)


## The hits that broke a thing standing at `foot` (its radius and height):
## the shots of the last SHOT_TIME whose ends struck within its reach (each
## pellet where it struck: [at, way, strength, "break"]), else a blast just
## gone off near it ([at, ZERO, strength, "blast"]), else none.
func _hits_for(foot: Vector3, radius: float, height: float, _knock_was: Vector3) -> Array:
	var out: Array = []
	var near := radius + SHOT_NEAR
	for shot: Array in _shots:
		var clock: float = shot[2]
		if game.clock - clock > SHOT_TIME:
			continue
		var to: Vector3 = shot[1]
		if (
			Vector2(to.x - foot.x, to.y - foot.y).length() > near
			or to.z < foot.z - .2
			or to.z > foot.z + height + .3
		):
			continue
		var from: Vector3 = shot[0]
		var way := (to - from).normalized()
		var damage: float = shot[3]
		# (A shot's end is level with the thing's middle: struck on its face.)
		var at := to - way * radius * .8
		out.append([at, way, BREAK_PUSH * clampf(.6 + damage / 40.0, .6, 2.2), "break"])
	if not out.is_empty():
		# A load of buckshot is many small knocks, a slug one big one.
		var each := 1.0 / sqrt(float(out.size()))
		for hit: Array in out:
			var strength: float = hit[2]
			hit[2] = strength * each
		return out
	var blast := _blast_near(foot.x, foot.y)
	if not blast.is_empty():
		var bx: float = blast[0]
		var by: float = blast[1]
		var bz: float = blast[2]
		return [[Vector3(bx, by, bz), Vector3.ZERO, BLAST_PUSH, "blast"]]
	return out


## A hitscan shot ended at `end` (from the acting player's eye): kept as a
## hit for whatever it broke, and a piece lying in its way is knocked where
## the shot entered it.
func _traced(end: Vector3, _struck: String) -> void:
	var p := game.player
	if p == null:
		return
	var from := Vector3(p.x, p.y, p.eye)
	var damage: float = Weapons.DAMAGE.get(game.armory.active, 20.0)
	_shots.append([from, end, game.clock, damage])
	while _shots.size() > 24:
		_shots.pop_front()
	if wrecks.is_empty():
		return
	var way := end - from
	var hit := physics.ray(from, end + way.normalized() * .05)
	if hit.is_empty():
		return
	var b: WreckPhysics.Body = hit[0]
	var at: Vector3 = hit[1]
	for w: Wreck in wrecks:
		if w.body == b:
			w.wedged = false
			w.wakes = 0
			if w.fading >= 0.0:
				return
	var push := minf(
		damage * WreckPhysics.tuned("knock", "shot_push", .12),
		WreckPhysics.tuned("knock", "shot_most", 8.0)
	)
	physics.impact(at, way.normalized(), push, "shot", -1, dice, b)


## The knocks of this step heard by what each piece is made of (wreck.cfg
## [stuff.*] cue, cue_hard, loud, alts), smaller pieces higher, at most
## `sounds_most` a second from them all and one a piece in `gap`.
func _sounds() -> void:
	var quiet := WreckPhysics.tuned("knock", "quiet", 1.1)
	var gap := WreckPhysics.tuned("knock", "gap", .25)
	var most := int(WreckPhysics.tuned("knock", "sounds_most", 9.0))
	while not _heard.is_empty() and game.clock - _heard[0] > 1.0:
		_heard.remove_at(0)
	if _heard.size() >= most:
		return
	# The two hardest knocks of this step.
	var best: WreckPhysics.Body = null
	var next: WreckPhysics.Body = null
	for item: Variant in physics.bodies:
		var b: WreckPhysics.Body = item
		if not b.awake or b.hit < quiet or game.clock - b.heard < gap:
			continue
		if best == null or b.hit > best.hit:
			next = best
			best = b
		elif next == null or b.hit > next.hit:
			next = b
	_rings()
	for b: WreckPhysics.Body in [best, next]:
		if b == null or _heard.size() >= most:
			continue
		b.heard = game.clock
		_heard.append(game.clock)
		var made := WreckPhysics.stuff_of(b.stuff)
		var cue := made.cue_hard if b.hit > made.loud * .5 else made.cue
		if cue == "":
			continue
		# One of its takes.
		if cue == made.cue and not made.alts.is_empty():
			var take := dice.randi_range(0, made.alts.size())
			if take > 0:
				cue = str(made.alts[take - 1])
		var strength := clampf(b.hit / made.loud, .12, 1.0) * .6
		var rate := clampf(.32 / maxf(b.reach, .05), .8, 1.35) * dice.randf_range(.94, 1.06)
		game.sound_at(cue, b.p.x, b.p.y, strength, rate)


## Throw pieces `only` of a cut another feature made (a vehicle's parts:
## src/vehicle_wreck_looks.gd), as _throw does, when pieces fly here.
func throw_cut(src: Dictionary, knock: Vector3, power: float, only: Array) -> void:
	if on:
		_throw(src, knock, power, only.size(), "debris_settle", only, "tin")


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


## A piece woken again and again where it lies (a pile of curved staves
## that will not settle, each waking the next) lies down once it has woken
## more than WAKES times since it was thrown or knocked, slow enough; one
## laid down still half in something shrinks away.
func _restless() -> void:
	for w: Wreck in wrecks:
		var b := w.body
		if not b.awake:
			w.asleep = true
			continue
		if w.asleep:
			w.asleep = false
			w.wakes += 1
		if w.wakes > WAKES and b.v.length() < .3 and b.w.length() < 1.0 and w.fading < 0.0:
			b.awake = false
			b.v = Vector3.ZERO
			b.w = Vector3.ZERO
			# Laid down half in something (it was still being pushed out):
			# it shrinks away instead.
			if physics.inside(b) > .03:
				w.fading = game.clock


## A piece gone to sleep wedged where nothing fits (WreckPhysics: stuck)
## shrinks away.
func _unstick() -> void:
	for w: Wreck in wrecks:
		if w.body.stuck and w.fading < 0.0:
			w.fading = game.clock


func _shrink(_dt: float) -> void:
	for k in range(wrecks.size() - 1, -1, -1):
		var w: Wreck = wrecks[k]
		if w.fading >= 0.0 and game.clock - w.fading >= fade:
			_drop(w)


## A hoop or lid that has begun to wobble down on its rim rings down (its
## stuff's spin_cue, wreck.cfg), once until it lies still.
func _rings() -> void:
	for item: Variant in physics.bodies:
		var b: WreckPhysics.Body = item
		if not b.wobbling:
			continue
		b.wobbling = false
		var made := WreckPhysics.stuff_of(b.stuff)
		if made.spin_cue != "":
			game.sound_at(made.spin_cue, b.p.x, b.p.y, .45)


## A blast's shove (game_combat.gd blast_shoved) throws what lies about:
## from where it went off (the last blast near), by how near, less behind
## cover (WreckPhysics.impact "blast").
func _shoved(x: float, y: float, reach: float, power: float) -> void:
	if wrecks.is_empty():
		return
	var z := game.world.elevation(x, y) + .3
	var blast := _blast_near(x, y)
	if not blast.is_empty():
		z = blast[2]
	for w: Wreck in wrecks:
		if absf(w.body.p.x - x) < reach and absf(w.body.p.y - y) < reach:
			w.wedged = false
			w.wakes = 0
	physics.impact(Vector3(x, y, z), Vector3.ZERO, power * 1.6, "blast", -1, dice)


## Walkers going through pieces kick and shove them (looks only): every
## player, the county's hands, BLUE the hound and the vehicles, each pushing
## what is under its knees within its reach along the way it goes, harder
## the faster (wreck.cfg [knock] kick_*). Only walkers near the pieces are
## looked at.
func _kick(dt: float) -> void:
	if wrecks.is_empty() or dt <= 0.0:
		_walked.clear()
		return
	var lo := Vector2(INF, INF)
	var hi := -lo
	for w: Wreck in wrecks:
		lo = lo.min(Vector2(w.body.p.x, w.body.p.y))
		hi = hi.max(Vector2(w.body.p.x, w.body.p.y))
	lo -= Vector2(2.0, 2.0)
	hi += Vector2(2.0, 2.0)
	var seen := {}
	for p: Player in game.players:
		_walker(p, p.x, p.y, game.world.stand(p), .28, "kick_player", lo, hi, dt, seen)
	# The county's hands kick only near this machine's player (where it is
	# seen): a horde walking through a yard of pieces kept them all awake.
	var eye := game.local_player if game.local_player != null else game.player
	for e: Enemy in game.enemies:
		if eye != null and absf(e.x - eye.x) + absf(e.y - eye.y) > KICK_SEEN:
			continue
		if e.x > lo.x and e.y > lo.y and e.x < hi.x and e.y < hi.y and e.alive:
			# (Its feet asked only once it is seen to walk: NAN.)
			_walker(e, e.x, e.y, NAN, maxf(e.radius, .2), "kick_enemy", lo, hi, dt, seen)
	var hound: Hound = game.features.get("hound")
	if hound != null:
		for d: Hound.Dog in hound.dogs:
			_walker(d, d.x, d.y, d.floor_z, .22, "kick_hound", lo, hi, dt, seen)
	var cars: Game.VehiclesScript = game.features.get("vehicles")
	if cars != null:
		for r: VehicleDrive.Ride in cars.rides:
			_walker(r, r.x, r.y, r.z, 1.0, "kick_ride", lo, hi, dt, seen)
	for k: Variant in _walked.keys():
		if not seen.has(k):
			_walked.erase(k)


## One walker at (x, y) on `feet`, `radius` wide: what it walked into this
## tick is kicked along its way.
func _walker(
	who: Object,
	x: float,
	y: float,
	feet: float,
	radius: float,
	how: String,
	lo: Vector2,
	hi: Vector2,
	dt: float,
	seen: Dictionary
) -> void:
	if x < lo.x or y < lo.y or x > hi.x or y > hi.y:
		return
	var id := who.get_instance_id()
	seen[id] = true
	var now := Vector3(x, y, feet)
	var was: Vector3 = _walked.get(id, now)
	_walked[id] = now
	var run := Vector2(x - was.x, y - was.y) / dt
	var speed := run.length()
	if speed < .8 or speed > 40.0:
		return
	if is_nan(feet):
		feet = game.world.stand(who)
	var way := Vector3(run.x / speed, run.y / speed, 0.0)
	var reach := radius + KICK_REACH
	var push := WreckPhysics.tuned("knock", how, .6) * speed
	var kind := "ram" if how == "kick_ride" else "kick"
	var near := reach + .3
	for w: Wreck in wrecks:
		var b := w.body
		# Across first (cheap): most pieces are nowhere near this walker.
		if absf(b.p.x - x) > near or absf(b.p.y - y) > near:
			continue
		if w.fading >= 0.0 or b.p.z > feet + KNEES + b.half.length() * .5 or b.p.z < feet - .3:
			continue
		var off := Vector2(b.p.x - x, b.p.y - y)
		if off.length() > reach + minf(b.reach, .3):
			continue
		# Already going its way faster than it walks: left alone.
		if Vector2(b.v.x, b.v.y).dot(run / speed) > speed * .7:
			continue
		# A hand kicks a piece once in KICK_AGAIN (it walks on through).
		if how == "kick_enemy":
			if game.clock - w.kicked < KICK_AGAIN:
				continue
			w.kicked = game.clock
		var at := Vector3(x, y, b.p.z) + Vector3(off.x, off.y, 0.0).normalized() * radius
		w.wedged = false
		w.wakes = 0
		physics.impact(at, way, push, kind, -1, dice, b)


# ------------------------------------------------------------------ drawing


func sprites() -> Array:
	var out: Array = []
	if not on:
		return out
	if ruin != null:
		ruin.sprites(out)
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
		s.turn = Basis(b.q) * w.shape * Basis.from_scale(Vector3.ONE * k)
		out.append(s)
	if not debris.bits.is_empty():
		out.append(_fine_sprite)
	return out
