## The 3D view's parts that need no window, for every level: the mesh
## builder turns its walls, floors, roofs, caps and slopes into geometry with
## sane numbers (every vertex finite, every tile index real, the moving walls
## too), and every modelled prop has its mesh and its baked picture.
##
##   godot --headless --path godot --script res://tools/view3d_check.gd
##
## Prints VIEW3D CHECK OK, or what failed. In check_all (quick too).
extends SceneTree

const Contrast := preload("res://tools/night_contrast.gd")

var _failed: Array[String] = []


func _init() -> void:
	var assets := Assets.new()
	var tile_count := assets.tiles.size() / (128 * 128 * 3)
	var ids: Array[String] = []
	for file: String in DirAccess.get_files_at("res://data"):
		if file.ends_with(".json") and file != "index.json":
			ids.append(file.get_basename())
	ids.sort()
	var total := 0
	for id: String in ids:
		var level := LevelData.load_level(id, assets)
		if level == null:
			_fail("%s: does not load" % id)
			continue
		var builder := LevelMesh.new(level)
		var parts := builder.build_static(level.active_base(false))
		var tris := 0
		for key: Vector2i in parts:
			var mesh: ArrayMesh = parts[key]
			for surface in mesh.get_surface_count():
				tris += _check_surface(id, mesh.surface_get_arrays(surface), tile_count)
		var moving := level.active_walls(false).slice(level.active_base(false).size())
		var doors := builder.build_walls(moving)
		if doors != null:
			for surface in doors.get_surface_count():
				tris += _check_surface(id, doors.surface_get_arrays(surface), tile_count)
		if tris == 0:
			_fail("%s: no geometry" % id)
		total += tris
		print("%-16s %6d triangles in %d chunks" % [id, tris, parts.size()])
	var models := PropModels.new(assets)
	for name: String in models.sizes:
		if models.mesh(name) == null:
			_fail("prop %s: no mesh" % name)
		if not assets.has_art("mesh_" + name):
			_fail("prop %s: no baked picture mesh_%s" % [name, name])
		var scene := models.scene(name)
		var shown := scene.instantiate() if scene != null else null
		if not shown is PropView:
			_fail("prop %s: no scene (tools/art/build_prop_scenes.gd)" % name)
		if shown != null:
			# A quest station's one model holds both its looks.
			if not shown.find_children("look_*", "Node3D", true, false).is_empty():
				for look in PropModels.LOOKS:
					if shown.find_children("look_" + look, "Node3D", true, false).is_empty():
						_fail("prop %s: no look_%s in its model" % [name, look])
			shown.free()
	for art_name: String in assets.art_index:
		if art_name.begins_with("town_quest_") and models.name_of(art_name) == "":
			_fail("quest station %s: no model (tools/art/build_prop_meshes.gd)" % art_name)
		elif art_name.begins_with("item_") and models.name_of(art_name) == "":
			_fail("pickup %s: no authored 3D scene" % art_name)
	print("%d triangles in %d levels, %d prop models" % [total, ids.size(), models.sizes.size()])
	var actors := ActorModels.new(assets)
	for kind: String in actors.kinds:
		var packed := actors.scene(kind)
		var view := packed.instantiate() as ActorView if packed != null else null
		if view == null:
			_fail("actor %s: no scene (tools/art/build_actor_scenes.gd)" % kind)
			continue
		if not view.setup(actors):
			_fail("actor %s: its model cannot pose (no animation)" % kind)
		else:
			_check_rest(kind, view, actors.kinds[kind])
		view.free()
		# Imported at the action's own 24 keys a second: at Godot's 30 the
		# keys are resampled between and a part shrunk away in one key
		# comes back part-grown in mid-air (build_actor_meshes.gd sets it).
		var import_path := ActorModels.FOLDER.path_join(kind + ".glb.import")
		if not FileAccess.get_file_as_string(import_path).contains("animation/fps=24"):
			_fail("actor %s: %s must import at animation/fps=24" % [kind, import_path])
	var fit: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(ActorModels.FOLDER.path_join("fit.json"))
	)
	if not fit is Dictionary:
		_fail("actors fit.json: not a dictionary")
	else:
		for kind: String in fit:
			if not actors.kinds.has(kind):
				_fail("actors fit.json: %s is not a model" % kind)
	print("%d actor models" % actors.kinds.size())
	_check_leftovers(models, actors)
	_check_slabs(assets)
	_check_reshape(assets)
	_check_night(assets)
	if _failed.is_empty():
		print("VIEW3D CHECK OK")
		quit(0)
	else:
		for line in _failed:
			print("FAIL ", line)
		quit(1)


