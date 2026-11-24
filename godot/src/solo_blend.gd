## Single player drawn between ticks (pass 14). The game ticks 120 times a
## second (MainState.SIM_STEP) while a screen draws up to 240 frames: drawn
## as it stood after its last tick, the view, the gun, the hands, the shots
## and the pieces held still one frame in six at 144 Hz and every other frame
## at 240, then stepped (tools/frame_smooth.gd). Each frame this puts what
## moves where it was part way between the last two ticks drawn, at the
## share of a tick the front end's accumulator holds (main.gd _solo_draw):
## pass 12's NetBlend (src/net/net_blend.gd: its ticks, span and share, its
## teleport rule, its forget) with more in it. Besides the players, the
## hands and the shots it blends the game's clock (so every look run on it,
## the hands' animations and the ragdolls, the shaders' time, runs smoothly
## too), the view's jolts and shake, the gun's sway and its timers (raised,
## lowered, a reload, a shot's cycle), the wreck pieces and their fine bits,
## the casings and chips, the gibs, the blasts, the vehicles and the hound.
## Specks and puffs (sparks, blood, smoke) still step a tick at a time: many,
## small and short-lived, they cost more than they show.
##
## The player's own turn is not blended: the mouse played by the ticks
## drawn is shown whole and the mouse not yet played added (as the next
## tick will turn it), so the view turns every frame by what the mouse did
## and the crosshair is where the next shot goes; only the rest of a turn (a
## vehicle coming round) is blended.
##
## Looks only: put on for the frame (main.gd net_draw_begin) and put back
## exactly after it (net_draw_end), so the game and what it plays never
## change; a tick boundary (a share of 1) draws the game as it stands.
class_name SoloBlend
extends NetBlend

const Wreckage := preload("res://src/features/wreckage.gd")
const Debris := preload("res://src/features/debris.gd")
const VariantsFeature := preload("res://src/features/variants_feature.gd")

## Off: single player drawn as it stands after its last tick (v3.11.0;
## frame_smooth `old`).
static var on := true
## A turn of the player's own between two ticks bigger than this (radians)
## that the mouse did not make is a cut (a respawn, a seat taken): drawn
## where it ends.
const CUT_TURN := .6
## The hands blended: those within SEEN cells ahead of the last frame's eye
## and its view's width and WIDER (a share of the distance) to each side,
## by REACH more (sprites()'s own sums: none is drawn past them), looked for
## again every LOOK_EVERY ticks (the whole list each tick cost more than the
## rest of the blend on hickston's hundred).
const SEEN := 51.0
const REACH := 3.5
const WIDER := .6
const LOOK_EVERY := 4
## A gun timer that moved more than this between the ticks drawn was started
## again (a new shot, a reload begun): drawn as it is.
const TIMER_JUMP := .1
## A casing or a gib slower than this (cells a second) moves less than a
## thousandth of a cell a tick: left as it is (they roll slowly a long while).
const SLOW := .1

## The few things, by the object itself (_rows): a row is its numbers, kind
## first, in a PackedFloat64Array.
enum { PLAYER, ARMS, CLOCK, BLAST, RIDE, DOG }

## The mouse's turn and look the ticks played since the last tick drawn
## (turned()), and those of the span drawn now.
var _turned := 0.0
var _looked := 0.0
var _span_turn := 0.0
var _span_look := 0.0
## The many things, a Swarm each: the hands near the view, the shots, the
## gibs, the casings and chips, the wreck pieces and their fine bits.
var _hands := Swarm.new(8)
var _shots := Swarm.new(3)
var _gibs := Swarm.new(5)
var _bits := Swarm.new(3)
var _bodies := Swarm.new(7)
var _fines := Swarm.new(4)
## The wreck's fine bits (their view writes them again when one was blended).
var _debris: WreckDebris = null
## The hands near the view (_look), and the tick they were looked for at.
var _near: Array[Enemy] = []
var _looked_at := -1


