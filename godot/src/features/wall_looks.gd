## How walls look taking a beating (features/wall_breaks.gd decides what
## breaks and when; this only shows it, each break its own):
##
## - A plank wall or fence (a fence cell of wall_breaks) keeps, for each of its
##   eight planks a cell, the stretch of it knocked out, in sixteenths of its
##   height. A round knocks a chunk out where it struck (a light one only
##   wears the plank until a few more land there: buckshot), the next one
##   there breaks it further or lets its shorter end go, a third takes it all;
##   a blast tears out the planks facing it, most where it was nearest; a body
##   thrown into it breaks them low. Every bit knocked out flies as a real
##   piece of that plank (wreckage.gd throw_shaped) out the far side along the
##   shot, splinters back toward the gun, and when the cell goes through what
##   is left of its planks bursts out along the shot or away from the blast,
##   broken at fresh places each time. The 3D view knocks the planks out of
##   the wall itself (view_rows(): world_body.gdshaderinc plank_damage), so
##   what is behind shows through, the yard or the room.
## - A window's first round lays its crack web where the round struck (a
##   View.WallMark over the <material>_crk tile's stress cracks); shot out its
##   pane is cut fresh round where it was struck (rays from the hole, rings
##   round it: small pieces near the hole, big ones at the frame), the
##   smallest thrown as glints, the rest as glinting shards that fly from the
##   hole by the shot's or the blast's force and break again where they land
##   (shatter()); a blast tears the frame out too, its sticks flying.
##
## Looks only (LOOKS_FEATURES): its own dice, never carried or saved. The
## host and a lone game know where each round struck (wall_breaks.gd tells
## it); a client, or a save put on, sees only the fences' hp and makes up
## the knocks it did not see from what they took (seeded by the cell).
class_name WallLooks
extends GameFeature

const WallBreaks := preload("res://src/features/wall_breaks.gd")
const Wreckage := preload("res://src/features/wreckage.gd")
const WeaponFx := preload("res://src/features/weapon_fx.gd")
const PATH := "res://data/tuning/breakables.cfg"
## Planks a cell and sixteenths a plank (the view's plank_damage reads the same).
const SLOTS := 8
const TALL := 16
## Fence cells handed to the view at most (four rows of view_data).
const MOST := 32
const BLANK := Vector4(-1.0, -1.0, 0.0, 0.0)
## How long after a window was struck its break counts as that round's.
const HIT_TIME := .6
## A shard bigger than this (square cells) breaks in two or three landing.
const SPLIT_AREA := .004
## A pane's piece is cut no bigger than this (square cells).
const SHARD_MOST := .007
## The pieces' sources (WreckCuts.put): a glass triangle, a frame's stick.
const GLASS := "p:fx_shard_glass|tri"
const GLASS_LIT := "p:fx_shard_glass_lit|tri"
const STICK := "p:fx_window_frame|stick"
## A plank's board: a tile's eight columns, each a plank a cell tall.
const BOARD := "t:%s@1,1|planks:8,1"
const BOARD_THICK := .0175
## No piece of plank flies longer than this (cells): a long stick lands
## badly against a wall.
const BOARD_LONGEST := .7


## One fence cell's planks.
class Planks:
	var fence: WallBreaks.Fence
	## Each plank's stretch knocked out [lo, hi) in sixteenths (lo >= hi: none),
	## and the wear of rounds too light to knock a chunk out.
	var lo := PackedInt32Array()
	var hi := PackedInt32Array()
	var wear := PackedFloat32Array()
	## The hp it has lost that its knocks account for.
	var counted := 0.0
	var z0 := 0.0
	var span := 1.0
	## How it was last struck: along, how hard (a share of its hp), how.
	var dir := Vector2.ZERO
	var power := .3
	var how := WallBreaks.SHOT
	var at := Vector3.ZERO

	func _init(f: WallBreaks.Fence, ground: float) -> void:
		fence = f
		z0 = ground
		span = maxf(.3, f.top)
		lo.resize(SLOTS)
		hi.resize(SLOTS)
		wear.resize(SLOTS)
		for j in SLOTS:
			lo[j] = TALL
			hi[j] = 0

	func gone(j: int) -> bool:
		return lo[j] < hi[j]

	func any() -> bool:
		for j in SLOTS:
			if lo[j] < hi[j]:
				return true
		return false

	## Its planks for the view: three words of eight bits a plank (lo, hi - 1).
	func words() -> Vector3:
		var w := PackedInt32Array([0, 0, 0])
		for j in SLOTS:
			var b := 15
			if lo[j] < hi[j]:
				b = lo[j] | ((hi[j] - 1) << 4)
			w[j / 3] = w[j / 3] | (b << ((j % 3) * 8))
		return Vector3(w[0], w[1], w[2])


var dice := RandomNumberGenerator.new()
var planks := {}
## Windows struck lately: face -> [at, along, amount, how, clock]; their crack
## webs: face -> View.WallMark.
var _struck := {}
var webs := {}
var _marks_out: Array = []
var _seen := -1
## Each window as last seen: 0 whole, 1 cracked in its frame, 2 shot out.
var _panes := {}
## Cells whose planks changed since the marks on them were last looked at.
var _dirty := {}
## Changes to the planks (the view's rows are made again when it moves).
var version := 0
var _rows: Array = []
var _rows_key := []
var _quiet := false
var _clink_next := 0.0
var _crack_next := 0.0
var shards_most := 14
var glints := 10


func id() -> String:
	return "wall_looks"


func attach() -> void:
	dice.seed = 2011
	var cfg := Tuning.file(PATH)
	shards_most = cfg.get_value("windows", "shards_most", 14)
	glints = cfg.get_value("windows", "glints", 10)
	_rows = blank_rows()
	if game.features.get("wall_breaks") == null:
		return
	_sync(true)
	tick_with(_tick)


