## How dirty fighting looks from the eye (features/brawl.gd is the play):
## Mundell's boot comes up into the view and drives out for a kick (the
## fx_boot_* cels, tools/art/build_boot_views.gd), the gun ducks out of its
## way; each finisher moves the gun in hand its own way (a pistol swung
## across, a stock driven up, the crowbar's own swing, the boot stomped
## down), and every blow that lands jolts the view and the gun
## (features/feel.gd punch(), scaled by SCREEN SHAKE). Looks only: no dice,
## nothing carried, it reads brawl's carried moments (kicked_at, last_moves).
extends GameFeature

const Brawl := preload("res://src/features/brawl.gd")
const Feel := preload("res://src/features/feel.gd")
## The kick's beats (seconds from the press): chambered until KICK_UP, out,
## the blow from KICK_LAND (hits.cfg [kick] land) held until KICK_OUT, back
## and away by KICK_DOWN.
const KICK_UP := .05
const KICK_LAND := .1
const KICK_OUT := .2
const KICK_DOWN := .42
## How far (view pixels) the gun ducks for the kick, down and to the right.
const DUCK := Vector2(34.0, 70.0)
## The finisher moves' gun paths: [seconds from the start, x, y (pixels the
## gun is off its place), turn (degrees about its grip, + clockwise)],
## eased between. The blow lands at [finish] wind (.15): each holds still a
## moment on contact (the hit-stop; the slow motion stretches it), then
## follows through and settles.
const PATHS := {
	# The revolver cocked back low, then swung across in a sideways arc,
	# butt first, the barrel coming up.
	"whip":
	[
		[0.0, 0.0, 0.0, 0.0],
		[0.11, 50.0, 10.0, -25.0],
		[0.15, -50.0, -24.0, 35.0],
		[0.21, -52.0, -25.0, 36.0],
		[0.32, -70.0, -10.0, 45.0],
		[0.62, 0.0, 0.0, 0.0],
	],
	# Shoved in at his face, the round, the kick of it.
	"mouth":
	[
		[0.0, 0.0, 0.0, 0.0],
		[.13, -34.0, -46.0, -12.0],
		[.15, -36.0, -48.0, -12.0],
		[.2, -36.0, -48.0, -12.0],
		[.26, -18.0, -70.0, -30.0],
		[.58, 0.0, 0.0, 0.0],
	],
	# The long gun turned stock first and driven up into him, then back.
	"butt":
	[
		[0.0, 0.0, 0.0, 0.0],
		[0.11, 40.0, 40.0, -20.0],
		[0.15, -50.0, -30.0, 30.0],
		[0.21, -52.0, -31.0, 31.0],
		[0.36, -40.0, -20.0, 24.0],
		[0.64, 0.0, 0.0, 0.0],
	],
	# Jammed into his gut, the round, the kick of it.
	"belly":
	[
		[0.0, 0.0, 0.0, 0.0],
		[.13, -12.0, 36.0, 12.0],
		[.15, -14.0, 38.0, 12.0],
		[.2, -14.0, 38.0, 12.0],
		[.27, 0.0, 6.0, -22.0],
		[.58, 0.0, 0.0, 0.0],
	],
	# Raised high over the right shoulder and brought down hard.
	"skull":
	[
		[0.0, 0.0, 0.0, 0.0],
		[0.11, 34.0, -70.0, 46.0],
		[0.15, -14.0, 4.0, -6.0],
		[0.21, -15.0, 5.0, -6.0],
		[0.36, -20.0, 16.0, -10.0],
		[0.64, 0.0, 0.0, 0.0],
	],
	# Drawn back low at the right, then swung flat across his belly.
	"gut":
	[
		[0.0, 0.0, 0.0, 0.0],
		[0.11, 76.0, 4.0, -20.0],
		[0.15, -50.0, -6.0, 20.0],
		[0.21, -52.0, -6.0, 21.0],
		[0.36, -70.0, 0.0, 28.0],
		[0.64, 0.0, 0.0, 0.0],
	],
	# The gun out of the boot's way (it comes up the middle).
	"stomp":
	[[0.0, 0.0, 0.0, 0.0], [.1, 30.0, 90.0, 10.0], [.5, 30.0, 90.0, 10.0], [.7, 0.0, 0.0, 0.0]],
	"punt":
	[[0.0, 0.0, 0.0, 0.0], [.1, 34.0, 80.0, 10.0], [.5, 34.0, 80.0, 10.0], [.7, 0.0, 0.0, 0.0]],
}
## Each blow's jolt: [view yaw (radians), view pitch (pixels), eye drop
## (cells), the gun's shove x and y (pixels)].
const KICK_PUNCH := [.0, -3.0, .02, 0.0, 10.0]
const BLOW_PUNCH := {
	"whip": [-.03, 3.0, .02, -10.0, 6.0],
	"mouth": [.0, -5.0, .015, 0.0, -8.0],
	"butt": [.02, -5.0, .025, -6.0, -10.0],
	"belly": [.0, 4.0, .03, 0.0, 12.0],
	"skull": [-.02, 5.0, .03, -8.0, 10.0],
	"gut": [-.03, 2.0, .02, -12.0, 4.0],
	"stomp": [.0, 7.0, .05, 0.0, 14.0],
	"punt": [.0, -4.0, .03, 0.0, 12.0],
}

