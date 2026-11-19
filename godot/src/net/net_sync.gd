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
## Ticks a client's shots are rewound by at most (game.gd keeps REWIND_KEEP).
const MAX_REWIND := 64
## Parts of a snapshot's save that follow the local player (presentation).
const LOCAL_ONLY := ["visited"]


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
	## input number -> the tick it was showing when it sent that one.
	var views := {}


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
	## Snapshots' worth of inputs sent again (a lost snapshot's are in the
	## next ones). Every row since the client's acknowledged base used to go
	## in each snapshot: a round trip's worth, the biggest part of a 5v5's
	## bandwidth.
	const ECHO_AGAIN := 3
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
	## peer id -> Remote
	var remotes := {}
	## Joins a player for a new client and returns its slot (-1: no room).
	var seat: Callable
	## Judge clients' shots where their screens showed the others (off: as
	## the host stands them).
	var rewind := true
	var sizes_full := PackedInt32Array()
	var sizes_delta := PackedInt32Array()
	var capture_us := 0
	var delta_us := 0
	var tick_us := 0
	## base seq -> what changed from it to the newest snapshot (_carry_since).
	var _since := {}

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
				bytes = NetWire.with_rewind(bytes, clampi(tick + 1 - view, 0, MAX_REWIND))
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
		for r: Remote in remotes.values():
			if r.acked >= 0:
				oldest = mini(oldest, r.acked)
		var kept := {}
		for base: int in _since:
			if base < oldest or base <= seq - KEEP:
				continue
			var next: Variant = GameSnapshot.merge(_since[base], change)
			if next != null:
				kept[base] = next
		kept[seq] = {}
		_since = kept

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
					var later: PackedByteArray = r.waiting[r.next]
					r.waiting[r.next] = NetWire.merged(dropped, later)
				r.skipped += 1
		if r.waiting.has(r.next):
			r.last = r.waiting[r.next]
			r.waiting.erase(r.next)
			r.played = r.next
			r.next += 1
			return r.last
		r.played = -1
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
		for r: Remote in remotes.values():
			if r.slot < 0:
				continue
			var base := r.acked if history.has(r.acked) and r.acked < seq else -1
			if base < 0 and tick - r.full_at < FULL_GAP:
				continue
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
			var since: int = tick if base < 0 else history[base][0]
			var first := maxi(since + 1, tick - MAX_ECHO + 1)
			if trim_echo and r.echo_sent >= 0 and base >= 0:
				first = maxi(first, r.echo_sent + 1 - ECHO_AGAIN * snap_every)
			r.echo_sent = tick
			var rows: Array = []
			for t in range(first, tick + 1):
				rows.append(played.get(t, PackedByteArray()))
			var snap_bytes: PackedByteArray = by_base[base]
			var packet := NetWire.snap(
				seq, base, tick, r.next - 1 if r.next > 0 else -1, [first, rows], snap_bytes
			)
			session.send(r.id, NetSession.CH_SNAPS, packet)


