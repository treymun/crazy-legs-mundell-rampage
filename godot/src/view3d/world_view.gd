## The game's 3D view: a SubViewport the size of the old view (320x156, HD
## 640x312) holding the level's meshes, the frame's sprites and the sky, seen
## by a camera that reproduces the old renderer's projection (an off-axis
## frustum: looking up and down shifts the horizon, as in the Build engine,
## so aim, crosshair and every screen overlay stay true). The display shader
## (the old view shader, view3d_on) lays the weapon/HUD layer and the look pass
## over its picture.
##
## Read-only toward play: it reads the game's level, camera and sprite list
## each frame (Game.view_frame, set by game_view.gd _draw) and changes nothing.
class_name WorldView3D
extends Node

const NEAR := .02
const FAR := 160.0
## How far behind the storm's front curtain the second one stands (cells;
## storm_wall.gdshader OUTER).
const OUTER_STORM := 2.5
const WeatherFeature := preload("res://src/features/weather.gd")
const WaterFeature := preload("res://src/features/water.gd")
const CountyRun := preload("res://src/features/county_run.gd")
const VehiclesFeature := preload("res://src/features/vehicles.gd")
## Render layers: the world (1), the player's reflection (2, the mirror's
## camera only), the sky behind the eye's camera (3), and the bit that tells
## the shaders they draw the mirror's pass (view_light.gdshaderinc).
const LAYER_WORLD := 1
const LAYER_REFLECTION := 2
const LAYER_SKY := 4
const LAYER_MIRROR := 1 << 19

var viewport: SubViewport
var camera: Camera3D
var world_material: ShaderMaterial
var glass_material: ShaderMaterial
var sky_material: ShaderMaterial
var sprites: SpriteLayer3D
var slabs: SlabLayer3D
var solids: SolidLayer3D
var props: PropLayer3D
var wrecks: WreckLayer3D
var actors: ActorLayer3D
## The driver's own vehicle from the seat (cab_layer.gd).
var cab: CabLayer3D
var tiles: ViewTiles
var _root: Node3D
var _chunks: Node3D
## How far this frame draws (View.draw_far).
var game_far := FAR
## A view tour's "cels": enemies drawn as their old cels, not their models
## (the old pictures beside the new, for comparison sheets).
static var cels := false
var _moving: MeshInstance3D
var _sky: MeshInstance3D
var _assets: Assets
var _level: LevelData
var _builder: LevelMesh
var _built_key: Array = []
## The level whose kinds' ragdoll rigs have been found (ActorLayer3D.prepare).
var _rigged: LevelData
## The level's chunks by key, and how many of its retiled wall pieces
## (LevelData.retiled) they show.
var _chunk_nodes := {}
var _retiled_seen := 0
## The walls' version and LevelData.reshapes, reshaped built for, and the
## cell texture's pixels (_reshape).
var _walls_seen := 0
var _reshapes_seen := 0
var _reshaped_seen := 0
var _cell_pixels: Image
var _moving_rows := PackedFloat32Array()
var _cells: ImageTexture
var _anim_tiles := {}
var _params := {}
## picture -> how a sprite showing it is drawn when nothing about the sprite
## itself says otherwise (_picture_kind): PICTURE_MODEL a prop's model, else
## its slab family (SlabModels.NONE: a picture). Asked for every sprite every
## frame.
const PICTURE_MODEL := -1
var _picture_kinds := {}
## The frame's numbers and the view's textures, which the shaders take as
## global uniforms (project.godot [shader_globals]), as last set: one call a
## number, no material touched. A model part's own numbers are its own
## material's (OwnMaterial).
const GLOBALS := {
	"anim_count": true,
	"anim_time": true,
	"blackout": true,
	"cells_tex": true,
	"effects_on": true,
	"eye": true,
	"flash": true,
	"flash_dir": true,
	"focal": true,
	"fog_banks": true,
	"fog_color": true,
	"fog_range": true,
	"grade": true,
	"horizon": true,
	"hub_fx": true,
	"hub_patch": true,
	"hub_runoff": true,
	"hub_wall": true,
	"light_count": true,
	"lightning": true,
	"liquor_flicker": true,
	"map_size": true,
	"mirror_on": true,
	"mirror_tex": true,
	"mirror_x": true,
	"moon_rim": true,
	"motion": true,
	"pool": true,
	"rain": true,
	"res_up": true,
	"ring_count": true,
	"shadow_gust": true,
	"shadow_lx": true,
	"shadow_ly": true,
	"shadow_still": true,
	"sky_drift": true,
	"sky_tex": true,
	"storm_base": true,
	"storm_k": true,
	"storm_r": true,
	"storm_rich": true,
	"storm_ring": true,
	"tile_info_tex": true,
	"tiles": true,
	"view_angle": true,
	"view_data": true,
	"view_size": true,
	"water_drift": true,
	"wet": true,
	"wind_now": true
}
var _globals := {}
## The frame's lists (view_light.gdshaderinc view_row): ROWS rows of DATA_W
## RGBA32F texels in view_data, uploaded once a frame when one changed.
const DATA_W := 16
const ROWS := 13
const ROW_LIGHT_POS := 0
const ROW_LIGHT_COL := 1
const ROW_LIGHT_FLAGS := 2
const ROW_RINGS := 3
const ROW_ANIMS := 4
const ROW_SHADOW_A := 5
const ROW_SHADOW_B := 6
const ROW_BLOBS := 7
const ROW_FLOW := 8
## The plank walls shot about (features/wall_looks.gd view_rows): cells and
## their planks, two rows of each.
const ROW_PLANK0 := 9
var _data := PackedFloat32Array()
var _data_image: Image
var _data_tex: ImageTexture
var _data_dirty := false
## SHADOWS' numbers as last handed to the floors, walls and marks.
var _received := {}
var _materials: Array[ShaderMaterial] = []
## The level's flowing floors' first two tiles and speeds, and the moving
## tiles' rows (_uniforms), worked out when the level or its tiles change.
var _flows_of: LevelData
var _flows: Array = []
var _anims := PackedVector4Array()
var _anim_count := -1
var _rain: Array[MeshInstance3D] = []
## County Run's storm front: a wall round the safe ground, its front curtain
## and the one behind it (storm_wall.gdshader).
var _storm_walls: Array[MeshInstance3D] = []
var _storm_materials: Array[ShaderMaterial] = []
## A county event's twister (src/event_twister.gd): its funnel, the debris
## cloud round its foot and the wall cloud over it (twister.gdshader).
var _twister: Array[MeshInstance3D] = []
var _twister_materials: Array[ShaderMaterial] = []
## The warm-up (warm_up): frames of a new level left to draw what is still
## hidden, and what was put out for it (node -> [its transform, shown]).
const WARM_FRAMES := 2
const SPECK := .0001
const SPECK_AWAY := 40.0
var _warm := 0
var _warmed := {}
## The title's warm-up (warm_title): what it draws and what it has still to
## put out.
var _stage: Node3D
## The pickups' pictures warm_title builds slab meshes for, a few a call.
var _stage_items: Array[String] = []
var _headless := DisplayServer.get_name() == "headless"
var _stage_left: Array[Callable] = []
## SHADOWS: what the strong lights and the sky throw (view_shadows.gd).
var _shadows := ViewShadows.new()
## Holes, scorch and char on props, vehicles and wreck pieces (thing_marks.gd).
var _thing_marks := ThingMarks.new()
## Where frame() spends its time, summed in microseconds per part (the
## benches print and clear it: main.gd --view-bench, tools/stress_bench.gd).
const PART_NAMES: Array[String] = [
	"setup",
	"shadows",
	"props",
	"wrecks",
	"marks",
	"actors",
	"glue",
	"sprites",
	"slabs",
	"decals",
	"uniforms"
]
var parts_us := PackedInt64Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
## The shader instance buffer where a uniform block holds 16 KB (WebGL2's
## least, many phones): 1024 vec4 slots for the global uniforms (one each)
## and, after them, a block of 16 for every model part drawn with a shader
## that has instance uniforms, shown or hidden (Godot's fixed block, whatever
## the shader uses; measured, pass 10). Past it parts draw black. No view3d
## shader has instance uniforms since pass 10 (OwnMaterial);
## tools/view_perf_check.gd and stress_bench.gd's check hold the busy scenes
## under INSTANCE_ROOM_SMALL parts with INSTANCE_MARGIN to spare.
const INSTANCE_SLOTS_SMALL := 1024
const INSTANCE_ROOM_SMALL := 60
const INSTANCE_MARGIN := 20
## The mirror's two pictures and their cameras, drawn in turn (_mirror):
## `_mirror_k` is the one being drawn, the other the one read.
var _mirror_views: Array[SubViewport] = []
var _mirror_cameras: Array[Camera3D] = []
var _mirror_k := 0
var _mirror_live := false