func restore(_state: Dictionary) -> void:
	# What a save or a snapshot put on shows, made up quietly from the hp.
	planks.clear()
	webs.clear()
	_panes.clear()
	_seen = -1
	_sync(true)


func _breaks() -> WallBreaks:
	return game.features.get("wall_breaks")


func _wreck() -> Wreckage:
	var w: Wreckage = game.features.get("wreckage")
	return w if w != null and w.on else null


func _fx() -> WeaponFx:
	return game.features.get("weapon_fx")


func _tick(_dt: float) -> void:
	var breaks := _breaks()
	if breaks == null:
		return
	if breaks.net_version != _seen:
		_sync(false)
	if not _dirty.is_empty():
		_drop_marks()


## The fences' hp and the windows' state as they are now: knocks made up for
## hp lost that no round told of (a client, a save), planks of a fence stood
## up again (a 5v5 round) forgotten, webs for windows newly cracked.
func _sync(quiet: bool) -> void:
	var breaks := _breaks()
	_seen = breaks.net_version
	_quiet = quiet
	for cell: Vector2i in breaks.fences:
		var f: WallBreaks.Fence = breaks.fences[cell]
		var pl: Planks = planks.get(cell)
		if f.hp >= f.most:
			if pl != null:
				planks.erase(cell)
				version += 1
			continue
		if f.stage == 2:
			continue
		pl = _planks(f)
		# (A snapshot put on may have made the fence anew.)
		pl.fence = f
		var lost := f.most - f.hp
		var left := lost - pl.counted
		var dice_cell := RandomNumberGenerator.new()
		dice_cell.seed = cell.x * 7919 + cell.y * 104729 + int(lost)
		while left > f.most * .06:
			var take := minf(left, f.most * .22)
			left -= take
			pl.counted += take
			var j := dice_cell.randi_range(0, SLOTS - 1)
			var h := dice_cell.randf_range(.2, .85) * TALL
			_shot(pl, j, h, take / f.most, true)
	for face: WallBreaks.WindowFace in breaks.windows:
		var now := 0 if not face.broken else (1 if face.cracked else 2)
		var was: int = _panes.get(face, 0)
		if now == was:
			continue
		_panes[face] = now
		webs.erase(face)
		if now == 1:
			_web(face)
		elif now == 2 and not quiet:
			_shatter_window(face)
	_quiet = false


func _planks(f: WallBreaks.Fence) -> Planks:
	var pl: Planks = planks.get(f.cell)
	if pl == null:
		var world := game.world
		pl = Planks.new(f, world.ground[f.cell.y * world.width + f.cell.x])
		planks[f.cell] = pl
	return pl


# ------------------------------------------------------------------- planks


## A fence cell struck at `at` going `along`, losing `amount` of its hp
## (wall_breaks.gd _knock, as it happens; looks only).
func fence_struck(
	f: WallBreaks.Fence, at: Vector3, along: Vector2, amount: float, how: int
) -> void:
	if amount <= 0.0:
		return
	var pl := _planks(f)
	pl.counted += amount
	var p := amount / maxf(1.0, f.most)
	pl.power = p
	pl.how = how
	pl.at = at
	pl.dir = along.normalized() if along.length() > .01 else _from_eye(at)
	var h := clampf((at.z - pl.z0) / pl.span * TALL, .5, TALL - .5)
	match how:
		WallBreaks.BLAST:
			_blast(pl, at, p)
		WallBreaks.BODY:
			_body(pl, at, p)
		_:
			_shot(pl, _slot(f, at), h, p, false)


## Which plank of the cell a point is over.
func _slot(f: WallBreaks.Fence, at: Vector3) -> int:
	var along := at.x - f.cell.x if f.along_x else at.y - f.cell.y
	return clampi(floori(along * SLOTS), 0, SLOTS - 1)


## A round (a share `p` of the cell's hp) into plank j at height h: wear, then
## a chunk out round it, then the shorter end let go, then all of it. A heavy
## round wears the plank beside it too.
func _shot(pl: Planks, j: int, h: float, p: float, made_up: bool) -> void:
	pl.wear[j] += p * 5.0
	var half := (.05 + .3 * p) / pl.span * TALL * dice.randf_range(.75, 1.3)
	if not pl.gone(j):
		if pl.wear[j] < .8:
			return
		_grow(pl, j, h - half, h + half)
	else:
		var a := minf(pl.lo[j], h - half)
		var b := maxf(pl.hi[j], h + half)
		if b - a >= 6.0 or pl.wear[j] >= 2.4:
			# Broken across most of it: the shorter end lets go.
			if a < TALL - b:
				a = 0.0
			else:
				b = TALL
		if b - a >= 11.0 or pl.wear[j] >= 3.6:
			a = 0.0
			b = TALL
		_grow(pl, j, a, b)
	if p >= .4 and not made_up:
		var k := j + (1 if dice.randf() < .5 else -1)
		if k >= 0 and k < SLOTS:
			_shot(pl, k, h + dice.randf_range(-2.0, 2.0), p * .45, true)


## A blast at `at` (a share `p` of the cell's hp): the planks facing it torn
## out round its height, the nearest all of their length, ragged.
func _blast(pl: Planks, at: Vector3, p: float) -> void:
	var f := pl.fence
	var along := at.x - f.cell.x if f.along_x else at.y - f.cell.y
	var hc := clampf((at.z - pl.z0) / pl.span * TALL, 2.0, TALL - 2.0)
	for j in SLOTS:
		var d := absf((j + .5) / SLOTS - clampf(along, -.4, 1.4))
		var s := p * 1.3 - d * 1.1 + dice.randf_range(-.15, .15)
		if s <= .06:
			pl.wear[j] += maxf(0.0, s + .1) * 4.0
			continue
		var half := (.1 + .8 * s) / pl.span * TALL
		var a := hc - half * dice.randf_range(.6, 1.4)
		var b := hc + half * dice.randf_range(.6, 1.4)
		if s > .45:
			if dice.randf() < .6:
				a = 0.0
			if dice.randf() < .6:
				b = TALL
		if pl.gone(j):
			a = minf(a, pl.lo[j])
			b = maxf(b, pl.hi[j])
		_grow(pl, j, a, b)


