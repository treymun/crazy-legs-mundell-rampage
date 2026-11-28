## The actors' models and how they move (polish pass 9; tools/check_all.gd
## runs it):
##
##   godot --headless --path godot --script res://tools/actor_check.gd [-- report]
##
## JSON: every kind in assets3d/actors/actors.json has its glb, scene and every
## look's texture (square, a power of two), keys numbered 0..n-1 once each,
## bone labels from the six, the cels' canvas; fit.json names only models and
## only numbers ActorModels reads. ANIM: every kind has the frames the game
## asks for (a hand: idle, the four-beat walk and back, aim, fire, pain, the
## five-step fall, down, and the hurt set when it has the hurt look; a boss
## its wind-up and recover; a critter its -1, 0, 1). TEXELS: each model's
## texels a metre over its whole body and over its head (the triangles bound to
## head bones): every model at least TEXEL_MIN, a hand (a kind with the hurt
## look) HAND_MIN and its head HEAD_MIN, a boss BOSS_MIN and BOSS_HEAD_MIN,
## so no face or belly is a few blocky texels beside the crisp ones.
## MOTION: ActorView's looks-only motion: a jump between poses blends (part way
## at half the blend, exactly the new key after it), the walk does not blend
## between its beats, a hit rocks the body by where it struck and is still
## again after ActorView.FLINCH, no two hits the same, an idle body breathes, a
## scripted fall is mirrored for about half the deaths and never for a boss,
## and none of it draws on game.rng; thrown specks keep between
## View.SPECK_PX_MIN and SPECK_PX_MAX pixels; a partner on the riding mower
## sits on it (vehicles.cfg `pose`).
## HOUND (pass 10): BLUE's fourteen motions of five keys in a row and his
## ten poses (src/hound_looks.gd plays them), his texels over him and his
## head, a motion played on the gait, a one-shot ending on its last key and
## his own longer blend between poses.
## `report` prints every kind's texels a metre.
extends SceneTree

const VehiclesFeature := preload("res://src/features/vehicles.gd")

## Texels a metre (the square root of a model's texels over its surface).
## The regular hands kept their v3.0.0 unwrap (smart project's .01 gaps) until
## pass 9, 41 to 73 a metre; packed (export_actors.py GAP, the head given
## HEAD more across) they are 90 to 145, their heads 120 to 190. The biggest
## bosses at 512 (Jerry, the foreman) were about 73 until pass 13 baked them
## (and Rudy, 86) again at 1024: a boss (a kind with the p2 look) now has
## BOSS_MIN over its body and BOSS_HEAD_MIN over its head, so no boss is
## blurrier than the hands round it.
const TEXEL_MIN := 70.0
const HAND_MIN := 85.0
const HEAD_MIN := 110.0
const BOSS_MIN := 90.0
const BOSS_HEAD_MIN := 90.0
## The razorback bakes at 256 for the browser's first download: no floor.
const TEXEL_FREE := ["hog"]
const LABELS := ["head", "arm_r", "arm_l", "leg_r", "leg_l", "body"]
const FIT_KEYS := [
	"light",
	"scale",
	"min_px",
	"ragdoll",
	"tips",
	"flat",
	"down_high",
	"down_cel",
	"blend",
	"yaw",
	"beast",
	"hand_over"
]
const HAND_FRAMES := [
	"0",
	"w0",
	"w1",
	"w2",
	"w3",
	"w4",
	"aim",
	"fire",
	"pain",
	"die_0",
	"die_1",
	"die_2",
	"die_3",
	"die_4",
	"down"
]
const HURT_FRAMES := ["hurt_0", "hurt_w0", "hurt_w4", "hurt_aim", "hurt_fire", "hurt_pain"]
const CRITTER_FRAMES := ["-1", "0", "1", "aim", "fire", "pain"]
## BLUE's motions (scripts/blender/actors_hound.py, pass 10), five keys
## each, and his poses: src/hound_looks.gd plays every one of them.
const HOUND_RUNS := ["i", "w", "t", "r", "l", "n", "c", "k", "f", "o", "v", "u", "j", "p"]
const HOUND_POSES := ["0", "sit", "sniff", "point", "bark", "bay", "pain", "fetch", "rest", "down"]
## His texels a metre: the pass 10 model at 512 measured 202 over him and
## 270 on his head (export_actors.py gives his head 1.4 times its share
## across; the content pass 8 dog had 151 and no head of its own): floors a
## little under.
const HOUND_MIN := 180.0
const HOUND_HEAD_MIN := 240.0
## His size against Mundell (a co-op partner's model as the world draws
## it): a bluetick's shoulder is about .37 of a man's height and the top of
## his head about .46 (HoundLooks.SIZE). Before the size fix he was drawn
## .69 and .85: near the man's height.
const HOUND_SHOULDER := [.33, .41]
const HOUND_HEAD_TOP := [.41, .52]

