## The authoritative host and its clients over a NetSession (net_wire.gd says
## what each packet holds; docs/multiplayer.md the whole model).
##
## NetSync.Host runs the one real game: each tick it plays its own players'
## controls and each client's next input (the last one again, without its
## one-shot actions, when one is late; catching up when a client's inputs
## pile up), and every `snap_every` ticks it takes a GameSnapshot and sends
## each client the delta from the newest snapshot that client acknowledged
## (the whole snapshot, at most every FULL_GAP ticks, while it has none),
## with the inputs everyone played since that base.
##
## NetSync.Client sends one input a tick (and the unconfirmed ones again),
## rebuilds each snapshot from its base, and keeps a copy of the game: it
## steps the copy with the inputs the host played, compares it with the
## snapshots as they come (CHECK_EVERY), and rebuilds it from a snapshot when
## it cannot step (inputs lost past the redundancy) or every REBUILD_EVERY
## ticks. GameSnapshot.apply only works on a game just made today, so a
## rebuild is a fresh game with the snapshot put on it; once apply works on a
## running game (the headless host work), set APPLY_RUNNING and the client
## puts every snapshot onto its copy instead.
class_name NetSync
extends RefCounted

const STEP := 1.0 / 60.0
const APPLY_RUNNING := false
## Parts of a snapshot's save that follow the local player (presentation).
const LOCAL_ONLY := ["visited"]


## A snapshot of `game` as the host takes it: player one acting (the save
## part follows the acting player, so a client whose own player is local
## would take another), and a copy of its own: a capture shares the game's
## packed arrays (the flow fields'), which the game goes on writing into.
static func capture(game: Game) -> Dictionary:
	var local: Player = game.local_player
	game.focus(game.players[0])
	var data := GameSnapshot.capture(game).duplicate(true)
	game.focus(local)
	return data


## `data` without what each machine keeps for itself: the save part carries
## some presentation (the walked map of whoever is local, the face's and
## messages' timers: GameSnapshot.VIEW_FIELDS). What a client's copy and the
## host's snapshot must agree on.
static func comparable(data: Dictionary) -> Dictionary:
	if not data.has("save"):
		return data
	var out := data.duplicate()
	var save: Dictionary = (data["save"] as Dictionary).duplicate()
	for name: String in LOCAL_ONLY + GameSnapshot.VIEW_FIELDS:
		save.erase(name)
	if save.get("game") is Dictionary:
		var fields: Dictionary = (save["game"] as Dictionary).duplicate()
		for name: String in LOCAL_ONLY + GameSnapshot.VIEW_FIELDS:
			fields.erase(name)
		save["game"] = fields
	out["save"] = save
	return out


## A connected client as the host sees it.
class Remote:
	extends RefCounted
	var id := 0
	var slot := -1
	## Inputs by number, waiting to be played.
	var waiting := {}
	var next := -1
	var last := PackedByteArray()
	## The newest snapshot it has (-1: none) and when it was last sent a whole one.
	var acked := -1
	var full_at := -1000000
	var starved := 0
	var skipped := 0