func _init(assets: Assets) -> void:
	_assets = assets
	tiles = ViewTiles.new(assets)
	viewport = SubViewport.new()
	viewport.size = Vector2i(320, 156)
	viewport.own_world_3d = true
	viewport.transparent_bg = false
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_debanding = false
	viewport.scaling_3d_scale = 1.0
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.positional_shadow_atlas_size = 0
	add_child(viewport)
	_root = Node3D.new()
	viewport.add_child(_root)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_FRUSTUM
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = NEAR
	camera.far = FAR
	camera.current = true
	camera.cull_mask = LAYER_WORLD | LAYER_SKY | CabLayer3D.LAYER
	_root.add_child(camera)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0, 0, 0)
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	_root.add_child(world_env)

	world_material = ShaderMaterial.new()
	world_material.shader = load("res://src/view3d/world.gdshader")
	glass_material = ShaderMaterial.new()
	glass_material.shader = load("res://src/view3d/world_glass.gdshader")
	glass_material.render_priority = 2
	sky_material = ShaderMaterial.new()
	sky_material.shader = load("res://src/view3d/sky.gdshader")
	sky_material.render_priority = -1
	_chunks = Node3D.new()
	_root.add_child(_chunks)
	_moving = MeshInstance3D.new()
	_root.add_child(_moving)
	sprites = SpriteLayer3D.new(assets)
	_root.add_child(sprites)
	slabs = SlabLayer3D.new(SlabModels.new(assets), sprites)
	_root.add_child(slabs)
	solids = SolidLayer3D.new()
	_root.add_child(solids)
	props = PropLayer3D.new(PropModels.new(assets))
	_root.add_child(props)
	wrecks = WreckLayer3D.new(assets)
	wrecks.prop_models = props.models
	_root.add_child(wrecks)
	actors = ActorLayer3D.new(ActorModels.new(assets))
	_root.add_child(actors)
	cab = CabLayer3D.new(assets)
	_root.add_child(cab)
	_sky = MeshInstance3D.new()
	var plane := QuadMesh.new()
	plane.size = Vector2(4000.0, 4000.0)
	_sky.mesh = plane
	_sky.material_override = sky_material
	_sky.position = Vector3(0.0, 0.0, -(FAR - 1.0))
	_sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sky.layers = LAYER_SKY
	camera.add_child(_sky)
	# The rain's three layers of streaks, nearest first (rain.gdshader).
	var rain_shader: Shader = load("res://src/view3d/rain.gdshader")
	var rain_materials: Array[ShaderMaterial] = []
	for k in 3:
		var depth: float = [1.3, 2.8, 6.0][k]
		var rain_material := ShaderMaterial.new()
		rain_material.shader = rain_shader
		rain_material.set_shader_parameter("layer_k", k)
		rain_material.render_priority = 10 - k
		var sheet := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(depth * 6.0, depth * 6.0)
		sheet.mesh = quad
		sheet.material_override = rain_material
		sheet.position = Vector3(0.0, 0.0, -depth)
		sheet.layers = LAYER_SKY
		sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sheet.visible = false
		camera.add_child(sheet)
		_rain.append(sheet)
		rain_materials.append(rain_material)
	var tube := CylinderMesh.new()
	tube.top_radius = 1.0
	tube.bottom_radius = 1.0
	tube.height = 1.0
	tube.cap_top = false
	tube.cap_bottom = false
	tube.radial_segments = 96
	tube.rings = 1
	var storm_shader: Shader = load("res://src/view3d/storm_wall.gdshader")
	for k in 2:
		var storm_material := ShaderMaterial.new()
		storm_material.shader = storm_shader
		storm_material.set_shader_parameter("layer_k", k)
		storm_material.render_priority = 5 - k
		var wall := MeshInstance3D.new()
		wall.mesh = tube
		wall.material_override = storm_material
		wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wall.visible = false
		_root.add_child(wall)
		_storm_walls.append(wall)
		_storm_materials.append(storm_material)
	var rope := CylinderMesh.new()
	rope.top_radius = 1.0
	rope.bottom_radius = 1.0
	rope.height = 1.0
	rope.cap_top = false
	rope.cap_bottom = false
	rope.radial_segments = 40
	rope.rings = 48
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 1.0
	disc.radial_segments = 48
	disc.rings = 6
	var twister_shader: Shader = load("res://src/view3d/twister.gdshader")
	for k in 3:
		var twister_material := ShaderMaterial.new()
		twister_material.shader = twister_shader
		twister_material.set_shader_parameter("part", k)
		twister_material.render_priority = [2, 3, 1][k]
		var piece := MeshInstance3D.new()
		piece.mesh = disc if k == 2 else rope
		piece.material_override = twister_material
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		piece.extra_cull_margin = 40.0
		piece.visible = false
		_root.add_child(piece)
		_twister.append(piece)
		_twister_materials.append(twister_material)
	_materials = [world_material, glass_material, sky_material]
	_materials.append_array(_storm_materials)
	_materials.append_array(_twister_materials)
	_materials.append_array(rain_materials)
	_materials.append_array(sprites.materials())
	_materials.append(slabs.material)
	_materials.append(solids.material)
	_share("tiles", tiles.tiles)
	_share("tile_info_tex", tiles.info)
	_data.resize(DATA_W * ROWS * 4)
	for k in DATA_W * 2:
		# No plank wall shot about yet (a cell's x of -1 ends the list).
		_data[((ROW_PLANK0 + (k / DATA_W) * 2) * DATA_W + k % DATA_W) * 4] = -1.0
	_data_image = Image.create_from_data(
		DATA_W, ROWS, false, Image.FORMAT_RGBAF, _data.to_byte_array()
	)
	_data_tex = ImageTexture.create_from_image(_data_image)
	_share("view_data", _data_tex)


