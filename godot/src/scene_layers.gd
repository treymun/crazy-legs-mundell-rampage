## Hands the display shader (palette.gdshader) what it needs to compose the
## game view on the graphics card: once per level the tiles, sky and map
## surfaces, and every frame the renderer's layers and camera.
##
## The software renderer in `layered` mode draws only what is cheap for it to
## draw (walls, wall marks, sprites, ground marks). The sky and every floor and
## ceiling, which were two thirds of a frame, are worked out per pixel by the
## shader from the textures set here.
class_name SceneLayers
extends RefCounted

const ATLAS_COLUMNS := 16
const TAU_ := 6.283185307179586

var material: ShaderMaterial
var _textures := {}
## The texture each of the shader's samplers has now.
var _bound := {}
## The numbers last handed to the shader (_set_param).
var _params := {}
var _art: Texture2DArray
var _art_blank: Image
var _atlas: Image
var _sky_row := 0
var _cells_row := 0
var _plane_table := PackedFloat32Array()
var _plane_width := 0
var _renderer: Renderer = null
var _light_version := -1
var _on := false
var _assets: Assets
var _glow_version := -1
## The atlas before any glow is baked in (every alpha whole).
var _atlas_plain: Image
## The tiles this level draws (walls, doors, floors, ceilings): a moving tile
## ([anim.*]) takes one of the shader's Effects.MAX_ANIMS slots only in a level
## that has it, so every chapter's signs fit, and the shader's per-pixel walk
## of the list stays short.
var _level_tiles := {}


func _init(p_material: ShaderMaterial, assets: Assets) -> void:
	material = p_material
	var count := assets.tiles.size() / Renderer.TILE_BYTES
	var rows := maxi(1, int(ceil(count / float(ATLAS_COLUMNS))))
	# The tiles, and under them room for the level's sky (_load_level).
	_sky_row = rows * 128
	var atlas := Image.create_empty(
		ATLAS_COLUMNS * 128, _sky_row + Renderer.SKY_H, false, Image.FORMAT_RGB8
	)
	for i in count:
		var tile := Image.create_from_data(
			128,
			128,
			false,
			Image.FORMAT_RGB8,
			assets.tiles.slice(i * Renderer.TILE_BYTES, (i + 1) * Renderer.TILE_BYTES)
		)
		atlas.blit_rect(
			tile,
			Rect2i(0, 0, 128, 128),
			Vector2i((i % ATLAS_COLUMNS) * 128, (i / ATLAS_COLUMNS) * 128)
		)
	atlas.convert(Image.FORMAT_RGBA8)
	_atlas = atlas
	_atlas_plain = atlas
	_assets = assets
	_bake_glow()
	_cells_row = _sky_row + Renderer.SKY_H
	# The sprite pictures' texture array exists from the start: a sampler with
	# nothing of its own type bound is an error in WebGL.
	_art_blank = Image.create_empty(Renderer.ART_SIZE, Renderer.ART_SIZE, false, Image.FORMAT_RGBA8)
	var blanks: Array[Image] = []
	for i in Renderer.ART_SLOTS:
		blanks.append(_art_blank)
	_art = Texture2DArray.new()
	_art.create_from_images(blanks)
	_set_param("sprite_art", _art)
	_set_param("sky_row", _sky_row)
	_set_param("cells_row", _cells_row)


## Set one of the shader's numbers, skipping one that has not changed (most of
## them stay the same from frame to frame, and each set costs the engine work).
## scene_on is set directly: main_state.gd sets it too.
func _set_param(name: String, value: Variant) -> void:
	var old: Variant = _params.get(name)
	if old != null and typeof(old) == typeof(value) and old == value:
		return
	_params[name] = value
	material.set_shader_parameter(name, value)


## Create or refill one of the shader's textures. A texture is kept for each
## size it has been (the per-frame ones change height with what they carry),
## so a frame refills one instead of making a new one.
func _put(name: String, w: int, h: int, format: Image.Format, data: PackedByteArray) -> void:
	var image := Image.create_from_data(w, h, false, format, data)
	var key := "%s %d %d %d" % [name, w, h, format]
	var texture: ImageTexture = _textures.get(key)
	if texture == null:
		texture = ImageTexture.create_from_image(image)
		_textures[key] = texture
	else:
		texture.update(image)
	if _bound.get(name) != texture:
		_bound[name] = texture
		material.set_shader_parameter(name, texture)


