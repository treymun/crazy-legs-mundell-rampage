## Voice chat online (src/net/net_voice.gd, voice_chat.gd, voice_codec.gd),
## headless, no mic and no sound card: a made-up voice (tones sliding,
## noise, a syllable's swell) goes in where the mic's sound would, through
## the gate, the codec and the real transport with latency, jitter and loss.
##
##   godot --headless --path godot --script res://tools/voice_chat_check.gd
##       [-- bench] [seconds=N]
##
## 1. The codec: a voice through it comes back near enough (SNR), at 8 kHz
##    from 44.1 and 48 kHz, 4 KB a second at most while talking.
## 2. The gate: PUSH TO TALK sends only while held (and a few frames after),
##    OPEN MIC only over MIC SENSITIVITY's level; the jitter buffer plays
##    frames in order, covers a lost one, drops a late one, catches up.
## 3. A lobby server (ENet and its WebSocket side, the party line on) with
##    four people, 40 ms each way, jitter and 5% loss: in the lobby everyone
##    hears ALICE, flat, every frame that came the bytes she sent; in a match
##    only those within NetVoice.RADIUS, placed; a muted talker and a player
##    with VOICE CHAT off are sent nothing; the dead hear the living and only
##    the dead hear the dead; the copies part no more and get their snapshots
##    as often with everyone talking as with nobody.
## 4. Where a voice is heard from: left and right by where the talker
##    stands, fainter and duller through a wall.
## 5. A player's own lobby through the party line: the host hears its
##    players and they hear the host and each other (one over WebSocket).
##
## `bench`: a full 5v5 of ten people on the server, everyone talking, the
## server's time and bytes with voices and without (prints, checks nothing).
## `bench server=<address:port> [talkers=6] [seconds=60] [quiet]`: that
## many people join a lobby server running elsewhere, say ready and talk the
## whole time on the real clock (`quiet`: never), while tools/net_pace.gd
## starts the match and times the snapshots (docs/dev/multiplayer.md "Voice
## chat").
## Fails on any script or engine error. Prints VOICE CHAT OK.
extends SceneTree

const NetPorts := preload("res://tools/net_ports.gd")
const STEP := NetSync.STEP
const LAG := 40.0
const JITTER := 10.0
const LOSS := .05