var failures: Array[String] = []
var passes := 0
var report := false


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, text: String) -> void:
	if not ok:
		print("  FAIL ", text)
		failures.append(text)
	else:
		passes += 1


func _run() -> void:
	report = OS.get_cmdline_user_args().has("report")
	var assets := Assets.new()
	var models := ActorModels.new(assets)
	print("JSON")
	_json(models, assets)
	print("ANIM")
	_anim(models)
	print("TEXELS")
	_texels(models, assets)
	print("MOTION")
	_motion(models, assets)
	print("%d checks" % (passes + failures.size()))
	print("ACTOR CHECK OK" if failures.is_empty() else "%d ACTOR CHECK(S) FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)


func _json(models: ActorModels, assets: Assets) -> void:
	for kind: String in models.kinds:
		var info: Dictionary = models.kinds[kind]
		_check(
			FileAccess.file_exists(ActorModels.FOLDER.path_join(kind + ".glb")), kind + ": no glb"
		)
		_check(models.scene(kind) != null, kind + ": no scene")
		var textures: Array = info.get("textures", [])
		_check(textures.size() > 0 and str(textures[0]) == "", kind + ": no plain look")
		for look: String in textures:
			var name := "actor3d_" + kind + ("" if look == "" else "_" + look)
			if not assets.has_art(name):
				_check(false, "%s: no art %s" % [kind, name])
				continue
			var art := assets.art(name)
			var w: int = art["w"]
			var h: int = art["h"]
			_check(
				w == h and w >= 128 and (w & (w - 1)) == 0,
				"%s: look %s is %dx%d" % [kind, name, w, h]
			)
		var frames: Dictionary = info.get("frames", {})
		var keys: Array[int] = []
		for name: String in frames:
			var key: float = frames[name]
			keys.append(int(key))
		keys.sort()
		var numbered := true
		for i in keys.size():
			numbered = numbered and keys[i] == i
		_check(numbered and keys.size() > 0, kind + ": keys not numbered 0..n-1 once each")
		var labels: Dictionary = info.get("labels", {})
		var bad := 0
		for bone: String in labels:
			bad += 0 if str(labels[bone]) in LABELS else 1
		_check(bad == 0, "%s: %d bones with a label not one of %s" % [kind, bad, LABELS])
		var canvas: Array = info.get("canvas", [])
		_check(canvas.size() == 2 and float(canvas[1]) > .1, kind + ": no canvas (the cels' size)")
	var fit: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(ActorModels.FOLDER.path_join("fit.json"))
	)
	_check(fit is Dictionary, "fit.json: not a dictionary")
	if fit is Dictionary:
		var fits: Dictionary = fit
		for kind: String in fits:
			_check(models.kinds.has(kind), "fit.json: %s is not a model" % kind)
			var own: Dictionary = fits[kind]
			for key: String in own:
				_check(key in FIT_KEYS, "fit.json %s: %s is not read" % [kind, key])
			var light: float = own.get("light", 1.0)
			_check(light >= .9 and light <= 1.45, "fit.json %s: light %.2f" % [kind, light])


