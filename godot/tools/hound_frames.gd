## Pictures of BLUE, the hound (features/hound.gd), in a real window:
##   hound_<name>   see POSES below (pass 10: his gaits, the limp and the
##                  tracking walk, the howl, the lunge, down on his side with
##                  USE's prompt, being got up with its bar, getting up, the
##                  shake, lying at STAY), hound_pin and hound_pin_side, and
##                  hound_behind and hound_behind_down (his marker over a
##                  wall, red when he is down), hound_size_40 and _26 (his
##                  size beside a co-op partner's Mundell)
## Each lands in out=<dir> as <name>.png; only=<a,b> takes some of them
## (only=poses all of POSES).
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/hound_frames.gd -- out=<dir> [only=follow,pin]
##
## Point APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

## [picture, level, state (features/hound.gd), his turn from facing the eye,
## what else is set (pass 10: his pace and gait, seconds down, the revive,
## his health, seconds since he got up, cells off, the bite to come)]
const POSES := [
	["stand", "hickston", 0, 1.2, {}],
	["front", "hickston", 0, 0.0, {}],
	["sit", "hickston", 1, 0.9, {}],
	["rest", "hickston", 1, 0.9, {"since": 12.0}],
	["bay", "fair", 6, 1.3, {"far": 2.0, "pitch": -40.0}],
	["point", "sawmill", 7, 1.2, {"look": 1.3}],
	["carry", "hickston", 5, 0.5, {}],
	["down", "hickston", 8, 1.5, {"down": 3.0, "far": 2.4, "pitch": -40.0, "rinds": 0}],
	[
		"revive",
		"hickston",
		8,
		1.5,
		{"down": 5.0, "revive": .6, "far": 1.35, "pitch": -90.0, "rinds": 0}
	],
	["getup", "hickston", 0, 1.3, {"up": .45}],
	["shake", "hickston", 0, 1.3, {"up": 1.0}],
	["trot", "hickston", 0, 1.57, {"pace": 2.0, "gait": 1.4}],
	["gallop", "hickston", 0, 1.57, {"pace": 4.0, "gait": 0.0}],
	["track", "hickston", 6, 1.3, {"pace": 1.0, "gait": 2.0, "tracking": true}],
	["limp", "hickston", 0, 1.57, {"pace": 2.0, "gait": 1.0, "health": 20.0}],
	["lunge", "hickston", 2, 1.57, {"bite": .05}],
	["howl", "quarry", 6, 1.0, {}],
	["dusk", "quarry", 0, 2.2, {}],
]

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
	if _wanted("start"):
		var g := _level("hickston")
		_ticks(g, 30)
		await _snap("hound_start")
	# Each pose of his from a few cells off, at his side and from the front.
	for pose: Array in POSES:
		var name: String = pose[0]
		if not _wanted(name) and not _wanted("poses"):
			continue
		var g := _level(str(pose[1]))
		_ticks(g, 4)
		var h = g.features["hound"]
		var d = h.dogs[0]
		var more: Dictionary = pose[4]
		# A moment out of his idle and tracking rounds (HoundLooks).
		g.clock = 13.0
		h.call("into", d, int(pose[2]))
		d.until = g.clock + 99.0
		d.bark_at = g.clock if pose[2] in [6, 7] else -10.0
		d.since = g.clock - float(more.get("since", 1.0))
		if more.get("tracking", false):
			d.bark_at = -10.0
		d.down_at = g.clock - float(more.get("down", 2.0)) if pose[2] == 8 else -1.0
		d.revive = float(more.get("revive", 0.0)) * h.n("revive_time")
		d.up_at = g.clock - float(more.get("up", 50.0))
		d.health = float(more.get("health", h.n("health")))
		d.hurt_at = -10.0
		if pose[2] == 2:
			d.bite_at = g.clock + float(more.get("bite", .5))
		if pose[2] == 5:
			d.item = "shells"
		var p := g.player
		var turn: float = pose[3]
		var far: float = more.get("far", 2.6)
		d.x = p.x + cos(p.angle) * far
		d.y = p.y + sin(p.angle) * far
		d.floor_z = g.world.floor_under(d.x, d.y, g.world.stand(p) + .4)
		d.angle = p.angle + PI + turn
		d.pace = float(more.get("pace", 0.0))
		d.gait = float(more.get("gait", 0.0))
		# (pass 12: his looks read his legs' speed and the gait it holds; just
		# stood, so not yet settled sitting by his player)
		d.stride_v = d.pace
		d.gait_kind = HoundLooks.gait_of(-1, d.pace)
		d.still_at = g.clock
		if more.has("look"):
			# what he points at: in the view, off to the side of him
			var reach: float = more["look"]
			var side := p.angle - PI * .5
			d.look = Vector2(
				d.x + cos(side) * reach + cos(p.angle) * .5,
				d.y + sin(side) * reach + sin(p.angle) * .5
			)
			d.angle = atan2(d.look.y - d.y, d.look.x - d.x)
		p.pitch = float(more.get("pitch", -16.0))
		if more.has("rinds"):
			p.inventory["rinds"] = int(more["rinds"])
		g.armory.holstered = true
		g.armory.lower = 1.0
		await _snap("hound_" + name)
	if _wanted("pin"):
		await _pin()
	if _wanted("behind"):
		await _behind()
	if _wanted("size"):
		await _size()
	print("hound frames written to ", out)
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
	main.render()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))