class Host:
	extends RefCounted
	## Whole snapshots no more often than this while a client has none.
	const FULL_GAP := 30
	## Snapshots kept as bases.
	const KEEP := 32
	## A client's inputs waiting past this are caught up on.
	const MAX_WAITING := 4
	## Ticks of inputs carried in a snapshot at most.
	const MAX_ECHO := 60

	var session: NetSession
	var game: Game
	var tick := 0
	var snap_every := 3
	var seq := -1
	## seq -> [tick, snapshot]
	var history := {}
	## tick -> the inputs every player played on it (NetWire.tick_row)
	var played := {}
	## peer id -> Remote
	var remotes := {}
	## Joins a player for a new client and returns its slot (-1: no room).
	var seat: Callable
	var sizes_full := PackedInt32Array()
	var sizes_delta := PackedInt32Array()
	var capture_us := 0
	var delta_us := 0
	var tick_us := 0

	func _init(s: NetSession, g: Game, seat_with: Callable, every := 3) -> void:
		session = s
		game = g
		seat = seat_with
		snap_every = every

	## Reads what came in (hellos, inputs) without playing a tick.
	func listen(now_ms: float) -> void:
		_receive(session.poll(now_ms))

	## Reads what came in, plays one tick with `own` (slot -> Controls, the
	## host's own players) and sends snapshots when one is due.
	func step(now_ms: float, own: Dictionary) -> void:
		_receive(session.poll(now_ms))
		var given := {}
		var rows := {}
		for slot in own:
			var bytes := NetWire.pack_controls(own[slot])
			rows[slot] = bytes
			given[slot] = NetWire.unpack_controls(bytes)
		for r: Remote in remotes.values():
			if r.slot < 0:
				continue
			var bytes := _next_input(r)
			rows[r.slot] = bytes
			given[r.slot] = NetWire.unpack_controls(bytes)
		var t0 := Time.get_ticks_usec()
		game.tick(STEP, given)
		tick_us += Time.get_ticks_usec() - t0
		tick += 1
		played[tick] = NetWire.tick_row(rows)
		played.erase(tick - MAX_ECHO * 2)
		if tick % snap_every == 0:
			_send_snapshots()

	func _next_input(r: Remote) -> PackedByteArray:
		if r.waiting.size() > MAX_WAITING:
			# Fallen behind (a burst after a stall): play on from the newest few.
			while r.waiting.size() > 1:
				if not r.waiting.has(r.next):
					r.next += 1
					continue
				var dropped: PackedByteArray = r.waiting[r.next]
				r.waiting.erase(r.next)
				r.next += 1
				if r.waiting.has(r.next):
					r.waiting[r.next] = NetWire.merged(dropped, r.waiting[r.next])
				r.skipped += 1
		if r.waiting.has(r.next):
			r.last = r.waiting[r.next]
			r.waiting.erase(r.next)
			r.next += 1
			return r.last
		r.starved += 1
		if r.last.is_empty():
			return NetWire.pack_controls(Game.Controls.new())
		r.last = NetWire.held_only(r.last)
		return r.last

	func _receive(packets: Array) -> void:
		var events := session.take_events()
		for id: int in events[1]:
			remotes.erase(id)
		for packet: Array in packets:
			var from := int(packet[0])
			var bytes: PackedByteArray = packet[1]
			if bytes.is_empty():
				continue
			if bytes[0] == NetWire.HELLO:
				_hello(from, NetWire.info_of(bytes))
			elif bytes[0] == NetWire.INPUTS and remotes.has(from):
				_inputs(remotes[from], NetWire.read_inputs(bytes))

	func _hello(from: int, info: Dictionary) -> void:
		if remotes.has(from):
			return
		var reply := {
			"level": game.level.id,
			"layout": game.level.layout,
			"tick_hz": roundi(1.0 / STEP),
			"snap_hz": roundi(1.0 / STEP / snap_every),
		}
		if int(info.get("protocol", 0)) != NetWire.PROTOCOL:
			reply["refused"] = "protocol %s, host has %d" % [info.get("protocol"), NetWire.PROTOCOL]
		else:
			var slot: int = seat.call()
			if slot < 0:
				reply["refused"] = "the game is full"
			else:
				var r := Remote.new()
				r.id = from
				r.slot = slot
				remotes[from] = r
				reply["slot"] = slot
		session.send(from, NetSession.CH_RELIABLE, NetWire.welcome(reply))

	func _inputs(r: Remote, msg: Dictionary) -> void:
		if msg.is_empty():
			return
		r.acked = maxi(r.acked, int(msg["ack"]))
		var first := int(msg["first"])
		var list: Array = msg["list"]
		if r.next < 0:
			r.next = first
		for i in list.size():
			if first + i >= r.next and not r.waiting.has(first + i):
				r.waiting[first + i] = list[i]

	func _send_snapshots() -> void:
		var t0 := Time.get_ticks_usec()
		var now := NetSync.capture(game)
		capture_us += Time.get_ticks_usec() - t0
		seq += 1
		history[seq] = [tick, now]
		history.erase(seq - KEEP)
		var by_base := {}
		for r: Remote in remotes.values():
			if r.slot < 0:
				continue
			var base := r.acked if history.has(r.acked) and r.acked < seq else -1
			if base < 0 and tick - r.full_at < FULL_GAP:
				continue
			if not by_base.has(base):
				t0 = Time.get_ticks_usec()
				var payload := (
					GameSnapshot.to_bytes(now)
					if base < 0
					else GameSnapshot.to_bytes(GameSnapshot.delta(history[base][1], now))
				)
				delta_us += Time.get_ticks_usec() - t0
				(sizes_full if base < 0 else sizes_delta).append(payload.size())
				by_base[base] = payload
			if base < 0:
				r.full_at = tick
			var since: int = tick if base < 0 else int(history[base][0])
			var first := maxi(since + 1, tick - MAX_ECHO + 1)
			var rows: Array = []
			for t in range(first, tick + 1):
				rows.append(played.get(t, PackedByteArray()))
			var packet := NetWire.snap(
				seq, base, tick, r.next - 1 if r.next > 0 else -1, [first, rows], by_base[base]
			)
			session.send(r.id, NetSession.CH_SNAPS, packet)


