## A vehicle's seat view in the 3D view: what the driver of the airboat, the
## stock car or the riding mower sees of their own vehicle from the seat
## (godot/assets3d/cabs/<model>.glb, made by tools/art/build_cab_meshes.gd
## from scripts/blender/vehicle_cabs.py): the body and its moving parts (a
## wheel with the hands on it, the airboat's stick, gauge needles, the fan's
## prop, the mower's blade lever), turned and placed as the frame's `cab`
## says (features/vehicles.gd, src/vehicle_cab.gd), lit by the cell the
## driver sits in.
##
## It is drawn SHRINK times its size toward the eye, looking just as big:
## then it is nearer than anything in the world can come (walls stop the
## hull a cell or more out) and further than the camera's near plane, so it
## never cuts into a wall or hides behind one, and the road beyond shows
## wherever the cab does not cover it. Its own render layer keeps it out of
## the mirror's camera.
class_name CabLayer3D
extends Node3D

const FOLDER := "res://assets3d/cabs"
## The cab is drawn this much of its size, toward the eye: the airboat's bow
## (3 cells ahead) at .3, a hand on a wheel (.35) at .035, inside the hull's
## reach and outside WorldView3D.NEAR (.02).
const SHRINK := .1
## Its render layer (WorldView3D adds it to the eye's camera only).
const LAYER := 8

## model -> {part: [pivot, axis]} in the glb's own (Godot) axes; a hand
## riding another part has [where it holds, that part's axis, its pivot,
## its name, how much of its turn the wrist takes]: it goes round with it
## and turns only that much, so the forearm swings less than the wheel.
var _pivots := {}
var _shader: Shader
var _assets: Assets
## model -> {part: MeshInstance3D} under its root; the root by model.
var _parts := {}
var _roots := {}
var _materials := {}
var _shown := ""
## The cell its light was last taken from.
var _lit := -1
var _lit_level: LevelData