## A body thrown into it: the planks round where it hit broken from the
## ground up past its shoulders.
func _body(pl: Planks, at: Vector3, p: float) -> void:
	var j0 := _slot(pl.fence, at)
	var top := clampf((at.z - pl.z0) / pl.span * TALL, 4.0, TALL)
	for j in range(j0 - 2, j0 + 3):
		if j < 0 or j >= SLOTS:
			continue
		var reach := top + dice.randf_range(-2.0, 2.0) - absf(j - j0) * 2.0
		if reach < 2.0 or dice.randf() > .55 + p:
			continue
		_grow(pl, j, 0.0, reach)


## Plank j knocked out from a to b (sixteenths) besides what was: what goes
## now flies as a piece of that plank.
func _grow(pl: Planks, j: int, a: float, b: float) -> void:
	var ia := clampi(floori(a), 0, TALL - 1)
	var ib := clampi(ceili(b), ia + 1, TALL)
	var was_lo := pl.lo[j]
	var was_hi := pl.hi[j]
	var had := was_lo < was_hi
	var lo := mini(was_lo, ia) if had else ia
	var hi := maxi(was_hi, ib) if had else ib
	if had and lo == was_lo and hi == was_hi:
		return
	pl.lo[j] = lo
	pl.hi[j] = hi
	version += 1
	_dirty[pl.fence.cell] = true
	if _quiet:
		return
	var gone: Array = []
	if had:
		if lo < was_lo:
			gone.append_array(_lengths(pl, lo, was_lo))
		if hi > was_hi:
			gone.append_array(_lengths(pl, was_hi, hi))
	else:
		gone = _lengths(pl, lo, hi)
	for piece: Vector2i in gone:
		_board(pl, j, piece.x, piece.y)


## A stretch of plank from a to b (sixteenths) as the lengths it breaks in:
## none longer than BOARD_LONGEST, broken at fresh places.
func _lengths(pl: Planks, a: int, b: int) -> Array:
	var out: Array = []
	var most := maxi(2, floori(BOARD_LONGEST / pl.span * TALL))
	while b - a > most:
		var cut := a + dice.randi_range(maxi(1, most / 2), most)
		out.append(Vector2i(a, cut))
		a = cut
	out.append(Vector2i(a, b))
	return out


## The piece of plank j from a to b (sixteenths) out of the wall: out the
## far side along the shot (or away from the blast), turning, and a spray of
## splinters back toward the gun.
func _board(pl: Planks, j: int, a: int, b: int) -> void:
	var f := pl.fence
	var axis := Vector2(1.0, 0.0) if f.along_x else Vector2(0.0, 1.0)
	var n := Vector2(-axis.y, axis.x)
	var mid_along := (j + .5) / SLOTS
	var line := Vector2(f.cell.x, f.cell.y) + Vector2(.5, .5) + axis * (mid_along - .5)
	var long := (b - a) / float(TALL) * pl.span
	var z := pl.z0 + (a + b) * .5 / TALL * pl.span
	var side := signf(pl.dir.dot(n))
	if side == 0.0:
		side = 1.0
	var fx := _fx()
	if fx != null:
		# Splinters back off the face it was struck on, a puff of dust.
		var near := line - n * side * .53
		for _k in 2 if pl.how == WallBreaks.SHOT else 3:
			var v: Vector3 = (
				fx.scatter(1.4, 1.2) - Vector3(n.x, n.y, 0.0) * side * dice.randf_range(.6, 1.8)
			)
			fx.spawn("splinter", Vector3(near.x, near.y, z), v, dice.randf_range(.9, 1.6), .06, 8.0)
	if game.clock >= _crack_next:
		# A board giving way (not each splinter of a load of buckshot).
		_crack_next = game.clock + .08
		game.sound_at("pierce_plank", line.x, line.y, .5)
	var wreck := _wreck()
	if wreck == null or long < .05:
		return
	var at := line + n * side * .56
	if wreck.physics.solid(Vector3(at.x, at.y, z)):
		at = line - n * side * .56
		side = -side
	var power := clampf(pl.power, .15, 1.5)
	var hard := 2.6 if pl.how == WallBreaks.BLAST else 1.0
	var out := Vector3(n.x, n.y, 0.0) * side
	var v := (
		out * dice.randf_range(.8, 1.6) * (1.0 + 2.5 * power) * hard
		+ Vector3(axis.x, axis.y, 0.0) * dice.randf_range(-.6, .6)
		+ Vector3(0.0, 0.0, dice.randf_range(.3, 1.4) * hard)
	)
	var w := (
		Vector3(axis.x, axis.y, 0.0) * dice.randf_range(-9.0, 9.0)
		+ Vector3(dice.randf_range(-3.0, 3.0), dice.randf_range(-3.0, 3.0), 0.0)
	)
	wreck.new_group()
	wreck.throw_shaped(
		_board_key(f),
		j,
		Vector3(at.x, at.y, z),
		Quaternion(_frame(Vector3(axis.x, axis.y, 0.0))),
		Basis.from_scale(Vector3(1.0, 1.0, long)),
		Vector3(.5 / SLOTS, BOARD_THICK, long * .5),
		v,
		w,
		"debris_settle"
	)


