## Always-open lobbies on a server (main.gd --lobby-server=<config.json>):
## one process, no window, sound or menus, a NetPlay.serve_lobby per lobby,
## each on its own UDP port, sharing the game's art. Nobody hosts: the first
## player in a lobby runs it (net_play.gd), bots fill the teams and are
## played here (TacticalBot), and a match goes back to its lobby on its own.
##
##   godot --headless --path godot -- --lobby-server=res://tools/lobbies.json
##
## The config (JSON): {"bind": "*", "lobbies": [{"port": 47197, "lobby_name":
## "5V5 SEARCH & DESTROY", "mode": "bomb", "map": "grainyard", ...}, ...]},
## each lobby's keys any of NetPlay.DEFAULTS. A lobby's "ws_port" also takes
## the browser build over a WebSocket on that TCP port, secured (wss) with the
## config's "tls_cert" and "tls_key" files when both load (a browser page on
## https may only open wss). The config's "relay" ({} for NetRelay.DEFAULTS,
## or any of them) runs THE PARTY LINE on the same ports: players' own lobbies
## reached through the server by a short code (net_relay.gd). Prints a line for
## everyone who comes and goes, each match, each party line room, and every
## STATUS_EVERY seconds how busy it is.
class_name LobbyServer
extends Node

## Seconds between status lines (the config's "status_every").
const STATUS_EVERY := 300.0
## Ticks played in one wake at most (the rest of a stall is caught up at the
## next, at once).
const MOST_STEPS := 8
## Behind the schedule by more than this (ms) the server lets the time go
## (the schedule starts again from now) instead of racing to catch it up.
const SLIP_MS := 500.0
## While the party line has players the server wakes at least this often
## (ms) between ticks to pass their packets on.
const RELAY_POLL_MS := 4.0
## Off: the old loop (Engine.max_fps frames, each room's ticks from the
## frame's delta, every snapshot of a catch-up sent): net_pace.gd's `old`,
## or the config's "paced": false.
static var paced := true
## Matches on at once at most (the config's "most_matches"): one 5v5 with
## nine bots is about 15-20% of a small VPS core (40% before NetSync's
## snapshots came from NetTrack).
const MOST_MATCHES := 2
## Frames a second while every lobby waits, and while a match is on.
const IDLE_FPS := 20
const MATCH_FPS := 120


## One lobby and the bots playing in its match.
class Room:
	extends RefCounted
	var net: NetPlay
	var pilots := {}
	var accum := 0.0
	var matches := 0
	var ticks := 0
	var tick_us := 0
	var worst_us := 0
	## Of tick_us, the bots' steering.
	var bot_us := 0
	## The bots' controls for the next tick (steered after this one went out).
	var own := {}
	## Pacing since the last status: ms between snapshots going out, each
	## tick's cost (ms), and the snapshot number last seen going out.
	var gaps := PackedFloat32Array()
	var costs := PackedFloat32Array()
	var sent_seq := -1
	var sent_at := -1.0


var rooms: Array[Room] = []
var art: Assets
## Every match's game made here (_make): a finished match's is disposed
## (GamePool) once its lobby has let it go.
var games := GamePool.new()
var sim := {}
var most_matches := MOST_MATCHES
## THE PARTY LINE on the lobbies' ports (null: the config has no "relay").
var relay: NetRelay = null
var _status_in := 10.0
var _status_at := 0.0
var status_every := STATUS_EVERY
var _failed := ""
## The schedule (paced): when the next tick is due (ms on frame()'s clock;
## -1 no match on), how often the time was let go, the ticks played.
var _due := -1.0
var slips := 0
var ticks := 0
var _rest_set := false


