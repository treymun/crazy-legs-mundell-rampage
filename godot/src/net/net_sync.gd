## The authoritative host and its clients over a NetSession (net_wire.gd says
## what each packet holds; docs/multiplayer.md the whole model).
##
## NetSync.Host runs the one real game: each tick it plays its own players'
## controls and each client's next input (the last one again, without its
## one-shot actions, when one is late; catching up when a client's inputs
## pile up), and every `snap_every` ticks it takes a GameSnapshot and sends
## each client the delta from the newest snapshot that client acknowledged
## (the whole snapshot, at most every FULL_GAP ticks, while it has none),
## with the inputs everyone played since that base. A client's shots are
## judged against the others where that client's screen showed them
## (Controls.rewind, from the tick its inputs say it was showing; game.gd
## `_rewound_hands`), and the rewind travels in the inputs echoed, so every
## copy plays it the same.
##
## NetSync.Client sends one input a tick (and the unconfirmed ones again),
## rebuilds each snapshot from its base, and keeps a copy of the game: it
## steps the copy with the inputs the host played (all at once, or played out
## a tick a frame a little behind the newest, `play_out`), compares it with
## the snapshots as they come (CHECK_EVERY), and puts a snapshot onto the copy
## when it cannot step (inputs lost past the redundancy) or the copy parted
## from the host. With REBUILD_RUNNING off it makes a fresh game for that
## instead (the old way, and every REBUILD_EVERY ticks).
##
## Either side can be driven by something that polls the session itself (the
## online lobby, net_play.gd): Host.take / play and Client.take / play_out.
class_name NetSync
extends RefCounted

const STEP := 1.0 / 60.0
const APPLY_RUNNING := false
## A rebuild puts the snapshot onto the copy already running (no fresh game,
## so no hitch): GameSnapshot.apply works on a running game.
const REBUILD_RUNNING := true
## Ticks a client's shots are rewound by at most (game.gd keeps REWIND_KEEP):
## 1.6 s. It was 64 until pass 13: past about 300 ms one way a shooter's
## screen showed the others further back than that, and net_lag at 400 ms
## cut 650 to 1,360 ticks' rewinds a minute short (judged where they were
## not seen); none at 96.
const MAX_REWIND := 96
## What a host uses (net_lag.gd's `rewind=`).
static var max_rewind := MAX_REWIND
## Parts of a snapshot's save that follow the local player (presentation).
const LOCAL_ONLY := ["visited"]


## A change to who plays from a tick's row (NetWire.event_of), made on a
## copy before it plays that tick, as the host made it before playing it:
## the same calls, so the same result. One already in the copy (a snapshot
## taken after it) is not made again.
static func play_event(game: Game, ev: Dictionary) -> void:
	if ev.is_empty():
		return
	var kind: int = ev["kind"]
	var slot: int = ev["slot"]
	var name: String = ev["name"]
	var here: Player = game.players[slot] if slot < game.players.size() else null
	match kind:
		NetWire.EVENT_AWAY:
			if here != null and not here.away:
				Modes.went_away(game, here)
		NetWire.EVENT_JOIN:
			if here == null or here.away:
				Modes.join_late(game, name)
		NetWire.EVENT_NAME:
			if here != null:
				here.name = name


## A snapshot of `game` as the host takes it: player one acting. (A capture
## copies the game's packed arrays itself, so no deep copy here: it was a
## third of a client's check every second.)
static func capture(game: Game) -> Dictionary:
	var local: Player = game.local_player
	game.focus(game.players[0])
	var data := GameSnapshot.capture(game)
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
	var save_in: Dictionary = data["save"]
	var save: Dictionary = save_in.duplicate()
	for name: String in LOCAL_ONLY + GameSnapshot.VIEW_FIELDS:
		save.erase(name)
	if save.get("game") is Dictionary:
		var fields_in: Dictionary = save["game"]
		var fields: Dictionary = fields_in.duplicate()
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
	## The snapshots it said it had lately, newest last (Host.coarse_bases).
	var acks := PackedInt32Array()
	var full_at := -1000000
	var starved := 0
	var skipped := 0
	## The tick of the game it was showing when it sent its newest inputs.
	var view_tick := -1
	## The number of its input played on the latest tick (-1: none came in
	## time, the last one held again). For the lag tool's hit report.
	var played := -1
	## The newest tick whose inputs went out to it in a snapshot (-1: none).
	var echo_sent := -1
	## INPUTS packets taken from it.
	var heard := 0
	## The newest tick whose place row went out to it.
	var places_sent := -1
	## input number -> the tick it was showing when it sent that one.
	var views := {}
	## The host's input buffer for it (Host.buffer_inputs): how late each
	## newest input came against its number (ticks), the ticks it is played
	## behind them, and whether it is filling up again after running dry.
	var arrivals := PackedInt32Array()
	var newest := -1
	var buffer := 0
	var refill := true