## What a level may show later that costs a hitch the first time (a model
## loaded and its texture made, its ragdoll rig found): the county events'
## hogs and raiders, the level's vehicles' seat views, the props it stands.
## Made now, at the level's first frame, behind the chapter's opener or the
## load.
func _warm_models(game: Game) -> void:
	var items: Array[String] = []
	var pickup_models: Array[String] = []
	for entry: Array in game.pickups:
		var item := "item_" + str(entry[0])
		var model := props.models.name_of(item)
		if model != "" and not model in pickup_models:
			pickup_models.append(model)
		elif model == "" and not item in items:
			items.append(item)
	props.warm(game.level, pickup_models)
	slabs.warm(items)
	actors.warm(_warm_actor_kinds(game))
	var rides: VehiclesFeature = game.features.get("vehicles")
	if rides != null:
		var seats: Array[String] = []
		for ride: VehicleDrive.Ride in rides.rides:
			var seat := VehicleDrive.spec(ride.kind).cab
			if seat != "" and not seat in seats:
				seats.append(seat)
		cab.warm(seats)


## Models shown from the first round or when a county event starts.
static func _warm_actor_kinds(game: Game) -> Array[String]:
	if Modes.is_tactical(game):
		var roles: Array[String] = [ModeBodies.OUTLAW_KIND, ModeBodies.DEPUTY_KIND]
		if Modes.mode_of(game) == Modes.HOSTAGE:
			roles.append(ModeBodies.HOSTAGE_KIND)
		return roles
	if game.features.get("events") == null:
		return []
	return ["hog", EventRaid.squad_kind()]


## The view's first frames of a level draw, a speck in front of the eye, all
## that is hidden till something calls for it (the twister, County Run's
## storm wall, the rain, the seat views made by _warm_models), so each
## shader is compiled now rather than in the frame it first shows: the
## twister cost 0.6 s there, a seat view 0.12 s (tools/hitch_bench.gd; the
## browser and a phone's first run compile every shader the first time it is
## drawn). The next frame puts them back as they were (_unwarm).
func warm_up() -> void:
	var front := camera.global_transform
	# Well off and a ten-thousandth of its size: the twister's 30-cell funnel
	# is then 0.003 of a cell 40 cells away, under a pixel at any HD.
	var speck := Transform3D(
		front.basis.scaled(Vector3.ONE * SPECK), front * Vector3(0.0, 0.0, -SPECK_AWAY)
	)
	var hidden: Array[Node3D] = []
	hidden.append_array(_twister)
	hidden.append_array(_storm_walls)
	hidden.append_array(_rain)
	hidden.append_array(cab.hidden_roots())
	hidden.append_array(actors.warm_roots())
	hidden.append_array(wrecks.warm_roots())
	for node: Node3D in hidden:
		if node.visible or _warmed.has(node):
			continue
		_warmed[node] = [node.transform, node.visible]
		node.global_transform = speck
		node.visible = true


## While a menu is up before the first level (pass 10): every shader the
## view draws with compiled, one more each call, so the first level's first
## frame compiles none. In the browser that frame took 10 s (SwiftShader;
## render() 0.66 s of it); a desktop's first run pays it too, a phone's
## likewise. Each call puts one more piece out in front of the camera (a
## quad with that shader's material; four of them in MultiMeshes, as the
## sprites, slabs and solids draw) and has the viewport draw once; the sky
## draws itself; then every pickup's slab mesh is built, eight a call
## (SlabLayer3D.warm). Nobody sees the viewport till play shows it, and the
## last call takes the pieces away. False when it is done.
func warm_title() -> bool:
	if _stage == null:
		_stage = Node3D.new()
		_root.add_child(_stage)
		_stage_left = _title_pieces()
		for name: String in _assets.art_index:
			if SlabModels.family(name) == SlabModels.PICKUP:
				_stage_items.append(name)
	if _stage_left.is_empty() and not _stage_items.is_empty():
		# Then every pickup's slab (SlabLayer3D.warm), eight a call.
		slabs.warm(_stage_items.slice(0, 8))
		_stage_items = _stage_items.slice(8)
		return true
	if _stage_left.is_empty():
		_stage.queue_free()
		_stage = null
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return false
	var make: Callable = _stage_left.pop_front()
	var piece: Node3D = make.call()
	piece.position = Vector3(0.0, -.5, -3.0)
	_stage.add_child(piece)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	return true


## warm_title's pieces, each a Callable making one.
func _title_pieces() -> Array[Callable]:
	var plain: Array[ShaderMaterial] = [world_material, glass_material]
	plain.append_array(_storm_materials)
	plain.append_array(_twister_materials)
	for sheet: MeshInstance3D in _rain:
		plain.append(sheet.material_override as ShaderMaterial)
	# (ActorRim.SHADER: the awake hands' edge pass, pass 15, hung as a next pass.)
	var shaders: Array[Shader] = [
		props._shader, wrecks._shader, cab._shader, actors.models._shader, ActorRim.SHADER
	]
	for shader: Shader in shaders:
		var m := ShaderMaterial.new()
		m.shader = shader
		plain.append(m)
	var out: Array[Callable] = []
	for m in plain:
		out.append(_title_quad.bind(m))
	out.append(wrecks.title_piece)
	var many: Array[ShaderMaterial] = sprites.materials()
	many.append_array([slabs.material, solids.material, wrecks.fine_material()])
	for m in many:
		out.append(_title_many.bind(m))
	return out


static func _title_quad(material: ShaderMaterial) -> Node3D:
	var node := MeshInstance3D.new()
	node.mesh = QuadMesh.new()
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