## One kind of many things: their numbers each tick in one flat array,
## `stride` a thing, each matched to its place in the tick before by order
## (the game's lists keep theirs: things come at the end and go from
## anywhere). A call a thing and a Dictionary row each cost three times this.
class Swarm:
	extends RefCounted
	## Things looked past for one gone since the tick before.
	const AHEAD := 4
	var stride := 3
	var things: Array = []
	var vals := PackedFloat64Array()
	var was_things: Array = []
	var was_vals := PackedFloat64Array()
	## Each thing's place in was_vals, or -1 (new).
	var from := PackedInt32Array()
	## The things put part way this frame (their index).
	var moved := PackedInt32Array()

	func _init(n: int) -> void:
		stride = n

	## The tick's things go to the tick before; `keep` false: forgotten.
	func roll(keep: bool) -> void:
		was_things = things if keep else []
		was_vals = vals if keep else PackedFloat64Array()
		things = []
		vals = PackedFloat64Array()

	## Each thing matched to the tick before: just ahead of the last match,
	## else (many gone at once) looked up.
	func pair() -> void:
		var n := things.size()
		from.resize(n)
		var have := was_things.size()
		var index := {}
		var p := 0
		for i in n:
			var it: Object = things[i]
			var found := -1
			for q in range(p, mini(p + AHEAD, have)):
				if was_things[q] == it:
					found = q
					break
			if found < 0 and p + AHEAD < have:
				if index.is_empty():
					for q in have:
						index[was_things[q]] = q
				found = index.get(it, -1)
			if found >= 0:
				from[i] = found * stride
				p = found + 1
			else:
				from[i] = -1

	func clear() -> void:
		roll(false)
		from.clear()
		moved.clear()


## A tick played the mouse's `turn` and `look` (main.gd advance).
func turned(turn: float, look: float) -> void:
	_turned += turn
	_looked += look


## Draws `game` at `at` ticks (a share between its last two; `tick` the
## ticks it has played), `me` (the player the mouse turns, or null) turned
## by the mouse not yet played (`turn`, `look`). Call end() after the frame.
func draw(game: Game, tick: int, at: float, me: Player, turn: float, look: float) -> void:
	_moved.clear()
	last_share = -1.0
	if not on or game == null:
		forget()
		return
	if _game == null or _game.get_ref() != game:
		forget()
		_game = weakref(game)
	# The one draw-time cache play's snapshot keeps (opener.gd CACHES) taken
	# by the tick's clock, as an unblended draw would.
	var doors: VariantsFeature = game.features.get("variants")
	if doors != null:
		doors.look_for_doors(game.clock)
	if tick != _cur_tick:
		var keep := _cur_tick >= 0 and tick > _cur_tick and tick - _cur_tick <= MOST_SPAN
		if _looked_at < 0 or tick - _looked_at >= LOOK_EVERY or tick < _looked_at:
			_look(game)
			_looked_at = tick
		var now := _rows(game, keep)
		_prev = _cur if keep else {}
		_prev_tick = _cur_tick if keep else -1
		_cur = now
		_cur_tick = tick
		_span_turn = _turned
		_span_look = _looked
		_turned = 0.0
		_looked = 0.0
	if not _prev.is_empty() and at >= 0.0:
		var share := clampf((at - _prev_tick) / float(_cur_tick - _prev_tick), 0.0, 1.0)
		last_share = share
		if share < 1.0:
			for key: Object in _cur:
				var row: PackedFloat64Array = _cur[key]
				var was: PackedFloat64Array = _prev.get(key, row)
				if was != row and _place(key, was, row, share):
					_moved.append(key)
			_place_hands(share)
			_place_points(share)
			_place_bodies(share)
	if not _fines.moved.is_empty():
		_debris.version += 1
	if me != null and me.health > 0 and not NetPredict.held(game):
		_aim(me, turn, look)


## The player the mouse turns: the mouse the ticks drawn played shown whole
## (where the next shot goes), the rest of their turn (a vehicle's) blended,
## and the mouse not yet played added.
func _aim(me: Player, turn: float, look: float) -> void:
	if not _cur.has(me):
		return
	var row: PackedFloat64Array = _cur[me]
	var angle := row[3]
	var pitch := row[4]
	if _moved.has(me):
		var was: PackedFloat64Array = _prev[me]
		var left := 1.0 - last_share
		angle -= (angle_difference(was[3], angle) - _span_turn) * left
		pitch -= (pitch - was[4] - _span_look) * left
	else:
		_moved.append(me)
	me.angle = fposmod(angle + turn, TAU)
	me.pitch = clampf(pitch + look, -53.0, 53.0)


## Everything put back where the game has it.
func end() -> void:
	for key: Object in _moved:
		var row: PackedFloat64Array = _cur[key]
		_back(key, row)
	_moved.clear()
	_back_all()


