## Pictures of the game modes (src/modes/) in a real window (the
## graphics-card view players see): co-op's partner in view with their tag
## and health, the same partner off to the side (the marker at the view's
## edge), a partner down with the revive prompt and its progress, this
## player down while the partner is up; deathmatch in play (an opponent, the
## frags and the clock), fragged, and the results screen. <name>.png in
## out=<dir>.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/mode_frames.gd -- out=<dir>
##
## Point APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

var main
var out := ""


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
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
	await _coop()
	await _deathmatch()
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
