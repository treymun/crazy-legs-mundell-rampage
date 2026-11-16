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
## SHADOWS' numbers as last handed to the floors, walls and marks.
var _received := {}
var _materials: Array[ShaderMaterial] = []
## The layers' materials drawn lately (_track_live), and the frame each was
## last drawn on.
const IDLE_FRAMES := 120
var _live: Array[ShaderMaterial] = []
var _used := {}
var _frames := 0
var _rain: Array[MeshInstance3D] = []
## County Run's storm front: a wall round the safe ground, its front curtain
## and the one behind it (storm_wall.gdshader).
var _storm_walls: Array[MeshInstance3D] = []
var _storm_materials: Array[ShaderMaterial] = []
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
var _mirror_view: SubViewport
var _mirror_camera: Camera3D


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
	camera.cull_mask = LAYER_WORLD | LAYER_SKY
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
	_root.add_child(wrecks)
	actors = ActorLayer3D.new(ActorModels.new(assets))
	_root.add_child(actors)
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
	_materials = [world_material, glass_material, sky_material]
	_materials.append_array(_storm_materials)
	_materials.append_array(rain_materials)
	_materials.append_array(sprites.materials())
	_materials.append(slabs.material)
	_materials.append(solids.material)
	_share("tiles", tiles.tiles)
	_share("tile_info_tex", tiles.info)


func texture() -> ViewportTexture:
	return viewport.get_texture()


## Set a shader number on every material of the view in use, when it
## changed: the view's own and the props', wrecks' and actors' drawn lately
## (_track_live; one not drawn for a while is handed every number when it is
## drawn again).
func _share(name: String, value: Variant) -> void:
	var old: Variant = _params.get(name)
	if old != null and typeof(old) == typeof(value) and old == value:
		return
	_params[name] = value
	for m: ShaderMaterial in _materials:
		m.set_shader_parameter(name, value)
	for m: ShaderMaterial in _live:
		m.set_shader_parameter(name, value)


## The props', wrecks' and actors' materials drawn this frame join `_live`
## (handed every shader number first when they were not in it); those not
## drawn for IDLE_FRAMES leave it. A long session meets hundreds of models,
## and handing each frame's numbers to every one of them cost more than the
## rest of the frame's view work.
func _track_live(materials: Array[ShaderMaterial]) -> void:
	_frames += 1
	for m in materials:
		var last: int = _used.get(m, -IDLE_FRAMES - 1)
		if _frames - last > IDLE_FRAMES:
			for key: String in _params:
				m.set_shader_parameter(key, _params[key])
			_live.append(m)
		_used[m] = _frames
	var k := _live.size() - 1
	while k >= 0:
		var gone: int = _used[_live[k]]
		if _frames - gone > IDLE_FRAMES:
			_live.remove_at(k)
		k -= 1


## SHADOWS' numbers (view_shadows.gd), only to what takes shadows: the
## level's floors and walls and the marks on them, when they changed.
func _share_shadows() -> void:
	var counts := Vector2i(_shadows.pair_count, _shadows.blob_count)
	var values := {
		"shadow_count": counts.x,
		"blob_count": counts.y,
	}
	# Copies: the layer fills its own arrays again each frame.
	if counts.x > 0:
		values["shadow_a"] = _shadows.pair_a.duplicate()
		values["shadow_b"] = _shadows.pair_b.duplicate()
	if counts.y > 0:
		values["blobs"] = _shadows.blobs.duplicate()
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
	_build(level, at_hub)
	if level != _rigged:
		_rigged = level
		actors.prepare(game.enemies)
	game_far = r.draw_far
	var horizon: float = view["horizon"]
	_place_camera(x, y, z, angle, horizon, r.focal, vh)
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
		var s: View.Sprite = item if item is View.Sprite else null
		if s != null and WreckLayer3D.takes(s):
			wrecked.append(s)
		elif s != null and s.gear != "" and s.who is Enemy:
			if not cels:
				gear.append(s)
		elif s != null and SolidLayer3D.takes(s):
			solid.append(s)
		elif s != null and not cels and s.who is Enemy and actors.takes(s, s.who as Enemy):
			acting.append(s)
		elif s != null and props.models.name_of(s.image) != "":
			modelled.append(s)
		elif s != null and slabs.takes(s):
			slabbed.append(s)
		else:
			pictures.append(item)
	var t1 := Time.get_ticks_usec()
	_shadows.collect(game, acting, modelled, wrecked, Vector3(x, y, z), props.models)
	var t2 := Time.get_ticks_usec()
	var fresh := props.show_props(modelled, level)
	var t3 := Time.get_ticks_usec()
	fresh.append_array(wrecks.show_wrecks(wrecked, level))
	var t4 := Time.get_ticks_usec()
	_thing_marks.update(game, props, wrecks)
	var t5 := Time.get_ticks_usec()
	var gear_lost: Dictionary = view.get("gear_lost", {})
	ActorView.draws += 1
	ActorView.lod_eye = Vector3(x, y, z) if r.detail == 1 else Vector3.INF
	fresh.append_array(actors.show_actors(acting, level, game.clock, game.gore_fx.lost, gear_lost))
	fresh.append_array(actors.show_gear(gear, level))
	var t6 := Time.get_ticks_usec()
	# The player in the mirror: their model when they have one, else their picture.
	var reflection: View.Sprite = null
	if mirror:
		reflection = view.get("reflection")
	fresh.append_array(actors.show_reflection(reflection, level, game.clock, LAYER_REFLECTION))
	if (
		reflection != null
		and reflection.who is Enemy
		and actors.kind_of(reflection.who as Enemy) != ""
	):
		reflection = null
	# What the layers draw with this frame (the ones made now among them).
	fresh.append_array(props.live_materials())
	fresh.append_array(wrecks.live_materials())
	fresh.append_array(actors.live_materials())
	_track_live(fresh)
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
	sprites.show_marks(marks, ground, Vector3(x, y, z), angle)
	var t10 := Time.get_ticks_usec()
	_uniforms(game, view, r, Vector3(x, y, z), angle, at_hub)
	var t11 := Time.get_ticks_usec()
	var at := [t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11]
	for k in PART_NAMES.size():
		parts_us[k] += at[k + 1] - at[k]