func forget() -> void:
	super()
	last_share = -1.0
	_turned = 0.0
	_looked = 0.0
	_near.clear()
	_looked_at = -1
	for swarm: Swarm in [_hands, _shots, _gibs, _bits, _bodies, _fines]:
		swarm.clear()


## The hands near enough the last frame's view cone to be drawn (sprites()'s
## cone written out: a call each was most of the cost).
func _look(game: Game) -> void:
	_near.clear()
	var cone := game.view_cone
	if cone.size() != 7:
		_near.assign(game.enemies)
		return
	var cx := cone[0]
	var cy := cone[1]
	var fx := cone[2]
	var fy := cone[3]
	var k := cone[4] + WIDER
	var edge := cone[5]
	var mx := cone[6]
	for e: Enemy in game.enemies:
		var dx := e.x - cx
		var dy := e.y - cy
		var d := dx * fx + dy * fy
		if d > -REACH and d < SEEN + REACH and absf(dy * fx - dx * fy) < (d + REACH) * k + REACH:
			_near.append(e)
			continue
		if is_nan(edge) or e.x + REACH < edge:
			continue
		dx = e.x - mx
		d = -dx * fx + dy * fy
		if d > -REACH and d < SEEN + REACH and absf(dy * fx + dx * fy) < (d + REACH) * k + REACH:
			_near.append(e)


## What moves this tick: the few by the object itself (the players and their
## guns, the clock, the blasts, the vehicles, the hound), the many in their
## swarms; `keep`: the tick before is kept to blend from.
func _rows(game: Game, keep: bool) -> Dictionary:
	var out := {}
	var rides: Game.VehiclesScript = game.features.get("vehicles")
	for p: Player in game.players:
		if p.away:
			continue
		var seated := 1.0 if rides != null and rides.seated(p) else 0.0
		out[p] = PackedFloat64Array(
			[
				PLAYER,
				p.x,
				p.y,
				p.angle,
				p.pitch,
				p.eye,
				p.air,
				p.bob,
				p.sway,
				p.walk_phase,
				p.motion,
				p.drift,
				p.weapon_lag.x,
				p.weapon_lag.y,
				p.weapon_turn,
				seated
			]
		)
		var arms := p.armory
		if arms != null:
			out[arms] = PackedFloat64Array(
				[
					ARMS,
					arms.lower,
					arms.switch,
					arms.reload,
					arms.shot_age,
					arms.jab_age,
					arms.flash,
					arms.active,
					arms.leaving
				]
			)
	var kick := game.view_kick
	out[game] = PackedFloat64Array([CLOCK, game.clock, kick.x, kick.y, kick.z, game.shake])
	for b: GameState.Blast in game.blasts:
		out[b] = PackedFloat64Array([BLAST, b.x, b.y, b.age])
	if rides != null:
		for r: VehicleDrive.Ride in rides.rides:
			out[r] = PackedFloat64Array([RIDE, r.x, r.y, r.z, r.h, r.steer])
	var hound: Game.HoundScript = game.features.get("hound")
	if hound != null:
		for d: Game.HoundScript.Dog in hound.dogs:
			out[d] = PackedFloat64Array([DOG, d.x, d.y, d.floor_z, d.angle, d.gait])
	_read_swarms(game, keep)
	return out