func _check_surface(id: String, arrays: Array, tile_count: int) -> int:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var c1: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM1]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for v in verts:
		if not (is_finite(v.x) and is_finite(v.y) and is_finite(v.z)):
			_fail("%s: a vertex is not a number" % id)
			break
	for i in range(0, c1.size(), 4):
		var tile := int(c1[i])
		if tile < 0 or tile >= tile_count or int(c1[i + 1]) >= tile_count:
			_fail("%s: tile %d out of range" % [id, tile])
			break
	for i in index:
		if i < 0 or i >= verts.size():
			_fail("%s: an index past the vertices" % id)
			break
	return index.size() / 3


## Every slab picture (SlabModels: the item_* pickups, the loose things, the
## range targets) makes its slab: sane numbers, and from the front the size
## and place of the picture's solid pixels, as the sprite showed them (one
## unit is the picture's height); a picture with a part (a gong's plate) and
## its part together.
func _check_slabs(assets: Assets) -> void:
	var models := SlabModels.new(assets)
	var names: Array[String] = []
	var counts := {}
	for name: String in assets.art_index:
		var kind := SlabModels.family(name)
		if kind != SlabModels.NONE:
			names.append(name)
			counts[kind] = int(counts.get(kind, 0)) + 1
	names.sort()
	var tris := 0
	for name in names:
		var mesh := models.mesh(name)
		if mesh == null:
			_fail("slab %s: no mesh" % name)
			continue
		tris += _check_slab_numbers(name, mesh)
		var aabb := mesh.get_aabb()
		if SlabModels.PARTS.has(name):
			var part := models.mesh(name + SlabModels.PART)
			if part == null:
				_fail("slab %s: no part" % name)
				continue
			tris += _check_slab_numbers(name + SlabModels.PART, part)
			aabb = aabb.merge(part.get_aabb())
			if is_nan(models.pivot(name)) or models.pivot(name) < part.get_aabb().end.y - .001:
				_fail("slab %s: its part hangs from below its top" % name)
		var a := assets.art(name)
		var w: int = a["w"]
		var h: int = a["h"]
		var data: PackedByteArray = a["data"]
		var box := Rect2i()
		for y in h:
			for x in w:
				if data[(y * w + x) * 4 + 3] > SlabModels.SOLID:
					var pixel := Rect2i(x, y, 1, 1)
					box = pixel if box.size == Vector2i.ZERO else box.merge(pixel)
		var want := Vector3(box.size.x, box.size.y, 0.0) / h
		if (
			absf(aabb.size.x - want.x) > .001
			or absf(aabb.size.y - want.y) > .001
			or absf(aabb.end.y - float(h - box.position.y) / h) > .001
			or absf(aabb.get_center().x) > .001
		):
			_fail("slab %s: the slab is not the picture's size and place" % name)
		if aabb.size.z <= 0.0 or aabb.size.z > maxf(aabb.size.x, aabb.size.y) + .001:
			_fail("slab %s: the slab is %.3f thick" % [name, aabb.size.z])
	for kind: int in [SlabModels.PICKUP, SlabModels.LOOSE, SlabModels.TARGET]:
		if int(counts.get(kind, 0)) == 0:
			_fail("no slab pictures of family %d" % kind)
	print(
		(
			"%d slab meshes (%d pickups, %d loose, %d targets), %d triangles"
			% [
				names.size(),
				int(counts.get(SlabModels.PICKUP, 0)),
				int(counts.get(SlabModels.LOOSE, 0)),
				int(counts.get(SlabModels.TARGET, 0)),
				tris
			]
		)
	)


## Finite vertices and indices inside them; the mesh's triangles.
func _check_slab_numbers(name: String, mesh: ArrayMesh) -> int:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for v in verts:
		if not (is_finite(v.x) and is_finite(v.y) and is_finite(v.z)):
			_fail("slab %s: a vertex is not a number" % name)
			break
	for i in index:
		if i < 0 or i >= verts.size():
			_fail("slab %s: an index past the vertices" % name)
			break
	return index.size() / 3


## A body that fell must lie: at the key "down" no part (one shrunk away too:
## it rides the body) sits higher than DOWN_HIGH of the standing height or half
## a metre (the floating bits after a kill; a dead crawler's legs stand up as
## in its cel), and at no key is a part partway shrunk (a key sampled between,
## as at Godot's 30 fps). A kind whose body at rest is its own cel (fit.json
## "down_cel") or that stays up (a flyer, no "down") is left out.
const DOWN_HIGH := .5


