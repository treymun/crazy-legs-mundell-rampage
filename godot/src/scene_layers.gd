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
	_cells_row = _sky_row + Renderer.SKY_H
	# The sprite pictures' texture array exists from the start: a sampler with
	# nothing of its own type bound is an error in WebGL.
	_art_blank = Image.create_empty(Renderer.ART_SIZE, Renderer.ART_SIZE, false, Image.FORMAT_RGBA8)
	var blanks: Array[Image] = []
	for i in Renderer.ART_SLOTS:
		blanks.append(_art_blank)
	_art = Texture2DArray.new()
	_art.create_from_images(blanks)
	material.set_shader_parameter("sprite_art", _art)
	material.set_shader_parameter("sky_row", _sky_row)
	material.set_shader_parameter("cells_row", _cells_row)


## Create or refill one of the shader's textures.
func _put(name: String, w: int, h: int, format: Image.Format, data: PackedByteArray) -> void:
	var image := Image.create_from_data(w, h, false, format, data)
	var texture: ImageTexture = _textures.get(name)
	if (
		texture == null
		or texture.get_width() != w
		or texture.get_height() != h
		or texture.get_format() != format
	):
		texture = ImageTexture.create_from_image(image)
		_textures[name] = texture
		material.set_shader_parameter(name, texture)
	else:
		texture.update(image)


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

	material.set_shader_parameter("map_size", Vector2i(lw, lh))
	material.set_shader_parameter("floor_count", floors.size())
	material.set_shader_parameter("roof_count", roofs.size())
	material.set_shader_parameter("tint_count", tint_count)
	material.set_shader_parameter("hub_runoff", renderer.tile_hub_runoff)
	material.set_shader_parameter("hub_patch", renderer.tile_hub_patch)
	material.set_shader_parameter("hub_wall", renderer.tile_hub_wall)


## This frame's layers and camera; call after Game.draw() when game.scene_live.
func frame(game: Game, _canvas: Canvas) -> void:
	var r: Renderer = game.renderer
	var level := r.level
	if r != _renderer:
		_renderer = r
		_light_version = -1
		_load_level(r)
	if level.light_version != _light_version:
		_light_version = level.light_version
		_light(level)
	var vw := r.vw
	var vh := r.vh
	# Stacked a view's height apart (see the shader's `colours` and `distances`).
	# Plain bytes, only copied: three colour bands, then the wall codes and the
	# coverage as a byte stream (palette.gdshader stream_byte()).
	var colours := r.frame.duplicate()
	colours.append_array(r.over)
	colours.append_array(r.pane_rgb)
	colours.append_array(r.wall_code.to_byte_array())
	colours.append_array(r.over_a)
	var row_bytes := vw * 3
	colours.resize((colours.size() + row_bytes - 1) / row_bytes * row_bytes)
	_put("colours", vw, colours.size() / row_bytes, Image.FORMAT_RGB8, colours)
	var distances := r.depth.to_byte_array()
	distances.append_array(r.over_d.to_byte_array())
	distances.append_array(r.pane_dist.to_byte_array())
	_put("distances", vw, vh * 3, Image.FORMAT_RF, distances)
	_sprites(r)
	# The wall spans, their counts, then the sprite table flowing on across rows.
	var table := r.span_f.duplicate()
	var count := r.gpu_spr_n if r.gpu_sprites else 0
	var rows := Renderer.SPAN_K * 2 + 1
	if count > 0:
		var sprite_rows := (count * 4 + vw - 1) / vw
		var sprites := r.gpu_spr.slice(0, count * 16)
		sprites.resize(sprite_rows * vw * 4)
		table.append_array(sprites)
		rows += sprite_rows
	_put("spans", vw, rows, Image.FORMAT_RGBAF, table.to_byte_array())

	var m := material
	var angle: float = r.cam["angle"]
	m.set_shader_parameter("pane_on", r.pane_any)
	m.set_shader_parameter("eye", Vector3(r.cam["x"], r.cam["y"], r.cam["z"]))
	m.set_shader_parameter("fwd", Vector2(cos(angle), sin(angle)))
	m.set_shader_parameter("side", Vector2(-sin(angle), cos(angle)))
	# Whole turns only: the sky column is cut off toward zero, so the sign stays.
	m.set_shader_parameter("view_angle", fmod(angle, TAU_ * 512.0))
	m.set_shader_parameter("horizon", float(r.cam["hz"]))
	m.set_shader_parameter("focal", r.focal)
	m.set_shader_parameter("view_size", Vector2i(vw, vh))
	m.set_shader_parameter("view_div", 1 << r.detail)
	m.set_shader_parameter("res_up", r.res_up)
	m.set_shader_parameter("flash_light", r.flash)
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
	m.set_shader_parameter("flow_tile", flow_tile)
	m.set_shader_parameter("flow_shift", flow_shift)
	m.set_shader_parameter("hub_fx", r.hub_fx)
	if r.hub_fx:
		m.set_shader_parameter("shadow_still", r._shadow_still)
		m.set_shader_parameter("shadow_gust", r._shadow_gust)
		m.set_shader_parameter("shadow_lx", r._shadow_lx)
		m.set_shader_parameter("shadow_ly", r._shadow_ly)
		m.set_shader_parameter("water_drift", fposmod(r._water_drift, TAU_ * 1000.0))
	m.set_shader_parameter("drunk", game.drunk_k)
	if game.drunk_k > 0.0:
		var ghost := int(2 + 4 * game.drunk_k)
		m.set_shader_parameter("drunk_phase", fposmod(game.clock * 3.1, TAU_))
		m.set_shader_parameter("drunk_ghost", -ghost if sin(game.clock * 1.7) <= 0.0 else ghost)
	if not _on:
		_on = true
		m.set_shader_parameter("scene_on", true)


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
	material.set_shader_parameter("sprite_count", r.gpu_spr_n if r.gpu_sprites else 0)


## The level's light map, as the band of `plane_data` under its five rows.
func _light(level: LevelData) -> void:
	var lw := level.width
	var lh := level.height
	var light := Image.create_from_data(lw, lh, false, Image.FORMAT_RF, level.light.to_byte_array())
	light.convert(Image.FORMAT_RGBAF)
	var table := Image.create_from_data(
		_plane_width, 5, false, Image.FORMAT_RGBAF, _plane_table.to_byte_array()
	)
	var whole := Image.create_empty(_plane_width, 5 + lh, false, Image.FORMAT_RGBAF)
	whole.blit_rect(table, Rect2i(0, 0, _plane_width, 5), Vector2i.ZERO)
	whole.blit_rect(light, Rect2i(0, 0, lw, lh), Vector2i(0, 5))
	_put("plane_data", _plane_width, 5 + lh, Image.FORMAT_RGBAF, whole.get_data())


## The canvas holds a finished picture this frame (menus, the tally).
func off() -> void:
	if _on:
		_on = false
		material.set_shader_parameter("scene_on", false)