var failures: Array = []
var server: LobbyServer
var main: Control
var now := 0.0
var nets: Array = []
var ws_port := 0
var lobby_port := 0
## net -> VoiceChat feeding its made-up voice; who talks this frame.
var mouths := {}
var talking := {}
## Pulled off each listener's talkers: net -> {id: samples}
var heard := {}
var bench := false
var seconds := 6.0
var remote := ""
var talkers := 6
var quiet := false


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "bench":
			bench = true
		elif arg.begins_with("seconds="):
			seconds = float(arg.substr(8))
		elif arg.begins_with("server="):
			remote = arg.substr(7)
		elif arg.begins_with("talkers="):
			talkers = int(arg.substr(8))
		elif arg == "quiet":
			quiet = true
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var tally := CrashLog.tally()
	if bench and remote != "":
		_bench_remote()
	elif bench:
		_bench()
	else:
		_codec()
		_gate_and_buffer()
		_placement()
		if _serve(2):
			_lobby_server()
			_party_line()
	tally.stop()
	_check(
		tally.errors == 0,
		(
			"no script or engine errors"
			+ ("" if tally.errors == 0 else " (%d: %s)" % [tally.errors, tally.first_errors[0]])
		)
	)
	_close_all()
	main.queue_free()
	print("")
	if bench:
		print("VOICE CHAT BENCH DONE")
	else:
		print("VOICE CHAT OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)
		if OS.get_environment("GITHUB_ACTIONS") != "":
			print("::error title=%s::%s" % [get_script().resource_path.get_file(), text])


func _close_all() -> void:
	for mouth: VoiceChat in mouths.values():
		mouth.free()
	mouths.clear()
	for net: NetPlay in nets:
		if net.session != null:
			net.session.close()
	nets.clear()
	if server != null:
		for room in server.rooms:
			room.net.finish()
		if server.relay != null:
			# A tapped session and the line hold each other: let go.
			for tapped: NetSession in server.relay.get("_sessions"):
				tapped.tap = null
		server.free()
		server = null
	RelayLink.server = {}


# ------------------------------------------------------------------ a voice


## `n` samples of a made-up voice at `rate`, starting at sample `from`: a
## tone sliding about its own pitch, its overtones, a little breath, swelling
## like syllables four times a second.
static func voice(n: int, rate: float, from: int, pitch: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var dice := RandomNumberGenerator.new()
	dice.seed = from
	for i in n:
		var t := (from + i) / rate
		var f := pitch * (1.0 + .25 * sin(TAU * .7 * t))
		var phase := TAU * f * t
		var syllable := .35 + .65 * maxf(0.0, sin(TAU * 4.0 * t))
		var s := sin(phase) * .5 + sin(phase * 2.0) * .25 + sin(phase * 3.0) * .12
		out[i] = (s + dice.randf_range(-.04, .04)) * syllable * .45
	return out


static func snr(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var sig := 0.0
	var err := 0.0
	for i in mini(a.size(), b.size()):
		sig += a[i] * a[i]
		err += (a[i] - b[i]) * (a[i] - b[i])
	return 10.0 * log(sig / maxf(err, 1e-12)) / log(10.0)


# ------------------------------------------------------------------ 1. codec


func _codec() -> void:
	print("THE CODEC")
	for rate: float in [44100.0, 48000.0]:
		var down := VoiceCodec.Down.new()
		var low := PackedFloat32Array()
		var chunk := int(rate * STEP)
		var at := 0
		while at < int(rate * 2.0):
			low.append_array(down.take(voice(chunk, rate, at, 180.0), rate))
			at += chunk
		var expect := int(at * VoiceCodec.RATE / rate)
		_check(
			absi(low.size() - expect) <= 2,
			"%d Hz comes down to 8 kHz (%d samples for %d)" % [rate, low.size(), expect]
		)
		var coder := VoiceCodec.Coder.new()
		var sent := PackedFloat32Array()
		var back := PackedFloat32Array()
		var began := Time.get_ticks_usec()
		var frames := 0
		for f in range(0, low.size() - VoiceCodec.FRAME, VoiceCodec.FRAME):
			var pcm := low.slice(f, f + VoiceCodec.FRAME)
			var bytes := coder.encode(pcm)
			frames += 1
			sent.append_array(pcm)
			back.append_array(VoiceCodec.decode(bytes))
		var us := (Time.get_ticks_usec() - began) / maxf(1.0, frames)
		var quality := snr(sent, back)
		_check(
			quality >= 15.0,
			(
				"a voice through the codec at %d Hz: %.1f dB SNR (%.0f us a frame both ways)"
				% [rate, quality, us]
			)
		)
	var per_second := (NetVoice.UP_HEADER + VoiceCodec.BYTES) * 1000.0 / 40.0
	_check(
		per_second <= 4300.0,
		(
			"a talker sends %.0f bytes a second up (%d a frame, 25 frames); %.0f down a voice"
			% [
				per_second,
				NetVoice.UP_HEADER + VoiceCodec.BYTES,
				(NetVoice.DOWN_HEADER + VoiceCodec.BYTES) * 25.0
			]
		)
	)
	_check(
		VoiceCodec.decode(PackedByteArray([1, 2, 3])).is_empty(),
		"a broken frame decodes to nothing"
	)


# ------------------------------------------------------------------ 2. gate


func _gate_and_buffer() -> void:
	print("THE GATE AND THE JITTER BUFFER")
	var gate := VoiceChat.Gate.new()
	var sent := 0
	for i in 10:
		sent += 1 if gate.step(-20.0, false, false, 50) else 0
	_check(sent == 0, "PUSH TO TALK: nothing goes out unheld, however loud")
	sent = 0
	for i in 10:
		sent += 1 if gate.step(-90.0, true, false, 50) else 0
	var tail := 0
	for i in 10:
		tail += 1 if gate.step(-20.0, false, false, 50) else 0
	_check(
		sent == 10 and tail == VoiceChat.RELEASE,
		(
			"held: every frame goes, then %d after it is let go (%d, %d)"
			% [VoiceChat.RELEASE, sent, tail]
		)
	)
	gate = VoiceChat.Gate.new()
	var quiet := 0
	for i in 10:
		quiet += 1 if gate.step(VoiceChat.Gate.threshold(50) - 3.0, false, true, 50) else 0
	var loud := 0
	for i in 5:
		loud += 1 if gate.step(VoiceChat.Gate.threshold(50) + 3.0, false, true, 50) else 0
	var after := 0
	for i in 20:
		after += 1 if gate.step(-90.0, false, true, 50) else 0
	_check(
		quiet == 0 and loud == 5 and after == VoiceChat.HANGOVER,
		"OPEN MIC: under the gate nothing, over it everything, %d frames after" % VoiceChat.HANGOVER
	)
	_check(
		VoiceChat.Gate.threshold(100) < VoiceChat.Gate.threshold(0),
		(
			"a higher MIC SENSITIVITY lets softer voices through (%.0f dB to %.0f dB)"
			% [VoiceChat.Gate.threshold(0), VoiceChat.Gate.threshold(100)]
		)
	)
	# The buffer, on a clock of our own.
	var coder := VoiceCodec.Coder.new()
	var frames: Array[PackedByteArray] = []
	var down := VoiceCodec.Down.new()
	var low := down.take(voice(44100, 44100.0, 0, 200.0), 44100.0)
	for f in 20:
		frames.append(coder.encode(low.slice(f * VoiceCodec.FRAME, (f + 1) * VoiceCodec.FRAME)))
	var t := NetVoice.Talker.new()
	var at := 0.0
	t.push(65534, frames[0], 0, at)
	_check(t.pull(160, at).is_empty(), "one frame in: it waits for the next before it plays")
	t.push(65535, frames[1], 0, at + 5.0)
	# 0 comes after the wrap; 1 is lost; 3 comes before 2.
	t.push(0, frames[2], 0, at + 10.0)
	t.push(3, frames[5], 0, at + 15.0)
	t.push(2, frames[4], 0, at + 20.0)
	var out := t.pull(VoiceCodec.FRAME * 5, at + 25.0)
	_check(
		out.size() == VoiceCodec.FRAME * 5 and t.lost == 1,
		(
			"in order across the wrap, out of order put right, the lost frame covered (%d, lost %d)"
			% [out.size(), t.lost]
		)
	)
	var first := VoiceCodec.decode(frames[0])
	_check(
		snr(first, out.slice(0, VoiceCodec.FRAME)) > 90.0,
		"and the frames played are the frames sent"
	)
	t.push(1, frames[3], 0, at + 30.0)
	_check(t.late == 1, "a frame after its turn is dropped")
	for f in 12:
		t.push(4 + f, frames[6 + f], 0, at + 40.0)
	_check(
		t.frames.size() <= NetVoice.MOST_FRAMES and t.skipped > 0,
		"a pile after a stall: the oldest go, %d held at most" % NetVoice.MOST_FRAMES
	)


# ------------------------------------------------------------------ 4. placement


func _placement() -> void:
	print("WHERE A VOICE IS HEARD FROM")
	var g: Game = main.make_game("grainyard")
	if g == null:
		_check(false, "a game to hear in")
		return
	var me := g.local_player
	# Find an open spot with open floor four cells either side, and a spot
	# behind a wall close by.
	var spot := Vector2(-1, -1)
	var walled := Vector2(-1, -1)
	for y in range(6, g.level.height - 6):
		for x in range(6, g.level.width - 6):
			var c := Vector2(x + .5, y + .5)
			if (
				not _open(g, c)
				or not _open(g, c + Vector2(0, 4))
				or not _open(g, c - Vector2(0, 4))
			):
				continue
			if not g.world.visible(c.x, c.y, c.x, c.y + 4.0, .95, .95):
				continue
			if not g.world.visible(c.x, c.y, c.x, c.y - 4.0, .95, .95):
				continue
			spot = c
			break
		if spot.x >= 0.0:
			break
	_check(spot.x >= 0.0, "an open spot on Grain Co-op to stand in")
	if spot.x < 0.0:
		g.dispose()
		return
	me.x = spot.x
	me.y = spot.y
	me.angle = 0.0
	var other := Player.new(spot.x, spot.y + 4.0, 0.0)
	var right := VoiceChat.placement(g, other, false, .7)
	other.y = spot.y - 4.0
	g.clock += 1.0
	var left := VoiceChat.placement(g, other, false, .7)
	_check(
		right.y > right.x * 1.5 and left.x > left.y * 1.5,
		(
			(
				"facing east, a talker to the south is on the right (L %.2f R %.2f),"
				+ " to the north on the left (L %.2f R %.2f)"
			)
			% [right.x, right.y, left.x, left.y]
		)
	)
	other.y = spot.y + NetVoice.RADIUS + 1.0
	g.clock += 1.0
	var far := VoiceChat.placement(g, other, false, .7)
	_check(far.x + far.y < .001, "past the radius: nothing")
	other.x = spot.x + 1.0
	other.y = spot.y
	g.clock += 1.0
	var close := VoiceChat.placement(g, other, false, .7)
	var flat := VoiceChat.placement(g, other, true, .7)
	_check(
		absf(close.x - close.y) < .05 and close.x > .9 and flat.x == 1.0 and flat.y == 1.0,
		"in front, close: both sides whole; flat (the lobby, the dead): both whole"
	)
	# Behind a wall: quieter and duller than the same distance in the open.
	var open_at := Vector2(-1, -1)
	for y in range(6, g.level.height - 6):
		for x in range(6, g.level.width - 6):
			var c := Vector2(x + .5, y + .5)
			var d := c + Vector2(5, 0)
			if not _open(g, c) or not _open(g, d):
				continue
			var seen := g.world.visible(c.x, c.y, d.x, d.y, .95, .95)
			if not seen and walled.x < 0.0:
				walled = c
			elif seen and open_at.x < 0.0:
				open_at = c
		if walled.x >= 0.0 and open_at.x >= 0.0:
			break
	if walled.x >= 0.0 and open_at.x >= 0.0:
		var heard_at := func(at: Vector2) -> Vector3:
			me.x = at.x
			me.y = at.y
			other.x = at.x + 5.0
			other.y = at.y
			g.clock += 1.0
			return VoiceChat.placement(g, other, false, .7)
		var through: Vector3 = heard_at.call(walled)
		var open: Vector3 = heard_at.call(open_at)
		_check(
			through.x + through.y < (open.x + open.y) * .8 and through.z < 6000.0,
			(
				"through a wall: quieter (%.2f against %.2f in the open) and muffled (%.0f Hz)"
				% [through.x + through.y, open.x + open.y, through.z]
			)
		)
	g.dispose()


func _open(g: Game, at: Vector2) -> bool:
	return not g.world.blocked(at.x, at.y, .3)


# ------------------------------------------------------------------ the server


func _serve(team_size: int) -> bool:
	var port := NetPorts.pick("voice_chat_check", [0], [3000])
	for k in 20:
		var config := {
			"bind": "127.0.0.1",
			"relay": {},
			"test_link": {"lag_ms": LAG, "jitter_ms": JITTER, "loss": LOSS},
			"lobbies":
			[
				{
					"port": port + k,
					"ws_port": port + k + 3000,
					"lobby_name": "VOICE LOBBY",
					"mode": "bomb",
					"map": "grainyard",
					"team_size": team_size,
					"bots": false,
					"rounds": 9,
					"round_seconds": 180.0,
					"freeze_seconds": 3.0,
				}
			]
		}
		server = LobbyServer.new(config, {"difficulty": 1})
		if not server.rooms.is_empty() and server.rooms[0].net.session.also != null:
			lobby_port = port + k
			ws_port = port + k + 3000
			break
		server.free()
		server = null
	_check(server != null, "a lobby server with voices on its ports")
	if server == null:
		return false
	root.add_child(server)
	server.set_process(false)
	RelayLink.server = {"host": "127.0.0.1", "port": lobby_port}
	return true


func _join(name: String, over_ws := false) -> NetPlay:
	var where := "127.0.0.1:%d" % lobby_port
	if over_ws:
		where = "ws://127.0.0.1:%d" % ws_port
	var net := NetPlay.join_lobby(where, name, "")
	net.make_match = func(info: Dictionary) -> Game: return main.net_match_game(info)
	if not over_ws:
		net.session.lag_ms = LAG
		net.session.jitter_ms = JITTER
		net.session.loss = LOSS
	nets.append(net)
	return net


## One frame: the server, every player (each talker's voice fed in, every
## voice heard taken off as a sound card would).
func _frame() -> void:
	now += STEP * 1000.0
	if server != null:
		server.frame(now, STEP)
	for net: NetPlay in nets:
		net.poll(now)
		if net.phase == "match" and net.role == NetPlay.Role.HOST:
			net.host_tick({})
		elif net.phase == "match":
			net.client_input(Game.Controls.new())
			net.client_play(1)
		var mouth: VoiceChat = mouths.get(net)
		if mouth != null and net.phase in ["lobby", "match"]:
			var rate := 44100.0
			var n := int(rate * STEP)
			var said: int = mouth.get_meta(&"said", 0)
			var held: bool = talking.get(net, false)
			mouth.feed(
				net, voice(n, rate, said, 140.0 + 30.0 * nets.find(net)), rate, held, false, 50, now
			)
			mouth.set_meta(&"said", said + n)
		var got: Dictionary = heard.get(net, {})
		for id: int in net.voice.talkers.keys():
			var t: NetVoice.Talker = net.voice.talkers[id]
			var pcm := t.pull(int(VoiceCodec.RATE * STEP) + 1, now)
			got[id] = int(got.get(id, 0)) + pcm.size()
		heard[net] = got
	OS.delay_msec(1)


func _wait(what: Callable, most := 600) -> bool:
	for i in most:
		if what.call():
			return true
		_frame()
	return what.call()


func _run_for(secs: float) -> void:
	for i in int(secs / STEP):
		_frame()


func _mouth(net: NetPlay) -> VoiceChat:
	var mouth := VoiceChat.new()
	mouths[net] = mouth
	return mouth


## Frames each listener got from `talker` while `secs` pass with only it talking.
func _talk(talker: NetPlay, secs: float) -> Dictionary:
	var before := {}
	for net: NetPlay in nets:
		before[net] = _got(net, talker.my_id)
	talking.clear()
	talking[talker] = true
	_run_for(secs)
	talking.clear()
	_run_for(.5)
	var out := {}
	for net: NetPlay in nets:
		out[net] = _got(net, talker.my_id) - int(before[net])
	return out


func _got(net: NetPlay, id: int) -> int:
	var t: NetVoice.Talker = net.voice.talkers.get(id)
	return t.got if t != null else 0


func _lobby_server() -> void:
	print("A LOBBY SERVER: 40 MS, JITTER, 5% LOSS")
	var lobby: NetPlay = server.rooms[0].net
	var alice := _join("alice")
	_wait(func() -> bool: return alice.phase == "lobby" and alice.is_admin())
	var bob := _join("bob")
	var carl := _join("carl")
	var dave := _join("dave", true)
	_wait(func() -> bool: return lobby.players.size() == 4 and dave.phase == "lobby")
	_check(lobby.players.size() == 4, "four people in the lobby (DAVE over the WebSocket)")
	for net: NetPlay in nets:
		_mouth(net)
	var said := _talk(alice, 2.0)
	var sent := alice.voice.frames_up
	_check(
		sent >= 48 and sent <= 60,
		"ALICE holds the talk key 2 s: %d frames go up (25 a second, and the release)" % sent
	)
	var everyone := true
	for net: NetPlay in [bob, carl, dave]:
		var got: int = said[net]
		var t: NetVoice.Talker = net.voice.talkers.get(alice.my_id)
		if got < sent * .8 or t == null or not t.flat:
			everyone = false
		print(
			(
				"    %s got %d of %d (%s)"
				% [net._my_name, got, sent, "flat" if t != null and t.flat else "-"]
			)
		)
	_check(everyone, "in the lobby everyone hears her, flat (loss takes a few)")
	_check(not alice.voice.talkers.has(alice.my_id), "and she is never sent her own voice")
	var bob_t: NetVoice.Talker = bob.voice.talkers.get(alice.my_id)
	var dave_t: NetVoice.Talker = dave.voice.talkers.get(alice.my_id)
	# Every frame the server took from ALICE went to all three (so a third of
	# what it passed on); the WebSocket loses none of them on the way down.
	var reached := lobby.voice.forwarded / 3
	_check(
		bob_t != null and bob_t.lost > 0 and dave_t != null and dave_t.got == reached,
		(
			"BOB's lost frames were covered (%d); DAVE's WebSocket got all the server sent (%d of %d)"
			% [bob_t.lost if bob_t else -1, dave_t.got if dave_t else -1, reached]
		)
	)
	var pulled: int = heard[dave].get(alice.my_id, 0)
	var played := (dave_t.got - dave_t.skipped) if dave_t != null else sent
	_check(
		pulled >= (played - 1) * VoiceCodec.FRAME,
		"and DAVE's sound card took the whole of it (%d samples for %d frames)" % [pulled, played]
	)
	# Teams and the match.
	alice.ask({"team": 0})
	bob.ask({"team": 0, "ready": true})
	carl.ask({"team": 1, "ready": true})
	dave.ask({"team": 1, "ready": true})
	_wait(func() -> bool: return alice.why_not_start() == "", 300)
	var why := alice.start_match()
	_check(why == "", "ALICE starts the match %s" % why)
	_wait(func() -> bool: return nets.all(func(n: NetPlay) -> bool: return n.client_ready()), 900)
	var g := lobby.match_game()
	_wait(func() -> bool: return g != null and String(Modes.feature(g).phase) == "live", 900)
	_run_for(1.5)
	var slot := func(n: NetPlay) -> Player: return g.players[int(lobby.player_of(n.my_id)["slot"])]
	var pa: Player = slot.call(alice)
	var pb: Player = slot.call(bob)
	var pc: Player = slot.call(carl)
	var pd: Player = slot.call(dave)
	var ab := Vector2(pa.x - pb.x, pa.y - pb.y).length()
	var ac := Vector2(pa.x - pc.x, pa.y - pc.y).length()
	var cd := Vector2(pc.x - pd.x, pc.y - pd.y).length()
	_check(
		ab < NetVoice.RADIUS and cd < NetVoice.RADIUS and ac > NetVoice.RADIUS,
		(
			"the teams stand apart: ALICE-BOB %.1f, CARL-DAVE %.1f, ALICE-CARL %.1f cells"
			% [ab, cd, ac]
		)
	)
	# Nobody talking, then everyone: the game's own packets the same.
	var quiet := _window(3.0, false)
	var loud := _window(3.0, true)
	var steady := true
	for net: NetPlay in nets:
		var q: Array = quiet[net]
		var l: Array = loud[net]
		print(
			(
				"    %s snapshots %d -> %d, partings %d -> %d, put back %d -> %d"
				% [net._my_name, q[0], l[0], q[1], l[1], q[2], l[2]]
			)
		)
		# (A starved process, check_all's sixty at once, puts a copy back
		# for late inputs now and then whoever talks: a little slack there.)
		if int(l[0]) < int(q[0]) * .85 or int(l[1]) > int(q[1]) or int(l[2]) > int(q[2]) + 2:
			steady = false
	_check(steady, "with all four talking the copies get their snapshots as often and part no more")
	var said_a := _talk(alice, 1.5)
	var b_place: NetVoice.Talker = bob.voice.talkers.get(alice.my_id)
	_check(
		int(said_a[bob]) > 25 and int(said_a[carl]) == 0 and int(said_a[dave]) == 0,
		(
			"in the match ALICE reaches BOB beside her (%d), not CARL or DAVE across the map (%d, %d)"
			% [said_a[bob], said_a[carl], said_a[dave]]
		)
	)
	_check(b_place != null and not b_place.flat, "and BOB hears her placed, not flat")
	var said_c := _talk(carl, 1.5)
	_check(
		int(said_c[dave]) > 25 and int(said_c[alice]) == 0 and int(said_c[bob]) == 0,
		(
			"CARL reaches DAVE (%d), not the other team (%d, %d)"
			% [said_c[dave], said_c[alice], said_c[bob]]
		)
	)
	# Muted, and VOICE CHAT off: sent nothing.
	bob.voice.toggle_mute(bob, alice.my_id)
	dave.voice.hearing = false
	dave.voice.tell(dave)
	_run_for(.6)
	var forwarded := lobby.voice.forwarded
	var muted := _talk(alice, 1.0)
	var deaf := _talk(carl, 1.0)
	_check(
		int(muted[bob]) == 0 and not bob.voice.talkers.has(alice.my_id),
		"BOB muted ALICE: the server sends him none of her"
	)
	_check(int(deaf[dave]) == 0, "DAVE turned VOICE CHAT off: the server sends him nothing")
	_check(
		lobby.voice.forwarded == forwarded,
		"so nothing went out at all (%d)" % (lobby.voice.forwarded - forwarded)
	)
	bob.voice.toggle_mute(bob, alice.my_id)
	dave.voice.hearing = true
	dave.voice.tell(dave)
	_run_for(.6)
	# PUSH TO TALK let go: nothing.
	var up := alice.voice.frames_up
	_run_for(1.0)
	_check(alice.voice.frames_up == up, "the talk key let go: ALICE sends nothing however loud")
	# The dead (a round mode): BOB and DAVE fall.
	pb.health = 0
	pd.health = 0
	var dead_d := _talk(dave, 1.5)
	_check(
		int(dead_d[bob]) > 25 and int(dead_d[carl]) == 0 and int(dead_d[alice]) == 0,
		(
			"dead DAVE reaches only dead BOB across the map (%d), not CARL or ALICE (%d, %d)"
			% [dead_d[bob], dead_d[carl], dead_d[alice]]
		)
	)
	var b_dead: NetVoice.Talker = bob.voice.talkers.get(dave.my_id)
	_check(b_dead != null and b_dead.flat, "and flat: the dead have no place to be heard from")
	var live_a := _talk(alice, 1.5)
	var live_c := _talk(carl, 1.5)
	_check(
		(
			int(live_a[bob]) > 25
			and int(live_a[dave]) == 0
			and int(live_c[dave]) > 25
			and int(live_c[bob]) == 0
		),
		(
			(
				"the dead hear the living near the teammates they watch:"
				+ " ALICE to BOB %d, not DAVE %d; CARL to DAVE %d, not BOB %d"
			)
			% [live_a[bob], live_a[dave], live_c[dave], live_c[bob]]
		)
	)
	var watched: NetVoice.Talker = bob.voice.talkers.get(alice.my_id)
	_check(watched != null and not watched.flat, "placed, as the game's sounds are while watching")
	# The cost.
	var route := lobby.voice.route_us / maxf(1.0, lobby.voice.forwarded)
	print(
		(
			"    the server passed %d frames on (%d KB), %.1f us of routing each; refused %d"
			% [
				lobby.voice.forwarded,
				lobby.voice.forwarded_bytes / 1024,
				route,
				lobby.voice.refused
			]
		)
	)
	_check(route < 400.0, "routing a frame costs the server little (%.1f us)" % route)
	for net: NetPlay in nets.duplicate():
		net.leave()
	_run_for(.5)
	for mouth: VoiceChat in mouths.values():
		mouth.free()
	mouths.clear()
	for net: NetPlay in nets:
		net.finish()
	nets.clear()
	heard.clear()


## `secs` with everyone talking or nobody: per player [snapshots got,
## partings, put back for lost inputs].
func _window(secs: float, all_talk: bool) -> Dictionary:
	var before := {}
	for net: NetPlay in nets:
		var cs := net.client_sync
		before[net] = [cs.latest, cs.mismatches, cs.rebuilds_lost]
	talking.clear()
	if all_talk:
		for net: NetPlay in nets:
			talking[net] = true
	_run_for(secs)
	talking.clear()
	var out := {}
	for net: NetPlay in nets:
		var cs := net.client_sync
		var b: Array = before[net]
		out[net] = [cs.latest - int(b[0]), cs.mismatches - int(b[1]), cs.rebuilds_lost - int(b[2])]
	return out


# ------------------------------------------------------------------ 5. party line


func _party_line() -> void:
	print("A PLAYER'S OWN LOBBY THROUGH THE PARTY LINE")
	var host: NetPlay = null
	for k in 20:
		host = NetPlay.host_lobby(
			NetPorts.pick("voice_chat_check host %d" % k), "hoss", {}, false, "127.0.0.1", true
		)
		if host != null:
			break
	_check(host != null, "a lobby hosted with the party line")
	if host == null:
		return
	host.make_match = func(info: Dictionary) -> Game: return main.net_match_game(info)
	nets.append(host)
	var link := host.party_line()
	_wait(func() -> bool: return link != null and link.state == "open")
	var ed := NetPlay.join_lobby(link.code, "ed", "")
	ed.make_match = func(info: Dictionary) -> Game: return main.net_match_game(info)
	nets.append(ed)
	var keep := RelayLink.server
	RelayLink.server = {"url": "ws://127.0.0.1:%d" % ws_port}
	var fay := NetPlay.join_lobby(link.code, "fay", "")
	RelayLink.server = keep
	fay.make_match = func(info: Dictionary) -> Game: return main.net_match_game(info)
	nets.append(fay)
	_wait(
		func() -> bool:
			return host.players.size() == 3 and ed.phase == "lobby" and fay.phase == "lobby",
		900
	)
	_check(host.players.size() == 3, "ED and FAY (over WebSocket) join by the line's code")
	for net: NetPlay in nets:
		_mouth(net)
	var from_host := _talk(host, 1.5)
	_check(
		int(from_host[ed]) > 25 and int(from_host[fay]) > 25,
		"the host is heard by both through the line (%d, %d)" % [from_host[ed], from_host[fay]]
	)
	var from_ed := _talk(ed, 1.5)
	_check(
		int(from_ed[host]) > 25 and int(from_ed[fay]) > 25 and int(from_ed[ed]) == 0,
		(
			"ED is heard by the host's own ears and by FAY (%d, %d), not by himself"
			% [from_ed[host], from_ed[fay]]
		)
	)
	for net: NetPlay in nets.duplicate():
		net.leave()
	_run_for(.5)


# ------------------------------------------------------------------ bench


## A full 5v5 of people, all talking: the server's time and bytes.
func _bench() -> void:
	if not _serve(5):
		return
	var lobby: NetPlay = server.rooms[0].net
	for room in server.rooms:
		room.net.session.lag_ms = 0.0
		room.net.session.jitter_ms = 0.0
		room.net.session.loss = 0.0
	for i in 10:
		var net := _join("p%d" % i)
		net.session.lag_ms = 0.0
		net.session.jitter_ms = 0.0
		net.session.loss = 0.0
		_wait(func() -> bool: return net.phase == "lobby", 300)
		net.ask({"team": i % 2, "ready": true})
		_mouth(net)
	_wait(func() -> bool: return lobby.players.size() == 10)
	var admin: NetPlay = nets[0]
	_wait(func() -> bool: return admin.why_not_start() == "", 300)
	print("start: '%s'" % admin.start_match())
	_wait(func() -> bool: return nets.all(func(n: NetPlay) -> bool: return n.client_ready()), 1200)
	var g := lobby.match_game()
	# Everyone close together, so every voice reaches every player.
	var p0: Player = g.players[0]
	for slot in g.players.size():
		var p: Player = g.players[slot]
		p.x = p0.x + (slot % 4) * .9
		p.y = p0.y + (slot / 4) * .9
	_run_for(1.0)
	for all_talk in [false, true, false, true]:
		var us := 0
		var bytes_before := lobby.session.sent
		var frames := int(seconds / STEP)
		talking.clear()
		if all_talk:
			for net: NetPlay in nets:
				talking[net] = true
		for i in frames:
			now += STEP * 1000.0
			var began := Time.get_ticks_usec()
			server.frame(now, STEP)
			us += Time.get_ticks_usec() - began
			for net: NetPlay in nets:
				net.poll(now)
				net.client_input(Game.Controls.new())
				net.client_play(1)
				var mouth: VoiceChat = mouths[net]
				var n := int(44100.0 * STEP)
				var said: int = mouth.get_meta(&"said", 0)
				mouth.feed(
					net,
					voice(n, 44100.0, said, 150.0),
					44100.0,
					talking.get(net, false),
					false,
					50,
					now
				)
				mouth.set_meta(&"said", said + n)
				for t: NetVoice.Talker in net.voice.talkers.values():
					t.pull(134, now)
		var kb := (lobby.session.sent - bytes_before) / 1024.0 / seconds
		print(
			(
				"%s: server %.1f%% of a core (%.2f ms a frame), out %.0f KB/s, frames passed on %d"
				% [
					"ten talking" if all_talk else "nobody talking",
					us / 10.0 / seconds / 1000.0,
					us / 1000.0 / frames,
					kb,
					lobby.voice.forwarded
				]
			)
		)


## People talking the whole time on a lobby server elsewhere, on the real clock.
func _bench_remote() -> void:
	var at := NetPlay.parse_address(remote)
	for i in talkers:
		var net := NetPlay.join_lobby(remote, "talker%d" % i, "")
		net.make_match = func(info: Dictionary) -> Game: return main.net_match_game(info)
		nets.append(net)
		_mouth(net)
	var began := Time.get_ticks_usec() / 1000.0
	var last := began
	var said_at := {}
	while Time.get_ticks_usec() / 1000.0 - began < seconds * 1000.0:
		now = Time.get_ticks_usec() / 1000.0
		var ticks := int((now - last) / (STEP * 1000.0))
		if ticks > 0:
			last += ticks * STEP * 1000.0
		for net: NetPlay in nets:
			net.poll(now)
			if net.phase == "lobby" and not net.has_meta(&"ready"):
				net.set_meta(&"ready", true)
				net.ask({"ready": true})
			if net.phase == "match" and net.client_ready():
				net.client_input(Game.Controls.new())
				net.client_play(mini(ticks, 4))
			if net.phase in ["lobby", "match"]:
				var mouth: VoiceChat = mouths[net]
				var from: float = said_at.get(net, now)
				var n := int((now - from) * 44.1)
				if n > 0:
					var said: int = mouth.get_meta(&"said", 0)
					var held := not quiet
					mouth.feed(net, voice(n, 44100.0, said, 150.0), 44100.0, held, false, 50, now)
					mouth.set_meta(&"said", said + n)
					said_at[net] = from + n / 44.1
				else:
					said_at[net] = from
			for t: NetVoice.Talker in net.voice.talkers.values():
				t.pull(VoiceCodec.FRAME, now)
		OS.delay_msec(2)
	var got := 0
	var up := 0
	for net: NetPlay in nets:
		up += net.voice.frames_up
		for t: NetVoice.Talker in net.voice.talkers.values():
			got += t.got
		print(
			(
				"%s %s slot %d"
				% [net._my_name, net.phase, net.my_slot() if net.phase == "match" else -1]
			)
		)
	print(
		"talkers sent %d frames, heard %d, server %s:%s" % [up, got, at.get("host"), at.get("port")]
	)