static func _title_many(material: ShaderMaterial) -> Node3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = QuadMesh.new()
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D.IDENTITY)
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## What warm_up put out, put back.
func _unwarm() -> void:
	for node: Node3D in _warmed:
		var was: Array = _warmed[node]
		node.transform = was[0]
		node.visible = was[1]
	_warmed.clear()


## Whether warm_up still has frames to draw (tools/warm_check.gd).
func warming() -> bool:
	return _warm > 0


## The model parts under `root` (shown or hidden) drawn with a shader that
## has instance uniforms: each holds a block of the shader instance buffer.
## (Tools and checks; none since pass 10.)
static func instance_uniform_parts(root: Node) -> int:
	var n := 0
	var asked := {}
	for node: Node in root.find_children("*", "GeometryInstance3D", true, false):
		var part := node as GeometryInstance3D
		var m := part.material_override as ShaderMaterial
		if m == null or m.shader == null:
			continue
		var has: Variant = asked.get(m.shader)
		if has == null:
			has = _has_instance_uniforms(m.shader.code, 0)
			asked[m.shader] = has
		n += 1 if has else 0
	return n


## Whether shader code (with its includes) declares an instance uniform.
static func _has_instance_uniforms(code: String, depth: int) -> bool:
	if RegEx.create_from_string("(?m)^\\s*instance\\s+uniform").search(code) != null:
		return true
	if depth > 4:
		return false
	for found in RegEx.create_from_string('(?m)^\\s*#include\\s+"([^"]+)"').search_all(code):
		var inner := FileAccess.get_file_as_string(found.get_string(1))
		if _has_instance_uniforms(inner, depth + 1):
			return true
	return false


func texture() -> ViewportTexture:
	return viewport.get_texture()


## The moon's rim (view_light.gdshaderinc moon_rim): the level's own
## (effects.cfg `moon_rim`, the night chapter's), and in a blackout as much
## more as the power is gone (events.cfg [blackout] `moon_rim`).
func _moon_rim(id: String, county: CountyEvents, dark: float) -> Vector4:
	var rim: Color = Effects.mood(id, "moon_rim", Color(0.55, 0.64, 0.95, 0.0))
	var amount := rim.a
	if dark > 0.0 and county != null:
		var full := county.n("blackout", "dark")
		amount += county.n("blackout", "moon_rim") * clampf(dark / maxf(full, .01), 0.0, 1.0)
	return Vector4(rim.r, rim.g, rim.b, amount)


## A number as last handed to the shaders (_share), global or not; null when
## never handed (tools/view_perf_check.gd, view_polish_check.gd).
func shared(name: String) -> Variant:
	return _globals.get(name, _params.get(name))


## Set a shader number when it changed: a global uniform (GLOBALS) once, or
## else on the view's own materials (the layers' copies never take one).
func _share(name: String, value: Variant) -> void:
	if GLOBALS.has(name):
		var was: Variant = _globals.get(name)
		if was != null and typeof(was) == typeof(value) and was == value:
			return
		_globals[name] = value
		RenderingServer.global_shader_parameter_set(name, value)
		return
	var old: Variant = _params.get(name)
	if old != null and typeof(old) == typeof(value) and old == value:
		return
	_params[name] = value
	for m: ShaderMaterial in _materials:
		m.set_shader_parameter(name, value)


## Row `row` of view_data from `values` (as many as fit), when it changed.
func _row(row: int, values: PackedVector4Array) -> void:
	var o := row * DATA_W * 4
	for i in mini(values.size(), DATA_W):
		var v := values[i]
		var k := o + i * 4
		if _data[k] != v.x or _data[k + 1] != v.y or _data[k + 2] != v.z or _data[k + 3] != v.w:
			_data[k] = v.x
			_data[k + 1] = v.y
			_data[k + 2] = v.z
			_data[k + 3] = v.w
			_data_dirty = true


## view_data to the graphics card, when a row changed this frame.
func _upload_data() -> void:
	if not _data_dirty:
		return
	_data_dirty = false
	_data_image.set_data(DATA_W, ROWS, false, Image.FORMAT_RGBAF, _data.to_byte_array())
	_data_tex.update(_data_image)


## SHADOWS' numbers (view_shadows.gd), only to what takes shadows: the
## level's floors and walls and the marks on them (their counts; the lists
## are view_data's rows), when they changed.
func _share_shadows() -> void:
	var counts := Vector2i(_shadows.pair_count, _shadows.blob_count)
	var values := {
		"shadow_count": counts.x,
		"blob_count": counts.y,
	}
	if counts.x > 0:
		_row(ROW_SHADOW_A, _shadows.pair_a)
		_row(ROW_SHADOW_B, _shadows.pair_b)
	if counts.y > 0:
		_row(ROW_BLOBS, _shadows.blobs)
	var takers: Array[ShaderMaterial] = [world_material, glass_material, sprites.mark_material]
	for name: String in values:
		var value: Variant = values[name]
		var old: Variant = _received.get(name)
		if old != null and typeof(old) == typeof(value) and old == value:
			continue
		_received[name] = value
		for m in takers:
			m.set_shader_parameter(name, value)


