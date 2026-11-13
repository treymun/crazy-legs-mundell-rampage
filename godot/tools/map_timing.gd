## How long each 5v5 map's runs take at a full run (headless):
##
##   Godot --headless --path <project> --script res://tools/map_timing.gd [-- maps=holler]
##
## From each side's spawn (the middle of its spawn points) to each bomb site
## and hostage, between the sites (a defender's rotation), and from each
## hostage to the rescue box, in seconds at RUN cells a second along the
## whole-map step fields the bots walk (tactical_nav.gd). The defenders should
## reach a site several seconds before the attackers can. Then the bots'
## plan: a route waypoint or hold inside something solid, and a hold that
## sees none of the attackers' way in within its view (HOLD_CONE each way,
## HOLD_REACH cells) are listed; `strict` fails on them.
extends SceneTree

const RUN := 3.85
const HOLD_CONE := .6
const HOLD_REACH := 30.0

var problems := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	var maps: Array = Modes.SHOWDOWN_MAPS.duplicate()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("maps="):
			maps = Array(arg.substr(5).split(","))
	for map: String in maps:
		var g: Game = main.make_game(map)
		var plan: Dictionary = g.world.tactical
		var attack := _middle(plan["attack_spawns"])
		var defend := _middle(plan["defend_spawns"])
		print("== %s" % map)
		var sites: Dictionary = plan["sites"]
		var centres := {}
		for name: String in sites:
			centres[name] = TacticalMode.box_centre(sites[name])
		for name: String in centres:
			var at: Vector2 = centres[name]
			var t_att := _secs(g, at, attack)
			var t_def := _secs(g, at, defend)
			print(
				(
					"  site %s: attackers %.1f s, defenders %.1f s (defenders %.1f s sooner)"
					% [name, t_att, t_def, t_att - t_def]
				)
			)
		if centres.has("A") and centres.has("B"):
			print("  rotation A to B: %.1f s" % _secs(g, centres["A"], centres["B"]))
		_plan_check(g, plan)
		for box: Array in plan.get("rescue_more", []):
			var mid := TacticalMode.box_centre(box)
			if g.world.blocked(mid.x, mid.y, .3):
				print("  PROBLEM rescue point at %.1f,%.1f is in something" % [mid.x, mid.y])
				problems += 1
		var rescue := TacticalMode.box_centre(plan["rescue"])
		for h: Array in plan["hostages"]:
			var at := Vector2(float(h[0]), float(h[1]))
			print(
				(
					"  hostage at %.0f,%.0f: deputies' side %.1f s to reach, %.1f s to the rescue box"
					% [at.x, at.y, _secs(g, at, attack), _secs(g, rescue, at)]
				)
			)
	main.queue_free()
	await process_frame
	print("MAP TIMING OK" if problems == 0 else "%d PLAN PROBLEM(S)" % problems)
	quit(1 if problems > 0 and OS.get_cmdline_user_args().has("strict") else 0)


## Waypoints and holds inside something, and holds that watch nothing.
func _plan_check(g: Game, plan: Dictionary) -> void:
	var lanes: Array = []
	for site: String in plan["routes"]:
		for r: Array in plan["routes"][site]:
			for i in r.size():
				var at := Vector2(float(r[i][0]), float(r[i][1]))
				if g.world.blocked(at.x, at.y, .3):
					print(
						(
							"  PROBLEM route %s point %d at %.1f,%.1f is in something"
							% [site, i, at.x, at.y]
						)
					)
					problems += 1
				if i > 0:
					var from := Vector2(float(r[i - 1][0]), float(r[i - 1][1]))
					for k in 6:
						lanes.append(from.lerp(at, k / 6.0))
	for key: String in plan["holds"]:
		for h: Array in plan["holds"][key]:
			var at := Vector2(float(h[0]), float(h[1]))
			if g.world.blocked(at.x, at.y, .3):
				print("  PROBLEM hold %s at %.1f,%.1f is in something" % [key, at.x, at.y])
				problems += 1
			var watched := 0
			for p: Vector2 in lanes:
				var gap := p - at
				if gap.length() < 2.0 or gap.length() > HOLD_REACH:
					continue
				if absf(Enemy.angle_delta(gap.angle(), float(h[2]))) > HOLD_CONE:
					continue
				if g.world.visible(at.x, at.y, p.x, p.y):
					watched += 1
			if watched == 0:
				print(
					"  PROBLEM hold %s at %.1f,%.1f watches none of the ways in" % [key, at.x, at.y]
				)
				problems += 1
			else:
				print(
					(
						"  hold %s at %.1f,%.1f watches %d points of the ways in"
						% [key, at.x, at.y, watched]
					)
				)


func _middle(points: Array) -> Vector2:
	var sum := Vector2.ZERO
	for p: Array in points:
		sum += Vector2(float(p[0]), float(p[1]))
	return sum / maxf(1, points.size())


## Seconds from `from` to `to` along the step field walked from `to`.
func _secs(g: Game, to: Vector2, from: Vector2) -> float:
	var f := TacticalNav.field(g, to.x, to.y)
	var steps := TacticalNav.steps(f, from.x, from.y)
	return steps / RUN if steps >= 0 else -1.0
