## The props that have a mesh for the 3D view (godot/assets3d/props, made by
## tools/art/build_prop_meshes.gd): a sprite showing `town_<name>` is drawn as
## that mesh instead, with its baked texture `mesh_<name>` from the art.
class_name PropModels
extends RefCounted

const FOLDER := "res://assets3d/props"
## Each prop's scene: a PropView over its mesh (tools/art/build_prop_scenes.gd).
const SCENES := "res://scenes/props"

## The looks a quest station's one model holds (mesh nodes `look_off`,
## `look_on`), named by its pictures' endings: town_quest_<name>_off / _on.
const LOOKS: Array[String] = ["off", "on"]
## How far the old pictures turned a model from face on (scripts/blender:
## -28 degrees): a prop that faces where it is used from is turned so, and
## from there is seen as its picture showed it.
const PICTURE_TURN := deg_to_rad(28.0)
## Pictures not named town_<name> that a model stands for: the hanging shop
## lamp game.gd hangs under a roof (and a boss arena's wreck drops).
const PICTURES := {"prop_lamp": "shop_lamp"}

## name -> [width, depth, height, texture size, picture height]: the last,
## how tall its picture town_<name> was drawn (a sprite shown at another
## height stands the model scaled to match; missing on older data).
var sizes: Dictionary = {}
var _meshes: Dictionary = {}
var _scenes: Dictionary = {}
var _textures: Dictionary = {}
## picture -> the model name its text stands for ("" none), and model name ->
## whether its scene exists: name_of runs for every sprite every frame, and
## ResourceLoader.exists costs tens of microseconds a call.
var _named: Dictionary = {}
var _has_scene: Dictionary = {}
## picture -> its model's name once its art and scene are here (they stay).
var _ready: Dictionary = {}
var _assets: Assets


func _init(assets: Assets) -> void:
	_assets = assets
	var path := FOLDER.path_join("meshes.json")
	if FileAccess.file_exists(path):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary:
			sizes = data


## The prop name a sprite's picture stands for, or "" when it has no mesh.
## A quest station's pictures (town_quest_<name>_off, _on) both stand for its
## one model, `quest_<name>`.
func name_of(image: String) -> String:
	var ready: Variant = _ready.get(image)
	if ready != null:
		var ready_name: String = ready
		return ready_name
	var known: Variant = _named.get(image)
	if known == null:
		known = _model_named(image)
		_named[image] = known
	var name: String = known
	if name == "":
		return ""
	# The art and model may come later (a chapter's pack fetched in the
	# browser): its picture stands in till then.
	if not _assets.art_ready("mesh_" + name):
		return ""
	var ok: Variant = _has_scene.get(name)
	if ok == null:
		ok = ResourceLoader.exists(SCENES.path_join(name + ".tscn"))
		_has_scene[name] = ok
	if not ok:
		return ""
	_ready[image] = name
	return name


## Whether a picture's name stands for a model at all (by its text alone:
## its art may still be coming).
func named(image: String) -> bool:
	var known: Variant = _named.get(image)
	if known == null:
		known = _model_named(image)
		_named[image] = known
	return known != ""


## The model a picture's name stands for by its text alone ("" none).
func _model_named(image: String) -> String:
	if PICTURES.has(image):
		var named: String = PICTURES[image]
		return named if sizes.has(named) else ""
	if not image.begins_with("town_"):
		return ""
	var name := image.substr(5)
	if not sizes.has(name):
		var look := look_of(image)
		if look == "":
			return ""
		name = name.trim_suffix("_" + look)
		if not sizes.has(name):
			return ""
	return name


## Which look of its model a picture shows ("off", "on"), or "" for a prop
## with one look.
func look_of(image: String) -> String:
	if sizes.has(image.substr(5)):
		return ""
	for look in LOOKS:
		if image.ends_with("_" + look):
			return look
	return ""


## How much bigger than its model a sprite stands (its height over the
## height its picture was drawn at); 1 when they match or that is unknown.
func scale_of(name: String, height: float) -> float:
	var dims: Array = sizes.get(name, [])
	if dims.size() < 5:
		return 1.0
	var drawn: float = dims[4]
	if drawn <= 0.0 or absf(height - drawn) < .02:
		return 1.0
	return height / drawn


## Which way a prop standing at (x, y) faces (radians about up, the model's
## +Z, map +y, turned by it): a board keeps its own axis (`plane`), a quest
## prop turns to show where it is used from (`face`) the view its picture
## had; anything else turns its front toward the most open of eight ways.
## The 3D view stands props so (PropLayer3D), and features/wreckage.gd
## throws a broken prop's pieces from where they stood.
static func facing(level: LevelData, x0: float, y0: float, plane := NAN, face := NAN) -> float:
	if not is_nan(plane):
		return -plane
	if not is_nan(face):
		return face - PICTURE_TURN
	var best := 0.0
	var best_open := -1.0
	for k in 8:
		var a := k * PI / 4.0
		var dx := sin(a)
		var dy := cos(a)
		var open := 0.0
		while open < 3.0:
			var x := x0 + dx * (open + .5)
			var y := y0 + dy * (open + .5)
			if x < 0 or y < 0 or x >= level.width or y >= level.height:
				break
			if level.solid[level.cell(x, y)] >= 0:
				break
			open += .25
		# Straight ways win a tie (the sprites were drawn square to the street).
		if open > best_open + (.01 if k % 2 == 0 else .3):
			best_open = open
			best = a
	return best


## The prop's scene (a PropView), or null when it has none.
func scene(name: String) -> PackedScene:
	var cached: Variant = _scenes.get(name)
	if cached == null:
		var path := SCENES.path_join(name + ".tscn")
		cached = load(path) if ResourceLoader.exists(path) else null
		_scenes[name] = cached
	var packed: PackedScene = cached
	return packed


func mesh(name: String) -> Mesh:
	var cached: Variant = _meshes.get(name)
	if cached != null:
		return cached
	var found: Mesh = null
	var scene := load(FOLDER.path_join(name + ".glb")) as PackedScene
	if scene != null:
		var root := scene.instantiate()
		found = _first_mesh(root)
		root.free()
	_meshes[name] = found
	return found


static func _first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D:
		return (node as MeshInstance3D).mesh
	for child in node.get_children():
		var m := _first_mesh(child)
		if m != null:
			return m
	return null


func texture(name: String) -> ImageTexture:
	var cached: Variant = _textures.get(name)
	if cached != null:
		return cached
	var a := _assets.art("mesh_" + name)
	var w: int = a["w"]
	var h: int = a["h"]
	var data: PackedByteArray = a["data"]
	var image := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	var tex := ImageTexture.create_from_image(image)
	_textures[name] = tex
	return tex