func _anim(models: ActorModels) -> void:
	for kind: String in models.kinds:
		var info: Dictionary = models.kinds[kind]
		var frames: Dictionary = info["frames"]
		var textures: Array = info.get("textures", [])
		var want: Array = []
		if frames.has("w0") and frames.has("aim"):
			want = HAND_FRAMES.duplicate()
			if info.get("down_cel", false):
				# Its body at rest is a cel of its own (ActorLayer3D.takes).
				for name: String in ["die_0", "die_1", "die_2", "die_3", "die_4", "down"]:
					want.erase(name)
			if "hurt" in textures:
				want.append_array(HURT_FRAMES)
			if "p2" in textures:
				want.append("recover")
		elif frames.has("-1"):
			want = CRITTER_FRAMES.duplicate() if frames.has("aim") else ["-1", "0", "1"]
		elif kind == "hound":
			want = HOUND_POSES.duplicate()
			for run: String in HOUND_RUNS:
				for beat in 5:
					want.append(run + str(beat))
		elif frames.has("r0"):
			want = ["0", "r0", "r1", "r2", "r3", "r4", "down"]
		else:
			want = ["0"]
		var missing: Array = []
		for name: String in want:
			if not frames.has(name):
				missing.append(name)
		_check(missing.is_empty(), "%s: no frames %s" % [kind, missing])
		# The walk and the gallop each run their beats in a row (ActorView
		# seeks between them on the gait).
		var runs: Array = ["w", "r", "hurt_w"]
		if kind == "hound":
			runs = HOUND_RUNS
		for run: String in runs:
			if frames.has(run + "0"):
				var first: float = frames[run + "0"]
				var row := true
				for beat in 5:
					var at: Variant = frames.get(run + str(beat))
					row = row and at != null and int(at) == int(first) + beat
				_check(row, "%s: %s0..%s4 not keys in a row" % [kind, run, run])
		if frames.has("die_0") and frames.has("die_4"):
			var fall: float = frames["die_0"]
			var last: float = frames["die_4"]
			_check(int(last) == int(fall) + 4, kind + ": die_0..die_4 not keys in a row")


func _texels(models: ActorModels, assets: Assets) -> void:
	var rows: Array = []
	for kind: String in models.kinds:
		var info: Dictionary = models.kinds[kind]
		var packed := models.scene(kind)
		if packed == null:
			continue
		var view := packed.instantiate()
		var size: int = (
			assets.art("actor3d_" + kind)["w"] if assets.has_art("actor3d_" + kind) else 512
		)
		var labels: Dictionary = info.get("labels", {})
		var sums := [0.0, 0.0, 0.0, 0.0]
		for child in view.find_children("*", "MeshInstance3D", true, false):
			var mi := child as MeshInstance3D
			if mi.mesh == null:
				continue
			for surface in mi.mesh.get_surface_count():
				_surface_area(mi, surface, labels, sums)
		view.free()
		var body := sqrt(sums[1] / maxf(sums[0], 1e-9)) * size
		var head := sqrt(sums[3] / maxf(sums[2], 1e-9)) * size if sums[2] > 0.0 else body
		rows.append([kind, body, head, size])
		if report:
			print("  %-14s %4d  texels a metre %4d  head %4d" % [kind, size, body, head])
		if kind in TEXEL_FREE:
			continue
		var hand := "hurt" in (info.get("textures", []) as Array)
		var boss := "p2" in (info.get("textures", []) as Array)
		var least := (
			HAND_MIN if hand else BOSS_MIN if boss else HOUND_MIN if kind == "hound" else TEXEL_MIN
		)
		_check(body >= least, "%s: %d texels a metre (at least %d)" % [kind, body, least])
		if kind == "hound":
			_check(
				sums[2] > 0.0 and head >= HOUND_HEAD_MIN,
				"hound: head %d texels a metre (at least %d)" % [head, HOUND_HEAD_MIN]
			)
		if (hand or boss) and sums[2] > 0.0:
			var head_least := HEAD_MIN if hand else BOSS_HEAD_MIN
			_check(
				head >= head_least,
				"%s: head %d texels a metre (at least %d)" % [kind, head, head_least]
			)
	print("  %d models measured" % rows.size())


