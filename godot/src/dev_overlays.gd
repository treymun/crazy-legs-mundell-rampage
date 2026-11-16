## The dev console's overlays over the game view (`show ai|paths|hits|net|
## ticks`, dev_console.gd), drawn on the canvas after the game: points in the
## world are put on the screen with the view's own sums (the eye, horizon and
## focal of game.view_frame, as view3d/world_view.gd places its camera), so
## they line up with the 3D view and work headless too.
##
##   ai     each enemy's state, its squad part (squad.gd Mind), who it is
##          after and how long it has had the player in sight, over its head
##   paths  the way each enemy after the player will walk (the flow field's
##          next steps) and the flow field's arrows round the player
##   hits   each body's hit box (its cylinder, with the head and legs lines of
##          hit_zones.gd) and the last hitscan traces (`traced` events)
##   net    online: the round trip, how far behind the newest snapshot the
##          copy plays, the prediction's last gap, snapshot sizes and bytes
##   ticks  each tick's time (a bar a tick) and the costliest `ticked`
##          listeners, timed as tools/tick_profile.gd does
##
## Looks only: nothing here changes play. Off they cost nothing: no signal is
## listened to, nothing is timed. `ticks` times the listeners by probes put
## between them (each listener is connected again in its own order, so play
## runs as before); `hits` listens to `traced`. Both go when turned off.
class_name DevOverlays
extends RefCounted

const TRACES := 8
const TRACE_SECONDS := 3.0
const TICK_BARS := 120

var ai := false
var paths := false
var hits := false
var net := false
var ticks := false

## The last hitscan traces: [from, to, struck, clock].
var traces: Array = []
var _traced_game: WeakRef = null
## Tick times (ms), and each listener's mean ms a tick.
var tick_ms := PackedFloat32Array()
var listener_ms := {}
var _woven: WeakRef = null
var _woven_count := -1
var _names := PackedStringArray()
var _probes: Array[Callable] = []
var _probe_at := 0
var _spent := {}
## The net view's byte counts a second ago, and the rates.
var _bytes_at := -1.0
var _bytes := Vector2i.ZERO
var _rates := Vector2.ZERO
## The projection of this frame: eye, angle, horizon, focal, view width.
var _eye := Vector3.ZERO
var _angle := 0.0
var _horizon := 0.0
var _focal := 1.0
var _vw := 320
var _scale := 1.0


func any() -> bool:
	return ai or paths or hits or net or ticks


## Toggle one by name; false when there is none by that name.
func toggle(what: String) -> bool:
	match what:
		"ai":
			ai = not ai
		"paths":
			paths = not paths
		"hits":
			hits = not hits
		"net":
			net = not net
		"ticks":
			ticks = not ticks
		_:
			return false
	return true


func off() -> void:
	ai = false
	paths = false
	hits = false
	net = false
	ticks = false
	_follow(null)


func states() -> String:
	var out := PackedStringArray()
	for pair: Array in [
		["ai", ai], ["paths", paths], ["hits", hits], ["net", net], ["ticks", ticks]
	]:
		var on: bool = pair[1]
		var name: String = pair[0]
		if on:
			out.append(name)
	return "overlays: " + (", ".join(out) if not out.is_empty() else "none")


## Every frame (the console's tick): the listeners follow the game in play
## and what is on.
func frame(game: Game) -> void:
	_follow(game)


## A tick of `game` took `us` (main.gd advance, while `ticks` is on).
func tick_took(game: Game, us: int) -> void:
	_follow(game)
	tick_ms.append(us / 1000.0)
	if tick_ms.size() > TICK_BARS:
		tick_ms = tick_ms.slice(tick_ms.size() - TICK_BARS)
	for name: String in _spent:
		var spent: int = _spent[name]
		var ms := spent / 1000.0
		var was: float = listener_ms.get(name, ms)
		listener_ms[name] = lerpf(was, ms, .05)
	_spent.clear()


