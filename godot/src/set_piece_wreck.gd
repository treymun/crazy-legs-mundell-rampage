## The big breaks coming apart (looks only: features/wreckage.gd owns it; play
## is features/set_pieces.gd). Play moves each part of a barn or a water tower
## whole (HINGE, DROP: its place a sum of its move and the clock); here each
## part is drawn in its own pieces instead (src/set_piece_mesh.gd spsplit: a
## wall's boards, the tin's sheets, a post snapped, a beam broken, a deck's
## planks) that ride the part's pose and break away on their own dice:
##
## - When it creaks the frame sways, dust sifts from the eaves and boards pop
##   off the walls; when it goes some pieces break away in the fall (a post's
##   top snaps off, the ridge folds, a sheet of tin tumbles away, boards peel
##   off a wall going over) and the rest come apart where the part lands,
##   hopping and sliding onto a pile: each lands on what came down before it
##   (a height map of the pile), so the rubble lies in layers. A post's foot
##   stays standing, snapped. A part landing throws splinters, hay and a low
##   billow of dust that rolls out along the ground (fx_barndust), and shakes
##   the view by how near it is.
## - A tower's legs snap and buckle as it goes, its tank tears open in the
##   fall (a few staves and a gush of water out of the side going down), its
##   hoops spring off in bent bands that land on the ground, its deck
##   splinters, and the burst throws a fan of water (fx_gush).
## - A fuel line's pipe bursts where the fire reaches it.
##
## How it breaks is its own: the dice are seeded by the play state that brought
## it down (which posts went, each part's hp left, the lean, the clock it went
## at: carried and saved, so a client and a save see the same pile), and what
## brought it down weakens the parts near it (a post shot out, a blast's
## place, fire): more pieces there, breaking away sooner, thrown away from the
## blast. Nothing here is play: never carried, saved or in anyone's way (the
## cover is play's own volumes). Every piece's flight is worked out once when
## it breaks away (no stepping, nothing asked of the level but the ground's
## height); once all of a piece lies still its pieces are merged into a mesh a
## tile.
class_name SetPieceWreck
extends RefCounted

const Shape := preload("res://src/set_piece_shape.gd")
const RIDE := 0
const FLY := 1
const REST := 2
## The pile's height map: cells this many metres a side.
const CELL := .4
## Pieces at rest merged into a mesh at a time.
const MERGE_AT := 12
## Merged meshes a ruin keeps before it is merged whole again.
const MERGED_MOST := 6
const DUST := SetPieceFx.DUST
const GUSH := SetPieceFx.GUSH
const BOOM := SetPieceFx.BOOM


## A piece of a part.
class Bit:
	var i := 0
	var k := 0
	var key := ""
	var index := 0
	## Its middle and turn in its part's frame, its half sizes.
	var at := Vector3.ZERO
	var turn := Basis.IDENTITY
	var half := Vector3(.1, .1, .1)
	## When it breaks away: a share of its part's move (1 its landing), or
	## the clock `tb` (fixed: a board popping off in the creak).
	var share := 1.0
	var fixed := false
	var tb := INF
	var move_t0 := NAN
	## How hard it is thrown when it goes; a snapped foot staying up; tin.
	var kick := 1.0
	var stub := false
	var tin := false
	var state := RIDE
	## Its flight: from p0, q0 at tb, at v, turning w; on the pile at `land`
	## (pl, ql), sliding and hopping to rest_p, rest_q over `settle`.
	var p0 := Vector3.ZERO
	var q0 := Quaternion.IDENTITY
	var v := Vector3.ZERO
	var w := Vector3.ZERO
	var land := INF
	var pl := Vector3.ZERO
	var ql := Quaternion.IDENTITY
	var rest_p := Vector3.ZERO
	var rest_q := Quaternion.IDENTITY
	var settle := .3
	var hop := 0.0
	var landed := false
	## In a merge on its way, merged (drawn in its ruin's merged mesh).
	var merging := false
	var merged := false
	## Popped off in the creak, before its part was taken.
	var popped := false
	## Riding its part to the ground with the rest of its part's group (drawn
	## as one mesh with them until the first of them goes).
	var grouped := false
	var sprite: View.Sprite
	## Scratch: how well it suits a tear (_tear).
	var score := 0.0


## A set piece coming (or come) apart.
class Ruin:
	var i := 0
	var seed := 0
	var bits: Array[Bit] = []
	## The pile: cell -> its top.
	var heights := {}
	var mid := Vector3.ZERO
	var reach := 6.0
	var warn_at := -1.0
	var lean := Vector2.ZERO
	## The way its frame sways in the creak (the lean when it began to).
	var sway := Vector2(1, 0)
	var blast := Vector3.ZERO
	var blasted := false
	var burning := false
	## A tower's tank tearing open in the fall (its clock, then done).
	var tear_at := INF
	## Its pieces lying still merged as they come to rest (`MERGE_AT` at a
	## time, the last when all of it lies still): a sprite a tile a merge.
	var merged: Array = []
	var still := false
	var merges := 0
	## Its pieces dropped back into their places this tick (merged at once:
	## they never move again), and whether it has been merged whole since it
	## last took a part.
	var slotted: Array = []
	var whole := false
	## Each part's pieces that ride it to the ground together, drawn as one
	## mesh while they all ride: part -> [key, sprite, still together].
	var groups := {}


var game: Game
var ruins := {}
## Parts the ruins draw (piece * 1000 + part): set_pieces.gd leaves them out.
var taken := {}
var version := 0
## The dust, water, flares, splinters, shakes and sounds (its own dice).
var fx: SetPieceFx
var dice := RandomNumberGenerator.new()
## Blasts lately (wreckage.gd's: [x, y, z, clock]).
var blasts: Array = []
var detail := 1.0
var _seen := {}
var _stage := {}
var _pipe_cell := {}
var _sift_next := 0.0
var _pose_cache := {}
var _pose_clock := -1.0
## Cutting the parts' pieces on a worker (tens of milliseconds for a barn):
## the takes waiting for their cuts ([i, k, warned, key, weak, their schedule's
## inputs]), the task, its keys and what it made ([pieces, schedule, the
## riding group's mesh] a key); the schedules made, by key.
var _waiting: Array = []
var _job := -1
var _job_keys: Array = []
var _job_out: Array = []
var _job_in: Array = []
var _scheds := {}
## Merging a still ruin on a worker: the task, the ruin and its merge, the
## groups' sources, what each group holds ([sub, middle, turn] each) and the
## merged parts it made.
var _merge_job := -1
var _merge_ruin: Ruin
var _merge_n := 0
var _merge_bits: Array = []
var _merge_whole := false
var _merge_src: Array = []
var _merge_in: Array = []
var _merge_out: Array = []
var _threads := false
## Meshes the wreck layer is handed (tiny, out of sight) in a creak so that
## when it goes nothing is made at once: solid -> true when handed; and
## those to hand, a few a frame.
var _warm := {}
var _to_warm: Array = []
var _warm_sprites: Array = []


func _init(g: Game) -> void:
	game = g
	dice.seed = 1911
	var phone := (
		OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	)
	var few := phone or Quality.level() == Quality.LOW
	detail = Shape.num("looks", "detail_low" if few else "detail", 1.0)
	fx = SetPieceFx.new(g, few)
	_threads = OS.has_feature("threads")
	sync()


func _sets() -> SetPiecesFeature:
	var sets: SetPiecesFeature = game.features.get("set_pieces")
	return sets


