## Doppler on fast movers (pass 14): a sound tied to something moving (a
## vehicle's engine, a race car or a cruiser coming round, a shot's flight
## loop, a thrown thing's whoosh, a saucer's hum) is pitched by how fast it
## and the listener close or open the gap between them:
##     pitch = base * (c - v_listener . n) / (c - v_source . n)
## with n the way from the source to the listener and c the tuned speed of
## sound (data/tuning/doppler.cfg). `base` is the pitch the cue was started
## at (Sound's per-play spread times an engine's rate), so the two multiply.
## The shift is clamped (most_up, most_down semitones), eased (ease) and its
## rate held (slew), so nothing zips or jumps.
##
## The speeds come from where things are drawn, frame to frame (feed() and
## listen(), from MoverSounds during the frame's draw: between ticks in
## single player and online alike), each followed over `track` seconds; a
## jump past `snap` (a respawn, a seat taken, a new level) forgets the speed
## there instead of reading one from it.
##
## Sound only: it sets AudioStreamPlayer.pitch_scale and nothing else; play,
## its dice and its snapshots never see it. Sound owns one (sound.doppler).
class_name Doppler
extends RefCounted

const DATA := "res://data/tuning/doppler.cfg"
## The movers' keys, one range each: a ride's index (features/vehicles.gd),
## a lap car's (features/race_laps.gd), a shot's uid, a carried thing's
## index and an enemy's uid (src/mover_sounds.gd).
const RIDE := 1 << 40
const LAP := 2 << 40
const SHOT := 3 << 40
const THING := 4 << 40
const FOE := 5 << 40


## Something moving that sounds may be tied to.
class Mover:
	extends RefCounted
	var at := Vector3.ZERO
	var velocity := Vector3.ZERO
	var family := ""
	## The pitch it gives (eased), and the seconds since it was last fed.
	var factor := 1.0
	var unseen := 0.0
	var placed := false


## A playing voice tied to a mover, at its own pitch `base`.
class Held:
	extends RefCounted
	var player: AudioStreamPlayer
	var key := 0
	var base := 1.0


var on := true
var sound_speed := 150.0
var most_up := 3.0
var most_down := 3.0
var glide := .05
var slew := 30.0
var track := .06
var snap := 2.0
var fastest := 45.0
var shortest := .45
var forget := .5
## Each family's share of its speeds (0: off), from [family.<name>].
var families := {}

var movers := {}
## The listener: where its ear was drawn, and how fast it moves.
var ear := Vector3.ZERO
var ear_velocity := Vector3.ZERO
var _ear_placed := false
## The mover the next sound started (Sound._start) or held (Sound.set_bed)
## belongs to (0: none), and a held loop's own pitch.
var next_from := 0
var next_base := 1.0
## Instance id of each tied player -> Held.
var _held := {}
var _cfg: ConfigFile = null


## The numbers again when the file is new (a saved change while the game runs
## from the project folder).
func tune() -> void:
	var cfg := Tuning.file(DATA)
	if cfg == _cfg:
		return
	_cfg = cfg
	on = cfg.get_value("all", "on", true)
	sound_speed = maxf(1.0, _num("sound_speed", 150.0))
	most_up = _num("most_up", 3.0)
	most_down = _num("most_down", 3.0)
	glide = _num("ease", .05)
	slew = _num("slew", 30.0)
	track = _num("track", .06)
	snap = _num("snap", 2.0)
	fastest = _num("fastest", 45.0)
	shortest = _num("shortest", .45)
	forget = _num("forget", .5)
	families.clear()
	for section: String in cfg.get_sections():
		if section.begins_with("family."):
			var used: bool = cfg.get_value(section, "on", true)
			var scale: float = cfg.get_value(section, "scale", 1.0)
			families[section.substr(7)] = scale if used else 0.0


func _num(key: String, fallback: float) -> float:
	var v: float = _cfg.get_value("all", key, fallback)
	return v


## Every mover and tie let go (a new level, the world paused).
func reset() -> void:
	movers.clear()
	_held.clear()
	_ear_placed = false
	ear_velocity = Vector3.ZERO


## Where the listener's ear is drawn this frame.
func listen(at: Vector3, dt: float) -> void:
	tune()
	ear_velocity = _follow(ear, at, ear_velocity, dt, _ear_placed)
	ear = at
	_ear_placed = true


## Where mover `key` (of `family`) is drawn this frame.
func feed(key: int, family: String, at: Vector3, dt: float) -> void:
	var m: Mover = movers.get(key)
	if m == null:
		m = Mover.new()
		movers[key] = m
	m.family = family
	m.velocity = _follow(m.at, at, m.velocity, dt, m.placed)
	m.at = at
	m.placed = true
	m.unseen = 0.0


