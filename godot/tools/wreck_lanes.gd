## The ways each toppling prop of the boss arenas' wrecks can go over on open
## floor (bosses.cfg [arena_wreck] "spots"), the clearest toward its boss first:
## to pick a way when adding or moving a step.
##
##   godot --headless --path godot --script res://tools/wreck_lanes.gd
extends SceneTree


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	for kind: String in ArenaWreckFeature.ARENAS:
		var g: Game = BossRematch.build(Callable(main, "make_game"), kind)
		var e := BossFight.of_kind(g, kind)
		var steps: Array = ArenaWreckFeature.ARENAS[kind]
		for step: Dictionary in steps:
			if str(step["do"]) != "topple":
				continue
			for spot: Array in step["spots"]:
				var board: LevelData.Billboard = null
				for b: LevelData.Billboard in g.world.billboards:
					if (
						b.image == str(step["image"])
						and absf(b.x - spot[0]) < .6
						and absf(b.y - spot[1]) < .6
					):
						board = b
				if board == null:
					print("%s %s %s: NOT FOUND" % [kind, step["image"], spot])
					continue
				var want := atan2(e.y - board.y, e.x - board.x)
				var ways: Array = []
				for k in 32:
					var a := k * TAU / 32.0
					var first := lane(g.world, board, a)
					if first < 0.0:
						ways.append([absf(angle_difference(a, want)), snappedf(a, .01)])
				ways.sort()
				var dir: float = spot[2]
				print(
					(
						"%s %s %s: now %.2f blocked at %.1f; clear ways %s"
						% [
							kind,
							step["image"],
							spot,
							dir,
							lane(g.world, board, dir),
							ways.slice(0, 5)
						]
					)
				)
	main.queue_free()
	await process_frame
	quit()


## How far along way `a` the first thing in the way is (-1: the whole prop's
## length is clear).
## Its own base (ArenaWreckFeature.base_at) is out of the way by then.
static func lane(w: LevelData, board: LevelData.Billboard, a: float) -> float:
	var base := ArenaWreckFeature.base_at(w, board.x, board.y)
	if not base.is_empty():
		w.drop_volume(base)
	var found := -1.0
	var length := board.height * .95
	var along := .7
	while along <= length and found < 0.0:
		var x := board.x + cos(a) * along
		var y := board.y + sin(a) * along
		if w.blocked(x, y, .3, w.elevation(x, y) + .3):
			found = along
		along += .3
	if not base.is_empty():
		ArenaWreckFeature.add_volume(w, base)
	return found