## Adds a surface's [3D area, UV area, head 3D area, head UV area].
func _surface_area(mi: MeshInstance3D, surface: int, labels: Dictionary, sums: Array) -> void:
	var arrays := mi.mesh.surface_get_arrays(surface)
	var at: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	# Into the scene's units (map units: the glb's nodes may scale the mesh).
	var place := Transform3D.IDENTITY
	var node: Node = mi
	while node != null:
		if node is Node3D and node.get_parent() != null:
			place = (node as Node3D).transform * place
		node = node.get_parent()
	at = place * at
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if uv.is_empty():
		return
	var ids: PackedInt32Array = (
		arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
	)
	var weights: PackedFloat32Array = (
		arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
	)
	var per := ids.size() / maxi(1, at.size())
	var heads := {}
	if mi.skin != null:
		var skeleton := mi.get_node_or_null(mi.skeleton) as Skeleton3D
		for b in mi.skin.get_bind_count():
			var bone_name := String(mi.skin.get_bind_name(b))
			if bone_name == "" and skeleton != null:
				bone_name = skeleton.get_bone_name(mi.skin.get_bind_bone(b))
			if str(labels.get(bone_name, "")) == "head":
				heads[b] = true
	var count := index.size() if not index.is_empty() else at.size()
	for t in range(0, count - 2, 3):
		var a := index[t] if not index.is_empty() else t
		var b := index[t + 1] if not index.is_empty() else t + 1
		var c := index[t + 2] if not index.is_empty() else t + 2
		var area := (at[b] - at[a]).cross(at[c] - at[a]).length() * .5
		var e1 := uv[b] - uv[a]
		var e2 := uv[c] - uv[a]
		var uv_area := absf(e1.x * e2.y - e1.y * e2.x) * .5
		if area < 1e-10 or uv_area <= 0.0:
			continue
		sums[0] += area
		sums[1] += uv_area
		if per > 0 and not heads.is_empty():
			var best := 0
			var most := -1.0
			for k in per:
				if weights[a * per + k] > most:
					most = weights[a * per + k]
					best = ids[a * per + k]
			if heads.has(best):
				sums[2] += area
				sums[3] += uv_area


