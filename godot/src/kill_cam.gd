## KILL CAM (PLAY setting: OFF, BOSSES, BOSSES AND AREAS; never online or
## with more than one player): with BOSSES AND AREAS, when the last foe of a
## fight goes down with nobody else awake near, play pauses and the last
## couple of seconds are shown again from another angle, slowed, a camera
## swinging round the body; any key, click or tap skips it. A boss's fall is
## shown live instead (boss_ending.gd, BOSSES and up): replayed here it was
## framed from a hand's distance whatever the boss's size, and ran time
## backwards (pass 10).
##
## Looks only. While play runs it samples what the 3D view was handed
## (game.view_frame: the moving sprites, copied, and each body's pose) RATE
## times a second of game clock, KEEP seconds of it; it listens to
## enemy_killed and only notes the kill. The replay is drawn from those
## samples, the level's fixed sprites and stand-in Enemies of its own that
## only the view reads (as ModeBodies' are), while the front end does not tick
## the game: nothing carried or simulated changes (net_check holds it).
##
## It waits for any slow motion to end (game.slowmo, the boss fall's and any
## finishing shot that uses it), a kill's hitstop and a boss's entrance, then
## DELAY more seconds of play, so it starts once the moment has played out.
class_name KillCam
extends RefCounted

const DATA := "res://data/tuning/camera.cfg"
const OFF := 0
const BOSSES := 1
const AREAS := 2
static var KEEP: float = _num("keep")
static var RATE: float = _num("rate")
static var BEFORE: float = _num("before")
static var AFTER: float = _num("after")
static var PACE: float = _num("pace")
static var DELAY: float = _num("delay")
static var DISTANCE: float = _num("distance")
static var HEIGHT: float = _num("height")
static var SWING: float = _num("swing")
static var AIM: float = _num("aim")
static var AREA: float = _num("area")
static var FIGHT: int = int(_num("fight"))
static var FIGHT_TIME: float = _num("fight_time")


## One sample of the view: its game clock, copies of its moving sprites, and
## for each one showing a body the pose that body had.
class Moment:
	var clock := 0.0
	var sprites: Array[View.Sprite] = []
	var poses: Array[Pose] = []


## A body's pose at a moment: which sprite, whose (the enemy's instance id),
## and what ActorView reads of it.
class Pose:
	var index := 0
	var id := 0
	var kind := ""
	var angle := 0.0
	var gait := 0.0
	var height := 1.0
	var variant := 1.0
	var died_at := -1.0


var mode := BOSSES
var game: Game
var moments: Array[Moment] = []
## The kill to show: {clock, x, y, floor, height} (empty: none).
var pending := {}
var playing := false
## Where the replay is (game clock of the samples), and its span.
var at := 0.0
var from_clock := 0.0
var to_clock := 0.0
## The camera: the point it circles (the body), its bearing at the start and
## the way it swings.
var centre := Vector3.ZERO
var bearing := 0.0
var swing_way := 1.0
var reach := 2.7
var _kills := PackedFloat64Array()
var _next_sample := -INF
var _fixed := {}
var _fixed_key := 0
var _stand_ins := {}
var _marks: Array = []
var _ground: Array = []


static func _num(key: String) -> float:
	var v: float = Tuning.file(DATA).get_value("kill_cam", key, 0.0)
	return v


## Whether it may run for this front end now (the setting, one player, offline).
func allowed(m: MainState) -> bool:
	return mode != OFF and m.net == null and m.game != null and m.game.players.size() == 1


# ------------------------------------------------------------------ recording


## After each play frame is drawn: listen to the game, and sample its view.
func record(m: MainState) -> void:
	if playing or not allowed(m):
		if not playing:
			moments.clear()
		return
	var g := m.game
	if g != game:
		_attach(g)
	if g.view_frame.is_empty() or g.showing_tally:
		return
	if not moments.is_empty() and g.clock < moments[-1].clock:
		moments.clear()  # a load or a retry: the clock went back
		_next_sample = -INF
	if mode < AREAS:
		moments.clear()  # only an area's last kill is replayed
		return
	if g.clock < _next_sample:
		return
	_next_sample = g.clock + 1.0 / maxf(1.0, RATE)
	moments.append(sample(g))
	while moments.size() > 2 and moments[0].clock < g.clock - KEEP:
		moments.pop_front()