## `config` is the parsed config; `sim_options` every match is configured
## with (difficulty, gore...: the settings that change play).
func _init(config: Dictionary, sim_options := {}) -> void:
	sim = sim_options
	art = Assets.new()
	var bind := str(config.get("bind", "*"))
	var tls := _tls(config)
	most_matches = config.get("most_matches", MOST_MATCHES)
	status_every = config.get("status_every", STATUS_EVERY)
	if config.has("paced"):
		paced = config["paced"]
	var relay_config: Variant = config.get("relay")
	var line_peers := 0
	if relay_config is Dictionary:
		var relay_dict: Dictionary = relay_config
		relay = NetRelay.new(relay_dict)
		line_peers = relay.limits["peers"]
	for entry: Variant in config.get("lobbies", []):
		if not entry is Dictionary:
			continue
		var entry_dict: Dictionary = entry
		var lobby := entry_dict.duplicate()
		var port: int = lobby.get("port", NetSession.PORT)
		lobby.erase("port")
		var ws_port: int = lobby.get("ws_port", 0)
		lobby.erase("ws_port")
		var net := NetPlay.serve_lobby(port, lobby, bind, line_peers)
		if net == null:
			_failed = "PORT %d IS TAKEN" % port
			continue
		if ws_port > 0:
			var ws := NetSession.host(
				ws_port, NetSession.Transport.WEBSOCKET, Modes.MAX_PLAYERS + 6, bind, tls
			)
			if ws == null:
				_failed = "PORT %d (WEBSOCKET) IS TAKEN" % ws_port
			else:
				net.session.also = ws
				_log("  and %s on TCP %d" % ["WSS" if tls != null else "WS", ws_port])
				if relay != null:
					relay.tap(ws)
		if relay != null:
			relay.tap(net.session)
		net.make_match = _make
		net.may_start = _may_start
		net.sim_options = sim
		var room := Room.new()
		room.net = net
		rooms.append(room)
		_log(
			(
				"OPEN %s on UDP %d (%s, %s)"
				% [net.settings["lobby_name"], port, net.settings["mode"], net.settings["map"]]
			)
		)


## The config's certificate for wss (null: none, or it would not load).
static func _tls(config: Dictionary) -> TLSOptions:
	var cert_path := str(config.get("tls_cert", ""))
	var key_path := str(config.get("tls_key", ""))
	if cert_path == "" or key_path == "":
		return null
	var cert := X509Certificate.new()
	var key := CryptoKey.new()
	if cert.load(cert_path) != OK or key.load(key_path) != OK:
		print("TLS: cannot read %s or %s; the WebSocket side is plain" % [cert_path, key_path])
		return null
	return TLSOptions.server(key, cert)


## "" when another match may start, else why not.
func _may_start() -> String:
	var on := rooms.filter(func(r: Room) -> bool: return r.net.phase == "match").size()
	if on >= most_matches:
		return "THE SERVER HAS %d MATCHES ON: TRY AGAIN WHEN ONE ENDS" % on
	return ""