## The board a fence's planks are cut from: its own tile's columns (the
## stockyard's posts and rails left out: plain planks).
func _board_key(f: WallBreaks.Fence) -> String:
	var name := String(game.world.tile_names[f.tile])
	if name == "stockyard" or name == "cover_boards":
		name = "wood"
	return BOARD % name


## A cell gone through (wreckage.gd _knock_fence): what is left of its planks
## over the stumps bursts out along the shot or away from the blast, broken
## at fresh places; the stockyard's rails go in halves.
func fence_staged(f: WallBreaks.Fence, _was: int) -> void:
	if f.stage < 2:
		return
	var pl := _planks(f)
	planks.erase(f.cell)
	version += 1
	var wreck := _wreck()
	if wreck == null:
		return
	if pl.dir == Vector2.ZERO:
		var c := Vector3(f.cell.x + .5, f.cell.y + .5, pl.z0 + pl.span * .5)
		pl.dir = _from_eye(c)
	var stump := dice.randi_range(2, 4)
	var bits: Array = []
	for j in SLOTS:
		var ranges: Array = []
		if not pl.gone(j):
			ranges.append([stump, TALL])
		else:
			if pl.lo[j] > stump + 1:
				ranges.append([stump, pl.lo[j]])
			if pl.hi[j] < TALL - 1:
				ranges.append([maxi(pl.hi[j], stump), TALL])
		for r: Array in ranges:
			var a: int = r[0]
			var b: int = r[1]
			# Whole lengths where they can (a board reads; a stick of it less).
			for piece: Vector2i in _lengths(pl, a, b):
				bits.append(PackedInt32Array([j, piece.x, piece.y]))
	# The longest fly as boards; the rest go as splinters.
	bits.sort_custom(_longer)
	var most: int = f.spec.get("pieces_most", 8)
	if wreck.most <= 20:
		most = mini(most, 4)
	wreck.new_group()
	pl.power = maxf(pl.power, .5)
	for k in mini(bits.size(), most):
		var bit: PackedInt32Array = bits[k]
		_burst_board(pl, bit[0], bit[1], bit[2])
	if String(game.world.tile_names[f.tile]) == "stockyard":
		_rails(pl)


static func _longer(m: PackedInt32Array, k: PackedInt32Array) -> bool:
	return m[2] - m[1] > k[2] - k[1]


## One board of a cell gone through: from where it stood, out along the shot
## (away from the blast and up), turning end over end.
func _burst_board(pl: Planks, j: int, a: int, b: int) -> void:
	var f := pl.fence
	var wreck := _wreck()
	var axis := Vector2(1.0, 0.0) if f.along_x else Vector2(0.0, 1.0)
	var along := Vector3(axis.x, axis.y, 0.0)
	var long := (b - a) / float(TALL) * pl.span
	# From where it stood, drawn in a little off the cells beside it.
	var centre := Vector2(f.cell.x + .5, f.cell.y + .5) + axis * ((j + .5) / SLOTS - .5) * .8
	var z := pl.z0 + (a + b) * .5 / TALL * pl.span
	var at := Vector3(centre.x, centre.y, z)
	var blast := pl.how == WallBreaks.BLAST
	var way := Vector3(pl.dir.x, pl.dir.y, 0.0)
	if blast:
		var from := Vector3(pl.at.x, pl.at.y, at.z)
		way = (at - from)
		way.z = 0.0
		way = way.normalized() if way.length() > .05 else Vector3(pl.dir.x, pl.dir.y, 0.0)
	var speed := (2.0 + 3.0 * clampf(pl.power, .3, 1.5)) * (1.8 if blast else 1.0)
	var v := (
		way * speed * dice.randf_range(.6, 1.3)
		+ along * dice.randf_range(-1.2, 1.2)
		+ Vector3(0.0, 0.0, dice.randf_range(.5, 2.0) * (1.6 if blast else 1.0))
	)
	var w := (
		along.cross(Vector3(0, 0, 1)) * dice.randf_range(-12.0, 12.0)
		+ along * dice.randf_range(-4.0, 4.0)
	)
	wreck.throw_shaped(
		_board_key(f),
		j,
		at,
		Quaternion(_frame(along)),
		Basis.from_scale(Vector3(1.0, 1.0, long)),
		Vector3(.5 / SLOTS, BOARD_THICK, long * .5),
		v,
		w,
		"debris_settle"
	)


## The stockyard's rails broken in halves, two of the three flying.
func _rails(pl: Planks) -> void:
	var f := pl.fence
	var wreck := _wreck()
	var key := "t:stockyard@1,%.2f|%s" % [f.top, str(f.spec.get("pieces", "fence:6"))]
	var parts := WreckCuts.parts(game.art, key)
	var axis := Vector3(1, 0, 0) if f.along_x else Vector3(0, 1, 0)
	var turn := _frame(axis)
	var centre := Vector3(f.cell.x + .5, f.cell.y + .5, pl.z0)
	for i in range(6, parts.size()):
		if dice.randf() < .34:
			continue
		var part: WreckCuts.Part = parts[i]
		for half_k in 2:
			var off := (half_k - .5) * .5
			var at := centre + turn * (part.centre + Vector3(off, 0.0, 0.0))
			var v := (
				Vector3(pl.dir.x, pl.dir.y, 0.0) * dice.randf_range(1.5, 3.5)
				+ Vector3(0.0, 0.0, dice.randf_range(.5, 1.6))
			)
			var w := axis.cross(Vector3(0, 0, 1)) * dice.randf_range(-8.0, 8.0)
			wreck.throw_shaped(
				key,
				i,
				at,
				Quaternion(turn),
				Basis.from_scale(Vector3(.5, 1.0, 1.0)),
				Vector3(part.half.x * .5, part.half.y, part.half.z),
				v,
				w,
				"debris_settle"
			)


