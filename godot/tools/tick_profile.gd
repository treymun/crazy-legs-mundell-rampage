## Where the game's tick spends its time, headless: for every chapter it
## stands the player at the spawn (idle) and then in the nearest fight with
## the trigger held (as bench.gd does), and times each feature's tick on its
## own (GameFeature.tick_with, in the order they run; a sleeping one is not
## run, as in play), and the rest of the tick (the bodies, enemies, shots:
## "core").
##
##   godot --headless --path godot --script res://tools/tick_profile.gd \
##       [-- <frames>] [levels=a,b] [top=N] [plain] [replay]
##
## Prints per scene the tick's mean, the core's share and the costliest
## listeners (mean ms per tick), then the same over every scene. `plain`
## times only the whole tick (no timer around each listener, which costs a
## little itself): the number to hold old against new. `replay` also
## records every tick as the front end does (src/replay.gd) and prints
## what the recording costs a tick, apart from the tick.
extends SceneTree

const LEVELS := ["hickston", "fair", "sawmill", "quarry", "bayou", "speedway", "mothership"]

## The listeners being timed (Callable) and their summed microseconds.
var _calls: Array[Callable] = []
## The game's events, and whether its features' ticks run through them
## (GameEvents._run_ticks, taken over here).
var _events: Object = null
var _dispatch := false
var _us: Dictionary = {}
var _total_us: Dictionary = {}


func _init() -> void:
	_run.call_deferred()


func _name_of(c: Callable) -> String:
	var who := c.get_object()
	var script_name := "?"
	if who != null and who.get_script() != null:
		script_name = (who.get_script() as Script).resource_path.get_file().get_basename()
	return "%s.%s" % [script_name, c.get_method()]


## Take every listener of `ticked` (and any joined since) under the one
## timer: the features' ticks (GameEvents.tick_list) as each feature's own.
func _absorb(events: GameEvents) -> void:
	var sig: Signal = events.ticked
	_events = events
	for link: Dictionary in sig.get_connections():
		var c: Callable = link["callable"]
		if c == Callable(self, "_timed"):
			continue
		if c.get_method() == "_run_ticks":
			sig.disconnect(c)
			_dispatch = true
			continue
		sig.disconnect(c)
		_calls.append(c)
	if not sig.is_connected(_timed):
		sig.connect(_timed)


func _timed(dt: float) -> void:
	if _dispatch:
		# GameEvents._run_ticks, each tick timed (a sleeping one is skipped).
		var ticks: Array = _events.get("_ticks")
		var awake: PackedByteArray = _events.get("_awake")
		for i in ticks.size():
			if awake[i] == 0:
				continue
			var c: Callable = ticks[i]
			var t0 := Time.get_ticks_usec()
			c.call(dt)
			var name := _name_of(c)
			_us[name] = int(_us.get(name, 0)) + Time.get_ticks_usec() - t0
			awake = _events.get("_awake")
	for c in _calls:
		var t0 := Time.get_ticks_usec()
		c.call(dt)
		var name := _name_of(c)
		_us[name] = int(_us.get(name, 0)) + Time.get_ticks_usec() - t0


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var frames := 300
	var levels: Array = LEVELS.duplicate()
	var top := 8
	var replay := args.has("replay")
	var all_rec_us := 0
	var plain := args.has("plain")
	for arg: String in args:
		if arg.is_valid_int():
			frames = int(arg)
		elif arg.begins_with("levels="):
			levels = Array(arg.substr(7).split(",", false))
		elif arg.begins_with("top="):
			top = int(arg.substr(4))
	var assets := Assets.new()
	var hud := HUD.new(assets)
	var sound := Sound.new(assets)
	root.add_child(sound)
	var options := SessionStore.settings("")
	var all_tick := 0.0
	var all_frames := 0
	for level: String in levels:
		for scene: String in ["idle", "fight"]:
			var game := Game.new(assets, hud, sound, level)
			game.configure(options)
			var controls := Game.Controls.new()
			if scene == "fight":
				_to_fight(game)
				controls.fire = true
				controls.turn = .4
			_calls.clear()
			_dispatch = false
			_us.clear()
			var tick_us := 0
			var rec: Replay = Replay.record(game, options) if replay else null
			var rec_us := 0
			for i in frames:
				if not plain:
					_absorb(game.events)
				if i == 20:
					_us.clear()
					tick_us = 0
					rec_us = 0
				var r0 := Time.get_ticks_usec()
				if rec != null:
					rec.tick(1.0 / 60.0, controls)
				var t0 := Time.get_ticks_usec()
				game.tick(1.0 / 60.0, controls)
				var t1 := Time.get_ticks_usec()
				tick_us += t1 - t0
				if rec != null:
					rec.ticked()
					rec_us += t0 - r0 + Time.get_ticks_usec() - t1
			var n := frames - 20
			var listened := 0
			for k: String in _us:
				listened += int(_us[k])
				_total_us[k] = int(_total_us.get(k, 0)) + int(_us[k])
			_total_us["(core)"] = int(_total_us.get("(core)", 0)) + tick_us - listened
			all_tick += tick_us
			all_frames += n
			print(
				(
					"%-10s %-5s tick %.3f ms  core %.3f  features %.3f"
					% [
						level,
						scene,
						tick_us / 1000.0 / n,
						(tick_us - listened) / 1000.0 / n,
						listened / 1000.0 / n
					]
				)
			)
			print("    " + _top(_us, n, top))
			if rec != null:
				all_rec_us += rec_us
				print("    recording %.1f us a tick" % [float(rec_us) / n])
	print("ALL        tick %.3f ms" % [all_tick / 1000.0 / all_frames])
	if replay:
		print("    recording %.1f us a tick" % [float(all_rec_us) / all_frames])
	print("    " + _top(_total_us, all_frames, top * 2))
	quit()


func _top(us: Dictionary, n: int, count: int) -> String:
	var rows: Array = []
	for k: String in us:
		rows.append([int(us[k]), k])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var out := ""
	for row: Array in rows.slice(0, count):
		out += "%s %.3f  " % [row[1], row[0] / 1000.0 / n]
	return out


## The player beside the nearest awake foe, as bench.gd's fight.
func _to_fight(game: Game) -> void:
	var p := game.player
	var best: Enemy = null
	for enemy: Enemy in game.enemies:
		if not enemy.hostile or enemy.dormant:
			continue
		if (
			best == null
			or absf(enemy.x - p.x) + absf(enemy.y - p.y) < absf(best.x - p.x) + absf(best.y - p.y)
		):
			best = enemy
	if best != null:
		for angle: float in [0.0, PI * .5, PI, -PI * .5]:
			var x := best.x - cos(angle) * 2.6
			var y := best.y - sin(angle) * 2.6
			if game.world.solid[game.world.cell(x, y)] < 0:
				p.x = x
				p.y = y
				p.angle = angle
				break
	p.health = 100000
