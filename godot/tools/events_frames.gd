## Pictures of the county events (features/county_events.gd) in a real
## window, each to out=<dir>/<name>.png (only=<a,b> takes some of them):
##   event_twister_far, _near, _rope   the funnel coming across, close, forming
##   event_hogs, event_hogs_side       the herd coming down on the player, passing
##   event_raid                        a revenue man shooting it out with a hand
##   event_dark, event_dark_off        the blackout with the flashlight on, off
##   event_breaker                     the main breaker on its wall
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/events_frames.gd -- out=<dir> [only=hogs,dark]
##
## Point APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

const STEP := 1.0 / 60.0

var main
var out := ""
var only: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
		elif String(arg).begins_with("only="):
			only = String(arg).substr(5).split(",")
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
	if _wanted("twister"):
		await _twister()
	if _wanted("hogs"):
		await _hogs()
	if _wanted("raid"):
		await _raid()
	if _wanted("dark"):
		await _dark()
	print("event frames written to ", out)
	main.queue_free()
	await process_frame
	quit()


func _wanted(part: String) -> bool:
	return only.is_empty() or only.has(part)


func _snap(name: String) -> void:
	var g: Game = main.game
	if g != null:
		g.message_until = 0.0
		g.callout_until = 0.0
		g.district_until = 0.0
		g.barks.until = 0.0
		g.caption_until = 0.0
	main.render()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))


func _level(level_id: String, calm := true) -> Game:
	main.options["events"] = 2
	main.start(level_id)
	var g: Game = main.game
	g.cheats.god = true
	g.lessons = false
	g.barks.enabled = false
	if calm:
		for e: Enemy in g.enemies:
			if e.hostile:
				e.dormant = true
	g.spawn_grace = 99.0
	return g


func _ticks(g: Game, n: int) -> void:
	for i in n:
		g.tick(STEP, Game.Controls.new())


func _ev(g: Game) -> CountyEvents:
	return g.features["events"]


func _place(g: Game, at: Vector2, look: Vector2, pitch := 0.0) -> void:
	var p := g.player
	p.x = at.x
	p.y = at.y
	p.floor_z = g.world.elevation(at.x, at.y)
	p.eye = p.floor_z + .95
	p.angle = atan2(look.y - at.y, look.x - at.x)
	p.pitch = pitch
	p.flow.update(p.x, p.y, g.clock)
	g.armory.holstered = false


## A spot `far` from `at` on open ground that sees its foot, or INF.
func _vantage(g: Game, at: Vector2, far: float) -> Vector2:
	var ground := g.world.elevation(at.x, at.y)
	for ring: float in [far, far * .8, far * 1.25, far * .6]:
		for k in 32:
			var q := at + Vector2.from_angle(k * TAU / 32.0) * ring
			if q.x < 2 or q.y < 2 or q.x > g.world.width - 2 or q.y > g.world.height - 2:
				continue
			if g.world.blocked(q.x, q.y, .3):
				continue
			var z := g.world.elevation(q.x, q.y)
			if g.world.visible(q.x, q.y, at.x, at.y, z + .95, ground + 1.0):
				return q
	return Vector2.INF


func _twister() -> void:
	var g := _level("hickston")
	_ticks(g, 4)
	var ev := _ev(g)
	var sets: SetPiecesFeature = g.features.get("set_pieces")
	var shed := sets.spec_of(0)
	var near := Vector2(float(shed["x"]) + 9.0, float(shed["y"]) + 3.0)
	_place(g, near, Vector2(float(shed["x"]), float(shed["y"])))
	ev.begin("twister")
	var p := g.player
	# Forming, far off: the rope coming down out of the cloud.
	_ticks(g, int(ev.n("twister", "warn") * 60.0 * .55))
	var watch := _vantage(g, ev.tw_at, 24.0)
	_place(g, watch, ev.tw_at, 30.0)
	_ticks(g, 2)
	_place(g, watch, ev.tw_at, 30.0)
	await _snap("event_twister_rope")
	_ticks(g, int(ev.n("twister", "warn") * 60.0 * .5))
	# On the ground, coming across, seen from well off.
	for t in 60 * 4:
		g.tick(STEP, Game.Controls.new())
	var safe := _vantage(g, ev.tw_at, 26.0)
	_place(g, safe, ev.tw_at, 26.0)
	p.knocked = 0.0
	_ticks(g, 2)
	_place(g, safe, ev.tw_at, 26.0)
	await _snap("event_twister_far")
	for t in 40:
		g.tick(STEP, Game.Controls.new())
		_place(g, _vantage(g, ev.tw_at, 9.0), ev.tw_at, 34.0)
		p.knocked = 0.0
	await _snap("event_twister_near")