func draw(c: Canvas, game: Game, main: MainFlow) -> void:
	if game != null and _project_from(game):
		if paths:
			_draw_paths(c, game)
		if hits:
			_draw_hits(c, game)
		if ai:
			_draw_ai(c, game)
	if net:
		_draw_net(c, main)
	if ticks:
		_draw_ticks(c)


# --- listening ---------------------------------------------------------------


func _follow(game: Game) -> void:
	var traced_on: Game = _traced_game.get_ref() if _traced_game != null else null
	var want_traced := game if hits else null
	if traced_on != want_traced:
		if traced_on != null and traced_on.events.traced.is_connected(_on_traced):
			traced_on.events.traced.disconnect(_on_traced)
		traces.clear()
		_traced_game = null
		if want_traced != null:
			want_traced.events.traced.connect(_on_traced)
			_traced_game = weakref(want_traced)
	var woven: Game = _woven.get_ref() if _woven != null else null
	var want_woven := game if ticks else null
	if woven != want_woven:
		if woven != null:
			_unweave(woven.events.ticked)
		_probes.clear()  # the game they were on is gone with them
		_woven = weakref(want_woven) if want_woven != null else null
		_woven_count = -1
		tick_ms.clear()
		listener_ms.clear()
	if want_woven != null:
		_weave(want_woven.events.ticked)


func _on_traced(end: Vector3, struck: String) -> void:
	var game: Game = _traced_game.get_ref() if _traced_game != null else null
	if game == null:
		return
	var p := game.player
	traces.append([Vector3(p.x, p.y, p.eye), end, struck, game.clock])
	if traces.size() > TRACES:
		traces.pop_front()


## Probes between the listeners of `sig`, each listener connected again in
## its own order with its own flags (again whenever one joined or left).
func _weave(sig: Signal) -> void:
	var listeners: Array = []
	for link: Dictionary in sig.get_connections():
		var c: Callable = link["callable"]
		if not _probes.has(c):
			listeners.append(link)
	if listeners.size() == _woven_count:
		return
	_unweave(sig)
	_names.clear()
	for link: Dictionary in listeners:
		var c: Callable = link["callable"]
		sig.disconnect(c)
	sig.connect(_probe_for(0))
	for i in listeners.size():
		var link: Dictionary = listeners[i]
		var c: Callable = link["callable"]
		var flags: int = link["flags"]
		sig.connect(c, flags)
		sig.connect(_probe_for(i + 1))
		_names.append(_name_of(c))
	_woven_count = listeners.size()


## A probe of its own for slot `i` (one method bound twice counts as the same
## connection, so each is a lambda).
func _probe_for(i: int) -> Callable:
	var probe := func(_dt: float) -> void: _probe(i)
	_probes.append(probe)
	return probe


func _unweave(sig: Signal) -> void:
	for probe: Callable in _probes:
		if sig.is_connected(probe):
			sig.disconnect(probe)
	_probes.clear()


func _probe(i: int) -> void:
	var now := Time.get_ticks_usec()
	if i > 0 and i <= _names.size():
		var name := _names[i - 1]
		var had: int = _spent.get(name, 0)
		_spent[name] = had + now - _probe_at
	_probe_at = now


static func _name_of(c: Callable) -> String:
	var who := c.get_object()
	var script_name := "?"
	if who != null:
		var script: Script = who.get_script()
		if script != null:
			script_name = script.resource_path.get_file().get_basename()
	var method: String = c.get_method()
	return script_name if method == "_tick" else "%s.%s" % [script_name, method.left(12)]


# --- the projection ----------------------------------------------------------


func _project_from(game: Game) -> bool:
	var view: Dictionary = game.view_frame
	if view.is_empty():
		return false
	var eye: Dictionary = view["eye"]
	var x: float = eye["x"]
	var y: float = eye["y"]
	var z: float = eye["eye"]
	_eye = Vector3(x, y, z)
	_angle = eye["view_angle"]
	_horizon = view["horizon"]
	_focal = game.view.focal
	_vw = game.view.vw
	_scale = float(Canvas.WIDTH) / maxf(1.0, float(_vw))
	return true


