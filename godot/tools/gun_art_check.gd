## The guns as the player sees them (polish pass 9; tools/check_all.gd runs it,
## headless, from the pictures in assets/art):
##
##   godot --headless --path godot --script res://tools/gun_art_check.gd
##
## FRAMES: every gun has every pose it can show (its rest and kick, a
## recovery when it eases back, the four reload or cycle frames when it has a
## magazine or a cycle, the swing, the throw, the grind, the sawed-off's one
## shell frames), each 320x120 like every other cel. MODS: every choice of a
## gun's junk bench mods has the same poses at the same size, the hand where
## the bare gun has it (its pixels in the bottom rows the same) and a muzzle
## where the bare gun's is (bar the mods that lengthen the barrel). MUZZLES:
## every gun that flashes has its muzzle noted for rest, kick and recovery,
## its mods too, and each point lies on the gun's own picture. MODELLED: the
## .38 and the sawed-off are renders like the rest (their cels and pickups
## carry no photograph). FINISHERS: each finisher's frames are pictures the
## guns of its class have, the boot's six cels are packed and placed.
## PICKUPS: every gun has its pickup picture, none with a hand on it, and the
## dynamite sticks' is not the shells' box. SWITCH: the gun put away goes down
## before the new one comes up, in the switch's own time.
extends SceneTree

const Looks := preload("res://src/features/brawl_looks.gd")
const CEL := Vector2i(320, 120)
## Mods that put the muzzle further out (weapon_mods.py FRONTS).
const LENGTHEN := ["brake", "choke"]
## The poses only some guns have.
const SWING := ["idle", "wind", "strike", "follow", "recover"]
const THROW := ["idle", "kick", "throw", "dry"]
const RELOAD := ["open", "eject", "load", "close"]

var failures: Array = []
var passes := 0
var art_dir := ""
var _cache := {}


func _init() -> void:
	art_dir = ProjectSettings.globalize_path("res://").path_join("../assets/art").simplify_path()
	print("GUN ART (frames, mods, muzzles, finishers, pickups, switch)")
	_frames()
	_mods()
	_muzzles()
	_modelled()
	_finishers()
	_pickups()
	_switch()
	print("%d passed, %d failed" % [passes, failures.size()])
	if failures.is_empty():
		print("GUN ART OK")
		quit(0)
	else:
		for f: String in failures:
			print("  failed: ", f)
		quit(1)


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if ok:
		passes += 1
	else:
		failures.append(text)


func _image(name: String) -> Image:
	if _cache.has(name):
		return _cache[name]
	var path := art_dir.path_join(name + ".png")
	var image: Image = null
	if FileAccess.file_exists(path):
		image = Image.load_from_file(path)
		if image != null:
			image.convert(Image.FORMAT_RGBA8)
	_cache[name] = image
	return image


## Every pose a gun's cels are named with (gun_<view>_<pose>), for the bare
## gun or one view of its mods.
func _poses(view: String) -> Array:
	var out: Array = []
	var prefix := "gun_%s_" % view
	for file in DirAccess.get_files_at(art_dir):
		if not file.ends_with(".png") or not file.begins_with(prefix):
			continue
		var pose := file.get_basename().substr(prefix.length())
		# (not another choice of mods: gun_revolver__loader_scope_idle is not
		# a pose of revolver__loader)
		if pose.begins_with("_") or not _vocabulary().has(pose):
			continue
		out.append(pose)
	out.sort()
	return out


## Every pose any gun can be drawn in.
func _vocabulary() -> Dictionary:
	if _cache.has("|poses"):
		return _cache["|poses"]
	var out := {}
	for slot in Weapons.COUNT:
		for pose: String in _wanted(slot):
			out[pose] = true
	_cache["|poses"] = out
	return out


## The views of gun `gun` with mods on: <gun>__<shorts>.
func _mod_views(gun: String) -> Array:
	var out := {}
	var prefix := "gun_%s__" % gun
	for file in DirAccess.get_files_at(art_dir):
		if file.begins_with(prefix) and file.ends_with("_idle.png"):
			out[file.trim_prefix("gun_").trim_suffix("_idle.png")] = true
	var names := out.keys()
	names.sort()
	return names


## The poses gun `slot` can be drawn in (Armory.pose()).
func _wanted(slot: int) -> Array:
	var gun: String = Weapons.NAMES[slot]
	if slot in [Weapons.CROWBAR, Weapons.SLING]:
		return SWING.duplicate()
	if slot == Weapons.DYNAMITE:
		return THROW + ["lit", "lit_alt"]
	if slot in Weapons.THROWN_GUNS:
		return THROW.duplicate()
	var out: Array = ["idle", "kick"]
	if slot in Weapons.RECOVERY_GUNS:
		out.append("recover")
	if Weapons.CAPACITY[slot] > 0 or slot in Weapons.CYCLE_GUNS:
		out.append_array(RELOAD)
	if slot == Weapons.RIPSAW:
		out.append_array(["grind", "grind_hot"])
	if gun == "shotgun":
		out.append_array(["eject_one", "load_one"])
	return out