## The kick and the blow last given a jolt (their moments), so each jolts once.
var _kick_punched := -1.0
var _blow_punched := -1.0


func id() -> String:
	return "brawl_looks"


func attach() -> void:
	tick_with(_tick)


## Where each boot cel's top left corner sits on the 320x200 view, as
## tools/art/build_boot_views.gd wrote them to assets/art/boot_views.json
## (tools/brawl_check.gd holds the two the same).
const PLACES := {"kick_0": [146, 95], "kick_1": [143, 85], "kick_2": [140, 76], "kick_3": [168, 96]}


func _brawl() -> Brawl:
	var b: Brawl = game.features.get("brawl")
	return b


## Where the boot is now for the local player: [pose, x, y] on the 320x200
## view, or [] when it is not up.
func boot() -> Array:
	var b := _brawl()
	if b == null:
		return []
	var slot := game.local_player.slot
	var at: float = b.kicked_at.get(slot, -10.0)
	var t := game.clock - at
	if t >= 0.0 and t < KICK_DOWN:
		return _kick_pose(t)
	var last: Array = b.last_moves.get(slot, [])
	if last.is_empty():
		return []
	var move: String = last[0]
	var started: float = last[1]
	var s := game.clock - started
	var wind: float = Brawl.FINISH["wind"]
	if move == "punt" and s >= 0.0 and s < wind + KICK_DOWN - KICK_UP:
		return _kick_pose(maxf(0.0, s - wind + KICK_UP))
	if move == "stomp" and s >= 0.0 and s < wind + .35:
		# Chambered, then driven up into his face, held on contact, dropped.
		if s < wind * .5:
			return _at("kick_0", 0.0, 0.0)
		if s < wind:
			return _at("kick_1", 0.0, 0.0)
		if s < wind + .1:
			return _at("kick_2", -4.0, -4.0)
		return _at("kick_3", 0.0, lerpf(0.0, 70.0, (s - wind - .1) / .25))
	return []


## The kick's frames: chambered, driven out, the blow (held a moment on
## contact: the hit-stop), pulled back, dropped away.
func _kick_pose(t: float) -> Array:
	if t < KICK_UP:
		return _at("kick_0", 0.0, lerpf(50.0, 0.0, t / KICK_UP))
	if t < KICK_LAND:
		return _at("kick_1", 0.0, 0.0)
	if t < KICK_OUT:
		return _at("kick_2", 0.0, 0.0)
	var d := (t - KICK_OUT) / (KICK_DOWN - KICK_OUT)
	if d < .4:
		return _at("kick_1", 0.0, lerpf(0.0, 12.0, d / .4))
	return _at("kick_3", 0.0, lerpf(0.0, 70.0, (d - .4) / .6))