## The level's surfaces: they only change when the level does.
func _load_level(renderer: Renderer) -> void:
	var level := renderer.level
	var lw := level.width
	var lh := level.height
	var floors: Array = level.floor_bounds.keys()
	var roofs: Array = level.roof_bounds.keys()
	var floor_index := {}
	for i in floors.size():
		floor_index[floors[i]] = i
	var roof_index := {}
	for i in roofs.size():
		roof_index[roofs[i]] = i
	var tint_count := maxi(1, renderer.tints.size() / 3)
	var cells := PackedByteArray()
	cells.resize(lw * lh * 4)
	var areas := PackedByteArray()
	areas.resize(lw * lh)
	for i in lw * lh:
		var o := i * 4
		cells[o] = mini(255, int(floor_index.get(level.ground[i], 255)))
		cells[o + 1] = mini(255, int(roof_index.get(level.roof[i], 255)))
		var below := level.floor_tile[i]
		cells[o + 2] = below if below >= 0 and below < 255 else 255
		var above := level.ceiling_tile[i]
		cells[o + 3] = above if above >= 0 and above < 255 else 255
		areas[i] = clampi(level.area[i], 0, tint_count - 1)
	# The tint indices go under the cells, as a second band.
	var tint_band := Image.create_from_data(lw, lh, false, Image.FORMAT_R8, areas)
	tint_band.convert(Image.FORMAT_RGBA8)
	cells.append_array(tint_band.get_data())
	var cell_bands := Image.create_from_data(lw, lh * 2, false, Image.FORMAT_RGBA8, cells)

	var cap_total := 0
	for h in floors:
		cap_total += (level.caps.get(h, []) as Array).size()
	var width := maxi(maxi(64, cap_total), maxi(maxi(floors.size(), roofs.size()), tint_count))
	# The cells' light goes under the five table rows (_light), so the table is
	# at least as wide as the map.
	width = maxi(width, lw)
	var table := PackedFloat32Array()
	table.resize(width * 5 * 4)
	table.fill(0.0)
	var next_cap := 0
	for i in floors.size():
		var caps_here: Array = level.caps.get(floors[i], [])
		table[i * 4] = float(floors[i])
		table[i * 4 + 1] = next_cap
		table[i * 4 + 2] = caps_here.size()
		for cap: Array in caps_here:
			var box := (width * 2 + next_cap) * 4
			table[box] = float(cap[0])
			table[box + 1] = float(cap[1])
			table[box + 2] = float(cap[2])
			table[box + 3] = float(cap[3])
			table[(width * 3 + next_cap) * 4] = float(cap[4])
			next_cap += 1
	for i in roofs.size():
		table[(width + i) * 4] = float(roofs[i])
	for i in tint_count:
		var o := (width * 4 + i) * 4
		table[o] = renderer.tints[i * 3]
		table[o + 1] = renderer.tints[i * 3 + 1]
		table[o + 2] = renderer.tints[i * 3 + 2]
	_plane_table = table
	_plane_width = width
	# The tiles, this level's sky under them, then its cells.
	var sky := Image.create_from_data(
		Renderer.SKY_W, Renderer.SKY_H, false, Image.FORMAT_RGB8, renderer.sky["data"]
	)
	sky.convert(Image.FORMAT_RGBA8)
	var whole := Image.create_empty(
		_atlas.get_width(), _cells_row + lh * 2, false, Image.FORMAT_RGBA8
	)
	whole.blit_rect(_atlas, Rect2i(0, 0, _atlas.get_width(), _sky_row), Vector2i.ZERO)
	whole.blit_rect(sky, Rect2i(0, 0, Renderer.SKY_W, Renderer.SKY_H), Vector2i(0, _sky_row))
	whole.blit_rect(cell_bands, Rect2i(0, 0, lw, lh * 2), Vector2i(0, _cells_row))
	_put("tiles_tex", whole.get_width(), whole.get_height(), Image.FORMAT_RGBA8, whole.get_data())

	_set_param("map_size", Vector2i(lw, lh))
	_set_param("floor_count", floors.size())
	_set_param("roof_count", roofs.size())
	_set_param("tint_count", tint_count)
	_set_param("hub_runoff", renderer.tile_hub_runoff)
	_set_param("hub_patch", renderer.tile_hub_patch)
	_set_param("hub_wall", renderer.tile_hub_wall)
	_level_tiles = {}
	for i in level.wall_count:
		_level_tiles[int(level.walls[i * LevelData.WALL_STRIDE + 4])] = true
	for door: LevelData.Door in level.doors:
		_level_tiles[door.material] = true
	for tile in level.floor_tile:
		_level_tiles[tile] = true
	for tile in level.ceiling_tile:
		_level_tiles[tile] = true


