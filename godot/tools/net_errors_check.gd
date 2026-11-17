## What a player is told when joining goes wrong, and the way back in
## (src/net/net_play.gd, main_flow.gd net_closed), headless over 127.0.0.1:
##
##   godot --headless --path godot --script res://tools/net_errors_check.gd
##
## - another version: an older game's HELLO is refused with both versions
##   named; another protocol is refused too;
## - a full lobby: THE LOBBY IS FULL;
## - nobody at the address: COULD NOT REACH THE HOST after CONNECT_WAIT;
## - a host that takes the line and never answers the HELLO: THE HOST NEVER
##   ANSWERED after ANSWER_WAIT (it used to wait for ever on "hello");
## - the way back: a client that lost the host (the line went quiet) lands
##   on the JOIN form as it was, the note says why and ENTER TO TRY AGAIN,
##   and ENTER takes it back into the lobby; a refusal or a host who closed
##   the lobby goes to the title as before;
## - another system: the host says its own in the WELCOME; a copy is held to
##   a host on the same system bit for bit, to one on another (or an older
##   host that does not say) with floats a last bit apart let be
##   (NetSync.Client.NEAR: the VPS runs Linux, players Windows), while an
##   int, the dice or a real parting still count.
##
## Prints NET ERRORS OK.
extends SceneTree

const NetPorts := preload("res://tools/net_ports.gd")
const STEP_MS := 1000.0 / 60.0

var failures: Array = []
var main: Control
var now := 0.0
var nets: Array = []


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