func _at(pose: String, dx: float, dy: float) -> Array:
	var place: Array = PLACES.get(pose, [140, 40])
	var x: float = place[0]
	var y: float = place[1]
	return [pose, x + dx, y + dy]


## The gun's place and turn for `move` at `s` seconds: (x, y, degrees).
func _path(move: String, s: float) -> Vector3:
	var keys: Array = PATHS.get(move, [])
	if keys.is_empty():
		return Vector3.ZERO
	var prev := Vector4.ZERO
	for i in keys.size():
		var row: Array = keys[i]
		var t: float = row[0]
		var x: float = row[1]
		var y: float = row[2]
		var turn: float = row[3]
		if s <= t and i > 0:
			var k := clampf((s - prev.x) / maxf(.001, t - prev.x), 0.0, 1.0)
			k = k * k * (3.0 - 2.0 * k)
			return Vector3(lerpf(prev.y, x, k), lerpf(prev.z, y, k), lerpf(prev.w, turn, k))
		prev = Vector4(t, x, y, turn)
	return Vector3(prev.y, prev.z, prev.w)


func _tick(_dt: float) -> void:
	var b := _brawl()
	if b == null or game.local_player == null:
		return
	var p := game.local_player
	var slot := p.slot
	p.weapon_turn = 0.0
	var feel: Feel = game.features.get("feel")
	# The kick: the gun ducks out of the boot's way; a jolt as it lands.
	var at: float = b.kicked_at.get(slot, -10.0)
	var t := game.clock - at
	if t >= 0.0 and t < KICK_DOWN + .15:
		var duck := sin(PI * clampf(t / (KICK_DOWN + .15), 0.0, 1.0))
		p.weapon_lag += DUCK * duck
		var lands: float = Brawl.KICK["land"]
		if t >= lands and _kick_punched != at:
			_kick_punched = at
			_punch(feel, KICK_PUNCH)
	var last: Array = b.last_moves.get(slot, [])
	if last.is_empty():
		return
	var move: String = last[0]
	var started: float = last[1]
	var s := game.clock - started
	if s < 0.0 or s > 1.0:
		return
	var path := _path(move, s)
	p.weapon_lag += Vector2(path.x, path.y)
	p.weapon_turn = deg_to_rad(path.z)
	var wind: float = Brawl.FINISH["wind"]
	if s >= wind and _blow_punched != started:
		_blow_punched = started
		var jolt: Array = BLOW_PUNCH.get(move, KICK_PUNCH)
		_punch(feel, jolt)


func _punch(feel: Feel, k: Array) -> void:
	if feel == null:
		return
	var yaw: float = k[0]
	var pitch: float = k[1]
	var drop: float = k[2]
	var sx: float = k[3]
	var sy: float = k[4]
	feel.punch(yaw, pitch, drop, Vector2(sx, sy))


func draw_view(c: Canvas) -> void:
	var shown := boot()
	if shown.is_empty() or game.local_player.health <= 0:
		return
	var pose: String = shown[0]
	var fx: float = shown[1]
	var fy: float = shown[2]
	var x := roundi(fx)
	var y := roundi(fy)
	var cel: Dictionary = game.art.art("fx_boot_" + pose)
	var w: int = cel["w"]
	var h: int = cel["h"]
	# Only the rows over the view (the status bar's below it).
	var rows := mini(h, View.VIEW - y)
	if rows <= 0:
		return
	var data: PackedByteArray = cel["data"]
	if rows < h:
		data = data.slice(0, rows * w * 4)
	var tint := c.view_tint
	if c.gpu and Effects.enabled:
		c.view_tint = game.gun_light()
	c.blit_rgba(data, w, rows, x, y, "boot|%s|%d" % [pose, rows])
	c.view_tint = tint
