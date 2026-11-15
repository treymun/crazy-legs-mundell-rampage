## The 3D view's parts that need no window, for every level: the mesh
## builder turns its walls, floors, roofs, caps and slopes into geometry with
## sane numbers (every vertex finite, every tile index real, the moving walls
## too), and every modelled prop has its mesh and its baked picture.
##
##   godot --headless --path godot --script res://tools/view3d_check.gd
##
## Prints VIEW3D CHECK OK, or what failed. In check_all (quick too).
extends SceneTree

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
			shown.free()
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
	_check_pickups(assets)
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


## Every pickup picture (item_*) makes its slab (PickupModels): sane numbers,
## and from the front the size and place of the picture's solid pixels, as the
## sprite showed them (one unit is the picture's height).
func _check_pickups(assets: Assets) -> void:
	var models := PickupModels.new(assets)
	var names: Array[String] = []
	for name: String in assets.art_index:
		if PickupModels.is_pickup(name):
			names.append(name)
	names.sort()
	var tris := 0
	for name in names:
		var mesh := models.mesh(name)
		if mesh == null:
			_fail("pickup %s: no mesh" % name)
			continue
		var arrays := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for v in verts:
			if not (is_finite(v.x) and is_finite(v.y) and is_finite(v.z)):
				_fail("pickup %s: a vertex is not a number" % name)
				break
		for i in index:
			if i < 0 or i >= verts.size():
				_fail("pickup %s: an index past the vertices" % name)
				break
		tris += index.size() / 3
		var a := assets.art(name)
		var w: int = a["w"]
		var h: int = a["h"]
		var data: PackedByteArray = a["data"]
		var box := Rect2i()
		for y in h:
			for x in w:
				if data[(y * w + x) * 4 + 3] > PickupModels.SOLID:
					var pixel := Rect2i(x, y, 1, 1)
					box = pixel if box.size == Vector2i.ZERO else box.merge(pixel)
		var aabb := mesh.get_aabb()
		var want := Vector3(box.size.x, box.size.y, 0.0) / h
		if (
			absf(aabb.size.x - want.x) > .001
			or absf(aabb.size.y - want.y) > .001
			or absf(aabb.end.y - float(h - box.position.y) / h) > .001
			or absf(aabb.get_center().x) > .001
		):
			_fail("pickup %s: the slab is not the picture's size and place" % name)
		if aabb.size.z <= 0.0 or aabb.size.z > aabb.size.x + .001:
			_fail("pickup %s: the slab is %.3f thick" % [name, aabb.size.z])
	if names.is_empty():
		_fail("no pickup pictures (item_*)")
	print("%d pickup meshes, %d triangles" % [names.size(), tris])


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
			if (
				spot >= 0
				and anim.position_track_interpolate(spot, t).y > maxf(height * DOWN_HIGH, .5)
			):
				high += 1
	if high > 0:
		_fail("actor %s: %d parts still up at rest (down)" % [kind, high])
	if partial > 0:
		_fail("actor %s: %d parts partway shrunk at keys" % [kind, partial])


func _fail(line: String) -> void:
	if _failed.size() < 40:
		_failed.append(line)