class Client:
	extends RefCounted
	## Compare the copy with a snapshot every this many ticks.
	const CHECK_EVERY := 60
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
	const KEEP := 32
	## Inputs remembered after they are confirmed (the view's prediction).
	const SENT_KEEP := 120
	## Partings kept in mismatch_log.
	const MISMATCH_LOG := 6
	## Snapshots whose arrival is remembered to judge the link's jitter.
	const ARRIVALS := 90
	## The copy is played at least this far behind the newest snapshot, and
	## at most PLAYOUT_MOST.
	const PLAYOUT_LEAST := 2
	const PLAYOUT_MOST := 14
	## Seconds a lower playout depth must hold before the copy closes up.
	const PLAYOUT_EASE := 3.0
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
	## Paced by the clock (playout); off for COUNTY RUN co-op, whose world
	## holds for the party's card picks and parted from the host when paced so.
	var by_clock := true
	var _depth := PLAYOUT_LEAST
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
				_snap(NetWire.read_snap(bytes))

	## Steps the copy toward the newest snapshot: at most `most` ticks, and no
	## nearer to it than `behind` ticks unless it has fallen far back (then it
	## catches up at once). Played a tick or so a frame, the world moves
	## smoothly between snapshots.
	func play_out(most: int, behind := 0) -> void:
		_catch_up(most, behind)

	## Ticks of the game this copy is behind the newest snapshot.
	func backlog() -> int:
		return latest_tick - game_tick if latest >= 0 else 0

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
		var target := _host_tick_at(now_ms) - playout_depth(now_ms)
		# A tick more than the frame's while behind the mark, none while ahead;
		# far back (a stall) it catches up at once (_catch_up).
		var most := clampi(target - game_tick, 0, frame_ticks + 1)
		_catch_up(most, maxi(0, latest_tick - target))

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
		_catch_up(most, maxi(0, latest_tick - target))
		view_at = at

	## The tick this frame shows (with its fraction).
	func _view_clock(now_ms: float, elapsed_ms: float) -> float:
		var step_ms := STEP * 1000.0
		var quickest := arrivals[0]
		for a in arrivals:
			quickest = minf(quickest, a)
		var want := (now_ms - quickest) / step_ms - playout_depth(now_ms)
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

	## Ticks the copy is shown behind the host's tick now: the snapshots'
	## gap and their arrivals' spread (95th percentile over the quickest),
	## up at once, down only after PLAYOUT_EASE seconds.
	func playout_depth(now_ms: float) -> int:
		var sorted := arrivals.duplicate()
		sorted.sort()
		var spread := sorted[int(sorted.size() * .95)] - sorted[0]
		var gap := 2
		if snaps.size() >= 2 and snaps.has(latest - 1):
			var before: int = snaps[latest - 1][0]
			gap = maxi(1, latest_tick - before)
		var step_ms := STEP * 1000.0
		var want := clampi(ceili(spread / step_ms) + gap, PLAYOUT_LEAST, PLAYOUT_MOST)
		if want >= _depth:
			_depth = want
			_lower_since = -1.0
		elif _lower_since < 0.0:
			_lower_since = now_ms
		elif now_ms - _lower_since > PLAYOUT_EASE * 1000.0:
			_depth -= 1
			_lower_since = now_ms
		return _depth

	## The host's tick at `now_ms`, from the quickest arrival lately.
	func _host_tick_at(now_ms: float) -> int:
		var quickest := arrivals[0]
		for a in arrivals:
			quickest = minf(quickest, a)
		return floori((now_ms - quickest) / (STEP * 1000.0))

	## A snapshot of `tick` came now: its arrival is noted (only the newest).
	func _arrived(tick: int) -> void:
		if tick <= latest_tick:
			return
		arrivals.append(_now - tick * STEP * 1000.0)
		if arrivals.size() > ARRIVALS:
			arrivals.remove_at(0)

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
		if predict_from_echo and input_ack >= 0 and latest_tick >= game_tick:
			var exact: Array = []
			for t in range(game_tick + 1, latest_tick + 1):
				var row: Variant = echo.get(t)
				var row_dict: Dictionary = {} if row == null else row
				if not row_dict.has(slot):
					exact = []
					break
				var mine: PackedByteArray = row_dict[slot]
				exact.append(NetWire.unpack_controls(mine))
			if exact.size() == latest_tick - game_tick:
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
		# The inputs played on each tick are the host's word whatever the
		# snapshot: kept from a late one too (big snapshots go reliable, the
		# rest not, so they can pass each other).
		var first: int = msg["echo_first"]
		var rows: Array = msg["echo"]
		for i in rows.size():
			if not echo.has(first + i) and first + i > game_tick:
				echo[first + i] = rows[i]
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
		snaps.erase(seq - KEEP)
		if keep_rebuilt:
			rebuilt[seq] = data
		latest = seq
		latest_tick = tick
		var ack: int = msg["input_ack"]
		if ack >= 0:
			input_ack = ack
			input_ack_tick = tick
			if sent_at.has(ack):
				var at_ms: float = sent_at[ack]
				lag_samples.append(_now - at_ms)
			for n: Variant in unacked.keys():
				var n_seq: int = n
				if n_seq <= ack:
					unacked.erase(n)
					sent_at.erase(n)
		if APPLY_RUNNING and game != null:
			GameSnapshot.apply(game, data)
			game_tick = tick
			_after_apply()

	func _catch_up(most := 1 << 30, behind := 0) -> void:
		if latest < 0:
			return
		if game == null or (not REBUILD_RUNNING and latest_tick - rebuilt_at >= REBUILD_EVERY):
			_rebuild()
			return
		if latest_tick - game_tick > behind + 12:
			behind = 0  # far back: catch up at once
			most = 1 << 30
		var steps := 0
		while game_tick < latest_tick - behind and steps < most:
			steps += 1
			var row: Variant = echo.get(game_tick + 1)
			var row_dict: Dictionary = {} if row == null else row
			if row_dict.is_empty():
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
				given[s_slot] = NetWire.unpack_controls(s_bytes)
			game.tick(STEP, given)
			echo.erase(game_tick)
			game_tick += 1
			if game_tick - checked_at >= CHECK_EVERY:
				if not _check_at(game_tick):
					return

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
			var where := GameSnapshot.first_difference(
				NetSync.comparable(seq_data), NetSync.comparable(NetSync.capture(game)), "", near
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

	func _rebuild(check := true) -> void:
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