## Draw this frame of `game` (call after game.draw()).
func frame(game: Game) -> void:
	var view: Dictionary = game.view_frame
	if view.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	_unwarm()
	if _stage != null:
		# A level started before the title's warm-up was done: its pieces go
		# (what it had not compiled compiles as the level draws).
		_stage.queue_free()
		_stage = null
		_stage_left.clear()
		_stage_items.clear()
	var r: View = game.view
	var level: LevelData = game.level
	var vw: int = r.vw
	var vh: int = r.vh
	if viewport.size != Vector2i(vw, vh):
		viewport.size = Vector2i(vw, vh)
	tiles.refresh()
	_share("tiles", tiles.tiles)
	_share("tile_info_tex", tiles.info)
	var eye: Dictionary = view["eye"]
	var x: float = eye["x"]
	var y: float = eye["y"]
	var z: float = eye["eye"]
	var angle: float = eye["view_angle"]
	var at_hub: bool = not level.road_and_hub.is_empty() and y > 33.0
	if level != _rigged and not _headless:
		# Its models load on the loader's threads while its mesh is built
		# (pass 10); _warm_models then takes them. Not headless: the dummy
		# renderer's meshes are not made safely from two threads at once.
		props.models.request(props.level_models(level))
		actors.request(game.enemies, _warm_actor_kinds(game))
	_build(level, at_hub)
	var looks: WallLooks = game.features.get("wall_looks")
	var planks := looks.view_rows(x, y) if looks != null else WallLooks.blank_rows()
	for k in 4:
		var row: PackedVector4Array = planks[k]
		_row(ROW_PLANK0 + k, row)
	if level != _rigged:
		_rigged = level
		actors.prepare(game.enemies)
		_warm_models(game)
	game_far = r.draw_far
	var horizon: float = view["horizon"]
	# A driver's view is a little wider, more so at speed (vehicle_cab.gd):
	# the view's middle still looks where the crosshair aims.
	var wide: float = eye.get("wide", 1.0)
	_place_camera(x, y, z, angle, horizon, r.focal, vh, wide)
	var roll: float = eye.get("roll", 0.0)
	if roll != 0.0:
		# A chapter opener's camera leans into its turns (opener_camera.gd).
		camera.transform.basis = camera.transform.basis * Basis(Vector3(0, 0, 1), -roll)
	var mirror := not is_nan(level.mirror_x)
	_mirror(mirror, level, x, y, z, angle, horizon, r.focal, Vector2i(vw, vh))
	# Sprites whose picture has a mesh are stood up as props, enemies with a
	# model as actors, pickups, loose things and range targets as slabs; the
	# rest stay pictures.
	var pictures: Array = []
	var modelled: Array = []
	var acting: Array = []
	var slabbed: Array = []
	var solid: Array = []
	var wrecked: Array = []
	var gear: Array = []
	var listed: Array = view["sprites"]
	for item: Variant in listed:
		if not item is View.Sprite:
			pictures.append(item)
			continue
		var s: View.Sprite = item
		# WreckLayer3D.takes, SolidLayer3D.takes, actors.takes, a prop's
		# model, slabs.takes, in that order, the picture's part kept.
		var enemy := s.who is Enemy
		if s.solid.begins_with("~"):
			wrecked.append(s)
		elif enemy and s.gear != "":
			if not cels:
				gear.append(s)
		elif s.solid != "":
			solid.append(s)
		elif enemy and not cels and actors.takes(s, s.who as Enemy):
			acting.append(s)
		else:
			var kind := _picture_kind(s.image)
			if kind == PICTURE_MODEL:
				modelled.append(s)
			elif (
				kind != SlabModels.NONE
				and not s.translucent
				and (kind != SlabModels.PICKUP or is_nan(s.plane))
			):
				slabbed.append(s)
			else:
				pictures.append(item)
	var t1 := Time.get_ticks_usec()
	_shadows.collect(game, acting, modelled, wrecked, Vector3(x, y, z), props.models)
	var t2 := Time.get_ticks_usec()
	var prop_clock: float = game.clock * [1.0, .4, 0.0][clampi(r.world_motion, 0, 2)]
	props.show_props(modelled, level, Vector3(x, y, z), prop_clock)
	var t3 := Time.get_ticks_usec()
	wrecks.show_wrecks(wrecked, level)
	var t4 := Time.get_ticks_usec()
	_thing_marks.update(game, props, wrecks)
	var t5 := Time.get_ticks_usec()
	var gear_lost: Dictionary = view.get("gear_lost", {})
	ActorView.draws += 1
	ActorView.lod_eye = Vector3(x, y, z)
	ActorView.lod_high = ActorView.LOD_HIGH * r.focal / View.FOCAL
	ActorView.lod_low = r.detail == 1
	actors.show_actors(acting, level, game.clock, game.gore_fx.lost, gear_lost, Vector3(x, y, z))
	actors.show_gear(gear, level)
	var t6 := Time.get_ticks_usec()
	# The player in the mirror: their model when they have one, else their picture.
	var reflection: View.Sprite = null
	if mirror:
		reflection = view.get("reflection")
	actors.show_reflection(reflection, level, game.clock, LAYER_REFLECTION)
	var seat_view: Dictionary = eye.get("cab", {})
	cab.show_cab(seat_view, Vector3(x, y, z), level)
	if (
		reflection != null
		and reflection.who is Enemy
		and actors.kind_of(reflection.who as Enemy) != ""
	):
		reflection = null
	var t7 := Time.get_ticks_usec()
	sprites.show_sprites(pictures, level, Vector3(x, y, z), angle, mirror)
	var t8 := Time.get_ticks_usec()
	slabs.show_slabs(slabbed, level, Vector3(x, y, z), angle, game.clock, r.world_motion, mirror)
	solids.show_solids(solid, level, Vector3(x, y, z), angle, mirror)
	var t9 := Time.get_ticks_usec()
	if mirror:
		sprites.show_reflection(reflection, level, angle)
	var marks: Array = view["marks"]
	var ground: Array = view["ground"]
	sprites.show_marks(marks, ground, Vector3(x, y, z), angle, mirror)
	var t10 := Time.get_ticks_usec()
	_uniforms(game, view, r, Vector3(x, y, z), angle, at_hub)
	if _warm > 0:
		_warm -= 1
		warm_up()
	var t11 := Time.get_ticks_usec()
	var at := [t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11]
	for k in PART_NAMES.size():
		parts_us[k] += at[k + 1] - at[k]


## How a sprite showing `image` is drawn by its picture alone (_picture_kinds):
## kept once known (a picture whose model is still coming is asked again).
func _picture_kind(image: String) -> int:
	var known: Variant = _picture_kinds.get(image)
	if known != null:
		var kind: int = known
		return kind
	if props.models.name_of(image) != "":
		_picture_kinds[image] = PICTURE_MODEL
		return PICTURE_MODEL
	var family := slabs.family_of(image)
	if not props.models.named(image):
		_picture_kinds[image] = family
	return family


func _place_camera(
	x: float, y: float, z: float, angle: float, horizon: float, focal: float, vh: int, wide := 1.0
) -> void:
	# Map forward (cos a, sin a) is Godot (cos a, 0, sin a); a camera looks
	# down its -Z, so its yaw is -a - PI/2.
	camera.transform = Transform3D(Basis(Vector3.UP, -angle - PI * .5), Vector3(x, z, y))
	# `wide` (below 1) widens the view about its middle, which keeps its way.
	var size := NEAR * vh / (focal * wide)
	var far := game_far
	camera.set_frustum(size, Vector2(0.0, (horizon - vh * .5) * NEAR / focal), NEAR, far)
	_sky.position.z = -(far - 1.0)


