## The 5v5 maps' breakable cover (src/modes/round_cover.gd, the boarded
## fences [fence.cover_boards] in data/tuning/breakables.cfg):
##
##   godot --headless --path godot --script res://tools/cover_check.gd
##
## On each 5v5 map, in search and destroy: the map has boarded cover and some
## of it opens; shots knock a board down until it breaks through, and then the
## cell is floor a body can stand in and a sight line passes; where the plan
## means it as a way through (holler's hedge, salvage's tyre wall) the bots'
## step fields find the way shorter; a crate or barrel broken too. The next
## round's start stands everything up again: the walls, the floor, the
## furniture and both features as built, the step fields back as they were.
## Online: a copy given the host's snapshot has the break; given the next
## round's snapshot without stepping the round's start (a copy that missed
## it), it stands up again too, and its walls match the host's. Prints
## COVER CHECK OK.
extends SceneTree

const WallBreaksScript := preload("res://src/features/wall_breaks.gd")
const BreakablesScript := preload("res://src/features/breakables.gd")
## Maps with a boarded way through, and the cells either side of it.
const WAYS := {
	"holler": [Vector2i(33, 28), Vector2i(36, 28), Vector2i(34, 28)],
	"salvage": [Vector2i(35, 21), Vector2i(39, 21), Vector2i(37, 21)],
}

var failures: Array = []


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	var tally := CrashLog.tally()
	var art := Assets.new()
	for map: String in Modes.SHOWDOWN_MAPS:
		_map(art, map)
	tally.stop()
	_check(
		tally.errors == 0,
		(
			"no script or engine errors"
			+ ("" if tally.errors == 0 else " (%d: %s)" % [tally.errors, tally.first_errors[0]])
		)
	)
	print("")
	print("COVER CHECK OK" if failures.is_empty() else "COVER CHECK FAILED (%d)" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


static func _made(art: Assets, map: String) -> Game:
	var g := Game.new(art, null, QuietSound.new(), map, true)
	g.configure({"difficulty": 1, "seed": 7})
	Modes.setup(g, Modes.BOMB, 10, {"arena": map, "rounds": 7})
	g.tick(NetSync.STEP, {})
	return g


func _map(art: Assets, map: String) -> void:
	var g := _made(art, map)
	var fences: WallBreaksScript = g.features.get("wall_breaks")
	var boards: Array = []
	for f: WallBreaksScript.Fence in fences.fences.values():
		if String(g.world.tile_names[f.tile]) == "cover_boards":
			boards.append(f)
	var opening: Array = boards.filter(func(f: WallBreaksScript.Fence) -> bool: return f.opens)
	_check(
		boards.size() >= 1 and opening.size() >= 1,
		(
			"%s: boarded cover (%d cells, %d open when shot through)"
			% [map, boards.size(), opening.size()]
		)
	)
	if opening.is_empty():
		return
	var built_walls := g.world.walls.duplicate()
	var built_solid := g.world.solid.duplicate()
	var built_volumes := g.world.collision_volumes.size()
	var way: Array = WAYS.get(map, [])
	var target: WallBreaksScript.Fence = opening[0]
	var before := -1
	if not way.is_empty():
		var at: Vector2i = way[2]
		target = fences.fences.get(at, target)
		before = _steps(g, way[0], way[1])
	var cell := target.cell
	var c := cell.y * g.world.width + cell.x
	var g_copy := _made(art, map)
	# Shots: a rifle's worth at a time, from in front of it.
	var shots := 0
	while target.stage < 2 and shots < 40:
		fences._knock(target, 34.0, 1.0, 0.0)
		shots += 1
	_check(
		(
			target.stage == 2
			and g.world.solid[c] < 0
			and not g.world.blocked(cell.x + .5, cell.y + .5, .2)
		),
		"%s: boards at %s shot through in %d hits: floor, open to bodies" % [map, cell, shots]
	)
	_check(
		(
			g.world.visible(cell.x + .5, cell.y - .5, cell.x + .5, cell.y + 1.5, .9, .9)
			if target.along_x
			else g.world.visible(cell.x - .5, cell.y + .5, cell.x + 1.5, cell.y + .5, .9, .9)
		),
		"%s: and to sight" % map
	)
	if before >= 0:
		var after := _steps(g, way[0], way[1])
		_check(
			after < before,
			(
				"%s: the boarded way through is a shorter walk once open (%d steps, was %d)"
				% [map, after, before]
			)
		)
	var pieces: BreakablesScript = g.features.get("breakables")
	var piece_broken := false
	if pieces != null and not pieces.pieces.is_empty():
		var piece: BreakablesScript.Piece = pieces.pieces[0]
		pieces.strike(0, 9999.0, 1.0, 0.0)
		piece_broken = piece.broken
	_check(RoundCover.broken(g), "%s: something is broken this round" % map)
	# Online: the copy gets the break from a snapshot.
	GameSnapshot.apply(g_copy, GameSnapshot.capture(g))
	_check(g_copy.world.solid[c] < 0, "%s: a copy given the snapshot has the boards down" % map)
	# The next round.
	var rules := Modes.rules(g) as TacticalMode
	var st := Modes.feature(g)
	rules.begin_round(g, st)
	_check(
		(
			g.world.solid == built_solid
			and g.world.walls == built_walls
			and g.world.collision_volumes.size() == built_volumes
			and target.stage == 0
			and target.hp == target.most
			and fences.gaps.is_empty()
		),
		"%s: the next round stands the boards up again (walls, floor, furniture as built)" % map
	)
	_check(
		not RoundCover.broken(g),
		"%s: and nothing is left broken%s" % [map, " (a prop too)" if piece_broken else ""]
	)
	if before >= 0:
		_check(_steps(g, way[0], way[1]) == before, "%s: the step fields walk round again" % map)
	# A copy that missed the round's start: the snapshot alone stands it up.
	GameSnapshot.apply(g_copy, GameSnapshot.capture(g))
	_check(
		g_copy.world.solid == built_solid and g_copy.world.walls == built_walls,
		"%s: a copy that missed the round's start stands them up from the snapshot" % map
	)


static func _steps(g: Game, a: Vector2i, b: Vector2i) -> int:
	var f := TacticalNav.field(g, a.x + .5, a.y + .5)
	return TacticalNav.steps(f, b.x + .5, b.y + .5)
