## Deterministic replays: a run kept as where it started (a snapshot of the
## game, GameSnapshot, or a fresh game and its seed) and then each tick's
## controls for every player, played back by feeding them to a fresh Game.
## Play is deterministic (gameplay dice only from game.rng, events synchronous,
## a fixed tick), so the same start and the same controls give the same run.
##
##   var rec := Replay.record(game, options, setup)   # before the first tick
##   rec.tick(dt, controls)       # just before game.tick(dt, controls)
##   rec.ticked()                 # just after it
##   rec.act(["select", 3])       # an action between ticks: recorded and done
##   var bytes := rec.to_bytes()  # or Replay.from_bytes(bytes)
##   var pb := Replay.Playback.new(rep)
##   var g := pb.start(Callable(main, "make_game"))
##   while pb.step(): pass        # pb.diverged: the first tick a hash differed
##
## A recording is a list of segments, each from a keyframe (a snapshot; the
## first may instead be a fresh game) with its stream of entries: a tick's
## controls (only the fields that changed, by slot), a run of ticks with the
## controls unchanged, an action between ticks (`OPS`), the state's hash every
## HASH_EVERY ticks, a snapshot when something outside the tick and the
## recorded actions touched the game (a cheat, the console: found by `probe`
## differing from what the last tick or action left), and the end. The whole
## run is kept from the start up to `cap_ticks`; past that the recording rolls
## on in segments of `roll_ticks`, the newest `keep_roll` kept, so a saved
## replay is the run's start plus its last few minutes.
##
## Recording only reads the game: a keyframe's capture names nothing new (the
## uids it would hand out are taken back), and the hashes only read.
class_name Replay
extends RefCounted

const VERSION := 1
const MAGIC := "CLRP"
## A hash of the state every this many ticks (a second at the game's 120 Hz).
const HASH_EVERY := 120
## The whole run up to here (30 minutes at 120 Hz); then segments roll.
const CAP_TICKS := 216000
## A rolling segment (a minute), and how many of the newest are kept.
const ROLL_TICKS := 7200
const KEEP_ROLL := 5

## Entries in a segment's stream (a byte each, then their own payload).
const T_SAME := 1
const T_TICK := 2
const T_OP := 3
const T_HASH := 4
const T_SNAP := 5
const T_END := 6

## A slot's controls as compared tick to tick: forward, strafe, turn, look,
## the buttons as bits, weapon, item, buy, cycle, rewind.
const F_FORWARD := 0
const F_STRAFE := 1
const F_TURN := 2
const F_LOOK := 3
const F_BITS := 4
const F_WEAPON := 5
const F_ITEM := 6
const F_BUY := 7
const F_CYCLE := 8
const F_REWIND := 9
const FIELD_COUNT := 10
## The idle controls every slot starts a segment from.
const IDLE := [0.0, 0.0, 0.0, 0.0, 0, -1, -1, -1, 0, 0]
## How a float is written: its common values in the tag alone.
const V_ZERO := 0
const V_ONE := 1
const V_MINUS := 2
const V_F32 := 3
const V_F64 := 4

## The actions between ticks a recording knows (apply_op does each).
const OPS := [
	"use",
	"select",
	"cycle",
	"item",
	"reload",
	"holster",
	"turn_back",
	"pitch0",
	"pocket",
	"county",
	"county_pause",
	"options",
	"local",
	"step",
]

## {v, build, level, layout, step, setup: {mode, count, options}, made, seed,
## god, history, fresh}.
var header := {}
## Each {first, ticks, snap (bytes; empty for a fresh start), options, local,
## data (the stream)}.
var segments: Array = []
## Why it was saved (death, end, crash, asked) and the tick it ends on.
var reason := ""

# ------------------------------------------------------------- recording
var game: Game = null
## Ticks recorded so far (the next tick's number).
var ticks := 0
var cap_ticks := CAP_TICKS
var roll_ticks := ROLL_TICKS
var keep_roll := KEEP_ROLL
## Snapshots taken because the game was touched outside the recorded actions.
var touches := 0
## Microseconds spent recording (ticks, actions, hashes; keyframes apart).
var spent_us := 0
var keyframe_us := 0
var _out: StreamPeerBuffer = null
var _seg: Dictionary = {}
var _seg_ticks := 0
var _roll_due := false
var _same := 0
var _prev := {}
var _slots := PackedInt32Array()
var _expected := 0
var _options := {}
var _step := 0.0
var _local := 0
var _scratch := PackedByteArray()