## The speed from one drawn place to the next, followed over `track`; a jump
## past `snap`, or faster than `fastest`, forgets it (no spike).
func _follow(old: Vector3, now: Vector3, velocity: Vector3, dt: float, placed: bool) -> Vector3:
	if not placed:
		return Vector3.ZERO
	if dt <= 0.0:
		return velocity
	var step := now - old
	if step.length() > snap or step.length() > fastest * dt:
		return Vector3.ZERO
	var k := 1.0 - exp(-dt / maxf(.001, track))
	return velocity.lerp(step / dt, k)


## Each mover's pitch eased toward what it and the listener give now, the
## ones not fed let go, and every tied voice set to its own pitch times its
## mover's.
func frame(dt: float) -> void:
	tune()
	for key: int in movers.keys():
		var m: Mover = movers[key]
		m.unseen += dt
		if m.unseen > forget:
			movers.erase(key)
			continue
		m.factor = _ease(m.factor, target(m), dt)
	for id: int in _held.keys():
		var h: Held = _held[id]
		if not is_instance_valid(h.player) or not h.player.playing:
			_held.erase(id)
			continue
		var m: Mover = movers.get(h.key)
		if m != null:
			Doppler.set_pitch(h.player, h.base * m.factor)


## The pitch mover `m` should have now (1: none), within the clamp.
func target(m: Mover) -> float:
	if not on or not m.placed or not _ear_placed:
		return 1.0
	var scale: float = families.get(m.family, 1.0)
	var r := Doppler.ratio(sound_speed, m.at, m.velocity, ear, ear_velocity, scale)
	if r == 1.0:
		return 1.0
	var semis := clampf(12.0 * log(r) / log(2.0), -most_down, most_up)
	return pow(2.0, semis / 12.0)


## The plain Doppler ratio: c the speed of sound, the source at `at` moving
## at `velocity`, the ear at `ear_at` moving at `ear_v`, both speeds times
## `scale` (each held under half of c).
static func ratio(
	c: float, at: Vector3, velocity: Vector3, ear_at: Vector3, ear_v: Vector3, scale: float
) -> float:
	var gap := ear_at - at
	var far := gap.length()
	if far < .001 or scale <= 0.0:
		return 1.0
	var n := gap / far
	var toward := clampf(velocity.dot(n) * scale, -c * .5, c * .5)
	var away := clampf(ear_v.dot(n) * scale, -c * .5, c * .5)
	return (c - away) / (c - toward)


## `from` eased toward `to` over `glide` ([all] ease), never faster than `slew` semitones
## a second.
func _ease(from: float, to: float, dt: float) -> float:
	if from == to or dt <= 0.0:
		return from
	var a := 12.0 * log(from) / log(2.0)
	var b := 12.0 * log(to) / log(2.0)
	var step := (b - a) * (1.0 - exp(-dt / maxf(.001, glide)))
	var most := slew * dt
	step = clampf(step, -most, most)
	if absf(b - a) <= absf(step) or absf(b - a) < .0005:
		return to
	return pow(2.0, (a + step) / 12.0)


## Mover `key`'s pitch now (1: not known).
func factor_of(key: int) -> float:
	var m: Mover = movers.get(key)
	return 1.0 if m == null else m.factor


## How fast mover `key` is drawn moving (cells a second; 0 not known).
func speed_of(key: int) -> float:
	var m: Mover = movers.get(key)
	return 0.0 if m == null else m.velocity.length()


## Whether `player` is tied to a mover now.
func holds(player: AudioStreamPlayer) -> bool:
	return _held.has(player.get_instance_id())


## A one-shot starting on `player` at `base` (Sound._start): tied to
## `next_from` when there is one and the cue is long enough to hear it bend.
func start(player: AudioStreamPlayer, base: float) -> void:
	var id := player.get_instance_id()
	var key := next_from
	if key == 0 or not on or player.stream == null or player.stream.get_length() < shortest:
		_held.erase(id)
		player.pitch_scale = base
		return
	_tie(id, player, key, base)
	player.pitch_scale = base * factor_of(key)


## A loop held on `player` (Sound.set_bed, every call): tied to `next_from`
## at `next_base`, or let go back to its own pitch.
func hold(player: AudioStreamPlayer) -> void:
	var id := player.get_instance_id()
	var key := next_from if on else 0
	if key == 0:
		_held.erase(id)
		Doppler.set_pitch(player, next_base)
		return
	_tie(id, player, key, next_base)
	Doppler.set_pitch(player, next_base * factor_of(key))


func _tie(id: int, player: AudioStreamPlayer, key: int, base: float) -> void:
	var h: Held = _held.get(id)
	if h == null:
		h = Held.new()
		h.player = player
		_held[id] = h
	h.key = key
	h.base = base


## A player's pitch, told the mixer only when it moves.
static func set_pitch(player: AudioStreamPlayer, value: float) -> void:
	value = clampf(value, .25, 4.0)
	if absf(player.pitch_scale - value) > .00001:
		player.pitch_scale = value