## What stands, lies or burst now is seen as it is (a save, a snapshot put
## on, the start): what is down lies in its pieces already, nothing thrown.
func sync() -> void:
	_settle()
	_waiting.clear()
	ruins.clear()
	taken.clear()
	fx.puffs.clear()
	_seen.clear()
	_stage.clear()
	version += 1
	var sets := _sets()
	if sets == null:
		return
	for i in sets.pieces.size():
		var st: Dictionary = sets.pieces[i]
		var stage: int = st["stage"]
		_stage[i] = stage
		var outs: Array = st["out"]
		var made: Array = sets.shapes[i]
		var any := false
		for k in outs.size():
			var was: int = outs[k]
			_seen[i * 1000 + k] = was
			var part: Shape.Part = made[k]
			if (
				(was == SetPiecesFeature.MOVING or was == SetPiecesFeature.LYING)
				and part.role != "pipe"
			):
				any = true
		if str(st["kind"]) == "fuel":
			_pipes(sets, i, true)
			continue
		if not any and stage < SetPiecesFeature.WARN:
			continue
		var r := _ruin(sets, i, true)
		for k in outs.size():
			var was: int = outs[k]
			if stage == SetPiecesFeature.WARN and was == SetPiecesFeature.UP:
				take(sets, i, k, true, true)
			elif was == SetPiecesFeature.MOVING or was == SetPiecesFeature.LYING:
				take(sets, i, k, false, true)
		_due(sets, r, game.clock, false)
		if stage == SetPiecesFeature.DOWN:
			_finish(sets, r, true)


# ------------------------------------------------------------------ watching


## The set pieces changed (their net_version): what creaks, falls, lands,
## bursts and burns now.
func watch(sets: SetPiecesFeature) -> void:
	for i in sets.pieces.size():
		var st: Dictionary = sets.pieces[i]
		var kind := str(st["kind"])
		if kind == "fuel":
			_pipes(sets, i, false)
			continue
		var stage: int = st["stage"]
		var was_stage: int = _stage.get(i, SetPiecesFeature.STANDING)
		_stage[i] = stage
		if stage != was_stage:
			_staged(sets, i, was_stage, stage)
		var outs: Array = st["out"]
		var made: Array = sets.shapes[i]
		for k in outs.size():
			var code := i * 1000 + k
			var now: int = outs[k]
			var was: int = _seen.get(code, SetPiecesFeature.UP)
			if now == was:
				continue
			_seen[code] = now
			var part: Shape.Part = made[k]
			if now == SetPiecesFeature.MOVING and not taken.has(code):
				take(sets, i, k, false)
			elif now == SetPiecesFeature.LYING:
				_landed(sets, i, k)
			elif now == SetPiecesFeature.GONE and part.tank:
				_burst_part(sets, i, k)


func _staged(sets: SetPiecesFeature, i: int, was: int, now: int) -> void:
	var st: Dictionary = sets.pieces[i]
	var made: Array = sets.shapes[i]
	var r := _ruin(sets, i, false)
	if now == SetPiecesFeature.WARN:
		r.warn_at = Shape.f(st["t0"])
		var outs: Array = st["out"]
		for k in made.size():
			var o: int = outs[k]
			if o == SetPiecesFeature.UP:
				take(sets, i, k, true)
	elif now == SetPiecesFeature.FALLING:
		if r.warn_at < 0.0:
			r.warn_at = Shape.f(st["t0"]) - Shape.num("all", "warn", .95)
		var lean_row: Array = st["lean"]
		r.lean = Vector2(Shape.f(lean_row[0]), Shape.f(lean_row[1]))
		fx.shake(r.mid.x, r.mid.y, .4)
		fx.sound("timber_snap", r.mid.x, r.mid.y, .9, .15)
		if str(st["kind"]) == "tower":
			var burst: float = st.get("burst", -1.0)
			if burst > 0.0:
				var t0: float = st["t0"]
				r.tear_at = burst - (burst - t0) * dice.randf_range(.22, .36)
	elif now == SetPiecesFeature.DOWN and was == SetPiecesFeature.FALLING:
		# A barn's dust rolls out round it (a tower's burst is its water).
		if str(st["kind"]) == "barn":
			_ring(sets, r)


## A barn or a tower's ruin (made the first time).
func _ruin(sets: SetPiecesFeature, i: int, settled: bool) -> Ruin:
	var found: Ruin = ruins.get(i)
	if found != null:
		return found
	var r := Ruin.new()
	r.i = i
	var st: Dictionary = sets.pieces[i]
	var box: Rect2 = sets._boxes[i]
	var ground: float = sets._ground[i]
	r.mid = Vector3(box.get_center().x, box.get_center().y, ground)
	r.reach = box.size.length() * .5
	var lean_row: Array = st["lean"]
	r.lean = Vector2(Shape.f(lean_row[0]), Shape.f(lean_row[1]))
	if r.lean.length() > .05:
		r.sway = r.lean.normalized()
	var stage: int = st["stage"]
	var t0: float = st["t0"]
	var warn := Shape.num("all", "warn", .95)
	if stage == SetPiecesFeature.WARN:
		r.warn_at = t0
	# The break's own dice, from what play holds of how it came down (the
	# same on a client and after a save): when it creaked, the hp each part
	# had left (the posts shot out, the walls shot about), the lean.
	var when := t0 if stage == SetPiecesFeature.WARN else t0 - warn - .5 / 60.0
	if stage < SetPiecesFeature.WARN:
		when = game.clock
	var sig := "%s:%d:%.2f" % [game.level.id, i, snappedf(when, .25)]
	for hp: Variant in st["hp"]:
		sig += ":%d" % roundi(Shape.f(hp))
	if stage < SetPiecesFeature.FALLING:
		sig += ":%.2f,%.2f" % [r.lean.x, r.lean.y]
	r.seed = absi(sig.hash()) % 16000000
	# A blast lately near it brought it down: the pieces fly from it.
	if not settled:
		for b: Array in blasts:
			var bx: float = b[0]
			var by: float = b[1]
			var at: float = b[3]
			if game.clock - at < 1.6 and box.grow(6.0).has_point(Vector2(bx, by)):
				r.blast = Vector3(bx, by, Shape.f(b[2]))
				r.blasted = true
	var fire: GameFeature = game.features.get("fire")
	if fire != null:
		for n in 5:
			var p := box.get_center() + (box.size * .35) * Vector2(cos(n * 1.3), sin(n * 1.3))
			if n == 4:
				p = box.get_center()
			if fire.call("burning_at", p.x, p.y):
				r.burning = true
	ruins[i] = r
	return r


## Part k of piece i drawn in its pieces from now on. `warned`: in the creak,
## still standing: its pieces are only cut (and a few boards pop off it) and
## play's part is drawn whole, swaying (sway_turn), until it goes. Its pieces
## are cut on a worker (`now`: here and now): until they are, play's part is
## drawn whole.
func take(sets: SetPiecesFeature, i: int, k: int, warned: bool, now := false) -> void:
	var code := i * 1000 + k
	if taken.has(code):
		return
	for w: Array in _waiting:
		var wi: int = w[0]
		var wk: int = w[1]
		if wi == i and wk == k:
			if not warned:
				# It went before its cut came: taken whole when it does.
				w[2] = false
			return
	var made: Array = sets.shapes[i]
	var part: Shape.Part = made[k]
	if part.key == "" or part.role in ["cap", "name"]:
		return
	var st: Dictionary = sets.pieces[i]
	var r := _ruin(sets, i, false)
	var d := RandomNumberGenerator.new()
	d.seed = r.seed + k * 7919
	var weak := _weakness(sets, r, i, k)
	var key := part.key
	var size := part.half * 2.0
	var tile := sets._tile_of(st, k)
	var fine := clampf(detail * (1.0 + .45 * weak), .3, 1.7)
	var mode := -1
	match part.role:
		"wall":
			mode = SetPieceMesh.BOARDS
		"roof":
			mode = SetPieceMesh.SHEETS
		"deck":
			mode = SetPieceMesh.PLANKS
		"tank", "hoop":
			mode = -1
		_:
			mode = SetPieceMesh.STICK
	if mode >= 0:
		key = (
			"t:%s@0,0|spsplit:%.3f,%.3f,%.3f,%d,%d,%.2f"
			% [tile, size.x, size.y, size.z, mode, d.randi() % 16000000, fine]
		)
	if not now and _threads and not WreckCuts.has(key):
		_waiting.append([i, k, warned, key, weak, _inputs(sets, r, i, k, weak)])
		return
	_bits(sets, i, k, warned, key, weak)