class Host:
	extends RefCounted
	## Whole snapshots no more often than this while a client has none.
	const FULL_GAP := 30
	## Snapshots kept as bases: 4 s at 30 a second. (32 until pass 12: past
	## about a second of round trip, a browser player at 250 ms whose TCP
	## held up a lost packet, a client's acknowledged base was gone and it
	## got whole snapshots with no input rows, its copy put back on each,
	## about one a second; net_soak_all.gd.)
	const KEEP := 120
	## A client's inputs waiting past this are caught up on.
	const MAX_WAITING := 4
	## Ticks of inputs carried in a snapshot at most.
	const MAX_ECHO := 60
	## Snapshots' worth of inputs sent again (a lost snapshot's are in the
	## next ones). Every row since the client's acknowledged base used to go
	## in each snapshot: a round trip's worth, the biggest part of a 5v5's
	## bandwidth. Pass 12: ECHO_TICKS ticks' worth whatever the rate (at 60
	## snapshots a second three snapshots were three ticks, and at 250 ms
	## with jitter the copies were put back 43 times in 20 s for rows that
	## never came); `echo_by_ticks` off: ECHO_AGAIN snapshots' worth.
	const ECHO_AGAIN := 3
	const ECHO_TICKS := 9
	static var echo_by_ticks := true
	## Off: a whole snapshot carries no rows (the old way).
	static var rows_in_wholes := true
	## Off: every row since the base (the old way, for net_lag.gd's comparison).
	static var trim_echo := true
	## Off: each client's change merged from its base every snapshot (the old way).
	static var carry := true
	## Off: a shot rewound from the newest tick the client said it showed,
	## not the one it showed when it sent that shot (the old way, which
	## judged shots from a buffered input too late).
	static var per_input_view := true
	## Inputs whose shown tick is remembered.
	const VIEWS_KEPT := 64
	## A person's inputs are played a little behind their arrival, by how
	## much they wander (0 to BUFFER_MOST ticks: their spread over the
	## quickest, ARRIVALS_KEPT of them, less a tick), and after running dry
	## the buffer fills again before they play on: they are played evenly,
	## where a late one used to be held, the pile then merged, and everyone
	## else saw them stop and lurch (net_feel.gd at 250 ms). The rewind
	## follows (_view_of: the tick they showed, the tick it is played).
	## Off: each input played as soon as it is there (the old way).
	static var buffer_inputs := true
	const BUFFER_MOST := 2
	const ARRIVALS_KEPT := 120
	## Deltas only from this many snapshots a second at most (60 a second:
	## every 4th, 30: every other one). Each base a client may still
	## acknowledge has every new change merged onto it (_carry_since), so the
	## work grew with the round trip times the rate: net_lag's 5v5 server at
	## 60 a second took 30, 52 and 68% of this PC's core at 120, 250 and
	## 400 ms (the snapshots 3.3, 6.7, 9.4 ms a tick), 27, 28 and 36% (2.5,
	## 2.9, 4.0) with these. A client keeps every snapshot it said it had
	## (Client.KEEP), so the host sends it a delta from the newest of those
	## that is a base (`Remote.acks`); it is hardly bigger (a round trip's
	## change either way: 1.01 against 0.97 KB median at 120 ms). Off
	## (net_lag's `allbases`): every snapshot a base (the old way).
	static var coarse_bases := true
	const BASES_A_SECOND := 15
	static var bases_a_second := BASES_A_SECOND
	const ACKS_KEPT := 16

	var session: NetSession
	var game: Game
	var tick := 0
	var snap_every := 3
	var seq := -1
	## seq -> [tick, snapshot], or [tick, what changed since the seq before]
	## when `tracked`.
	var history := {}
	## Each snapshot's changes found by NetTrack (it looks only at what moved:
	## about a sixth of a whole capture and diff for a 5v5) and merged from a
	## client's base; a whole capture only for a client with none. Off: every
	## snapshot captured whole and diffed against the client's base.
	var tracked := true
	var track: NetTrack = null
	## tick -> the inputs every player played on it (NetWire.tick_row)
	var played := {}
	## tick -> where everyone stood on it (game.place_log's row), sent with
	## the echoed inputs (send_places; off: the old packets).
	var places := {}
	static var send_places := true
	## peer id -> Remote
	var remotes := {}
	## Joins a player for a new client and returns its slot (-1: no room).
	var seat: Callable
	## Judge clients' shots where their screens showed the others (off: as
	## the host stands them).
	var rewind := true
	var sizes_full := PackedInt32Array()
	var sizes_delta := PackedInt32Array()
	## Every SNAP packet's size, and how many went in parts.
	var sizes_packet := PackedInt32Array()
	var split_count := 0
	## Off: a SNAP over the MTU goes reliable (the 3.9.0 way, net_lag's
	## `oldserver`).
	static var split_big := true
	var capture_us := 0
	var delta_us := 0
	var tick_us := 0
	## The longest rewind a client's tick asked for (ticks), and how many
	## ticks asked for more than MAX_REWIND (net_lag.gd).
	var rewind_most := 0
	var rewind_capped := 0
	## base seq -> what changed from it to the newest snapshot (_carry_since).
	var _since := {}
	## Snapshots go out on ticks where (tick + snap_phase) % snap_every is 0
	## (-1 until a lobby server sets it: then 0); with `hold` a tick keeps a
	## due one for the next tick without hold (a server catching up sends
	## one snapshot, not a burst).
	var snap_phase := -1
	var hold := false
	var _owed := false
	## Changes to who plays made on the host's game since the last tick (a
	## leave, a join, a new name: NetWire.event), sent in the next tick's row
	## so every copy makes them before that tick as the host did. Off
	## (`tick_events`): none sent, and every other copy is put back once for
	## each (the old way).
	var events: Array[PackedByteArray] = []
	static var tick_events := true

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
		play(own)

	## Inputs handed in by whoever polls the session (the lobby around it).
	func take(packets: Array) -> void:
		for packet: Array in packets:
			var bytes: PackedByteArray = packet[1]
			var from: int = packet[0]
			if not bytes.is_empty() and bytes[0] == NetWire.INPUTS and remotes.has(from):
				var r: Remote = remotes[from]
				_inputs(r, NetWire.read_inputs(bytes))

	## A client playing `slot` from now on (seated by a lobby, not a HELLO).
	func add_remote(id: int, slot: int) -> void:
		var r := Remote.new()
		r.id = id
		r.slot = slot
		remotes[id] = r

	func drop_remote(id: int) -> void:
		remotes.erase(id)

	## A change to who plays, just made on the host's game between ticks
	## (Modes.went_away, join_late, a new name): it rides the next tick's row.
	func note_event(bytes: PackedByteArray) -> void:
		if tick_events and events.size() < 255 - NetWire.EVENT_SLOT:
			events.append(bytes)

	## One tick with `own` (slot -> Controls, the host's own players) and
	## every client's next input; snapshots when one is due.
	func play(own: Dictionary) -> void:
		var given := {}
		var rows := {}
		for slot: Variant in own:
			var controls: Game.Controls = own[slot]
			var bytes := NetWire.pack_controls(controls)
			rows[slot] = bytes
			given[slot] = NetWire.unpack_controls(bytes)
		for r: Remote in remotes.values():
			if r.slot < 0 or r.slot >= game.players.size():
				continue
			var bytes := _next_input(r)
			var view := _view_of(r) if per_input_view else r.view_tick
			if rewind and view >= 0:
				var back := tick + 1 - view
				rewind_most = maxi(rewind_most, back)
				if back > NetSync.max_rewind:
					rewind_capped += 1
				bytes = NetWire.with_rewind(bytes, clampi(back, 0, NetSync.max_rewind))
			rows[r.slot] = bytes
			given[r.slot] = NetWire.unpack_controls(bytes)
		for i in events.size():
			rows[NetWire.EVENT_SLOT + i] = events[i]
		events.clear()
		var t0 := Time.get_ticks_usec()
		game.tick(STEP, given)
		tick_us += Time.get_ticks_usec() - t0
		tick += 1
		played[tick] = NetWire.tick_row(rows)
		played.erase(tick - MAX_ECHO * 2)
		_note_place()
		if (tick + maxi(0, snap_phase)) % snap_every == 0 or _owed:
			if hold:
				_owed = true
			else:
				_owed = false
				_send_snapshots()

	## The tick just played's row of game.place_log, kept to send.
	func _note_place() -> void:
		if not send_places or game.place_log.is_empty() or game.players.size() < 2:
			return
		places[tick] = game.place_log[-1]
		places.erase(tick - MAX_ECHO * 2)

	## The place rows `r` has not been sent, of the ticks from `first` to
	## now, each once (the last ticks of the echoed ones; [] for a game of
	## one, or with send_places off).
	func _places_for(r: Remote, first: int) -> Array:
		var out: Array = []
		for t in range(maxi(first, r.places_sent + 1), tick + 1):
			if not places.has(t):
				return []
			out.append(places[t])
		if not out.is_empty():
			r.places_sent = tick
		return out

	## What changed from snapshot `base` to this one (null: send it whole).
	func _change_since(base: int, now: Dictionary) -> Variant:
		if not tracked:
			var base_snap: Dictionary = history[base][1]
			return GameSnapshot.delta(base_snap, now)
		if carry and _since.has(base):
			return _since[base]
		var merged := {}
		for s in range(base + 1, seq + 1):
			if not history.has(s):
				return null
			var change: Dictionary = history[s][1]
			var next: Variant = GameSnapshot.merge(merged, change)
			if next == null:
				return null
			merged = next
		if carry:
			_since[base] = merged
		return merged

	## The newest change merged onto each base a client may still send an
	## acknowledgement of (from the oldest acknowledged on): one merge a base
	## per snapshot, where each client used to merge every snapshot since its
	## own base; and the newest snapshot as a base to come.
	func _carry_since(change: Dictionary) -> void:
		var oldest := seq
		var every := base_every()
		for r: Remote in remotes.values():
			var base := _base_for(r) if every > 1 else r.acked
			if base >= 0:
				oldest = mini(oldest, base)
		var kept := {}
		for base: int in _since:
			if base < oldest or base <= seq - KEEP:
				continue
			var next: Variant = GameSnapshot.merge(_since[base], change)
			if next != null:
				kept[base] = next
		if seq % every == 0:
			kept[seq] = {}
		_since = kept

	## Every this many snapshots is a base for deltas (coarse_bases).
	func base_every() -> int:
		if not coarse_bases or not carry:
			return 1
		return maxi(1, roundi(1.0 / STEP / snap_every / bases_a_second))

	## The snapshot `r`'s next delta is from: the newest it said it had that
	## is a base (base_every), else its newest; -1 none (a whole one).
	func _base_for(r: Remote) -> int:
		var every := base_every()
		if every > 1:
			for i in range(r.acks.size() - 1, -1, -1):
				var s := r.acks[i]
				if s % every == 0 and s < seq and history.has(s):
					return s
		return r.acked if history.has(r.acked) and r.acked < seq else -1

	## The remotes with a base to make a delta from first, then those that
	## need a whole snapshot.
	func _deltas_first() -> Array[Remote]:
		var out: Array[Remote] = []
		var whole: Array[Remote] = []
		for r: Remote in remotes.values():
			if _base_for(r) >= 0:
				out.append(r)
			else:
				whole.append(r)
		out.append_array(whole)
		return out

	## The tick a client was showing when it sent the input played now: its
	## own packet's, or worked out a tick an input from the nearest one known
	## (that packet lost). -1: none known.
	func _view_of(r: Remote) -> int:
		var n := r.played if r.played >= 0 else r.next - 1
		for old: int in r.views.keys():
			if old < n - VIEWS_KEPT:
				r.views.erase(old)
		if r.views.has(n):
			return r.views[n]
		var best := -1
		var view := r.view_tick
		for s: int in r.views:
			if best < 0 or absi(s - n) < absi(best - n):
				best = s
				var known: int = r.views[s]
				view = known - (s - n)
		return mini(view, tick)

	func _next_input(r: Remote) -> PackedByteArray:
		var keep := r.buffer + 1 if buffer_inputs else 1
		if r.waiting.size() > MAX_WAITING + keep - 1:
			# Fallen behind (a burst after a stall): play on from the newest few.
			while r.waiting.size() > keep:
				if not r.waiting.has(r.next):
					r.next += 1
					continue
				var dropped: PackedByteArray = r.waiting[r.next]
				r.waiting.erase(r.next)
				r.next += 1
				if r.waiting.has(r.next):
					var later: PackedByteArray = r.waiting[r.next]
					r.waiting[r.next] = NetWire.merged(dropped, later)
				r.skipped += 1
		if buffer_inputs and r.refill and r.buffer > 0:
			var have := 0
			while r.waiting.has(r.next + have):
				have += 1
			if have <= r.buffer:
				return _held(r)
		r.refill = false
		if r.waiting.has(r.next):
			r.last = r.waiting[r.next]
			r.waiting.erase(r.next)
			r.played = r.next
			r.next += 1
			return r.last
		r.refill = true
		return _held(r)

	## No input of its own this tick: the last one held (without its
	## one-shot actions, turn and look).
	func _held(r: Remote) -> PackedByteArray:
		r.played = -1
		r.starved += 1
		if r.last.is_empty():
			return NetWire.pack_controls(Game.Controls.new())
		r.last = NetWire.held_only(r.last)
		return r.last

	## How late its newest input came (ticks behind its number), and the
	## buffer that covers how much that wanders.
	func _arrival(r: Remote, newest: int) -> void:
		if newest <= r.newest:
			return
		r.newest = newest
		r.arrivals.append(tick - newest)
		if r.arrivals.size() > ARRIVALS_KEPT:
			r.arrivals = r.arrivals.slice(r.arrivals.size() - ARRIVALS_KEPT)
		if r.arrivals.size() < 30 or r.arrivals.size() % 15 != 0:
			return
		var sorted := r.arrivals.duplicate()
		sorted.sort()
		var spread := sorted[int(sorted.size() * .95)] - sorted[0]
		r.buffer = clampi(spread - 1, 0, BUFFER_MOST)

	func _receive(packets: Array) -> void:
		var events := session.take_events()
		for id: int in events[1]:
			remotes.erase(id)
		for packet: Array in packets:
			var from: int = packet[0]
			var bytes: PackedByteArray = packet[1]
			if bytes.is_empty():
				continue
			if bytes[0] == NetWire.HELLO:
				_hello(from, NetWire.info_of(bytes))
			elif bytes[0] == NetWire.INPUTS and remotes.has(from):
				var r: Remote = remotes[from]
				_inputs(r, NetWire.read_inputs(bytes))

	func _hello(from: int, info: Dictionary) -> void:
		if remotes.has(from):
			return
		var reply := {
			"level": game.level.id,
			"layout": game.level.layout,
			"tick_hz": roundi(1.0 / STEP),
			"snap_hz": roundi(1.0 / STEP / snap_every),
		}
		var protocol: int = info.get("protocol", 0)
		if protocol != NetWire.PROTOCOL:
			reply["refused"] = "protocol %s, host has %d" % [info.get("protocol"), NetWire.PROTOCOL]
		else:
			var slot: int = seat.call()
			if slot < 0:
				reply["refused"] = "the game is full"
			else:
				add_remote(from, slot)
				reply["slot"] = slot
		session.send(from, NetSession.CH_RELIABLE, NetWire.welcome(reply))

	func _inputs(r: Remote, msg: Dictionary) -> void:
		if msg.is_empty():
			return
		r.heard += 1
		var ack: int = msg["ack"]
		r.acked = maxi(r.acked, ack)
		if ack >= 0 and (r.acks.is_empty() or ack > r.acks[-1]):
			r.acks.append(ack)
			if r.acks.size() > ACKS_KEPT:
				r.acks = r.acks.slice(r.acks.size() - ACKS_KEPT)
		var view: int = msg.get("view_tick", -1)
		if view > r.view_tick and view <= tick:
			r.view_tick = view
		var first: int = msg["first"]
		var list: Array = msg["list"]
		if view >= 0 and not list.is_empty() and view <= tick:
			# The tick shown when the newest of these was sent: that input's
			# own (_view_of), not whatever came in last before it is played.
			r.views[first + list.size() - 1] = view
		if r.next < 0:
			r.next = first
		if not list.is_empty():
			_arrival(r, first + list.size() - 1)
		for i in list.size():
			if first + i >= r.next and not r.waiting.has(first + i):
				r.waiting[first + i] = list[i]

	func _send_snapshots() -> void:
		var t0 := Time.get_ticks_usec()
		var now := {}
		if not tracked:
			now = NetSync.capture(game)
			history[seq + 1] = [tick, now]
		elif track == null:
			track = NetTrack.new(game)
			history[seq + 1] = [tick, {}]
		else:
			history[seq + 1] = [tick, track.changes()]
		capture_us += Time.get_ticks_usec() - t0
		seq += 1
		history.erase(seq - KEEP)
		if tracked and carry:
			t0 = Time.get_ticks_usec()
			var newest: Dictionary = history[seq][1]
			_carry_since(newest)
			delta_us += Time.get_ticks_usec() - t0
		var by_base := {}
		var flushed := false
		for r: Remote in _deltas_first():
			if r.slot < 0:
				continue
			var base := _base_for(r)
			if base < 0 and tick - r.full_at < FULL_GAP:
				continue
			if base < 0 and not flushed:
				# Everyone's delta is on its way before a whole snapshot (a
				# joiner's: 5 to 15 ms to capture and pack) holds this up.
				session.flush()
				flushed = true
			if not by_base.has(base):
				t0 = Time.get_ticks_usec()
				var change: Variant = _change_since(base, now) if base >= 0 else null
				if change == null:
					if now.is_empty():
						now = GameSnapshot.capture(game)
					base = -1
				var to_send: Dictionary = now if change == null else change
				var payload := GameSnapshot.to_bytes(to_send)
				delta_us += Time.get_ticks_usec() - t0
				(sizes_full if base < 0 else sizes_delta).append(payload.size())
				by_base[base] = payload
			if base < 0:
				r.full_at = tick
			var again := ECHO_TICKS if echo_by_ticks else ECHO_AGAIN * snap_every
			var since: int = tick if base < 0 else history[base][0]
			if base < 0 and r.echo_sent >= 0 and rows_in_wholes:
				# A client that fell behind gets a whole snapshot: with the
				# rows since the last it was sent, so its copy plays on to it
				# instead of being put back (co-op and County Run at 250 ms:
				# their big deltas went missing in parts until the base was
				# too old, and the whole one carried no rows at all).
				since = r.echo_sent - again
			var first := maxi(since + 1, tick - MAX_ECHO + 1)
			if trim_echo and r.echo_sent >= 0 and base >= 0:
				first = maxi(first, r.echo_sent + 1 - again)
			r.echo_sent = tick
			var rows: Array = []
			for t in range(first, tick + 1):
				rows.append(played.get(t, PackedByteArray()))
			var snap_bytes: PackedByteArray = by_base[base]
			var packet := NetWire.snap(
				seq,
				base,
				tick,
				r.next - 1 if r.next > 0 else -1,
				[first, rows],
				snap_bytes,
				_places_for(r, first)
			)
			sizes_packet.append(packet.size())
			if base >= 0 and packet.size() > NetWire.PART_MOST and split_big:
				# Too big for one packet: in parts, still unreliable (a
				# reliable snapshot lost held up every one after it for a
				# resend, the whole stream frozen for a round trip or more).
				for part in NetWire.split(packet, seq):
					session.send(r.id, NetSession.CH_SNAPS, part)
				split_count += 1
			else:
				session.send(r.id, NetSession.CH_SNAPS, packet)