## Holes on planks knocked out from under them go with them.
func _drop_marks() -> void:
	var kept: Array = []
	var dropped := false
	for item: Variant in game.wall_marks:
		var mark: View.WallMark = item
		var cell := Vector2i(floori(mark.x), floori(mark.y))
		var pl: Planks = null
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var c := cell + Vector2i(dx, dy)
				if pl == null and _dirty.has(c) and planks.has(c):
					var near: Planks = planks[c]
					var f := near.fence
					if (
						mark.x > f.cell.x - .03
						and mark.x < f.cell.x + 1.03
						and mark.y > f.cell.y - .03
						and mark.y < f.cell.y + 1.03
					):
						pl = near
		if pl != null:
			var j := _slot(pl.fence, Vector3(mark.x, mark.y, 0.0))
			var h := (mark.z - pl.z0) / pl.span * TALL
			if pl.gone(j) and h > pl.lo[j] - .7 and h < pl.hi[j] + .7:
				dropped = true
				continue
		kept.append(mark)
	_dirty.clear()
	if dropped:
		game.wall_marks.assign(kept)


## The planks for the view (world_view.gd), the MOST cells nearest (x, y):
## four rows of view_data, [cell x, cell y, ground, height (less than 0:
## the fence runs along y)] and [the planks' three words, 0] by turns.
func view_rows(x: float, y: float) -> Array:
	var key := [floori(x), floori(y), version]
	if key == _rows_key:
		return _rows
	_rows_key = key
	var near: Array = []
	for cell: Vector2i in planks:
		var pl: Planks = planks[cell]
		if pl.fence.stage < 2 and pl.any():
			near.append([Vector2(cell.x + .5 - x, cell.y + .5 - y).length_squared(), pl])
	near.sort_custom(_nearer)
	_rows = blank_rows()
	for k in mini(near.size(), MOST):
		var item: Array = near[k]
		var pl: Planks = item[1]
		var f := pl.fence
		var cells: PackedVector4Array = _rows[0 if k < 16 else 2]
		var words: PackedVector4Array = _rows[1 if k < 16 else 3]
		cells[k % 16] = Vector4(f.cell.x, f.cell.y, pl.z0, pl.span if f.along_x else -pl.span)
		var wd := pl.words()
		words[k % 16] = Vector4(wd.x, wd.y, wd.z, 0.0)
		_rows[0 if k < 16 else 2] = cells
		_rows[1 if k < 16 else 3] = words
	return _rows


static func _nearer(a: Array, b: Array) -> bool:
	var da: float = a[0]
	var db: float = b[0]
	return da < db


static func blank_rows() -> Array:
	var out: Array = []
	for r in 4:
		var row := PackedVector4Array()
		row.resize(16)
		row.fill(BLANK if r % 2 == 0 else Vector4.ZERO)
		out.append(row)
	return out


# ------------------------------------------------------------------ windows


## A window struck at `at` going `along` (wall_breaks.gd, before it cracks or
## goes: a blast's `at` is where it went off).
func window_struck(
	face: WallBreaks.WindowFace, at: Vector3, along: Vector2, amount: float, how: int
) -> void:
	_struck[face] = [at, along, amount, how, game.clock]


## Where on the glass a window was struck, as (along its face from its
## middle, height), and how: [hit, along, power, how] (nothing lately: a
## made-up spot, as from this machine's eye).
func _window_hit(face: WallBreaks.WindowFace) -> Array:
	var a := Vector2(face.edge.x, face.edge.y)
	var b := Vector2(face.edge.z, face.edge.w)
	var long := a.distance_to(b)
	var axis := (b - a) / maxf(long, .01)
	var mid := face.middle()
	var x0 := (WallBreaks.ACROSS.x - .5) * long + .03
	var x1 := (WallBreaks.ACROSS.y - .5) * long - .03
	var row: Array = _struck.get(face, [])
	var when: float = row[4] if not row.is_empty() else -99.0
	if not row.is_empty() and game.clock - when <= HIT_TIME:
		var at: Vector3 = row[0]
		var amount: float = row[2]
		var how: int = row[3]
		var u := clampf((Vector2(at.x, at.y) - mid).dot(axis), x0, x1)
		var z := clampf(at.z, face.low + .03, face.high - .03)
		var power := clampf(amount / (90.0 if how == WallBreaks.BLAST else 45.0), .25, 1.6)
		return [Vector2(u, z), row[1], power, how]
	var hit := Vector2(
		lerpf(x0, x1, dice.randf_range(.25, .75)),
		lerpf(face.low + .03, face.high - .03, dice.randf_range(.3, .7))
	)
	var c := Vector3(mid.x, mid.y, hit.y)
	var from := _from_eye(c)
	return [hit, from, .5, WallBreaks.SHOT]


## A window's light first round (wall_breaks.gd: broken, held cracked in its
## frame): its crack web laid where it struck, as big as the glass round that
## spot allows (fx_glass_web_<n>: wall_mark_art.gd).
func _web(face: WallBreaks.WindowFace) -> void:
	var a := Vector2(face.edge.x, face.edge.y)
	var b := Vector2(face.edge.z, face.edge.w)
	var long := a.distance_to(b)
	var axis := (b - a) / maxf(long, .01)
	var hit: Vector2 = _window_hit(face)[0]
	var x0 := (WallBreaks.ACROSS.x - .5) * long
	var x1 := (WallBreaks.ACROSS.y - .5) * long
	var room := minf(minf(hit.x - x0, x1 - hit.x), minf(hit.y - face.low, face.high - hit.y))
	var mark := View.WallMark.new()
	var at := face.middle() + axis * hit.x
	mark.x = at.x
	mark.y = at.y
	mark.z = hit.y
	mark.ux = axis.x
	mark.uy = axis.y
	mark.radius = clampf(room + .05, .09, .24)
	mark.image = "fx_glass_web_%d" % dice.randi_range(0, 3)
	mark.material = "glass"
	webs[face] = mark


