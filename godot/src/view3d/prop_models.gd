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
## Legacy scenery and pickup art mapped to their authored 3D props.
const PICTURES := {
	"county_dispatch_trunk": "dispatch_trunk",
	"county_room_break": "county_break_kit",
	"county_room_bunk": "county_bunk_kit",
	"county_room_dispatch": "county_dispatch_board",
	"county_room_tickets": "county_ticket_tray",
	"detail_apron_blade_rack": "mill_blade_rack",
	"detail_bar_backstock": "quarry_bottle_row",
	"detail_bottling_cradles": "quarry_bottle_row",
	"detail_carriage_tools": "mill_carriage_tool_board",
	"detail_culvert_catch_rack": "culvert_grate_rack",
	"detail_cutting_drill": "sawmill_cutting_drill",
	"detail_delivery_chocks": "loading_chocks",
	"detail_dispatch_rack": "county_dispatch_board",
	"detail_fair_route_crate": "county_ticket_tray",
	"detail_feed_sampler": "feed_sacks",
	"detail_freight_cartons": "freight_cartons",
	"detail_kiln_duct": "cast_pump_manifold",
	"detail_lost_property_tray": "fair_lost_property_tray",
	"detail_mill_tie_off": "sawmill_tie_off",
	"detail_pa_cable_case": "fair_pa_cable_case",
	"detail_pump_manifold": "cast_pump_manifold",
	"detail_raffle_drawer": "county_ticket_tray",
	"detail_railhead_sacks": "feed_sacks",
	"detail_rain_stock": "lumber_stack",
	"detail_registry_stamp": "county_stamp",
	"detail_scale_weights": "iron_scale_weights",
	"detail_shed_spare_screen": "workshop_spare_screen",
	"detail_shed_tool_tray": "farm_tool_tray",
	"detail_sluice_winder": "sluice_winder",
	"detail_soda_fountain": "county_soda_fountain",
	"detail_sort_chain_box": "mill_sort_roller_frame",
	"detail_stage_footlights": "fair_stage_footlights",
	"detail_still_gauge_bank": "pressure_gauges",
	"detail_ticket_rolls": "county_ticket_rolls",
	"detail_tire_patch_bench": "tire_repair_bench",
	"detail_tow_spool": "county_tow_spool",
	"detail_town_roadside_kit": "county_break_kit",
	"detail_trailer_service": "trailer_service_panel",
	"detail_wash_rejects": "quarry_bottle_row",
	"fair_bulbs": "fair_string_lights",
	"fair_bulbs_off": "fair_string_lights_off",
	"fair_bulbs_on": "fair_string_lights",
	"fair_prize_pile": "fair_prize_toys",
	"fair_pylon": "fair_marker",
	"fair_spill": "fair_cup_litter",
	"hub_lamp": "streetlamp",
	"hub_road_stake": "road_hub_arrow",
	"item_key_brass": "quest_key_brass",
	"item_key_steel": "quest_key_steel",
	"mill_pilings": "mill_pilings",
	"prop_barrel": "yard_barrel",
	"prop_crate": "yard_crate",
	"prop_fuel": "red_fuel_drum",
	"prop_hay": "hay_bale",
	"prop_lamp": "shop_lamp",
	"prop_mailbox": "rural_mailbox",
	"prop_pickup_truck": "pickup_truck",
	"prop_pickup_truck_b": "pickup_truck_b",
	"prop_pump": "roadside_pump",
	"prop_pump_b": "roadside_pump_b",
	"prop_reeds": "brush_reeds",
	"prop_roadsign": "road_sign",
	"prop_silo": "farm_silo",
	"prop_sink": "outdoor_sink",
	"prop_tire": "discarded_tire",
	"prop_tree": "roadside_tree",
	"prop_tree_b": "roadside_tree_b",
	"prop_utilitypole": "power_pole",
	"prop_water_tower": "water_tower",
	"prop_windmill_0": "farm_windmill",
	"prop_windmill_1": "farm_windmill",
	"prop_windmill_2": "farm_windmill",
	"quarry_bottles": "quarry_bottle_row",
	"range_display": "range_weapon_rack",
	"scenery_belt_spent": "yard_belt_spent",
	"scenery_belt_whole": "yard_belt",
	"scenery_bottles_spent": "bottle_group_spent",
	"scenery_bottles_whole": "bottle_group",
	"scenery_cancan_spent": "battered_can_spent",
	"scenery_cancan_whole": "battered_can",
	"scenery_cans_spent": "can_group_spent",
	"scenery_cans_whole": "can_group",
	"scenery_jukebox_spent": "jukebox_cabinet_spent",
	"scenery_jukebox_whole": "jukebox_cabinet",
	"scenery_pipe_spent": "pipe_scrap_spent",
	"scenery_pipe_whole": "pipe_scrap",
	"scenery_scrap_spent": "metal_scrap_spent",
	"scenery_scrap_whole": "metal_scrap",
	"scenery_toilet_spent": "porcelain_toilet_spent",
	"scenery_toilet_whole": "porcelain_toilet",
	"scenery_tv_spent": "tube_tv_spent",
	"scenery_tv_whole": "tube_tv",
	"scenery_vending_spent": "vending_machine_spent",
	"scenery_vending_whole": "vending_machine",
	"scenery_window_spent": "salvage_window_spent",
	"scenery_window_whole": "salvage_window",
	"split_feed_sacks": "feed_sacks",
	"survey_peg": "county_line_marker",
	"wing_mill_sort_rollers": "mill_sort_roller_frame",
	"wing_quarry_still": "still",
	"wing_town_scale": "county_hog_scale_panel",
}