## The mirror's picture: the room seen from the eye mirrored in the line
## x = mirror_x, looking along PI - angle (the old renderer's mirror pass);
## the mirror's tile shows it flipped.
func _mirror(
	on: bool,
	level: LevelData,
	x: float,
	y: float,
	z: float,
	angle: float,
	horizon: float,
	focal: float,
	size: Vector2i
) -> void:
	_share("mirror_on", on)
	_mirror_live = on
	if not on:
		for shown: SubViewport in _mirror_views:
			shown.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	if _mirror_views.is_empty():
		for i in 2:
			var port := SubViewport.new()
			port.world_3d = viewport.find_world_3d()
			port.transparent_bg = false
			port.msaa_3d = Viewport.MSAA_DISABLED
			add_child(port)
			var eye := Camera3D.new()
			eye.projection = Camera3D.PROJECTION_FRUSTUM
			eye.keep_aspect = Camera3D.KEEP_HEIGHT
			eye.cull_mask = LAYER_WORLD | LAYER_REFLECTION | LAYER_MIRROR
			eye.current = true
			port.add_child(eye)
			_mirror_views.append(port)
			_mirror_cameras.append(eye)
		RenderingServer.frame_post_draw.connect(_turn_mirrors)
		_turn_mirrors()
	_mirror_views[_mirror_k].render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_share("mirror_x", level.mirror_x)
	var turn := PI - angle
	var tall := NEAR * size.y / focal
	for k in 2:
		var port := _mirror_views[k]
		if port.size != size:
			port.size = size
		var eye := _mirror_cameras[k]
		eye.transform = Transform3D(
			Basis(Vector3.UP, -turn - PI * .5), Vector3(2.0 * level.mirror_x - x, z, y)
		)
		eye.set_frustum(tall, Vector2(0.0, (horizon - size.y * .5) * NEAR / focal), NEAR, game_far)


## The mirror's two pictures change places after every frame drawn: the
## shaders read the one drawn last frame (the main view, drawn before the
## mirror's viewport, read it a frame old already; the mirror's own pass
## reads it for the mirror's tile seen in the mirror) while the other is
## drawn. A pass reading the picture it draws into is a feedback loop: WebGL
## refuses each such draw with an error (the browser's 256 within seconds
## in Hickston before pass 14) and leaves holes; desktop drivers let it be.
func _turn_mirrors() -> void:
	if _mirror_views.is_empty() or not _mirror_live:
		return
	_mirror_k = 1 - _mirror_k
	var read := _mirror_views[1 - _mirror_k]
	read.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_mirror_views[_mirror_k].render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_share("mirror_tex", read.get_texture())


## (Re)build the level's meshes when the level, its walls, its light or
## (moving walls only) its doors, panes and gates changed.
func _build(level: LevelData, at_hub: bool) -> void:
	var key: Array = [level, level.light_version, at_hub]
	# Cells opened since (LevelData.open_cell) and nothing else changing the
	# walls: only their chunks again (a full build is 40 to 100 ms).
	var opened := level.walls_version - _walls_seen
	if key == _built_key and opened > 0 and opened == level.reshapes - _reshapes_seen:
		_reshape(level, at_hub)
	elif key != _built_key or opened != 0:
		_built_key = key
		_walls_seen = level.walls_version
		_reshapes_seen = level.reshapes
		_reshaped_seen = level.reshaped.size()
		_level = level
		_warm = WARM_FRAMES
		_builder = LevelMesh.new(level)
		for child in _chunks.get_children():
			child.queue_free()
		_chunk_nodes.clear()
		_retiled_seen = level.retiled.size()
		var parts := _builder.build_static(level.active_base(at_hub))
		for k: Vector2i in parts:
			var built: ArrayMesh = parts[k]
			_chunk_node(k, built)
		_moving_rows = PackedFloat32Array([NAN])
		_cell_pixels = _cell_image(level)
		_cells = ImageTexture.create_from_image(_cell_pixels)
		_share("cells_tex", _cells)
		_share("map_size", Vector2i(level.width, level.height))
		var sky := _assets.sky(level.sky)
		var sky_w: int = sky["w"]
		var sky_h: int = sky["h"]
		var sky_data: PackedByteArray = sky["data"]
		var sky_image := Image.create_from_data(sky_w, sky_h, false, Image.FORMAT_RGB8, sky_data)
		_share("sky_tex", ImageTexture.create_from_image(sky_image))
		_anim_tiles = {}
		for i in level.wall_count:
			_anim_tiles[int(level.walls[i * LevelData.WALL_STRIDE + 4])] = true
		for t in level.floor_tile:
			_anim_tiles[t] = true
		_anim_count = -1
	if level.retiled.size() > _retiled_seen:
		# A window shot out, a fence shot about: only its chunks again.
		var only := {}
		for i in range(_retiled_seen, level.retiled.size()):
			_chunks_at(level.retiled[i], only)
		_retiled_seen = level.retiled.size()
		_rebuild(level, at_hub, only)
	var active := level.active_walls(at_hub)
	var base_size := level.active_base(at_hub).size()
	var rows := active.slice(base_size)
	if rows != _moving_rows:
		_moving_rows = rows
		var mesh := _builder.build_walls(rows)
		_moving.mesh = mesh
		if mesh != null:
			_moving.set_surface_override_material(0, world_material)
			if mesh.get_surface_count() > 1:
				_moving.set_surface_override_material(1, glass_material)


## The chunks a change at map point `at` may touch (it and anything within
## .6 of it), into `only`.
static func _chunks_at(at: Vector2, only: Dictionary) -> void:
	for corner: Vector2 in [Vector2(-.6, -.6), Vector2(.6, -.6), Vector2(-.6, .6), Vector2(.6, .6)]:
		var near := at + corner
		only[Vector2i(floori(near.x / LevelMesh.CHUNK), floori(near.y / LevelMesh.CHUNK))] = true


## Build the chunks `only` again.
func _rebuild(level: LevelData, at_hub: bool, only: Dictionary) -> void:
	var parts := _builder.build_static(level.active_base(at_hub), only)
	for k: Vector2i in only:
		var old: MeshInstance3D = _chunk_nodes.get(k)
		if old != null:
			old.queue_free()
			_chunk_nodes.erase(k)
		if parts.has(k):
			var remade: ArrayMesh = parts[k]
			_chunk_node(k, remade)


## Cells opened (LevelData.open_cell: a plank wall or a fence broken
## through, a shed's wall opened under its roof): their chunks built again
## and their cells' pixels of the cell texture made again.
func _reshape(level: LevelData, at_hub: bool) -> void:
	var only := {}
	for i in range(_reshaped_seen, level.reshaped.size()):
		var at := level.reshaped[i]
		_chunks_at(at, only)
		var cx := clampi(floori(at.x), 0, level.width - 1)
		var cy := clampi(floori(at.y), 0, level.height - 1)
		_cell_pixels.set_pixel(cx, cy, _cell_colour(level, cy * level.width + cx))
		_anim_tiles[level.floor_tile[cy * level.width + cx]] = true
	_walls_seen = level.walls_version
	_reshapes_seen = level.reshapes
	_reshaped_seen = level.reshaped.size()
	_rebuild(level, at_hub, only)
	_cells.update(_cell_pixels)
	for i in level.wall_count:
		_anim_tiles[int(level.walls[i * LevelData.WALL_STRIDE + 4])] = true
	_anim_count = -1


