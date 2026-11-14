## The game's 3D view: a SubViewport the size of the old view (320x156, HD
## 640x312) holding the level's meshes, the frame's sprites and the sky, seen
## by a camera that reproduces the old renderer's projection (an off-axis
## frustum: looking up and down shifts the horizon, as in the Build engine,
## so aim, crosshair and every screen overlay stay true). The display shader
## (palette.gdshader, view3d_on) lays the weapon/HUD layer and the look pass
## over its picture.
##
## Read-only toward play: it reads the game's level, camera and sprite list
## each frame (Game.view_frame, set by game_view.gd _draw) and changes nothing.
class_name WorldView3D
extends Node

const NEAR := .02
const FAR := 160.0

var viewport: SubViewport
var camera: Camera3D
var world_material: ShaderMaterial
var glass_material: ShaderMaterial
var sky_material: ShaderMaterial
var sprites: SpriteLayer3D
var tiles: ViewTiles
var _root: Node3D
var _chunks: Node3D
var _moving: MeshInstance3D
var _sky: MeshInstance3D
var _assets: Assets
var _level: LevelData
var _builder: LevelMesh
var _built_key: Array = []
var _moving_rows := PackedFloat32Array()
var _cells: ImageTexture
var _anim_tiles := {}
var _params := {}
var _materials: Array[ShaderMaterial] = []


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
	_sky = MeshInstance3D.new()
	var plane := QuadMesh.new()
	plane.size = Vector2(4000.0, 4000.0)
	_sky.mesh = plane
	_sky.material_override = sky_material
	_sky.position = Vector3(0.0, 0.0, -(FAR - 1.0))
	_sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	camera.add_child(_sky)
	_materials = [world_material, glass_material, sky_material]
	_materials.append_array(sprites.materials())
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
	var r: Renderer = game.renderer
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
	_place_camera(x, y, z, angle, view["horizon"], r.focal, vh)
	sprites.show_sprites(view["sprites"], level, Vector3(x, y, z), angle)
	_uniforms(game, view, r, Vector3(x, y, z), angle)


func _place_camera(
	x: float, y: float, z: float, angle: float, horizon: float, focal: float, vh: int
) -> void:
	# Map forward (cos a, sin a) is Godot (cos a, 0, sin a); a camera looks
	# down its -Z, so its yaw is -a - PI/2.
	camera.transform = Transform3D(Basis(Vector3.UP, -angle - PI * .5), Vector3(x, z, y))
	var size := NEAR * vh / focal
	camera.set_frustum(size, Vector2(0.0, (horizon - vh * .5) * NEAR / focal), NEAR, FAR)


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
		var parts := _builder.build_static(level.active_base(at_hub))
		for k: Vector2i in parts:
			var node := MeshInstance3D.new()
			node.mesh = parts[k]
			node.material_override = null
			node.set_surface_override_material(0, world_material)
			if (parts[k] as ArrayMesh).get_surface_count() > 1:
				node.set_surface_override_material(1, glass_material)
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_chunks.add_child(node)
		_moving_rows = PackedFloat32Array([NAN])
		_cells = ImageTexture.create_from_image(_cell_image(level))
		_share("cells_tex", _cells)
		_share("map_size", Vector2i(level.width, level.height))
		var sky := _assets.sky(level.sky)
		var sky_image := Image.create_from_data(
			int(sky["w"]), int(sky["h"]), false, Image.FORMAT_RGB8, sky["data"]
		)
		sky_material.set_shader_parameter("sky_tex", ImageTexture.create_from_image(sky_image))
		_anim_tiles = {}
		for i in level.wall_count:
			_anim_tiles[int(level.walls[i * LevelData.WALL_STRIDE + 4])] = true
		for t in level.floor_tile:
			_anim_tiles[t] = true
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


func _uniforms(game: Game, view: Dictionary, r: Renderer, cam: Vector3, angle: float) -> void:
	_share("eye", cam)
	_share("flash", float(view["flash"]))
	var phase := r.time - floorf(r.time / 6.1) * 6.1
	_share("liquor_flicker", phase > .87 and phase < 1.02)
	var flow_tile := PackedInt32Array([-1, -1])
	var flow_shift := PackedInt32Array([0, 0])
	var found := 0
	for h: float in _level.moving_floors:
		for f: Array in _level.moving_floors[h]:
			var tile := int(f[0])
			if found < 2 and not flow_tile.has(tile):
				flow_tile[found] = tile
				flow_shift[found] = int(r.time * float(f[1])) & 127
				found += 1
	_share("flow_tile", flow_tile)
	_share("flow_shift", flow_shift)
	sky_material.set_shader_parameter("view_angle", fmod(angle, TAU * 512.0))
	sky_material.set_shader_parameter("horizon", float(view["horizon"]))
	sky_material.set_shader_parameter("focal", r.focal)
	sky_material.set_shader_parameter("view_size", Vector2(r.vw, r.vh))
	sky_material.set_shader_parameter("res_up", r.res_up)
	_effects(game)


## LIGHTS AND GLOW: this frame's lights, the level's mood, weather and moving
## tiles (what SceneLayers handed the old shader).
func _effects(game: Game) -> void:
	var on := Effects.enabled
	_share("effects_on", on)
	if not on:
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
		at[i] = Vector4(l[0], l[1], l[2], l[3])
		tint[i] = Vector4(c.r, c.g, c.b, l[5])
		flags[i] = int(l[6]) if l.size() > 6 else 0
	_share("light_count", mini(found.size(), Effects.MAX_LIGHTS))
	_share("light_pos", at)
	_share("light_col", tint)
	_share("light_flags", flags)
	var id := game.level.id
	var fog: Color = Effects.mood(id, "fog", Color(0, 0, 0))
	_share("fog_color", Vector3(fog.r, fog.g, fog.b))
	_share(
		"fog_range",
		Vector3(
			float(Effects.mood(id, "fog_start", 1000.0)),
			float(Effects.mood(id, "fog_full", 2000.0)),
			float(Effects.mood(id, "fog_most", 0.0))
		)
	)
	var tone: Color = Effects.mood(id, "grade", Color(1, 1, 1))
	_share("grade", Vector3(tone.r, tone.g, tone.b))
	sky_material.set_shader_parameter(
		"sky_drift", fposmod(game.clock * float(Effects.mood(id, "clouds", 0.0)), 1.0)
	)
	_share("lightning", game.lightning)
	var motion: float = [1.0, .4, 0.0][clampi(game.renderer.world_motion, 0, 2)]
	_share("motion", motion)
	var weather: Variant = game.features.get("weather")
	_share("rain", float(weather.rain) if weather != null else 0.0)
	_share("wet", float(weather.wet) if weather != null else 0.0)
	if weather != null:
		_share("flash_dir", weather.flash_dir)
	_share("fog_banks", float(Effects.mood(id, "fog_banks", 0.0)))
	var anims := PackedVector4Array()
	anims.resize(Effects.MAX_ANIMS)
	var count := 0
	for tile_name: String in Effects.ANIMS:
		if count >= Effects.MAX_ANIMS or not _assets.tile_index.has(tile_name):
			continue
		var tile := int(_assets.tile_index[tile_name])
		if not _anim_tiles.has(tile):
			continue
		var a: Dictionary = Effects.ANIMS[tile_name]
		anims[count] = Vector4(
			tile,
			0.0 if String(a.get("mode", "neon")) == "neon" else 1.0,
			float(a.get("rate", 8.0)),
			float(a.get("depth", .05))
		)
		count += 1
	_share("anim_count", count)
	_share("anims", anims)
	_share("anim_time", fposmod(game.clock, 3600.0))