## A window's glass shot out (seen in _sync: at once by a big round, a
## blast or a body, or the round after it cracked): its pane cut fresh round
## where it was struck, the smallest pieces near the hole thrown as glints,
## the rest (up to shards_most, the biggest) as shards flying from the hole
## by the round's or the blast's force; a blast tears its frame out too.
func _shatter_window(face: WallBreaks.WindowFace) -> void:
	var row := _window_hit(face)
	_struck.erase(face)
	var hit: Vector2 = row[0]
	var power: float = row[2]
	var how: int = row[3]
	var a := Vector2(face.edge.x, face.edge.y)
	var b := Vector2(face.edge.z, face.edge.w)
	var long := a.distance_to(b)
	var axis2 := (b - a) / maxf(long, .01)
	var axis := Vector3(axis2.x, axis2.y, 0.0)
	var n2 := face.normal()
	var out := Vector3(n2.x, n2.y, 0.0)
	var mid2 := face.middle() + n2 * .035
	var mid := Vector3(mid2.x, mid2.y, 0.0)
	var up := Vector3(0.0, 0.0, 1.0)
	var rect := Rect2(
		(WallBreaks.ACROSS.x - .5) * long,
		face.low,
		(WallBreaks.ACROSS.y - WallBreaks.ACROSS.x) * long,
		face.high - face.low
	)
	var cut := cut_pane(rect, hit, how == WallBreaks.BLAST, dice)
	var inner: Array = cut[0]
	var rest: Array = cut[1]
	rest.sort_custom(_bigger)
	var wreck := _wreck()
	var most := shards_most
	if wreck != null and wreck.most <= 20:
		most = mini(most, 6)
	var lit := String(game.world.tile_names[face.whole]).ends_with("_lit")
	var key := GLASS_LIT if lit else GLASS
	_templates()
	var blast := how == WallBreaks.BLAST
	if wreck != null:
		wreck.new_group()
	var turn := _frame(axis)
	var q := Quaternion(turn)
	var fx := _fx()
	var glinted := 0
	for k in rest.size() + inner.size():
		var tri: PackedVector2Array = rest[k] if k < rest.size() else inner[k - rest.size()]
		var g := (tri[0] + tri[1] + tri[2]) / 3.0
		var world := mid + axis * g.x + up * g.y
		var r := g - hit
		var rd := maxf(r.length(), .02)
		var radial := axis * (r.x / rd) + up * (r.y / rd)
		var v: Vector3
		if blast:
			v = (
				radial * dice.randf_range(1.5, 3.5) * power
				+ out * dice.randf_range(1.0, 3.0) * power
				+ up * dice.randf_range(.4, 1.8) * power
			)
		else:
			v = (
				radial * power * 1.1 / (.12 + rd) * dice.randf_range(.5, 1.1)
				+ out * dice.randf_range(.25, 1.0) * (.6 + power)
				+ up * dice.randf_range(0.0, .6)
			)
		if k < rest.size() and k < most and wreck != null:
			var shard := _shard(tri, g)
			var shape: Basis = shard[0]
			var half: Vector3 = shard[1]
			var about: PackedVector2Array = shard[2]
			var spin := (
				Vector3(dice.randf_range(-1, 1), dice.randf_range(-1, 1), dice.randf_range(-1, 1))
				* dice.randf_range(5.0, 16.0)
			)
			wreck.throw_shaped(key, 0, world, q, shape, half, v, spin, "glass_settle", about)
		elif fx != null and glinted < glints:
			glinted += 1
			fx.spawn("glint", world, v * .8, dice.randf_range(3.0, 6.0), .03, 9.0)
	if blast and wreck != null and face.blasted:
		_frame_sticks(rect, mid, axis, out, power)


