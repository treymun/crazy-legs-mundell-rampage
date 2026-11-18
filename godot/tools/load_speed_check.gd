## Pass 10's load speed held headless (PERFLOAD; docs/dev/checks.md
## "Benchmarks", view3d.md "The warm-up"):
## - every actor kind's baked ragdoll rig (assets3d/actors/<kind>.rig,
##   RagdollRig.baked) is the rig found from its model, field for field and
##   bit for bit (tools/rig_reference.gd, the build as it was); a stale one
##   names tools/art/bake_rigs.gd;
## - the cues made in code (Assets.MADE_CUES), packed by pack_assets.gd
##   (made_cues.bin), are the samples made at once;
## - the title's warm-up (WorldView3D.warm_title) draws every view3d shader
##   but the sky's (which draws itself) and takes its pieces away;
## - each chapter's load (start() and the view's first frame) finds no rig
##   from vertices, leaves no model asked of the loader untaken, and keeps
##   within its time budget; no model's looks are kept as pixels beside the
##   texture made from them (Assets.art_for_texture); visiting the chapters
##   again keeps memory within its ceiling and grows it by no more than
##   GROWTH_MB.
##
##   Godot --headless --path <project> --script res://tools/load_speed_check.gd [-- report]
##
## Prints LOAD SPEED OK, or what failed. `report` prints each chapter's times.
extends SceneTree

const RigReference := preload("res://tools/rig_reference.gd")
const CHAPTERS := [
	"hickston", "fair", "sawmill", "quarry", "bayou", "speedway", "moonshine", "mothership"
]
const RIG_FIELDS := [
	"ok",
	"points",
	"radii",
	"bone_seg",
	"bone_rest",
	"dead_scale",
	"anchors",
	"rest_frames",
	"down_points",
	"lying_points",
	"hull",
	"hull_reach",
	"_rest_inv"
]
## The eight chapters' first visits, headless, in ms: start() (the game
## made) and the view's first frame (the level's mesh, its models, rigs and
## looks). Desktop 2026-11-17: about 1,400 and 1,250, beside other work
## (the rigs found from vertices instead cost 1,100 more); CI's runners are
## slower and run two checks at once. The rigs and models are held by the
## counts above; these catch a load grown several times over.
const START_MS := 7000.0
const VIEW_MS := 6000.0
## Static memory after the chapters twice (MB; desktop about 570), and what
## the second round may add to the first's.
const MEMORY_MB := 900.0
const GROWTH_MB := 40.0

var failures: Array = []
var report := false
var main


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


func _run() -> void:
	report = OS.get_cmdline_user_args().has("report")
	_cues()
	_rigs()
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.touring = true
	var view := WorldView3D.new(main.art)
	main.add_child(view)
	_title(view)
	await _loads(view)
	_done()


## MADE_CUES from the packs against the same made at once.
func _cues() -> void:
	var art := Assets.new()
	var same := 0
	for name: String in Assets.MADE_CUES:
		var made := art.cue(name) as AudioStreamWAV
		if made != null and made.data == Assets._synth(name, art.sfx_rate):
			same += 1
	_check(
		same == Assets.MADE_CUES.size(),
		(
			"the cues packed are the samples made at once (%d of %d; run pack_assets.gd if not)"
			% [same, Assets.MADE_CUES.size()]
		)
	)


## Every kind's baked rig against the rig found from its model.
func _rigs() -> void:
	var models := ActorModels.new(Assets.new())
	var stale := PackedStringArray()
	var kinds := 0
	for kind: String in models.kinds:
		var packed := models.scene(kind)
		if packed == null:
			continue
		kinds += 1
		var info: Dictionary = models.kinds[kind]
		var view := packed.instantiate()
		var baked := RagdollRig.baked(kind, view, info)
		var found: Object = RigReference.new()
		found.call("_build", view, info)
		view.free()
		if baked == null:
			stale.append(kind + " (none)")
			continue
		for field: String in RIG_FIELDS if baked.ok else ["ok"]:
			var a: Variant = baked.get(field)
			var b: Variant = found.get(field)
			if a != b or var_to_bytes(a) != var_to_bytes(b):
				stale.append("%s (%s)" % [kind, field])
				break
	_check(
		kinds >= 40 and stale.is_empty(),
		(
			"every kind's baked rig is its model's (%d kinds)%s"
			% [
				kinds,
				(
					""
					if stale.is_empty()
					else (": " + ", ".join(stale) + " - run tools/art/bake_rigs.gd")
				)
			]
		)
	)