## A map point (x, y, height) on the canvas: Vector3(sx, sy, depth); depth
## under .2 is behind or at the eye.
func _screen(x: float, y: float, z: float) -> Vector3:
	var dx := x - _eye.x
	var dy := y - _eye.y
	var depth := dx * cos(_angle) + dy * sin(_angle)
	if depth < .2:
		return Vector3(0, 0, -1)
	var side := -dx * sin(_angle) + dy * cos(_angle)
	var sx := (_vw * .5 + _focal * side / depth) * _scale
	var sy := (_horizon - _focal * (z - _eye.z) / depth) * _scale
	return Vector3(sx, sy, depth)


## Inside the view (above the status bar).
static func _on_canvas(at: Vector3) -> bool:
	return at.z > 0.0 and at.x >= 0.0 and at.x < Canvas.WIDTH and at.y >= 0.0 and at.y < View.VIEW


func _segment(c: Canvas, a: Vector3, b: Vector3, colour: Color) -> void:
	# Cut to the part in front of the eye, then draw what can show.
	var pa := _screen(a.x, a.y, a.z)
	var pb := _screen(b.x, b.y, b.z)
	if pa.z <= 0.0 and pb.z <= 0.0:
		return
	if pa.z <= 0.0 or pb.z <= 0.0:
		var da := (a.x - _eye.x) * cos(_angle) + (a.y - _eye.y) * sin(_angle)
		var db := (b.x - _eye.x) * cos(_angle) + (b.y - _eye.y) * sin(_angle)
		var t := clampf((.25 - da) / (db - da), 0.0, 1.0) if absf(db - da) > 1e-6 else 0.0
		var cut := a.lerp(b, t)
		if pa.z <= 0.0:
			pa = _screen(cut.x, cut.y, cut.z)
		else:
			pb = _screen(cut.x, cut.y, cut.z)
	# Cut to the view (Liang-Barsky): never over the status bar.
	var p0 := Vector2(pa.x, pa.y)
	var d := Vector2(pb.x, pb.y) - p0
	var t0 := 0.0
	var t1 := 1.0
	var edges := [
		[-d.x, p0.x], [d.x, Canvas.WIDTH - 1.0 - p0.x], [-d.y, p0.y], [d.y, View.VIEW - 1.0 - p0.y]
	]
	for edge: Array in edges:
		var q: float = edge[0]
		var r: float = edge[1]
		if absf(q) < 1e-9:
			if r < 0.0:
				return
			continue
		var t := r / q
		if q < 0.0:
			t0 = maxf(t0, t)
		else:
			t1 = minf(t1, t)
		if t0 > t1:
			return
	var a2 := p0 + d * t0
	var b2 := p0 + d * t1
	c.stroke(int(a2.x), int(a2.y), int(b2.x), int(b2.y), colour)


# --- the overlays ------------------------------------------------------------


func _draw_ai(c: Canvas, game: Game) -> void:
	for e: Enemy in game.enemies:
		if e.hp <= 0.0:
			continue
		var feet: float = game.world.stand(e) + e.z
		var at := _screen(e.x, e.y, feet + e.height * e.variant + .15)
		if at.z <= 0.0 or at.z > 22.0 or at.x < -20.0 or at.x > Canvas.WIDTH + 20.0:
			continue
		var lines := PackedStringArray()
		for text: String in [_state_of(e, game), _part_of(e, game), _after_of(e, game)]:
			if text != "":
				lines.append(text)
		var colour := (
			HUD.AMBER
			if e.alerted and e.player_seen
			else (Color(1, .6, .2) if e.alerted else HUD.INK)
		)
		# Over its head; one close by whose head is off the top keeps to the top.
		var bottom := clampi(int(at.y), lines.size() * 6 + 1, View.VIEW - 2)
		for k in lines.size():
			HUD.text(c, lines[k], int(at.x), bottom - 6 * (lines.size() - k), "mini", colour, true)


