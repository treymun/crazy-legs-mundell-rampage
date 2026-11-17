## Pictures of the game modes (src/modes/) in a real window (the
## graphics-card view players see): co-op's partner in view with their tag
## and health, the same partner off to the side (the marker at the view's
## edge), a partner down with the revive prompt and its progress, this
## player down while the partner is up; deathmatch in play (an opponent, the
## frags and the clock), fragged, and the results screen; team deathmatch in
## play (a teammate and two opponents: the team colours); the 5v5 bodies close
## up (both sides, one falling) and a hostage; the speedway's lap cars going
## by. <name>.png in out=<dir>; only=coop,deathmatch,team,tactical,race runs
## some of them. only=mundell (not in the default set) lines up co-op
## partners close up, turned every way round and in each pose (Mundell's
## body, the sheets in docs/godot3d/compare/actors/mundell_*.png).
## only=party (not in the default set): the flat pictures of partners down
## (player_down_side, _head, _feet: the view's cels, then the models), the
## kill feed and watching a partner while down, and the lobby's posse.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/mode_frames.gd -- out=<dir> [only=team,race]
##
## Point APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

const NetPorts := preload("res://tools/net_ports.gd")

var main
var out := ""
var only: Array = ["coop", "deathmatch", "team", "tactical", "race"]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
		elif String(arg).begins_with("only="):
			only = Array(String(arg).substr(5).split(","))
	if out == "":
		push_error("out=<dir> is needed")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.touring = true
	Effects.enabled = true
	if only.has("coop"):
		await _coop()
	if only.has("deathmatch"):
		await _deathmatch()
	if only.has("team"):
		await _team()
	if only.has("tactical"):
		await _tactical()
	if only.has("race"):
		await _race()
	if only.has("bench"):
		await _bench()
	if only.has("mundell"):
		await _mundell()
	if only.has("party"):
		await _party()
	print("mode frames written to ", out)
	main.queue_free()
	await process_frame
	quit()


func _game(level_id: String, mode: String, count: int, options := {}) -> Game:
	var g: Game = main.make_game(level_id)
	main.game = g
	main.state = "play"
	g.configure(SessionStore.defaults())
	Modes.setup(g, mode, count, options)
	g.barks.enabled = false
	return g


func _snap(name: String, keep_notice := false) -> void:
	var g: Game = main.game
	if not keep_notice:
		g.message_until = 0.0
	g.barks.until = 0.0
	g.callout_until = 0.0
	g.district_until = 0.0
	main.render()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))


func _ticks(g: Game, n: int, given = null) -> void:
	for i in n:
		g.tick(1.0 / 60.0, given if given != null else Game.Controls.new())


## `b` a few steps ahead of `a` on open ground, `a` looking at them.
func _face(g: Game, a: Player, b: Player, reach := 3.2) -> void:
	for k in 16:
		var ang := a.angle + (k / 2) * .4 * (1.0 if k % 2 == 0 else -1.0)
		var at := Vector2(a.x + cos(ang) * reach, a.y + sin(ang) * reach)
		if not g.world.blocked(at.x, at.y, .35) and g.world.visible(a.x, a.y, at.x, at.y):
			Modes.place(g, b, at.x, at.y, ang + PI + .5)
			a.angle = ang
			return


## `others` spread side by side a few steps ahead of `a`, who looks at them.
func _fan(g: Game, a: Player, others: Array, reach: float) -> void:
	_face(g, a, others[0], reach)
	var ahead := Vector2(cos(a.angle), sin(a.angle))
	var side := Vector2(-ahead.y, ahead.x)
	var mid := Vector2(others[0].x, others[0].y)
	for k in range(1, others.size()):
		var lean := (1.0 if k % 2 == 1 else -1.0) * (.9 + .5 * (k / 2))
		var at := Vector2(a.x, a.y) + ahead * (reach + k * .8) + side * lean
		if not g.world.blocked(at.x, at.y, .35):
			Modes.place(g, others[k], at.x, at.y, a.angle + PI + .4 * k)
		mid += Vector2(others[k].x, others[k].y)
	mid /= others.size()
	a.angle = atan2(mid.y - a.y, mid.x - a.x)