## Starts recording `g` now (before its next tick): `options` are the
## settings it was configured with, `setup` its mode {mode, count, options}.
## `fresh`: the game is as Game.new made it, configured, set up and seeded
## (rng state `seed_state`), so no snapshot is kept (tools).
static func record(
	g: Game, options: Dictionary, setup := {}, fresh := false, seed_state := -1
) -> Replay:
	var rec := Replay.new()
	rec.game = g
	rec._options = options.duplicate()
	rec._step = 0.0
	rec.header = {
		"v": VERSION,
		"build": str(ProjectSettings.get_setting("application/config/version", "?")),
		"level": g.level.id,
		"layout": g.level.layout,
		"setup": setup.duplicate(true),
		"made": int(Time.get_unix_time_from_system()),
		"fresh": fresh,
		"seed": seed_state if seed_state >= 0 else g.rng.state,
		"god": g.cheats.god,
		"history": g.history.duplicate(true),
		"slots": g.players.size(),
		# The physics detail steps some play (src/core/quality.gd): played back at it.
		"quality": Quality.physics,
	}
	rec._scratch.resize(8)
	rec._begin_segment(not fresh)
	return rec


## The tick about to be played: `controls` as game.tick takes them (one
## Controls for the local player, or slot -> Controls). `check`: whether
## anything outside the tick may have run since the last one (false for a
## frame's second tick and on: the probe is skipped, the costliest part).
func tick(dt: float, controls: Variant, check := true) -> void:
	var t0 := Time.get_ticks_usec()
	var kf0 := keyframe_us
	if _roll_due:
		# Past the cap: a new segment from a keyframe of the game as it is now.
		_roll_due = false
		_begin_segment(true)
		_drop_old()
	elif check and Replay.probe(game) != _expected:
		_touched()
	if dt != _step:
		_put_op(["step", dt])
		_step = dt
	var local: int = game.local_player.slot
	if local != _local:
		_local = local
		_put_op(["local", _local])
	if not controls is Dictionary:
		# One player's controls (the campaign): compared with the last tick's.
		var c: Game.Controls = controls
		var row := _row(c)
		if _slots.size() == 1 and _slots[0] == local and row == _prev[local]:
			_same += 1
		else:
			_write_tick(PackedInt32Array([local]), [row])
		spent_us += Time.get_ticks_usec() - t0 - (keyframe_us - kf0)
		return
	var by_slot: Dictionary = controls
	var keys: Array = by_slot.keys()
	keys.sort()
	var slots := PackedInt32Array(keys)
	var rows: Array = []
	var changed := slots != _slots
	for slot: int in keys:
		var each: Game.Controls = by_slot[slot]
		var row := _row(each)
		rows.append(row)
		if not changed and row != _prev[slot]:
			changed = true
	if changed:
		_write_tick(slots, rows)
	else:
		_same += 1
	spent_us += Time.get_ticks_usec() - t0 - (keyframe_us - kf0)


## The tick was played: the state it left (`settle`: probed, for the next
## tick's check; false when the next tick is the same frame's), a hash now
## and then, and a new segment past the cap (begun before the next tick).
func ticked(settle := true) -> void:
	var t0 := Time.get_ticks_usec()
	ticks += 1
	_seg_ticks += 1
	_seg["ticks"] = _seg_ticks
	if settle:
		_expected = Replay.probe(game)
	if ticks % HASH_EVERY == 0:
		_flush_same()
		_out.put_u8(T_HASH)
		_out.put_u32(Replay.state_hash(game))
	if ticks >= cap_ticks and _seg_ticks >= roll_ticks:
		_roll_due = true
	spent_us += Time.get_ticks_usec() - t0


## A tick whose controls differ from the last: each slot's changed fields.
func _write_tick(slots: PackedInt32Array, rows: Array) -> void:
	_flush_same()
	_out.put_u8(T_TICK)
	_out.put_u8(slots.size())
	for i in slots.size():
		var row: Array = rows[i]
		var before: Array = _prev.get(slots[i], IDLE)
		var mask := 0
		for f in FIELD_COUNT:
			if row[f] != before[f]:
				mask |= 1 << f
		_out.put_u8(slots[i])
		_put_var(mask)
		for f in FIELD_COUNT:
			if mask & (1 << f):
				_put_field(f, row[f])
		_prev[slots[i]] = row
	_slots = slots


## An action between ticks (OPS): recorded, then done. Returns what it gave.
func act(op: Array) -> Variant:
	note(op)
	var out: Variant = Replay.apply_op(game, op)
	_expected = Replay.probe(game)
	return out


