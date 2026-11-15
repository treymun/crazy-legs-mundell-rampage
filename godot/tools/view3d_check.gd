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
		view.free()
	print("%d actor models" % actors.kinds.size())
	_check_slabs(assets)
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


func _fail(line: String) -> void:
	if _failed.size() < 40:
		_failed.append(line)