## The many things' numbers this tick, each swarm matched to the last.
func _read_swarms(game: Game, keep: bool) -> void:
	for swarm: Swarm in [_hands, _shots, _gibs, _bits, _bodies, _fines]:
		swarm.roll(keep)
	var h := _hands.vals
	for e: Enemy in _near:
		_hands.things.append(e)
		var floats := e.brain == "saucer" or e.brain == "skeeter" or e.brain == "lantern"
		h.append_array([e.x, e.y, e.angle, e.gait, e.hop, e.climb_z, e.sunk])
		h.append(e.pose if floats else 0.0)
	_hands.vals = h
	var s := _shots.vals
	for shot: GameState.Shot in game.shots:
		_shots.things.append(shot)
		s.append_array([shot.x, shot.y, shot.z])
	_shots.vals = s
	var g := _gibs.vals
	for gib: Gore.Gib in game.gore_fx.gibs:
		if not gib.rest and absf(gib.vx) + absf(gib.vy) + absf(gib.vz) > SLOW:
			_gibs.things.append(gib)
			g.append_array([gib.x, gib.y, gib.z, gib.spin, gib.roll])
	_gibs.vals = g
	var loose: Debris = game.features.get("debris")
	if loose != null:
		var c := _bits.vals
		for bit: Debris.Bit in loose.bits:
			if not bit.rest and absf(bit.vx) + absf(bit.vy) + absf(bit.vz) > SLOW:
				_bits.things.append(bit)
				c.append_array([bit.x, bit.y, bit.z])
		_bits.vals = c
	var wreck: Wreckage = game.features.get("wreckage")
	_debris = wreck.debris if wreck != null else null
	if wreck != null:
		var w := _bodies.vals
		for piece: Wreckage.Wreck in wreck.wrecks:
			var body := piece.body
			if body.awake:
				_bodies.things.append(body)
				var p := body.p
				var q := body.q
				w.append_array([p.x, p.y, p.z, q.x, q.y, q.z, q.w])
		_bodies.vals = w
		var f := _fines.vals
		for bit: WreckDebris.Bit in _debris.bits:
			if not bit.resting:
				_fines.things.append(bit)
				var p := bit.p
				f.append_array([p.x, p.y, p.z, bit.angle])
		_fines.vals = f
	for swarm: Swarm in [_hands, _shots, _gibs, _bits, _bodies, _fines]:
		swarm.pair()


func _place_hands(s: float) -> void:
	var sw := _hands
	sw.moved.clear()
	var a := sw.was_vals
	var b := sw.vals
	for i in sw.things.size():
		var j := sw.from[i]
		var k := i * 8
		if j < 0 or absf(b[k] - a[j]) + absf(b[k + 1] - a[j + 1]) > TELEPORT:
			continue
		if (
			a[j] == b[k]
			and a[j + 1] == b[k + 1]
			and a[j + 2] == b[k + 2]
			and a[j + 3] == b[k + 3]
			and a[j + 4] == b[k + 4]
			and a[j + 5] == b[k + 5]
			and a[j + 6] == b[k + 6]
			and a[j + 7] == b[k + 7]
		):
			continue
		var e: Enemy = sw.things[i]
		e.x = a[j] + (b[k] - a[j]) * s
		e.y = a[j + 1] + (b[k + 1] - a[j + 1]) * s
		e.angle = _turn(a[j + 2], b[k + 2], s)
		e.gait = a[j + 3] + (b[k + 3] - a[j + 3]) * s
		if a[j + 4] != b[k + 4]:
			e.hop = a[j + 4] + (b[k + 4] - a[j + 4]) * s
		if a[j + 5] != b[k + 5]:
			e.climb_z = a[j + 5] + (b[k + 5] - a[j + 5]) * s
		if a[j + 6] != b[k + 6]:
			e.sunk = a[j + 6] + (b[k + 6] - a[j + 6]) * s
		if a[j + 7] != b[k + 7]:
			e.pose = a[j + 7] + (b[k + 7] - a[j + 7]) * s
		sw.moved.append(i)


## The shots, gibs, casings and fine bits: a place each (and a gib's turn).
func _place_points(s: float) -> void:
	for sw: Swarm in [_shots, _gibs, _bits, _fines]:
		sw.moved.clear()
		var a := sw.was_vals
		var b := sw.vals
		var n := sw.stride
		for i in sw.things.size():
			var j := sw.from[i]
			var k := i * n
			if j < 0 or absf(b[k] - a[j]) + absf(b[k + 1] - a[j + 1]) > TELEPORT:
				continue
			var x := a[j] + (b[k] - a[j]) * s
			var y := a[j + 1] + (b[k + 1] - a[j + 1]) * s
			var z := a[j + 2] + (b[k + 2] - a[j + 2]) * s
			if sw == _shots:
				var shot: GameState.Shot = sw.things[i]
				shot.x = x
				shot.y = y
				shot.z = z
			elif sw == _gibs:
				var gib: Gore.Gib = sw.things[i]
				gib.x = x
				gib.y = y
				gib.z = z
				gib.spin = a[j + 3] + (b[k + 3] - a[j + 3]) * s
				gib.roll = a[j + 4] + (b[k + 4] - a[j + 4]) * s
			elif sw == _bits:
				var bit: Debris.Bit = sw.things[i]
				bit.x = x
				bit.y = y
				bit.z = z
			else:
				var fine: WreckDebris.Bit = sw.things[i]
				fine.p = Vector3(x, y, z)
				fine.angle = a[j + 3] + (b[k + 3] - a[j + 3]) * s
			sw.moved.append(i)