func _run() -> void:
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var tally := CrashLog.tally()
	_refusals()
	_unreachable()
	_never_answered()
	_way_back()
	_systems()
	tally.stop()
	_check(
		tally.errors == 0,
		(
			"no script or engine errors"
			+ ("" if tally.errors == 0 else " (%d: %s)" % [tally.errors, tally.first_errors[0]])
		)
	)
	for net: NetPlay in nets:
		net.finish()
	if main.net != null:
		main.net.finish()
	print("")
	print("NET ERRORS OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _pump(frames: int, extra: Array = []) -> void:
	for i in frames:
		now += STEP_MS
		for net: NetPlay in nets:
			net.poll(now)
		for s: NetSession in extra:
			s.poll(now)
		OS.delay_msec(1)


func _wait(what: Callable, most := 600, extra: Array = []) -> bool:
	for i in most:
		if what.call():
			return true
		_pump(1, extra)
	return what.call()


func _host(max_players := 10) -> NetPlay:
	var port := NetPorts.pick("net_errors_check")
	var host := NetPlay.host_lobby(port, "Trey", {"max_players": max_players}, false, "127.0.0.1")
	if host != null:
		nets.append(host)
	return host


func _join(host: NetPlay, name: String) -> NetPlay:
	var net := NetPlay.join_lobby("127.0.0.1:%d" % host.port, name, "")
	if net != null:
		nets.append(net)
	return net


## A raw HELLO from an older game: what the WELCOME says.
func _old_hello(host: NetPlay, extra: Dictionary, version: String) -> String:
	var s := NetSession.join("127.0.0.1", host.port)
	if s == null:
		return "(no session)"
	var said := ""
	var sent := false
	for i in 400:
		_pump(1, [])
		for packet: Array in s.poll(now):
			var bytes: PackedByteArray = packet[1]
			if not bytes.is_empty() and bytes[0] == NetWire.WELCOME:
				said = str(NetWire.info_of(bytes).get("refused", "(let in)"))
		if said != "":
			break
		if not sent and s.connected():
			var info := {"protocol": NetWire.PROTOCOL, "version": version, "name": "OLD"}
			info.merge(extra, true)
			s.send(NetSession.HOST_ID, NetSession.CH_RELIABLE, NetWire.message(NetWire.HELLO, info))
			sent = true
	s.close()
	return said


func _refusals() -> void:
	print("REFUSALS")
	var host := _host(2)
	_check(host != null, "a host opens a lobby for two")
	if host == null:
		return
	var mine := str(ProjectSettings.get_setting("application/config/version", ""))
	var older := _old_hello(host, {}, "3.5.0")
	_check(
		older == "THE HOST RUNS %s, YOU RUN 3.5.0" % mine,
		"another version is told both: %s" % older
	)
	var protocol := _old_hello(host, {"protocol": NetWire.PROTOCOL - 1}, mine)
	_check(
		protocol.begins_with("THE HOST RUNS ANOTHER VERSION"),
		"another protocol is refused: %s" % protocol
	)
	var alice := _join(host, "Alice")
	_wait(func() -> bool: return alice.phase == "lobby")
	var bob := _join(host, "Bob")
	_wait(func() -> bool: return bob.phase == "closed")
	_check(
		alice.phase == "lobby" and bob.phase == "closed" and bob.reason == "THE LOBBY IS FULL",
		"one more than it holds: %s" % bob.reason
	)
	_check(not NetPlay.may_retry(bob.reason), "a refusal is not offered again")
	alice.leave()
	host.leave("THE HOST CLOSED THE LOBBY")
	_pump(30)


func _unreachable() -> void:
	print("NOBODY THERE")
	var port := NetPorts.pick("net_errors_check nobody")
	var net := NetPlay.join_lobby("127.0.0.1:%d" % port, "Alice", "")
	nets.append(net)
	var frames := int((NetPlay.CONNECT_WAIT + 1.0) * 1000.0 / STEP_MS)
	_wait(func() -> bool: return net.phase == "closed", frames)
	_check(
		net.phase == "closed" and net.reason == "COULD NOT REACH THE HOST",
		"an address nobody answers: %s after %.0f s" % [net.reason, NetPlay.CONNECT_WAIT]
	)
	_check(NetPlay.may_retry(net.reason), "that is offered again")


func _never_answered() -> void:
	print("A HOST THAT NEVER ANSWERS")
	var port := NetPorts.pick("net_errors_check silent")
	var silent := NetSession.host(port, NetSession.Transport.ENET, 3, "127.0.0.1")
	_check(silent != null, "a silent host listens")
	if silent == null:
		return
	var net := NetPlay.join_lobby("127.0.0.1:%d" % port, "Alice", "")
	nets.append(net)
	_wait(func() -> bool: return net.phase == "hello", 300, [silent])
	_check(net.phase == "hello", "the line is taken and HELLO said (%s)" % net.phase)
	var frames := int((NetPlay.ANSWER_WAIT + 1.0) * 1000.0 / STEP_MS)
	_wait(func() -> bool: return net.phase == "closed", frames, [silent])
	_check(
		net.phase == "closed" and net.reason == "THE HOST NEVER ANSWERED",
		"no WELCOME: %s (it used to wait for ever)" % net.reason
	)
	silent.close()


## The front end: lost, then ENTER on the JOIN form again.
func _way_back() -> void:
	print("THE WAY BACK")
	var host := _host()
	if host == null:
		_check(false, "a host for the way back")
		return
	main.net_form = {"name": "ALICE", "address": "127.0.0.1:%d" % host.port, "password": ""}
	main.net_join()
	var first: NetPlay = main.net
	_check(first != null, "ALICE joins from the JOIN form")
	if first == null:
		return
	nets.append(first)
	_wait(func() -> bool: return first.phase == "lobby")
	# The line goes quiet: what the client's poll says when ENet gives up.
	first._close("LOST THE HOST")
	nets.erase(first)
	main.net_closed()
	_check(
		main.state == "netjoin" and main.net == null,
		"lost: back on the JOIN form (%s), not the title" % main.state
	)
	_check(
		(
			str(main.net_note) == "LOST THE HOST. ENTER TO TRY AGAIN."
			and str(main.net_form.get("address", "")) == "127.0.0.1:%d" % host.port
		),
		"the note says why and how (%s), the address kept" % main.net_note
	)
	OnlineInput.key_online(main, KEY_ENTER)
	var again: NetPlay = main.net
	if again != null:
		nets.append(again)
	_wait(func() -> bool: return again != null and again.phase == "lobby")
	_check(again != null and again.phase == "lobby", "ENTER takes ALICE back into the lobby")
	_check(host.players.size() == 2, "the host has her once (%d in)" % host.players.size())
	# Closed by the host: the title, as ever.
	host.leave("THE HOST CLOSED THE LOBBY")
	_wait(func() -> bool: return again == null or again.phase == "closed")
	if again != null:
		main.net_closed()
	_check(
		main.state == "title" and str(main.menu_note) == "THE HOST CLOSED THE LOBBY.",
		"the host closing it goes to the title (%s: %s)" % [main.state, main.menu_note]
	)


func _systems() -> void:
	print("ANOTHER SYSTEM")
	var a := {"players": [{"vy": -0.8207086132592, "hp": 100}], "rng": 7, "wind": Vector2(.5, .2)}
	var b := a.duplicate(true)
	b["players"][0]["vy"] = -0.8207086132592 * (1.0 + 2e-16)
	b["wind"] = Vector2(.5, .2 + 3e-8)  # a last bit of a single-precision part
	var exact := GameSnapshot.first_difference(a, b)
	var near := GameSnapshot.first_difference(a, b, "", NetSync.Client.NEAR)
	_check(
		exact != "" and near == "",
		"floats a last bit apart: parted bit for bit (%s), the same when near" % exact
	)
	var c := b.duplicate(true)
	c["players"][0]["hp"] = 99
	var d := b.duplicate(true)
	d["players"][0]["vy"] = -0.83
	var e := b.duplicate(true)
	e["wind"] = Vector2(.5, .21)
	_check(
		(
			GameSnapshot.first_difference(a, c, "", NetSync.Client.NEAR) != ""
			and GameSnapshot.first_difference(a, d, "", NetSync.Client.NEAR) != ""
			and GameSnapshot.first_difference(a, e, "", NetSync.Client.NEAR) != ""
		),
		"an int or a float that really moved still parts them"
	)
	var host := _host()
	if host == null:
		return
	var alice := _join(host, "Alice")
	_wait(func() -> bool: return alice.phase == "lobby")
	_check(alice.host_os == OS.get_name(), "the host says its system (%s)" % alice.host_os)
	_check(NetPlay.near_for(alice.host_os) == 0.0, "the same system: the copy is held bit for bit")
	_check(
		(
			(
				NetPlay.near_for("Linux" if OS.get_name() != "Linux" else "Windows")
				== NetSync.Client.NEAR
			)
			and NetPlay.near_for("") == NetSync.Client.NEAR
		),
		"a host on another system, or one that does not say: floats a last bit apart are let be"
	)
	alice.leave()
	host.leave("DONE")
	_pump(30)