func _chunk_node(k: Vector2i, chunk: ArrayMesh) -> void:
	var node := MeshInstance3D.new()
	node.mesh = chunk
	node.material_override = null
	node.set_surface_override_material(0, world_material)
	if chunk.get_surface_count() > 1:
		node.set_surface_override_material(1, glass_material)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_chunks.add_child(node)
	_chunk_nodes[k] = node


## Each cell: g 255 under the open sky (the weather's test).
static func _cell_image(level: LevelData) -> Image:
	var lw := level.width
	var lh := level.height
	var bytes := PackedByteArray()
	bytes.resize(lw * lh * 4)
	for i in lw * lh:
		var o := i * 4
		bytes[o] = clampi(level.area[i], 0, 255)
		bytes[o + 1] = 255 if level.roof[i] <= level.ground[i] + .01 else 0
		if level.geo != null and level.geo.covered(i % lw + .5, i / lw + .5, level.ground[i]):
			bytes[o + 1] = 0
		bytes[o + 3] = 255
	return Image.create_from_data(lw, lh, false, Image.FORMAT_RGBA8, bytes)


## Cell i's pixel of _cell_image.
static func _cell_colour(level: LevelData, i: int) -> Color:
	var lw := level.width
	var sky := level.roof[i] <= level.ground[i] + .01
	if level.geo != null and level.geo.covered(i % lw + .5, i / lw + .5, level.ground[i]):
		sky = false
	return Color8(clampi(level.area[i], 0, 255), 255 if sky else 0, 0, 255)


func _uniforms(
	game: Game, view: Dictionary, r: View, cam: Vector3, angle: float, at_hub: bool
) -> void:
	_share("eye", cam)
	var flash: float = view["flash"]
	_share("flash", flash)
	var phase := r.time - floorf(r.time / 6.1) * 6.1
	_share("liquor_flicker", phase > .87 and phase < 1.02)
	if _flows_of != _level:
		_flows_of = _level
		_flows = []
		for h: float in _level.moving_floors:
			for f: Array in _level.moving_floors[h]:
				var tile: int = f[0]
				var speed: float = f[1]
				if (
					_flows.size() < 2
					and not _flows.any(func(g: Array) -> bool: return g[0] == tile)
				):
					_flows.append([tile, speed])
	var flow_tile := PackedInt32Array([-1, -1])
	var flow_shift := PackedInt32Array([0, 0])
	for found in _flows.size():
		var flow: Array = _flows[found]
		var tile: int = flow[0]
		var speed: float = flow[1]
		flow_tile[found] = tile
		flow_shift[found] = int(r.time * speed) & 127
	_row(
		ROW_FLOW,
		PackedVector4Array([Vector4(flow_tile[0], flow_tile[1], flow_shift[0], flow_shift[1])])
	)
	_share("view_angle", fmod(angle, TAU * 512.0))
	var horizon: float = view["horizon"]
	# A widened view (a driver's) has its horizon row and focal moved with it.
	var eye: Dictionary = view["eye"]
	var wide: float = eye.get("wide", 1.0)
	_share("horizon", r.vh * .5 + (horizon - r.vh * .5) * wide)
	_share("focal", r.focal * wide)
	_share("view_size", Vector2(r.vw, r.vh))
	_share("res_up", r.res_up)
	# The Crossroads' tower shadow and runoff (render_state.gd _prepare_hub).
	var motion := r.world_motion
	var hub := at_hub and _level.tile_id("hub_patch") >= 0
	_share("hub_fx", hub)
	if hub:
		var still := motion == 2
		var gust := 0.0 if still else sin(r.time * .83) * (.13 if motion == 0 else .045)
		_share("hub_runoff", _level.tile_id("hub_runoff"))
		_share("hub_patch", _level.tile_id("hub_patch"))
		_share("hub_wall", _level.tile_id("hub_service_wall"))
		_share("shadow_still", still)
		_share("shadow_gust", gust)
		_share("shadow_lx", 1.15 + gust)
		_share("shadow_ly", .73 + gust * .32)
		_share(
			"water_drift",
			fposmod((0.0 if still else r.time) * (1.9 if motion == 0 else .72), TAU * 1000.0)
		)
	_effects(game)
	_storm(game, cam)
	_twister_at(game)
	_upload_data()


## A county event's twister: its funnel stood where it is, its strength (a
## rope forming or lifting), leaning back from the way it goes.
func _twister_at(game: Game) -> void:
	var ev: CountyEvents = game.features.get("events")
	var on := ev != null and ev.kind == "twister" and ev.tw_k > 0.0
	for piece: MeshInstance3D in _twister:
		piece.visible = on
	if not on:
		return
	var at := ev.tw_at
	var ground := game.world.elevation(
		clampf(at.x, 0.0, _level.width - .01), clampf(at.y, 0.0, _level.height - .01)
	)
	var way := (ev.tw_to - ev.tw_from).normalized()
	var tall := 30.0
	var lean := -way * .5
	for k in 3:
		var m := _twister_materials[k]
		m.set_shader_parameter("strength", ev.tw_k)
		m.set_shader_parameter("tall", tall)
		m.set_shader_parameter("lean", lean)
		m.set_shader_parameter("base_z", ground)
	_twister[0].position = Vector3(at.x, ground - .3 + tall * .0, at.y)
	_twister[1].position = Vector3(at.x, ground - .2, at.y)
	var top := at + lean * 6.0
	_twister[2].position = Vector3(top.x, ground + tall - .6, top.y)
	_twister[2].scale = Vector3(15.0, 1.0, 15.0) * (.6 + .4 * ev.tw_k)


## County Run's storm front: its wall stood round the safe ground, as tall as
## the weather, sized to the ring (county_storm.gd).
func _storm(game: Game, cam: Vector3) -> void:
	var f: CountyRun = game.features.get("county")
	var on := f != null and f.on and f.storm_on and (f.storm_stage > 0 or f.storm_warned)
	# The rich wall (the curtain behind, the flickers, the debris) with LIGHTS
	# AND GLOW at a view detail above LOW (QUALITY LOW has neither).
	var rich := Effects.enabled and game.view.detail != 1
	_storm_walls[0].visible = on
	_storm_walls[1].visible = on and rich
	if not on:
		_share("storm_ring", Vector4.ZERO)
		return
	var base := 0.0
	var level := game.level
	var middle := Vector2(
		clampf(f.storm_at.x, 0.0, level.width - .01), clampf(f.storm_at.y, 0.0, level.height - .01)
	)
	if level.width > 0 and level.height > 0:
		base = level.ground[level.cell(middle.x, middle.y)]
	var low := base - 1.5
	var tall := 30.0
	var k := CountyStorm.strength(f)
	for i in 2:
		var r := f.storm_r + i * OUTER_STORM
		_storm_walls[i].position = Vector3(f.storm_at.x, low + tall * .5, f.storm_at.y)
		_storm_walls[i].scale = Vector3(r, tall, r)
	# From out in the storm the front curtain is the far one: draw it first.
	var out := Vector2(cam.x, cam.y).distance_to(f.storm_at) > f.storm_r
	_storm_materials[0].render_priority = 4 if out else 5
	_storm_materials[1].render_priority = 5 if out else 4
	_share("storm_r", f.storm_r)
	_share("storm_k", k)
	_share("storm_base", base)
	_share("storm_rich", rich)
	_share("storm_ring", Vector4(f.storm_at.x, f.storm_at.y, f.storm_r, maxf(k, .05)))