## This frame's layers and camera; call after Game.draw() when game.scene_live.
func frame(game: Game, _canvas: Canvas) -> void:
	var r: Renderer = game.renderer
	var level := r.level
	if Effects.version != _glow_version:
		# effects.cfg changed: bake the glows again and hand the level over anew.
		_bake_glow()
		_renderer = null
	if r != _renderer:
		_renderer = r
		_light_version = -1
		_load_level(r)
	if level.light_version != _light_version:
		_light_version = level.light_version
		_light(level)
	var vw := r.vw
	var vh := r.vh
	# What the renderer left empty this frame is not sent (the shader's
	# pixels_on, over_on, pane_on): no wall pixel (every wall a span) leaves the
	# wall distances at their 160, no sprite or ground mark pixel leaves the
	# coverage at 0.
	var view_px := vw * vh
	var pixels_on := r.depth.count(160.0) != view_px
	var over_on := r.over_a.count(0) != view_px
	var pane_on := r.pane_any
	# Stacked a view's height apart (see the shader's `colours`). Plain bytes,
	# only copied: walls, sprites and ground marks, then the wall codes and the
	# coverage as a byte stream (palette.gdshader stream_byte()), then panes.
	var row_bytes := vw * 3
	var colours := r.frame.duplicate() if pixels_on else PackedByteArray()
	var over_row := colours.size() / row_bytes
	if over_on:
		colours.append_array(r.over)
	var stream_row := colours.size() / row_bytes
	if pixels_on:
		colours.append_array(r.wall_code.to_byte_array())
	var cover_at := colours.size() - stream_row * row_bytes
	if over_on:
		colours.append_array(r.over_a)
	colours.resize((colours.size() + row_bytes - 1) / row_bytes * row_bytes)
	var pane_row := colours.size() / row_bytes
	if pane_on:
		colours.append_array(r.pane_rgb)
	if not colours.is_empty():
		_put("colours", vw, colours.size() / row_bytes, Image.FORMAT_RGB8, colours)
	_set_param("pixels_on", pixels_on)
	_set_param("over_on", over_on)
	_set_param("over_row", over_row)
	_set_param("stream_row", stream_row)
	_set_param("cover_at", cover_at)
	_set_param("pane_row", pane_row)
	_sprites(r)
	# The wall spans (only as many rows as the fullest column needs: the shader
	# walks most walls itself now), their counts and where the shader's own walk
	# starts in each column, then the sprite table flowing on across rows.
	var row_floats := vw * 4
	var span_rows := 0
	for k in range(Renderer.SPAN_K, 0, -1):
		if r.span_n.count(k) > 0:
			span_rows = k * 2
			break
	var table := r.span_f.slice(0, span_rows * row_floats)
	var count_at := Renderer.SPAN_K * 2 * row_floats
	table.append_array(r.span_f.slice(count_at, count_at + row_floats))
	_set_param("count_row", span_rows)
	_set_param("sprite_row", span_rows + 1)
	var count := r.gpu_spr_n if r.gpu_sprites else 0
	var rows := span_rows + 1
	if count > 0:
		var sprite_rows := (count * 4 + vw - 1) / vw
		var sprites := r.gpu_spr.slice(0, count * 16)
		sprites.resize(sprite_rows * vw * 4)
		table.append_array(sprites)
		rows += sprite_rows
	# Then the walls the shader walks itself (render_state.gd gpu_walls).
	var walls_on := r.gpu_walls
	_set_param("walls_on", walls_on)
	if walls_on:
		_set_param("wall_row", rows)
		_set_param("block_at", r.wall_blocks_at)
		_set_param("entry_at", r.wall_entries_at)
		_set_param("block_w", r.block_w)
		table.append_array(r.wall_table)
		table.resize((table.size() + row_floats - 1) / row_floats * row_floats)
		rows = table.size() / row_floats
	# Then the distance bands this frame has, four floats a texel.
	var dist_row := rows
	var dist_start := Vector3i.ZERO
	var floats := 0
	if pixels_on:
		table.append_array(r.depth)
		floats += view_px
	if over_on:
		dist_start.y = floats
		table.append_array(r.over_d)
		floats += view_px
	if pane_on:
		dist_start.z = floats
		table.append_array(r.pane_dist)
	table.resize((table.size() + row_floats - 1) / row_floats * row_floats)
	rows = table.size() / row_floats
	_put("spans", vw, rows, Image.FORMAT_RGBAF, table.to_byte_array())
	_set_param("dist_row", dist_row)
	_set_param("dist_start", dist_start)

	var m := material
	var angle: float = r.cam["angle"]
	_set_param("pane_on", r.pane_any)
	_set_param("eye", Vector3(r.cam["x"], r.cam["y"], r.cam["z"]))
	_set_param("fwd", Vector2(cos(angle), sin(angle)))
	_set_param("side", Vector2(-sin(angle), cos(angle)))
	# Whole turns only: the sky column is cut off toward zero, so the sign stays.
	_set_param("view_angle", fmod(angle, TAU_ * 512.0))
	_set_param("horizon", float(r.cam["hz"]))
	_set_param("focal", r.focal)
	_set_param("view_size", Vector2i(vw, vh))
	_set_param("view_div", 1 << maxi(r.detail, 0))
	_set_param("view_mul", 2 if r.detail < 0 else 1)
	_set_param("res_up", r.res_up)
	_set_param("flash_light", r.flash)
	var flow_tile := PackedInt32Array([-1, -1])
	var flow_shift := PackedInt32Array([0, 0])
	var found := 0
	for h in level.moving_floors:
		for f: Array in level.moving_floors[h]:
			var tile := int(f[0])
			if found < 2 and not flow_tile.has(tile):
				flow_tile[found] = tile
				flow_shift[found] = int(r.time * float(f[1])) & 127
				found += 1
	_set_param("flow_tile", flow_tile)
	_set_param("flow_shift", flow_shift)
	_set_param("hub_fx", r.hub_fx)
	if r.hub_fx:
		_set_param("shadow_still", r._shadow_still)
		_set_param("shadow_gust", r._shadow_gust)
		_set_param("shadow_lx", r._shadow_lx)
		_set_param("shadow_ly", r._shadow_ly)
		_set_param("water_drift", fposmod(r._water_drift, TAU_ * 1000.0))
	_lights(game)
	_set_param("drunk", game.drunk_k)
	if game.drunk_k > 0.0:
		var ghost := int(2 + 4 * game.drunk_k)
		_set_param("drunk_phase", fposmod(game.clock * 3.1, TAU_))
		_set_param("drunk_ghost", -ghost if sin(game.clock * 1.7) <= 0.0 else ghost)
	if not _on:
		_on = true
		material.set_shader_parameter("scene_on", true)