func _place_bodies(s: float) -> void:
	var sw := _bodies
	sw.moved.clear()
	var a := sw.was_vals
	var b := sw.vals
	for i in sw.things.size():
		var j := sw.from[i]
		var k := i * 7
		if j < 0:
			continue
		var p0 := Vector3(a[j], a[j + 1], a[j + 2])
		var p1 := Vector3(b[k], b[k + 1], b[k + 2])
		if p0.distance_squared_to(p1) > TELEPORT * TELEPORT:
			continue
		var q0 := Quaternion(a[j + 3], a[j + 4], a[j + 5], a[j + 6])
		var q1 := Quaternion(b[k + 3], b[k + 4], b[k + 5], b[k + 6])
		if p0 == p1 and q0 == q1:
			continue
		var body: PhysCore.Body = sw.things[i]
		body.p = p0.lerp(p1, s)
		body.q = q0.slerp(q1, s)
		sw.moved.append(i)


## The many things put back as the tick left them.
func _back_all() -> void:
	var b := _hands.vals
	for i: int in _hands.moved:
		var k := i * 8
		var e: Enemy = _hands.things[i]
		e.x = b[k]
		e.y = b[k + 1]
		e.angle = b[k + 2]
		e.gait = b[k + 3]
		e.hop = b[k + 4]
		e.climb_z = b[k + 5]
		e.sunk = b[k + 6]
		if b[k + 7] != 0.0:
			e.pose = b[k + 7]  # (a floating one's; the rest keep theirs)
	_hands.moved.clear()
	for sw: Swarm in [_shots, _gibs, _bits, _fines]:
		b = sw.vals
		var n := sw.stride
		for i: int in sw.moved:
			var k := i * n
			if sw == _shots:
				var shot: GameState.Shot = sw.things[i]
				shot.x = b[k]
				shot.y = b[k + 1]
				shot.z = b[k + 2]
			elif sw == _gibs:
				var gib: Gore.Gib = sw.things[i]
				gib.x = b[k]
				gib.y = b[k + 1]
				gib.z = b[k + 2]
				gib.spin = b[k + 3]
				gib.roll = b[k + 4]
			elif sw == _bits:
				var bit: Debris.Bit = sw.things[i]
				bit.x = b[k]
				bit.y = b[k + 1]
				bit.z = b[k + 2]
			else:
				var fine: WreckDebris.Bit = sw.things[i]
				fine.p = Vector3(b[k], b[k + 1], b[k + 2])
				fine.angle = b[k + 3]
		if sw == _fines and not sw.moved.is_empty():
			_debris.version += 1
		sw.moved.clear()
	b = _bodies.vals
	for i: int in _bodies.moved:
		var k := i * 7
		var body: PhysCore.Body = _bodies.things[i]
		body.p = Vector3(b[k], b[k + 1], b[k + 2])
		body.q = Quaternion(b[k + 3], b[k + 4], b[k + 5], b[k + 6])
	_bodies.moved.clear()