func _hogs() -> void:
	var g := _level("hickston")
	_ticks(g, 4)
	var ev := _ev(g)
	ev.begin("hogs")
	var stand := ev.herd_from + ev.herd_way * minf(ev.herd_len - 2.0, 16.0)
	_place(g, stand, ev.herd_from, -8.0)
	# Until the lead hog is a few cells off.
	for t in 60 * 8:
		g.tick(STEP, Game.Controls.new())
		_place(g, stand, ev.herd_from, -8.0)
		var lead: Array = ev.herd[0]
		if Vector2(EventHerd.f(lead, 0), EventHerd.f(lead, 1)).distance_to(stand) < 4.5:
			break
	g.player.knocked = 0.0
	await _snap("event_hogs")
	var g2 := _level("hickston")
	_ticks(g2, 4)
	var ev2 := _ev(g2)
	ev2.begin("hogs")
	var side := Vector2(-ev2.herd_way.y, ev2.herd_way.x)
	var mid := ev2.herd_from + ev2.herd_way * minf(ev2.herd_len * .5, 10.0)
	var watch := mid + side * 3.4
	if g2.world.blocked(watch.x, watch.y, .3):
		watch = mid - side * 3.4
	for t in 60 * 8:
		g2.tick(STEP, Game.Controls.new())
		_place(g2, watch, mid, -10.0)
		var row: Array = ev2.herd[4]
		var along := (Vector2(EventHerd.f(row, 0), EventHerd.f(row, 1)) - ev2.herd_from).dot(
			ev2.herd_way
		)
		if along > minf(ev2.herd_len * .5, 10.0):
			break
	await _snap("event_hogs_side")


func _raid() -> void:
	var g := _level("hickston", false)
	_ticks(g, 4)
	var ev := _ev(g)
	var p := g.player
	var hand: Enemy = null
	for e: Enemy in g.enemies:
		if (
			e.tactical()
			and e.alive
			and not e.dormant
			and hand == null
			and not Enemy.BOSS_TITLES.has(e.kind)
		):
			hand = e
		elif e.hostile:
			e.dormant = true
	var at := Vector2(p.x + cos(p.angle) * 6.0, p.y + sin(p.angle) * 6.0)
	hand.x = at.x + sin(p.angle) * 1.6
	hand.y = at.y - cos(p.angle) * 1.6
	ev.begin("raid")
	for i in ev.raiders.size():
		var r: Enemy = g.enemies[ev.raiders[i]]
		if i == 0:
			r.x = at.x - sin(p.angle) * 1.8
			r.y = at.y + cos(p.angle) * 1.8
		else:
			r.dormant = true
	g.spawn_grace = 99.0
	for t in 120:
		g.tick(STEP, Game.Controls.new())
		if not ev.raid_shots.is_empty():
			var last: Array = ev.raid_shots[ev.raid_shots.size() - 1]
			if g.clock - CountyEvents.at(last, 6) < .02:
				break
	await _snap("event_raid")


func _dark() -> void:
	var g := _level("hickston", false)
	_ticks(g, 4)
	var ev := _ev(g)
	var p := g.player
	ev.begin("blackout")
	_ticks(g, int(ev.n("blackout", "fade") * 60.0) + 10)
	var lit: Enemy = null
	for i: int in ev.lanterns:
		var e: Enemy = g.enemies[i]
		if lit == null:
			lit = e
	for e: Enemy in g.enemies:
		if e != lit and e.hostile:
			e.dormant = true
	if lit != null:
		lit.x = p.x + cos(p.angle + .5) * 5.0
		lit.y = p.y + sin(p.angle + .5) * 5.0
		lit.angle = p.angle + PI
	g.spawn_grace = 99.0
	p.pitch = -10.0
	_ticks(g, 2)
	for l: Array in g.effect_lights():
		print("light ", l)
	await _snap("event_dark")
	g.torch()
	_ticks(g, 2)
	await _snap("event_dark_off")
	g.torch()
	var b := ev.breaker
	var off := Vector2.from_angle(b.z * PI * .5)
	_place(g, Vector2(b.x, b.y) - off * 2.4, Vector2(b.x, b.y), -14.0)
	_ticks(g, 2)
	await _snap("event_breaker")