func _coop() -> void:
	var g := _game("hickston", Modes.COOP, 2)
	_ticks(g, 2)
	g.cheats.god = true
	g.spawn_grace = 99.0
	var a: Player = g.players[0]
	var b: Player = g.players[1]
	_face(g, a, b)
	b.health = 64
	b.walk_phase = 1.0
	_ticks(g, 1)
	await _snap("coop_partner")
	a.angle += 1.1
	_ticks(g, 1)
	await _snap("coop_partner_edge")
	a.angle -= 1.1
	g.cheats.god = false
	g.damage(500.0, null, "TEST", b)
	g.cheats.god = true
	_face(g, a, b, 1.25)
	a.pitch = -48.0
	var holding := Game.Controls.new()
	holding.hold = true
	_ticks(g, 95, {0: holding})
	a.pitch = -48.0
	await _snap("coop_revive")
	# This player down, the partner up beside them.
	_ticks(g, int(CoopMode.REVIVE_TIME * 60.0), {0: holding})
	g.cheats.god = false
	g.damage(500.0, null, "TEST", a)
	g.cheats.god = true
	_ticks(g, 40)
	await _snap("coop_down")


func _deathmatch() -> void:
	var g := _game("range", Modes.DEATHMATCH, 2, {"frag_limit": 10})
	_ticks(g, 2)
	var a: Player = g.players[0]
	var b: Player = g.players[1]
	_face(g, a, b, 4.5)
	a.frags = 3
	b.frags = 2
	b.deaths = 3
	a.deaths = 1
	_ticks(g, 1)
	await _snap("dm_play")
	g.features["mode"].blame = 1
	g.damage(500.0, null, "SHOT", a)
	g.features["mode"].blame = -1
	_ticks(g, 30)
	await _snap("dm_fragged")
	_ticks(g, int(DeathmatchMode.RESPAWN_DELAY * 60.0))
	var st = g.features["mode"]
	a.frags = 10
	st.match_over = true
	st.over_clock = 184.0
	g.won = true
	await _snap("dm_results")
	var t := _game("range", Modes.TEAM, 4)
	_ticks(t, 2)
	var frags := [6, 4, 5, 3]
	for p: Player in t.players:
		p.frags = int(frags[p.slot])
		p.deaths = 7 - p.slot
	var ts = t.features["mode"]
	ts.match_over = true
	ts.over_clock = 300.0
	t.won = true
	await _snap("tdm_results")


## Team deathmatch on the range: RED's second player and BLUE's two ahead.
func _team() -> void:
	var g := _game("range", Modes.TEAM, 4)
	_ticks(g, 2)
	var a: Player = g.players[0]
	_fan(g, a, [g.players[1], g.players[2], g.players[3]], 3.0)
	_ticks(g, 1)
	await _snap("tdm_play")


## Frame time with all nine other 5v5 bodies in view (only=bench, not in the
## default set): the median of 240 drawn frames, printed.
func _bench() -> void:
	var g := _game("holler", Modes.BOMB, 10, {"arena": "holler"})
	_ticks(g, 2)
	var a: Player = g.players[0]
	var others: Array = g.players.slice(1)
	_fan(g, a, others, 2.4)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var times: Array = []
	for i in 240:
		var t0 := Time.get_ticks_usec()
		main.render()
		await RenderingServer.frame_post_draw
		times.append(Time.get_ticks_usec() - t0)
	times.sort()
	var shown := 0
	for q: Player in others:
		if g.in_view(q.x, q.y, 1.0):
			shown += 1
	print(
		(
			"BENCH 5v5 bodies in view %d: median %.2f ms, 90th %.2f ms"
			% [shown, times[120] / 1000.0, times[216] / 1000.0]
		)
	)
	await _snap("tac_bench")


## `others` side by side a little ahead of `a` on Hickston's main street,
## `a`'s gun put away.
func _line_up(g: Game, a: Player, others: Array) -> void:
	Modes.place(g, a, 60.0, 51.0, -PI * .5)
	a.pitch = -6.0
	for k in others.size():
		Modes.place(g, others[k], 60.0 + (k - 1) * 1.15, 48.4 - absf(k - 1) * .3, PI * .5)
	_ticks(g, 1)
	a.angle = -PI * .5
	a.armory.holstered = true
	a.armory.lower = 1.0


## Three partners `turns` from facing this player (radians), standing.
func _turned(a: Player, others: Array, turns: Array) -> void:
	for k in others.size():
		var q: Player = others[k]
		var turn: float = turns[k]
		q.angle = atan2(a.y - q.y, a.x - q.x) + turn
		q.motion = 0.0
		q.vx = 0.0
		q.vy = 0.0