static func _state_of(e: Enemy, game: Game) -> String:
	var state := ""
	if e.dormant:
		state = "ASLEEP"
	elif not e.hostile:
		state = "CALM"
	elif not e.alerted:
		state = "IDLE"
	elif e.player_seen:
		state = "FIGHT"
	else:
		state = "HUNT" if game.clock < e.hunt_until else "LOST"
	var flags := PackedStringArray()
	if e.windup > 0.0:
		flags.append("WIND")
	if e.recovery > 0.0:
		flags.append("RECOVER")
	if e.stun > 0.0:
		flags.append("STUN")
	if e.cover != null:
		flags.append("COVER")
	if e.fetching != null:
		flags.append("FETCH")
	if e.grudge != null:
		flags.append("BRAWL")
	if e.retreat != null:
		flags.append("BACK")
	var head := "%s %s" % [e.kind.to_upper(), state]
	return head if flags.is_empty() else head + " " + " ".join(flags)


static func _part_of(e: Enemy, game: Game) -> String:
	var m := e.mind
	if m == null:
		return ""
	var now := game.clock
	if m.activity != "":
		return "IDLE: " + m.activity.to_upper()
	if m.flush_at > now:
		return "FLUSH"
	if m.flank_until > now:
		return "FLANK %s" % ("L" if m.flank_side < 0.0 else "R")
	if m.press_until > now:
		return "PRESS"
	if m.regroup != null:
		return "REGROUP"
	if m.reload_until > now:
		return "RELOAD"
	if m.peek_to != Vector2.INF:
		return "PEEK"
	if m.investigate != null:
		return "LOOK"
	if m.search_until > now:
		return "SEARCH %.0fS" % (m.search_until - now)
	return ""


static func _after_of(e: Enemy, game: Game) -> String:
	var parts := PackedStringArray()
	if e.hunted != null and game.players.size() > 1:
		parts.append("AFTER P%d" % (game.players.find(e.hunted) + 1))
	if e.see_time > 0.0:
		parts.append("SEEN %.1fS" % e.see_time)
	if e.heard != null:
		parts.append("HEARD")
	return " ".join(parts)


func _draw_paths(c: Canvas, game: Game) -> void:
	if game.flow == null:
		return
	var p := game.player
	var floor_z: float = game.world.elevation(p.x, p.y)
	# The flow field's arrows round the player: each cell to the next one down.
	var px := int(p.x)
	var py := int(p.y)
	var w := game.world.width
	for gy in range(-7, 8):
		for gx in range(-7, 8):
			var cx := px + gx
			var cy := py + gy
			if cx < 0 or cy < 0 or cx >= w or cy >= game.world.height:
				continue
			if game.world.solid[cy * w + cx] >= 0:
				continue
			var from := Vector2(cx + .5, cy + .5)
			var to := game.flow.waypoint(from.x, from.y, 1)
			if to == from:
				continue
			var z := game.world.elevation(from.x, from.y) + .02
			var tip := from.lerp(to, .45)
			_segment(c, Vector3(from.x, from.y, z), Vector3(tip.x, tip.y, z), Color(.3, .6, .9))
	# The way each enemy after the player will walk.
	for e: Enemy in game.enemies:
		if not e.alive or not e.hostile or not e.alerted:
			continue
		var steps: Array = []
		game.flow.waypoint(e.x, e.y, 10, steps)
		var last := Vector3(e.x, e.y, game.world.stand(e) + .05)
		var colour := Color(1, .3, .2) if e.player_seen else Color(1, .65, .15)
		for cell: Vector2i in steps:
			var next := Vector3(cell.x + .5, cell.y + .5, floor_z)
			next.z = game.world.elevation(next.x, next.y) + .05
			_segment(c, last, next, colour)
			last = next
		if e.target is Array:
			var mark: Array = e.target
			if mark.size() >= 2:
				var tx: float = mark[0]
				var ty: float = mark[1]
				var tz := game.world.elevation(tx, ty) + .05
				_segment(c, Vector3(tx - .2, ty, tz), Vector3(tx + .2, ty, tz), Color(1, 1, 1))
				_segment(c, Vector3(tx, ty - .2, tz), Vector3(tx, ty + .2, tz), Color(1, 1, 1))