## The sprite table and any pictures new to the art slots.
func _sprites(r: Renderer) -> void:
	for slot_index: int in r.art_dirty:
		var art: Dictionary = r.art_dirty[slot_index]
		var w: int = art["w"]
		var h: int = art["h"]
		var picture := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, art["data"])
		var slot := _art_blank.duplicate() as Image
		slot.blit_rect(picture, Rect2i(0, 0, w, h), Vector2i.ZERO)
		_art.update_layer(slot, slot_index)
	r.art_dirty.clear()
	_set_param("sprite_count", r.gpu_spr_n if r.gpu_sprites else 0)


## The level's light map, under the plane table's five rows.
func _light(level: LevelData) -> void:
	var lw := level.width
	var lh := level.height
	var floats := _plane_table.duplicate()
	floats.resize(_plane_width * (5 + lh) * 4)
	for y in lh:
		for x in lw:
			floats[((5 + y) * _plane_width + x) * 4] = level.light[y * lw + x]
	_put("planes", _plane_width, 5 + lh, Image.FORMAT_RGBAF, floats.to_byte_array())


## The glows of effects.cfg in the atlas's alpha: a texel brighter than its
## tile's threshold gets 1 - its light there (palette.gdshader glow_of()).
func _bake_glow() -> void:
	_glow_version = Effects.version
	var data := _atlas_plain.get_data()
	var width := _atlas_plain.get_width()
	for name: String in Effects.GLOW:
		if not _assets.tile_index.has(name):
			push_warning("effects.cfg glows a tile that does not exist: " + name)
			continue
		var tile := int(_assets.tile_index[name])
		var spec: Vector2 = Effects.GLOW[name]
		var alpha := clampi(255 - int(roundf(spec.y * 255.0)), 0, 254)
		var left := (tile % ATLAS_COLUMNS) * 128
		var top := (tile / ATLAS_COLUMNS) * 128
		for y in 128:
			var row := ((top + y) * width + left) * 4
			for x in 128:
				var o := row + x * 4
				if maxi(data[o], maxi(data[o + 1], data[o + 2])) > int(spec.x):
					data[o + 3] = alpha
	_atlas = Image.create_from_data(
		width, _atlas_plain.get_height(), false, Image.FORMAT_RGBA8, data
	)