## name -> [width, depth, height, texture size, picture height]: the last,
## how tall its picture town_<name> was drawn (a sprite shown at another
## height stands the model scaled to match; missing on older data).
var sizes: Dictionary = {}
var _meshes: Dictionary = {}
var _scenes: Dictionary = {}
## name -> scene path asked for on the loader's threads (request), not yet taken.
var _asked: Dictionary = {}
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
	if image.begins_with("item_"):
		var pickup := "pickup_" + image.substr(5)
		return pickup if sizes.has(pickup) else ""
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


## The prop's scene (a PropView), or null when it has none. One asked for
## (request) is taken from the loader, waiting for it if it is not done.
func scene(name: String) -> PackedScene:
	var cached: Variant = _scenes.get(name)
	if cached == null:
		var path := SCENES.path_join(name + ".tscn")
		if _asked.has(name):
			_asked.erase(name)
			cached = ResourceLoader.load_threaded_get(path)
		else:
			cached = load(path) if ResourceLoader.exists(path) else null
		_scenes[name] = cached
	var packed: PackedScene = cached
	return packed


## Start loading the scenes of `names` on the loader's threads (pass 10): a
## level's first frame asks for its props' while it builds the level's mesh,
## and scene() takes each when it is needed.
func request(names: Array[String]) -> void:
	for name in names:
		if _scenes.has(name) or _asked.has(name):
			continue
		var path := SCENES.path_join(name + ".tscn")
		if not ResourceLoader.exists(path):
			continue
		if ResourceLoader.load_threaded_request(path, "PackedScene") == OK:
			_asked[name] = path


func mesh(name: String) -> Mesh:
	var cached: Variant = _meshes.get(name)
	if cached != null:
		return cached
	var found: Mesh = null
	# A painted variant can use its base GLB through its own PropView scene.
	var path := FOLDER.path_join(name + ".glb")
	var packed := load(path) as PackedScene if ResourceLoader.exists(path) else scene(name)
	if packed != null:
		var root := packed.instantiate()
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
	var a := _assets.art_for_texture("mesh_" + name)
	var w: int = a["w"]
	var h: int = a["h"]
	var data: PackedByteArray = a["data"]
	var image := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	var tex := ImageTexture.create_from_image(image)
	_textures[name] = tex
	return tex