class Client:
	extends RefCounted
	## Compare the copy with a snapshot every this many ticks.
	const CHECK_EVERY := 60
	## With spread_check: a part of the copy every this many ticks
	## (net_check_parts.gd), all of it in turn about once a second; off: the
	## whole copy every CHECK_EVERY ticks in one frame (a hitch of 7 to 40 ms).
	const CHECK_PART_EVERY := 4
	static var spread_check := true
	## Off: every snapshot of a bunch put together, the old way (_snaps_in).
	static var bunch_newest := true
	## Snapshots of a bunch not put together (their newest was).
	var bunched := 0
	## Floats this near (relative) are the same to that comparison: a server
	## on Linux and a client on Windows round sin, cos and the like a last bit
	## apart, and copies were put back every 20 to 40 s for it against the VPS
	## (pass 9 soak). A parting that matters moves an int, a bool, the dice or
	## a float by far more, and still puts the copy back. 0: bit for bit.
	const NEAR := 1e-9
	## What this copy uses (NetPlay sets NEAR when the host runs another system).
	var near := 0.0
	## Rebuild the copy from a snapshot every this many ticks (exercises
	## apply; only with REBUILD_RUNNING off).
	const REBUILD_EVERY := 600
	## Snapshots kept as bases for the host's deltas: as many as the host
	## keeps (Host.KEEP; each shares what did not change with the one before).
	const KEEP := 120
	## Inputs remembered after they are confirmed (the view's prediction).
	const SENT_KEEP := 120
	## Round trips kept in lag_samples (the newest; a tool folding them in
	## takes them more often than this fills).
	const LAG_KEPT := 8192
	## Partings kept in mismatch_log.
	const MISMATCH_LOG := 6
	## When the rows came, to judge the link (`arrivals`): with fine_depth
	## every tick's row as it first came (a snapshot brings the rows of the
	## ticks since the last, so the pairs at 30 a second and the rows a lost
	## snapshot held back count as late as they were), the last
	## ARRIVAL_SECONDS of them at most ARRIVALS; the pass 12 way the newest
	## snapshots' own ticks only, the last 90 (3 s at 30 a second, 1.5 at 60).
	const ARRIVALS := 240
	const ARRIVAL_SECONDS := 3.0
	## The share of the rows the playout depth covers (the rest come a little
	## late: everyone else held a frame or two).
	const SPREAD_SHARE := .99
	## The copy is played at least this far behind the newest snapshot, and
	## at most PLAYOUT_MOST.
	const PLAYOUT_LEAST := 2
	const PLAYOUT_MOST := 14
	## Seconds a lower playout depth must hold before the copy closes up, and
	## then how fast it closes up (ticks a second; the render clock takes it
	## in at most CLOCK_FAST faster). Until pass 13 a tick every 3 s: a spike
	## or the match's first second left everyone shown 2 to 4 ticks later
	## than the link needed for half a minute.
	const PLAYOUT_EASE := 1.0
	const PLAYOUT_CLOSE := 1.5
	## Faster when far above where it should be: this share of the gap a second.
	const PLAYOUT_CLOSE_SHARE := .5
	## The copy plays on as far as the host's rows go (a snapshot's first
	## part carries its tick's rows and input ack: `rows_tick`), not only to
	## the newest snapshot put together whole; a split one (co-op and County
	## Run deltas, 7 to 12 parts) used to hold everyone still until its last
	## part, or for good when one was lost. Off: the newest whole snapshot.
	static var rows_ahead := true
	## Off: the depth in whole ticks, down a tick every 3 s, the arrivals the
	## last 90 snapshots' (the pass 12 way; net_feel's `depth12`).
	static var fine_depth := true
	## SPREAD_SHARE, and ticks added to the depth (net_feel's share=, margin=).
	static var spread_share := SPREAD_SHARE
	static var depth_margin := 0.0
	## Off: prediction from our inputs alone, and a fixed playout depth (the
	## old ways, for net_lag.gd's before and after).
	static var predict_from_echo := true
	static var adaptive_playout := true
	## Off: the copy shown at whole ticks by the clock as it was (net_feel's
	## `old`): no render clock, no fraction for NetBlend.
	static var smooth_clock := true
	## The render clock eases toward its mark by at most these shares of the
	## time passing (faster, slower), and jumps only when this many ticks off.
	const CLOCK_FAST := .08
	const CLOCK_SLOW := .15
	const CLOCK_SNAP := 10.0
	## Ticks the newest snapshot may be ahead while the copy waits for a
	## late snapshot's inputs (_rows_late); off: put back at once.
	const ROWS_WAIT := 12
	static var wait_rows := true

	var session: NetSession
	## level id -> a fresh Game for it (configured as the host's).
	var make_game: Callable
	var slot := -1
	var refused := ""
	var level := ""
	var input_seq := 0
	var unacked := {}
	## Every input sent lately, seq -> packed controls (confirmed ones too).
	var sent := {}
	## The newest input of ours the host had played, and at which tick.
	var input_ack := -1
	var input_ack_tick := -1
	## seq -> [tick, snapshot]
	var snaps := {}
	var latest := -1
	var latest_tick := -1
	## The newest tick whose rows came (a snapshot's or a first part's
	## header, rows_ahead): the copy may be played up to head().
	var rows_tick := -1
	var _arrival_tick := -1
	## The copy of the game and the tick it is at.
	var game: Game = null
	var game_tick := -1
	var rebuilt_at := -1000000
	var checked_at := -1000000
	var echo := {}
	## tick -> the host's game.place_log row for it (the echoed ticks' and
	## those a rewind may still reach back to): a copy put back on a snapshot
	## ahead of it takes these for the ticks it skipped (_put_places).
	var places := {}
	var sent_at := {}
	var lag_samples := PackedFloat32Array()
	var stale := 0
	var no_base := 0
	var rebuilds := 0
	## Leaves, joins and names made on the copy from the rows (NetWire.event).
	var events_played := 0
	var checks := 0
	var mismatches := 0
	var first_mismatch := ""
	## Where each parting was (the first MISMATCH_LOG), for a check's report.
	var mismatch_log: Array[String] = []
	## Snapshots as rebuilt here, seq -> snapshot, for a test to hold against
	## the host's (keep_rebuilt).
	var keep_rebuilt := false
	var rebuilt := {}
	## Copies put back on a snapshot because a tick's inputs never came.
	var rebuilds_lost := 0
	## When each newest snapshot came, as (ms) less its tick's time: how much
	## that wanders is the link's jitter.
	var arrivals := PackedFloat32Array()
	## When each of `arrivals` came (ms), to keep the last ARRIVAL_SECONDS.
	var _arrived_ms := PackedFloat32Array()
	## Paced by the clock (playout); off for COUNTY RUN co-op, whose world
	## holds for the party's card picks and parted from the host when paced so.
	var by_clock := true
	## Snapshots that came in SNAP_PARTs, and the parts of those still coming.
	## `rows_from_parts` off: a split snapshot's rows only once it is whole.
	static var rows_from_parts := true
	var parts_joined := 0
	## The part of the copy the next check looks at (net_check_parts.gd).
	var check_part := 0
	## Frames the copy waited for inputs on their way (_rows_late).
	var rows_waited := 0
	## Frames the copy could not be played as far as the render clock (the
	## newest snapshot not yet there): everyone else held still.
	var short := 0
	var _parts := {}
	var _depth := float(PLAYOUT_LEAST)
	## The arrival the render clock reckons the host's tick from (the
	## quickest lately) and how much later the rows come (SPREAD_SHARE of
	## them, ms): _measure, at each arrival.
	var _quickest := 0.0
	var _spread_ms := 0.0
	var _depth_ms := -1.0
	var _lower_since := -1.0
	var _now := 0.0
	## The tick this frame shows, with its fraction (-1: the copy as it
	## stands): NetBlend draws everyone between the copy's last two ticks by it.
	var view_at := -1.0
	var _clock := -1.0
	var _clock_ms := -1.0

	func _init(s: NetSession, maker: Callable) -> void:
		session = s
		make_game = maker

	func hello() -> void:
		session.send(
			NetSession.HOST_ID,
			NetSession.CH_RELIABLE,
			NetWire.hello(str(ProjectSettings.get_setting("application/config/version", "")))
		)

	## Reads what came in and brings the copy up to the newest snapshot.
	func receive(now_ms: float) -> void:
		take(session.poll(now_ms), now_ms)
		_catch_up()

	## Snapshots and the welcome handed in by whoever polls the session.
	func take(packets: Array, now_ms := -1.0) -> void:
		if now_ms >= 0.0:
			_now = now_ms
		var came: Array = []
		for packet: Array in packets:
			var bytes: PackedByteArray = packet[1]
			if bytes.is_empty():
				continue
			if bytes[0] == NetWire.WELCOME:
				var info := NetWire.info_of(bytes)
				refused = str(info.get("refused", ""))
				slot = info.get("slot", -1)
				level = str(info.get("level", ""))
			elif bytes[0] == NetWire.SNAP:
				came.append(NetWire.read_snap(bytes))
			elif bytes[0] == NetWire.SNAP_PART:
				var whole := _joined(bytes)
				if not whole.is_empty():
					came.append(NetWire.read_snap(whole))
		_snaps_in(came)

	## The snapshots that came together (a bunch after a stall, a WebSocket
	## held up a round trip): each delta is from a base this copy acknowledged,
	## not from the one before it, so only the newest needs putting together
	## (one patch, 2 to 4 ms in Hickston co-op, where a bunch of five took
	## five; pass 12 soak). Every one's inputs and arrival are taken; the
	## older ones are put together only when the newest's base is not here.
	func _snaps_in(came: Array) -> void:
		var newest := -1
		var newest_seq := -1
		for i in came.size():
			var msg: Dictionary = came[i]
			if msg.is_empty():
				continue
			var msg_seq: int = msg["seq"]
			if newest < 0 or msg_seq > newest_seq:
				newest = i
				newest_seq = msg_seq
		if newest < 0:
			return
		var top: Dictionary = came[newest]
		var base: int = top["base"]
		if not bunch_newest or came.size() < 2 or (base >= 0 and not snaps.has(base)):
			for msg: Dictionary in came:
				_snap(msg)
			return
		for i in came.size():
			var msg: Dictionary = came[i]
			if i == newest or msg.is_empty():
				continue
			_take_rows(msg)
			if not rows_ahead:
				var msg_tick: int = msg["tick"]
				_arrived(msg_tick)
			bunched += 1
		_snap(top)

	## The inputs played on each tick are the host's word whatever the
	## snapshot: kept from a late one too (big snapshots go reliable, the
	## rest not, so they can pass each other), and from a split one's first
	## part.
	func _take_rows(msg: Dictionary) -> void:
		if not msg.has("echo"):
			return
		if rows_ahead:
			_head(msg)
		var first: int = msg["echo_first"]
		var rows: Array = msg["echo"]
		for i in rows.size():
			if not echo.has(first + i) and first + i > game_tick:
				echo[first + i] = rows[i]
		var places_in: Array = msg.get("places", [])
		_take_places(first + rows.size() - places_in.size(), places_in)

	## A SNAP_PART kept until its snapshot's parts are all in: then the SNAP
	## they make (empty until then, or for a malformed part).
	func _joined(part: PackedByteArray) -> PackedByteArray:
		if part.size() <= NetWire.PART_HEADER:
			return PackedByteArray()
		var seq := part.decode_u32(1)
		var index := part[5]
		var count := part[6]
		if count == 0 or index >= count or count > NetWire.PARTS_MOST:
			return PackedByteArray()
		var got: Dictionary = _parts.get(seq, {})
		got[index] = part.slice(NetWire.PART_HEADER)
		if index == 0 and rows_from_parts:
			# The rows come first in a snapshot: the first part alone has
			# them, so a later part lost loses the state, not the inputs.
			var head: PackedByteArray = got[0]
			_take_rows(NetWire.read_snap(head))
		_parts[seq] = got
		for old: int in _parts.keys():
			if old < seq - KEEP:
				_parts.erase(old)
		if got.size() < count:
			return PackedByteArray()
		_parts.erase(seq)
		var whole := PackedByteArray()
		for i in count:
			if not got.has(i):
				return PackedByteArray()
			var piece: PackedByteArray = got[i]
			whole.append_array(piece)
		parts_joined += 1
		return whole

	## Steps the copy toward the newest snapshot: at most `most` ticks, and no
	## nearer to it than `behind` ticks unless it has fallen far back (then it
	## catches up at once). Played a tick or so a frame, the world moves
	## smoothly between snapshots.
	func play_out(most: int, behind := 0) -> void:
		_catch_up(most, behind)

	## Ticks of the game this copy is behind the newest snapshot.
	func backlog() -> int:
		return head() - game_tick if latest >= 0 else 0

	## The newest tick the copy may be played to: the newest whole snapshot's,
	## or past it as far as the host's rows go (rows_ahead).
	func head() -> int:
		return maxi(latest_tick, rows_tick) if rows_ahead else latest_tick

	## A snapshot's header (a whole one's, or its first part's): its tick's
	## rows are in, so the copy may be played to it; its input ack is the
	## host's word on which of ours it had played by then. The arrival that
	## paces the copy is this one's.
	func _head(msg: Dictionary) -> void:
		var tick: int = msg["tick"]
		if tick <= rows_tick:
			return
		rows_tick = tick
		_arrived(tick)
		var ack: int = msg["input_ack"]
		if ack >= 0:
			_acked(ack, tick)

	## The host had played our input `ack` by `tick`.
	func _acked(ack: int, tick: int) -> void:
		input_ack = ack
		input_ack_tick = tick
		if sent_at.has(ack):
			var at_ms: float = sent_at[ack]
			lag_samples.append(_now - at_ms)
			if lag_samples.size() > LAG_KEPT * 2:
				# The newest only (a session of hours grew it without end).
				lag_samples = lag_samples.slice(lag_samples.size() - LAG_KEPT)
		for n: Variant in unacked.keys():
			var n_seq: int = n
			if n_seq <= ack:
				unacked.erase(n)
				sent_at.erase(n)

	## Plays the copy on by the clock, not by when snapshots come: the tick it
	## shows is the host's tick now (judged from the quickest arrivals) less
	## a depth that covers how much the arrivals wander (playout_depth), so
	## it moves a tick a frame however the snapshots bunch up, and closes on
	## that mark by a tick a frame at most. `frame_ticks` is the frame's ticks
	## (NetSync.STEP), `now_ms` the clock the session is polled on.
	func playout(frame_ticks: int, now_ms: float, elapsed_ms := -1.0) -> void:
		if not (adaptive_playout and by_clock) or arrivals.size() < 8 or latest < 0 or game == null:
			view_at = -1.0
			_clock = -1.0
			var extra := 1 if backlog() > PLAYOUT_LEAST + 2 else 0
			_catch_up(maxi(1, frame_ticks) + extra, PLAYOUT_LEAST)
			return
		if smooth_clock:
			_paced(frame_ticks, now_ms, elapsed_ms)
			return
		view_at = -1.0
		var target := _host_tick_at(now_ms) - ceili(playout_depth(now_ms) - 1e-4)
		# A tick more than the frame's while behind the mark, none while ahead;
		# far back (a stall) it catches up at once (_catch_up).
		var most := clampi(target - game_tick, 0, frame_ticks + 1)
		_catch_up(most, maxi(0, head() - target))

	## The copy played on by the render clock (_view_clock): stepped to the
	## tick at or just past the time this frame shows, so NetBlend can draw
	## everyone between that tick and the one before by the fraction. The
	## clock runs with the frame's time and eases toward the host's tick less
	## the depth, so a late snapshot, a quicker arrival or a deeper playout
	## bends its pace a little instead of freezing or hurrying everyone.
	func _paced(frame_ticks: int, now_ms: float, elapsed_ms: float) -> void:
		var at := _view_clock(now_ms, elapsed_ms)
		var target := ceili(at - 1e-4)
		var most := clampi(target - game_tick, 0, frame_ticks + 2)
		_catch_up(most, maxi(0, head() - target))
		view_at = at
		if game_tick < target:
			short += 1

	## The tick this frame shows (with its fraction).
	func _view_clock(now_ms: float, elapsed_ms: float) -> float:
		var step_ms := STEP * 1000.0
		var depth := playout_depth(now_ms)
		var want := (now_ms - _quickest) / step_ms - depth
		if _clock < 0.0 or _clock_ms < 0.0 or absf(want - _clock) > CLOCK_SNAP:
			_clock = want
		else:
			var passed := (
				maxf(0.0, elapsed_ms if elapsed_ms >= 0.0 else now_ms - _clock_ms) / step_ms
			)
			var off := want - (_clock + passed)
			_clock += passed * (1.0 + clampf(off * .1, -CLOCK_SLOW, CLOCK_FAST))
		_clock_ms = now_ms
		return _clock

	## The tick our inputs say this screen shows (the host rewinds our shots
	## to it): the render clock's, rounded, never past the copy's.
	func shown_tick() -> int:
		if view_at < 0.0:
			return game_tick
		return clampi(roundi(view_at), game_tick - 4, game_tick)

	## Ticks the copy is shown behind the host's tick now, in ticks and their
	## fraction (the render clock is not held to whole ticks): how much later
	## than the quickest SPREAD_SHARE of the rows come, and a tick (the copy
	## plays to the tick at or past the clock, so it needs that tick's row);
	## up at once, down after PLAYOUT_EASE seconds, by PLAYOUT_CLOSE ticks a
	## second or faster when far off. The rows' own arrivals hold the 30 a
	## second pairs and the lost snapshots, so one rule serves every rate.
	## (fine_depth off: the pass 12 way, the snapshots' spread rounded up to
	## whole ticks and their gap added, down a tick every 3 s: everyone shown
	## 2 to 8 ticks later than the link needed for half a minute after the
	## match's first seconds or a spike.)
	func playout_depth(now_ms: float) -> float:
		if not fine_depth:
			return _depth_whole(now_ms)
		var step_ms := STEP * 1000.0
		var want := clampf(_spread_ms / step_ms + 1.0 + depth_margin, 1.0, float(PLAYOUT_MOST))
		var passed := clampf(now_ms - _depth_ms, 0.0, 250.0) if _depth_ms >= 0.0 else 0.0
		_depth_ms = now_ms
		if want >= _depth:
			_depth = want
			_lower_since = -1.0
		elif _lower_since < 0.0:
			_lower_since = now_ms
		elif now_ms - _lower_since > PLAYOUT_EASE * 1000.0:
			var close := maxf(PLAYOUT_CLOSE, (_depth - want) * PLAYOUT_CLOSE_SHARE)
			_depth = maxf(want, _depth - close * passed / 1000.0)
		return _depth

	## The pass 12 depth: whole ticks, the newest snapshots' arrivals.
	func _depth_whole(now_ms: float) -> float:
		var sorted := arrivals.duplicate()
		sorted.sort()
		var spread := sorted[int(sorted.size() * .95)] - sorted[0]
		_quickest = sorted[0]
		var gap := 2
		if snaps.size() >= 2 and snaps.has(latest - 1):
			var before: int = snaps[latest - 1][0]
			gap = maxi(1, latest_tick - before)
		var whole := clampi(ceili(spread / (STEP * 1000.0)) + gap, PLAYOUT_LEAST, PLAYOUT_MOST)
		if whole >= _depth:
			_depth = whole
			_lower_since = -1.0
		elif _lower_since < 0.0:
			_lower_since = now_ms
		elif now_ms - _lower_since > 3000.0:
			_depth -= 1.0
			_lower_since = now_ms
		return _depth

	## The quickest arrival lately and the rows' spread over it (fine_depth).
	## More spread than the deepest playout covers (the link got slower and
	## its quick arrivals of the last seconds are gone for good, or a long
	## stall): the clock goes by the slower ones, so it does not run ahead of
	## every snapshot and hold everyone still until the quick ones leave.
	func _measure() -> void:
		var sorted := arrivals.duplicate()
		sorted.sort()
		var late := sorted[mini(sorted.size() - 1, int(sorted.size() * spread_share))]
		_quickest = sorted[0]
		_spread_ms = late - sorted[0]
		var most_ms := (PLAYOUT_MOST - 1) * STEP * 1000.0
		if _spread_ms > most_ms:
			_quickest = late - most_ms
			_spread_ms = most_ms

	## The playout depth as it stands (ticks; for net_feel.gd).
	func depth_ticks() -> float:
		return _depth

	## The host's tick at `now_ms`, from the quickest arrival lately.
	func _host_tick_at(now_ms: float) -> int:
		var quickest := arrivals[0]
		for a in arrivals:
			quickest = minf(quickest, a)
		return floori((now_ms - quickest) / (STEP * 1000.0))

	## The rows to `tick` came now (a snapshot's or its first part's): their
	## arrival is noted (only the newest).
	func _arrived(tick: int) -> void:
		if tick <= _arrival_tick or (not rows_ahead and tick <= latest_tick):
			return
		var first := tick
		if fine_depth and _arrival_tick >= 0:
			# Every tick whose row this brought (at most half a second's).
			first = maxi(_arrival_tick + 1, tick - 30)
		_arrival_tick = tick
		for t in range(first, tick + 1):
			arrivals.append(_now - t * STEP * 1000.0)
			_arrived_ms.append(_now)
		var kept := ARRIVALS if fine_depth else 90
		var drop := 0
		while (
			drop < arrivals.size() - 8
			and (
				arrivals.size() - drop > kept
				or (fine_depth and _now - _arrived_ms[drop] > ARRIVAL_SECONDS * 1000.0)
			)
		):
			drop += 1
		if drop > 0:
			arrivals = arrivals.slice(drop)
			_arrived_ms = _arrived_ms.slice(drop)
		if fine_depth:
			_measure()

	## Sends this tick's input (and every one not confirmed yet).
	func send_input(c: Game.Controls) -> void:
		if slot < 0:
			return
		var bytes := NetWire.pack_controls(c)
		unacked[input_seq] = bytes
		sent[input_seq] = bytes
		sent.erase(input_seq - SENT_KEEP)
		sent_at[input_seq] = _now
		input_seq += 1
		var first := input_seq - 1
		while first > 0 and unacked.has(first - 1) and input_seq - first < NetWire.REDUNDANT:
			first -= 1
		var list: Array = []
		for i in range(first, input_seq):
			list.append(unacked[i])
		session.send(
			NetSession.HOST_ID,
			NetSession.CH_INPUTS,
			NetWire.inputs(latest, first, list, shown_tick())
		)

	## The turn and look of our inputs the copy has not played yet (sent, or
	## played by the host after the tick the copy is at): added to the view so
	## the aim answers the mouse at once, whatever the lag.
	func unplayed_aim() -> Vector2:
		var played := input_ack - maxi(0, input_ack_tick - game_tick) if input_ack >= 0 else -1
		var out := Vector2.ZERO
		for n in range(maxi(played + 1, input_seq - SENT_KEEP), input_seq):
			var bytes: PackedByteArray = sent.get(n, PackedByteArray())
			if bytes.size() >= NetWire.CONTROL_BYTES:
				out.x += bytes.decode_half(4)
				out.y += bytes.decode_half(6)
		return out

	## Our inputs the copy has not played yet, oldest first: what
	## net_predict.gd walks our player on with. First what the host played
	## for us on each tick past the copy's (the echoed rows: a late input
	## held again, inputs merged after a stall, exactly), then ours it has not
	## played by the newest snapshot. Without those rows (or with
	## predict_from_echo off, the old way) our inputs after a guess at the
	## one the copy's tick had, which a held or merged input put a tick or
	## more out: the drawn player jumped when the copy caught up.
	func unplayed_inputs() -> Array:
		if predict_from_echo and input_ack >= 0 and input_ack_tick >= game_tick:
			var exact: Array = []
			for t in range(game_tick + 1, input_ack_tick + 1):
				var row: Variant = echo.get(t)
				var row_dict: Dictionary = {} if row == null else row
				if not row_dict.has(slot):
					exact = []
					break
				var mine: PackedByteArray = row_dict[slot]
				exact.append(NetWire.unpack_controls(mine))
			if exact.size() == input_ack_tick - game_tick:
				for n in range(maxi(input_ack + 1, input_seq - SENT_KEEP), input_seq):
					var bytes: PackedByteArray = sent.get(n, PackedByteArray())
					if bytes.size() >= NetWire.CONTROL_BYTES:
						exact.append(NetWire.unpack_controls(bytes))
				return exact
		var played := input_ack - maxi(0, input_ack_tick - game_tick) if input_ack >= 0 else -1
		var out: Array = []
		for n in range(maxi(played + 1, input_seq - SENT_KEEP), input_seq):
			var bytes: PackedByteArray = sent.get(n, PackedByteArray())
			if bytes.size() >= NetWire.CONTROL_BYTES:
				out.append(NetWire.unpack_controls(bytes))
		return out

	func _snap(msg: Dictionary) -> void:
		if msg.is_empty():
			return
		var seq: int = msg["seq"]
		_take_rows(msg)
		if not rows_ahead:
			var arrived_tick: int = msg["tick"]
			_arrived(arrived_tick)
		if seq <= latest:
			stale += 1
			return
		var base: int = msg["base"]
		var data := {}
		if base < 0:
			var payload: PackedByteArray = msg["payload"]
			data = GameSnapshot.from_bytes(payload)
		elif snaps.has(base):
			var base_data: Dictionary = snaps[base][1]
			var payload: PackedByteArray = msg["payload"]
			data = GameSnapshot.patch(base_data, GameSnapshot.from_bytes(payload))
		else:
			no_base += 1
			return
		var tick: int = msg["tick"]
		snaps[seq] = [tick, data]
		_forget_before(seq - KEEP + 1)
		if keep_rebuilt:
			rebuilt[seq] = data
		latest = seq
		latest_tick = tick
		var ack: int = msg["input_ack"]
		if ack >= 0 and (not rows_ahead or tick > input_ack_tick):
			_acked(ack, tick)
		if APPLY_RUNNING and game != null:
			GameSnapshot.apply(game, data)
			game_tick = tick
			_after_apply()

	## Lets go of every snapshot before `seq`. (Only `seq - KEEP` itself went
	## until pass 12: one that came after a lost one stayed for ever, about
	## one in fifty with 2% loss, each holding its whole game; net_soak_all.)
	func _forget_before(seq: int) -> void:
		for old: int in snaps.keys():
			if old < seq:
				snaps.erase(old)

	func _catch_up(most := 1 << 30, behind := 0) -> void:
		if latest < 0:
			return
		if game == null or (not REBUILD_RUNNING and latest_tick - rebuilt_at >= REBUILD_EVERY):
			_rebuild()
			return
		var top := head()
		if top - game_tick > behind + 12:
			behind = 0  # far back: catch up at once
			most = 1 << 30
		var steps := 0
		while game_tick < top - behind and steps < most:
			steps += 1
			var row: Variant = echo.get(game_tick + 1)
			var row_dict: Dictionary = {} if row == null else row
			if row_dict.is_empty():
				if _rows_late() or latest_tick <= game_tick:
					# (No whole snapshot past the copy to put it on yet.)
					return
				# The inputs for the next tick never came (lost past the
				# redundancy): start again from the newest snapshot.
				if game_tick >= 0:
					rebuilds_lost += 1
				_rebuild()
				return
			var given := {}
			for s: Variant in row_dict:
				var s_slot: int = s
				var s_bytes: PackedByteArray = row_dict[s]
				if s_slot >= NetWire.EVENT_SLOT:
					NetSync.play_event(game, NetWire.event_of(s_bytes))
					events_played += 1
					continue
				given[s_slot] = NetWire.unpack_controls(s_bytes)
			game.tick(STEP, given)
			echo.erase(game_tick)
			game_tick += 1
			if game_tick - checked_at >= (CHECK_PART_EVERY if spread_check else CHECK_EVERY):
				if not _check_at(game_tick):
					return

	## The next tick's inputs are missing but may still be on their way: a
	## snapshot that carried them passed by a newer one (jitter reorders the
	## unreliable ones; the newest repeats only the last few snapshots'
	## rows). The copy waits for them (a frozen frame or two) while the
	## newest snapshot is under ROWS_WAIT ticks ahead; it was put back on the
	## newest at once, a jump of the whole world: 3 to 11 times in 20 s in
	## co-op at 250 ms, 44 at 60 snapshots a second (net_feel.gd).
	func _rows_late() -> bool:
		if not wait_rows or game_tick < 0 or head() - game_tick > ROWS_WAIT:
			return false
		rows_waited += 1
		return true

	## Compares the copy with the snapshot of the tick it is at, if one is
	## kept; false when they parted (the copy is then put back on the newest).
	func _check_at(tick: int) -> bool:
		for seq: Variant in snaps:
			var seq_tick: int = snaps[seq][0]
			if seq_tick != tick:
				continue
			checked_at = tick
			checks += 1
			var seq_data: Dictionary = snaps[seq][1]
			var where := ""
			if spread_check:
				where = NetCheckParts.compare(game, seq_data, check_part, near)
				check_part += 1
			else:
				where = GameSnapshot.first_difference(
					NetSync.comparable(seq_data),
					NetSync.comparable(NetSync.capture(game)),
					"",
					near
				)
			if where != "":
				mismatches += 1
				if first_mismatch == "":
					first_mismatch = "tick %d: %s" % [tick, where]
				if mismatch_log.size() < MISMATCH_LOG:
					mismatch_log.append("tick %d: %s" % [tick, where])
				if REBUILD_RUNNING:
					_rebuild(false)
					return false
			return true
		return true

	## The host's place rows from tick `first` on, kept while a rewind may
	## reach back to them.
	func _take_places(first: int, rows: Array) -> void:
		for i in rows.size():
			if first + i > game_tick - GameState.REWIND_KEEP:
				places[first + i] = rows[i]
		for t: int in places.keys():
			if t <= game_tick - GameState.REWIND_KEEP:
				places.erase(t)

	## After a put back that moved the copy from `was_tick` to game_tick: its
	## place log as the host had it (rows it skipped from the host's, the rest
	## its own where none came), so a rewound shot in the next second plays
	## as the host's did.
	func _put_places(own: Array[PackedFloat32Array], was_tick: int) -> void:
		if game.players.size() < 2:
			return
		var out: Array[PackedFloat32Array] = []
		var last := PackedFloat32Array()
		for t in range(game_tick - GameState.REWIND_KEEP + 1, game_tick + 1):
			var row: PackedFloat32Array = places.get(t, PackedFloat32Array())
			if row.is_empty():
				var i := own.size() - 1 - (was_tick - t)
				if i >= 0 and i < own.size() and t <= was_tick:
					row = own[i]
			if row.is_empty():
				row = last
			if not row.is_empty():
				out.append(row)
				last = row
		game.place_log = out

	func _rebuild(check := true) -> void:
		var own: Array[PackedFloat32Array] = []
		if game != null:
			own = game.place_log
		var was_tick := game_tick
		var data: Dictionary = snaps[latest][1]
		if REBUILD_RUNNING and game != null:
			if not GameSnapshot.apply(game, data.duplicate(true)):
				return
		else:
			var fresh: Game = make_game.call(level)
			if fresh == null or not GameSnapshot.apply(fresh, data.duplicate(true)):
				return
			game = fresh
		rebuilds += 1
		game_tick = latest_tick
		rebuilt_at = latest_tick
		_put_places(own, was_tick)
		for t: Variant in echo.keys():
			var t_tick: int = t
			if t_tick <= game_tick:
				echo.erase(t)
		_after_apply()
		if check:
			_check_at(game_tick)

	func _after_apply() -> void:
		if slot >= 0 and slot < game.players.size():
			Players.set_local(game, game.players[slot])

	## This machine's player in the copy (null before the first snapshot).
	func me() -> Player:
		if game == null or slot < 0 or slot >= game.players.size():
			return null
		return game.players[slot]