## This frame's lights (Game.effect_lights()) for the shader, when LIGHTS AND
## GLOW is on.
func _lights(game: Game) -> void:
	var m := material
	_set_param("effects_on", Effects.enabled)
	if not Effects.enabled:
		_set_param("lightning", 0.0)
	var found: Array = game.effect_lights() if Effects.enabled else []
	var at := PackedVector4Array()
	var tint := PackedVector4Array()
	at.resize(Effects.MAX_LIGHTS)
	tint.resize(Effects.MAX_LIGHTS)
	for i in found.size():
		var l: Array = found[i]
		var c: Color = l[4]
		at[i] = Vector4(l[0], l[1], l[2], l[3])
		tint[i] = Vector4(c.r, c.g, c.b, l[5])
	_set_param("light_count", found.size())
	_set_param("light_pos", at)
	_set_param("light_col", tint)
	if not Effects.enabled:
		return
	# The level's mood and its moving tiles (effects.cfg).
	var id := game.level.id
	var fog: Color = Effects.mood(id, "fog", Color(0, 0, 0))
	_set_param("fog_color", Vector3(fog.r, fog.g, fog.b))
	_set_param(
		"fog_range",
		Vector3(
			float(Effects.mood(id, "fog_start", 1000.0)),
			float(Effects.mood(id, "fog_full", 2000.0)),
			float(Effects.mood(id, "fog_most", 0.0))
		)
	)
	var tone: Color = Effects.mood(id, "grade", Color(1, 1, 1))
	_set_param("grade", Vector3(tone.r, tone.g, tone.b))
	_set_param("sky_drift", fposmod(game.clock * float(Effects.mood(id, "clouds", 0.0)), 1.0))
	_set_param("lightning", game.lightning)
	var anims := PackedVector4Array()
	anims.resize(Effects.MAX_ANIMS)
	var count := 0
	for tile_name: String in Effects.ANIMS:
		if (
			count < Effects.MAX_ANIMS
			and _assets.tile_index.has(tile_name)
			and _level_tiles.has(int(_assets.tile_index[tile_name]))
		):
			var a: Dictionary = Effects.ANIMS[tile_name]
			anims[count] = Vector4(
				_assets.tile_index[tile_name],
				0.0 if String(a.get("mode", "neon")) == "neon" else 1.0,
				float(a.get("rate", 8.0)),
				float(a.get("depth", .05))
			)
			count += 1
	_set_param("anim_count", count)
	_set_param("anims", anims)
	_set_param("anim_time", fposmod(game.clock, 3600.0))


## The canvas holds a finished picture this frame (menus, the tally).
func off() -> void:
	if _on:
		_on = false
		material.set_shader_parameter("scene_on", false)
