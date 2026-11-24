## The sounds of fast movers, each drawn frame (pass 14): tells the Doppler
## (src/doppler.gd, sound.doppler) where the listener and every mover are
## drawn, and keeps the flight loops going. Called by the front end during
## the frame's draw (main.gd, between net_draw_begin and net_draw_end), so
## everything is where it is drawn: part way between ticks in single player
## (SoloBlend) and online (NetBlend, our own player predicted).
##
## - The movers: each ride (features/vehicles.gd ties its engine's notes and
##   its tyres to it, Doppler.RIDE), each lap car or cruiser running
##   (features/race_laps.gd, Doppler.LAP), the shots with a flight loop
##   (doppler.cfg [fly], by uid), the carried things in the air
##   (features/carry.gd), the saucers and probes, the swamp king's airboat
##   and Bumper Boggs's derby car (FOES, by uid).
## - The loops: the nearest [loops] `slots` shots and thrown things in the air
##   within `reach` each play their loop on a bed of their own (Sound.BED_FLY
##   and the two after it), the nearest saucer or probe its hum
##   (Sound.BED_HUM), placed as any sound is (Game.sound_position and
##   sound_cutoff, so through a wall or a floor they are muffled, and bend
##   all the same), faded up and down, tied to their mover.
##
## Sound only: it reads the game and the features and changes none of them.
class_name MoverSounds
extends RefCounted

const VehiclesScript := preload("res://src/features/vehicles.gd")
const RaceLaps := preload("res://src/features/race_laps.gd")
const Carry := preload("res://src/features/carry.gd")
## The county's movers by brain, and the family each one's sounds bend by:
## the saucers and probes (their hum), the swamp king's airboat (his rev,
## charge and wake: bayou_brains.gd, soundscape.gd) and Bumper Boggs's derby
## car (his rev into a charge: derby_champ.gd).
const FOES := {"saucer": "saucer", "swamp_king": "airboat", "derby_champ": "car"}


## One loop's voice (a Sound bed) and the mover it follows.
class Slot:
	extends RefCounted
	var bed := 0
	var key := 0
	## [cue, level, pitch, family, whoosh] (doppler.cfg).
	var row: Array = []
	var at := Vector3.ZERO
	## Its share of its level (faded), where it was last heard from (volume,
	## pan) and its cutoff, and how long ago that was looked at.
	var level := 0.0
	var place := Vector2.ZERO
	var cutoff := Sound.OPEN_CUTOFF
	var since := INF

	func _init(p_bed: int) -> void:
		bed = p_bed


## Something that may carry a loop this frame.
class Wanted:
	extends RefCounted
	var key := 0
	var row: Array = []
	var at := Vector3.ZERO
	var far := 0.0
	## Its share of its level (a whoosh by how fast it goes).
	var share := 1.0


var fly: Array[Slot] = []
var hum: Array[Slot] = []
var _game_id := 0
var _cfg: ConfigFile = null
var _rows := {}
var _carried: Array = []
var _saucer: Array = []
var _slots := 3
var _reach := 14.0
var _hum_reach := 11.0
var _fade_in := .06
var _fade_out := .1
var _hear_every := .033
var _quiet := 2.0
var _loud := 8.0
## The FOES among game.enemies, as of that list at that size.
var _movers: Array = []
var _foes_in: Array = []
var _foes_of := -1


func _init() -> void:
	for i in 3:
		fly.append(Slot.new(Sound.BED_FLY + i))
	hum.append(Slot.new(Sound.BED_HUM))