func _check_rest(kind: String, view: ActorView, info: Dictionary) -> void:
	var players := view.find_children("*", "AnimationPlayer", true, false)
	var player := players[0] as AnimationPlayer
	var anim := player.get_animation(player.get_animation_list()[0])
	var frames: Dictionary = info["frames"]
	var height: float = info["height"]
	var own_cel: bool = info.get("down_cel", false)
	# A body that lies with its legs up (fit.json "down_high": the tipped
	# cow's top pair stuck up stiff) may reach higher.
	var reach: float = info.get("down_high", DOWN_HIGH)
	var high := 0
	var partial := 0
	for name: String in frames:
		var key: float = frames[name]
		var t := key * ActorModels.KEY_TIME
		for track in anim.get_track_count():
			if anim.track_get_type(track) != Animation.TYPE_SCALE_3D:
				continue
			var size := anim.scale_track_interpolate(track, t).x
			if size > .02 and size < .6:
				partial += 1
			if name != "down" or own_cel:
				continue
			var path := anim.track_get_path(track)
			var spot := anim.find_track(path, Animation.TYPE_POSITION_3D)
			if spot >= 0 and anim.position_track_interpolate(spot, t).y > maxf(height * reach, .5):
				high += 1
	if high > 0:
		_fail("actor %s: %d parts still up at rest (down)" % [kind, high])
	if partial > 0:
		_fail("actor %s: %d parts partway shrunk at keys" % [kind, partial])


## The pictures drawn flat until after v3.2.0 that have models now: the
## hanging shop lamp (game.gd's prop_lamp, which a boss arena drops) is the
## shop_lamp model; the cow is a model that rolls over on the hooves of the
## side she lies on `down` as she is tipped (ActorView.tipped).
func _check_leftovers(models: PropModels, actors: ActorModels) -> void:
	for picture: String in PropModels.PICTURES:
		if models.name_of(picture) != PropModels.PICTURES[picture]:
			_fail("%s: its authored model is unavailable" % picture)
	var cow: Dictionary = actors.kinds.get("cow", {})
	var tips: float = cow.get("tips", 0.0)
	var frames: Dictionary = cow.get("frames", {})
	if tips <= 0.0 or not frames.has("down"):
		_fail("actor cow: no model that tips (fit.json tips) and lies down")
		return
	var over := ActorView.tipped(PI * .5, tips)
	var hoof := over * Vector3(tips, 0.0, 0.0)
	var back := over * Vector3(0.0, 1.4, 0.0)
	if (
		hoof.distance_to(Vector3(tips, 0.0, 0.0)) > .001
		or absf(back.y - tips) > .01
		or back.x < 1.0
	):
		_fail("actor cow: tipped, she does not go over on her hooves (%s, %s)" % [hoof, back])


## A plank wall or a shed's wall broken through (LevelData.open_cell) builds
## only the chunks it touched again (WorldView3D._reshape): those come out as
## a whole build after would make them, every other chunk as it was, and the
## cell texture's pixels as _cell_image after.
func _check_reshape(assets: Assets) -> void:
	var hud := HUD.new(assets)
	var sound := Sound.new(assets)
	root.add_child(sound)
	var opened := 0
	var part_us := 0
	var whole_us := 0
	var sheds := 0
	for id: String in ["fair", "sawmill", "bayou", "county_hickston"]:
		var game := Game.new(assets, hud, sound, id)
		var level := game.level
		var walls: Object = game.features.get("wall_breaks")
		if walls == null:
			continue
		var builder := LevelMesh.new(level)
		var tried := 0
		for f: Object in (walls.get("fences") as Dictionary).values():
			if tried >= 3 or not walls.call("_may_open", f):
				continue
			tried += 1
			var before := builder.build_static(level.active_base(false))
			var reshaped := level.reshaped.size()
			var retiled := level.retiled.size()
			var reshapes := level.reshapes
			var version := level.walls_version
			walls.call("_break_through", f, true)
			if level.reshapes != reshapes + 1 or level.walls_version != version + 1:
				_fail("%s: a wall broken through is not one reshape" % id)
				continue
			var only := {}
			for i in range(reshaped, level.reshaped.size()):
				WorldView3D._chunks_at(level.reshaped[i], only)
			for i in range(retiled, level.retiled.size()):
				WorldView3D._chunks_at(level.retiled[i], only)
			var t0 := Time.get_ticks_usec()
			var some := builder.build_static(level.active_base(false), only)
			var t1 := Time.get_ticks_usec()
			var after := builder.build_static(level.active_base(false))
			part_us += t1 - t0
			whole_us += Time.get_ticks_usec() - t1
			for k: Vector2i in after.keys() + before.keys():
				var want := _arrays(after.get(k))
				var got := _arrays(some.get(k) if only.has(k) else before.get(k))
				if want != got:
					_fail("%s: chunk %s after a wall opened at %s" % [id, k, f.get("cell")])
					break
			var image := WorldView3D._cell_image(level)
			var cell: Vector2i = f.get("cell")
			var c := cell.y * level.width + cell.x
			if image.get_pixelv(cell) != WorldView3D._cell_colour(level, c):
				_fail("%s: the cell texture at %s" % [id, cell])
			opened += 1
			sheds += 1 if int(f.get("inside")) >= 0 else 0
	if opened < 4 or sheds < 1:
		_fail("walls broken through: only %d (%d sheds)" % [opened, sheds])
	print(
		(
			(
				"%d walls broken through (%d sheds): only their chunks built again,"
				+ " %.1f ms a wall (a whole build %.1f)"
			)
			% [
				opened,
				sheds,
				part_us / 1000.0 / maxi(1, opened),
				whole_us / 1000.0 / maxi(1, opened)
			]
		)
	)