func _draw_hits(c: Canvas, game: Game) -> void:
	for e: Enemy in game.enemies:
		if not e.alive:
			continue
		var feet: float = game.world.stand(e) + e.z
		var tall := e.height * e.variant
		var zones := [
			[0.0, Color(.9, .9, .3)],
			[HitZones.LEGS_BELOW, Color(.4, .8, 1)],
			[HitZones.HEAD_AT, Color(1, .3, .3)],
			[1.0, Color(.9, .9, .3)],
		]
		_box(c, e.x, e.y, e.radius, feet, tall, zones)
	for q: Player in game.players:
		if q == game.local_player or q.health <= 0:
			continue
		var feet: float = game.world.stand(q)
		_box(c, q.x, q.y, GameState.PLAYER_RADIUS, feet, q.eye - feet + .12, [[0.0, HUD.INK]])
	var now := game.clock
	for t: Array in traces:
		var when: float = t[3]
		var age := now - when
		if age > TRACE_SECONDS or age < 0.0:
			continue
		var from: Vector3 = t[0]
		var to: Vector3 = t[1]
		var struck: String = t[2]
		var colour := Color(1, .25, .2) if struck == "enemy" else Color(1, .9, .4)
		# Start a little ahead of the eye, where the muzzle would be.
		var dir := (to - from).normalized()
		_segment(c, from + dir * .4 - Vector3(0, 0, .12), to, colour)
		var hit := _screen(to.x, to.y, to.z)
		if _on_canvas(hit):
			c.fill_rect(int(hit.x) - 1, int(hit.y) - 1, 3, 3, colour)


## A body's cylinder as its outline seen from the eye, with a line across at
## each of `zones` ([share of the height, colour]).
func _box(c: Canvas, x: float, y: float, r: float, feet: float, tall: float, zones: Array) -> void:
	var near := _screen(x, y, feet)
	if near.z <= 0.0 or near.z > 24.0:
		return
	var side := Vector2(-sin(_angle), cos(_angle)) * r
	var a := Vector2(x, y) - side
	var b := Vector2(x, y) + side
	var top := feet + tall
	var edge := Color(.9, .9, .3)
	_segment(c, Vector3(a.x, a.y, feet), Vector3(a.x, a.y, top), edge)
	_segment(c, Vector3(b.x, b.y, feet), Vector3(b.x, b.y, top), edge)
	for zone: Array in zones:
		var share: float = zone[0]
		var colour: Color = zone[1]
		var z := feet + tall * share
		_segment(c, Vector3(a.x, a.y, z), Vector3(b.x, b.y, z), colour)