func _tune() -> void:
	var cfg := Tuning.file(Doppler.DATA)
	if cfg == _cfg:
		return
	_cfg = cfg
	var slots: int = cfg.get_value("loops", "slots", 3)
	var fade_in: float = cfg.get_value("loops", "fade_in", .06)
	var fade_out: float = cfg.get_value("loops", "fade_out", .1)
	var loud: float = cfg.get_value("loops", "loud", 8.0)
	_slots = clampi(slots, 0, fly.size())
	_reach = cfg.get_value("loops", "reach", 14.0)
	_hum_reach = cfg.get_value("loops", "hum_reach", 11.0)
	_fade_in = maxf(.001, fade_in)
	_fade_out = maxf(.001, fade_out)
	_hear_every = cfg.get_value("loops", "hear_every", .033)
	_quiet = cfg.get_value("loops", "quiet", 2.0)
	_loud = maxf(_quiet + .1, loud)
	_rows.clear()
	if cfg.has_section("fly"):
		for kind: String in cfg.get_section_keys("fly"):
			_rows[kind] = cfg.get_value("fly", kind)
	_carried = cfg.get_value("carried", "loop", [])
	_saucer = cfg.get_value("saucer", "loop", [])


## This frame's movers and loops for `game` (the frame's draw, `dt` seconds
## since the last).
func frame(game: Game, dt: float) -> void:
	var sound: Sound = null
	if game != null and not game.host and game.speaker != null:
		sound = game.speaker.node()
	if sound == null:
		return
	_tune()
	var d := sound.doppler
	if game.get_instance_id() != _game_id:
		_game_id = game.get_instance_id()
		d.reset()
		_foes_of = -1
	var p := game.local_player
	d.listen(Vector3(p.x, p.y, p.eye), dt)
	_rides(game, d, dt)
	_laps(game, d, dt)
	var wanted: Array = []
	_shots(game, d, dt, wanted)
	_things(game, d, dt, wanted)
	_loops(game, sound, fly, _slots, wanted, dt)
	_loops(game, sound, hum, 1, _foes(game, d, dt), dt)
	d.frame(dt)


## Every loop let go at once (the game held still: PHOTO MODE, an opener, the
## KILL CAM; out of play).
func hush(sound: Sound) -> void:
	for slot: Slot in fly + hum:
		if slot.key != 0 and sound != null:
			sound.set_bed(slot.bed, "", 0.0)
		slot.key = 0
		slot.level = 0.0


func _rides(game: Game, d: Doppler, dt: float) -> void:
	var feature: VehiclesScript = game.features.get("vehicles")
	if feature == null:
		return
	for i in feature.rides.size():
		var v: VehicleDrive.Ride = feature.rides[i]
		d.feed(Doppler.RIDE + i, v.kind, Vector3(v.x, v.y, v.z + .5), dt)


func _laps(game: Game, d: Doppler, dt: float) -> void:
	var feature: RaceLaps = game.features.get("race_laps")
	if feature == null:
		return
	for k in feature.cars.size():
		var at := feature.car_spot(k)
		if at != Vector3.INF:
			d.feed(Doppler.LAP + k, "race", at + Vector3(0.0, 0.0, .5), dt)


func _shots(game: Game, d: Doppler, dt: float, wanted: Array) -> void:
	if _rows.is_empty():
		return
	for shot: GameState.Shot in game.shots:
		if shot.resting or shot.uid == 0 or not _rows.has(shot.kind):
			continue
		var row: Array = _rows[shot.kind]
		if row.size() < 5:
			continue
		var key := Doppler.SHOT + shot.uid
		var at := Vector3(shot.x, shot.y, shot.z)
		d.feed(key, str(row[3]), at, dt)
		_want(d, key, row, at, wanted)


func _things(game: Game, d: Doppler, dt: float, wanted: Array) -> void:
	var feature: Carry = game.features.get("carry")
	if feature == null or _carried.size() < 5:
		return
	for i: int in feature.active:
		if i < 0 or i >= feature.things.size():
			continue
		var t: Carry.Thing = feature.things[i]
		if t.state != Carry.FLY:
			continue
		var key := Doppler.THING + i
		var at := Vector3(t.x, t.y, t.z)
		d.feed(key, str(_carried[3]), at, dt)
		_want(d, key, _carried, at, wanted)


