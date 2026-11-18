## The chapter openers' camera, headless (src/opener_camera.gd, the shots in
## data/tuning/openers.json):
##
##   Godot --headless --path <project> --script res://tools/opener_camera_check.gd [-- report]
##
## Every chapter's opener sampled sixty times a second from start to end:
## - no sample is inside a wall, a roof, a deck, a prop or the ground, nor
##   skimming them (OpenerCamera.clear_at; the landing's last fifth, the
##   player's own spot, only of walls' insides, roofs and the ground);
## - between cuts the camera turns at most MAX_TURN degrees a second and tilts
##   at most MAX_TILT, never flies faster than MAX_SPEED, and its velocity is
##   continuous (no change faster than MAX_ACCEL cells a second squared, so no
##   jolt, kink or jump); it leans at most OpenerCamera.BANK_MAX;
## - it ends in the player's own eye (place, heading and horizon) and leaves
##   no picture of him in the way as it comes down.
## `report` prints each chapter's numbers too. Fails on any script error.
extends SceneTree

const MAX_TURN := 45.0
const MAX_TILT := 30.0
const MAX_SPEED := 8.0
const MAX_ACCEL := 12.0
const STEP := 1.0 / 60.0

var failures: Array = []
var main


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	var report := OS.get_cmdline_user_args().has("report")
	var op: ChapterOpener = main.opener
	op.tools_write = true
	op.seen_path = OS.get_cache_dir().path_join("clmr_opener_camera_check_seen.json")
	main.options["openers"] = ChapterOpener.ALWAYS
	main.apply_options()
	var tally := CrashLog.tally()
	var hits: Array = []
	var fast: Array = []
	var rough: Array = []
	var ends: Array = []
	for id: String in Campaign.ORDER:
		main.start(id)
		main.state = "play"
		var g: Game = main.game
		if not op.start(main):
			hits.append(id + " (no opener)")
			continue
		var m := _measure(op, g)
		if report:
			print(
				(
					"  %-10s %4.1f s  turn %4.1f deg/s  tilt %4.1f  speed %4.1f  accel %5.1f  lean %.1f deg  %s"
					% [
						id,
						op.length,
						m["turn"],
						m["tilt"],
						m["speed"],
						m["accel"],
						rad_to_deg(m["lean"]),
						m["hits"].slice(0, 3)
					]
				)
			)
		for h: String in m["hits"].slice(0, 4):
			hits.append("%s %s" % [id, h])
		if m["turn"] > MAX_TURN or m["tilt"] > MAX_TILT or m["speed"] > MAX_SPEED:
			fast.append(
				"%s turn %.0f tilt %.0f speed %.1f" % [id, m["turn"], m["tilt"], m["speed"]]
			)
		if m["accel"] > MAX_ACCEL or m["lean"] > OpenerCamera.BANK_MAX + .0001:
			rough.append(
				"%s accel %.1f at %.2f s, lean %.3f" % [id, m["accel"], m["accel_at"], m["lean"]]
			)
		var last := op.eye_at(op.length)
		var mine := g.player.as_render_player()
		var off := Vector3(last["x"], last["y"], last["eye"]).distance_to(
			Vector3(mine["x"], mine["y"], mine["eye"])
		)
		var turn := absf(angle_difference(float(last["view_angle"]), float(mine["view_angle"])))
		var tilt := absf(float(last["pitch"]) - float(mine["pitch"]))
		if off > .001 or turn > .001 or tilt > .01 or not last.get("hide_player", false):
			ends.append("%s (%.3f cells, %.3f rad, %.2f px)" % [id, off, turn, tilt])
		op.stop(main)
	_check(
		hits.is_empty(),
		"no camera sample is in or skims a wall, roof, prop or the ground %s" % [hits]
	)
	_check(
		fast.is_empty(),
		(
			"no turn over %.0f deg/s, tilt over %.0f deg/s or speed over %.0f cells/s %s"
			% [MAX_TURN, MAX_TILT, MAX_SPEED, fast]
		)
	)
	_check(
		rough.is_empty(),
		(
			"smooth between cuts: velocity changes under %.0f cells/s^2, a gentle lean %s"
			% [MAX_ACCEL, rough]
		)
	)
	_check(
		ends.is_empty(),
		"every opener lands in the player's own eye, his picture out of the way %s" % [ends]
	)
	tally.stop()
	_check(
		tally.errors == 0,
		(
			"no script or engine errors"
			+ ("" if tally.errors == 0 else " (%d: %s)" % [tally.errors, tally.first_errors[0]])
		)
	)
	DirAccess.remove_absolute(op.seen_path)
	print("")
	print("OPENER CAMERA OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


## The opener sampled every STEP: what it hits, and its fastest turn, tilt,
## speed, change of velocity and lean between cuts.
func _measure(op: ChapterOpener, g: Game) -> Dictionary:
	var out := {"hits": [], "turn": 0.0, "tilt": 0.0, "speed": 0.0, "accel": 0.0, "accel_at": 0.0}
	out["lean"] = 0.0
	var focal := View.base_focal
	var prev: Dictionary = {}
	var prev_v := Vector3.INF
	var prev_span := Vector2(-1, -1)
	var t := 0.0
	var last_hit := -1.0
	while t <= op.length + .0001:
		var e := op.eye_at(t)
		var p := Vector3(e["x"], e["y"], e["eye"])
		var near := t < op.land_at + OpenerCamera.LAND * .8
		var hit := OpenerCamera.clear_at(g.world, p.x, p.y, p.z, near)
		if hit != "" and t - last_hit > .5:
			out["hits"].append("%.2f s %s (%.1f, %.1f, %.1f)" % [t, hit, p.x, p.y, p.z])
			last_hit = t
		out["lean"] = maxf(out["lean"], absf(float(e.get("roll", 0.0))))
		var span := op.camera.span(t)
		if not prev.is_empty() and span == prev_span:
			var q := Vector3(prev["x"], prev["y"], prev["eye"])
			var v := (p - q) / STEP
			var turn := absf(angle_difference(float(prev["view_angle"]), float(e["view_angle"])))
			var tilt := absf(atan(float(e["pitch"]) / focal) - atan(float(prev["pitch"]) / focal))
			out["turn"] = maxf(out["turn"], rad_to_deg(turn / STEP))
			out["tilt"] = maxf(out["tilt"], rad_to_deg(tilt / STEP))
			out["speed"] = maxf(out["speed"], v.length())
			if prev_v != Vector3.INF:
				var accel := (v - prev_v).length() / STEP
				if accel > out["accel"]:
					out["accel"] = accel
					out["accel_at"] = t
			prev_v = v
		else:
			prev_v = Vector3.INF
		prev = e
		prev_span = span
		t += STEP
	return out
