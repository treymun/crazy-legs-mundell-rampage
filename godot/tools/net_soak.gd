## A soak of an always-open lobby server (src/net/lobby_server.gd), on the
## real clock: `people` probes join one lobby, the first (the admin) starts a
## match, each played by a TacticalBot steering from its own copy, and the
## match is put through what players do to a server:
##
## - a probe hangs for `stall` seconds (nothing polled: a machine loading,
##   a lag spike) and must come back without being dropped;
## - the last probe leaves mid-match and joins again (a late join into its
##   old team's bot slot);
## - the admin leaves (the lobby passes to the next in line) and joins again.
##
##   godot --headless --path godot --script res://tools/net_soak.gd
##       [-- server=<address:port>] [people=3] [seconds=180] [stall=4]
##       [mode=tagteam] [map=pumpngo] [grew=1]
##
## Without `server` it serves a lobby from this build on 127.0.0.1 (a port of
## its own) in the same process, as the VPS does. With one it first knocks
## (INFO, as COUNTY SERVERS does) and will not join a lobby with anyone in it,
## another version or a match on: a soak must not walk into people's game.
## Keep it gentle on a real server (four probes, minutes, not hours).
##
## Reported per probe: drops (closed without leaving: why), copies parted
## from the server (mismatches) and put back (rebuilds, lost inputs), the
## round trip (median, p95, worst), snapshots that came stale or without
## their base, bytes down and up a second; for the process: memory and
## objects at the start, middle and end. Prints NET SOAK OK, or what failed.
extends SceneTree

const NetPorts := preload("res://tools/net_ports.gd")
const STEP := NetSync.STEP