## An action between ticks already done by the caller (a setting changed):
## recorded to be done again at the same place in playback.
func note(op: Array) -> void:
	if Replay.probe(game) != _expected:
		_touched()
	_put_op(op)
	if not OPS.has(str(op[0])):
		push_warning("replay: unknown action %s" % str(op[0]))


## Which ticks the kept segments cover, as text.
func covers() -> String:
	var parts: PackedStringArray = []
	for seg: Dictionary in segments:
		var first: int = seg["first"]
		var n: int = seg["ticks"]
		parts.append("%d-%d" % [first, first + n])
	return ", ".join(parts)


## The last tick recorded (the end of the newest segment).
func last_tick() -> int:
	if segments.is_empty():
		return 0
	var seg: Dictionary = segments[segments.size() - 1]
	var first: int = seg["first"]
	var n: int = seg["ticks"]
	return first + n


func _row(c: Game.Controls) -> Array:
	var bits := (
		int(c.running)
		| int(c.fire) << 1
		| int(c.alt_fire) << 2
		| int(c.jump) << 3
		| int(c.crouch) << 4
		| int(c.use) << 5
		| int(c.hold) << 6
		| int(c.reload) << 7
	)
	return [c.forward, c.strafe, c.turn, c.look, bits, c.weapon, c.item, c.buy, c.cycle, c.rewind]


func _touched() -> void:
	# Something outside the tick and the recorded actions changed the game: a
	# snapshot of it as it is now, put back at this place in playback.
	touches += 1
	_flush_same()
	var t0 := Time.get_ticks_usec()
	var snap := GameSnapshot.to_bytes(Replay.capture_quiet(game))
	keyframe_us += Time.get_ticks_usec() - t0
	_out.put_u8(T_SNAP)
	_put_var(snap.size())
	_out.put_data(snap)
	_expected = Replay.probe(game)


func _put_op(op: Array) -> void:
	_flush_same()
	var bytes := var_to_bytes(op)
	_out.put_u8(T_OP)
	_put_var(bytes.size())
	_out.put_data(bytes)


func _flush_same() -> void:
	if _same > 0:
		_out.put_u8(T_SAME)
		_put_var(_same)
		_same = 0


func _put_var(v: int) -> void:
	while v >= 128:
		_out.put_u8((v & 127) | 128)
		v >>= 7
	_out.put_u8(v)


func _put_field(f: int, v: Variant) -> void:
	if f <= F_LOOK:
		var x: float = v
		_scratch.encode_double(0, x)
		if x == 0.0 and _scratch[7] < 128:
			_out.put_u8(V_ZERO)
		elif x == 1.0:
			_out.put_u8(V_ONE)
		elif x == -1.0:
			_out.put_u8(V_MINUS)
		else:
			_scratch.encode_float(0, x)
			if _scratch.decode_float(0) == x:
				_out.put_u8(V_F32)
				_out.put_float(x)
			else:
				_out.put_u8(V_F64)
				_out.put_double(x)
	elif f == F_BITS:
		var bits: int = v
		_out.put_u8(bits)
	else:
		var n: int = v
		_put_var((n << 1) ^ (n >> 63))  # zigzag: -1 is one byte


## Closes the segment being written and starts the next from a keyframe (a
## snapshot of the game now) or, the first of a fresh recording, from nothing.
func _begin_segment(snap: bool) -> void:
	_close_segment()
	var bytes := PackedByteArray()
	if snap:
		var t0 := Time.get_ticks_usec()
		bytes = GameSnapshot.to_bytes(Replay.capture_quiet(game))
		keyframe_us += Time.get_ticks_usec() - t0
	_seg = {
		"first": ticks,
		"ticks": 0,
		"snap": bytes,
		"options": _options.duplicate(),
		"local": game.local_player.slot,
		"step": _step,
		"data": PackedByteArray(),
	}
	_seg_ticks = 0
	segments.append(_seg)
	_out = StreamPeerBuffer.new()
	_prev = {}
	_slots = PackedInt32Array()
	_same = 0
	_local = game.local_player.slot
	_expected = Replay.probe(game)


func _close_segment() -> void:
	if _out != null and not _seg.is_empty():
		_flush_same()
		_seg["data"] = _out.data_array


