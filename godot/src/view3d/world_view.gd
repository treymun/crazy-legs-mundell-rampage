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
const WeatherFeature := preload("res://src/features/weather.gd")
const WaterFeature := preload("res://src/features/water.gd")
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
## The level's chunks by key, and how many of its retiled wall pieces
## (LevelData.retiled) they show.
var _chunk_nodes := {}
var _retiled_seen := 0
var _moving_rows := PackedFloat32Array()
var _cells: ImageTexture
var _anim_tiles := {}
var _params := {}
var _materials: Array[ShaderMaterial] = []
var _rain: Array[MeshInstance3D] = []
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
	_materials = [world_material, glass_material, sky_material]
	_materials.append_array(rain_materials)
	_materials.append_array(sprites.materials())
	_materials.append(slabs.material)
	_materials.append(solids.material)
	_share("tiles", tiles.tiles)
	_share("tile_info_tex", tiles.info)


func texture() -> ViewportTexture:
	return viewport.get_texture()


## Set a shader number on every material of the view, when it changed.
func _share(name: String, value: Variant) -> void:
	var old: Variant = _params.get(name)
	if old != null and typeof(old) == typeof(value) and old == value:
		return
	_params[name] = value
	for m: ShaderMaterial in _materials:
		m.set_shader_parameter(name, value)


## Draw this frame of `game` (call after game.draw()).
func frame(game: Game) -> void:
	var view: Dictionary = game.view_frame
	if view.is_empty():
		return
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
	var listed: Array = view["sprites"]
	for item: Variant in listed:
		var s: View.Sprite = item if item is View.Sprite else null
		if s != null and WreckLayer3D.takes(s):
			wrecked.append(s)
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
	var fresh := props.show_props(modelled, level)
	fresh.append_array(wrecks.show_wrecks(wrecked, level))
	fresh.append_array(actors.show_actors(acting, level, game.clock, game.gore_fx.lost))
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
	for m: ShaderMaterial in fresh:
		_materials.append(m)
		for key: String in _params:
			m.set_shader_parameter(key, _params[key])
	sprites.show_sprites(pictures, level, Vector3(x, y, z), angle, mirror)
	slabs.show_slabs(slabbed, level, Vector3(x, y, z), angle, game.clock, r.world_motion, mirror)
	solids.show_solids(solid, level, Vector3(x, y, z), angle, mirror)
	if mirror:
		sprites.show_reflection(reflection, level, angle)
	var marks: Array = view["marks"]
	var ground: Array = view["ground"]
	sprites.show_marks(marks, ground, Vector3(x, y, z), angle)
	_uniforms(game, view, r, Vector3(x, y, z), angle, at_hub)


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
	var key: Array = [level, level.walls_version, level.light_version, at_hub]
	if key != _built_key:
		_built_key = key
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
		_cells = ImageTexture.create_from_image(_cell_image(level))
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
			var at := level.retiled[i]
			for corner: Vector2 in [
				Vector2(-.6, -.6), Vector2(.6, -.6), Vector2(-.6, .6), Vector2(.6, .6)
			]:
				var near := at + corner
				var chunk := Vector2i(
					floori(near.x / LevelMesh.CHUNK), floori(near.y / LevelMesh.CHUNK)
				)
				only[chunk] = true
		_retiled_seen = level.retiled.size()
		var parts := _builder.build_static(level.active_base(at_hub), only)
		for k: Vector2i in only:
			var old: MeshInstance3D = _chunk_nodes.get(k)
			if old != null:
				old.queue_free()
				_chunk_nodes.erase(k)
			if parts.has(k):
				var remade: ArrayMesh = parts[k]
				_chunk_node(k, remade)
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


## LIGHTS AND GLOW: this frame's lights, the level's mood, weather and moving
## tiles (what SceneLayers handed the old shader).
func _effects(game: Game) -> void:
	var on := Effects.enabled
	_share("effects_on", on)
	if not on:
		for sheet: MeshInstance3D in _rain:
			sheet.visible = false
		_share("light_count", 0)
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
	var weather: WeatherFeature = game.features.get("weather")
	var raining: float = weather.rain if weather != null else 0.0
	_share("rain", raining)
	for sheet: MeshInstance3D in _rain:
		sheet.visible = raining > 0.0 and motion > 0.0
	_share("wet", weather.wet if weather != null else 0.0)
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
