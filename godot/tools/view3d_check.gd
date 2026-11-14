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
	print("%d triangles in %d levels, %d prop models" % [total, ids.size(), models.sizes.size()])
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


func _fail(line: String) -> void:
	if _failed.size() < 40:
		_failed.append(line)