func _frames() -> void:
	var missing: Array = []
	var odd: Array = []
	for slot in Weapons.COUNT:
		var gun: String = Weapons.NAMES[slot]
		var have := _poses(gun)
		for pose: String in _wanted(slot):
			if not have.has(pose):
				missing.append("%s %s" % [gun, pose])
		for pose: String in have:
			var image := _image("gun_%s_%s" % [gun, pose])
			if image == null or image.get_size() != CEL:
				odd.append("gun_%s_%s" % [gun, pose])
	_check(missing.is_empty(), "every gun has every pose it can show %s" % [missing])
	_check(odd.is_empty(), "every gun's cels are 320x120 %s" % [odd])


## The bottom rows' shape (which pixels are drawn): the hand.
func _hand_rows(image: Image, rows: int) -> PackedByteArray:
	var out := PackedByteArray()
	for y in range(CEL.y - rows, CEL.y):
		for x in CEL.x:
			out.append(1 if image.get_pixel(x, y).a > .5 else 0)
	return out


func _mods() -> void:
	var guns := 0
	var bad_poses: Array = []
	var bad_size: Array = []
	var bad_hand: Array = []
	for slot in Weapons.COUNT:
		var gun: String = Weapons.NAMES[slot]
		var views := _mod_views(gun)
		if views.is_empty():
			continue
		guns += 1
		var bare_poses := _poses(gun)
		var bare_hand := _hand_rows(_image("gun_%s_idle" % gun), 10)
		for view: String in views:
			if _poses(view) != bare_poses:
				bad_poses.append(view)
			for pose: String in _poses(view):
				var image := _image("gun_%s_%s" % [view, pose])
				if image == null or image.get_size() != CEL:
					bad_size.append("gun_%s_%s" % [view, pose])
			# A mod adds to the picture: what the bare gun draws there is still drawn.
			var hand := _hand_rows(_image("gun_%s_idle" % view), 10)
			var kept := 0
			var drawn := 0
			for i in hand.size():
				if bare_hand[i]:
					drawn += 1
					kept += hand[i]
			if float(kept) / maxf(1.0, drawn) < .97:
				bad_hand.append("%s %.2f" % [view, float(kept) / maxf(1.0, drawn)])
	_check(guns >= 5, "the bench's five guns have mod pictures (%d)" % guns)
	_check(bad_poses.is_empty(), "every choice of mods has the bare gun's poses %s" % [bad_poses])
	_check(bad_size.is_empty(), "every mod picture is 320x120 %s" % [bad_size])
	_check(
		bad_hand.is_empty(),
		"every mod picture has the hand where the bare gun has it %s" % [bad_hand]
	)


func _muzzles() -> void:
	var anchors: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(art_dir.path_join("weapon_anchors.json"))
	)
	if not anchors is Dictionary:
		_check(false, "weapon_anchors.json reads")
		return
	var missing: Array = []
	var off_gun: Array = []
	var moved: Array = []
	for slot: int in Weapons.MUZZLE_GUNS:
		var gun: String = Weapons.NAMES[slot]
		var views: Array = [gun] + _mod_views(gun)
		var bare: Dictionary = anchors.get(gun, {})
		for view: String in views:
			var table: Dictionary = anchors.get(view, {})
			for pose: String in (
				["idle", "kick"] + (["recover"] if slot in Weapons.RECOVERY_GUNS else [])
			):
				if not table.has(pose):
					missing.append("%s %s" % [view, pose])
					continue
				var at: Array = table[pose]
				var image := _image("gun_%s_%s" % [view, pose])
				if image == null:
					continue
				# Within a few pixels of something drawn (the muzzle's end; the
				# arm gun's lies between its claws).
				var near := false
				var cx := roundi(float(at[0]))
				var cy := roundi(float(at[1]))
				for dy in range(-8, 9):
					for dx in range(-8, 9):
						var x := cx + dx
						var y := cy + dy
						if x >= 0 and y >= 0 and x < CEL.x and y < CEL.y:
							near = near or image.get_pixel(x, y).a > .5
				if not near:
					off_gun.append("%s %s" % [view, pose])
				if view != gun and bare.has(pose):
					var lengthened := false
					for m: String in LENGTHEN:
						lengthened = lengthened or view.get_slice("__", 1).split("_").has(m)
					var b: Array = bare[pose]
					var d := (
						Vector2(float(at[0]) - float(b[0]), float(at[1]) - float(b[1])).length()
					)
					if not lengthened and d > 1.5:
						moved.append("%s %s %.1f" % [view, pose, d])
	_check(
		missing.is_empty(), "every flashing gun and its mods has its muzzle noted %s" % [missing]
	)
	_check(off_gun.is_empty(), "every muzzle point lies on its gun's picture %s" % [off_gun])
	_check(
		moved.is_empty(), "a mod leaves the muzzle where it was unless it lengthens it %s" % [moved]
	)