## ActorView on a real game's level: blends, flinches, breath, falls.
func _motion(models: ActorModels, assets: Assets) -> void:
	var hud := HUD.new(assets)
	var sound := Sound.new(assets)
	root.add_child(sound)
	var game := Game.new(assets, hud, sound, "hickston")
	var level := game.level
	var rng_before := game.rng.state
	var view := models.scene("billy").instantiate() as ActorView
	root.add_child(view)
	_check(view.setup(models), "billy: cannot pose")
	var e := Enemy.new("billy", 10.0, 10.0, 0.0)
	e.uid = 7
	var s := View.Sprite.new()
	s.x = e.x
	s.y = e.y
	var skeleton := view.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var clock := 100.0
	s.image = "billy_0"
	view.show_as(s, e, level, clock)
	var idle := _pose(skeleton)
	# Idle to aim: part way at half the blend, exactly aim after it.
	s.image = "billy_aim"
	view.show_as(s, e, level, clock + .001)
	var start := _pose(skeleton)
	_check(_far(start, idle) < .001, "blend: the first draw of a new pose jumped")
	view.show_as(s, e, level, clock + ActorView.BLEND * .5)
	var half := _pose(skeleton)
	view.show_as(s, e, level, clock + ActorView.BLEND + .01)
	var aim := _pose(skeleton)
	_check(_far(aim, idle) > .01, "blend: aim is not another pose than idle")
	_check(
		_far(half, idle) > .002 and _far(half, aim) > .002,
		"blend: half way through it is not between idle and aim"
	)
	view._player.seek(models.key_time("billy", "aim"), true)
	_check(_far(_pose(skeleton), aim) < 1e-4, "blend: after it the pose is not aim's key")
	# The walk's beats do not blend: each draw is the gait's place.
	s.image = "billy_w0"
	e.gait = 0.0
	view.show_as(s, e, level, clock + 1.0)
	view.show_as(s, e, level, clock + 1.0 + ActorView.BLEND + .01)
	e.gait = PI * .5
	s.image = "billy_w1"
	view.show_as(s, e, level, clock + 1.3)
	var walked := _pose(skeleton)
	view._player.seek(models.key_time("billy", "w1"), true)
	_check(_far(walked, _pose(skeleton)) < 1e-4, "walk: blended between its beats")
	# Sprite cels are selected by observer angle. The model stays on the same activity.
	e.mind = Squad.Mind.new()
	e.mind.spot = Vector2(e.x, e.y)
	e.mind.activity = "chopping"
	e.pose = 0.0
	e.mind.phase = 0.0
	s.image = "billy_aim"
	view.show_as(s, e, level, clock + 1.4)
	view.show_as(s, e, level, clock + 1.6)
	var front := _pose(skeleton)
	s.image = "billy_back_0"
	view.show_as(s, e, level, clock + 1.6)
	_check(_far(front, _pose(skeleton)) < 1e-4, "idle: the model kept its pose as the view moved")
	e.mind = null
	# A hit rocks it: by the zone, its own dice, still again after FLINCH.
	s.image = "billy_0"
	view.show_as(s, e, level, clock + 2.0)
	e.struck_at = clock + 3.0
	e.struck_sum = 30.0
	var leans: Array[Transform3D] = []
	for zone: String in ["head", "body", "arms", "legs"]:
		e.last_zone = zone
		leans.append(ActorView.flinch(e, ActorView.FLINCH_RISE))
	for i in leans.size():
		_check(
			leans[i].basis.get_euler().length() > .03,
			"flinch: a %s hit does not rock the body" % ["head", "body", "arms", "legs"][i]
		)
	_check(
		leans[0].basis.get_euler().x != leans[3].basis.get_euler().x,
		"flinch: a head hit and a leg hit rock it alike"
	)
	e.last_zone = "body"
	var one := ActorView.flinch(e, .1)
	_check(one.is_equal_approx(ActorView.flinch(e, .1)), "flinch: the same hit rocks it two ways")
	e.struck_at += .5
	_check(not one.is_equal_approx(ActorView.flinch(e, .1)), "flinch: two hits rock it alike")
	_check(
		ActorView.flinch(e, ActorView.FLINCH - .0001).basis.get_euler().length() < .002,
		"flinch: still rocking at its end"
	)
	view.show_as(s, e, level, e.struck_at + ActorView.FLINCH_RISE)
	var rocked := view.transform
	view.show_as(s, e, level, e.struck_at + ActorView.FLINCH + .2)
	var after := view.transform
	_check(not rocked.basis.is_equal_approx(after.basis), "flinch: the drawn body does not rock")
	# Idle breathes (its height changes a touch), not the walk.
	var tall := []
	for t in [0.0, .4, .8, 1.2]:
		view.show_as(s, e, level, clock + 10.0 + t)
		tall.append(view.transform.basis.y.length())
	_check(absf(float(tall.max()) - float(tall.min())) > .002, "idle: the body stands stock still")
	var was := View.ragdolls
	View.ragdolls = true
	view.live_ok = true
	e.died_at = clock + 12.0
	e.hp = 0.0
	s.image = "billy_die_0"
	view.show_as(s, e, level, e.died_at + .01)
	_check(
		view.doll != null and not (view.doll is DyingDoll),
		"fall: a nearby hand switches straight to a passive ragdoll"
	)
	# A scripted fall: mirrored for about half the deaths, never a boss's.
	View.ragdolls = false
	var mirrored := 0
	for uid in 40:
		e.uid = uid
		e.hp = 0.0
		e.died_at = clock + 20.0 + uid
		s.image = "billy_die_1"
		view.revive()
		view.show_as(s, e, level, e.died_at + .1)
		mirrored += 1 if view.transform.basis.determinant() < 0.0 else 0
	_check(mirrored > 8 and mirrored < 32, "fall: %d of 40 deaths mirrored" % mirrored)
	View.ragdolls = was
	view.queue_free()
	if models.kinds.has("boss"):
		var boss_view := models.scene("boss").instantiate() as ActorView
		root.add_child(boss_view)
		boss_view.setup(models)
		var b := Enemy.new("boss", 10.0, 10.0, 0.0)
		var flipped := 0
		for uid in 12:
			b.uid = uid
			b.hp = 0.0
			b.died_at = clock + uid
			var bs := View.Sprite.new()
			bs.x = b.x
			bs.y = b.y
			bs.image = "boss_die_1"
			boss_view.show_as(bs, b, level, b.died_at + .1)
			flipped += 1 if boss_view.transform.basis.determinant() < 0.0 else 0
		_check(flipped == 0, "fall: a boss's set piece fall mirrored")
		boss_view.queue_free()
	_hound_motion(models, level)
	_hound_size(models)
	_check(game.rng.state == rng_before, "looks: the actors' motion drew on game.rng")
	# Specks: never under SPECK_PX_MIN of the view's pixels far off, nor over
	# SPECK_PX_MAX right in front; their own size between.
	for d in [.3, 1.0, 3.0, 8.0, 20.0, 40.0]:
		var px: float = View.speck_size(d) * View.base_focal / d
		_check(
			px >= View.SPECK_PX_MIN - .001 and px <= View.SPECK_PX_MAX + .001,
			"specks: %.1f pixels at %.0f" % [px, d]
		)
	_check(is_equal_approx(View.speck_size(8.0), View.SPECK), "specks: not their size mid way")
	# A partner on the riding mower sits on it (Mundell's model's `sit` key),
	# one on foot does not.
	var frames: Dictionary = models.kinds.get("mundell", {}).get("frames", {})
	_check(frames.has("sit") and frames.has("hurt_sit"), "mundell: no sit key")
	var rides: VehiclesFeature = game.features.get("vehicles")
	var mower := -1
	if rides != null:
		for i in rides.rides.size():
			if (rides.rides[i] as VehicleDrive.Ride).kind == "mower":
				mower = i
	_check(mower >= 0, "hickston: no riding mower")
	if mower >= 0:
		var p := game.player
		var on_foot := ModeBodies.player_pose(game, p, "mundell")
		rides.seat_in(p, mower)
		var seated := ModeBodies.player_pose(game, p, "mundell")
		_check(
			not on_foot.ends_with("_sit") and seated == "mundell_sit",
			"mower: a rider shows %s (on foot %s)" % [seated, on_foot]
		)
	sound.queue_free()