## Puts `who` part way (`s`) from row `a` to row `b`; false when it is drawn
## where it is (a jump: a respawn, a seat taken or left, a gun changed).
func _place(who: Object, a: PackedFloat64Array, b: PackedFloat64Array, s: float) -> bool:
	if absf(b[1] - a[1]) + absf(b[2] - a[2]) > TELEPORT:
		return false  # (the clock's and a gun's [1] and [2] never jump so far)
	match int(b[0]):
		PLAYER:
			if a[15] != b[15] or absf(angle_difference(a[3], b[3])) > CUT_TURN + absf(_span_turn):
				return false
			# (Only what moved: most of these stand still most ticks.)
			var p: Player = who
			p.x = a[1] + (b[1] - a[1]) * s
			p.y = a[2] + (b[2] - a[2]) * s
			if a[3] != b[3]:
				p.angle = _turn(a[3], b[3], s)
			if a[4] != b[4]:
				p.pitch = a[4] + (b[4] - a[4]) * s
			if a[5] != b[5]:
				p.eye = a[5] + (b[5] - a[5]) * s
			if a[6] != b[6]:
				p.air = a[6] + (b[6] - a[6]) * s
			if a[7] != b[7]:
				p.bob = a[7] + (b[7] - a[7]) * s
			if a[8] != b[8]:
				p.sway = a[8] + (b[8] - a[8]) * s
			if a[9] != b[9]:
				p.walk_phase = a[9] + (b[9] - a[9]) * s
			if a[10] != b[10]:
				p.motion = a[10] + (b[10] - a[10]) * s
			if a[11] != b[11]:
				p.drift = a[11] + (b[11] - a[11]) * s
			if a[12] != b[12] or a[13] != b[13]:
				p.weapon_lag = Vector2(a[12] + (b[12] - a[12]) * s, a[13] + (b[13] - a[13]) * s)
			if a[14] != b[14]:
				p.weapon_turn = a[14] + (b[14] - a[14]) * s
		ARMS:
			# Each timer blended unless it was started again; none when the
			# gun changed.
			if a[7] != b[7] or a[8] != b[8]:
				return false
			var arms: Weapons.Armory = who
			arms.lower = _timer(a[1], b[1], s)
			arms.switch = _timer(a[2], b[2], s)
			arms.reload = _timer(a[3], b[3], s)
			arms.shot_age = _timer(a[4], b[4], s)
			arms.jab_age = _timer(a[5], b[5], s)
			arms.flash = _timer(a[6], b[6], s)
		CLOCK:
			var game: Game = who
			game.clock = a[1] + (b[1] - a[1]) * s
			game.view_kick = Vector3(
				a[2] + (b[2] - a[2]) * s, a[3] + (b[3] - a[3]) * s, a[4] + (b[4] - a[4]) * s
			)
			game.shake = a[5] + (b[5] - a[5]) * s
		BLAST:
			var blast: GameState.Blast = who
			blast.age = a[3] + (b[3] - a[3]) * s
		RIDE:
			var r: VehicleDrive.Ride = who
			r.x = a[1] + (b[1] - a[1]) * s
			r.y = a[2] + (b[2] - a[2]) * s
			r.z = a[3] + (b[3] - a[3]) * s
			r.h = _turn(a[4], b[4], s)
			r.steer = a[5] + (b[5] - a[5]) * s
		DOG:
			var d: Game.HoundScript.Dog = who
			d.x = a[1] + (b[1] - a[1]) * s
			d.y = a[2] + (b[2] - a[2]) * s
			d.floor_z = a[3] + (b[3] - a[3]) * s
			d.angle = _turn(a[4], b[4], s)
			d.gait = a[5] + (b[5] - a[5]) * s
	return true


## Puts `who` back as row `b` has it (what _place put on, exactly).
func _back(who: Object, b: PackedFloat64Array) -> void:
	match int(b[0]):
		PLAYER:
			var p: Player = who
			p.x = b[1]
			p.y = b[2]
			p.angle = b[3]
			p.pitch = b[4]
			p.eye = b[5]
			p.air = b[6]
			p.bob = b[7]
			p.sway = b[8]
			p.walk_phase = b[9]
			p.motion = b[10]
			p.drift = b[11]
			p.weapon_lag = Vector2(b[12], b[13])
			p.weapon_turn = b[14]
		ARMS:
			var arms: Weapons.Armory = who
			arms.lower = b[1]
			arms.switch = b[2]
			arms.reload = b[3]
			arms.shot_age = b[4]
			arms.jab_age = b[5]
			arms.flash = b[6]
		CLOCK:
			var game: Game = who
			game.clock = b[1]
			game.view_kick = Vector3(b[2], b[3], b[4])
			game.shake = b[5]
		BLAST:
			var blast: GameState.Blast = who
			blast.age = b[3]
		RIDE:
			var r: VehicleDrive.Ride = who
			r.x = b[1]
			r.y = b[2]
			r.z = b[3]
			r.h = b[4]
			r.steer = b[5]
		DOG:
			var d: Game.HoundScript.Dog = who
			d.x = b[1]
			d.y = b[2]
			d.floor_z = b[3]
			d.angle = b[4]
			d.gait = b[5]


## A gun timer part way, or where it is now when it jumped (started again).
static func _timer(v0: float, v1: float, s: float) -> float:
	return v1 if absf(v1 - v0) > TIMER_JUMP else v0 + (v1 - v0) * s