## The config at `path` (res://, user:// or a plain path); {} when unreadable.
static func read_config(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _ready() -> void:
	if rooms.is_empty() or _failed != "":
		_log(
			"COULD NOT OPEN EVERY LOBBY: %s" % (_failed if _failed != "" else "NONE IN THE CONFIG")
		)
		get_tree().quit(1)
		return
	Engine.max_fps = IDLE_FPS
	_log(
		(
			"VERSION %s, %d LOBBIES%s"
			% [
				ProjectSettings.get_setting("application/config/version", "?"),
				rooms.size(),
				", THE PARTY LINE ON THEIR PORTS" if relay != null else ""
			]
		)
	)


func _process(delta: float) -> void:
	if not paced:
		frame(float(Time.get_ticks_msec()), delta)
		return
	if not _rest_set:
		# The loop sleeps itself (_rest): no frame cap, and none of the
		# headless main loop's own sleep between frames
		# (OS.low_processor_usage_mode_sleep_usec, 6.9 ms).
		_rest_set = true
		Engine.max_fps = 0
		OS.low_processor_usage_mode_sleep_usec = 0
	frame(Time.get_ticks_usec() / 1000.0, delta)
	_rest(Time.get_ticks_usec() / 1000.0)


## Sleeps until the next tick is due, or (the party line busy) its next
## look, or the idle beat.
func _rest(now: float) -> void:
	var wake := now + 1000.0 / IDLE_FPS
	if _due >= 0.0:
		wake = minf(wake, _due)
	if relay != null and relay.busy():
		wake = minf(wake, now + RELAY_POLL_MS)
	if wake > now:
		OS.delay_usec(int((wake - now) * 1000.0))


## One frame: every lobby polled at `now` (ms), the matches' ticks due by
## then played (tools drive it on their own clock, a tick's time a frame;
## `delta` is only the old loop's).
func frame(now: float, delta: float) -> void:
	var busy := false
	for room in rooms:
		_poll(room, now)
		if room.net.phase == "match":
			busy = true
			if not paced:
				_play(room, delta)
	if paced:
		_play_due(now)
	if relay != null:
		relay.poll(now)
		# What the lobbies' polls forwarded goes out now, not a frame later.
		relay.flush()
		for line: String in relay.take_news():
			_log("PARTY LINE: " + line)
		busy = busy or relay.busy()
	if not paced:
		Engine.max_fps = MATCH_FPS if busy else IDLE_FPS
		_note_sends(Time.get_ticks_usec() / 1000.0)
	if games.size() > 0:
		games.sweep(rooms.map(func(r: Room) -> Game: return r.net.match_game()))
	_status_in -= delta if not paced else clampf(now - _status_at, 0.0, 1000.0) / 1000.0
	_status_at = now
	if _status_in <= 0.0:
		_status_in = status_every
		_status()


## The ticks due by `now` on one schedule for every match (paced): a tick
## every NetSync.STEP from when the first match began, so the snapshots go
## out evenly whatever each wake's own timing. A late wake plays the ticks
## it owes (MOST_STEPS at most, the rest at the next, at once) and only the
## last of them sends snapshots: a stall never sends a burst of them. Each
## tick's packets leave at once (flushed); the bots steer for the next tick
## after that, off the snapshots' way.
func _play_due(now: float) -> void:
	var on: Array[Room] = []
	for room in rooms:
		if room.net.phase == "match" and room.net.match_game() != null:
			on.append(room)
	if on.is_empty():
		_due = -1.0
		return
	var step_ms := NetSync.STEP * 1000.0
	if _due < 0.0:
		_due = now
	elif now - _due > SLIP_MS:
		slips += 1
		_due = now
	if now + .001 < _due:
		return
	var owed := mini(MOST_STEPS, floori((now + .001 - _due) / step_ms) + 1)
	for i in owed:
		ticks += 1
		for room in on:
			if room.net.phase == "match":
				_tick(room, i < owed - 1)
		_due += step_ms
	_note_sends(Time.get_ticks_usec() / 1000.0)


## One tick of a room's match (paced) with the bots' controls steered after
## the last and every client's next input; `hold` keeps its snapshots for
## the wake's last tick. Its packets go out at once, then the bots steer.
func _tick(room: Room, hold: bool) -> void:
	var g := room.net.match_game()
	var host := room.net.host_sync
	if g == null or host == null:
		return
	var t0 := Time.get_ticks_usec()
	if room.own.is_empty() and not room.pilots.is_empty():
		room.own = _steer(room, g, false)
	var bots_us := Time.get_ticks_usec() - t0
	host.hold = hold
	if host.snap_phase < 0:
		# The rooms' snapshots on alternate ticks: their costs spread out.
		host.snap_phase = (ticks + rooms.find(room)) % host.snap_every
	room.net.host_tick(room.own)
	host.hold = false
	if not hold and room.net.session != null:
		room.net.session.flush()
	var t1 := Time.get_ticks_usec()
	room.own = _steer(room, g, true) if room.net.phase == "match" else {}
	bots_us += Time.get_ticks_usec() - t1
	var spent := Time.get_ticks_usec() - t0
	room.bot_us += bots_us
	room.ticks += 1
	room.tick_us += spent
	room.worst_us = maxi(room.worst_us, spent)
	room.costs.append(spent / 1000.0)


## The bots' controls for the next tick (`after`: each has seen the tick
## its last controls played first, TacticalBot.moved).
func _steer(room: Room, g: Game, after: bool) -> Dictionary:
	var out := {}
	for slot: int in room.pilots:
		if slot >= g.players.size():
			continue
		var p: Player = g.players[slot]
		var pilot: TacticalBot = room.pilots[slot]
		g.focus(p)
		if after and room.own.has(slot):
			pilot.moved(g)
		if p.health > 0:
			out[slot] = pilot.steer(g)
	g.focus(g.local_player)
	return out


## Notes the snapshots that went out by `now` (ms): the gap since each
## room's last.
func _note_sends(now: float) -> void:
	for room in rooms:
		var host := room.net.host_sync
		if host == null or room.net.phase != "match":
			room.sent_at = -1.0
			continue
		if host.seq == room.sent_seq:
			continue
		room.sent_seq = host.seq
		if room.sent_at >= 0.0:
			room.gaps.append(now - room.sent_at)
		room.sent_at = now


func _poll(room: Room, now: float) -> void:
	var net := room.net
	net.poll(now)
	for line: String in net.take_news():
		_log("%s: %s" % [net.settings["lobby_name"], line])
	for change: Dictionary in net.take_changes():
		if change.has("started"):
			room.pilots.clear()
			room.own = {}
			room.accum = 0.0
			room.sent_at = -1.0
			room.matches += 1
			for slot: int in net.bot_slots():
				room.pilots[slot] = TacticalBot.new(slot)
			_log(
				(
					"%s: MATCH ON %s (%s), %d PEOPLE"
					% [
						net.settings["lobby_name"],
						net.settings["map"],
						net.settings["mode"],
						net.players.size()
					]
				)
			)
		elif change.has("lobby"):
			room.pilots.clear()
			room.own = {}
			_log("%s: BACK TO THE LOBBY" % net.settings["lobby_name"])
		elif change.has("bot"):
			var bot: int = change["bot"]
			room.pilots[bot] = TacticalBot.new(bot)
		elif change.has("human"):
			var human: int = change["human"]
			room.pilots.erase(human)
			room.own.erase(human)


## A frame's ticks of a room's match at the network's rate: the bots' controls
## and every client's next input (NetPlay.host_tick).
func _play(room: Room, delta: float) -> void:
	room.accum = minf(room.accum + delta, NetSync.STEP * MOST_STEPS)
	while room.accum >= NetSync.STEP and room.net.phase == "match":
		room.accum -= NetSync.STEP
		var g := room.net.match_game()
		if g == null:
			return
		var t0 := Time.get_ticks_usec()
		var own := {}
		for slot: int in room.pilots:
			var p: Player = g.players[slot]
			if p.health > 0:
				g.focus(p)
				var pilot: TacticalBot = room.pilots[slot]
				own[slot] = pilot.steer(g)
		g.focus(g.local_player)
		var steered := Time.get_ticks_usec() - t0
		room.net.host_tick(own)
		var t1 := Time.get_ticks_usec()
		for slot: int in room.pilots:
			g.focus(g.players[slot])
			var pilot: TacticalBot = room.pilots[slot]
			pilot.moved(g)
		g.focus(g.local_player)
		room.bot_us += steered + Time.get_ticks_usec() - t1
		var spent := Time.get_ticks_usec() - t0
		room.ticks += 1
		room.tick_us += spent
		room.worst_us = maxi(room.worst_us, spent)
		room.costs.append(spent / 1000.0)


## A match's game, as every client makes its copy (main_flow.gd
## net_match_game), on a host game: no looks, no sound, nothing drawn.
func _make(info: Dictionary) -> Game:
	var level := str(info["level"])
	if not FileAccess.file_exists("res://data/%s.json" % level):
		return null
	var made := Game.new(art, null, QuietSound.new(), level, true)
	var opts := sim.duplicate()
	var info_sim: Dictionary = info.get("sim", {})
	opts.merge(info_sim, true)
	made.configure(opts)
	var count: int = info["count"]
	var options: Dictionary = info["options"]
	Modes.setup(made, str(info["mode"]), count, options)
	return games.track(made)


## The process's resident memory in MB (Linux; else Godot's own count, which
## a release build leaves at 0).
static func memory_mb() -> float:
	# Line by line: a /proc file says it is 0 bytes long, so reading it whole
	# read nothing and every status line said 0 MB.
	var f := FileAccess.open("/proc/self/status", FileAccess.READ)
	if f != null:
		while not f.eof_reached():
			var line := f.get_line()
			if line.begins_with("VmRSS:"):
				return float(line.get_slice(":", 1).strip_edges().get_slice(" ", 0)) / 1024.0
	return OS.get_static_memory_usage() / 1048576.0


func _status() -> void:
	var mem := memory_mb()
	var parts: PackedStringArray = []
	for room in rooms:
		var n := room.net
		var avg := room.tick_us / maxf(1.0, room.ticks) / 1000.0
		var line := (
			"%s %s %d in, %d matches, tick %.2f ms (bots %.2f, worst %.1f)"
			% [
				n.port,
				n.phase,
				n.players.size(),
				room.matches,
				avg,
				room.bot_us / maxf(1.0, room.ticks) / 1000.0,
				room.worst_us / 1000.0
			]
		)
		if room.gaps.size() > 1:
			var p := pacing(room)
			line += (
				", snaps %.1f ms apart (p99 %.1f, worst %.1f, %d bunched), tick p99 %.2f"
				% [p["gap_med"], p["gap_p99"], p["gap_max"], p["bunched"], p["cost_p99"]]
			)
		parts.append(line)
		room.ticks = 0
		room.tick_us = 0
		room.worst_us = 0
		room.bot_us = 0
		room.gaps.clear()
		room.costs.clear()
	if relay != null:
		parts.append(relay.status())
	if slips > 0:
		parts.append("%d SLIPS" % slips)
		slips = 0
	_log("STATUS %.0f MB; %s" % [mem, "; ".join(parts)])


## A room's pacing since the last status: the snapshots' gaps (median, p99,
## worst ms; `bunched`: closer than half the beat) and its ticks' cost (ms).
static func pacing(room: Room) -> Dictionary:
	var g := room.gaps.duplicate()
	g.sort()
	var c := room.costs.duplicate()
	c.sort()
	var beat := NetSync.STEP * 1000.0 * NetPlay.SNAP_EVERY
	var bunched := 0
	for v in g:
		if v < beat * .5:
			bunched += 1
	return {
		"gap_med": _at(g, .5),
		"gap_p99": _at(g, .99),
		"gap_max": g[-1] if not g.is_empty() else 0.0,
		"bunched": bunched,
		"cost_med": _at(c, .5),
		"cost_p99": _at(c, .99),
		"cost_max": c[-1] if not c.is_empty() else 0.0,
	}


static func _at(sorted: PackedFloat32Array, q: float) -> float:
	if sorted.is_empty():
		return 0.0
	return sorted[mini(sorted.size() - 1, int(sorted.size() * q))]


## Closes every lobby, telling everyone why (the service is stopping).
func close_all(why := "THE SERVER IS RESTARTING") -> void:
	if relay != null:
		relay.close_all(why)
	for room in rooms:
		room.net.leave(why)
	for room in rooms:
		room.net.flush_leave()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if not rooms.is_empty() and rooms[0].net.session != null:
			close_all()


func _log(line: String) -> void:
	var t := Time.get_datetime_string_from_system(true, true)
	print("%s %s" % [t, line])