func _attach(g: Game) -> void:
	game = g
	moments.clear()
	pending = {}
	_kills = PackedFloat64Array()
	_next_sample = -INF
	_stand_ins.clear()
	var heard := _killed.bind(g)
	if not g.events.enemy_killed.is_connected(heard):
		g.events.enemy_killed.connect(heard)


## A copy of what the view shows now that moves (the level's fixed sprites are
## taken as they stand when it plays), with each body's pose.
func sample(g: Game) -> Moment:
	var key := hash([g.fixed_sprites.size(), g.fixed_sprites_late.size(), g.fixed_sprites_key])
	if key != _fixed_key:
		_fixed_key = key
		_fixed.clear()
		for list: Array in [g.fixed_sprites, g.fixed_sprites_late, g.fixed_windmills]:
			for s: Variant in list:
				_fixed[s] = true
	var out := Moment.new()
	out.clock = g.clock
	var listed: Array = g.view_frame.get("sprites", [])
	for item: Variant in listed:
		if not item is View.Sprite or _fixed.has(item):
			continue
		var s: View.Sprite = item
		var kept := copy(s)
		if s.who is Enemy:
			var e := s.who as Enemy
			var pose := Pose.new()
			pose.index = out.sprites.size()
			pose.id = e.get_instance_id()
			pose.kind = e.kind
			pose.angle = e.angle
			pose.gait = e.gait
			pose.height = e.height
			pose.variant = e.variant
			pose.died_at = e.died_at
			out.poses.append(pose)
		out.sprites.append(kept)
	return out


static func copy(s: View.Sprite) -> View.Sprite:
	var out := View.Sprite.new(s.x, s.y, s.image, s.height, s.z)
	out.glow = s.glow
	out.flip = s.flip
	out.translucent = s.translucent
	out.body = s.body
	out.plane = s.plane
	out.face = s.face
	out.hurt = s.hurt
	out.tell = s.tell
	out.pose = s.pose
	out.spin = s.spin
	out.solid = s.solid
	out.turn = s.turn
	out.tilt = s.tilt
	out.lying = s.lying
	return out


## A foe died: (BOSSES AND AREAS) the last of a fight with nobody else awake
## within AREA is noted to be shown; never a boss (boss_ending.gd). Reads only.
func _killed(e: Enemy, g: Game) -> void:
	if g != game or playing or mode == OFF:
		return
	_kills.append(g.clock)
	while not _kills.is_empty() and _kills[0] < g.clock - FIGHT_TIME:
		_kills.remove_at(0)
	if BossKit.is_boss(e) or mode < AREAS or _kills.size() < FIGHT or _foe_near(g, e):
		return
	pending = {"clock": g.clock, "x": e.x, "y": e.y, "floor": g.world.stand(e), "height": e.height}


static func _foe_near(g: Game, dead: Enemy) -> bool:
	for e: Enemy in g.enemies:
		if e == dead or not e.alive or e.dormant or not e.hostile:
			continue
		if Vector2(e.x - dead.x, e.y - dead.y).length() < AREA:
			return true
	return false


# ------------------------------------------------------------------ replay


## Whether a noted kill can be shown now (any slow motion over, DELAY played).
func ready(m: MainState) -> bool:
	if playing or pending.is_empty() or not allowed(m) or m.game != game:
		return false
	var g := game
	var when: float = pending["clock"]
	if g.defeated() or g.clock < when - .01 or g.clock > when + KEEP:
		pending = {}
		return false
	if g.slowmo > 0.0 or g.hitstop > 0.0 or g.boss_hold > 0.0:
		return false
	return g.clock >= when + DELAY and moments.size() >= 4