## What part k's pieces' schedule is worked out from (_schedule): [role,
## weak, blasted, in a creak, leans the way it sways, its dice's seed].
func _inputs(sets: SetPiecesFeature, r: Ruin, i: int, k: int, weak: float) -> Array:
	var made: Array = sets.shapes[i]
	var part: Shape.Part = made[k]
	var leans := part.side.dot(r.sway) > 0.0 or part.role == "post"
	return [part.role, weak, r.blasted, r.warn_at >= 0.0, leans, r.seed + k * 7919]


## Part k's pieces (its cut `key`), each with when and how it breaks away.
func _bits(sets: SetPiecesFeature, i: int, k: int, warned: bool, key: String, weak: float) -> void:
	var code := i * 1000 + k
	if taken.has(code):
		return
	var made: Array = sets.shapes[i]
	var part: Shape.Part = made[k]
	var r := _ruin(sets, i, false)
	var d := RandomNumberGenerator.new()
	d.seed = r.seed + k * 7919
	d.randi()
	var subs := WreckCuts.parts(game.art, key)
	if subs.is_empty():
		return
	var had := {}
	for b: Bit in r.bits:
		if b.k == k and b.key == key:
			had[b.index] = true
	if warned and not had.is_empty():
		return
	if not warned:
		taken[code] = true
		version += 1
	r.still = false
	r.whole = false
	var inputs := _inputs(sets, r, i, k, weak)
	var sched_key := "%s:%s" % [key, str(inputs)]
	var sched: Array = _scheds.get(sched_key, [])
	if sched.is_empty():
		sched = SetPieceBits.schedule(subs, inputs)
		_scheds[sched_key] = sched
	var warn := Shape.num("all", "warn", .95)
	var members: Array = []
	for n in subs.size():
		var sub: WreckCuts.Part = subs[n]
		var row: PackedFloat32Array = sched[n]
		var flags := int(row[2])
		var b := Bit.new()
		b.i = i
		b.k = k
		b.key = key
		b.index = n
		b.at = sub.centre
		b.turn = sub.basis
		b.half = sub.half
		b.share = row[0]
		b.kick = row[1]
		b.tin = flags & 1 != 0
		b.stub = flags & 2 != 0
		var pop := flags & 4 != 0 and r.warn_at >= 0.0
		if pop:
			# Popped off in the creak.
			b.fixed = true
			b.popped = true
			b.tb = r.warn_at + row[3] * warn
		if had.has(n) or (warned and not pop):
			continue
		b.sprite = View.Sprite.new(0.0, 0.0, "", 1.0, 0.0)
		b.sprite.solid = "~%s#%d" % [key, n]
		r.bits.append(b)
		if not warned and flags & 8 != 0 and not pop:
			b.grouped = true
			members.append(b)
	if members.size() > 1:
		var group_key := SetPieceBits.group_key(key, inputs)
		if not WreckCuts.has(group_key):
			WreckCuts.put(group_key, [SetPieceBits.group(subs, sched)])
		var gs := View.Sprite.new(0.0, 0.0, "", 1.0, 0.0)
		gs.solid = "~%s#0" % group_key
		r.groups[k] = [group_key, gs, true]
		_warm.erase(gs.solid)
	else:
		for item: Variant in members:
			var b: Bit = item
			b.grouped = false


## How weak part k is by what brought piece i down (0 sound to about 1.5):
## its hp spent, the posts or legs out near it, a blast near, fire.
func _weakness(sets: SetPiecesFeature, r: Ruin, i: int, k: int) -> float:
	var st: Dictionary = sets.pieces[i]
	var made: Array = sets.shapes[i]
	var hp: Array = st["hp"]
	var part: Shape.Part = made[k]
	var w := 0.0
	if part.hp > 0.0:
		w += clampf(1.0 - Shape.f(hp[k]) / part.hp, 0.0, 1.0) * .7
	var at := Vector2(part.p.x, part.p.y)
	for n in made.size():
		var other: Shape.Part = made[n]
		if (other.role == "post" or other.role == "leg") and Shape.f(hp[n]) <= 0.0:
			w += maxf(0.0, 1.0 - at.distance_to(Vector2(other.p.x, other.p.y)) / 3.5) * .55
	if r.blasted:
		w += maxf(0.0, 1.0 - at.distance_to(Vector2(r.blast.x, r.blast.y)) / 6.0)
	if r.burning:
		w += .4
	return clampf(w, 0.0, 1.5)


## Part k came down: dust rolls out from under it, splinters and hay fly,
## the view shakes by how near.
func _landed(sets: SetPiecesFeature, i: int, k: int) -> void:
	var made: Array = sets.shapes[i]
	var part: Shape.Part = made[k]
	var r: Ruin = ruins.get(i)
	if r == null:
		return
	var at: Array = sets.pose(i, k, INF)
	var c: Vector3 = at[0]
	var q: Quaternion = at[1]
	var big := part.half.length()
	var b := Basis(q)
	var long := b.x * part.half.x if part.half.x >= part.half.y else b.y * part.half.y
	if part.half.z > maxf(part.half.x, part.half.y):
		long = b.z * part.half.z
	var n := 1 + int(big > 1.6)
	if part.role == "brace":
		# A tower's braces land all at once: a billow for a few of them.
		n = 1 if dice.randf() < .15 else 0
	for m in n:
		var p := c + long * dice.randf_range(-.9, .9)
		var out := Vector3(p.x - r.mid.x, p.y - r.mid.y, 0.0)
		if out.length() < .2:
			out = Vector3(dice.randf_range(-1, 1), dice.randf_range(-1, 1), 0)
		out = out.normalized() * dice.randf_range(1.2, 2.4)
		var floor_z := _ground(p.x, p.y)
		var size := minf(2.3, 1.6 + big * .3)
		fx.puff(DUST, Vector3(p.x, p.y, floor_z - .15), out, dice.randf_range(2.2, 3.4), .7, size)
	fx.specks(c.x, c.y, c.z + .1, "splinter_%d" % (k % 2), 2 + int(big), 2.0, 2.4)
	if part.role == "roof":
		fx.specks(c.x, c.y, c.z + .2, "brk_straw_0" if not r.burning else "ember_0", 3, 1.8, 2.6)
	elif part.role == "wall":
		fx.specks(c.x, c.y, c.z + .1, "chaff_0" if not r.burning else "ember_0", 2, 1.4, 2.0)
	fx.shake(c.x, c.y, .04 + .05 * minf(big, 2.0))
	if part.role == "roof":
		fx.sound("collapse_tin", c.x, c.y, .8, .25)
	elif big > 1.0:
		fx.sound("collapse_rumble", c.x, c.y, .7, .4)


