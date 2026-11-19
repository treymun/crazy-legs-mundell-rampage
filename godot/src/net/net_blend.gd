## Everyone else drawn between ticks. Online the game ticks 60 times a
## second (NetSync.STEP) while a screen draws 60 to 240 frames: a client's
## copy moved the other players, the hands and the shots a whole tick at a
## time, so on a 144 Hz screen each held still for two or three frames and
## then jumped (and single-player, at 120 ticks, held one frame in six).
## Each frame this puts them where they were between the copy's last two
## ticks, at the fraction the client's playout clock says this frame shows
## (NetSync.Client.view_at); the host's own view uses its tick's remainder.
## Looks only: put on for the frame (main.gd net_draw_begin) and put back
## after it (net_draw_end), so the copy and what it plays never change.
class_name NetBlend
extends RefCounted

## Off: the copy drawn at its tick as it stands (net_lag/net_feel `old`).
static var enabled := true
## A move longer than this between two ticks (cells) is a respawn or a
## round's new start: drawn where it is, never slid there.
const TELEPORT := 1.5
## A frame that stepped the copy more ticks than this (a catch-up) is not
## blended across.
const MOST_SPAN := 4

## key -> [object, x, y, ...] as the copy stood at _cur_tick and _prev_tick.
var _cur := {}
var _prev := {}
var _cur_tick := -1
var _prev_tick := -1
var _game: WeakRef = null
## What was put on this frame (keys of _cur), to put back.
var _moved: Array = []
## For net_feel.gd: the share of the tick this frame was blended at (-1 none).
var last_share := -1.0


## Puts everyone but `skip` (our own player, drawn by the prediction) where
## the copy had them at tick `at` (a fraction between its last two ticks);
## `tick` is the tick the copy is at. Call end() after the frame.
func begin(game: Game, tick: int, at: float, skip: Player) -> void:
	_moved.clear()
	last_share = -1.0
	if not enabled or game == null:
		forget()
		return
	if _game == null or _game.get_ref() != game:
		forget()
		_game = weakref(game)
	if tick != _cur_tick:
		var now := _read(game)
		if _cur_tick >= 0 and tick > _cur_tick and tick - _cur_tick <= MOST_SPAN:
			_prev = _cur
			_prev_tick = _cur_tick
		else:
			_prev = {}
			_prev_tick = -1
		_cur = now
		_cur_tick = tick
	if _prev.is_empty() or at < 0.0:
		return
	var share := clampf((at - _prev_tick) / float(_cur_tick - _prev_tick), 0.0, 1.0)
	last_share = share
	if share >= 1.0:
		return
	for key: String in _cur:
		var was: Array = _prev.get(key, [])
		if was.is_empty():
			continue
		var row: Array = _cur[key]
		var who: Object = row[0]
		if who == skip or who != was[0]:
			continue
		var x0: float = was[1]
		var y0: float = was[2]
		var x1: float = row[1]
		var y1: float = row[2]
		if absf(x1 - x0) + absf(y1 - y0) > TELEPORT:
			continue
		_put(who, was, row, share)
		_moved.append(key)


## Everyone put back where the copy has them.
func end() -> void:
	for key: String in _moved:
		var row: Array = _cur[key]
		var who: Object = row[0]
		_put(who, row, row, 0.0)
	_moved.clear()


## Forgets the ticks seen (another match, a copy put back far off).
func forget() -> void:
	end()
	_cur = {}
	_prev = {}
	_cur_tick = -1
	_prev_tick = -1


## The drawn places of everything that moves: enemies and shots by uid,
## players by slot.
static func _read(game: Game) -> Dictionary:
	var out := {}
	for e: Enemy in game.enemies:
		if e.uid > 0:
			out["e%d" % e.uid] = [e, e.x, e.y, e.angle]
	for p: Player in game.players:
		if p.health > 0 and not p.away:
			out["p%d" % p.slot] = [p, p.x, p.y, p.angle, p.pitch, p.eye, p.air]
	for s: GameState.Shot in game.shots:
		if s.uid > 0:
			out["s%d" % s.uid] = [s, s.x, s.y, s.z]
	return out


## Sets `who` part way (`share`) from row `a` to row `b`.
static func _put(who: Object, a: Array, b: Array, share: float) -> void:
	var x0: float = a[1]
	var y0: float = a[2]
	var x1: float = b[1]
	var y1: float = b[2]
	var turn0: float = a[3]
	var turn1: float = b[3]
	if who is Enemy:
		var e: Enemy = who
		e.x = lerpf(x0, x1, share)
		e.y = lerpf(y0, y1, share)
		e.angle = _turn(turn0, turn1, share)
	elif who is Player:
		var p: Player = who
		p.x = lerpf(x0, x1, share)
		p.y = lerpf(y0, y1, share)
		p.angle = _turn(turn0, turn1, share)
		var pitch0: float = a[4]
		var pitch1: float = b[4]
		var eye0: float = a[5]
		var eye1: float = b[5]
		var air0: float = a[6]
		var air1: float = b[6]
		p.pitch = lerpf(pitch0, pitch1, share)
		p.eye = lerpf(eye0, eye1, share)
		p.air = lerpf(air0, air1, share)
	else:
		var s: GameState.Shot = who
		var z0: float = a[3]
		var z1: float = b[3]
		s.x = lerpf(x0, x1, share)
		s.y = lerpf(y0, y1, share)
		s.z = lerpf(z0, z1, share)


static func _turn(from: float, to: float, share: float) -> float:
	if share <= 0.0:
		return from
	return fposmod(from + angle_difference(from, to) * share, TAU)