class Client:
	extends RefCounted
	## Compare the copy with a snapshot every this many ticks.
	const CHECK_EVERY := 60
	## Rebuild the copy from a snapshot every this many ticks (exercises apply).
	const REBUILD_EVERY := 600
	const KEEP := 32

	var session: NetSession
	## level id -> a fresh Game for it (configured as the host's).
	var make_game: Callable
	var slot := -1
	var refused := ""
	var level := ""
	var input_seq := 0
	var unacked := {}
	## seq -> [tick, snapshot]
	var snaps := {}
	var latest := -1
	var latest_tick := -1
	## The copy of the game and the tick it is at.
	var game: Game = null
	var game_tick := -1
	var rebuilt_at := -1000000
	var checked_at := -1000000
	var echo := {}
	var sent_at := {}
	var lag_samples := PackedFloat32Array()
	var stale := 0
	var no_base := 0
	var rebuilds := 0
	var checks := 0
	var mismatches := 0
	var first_mismatch := ""
	## Snapshots as rebuilt here, seq -> snapshot, for a test to hold against
	## the host's (keep_rebuilt).
	var keep_rebuilt := false
	var rebuilt := {}
	var _now := 0.0

	func _init(s: NetSession, maker: Callable) -> void:
		session = s
		make_game = maker

	func hello() -> void:
		session.send(
			NetSession.HOST_ID,
			NetSession.CH_RELIABLE,
			NetWire.hello(String(ProjectSettings.get_setting("application/config/version", "")))
		)

	## Reads what came in and brings the copy up to the newest snapshot.
	func receive(now_ms: float) -> void:
		_now = now_ms
		for packet: Array in session.poll(now_ms):
			var bytes: PackedByteArray = packet[1]
			if bytes.is_empty():
				continue
			if bytes[0] == NetWire.WELCOME:
				var info := NetWire.info_of(bytes)
				refused = String(info.get("refused", ""))
				slot = int(info.get("slot", -1))
				level = String(info.get("level", ""))
			elif bytes[0] == NetWire.SNAP:
				_snap(NetWire.read_snap(bytes))
		_catch_up()

	## Sends this tick's input (and every one not confirmed yet).
	func send_input(c: Game.Controls) -> void:
		if slot < 0:
			return
		unacked[input_seq] = NetWire.pack_controls(c)
		sent_at[input_seq] = _now
		input_seq += 1
		var first := input_seq - 1
		while first > 0 and unacked.has(first - 1) and input_seq - first < NetWire.REDUNDANT:
			first -= 1
		var list: Array = []
		for i in range(first, input_seq):
			list.append(unacked[i])
		session.send(NetSession.HOST_ID, NetSession.CH_INPUTS, NetWire.inputs(latest, first, list))

	func _snap(msg: Dictionary) -> void:
		if msg.is_empty():
			return
		var seq := int(msg["seq"])
		if seq <= latest:
			stale += 1
			return
		var base := int(msg["base"])
		var data := {}
		if base < 0:
			data = GameSnapshot.from_bytes(msg["payload"])
		elif snaps.has(base):
			data = GameSnapshot.patch(snaps[base][1], GameSnapshot.from_bytes(msg["payload"]))
		else:
			no_base += 1
			return
		var tick := int(msg["tick"])
		snaps[seq] = [tick, data]
		snaps.erase(seq - KEEP)
		if keep_rebuilt:
			rebuilt[seq] = data
		latest = seq
		latest_tick = tick
		var ack := int(msg["input_ack"])
		if ack >= 0:
			if sent_at.has(ack):
				lag_samples.append(_now - float(sent_at[ack]))
			for n in unacked.keys():
				if int(n) <= ack:
					unacked.erase(n)
					sent_at.erase(n)
		var first := int(msg["echo_first"])
		var rows: Array = msg["echo"]
		for i in rows.size():
			if not echo.has(first + i) and first + i > game_tick:
				echo[first + i] = rows[i]
		if APPLY_RUNNING and game != null:
			GameSnapshot.apply(game, data)
			game_tick = tick
			_after_apply()

	func _catch_up() -> void:
		if latest < 0:
			return
		if game == null or latest_tick - rebuilt_at >= REBUILD_EVERY:
			_rebuild()
			return
		while game_tick < latest_tick:
			var row = echo.get(game_tick + 1)
			if row == null or (row as Dictionary).is_empty():
				# The inputs for the next tick never came (lost past the
				# redundancy): start again from the newest snapshot.
				_rebuild()
				return
			var given := {}
			for s in row:
				given[int(s)] = NetWire.unpack_controls(row[s])
			game.tick(STEP, given)
			echo.erase(game_tick)
			game_tick += 1
			if game_tick - checked_at >= CHECK_EVERY:
				_check_at(game_tick)

	## Compares the copy with the snapshot of the tick it is at, if one is kept.
	func _check_at(tick: int) -> void:
		for seq in snaps:
			if int(snaps[seq][0]) != tick:
				continue
			checked_at = tick
			checks += 1
			var where := GameSnapshot.first_difference(
				NetSync.comparable(snaps[seq][1]), NetSync.comparable(NetSync.capture(game))
			)
			if where != "":
				mismatches += 1
				if first_mismatch == "":
					first_mismatch = "tick %d: %s" % [tick, where]
			return

	func _rebuild() -> void:
		var data: Dictionary = snaps[latest][1]
		var fresh: Game = make_game.call(level)
		if fresh == null or not GameSnapshot.apply(fresh, data.duplicate(true)):
			return
		rebuilds += 1
		game = fresh
		game_tick = latest_tick
		rebuilt_at = latest_tick
		for t in echo.keys():
			if int(t) <= game_tick:
				echo.erase(t)
		_after_apply()
		_check_at(game_tick)

	func _after_apply() -> void:
		if slot >= 0 and slot < game.players.size():
			Players.set_local(game, game.players[slot])

	## This machine's player in the copy (null before the first snapshot).
	func me() -> Player:
		if game == null or slot < 0 or slot >= game.players.size():
			return null
		return game.players[slot]