## Everything down: the big billow round its footprint, rolling out.
func _ring(sets: SetPiecesFeature, r: Ruin) -> void:
	var box: Rect2 = sets._boxes[r.i]
	var n := 9
	for m in n:
		var a := TAU * m / n + dice.randf_range(-.2, .2)
		var edge := Vector2(cos(a) * box.size.x * .45, sin(a) * box.size.y * .45)
		var p := box.get_center() + edge
		var out := Vector3(cos(a), sin(a), 0.0) * dice.randf_range(1.6, 3.0)
		var floor_z := _ground(p.x, p.y) - .2
		fx.puff(DUST, Vector3(p.x, p.y, floor_z), out, dice.randf_range(3.0, 4.4), 1.0, 2.5)
	fx.shake(r.mid.x, r.mid.y, .25)
	fx.sound("collapse_rumble", r.mid.x, r.mid.y, 1.0, .5)


## A tower's tank part gone at the burst: its staves fly (wreckage.gd throws
## the rest), its hoops spring off in bands, its deck splinters, its water
## goes out in a fan.
func _burst_part(sets: SetPiecesFeature, i: int, k: int) -> void:
	var r: Ruin = ruins.get(i)
	var made: Array = sets.shapes[i]
	var part: Shape.Part = made[k]
	var at: Array = sets.pose(i, k, game.clock)
	var c: Vector3 = at[0]
	var q: Quaternion = at[1]
	if r == null:
		r = _ruin(sets, i, false)
	match part.role:
		"tank":
			_drop_riding(r, k)
			_gush(r, c, 12)
			fx.shake(c.x, c.y, .5)
		"hoop":
			_drop_riding(r, k)
			var key := (
				"t:%s@0,0|sphooparc:%.3f,%.3f,%d,3,%d,%d"
				% [
					part.tile,
					part.half.x + .05,
					part.half.z * 1.8,
					18,
					2 + int(detail > .8),
					r.seed
				]
			)
			var b0 := Basis(q)
			var arcs := WreckCuts.parts(game.art, key)
			for n in arcs.size():
				var sub: WreckCuts.Part = arcs[n]
				var b := Bit.new()
				b.i = i
				b.k = k
				b.key = key
				b.index = n
				b.at = sub.centre
				b.turn = sub.basis
				b.half = sub.half
				b.fixed = true
				b.tb = game.clock
				b.kick = 2.2
				b.sprite = View.Sprite.new(0.0, 0.0, "", 1.0, 0.0)
				b.sprite.solid = "~%s#%d" % [key, n]
				b.p0 = c + b0 * sub.centre
				b.q0 = Quaternion((b0 * sub.basis).orthonormalized())
				r.bits.append(b)
				var out := b0 * Vector3(sub.centre.x, sub.centre.y, 0.0)
				var v := (
					out.normalized() * dice.randf_range(2.5, 4.5)
					+ Vector3(r.lean.x, r.lean.y, 0) * 1.5
					+ Vector3(0, 0, dice.randf_range(2.0, 4.0))
				)
				_launch(r, b, game.clock, v, SetPieceBits.spin(9.0, dice))
			taken[i * 1000 + k] = true
			version += 1
			fx.sound("hoop_ring", c.x, c.y, .8, .1)
		"deck":
			var g: Array = r.groups.get(k, [])
			if not g.is_empty():
				g[2] = false
			for b: Bit in r.bits:
				if b.k == k:
					b.grouped = false
			for b: Bit in r.bits:
				if b.k == k and b.state == RIDE:
					b.fixed = true
					b.tb = game.clock
					b.kick = 3.2
	r.still = false


func _drop_riding(r: Ruin, k: int) -> void:
	r.groups.erase(k)
	var kept: Array[Bit] = []
	for b: Bit in r.bits:
		if b.k != k or b.state != RIDE:
			kept.append(b)
	r.bits = kept


## The staves of tower i's tank that tore out in the fall (indexes into its
## key): wreckage.gd throws the others at the burst.
func flown(i: int, k: int) -> Array:
	var out: Array = []
	var r: Ruin = ruins.get(i)
	if r == null:
		return out
	for b: Bit in r.bits:
		if b.k == k and b.state != RIDE:
			out.append(b.index)
	return out


## A fuel line's pipe bursts where the fire reaches it (`quiet`: as found).
func _pipes(sets: SetPiecesFeature, i: int, quiet: bool) -> void:
	var st: Dictionary = sets.pieces[i]
	var lit: Array = st.get("lit", [])
	if lit.is_empty():
		return
	var made: Array = sets.shapes[i]
	var cells: Array = sets.trails[i]
	for k in made.size():
		var part: Shape.Part = made[k]
		var code := i * 1000 + k
		if part.role != "pipe" or taken.has(code):
			continue
		if not _pipe_cell.has(code):
			var best := 0
			var near := INF
			for j in cells.size():
				var cell: Vector2i = cells[j]
				var dd := Vector2(cell.x + .5 - part.p.x, cell.y + .5 - part.p.y).length()
				if dd < near:
					near = dd
					best = j
			_pipe_cell[code] = best
		var j: int = _pipe_cell[code]
		var when: float = lit[j]
		if when < 0.0:
			continue
		var r := _ruin(sets, i, quiet)
		take(sets, i, k, false, true)
		for b: Bit in r.bits:
			if b.k == k:
				b.fixed = true
				b.tb = when + .03
				b.kick = 2.6
		if not quiet:
			fx.puff(BOOM, part.p + Vector3(0, 0, .1), Vector3.ZERO, .45, .7, 1.5)
			fx.sound("pipe_burst", part.p.x, part.p.y, .9, .12)
			fx.specks(part.p.x, part.p.y, part.p.z + .1, "brk_tin_0", 5, 2.4, 3.0)
		else:
			_due(sets, r, game.clock, false)


# ------------------------------------------------------------------ the tick


func busy() -> bool:
	return not fx.puffs.is_empty() or not ruins.is_empty() or not _waiting.is_empty()


## The workers' cuts and merges, when done; the next cut started.
func _jobs(sets: SetPiecesFeature) -> void:
	if _job >= 0 and WorkerThreadPool.is_task_completed(_job):
		WorkerThreadPool.wait_for_task_completion(_job)
		_job = -1
		for n in _job_keys.size():
			var made: Array = _job_out[n]
			var cut: Array = made[0]
			var key := str(_job_keys[n])
			var inputs: Array = _job_in[n]
			WreckCuts.put(key, cut)
			_scheds["%s:%s" % [key, str(inputs)]] = made[1]
			WreckCuts.put(SetPieceBits.group_key(key, inputs), [made[2]])
		for n in _job_keys.size():
			var inputs: Array = _job_in[n]
			var solid := "~%s#0" % SetPieceBits.group_key(str(_job_keys[n]), inputs)
			if not _warm.has(solid):
				_warm[solid] = false
				_to_warm.append(solid)
		var still: Array = []
		for w: Array in _waiting:
			var key: String = w[3]
			if WreckCuts.has(key):
				var wi: int = w[0]
				var wk: int = w[1]
				var warned: bool = w[2]
				var weak: float = w[4]
				_bits(sets, wi, wk, warned, key, weak)
			else:
				still.append(w)
		_waiting = still
	if _job < 0 and not _waiting.is_empty():
		_job_keys = []
		_job_in = []
		for w: Array in _waiting:
			if not _job_keys.has(w[3]):
				_job_keys.append(w[3])
				_job_in.append(w[5])
		_job_out = []
		_job = WorkerThreadPool.add_task(
			SetPieceBits.cut_all.bind(_job_keys, _job_in, _job_out), false, "set piece cuts"
		)
	if _merge_job >= 0 and WorkerThreadPool.is_task_completed(_merge_job):
		WorkerThreadPool.wait_for_task_completion(_merge_job)
		_merge_job = -1
		var r := _merge_ruin
		_merge_ruin = null
		if r != null and r.merges == _merge_n and ruins.get(r.i) == r:
			if _merge_whole:
				r.merged.clear()
			_merged(r, _merge_src, _merge_out, _merge_bits)
		_merge_bits = []