static func _arrays(mesh: Variant) -> Array:
	var out: Array = []
	if mesh is ArrayMesh:
		var m: ArrayMesh = mesh
		for s in m.get_surface_count():
			out.append(m.surface_get_arrays(s))
	return out


func _fail(line: String) -> void:
	if _failed.size() < 40:
		_failed.append(line)


## Polish pass 9: the tiles carry their mip levels (a glow kept as the
## brightest of its four), the moon's rim is the night chapter's and a
## blackout's only (by day the actors keep their cels' look), and the
## contrast measure compare_3d.gd holds the night views to reads true.
func _check_night(assets: Assets) -> void:
	Effects.load_tuning()
	var tiles := ViewTiles.new(assets)
	if not tiles.tiles.has_mipmaps():
		_fail("view tiles: no mip levels")
	# One glowing texel (alpha 40) in a tile: its mip levels keep it whole.
	var size := ViewTiles.SIZE
	var lit := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	lit.fill(Color8(90, 80, 70, 255))
	lit.set_pixel(6, 8, Color8(250, 220, 160, 40))
	var mipped := ViewTiles._with_mips(lit, true)
	var data := mipped.get_data()
	var level1 := size * size * 4
	var level2 := level1 + (size / 2) * (size / 2) * 4
	if (
		not mipped.has_mipmaps()
		or data[level1 + (4 * size / 2 + 3) * 4 + 3] != 40
		or data[level2 + (2 * size / 4 + 1) * 4 + 3] != 40
		or data[level1 + 3] != 255
	):
		_fail("view tiles: a glow's mip levels are not the brightest of the texels under them")
	for id: String in ["hickston", "fair", "sawmill", "quarry", "bayou", "speedway", "mothership"]:
		var rim: Color = Effects.mood(id, "moon_rim", Color(0, 0, 0, 0))
		if rim.a != 0.0:
			_fail("effects.cfg: %s has a moon_rim (the night chapter's only)" % id)
	var night: Color = Effects.mood("moonshine", "moon_rim", Color(0, 0, 0, 0))
	if night.a <= 0.0:
		_fail("effects.cfg: the night chapter has no moon_rim")
	var blackout: float = Tuning.file("res://data/tuning/events.cfg").get_value(
		"blackout", "moon_rim", 0.0
	)
	if blackout <= 0.0:
		_fail("events.cfg: the blackout has no moon_rim")
	# A grey figure on a darker ground: the measure finds just its pixels.
	var with := Image.create_empty(40, 20, false, Image.FORMAT_RGB8)
	var bare := Image.create_empty(40, 20, false, Image.FORMAT_RGB8)
	with.fill(Color8(20, 20, 20))
	bare.fill(Color8(20, 20, 20))
	with.fill_rect(Rect2i(10, 5, 4, 8), Color8(60, 60, 60))
	var r: Dictionary = Contrast.measure(with, bare, null, null)
	var want := Contrast.lightness(Color8(60, 60, 60)) - Contrast.lightness(Color8(20, 20, 20))
	if int(r["px"]) != 32 or absf(float(r["delta"]) - want) > .01:
		_fail("night_contrast: measured %s, wanted 32 px %.2f apart" % [r, want])