func _draw_net(c: Canvas, main: MainFlow) -> void:
	var lines := PackedStringArray()
	var play: NetPlay = main.net
	if play == null:
		lines.append("NET: OFFLINE")
	else:
		lines.append("NET: " + ("HOST" if play.role == NetPlay.Role.HOST else "CLIENT"))
		var session: Object = play.session
		if session != null:
			_count_bytes(session)
			lines.append("OUT %.1f KB/S  IN %.1f KB/S" % [_rates.x / 1024.0, _rates.y / 1024.0])
		var client: Object = play.client_sync
		if client != null:
			var lags: Variant = client.get("lag_samples")
			if lags is PackedFloat32Array:
				var all: PackedFloat32Array = lags
				if not all.is_empty():
					var recent := all.slice(maxi(0, all.size() - 30))
					recent.sort()
					lines.append("INPUT TO ACK %.0f MS" % recent[recent.size() / 2])
			var latest: Variant = client.get("latest_tick")
			var at: Variant = client.get("game_tick")
			if latest is int and at is int:
				var newest: int = latest
				var playing: int = at
				var behind := newest - playing
				lines.append("PLAYS %d TICKS BEHIND (%.0f MS)" % [behind, behind * 1000.0 / 120.0])
			var mismatches: Variant = client.get("mismatches")
			if mismatches is int:
				lines.append("MISMATCHES %d" % mismatches)
			var smooth: Object = main.get("net_smooth")
			if smooth != null:
				var gap: Variant = smooth.get("last_gap")
				if gap is float:
					lines.append("PREDICTION GAP %.3f" % gap)
		var host: Object = play.host_sync
		if host != null:
			for pair: Array in [["sizes_delta", "DELTA"], ["sizes_full", "FULL"]]:
				var field: String = pair[0]
				var sizes: Variant = host.get(field)
				if sizes is PackedInt32Array:
					var all: PackedInt32Array = sizes
					if not all.is_empty():
						lines.append("%s %d B (LAST)" % [pair[1], all[all.size() - 1]])
			var us: Variant = host.get("capture_us")
			if us is int:
				var capture: int = us
				lines.append("CAPTURE %.2f MS" % (capture / 1000.0))
	var top := 40
	c.fill_rect(2, top - 1, 132, lines.size() * 6 + 2, Color(0, 0, 0))
	for k in lines.size():
		HUD.text(c, lines[k], 4, top + k * 6, "mini", HUD.INK, false, false)


func _count_bytes(session: Object) -> void:
	var sent: Variant = session.get("sent")
	var got: Variant = session.get("received")
	if not (sent is int and got is int):
		return
	var out: int = sent
	var into: int = got
	var now := Time.get_ticks_msec() / 1000.0
	if _bytes_at < 0.0 or now - _bytes_at >= 1.0:
		if _bytes_at >= 0.0:
			var span := now - _bytes_at
			_rates = Vector2((out - _bytes.x) / span, (into - _bytes.y) / span)
		_bytes_at = now
		_bytes = Vector2i(out, into)


static func _costlier(a: Array, b: Array) -> bool:
	var x: float = a[0]
	var y: float = b[0]
	return x > y


func _draw_ticks(c: Canvas) -> void:
	var left := Canvas.WIDTH - TICK_BARS - 6
	var top := 112
	c.fill_rect(left, top, TICK_BARS + 2, 34, Color(0, 0, 0))
	var mean := 0.0
	var worst := 0.0
	for i in tick_ms.size():
		var ms := tick_ms[i]
		mean += ms
		worst = maxf(worst, ms)
		# 8 pixels a millisecond; the line is a tick's share of a 60 Hz frame.
		var tall := clampi(int(ms * 8.0), 0, 32)
		var colour := Color(.3, .9, .3) if ms <= 2.0 else Color(.95, .3, .2)
		c.fill_rect(left + 1 + i, top + 33 - tall, 1, tall, colour)
	c.fill_rect(left, top + 33 - 16, TICK_BARS + 2, 1, Color(.9, .8, .3))
	mean /= maxf(1.0, tick_ms.size())
	HUD.text(
		c,
		"TICK %.2f MS  WORST %.2f" % [mean, worst],
		left + 2,
		top + 1,
		"mini",
		HUD.INK,
		false,
		false
	)
	var rows: Array = []
	var listeners := 0.0
	for name: String in listener_ms:
		var ms: float = listener_ms[name]
		listeners += ms
		rows.append([ms, name])
	rows.sort_custom(_costlier)
	var lines := PackedStringArray(["CORE %.2f" % maxf(0.0, mean - listeners)])
	for row: Array in rows.slice(0, 6):
		var name: String = row[1]
		lines.append("%s %.2f" % [name.to_upper().replace("_", " "), row[0]])
	var list_top := top - 2 - lines.size() * 6
	c.fill_rect(left, list_top - 1, TICK_BARS + 2, lines.size() * 6 + 2, Color(0, 0, 0))
	for k in lines.size():
		HUD.text(c, lines[k], left + 2, list_top + k * 6, "mini", HUD.INK, false, false)