## Whether piece i has parts waiting for their cut.
func _cutting(i: int) -> bool:
	for w: Array in _waiting:
		var wi: int = w[0]
		if wi == i:
			return true
	return false


## Its game is gone: the workers waited for, nothing kept.
func close() -> void:
	_settle()
	_waiting.clear()
	ruins.clear()
	fx.puffs.clear()
	game = null


## Waits for the workers (a level put back, the feature gone).
func _settle() -> void:
	if _job >= 0:
		WorkerThreadPool.wait_for_task_completion(_job)
		_job = -1
	if _merge_job >= 0:
		WorkerThreadPool.wait_for_task_completion(_merge_job)
		_merge_job = -1
		_merge_ruin = null
		_merge_bits = []


func tick(dt: float) -> void:
	var sets := _sets()
	if sets == null:
		return
	_jobs(sets)
	var t := game.clock
	for i: int in ruins:
		var r: Ruin = ruins[i]
		if r.still:
			continue
		var st: Dictionary = sets.pieces[i]
		var stage: int = st["stage"]
		if stage == SetPiecesFeature.WARN and t >= _sift_next:
			_sift(sets, r)
		if t >= r.tear_at:
			r.tear_at = INF
			_tear(sets, r)
		# Nothing of it breaks away while its pieces are being cut: then all
		# that is due goes in order (the pile the same however quick the
		# worker was).
		if not _cutting(i):
			_due(sets, r, t, true)
		var all_still := stage != SetPiecesFeature.WARN and stage != SetPiecesFeature.FALLING
		var loose := 0
		for b: Bit in r.bits:
			if b.state == FLY:
				if not b.landed and t >= b.land:
					b.landed = true
					_touch(b)
				if t >= b.land + b.settle:
					b.state = REST
			if b.state != REST:
				all_still = false
			elif not b.merging and not b.merged:
				loose += 1
		all_still = all_still and not sets._any_moving(st) and not _cutting(i)
		if loose >= MERGE_AT or (all_still and loose > 0):
			_finish(sets, r)
		elif r.merged.size() >= MERGED_MOST and _merge_job < 0 and loose == 0:
			# Each landing's merge is a mesh (a draw) of its own: past a few,
			# all of it merged into a mesh a tile on the worker.
			_finish(sets, r, false, true)
		elif all_still and loose == 0 and _merge_ruin != r:
			if not r.whole and r.merged.size() > 3:
				_finish(sets, r, false, true)
			else:
				r.still = true
	fx.tick(dt)


## The pieces of r whose time to break away has come (`live`: with their
## noise), oldest first so the pile builds in order.
func _due(sets: SetPiecesFeature, r: Ruin, t: float, live: bool) -> void:
	var due: Array[Bit] = []
	for b: Bit in r.bits:
		if b.state != RIDE:
			continue
		if not b.fixed:
			var st: Dictionary = sets.pieces[b.i]
			var moves: Array = st["moves"]
			var m: Array = moves[b.k]
			if m.is_empty():
				continue
			var mt0: float = m[1]
			if mt0 != b.move_t0:
				b.move_t0 = mt0
				var time: float = m[2]
				b.tb = mt0 + b.share * time if b.share < INF else INF
		if b.tb <= t:
			due.append(b)
	if due.size() > 1:
		due.sort_custom(func(a: Bit, c: Bit) -> bool: return a.tb < c.tb)
	var flying := 0
	for b: Bit in r.bits:
		flying += 1 if b.state == FLY else 0
	var most := int(Shape.num("looks", "flying", 36.0))
	for b: Bit in due:
		if live and b.share < 1.0 and not b.fixed and not b.stub and flying >= most:
			# Enough in the air: it rides its part to the ground instead.
			b.share = 1.0
			b.move_t0 = NAN
			continue
		flying += 1
		if b.grouped:
			_leave(r, b)
		_go(sets, r, b, live)
	if not r.slotted.is_empty():
		if live:
			_merge_now(r, r.slotted)
		r.slotted = []
	if not live:
		for b: Bit in due:
			b.state = REST
			b.landed = true


## b leaves its part's riding group: early (in the fall) the group's mesh is
## made again without it; the first to go where the part lands breaks the
## group up (each drawn on its own from then on).
func _leave(r: Ruin, b: Bit) -> void:
	b.grouped = false
	var g: Array = r.groups.get(b.k, [])
	if g.is_empty() or not g[2]:
		return
	var left: Array = []
	for o: Bit in r.bits:
		if o.k == b.k and o.grouped and o.state == RIDE:
			left.append(o.index)
	var early := b.share < 1.0 or (b.fixed and b.share == INF)
	if not early or left.size() < 2:
		g[2] = false
		for o: Bit in r.bits:
			if o.k == b.k:
				o.grouped = false
		return
	left.sort()
	var key := "%s:%s" % [str(g[0]).get_slice(":-", 0), ",".join(PackedStringArray(left))]
	key = "%s:-%d" % [str(g[0]).get_slice(":-", 0), absi(key.hash())]
	if not WreckCuts.has(key):
		WreckCuts.put(key, [SetPieceBits.group_of(WreckCuts.parts(game.art, b.key), left)])
	g[0] = key
	var gs: View.Sprite = g[1]
	gs.solid = "~%s#0" % key


## Bit b breaks away at its tb: from where it rides then, at the speed it had
## there (and its kick), onto the pile.
func _go(sets: SetPiecesFeature, r: Ruin, b: Bit, live: bool) -> void:
	var d := RandomNumberGenerator.new()
	d.seed = r.seed + b.k * 131 + b.index * 7
	var a := _ride(sets, r, b, b.tb)
	var before := _ride(sets, r, b, b.tb - .03)
	b.p0 = a.origin
	b.q0 = Quaternion(a.basis.orthonormalized())
	var v := (a.origin - before.origin) / .03
	var dq := (b.q0 * Quaternion(before.basis.orthonormalized()).inverse()).normalized()
	var w := Vector3.ZERO
	if absf(dq.w) < .99999:
		w = dq.get_axis() * dq.get_angle() / .03
	if b.stub:
		_stand(r, b, d)
		return
	var out := b.p0 - (r.mid + Vector3(0, 0, 1.0))
	out.z = 0.0
	out = out.normalized() if out.length() > .01 else Vector3(1, 0, 0)
	if b.share >= 1.0 and not b.fixed and d.randf() > Shape.num("looks", "scatter", .3) * b.kick:
		# Came apart where it struck: it jumps and drops back into its place
		# in the part as the part lies, knocked askew (so the pile keeps the
		# part's layers and its cover, in pieces).
		_slot(sets, r, b, d)
		return
	if b.share >= 1.0 and not b.fixed:
		# Thrown off where it struck: a hop up and out, the rest of the
		# strike spent.
		v = Vector3(v.x * .3, v.y * .3, absf(v.z) * .1)
		v += out * d.randf_range(.1, .9) * b.kick + Vector3(0, 0, d.randf_range(.3, 1.6) * b.kick)
		w = w * .25 + SetPieceBits.spin(4.0 * b.kick, d)
		if b.tin and r.lean.length() > .05:
			# The tin skates off the way it fell.
			var way := r.lean.normalized() * d.randf_range(.6, 2.2)
			v += Vector3(way.x, way.y, 0.0)
	else:
		var turn := d.randf() * TAU
		var spread := Vector3(cos(turn), sin(turn), 0.0) * d.randf_range(0.0, .9)
		v += (
			(out * d.randf_range(.2, 1.1) + spread) * b.kick
			+ Vector3(0, 0, d.randf_range(.2, 1.4) * b.kick)
		)
		w += SetPieceBits.spin(4.5 * b.kick, d)
	if r.blasted:
		var away := b.p0 - r.blast
		var dist := away.length()
		if dist < 7.0:
			v += away.normalized() * (1.0 - dist / 7.0) * d.randf_range(3.0, 7.0)
	if v.length() > 9.0:
		v = v.normalized() * 9.0
	_launch(r, b, b.tb, v, w, d)
	if live and b.share < 1.0:
		if b.index % 2 == 0:
			fx.specks(b.p0.x, b.p0.y, b.p0.z, "splinter_%d" % (b.k % 2), 1, 1.6, 1.4)
		if b.tin:
			fx.sound("ricochet_tin", b.p0.x, b.p0.y, .35, .2)
		else:
			fx.sound("plank_crack", b.p0.x, b.p0.y, .55, .12)


