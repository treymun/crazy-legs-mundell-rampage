## How each chapter's way through paces: the objective route (route_map.gd's
## stops, walked with every door open) step by step, and what a player meets
## along it. A step is "quiet" when no hand stands within FIGHT cells of it,
## no pickup within LOOT and no station or sign within LOOK; the longest run
## of quiet steps walked for the first time is the chapter's dead stretch
## (steps walked again, going back over cleared ground, are counted apart).
## The thickest fight is the most hands within FIGHT of one step. It is a
## yardstick for the plans, not a judge of fun: hands move, and a long walk
## can be a good breather; a chapter fails only past DEAD_MAX (the Moonshine
## Run's north blacktop was 31 before polish pass 9's pull-offs, 15 after).
##
## Then the versus maps as DEATHMATCH arenas (Modes.ARENAS without a boss box,
## the hub and the range): each has something to heal with and rounds lying
## out (their plans' arena_loot()), every pickup on open floor a player can
## walk to from the map's start, and every spawn point Modes.spawn_points
## gives within LOOT_MAX cells of a pickup.
##
##   godot --headless --path godot --script res://tools/pacing_check.gd [-- <level> ...]
##
## Prints PACING OK (check_all runs it).
extends SceneTree

const RouteMap := preload("res://tools/route_map.gd")

const FIGHT := 10.0
const LOOT := 3.5
const LOOK := 5.0
const DEAD_MAX := 24
const LOOT_MAX := 26.0
const HEALS := ["rinds", "beer", "whiskey", "moonshine"]
const ROUNDS := ["shells", "bullets", "rifle_ammo", "dynamite"]
const CHAPTERS := [
	"hickston", "fair", "sawmill", "quarry", "bayou", "speedway", "moonshine", "mothership"
]

var failed: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var ids: Array = Array(OS.get_cmdline_user_args())
	var art := Assets.new()
	for id: String in ids if not ids.is_empty() else CHAPTERS:
		_pace(LevelData.load_level(id, art))
	if ids.is_empty():
		var hud := HUD.new(art)
		var sound := Sound.new(art)
		root.add_child(sound)
		for arena: String in Modes.ARENAS:
			var parts := Modes.arena_of(arena)
			if String(parts[1]) == "" and not String(parts[0]) in ["hub", "range"]:
				_arena(Game.new(art, hud, sound, String(parts[0])))
	if failed.is_empty():
		print("PACING OK")
	else:
		print("PACING FAILED: ", ", ".join(failed))
	quit()


## A versus map as a deathmatch arena: something to heal with, rounds, every
## pickup walked to, no spawn point far from all of them.
func _arena(game: Game) -> void:
	var w := game.world
	var field := FlowField.new(w)
	field.reach = 100000
	field.update(float(w.spawn[0]), float(w.spawn[1]), 0.0)
	var heals := 0
	var rounds := 0
	var spots: Array[Vector2] = []
	for p: Array in w.pickups:
		var at := Vector2(float(p[1]), float(p[2]))
		spots.append(at)
		if HEALS.has(String(p[0])):
			heals += 1
		if ROUNDS.has(String(p[0])):
			rounds += 1
		if field.distance(at.x, at.y) >= FlowField.FAR:
			failed.append("%s: %s at %s cannot be walked to" % [w.id, p[0], at])
	if heals < 2 or rounds < 2:
		failed.append("%s: %d to heal with, %d rounds" % [w.id, heals, rounds])
	var worst := 0.0
	for spawn: Array in Modes.spawn_points(game, Rect2i(), 12):
		var c := Vector2(float(spawn[0]), float(spawn[1]))
		var near := INF
		for at in spots:
			near = minf(near, at.distance_to(c))
		worst = maxf(worst, near)
	print(
		(
			"%-10s arena: %d pickups (%d heal, %d rounds), spawn to loot at worst %.1f"
			% [w.id, spots.size(), heals, rounds, worst]
		)
	)
	if worst > LOOT_MAX:
		failed.append("%s: a spawn point %.1f from any pickup" % [w.id, worst])


func _pace(level: LevelData) -> void:
	var stops := RouteMap.stops_of(level)
	var field := FlowField.new(level)
	field.reach = 100000
	field.doors_open = true
	field.every_door = true
	var hands: Array[Vector2] = []
	for e: Dictionary in level.enemies:
		hands.append(Vector2(float(e["x"]), float(e["y"])))
	var loot: Array[Vector2] = []
	for p: Array in level.pickups:
		loot.append(Vector2(float(p[1]), float(p[2])))
	var looks: Array[Vector2] = []
	for s: LevelData.Station in level.stations:
		looks.append(Vector2(s.x, s.y))
	for bd: LevelData.Billboard in level.billboards:
		if bd.image.contains("sign") or bd.image.contains("arrow"):
			looks.append(Vector2(bd.x, bd.y))
	var walked := {}
	var from := Vector2(float(level.spawn[0]), float(level.spawn[1]))
	var steps: Array = []  # [cell, first time, leg name]
	for stop: Array in stops:
		var to: Vector2 = stop[1]
		field.origin = Vector2i(-1, -1)
		field.next_at = 0.0
		field.update(to.x, to.y, 0.0)
		var path: Array = []
		var begin := RouteMap.nearest_reached(field, from)
		field.waypoint(begin.x, begin.y, 100000, path)
		for cell: Vector2i in path:
			steps.append([cell, not walked.has(cell), String(stop[0])])
			walked[cell] = true
		from = to
	var run := 0
	var run_start := 0
	var best := 0
	var best_at := [Vector2i.ZERO, Vector2i.ZERO, ""]
	var again := 0
	var thick := 0
	var thick_at := Vector2i.ZERO
	var quiet_total := 0
	for i in steps.size():
		var cell: Vector2i = steps[i][0]
		var c := Vector2(cell.x + .5, cell.y + .5)
		var near := 0
		for hand in hands:
			if hand.distance_to(c) <= FIGHT:
				near += 1
		if near > thick:
			thick = near
			thick_at = cell
		var quiet := (
			near == 0 and not _any_within(loot, c, LOOT) and not _any_within(looks, c, LOOK)
		)
		if not bool(steps[i][1]):
			again += 1
			continue
		if quiet:
			quiet_total += 1
			if run == 0:
				run_start = i
			run += 1
			if run > best:
				best = run
				best_at = [steps[run_start][0], cell, steps[i][2]]
		else:
			run = 0
	var first := steps.size() - again
	print(
		(
			(
				"%-10s route %4d steps (%d again)  quiet %3d%%  dead stretch %3d steps"
				+ " %s->%s (to %s)  thickest %d hands at %s"
			)
			% [
				level.id,
				steps.size(),
				again,
				roundi(100.0 * quiet_total / maxf(first, 1)),
				best,
				best_at[0],
				best_at[1],
				best_at[2],
				thick,
				thick_at
			]
		)
	)
	if best > DEAD_MAX:
		failed.append("%s (%d)" % [level.id, best])


func _any_within(points: Array[Vector2], c: Vector2, reach: float) -> bool:
	for p in points:
		if p.distance_to(c) <= reach:
			return true
	return false