## A pane `rect` (along its face, height) cut round `hit`: rays from the hole
## to the frame, two rings round it, each wobbling. Returns [the pieces in
## the inner ring, the rest], each a triangle of three corners. A blast's has
## more rays and wider rings (it tears the whole pane, not round a hole).
static func cut_pane(rect: Rect2, hit: Vector2, blast: bool, rng: RandomNumberGenerator) -> Array:
	var h := Vector2(
		clampf(hit.x, rect.position.x + .01, rect.end.x - .01),
		clampf(hit.y, rect.position.y + .01, rect.end.y - .01)
	)
	var rays := rng.randi_range(9, 12) if blast else rng.randi_range(7, 10)
	var start := rng.randf_range(0.0, TAU)
	var angles: Array[float] = []
	for k in rays:
		angles.append(start + (k + rng.randf_range(-.32, .32)) * TAU / rays)
	var r1 := rng.randf_range(.03, .05) * (1.6 if blast else 1.0)
	var r2 := rng.randf_range(.1, .16) * (1.4 if blast else 1.0)
	var ends: Array[Vector2] = []
	var ring1: Array[Vector2] = []
	var ring2: Array[Vector2] = []
	for a: float in angles:
		var d := Vector2(cos(a), sin(a))
		var reach := _exit(rect, h, d)
		ends.append(h + d * reach)
		var q1 := minf(r1 * rng.randf_range(.7, 1.3), reach * .3)
		var q2 := minf(r2 * rng.randf_range(.7, 1.35), reach * .75)
		ring1.append(h + d * q1)
		ring2.append(h + d * maxf(q2, q1 + .01))
	var corners: Array[Vector2] = [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y)
	]
	var inner: Array = []
	var rest: Array = []
	for k in rays:
		var k2 := (k + 1) % rays
		inner.append(PackedVector2Array([h, ring1[k], ring1[k2]]))
		rest.append(PackedVector2Array([ring1[k], ring2[k], ring2[k2]]))
		rest.append(PackedVector2Array([ring1[k], ring2[k2], ring1[k2]]))
		# The outer piece: from the ring out to the frame, round any corner
		# between the two rays, fanned from the ring.
		var poly := PackedVector2Array([ring2[k], ends[k]])
		var a0 := angles[k]
		var a1 := angles[k2] if k2 > k else angles[k2] + TAU
		var between: Array = []
		for c: Vector2 in corners:
			var ca := atan2(c.y - h.y, c.x - h.x)
			while ca < a0:
				ca += TAU
			if ca < a1:
				between.append([ca, c])
		between.sort_custom(_nearer)
		for item: Array in between:
			var corner: Vector2 = item[1]
			poly.append(corner)
		poly.append(ends[k2])
		poly.append(ring2[k2])
		for i in range(1, poly.size() - 1):
			var tri := PackedVector2Array([poly[0], poly[i], poly[i + 1]])
			if _area(tri) > .0004:
				rest.append(tri)
	# No piece bigger than a hand: the big ones split along their longest side.
	var k := 0
	while k < rest.size():
		var tri: PackedVector2Array = rest[k]
		if _area(tri) <= SHARD_MOST:
			k += 1
			continue
		var at := 0
		var longest := 0.0
		for i in 3:
			var d := tri[i].distance_to(tri[(i + 1) % 3])
			if d > longest:
				longest = d
				at = i
		var m := tri[at].lerp(tri[(at + 1) % 3], rng.randf_range(.35, .65))
		rest[k] = PackedVector2Array([tri[at], m, tri[(at + 2) % 3]])
		rest.append(PackedVector2Array([m, tri[(at + 1) % 3], tri[(at + 2) % 3]]))
	return [inner, rest]


## How far from `from` along `d` the line leaves `rect`.
static func _exit(rect: Rect2, from: Vector2, d: Vector2) -> float:
	var t := INF
	if d.x > 1e-5:
		t = minf(t, (rect.end.x - from.x) / d.x)
	elif d.x < -1e-5:
		t = minf(t, (rect.position.x - from.x) / d.x)
	if d.y > 1e-5:
		t = minf(t, (rect.end.y - from.y) / d.y)
	elif d.y < -1e-5:
		t = minf(t, (rect.position.y - from.y) / d.y)
	return maxf(t, .005)


static func _bigger(m: PackedVector2Array, k: PackedVector2Array) -> bool:
	return _area(m) > _area(k)


static func _area(tri: PackedVector2Array) -> float:
	return absf((tri[1] - tri[0]).cross(tri[2] - tri[0])) * .5


## A triangle (corners along the face, up) about its middle `g` as the
## template drawn through a shape: [shape, box half, corners about g].
static func _shard(tri: PackedVector2Array, g: Vector2) -> Array:
	var ab := tri[1] - tri[0]
	var ac := tri[2] - tri[0]
	var shape := Basis(Vector3(ab.x, 0.0, ab.y), Vector3(0.0, 1.0, 0.0), Vector3(ac.x, 0.0, ac.y))
	var hx := 0.0
	var hz := 0.0
	var about := PackedVector2Array()
	for p: Vector2 in tri:
		var o := p - g
		about.append(o)
		hx = maxf(hx, absf(o.x))
		hz = maxf(hz, absf(o.y))
	return [shape, Vector3(maxf(hx, .012), .012, maxf(hz, .012)), about]


## A shard that hit the ground hard (wreckage.gd _glass_lands, already let
## go): a big one breaks in two or three where it lies, a small one (or a
## piece of one) into glints lying where it fell, with a tinkle.
func shatter(w: Wreckage.Wreck) -> void:
	var b := w.body
	if game.clock >= _clink_next:
		_clink_next = game.clock + .12
		game.sound_at("glass_settle", b.p.x, b.p.y, .3)
	var wreck := _wreck()
	var turn := Basis(b.q)
	if w.breaks < 1 and _area(w.tri) > SPLIT_AREA and wreck != null:
		var tri := w.tri
		# Split at the middle of its longest side (and the bigger half again).
		var k := 0
		var longest := 0.0
		for i in 3:
			var d := tri[i].distance_to(tri[(i + 1) % 3])
			if d > longest:
				longest = d
				k = i
		var m := tri[k].lerp(tri[(k + 1) % 3], dice.randf_range(.35, .65))
		var halves := [
			PackedVector2Array([tri[k], m, tri[(k + 2) % 3]]),
			PackedVector2Array([m, tri[(k + 1) % 3], tri[(k + 2) % 3]])
		]
		wreck.new_group()
		for piece: PackedVector2Array in halves:
			var g := (piece[0] + piece[1] + piece[2]) / 3.0
			var shard := _shard(piece, g)
			var shape: Basis = shard[0]
			var half: Vector3 = shard[1]
			var about: PackedVector2Array = shard[2]
			var at := b.p + turn * Vector3(g.x, 0.0, g.y) + Vector3(0.0, 0.0, .02)
			var v := (
				Vector3(b.v.x, b.v.y, 0.0) * .35
				+ Vector3(dice.randf_range(-1.0, 1.0), dice.randf_range(-1.0, 1.0), 0.0)
				+ Vector3(0.0, 0.0, dice.randf_range(.6, 1.6))
			)
			var spin := (
				Vector3(dice.randf_range(-1, 1), dice.randf_range(-1, 1), dice.randf_range(-1, 1))
				* dice.randf_range(4.0, 12.0)
			)
			var made := wreck.throw_shaped(w.key, 0, at, b.q, shape, half, v, spin, w.clink, about)
			if made != null:
				made.breaks = w.breaks + 1
		return
	var fx := _fx()
	if fx == null:
		return
	for _k in dice.randi_range(2, 4):
		var v := Vector3(dice.randf_range(-1.0, 1.0), dice.randf_range(-1.0, 1.0), 0.0) * .9
		v.z = dice.randf_range(.3, 1.0)
		fx.spawn("glint", b.p + Vector3(0, 0, .02), v, dice.randf_range(3.0, 6.0), .028, 9.0)