## b shakes loose where its part struck and lies in its own place in the part
## as it lies, a little off and askew (in the strike's dust: merged with the
## rest of its part's at once, so a landing costs a mesh, not a piece each).
func _slot(sets: SetPiecesFeature, r: Ruin, b: Bit, d: RandomNumberGenerator) -> void:
	var at := _ride(sets, r, b, INF)
	var place := Quaternion(at.basis.orthonormalized())
	var a := d.randf() * TAU
	var lift := d.randf_range(0.0, .24)
	var tilt := Quaternion(Vector3(cos(a), sin(a), 0.0), lift)
	# Tin skates round and off its place further than boards.
	var spread := 1.5 if b.tin else 1.0
	var yaw := Quaternion(Vector3(0, 0, 1), d.randf_range(-.4, .4) * b.kick * spread)
	b.rest_q = (yaw * tilt * place).normalized()
	var off := Vector3(d.randf_range(-1, 1), d.randf_range(-1, 1), 0.0) * .28 * b.kick * spread
	b.rest_p = at.origin + off
	# On whatever came down there before it (and up a little where it is
	# knocked askew, one edge on the pile).
	var under := _height(r, b.rest_p.x, b.rest_p.y) + b.half[SetPieceBits.thin(b.half)]
	b.rest_p.z = maxf(at.origin.z, under) + d.randf_range(0.0, .04)
	_above(b)
	b.land = b.tb
	b.pl = b.rest_p
	b.ql = b.rest_q
	b.state = REST
	b.landed = true
	r.slotted.append(b)
	_raise(r, b)


## A snapped foot: it stays up where it stood, leaning a little.
func _stand(r: Ruin, b: Bit, d: RandomNumberGenerator) -> void:
	var tilt := d.randf_range(.1, .38)
	var a := d.randf() * TAU
	var axis := Vector3(cos(a), sin(a), 0.0)
	b.v = Vector3.ZERO
	b.w = Vector3.ZERO
	b.land = b.tb
	b.pl = b.p0
	b.ql = b.q0
	b.rest_q = (Quaternion(axis, tilt) * b.q0).normalized()
	var foot := b.p0.z - b.half.z
	b.rest_p = b.p0 + Vector3(axis.y, -axis.x, 0.0) * sin(tilt) * b.half.z
	b.rest_p.z = foot + cos(tilt) * b.half.z
	b.settle = .4
	b.hop = 0.0
	b.state = FLY
	r.still = false


## b flies from its p0, q0 at `t` at v turning w: where it lands on the pile,
## and how it comes to rest there.
func _launch(
	r: Ruin, b: Bit, t: float, v: Vector3, w: Vector3, d: RandomNumberGenerator = null
) -> void:
	if d == null:
		d = dice
	var g := Shape.num("all", "gravity", 14.0)
	b.v = v
	b.w = w
	b.tb = t
	b.state = FLY
	var thin := SetPieceBits.thin(b.half)
	var fall := SetPieceBits.fall_time(b.p0.z, v.z, _ground(b.p0.x, b.p0.y) + b.half[thin], g)
	var where := b.p0 + v * fall
	var q := _turned(b, fall)
	var rest := SetPieceBits.flat(b, q, d)
	var top := _pile(r, where, rest, b.half)
	fall = SetPieceBits.fall_time(b.p0.z, v.z, top.x, g)
	b.land = t + fall
	b.pl = b.p0 + v * fall
	b.pl.z = top.x
	b.ql = _turned(b, fall)
	var slide := Vector2(v.x, v.y) * (.3 if b.tin else .08)
	slide = slide.limit_length(1.8 if b.tin else .5)
	b.rest_p = Vector3(b.pl.x + slide.x, b.pl.y + slide.y, top.x)
	var pitch := top.y
	if not b.tin and b.share < INF and d.randf() < Shape.num("looks", "propped", .22):
		# Propped up on the pile, one end on the ground.
		var up := d.randf_range(.25, .7)
		pitch = up if d.randf() < .5 else -up
		top.x += sin(up) * b.half[SetPieceBits.long_axis(b.half)] * .8
		b.rest_p.z = top.x
	b.rest_q = rest
	if absf(pitch) > .01:
		var bb := Basis(rest)
		var long := bb[SetPieceBits.long_axis(b.half)]
		var across := Vector3(0, 0, 1).cross(Vector3(long.x, long.y, 0.0)).normalized()
		if across.length() > .5:
			b.rest_q = (Quaternion(across, -pitch) * rest).normalized()
	_above(b)
	b.settle = d.randf_range(.45, .7) if b.tin else d.randf_range(.22, .36)
	var strike := absf(v.z - g * fall)
	b.hop = clampf(strike * (.012 if b.tin else .03), .01, .25)
	_raise(r, b)


## b's rest lifted so no corner of it is under the ground.
func _above(b: Bit) -> void:
	var basis := Basis(b.rest_q)
	var reach := absf(basis[0].z) * b.half.x + absf(basis[1].z) * b.half.y
	reach += absf(basis[2].z) * b.half.z
	var floor_z := _ground(b.rest_p.x, b.rest_p.y)
	b.rest_p.z = maxf(b.rest_p.z, floor_z + reach - .02)


func _turned(b: Bit, after: float) -> Quaternion:
	var spin := b.w.length()
	if spin < .001:
		return b.q0
	return (Quaternion(b.w / spin, spin * after) * b.q0).normalized()


## Where a piece turned `rest` lies on the pile at `at`: [its middle's height,
## its pitch along its length] as (x, y).
func _pile(r: Ruin, at: Vector3, rest: Quaternion, half: Vector3) -> Vector2:
	var basis := Basis(rest)
	var long := SetPieceBits.long_axis(half)
	var reach := basis[long] * half[long] * .85
	var mid := _height(r, at.x, at.y)
	var h0 := _height(r, at.x - reach.x, at.y - reach.y)
	var h1 := _height(r, at.x + reach.x, at.y + reach.y)
	var length := maxf(.1, Vector2(reach.x, reach.y).length() * 2.0)
	var pitch := clampf(atan2(h1 - h0, length), -.45, .45)
	var thick := half[SetPieceBits.thin(half)]
	return Vector2(maxf(mid, (h0 + h1) * .5) + thick, pitch)