## The party's pictures (only=party): three partners down lying three ways
## round, as the flat pictures (a view tour's cels) and as the models; the
## kill feed with a down and a revive in it while this player watches a
## partner; the lobby's posse for CAMPAIGN CO-OP and DEATHMATCH.
func _party() -> void:
	var g := _game("hickston", Modes.COOP, 4)
	_ticks(g, 2)
	g.cheats.god = true
	g.spawn_grace = 99.0
	for e: Enemy in g.enemies:
		e.dormant = true
	var a: Player = g.players[0]
	var others: Array = [g.players[1], g.players[2], g.players[3]]
	_line_up(g, a, others)
	g.cheats.god = false
	for q: Player in others:
		g.damage(500.0, null, "TEST", q)
	g.cheats.god = true
	_ticks(g, 2)
	# Across (head left), from the head, from the feet.
	_turned(a, others, [0.0, PI * .5, -PI * .5])
	a.pitch = -14.0
	_ticks(g, int(Enemy.DEATH_TIME * 60.0) + 60)
	_turned(a, others, [0.0, PI * .5, -PI * .5])
	WorldView3D.cels = true
	await _snap("party_down_cels")
	_turned(a, others, [PI, -PI * .5 + .3, PI * .5 - .3])
	await _snap("party_down_cels2")
	WorldView3D.cels = false
	_turned(a, others, [0.0, PI * .5, -PI * .5])
	await _snap("party_down_models")
	# The feed and the watching line: this player down, the view on a partner.
	var feed = g.features["kill_feed"]
	g.cheats.god = false
	g.damage(500.0, null, "TEST", a)
	g.cheats.god = true
	for q: Player in others:
		Modes.stand_up(g, q, 80)
	q_names(g)
	feed.add("BUBBA  SAWED-OFF  BILLY", feed.KILL_INK)
	feed.add("CLETUS WENT DOWN", feed.DOWN_INK)
	feed.add("EARLENE HAULED CLETUS UP", feed.UP_INK)
	feed.add("BUBBA  DYNAMITE CROSSBOW  ALIEN SHERIFF", feed.BOSS_INK)
	TacticalScreens.human = 0
	_ticks(g, 30)
	Players.set_local(g, others[0])
	await _snap("party_feed_watching", true)
	Players.set_local(g, a)
	await _lobby()


func q_names(g: Game) -> void:
	var names := ["MUNDELL", "BUBBA", "CLETUS", "EARLENE"]
	for p: Player in g.players:
		p.name = names[p.slot % names.size()]


## The lobby in every mode, as the host and as someone in it (the rows,
## labels and values each mode shows): lobby_<mode>_host / _client.
func _lobby() -> void:
	var net := NetPlay.host_lobby(NetPorts.pick("mode_frames"), "Mundell", {}, false, "127.0.0.1")
	if net == null:
		return
	net.players.append({"id": 7, "name": "BUBBA", "team": -1, "ready": true})
	net.players.append({"id": 8, "name": "CLETUS", "team": 1, "ready": false})
	main.net = net
	main.state = "lobby"
	main.game = null
	for mode: String in [
		"bomb", "hostage", "tagteam", "county", Modes.COOP, Modes.DEATHMATCH, Modes.TEAM
	]:
		net.role = NetPlay.Role.HOST
		net.my_id = NetSession.HOST_ID
		net.set_setting("mode", mode)
		if mode == Modes.DEATHMATCH:
			net.set_setting("time_limit", 600.0)
		for side: String in ["host", "client"]:
			if side == "client":
				net.role = NetPlay.Role.CLIENT
				net.my_id = 7
			main.render()
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var shot := root.get_texture().get_image()
			shot.save_png(out.path_join("lobby_%s_%s.png" % [mode, side]))
	net.role = NetPlay.Role.HOST
	net.my_id = NetSession.HOST_ID
	main.net = null
	net.finish()