## The county's movers (FOES) followed; the nearest saucer or probe hums.
func _foes(game: Game, d: Doppler, dt: float) -> Array:
	var wanted: Array = []
	if not is_same(_foes_in, game.enemies) or _foes_of != game.enemies.size():
		_foes_in = game.enemies
		_foes_of = game.enemies.size()
		_movers = game.enemies.filter(func(e: Enemy) -> bool: return e.brain in FOES)
	for e: Enemy in _movers:
		if not e.alive or e.uid == 0:
			continue
		var key := Doppler.FOE + e.uid
		var at := Vector3(e.x, e.y, e.z + e.height * .5)
		if e.brain != "saucer":
			d.feed(key, str(FOES[e.brain]), at, dt)
		elif _saucer.size() >= 5:
			d.feed(key, str(_saucer[3]), at, dt)
			if d.ear.distance_to(at) < _hum_reach:
				_want(d, key, _saucer, at, wanted)
	return wanted


func _want(d: Doppler, key: int, row: Array, at: Vector3, wanted: Array) -> void:
	var far := d.ear.distance_to(at)
	if far >= _reach:
		return
	var w := Wanted.new()
	w.key = key
	w.row = row
	w.at = at
	w.far = far
	var whoosh: bool = row[4]
	if whoosh:
		w.share = clampf((d.speed_of(key) - _quiet) / (_loud - _quiet), 0.0, 1.0)
	wanted.append(w)


## The `count` first of `slots` follow the nearest of `wanted`: a slot keeps
## its mover while that is still wanted, a free one takes the nearest not
## yet heard, and a mover gone (burst, landed, out of reach) fades out where
## it was last.
func _loops(game: Game, sound: Sound, slots: Array, count: int, wanted: Array, dt: float) -> void:
	var by_key := {}
	for w: Wanted in wanted:
		by_key[w.key] = w
	var taken := {}
	for i in slots.size():
		var slot: Slot = slots[i]
		if i >= count and slot.key != 0:
			sound.set_bed(slot.bed, "", 0.0)
			slot.key = 0
		if slot.key != 0:
			taken[slot.key] = true
	if wanted.size() > count:
		wanted.sort_custom(func(a: Wanted, b: Wanted) -> bool: return a.far < b.far)
	for w: Wanted in wanted:
		if taken.has(w.key) or w.share <= 0.0:
			continue
		for i in count:
			var slot: Slot = slots[i]
			if slot.key == 0:
				slot.key = w.key
				slot.level = 0.0
				slot.since = INF
				taken[w.key] = true
				break
	for i in count:
		var slot: Slot = slots[i]
		if slot.key != 0:
			var w: Wanted = by_key.get(slot.key)
			_drive(game, sound, slot, w, dt)


func _drive(game: Game, sound: Sound, slot: Slot, w: Wanted, dt: float) -> void:
	var want := 0.0
	if w != null:
		want = w.share
		slot.row = w.row
		slot.at = w.at
	var fade := _fade_in if want > slot.level else _fade_out
	var was := slot.level
	slot.level = move_toward(slot.level, want, dt / fade)
	if slot.level <= 0.0 and want <= 0.0:
		sound.set_bed(slot.bed, "", 0.0)
		slot.key = 0
		return
	slot.since += dt
	if slot.since >= _hear_every:
		slot.since = 0.0
		var gain: float = slot.row[1]
		slot.place = game.sound_position(slot.at.x, slot.at.y, gain)
		slot.cutoff = game.sound_cutoff(slot.at.x, slot.at.y)
	elif slot.level == was:
		# Nothing to tell the bed: its pitch follows the mover in d.frame().
		return
	var d := sound.doppler
	d.next_from = slot.key
	d.next_base = slot.row[2]
	sound.set_bed(slot.bed, str(slot.row[0]), slot.place.x * slot.level, slot.place.y, slot.cutoff)
	d.next_from = 0
	d.next_base = 1.0
