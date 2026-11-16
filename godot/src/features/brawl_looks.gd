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
## The kick's beats (seconds from the press): the boot comes up, drives out,
## holds, drops away.
const KICK_UP := .07
const KICK_OUT := .2
const KICK_DOWN := .42
## How far (view pixels) the gun ducks for the kick, down and to the right.
const DUCK := Vector2(34.0, 70.0)
## The finisher moves' gun paths: [seconds from the start, x, y] (pixels the
## gun is off its place), straight between.
const PATHS := {
	"whip": [[0.0, 0.0, 0.0], [.13, 34.0, -16.0], [.17, -86.0, 34.0], [.3, -70.0, 30.0], [.6, 0.0, 0.0]],
	"mouth": [[0.0, 0.0, 0.0], [.13, -24.0, -30.0], [.3, -20.0, -22.0], [.55, 0.0, 0.0]],
	"butt": [[0.0, 0.0, 0.0], [.12, 26.0, 40.0], [.17, -48.0, -46.0], [.32, -40.0, -36.0], [.6, 0.0, 0.0]],
	"belly": [[0.0, 0.0, 0.0], [.13, -6.0, 30.0], [.3, -4.0, 26.0], [.55, 0.0, 0.0]],
	"skull": [[0.0, 0.0, 0.0], [.13, 20.0, -20.0], [.18, -30.0, 30.0], [.5, 0.0, 0.0]],
	"gut": [[0.0, 0.0, 0.0], [.13, 30.0, 10.0], [.18, -50.0, 6.0], [.5, 0.0, 0.0]],
	"stomp": [[0.0, 0.0, 0.0], [.1, 30.0, 90.0], [.5, 30.0, 90.0], [.7, 0.0, 0.0]],
	"punt": [[0.0, 0.0, 0.0], [.1, 34.0, 80.0], [.5, 34.0, 80.0], [.7, 0.0, 0.0]],
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
const PLACES := {"kick_1": [115, 71]}


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
		# Chambered low, then driven up into his face, then away.
		var y := lerpf(80.0, 30.0, clampf(s / wind, 0.0, 1.0))
		if s > wind:
			var k := clampf((s - wind) / .35, 0.0, 1.0)
			y = lerpf(-34.0, 110.0, k * k) if k > .3 else -34.0
		return _at("kick_1", -6.0, y)
	return []


func _kick_pose(t: float) -> Array:
	if t < KICK_UP:
		return _at("kick_1", 0.0, lerpf(100.0, 26.0, t / KICK_UP))
	if t < KICK_OUT:
		# Out, with a little thrust: up and in at the moment it lands.
		var k := (t - KICK_UP) / (KICK_OUT - KICK_UP)
		return _at("kick_1", 0.0, lerpf(26.0, 0.0, minf(1.0, k * 2.5)))
	var d := (t - KICK_OUT) / (KICK_DOWN - KICK_OUT)
	return _at("kick_1", 0.0, lerpf(0.0, 100.0, d * d))


func _at(pose: String, dx: float, dy: float) -> Array:
	var place: Array = PLACES.get(pose, [140, 40])
	var x: float = place[0]
	var y: float = place[1]
	return [pose, x + dx, y + dy]


func _path(move: String, s: float) -> Vector2:
	var keys: Array = PATHS.get(move, [])
	if keys.is_empty():
		return Vector2.ZERO
	var prev := Vector3.ZERO
	for i in keys.size():
		var row: Array = keys[i]
		var t: float = row[0]
		var x: float = row[1]
		var y: float = row[2]
		var key := Vector3(t, x, y)
		if s <= t and i > 0:
			var k := clampf((s - prev.x) / maxf(.001, t - prev.x), 0.0, 1.0)
			k = k * k * (3.0 - 2.0 * k)
			return Vector2(lerpf(prev.y, x, k), lerpf(prev.z, y, k))
		prev = key
	return Vector2(prev.y, prev.z)


func _tick(_dt: float) -> void:
	var b := _brawl()
	if b == null or game.local_player == null:
		return
	var p := game.local_player
	var slot := p.slot
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
	p.weapon_lag += _path(move, s)
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
