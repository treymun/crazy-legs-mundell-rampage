## The textures every 3D view surface shares: the tiles as one texture array
## (alpha carries effects.cfg's glow, as the old shader's atlas did), and a
## row saying what each tile is to the weather (water, relief, puddles).
## Built once per Assets and kept; rebuilt when effects.cfg reloads.
class_name ViewTiles
extends RefCounted

const SIZE := 128

var tiles: Texture2DArray
var info: ImageTexture
var count := 0
var _plain: Array[Image] = []
var _assets: Assets
var _glow_version := -1


func _init(assets: Assets) -> void:
	_assets = assets
	count = assets.tiles.size() / (SIZE * SIZE * 3)
	_plain.clear()
	for i in count:
		var image := Image.create_from_data(
			SIZE,
			SIZE,
			false,
			Image.FORMAT_RGB8,
			assets.tiles.slice(i * SIZE * SIZE * 3, (i + 1) * SIZE * SIZE * 3)
		)
		image.convert(Image.FORMAT_RGBA8)
		_plain.append(image)
	refresh()


## Bake the glows and the weather row again when effects.cfg has changed.
func refresh() -> void:
	if _glow_version == Effects.version and tiles != null:
		return
	_glow_version = Effects.version
	var layers: Array[Image] = []
	for image: Image in _plain:
		layers.append(image)
	for name: String in Effects.GLOW:
		if not _assets.tile_index.has(name):
			continue
		var tile: int = _assets.tile_index[name]
		var spec: Vector2 = Effects.GLOW[name]
		var alpha := clampi(255 - int(roundf(spec.y * 255.0)), 0, 254)
		var data := _plain[tile].get_data()
		for o in range(0, data.size(), 4):
			if maxi(data[o], maxi(data[o + 1], data[o + 2])) > int(spec.x):
				data[o + 3] = alpha
		layers[tile] = Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, data)
	if tiles == null:
		tiles = Texture2DArray.new()
	tiles.create_from_images(layers)
	info = ImageTexture.create_from_image(_info_row())


## One texel a tile: r water, g relief (signed, 128 flat), b puddles.
func _info_row() -> Image:
	var bytes := PackedByteArray()
	bytes.resize(count * 4)
	bytes.fill(0)
	for tile in count:
		bytes[tile * 4 + 1] = 128
		bytes[tile * 4 + 3] = 255
	var tables: Array[Dictionary] = [Effects.WATER, Effects.RELIEF, Effects.PUDDLES]
	for k in tables.size():
		var table: Dictionary = tables[k]
		for name: String in table:
			if not _assets.tile_index.has(name):
				continue
			var tile: int = _assets.tile_index[name]
			var value: float = table[name]
			if tile < count:
				bytes[tile * 4 + k] = (
					clampi(128 + int(roundf(value * 127.0)), 1, 255)
					if k == 1
					else clampi(int(roundf(value * 255.0)), 0, 255)
				)
	return Image.create_from_data(count, 1, false, Image.FORMAT_RGBA8, bytes)