## The title's warm-up: every view3d shader but the sky's drawn, then gone.
func _title(view: WorldView3D) -> void:
	var drawn := {}
	for make: Callable in view._title_pieces():
		var piece: Node3D = make.call()
		var node := piece as GeometryInstance3D
		var m := node.material_override as ShaderMaterial
		drawn[m.shader.resource_path.get_file()] = true
		piece.free()
	var missing := PackedStringArray()
	for file in DirAccess.get_files_at("res://src/view3d"):
		if file.get_extension() == "gdshader" and file != "sky.gdshader" and not drawn.has(file):
			missing.append(file)
	_check(
		missing.is_empty(),
		(
			"the title's warm-up draws every view3d shader but the sky's (%d)%s"
			% [drawn.size(), "" if missing.is_empty() else ": missing " + ", ".join(missing)]
		)
	)
	var calls := 0
	while view.warm_title() and calls < 100:
		calls += 1
	_check(
		calls > 10 and calls < 100 and view.get("_stage_left").is_empty(),
		"the title's warm-up puts out a piece a call and is done (%d calls)" % calls
	)


## Each chapter loaded twice over (start() and the view's first frame).
func _loads(view: WorldView3D) -> void:
	RagdollRig.found = 0
	var start_ms := 0.0
	var view_ms := 0.0
	var after_first := 0
	var dangling := PackedStringArray()
	var canvas := Canvas.new()
	for round in 2:
		for level: String in CHAPTERS:
			var t0 := Time.get_ticks_usec()
			main.start(level)
			var g: Game = main.game
			main.state = "play"
			var t1 := Time.get_ticks_usec()
			g.draw(canvas, 0, true)
			var t2 := Time.get_ticks_usec()
			view.frame(g)
			var t3 := Time.get_ticks_usec()
			if round == 0:
				start_ms += (t1 - t0) / 1000.0
				view_ms += (t3 - t2) / 1000.0
				if report:
					print(
						(
							"    %-10s start %6.1f  view's first frame %6.1f ms"
							% [level, (t1 - t0) / 1000.0, (t3 - t2) / 1000.0]
						)
					)
			for asked: Dictionary in [view.props.models._asked, view.actors.models._asked]:
				for name: String in asked:
					dangling.append("%s on %s" % [name, level])
			await process_frame
		if round == 0:
			after_first = OS.get_static_memory_usage()
	var after := OS.get_static_memory_usage()
	_check(
		RagdollRig.found == 0, "no chapter's load finds a rig from vertices (%d)" % RagdollRig.found
	)
	_check(
		dangling.is_empty(),
		(
			"every model asked of the loader is taken%s"
			% ("" if dangling.is_empty() else ": " + ", ".join(dangling))
		)
	)
	_check(
		start_ms < START_MS,
		"the chapters' starts within budget (%.0f ms, under %.0f)" % [start_ms, START_MS]
	)
	_check(
		view_ms < VIEW_MS,
		"the chapters' first view frames within budget (%.0f ms, under %.0f)" % [view_ms, VIEW_MS]
	)
	var kept := 0
	for name: String in main.art._art_cache:
		if name.begins_with("mesh_") or name.begins_with("actor3d_"):
			kept += 1
	_check(kept == 0, "no model's looks kept as pixels beside its texture (%d)" % kept)
	var grew := (after - after_first) / 1048576.0
	_check(
		after / 1048576.0 < MEMORY_MB and grew < GROWTH_MB,
		(
			(
				"memory within its ceiling after the chapters twice (%.0f MB, under %.0f;"
				+ " the second round %+.1f MB, under %.0f)"
			)
			% [after / 1048576.0, MEMORY_MB, grew, GROWTH_MB]
		)
	)


func _done() -> void:
	print("")
	print("LOAD SPEED OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)