## Mundell's body as the others see it (only=mundell): three co-op partners
## on the range turned to face, side and back, then a quarter, away and the
## other side; walking, aiming and firing; hurt walking, flinching from a hit
## and hurt aiming; falling, down and crouched; team deathmatch's colours.
func _mundell() -> void:
	var g := _game("hickston", Modes.COOP, 4)
	_ticks(g, 2)
	g.cheats.god = true
	g.spawn_grace = 99.0
	for e: Enemy in g.enemies:
		e.dormant = true
	var a: Player = g.players[0]
	var others: Array = [g.players[1], g.players[2], g.players[3]]
	_line_up(g, a, others)
	_turned(a, others, [0.0, PI * .5, PI])
	await _snap("mundell_turns")
	_turned(a, others, [PI * .25, PI * .75, -PI * .5])
	await _snap("mundell_turns2")
	# Close up: the middle partner a step and a half ahead, the others aside.
	var mid: Player = others[1]
	Modes.place(g, mid, a.x, a.y - 1.5, PI * .5)
	Modes.place(g, others[0], a.x - 3.0, a.y - 4.0, PI * .5)
	Modes.place(g, others[2], a.x + 3.0, a.y - 4.0, PI * .5)
	_turned(a, others, [0.0, 0.0, 0.0])
	a.pitch = 4.0
	await _snap("mundell_close")
	_turned(a, [mid], [PI * .5])
	await _snap("mundell_close_side")
	_line_up(g, a, others)
	_turned(a, others, [.3, -.4, .2])
	for k in 3:
		var q: Player = others[k]
		q.walk_phase = 1.0 + k * .6
	others[0].motion = 1.0
	others[1].armory.shot_age = .4
	others[2].armory.shot_age = .05
	await _snap("mundell_poses")
	for q: Player in others:
		q.armory.shot_age = 1.0
		q.health = 40
	await _snap("mundell_hurt_still")
	others[0].motion = 1.0
	others[1].health = 30
	others[2].armory.shot_age = .4
	await _snap("mundell_hurt")
	_turned(a, others, [.3, -.4, .2])
	g.cheats.god = false
	g.damage(500.0, null, "TEST", others[0])
	g.damage(500.0, null, "TEST", others[1])
	g.cheats.god = true
	await _snap("mundell_falling_0")
	_ticks(g, 20)
	await _snap("mundell_falling")
	others[2].crouched = true
	_ticks(g, 200)
	_turned(a, [others[2]], [.2])
	others[2].crouched = true
	await _snap("mundell_down")
	var t := _game("hickston", Modes.TEAM, 4)
	_ticks(t, 2)
	for e: Enemy in t.enemies:
		e.dormant = true
	var me: Player = t.players[0]
	_line_up(t, me, [t.players[1], t.players[2], t.players[3]])
	_turned(me, [t.players[1], t.players[2], t.players[3]], [.3, -.3, .6])
	await _snap("mundell_team")


## The 5v5 bodies close up: an outlaw and two deputies ahead, one walking,
## then the nearest shot down and falling; then a hostage.
func _tactical() -> void:
	var g := _game("holler", Modes.BOMB, 10, {"arena": "holler"})
	_ticks(g, 2)
	var a: Player = g.players[0]
	_fan(g, a, [g.players[1], g.players[2], g.players[3]], 2.6)
	g.players[3].walk_phase = 2.0
	_ticks(g, 1)
	await _snap("tac_bodies")
	g.players[1].health = 0
	_ticks(g, 20)
	await _snap("tac_bodies_falling")
	var h := _game("holler", Modes.HOSTAGE, 10, {"arena": "holler"})
	_ticks(h, 2)
	var st = h.features["mode"]
	var hostage: Array = st.hostages[0]
	var hx: float = hostage[0]
	var hy: float = hostage[1]
	var me: Player = h.players[0]
	for k in 16:
		var ang := k * TAU / 16.0
		var at := Vector2(hx + cos(ang) * 2.2, hy + sin(ang) * 2.2)
		if not h.world.blocked(at.x, at.y, .35) and h.world.visible(at.x, at.y, hx, hy):
			Modes.place(h, me, at.x, at.y, ang + PI)
			break
	_ticks(h, 1)
	await _snap("tac_hostage")
	# Carried out: the hostage walks at the carrier's heels.
	var carrier: Player = h.players[1]
	_face(h, me, carrier, 3.2)
	carrier.angle = me.angle + .5
	carrier.walk_phase = 1.0
	hostage[2] = "carried"
	hostage[3] = carrier.slot
	_ticks(h, 1)
	carrier.vx = cos(carrier.angle) * 2.0
	carrier.vy = sin(carrier.angle) * 2.0
	await _snap("tac_hostage_carried")


## The speedway's lap cars, seen from beside the racing line as one comes on
## and as it goes by.
func _race() -> void:
	var g := _game("speedway", Modes.CAMPAIGN, 1)
	_ticks(g, 2)
	g.cheats.god = true
	var laps = g.features.get("race_laps")
	if laps == null or laps.cars.is_empty():
		push_error("no lap cars")
		return
	var p: Player = g.players[0]
	var car: Array = laps.cars[0]
	var ahead: Array = laps._at(float(car[0]) + 7.0)
	var at: Vector2 = ahead[0]
	var heading: float = ahead[1]
	for side in [1.0, -1.0, 2.0, -2.0]:
		var spot: Vector2 = (
			at + Vector2(cos(heading + PI * .5), sin(heading + PI * .5)) * 3.0 * side
		)
		if not g.world.blocked(spot.x, spot.y, .35):
			Modes.place(g, p, spot.x, spot.y, heading + PI + .6 * signf(side))
			break
	_ticks(g, 1)
	await _snap("race_coming")
	_ticks(g, 40)
	var now: Vector2 = laps._at(float(car[0]))[0]
	p.angle = atan2(now.y - p.y, now.x - p.x)
	_ticks(g, 1)
	await _snap("race_passing")
