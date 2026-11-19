## How smooth an online game looks, frame by frame, against the same scene
## single-player. One client is drawn the way main.gd draws it (its real
## advance(), net_draw_begin() and net_draw_end(), at a screen's frame rate
## with a little frame-time wobble), the others are bots on their own
## copies, over 127.0.0.1 ENet with latency, jitter and loss on both sides.
## Scenes: a 5v5 round on an always-open lobby (`5v5`), online deathmatch
## (`dm`), campaign co-op hosted from a lobby (`coop`; `host` draws the
## host's own view, main.gd hosting it), County Run co-op (`county`); each
## also played single-player (SP), the bar.
##
## Per frame it records what the screen shows: our eye (place and turn),
## every other player and hand near us, our gun's flash and the crosshair's
## hit mark, the correction offset drawn. From that:
##
## - VIEW, OTHERS: frames a moving thing held still (frozen), stepped more
##   than 1.75 times its local pace (a burst, the catch-up after a freeze),
##   off its local pace by over 35% (uneven), the mean of that (jerk), and
##   snaps (a step over .3 cells and four times the pace: a correction seen).
##   The local pace is its mean step over the 7 frames round it.
## - DELAY: key to screen for a move and a turn (the bot is stopped for a few
##   frames now and then and let go), the trigger to the gun's flash and to
##   the hit mark, and an input's round trip to the host's word.
##
##   godot --headless --path godot --script res://tools/net_feel.gd
##       [-- scenes=5v5,dm,coop,host,county] [lags=50,120,250] [hz=144]
##       [seconds=20] [ways=old,new] [jitter=0.2] [loss=0.02] [quick]
##
## `ways`: old turns this track's fixes off (NetBlend, NetPredict.between,
## mates_ahead and holds_aware, NetOwnShots, NetSync.Client.smooth_clock,
## NetPlay.county_by_clock), so both run on one build; noblend, noahead,
## noclock, nomates, noholds turn one off; v390 is old with the server's
## side of pass 12 off too (v3.9.0 as it was). `snaps=N`: a snapshot every
## N ticks. quick (check_all): the 5v5 as a client and co-op as its host, at
## 120 ms for 10 s, new only, held to QUICK_LIMITS. Prints NET FEEL OK.
extends SceneTree

const NetPorts := preload("res://tools/net_ports.gd")
const ModeBot := preload("res://tools/mode_bot.gd")
const CountyBot := preload("res://tools/county_bot.gd")
const Kit := preload("res://tools/net_feel_kit.gd")
const STEP_MS := NetSync.STEP * 1000.0
## The bot is stopped for PROBE_STILL frames every PROBE_EVERY (key to screen).
const PROBE_EVERY := 180
const PROBE_STILL := 6
## Slower than this (cells a second; radians a second for the turn) is not moving.
const MOVE_MIN := .4
const TURN_MIN := .3
## Others farther from us than this are not looked at.
const NEAR := 24.0
## The quick part's limits (120 ms + 24 jitter + 2% loss, 144 Hz; v3.9.0 had
## 55-60% frozen frames and 100-115% jerk on both, single-player 17% and 35%).
const QUICK_LIMITS := {
	"view_frozen": .02,
	"view_jerk": .12,
	"turn_frozen": .02,
	"others_frozen": .05,
	"others_jerk": .2,
	"view_snaps": 6.0,
}