## The pile's top at (x, y): the ground, or what has come to lie there.
func _height(r: Ruin, x: float, y: float) -> float:
	var cell := Vector2i(floori(x / CELL), floori(y / CELL))
	var top: Variant = r.heights.get(cell)
	if top != null:
		var known: float = top
		return known
	return _ground(x, y)


func _ground(x: float, y: float) -> float:
	var w := game.world
	return w.elevation(clampf(x, 0.0, w.width - .01), clampf(y, 0.0, w.height - .01))


## b's rest raises the pile under it.
func _raise(r: Ruin, b: Bit) -> void:
	var basis := Basis(b.rest_q)
	var thin := SetPieceBits.thin(b.half)
	var top := b.rest_p.z + b.half[thin]
	var ax := basis[(thin + 1) % 3] * b.half[(thin + 1) % 3]
	var ay := basis[(thin + 2) % 3] * b.half[(thin + 2) % 3]
	var span := Vector2(absf(ax.x) + absf(ay.x), absf(ax.y) + absf(ay.y))
	var u := Vector2(ax.x, ax.y)
	var vv := Vector2(ay.x, ay.y)
	var uu := maxf(u.length_squared(), 1e-4)
	var vl := maxf(vv.length_squared(), 1e-4)
	for cy in range(floori((b.rest_p.y - span.y) / CELL), floori((b.rest_p.y + span.y) / CELL) + 1):
		for cx in range(
			floori((b.rest_p.x - span.x) / CELL), floori((b.rest_p.x + span.x) / CELL) + 1
		):
			var p := Vector2((cx + .5) * CELL - b.rest_p.x, (cy + .5) * CELL - b.rest_p.y)
			if absf(p.dot(u)) / uu > 1.0 or absf(p.dot(vv)) / vl > 1.0:
				continue
			var cell := Vector2i(cx, cy)
			r.heights[cell] = maxf(_height(r, (cx + .5) * CELL, (cy + .5) * CELL), top)


## Where part k of piece i is at `t` (and the creak's sway).
func _part_xf(sets: SetPiecesFeature, r: Ruin, i: int, k: int, t: float) -> Transform3D:
	var at: Array = sets.pose(i, k, t)
	var c: Vector3 = at[0]
	var q: Quaternion = at[1]
	var xf := Transform3D(Basis(q), c)
	var lean := _sway(r, t)
	if lean != 0.0:
		var turn := Basis(Vector3(-r.sway.y, r.sway.x, 0.0), lean)
		xf = Transform3D(turn, r.mid - turn * r.mid) * xf
	return xf


## Where b rides its part at `t` (and the creak's sway).
func _ride(sets: SetPiecesFeature, r: Ruin, b: Bit, t: float) -> Transform3D:
	var at: Array
	if t == game.clock:
		var code := b.i * 1000 + b.k
		if _pose_clock != t:
			_pose_clock = t
			_pose_cache.clear()
		var cached: Variant = _pose_cache.get(code)
		if cached == null:
			at = sets.pose(b.i, b.k, t)
			_pose_cache[code] = at
		else:
			at = cached
	else:
		at = sets.pose(b.i, b.k, t)
	var c: Vector3 = at[0]
	var q: Quaternion = at[1]
	var basis := Basis(q)
	var xf := Transform3D(basis * b.turn, c + basis * b.at)
	var lean := _sway(r, t)
	if lean != 0.0:
		var axis := Vector3(-r.sway.y, r.sway.x, 0.0)
		var turn := Basis(axis, lean)
		xf = Transform3D(turn, r.mid - turn * r.mid) * xf
	return xf


## The turn of piece i's standing parts in its creak (set_pieces.gd draws
## them so, about its middle on the ground).
func sway_turn(i: int) -> Basis:
	var r: Ruin = ruins.get(i)
	if r == null:
		return Basis.IDENTITY
	var lean := _sway(r, game.clock)
	if lean == 0.0:
		return Basis.IDENTITY
	return Basis(Vector3(-r.sway.y, r.sway.x, 0.0), lean)


## How far the frame leans in its creak at t (radians): swaying more and more
## and settling toward its fall; easing off once it goes.
func _sway(r: Ruin, t: float) -> float:
	if r.warn_at < 0.0 or t < r.warn_at:
		return 0.0
	var warn := Shape.num("all", "warn", .95)
	var amp := Shape.num("looks", "sway", .03)
	var end := r.warn_at + warn
	var at := minf(t, end)
	var s := (at - r.warn_at) / warn
	var lean := amp * s * sin(TAU * 2.2 * (at - r.warn_at)) + amp * .7 * s * s
	if t > end:
		lean *= maxf(0.0, 1.0 - (t - end) / .18)
	return lean


## A piece striking the pile: splinters off a board, a tin's rattle.
func _touch(b: Bit) -> void:
	if b.half.length() < .35 or fx.puffs.size() > fx.most_puffs - 4:
		return
	if dice.randf() < .35:
		fx.specks(b.pl.x, b.pl.y, b.pl.z + .05, "splinter_%d" % (b.index % 2), 2, 1.2, 1.4)
	if b.tin:
		fx.sound("ricochet_tin", b.pl.x, b.pl.y, .3, .15)
	elif dice.randf() < .3:
		fx.sound("impact_wood", b.pl.x, b.pl.y, .3, .1)


## The creak: dust sifting down off the eaves.
func _sift(sets: SetPiecesFeature, r: Ruin) -> void:
	_sift_next = game.clock + .06
	var box: Rect2 = sets._boxes[r.i]
	var spec := sets.spec_of(r.i)
	var top := r.mid.z + Shape.own(spec, "eave", Shape.own(spec, "legs", 3.0))
	var p := box.position + Vector2(dice.randf() * box.size.x, dice.randf() * box.size.y)
	fx.specks(p.x, p.y, top, "dust", 2, .3, .1)
	if dice.randf() < .3:
		fx.specks(p.x, p.y, top, "chaff_0", 1, .4, .2)
	if dice.randf() < .12:
		fx.puff(DUST, Vector3(p.x, p.y, top - .5), Vector3(0, 0, -.6), 1.2, .3, .7, 1.4, 2.0)


## A tower's tank tears in its fall: the staves facing the ground burst out
## with a gush.
func _tear(sets: SetPiecesFeature, r: Ruin) -> void:
	var tank := -1
	var made: Array = sets.shapes[r.i]
	for k in made.size():
		var part: Shape.Part = made[k]
		if part.role == "tank":
			tank = k
	if tank < 0:
		return
	var at: Array = sets.pose(r.i, tank, game.clock)
	var c: Vector3 = at[0]
	var best: Array[Bit] = []
	var down := Vector3(r.lean.x, r.lean.y, -1.6).normalized()
	for b: Bit in r.bits:
		if b.k == tank and b.state == RIDE:
			var xf := _ride(sets, r, b, game.clock)
			b.score = (xf.origin - c).normalized().dot(down)
			best.append(b)
	best.sort_custom(func(a: Bit, b2: Bit) -> bool: return a.score > b2.score)
	var n := mini(best.size(), 3 + dice.randi_range(0, 2))
	var gush := Vector3.ZERO
	for m in n:
		var b := best[m]
		b.fixed = true
		b.tb = game.clock
		b.kick = 3.0
		gush += _ride(sets, r, b, game.clock).origin / n
	_gush(r, gush, 4)
	fx.sound("plank_crack", gush.x, gush.y, 1.0, .05)