## A blast's window: its frame's sticks torn out and flying, splintered.
func _frame_sticks(rect: Rect2, mid: Vector3, axis: Vector3, out: Vector3, power: float) -> void:
	var wreck := _wreck()
	var up := Vector3(0.0, 0.0, 1.0)
	var turn := _frame(axis)
	var q := Quaternion(turn)
	var sticks: Array = [
		[Vector2(rect.get_center().x, rect.end.y + .02), rect.size.x, 0.0],
		[Vector2(rect.get_center().x, rect.position.y - .02), rect.size.x, 0.0],
		[Vector2(rect.position.x - .02, rect.get_center().y), rect.size.y, PI * .5],
		[Vector2(rect.end.x + .02, rect.get_center().y), rect.size.y, PI * .5],
		[rect.get_center(), rect.size.y, PI * .5],
	]
	for s: Array in sticks:
		if dice.randf() < .25:
			continue
		var at2: Vector2 = s[0]
		var full: float = s[1]
		var roll: float = s[2]
		# Each torn in one or two lengths.
		var parts := 2 if full > .4 and dice.randf() < .6 else 1
		for k in parts:
			var long := full / parts * dice.randf_range(.7, 1.0)
			var off := (k + .5) / parts - .5
			var along := Vector2(full * off, 0.0) if roll == 0.0 else Vector2(0.0, full * off)
			var at := mid + out * .03 + axis * (at2.x + along.x) + up * (at2.y + along.y)
			var lay := Quaternion(turn * Basis(Vector3(0, 1, 0), roll))
			var v := (
				out * dice.randf_range(1.5, 3.5) * power
				+ axis * dice.randf_range(-1.5, 1.5)
				+ up * dice.randf_range(.5, 2.0)
			)
			var spin := (
				Vector3(dice.randf_range(-1, 1), dice.randf_range(-1, 1), dice.randf_range(-1, 1))
				* dice.randf_range(6.0, 14.0)
			)
			wreck.throw_shaped(
				STICK,
				0,
				at,
				lay,
				Basis.from_scale(Vector3(long, 1.0, 1.0)),
				Vector3(long * .5, .015, .022),
				v,
				spin,
				"debris_settle"
			)


## The pieces' templates, made once: a triangle of glass (corners (0, 0),
## (1, 0), (0, 1) about their middle, a shape stretches it to any triangle)
## and a frame's stick a cell long.
func _templates() -> void:
	if not WreckCuts.has(GLASS):
		WreckCuts.put(GLASS, [_glass_part()])
		WreckCuts.put(GLASS_LIT, [_glass_part()])
	if not WreckCuts.has(STICK):
		var stick := WreckCuts.board(
			Rect2(-.5, -.022, 1.0, .044), Rect2(0, 0, 1, 1), .03, Vector2(32, 8)
		)
		stick.centre = Vector3.ZERO
		WreckCuts.put(STICK, [stick])


## The template triangle as a thin prism: the picture's triangle (its pale
## rim on the long side) on both faces, its edges the rim's colour.
static func _glass_part() -> WreckCuts.Part:
	var part := WreckCuts.Part.new()
	var third := 1.0 / 3.0
	var corners: Array[Vector2] = [
		Vector2(-third, -third), Vector2(1.0 - third, -third), Vector2(-third, 1.0 - third)
	]
	var uvs: Array[Vector2] = [Vector2(.06, .94), Vector2(.94, .94), Vector2(.06, .06)]
	var t := .008
	for side: float in [-1.0, 1.0]:
		for k in 3:
			var c := corners[k]
			part.verts.append(Vector3(c.x, t * side, c.y))
			part.normals.append(Vector3(0.0, side, 0.0))
			part.uvs.append(uvs[k])
	for k in 3:
		var ca := corners[k]
		var cb := corners[(k + 1) % 3]
		var edge := Vector3(cb.x - ca.x, 0.0, cb.y - ca.y).cross(Vector3(0, 1, 0)).normalized()
		var quad: Array[Vector3] = [
			Vector3(ca.x, -t, ca.y),
			Vector3(cb.x, -t, cb.y),
			Vector3(cb.x, t, cb.y),
			Vector3(ca.x, t, ca.y)
		]
		for i: int in [0, 1, 2, 0, 2, 3]:
			part.verts.append(quad[i])
			part.normals.append(edge)
			part.uvs.append(Vector2(.5, .5))
	part.half = Vector3(.5, t, .5)
	return part


## A frame running x along `axis`, z up.
static func _frame(axis: Vector3) -> Basis:
	var up := Vector3(0.0, 0.0, 1.0)
	return Basis(axis, up.cross(axis), up)


## Along the line from this machine's eye to `at` (looks only), flat.
func _from_eye(at: Vector3) -> Vector2:
	var p := game.local_player if game.local_player != null else game.player
	if p != null:
		var d := Vector2(at.x - p.x, at.y - p.y)
		if d.length() > .05:
			return d.normalized()
	return Vector2(1.0, 0.0)


func wall_marks() -> Array:
	_marks_out.clear()
	for face: WallBreaks.WindowFace in webs:
		if face.cracked:
			_marks_out.append(webs[face])
	return _marks_out