## Begin the replay: the samples from BEFORE the kill to AFTER it, the camera
## placed where it sees the body clear of walls.
func start(m: MainState) -> bool:
	if not ready(m):
		return false
	var when: float = pending["clock"]
	from_clock = maxf(moments[0].clock, when - BEFORE)
	to_clock = minf(moments[-1].clock, when + AFTER)
	if to_clock - from_clock < .3:
		pending = {}
		return false
	var x: float = pending["x"]
	var y: float = pending["y"]
	var ground: float = pending["floor"]
	var tall: float = pending["height"]
	centre = Vector3(x, y, ground + tall * AIM)
	_place(game)
	at = from_clock
	playing = true
	_marks = game.view_frame.get("marks", [])
	_ground = game.view_frame.get("ground", [])
	return true


## Pick the camera's bearing round the body: off to the side of the player's
## line, swinging away from it, its whole swing clear of walls (nearer, or
## from the player's side, where nothing else is).
func _place(g: Game) -> void:
	var p := g.player
	var toward := atan2(p.y - centre.y, p.x - centre.x)
	var ground: float = pending["floor"]
	var eye_z := ground + HEIGHT
	for distance: float in [DISTANCE, DISTANCE * .6]:
		for turn: float in [1.9, -1.9, 1.2, -1.2, 2.6, -2.6, .5, -.5]:
			var way := signf(turn)
			var a := toward + turn
			if _clear(g, a, distance, eye_z) and _clear(g, a + SWING * way, distance, eye_z):
				bearing = a
				swing_way = way
				reach = distance
				return
	bearing = toward
	swing_way = 1.0
	reach = minf(DISTANCE, Vector2(p.x - centre.x, p.y - centre.y).length())


func _clear(g: Game, a: float, distance: float, z: float) -> bool:
	var level := g.world
	var steps := int(ceilf(distance / .25))
	for i in range(1, steps + 1):
		var d := distance * i / steps
		var x := centre.x + cos(a) * d
		var y := centre.y + sin(a) * d
		if x < 1.0 or y < 1.0 or x > level.width - 1.0 or y > level.height - 1.0:
			return false
		if level.blocked(x, y, .15, z - .5):
			return false
	return true


## One frame of the replay: it runs on at PACE until its end.
func frame(m: MainState, dt: float) -> void:
	if not playing:
		return
	if m.game != game:
		stop(m)
		return
	at += dt * PACE
	if at >= to_clock:
		stop(m)


func stop(m: MainState) -> void:
	if not playing:
		return
	playing = false
	pending = {}
	moments.clear()
	_next_sample = -INF
	m.mouse_rel = Vector2.ZERO


## The camera's eye at the replay's moment `t`.
func eye_at(t: float) -> Dictionary:
	var share := clampf((t - from_clock) / maxf(.01, to_clock - from_clock), 0.0, 1.0)
	var smooth := share * share * (3.0 - 2.0 * share)
	var a := bearing + SWING * swing_way * smooth
	var x := centre.x + cos(a) * reach
	var y := centre.y + sin(a) * reach
	var ground: float = pending.get("floor", centre.z)
	var z := ground + HEIGHT
	var pitch := -View.base_focal * (z - centre.z) / maxf(.5, reach)
	return {
		"x": x,
		"y": y,
		"eye": z,
		"view_angle": atan2(centre.y - y, centre.x - x),
		"pitch": clampf(pitch, -70.0, 70.0),
		"bob": 0.0,
		"sway": 0.0,
	}