## Water thrown out at `at`: a fan of gushes along the fall, splashes.
func _gush(r: Ruin, at: Vector3, n: int) -> void:
	var way := r.lean.normalized() if r.lean.length() > .05 else Vector2(1, 0)
	for m in n:
		var a := way.angle() + dice.randf_range(-1.1, 1.1)
		var speed := dice.randf_range(2.5, 7.0)
		var v := Vector3(cos(a) * speed, sin(a) * speed, dice.randf_range(.5, 2.5))
		var floor_z := _ground(at.x, at.y)
		var p := Vector3(at.x, at.y, maxf(floor_z, at.z - .8))
		fx.puff(GUSH, p, v, dice.randf_range(.7, 1.3), .9, dice.randf_range(1.8, 2.8), .8, 6.0)
	fx.specks(at.x, at.y, at.z, "splash", 10, 3.0, 2.6)


## r lies still: its pieces merged into a mesh a tile (one a tick at most).
func _finish(sets: SetPiecesFeature, r: Ruin, now := false, whole := false) -> void:
	if _merge_job >= 0 and (not now or _merge_ruin == r):
		return
	r.merges += 1
	r.whole = whole or now
	var groups := {}
	var bits: Array = []
	for b: Bit in r.bits:
		if now and b.state == RIDE:
			var xf := _ride(sets, r, b, INF)
			b.rest_p = xf.origin
			b.rest_q = Quaternion(xf.basis.orthonormalized())
			b.state = REST
		if b.state != REST or b.merging or (b.merged and not whole and not now):
			continue
		b.merging = true
		bits.append(b)
		var src := b.key.get_slice("|", 0)
		if not groups.has(src):
			groups[src] = []
		var list: Array = groups[src]
		list.append(b)
	var srcs: Array = []
	var into: Array = []
	for src: String in groups:
		var items: Array = []
		var list: Array = groups[src]
		for item: Variant in list:
			var b: Bit = item
			var subs := WreckCuts.parts(game.art, b.key)
			if b.index < subs.size():
				items.append([subs[b.index], b.rest_p - r.mid, Basis(b.rest_q)])
		srcs.append(src)
		into.append(items)
	var out: Array = []
	if now or not _threads:
		SetPieceBits.merge_all(into, Vector3(r.reach, r.reach, 2.0), out)
		if whole or now:
			r.merged.clear()
		_merged(r, srcs, out, bits)
		if now:
			r.still = true
		return
	_merge_ruin = r
	_merge_n = r.merges
	_merge_src = srcs
	_merge_in = into
	_merge_out = out
	_merge_bits = bits
	_merge_whole = whole
	_merge_job = WorkerThreadPool.add_task(
		SetPieceBits.merge_all.bind(into, Vector3(r.reach, r.reach, 2.0), out),
		false,
		"set piece merge"
	)


## Pieces `bits` (at rest) merged here and now into a mesh a tile.
func _merge_now(r: Ruin, bits: Array) -> void:
	var groups := {}
	for item: Variant in bits:
		var b: Bit = item
		b.merging = true
		var src := b.key.get_slice("|", 0)
		if not groups.has(src):
			groups[src] = []
		var list: Array = groups[src]
		var subs := WreckCuts.parts(game.art, b.key)
		if b.index < subs.size():
			list.append([subs[b.index], b.rest_p - r.mid, Basis(b.rest_q)])
	var srcs: Array = []
	var into: Array = []
	for src: String in groups:
		srcs.append(src)
		into.append(groups[src])
	var out: Array = []
	SetPieceBits.merge_all(into, Vector3(r.reach, r.reach, 2.0), out)
	r.merges += 1
	r.whole = false
	_merged(r, srcs, out, bits)


## r's merged parts made: drawn from now on instead of those pieces.
func _merged(r: Ruin, srcs: Array, parts: Array, bits: Array) -> void:
	for n in srcs.size():
		var key := "%s|sprest:%s:%d:%d:%d" % [srcs[n], game.level.id, r.i, r.seed, r.merges]
		var part: WreckCuts.Part = parts[n]
		WreckCuts.put(key, [part])
		var s := View.Sprite.new(r.mid.x, r.mid.y, "", 1.0, r.mid.z)
		s.solid = "~%s#0" % key
		r.merged.append(s)
	for item: Variant in bits:
		var b: Bit = item
		b.merging = false
		b.merged = true


# ------------------------------------------------------------------ drawing


## The meshes cut in a creak handed to the wreck layer a few a frame, tiny
## and under the ground, so it has them made when the parts go.
func _warming(out: Array) -> void:
	if _to_warm.is_empty() and _warm_sprites.is_empty():
		return
	for n in mini(3, _to_warm.size()):
		var solid: String = _to_warm.pop_front()
		if not _warm.has(solid):
			continue
		var s := View.Sprite.new(0.0, 0.0, "", 1.0, -40.0)
		s.solid = solid
		s.turn = Basis.from_scale(Vector3.ONE * .001)
		_warm_sprites.append(s)
	var me := game.local_player if game.local_player != null else game.player
	var kept: Array = []
	for item: Variant in _warm_sprites:
		var s: View.Sprite = item
		if not _warm.has(s.solid.substr(0)):
			continue
		if me != null:
			s.x = me.x
			s.y = me.y
		out.append(s)
		kept.append(s)
	_warm_sprites = kept if not _to_warm.is_empty() else []


## Where b is at t: [middle, turn].
func pose(sets: SetPiecesFeature, r: Ruin, b: Bit, t: float) -> Transform3D:
	match b.state:
		RIDE:
			return _ride(sets, r, b, t)
		FLY:
			if t < b.land:
				var after := maxf(0.0, t - b.tb)
				var g := Shape.num("all", "gravity", 14.0)
				var p := b.p0 + b.v * after
				p.z -= .5 * g * after * after
				return Transform3D(Basis(_turned(b, after)), p)
			var s := clampf((t - b.land) / maxf(.01, b.settle), 0.0, 1.0)
			var e := 1.0 - (1.0 - s) * (1.0 - s)
			var at := b.pl.lerp(b.rest_p, e)
			at.z += b.hop * sin(PI * s)
			return Transform3D(Basis(b.ql.slerp(b.rest_q, s * s * (3.0 - 2.0 * s))), at)
	return Transform3D(Basis(b.rest_q), b.rest_p)


func sprites(out: Array) -> void:
	var sets := _sets()
	if sets == null:
		return
	_warming(out)
	var t := game.clock
	for i: int in ruins:
		var r: Ruin = ruins[i]
		if not game.in_view(r.mid.x, r.mid.y, r.reach + 9.0):
			continue
		out.append_array(r.merged)
		if r.still:
			continue
		for k: int in r.groups:
			var g: Array = r.groups[k]
			if g[2]:
				var xf := _part_xf(sets, r, i, k, t)
				var gs: View.Sprite = g[1]
				gs.x = xf.origin.x
				gs.y = xf.origin.y
				gs.z = xf.origin.z
				gs.turn = xf.basis
				out.append(gs)
		for b: Bit in r.bits:
			if b.merged:
				continue
			if b.grouped and b.state == RIDE:
				var g: Array = r.groups.get(b.k, [])
				if not g.is_empty() and g[2]:
					continue
			var xf := pose(sets, r, b, t)
			var s := b.sprite
			s.x = xf.origin.x
			s.y = xf.origin.y
			s.z = xf.origin.z
			s.turn = xf.basis
			out.append(s)
	fx.draw(out)