func _place_camera(
	x: float, y: float, z: float, angle: float, horizon: float, focal: float, vh: int
) -> void:
	# Map forward (cos a, sin a) is Godot (cos a, 0, sin a); a camera looks
	# down its -Z, so its yaw is -a - PI/2.
	camera.transform = Transform3D(Basis(Vector3.UP, -angle - PI * .5), Vector3(x, z, y))
	var size := NEAR * vh / focal
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
	if not on:
		if _mirror_view != null:
			_mirror_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	if _mirror_view == null:
		_mirror_view = SubViewport.new()
		_mirror_view.world_3d = viewport.find_world_3d()
		_mirror_view.transparent_bg = false
		_mirror_view.msaa_3d = Viewport.MSAA_DISABLED
		add_child(_mirror_view)
		_mirror_camera = Camera3D.new()
		_mirror_camera.projection = Camera3D.PROJECTION_FRUSTUM
		_mirror_camera.keep_aspect = Camera3D.KEEP_HEIGHT
		_mirror_camera.cull_mask = LAYER_WORLD | LAYER_REFLECTION | LAYER_MIRROR
		_mirror_camera.current = true
		_mirror_view.add_child(_mirror_camera)
		_share("mirror_tex", _mirror_view.get_texture())
	_mirror_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if _mirror_view.size != size:
		_mirror_view.size = size
	_share("mirror_x", level.mirror_x)
	var turn := PI - angle
	_mirror_camera.transform = Transform3D(
		Basis(Vector3.UP, -turn - PI * .5), Vector3(2.0 * level.mirror_x - x, z, y)
	)
	var tall := NEAR * size.y / focal
	_mirror_camera.set_frustum(
		tall, Vector2(0.0, (horizon - size.y * .5) * NEAR / focal), NEAR, game_far
	)


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
	var flow_tile := PackedInt32Array([-1, -1])
	var flow_shift := PackedInt32Array([0, 0])
	var found := 0
	for h: float in _level.moving_floors:
		for f: Array in _level.moving_floors[h]:
			var tile: int = f[0]
			var speed: float = f[1]
			if found < 2 and not flow_tile.has(tile):
				flow_tile[found] = tile
				flow_shift[found] = int(r.time * speed) & 127
				found += 1
	_share("flow_tile", flow_tile)
	_share("flow_shift", flow_shift)
	_share("view_angle", fmod(angle, TAU * 512.0))
	var horizon: float = view["horizon"]
	_share("horizon", horizon)
	_share("focal", r.focal)
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
		return
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
	_share("light_pos", at)
	_share("light_col", tint)
	_share("light_flags", flags)
	_shadows.pair(found)
	_share_shadows()
	var id := game.level.id
	var fog: Color = Effects.mood(id, "fog", Color(0, 0, 0))
	_share("fog_color", Vector3(fog.r, fog.g, fog.b))
	var fog_start: float = Effects.mood(id, "fog_start", 1000.0)
	var fog_full: float = Effects.mood(id, "fog_full", 2000.0)
	var fog_most: float = Effects.mood(id, "fog_most", 0.0)
	_share("fog_range", Vector3(fog_start, fog_full, fog_most))
	var tone: Color = Effects.mood(id, "grade", Color(1, 1, 1))
	_share("grade", Vector3(tone.r, tone.g, tone.b))
	var clouds: float = Effects.mood(id, "clouds", 0.0)
	_share("sky_drift", fposmod(game.clock * clouds, 1.0))
	_share("lightning", game.lightning)
	var motion: float = [1.0, .4, 0.0][clampi(game.view.world_motion, 0, 2)]
	_share("motion", motion)
	var raining: float = weather.rain if weather != null else 0.0
	_share("rain", raining)
	for sheet: MeshInstance3D in _rain:
		sheet.visible = raining > 0.0 and motion > 0.0
	_share("wet", weather.wet if weather != null else 0.0)
	_share("pool", weather.pool if weather != null else 0.0)
	if weather != null:
		_share("flash_dir", weather.flash_dir)
	var banks: float = Effects.mood(id, "fog_banks", 0.0)
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
	_share("rings", rings)
	var anims := PackedVector4Array()
	anims.resize(Effects.MAX_ANIMS)
	var count := 0
	for tile_name: String in Effects.ANIMS:
		if count >= Effects.MAX_ANIMS or not _assets.tile_index.has(tile_name):
			continue
		var tile: int = _assets.tile_index[tile_name]
		if not _anim_tiles.has(tile):
			continue
		var a: Dictionary = Effects.ANIMS[tile_name]
		var rate: float = a.get("rate", 8.0)
		var depth: float = a.get("depth", .05)
		anims[count] = Vector4(
			tile, 0.0 if str(a.get("mode", "neon")) == "neon" else 1.0, rate, depth
		)
		count += 1
	_share("anim_count", count)
	_share("anims", anims)
	_share("anim_time", fposmod(game.clock, 3600.0))