## BLUE's motions as ActorView plays them (src/hound_looks.gd hands it the
## frame and the gait): a motion's beat on the gait, a one-shot short of
## its last key, his own longer blend (fit.json "blend") between poses.
func _hound_motion(models: ActorModels, level: LevelData) -> void:
	if not models.kinds.has("hound"):
		_check(false, "hound: no model")
		return
	var view := models.scene("hound").instantiate() as ActorView
	root.add_child(view)
	view.setup(models)
	var skeleton := view.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var e := Enemy.new("coot", 10.0, 10.0, 0.0)
	e.kind = "hound"
	e.height = 1.0
	var s := View.Sprite.new()
	s.x = e.x
	s.y = e.y
	s.image = "hound_0"
	var clock := 500.0
	# The trot one and a half beats in: between t1 and t2, unblended.
	s.pose = "hound_t0"
	e.gait = 0.0
	view.show_as(s, e, level, clock)
	view.show_as(s, e, level, clock + 1.0)
	e.gait = PI * .5 * 1.5
	view.show_as(s, e, level, clock + 1.1)
	var trot := _pose(skeleton)
	var t0: float = models.key_time("hound", "t0")
	view._player.seek(t0 + 1.5 * ActorModels.KEY_TIME, true)
	_check(_far(trot, _pose(skeleton)) < 1e-4, "hound: the trot not played on his gait")
	# Going down, played through once: its end is the last key, f4.
	s.pose = "hound_f0"
	e.gait = HoundLooks._once(1.0) * PI * .5
	view.show_as(s, e, level, clock + 2.0)
	view.show_as(s, e, level, clock + 3.0)
	var fallen := _pose(skeleton)
	view._player.seek(models.key_time("hound", "f4"), true)
	_check(_far(fallen, _pose(skeleton)) < .02, "hound: going down does not end on his side (f4)")
	view._player.seek(models.key_time("hound", "f0"), true)
	_check(_far(fallen, _pose(skeleton)) > .05, "hound: going down wrapped back to its start")
	# Sat to lying at STAY: his own blend, half way at half of it.
	var blend: float = models.kinds["hound"].get("blend", ActorView.BLEND)
	_check(blend > ActorView.BLEND, "hound: no blend of his own (fit.json)")
	s.pose = "hound_sit"
	view.show_as(s, e, level, clock + 4.0)
	view.show_as(s, e, level, clock + 5.0)
	var sat := _pose(skeleton)
	s.pose = "hound_rest"
	view.show_as(s, e, level, clock + 6.0)
	view.show_as(s, e, level, clock + 6.0 + blend * .5)
	var half := _pose(skeleton)
	view.show_as(s, e, level, clock + 6.0 + blend + .01)
	var lying := _pose(skeleton)
	_check(
		_far(half, sat) > .002 and _far(half, lying) > .002,
		"hound: sat to lying not blended over his own blend"
	)
	view.queue_free()