func _init(assets: Assets) -> void:
	_assets = assets
	_shader = load("res://src/view3d/cab.gdshader")
	var path := FOLDER.path_join("cabs.json")
	if not FileAccess.file_exists(path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		return
	var table: Dictionary = data
	for model: String in table:
		var entry: Dictionary = table[model]
		var parts := {}
		for part: String in entry:
			var cell: Variant = entry[part]
			if not cell is Dictionary:
				continue
			var row: Dictionary = cell
			var at: Array = row["at"]
			var axis: Array = row["axis"]
			var made: Array = [_from_blender(at), _from_blender(axis).normalized()]
			if row.has("follow"):
				# A hand riding a turning part (the wheel, the stick).
				var hub: Array = row["hub"]
				var turn: float = row.get("turn", 0.0)
				made.append_array([_from_blender(hub), str(row["follow"]), turn])
			parts[part] = made
		_pivots[model] = parts


## A point or way in Blender's axes (x ahead, y left, z up) in the glb's
## own: glTF's y up, its z toward the old -y.
static func _from_blender(v: Array) -> Vector3:
	var x: float = v[0]
	var y: float = v[1]
	var z: float = v[2]
	return Vector3(x, z, -y)


## Whether a model's seat view can be drawn (its mesh and its baked art are
## here: a browser build may not have fetched them).
func has_model(model: String) -> bool:
	return (
		_pivots.has(model)
		and _assets.has_art("mesh_" + model)
		and ResourceLoader.exists(FOLDER.path_join(model + ".glb"))
	)


## Make the seat views of `seats` (cab model names) now, hidden (a level's
## first frame: a seat view's model, texture and shader cost a tenth of a
## second the first time). Returns the materials made.
func warm(seats: Array[String]) -> Array[ShaderMaterial]:
	var fresh: Array[ShaderMaterial] = []
	for model in seats:
		if has_model(model) and not _roots.has(model):
			fresh.append(_make(model))
			var root: Node3D = _roots[model]
			root.visible = false
	return fresh


## The seat views made and not shown (the view's warm-up draws them once).
func hidden_roots() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for model: String in _roots:
		if model != _shown:
			out.append(_roots[model])
	return out


## Show the frame's `cab` (VehicleCab.dress: model, turn, lift, parts, and
## `fade`: how much of a part shows, 0..1, stippled) seen
## from the eye at map `eye`, or none when it is empty. Returns the material
## made this frame, if any (the view hands it its shader numbers).
func show_cab(cab: Dictionary, eye: Vector3, level: LevelData) -> Array[ShaderMaterial]:
	var fresh: Array[ShaderMaterial] = []
	var model: String = cab.get("model", "")
	if model != "" and not has_model(model):
		model = ""
	if model != _shown:
		if _shown != "":
			var old: Node3D = _roots[_shown]
			old.visible = false
		_shown = model
		_lit = -1
		if model != "":
			if not _roots.has(model):
				fresh.append(_make(model))
			var now: Node3D = _roots[model]
			now.visible = true
	if model == "":
		return fresh
	var turn: Basis = cab["turn"]
	var lift: Vector3 = cab["lift"]
	var full := eye + lift * SHRINK
	var root := Transform3D(
		SolidLayer3D.godot_basis(turn).scaled(Vector3.ONE * SHRINK), Vector3(full.x, full.z, full.y)
	)
	var angles: Dictionary = cab.get("parts", {})
	var fades: Dictionary = cab.get("fade", {})
	var pivots: Dictionary = _pivots[model]
	var parts: Dictionary = _parts[model]
	for part: String in parts:
		var node: MeshInstance3D = parts[part]
		var local := Transform3D.IDENTITY
		if pivots.has(part):
			var row: Array = pivots[part]
			var at: Vector3 = row[0]
			var axis: Vector3 = row[1]
			var angle: float = angles.get(part, 0.0)
			if row.size() > 2:
				var hub: Vector3 = row[2]
				var follow: String = row[3]
				var wrist: float = row[4]
				var round_by: float = angles.get(follow, 0.0)
				var spun := Basis(axis, round_by)
				local = Transform3D(Basis(axis, round_by * wrist), hub + spun * (at - hub))
			else:
				local = Transform3D(Basis(axis, angle), at)
		node.transform = root * local
		if fades.has(part):
			# A part fading out or in (the airboat's prop and its blur).
			var shows: float = fades[part]
			node.visible = shows > .01
			OwnMaterial.put(node, "opacity", shows)
	_light(level, eye)
	return fresh


func _make(model: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader
	var art := _assets.art("mesh_" + model)
	var w: int = art["w"]
	var h: int = art["h"]
	var data: PackedByteArray = art["data"]
	var image := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	m.set_shader_parameter("baked", ImageTexture.create_from_image(image))
	m.set_shader_parameter("shrink", SHRINK)
	_materials[model] = m
	var root := Node3D.new()
	root.name = model
	add_child(root)
	_roots[model] = root
	var parts := {}
	var packed := load(FOLDER.path_join(model + ".glb")) as PackedScene
	if packed != null:
		var scene := packed.instantiate()
		for found in scene.find_children("look_*", "MeshInstance3D", true, false):
			var source := found as MeshInstance3D
			var node := MeshInstance3D.new()
			node.mesh = source.mesh
			OwnMaterial.give(node, m)
			node.layers = LAYER
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(node)
			parts[str(source.name).trim_prefix("look_")] = node
		scene.free()
	_parts[model] = parts
	return m


## Lit by the light and tint of the cell the eye is in, when that changed.
func _light(level: LevelData, eye: Vector3) -> void:
	var c := level.cell(
		clampf(eye.x, 0.0, level.width - .01), clampf(eye.y, 0.0, level.height - .01)
	)
	if c == _lit and level == _lit_level:
		return
	_lit = c
	_lit_level = level
	var ti := clampi(level.area[c], 0, maxi(0, level.tints.size() / 3 - 1)) * 3
	var tone := Color(1, 1, 1, level.light[c])
	if level.tints.size() >= 3:
		tone = Color(level.tints[ti], level.tints[ti + 1], level.tints[ti + 2], level.light[c])
	var parts: Dictionary = _parts[_shown]
	for node: MeshInstance3D in parts.values():
		OwnMaterial.put(node, "tone", tone)
