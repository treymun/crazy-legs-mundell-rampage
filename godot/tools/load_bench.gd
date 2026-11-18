## How long each level takes to load, headless: the game made for it
## (Game.new and configure: the level read, its nav graph, its features
## attached), the first time in the session and again;
## the 3D view's level mesh (LevelMesh.build_static, what a window builds on
## the level's first frame and again whenever a wall opens), and the wreck
## pieces' cutting alone with their caches empty (WreckCuts: since the load
## pass it runs on a worker in the level's first frames, not in the load),
## and the 3D view's first frame of the level on a new view (headless: the
## level's mesh, its models loaded and made, its enemies' ragdoll rigs, its
## props' and pickups' looks; the rigs' and pictures' caches emptied as on a
## first visit;
## without a window its models load on the main thread, as before pass 10).
##
##   godot --headless --path godot --script res://tools/load_bench.gd [-- levels=a,b] [rounds=3]
##
## Prints a row per level (medians of `rounds`) and the totals.
extends SceneTree

const LEVELS := [
	"hickston",
	"fair",
	"sawmill",
	"quarry",
	"bayou",
	"speedway",
	"moonshine",
	"mothership",
	"hub",
	"range",
	"county_hickston",
	"county_bayou",
	"county_quarry",
	"grainyard",
	"salvage",
	"pineacres",
]


func _init() -> void:
	_run.call_deferred()


func _median(values: Array) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


func _run() -> void:
	var levels: Array = LEVELS.duplicate()
	var rounds := 3
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("levels="):
			levels = Array(arg.substr(7).split(",", false))
		elif arg.begins_with("rounds="):
			rounds = int(arg.substr(7))
	var t_start := Time.get_ticks_usec()
	var assets := Assets.new()
	var hud := HUD.new(assets)
	var sound := Sound.new(assets)
	root.add_child(sound)
	print(
		"ASSETS    %.1f ms (Assets, HUD, Sound made)" % [(Time.get_ticks_usec() - t_start) / 1000.0]
	)
	var options := SessionStore.settings("")
	var totals := [0.0, 0.0, 0.0, 0.0, 0.0]
	var canvas := Canvas.new()
	for level: String in levels:
		var cold: Array = []
		var warm: Array = []
		var mesh: Array = []
		var cuts: Array = []
		var views: Array = []
		for r in rounds:
			# Cold: the wreck pieces' and nav graphs' caches empty, as on a
			# level's first visit (warm: played again, a retry or a load).
			WreckCuts.clear()
			var navs: Variant = (LevelGeometry as Script).get("_navs")
			if navs is Dictionary:
				(navs as Dictionary).clear()
			var t0 := Time.get_ticks_usec()
			var game := Game.new(assets, hud, sound, level)
			game.configure(options)
			var t1 := Time.get_ticks_usec()
			var again := Game.new(assets, hud, sound, level)
			again.configure(options)
			var t2 := Time.get_ticks_usec()
			var builder := LevelMesh.new(game.level)
			var parts := builder.build_static(game.level.active_base(false))
			var t3 := Time.get_ticks_usec()
			# The cutting alone (the keys the wreckage feature cut at load).
			var keys := _wreck_keys(game)
			WreckCuts.clear()
			var t4 := Time.get_ticks_usec()
			for key: String in keys:
				WreckCuts.parts(assets, key)
			var t5 := Time.get_ticks_usec()
			# The view's first frame, on a new view with no rigs found yet.
			RagdollRig._built.clear()
			assets._art_cache.clear()
			var view := WorldView3D.new(assets)
			root.add_child(view)
			game.draw(canvas, 0, true)
			var t6 := Time.get_ticks_usec()
			view.frame(game)
			var t7 := Time.get_ticks_usec()
			view.free()
			views.append((t7 - t6) / 1000.0)
			cold.append((t1 - t0) / 1000.0)
			warm.append((t2 - t1) / 1000.0)
			mesh.append((t3 - t2) / 1000.0)
			cuts.append((t5 - t4) / 1000.0)
			if r == rounds - 1:
				print(
					(
						(
							"%-16s cold %7.1f  warm %7.1f  mesh %6.1f (%d chunks)  cuts %6.1f"
							+ " (%d kinds)  view %6.1f ms"
						)
						% [
							level,
							_median(cold),
							_median(warm),
							_median(mesh),
							parts.size(),
							_median(cuts),
							keys.size(),
							_median(views)
						]
					)
				)
		totals[0] += _median(cold)
		totals[1] += _median(warm)
		totals[2] += _median(mesh)
		totals[3] += _median(cuts)
		totals[4] += _median(views)
	print(
		(
			"TOTAL            cold %7.1f  warm %7.1f  mesh %6.1f  cuts %6.1f  view %6.1f ms"
			% [totals[0], totals[1], totals[2], totals[3], totals[4]]
		)
	)
	quit()


## The wreck cut keys of the level's breakables (wreckage.gd _source).
func _wreck_keys(game: Game) -> Array:
	var out := {}
	var wreck: Object = game.features.get("wreckage")
	var pieces: Object = game.features.get("breakables")
	if wreck == null or pieces == null or not bool(wreck.get("on")):
		return []
	for p: Object in pieces.get("pieces"):
		var src: Dictionary = wreck.call("_source", p)
		if not src.is_empty():
			out[str(src["key"])] = true
	return out.keys()