func _level(level_id: String) -> Game:
	main.options["hound"] = 1
	main.start(level_id)
	var g: Game = main.game
	g.cheats.god = true
	g.lessons = false
	g.barks.enabled = false
	for e: Enemy in g.enemies:
		if e.hostile:
			e.dormant = true
	g.spawn_grace = 99.0
	return g


func _ticks(g: Game, n: int) -> void:
	for i in n:
		g.tick(1.0 / 60.0, Game.Controls.new())


## His size: BLUE beside Mundell (a co-op partner's model) and a hand (a
## Billy), side on, from a few cells off and from close by.
func _size() -> void:
	main.options["hound"] = 1
	var g: Game = main.make_game("hickston")
	main.game = g
	main.state = "play"
	var options := SessionStore.defaults()
	options["hound"] = 1
	g.configure(options)
	Modes.setup(g, Modes.COOP, 2, {})
	g.cheats.god = true
	g.lessons = false
	g.barks.enabled = false
	g.spawn_grace = 99.0
	_ticks(g, 4)
	var a: Player = g.players[0]
	var b: Player = g.players[1]
	var foe: Enemy = null
	for e: Enemy in g.enemies:
		e.dormant = true
		if foe == null and e.hostile and HoundNose.takes(e) and e.tactical():
			foe = e
	var h = g.features["hound"]
	var d = h.dogs[0]
	for d2 in h.dogs:
		if d2 != d:
			d2.x = -100.0
	g.clock = 13.0
	for far: float in [4.0, 2.6]:
		var ahead := Vector2(cos(a.angle), sin(a.angle))
		var side := Vector2(-ahead.y, ahead.x)
		var mid := Vector2(a.x, a.y) + ahead * far
		Modes.place(g, b, mid.x, mid.y, a.angle + PI * .5)
		d.x = mid.x + side.x * .8
		d.y = mid.y + side.y * .8
		d.floor_z = g.world.floor_under(d.x, d.y, g.world.stand(a) + .4)
		d.angle = a.angle + PI * .5
		d.state = 0
		if foe != null:
			foe.x = mid.x - side.x * .9
			foe.y = mid.y - side.y * .9
			foe.floor_z = g.world.floor_under(foe.x, foe.y, g.world.stand(a) + .4)
			foe.angle = a.angle - PI * .5
		a.pitch = -4.0
		g.armory.holstered = true
		g.armory.lower = 1.0
		await _snap("hound_size_%d" % roundi(far * 10.0))


## BLUE behind a wall from the player: his marker over him.
func _behind() -> void:
	var g := _level("hickston")
	_ticks(g, 4)
	var h = g.features["hound"]
	var d = h.dogs[0]
	var p := g.player
	g.clock = 13.0
	for r: float in [4.0, 5.0, 6.0, 8.0, 10.0]:
		for k in 36:
			var a := k * TAU / 36.0
			var x := p.x + cos(a) * r
			var y := p.y + sin(a) * r
			if g.world.blocked(x, y, .25):
				continue
			var z := g.world.floor_under(x, y, g.world.stand(p) + .4)
			if not g.world.visible(p.x, p.y, x, y, p.eye, z + .5):
				d.x = x
				d.y = y
				d.floor_z = z
				p.angle = a
				p.pitch = -6.0
				g.armory.holstered = true
				g.armory.lower = 1.0
				await _snap("hound_behind")
				h.call("into", d, 8)
				d.down_at = g.clock - 3.0
				await _snap("hound_behind_down")
				return


## BLUE holding a hand down: the hand stunned in its pain pose, BLUE hauling
## on it, from the side.
func _pin() -> void:
	main.options["hound"] = 1
	main.start("hickston")
	var g: Game = main.game
	g.cheats.god = true
	g.lessons = false
	g.barks.enabled = false
	g.spawn_grace = 99.0
	_ticks(g, 4)
	var p := g.player
	var foe: Enemy = null
	for e: Enemy in g.enemies:
		if foe == null and e.hostile and HoundNose.takes(e) and e.tactical():
			foe = e
		else:
			e.dormant = true
	var at := Vector2(p.x + cos(p.angle) * 3.4, p.y + sin(p.angle) * 3.4)
	foe.x = at.x
	foe.y = at.y
	foe.floor_z = g.world.floor_under(at.x, at.y, g.world.stand(p) + .4)
	foe.alerted = true
	foe.angle = p.angle + PI * .5
	foe.hp = foe.max_hp * .4
	var h = g.features["hound"]
	var d = h.dogs[0]
	var side := p.angle - PI * .5
	d.x = foe.x + cos(side) * .62
	d.y = foe.y + sin(side) * .62
	d.floor_z = foe.floor_z
	h.call("into", d, 3)
	d.foe = foe.uid
	d.until = g.clock + 99.0
	d.angle = atan2(foe.y - d.y, foe.x - d.x)
	foe.stun = .3
	g.armory.holstered = true
	g.armory.lower = 1.0
	_ticks(g, 3)
	d.angle = atan2(foe.y - d.y, foe.x - d.x)
	p.pitch = -10.0
	await _snap("hound_pin")
	# From his side, a moment on (the dog shaking the other way).
	var round_to := atan2(d.y - foe.y, d.x - foe.x) + .5
	p.x = foe.x + cos(round_to) * 3.2
	p.y = foe.y + sin(round_to) * 3.2
	p.angle = atan2(foe.y - p.y, foe.x - p.x)
	_ticks(g, 16)
	await _snap("hound_pin_side")
