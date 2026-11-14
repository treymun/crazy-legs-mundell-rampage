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
## each lobby's keys any of NetPlay.DEFAULTS. Prints a line for everyone who
## comes and goes, each match, and every STATUS_EVERY seconds how busy it is.
class_name LobbyServer
extends Node

## Seconds between status lines.
const STATUS_EVERY := 300.0
## Ticks played in one frame at most (a stall is not caught up past this).
const MOST_STEPS := 8
## Matches on at once at most (the config's "most_matches"): one 5v5 with
## nine bots is about 15-20% of a small VPS core (40% before NetSync's
## snapshots came from NetTrack).
const MOST_MATCHES := 3
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


var rooms: Array[Room] = []
var art: Assets
var sim := {}
var most_matches := MOST_MATCHES
var _status_in := 10.0
var _failed := ""


## `config` is the parsed config; `sim_options` every match is configured
## with (difficulty, gore...: the settings that change play).
func _init(config: Dictionary, sim_options := {}) -> void:
	sim = sim_options
	art = Assets.new()
	var bind := String(config.get("bind", "*"))
	most_matches = int(config.get("most_matches", MOST_MATCHES))
	for entry in config.get("lobbies", []):
		if not entry is Dictionary:
			continue
		var lobby := (entry as Dictionary).duplicate()
		var port := int(lobby.get("port", NetSession.PORT))
		lobby.erase("port")
		var net := NetPlay.serve_lobby(port, lobby, bind)
		if net == null:
			_failed = "PORT %d IS TAKEN" % port
			continue
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
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
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
			"VERSION %s, %d LOBBIES"
			% [ProjectSettings.get_setting("application/config/version", "?"), rooms.size()]
		)
	)


func _process(delta: float) -> void:
	frame(float(Time.get_ticks_msec()), delta)


## One frame: every lobby polled at `now` (ms), `delta` seconds of matches
## played (tools/net_server_check.gd drives it on its own clock).
func frame(now: float, delta: float) -> void:
	var busy := false
	for room in rooms:
		_poll(room, now)
		if room.net.phase == "match":
			busy = true
			_play(room, delta)
	Engine.max_fps = MATCH_FPS if busy else IDLE_FPS
	_status_in -= delta
	if _status_in <= 0.0:
		_status_in = STATUS_EVERY
		_status()


func _poll(room: Room, now: float) -> void:
	var net := room.net
	net.poll(now)
	for line: String in net.take_news():
		_log("%s: %s" % [net.settings["lobby_name"], line])
	for change: Dictionary in net.take_changes():
		if change.has("started"):
			room.pilots.clear()
			room.accum = 0.0
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
			_log("%s: BACK TO THE LOBBY" % net.settings["lobby_name"])
		elif change.has("bot"):
			room.pilots[int(change["bot"])] = TacticalBot.new(int(change["bot"]))
		elif change.has("human"):
			room.pilots.erase(int(change["human"]))


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
				own[slot] = room.pilots[slot].steer(g)
		g.focus(g.local_player)
		room.net.host_tick(own)
		for slot: int in room.pilots:
			g.focus(g.players[slot])
			room.pilots[slot].moved(g)
		g.focus(g.local_player)
		var spent := Time.get_ticks_usec() - t0
		room.ticks += 1
		room.tick_us += spent
		room.worst_us = maxi(room.worst_us, spent)


## A match's game, as every client makes its copy (main_flow.gd
## net_match_game), on a host game: no looks, no sound, nothing drawn.
func _make(info: Dictionary) -> Game:
	var level := String(info["level"])
	if not FileAccess.file_exists("res://data/%s.json" % level):
		return null
	var made := Game.new(art, null, QuietSound.new(), level, true)
	var opts := sim.duplicate()
	opts.merge(info.get("sim", {}), true)
	made.configure(opts)
	Modes.setup(made, String(info["mode"]), int(info["count"]), info["options"])
	return made


## The process's resident memory in MB (Linux; else Godot's own count, which
## a release build leaves at 0).
static func memory_mb() -> float:
	if FileAccess.file_exists("/proc/self/status"):
		for line in FileAccess.get_file_as_string("/proc/self/status").split("\n"):
			if line.begins_with("VmRSS:"):
				return float(line.get_slice(":", 1).strip_edges().get_slice(" ", 0)) / 1024.0
	return OS.get_static_memory_usage() / 1048576.0


func _status() -> void:
	var mem := memory_mb()
	var parts: PackedStringArray = []
	for room in rooms:
		var n := room.net
		var avg := room.tick_us / maxf(1.0, room.ticks) / 1000.0
		parts.append(
			(
				"%s %s %d in, %d matches, tick %.2f ms (worst %.1f)"
				% [n.port, n.phase, n.players.size(), room.matches, avg, room.worst_us / 1000.0]
			)
		)
		room.ticks = 0
		room.tick_us = 0
		room.worst_us = 0
	_log("STATUS %.0f MB; %s" % [mem, "; ".join(parts)])


## Closes every lobby, telling everyone why (the service is stopping).
func close_all(why := "THE SERVER IS RESTARTING") -> void:
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