## What the 3D view is handed for the replay's moment `t` (as game_view.gd
## builds game.view_frame): the samples' moving sprites, their bodies posed
## by stand-ins (smoothed between two samples), and the level's fixed
## sprites near the camera.
func frame_at(g: Game, t: float) -> Dictionary:
	var a := moments[0]
	var b := moments[-1]
	for i in moments.size() - 1:
		if moments[i + 1].clock > t:
			a = moments[i]
			b = moments[i + 1]
			break
	var share := clampf((t - a.clock) / maxf(.001, b.clock - a.clock), 0.0, 1.0)
	var shown := a if share < .5 else b
	var eye := eye_at(t)
	var listed: Array = []
	var ex: float = eye["x"]
	var ey: float = eye["y"]
	var facing: float = eye["view_angle"]
	var pitch: float = eye["pitch"]
	var fx := cos(facing)
	var fy := sin(facing)
	for list: Array in [g.fixed_sprites, g.fixed_sprites_late]:
		for item: Variant in list:
			if not item is View.Sprite:
				continue
			var s: View.Sprite = item
			var d := (s.x - ex) * fx + (s.y - ey) * fy
			if d > -2.0 and d < g.view.draw_far:
				listed.append(s)
	var posed := {}
	for pose: Pose in shown.poses:
		posed[pose.index] = pose
	var later := {}
	for pose: Pose in b.poses:
		later[pose.id] = pose
	for k in shown.sprites.size():
		var s := shown.sprites[k]
		if not posed.has(k):
			listed.append(s)
			continue
		var pose: Pose = posed[k]
		listed.append(_posed(g, s, pose, a, b, later, share, t))
	return {
		"eye": eye,
		"horizon": (View.VIEW / 2.0 + pitch) / g.view.res_up,
		"flash": 0.0,
		"sprites": listed,
		"marks": _marks,
		"ground": _ground,
		"reflection": null,
	}


## A body's sprite at `t`: its sample's, moved between the two samples, worn
## by this body's stand-in posed as it was then.
func _posed(
	g: Game,
	s: View.Sprite,
	pose: Pose,
	a: Moment,
	b: Moment,
	later: Dictionary,
	share: float,
	t: float
) -> View.Sprite:
	var out := copy(s)
	var before := pose
	var after: Pose = later.get(pose.id, pose)
	if a != b:
		for p: Pose in a.poses:
			if p.id == pose.id:
				before = p
	var from_s := a.sprites[before.index] if before.index < a.sprites.size() else s
	var to_s := b.sprites[after.index] if after.index < b.sprites.size() else s
	out.x = lerpf(from_s.x, to_s.x, share)
	out.y = lerpf(from_s.y, to_s.y, share)
	out.z = lerpf(from_s.z, to_s.z, share)
	var e: Enemy = _stand_ins.get(pose.id)
	if e == null or e.kind != pose.kind:
		e = Enemy.new(pose.kind if Enemy.DEFS.has(pose.kind) else "coot")
		e.kind = pose.kind
		_stand_ins[pose.id] = e
	e.angle = lerp_angle(before.angle, after.angle, share)
	e.gait = lerpf(before.gait, after.gait, share)
	e.height = pose.height
	e.variant = pose.variant
	# ActorView times a fall from game.clock (still while this plays).
	e.died_at = g.clock - t + pose.died_at if pose.died_at >= 0.0 else -1.0
	e.x = out.x
	e.y = out.y
	out.who = e
	return out


## Draw the replay: the view from the camera (the 3D view), black bars over
## and under it with KILL CAM and how to skip.
func draw(m: MainState) -> void:
	var g := m.game
	var c := m.canvas
	c.begin_layer()
	var kept := g.view_frame
	g.view_frame = frame_at(g, at)
	m.show_view()
	g.view_frame = kept
	var black := Color(0, 0, 0)
	c.fill_rect(0, 0, View.WIDTH, 12, black)
	c.fill_rect(0, View.VIEW - 12, View.WIDTH, View.HEIGHT - View.VIEW + 12, black)
	# ASPECT WIDE: the words at the picture's own corners.
	c.anchor(-View.shift)
	HUD.text(c, "KILL CAM", 8, 3, "mini", HUD.AMBER, false, false)
	c.anchor(View.shift)
	var skip := "TAP TO SKIP" if m.input_device == "touch" else "ANY KEY SKIPS"
	HUD.text(c, skip, 312, 3, "mini", HUD.DIM, false, false, true)
	c.anchor(0)