## LIGHTS AND GLOW: this frame's lights, the level's mood, weather and moving
## tiles (what SceneLayers handed the old shader).
func _effects(game: Game) -> void:
	var on := Effects.enabled
	_share("effects_on", on)
	# The wind sways the props whatever LIGHTS AND GLOW (SCENERY MOTION stills it).
	var weather: WeatherFeature = game.features.get("weather")
	if weather != null:
		_share("wind_now", Vector3(weather.wind.x, weather.wind.y, weather.gusting))
	if not on:
		for sheet: MeshInstance3D in _rain:
			sheet.visible = false
		_share("light_count", 0)
		_shadows.pair_count = 0
		_shadows.blob_count = 0
		_share_shadows()
		_share("lightning", 0.0)
		_share("rain", 0.0)
		_share("wet", 0.0)
		_share("blackout", 0.0)
		_share("moon_rim", Vector4.ZERO)
		return
	var county: CountyEvents = game.features.get("events")
	var dark := county.darkness() if county != null else 0.0
	_share("blackout", dark)
	_share("moon_rim", _moon_rim(game.level.id, county, dark))
	var found: Array = game.effect_lights()
	var at := PackedVector4Array()
	var tint := PackedVector4Array()
	var flags := PackedInt32Array()
	at.resize(Effects.MAX_LIGHTS)
	tint.resize(Effects.MAX_LIGHTS)
	flags.resize(Effects.MAX_LIGHTS)
	for i in mini(found.size(), Effects.MAX_LIGHTS):
		var l: Array = found[i]
		var c: Color = l[4]
		var lx: float = l[0]
		var ly: float = l[1]
		var lz: float = l[2]
		var reach: float = l[3]
		var power: float = l[5]
		at[i] = Vector4(lx, ly, lz, reach)
		tint[i] = Vector4(c.r, c.g, c.b, power)
		var light_flags: int = l[6] if l.size() > 6 else 0
		flags[i] = light_flags
	_share("light_count", mini(found.size(), Effects.MAX_LIGHTS))
	_row(ROW_LIGHT_POS, at)
	_row(ROW_LIGHT_COL, tint)
	# The flags whole: 16 bits a channel, as a float holds them exactly.
	var halves := PackedVector4Array()
	halves.resize(Effects.MAX_LIGHTS)
	for i in flags.size():
		halves[i] = Vector4(flags[i] & 0xFFFF, (flags[i] >> 16) & 0xFFFF, 0.0, 0.0)
	_row(ROW_LIGHT_FLAGS, halves)
	_shadows.pair(found)
	_share_shadows()
	var id := game.level.id
	# A map's moods by area (features/area_moods.gd): {} on a level with none.
	var moods: AreaMoodsFeature = game.features.get("moods")
	var mood: Dictionary = (
		moods.now(game.player.x, game.player.y, game.clock) if moods != null else {}
	)
	var fog: Color = mood.get("fog", Effects.mood(id, "fog", Color(0, 0, 0)))
	_share("fog_color", Vector3(fog.r, fog.g, fog.b))
	var fog_start: float = mood.get("fog_start", Effects.mood(id, "fog_start", 1000.0))
	var fog_full: float = mood.get("fog_full", Effects.mood(id, "fog_full", 2000.0))
	var fog_most: float = mood.get("fog_most", Effects.mood(id, "fog_most", 0.0))
	_share("fog_range", Vector3(fog_start, fog_full, fog_most))
	var tone: Color = mood.get("grade", Effects.mood(id, "grade", Color(1, 1, 1)))
	_share("grade", Vector3(tone.r, tone.g, tone.b))
	var clouds: float = Effects.mood(id, "clouds", 0.0)
	_share("sky_drift", fposmod(game.clock * clouds, 1.0))
	_share("lightning", game.lightning)
	var motion: float = [1.0, .4, 0.0][clampi(game.view.world_motion, 0, 2)]
	_share("motion", motion)
	var raining: float = weather.rain if weather != null else 0.0
	var drawn: float = mood.get("rain", 1.0)
	raining *= drawn
	_share("rain", raining)
	for sheet: MeshInstance3D in _rain:
		sheet.visible = raining > 0.0 and motion > 0.0
	_share("wet", weather.wet if weather != null else 0.0)
	_share("pool", weather.pool if weather != null else 0.0)
	if weather != null:
		_share("flash_dir", weather.flash_dir)
	var banks: float = mood.get("fog_banks", Effects.mood(id, "fog_banks", 0.0))
	_share("fog_banks", banks)
	var water: WaterFeature = game.features.get("water")
	var shown: Array = water.shown(game.player.x, game.player.y) if water != null else []
	var rings := PackedVector4Array()
	rings.resize(16)
	for i in mini(shown.size(), 16):
		var w: Array = shown[i]
		var wx: float = w[0]
		var wy: float = w[1]
		var wr: float = w[2]
		var wk: float = w[3]
		rings[i] = Vector4(wx, wy, wr, wk)
	_share("ring_count", mini(shown.size(), 16))
	_row(ROW_RINGS, rings)
	if _anim_count < 0:
		# The moving tiles the level shows (again when its tiles change).
		_anims = PackedVector4Array()
		_anims.resize(Effects.MAX_ANIMS)
		_anim_count = 0
		for tile_name: String in Effects.ANIMS:
			if _anim_count >= Effects.MAX_ANIMS or not _assets.tile_index.has(tile_name):
				continue
			var tile: int = _assets.tile_index[tile_name]
			if not _anim_tiles.has(tile):
				continue
			var a: Dictionary = Effects.ANIMS[tile_name]
			var rate: float = a.get("rate", 8.0)
			var depth: float = a.get("depth", .05)
			_anims[_anim_count] = Vector4(
				tile, 0.0 if str(a.get("mode", "neon")) == "neon" else 1.0, rate, depth
			)
			_anim_count += 1
	_share("anim_count", _anim_count)
	_row(ROW_ANIMS, _anims)
	_share("anim_time", fposmod(game.clock, 3600.0))