## BLUE's drawn shoulder and head top standing (his idle's first key, his
## model's skinned vertices: the trunk's top over the withers, the head's
## highest) against Mundell's drawn height.
func _hound_size(models: ActorModels) -> void:
	if not models.kinds.has("hound") or not models.kinds.has("mundell"):
		_check(false, "hound size: no hound or no Mundell model")
		return
	var view := models.scene("hound").instantiate() as ActorView
	root.add_child(view)
	view.setup(models)
	var player := view.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var at: float = models.key_time("hound", "i0")
	player.seek(at, true)
	var labels: Dictionary = models.kinds["hound"].get("labels", {})
	var heads: Array[Vector3] = []
	var bodies: Array[Vector3] = []
	for child in view.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		var skeleton := mi.get_node_or_null(mi.skeleton) as Skeleton3D
		if mi.mesh == null or mi.skin == null or skeleton == null:
			continue
		var place := Transform3D.IDENTITY
		var node: Node = skeleton
		while node != null and node != view:
			if node is Node3D:
				place = (node as Node3D).transform * place
			node = node.get_parent()
		for surface in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var per := bones.size() / maxi(1, verts.size())
			for i in verts.size():
				var p := Vector3.ZERO
				var most := -1.0
				var label := "body"
				for k in per:
					var w := weights[i * per + k]
					if w <= 0.0:
						continue
					var bind := bones[i * per + k]
					var bone := mi.skin.get_bind_bone(bind)
					if bone < 0:
						bone = skeleton.find_bone(mi.skin.get_bind_name(bind))
					var pose := skeleton.get_bone_global_pose(bone) * mi.skin.get_bind_pose(bind)
					p += (pose * verts[i]) * w
					if w > most:
						most = w
						label = str(labels.get(skeleton.get_bone_name(bone), "body"))
				p = place * p
				if label == "head":
					heads.append(p)
				else:
					bodies.append(p)
	view.queue_free()
	if heads.is_empty() or bodies.is_empty():
		_check(false, "hound size: no head or body measured")
		return
	# His forward: from his middle toward his head, on the ground.
	var mid := Vector3.ZERO
	for p in heads:
		mid += p
	mid /= heads.size()
	var forward := Vector3(mid.x, 0.0, mid.z).normalized()
	var top := 0.0
	for p in heads:
		top = maxf(top, p.y)
	var shoulder := 0.0
	for p in bodies:
		var along := p.dot(forward)
		if along > .12 and along < .24:
			shoulder = maxf(shoulder, p.y)
	var mundell: Dictionary = models.kinds["mundell"]
	var canvas: Array = mundell.get("canvas", [1.0, 1.87])
	var man: float = float(mundell["height"]) * ModeScreens.PARTNER_HEIGHT / float(canvas[1])
	var drawn_shoulder := shoulder * HoundLooks.SIZE / man
	var drawn_top := top * HoundLooks.SIZE / man
	print(
		(
			"  hound: shoulder %.3f, head %.3f of his model; drawn %.2f and %.2f of Mundell (%.2f)"
			% [shoulder, top, drawn_shoulder, drawn_top, man]
		)
	)
	_check(
		drawn_shoulder >= HOUND_SHOULDER[0] and drawn_shoulder <= HOUND_SHOULDER[1],
		"hound: shoulder %.2f of Mundell's height (a hound's %s)" % [drawn_shoulder, HOUND_SHOULDER]
	)
	_check(
		drawn_top >= HOUND_HEAD_TOP[0] and drawn_top <= HOUND_HEAD_TOP[1],
		"hound: head top %.2f of Mundell's height (a hound's %s)" % [drawn_top, HOUND_HEAD_TOP]
	)


func _pose(skeleton: Skeleton3D) -> Array:
	var out := []
	for b in skeleton.get_bone_count():
		out.append(skeleton.get_bone_pose_position(b))
		out.append(skeleton.get_bone_pose_rotation(b))
	return out


## The biggest difference between two poses (positions in metres, turns as
## quaternion components).
func _far(a: Array, b: Array) -> float:
	var most := 0.0
	for i in mini(a.size(), b.size()):
		if a[i] is Vector3:
			most = maxf(most, (a[i] as Vector3).distance_to(b[i]))
		else:
			var qa: Quaternion = a[i]
			var qb: Quaternion = b[i]
			most = maxf(most, minf((qa - qb).length(), (qa + qb).length()))
	return most