## A share of the picture's drawn pixels that look like the photographed
## hands' skin (a pickup or a modelled gun's metal never has much).
func _skin(image: Image, rows_from := 0) -> float:
	var drawn := 0
	var skin := 0
	for y in range(rows_from, image.get_height()):
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a < .5:
				continue
			drawn += 1
			if (
				c.r8 > 150
				and c.g8 > 95
				and c.b8 > 65
				and c.r8 - c.b8 > 40
				and c.r8 > c.g8
				and c.g8 > c.b8
			):
				skin += 1
	return float(skin) / maxf(1.0, drawn)


func _modelled() -> void:
	var views := FileAccess.get_file_as_string(
		(
			ProjectSettings
			. globalize_path("res://")
			. path_join("../scripts/blender/weapon_views.py")
			. simplify_path()
		)
	)
	_check(
		(
			views.contains('"revolver": (revolver, "pistol"')
			and views.contains('"shotgun": (shotgun, "long"')
		),
		"the .38 and the sawed-off are modelled and held like the other guns (weapon_views.py)"
	)
	var mods := FileAccess.get_file_as_string(
		(
			ProjectSettings
			. globalize_path("res://")
			. path_join("../scripts/blender/weapon_mods.py")
			. simplify_path()
		)
	)
	_check(
		not mods.contains("PHOTO["),
		"their mods are rendered on the gun, not laid over a photograph"
	)


func _finishers() -> void:
	var places_ok := true
	for pose: String in Looks.PLACES:
		places_ok = places_ok and _image("fx_boot_" + pose) != null
	_check(
		places_ok and Looks.PLACES.size() >= 6,
		(
			"the boot's %d cels are all there (lifted, chambered, out, the blow, back, away)"
			% Looks.PLACES.size()
		)
	)
	var lacking: Array = []
	var classes := {"whip": "pistol", "butt": "long", "skull": "blade", "gut": "blade"}
	for move: String in classes:
		var cls: String = classes[move]
		var guns: Array = HitData.value("finish", cls, [])
		var shown := 0
		for gun: String in guns:
			var all := true
			for row: Array in Looks.FRAMES[move]:
				var pose := Looks.frame(move, float(row[0]), gun)
				if pose != "" and _image("gun_%s_%s" % [gun, pose]) == null:
					all = false
			if all:
				shown += 1
			elif cls != "long":
				lacking.append("%s %s" % [move, gun])
		if cls == "long":
			# A long gun with no recovery frame keeps its own pose there.
			_check(
				shown * 2 >= guns.size(),
				"%s: most long guns show its frames (%d of %d)" % [move, shown, guns.size()]
			)
	_check(lacking.is_empty(), "every pistol and blade has its finishers' frames %s" % [lacking])
	var turns := 0
	var last := "?"
	for k in 60:
		var pose := Looks.frame("whip", k / 100.0, "revolver")
		if pose != last:
			turns += 1
			last = pose
	_check(turns >= 4, "a pistol whip is frames, not one picture slid (%d changes)" % turns)


func _pickups() -> void:
	var missing: Array = []
	var handed: Array = []
	for slot in Weapons.COUNT:
		var gun: String = Weapons.NAMES[slot]
		var image := _image("item_" + gun)
		if image == null:
			missing.append(gun)
			continue
		# (a throwable's glass or rag may be skin coloured)
		if not slot in Weapons.THROWN_GUNS and _skin(image) > .12:
			handed.append("%s %.2f" % [gun, _skin(image)])
	_check(missing.is_empty(), "every gun has its pickup picture %s" % [missing])
	_check(handed.is_empty(), "no gun's pickup has a hand on it %s" % [handed])
	var sticks := _image("item_dynamite")
	var shells := _image("item_shells")
	_check(
		sticks != null and shells != null and sticks.get_data() != shells.get_data(),
		"the dynamite sticks' pickup is its own picture, not the shells' box"
	)
	for gun: String in ["revolver", "shotgun"]:
		var cel := _image("gun_%s_idle" % gun)
		_check(
			cel != null and _skin(cel, 0) < .5,
			"the %s's cel is a render held by the plate's hand" % gun
		)


func _switch() -> void:
	_check(
		Weapons.SWITCH_LOWER > 0.0 and Weapons.SWITCH_LOWER < Weapons.SWITCH_TIME * .6,
		(
			"the gun put away goes down in a part of the switch (%.2f of %.2f s)"
			% [Weapons.SWITCH_LOWER, Weapons.SWITCH_TIME]
		)
	)
	var a := Weapons.Armory.new(Weapons.REVOLVER)
	a.owned[Weapons.SHOTGUN] = true
	a._note_drawn()
	a.active = Weapons.SHOTGUN
	a.switch = Weapons.SWITCH_TIME
	a._note_drawn()
	var first := a.shown_gun()
	a.switch = Weapons.SWITCH_TIME - Weapons.SWITCH_LOWER - .01
	var then := a.shown_gun()
	_check(
		first == Weapons.REVOLVER and then == Weapons.SHOTGUN,
		"a switch shows the .38 going down, then the sawed-off coming up"
	)
	var b := Weapons.Armory.new(Weapons.REVOLVER)
	b._note_drawn()
	b.switch = .2
	b._note_drawn()
	_check(
		b.shown_gun() == Weapons.REVOLVER, "raising the gun from the holster has nothing going down"
	)