## The rolling segments past the newest keep_roll go (the run's start stays).
func _drop_old() -> void:
	var rolling: Array[int] = []
	for i in segments.size():
		var seg: Dictionary = segments[i]
		var first: int = seg["first"]
		if first >= cap_ticks:
			rolling.append(i)
	while rolling.size() > keep_roll:
		var gone: int = rolling.pop_front()
		segments.remove_at(gone)
		for k in rolling.size():
			rolling[k] -= 1


## Something changed the game that the probe may not see (the dev console):
## a snapshot of it now, put back here in playback.
func touch() -> void:
	_touched()


## Options changed mid-run: the next keyframe carries them too.
func set_options(options: Dictionary) -> void:
	_options = options.duplicate()
	note(["options", _options])


# ------------------------------------------------------------- the file


## The recording as a file's bytes (it can go on recording after).
func to_bytes() -> PackedByteArray:
	return Replay.bytes_of(pack())


## The recording as plain values, put together on the main thread (cheap:
## the streams are shared, not copied); bytes_of() packs them anywhere.
func pack() -> Dictionary:
	var segs: Array = []
	for seg: Dictionary in segments:
		var copy := seg.duplicate()
		if is_same(seg, _seg) and _out != null:
			_flush_same()
			copy["data"] = _out.data_array
		segs.append(copy)
	var end := {"ticks": ticks, "reason": reason}
	if game != null and Replay.probe(game) == _expected:
		# The state the last tick left (untouched since): a playback's end.
		end["hash"] = Replay.state_hash(game)
	return {"header": header, "segments": segs, "end": end}


## A pack() as a file's bytes: MAGIC, the size, the values (zstd).
static func bytes_of(data: Dictionary) -> PackedByteArray:
	var raw := var_to_bytes(data)
	var out := MAGIC.to_ascii_buffer()
	out.resize(8)
	out.encode_u32(4, raw.size())
	out.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD))
	return out


## A replay from a file's bytes (null when they are not one).
static func from_bytes(bytes: PackedByteArray) -> Replay:
	if bytes.size() < 8 or bytes.slice(0, 4).get_string_from_ascii() != MAGIC:
		return null
	var size := bytes.decode_u32(4)
	var raw := bytes.slice(8).decompress(size, FileAccess.COMPRESSION_ZSTD)
	var parsed: Variant = bytes_to_var(raw)
	if not parsed is Dictionary:
		return null
	var data: Dictionary = parsed
	var rep := Replay.new()
	rep.header = data.get("header", {})
	rep.segments = data.get("segments", [])
	var end: Dictionary = data.get("end", {})
	rep.reason = str(end.get("reason", ""))
	rep.header["end"] = end
	var v: int = rep.header.get("v", 0)
	if rep.segments.is_empty() or v > VERSION:
		return null
	return rep


static func load_file(path: String) -> Replay:
	if not FileAccess.file_exists(path):
		return null
	return from_bytes(FileAccess.get_file_as_bytes(path))