var failures: Array = []
var main: Control
var server: LobbyServer = null
var opts := {
	"server": "",
	"people": 3,
	"seconds": 180.0,
	"stall": 4.0,
	"mode": "tagteam",
	"map": "pumpngo",
	"grew": 0,
}
var target := {}
## name -> NetPlay (the live one), and each probe's tallies by name.
var probes := {}
var tallies := {}
var pilots := {}
var began := 0
var _last_frame := 0
var _sampled_at := 0


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var kv := arg.split("=", true, 1)
		if kv.size() == 2 and opts.has(kv[0]):
			var was: Variant = opts[kv[0]]
			if was is String:
				opts[kv[0]] = kv[1]
			elif was is int:
				opts[kv[0]] = int(kv[1])
			else:
				opts[kv[0]] = float(kv[1])
	opts["people"] = clampi(int(opts["people"]), 2, 4)
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var tally := CrashLog.tally()
	if _target():
		_soak()
	tally.stop()
	_check(
		tally.errors == 0,
		(
			"no script or engine errors"
			+ ("" if tally.errors == 0 else " (%d: %s)" % [tally.errors, tally.first_errors[0]])
		)
	)
	for net: NetPlay in probes.values():
		net.leave("SOAK DONE")
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 400:
		_frame(true)
	for net: NetPlay in probes.values():
		net.finish()
	if server != null:
		for room in server.rooms:
			room.net.finish()
		server.queue_free()
	print("")
	print("NET SOAK OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


## The server to soak: the one asked for (knocked first), or one of our own.
func _target() -> bool:
	if str(opts["server"]) == "":
		var port := NetPorts.pick("net_soak")
		var lobby := {
			"port": port,
			"lobby_name": "SOAK",
			"mode": str(opts["mode"]),
			"map": str(opts["map"]),
			"team_size": 2 if str(opts["mode"]) == "tagteam" else 5,
		}
		server = LobbyServer.new({"bind": "127.0.0.1", "lobbies": [lobby]}, {"difficulty": 1})
		if server.rooms.is_empty():
			_check(false, "a lobby server of this build opens on 127.0.0.1")
			return false
		root.add_child(server)
		server.set_process(false)
		target = {"host": "127.0.0.1", "port": port}
		print("SOAK: a lobby of this build on 127.0.0.1:%d (%s)" % [port, opts["mode"]])
		return true
	target = NetPlay.parse_address(str(opts["server"]))
	if target.is_empty():
		_check(false, "server= is an address:port")
		return false
	var browser := NetBrowser.new(
		[{"name": "SOAKED", "address": target["host"], "port": target["port"]}]
	)
	var t0 := Time.get_ticks_msec()
	var s: Dictionary = browser.servers[0]
	while Time.get_ticks_msec() - t0 < 6000 and s["state"] == "asking":
		browser.poll(float(Time.get_ticks_msec()))
		OS.delay_msec(10)
	browser.close()
	var info: Dictionary = s["info"]
	print("SOAK: the server answers %s in %.0f ms: %s" % [s["state"], s["ping"], info])
	if s["state"] != "up":
		_check(false, "the server answers an INFO knock")
		return false
	var mine := str(ProjectSettings.get_setting("application/config/version", ""))
	var busy := int(info.get("players", 0)) > 0 or str(info.get("phase", "")) != "lobby"
	if busy or str(info.get("version", "")) != mine:
		print(
			(
				"SOAK: not joining (players %s, %s, version %s, ours %s)"
				% [info.get("players"), info.get("phase"), info.get("version"), mine]
			)
		)
		return false
	return true


func _join(name: String) -> NetPlay:
	var net := NetPlay.join_lobby("%s:%d" % [target["host"], target["port"]], name, "")
	if net == null:
		return null
	net.make_match = func(info: Dictionary) -> Game: return main.net_match_game(info)
	probes[name] = net
	if not tallies.has(name):
		tallies[name] = {
			"drops": [],
			"mismatches": 0,
			"rebuilds": 0,
			"lost": 0,
			"stale": 0,
			"no_base": 0,
			"lag": PackedFloat32Array(),
			"down": 0,
			"up": 0,
			"logs": [],
		}
	return net


## One frame on the real clock (paced at the game's own rate): the server if
## it is ours, each probe's packets, controls and copy.
func _frame(quiet := false, skip := "") -> void:
	var now := Time.get_ticks_msec()
	var wait := int(STEP * 1000.0) - (now - _last_frame)
	if wait > 0:
		OS.delay_msec(wait)
	_last_frame = Time.get_ticks_msec()
	var t := float(_last_frame)
	if server != null:
		server.frame(t, STEP)
	for name: String in probes:
		if name == skip:
			continue
		var net: NetPlay = probes[name]
		net.poll(t)
		if net.phase == "closed":
			continue
		if quiet or net.phase != "match":
			continue
		var c := Game.Controls.new()
		if net.client_ready():
			var copy := net.match_game()
			var slot := net.my_slot()
			if slot >= 0 and slot < copy.players.size() and copy.players[slot].health > 0:
				var key := "%s/%d/%d" % [name, slot, copy.get_instance_id()]
				if not pilots.has(key):
					pilots[key] = TacticalBot.new(slot)
				var bot: TacticalBot = pilots[key]
				copy.focus(copy.players[slot])
				c = bot.steer(copy)
				copy.focus(copy.local_player)
		net.client_input(c)
		net.client_play(1)


func _run_for(seconds: float, skip := "") -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		_frame(false, skip)
		_note_drops()
		if Time.get_ticks_msec() - _sampled_at >= 30000:
			_sampled_at = Time.get_ticks_msec()
			_sweep()
			_memory("at %d s" % ((_sampled_at - began) / 1000))


func _wait(what: Callable, seconds: float) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		if what.call():
			return true
		_frame()
		_note_drops()
	return what.call()


## A probe closed that was not asked to leave: a drop, with why.
func _note_drops() -> void:
	for name: String in probes.keys():
		var net: NetPlay = probes[name]
		if net.phase == "closed" and not net.has_meta("leaving"):
			var t: Dictionary = tallies[name]
			var drops: Array = t["drops"]
			drops.append(net.reason)
			print("    %s DROPPED: %s" % [name, net.reason])
			_fold(name, net)
			probes.erase(name)


## A probe's sync tallies added to its name's (before it goes or at the end).
func _fold(name: String, net: NetPlay) -> void:
	var t: Dictionary = tallies[name]
	var cs := net.client_sync
	if cs != null:
		t["mismatches"] += cs.mismatches
		t["rebuilds"] += cs.rebuilds
		t["lost"] += cs.rebuilds_lost
		t["stale"] += cs.stale
		t["no_base"] += cs.no_base
		var lag: PackedFloat32Array = t["lag"]
		lag.append_array(cs.lag_samples)
		var logs: Array = t["logs"]
		logs.append_array(cs.mismatch_log)
	if net.session != null:
		t["down"] += net.session.received
		t["up"] += net.session.sent


## The front end lets a game go when what it shows changes (its GamePool,
## at the frame's end); here nothing it shows changes, so the copies of
## probes that left are let go as the front end would, and their pilots.
func _sweep() -> void:
	var kept: Array = []
	var ids := {}
	for net: NetPlay in probes.values():
		var g := net.match_game()
		if g != null:
			kept.append(g)
			ids[str(g.get_instance_id())] = true
	main.games.sweep(kept)
	for key: String in pilots.keys():
		if not ids.has(key.get_slice("/", 2)):
			pilots.erase(key)


var _sizes := {}


func _games() -> Dictionary:
	var out := {}
	for name: String in probes:
		var g: Game = probes[name].match_game()
		if g != null:
			out[name] = g
	if server != null:
		for room in server.rooms:
			var g2: Game = room.net.match_game()
			if g2 != null:
				out["server"] = g2
	return out


func _measure(prefix: String, obj: Object, out: Dictionary) -> void:
	for prop: Dictionary in obj.get_property_list():
		if int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var v: Variant = obj.get(prop["name"])
		if v is Array or v is Dictionary:
			out[prefix + "." + str(prop["name"])] = v.size()


## `grew`: every list and dictionary in each game (its features, its
## players) that grew since the last sample, the largest first.
func _diag() -> void:
	var now := {}
	var gs := _games()
	for name: String in gs:
		var g: Game = gs[name]
		_measure(name + ":game", g, now)
		for key: String in g.features:
			_measure(name + ":" + key, g.features[key], now)
		for p: Player in g.players:
			_measure(name + ":p%d" % p.slot, p, now)
	var growth: Array = []
	for k: String in now:
		var was: int = _sizes.get(k, now[k])
		if now[k] - was > 0:
			growth.append([now[k] - was, k, now[k]])
	growth.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	print("    grew: ", growth.slice(0, 12))
	_sizes = now


func _memory(when: String) -> void:
	if int(opts["grew"]) != 0:
		_diag()
	print(
		(
			"    memory %s: %.1f MB, %d objects, %d nodes"
			% [
				when,
				OS.get_static_memory_usage() / 1048576.0,
				Performance.get_monitor(Performance.OBJECT_COUNT),
				Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
			]
		)
	)


func _leave(name: String) -> void:
	var net: NetPlay = probes.get(name)
	if net == null:
		return
	net.set_meta("leaving", true)
	_fold(name, net)
	net.leave("SOAK LEAVES")
	probes.erase(name)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300:
		net.poll(float(Time.get_ticks_msec()))
		_frame()
	net.finish()


func _soak() -> void:
	var people := int(opts["people"])
	var seconds := float(opts["seconds"])
	var names: Array = []
	for i in people:
		names.append("PROBE%d" % (i + 1))
	began = Time.get_ticks_msec()
	_last_frame = began
	for name: String in names:
		var net := _join(name)
		_check(net != null, "%s starts to join" % name)
		if net == null:
			return
		_wait(func() -> bool: return net.phase == "lobby" or net.phase == "closed", 10.0)
		_check(net.phase == "lobby", "%s is in the lobby (%s)" % [name, net.reason])
		if net.phase != "lobby":
			return
	var admin: NetPlay = probes[names[0]]
	_check(admin.is_admin(), "%s, first in, runs the lobby" % names[0])
	for name: String in names.slice(1):
		probes[name].ask({"ready": true})
	_wait(
		func() -> bool:
			return admin.players.all(
				func(p: Dictionary) -> bool:
					return bool(p.get("ready", false)) or p["id"] == admin.my_id
			),
		5.0
	)
	var why := admin.start_match()
	var started := _wait(
		func() -> bool:
			return probes.values().all(func(n: NetPlay) -> bool: return n.client_ready()),
		15.0
	)
	_check(why == "" and started, "the admin starts a match, every probe has it (%s)" % why)
	if not started:
		return
	_memory("at the start")
	var slice := seconds / 4.0
	_run_for(slice)
	# A hang: the second probe polls nothing for a while, then plays on.
	var hung := str(names[1])
	print("    %s hangs %.1f s" % [hung, float(opts["stall"])])
	_run_for(float(opts["stall"]), hung)
	var back := _wait(
		func() -> bool:
			var n: NetPlay = probes.get(hung)
			return n != null and n.client_ready() and n.client_sync.backlog() < 20,
		10.0
	)
	_check(back, "%s comes back after a %.0f s hang without a drop" % [hung, opts["stall"]])
	_run_for(slice)
	_sweep()
	_memory("in the middle")
	# The last probe leaves mid-match and joins again.
	var last := str(names[-1])
	_leave(last)
	_run_for(3.0)
	var again := _join(last)
	var rejoined := _wait(func() -> bool: return again != null and again.client_ready(), 15.0)
	_check(
		rejoined, "%s leaves mid-match and joins again (%s)" % [last, again.reason if again else ""]
	)
	_run_for(slice)
	# The admin leaves: the lobby passes on; then they join again.
	var first := str(names[0])
	_leave(first)
	var heir: NetPlay = probes[names[1]] if probes.has(names[1]) else null
	var passed := _wait(func() -> bool: return heir != null and heir.is_admin(), 8.0)
	_check(passed, "the admin leaves: %s runs the lobby now" % names[1])
	var returned := _join(first)
	var in_again := _wait(func() -> bool: return returned != null and returned.client_ready(), 15.0)
	_check(in_again, "%s joins the match again" % first)
	_run_for(slice)
	_sweep()
	_memory("at the end")
	var total := (Time.get_ticks_msec() - began) / 1000.0
	print("  over %.0f s:" % total)
	for name: String in probes.keys():
		_fold(name, probes[name])
	for name: String in tallies:
		var t: Dictionary = tallies[name]
		var lag: PackedFloat32Array = t["lag"]
		lag.sort()
		var at := func(q: float) -> float:
			return lag[int((lag.size() - 1) * q)] if lag.size() else 0.0
		print(
			(
				(
					"    %s: drops %s; parted %d, put back %d (lost inputs %d); stale %d,"
					+ " no base %d; round trip %.0f / %.0f / %.0f ms; down %.1f up %.1f KB/s"
				)
				% [
					name,
					t["drops"],
					t["mismatches"],
					t["rebuilds"],
					t["lost"],
					t["stale"],
					t["no_base"],
					at.call(.5),
					at.call(.95),
					at.call(1.0),
					t["down"] / 1024.0 / total,
					t["up"] / 1024.0 / total,
				]
			)
		)
		var logs: Array = t["logs"]
		if not logs.is_empty():
			print("      parted at: %s" % "; ".join(logs.slice(0, 4)))
		var drops: Array = t["drops"]
		_check(drops.is_empty(), "%s was never dropped" % name)
		# A late join puts a copy back once; a hang a few times more.
		_check(
			t["mismatches"] <= 3,
			"%s's copy kept with the server (%d parted)" % [name, t["mismatches"]]
		)