var failures: Array = []
var main: Control
var now := 0.0
var dice := RandomNumberGenerator.new()
var opts := {
	"scenes": "5v5,dm,coop,host,county",
	"lags": "50,120,250",
	"ways": "new",
	"jitter": .2,
	"loss": .02,
	"seconds": 20.0,
	"hz": 144.0,
}
var quick := false
## The scene played online, for the single-player run of it: its START.
var last_info := {}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "quick":
			quick = true
			continue
		var parts := arg.split("=")
		if parts.size() == 2:
			var key := parts[0]
			opts[key] = parts[1] if key in ["scenes", "lags", "ways"] else float(parts[1])
			if key == "snaps":
				NetPlay.snap_every = int(parts[1])
	if quick:
		opts["scenes"] = "5v5,host"
		opts["lags"] = "120"
		opts["ways"] = "new"
		opts["seconds"] = 10.0
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var tally := CrashLog.tally()
	var checked := {}
	for scene: String in str(opts["scenes"]).split(","):
		var cols: Array = []
		var heads: Array = []
		for lag_text: String in str(opts["lags"]).split(","):
			var lag := float(lag_text)
			for way: String in str(opts["ways"]).split(","):
				_way(way == "old" or way == "v390", way)
				dice.seed = int(opts.get("seed", 7))
				var r := _online(scene, lag, lag * float(opts["jitter"]), float(opts["loss"]))
				_way(false)
				if r.is_empty():
					continue
				cols.append(r)
				heads.append("%d %s" % [lag, way])
				if way == "new" and lag == 120.0:
					checked[scene] = r
		if not last_info.is_empty() and not quick:
			dice.seed = int(opts.get("seed", 7))
			var sp := _single(scene)
			if not sp.is_empty():
				cols.insert(0, sp)
				heads.insert(0, "SP")
		print("")
		print("  %s at %d Hz, %d s each" % [scene, opts["hz"], opts["seconds"]])
		_table(heads, cols)
	tally.stop()
	print("")
	_check(
		tally.errors == 0,
		(
			"no script or engine errors"
			+ ("" if tally.errors == 0 else " (%d: %s)" % [tally.errors, tally.first_errors[0]])
		)
	)
	if quick:
		for scene: String in ["5v5", "host"]:
			_check(checked.has(scene), "%s at 120 ms played" % scene)
			if not checked.has(scene):
				continue
			var r: Dictionary = checked[scene]
			for key: String in QUICK_LIMITS:
				var most: float = QUICK_LIMITS[key]
				var got: float = r[key]
				_check(got <= most, "%s: %s %.3f <= %.3f" % [scene, key, got, most])
			_check(r["parted"] == 0, "%s: the copy keeps with the host (%d)" % [scene, r["parted"]])
	print("")
	print("NET FEEL OK" if failures.is_empty() else "NET FEEL FAILED (%d)" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


## Every pass 12 fix off (old) or on; `noblend`, `noahead`, `noclock` turn
## one off.
static func _way(old: bool, way := "") -> void:
	NetBlend.enabled = not old and way != "noblend"
	NetPredict.between = not old and way != "noahead"
	NetSync.Client.smooth_clock = not old and way != "noclock"
	NetPlay.county_by_clock = not old
	NetPredict.mates_ahead = not old and way != "nomates"
	NetPredict.holds_aware = not old and way != "noholds"
	NetOwnShots.enabled = not old
	NetOwnShots.blasts = not old
	NetHitLooks.enabled = not old
	NetUseLooks.enabled = not old
	NetGunLead.scopes = not old
	NetSync.Client.wait_rows = not old and way != "nowait"
	# v390: the server's side of pass 12 off too (NETSERVER's: net_lag's oldserver).
	LobbyServer.paced = way != "v390"
	NetWire.pack_rows = way != "v390"
	NetSync.Host.split_big = way != "v390"


## A frame's length: the screen's, wobbling a little as real frames do.
func _frame_ms() -> float:
	var base := 1000.0 / float(opts["hz"])
	return clampf(base + dice.randfn(0.0, .25), base * .5, base * 1.5)


# ------------------------------------------------------------------ online


func _make(info: Dictionary) -> Game:
	var made: Game = main.net_match_game(info)
	if made != null:
		made.cheats.god = true
	return made


## One scene online: a server or a host, our client drawn as main.gd draws
## it, `seconds` of play recorded.
func _online(scene: String, lag: float, jitter: float, loss: float) -> Dictionary:
	var rig := _open(scene)
	if rig.is_empty():
		_check(false, "%s: the lobby opens" % scene)
		return {}
	var me_net: NetPlay = rig["me"]
	var started := false
	for w in 4000:
		_frame(rig, null)
		if me_net.phase == "match" and _ready(me_net) and main.game != null:
			started = true
			break
	if not started:
		_check(false, "%s: the match starts" % scene)
		_close(rig)
		return {}
	var sessions: Array = rig["sessions"]
	for s: NetSession in sessions:
		s.lag_ms = lag
		s.jitter_ms = jitter
		s.loss = loss
	# Let the link settle (the playout learns the jitter).
	var rec := Recording.new()
	var settle := 2.0
	var t_end := now + (settle + float(opts["seconds"])) * 1000.0
	var t_rec := now + settle * 1000.0
	while now < t_end:
		_frame(rig, rec if now >= t_rec else null)
	var cs: NetSync.Client = me_net.client_sync
	var out := rec.report()
	if cs == null:
		last_info = {}
	out["confirm_ms"] = Recording.median(cs.lag_samples) if cs != null else 0.0
	out["parted"] = cs.mismatches if cs != null else 0
	out["rebuilds"] = cs.rebuilds if cs != null else 0
	out["rebuilds_lost"] = cs.rebuilds_lost if cs != null else 0
	if cs != null and cs.rebuilds > 2:
		print(
			(
				"    put back %d (inputs lost %d), no base %d, stale %d, waited %d"
				% [cs.rebuilds, cs.rebuilds_lost, cs.no_base, cs.stale, cs.rows_waited]
			)
		)
	out["fire_shown_ms"] = Recording.median(main.net_shots.show_ms)
	if rig.has("kit"):
		var kit: Kit = rig["kit"]
		out["kit_shown"] = 0
		out["kit_missed"] = 0
		for k: String in Kit.PHASES:
			out["kit_shown"] += kit.delays[k].size()
			out["kit_missed"] += kit.missed[k]
			var list: PackedFloat32Array = kit.delays[k]
			out["kit_" + k] = Recording.median(list)
			out["kit_" + k + "_n"] = list.size()
			out["kit_" + k + "_missed"] = kit.missed[k]
	if cs != null:
		last_info = me_net.match_info.duplicate(true)
	_close(rig)
	return out


## Opens the scene's server or host and joins our client (and the others).
func _open(scene: String) -> Dictionary:
	var rig := {"scene": scene, "server": null, "host": null, "others": [], "bots": {}}
	var port := NetPorts.pick("net_feel")
	var people := 2
	var lobby := {}
	match scene:
		"5v5":
			lobby = {"mode": "bomb", "map": "grainyard", "team_size": 5, "rounds": 7}
		"dm":
			lobby = {"mode": "deathmatch", "map": "hickston:boss"}
			people = 3
		"county":
			lobby = {"map": "county_hickston"}
		"coop", "host", "kit":
			people = 1
		_:
			return {}
	if scene == "host":
		# Campaign co-op hosted by this front end: our view is the host's.
		var hosting: NetPlay = null
		for k in 20:
			hosting = NetPlay.host_lobby(
				port + k, "HOST", {"mode": "coop", "map": "hickston"}, false, "127.0.0.1"
			)
			if hosting != null:
				port += k
				break
		if hosting == null:
			return {}
		hosting.make_match = _make
		main.net = hosting
		rig["hosted"] = hosting
	elif scene == "coop" or scene == "kit":
		var host: NetPlay = null
		for k in 20:
			host = NetPlay.host_lobby(
				port + k, "HOST", {"mode": "coop", "map": "hickston"}, false, "127.0.0.1"
			)
			if host != null:
				port += k
				break
		if host == null:
			return {}
		host.make_match = func(info: Dictionary) -> Game:
			var was: NetPlay = main.net
			main.net = host
			var made := _make(info)
			main.net = was
			return made
		rig["host"] = host
		rig["host_bot"] = ModeBot.new()
		rig["host_accum"] = 0.0
	else:
		var server: LobbyServer = null
		for k in 20:
			var room := {"port": port + k, "lobby_name": "FEEL"}
			var config := {"bind": "127.0.0.1", "lobbies": [room]}
			if opts.has("snaps"):
				config["snap_every"] = int(opts["snaps"])
			room.merge(lobby, true)
			server = LobbyServer.new(config, {"difficulty": 1})
			if not server.rooms.is_empty():
				port += k
				break
			server.free()
			server = null
		if server == null:
			return {}
		root.add_child(server)
		server.set_process(false)
		rig["server"] = server
	var nets: Array = []
	for i in people:
		var net := NetPlay.join_lobby("127.0.0.1:%d" % port, "P%d" % i, "")
		net.make_match = _make
		nets.append(net)
		if i == 0 and not rig.has("hosted"):
			main.net = net
		for w in 600:
			if net.phase == "lobby":
				break
			_frame(rig, null, nets)
	var me_net: NetPlay = rig.get("hosted", nets[0])
	rig["me"] = me_net
	rig["others"] = nets if rig.has("hosted") else nets.slice(1)
	rig["accum"] = {}
	for w in 60:
		_frame(rig, null)
	if scene == "host":
		nets[0].ask({"ready": true})
		for w in 120:
			_frame(rig, null)
		var why := me_net.start_match()
		if why != "":
			print("  host: ", why)
	elif scene == "coop" or scene == "kit":
		var host: NetPlay = rig["host"]
		me_net.ask({"ready": true})
		for w in 120:
			_frame(rig, null)
		var why := host.start_match()
		if why != "":
			print("  coop: ", why)
	else:
		for net: NetPlay in rig["others"]:
			net.ask({"ready": true})
		for w in 120:
			_frame(rig, null)
		var why := me_net.start_match()
		if why != "":
			print("  %s: %s" % [scene, why])
	var sessions: Array = []
	for net: NetPlay in nets:
		sessions.append(net.session)
	if rig["server"] != null:
		var server: LobbyServer = rig["server"]
		sessions.append(server.rooms[0].net.session)
	else:
		var host: NetPlay = rig["host"] if rig["host"] != null else rig["hosted"]
		sessions.append(host.session)
	rig["sessions"] = sessions
	return rig


## One frame of the screen: the server or host, the other clients (a tick of
## input when one is due), our client by main.gd's own calls.
func _frame(rig: Dictionary, rec: Recording, joining: Array = []) -> void:
	var dt := _frame_ms()
	now += dt
	if rig["server"] != null:
		var server: LobbyServer = rig["server"]
		server.frame(now, dt / 1000.0)
		var g := server.rooms[0].net.match_game()
		if g != null:
			g.cheats.god = true
	if rig["host"] != null:
		_host_frame(rig, dt)
	var others: Array = rig["others"]
	if not joining.is_empty():
		others = joining if rig.has("hosted") else joining.slice(1)
	var accum: Dictionary = rig.get("accum", {})
	for net: NetPlay in others:
		net.poll(now)
		var a: float = accum.get(net, 0.0) + dt
		while a >= STEP_MS:
			a -= STEP_MS
			if net.phase == "match":
				net.client_input(_other_controls(rig, net))
				net.client_play(1)
		accum[net] = a
	rig["accum"] = accum
	var me_net: NetPlay = rig.get("me", rig.get("hosted"))
	if me_net == null and not joining.is_empty():
		me_net = joining[0]
	if me_net == null:
		return
	me_net.poll(now)
	me_net.take_news()
	for change: Dictionary in me_net.take_changes():
		if change.has("started"):
			main.net_begin_match()
	if me_net.phase != "match" or main.state != "play" or main.game == null:
		OS.delay_msec(1)
		return
	var c := _my_controls(rig, me_net, dt, rec)
	if str(rig["scene"]) == "kit" and rec != null:
		c = _kit_controls(rig, me_net, dt)
	var given := _given(c)
	main.advance(dt / 1000.0, c)
	var aimed: Array = main.net_draw_begin(dt / 1000.0)
	if rig.has("kit") and rec != null and me_net.client_ready():
		var kit: Kit = rig["kit"]
		kit.observe(main.game, main.game.players[me_net.my_slot()], now)
	if rec != null and _ready(me_net):
		var g: Game = main.game
		var mine: int = me_net.my_slot()
		var on := _live(g)
		rec.frame(g, g.players[mine], dt, given, on, main.net_smooth.offset.length())
		rec.gap(main.net_smooth.last_gap, g, g.players[mine])
		var hs: NetSync.Host = _host_sync(rig)
		var cs := me_net.client_sync
		if hs != null and cs != null and on:
			var shown: float = cs.view_at if cs.view_at >= 0.0 else float(cs.game_tick)
			rec.behind.append((hs.tick - shown) * STEP_MS)
	main.net_draw_end(aimed)
	if _ready(me_net):
		var g: Game = main.game
		var bot: Object = rig["bots"].get(me_net)
		if bot != null and g.players[me_net.my_slot()].health > 0:
			g.focus(g.players[me_net.my_slot()])
			bot.call("moved", g)
			g.focus(g.local_player)
	if int(now / STEP_MS) % 2 == 0:
		OS.delay_msec(1)


## The kit scene's controls (net_feel_kit.gd): from our player as this screen
## draws it (led by the prediction and the mouse not sent yet).
func _kit_controls(rig: Dictionary, net: NetPlay, dt: float) -> Game.Controls:
	if not net.client_ready():
		return Game.Controls.new()
	if not rig.has("kit"):
		var made := Kit.new()
		made.slot = net.my_slot()
		rig["kit"] = made
	var kit: Kit = rig["kit"]
	var host: NetPlay = rig["host"]
	var g: Game = main.game
	var me: Player = g.players[net.my_slot()]
	var kept := {}
	for field: String in NetPredict.KEPT:
		kept[field] = me.get(field)
	NetPredict.lead(g, me, net.client_sync.unplayed_inputs())
	me.angle = fposmod(me.angle + main.net_turn, TAU)
	me.pitch = clampf(me.pitch + main.net_look, -53.0, 53.0)
	var c: Game.Controls = kit.controls(host.match_game(), g, me, dt, now)
	NetPredict.restore(me, kept)
	return c


## Our side has the match: a client's copy has its first snapshot, a host its game.
static func _ready(net: NetPlay) -> bool:
	if net.role == NetPlay.Role.HOST:
		return net.host_sync != null
	return net.client_ready()


## The host's game's sync (the lobby server's room, or the co-op host).
static func _host_sync(rig: Dictionary) -> NetSync.Host:
	if rig["server"] != null:
		var server: LobbyServer = rig["server"]
		return server.rooms[0].net.host_sync
	if rig["host"] != null:
		var host: NetPlay = rig["host"]
		return host.host_sync
	if rig.has("hosted"):
		var hosting: NetPlay = rig["hosted"]
		return hosting.host_sync
	return null


## Campaign co-op's host: its player one played by a mode bot, a tick each STEP.
func _host_frame(rig: Dictionary, dt: float) -> void:
	var host: NetPlay = rig["host"]
	host.poll(now)
	host.take_news()
	host.take_changes()
	var a: float = rig["host_accum"] + dt
	while a >= STEP_MS:
		a -= STEP_MS
		var g := host.match_game()
		if g == null or host.phase != "match":
			continue
		g.cheats.god = true
		var bot: Object = rig["host_bot"]
		var own := {0: Game.Controls.new()}
		var p: Player = g.players[0]
		if p.health > 0:
			g.focus(p)
			own[0] = bot.call("steer", g)
		g.focus(g.local_player)
		host.host_tick(own)
		if p.health > 0:
			g.focus(p)
			bot.call("moved", g)
			g.focus(g.local_player)
	rig["host_accum"] = a


## Whether the scene is in play (a 5v5 round live; anything else always).
static func _live(g: Game) -> bool:
	if not Modes.is_tactical(g):
		return true
	var st = Modes.feature(g)
	return st != null and String(st.phase) == "live"


func _bot_for(rig: Dictionary, net: Object, slot: int) -> Object:
	var bots: Dictionary = rig["bots"]
	if not bots.has(net):
		match str(rig["scene"]):
			"5v5":
				bots[net] = TacticalBot.new(slot)
			"county":
				bots[net] = CountyBot.new()
			_:
				var b := ModeBot.new()
				b.as_controls = true
				bots[net] = b
	return bots[net]


## Another person's tick: their bot steers from their copy led by their
## prediction, as a person's screen shows it.
func _other_controls(rig: Dictionary, net: NetPlay) -> Game.Controls:
	var c := Game.Controls.new()
	if not net.client_ready():
		return c
	var copy := net.match_game()
	var me: Player = copy.players[net.my_slot()]
	if me.health > 0:
		var bot: Object = _bot_for(rig, net, net.my_slot())
		var led := NetPredict.lead(copy, me, net.client_sync.unplayed_inputs())
		copy.focus(me)
		c = bot.call("steer", copy)
		bot.call("moved", copy)
		copy.focus(copy.local_player)
		NetPredict.restore(me, led)
	_pick_card(copy, me, c)
	return c


## Our frame's controls: the bot steering from what this screen shows (our
## player led by the prediction and the mouse not sent yet), its turn a
## frame's share of a tick's; stopped now and then for the key-to-screen probe.
func _my_controls(rig: Dictionary, net: NetPlay, dt: float, rec: Recording) -> Game.Controls:
	var c := Game.Controls.new()
	var g: Game = main.game
	var client := net != null and net.role == NetPlay.Role.CLIENT
	if net != null and not _ready(net):
		return c
	var slot: int = net.my_slot() if net != null else TacticalScreens.human
	var me: Player = g.players[slot]
	if me.health > 0:
		var bot: Object = _bot_for(rig, net if net != null else main, slot)
		var kept := {}
		for field: String in NetPredict.KEPT:
			kept[field] = me.get(field)
		if client:
			NetPredict.lead(g, me, net.client_sync.unplayed_inputs())
		if net != null:
			me.angle = fposmod(me.angle + main.net_turn, TAU)
			me.pitch = clampf(me.pitch + main.net_look, -53.0, 53.0)
		else:
			me.angle = fposmod(me.angle + main.pending_turn, TAU)
			me.pitch = clampf(me.pitch + main.pending_look, -53.0, 53.0)
		g.focus(me)
		c = bot.call("steer", g)
		g.focus(g.local_player)
		NetPredict.restore(me, kept)
	_pick_card(g, me, c)
	if Modes.holds(g):
		# A card on offer (County Run): the pointer is free to pick it, the
		# mouse and the keys are off the player, as on a person's screen.
		var picking := Game.Controls.new()
		picking.buy = c.buy
		c = picking
	var k := dt / STEP_MS
	c.turn *= k
	c.look *= k
	var n := rec.frames if rec != null else 0
	if rec != null and n % PROBE_EVERY < PROBE_STILL:
		var still := Game.Controls.new()
		still.buy = c.buy
		return still
	return c


## A copy of the frame's controls as given (advance() puts the ticks' share
## of the turn into the ones it is handed).
static func _given(c: Game.Controls) -> Game.Controls:
	var out := Game.Controls.new()
	out.forward = c.forward
	out.strafe = c.strafe
	out.turn = c.turn
	out.look = c.look
	out.fire = c.fire
	return out


## County Run: the leader picks the card on offer (the world holds till then).
static func _pick_card(g: Game, me: Player, c: Game.Controls) -> void:
	var f = CountyMode.run(g)
	if f == null or f.offer.is_empty() or CountyCoop.leader(g) != me:
		return
	var i := CountyBot.pick(g, f)
	var full: bool = String(f.offer[i]["type"]) == "weapon" and CountyBuild.open_slot(f) < 0
	c.buy = CountyCoop.encode(i, 0 if full else -1)


func _close(rig: Dictionary) -> void:
	main.net_draw_end([])
	main.net_blend.forget()
	main.net_smooth.reset()
	main.net_shots.forget()
	main.net_shots.clear_stats()
	var nets: Array = [rig.get("me")] + rig["others"]
	for net: NetPlay in nets:
		if net != null:
			net.leave()
			net.finish()
	main.net = null
	main.game = null
	main.state = "title"
	if rig["host"] != null:
		var host: NetPlay = rig["host"]
		host.leave()
		host.finish()
	if rig["server"] != null:
		var server: LobbyServer = rig["server"]
		for room in server.rooms:
			room.net.finish()
		server.queue_free()


# ---------------------------------------------------------- single-player


## The same scene played single-player (the online START's level, mode and
## seat, at the game's own 120 ticks), the same bot on our player.
func _single(scene: String) -> Dictionary:
	var info := last_info.duplicate(true)
	main.net = null
	var g: Game = _make(info)
	if g == null:
		return {}
	g.net_role = ""
	var slot: int = info.get("slot", 0)
	if slot >= 0 and slot < g.players.size():
		Players.set_local(g, g.players[slot])
	main.mode_name = ""
	main.play(g)
	var rig := {"scene": scene, "bots": {}}
	var rec := Recording.new()
	var t_end := now + (2.0 + float(opts["seconds"])) * 1000.0
	var t_rec := now + 2000.0
	while now < t_end:
		var dt := _frame_ms()
		now += dt
		var r := rec if now >= t_rec else null
		var c := _my_controls(rig, null, dt, r)
		var given := _given(c)
		main.advance(dt / 1000.0, c)
		if main.game != g:
			break
		var me: Player = g.players[TacticalScreens.human]
		if r != null:
			r.frame(g, me, dt, given, _live(g), 0.0)
		var bot: Object = rig["bots"].get(main)
		if bot != null and me.health > 0:
			g.focus(me)
			bot.call("moved", g)
			g.focus(g.local_player)
	var out := rec.report()
	out["confirm_ms"] = 0.0
	out["parted"] = 0
	out["rebuilds"] = 0
	out["fire_shown_ms"] = 0.0
	main.game = null
	main.pilots.clear()
	main.state = "title"
	return out


# ----------------------------------------------------------------- report


static func _median(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


func _table(heads: Array, cols: Array) -> void:
	if cols.is_empty():
		return
	var head := PackedStringArray()
	for h: String in heads:
		head.append(h.lpad(10))
	print("  %-40s%s" % ["", "".join(head)])
	var rows := [
		["view: frames moving", "%.0f", "view_n", 1.0],
		["view: frozen frames (%)", "%.1f", "view_frozen", 100.0],
		["view: bursts (%)", "%.1f", "view_burst", 100.0],
		["view: uneven frames (%)", "%.1f", "view_uneven", 100.0],
		["view: jerk (mean off pace, %)", "%.1f", "view_jerk", 100.0],
		["view: snaps a minute", "%.1f", "view_snaps", 1.0],
		["view: corrections a minute (>.02 cells)", "%.1f", "gaps_min", 1.0],
		["view: correction p95 (cells)", "%.3f", "gap_p95", 1.0],
		["  with a hand by us (%)", "%.0f", "gap_enemy", 100.0],
		["  with another player by us (%)", "%.0f", "gap_mate", 100.0],
		["view: correction drawn (mean cells)", "%.3f", "offset", 1.0],
		["turn: frames turning", "%.0f", "turn_n", 1.0],
		["turn: held frames (%)", "%.1f", "turn_frozen", 100.0],
		["turn: doubled frames (%)", "%.1f", "turn_burst", 100.0],
		["turn: off the mouse (%)", "%.1f", "turn_uneven", 100.0],
		["turn: jerk (%)", "%.1f", "turn_jerk", 100.0],
		["others: frames moving", "%.0f", "others_n", 1.0],
		["others: frozen frames (%)", "%.1f", "others_frozen", 100.0],
		["others: bursts (%)", "%.1f", "others_burst", 100.0],
		["others: uneven frames (%)", "%.1f", "others_uneven", 100.0],
		["others: jerk (%)", "%.1f", "others_jerk", 100.0],
		["others: snaps a 1000 frames", "%.2f", "others_snaps", 1.0],
		["others: drawn behind the host (ms)", "%.0f", "behind_ms", 1.0],
		["delay: key to a move shown (ms)", "%.1f", "move_ms", 1.0],
		["delay: mouse to a turn shown (ms)", "%.1f", "turn_ms", 1.0],
		["own shots: flashes drawn", "%.0f", "shots", 1.0],
		["own shots: button to flash, shown (ms)", "%.1f", "fire_shown_ms", 1.0],
		["hit marks drawn", "%.0f", "marks", 1.0],
		["hit marks: with the shot's frame (%)", "%.0f", "marks_at_once", 100.0],
		["hit marks: shot to mark, median (ms)", "%.1f", "mark_ms", 1.0],
		["kit: ALT FIRE to the scope up (ms)", "%.0f", "kit_scope", 1.0],
		["kit: a bolt's blast, past its flight (ms)", "%.0f", "kit_bolt", 1.0],
		["kit: USE to the door moving (ms)", "%.0f", "kit_door", 1.0],
		["kit: a shot to the hand's flinch (ms)", "%.0f", "kit_flinch", 1.0],
		["kit: a stick's blast, past its fuse (ms)", "%.0f", "kit_tnt", 1.0],
		["  kit presses shown / missed", "%.0f", "kit_shown", 1.0],
		["", "%.0f", "kit_missed", 1.0],
		["delay: input to the host's word (ms)", "%.0f", "confirm_ms", 1.0],
		["copy: put back / parted", "%.0f", "rebuilds", 1.0],
		["", "%.0f", "parted", 1.0],
	]
	for row: Array in rows:
		var cells := PackedStringArray()
		for c: Dictionary in cols:
			cells.append((str(row[1]) % (float(c.get(row[2], 0.0)) * float(row[3]))).lpad(10))
		print("  %-40s%s" % [row[0], "".join(cells)])


## What the screen showed, frame by frame, and the numbers made of it.
class Recording:
	extends RefCounted
	var frames := 0
	var dts := PackedFloat32Array()
	var eye := PackedVector2Array()
	var turn := PackedFloat32Array()
	## The mouse's turn given each frame.
	var turn_in := PackedFloat32Array()
	var offsets := PackedFloat32Array()
	var gaps := PackedFloat32Array()
	## How far behind the host's tick now the others were drawn (ms).
	var behind := PackedFloat32Array()
	var gap_by_enemy := 0
	var gap_by_mate := 0
	var on := []
	## key -> [frame indices, places]
	var tracks := {}
	var move_ms := PackedFloat32Array()
	var turn_ms := PackedFloat32Array()
	var mark_ms := PackedFloat32Array()
	var _t := 0.0
	var shots := 0
	var _probe_at := -1.0
	var _probe_moved := false
	var _probe_turned := false
	var _probe_from := Vector2.ZERO
	var _probe_angle := 0.0
	var _fire_at := -1.0
	var _flash_was := 0.0
	var _mark_was := false

	func frame(g: Game, me: Player, dt: float, c: Game.Controls, live: bool, offset: float) -> void:
		var i := frames
		frames += 1
		_t += dt
		dts.append(dt)
		eye.append(Vector2(me.x, me.y))
		turn.append(me.angle)
		turn_in.append(c.turn)
		offsets.append(offset)
		on.append(live and me.health > 0)
		if not (live and me.health > 0):
			return
		# Key to screen: the frame the probe lets the bot go.
		if i % PROBE_EVERY == PROBE_STILL:
			_probe_at = _t - dt
			# From last frame's picture: a move shown this very frame is 0 ms.
			_probe_from = eye[i - 1] if i > 0 else Vector2(me.x, me.y)
			_probe_angle = turn[i - 1] if i > 0 else me.angle
			_probe_moved = c.forward == 0.0 and c.strafe == 0.0
			_probe_turned = absf(c.turn) < 1e-6
		if _probe_at >= 0.0:
			if not _probe_moved and Vector2(me.x, me.y).distance_to(_probe_from) > 1e-4:
				move_ms.append(_t - dt - _probe_at)
				_probe_moved = true
			if not _probe_turned and absf(angle_difference(_probe_angle, me.angle)) > 1e-5:
				turn_ms.append(_t - dt - _probe_at)
				_probe_turned = true
			if _t - _probe_at > 400.0:
				_probe_at = -1.0
		# Our shots as drawn (the flash coming up) and the hit mark after one.
		var flash: float = g.armory.flash
		if flash > _flash_was + .01:
			shots += 1
			_fire_at = _t - dt
		_flash_was = flash
		var mark := g.clock < g.hit_mark_until
		if mark and not _mark_was and _fire_at >= 0.0 and _t - dt - _fire_at < 600.0:
			mark_ms.append(_t - dt - _fire_at)
		_mark_was = mark
		# Everyone else near us, as drawn.
		for q: Player in g.players:
			if q != me and q.health > 0 and not q.away:
				_note("p%d" % q.slot, i, Vector2(q.x, q.y), me)
		for e: Enemy in g.enemies:
			if e.alive and e.uid > 0:
				_note("e%d" % e.uid, i, Vector2(e.x, e.y), me)

	## The prediction's correction this frame (before the easing).
	func gap(cells: float, g: Game, me: Player) -> void:
		if cells <= .02:
			return
		gaps.append(cells)
		var near_enemy := 99.0
		for e: Enemy in g.enemies:
			if e.alive and e.hostile:
				near_enemy = minf(near_enemy, Vector2(e.x - me.x, e.y - me.y).length())
		var near_mate := 99.0
		for q: Player in g.players:
			if q != me and q.health > 0:
				near_mate = minf(near_mate, Vector2(q.x - me.x, q.y - me.y).length())
		if near_enemy < 1.6:
			gap_by_enemy += 1
		elif near_mate < 1.2:
			gap_by_mate += 1

	func _note(key: String, i: int, at: Vector2, me: Player) -> void:
		if absf(at.x - me.x) + absf(at.y - me.y) > NEAR:
			return
		if not tracks.has(key):
			tracks[key] = [PackedInt32Array(), PackedVector2Array()]
		var t: Array = tracks[key]
		var idx: PackedInt32Array = t[0]
		var pts: PackedVector2Array = t[1]
		idx.append(i)
		pts.append(at)
		t[0] = idx
		t[1] = pts

	func report() -> Dictionary:
		var out := {}
		var idx := PackedInt32Array()
		var steps := PackedFloat32Array()
		var angle_steps := PackedFloat32Array()
		for i in range(1, frames):
			if on[i] and on[i - 1]:
				idx.append(i)
				steps.append(eye[i].distance_to(eye[i - 1]))
				angle_steps.append(absf(angle_difference(turn[i - 1], turn[i])))
		_put(out, "view", _even(idx, steps, MOVE_MIN, frames))
		_put(out, "turn", _against(idx, angle_steps))
		var all := {"n": 0, "frozen": 0, "burst": 0, "uneven": 0, "jerk": 0.0, "snaps": 0}
		for key: String in tracks:
			var t: Array = tracks[key]
			var ti: PackedInt32Array = t[0]
			var tp: PackedVector2Array = t[1]
			var si := PackedInt32Array()
			var ss := PackedFloat32Array()
			for k in range(1, ti.size()):
				if ti[k] == ti[k - 1] + 1:
					si.append(ti[k])
					ss.append(tp[k].distance_to(tp[k - 1]))
			var r := _even(si, ss, MOVE_MIN, -1)
			for f: String in ["n", "frozen", "burst", "uneven", "snaps"]:
				all[f] = int(all[f]) + int(r["count_" + f])
			all["jerk"] = float(all["jerk"]) + float(r["sum_jerk"])
		var n := maxi(1, int(all["n"]))
		out["others_n"] = all["n"]
		out["others_frozen"] = float(all["frozen"]) / n
		out["others_burst"] = float(all["burst"]) / n
		out["others_uneven"] = float(all["uneven"]) / n
		out["others_jerk"] = float(all["jerk"]) / n
		out["others_snaps"] = float(all["snaps"]) * 1000.0 / n
		var sum := 0.0
		for o in offsets:
			sum += o
		out["offset"] = sum / maxf(1.0, offsets.size())
		out["behind_ms"] = Recording.median(behind)
		out["gaps_min"] = gaps.size() / maxf(1e-3, _t / 60000.0)
		out["gap_enemy"] = gap_by_enemy / maxf(1.0, gaps.size())
		out["gap_mate"] = gap_by_mate / maxf(1.0, gaps.size())
		var g := gaps.duplicate()
		g.sort()
		out["gap_p95"] = g[int(g.size() * .95)] if not g.is_empty() else 0.0
		out["move_ms"] = Recording.median(move_ms)
		out["turn_ms"] = Recording.median(turn_ms)
		out["shots"] = shots
		out["mark_ms"] = Recording.median(mark_ms)
		out["marks"] = mark_ms.size()
		var at_once := 0
		for ms in mark_ms:
			if ms < 20.0:
				at_once += 1
		out["marks_at_once"] = at_once / maxf(1.0, mark_ms.size())
		return out

	func _put(out: Dictionary, name: String, r: Dictionary) -> void:
		var n := maxi(1, int(r["count_n"]))
		out[name + "_n"] = r["count_n"]
		out[name + "_frozen"] = float(r["count_frozen"]) / n
		out[name + "_burst"] = float(r["count_burst"]) / n
		out[name + "_uneven"] = float(r["count_uneven"]) / n
		out[name + "_jerk"] = float(r["sum_jerk"]) / n
		var minutes := maxf(1e-3, _t / 60000.0)
		out[name + "_snaps"] = float(r["count_snaps"]) / minutes

	## The view's turn each frame against the mouse's turn that frame: held
	## (under a quarter of it), off (by over 35%), and the mean of that.
	func _against(idx: PackedInt32Array, steps: PackedFloat32Array) -> Dictionary:
		var r := {
			"count_n": 0,
			"count_frozen": 0,
			"count_burst": 0,
			"count_uneven": 0,
			"count_snaps": 0,
			"sum_jerk": 0.0
		}
		for k in idx.size():
			var given := absf(turn_in[idx[k]])
			if given < 1e-4:
				continue
			var d := steps[k]
			r["count_n"] += 1
			if d < .25 * given:
				r["count_frozen"] += 1
			if d > 1.75 * given:
				r["count_burst"] += 1
			if absf(d - given) > .35 * given:
				r["count_uneven"] += 1
			r["sum_jerk"] += minf(4.0, absf(d - given) / given)
		return r

	## Steps `steps` taken on frames `idx` (consecutive runs), each against
	## the mean pace of the 7 frames round it.
	func _even(
		idx: PackedInt32Array, steps: PackedFloat32Array, least: float, _f: int
	) -> Dictionary:
		var r := {
			"count_n": 0,
			"count_frozen": 0,
			"count_burst": 0,
			"count_uneven": 0,
			"count_snaps": 0,
			"sum_jerk": 0.0
		}
		for k in range(3, idx.size() - 3):
			if idx[k + 3] - idx[k - 3] != 6:
				continue
			var d := steps[k]
			if d > 2.5:
				continue
			var span := 0.0
			var time := 0.0
			for j in range(k - 3, k + 4):
				span += steps[j]
				time += dts[idx[j]]
			var pace := span / time
			if pace * 1000.0 < least:
				continue
			var e := pace * dts[idx[k]]
			r["count_n"] += 1
			if d < .25 * e:
				r["count_frozen"] += 1
			if d > 1.75 * e:
				r["count_burst"] += 1
			if absf(d - e) > .35 * e:
				r["count_uneven"] += 1
			if d > .3 and d > 4.0 * e:
				r["count_snaps"] += 1
			r["sum_jerk"] += minf(4.0, absf(d - e) / e)
		return r

	static func median(values: PackedFloat32Array) -> float:
		if values.is_empty():
			return 0.0
		var sorted := values.duplicate()
		sorted.sort()
		return sorted[sorted.size() / 2]