func save_file(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(to_bytes())
	f.close()
	return true


# ------------------------------------------------------------- the state


## What the front end can change between ticks, as one number: each player's
## place, view, health, gun and pockets, the dice, the count of enemies and
## shots, god mode. Read before every tick and action; a change since the
## last one means the game was touched outside them.
static func probe(g: Game) -> int:
	var a: Array = [
		g.rng.state, g.enemies.size(), g.shots.size(), g.cheats.god, g.keys.size(), g.touch_aim
	]
	for p: Player in g.players:
		var arm: Weapons.Armory = p.armory
		(
			a
			. append(
				[
					p.x,
					p.y,
					p.eye,
					p.angle,
					p.pitch,
					p.vx,
					p.vy,
					p.health,
					p.inventory_slot,
					p.inventory,
					arm.active,
					arm.holstered,
					arm.loaded,
					arm.reserve,
					arm.owned,
				]
			)
		)
	return hash(a)


## The state's hash a playback compares: the probe, the clock, the kills and
## every enemy's place and health.
static func state_hash(g: Game) -> int:
	var f := PackedFloat64Array()
	f.append(g.clock)
	f.append(g.kills)
	f.append(g.next_uid)
	for p: Player in g.players:
		f.append(p.vx)
		f.append(p.vy)
		f.append(p.floor_z)
	for e: Enemy in g.enemies:
		f.append(e.x)
		f.append(e.y)
		f.append(e.hp)
		f.append(e.angle)
	for s: GameState.Shot in g.shots:
		f.append(s.x)
		f.append(s.y)
	return hash([Replay.probe(g), f]) & 0xFFFFFFFF


## GameSnapshot.capture without its side effect: the uids it hands to things
## made since the last tick are taken back (the tick's end names them, in its
## own order, as if nothing had looked).
static func capture_quiet(g: Game) -> Dictionary:
	var next := g.next_uid
	var named := g._named_enemies
	var fresh: Array = []
	for e: Enemy in g.enemies:
		if e.uid == 0:
			fresh.append(e)
	for s: GameState.Shot in g.shots:
		if s.uid == 0:
			fresh.append(s)
	var snap := GameSnapshot.capture(g)
	for thing: Object in fresh:
		thing.set("uid", 0)
	g.next_uid = next
	g._named_enemies = named
	return snap


## Does one recorded action on `g` (what the front end does on a key).
static func apply_op(g: Game, op: Array) -> Variant:
	var what := str(op[0])
	var arg: int = op[1] if op.size() > 1 and op[1] is int else -1
	match what:
		"use":
			g.interact()
		"select":
			g.armory.select(arg, g)
		"cycle":
			g.armory.cycle(arg, g)
		"item":
			g.use_item(arg)
		"reload":
			if g.armory.start_reload(g):
				g.barks.say(g, "reload")
				return true
			return false
		"holster":
			g.armory.holstered = not g.armory.holstered
		"turn_back":
			g.player.angle = fposmod(g.player.angle + PI, TAU)
		"pitch0":
			g.player.pitch = 0.0
		"hound":
			g.hound_call()
		"pocket":
			g.inventory_slot = arg
		"county":
			var slot: int = op[2]
			return CountyMode.choose(g, arg, slot)
		"county_pause":
			var run := CountyMode.run(g)
			if run != null:
				run.paused = arg == 1
		"options":
			var options: Dictionary = op[1]
			g.configure(options)
		"local":
			if arg >= 0 and arg < g.players.size():
				Players.set_local(g, g.players[arg])
	return null


# ------------------------------------------------------------- playback


## Plays a Replay onto a fresh Game, one tick per step().
class Playback:
	extends RefCounted

	var rep: Replay
	var game: Game = null
	## Ticks played (the number of the next).
	var tick := 0
	## The first tick a hash differed at (-1: none), and the last that matched.
	var diverged := -1
	var last_good := 0
	var hashes := 0
	## Keyframes put on (a gap between kept segments, or a touch).
	var jumps := 0
	var done := false
	var note := ""
	var _maker := Callable()
	var _seg_i := -1
	var _in: StreamPeerBuffer = null
	var _prev := {}
	var _same := 0
	var _step := 1.0 / 120.0
	## The slots the current controls are for (the others stand idle).
	var _slots: Array = []

	func _init(r: Replay) -> void:
		rep = r

	## Makes the game (`maker`: level id -> Game, main.make_game) as the
	## replay's first segment starts it.
	func start(maker: Callable) -> Game:
		_maker = maker
		var seg: Dictionary = rep.segments[0]
		var quality: int = rep.header.get("quality", Quality.physics)
		Quality.physics = quality
		game = maker.call(str(rep.header["level"]))
		var options: Dictionary = seg["options"]
		game.configure(options)
		var setup: Dictionary = rep.header.get("setup", {})
		var mode := str(setup.get("mode", Modes.CAMPAIGN))
		if mode != Modes.CAMPAIGN and mode != "":
			var count: int = setup.get("count", 1)
			var mode_options: Dictionary = setup.get("options", {})
			Modes.setup(game, mode, count, mode_options)
		var snap: PackedByteArray = seg["snap"]
		if snap.is_empty():
			var seed_state: int = rep.header["seed"]
			game.rng.set_state(seed_state)
			var god: bool = rep.header.get("god", false)
			game.cheats.god = god
			var history: Array = rep.header.get("history", [])
			game.history = history.duplicate(true)
		elif not GameSnapshot.apply(game, GameSnapshot.from_bytes(snap)):
			note = "the replay's level does not match this build's"
			done = true
			return game
		_local(seg)
		var build := str(rep.header.get("build", "?"))
		if build != str(ProjectSettings.get_setting("application/config/version", "?")):
			note = "recorded on %s" % build
		_open(0)
		return game

	## Plays the next tick (and the actions before it). False at the end.
	func step() -> bool:
		while not done:
			if _same > 0:
				_same -= 1
				_play()
				return true
			if _in == null or _in.get_position() >= _in.get_size():
				if not _next_segment():
					_finish()
					return false
				continue
			var tag := _in.get_u8()
			match tag:
				T_SAME:
					_same = _get_var()
				T_TICK:
					var n := _in.get_u8()
					_slots = []
					for _i in n:
						var slot := _in.get_u8()
						var mask := _get_var()
						var before: Array = _prev.get(slot, IDLE)
						var row := before.duplicate()
						for f in FIELD_COUNT:
							if mask & (1 << f):
								row[f] = _get_field(f)
						_prev[slot] = row
						_slots.append(slot)
					_play()
					return true
				T_OP:
					var size := _get_var()
					var got: Array = _in.get_data(size)
					var raw: PackedByteArray = got[1]
					var op: Variant = bytes_to_var(raw)
					if op is Array:
						var action: Array = op
						if str(action[0]) == "step":
							_step = action[1]
						else:
							Replay.apply_op(game, action)
				T_HASH:
					var want := _in.get_u32()
					hashes += 1
					if Replay.state_hash(game) == want:
						if diverged < 0:
							last_good = tick
					elif diverged < 0:
						diverged = tick
				T_SNAP:
					var size := _get_var()
					var snap: PackedByteArray = _in.get_data(size)[1]
					GameSnapshot.apply(game, GameSnapshot.from_bytes(snap))
					jumps += 1
				_:
					note = "the replay is damaged at tick %d" % tick
					done = true
		return false

	## Plays to the end (or `limit` ticks); the ticks played.
	func run(limit := -1) -> int:
		var n := 0
		while (limit < 0 or n < limit) and step():
			n += 1
		return n

	## The recorded end: the tick count and the final hash, matched or not.
	func end_matches() -> bool:
		var end: Dictionary = rep.header.get("end", {})
		if not end.has("hash"):
			return true
		var n: int = end["ticks"]
		var want: int = end["hash"]
		return n == tick and want == Replay.state_hash(game)

	func _play() -> void:
		var controls := {}
		for slot: int in _slots:
			var row: Array = _prev[slot]
			var c := Game.Controls.new()
			c.forward = row[F_FORWARD]
			c.strafe = row[F_STRAFE]
			c.turn = row[F_TURN]
			c.look = row[F_LOOK]
			var bits: int = row[F_BITS]
			c.running = bits & 1 != 0
			c.fire = bits & 2 != 0
			c.alt_fire = bits & 4 != 0
			c.jump = bits & 8 != 0
			c.crouch = bits & 16 != 0
			c.use = bits & 32 != 0
			c.hold = bits & 64 != 0
			c.reload = bits & 128 != 0
			c.weapon = row[F_WEAPON]
			c.item = row[F_ITEM]
			c.buy = row[F_BUY]
			c.cycle = row[F_CYCLE]
			c.rewind = row[F_REWIND]
			controls[slot] = c
		game.tick(_step, controls)
		tick += 1

	func _open(i: int) -> void:
		_seg_i = i
		var seg: Dictionary = rep.segments[i]
		_in = StreamPeerBuffer.new()
		_in.data_array = seg["data"]
		_prev = {}
		_slots = []
		_same = 0
		var step_dt: float = seg.get("step", 0.0)
		if step_dt > 0.0:
			_step = step_dt

	func _next_segment() -> bool:
		if _seg_i + 1 >= rep.segments.size():
			return false
		var seg: Dictionary = rep.segments[_seg_i + 1]
		var first: int = seg["first"]
		if first != tick:
			# A gap (the middle of a long run was let go): the keyframe.
			var options: Dictionary = seg["options"]
			game.configure(options)
			var snap: PackedByteArray = seg["snap"]
			GameSnapshot.apply(game, GameSnapshot.from_bytes(snap))
			_local(seg)
			tick = first
			jumps += 1
		_open(_seg_i + 1)
		return true

	func _local(seg: Dictionary) -> void:
		var slot: int = seg.get("local", 0)
		if slot >= 0 and slot < game.players.size() and game.local_player.slot != slot:
			Players.set_local(game, game.players[slot])

	func _finish() -> void:
		done = true

	func _get_var() -> int:
		var v := 0
		var shift := 0
		while true:
			var b := _in.get_u8()
			v |= (b & 127) << shift
			if b < 128:
				break
			shift += 7
		return v

	func _get_field(f: int) -> Variant:
		if f <= F_LOOK:
			match _in.get_u8():
				V_ZERO:
					return 0.0
				V_ONE:
					return 1.0
				V_MINUS:
					return -1.0
				V_F32:
					return _in.get_float()
				_:
					return _in.get_double()
		if f == F_BITS:
			return _in.get_u8()
		var z := _get_var()
		return (z >> 1) ^ -(z & 1)
